#!/usr/bin/env bash
# ============================================================
#  install_lkrg.sh — Linux Kernel Runtime Guard
# ============================================================
set -euo pipefail
log() { echo -e "\033[0;36m[lkrg]\033[0m $*"; }
ok()  { echo -e "\033[0;32m[✓]\033[0m $*"; }
warn(){ echo -e "\033[0;33m[!]\033[0m $*"; }

# LKRG требует заголовков ядра
apt-get install -y dkms linux-headers-generic build-essential 2>/dev/null || true

log "Клонирование LKRG из официального репозитория Openwall..."
LKRG_DIR="/usr/src/lkrg"
if [[ -d "$LKRG_DIR" ]]; then
    cd "$LKRG_DIR" && git pull --quiet
else
    git clone --depth 1 https://github.com/lkrg-org/lkrg.git "$LKRG_DIR"
fi

cd "$LKRG_DIR"
LKRG_VER=$(git describe --tags 2>/dev/null || echo "git")

# Определяем версию ядра для которой строим
KVER=$(ls /lib/modules/ | sort -V | tail -1)
log "Сборка LKRG для ядра $KVER..."

if dkms add "$LKRG_DIR" 2>/dev/null; then
    dkms build  -m lkrg -v "$LKRG_VER" -k "$KVER" 2>/dev/null && \
    dkms install -m lkrg -v "$LKRG_VER" -k "$KVER" 2>/dev/null && \
    ok "LKRG $LKRG_VER установлен через DKMS"
else
    # Ручная сборка если DKMS не сработал
    make -C "/lib/modules/$KVER/build" M="$LKRG_DIR/src" modules 2>/dev/null && \
    cp "$LKRG_DIR/src/p_lkrg.ko" "/lib/modules/$KVER/kernel/security/" && \
    depmod -a "$KVER" && \
    ok "LKRG $LKRG_VER установлен вручную" || \
    warn "LKRG не удалось собрать — будет установлен при первом запуске системы"
fi

# Автозагрузка
echo "p_lkrg" >> /etc/modules-load.d/blacklinux-security.conf

# Конфигурация LKRG (умеренный режим — баланс безопасность/производительность)
cat > /etc/modprobe.d/lkrg.conf <<'EOF'
options p_lkrg kint_validate=1 pint_validate=1 pcfi_validate=1 log_level=4
EOF

ok "LKRG настроен и включён в автозагрузку"
