#!/usr/bin/env bash
# verticalmedia installer — Linux & macOS
# Usage: curl -sSL https://raw.githubusercontent.com/PreFounded/verticalmedia/main/install.sh | bash

set -euo pipefail

REPO="https://github.com/PreFounded/verticalmedia.git"

# ─────────────────────────────────────────────────────────────────────────────
#  Colours
# ─────────────────────────────────────────────────────────────────────────────
CY='\033[0;36m'; GR='\033[0;32m'; YL='\033[1;33m'
RD='\033[0;31m'; DM='\033[2m'; NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────────────────────────────────────
header() {
    printf '\033[H\033[2J' 2>/dev/null || true
    printf "${CY}"
    cat << 'BANNER'

  ██╗   ██╗███╗   ███╗
  ██║   ██║████╗ ████║
  ██║   ██║██╔████╔██║
  ╚██╗ ██╔╝██║╚██╔╝██║
   ╚████╔╝ ██║ ╚═╝ ██║
    ╚═══╝  ╚═╝     ╚═╝
BANNER
    printf "${NC}  verticalmedia installer\n\n"
}

section() {
    local title="$1"
    local pad=$(( 44 - ${#title} ))
    local line; line=$(printf '─%.0s' $(seq 1 $pad))
    printf "\n${CY}  ── %s %s${NC}\n" "$title" "$line"
}

ok()   { printf "  ${GR}v${NC}  %s\n" "$1"; }
info() { printf "  ${DM}   %s${NC}\n" "$1"; }
warn() { printf "  ${YL}!${NC}  %s\n" "$1"; }
die()  { printf "\n  ${RD}x${NC}  %s\n\n" "$1" >&2; exit 1; }

# read from /dev/tty so it works when piped through curl | bash
ask() {
    local prompt="$1" default="${2:-}"
    if [[ -n "$default" ]]; then
        printf "     ${NC}%s ${DM}[%s]${NC}: " "$prompt" "$default" >/dev/tty
    else
        printf "     ${NC}%s: " "$prompt" >/dev/tty
    fi
    local val
    read -r val </dev/tty
    [[ -z "$val" ]] && val="$default"
    printf '%s' "$val"
}

ask_secret() {
    local prompt="$1" default="${2:-}"
    if [[ -n "$default" ]]; then
        printf "     ${NC}%s ${DM}[%s]${NC}: " "$prompt" "$default" >/dev/tty
    else
        printf "     ${NC}%s: " "$prompt" >/dev/tty
    fi
    local val
    read -rs val </dev/tty; echo >/dev/tty
    [[ -z "$val" ]] && val="$default"
    printf '%s' "$val"
}

ask_yn() {
    local prompt="$1" default="${2:-y}"
    local hint; [[ "$default" == "y" ]] && hint="Y/n" || hint="y/N"
    printf "     ${NC}%s ${DM}[%s]${NC}: " "$prompt" "$hint" >/dev/tty
    local val
    read -r val </dev/tty
    [[ -z "$val" ]] && val="$default"
    # tr instead of ${val,,} for bash 3.x compatibility (macOS ships bash 3.2)
    [[ "$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')" == "y" ]]
}

# Expand leading ~ to $HOME (tilde is not expanded inside $(...) subshells)
expand_path() {
    local p="$1"
    case "$p" in
        "~/"|"~")  printf '%s' "$HOME" ;;
        "~/"*)     printf '%s' "$HOME/${p:2}" ;;
        *)         printf '%s' "$p" ;;
    esac
}

# Run a command silently in background with a spinner; show output only on failure
run_spin() {
    local label="$1"; shift
    local log; log=$(mktemp)
    "$@" >"$log" 2>&1 &
    local pid=$! sp='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r     ${CY}%s${NC}  %s  " "${sp:$((i++ % ${#sp})):1}" "$label" >/dev/tty
        sleep 0.1
    done
    printf "\r                                                        \r" >/dev/tty
    local rc=0; wait "$pid" || rc=$?
    [[ $rc -ne 0 ]] && { cat "$log" >&2; rm -f "$log"; return $rc; }
    rm -f "$log"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Package manager detection
# ─────────────────────────────────────────────────────────────────────────────
PM=""
if   command -v apt-get &>/dev/null; then PM="apt"
elif command -v pacman  &>/dev/null; then PM="pacman"
elif command -v dnf     &>/dev/null; then PM="dnf"
elif command -v brew    &>/dev/null; then PM="brew"
fi

pm_install() {
    case "$PM" in
        apt)    sudo apt-get install -y "$@" ;;
        pacman) sudo pacman -S --noconfirm "$@" ;;
        dnf)    sudo dnf install -y "$@" ;;
        brew)   brew install "$@" ;;
        *)      die "No supported package manager found. Install manually: $*" ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
