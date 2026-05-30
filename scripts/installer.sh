#!/usr/bin/env bash
# ============================================================
#  installer.sh — Графический установщик Black Linux
#  Запускается из Live-сессии. Требует: zenity, parted, rsync
# ============================================================
set -euo pipefail

# ── Зависимости установщика ───────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
apt-get install -y zenity parted e2fsprogs dosfstools rsync \
    grub-pc grub-efi-amd64 efibootmgr 2>/dev/null || true

# ── Цвета и хелперы ──────────────────────────────────────────
GRN='\033[0;32m'; RED='\033[0;31m'; CYN='\033[0;36m'; RST='\033[0m'
log() { echo -e "${CYN}[installer]${RST} $*"; }
ok()  { echo -e "${GRN}[✓]${RST} $*"; }
die() { zenity --error --title="Black Linux — Ошибка" \
               --text="$*" --width=400 2>/dev/null; exit 1; }

# Прогресс через пайп в zenity
PIPE=/tmp/bl_install_pipe
[[ -p "$PIPE" ]] || mkfifo "$PIPE"

# ── Проверка UEFI/BIOS ────────────────────────────────────────
IS_UEFI=false
[[ -d /sys/firmware/efi ]] && IS_UEFI=true
log "Режим загрузки: $( $IS_UEFI && echo UEFI || echo BIOS )"

# ── GUI: Приветствие ─────────────────────────────────────────
show_welcome() {
zenity --info \
    --title="Установка Black Linux" \
    --width=600 --height=400 \
    --text="<span font='16' weight='bold' color='#cccccc'>
╔══════════════════════════════════╗
║         BLACK LINUX              ║
║      Obsidian Edition            ║
╚══════════════════════════════════╝
</span>
<span font='12'>
Добро пожаловать в установщик Black Linux.

Процесс займёт около 10–20 минут.
Убедитесь что:

  ✔ Подключён интернет
  ✔ Есть минимум 20 ГБ свободного места
  ✔ Подключён источник питания

</span>" 2>/dev/null || exit 0
}

# ── GUI: Выбор диска ─────────────────────────────────────────
select_disk() {
    # Получаем список дисков
    DISK_LIST=""
    while IFS= read -r line; do
        DEV=$(echo "$line" | awk '{print $1}')
        SIZE=$(echo "$line" | awk '{print $4}')
        MODEL=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf $i" "; print ""}' | \
                sed 's/[[:space:]]*$//')
        DISK_LIST="${DISK_LIST}FALSE\n/dev/${DEV}\n${SIZE} — ${MODEL}\n"
    done < <(lsblk -dno NAME,TYPE,RM,SIZE,MODEL | grep ' disk ' | grep ' 0 ')

    SELECTED=$(echo -e "$DISK_LIST" | zenity --list \
        --title="Выбор диска для установки" \
        --width=600 --height=400 \
        --text="<b>Выберите диск для установки Black Linux:</b>
<span color='red'>⚠ ВСЕ ДАННЫЕ НА ДИСКЕ БУДУТ УДАЛЕНЫ!</span>" \
        --radiolist \
        --column="Выбрать" \
        --column="Устройство" \
        --column="Размер / Модель" \
        2>/dev/null) || die "Диск не выбран"

    echo "$SELECTED"
}

# ── GUI: Разметка диска ───────────────────────────────────────
partition_disk() {
    local disk="$1"

    PART_SCHEME=$(zenity --list \
        --title="Схема разметки" \
        --width=500 --height=300 \
        --text="<b>Выберите схему разметки диска:</b>" \
        --radiolist \
        --column="Выбрать" \
        --column="Схема" \
        --column="Описание" \
        FALSE "auto"     "Автоматически (рекомендуется)" \
        FALSE "lvm"      "LVM (гибкое управление томами)" \
        FALSE "encrypt"  "LVM + LUKS шифрование" \
        2>/dev/null) || PART_SCHEME="auto"

    log "Схема разметки: $PART_SCHEME"

    # Подтверждение
    zenity --question \
        --title="Подтверждение" \
        --width=500 \
        --text="<b>ВНИМАНИЕ!</b>

Диск <b>$disk</b> будет полностью отформатирован.
Все данные будут <b>безвозвратно удалены</b>.

Вы уверены?" 2>/dev/null || exit 0

    case "$PART_SCHEME" in
        auto)    _partition_auto "$disk" ;;
        lvm)     _partition_lvm "$disk" ;;
        encrypt) _partition_luks "$disk" ;;
    esac
}

