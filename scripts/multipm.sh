#!/usr/bin/env bash
# ============================================================
#  pm — универсальный менеджер пакетов Black Linux
#  Механизм: каждый PM работает в своём stratum (namespace/chroot)
#  Аналогично Bedrock Linux, но упрощённо через overlayfs
# ============================================================
set -euo pipefail

STRATA_DIR="/var/lib/blacklinux/strata"
ACTIVE_STRATA=()

# ── Цвета ────────────────────────────────────────────────────
GRN='\033[0;32m'; YLW='\033[0;33m'; RED='\033[0;31m'
CYN='\033[0;36m'; WHT='\033[1;37m'; RST='\033[0m'

usage() {
cat <<EOF
${WHT}pm${RST} — Black Linux универсальный менеджер пакетов

${CYN}Использование:${RST}
  pm <команда> [пакет...]
  pm --from <менеджер> <команда> [пакет...]

${CYN}Команды:${RST}
  install   <pkg>    Установить пакет (автовыбор PM)
  remove    <pkg>    Удалить пакет
  update             Обновить все базы пакетов
  upgrade            Обновить все пакеты
  search    <pkg>    Поиск во всех репозиториях
  info      <pkg>    Информация о пакете
  list               Список установленных пакетов
  strata             Показать активные strata (менеджеры)

${CYN}Менеджеры (--from):${RST}
  apt       Debian/Ubuntu пакеты (.deb)
  pacman    Arch Linux пакеты (.pkg.tar.zst)
  dnf       Fedora/RHEL пакеты (.rpm)
  portage   Gentoo исходники (emerge)
  cargo     Rust пакеты
  pip       Python пакеты
  go        Go модули

${CYN}Примеры:${RST}
  pm install firefox
  pm --from pacman install yay
  pm --from portage install chromium
  pm search neovim
  pm update && pm upgrade
EOF
}

# ── Определение доступных PM ─────────────────────────────────
detect_pm() {
    AVAILABLE_PM=()
    command -v apt     &>/dev/null && AVAILABLE_PM+=("apt")
    command -v pacman  &>/dev/null && AVAILABLE_PM+=("pacman")
    command -v dnf     &>/dev/null && AVAILABLE_PM+=("dnf")
    command -v emerge  &>/dev/null && AVAILABLE_PM+=("portage")
    command -v cargo   &>/dev/null && AVAILABLE_PM+=("cargo")
    command -v pip3    &>/dev/null && AVAILABLE_PM+=("pip")
    command -v go      &>/dev/null && AVAILABLE_PM+=("go")
}

# ── Инициализация strata ──────────────────────────────────────
init_stratum() {
    local name="$1"
    local dir="$STRATA_DIR/$name"
    [[ -d "$dir" ]] && return 0

    echo -e "${CYN}[pm]${RST} Инициализация stratum: $name"
    mkdir -p "$dir/rootfs" "$dir/work" "$dir/merged"

    case "$name" in
        pacman-stratum)
            # Bootstrap Arch Linux stratum
            _bootstrap_arch "$dir"
            ;;
        dnf-stratum)
            # Bootstrap Fedora stratum
            _bootstrap_fedora "$dir"
            ;;
        portage-stratum)
            # Bootstrap Gentoo stratum
            _bootstrap_gentoo "$dir"
            ;;
    esac
}

# ── Bootstrap Arch stratum ────────────────────────────────────
_bootstrap_arch() {
    local dir="$1"
    echo -e "${CYN}[pm]${RST} Загрузка Arch Linux bootstrap..."
    local ARCH_MIRROR="https://geo.mirror.pkgbuild.com"
    local BOOTSTRAP_URL="$ARCH_MIRROR/iso/latest/archlinux-bootstrap-x86_64.tar.zst"

    if [[ ! -f "$dir/.bootstrapped" ]]; then
        mkdir -p "$dir/rootfs"
        curl -fsSL "$BOOTSTRAP_URL" -o /tmp/arch-bootstrap.tar.zst
        tar --use-compress-program=unzstd -xf /tmp/arch-bootstrap.tar.zst \
            --strip-components=1 -C "$dir/rootfs" 2>/dev/null
        rm -f /tmp/arch-bootstrap.tar.zst

        # Базовая настройка
        echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' \
            > "$dir/rootfs/etc/pacman.d/mirrorlist"
        _chroot_stratum "$dir" pacman-key --init
        _chroot_stratum "$dir" pacman-key --populate archlinux
        _chroot_stratum "$dir" pacman -Sy --noconfirm 2>/dev/null
        touch "$dir/.bootstrapped"
    fi
    echo -e "${GRN}[✓]${RST} Arch stratum готов"
}