#  Python — find or install >= 3.10
# ─────────────────────────────────────────────────────────────────────────────
find_python() {
    for cmd in python3.13 python3.12 python3.11 python3.10 python3 python; do
        if command -v "$cmd" &>/dev/null; then
            local ver; ver=$("$cmd" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null) || continue
            local maj="${ver%%.*}"; local min="${ver##*.}"
            if (( maj > 3 || (maj == 3 && min >= 10) )); then
                printf '%s' "$cmd"; return 0
            fi
        fi
    done
    return 1
}

install_python() {
    section "Installing Python"
    case "$PM" in
        apt)
            sudo -v
            info "Trying python3.12 from default repos..."
            if apt-cache show python3.12 &>/dev/null 2>&1; then
                run_spin "Updating package list (~15s)..." sudo apt-get update -qq
                run_spin "Installing Python 3.12 (1-3 min)..." \
                    sudo apt-get install -y python3.12 python3.12-venv python3.12-distutils || \
                run_spin "Installing Python 3.12 (1-3 min)..." \
                    sudo apt-get install -y python3.12 python3.12-venv
            else
                info "Adding deadsnakes PPA for Python 3.12..."
                run_spin "Installing prerequisites (~30s)..." \
                    sudo apt-get install -y software-properties-common
                run_spin "Adding deadsnakes PPA..." \
                    sudo add-apt-repository -y ppa:deadsnakes/ppa
                run_spin "Updating package list (~15s)..." sudo apt-get update -qq
                run_spin "Installing Python 3.12 (1-3 min)..." \
                    sudo apt-get install -y python3.12 python3.12-venv
            fi
            ;;
        pacman) info "Installing Python (~1-2 min)..."; pm_install python python-pip ;;
        dnf)    info "Installing Python (~1-2 min)..."; pm_install python3.12 python3-pip 2>/dev/null || pm_install python3 python3-pip ;;
        brew)   info "Installing Python (~1-3 min)..."; brew install python@3.12 ;;
        *)      die "No package manager found. Install Python 3.10+ from https://python.org and re-run." ;;
    esac
}

install_git() {
    section "Installing Git"
    case "$PM" in
        apt)
            sudo -v
            run_spin "Updating package list (~15s)..." sudo apt-get update -qq
            run_spin "Installing git (~30s)..." sudo apt-get install -y git
            ;;
        pacman) info "Installing git (~30s)..."; pm_install git ;;
        dnf)    info "Installing git (~30s)..."; pm_install git ;;
        brew)   info "Installing git (~1 min)..."; brew install git ;;
        *)      die "No package manager found. Install Git from https://git-scm.com and re-run." ;;
    esac
}

install_curl() {
    case "$PM" in
        apt)
            run_spin "Updating package list (~15s)..." sudo apt-get update -qq
            run_spin "Installing curl (~15s)..." sudo apt-get install -y curl
            ;;
        pacman) pm_install curl ;;
        dnf)    pm_install curl ;;
        brew)   brew install curl ;;
        *)      warn "Could not install curl — some auto-setup steps may be skipped." ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
#  qBittorrent — find, install, configure (unattended)
# ─────────────────────────────────────────────────────────────────────────────
find_qbittorrent() {
    for cmd in qbittorrent-nox qbittorrent; do
        if command -v "$cmd" &>/dev/null; then
            printf '%s' "$(command -v "$cmd")"; return 0
        fi
    done
    return 1
}

