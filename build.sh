#!/usr/bin/env bash
# ============================================================
#  BLACK LINUX — Главный скрипт сборки
#  build.sh  — запускается от root на хост-машине с Debian/Ubuntu
# ============================================================
set -euo pipefail
IFS=$'\n\t'

# ── Цвета для вывода ─────────────────────────────────────────
BLK='\033[0;30m'; RED='\033[0;31m'; GRN='\033[0;32m'
YLW='\033[0;33m'; BLU='\033[0;34m'; PRP='\033[0;35m'
CYN='\033[0;36m'; WHT='\033[1;37m'; RST='\033[0m'
BOLD='\033[1m'

# ── Конфигурация ─────────────────────────────────────────────
DISTRO_NAME="Black Linux"
DISTRO_CODENAME="obsidian"
BUILD_DIR="/opt/blacklinux-build"
ROOTFS_DIR="$BUILD_DIR/rootfs"
ISO_DIR="$BUILD_DIR/iso"
OUTPUT_DIR="/opt/blacklinux-output"
LOG_FILE="/var/log/blacklinux-build.log"
JOBS=$(nproc)                       # параллельные задачи = кол-во CPU
ARCH="x86_64"

# ── Вспомогательные функции ──────────────────────────────────
log()  { echo -e "${CYN}[$(date '+%H:%M:%S')]${RST} $*" | tee -a "$LOG_FILE"; }
ok()   { echo -e "${GRN}[✓]${RST} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YLW}[!]${RST} $*" | tee -a "$LOG_FILE"; }
die()  { echo -e "${RED}[✗] FATAL: $*${RST}" | tee -a "$LOG_FILE"; exit 1; }
step() { echo -e "\n${BOLD}${PRP}══════════════════════════════════════${RST}"; \
         echo -e "${BOLD}${WHT}  $*${RST}"; \
         echo -e "${BOLD}${PRP}══════════════════════════════════════${RST}\n"; }

banner() {
cat <<'EOF'
  ██████╗ ██╗      █████╗  ██████╗██╗  ██╗    ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗
  ██╔══██╗██║     ██╔══██╗██╔════╝██║ ██╔╝    ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝
  ██████╔╝██║     ███████║██║     █████╔╝     ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝
  ██╔══██╗██║     ██╔══██║██║     ██╔═██╗     ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗
  ██████╔╝███████╗██║  ██║╚██████╗██║  ██╗    ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗
  ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝   ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝
EOF
echo -e "  ${PRP}Build System v1.0 — ${DISTRO_NAME} «${DISTRO_CODENAME}»${RST}\n"
}

require_root() {
    [[ $EUID -eq 0 ]] || die "Запустите скрипт от root: sudo $0"
}

# ── Шаг 0: подготовка окружения ──────────────────────────────
prepare_host() {
    step "Подготовка хост-системы"

    # Отключаем проблемные сторонние PPA с битыми GPG ключами
    log "Проверка и отключение проблемных репозиториев..."
    for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [[ -f "$f" ]] || continue
        if grep -qE "launchpadcontent|cloudfront|toolchain-r|ppa\." "$f" 2>/dev/null; then
            warn "Отключён проблемный PPA: $(basename $f)"
            mv "$f" "${f}.disabled" 2>/dev/null || true
        fi
    done

    # Добавляем недостающие GPG ключи автоматически
    log "Восстановление GPG ключей..."
    for key in 2C277A0A352154E5 1E9377A2BA9EF27F 65106822B35B1B1F; do
        gpg --keyserver keyserver.ubuntu.com --recv-keys "$key" 2>/dev/null && \
        gpg --export "$key" | apt-key add - 2>/dev/null || \
        log "Ключ $key пропущен (PPA отключён)"
    done

    apt-get update 2>&1 | grep -v "^W:\|^N:" || true

    apt-get install -y --no-install-recommends \
        debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin \
        mtools dosfstools curl wget git build-essential bc flex bison \
        libssl-dev libelf-dev libncurses-dev dwarves cpio rsync \
        python3 python3-pip pciutils lshw jq aria2 \
        2>>"$LOG_FILE"
    ok "Зависимости хоста установлены"

    mkdir -p "$BUILD_DIR" "$ROOTFS_DIR" "$ISO_DIR" "$OUTPUT_DIR"
    log "Рабочие каталоги созданы"
}