# Авто-разметка
_partition_auto() {
    local disk="$1"
    log "Разметка $disk (авто)..."

    # Очищаем диск
    wipefs -a "$disk" 2>/dev/null || true
    sgdisk -Z "$disk" 2>/dev/null || true

    if $IS_UEFI; then
        # GPT + EFI
        parted -s "$disk" mklabel gpt
        parted -s "$disk" mkpart ESP fat32 1MiB 513MiB
        parted -s "$disk" set 1 esp on
        parted -s "$disk" mkpart swap linux-swap 513MiB 4609MiB
        parted -s "$disk" mkpart rootfs ext4 4609MiB 100%

        EFI_PART="${disk}1"
        SWAP_PART="${disk}2"
        ROOT_PART="${disk}3"

        mkfs.fat -F32 -n EFI "$EFI_PART"
    else
        # MBR + BIOS
        parted -s "$disk" mklabel msdos
        parted -s "$disk" mkpart primary linux-swap 1MiB 4097MiB
        parted -s "$disk" mkpart primary ext4 4097MiB 100%
        parted -s "$disk" set 2 boot on

        SWAP_PART="${disk}1"
        ROOT_PART="${disk}2"
    fi

    mkswap -L swap "$SWAP_PART"
    mkfs.ext4 -L BLACKLINUX_ROOT -F "$ROOT_PART"

    ok "Разметка завершена"
    export EFI_PART SWAP_PART ROOT_PART
}

# LVM разметка
_partition_lvm() {
    local disk="$1"
    log "Разметка $disk (LVM)..."

    wipefs -a "$disk" 2>/dev/null || true

    if $IS_UEFI; then
        parted -s "$disk" mklabel gpt
        parted -s "$disk" mkpart ESP fat32 1MiB 513MiB
        parted -s "$disk" set 1 esp on
        parted -s "$disk" mkpart primary 513MiB 100%
        EFI_PART="${disk}1"
        LVM_PART="${disk}2"
        mkfs.fat -F32 -n EFI "$EFI_PART"
    else
        parted -s "$disk" mklabel msdos
        parted -s "$disk" mkpart primary 1MiB 100%
        parted -s "$disk" set 1 boot on
        LVM_PART="${disk}1"
    fi

    pvcreate "$LVM_PART"
    vgcreate blacklinux_vg "$LVM_PART"
    lvcreate -L 4G  -n swap blacklinux_vg
    lvcreate -l 100%FREE -n root blacklinux_vg

    mkswap  -L swap /dev/blacklinux_vg/swap
    mkfs.ext4 -L BLACKLINUX_ROOT -F /dev/blacklinux_vg/root

    SWAP_PART="/dev/blacklinux_vg/swap"
    ROOT_PART="/dev/blacklinux_vg/root"
    export EFI_PART SWAP_PART ROOT_PART
    ok "LVM разметка завершена"
}

# LUKS + LVM разметка
_partition_luks() {
    local disk="$1"

    # Пароль шифрования
    LUKS_PASS=$(zenity --password \
        --title="Пароль шифрования диска" \
        --text="Введите пароль для шифрования LUKS:" \
        2>/dev/null) || die "Пароль не введён"

    log "Разметка $disk (LUKS+LVM)..."
    wipefs -a "$disk" 2>/dev/null || true

    if $IS_UEFI; then
        parted -s "$disk" mklabel gpt
        parted -s "$disk" mkpart ESP fat32 1MiB 513MiB
        parted -s "$disk" set 1 esp on
        parted -s "$disk" mkpart primary 513MiB 100%
        EFI_PART="${disk}1"
        LUKS_PART="${disk}2"
        mkfs.fat -F32 -n EFI "$EFI_PART"
    else
        parted -s "$disk" mklabel msdos
        parted -s "$disk" mkpart primary 1MiB 100%
        parted -s "$disk" set 1 boot on
        LUKS_PART="${disk}1"
    fi

    # Форматируем LUKS
    echo -n "$LUKS_PASS" | cryptsetup luksFormat \
        --cipher aes-xts-plain64 --key-size 512 \
        --hash sha512 --iter-time 2000 \
        "$LUKS_PART" -

    echo -n "$LUKS_PASS" | cryptsetup open "$LUKS_PART" blacklinux_crypt -

    pvcreate /dev/mapper/blacklinux_crypt
    vgcreate blacklinux_vg /dev/mapper/blacklinux_crypt
    lvcreate -L 4G  -n swap blacklinux_vg
    lvcreate -l 100%FREE -n root blacklinux_vg

    mkswap  -L swap /dev/blacklinux_vg/swap
    mkfs.ext4 -L BLACKLINUX_ROOT -F /dev/blacklinux_vg/root

    SWAP_PART="/dev/blacklinux_vg/swap"
    ROOT_PART="/dev/blacklinux_vg/root"
    export EFI_PART SWAP_PART ROOT_PART LUKS_PART
    ok "LUKS+LVM разметка завершена"
}

