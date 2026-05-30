#!/usr/bin/env bash
# ============================================================
#  apply_theme.sh — чёрная тема Black Linux
# ============================================================
set -euo pipefail
log() { echo -e "\033[0;36m[theme]\033[0m $*"; }
ok()  { echo -e "\033[0;32m[✓]\033[0m $*"; }

USER_HOME="/home/blackuser"
mkdir -p "$USER_HOME/.config/fluxbox"
mkdir -p "$USER_HOME/.config/alacritty"
mkdir -p "$USER_HOME/.local/share/themes/BlackLinux/openbox-3"
mkdir -p "$USER_HOME/Pictures"
mkdir -p /usr/share/pixmaps
mkdir -p /usr/share/backgrounds

# ── ASCII арт (логотип в терминале) ──────────────────────────
cat > /etc/blacklinux-ascii.txt <<'ASCIIEOF'

     ██████╗ ██╗      █████╗  ██████╗██╗  ██╗
     ██╔══██╗██║     ██╔══██╗██╔════╝██║ ██╔╝
     ██████╔╝██║     ███████║██║     █████╔╝
     ██╔══██╗██║     ██╔══██║██║     ██╔═██╗
     ██████╔╝███████╗██║  ██║╚██████╗██║  ██╗
     ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
          ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗
          ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝
          ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝
          ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗
          ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗
          ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝

           The Dark Side of Open Source
ASCIIEOF

# ── Обои (SVG → PNG через Python) ────────────────────────────
log "Генерация обоев..."
python3 - <<'PYEOF'
import os

svg = '''<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080">
  <defs>
    <radialGradient id="bg" cx="50%" cy="50%" r="70%">
      <stop offset="0%" stop-color="#0a0a0a"/>
      <stop offset="100%" stop-color="#000000"/>
    </radialGradient>
    <filter id="glow">
      <feGaussianBlur stdDeviation="3" result="coloredBlur"/>
      <feMerge><feMergeNode in="coloredBlur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <!-- Фон -->
  <rect width="1920" height="1080" fill="url(#bg)"/>
  <!-- Сетка -->
  <g stroke="#0d0d0d" stroke-width="1" opacity="0.8">
    <line x1="0" y1="0" x2="1920" y2="1080" stroke="#111" stroke-width="0.5"/>
    <line x1="1920" y1="0" x2="0" y2="1080" stroke="#111" stroke-width="0.5"/>
  </g>
  <!-- Горизонтальные линии сетки -->
  <g stroke="#111111" stroke-width="0.5" opacity="0.5">
    <line x1="0" y1="135" x2="1920" y2="135"/>
    <line x1="0" y1="270" x2="1920" y2="270"/>
    <line x1="0" y1="405" x2="1920" y2="405"/>
    <line x1="0" y1="540" x2="1920" y2="540"/>
    <line x1="0" y1="675" x2="1920" y2="675"/>
    <line x1="0" y1="810" x2="1920" y2="810"/>
    <line x1="0" y1="945" x2="1920" y2="945"/>
  </g>
  <!-- Вертикальные линии сетки -->
  <g stroke="#111111" stroke-width="0.5" opacity="0.5">
    <line x1="240" y1="0" x2="240" y2="1080"/>
    <line x1="480" y1="0" x2="480" y2="1080"/>
    <line x1="720" y1="0" x2="720" y2="1080"/>
    <line x1="960" y1="0" x2="960" y2="1080"/>
    <line x1="1200" y1="0" x2="1200" y2="1080"/>
    <line x1="1440" y1="0" x2="1440" y2="1080"/>
    <line x1="1680" y1="0" x2="1680" y2="1080"/>
  </g>
  <!-- Логотип текст центр -->
  <text x="960" y="430" font-family="monospace" font-size="96" font-weight="bold"
        fill="#1a1a1a" text-anchor="middle" filter="url(#glow)">BLACK LINUX</text>
  <text x="960" y="430" font-family="monospace" font-size="96" font-weight="bold"
        fill="#333333" text-anchor="middle">BLACK LINUX</text>
  <!-- Подзаголовок -->
  <text x="960" y="510" font-family="monospace" font-size="22"
        fill="#222222" text-anchor="middle">The Dark Side of Open Source</text>
  <!-- Декоративные уголки -->
  <rect x="100" y="100" width="200" height="2" fill="#1a1a1a"/>
  <rect x="100" y="100" width="2" height="200" fill="#1a1a1a"/>
  <rect x="1620" y="100" width="200" height="2" fill="#1a1a1a"/>
  <rect x="1818" y="100" width="2" height="200" fill="#1a1a1a"/>
  <rect x="100" y="978" width="200" height="2" fill="#1a1a1a"/>
  <rect x="100" y="780" width="2" height="200" fill="#1a1a1a"/>
  <rect x="1620" y="978" width="200" height="2" fill="#1a1a1a"/>
  <rect x="1818" y="780" width="2" height="200" fill="#1a1a1a"/>
</svg>'''