# ── Шаг 1: определение оборудования ──────────────────────────
detect_hardware() {
    step "Определение оборудования"

    GPU_VENDOR=""
    CPU_VENDOR=""
    WIFI_CHIP=""
    NEEDS_NVIDIA=false
    NEEDS_AMD_GPU=false
    NEEDS_INTEL_GPU=false
    NEEDS_BROADCOM=false

    # CPU
    if grep -qi "intel" /proc/cpuinfo; then
        CPU_VENDOR="intel"; log "CPU: Intel"
        MICROCODE_PKG="intel-microcode"
    elif grep -qi "amd" /proc/cpuinfo; then
        CPU_VENDOR="amd"; log "CPU: AMD"
        MICROCODE_PKG="amd64-microcode"
    fi

    # GPU через lspci
    if lspci | grep -qi "nvidia"; then
        NEEDS_NVIDIA=true; log "GPU: NVIDIA обнаружен"
    fi
    if lspci | grep -qi "amd\|ati\|radeon"; then
        NEEDS_AMD_GPU=true; log "GPU: AMD/Radeon обнаружен"
    fi
    if lspci | grep -qi "intel.*graphics\|intel.*display"; then
        NEEDS_INTEL_GPU=true; log "GPU: Intel Graphics обнаружен"
    fi

    # WiFi
    if lspci | grep -qi "broadcom\|bcm"; then
        NEEDS_BROADCOM=true; log "WiFi: Broadcom обнаружен (нужен firmware-b43)"
    fi

    # Запись профиля оборудования
    cat > "$BUILD_DIR/hw_profile.env" <<HW
CPU_VENDOR="$CPU_VENDOR"
MICROCODE_PKG="$MICROCODE_PKG"
NEEDS_NVIDIA=$NEEDS_NVIDIA
NEEDS_AMD_GPU=$NEEDS_AMD_GPU
NEEDS_INTEL_GPU=$NEEDS_INTEL_GPU
NEEDS_BROADCOM=$NEEDS_BROADCOM
HW
    ok "Профиль оборудования сохранён в $BUILD_DIR/hw_profile.env"
}

# ── Шаг 2: скачать актуальное ядро Linux ─────────────────────
fetch_latest_kernel() {
    step "Получение актуального ядра Linux"

    KERNEL_VERSION=$(curl -s https://www.kernel.org/releases.json \
        | python3 -c "import sys,json; d=json.load(sys.stdin); \
          print([r['version'] for r in d['releases'] if r['moniker']=='stable'][0])")
    log "Актуальная стабильная версия: $KERNEL_VERSION"

    KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_VERSION%%.*}.x/linux-${KERNEL_VERSION}.tar.xz"
    KERNEL_SRC="$BUILD_DIR/linux-${KERNEL_VERSION}"

    if [[ ! -d "$KERNEL_SRC" ]]; then
        log "Загрузка ядра $KERNEL_VERSION..."
        aria2c -x 8 -s 8 -d "$BUILD_DIR" "$KERNEL_URL" 2>>"$LOG_FILE"
        tar -xf "$BUILD_DIR/linux-${KERNEL_VERSION}.tar.xz" -C "$BUILD_DIR"
        ok "Ядро распаковано"
    else
        ok "Ядро уже загружено"
    fi

    export KERNEL_VERSION KERNEL_SRC
}

