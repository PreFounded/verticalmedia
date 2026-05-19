#!/bin/bash
# verticalmedia installer for Linux/macOS
# Usage: curl -sSL https://raw.githubusercontent.com/PreFounded/verticalmedia/main/install.sh | bash

set -e

CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${CYAN}"
cat << 'BANNER'
  ██╗   ██╗███╗   ███╗
  ██║   ██║████╗ ████║
  ██║   ██║██╔████╔██║
  ╚██╗ ██╔╝██║╚██╔╝██║
   ╚████╔╝ ██║ ╚═╝ ██║
    ╚═══╝  ╚═╝     ╚═╝
BANNER
echo -e "${NC}  verticalmedia installer"
echo "  ─────────────────────"

echo -e "\n${YELLOW}Checking Python...${NC}"
if ! command -v python3 &>/dev/null; then
    echo -e "${RED}Python 3 not found. Installing...${NC}"
    if command -v apt &>/dev/null; then sudo apt update && sudo apt install -y python3 python3-pip
    elif command -v pacman &>/dev/null; then sudo pacman -S --noconfirm python python-pip
    elif command -v dnf &>/dev/null; then sudo dnf install -y python3 python3-pip
    elif command -v brew &>/dev/null; then brew install python3
    else echo -e "${RED}Cannot install Python. Please install Python 3.10+ manually.${NC}"; exit 1; fi
fi

PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo -e "${GREEN}✓ Python ${PYTHON_VERSION} found${NC}"

python3 -c "import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)" || {
    echo -e "${RED}Python 3.10+ required. Found ${PYTHON_VERSION}.${NC}"; exit 1; }

INSTALL_DIR="${HOME}/verticalmedia"
echo -e "\n${YELLOW}Installing to ${INSTALL_DIR}...${NC}"

if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}Existing installation found. Updating...${NC}"
    cd "$INSTALL_DIR" && git pull 2>/dev/null || true
else
    if command -v git &>/dev/null; then
        git clone https://github.com/PreFounded/verticalmedia "$INSTALL_DIR"
    else
        mkdir -p "$INSTALL_DIR"
        curl -sSL https://github.com/PreFounded/verticalmedia/archive/main.tar.gz \
            | tar -xz -C "$INSTALL_DIR" --strip-components=1
    fi
fi

cd "$INSTALL_DIR"

echo -e "\n${YELLOW}Installing dependencies...${NC}"
pip3 install -r requirements.txt --break-system-packages 2>/dev/null || \
pip3 install -r requirements.txt --user
echo -e "${GREEN}✓ Dependencies installed${NC}"

echo -e "\n${YELLOW}Configuration${NC}"
echo "─────────────────────────────────"

read -p "qBittorrent URL [http://localhost:8081]: " QBIT_URL
QBIT_URL="${QBIT_URL:-http://localhost:8081}"

read -p "qBittorrent Username [admin]: " QBIT_USER
QBIT_USER="${QBIT_USER:-admin}"

read -s -p "qBittorrent Password [adminadmin]: " QBIT_PASS
echo ""
QBIT_PASS="${QBIT_PASS:-adminadmin}"

read -p "Prowlarr URL (optional, press Enter to skip): " PROWLARR_URL
read -p "Prowlarr API Key (optional): " PROWLARR_KEY

echo -e "\n${YELLOW}Download Paths${NC}"
read -p "Anime path [/downloads/anime]: " PATH_ANIME
PATH_ANIME="${PATH_ANIME:-/downloads/anime}"
read -p "Movies path [/downloads/movies]: " PATH_MOVIES
PATH_MOVIES="${PATH_MOVIES:-/downloads/movies}"
read -p "Shows path [/downloads/shows]: " PATH_SHOWS
PATH_SHOWS="${PATH_SHOWS:-/downloads/shows}"

cat > "$INSTALL_DIR/.env" << ENV
QBIT_URL=${QBIT_URL}
QBIT_USERNAME=${QBIT_USER}
QBIT_PASSWORD=${QBIT_PASS}
PROWLARR_URL=${PROWLARR_URL}
PROWLARR_KEY=${PROWLARR_KEY}
PATH_ANIME=${PATH_ANIME}
PATH_MOVIES=${PATH_MOVIES}
PATH_SHOWS=${PATH_SHOWS}
VM_PORT=7171
ENV
echo -e "${GREEN}✓ Configuration saved${NC}"

read -p "Install as systemd service (auto-start on boot)? [Y/n]: " INSTALL_SERVICE
INSTALL_SERVICE="${INSTALL_SERVICE:-Y}"

if [[ "$INSTALL_SERVICE" =~ ^[Yy] ]] && command -v systemctl &>/dev/null; then
    mkdir -p ~/.config/systemd/user/
    cat > ~/.config/systemd/user/verticalmedia.service << SVCEOF
[Unit]
Description=verticalmedia - Torrent Search Manager
After=network.target

[Service]
ExecStart=$(which python3) -m uvicorn main:app --host 0.0.0.0 --port 7171
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
SVCEOF
    systemctl --user daemon-reload
    systemctl --user enable --now verticalmedia
    echo -e "${GREEN}✓ Service installed and started${NC}"
else
    cat > "$INSTALL_DIR/run.sh" << RUNEOF
#!/bin/bash
cd "\$(dirname "\$0")"
set -a; source .env; set +a
python3 -m uvicorn main:app --host 0.0.0.0 --port 7171
RUNEOF
    chmod +x "$INSTALL_DIR/run.sh"
    echo -e "${YELLOW}Run with: ${INSTALL_DIR}/run.sh${NC}"
fi

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ verticalmedia installed successfully${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "\n  Open: ${CYAN}http://localhost:7171${NC}"
echo -e "  Docs: ${CYAN}http://localhost:7171/docs${NC}\n"