# ── GUI: Настройки пользователя ───────────────────────────────
get_user_settings() {
    # Имя хоста
    HOSTNAME=$(zenity --entry \
        --title="Имя компьютера" \
        --text="Введите имя компьютера:" \
        --entry-text="blacklinux" \
        --width=400 2>/dev/null) || HOSTNAME="blacklinux"

    # Имя пользователя
    USERNAME=$(zenity --entry \
        --title="Пользователь" \
        --text="Введите имя пользователя (только строчные буквы):" \
        --entry-text="user" \
        --width=400 2>/dev/null) || USERNAME="user"

    # Проверка имени
    [[ "$USERNAME" =~ ^[a-z][a-z0-9_-]*$ ]] || \
        { zenity --error --text="Недопустимое имя пользователя" 2>/dev/null; exit 1; }

    # Пароль
    USERPASS=$(zenity --password \
        --title="Пароль пользователя $USERNAME" \
        --text="Введите пароль для $USERNAME:" \
        --width=400 2>/dev/null) || die "Пароль не введён"

    USERPASS2=$(zenity --password \
        --title="Подтверждение пароля" \
        --text="Повторите пароль:" \
        --width=400 2>/dev/null) || die "Пароль не введён"

    [[ "$USERPASS" == "$USERPASS2" ]] || \
        { zenity --error --text="Пароли не совпадают!" 2>/dev/null; exit 1; }

    # Часовой пояс
    TIMEZONE=$(zenity --list \
        --title="Часовой пояс" \
        --text="Выберите часовой пояс:" \
        --column="Зона" \
        --width=400 --height=400 \
        "Europe/Moscow" "Europe/Kiev" "Europe/Minsk" \
        "Europe/London" "Europe/Berlin" "Europe/Paris" \
        "Asia/Novosibirsk" "Asia/Yekaterinburg" "Asia/Vladivostok" \
        "America/New_York" "America/Los_Angeles" "UTC" \
        2>/dev/null) || TIMEZONE="UTC"

    # Клавиатура
    KB_LAYOUT=$(zenity --list \
        --title="Раскладка клавиатуры" \
        --text="Выберите раскладку:" \
        --column="Раскладка" --column="Язык" \
        --width=400 --height=300 \
        "us" "English (US)" \
        "ru" "Русский" \
        "de" "Deutsch" \
        "fr" "Français" \
        "ua" "Українська" \
        2>/dev/null | cut -d'|' -f1) || KB_LAYOUT="us"

    export HOSTNAME USERNAME USERPASS TIMEZONE KB_LAYOUT
    ok "Настройки пользователя получены"
}