# ── Шаг 3: настройка и сборка ядра ───────────────────────────
build_kernel() {
    step "Сборка ядра (оптимизированная)"
    source "$BUILD_DIR/hw_profile.env"
    cd "$KERNEL_SRC"

    # Базовая конфигурация + оптимизации
    make defconfig 2>>"$LOG_FILE"

    # Перфоманс-оптимизации через scripts/config
    scripts/config \
        --enable  CONFIG_HZ_1000 \
        --disable CONFIG_HZ_250 \
        --enable  CONFIG_PREEMPT \
        --disable CONFIG_PREEMPT_VOLUNTARY \
        --enable  CONFIG_TRANSPARENT_HUGEPAGE \
        --enable  CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS \
        --enable  CONFIG_ZSWAP \
        --enable  CONFIG_ZSWAP_COMPRESSOR_DEFAULT_LZ4 \
        --enable  CONFIG_LZ4_COMPRESS \
        --enable  CONFIG_ZRAM \
        --enable  CONFIG_BLK_DEV_ZONED \
        --enable  CONFIG_IOSCHED_BFQ \
        --enable  CONFIG_COMPACTION \
        --enable  CONFIG_KSM \
        --disable CONFIG_DEBUG_KERNEL \
        --disable CONFIG_DEBUG_INFO \
        --disable CONFIG_KPROBES \
        2>>"$LOG_FILE"

    # Драйверы под обнаруженное железо
    if $NEEDS_NVIDIA; then
        scripts/config --enable CONFIG_DRM_NOUVEAU 2>>"$LOG_FILE"
    fi
    if $NEEDS_AMD_GPU; then
        scripts/config --enable CONFIG_DRM_AMDGPU --enable CONFIG_DRM_RADEON 2>>"$LOG_FILE"
    fi
    if $NEEDS_INTEL_GPU; then
        scripts/config --enable CONFIG_DRM_I915 2>>"$LOG_FILE"
    fi
    if $NEEDS_BROADCOM; then
        scripts/config --enable CONFIG_B43 --enable CONFIG_BRCMFMAC 2>>"$LOG_FILE"
    fi

    make olddefconfig 2>>"$LOG_FILE"

    log "Сборка ядра ($JOBS потоков)..."
    make -j"$JOBS" 2>>"$LOG_FILE"
    make modules -j"$JOBS" 2>>"$LOG_FILE"

    ok "Ядро собрано: $(make kernelversion)"
    cd -
}

# ── Шаг 4: создание rootfs через debootstrap ─────────────────
create_rootfs() {
    step "Создание базовой корневой ФС (Debian Sid)"

    debootstrap --arch="$ARCH" --variant=minbase \
        sid "$ROOTFS_DIR" http://deb.debian.org/debian \
        2>>"$LOG_FILE"

    ok "Базовый rootfs создан"

    # Монтируем нужные ФС для chroot
    mount --bind /dev  "$ROOTFS_DIR/dev"
    mount --bind /proc "$ROOTFS_DIR/proc"
    mount --bind /sys  "$ROOTFS_DIR/sys"

    # Копируем hw_profile внутрь
    cp "$BUILD_DIR/hw_profile.env" "$ROOTFS_DIR/hw_profile.env"

    ok "Виртуальные ФС смонтированы"
}

# ── Шаг 5: настройка внутри chroot ───────────────────────────
configure_rootfs() {
    step "Настройка rootfs (chroot)"

    # Копируем все вспомогательные скрипты
    cp scripts/chroot_setup.sh   "$ROOTFS_DIR/chroot_setup.sh"
    cp scripts/install_langs.sh  "$ROOTFS_DIR/install_langs.sh"
    cp scripts/install_lkrg.sh   "$ROOTFS_DIR/install_lkrg.sh"
    cp scripts/multipm.sh        "$ROOTFS_DIR/usr/local/bin/pm"
    cp -r configs/               "$ROOTFS_DIR/root/configs/"
    cp -r theme/                 "$ROOTFS_DIR/root/theme/"

    chmod +x "$ROOTFS_DIR/chroot_setup.sh" \
             "$ROOTFS_DIR/install_langs.sh" \
             "$ROOTFS_DIR/install_lkrg.sh" \
             "$ROOTFS_DIR/usr/local/bin/pm"

    chroot "$ROOTFS_DIR" /bin/bash /chroot_setup.sh
    ok "chroot настройка завершена"
}