install_qbittorrent() {
    info "Installing qbittorrent-nox (headless torrent daemon)..."
    case "$PM" in
        apt)
            sudo -v
            run_spin "Updating package list (~15s)..." sudo apt-get update -qq
            if apt-cache show qbittorrent-nox &>/dev/null 2>&1; then
                run_spin "Installing qbittorrent-nox (~1 min)..." sudo apt-get install -y qbittorrent-nox
            else
                run_spin "Installing qbittorrent (~1 min)..." sudo apt-get install -y qbittorrent
            fi
            ;;
        pacman) pm_install qbittorrent-nox 2>/dev/null || pm_install qbittorrent ;;
        dnf)    pm_install qbittorrent-nox 2>/dev/null || pm_install qbittorrent ;;
        brew)   brew install --cask qbittorrent 2>/dev/null || brew install qbittorrent ;;
        *)      warn "Cannot auto-install qBittorrent. Download from https://qbittorrent.org" ;;
    esac
}

# Write or patch qBittorrent.ini to enable Web UI with no local-auth
configure_qbit_ini() {
    local port="$1" user="$2"
    local ini_dir="$HOME/.config/qBittorrent"
    local ini_file="$ini_dir/qBittorrent.ini"

    # Stop any running instance so the ini write is safe
    pkill -x qbittorrent-nox 2>/dev/null || true
    pkill -x qbittorrent     2>/dev/null || true
    sleep 1

    # Use a temp Python script to patch the ini — avoids shell escaping hell
    # with backslash-separated key names like "WebUI\Port"
    local pyscript; pyscript=$(mktemp /tmp/vm_qbitcfg_XXXXX.py)
    cat > "$pyscript" << 'PYEOF'
import re, sys, os

path, port, user = sys.argv[1], sys.argv[2], sys.argv[3]

def patch(text, section, key, value):
    """Set key=value under [section], inserting both if absent."""
    key_pat = re.compile(r'^' + re.escape(key) + r'\s*=.*$', re.MULTILINE)
    if key_pat.search(text):
        return key_pat.sub(key + '=' + value, text)
    # Insert right after [section] header line
    sec_m = re.search(r'\[' + re.escape(section) + r'\]', text)
    if sec_m:
        nl = text.find('\n', sec_m.end())
        ins = (nl + 1) if nl >= 0 else len(text)
        return text[:ins] + key + '=' + value + '\n' + text[ins:]
    # Section missing — append at end
    return text.rstrip('\n') + '\n\n[' + section + ']\n' + key + '=' + value + '\n'

text = open(path, encoding='utf-8').read() if os.path.exists(path) else ''

for sec, key, val in [
    ('LegalNotice', 'Accepted',               'true'),
    ('Preferences', r'WebUI\Enabled',         'true'),
    ('Preferences', r'WebUI\Port',            port),
    ('Preferences', r'WebUI\Username',        user),
    ('Preferences', r'WebUI\LocalHostAuth',   'false'),
    ('Preferences', r'WebUI\CSRFProtection',  'false'),
    ('Preferences', r'General\StartMinimized','true'),
]:
    text = patch(text, sec, key, val)

os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
with open(path, 'w', encoding='utf-8') as f:
    f.write(text)
PYEOF
    "$PYTHON" "$pyscript" "$ini_file" "$port" "$user"
    rm -f "$pyscript"
    ok "qBittorrent config written (port $port, user $user, local-auth disabled)"
}

start_qbittorrent_service() {
    local qbit_bin="$1"

    if command -v systemctl &>/dev/null; then
        local svc_dir="$HOME/.config/systemd/user"
        mkdir -p "$svc_dir"
        cat > "$svc_dir/qbittorrent-nox.service" << SVCEOF
[Unit]
Description=qBittorrent-nox Daemon
After=network.target

[Service]
ExecStart=${qbit_bin} --confirm-legal-notice
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SVCEOF
        systemctl --user daemon-reload
        systemctl --user enable --now qbittorrent-nox 2>/dev/null || \
            systemctl --user restart qbittorrent-nox 2>/dev/null || true
        ok "qbittorrent-nox started as systemd user service"
        info "Manage: systemctl --user start|stop|status qbittorrent-nox"

    elif [[ "$(uname)" == "Darwin" ]]; then
        local plist="$HOME/Library/LaunchAgents/org.qbittorrent.nox.plist"
        mkdir -p "$HOME/Library/LaunchAgents"
        cat > "$plist" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key>             <string>org.qbittorrent.nox</string>
  <key>ProgramArguments</key>  <array>
    <string>${qbit_bin}</string>
    <string>--confirm-legal-notice</string>
  </array>
  <key>RunAtLoad</key>         <true/>
  <key>KeepAlive</key>         <true/>
  <key>StandardOutPath</key>   <string>${HOME}/Library/Logs/qbittorrent-nox.log</string>
  <key>StandardErrorPath</key> <string>${HOME}/Library/Logs/qbittorrent-nox.log</string>
</dict></plist>
PLISTEOF
        launchctl load "$plist" 2>/dev/null || \
            launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || true
        ok "qBittorrent LaunchAgent installed (auto-starts at login)"

    else
        nohup "$qbit_bin" --confirm-legal-notice &>/dev/null &
        info "qBittorrent started in background (no service manager found)"
    fi
}

