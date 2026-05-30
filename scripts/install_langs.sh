#!/usr/bin/env bash
# ============================================================
#  install_langs.sh — языки программирования
# ============================================================
set -euo pipefail
log() { echo -e "\033[0;36m[langs]\033[0m $*"; }
ok()  { echo -e "\033[0;32m[✓]\033[0m $*"; }

# ── GCC ──────────────────────────────────────────────────────
log "GCC..."
apt-get install -y gcc g++ make binutils 2>/dev/null
ok "GCC $(gcc --version | head -1 | grep -oP '\d+\.\d+\.\d+')"

# ── Python ───────────────────────────────────────────────────
log "Python..."
apt-get install -y python3 python3-pip python3-venv python3-dev 2>/dev/null
ok "Python $(python3 --version | cut -d' ' -f2)"

# ── Golang ───────────────────────────────────────────────────
log "Go..."
GO_VER=$(curl -s "https://go.dev/dl/?mode=json" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d[0]['version'])")
curl -fsSL "https://go.dev/dl/${GO_VER}.linux-amd64.tar.gz" -o /tmp/go.tar.gz
rm -rf /usr/local/go
tar -C /usr/local -xzf /tmp/go.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/golang.sh
ok "Go $GO_VER"

# ── Rust ─────────────────────────────────────────────────────
log "Rust (rustup)..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --default-toolchain stable 2>/dev/null
cp /root/.cargo/bin/* /usr/local/bin/ 2>/dev/null || true
echo 'export PATH=$PATH:/root/.cargo/bin' > /etc/profile.d/rust.sh
ok "Rust $(rustc --version 2>/dev/null | cut -d' ' -f2 || echo 'installed')"

# ── Lua ──────────────────────────────────────────────────────
log "Lua..."
apt-get install -y lua5.4 luarocks 2>/dev/null
ok "Lua $(lua5.4 -v 2>&1 | cut -d' ' -f2)"

# ── GNU Nano ─────────────────────────────────────────────────
log "GNU Nano..."
apt-get install -y nano 2>/dev/null
# Улучшенная конфигурация nano
cat > /etc/nanorc <<'EOF'
set linenumbers
set autoindent
set tabsize 4
set mouse
set smooth
set titlecolor bold,white,black
set statuscolor bold,white,black
set errorcolor bold,white,red
set selectedcolor white,black
set numbercolor cyan
include "/usr/share/nano/*.nanorc"
EOF
ok "GNU Nano $(nano --version | head -1 | grep -oP '\d+\.\d+')"

rm -f /tmp/go.tar.gz