# ── Шаг 6: установка ядра в rootfs ───────────────────────────
install_kernel_to_rootfs() {
    step "Установка ядра в rootfs"
    source "$BUILD_DIR/hw_profile.env"
    cd "$KERNEL_SRC"

    make INSTALL_PATH="$ROOTFS_DIR/boot" install 2>>"$LOG_FILE"
    make INSTALL_MOD_PATH="$ROOTFS_DIR" modules_install 2>>"$LOG_FILE"

    # initramfs
    chroot "$ROOTFS_DIR" update-initramfs -c -k all 2>>"$LOG_FILE"

    ok "Ядро $KERNEL_VERSION установлено в rootfs"
    cd -
}

# ── Шаг 7: сборка ISO ────────────────────────────────────────
build_iso() {
    step "Сборка ISO-образа"

    SQUASH="$ISO_DIR/live/filesystem.squashfs"
    mkdir -p "$ISO_DIR/live" "$ISO_DIR/boot/grub"

    # Squash rootfs
    log "Сжатие rootfs (zstd)..."
    mksquashfs "$ROOTFS_DIR" "$SQUASH" \
        -comp zstd -Xcompression-level 19 \
        -e boot -noappend -progress \
        2>>"$LOG_FILE"
    ok "squashfs создан ($(du -sh "$SQUASH" | cut -f1))"

    # Копируем ядро и initrd
    cp "$ROOTFS_DIR"/boot/vmlinuz-*  "$ISO_DIR/boot/vmlinuz"
    cp "$ROOTFS_DIR"/boot/initrd.img-* "$ISO_DIR/boot/initrd.img"

    # GRUB конфигурация
    cp configs/grub.cfg "$ISO_DIR/boot/grub/grub.cfg"

    # Итоговый ISO
    ISO_FILE="$OUTPUT_DIR/blacklinux-${KERNEL_VERSION}-${ARCH}.iso"
    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "BLACKLINUX" \
        -eltorito-boot boot/grub/bios.img \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        --efi-boot boot/grub/efi.img \
        -efi-boot-part --efi-boot-image \
        --protective-msdos-label \
        -o "$ISO_FILE" \
        "$ISO_DIR" \
        2>>"$LOG_FILE"

    ok "ISO создан: $ISO_FILE"
    echo -e "\n${BOLD}${GRN}  Размер: $(du -sh "$ISO_FILE" | cut -f1)${RST}"
    echo -e "${BOLD}${GRN}  SHA256: $(sha256sum "$ISO_FILE" | cut -d' ' -f1)${RST}\n"
}

# ── Шаг 8: очистка ───────────────────────────────────────────
cleanup() {
    log "Размонтирование виртуальных ФС..."
    umount -lf "$ROOTFS_DIR/dev"  2>/dev/null || true
    umount -lf "$ROOTFS_DIR/proc" 2>/dev/null || true
    umount -lf "$ROOTFS_DIR/sys"  2>/dev/null || true
    ok "Очистка завершена"
}

trap cleanup EXIT

# ══════════════════ ГЛАВНЫЙ ПОРЯДОК СБОРКИ ═══════════════════
main() {
    clear
    banner
    require_root
    touch "$LOG_FILE"

    log "Начало сборки: $(date)"
    log "Лог: $LOG_FILE"

    prepare_host
    detect_hardware
    fetch_latest_kernel
    build_kernel
    create_rootfs
    configure_rootfs
    install_kernel_to_rootfs
    build_iso

    step "СБОРКА ЗАВЕРШЕНА"
    echo -e "${BOLD}${WHT}  ${DISTRO_NAME} готов к использованию!${RST}"
    log "Завершено: $(date)"
}

main "$@"
