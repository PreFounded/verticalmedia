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
    [[ "${val,,}" == "y" ]]
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
#  Python — find or install a version >= 3.10
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
            info "Trying python3.12 from default repos..."
            if apt-cache show python3.12 &>/dev/null 2>&1; then
                sudo apt-get update -qq
                pm_install python3.12 python3.12-venv python3.12-distutils 2>/dev/null || \
                pm_install python3.12 python3.12-venv
            else
                info "Adding deadsnakes PPA for Python 3.12..."
                pm_install software-properties-common
                sudo add-apt-repository -y ppa:deadsnakes/ppa
                sudo apt-get update -qq
                pm_install python3.12 python3.12-venv
            fi
            ;;
        pacman)
            pm_install python python-pip
            ;;
        dnf)
            pm_install python3.12 python3-pip 2>/dev/null || pm_install python3 python3-pip
            ;;
        brew)
            brew install python@3.12
            ;;
        *)
            die "No package manager found. Install Python 3.10+ from https://python.org and re-run."
            ;;
    esac
}

install_git() {
    section "Installing Git"
    case "$PM" in
        apt)    sudo apt-get update -qq; pm_install git ;;
        pacman) pm_install git ;;
        dnf)    pm_install git ;;
        brew)   brew install git ;;
        *)      die "No package manager found. Install Git from https://git-scm.com and re-run." ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
#  Step 1 — Requirements
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

# ─────────────────────────────────────────────────────────────────────────────
#  Step 2 — Install location
# ─────────────────────────────────────────────────────────────────────────────
section "Install location"

DEFAULT_DIR="$HOME/verticalmedia"
INSTALL_DIR=$(ask "Where should verticalmedia be installed?" "$DEFAULT_DIR")

if [[ -d "$INSTALL_DIR/.git" ]]; then
    warn "Existing installation found — will update to latest."
elif [[ -d "$INSTALL_DIR" ]]; then
    warn "Folder exists but is not a git repo — files may be overwritten."
else
    mkdir -p "$INSTALL_DIR"
fi
info "Location: $INSTALL_DIR"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 3 — Clone / update
# ─────────────────────────────────────────────────────────────────────────────
section "Downloading verticalmedia"

if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Pulling latest changes..."
    git -C "$INSTALL_DIR" pull --ff-only
else
    info "Cloning repository..."
    git clone "$REPO" "$INSTALL_DIR"
fi
ok "Files ready"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 4 — Virtual environment + dependencies
# ─────────────────────────────────────────────────────────────────────────────
section "Python environment"

VENV="$INSTALL_DIR/.venv"
VENV_PYTHON="$VENV/bin/python"

if [[ ! -d "$VENV" ]]; then
    info "Creating virtual environment..."
    "$PYTHON" -m venv "$VENV" || {
        # Debian/Ubuntu may need python3-venv installed
        case "$PM" in
            apt) sudo apt-get install -y "python${PY_VER}-venv" python3-venv 2>/dev/null || true ;;
        esac
        "$PYTHON" -m venv "$VENV"
    }
fi

info "Installing dependencies..."
"$VENV_PYTHON" -m pip install -q --upgrade pip
"$VENV_PYTHON" -m pip install -q -r "$INSTALL_DIR/requirements.txt"
ok "Dependencies installed"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 5 — Configuration
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
    section "qBittorrent"
    info "verticalmedia sends torrents directly to qBittorrent."
    info "Enable its Web UI first: qBittorrent > Preferences > Web UI > Enable Web UI"
    echo
    QBIT_URL=$(ask  "qBittorrent Web UI URL" "http://localhost:8081")
    QBIT_USER=$(ask "qBittorrent username"   "admin")
    QBIT_PASS=$(ask_secret "qBittorrent password" "adminadmin")

    section "Prowlarr (optional)"
    info "Prowlarr aggregates many torrent indexers into one API."
    info "Skip this if you don't use it — it can be added later in Settings."
    echo
    PROWLARR_URL=""; PROWLARR_KEY=""
    if ask_yn "Do you use Prowlarr?" "n"; then
        PROWLARR_URL=$(ask "Prowlarr URL"     "http://localhost:9696")
        PROWLARR_KEY=$(ask "Prowlarr API key" "")
    fi

    section "Download paths"
    info "Full paths to where torrents will be saved."
    info "These must match the category save paths configured in qBittorrent."
    echo
    PATH_ANIME=$(ask  "Anime save path"    "/downloads/anime")
    PATH_MOVIES=$(ask "Movies save path"   "/downloads/movies")
    PATH_SHOWS=$(ask  "TV shows save path" "/downloads/shows")

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
#  Step 6 — Always write run.sh
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
#  Step 7 — Systemd service (optional)
# ─────────────────────────────────────────────────────────────────────────────
section "Run on startup (optional)"
info "Without a service, use run.sh to start verticalmedia manually."
echo

INSTALLED_SERVICE=false

if command -v systemctl &>/dev/null; then
    if ask_yn "Install as a systemd user service? (auto-starts at login, runs in background)" "y"; then
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
        ok "Service installed and started (auto-starts at login)"
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
  <key>EnvironmentVariables</key>
  <dict>
    $(while IFS='=' read -r k v; do
        [[ -z "$k" || "$k" =~ ^# ]] && continue
        echo "    <key>${k}</key><string>${v}</string>"
      done < "$ENV_FILE")
  </dict>
  <key>RunAtLoad</key>          <true/>
  <key>KeepAlive</key>          <true/>
  <key>StandardOutPath</key>    <string>${INSTALL_DIR}/verticalmedia.log</string>
  <key>StandardErrorPath</key>  <string>${INSTALL_DIR}/verticalmedia.log</string>
</dict>
</plist>
PLISTEOF
        launchctl load "$PLIST"
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
#  Done
# ─────────────────────────────────────────────────────────────────────────────
echo
printf "  ${CY}──────────────────────────────────────────────${NC}\n"
printf "   ${GR}verticalmedia is ready!${NC}\n\n"
printf "   Open  > ${CY}http://localhost:${VM_PORT}${NC}\n"
printf "   API   > ${DM}http://localhost:${VM_PORT}/docs${NC}\n\n"
printf "   Config : ${DM}${ENV_FILE}${NC}\n"
printf "   Run    : ${DM}${RUN_SH}${NC}\n"
if $INSTALLED_SERVICE; then
    printf "   Logs   : ${DM}journalctl --user -u verticalmedia -f${NC}\n"
fi
printf "  ${CY}──────────────────────────────────────────────${NC}\n\n"