# ── Bootstrap Fedora stratum ──────────────────────────────────
_bootstrap_fedora() {
    local dir="$1"
    echo -e "${CYN}[pm]${RST} Загрузка Fedora bootstrap (dnf)..."
    if [[ ! -f "$dir/.bootstrapped" ]]; then
        mkdir -p "$dir/rootfs"
        # Используем dnf installroot
        dnf install -y --installroot="$dir/rootfs" --releasever=40 \
            fedora-release dnf bash coreutils 2>/dev/null || \
            echo -e "${YLW}[!]${RST} dnf stratum: нужен dnf на хосте"
        touch "$dir/.bootstrapped"
    fi
    echo -e "${GRN}[✓]${RST} Fedora stratum готов"
}

# ── Bootstrap Gentoo stratum ──────────────────────────────────
_bootstrap_gentoo() {
    local dir="$1"
    echo -e "${CYN}[pm]${RST} Загрузка Gentoo stage3..."
    if [[ ! -f "$dir/.bootstrapped" ]]; then
        mkdir -p "$dir/rootfs"
        # Получаем актуальный stage3
        local GENTOO_MIRROR="https://distfiles.gentoo.org/releases/amd64/autobuilds"
        local STAGE3_FILE=$(curl -s "$GENTOO_MIRROR/latest-stage3-amd64-openrc.txt" \
            | grep -v '^#' | cut -d' ' -f1 | head -1)
        curl -fsSL "$GENTOO_MIRROR/$STAGE3_FILE" -o /tmp/stage3.tar.xz
        tar -xf /tmp/stage3.tar.xz -C "$dir/rootfs" 2>/dev/null
        rm -f /tmp/stage3.tar.xz
        touch "$dir/.bootstrapped"
    fi
    echo -e "${GRN}[✓]${RST} Gentoo stratum готов"
}

# ── Запуск команды в stratum ──────────────────────────────────
_chroot_stratum() {
    local dir="$1"; shift
    local rootfs="$dir/rootfs"

    # Монтируем overlayfs поверх системных директорий
    mount --bind /proc "$rootfs/proc" 2>/dev/null || true
    mount --bind /dev  "$rootfs/dev"  2>/dev/null || true
    mount --bind /sys  "$rootfs/sys"  2>/dev/null || true

    # Пробрасываем /usr/local/bin из основной системы
    mount --bind /usr/local/bin "$rootfs/usr/local/bin" 2>/dev/null || true

    chroot "$rootfs" "$@"

    umount "$rootfs/proc" "$rootfs/dev" "$rootfs/sys" \
           "$rootfs/usr/local/bin" 2>/dev/null || true
}

# ── Кросс-stratum: установить пакет с интеграцией ────────────
_install_cross() {
    local pm="$1"; local pkg="$2"
    local stratum_dir="$STRATA_DIR/${pm}-stratum"

    init_stratum "${pm}-stratum"

    case "$pm" in
        pacman)
            _chroot_stratum "$stratum_dir" pacman -S --noconfirm "$pkg"
            # Симлинк бинарей в основную систему
            _link_stratum_bins "$stratum_dir" "$pkg"
            ;;
        dnf)
            _chroot_stratum "$stratum_dir" dnf install -y "$pkg"
            _link_stratum_bins "$stratum_dir" "$pkg"
            ;;
        portage)
            _chroot_stratum "$stratum_dir" emerge --ask n "$pkg"
            _link_stratum_bins "$stratum_dir" "$pkg"
            ;;
    esac
}

# ── Симлинк бинарей из stratum в основную систему ────────────
_link_stratum_bins() {
    local stratum_dir="$1"
    local rootfs="$stratum_dir/rootfs"

    for bin in "$rootfs/usr/bin/"* "$rootfs/usr/local/bin/"*; do
        [[ -f "$bin" && -x "$bin" ]] || continue
        local name=$(basename "$bin")
        # Создаём wrapper-скрипт
        if [[ ! -e "/usr/local/bin/$name" ]]; then
            cat > "/usr/local/bin/${name}" <<WRAPPER
#!/usr/bin/env bash
# Автоматический wrapper от pm (stratum: $stratum_dir)
exec chroot "$rootfs" /usr/bin/$name "\$@"
WRAPPER
            chmod +x "/usr/local/bin/${name}"
        fi
    done
}

# ── Умный выбор пакетного менеджера ──────────────────────────
_smart_select_pm() {
    local pkg="$1"
    detect_pm

    # Если установлен основной APT — используем его по умолчанию
    if [[ " ${AVAILABLE_PM[*]} " == *" apt "* ]]; then
        # Проверяем наличие в репах
        if apt-cache show "$pkg" &>/dev/null; then
            echo "apt"; return
        fi
    fi
    # Fallback на pacman stratum (AUR покрывает почти всё)
    echo "pacman"
}