wait_for_webui() {
    local port="$1"
    printf "     ${DM}Waiting for Web UI${NC}" >/dev/tty
    local i
    for i in $(seq 1 30); do
        if curl -sf "http://localhost:$port/api/v2/app/version" &>/dev/null 2>&1; then
            printf "\n" >/dev/tty
            ok "qBittorrent Web UI ready: http://localhost:$port"
            return 0
        fi
        printf "${DM}.${NC}" >/dev/tty
        sleep 1
    done
    printf "\n" >/dev/tty
    warn "qBittorrent Web UI did not respond in 30s — download categories need manual setup."
    return 1
}

create_qbit_categories() {
    local port="$1" path_anime="$2" path_movies="$3" path_shows="$4"
    local base="http://localhost:$port"
    for pair in "anime:$path_anime" "movies:$path_movies" "shows:$path_shows"; do
        local cat_name="${pair%%:*}"
        local cat_path="${pair#*:}"
        mkdir -p "$cat_path" 2>/dev/null || true
        if curl -sf -X POST "$base/api/v2/torrents/createCategory" \
            --data-urlencode "category=$cat_name" \
            --data-urlencode "savePath=$cat_path" &>/dev/null 2>&1; then
            ok "Category '$cat_name' → $cat_path"
        else
            warn "Could not create category '$cat_name' — add manually in qBittorrent."
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  Step 1 — Requirements: Python, Git, curl, qBittorrent
# ─────────────────────────────────────────────────────────────────────────────
header
section "Requirements"

# Python
PYTHON=""
if ! PYTHON=$(find_python); then
    warn "Python 3.10+ not found — installing automatically."
    install_python
    PYTHON=$(find_python) || die "Python installation failed. Install Python 3.10+ manually."
fi
PY_VER=$("$PYTHON" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
ok "Python $PY_VER ($PYTHON)"

# Git
if ! command -v git &>/dev/null; then
    warn "Git not found — installing automatically."
    install_git
fi
ok "$(git --version)"

# curl (needed for qBit API calls and category setup)
if ! command -v curl &>/dev/null; then
    warn "curl not found — installing automatically."
    install_curl
fi
command -v curl &>/dev/null && ok "curl $(curl --version 2>/dev/null | head -1 | awk '{print $2}')"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 2 — qBittorrent: detect and install
# ─────────────────────────────────────────────────────────────────────────────
section "qBittorrent"
info "qBittorrent is required — verticalmedia sends torrents directly to its Web UI."
info "qbittorrent-nox is the headless daemon, perfect for servers (no display needed)."
echo

QBIT_BIN=$(find_qbittorrent || true)
if [[ -z "$QBIT_BIN" ]]; then
    warn "qBittorrent not found — installing automatically."
    install_qbittorrent
    QBIT_BIN=$(find_qbittorrent || true)
    if [[ -n "$QBIT_BIN" ]]; then
        ok "Installed: $QBIT_BIN"
    else
        warn "qBittorrent install may have failed — install manually from https://qbittorrent.org"
    fi
else
    ok "Found: $QBIT_BIN"
fi

# ─────────────────────────────────────────────────────────────────────────────
#  Step 3 — Install location
# ─────────────────────────────────────────────────────────────────────────────
section "Install location"

info "This is where the verticalmedia app files will be placed."
info "The directory will be created if it doesn't exist."
info "Press Enter to accept the default, or type a custom path."
echo

DEFAULT_DIR="$HOME/verticalmedia"
INSTALL_DIR_RAW=$(ask "Install path" "$DEFAULT_DIR")

# Expand leading ~ that would not expand inside $(...) subshells
INSTALL_DIR=$(expand_path "$INSTALL_DIR_RAW")

# Ensure we got something
if [[ -z "$INSTALL_DIR" ]]; then
    warn "No path entered — using default: $DEFAULT_DIR"
    INSTALL_DIR="$DEFAULT_DIR"
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
    warn "Existing installation found — will update to latest."
elif [[ -d "$INSTALL_DIR" ]]; then
    warn "Folder already exists — app files will be placed inside it."
else
    if ! mkdir -p "$INSTALL_DIR" 2>/dev/null; then
        die "Cannot create directory: $INSTALL_DIR\nCheck that you have write permission to the parent folder."
    fi
fi
ok "Install path: $INSTALL_DIR"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 4 — Clone / update
# ─────────────────────────────────────────────────────────────────────────────
section "Downloading verticalmedia"

if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Pulling latest changes..."
    git -C "$INSTALL_DIR" pull --ff-only
else
    info "Cloning repository (~20s, depends on connection)..."
    git clone "$REPO" "$INSTALL_DIR"
fi
ok "Files ready"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 5 — Virtual environment + dependencies
# ─────────────────────────────────────────────────────────────────────────────
section "Python environment"

VENV="$INSTALL_DIR/.venv"
VENV_PYTHON="$VENV/bin/python"

if [[ ! -d "$VENV" ]]; then
    info "Creating virtual environment..."
    "$PYTHON" -m venv "$VENV" || {
        case "$PM" in
            apt) sudo apt-get install -y "python${PY_VER}-venv" python3-venv 2>/dev/null || true ;;
        esac
        "$PYTHON" -m venv "$VENV"
    }
fi

run_spin "Upgrading pip..." "$VENV_PYTHON" -m pip install -q --upgrade pip
run_spin "Installing packages (~30-90s)..." "$VENV_PYTHON" -m pip install -q -r "$INSTALL_DIR/requirements.txt"
ok "Dependencies installed"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 6 — Configuration
# ─────────────────────────────────────────────────────────────────────────────
ENV_FILE="$INSTALL_DIR/.env"
DO_CONFIG=true

if [[ -f "$ENV_FILE" ]]; then
    section "Existing configuration found"
    if ! ask_yn "Reconfigure settings?" "n"; then
        DO_CONFIG=false
        info "Keeping existing configuration."
        VM_PORT=$(grep -m1 '^VM_PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo "7171")
    fi
fi

if $DO_CONFIG; then
    section "qBittorrent connection"
    QBIT_URL=$(ask  "qBittorrent Web UI URL" "http://localhost:8081")
    QBIT_USER=$(ask "qBittorrent username"   "admin")
    QBIT_PASS=$(ask_secret "qBittorrent password" "adminadmin")

    section "Prowlarr (optional)"
    info "Prowlarr aggregates many torrent indexers into one API."
    info "Skip this if you don't use it — configurable later via Settings."
    echo
    PROWLARR_URL=""; PROWLARR_KEY=""
    if ask_yn "Do you use Prowlarr?" "n"; then
        PROWLARR_URL=$(ask "Prowlarr URL"     "http://localhost:9696")
        PROWLARR_KEY=$(ask "Prowlarr API key" "")
    fi

    section "Download paths"
    info "Choose a media folder — Anime, Movies and Shows subfolders are created inside it."
    echo
    DEFAULT_MEDIA="$HOME/VerticalMedia"
    MEDIA_DIR_RAW=$(ask "Media folder" "$DEFAULT_MEDIA")
    MEDIA_DIR=$(expand_path "$MEDIA_DIR_RAW")
    [[ -z "$MEDIA_DIR" ]] && MEDIA_DIR="$DEFAULT_MEDIA"

    PATH_ANIME="$MEDIA_DIR/Anime"
    PATH_MOVIES="$MEDIA_DIR/Movies"
    PATH_SHOWS="$MEDIA_DIR/Shows"

    for _p in "$PATH_ANIME" "$PATH_MOVIES" "$PATH_SHOWS"; do
        mkdir -p "$_p"
    done
    ok "$MEDIA_DIR/{Anime, Movies, Shows}"

    section "Server settings"
    VM_PORT=$(ask "Port to listen on" "7171")

    cat > "$ENV_FILE" << ENV
# qBittorrent
QBIT_URL=${QBIT_URL}
QBIT_USERNAME=${QBIT_USER}
QBIT_PASSWORD=${QBIT_PASS}

# Prowlarr (leave KEY empty to disable)
PROWLARR_URL=${PROWLARR_URL}
PROWLARR_KEY=${PROWLARR_KEY}

# Download paths
PATH_ANIME=${PATH_ANIME}
PATH_MOVIES=${PATH_MOVIES}
PATH_SHOWS=${PATH_SHOWS}

# Server
VM_HOST=0.0.0.0
VM_PORT=${VM_PORT}
ENV
    ok ".env written to $ENV_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
#  Step 7 — Configure qBittorrent (only for localhost installs)
# ─────────────────────────────────────────────────────────────────────────────

# Read effective values from .env so this works whether DO_CONFIG ran or not
_QBIT_URL=$(grep -m1  '^QBIT_URL='       "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
_QBIT_USER=$(grep -m1 '^QBIT_USERNAME='  "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
_PATH_ANIME=$(grep -m1  '^PATH_ANIME='   "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
_PATH_MOVIES=$(grep -m1 '^PATH_MOVIES='  "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
_PATH_SHOWS=$(grep -m1  '^PATH_SHOWS='   "$ENV_FILE" 2>/dev/null | cut -d= -f2-)

_QBIT_HOST=$("$PYTHON" -c "
from urllib.parse import urlparse
print(urlparse('${_QBIT_URL:-http://localhost:8081}').hostname or 'localhost')
" 2>/dev/null || echo "localhost")

_QBIT_PORT=$("$PYTHON" -c "
from urllib.parse import urlparse
print(urlparse('${_QBIT_URL:-http://localhost:8081}').port or 8081)
" 2>/dev/null || echo "8081")

_QBIT_PORT="${_QBIT_PORT:-8081}"
_QBIT_USER="${_QBIT_USER:-admin}"

# Determine if qBit is local
_IS_LOCAL=false
case "${_QBIT_HOST:-localhost}" in
    localhost|127.0.0.1|::1) _IS_LOCAL=true ;;
esac

if $_IS_LOCAL && [[ -n "$QBIT_BIN" ]]; then
    section "Configuring qBittorrent"
    configure_qbit_ini "$_QBIT_PORT" "$_QBIT_USER"
    start_qbittorrent_service "$QBIT_BIN"

    if command -v curl &>/dev/null; then
        if wait_for_webui "$_QBIT_PORT"; then
            create_qbit_categories "$_QBIT_PORT" \
                "${_PATH_ANIME:-/downloads/anime}" \
                "${_PATH_MOVIES:-/downloads/movies}" \
                "${_PATH_SHOWS:-/downloads/shows}"
        fi
    else
        warn "curl not available — skipping category auto-setup. Add categories manually in qBittorrent."
    fi
elif ! $_IS_LOCAL; then
    section "qBittorrent (remote)"
    info "qBittorrent is on a remote host ($_QBIT_HOST) — configure its Web UI manually."
    info "Make sure 'Bypass auth for localhost' is enabled if verticalmedia is on the same host."
fi

# ─────────────────────────────────────────────────────────────────────────────
#  Step 8 — Always write run.sh
# ─────────────────────────────────────────────────────────────────────────────
RUN_SH="$INSTALL_DIR/run.sh"
cat > "$RUN_SH" << RUNEOF
#!/usr/bin/env bash
cd "\$(dirname "\$0")"
set -a; source .env; set +a
exec .venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port \${VM_PORT:-7171}
RUNEOF
chmod +x "$RUN_SH"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 9 — Systemd / launchd service for verticalmedia (optional)
# ─────────────────────────────────────────────────────────────────────────────
section "Run verticalmedia on startup (optional)"
info "Without a service, use run.sh to start verticalmedia manually."
echo

INSTALLED_SERVICE=false

if command -v systemctl &>/dev/null; then
    if ask_yn "Install verticalmedia as a systemd user service? (auto-starts at login)" "y"; then
        SVC_DIR="$HOME/.config/systemd/user"
        mkdir -p "$SVC_DIR"
        cat > "$SVC_DIR/verticalmedia.service" << SVCEOF
[Unit]
Description=verticalmedia — Torrent Search Manager
After=network.target

[Service]
ExecStart=${VENV_PYTHON} -m uvicorn main:app --host 0.0.0.0 --port ${VM_PORT}
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${ENV_FILE}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SVCEOF
        systemctl --user daemon-reload
        systemctl --user enable --now verticalmedia
        ok "verticalmedia service installed and started (auto-starts at login)"
        info "Manage: systemctl --user start|stop|restart|status verticalmedia"
        info "Logs:   journalctl --user -u verticalmedia -f"
        INSTALLED_SERVICE=true
    else
        ok "Skipped — use run.sh to start manually."
    fi

elif [[ "$(uname)" == "Darwin" ]]; then
    if ask_yn "Install as a launchd agent? (auto-starts at login)" "y"; then
        PLIST="$HOME/Library/LaunchAgents/com.verticalmedia.plist"
        mkdir -p "$HOME/Library/LaunchAgents"
        cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>              <string>com.verticalmedia</string>
  <key>ProgramArguments</key>   <array>
    <string>${VENV_PYTHON}</string>
    <string>-m</string><string>uvicorn</string>
    <string>main:app</string>
    <string>--host</string><string>0.0.0.0</string>
    <string>--port</string><string>${VM_PORT}</string>
  </array>
  <key>WorkingDirectory</key>   <string>${INSTALL_DIR}</string>
  <key>RunAtLoad</key>          <true/>
  <key>KeepAlive</key>          <true/>
  <key>StandardOutPath</key>    <string>${INSTALL_DIR}/verticalmedia.log</string>
  <key>StandardErrorPath</key>  <string>${INSTALL_DIR}/verticalmedia.log</string>
</dict>
</plist>
PLISTEOF
        launchctl load "$PLIST" 2>/dev/null || \
            launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || true
        ok "LaunchAgent installed (auto-starts at login)"
        info "Manage: launchctl start|stop com.verticalmedia"
        INSTALLED_SERVICE=true
    else
        ok "Skipped — use run.sh to start manually."
    fi
else
    warn "No service manager found — using run.sh only."
fi

# ─────────────────────────────────────────────────────────────────────────────
#  Step 10 — Firewall (UFW / firewalld)
# ─────────────────────────────────────────────────────────────────────────────
if command -v ufw &>/dev/null; then
    if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
        section "Firewall (UFW)"
        sudo ufw allow "${VM_PORT}/tcp" comment "verticalmedia" 2>/dev/null && \
            ok "UFW: port ${VM_PORT}/tcp allowed" || \
            warn "Could not add UFW rule — run: sudo ufw allow ${VM_PORT}/tcp"
        if $_IS_LOCAL && [[ -n "$QBIT_BIN" ]]; then
            sudo ufw allow "${_QBIT_PORT}/tcp" comment "qBittorrent Web UI" 2>/dev/null && \
                ok "UFW: port ${_QBIT_PORT}/tcp allowed" || true
        fi
    fi
elif command -v firewall-cmd &>/dev/null; then
    if sudo firewall-cmd --state 2>/dev/null | grep -q "running"; then
        section "Firewall (firewalld)"
        sudo firewall-cmd --permanent --add-port="${VM_PORT}/tcp" 2>/dev/null && \
            sudo firewall-cmd --reload 2>/dev/null && \
            ok "firewalld: port ${VM_PORT}/tcp added" || \
            warn "Could not add firewalld rule — run: sudo firewall-cmd --permanent --add-port=${VM_PORT}/tcp"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
#  Done
# ─────────────────────────────────────────────────────────────────────────────
echo
printf "  ${CY}──────────────────────────────────────────────${NC}\n"
printf "   ${GR}verticalmedia is ready!${NC}\n\n"
printf "   Open  > ${CY}http://localhost:${VM_PORT}${NC}\n"
printf "   API   > ${DM}http://localhost:${VM_PORT}/docs${NC}\n\n"
if $_IS_LOCAL && [[ -n "$QBIT_BIN" ]]; then
    printf "   qBit  > ${DM}http://localhost:${_QBIT_PORT}${NC}\n\n"
fi
printf "   Config : ${DM}${ENV_FILE}${NC}\n"
printf "   Run    : ${DM}${RUN_SH}${NC}\n"
if $INSTALLED_SERVICE; then
    printf "   Logs   : ${DM}journalctl --user -u verticalmedia -f${NC}\n"
fi
printf "  ${CY}──────────────────────────────────────────────${NC}\n\n"