# ── Копирование системы ───────────────────────────────────────
install_system() {
    MOUNT_ROOT="/mnt/blacklinux"
    mkdir -p "$MOUNT_ROOT"
    mount "$ROOT_PART" "$MOUNT_ROOT"

    if $IS_UEFI && [[ -n "${EFI_PART:-}" ]]; then
        mkdir -p "$MOUNT_ROOT/boot/efi"
        mount "$EFI_PART" "$MOUNT_ROOT/boot/efi"
    fi

    swapon "$SWAP_PART" 2>/dev/null || true

    log "Копирование системы..."
    # Прогресс бар
    (
        rsync -aAX --delete \
            --exclude={/proc,/sys,/dev,/run,/mnt,/media,/tmp,/lost+found} \
            / "$MOUNT_ROOT/" 2>/dev/null

        # fstab
        ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
        SWAP_UUID=$(blkid -s UUID -o value "$SWAP_PART")

        cat > "$MOUNT_ROOT/etc/fstab" <<FSTAB
# Black Linux fstab
UUID=$ROOT_UUID  /     ext4  defaults,noatime,nodiratime  0 1
UUID=$SWAP_UUID  none  swap  sw                           0 0
FSTAB

        if $IS_UEFI && [[ -n "${EFI_PART:-}" ]]; then
            EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")
            echo "UUID=$EFI_UUID  /boot/efi  vfat  umask=0077  0 1" \
                >> "$MOUNT_ROOT/etc/fstab"
        fi

        # Настройка системы в chroot
        for fs in dev proc sys; do
            mount --bind "/$fs" "$MOUNT_ROOT/$fs"
        done

        # Пользователь
        chroot "$MOUNT_ROOT" useradd -m -s /bin/bash \
            -G sudo,audio,video,netdev,plugdev "$USERNAME" 2>/dev/null || true
        echo "${USERNAME}:${USERPASS}" | chroot "$MOUNT_ROOT" chpasswd

        # Хост
        echo "$HOSTNAME" > "$MOUNT_ROOT/etc/hostname"
        cat > "$MOUNT_ROOT/etc/hosts" <<HOSTS
127.0.0.1   localhost
127.0.1.1   $HOSTNAME
::1         localhost ip6-localhost ip6-loopback
HOSTS

        # Часовой пояс
        chroot "$MOUNT_ROOT" ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
        chroot "$MOUNT_ROOT" hwclock --systohc 2>/dev/null || true

        # Клавиатура
        cat > "$MOUNT_ROOT/etc/default/keyboard" <<KB
XKBMODEL="pc105"
XKBLAYOUT="$KB_LAYOUT,us"
XKBOPTIONS="grp:alt_shift_toggle"
KB

        # Автовход настроить на нового пользователя
        sed -i "s/autologin-user=blackuser/autologin-user=$USERNAME/" \
            "$MOUNT_ROOT/etc/lightdm/lightdm.conf" 2>/dev/null || true

        # Установка GRUB
        if $IS_UEFI; then
            chroot "$MOUNT_ROOT" grub-install \
                --target=x86_64-efi \
                --efi-directory=/boot/efi \
                --bootloader-id=BlackLinux \
                --recheck 2>/dev/null
        else
            chroot "$MOUNT_ROOT" grub-install \
                --target=i386-pc \
                --recheck "$DISK" 2>/dev/null
        fi

        chroot "$MOUNT_ROOT" grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null

        # Размонтируем
        for fs in dev proc sys; do
            umount -lf "$MOUNT_ROOT/$fs" 2>/dev/null || true
        done

        echo "100"
    ) | zenity --progress \
        --title="Установка Black Linux" \
        --text="Копирование системы на диск..." \
        --percentage=0 \
        --auto-close \
        --width=500 \
        2>/dev/null

    # Размонтируем всё
    $IS_UEFI && umount "$MOUNT_ROOT/boot/efi" 2>/dev/null || true
    umount "$MOUNT_ROOT" 2>/dev/null || true
    swapoff "$SWAP_PART" 2>/dev/null || true

    ok "Система установлена"
}

# ── Финальное сообщение ───────────────────────────────────────
show_finish() {
    zenity --info \
        --title="Установка завершена!" \
        --width=500 \
        --text="<span font='14' weight='bold'>✓ Black Linux успешно установлен!</span>

<span font='11'>
  Пользователь: <b>$USERNAME</b>
  Хост:         <b>$HOSTNAME</b>
  Часовой пояс: <b>$TIMEZONE</b>
  Раскладка:    <b>$KB_LAYOUT / us</b>

Извлеките установочный носитель
и нажмите OK для перезагрузки.
</span>" 2>/dev/null

    systemctl reboot
}

# ══════════════════ ГЛАВНЫЙ ПОТОК ════════════════════════════
main() {
    log "Black Linux Installer запущен"
    [[ $EUID -eq 0 ]] || { zenity --error --text="Запустите от root!"; exit 1; }

    show_welcome
    DISK=$(select_disk)
    [[ -n "$DISK" ]] || die "Диск не выбран"
    export DISK

    partition_disk "$DISK"
    get_user_settings
    install_system
    show_finish
}

main "$@"