with open('/usr/share/backgrounds/blacklinux-wallpaper.svg', 'w') as f:
    f.write(svg)

print("SVG обои созданы")
PYEOF

ok "Обои созданы: /usr/share/backgrounds/blacklinux-wallpaper.svg"

# ── Логотип SVG ───────────────────────────────────────────────
cat > /usr/share/pixmaps/blacklinux-logo.svg <<'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="8" fill="#000000"/>
  <text x="32" y="22" font-family="monospace" font-size="10" font-weight="bold"
        fill="#333333" text-anchor="middle">BLACK</text>
  <text x="32" y="38" font-family="monospace" font-size="10" font-weight="bold"
        fill="#333333" text-anchor="middle">LINUX</text>
  <rect x="8" y="44" width="48" height="1" fill="#222222"/>
  <text x="32" y="56" font-family="monospace" font-size="6"
        fill="#1a1a1a" text-anchor="middle">obsidian</text>
</svg>
SVGEOF

# ── Fluxbox тема ──────────────────────────────────────────────
log "Настройка Fluxbox..."

# init
cat > "$USER_HOME/.config/fluxbox/init" <<'EOF'
session.menuFile: ~/.config/fluxbox/menu
session.keyFile: ~/.config/fluxbox/keys
session.styleFile: ~/.config/fluxbox/styles/BlackLinux
session.screen0.toolbar.visible: true
session.screen0.toolbar.height: 22
session.screen0.toolbar.layer: Dock
session.screen0.toolbar.placement: BottomCenter
session.screen0.toolbar.widthPercent: 100
session.screen0.toolbar.tools: workspacename, clock, systray
session.screen0.workspaces: 4
session.screen0.workspaceNames: Main,Dev,Net,Sec
session.screen0.window.focus.alpha: 255
session.screen0.window.unfocus.alpha: 200
session.screen0.rootCommand: feh --bg-fill /usr/share/backgrounds/blacklinux-wallpaper.svg
session.screen0.slit.autoHide: true
EOF

# startup
cat > "$USER_HOME/.config/fluxbox/startup" <<'EOF'
#!/usr/bin/env bash
# Запуск сервисов при входе
/usr/bin/pipewire &
/usr/bin/pipewire-pulse &
/usr/bin/wireplumber &
/usr/bin/nm-applet &
feh --bg-fill /usr/share/backgrounds/blacklinux-wallpaper.svg &
exec fluxbox
EOF
chmod +x "$USER_HOME/.config/fluxbox/startup"

# Стиль Fluxbox (чёрная тема)
mkdir -p "$USER_HOME/.config/fluxbox/styles"
cat > "$USER_HOME/.config/fluxbox/styles/BlackLinux" <<'EOF'
! ============ BLACK LINUX — Fluxbox Style ============
! Цвета
#define BG      #000000
#define BG2     #0a0a0a
#define BG3     #111111
#define FG      #cccccc
#define FG2     #888888
#define ACC     #333333
#define BORDER  #1a1a1a

