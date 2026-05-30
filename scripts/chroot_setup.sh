#!/usr/bin/env bash
# ============================================================
#  chroot_setup.sh — выполняется ВНУТРИ chroot
# ============================================================
set -euo pipefail

source /hw_profile.env

log() { echo -e "\033[0;36m[chroot]\033[0m $*"; }
ok()  { echo -e "\033[0;32m[✓]\033[0m $*"; }

# ── Базовые настройки ─────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8

cat > /etc/apt/sources.list <<'EOF'
deb http://deb.debian.org/debian sid main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security sid-security main
EOF

apt-get update -qq
apt-get upgrade -y -qq

# ── Базовые пакеты ───────────────────────────────────────────
log "Установка базовых пакетов..."
apt-get install -y --no-install-recommends \
    linux-base initramfs-tools live-boot live-config \
    systemd systemd-sysv dbus udev \
    locales keyboard-configuration console-setup \
    network-manager wireless-tools wpasupplicant \
    sudo curl wget git ca-certificates \
    pciutils usbutils lshw \
    xorg xinit xserver-xorg \
    fluxbox alacritty feh \
    lightdm lightdm-gtk-greeter \
    nano less htop neofetch \
    fontconfig fonts-terminus fonts-liberation2 \
    pipewire pipewire-pulse wireplumber \
    gzip bzip2 xz-utils zstd \
    python3 python3-pip \
    2>/dev/null

ok "Базовые пакеты установлены"

# ── Микрокод CPU ──────────────────────────────────────────────
if [[ -n "${MICROCODE_PKG:-}" ]]; then
    log "Установка микрокода: $MICROCODE_PKG"
    apt-get install -y "$MICROCODE_PKG" 2>/dev/null && ok "Микрокод установлен"
fi

# ── Драйверы GPU ─────────────────────────────────────────────
if [[ "${NEEDS_NVIDIA:-false}" == "true" ]]; then
    log "Установка драйверов NVIDIA..."
    apt-get install -y nvidia-driver firmware-misc-nonfree 2>/dev/null
    ok "NVIDIA драйверы установлены"
fi
if [[ "${NEEDS_AMD_GPU:-false}" == "true" ]]; then
    log "Установка драйверов AMD..."
    apt-get install -y firmware-amd-graphics libgl1-mesa-dri 2>/dev/null
    ok "AMD драйверы установлены"
fi
if [[ "${NEEDS_INTEL_GPU:-false}" == "true" ]]; then
    log "Установка драйверов Intel..."
    apt-get install -y firmware-misc-nonfree intel-media-va-driver libgl1-mesa-dri 2>/dev/null
    ok "Intel GPU драйверы установлены"
fi
if [[ "${NEEDS_BROADCOM:-false}" == "true" ]]; then
    log "Установка firmware Broadcom..."
    apt-get install -y firmware-b43-installer broadcom-sta-dkms 2>/dev/null
    ok "Broadcom firmware установлен"
fi

# ── Языки программирования ────────────────────────────────────
/install_langs.sh

# ── LKRG ─────────────────────────────────────────────────────
/install_lkrg.sh

# ── Tor ───────────────────────────────────────────────────────
log "Установка Tor..."
apt-get install -y tor 2>/dev/null
systemctl enable tor 2>/dev/null || true
ok "Tor установлен"

# Tor Browser (скачиваем официальный релиз)
log "Загрузка Tor Browser..."
TB_VERSION=$(curl -s https://www.torproject.org/download/ \
    | grep -oP 'torbrowser/\K[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
TB_URL="https://www.torproject.org/dist/torbrowser/${TB_VERSION}/tor-browser-linux-x86_64-${TB_VERSION}.tar.xz"
curl -fsSL "$TB_URL" -o /tmp/torbrowser.tar.xz 2>/dev/null || \
    wget -qO /tmp/torbrowser.tar.xz "$TB_URL"
mkdir -p /opt/tor-browser
tar -xf /tmp/torbrowser.tar.xz --strip-components=1 -C /opt/tor-browser
ln -sf /opt/tor-browser/Browser/start-tor-browser /usr/local/bin/tor-browser
ok "Tor Browser установлен"

# ── Настройка имени хоста и локали ────────────────────────────
echo "blacklinux" > /etc/hostname
cat > /etc/hosts <<'EOF'
127.0.0.1   localhost
127.0.1.1   blacklinux
::1         localhost ip6-localhost ip6-loopback
EOF

sed -i 's/# ru_RU.UTF-8/ru_RU.UTF-8/' /etc/locale.gen
sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# ── Пользователь ──────────────────────────────────────────────
useradd -m -s /bin/bash -G sudo,audio,video,netdev,plugdev blackuser 2>/dev/null || true
echo "blackuser:blacklinux" | chpasswd
echo "root:blacklinux" | chpasswd

# ── Тема и конфиги ────────────────────────────────────────────
/root/theme/apply_theme.sh

# ── Автоматический вход в графику ────────────────────────────
mkdir -p /etc/lightdm
cat > /etc/lightdm/lightdm.conf <<'EOF'
[Seat:*]
autologin-user=blackuser
autologin-user-timeout=0
user-session=fluxbox
greeter-session=lightdm-gtk-greeter
EOF

# ── Оптимизации производительности ───────────────────────────
cat > /etc/sysctl.d/99-blacklinux.conf <<'EOF'
# Память
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
vm.vfs_cache_pressure=50
# Сеть
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_congestion_control=bbr
# Ядро
kernel.sched_latency_ns=3000000
kernel.sched_min_granularity_ns=300000
kernel.sched_wakeup_granularity_ns=500000
kernel.nmi_watchdog=0
kernel.randomize_va_space=2
EOF

# zram для swap
cat > /etc/modules-load.d/zram.conf <<'EOF'
zram
EOF
cat > /etc/udev/rules.d/99-zram.rules <<'EOF'
KERNEL=="zram0", ACTION=="add", ATTR{disksize}="4G", RUN+="/sbin/mkswap /dev/zram0", RUN+="/sbin/swapon /dev/zram0"
EOF

# ── Включить нужные сервисы ───────────────────────────────────
systemctl enable lightdm NetworkManager 2>/dev/null || true
systemctl disable bluetooth 2>/dev/null || true  # только если не нужен

# ── Очистка ───────────────────────────────────────────────────
apt-get autoremove -y -qq
apt-get clean -qq
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
rm -f /hw_profile.env /chroot_setup.sh /install_langs.sh /install_lkrg.sh

ok "chroot настройка полностью завершена"