# ── Команды ──────────────────────────────────────────────────
cmd_install() {
    local pkg="$1"
    local pm="${FORCE_PM:-}"

    if [[ -z "$pm" ]]; then
        pm=$(_smart_select_pm "$pkg")
        echo -e "${CYN}[pm]${RST} Выбран менеджер: ${WHT}$pm${RST}"
    fi

    case "$pm" in
        apt)     apt-get install -y "$pkg" ;;
        pacman)
            if command -v pacman &>/dev/null; then
                pacman -S --noconfirm "$pkg"
            else
                _install_cross pacman "$pkg"
            fi ;;
        dnf)
            if command -v dnf &>/dev/null; then
                dnf install -y "$pkg"
            else
                _install_cross dnf "$pkg"
            fi ;;
        portage)
            if command -v emerge &>/dev/null; then
                emerge "$pkg"
            else
                _install_cross portage "$pkg"
            fi ;;
        cargo)   cargo install "$pkg" ;;
        pip)     pip3 install --user "$pkg" ;;
        go)      go install "${pkg}@latest" ;;
        *)       echo -e "${RED}[✗]${RST} Неизвестный PM: $pm"; exit 1 ;;
    esac
}

cmd_update() {
    detect_pm
    echo -e "${CYN}[pm]${RST} Обновление баз пакетов..."
    [[ " ${AVAILABLE_PM[*]} " == *" apt "* ]]    && apt-get update -qq
    [[ " ${AVAILABLE_PM[*]} " == *" pacman "* ]] && pacman -Sy --noconfirm 2>/dev/null || true
    [[ " ${AVAILABLE_PM[*]} " == *" dnf "* ]]    && dnf check-update -q 2>/dev/null || true
    [[ " ${AVAILABLE_PM[*]} " == *" portage "* ]] && emerge --sync -q 2>/dev/null || true
    echo -e "${GRN}[✓]${RST} Базы обновлены"
}

cmd_upgrade() {
    detect_pm
    echo -e "${CYN}[pm]${RST} Обновление пакетов..."
    [[ " ${AVAILABLE_PM[*]} " == *" apt "* ]]    && apt-get upgrade -y -qq
    [[ " ${AVAILABLE_PM[*]} " == *" pacman "* ]] && pacman -Su --noconfirm 2>/dev/null || true
    [[ " ${AVAILABLE_PM[*]} " == *" dnf "* ]]    && dnf upgrade -y -q 2>/dev/null || true
    [[ " ${AVAILABLE_PM[*]} " == *" portage "* ]] && emerge -uDN @world 2>/dev/null || true
    echo -e "${GRN}[✓]${RST} Система обновлена"
}

cmd_search() {
    local pkg="$1"
    detect_pm
    echo -e "${CYN}[pm]${RST} Поиск: ${WHT}$pkg${RST}\n"

    if [[ " ${AVAILABLE_PM[*]} " == *" apt "* ]]; then
        echo -e "${YLW}── APT ──${RST}"
        apt-cache search "$pkg" 2>/dev/null | head -10
    fi
    if [[ " ${AVAILABLE_PM[*]} " == *" pacman "* ]]; then
        echo -e "${YLW}── Pacman ──${RST}"
        pacman -Ss "$pkg" 2>/dev/null | head -10
    fi
}

cmd_remove() {
    local pkg="$1"
    local pm="${FORCE_PM:-apt}"
    case "$pm" in
        apt)    apt-get remove -y "$pkg" ;;
        pacman) pacman -R --noconfirm "$pkg" ;;
        dnf)    dnf remove -y "$pkg" ;;
        portage) emerge --depclean "$pkg" ;;
    esac
}

cmd_strata() {
    detect_pm
    echo -e "${WHT}Активные менеджеры пакетов:${RST}"
    for pm in "${AVAILABLE_PM[@]}"; do
        echo -e "  ${GRN}●${RST} $pm"
    done
    if [[ -d "$STRATA_DIR" ]]; then
        echo -e "\n${WHT}Установленные strata:${RST}"
        for d in "$STRATA_DIR"/*/; do
            [[ -d "$d" ]] && echo -e "  ${CYN}◆${RST} $(basename $d)"
        done
    fi
}

# ── Точка входа ───────────────────────────────────────────────
FORCE_PM=""

[[ $# -eq 0 ]] && { usage; exit 0; }

# Разбор --from
if [[ "${1:-}" == "--from" ]]; then
    FORCE_PM="${2:?'Укажите менеджер после --from'}"
    shift 2
fi

COMMAND="${1:-help}"; shift || true

case "$COMMAND" in
    install|i)   cmd_install "${1:?'Укажите пакет'}" ;;
    remove|rm)   cmd_remove  "${1:?'Укажите пакет'}" ;;
    update|up)   cmd_update ;;
    upgrade|ug)  cmd_upgrade ;;
    search|s)    cmd_search  "${1:?'Укажите запрос'}" ;;
    info)        apt-cache show "${1:-}" 2>/dev/null || pacman -Si "${1:-}" 2>/dev/null ;;
    list)        dpkg -l 2>/dev/null | grep '^ii' || pacman -Q 2>/dev/null ;;
    strata)      cmd_strata ;;
    help|--help|-h) usage ;;
    *)           echo -e "${RED}[✗]${RST} Неизвестная команда: $COMMAND"; usage; exit 1 ;;
esac