! Заголовок окна (активное)
window.title.appearance: Flat
window.title.color: BG2
window.title.textColor: FG
window.title.font: terminus-12:bold
window.title.height: 20
window.label.active.appearance: Flat
window.label.active.color: BG3
window.label.active.textColor: FG
window.label.inactive.appearance: Flat
window.label.inactive.color: BG
window.label.inactive.textColor: FG2

! Кнопки
window.button.close.appearance: Flat
window.button.close.color: BG2
window.button.close.picColor: #444444
window.button.maximize.appearance: Flat
window.button.maximize.color: BG2
window.button.maximize.picColor: #333333
window.button.minimize.appearance: Flat
window.button.minimize.color: BG2
window.button.minimize.picColor: #333333
window.button.pressed.appearance: Flat
window.button.pressed.color: BG3

! Рамки
window.frame.focusColor: BORDER
window.frame.unfocusColor: BG
window.borderWidth: 1
window.borderColor: BORDER
window.handleWidth: 4

! Toolbar (панель задач)
toolbar.appearance: Flat
toolbar.color: BG
toolbar.textColor: FG2
toolbar.font: terminus-10
toolbar.height: 22
toolbar.clock.appearance: Flat
toolbar.clock.color: BG
toolbar.clock.textColor: #444444
toolbar.clock.font: terminus-10
toolbar.workspace.appearance: Flat
toolbar.workspace.color: BG
toolbar.workspace.textColor: #333333

! Меню
menu.appearance: Flat
menu.color: BG2
menu.textColor: FG
menu.font: terminus-11
menu.title.appearance: Flat
menu.title.color: BG3
menu.title.textColor: FG
menu.title.font: terminus-11:bold
menu.frame.appearance: Flat
menu.frame.color: BG2
menu.frame.textColor: FG2
menu.hilite.appearance: Flat
menu.hilite.color: BG3
menu.hilite.textColor: FG
menu.bullet.left: Triangle
menu.borderWidth: 1
menu.borderColor: BORDER
EOF

# Меню Fluxbox
cat > "$USER_HOME/.config/fluxbox/menu" <<'EOF'
[begin] (Black Linux)
  [exec] (Alacritty) {alacritty} </usr/share/pixmaps/blacklinux-logo.svg>
  [exec] (Tor Browser) {tor-browser}
  [exec] (File Manager) {thunar}
  [separator]
  [submenu] (Инструменты)
    [exec] (htop) {alacritty -e htop}
    [exec] (neofetch) {alacritty -e neofetch}
    [exec] (nano) {alacritty -e nano}
  [end]
  [submenu] (Сеть)
    [exec] (Firefox) {firefox-esr}
    [exec] (Tor Browser) {tor-browser}
    [exec] (NetworkManager) {nm-connection-editor}
  [end]
  [submenu] (Разработка)
    [exec] (Терминал) {alacritty}
    [exec] (Python) {alacritty -e python3}
    [exec] (Go REPL) {alacritty -e bash -c "go version; bash"}
  [end]
  [separator]
  [submenu] (Рабочий стол)
    [workspaces] (Переключить)
    [config] (Настройки)
    [reconfig] (Перезагрузить конфиг)
  [end]
  [separator]
  [restart] (Перезапустить Fluxbox)
  [exit] (Выход)
[end]
EOF

# ── Alacritty (чёрная тема) ───────────────────────────────────
log "Настройка Alacritty..."
cat > "$USER_HOME/.config/alacritty/alacritty.toml" <<'EOF'
[window]
opacity          = 0.95
padding          = { x = 8, y = 8 }
decorations      = "None"
startup_mode     = "Windowed"
title            = "Black Linux"

[font]
size = 11.0

[font.normal]
family = "Terminus"
style  = "Regular"

[font.bold]
family = "Terminus"
style  = "Bold"

[colors.primary]
background = "#000000"
foreground = "#cccccc"

[colors.cursor]
text   = "#000000"
cursor = "#444444"

[colors.normal]
black   = "#000000"
red     = "#1a1a1a"
green   = "#222222"
yellow  = "#2a2a2a"
blue    = "#333333"
magenta = "#3a3a3a"
cyan    = "#444444"
white   = "#888888"

[colors.bright]
black   = "#111111"
red     = "#555555"
green   = "#666666"
yellow  = "#777777"
blue    = "#888888"
magenta = "#999999"
cyan    = "#aaaaaa"
white   = "#cccccc"

[cursor]
style  = { shape = "Block", blinking = "On" }
blink_interval = 600

[scrolling]
history    = 10000
multiplier = 3

[selection]
save_to_clipboard = true

[keyboard]
bindings = [
  { key = "Return", mods = "Control|Shift", action = "SpawnNewInstance" },
  { key = "C",      mods = "Control|Shift", action = "Copy" },
  { key = "V",      mods = "Control|Shift", action = "Paste" },
]
EOF

# ── .bashrc с neofetch и ASCII-артом ─────────────────────────
log "Настройка bash..."
cat > "$USER_HOME/.bashrc" <<'BASHEOF'
# Black Linux .bashrc

# История
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoredups:erasedups
shopt -s histappend

# Prompt — минималистичный чёрно-серый
PS1='\[\033[0;90m\][\[\033[0;37m\]\u\[\033[0;90m\]@\[\033[0;37m\]\h\[\033[0;90m\]] \[\033[0;90m\]\w \[\033[0;37m\]▶\[\033[0m\] '

# Алиасы
alias ls='ls --color=auto -h'
alias ll='ls -la'
alias grep='grep --color=auto'
alias pm='sudo /usr/local/bin/pm'
alias update='sudo pm update && sudo pm upgrade'
alias ..='cd ..'
alias ...='cd ../..'
alias cls='clear'

# PATH
export PATH="$PATH:/usr/local/go/bin:$HOME/.cargo/bin:$HOME/.local/bin"
export GOPATH="$HOME/go"
export EDITOR="nano"

# Приветствие при входе
if [[ $- == *i* ]]; then
    cat /etc/blacklinux-ascii.txt
    echo ""
    neofetch --config /etc/neofetch.conf 2>/dev/null || true
fi
BASHEOF

cp "$USER_HOME/.bashrc" /root/.bashrc

# ── neofetch конфиг ───────────────────────────────────────────
cat > /etc/neofetch.conf <<'EOF'
print_info() {
    info title
    info underline
    info "OS"      distro
    info "Kernel"  kernel
    info "Shell"   shell
    info "WM"      wm
    info "Terminal" term
    info "CPU"     cpu
    info "GPU"     gpu
    info "Memory"  memory
    prin ""
    prin "$(color 0)███$(color 1)███$(color 2)███$(color 3)███$(color 4)███$(color 5)███$(color 6)███$(color 7)███$(color reset)"
}
kernel_shorthand="on"
distro_shorthand="off"
os_arch="on"
uptime_shorthand="tiny"
memory_percent="on"
package_managers="on"
speed_shorthand="on"
cpu_temp="C"
colors=(0 1 2 3 4 5 6 7)
bold="on"
underline_enabled="on"
separator=" ▶"
color_blocks="on"
EOF

# ── LightDM GTK greeter (чёрная тема) ─────────────────────────
log "Настройка экрана входа..."
mkdir -p /etc/lightdm
cat > /etc/lightdm/lightdm-gtk-greeter.conf <<'EOF'
[greeter]
background           = /usr/share/backgrounds/blacklinux-wallpaper.svg
theme-name           = Adwaita-dark
icon-theme-name      = Adwaita
font-name            = Terminus 11
xft-dpi              = 96
indicators           = ~spacer;~clock;~spacer;~session;~language;~a11y;~power
clock-format         = %H:%M  %d.%m.%Y
position             = 50%,center 50%,center
panel-position       = bottom
EOF

# ── Права ─────────────────────────────────────────────────────
chown -R blackuser:blackuser "$USER_HOME"

ok "Тема Black Linux применена"
