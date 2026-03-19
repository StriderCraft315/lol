#!/bin/bash

# ─────────────────────────────────────────────
#  NexusCloud Bot Installer
# ─────────────────────────────────────────────

LIGHT_BLUE='\033[1;36m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
DIM='\033[2m'
RESET='\033[0m'

VALID_KEY_HASH="34550715062af006ac4fab288de67ecb44793c3a05c475227241535f6ef7a81b"

spinner() {
    local pid=$1 msg=$2
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${LIGHT_BLUE}${frames[$i]}${RESET}  ${WHITE}%s${RESET}${DIM}...${RESET}" "$msg"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.08
    done
    printf "\r  ${GREEN}✔${RESET}  ${WHITE}%s${RESET}%-30s\n" "$msg" " "
}

step() { echo -e "\n  ${LIGHT_BLUE}┌─${RESET} ${WHITE}$1${RESET}"; }
ok()   { echo -e "  ${LIGHT_BLUE}└─${RESET} ${GREEN}✔ $1${RESET}"; }
warn() { echo -e "  ${LIGHT_BLUE}└─${RESET} ${YELLOW}⚠ $1${RESET}"; }
fail() { echo -e "\n  ${RED}✘ $1${RESET}\n"; exit 1; }
info() { echo -e "       ${DIM}$1${RESET}"; }

prompt() {
    # prompt <VAR_NAME> <display_label> <default>
    local var=$1 label=$2 default=$3
    if [[ -n "$default" ]]; then
        echo -ne "  ${LIGHT_BLUE}▸${RESET} ${WHITE}${label}${RESET} ${DIM}[${default}]:${RESET} "
    else
        echo -ne "  ${LIGHT_BLUE}▸${RESET} ${WHITE}${label}${RESET}: "
    fi
    read -r input
    if [[ -z "$input" && -n "$default" ]]; then
        eval "$var=\"$default\""
    else
        eval "$var=\"$input\""
    fi
}

prompt_secret() {
    local var=$1 label=$2
    echo -ne "  ${LIGHT_BLUE}▸${RESET} ${WHITE}${label}${RESET}: "
    read -rs input; echo ""
    eval "$var=\"$input\""
}

# ══════════════════════════════════════════════
#  BANNER
# ══════════════════════════════════════════════
clear
echo -e "${LIGHT_BLUE}"
cat << 'EOF'
    _   _                          _                 _
   | \ | |                        | |               | |
   |  \| | _____  ___   _ ___  ___| | ___  _   _  __| |
   | . ` |/ _ \ \/ / | | / __|/ __| |/ _ \| | | |/ _` |
   | |\  |  __/>  <| |_| \__ \ (__| | (_) | |_| | (_| |
   |_| \_|\___/_/\_\\__,_|___/\___|_|\___/ \__,_|\__,_|

EOF
echo -e "${RESET}"
echo -e "  ${CYAN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "  ${CYAN}║${RESET}      ${WHITE}Discord Bot Installer  •  LXC Edition${RESET}     ${CYAN}║${RESET}"
echo -e "  ${CYAN}╚══════════════════════════════════════════════╝${RESET}"
echo ""

# ══════════════════════════════════════════════
#  KEY VERIFICATION
# ══════════════════════════════════════════════
echo -e "  ${CYAN}┌─────────────────────────────────────────────┐${RESET}"
echo -e "  ${CYAN}│${RESET}  ${LIGHT_BLUE}🔑  License Key Required${RESET}                     ${CYAN}│${RESET}"
echo -e "  ${CYAN}└─────────────────────────────────────────────┘${RESET}"
echo ""

MAX_ATTEMPTS=3; ATTEMPT=0
while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
    ATTEMPT=$(( ATTEMPT + 1 ))
    echo -ne "  ${WHITE}Enter your license key:${RESET} "
    read -rs USER_KEY; echo ""
    USER_HASH=$(printf '%s' "$USER_KEY" | sha256sum | awk '{print $1}')
    if [[ "$USER_HASH" == "$VALID_KEY_HASH" ]]; then
        echo ""; (sleep 1.0) & spinner $! "Verifying key"
        echo -e "\n  ${GREEN}✔  Access granted.${RESET}\n"; sleep 0.4; break
    else
        REMAINING=$(( MAX_ATTEMPTS - ATTEMPT ))
        [[ $REMAINING -gt 0 ]] && { echo -e "  ${RED}✘  Invalid key. ${REMAINING} attempt(s) remaining.${RESET}\n"; sleep 2; } \
        || { echo -e "\n  ${RED}╔══════════════════════════════════════════════╗\n  ║   ✘  Access denied — too many attempts.      ║\n  ╚══════════════════════════════════════════════╝${RESET}\n"; exit 1; }
    fi
done

[[ "$EUID" -ne 0 ]] && fail "Please run as root or with sudo."

# ══════════════════════════════════════════════
#  .ENV CONFIGURATION WIZARD
# ══════════════════════════════════════════════
echo -e "  ${CYAN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "  ${CYAN}║${RESET}  ${LIGHT_BLUE}⚙  Bot Configuration${RESET}                        ${CYAN}║${RESET}"
echo -e "  ${CYAN}║${RESET}  ${DIM}Press Enter to accept [defaults]${RESET}            ${CYAN}║${RESET}"
echo -e "  ${CYAN}╚══════════════════════════════════════════════╝${RESET}"
echo ""

echo -e "  ${WHITE}── Discord ──────────────────────────────────${RESET}"
prompt_secret   DISCORD_TOKEN   "Bot Token (discord.com/developers)"
prompt          BOT_NAME        "Bot display name"          "NexusCloud"
prompt          PREFIX          "Command prefix"            "!"
prompt          BOT_VERSION     "Bot version"               "v1.0-PRO"
prompt          BOT_DEVELOPER   "Developer name"            "Hopingboz"

echo ""
echo -e "  ${WHITE}── Admin ────────────────────────────────────${RESET}"
prompt          MAIN_ADMIN_ID   "Your Discord User ID"      ""
prompt          VPS_USER_ROLE_ID "VPS User Role ID (0 = auto-create)" "0"

echo ""
echo -e "  ${WHITE}── Server ───────────────────────────────────${RESET}"
# Auto-detect public IP, let user override
DETECTED_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
if [[ -n "$DETECTED_IP" ]]; then
    info "Detected public IP: ${DETECTED_IP}"
    prompt YOUR_SERVER_IP "Server public IP" "$DETECTED_IP"
else
    prompt YOUR_SERVER_IP "Server public IP" "127.0.0.1"
fi

echo ""
echo -e "  ${WHITE}── Thresholds ───────────────────────────────${RESET}"
prompt CPU_THRESHOLD    "CPU usage threshold (%)"   "90"
prompt RAM_THRESHOLD    "RAM usage threshold (%)"   "90"

echo ""
echo -e "  ${WHITE}── Economy ──────────────────────────────────${RESET}"
prompt COINS_PER_INVITE          "Coins per invite"          "50"
prompt COINS_PER_MESSAGE         "Coins per message"         "1"
prompt COINS_PER_VOICE_MINUTE    "Coins per voice minute"    "2"
prompt COINS_DAILY_REWARD        "Daily reward coins"        "100"
prompt DEFAULT_VPS_DURATION_DAYS "Default VPS duration (days)" "7"

echo ""

# ══════════════════════════════════════════════
#  COUNTDOWN
# ══════════════════════════════════════════════
echo -e "  ${DIM}Starting installation in...${RESET}"
for i in 3 2 1; do echo -ne "  ${LIGHT_BLUE}${i}${RESET}\r"; sleep 1; done
echo -e "  ${GREEN}Go!${RESET}\n"

# ══════════════════════════════════════════════
#  STEP 1 — System update + deps
# ══════════════════════════════════════════════
step "Updating system packages"
(apt-get update -qq > /dev/null 2>&1) & spinner $! "Refreshing apt cache"
ok "Done"

step "Installing base dependencies"
(apt-get install -y python3-pip wget snapd curl -qq > /dev/null 2>&1) & spinner $! "Installing packages"
ok "Done"

step "Configuring pip"
(mkdir -p ~/.config/pip && echo -e "[global]\nbreak-system-packages = true" > ~/.config/pip/pip.conf) &
spinner $! "Writing pip config"; ok "Done"

# ══════════════════════════════════════════════
#  STEP 2 — ZFS detection (proper for LXC)
# ══════════════════════════════════════════════
step "Detecting ZFS availability"

ZFS_AVAILABLE=false
STORAGE_BACKEND="dir"
POOL_SIZE=""

# Check 1: kernel module already loaded
if lsmod 2>/dev/null | grep -q "^zfs "; then
    ZFS_AVAILABLE=true
    info "ZFS kernel module is loaded"
# Check 2: zfs binary exists and actually works
elif command -v zfs &>/dev/null && zfs list &>/dev/null 2>&1; then
    ZFS_AVAILABLE=true
    info "ZFS binary found and functional"
# Check 3: try loading the module (works on privileged containers)
elif modprobe zfs &>/dev/null 2>&1; then
    ZFS_AVAILABLE=true
    info "ZFS module loaded via modprobe"
# Check 4: try installing zfsutils and then check again
else
    info "Attempting to install zfsutils-linux..."
    if apt-get install -y zfsutils-linux -qq > /dev/null 2>&1; then
        if modprobe zfs &>/dev/null 2>&1 || zfs list &>/dev/null 2>&1; then
            ZFS_AVAILABLE=true
            info "ZFS installed and loaded successfully"
        fi
    fi
fi

if [[ "$ZFS_AVAILABLE" == "true" ]]; then
    # Calculate loop device size: free space minus 5GB reserve
    FREE_KB=$(df / | awk 'NR==2 {print $4}')
    FREE_GB=$(( FREE_KB / 1024 / 1024 ))

    if [[ $FREE_GB -gt 6 ]]; then
        LOOP_GB=$(( FREE_GB - 5 ))
        STORAGE_BACKEND="zfs"
        POOL_SIZE="${LOOP_GB}GB"
        ok "ZFS available — pool size: ${LOOP_GB}GB (${FREE_GB}GB free, 5GB reserved for host)"
    else
        warn "ZFS available but only ${FREE_GB}GB free — need >6GB. Falling back to dir."
        STORAGE_BACKEND="dir"
    fi
else
    warn "ZFS not available on this system — using directory backend"
    STORAGE_BACKEND="dir"
fi

# ══════════════════════════════════════════════
#  STEP 3 — Install LXD
# ══════════════════════════════════════════════
step "Installing LXD"
export PATH="/snap/bin:$PATH"

if command -v lxd &>/dev/null; then
    warn "LXD already installed — skipping"
else
    (snap install lxd > /dev/null 2>&1) & spinner $! "Installing LXD via snap"
    ok "LXD installed"
fi

# ══════════════════════════════════════════════
#  STEP 4 — Init LXD
# ══════════════════════════════════════════════
step "Initializing LXD (backend: ${STORAGE_BACKEND})"

# Check if already initialized by seeing if default profile has storage
ALREADY_INIT=false
lxc profile show default 2>/dev/null | grep -q "pool:" && ALREADY_INIT=true

if [[ "$ALREADY_INIT" == "true" ]]; then
    warn "LXD already initialized — skipping"
else
    if [[ "$STORAGE_BACKEND" == "zfs" ]]; then
        info "ZFS loop device: ${POOL_SIZE}"
        (cat <<PRESEED | lxd init --preseed > /dev/null 2>&1
config: {}
networks:
- config:
    ipv4.address: auto
    ipv6.address: none
  description: ""
  name: lxdbr0
  type: bridge
storage_pools:
- config:
    size: ${POOL_SIZE}
  description: ""
  name: default
  driver: zfs
profiles:
- config: {}
  description: ""
  devices:
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
PRESEED
) & spinner $! "Initializing LXD with ZFS (${POOL_SIZE})"

    else
        (cat <<PRESEED | lxd init --preseed > /dev/null 2>&1
config: {}
networks:
- config:
    ipv4.address: auto
    ipv6.address: none
  description: ""
  name: lxdbr0
  type: bridge
storage_pools:
- config: {}
  description: ""
  name: default
  driver: dir
profiles:
- config: {}
  description: ""
  devices:
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
PRESEED
) & spinner $! "Initializing LXD with directory backend"
    fi

    ok "LXD initialized"
fi

# ══════════════════════════════════════════════
#  STEP 5 — Download bot files
# ══════════════════════════════════════════════
step "Downloading bot.pyc"
(wget -q "https://raw.githubusercontent.com/StriderCraft315/lol/main/bot.pyc" -O /root/bot.pyc 2>/dev/null) &
spinner $! "Fetching bot.pyc"
[[ -f /root/bot.pyc && -s /root/bot.pyc ]] && ok "bot.pyc saved to /root/bot.pyc" || fail "Download failed — check repo visibility."

if wget -q "https://raw.githubusercontent.com/StriderCraft315/lol/main/requirements.txt" -O /tmp/req.txt 2>/dev/null && [[ -s /tmp/req.txt ]]; then
    step "Installing Python requirements"
    (pip3 install -r /tmp/req.txt -q > /dev/null 2>&1) & spinner $! "Installing packages"
    ok "Done"
fi

# ══════════════════════════════════════════════
#  STEP 6 — Write .env
# ══════════════════════════════════════════════
step "Writing .env configuration"

# Set DEFAULT_STORAGE_POOL based on what we actually initialized
[[ "$STORAGE_BACKEND" == "zfs" ]] && STORAGE_POOL_NAME="default" || STORAGE_POOL_NAME="default"

cat > /root/.env << ENVEOF
# ============================================
# UnixNodes VPS Bot Configuration
# Version: 7.1-PRO
# ============================================

# ============================================
# DISCORD BOT CONFIGURATION (REQUIRED)
# ============================================
DISCORD_TOKEN=${DISCORD_TOKEN}
BOT_NAME=${BOT_NAME}
PREFIX=${PREFIX}
BOT_VERSION=${BOT_VERSION}
BOT_DEVELOPER=${BOT_DEVELOPER}

# ============================================
# ADMIN CONFIGURATION (REQUIRED)
# ============================================
MAIN_ADMIN_ID=${MAIN_ADMIN_ID}
VPS_USER_ROLE_ID=${VPS_USER_ROLE_ID}

# ============================================
# SERVER CONFIGURATION
# ============================================
YOUR_SERVER_IP=${YOUR_SERVER_IP}
DEFAULT_STORAGE_POOL=${STORAGE_POOL_NAME}

# ============================================
# RESOURCE MONITORING THRESHOLDS
# ============================================
CPU_THRESHOLD=${CPU_THRESHOLD}
RAM_THRESHOLD=${RAM_THRESHOLD}

# ============================================
# COINS & ECONOMY SYSTEM
# ============================================
COINS_PER_INVITE=${COINS_PER_INVITE}
COINS_PER_MESSAGE=${COINS_PER_MESSAGE}
COINS_PER_VOICE_MINUTE=${COINS_PER_VOICE_MINUTE}
COINS_DAILY_REWARD=${COINS_DAILY_REWARD}
COINS_VPS_RENEWAL_1DAY=50
COINS_VPS_RENEWAL_7DAYS=350
COINS_VPS_RENEWAL_30DAYS=1500
DEFAULT_VPS_DURATION_DAYS=${DEFAULT_VPS_DURATION_DAYS}
VPS_EXPIRY_WARNING_HOURS=24
MESSAGE_COOLDOWN_SECONDS=60
VOICE_MIN_DURATION_MINUTES=5
LEADERBOARD_TOP_COUNT=10
ENVEOF

chmod 600 /root/.env
ok ".env written to /root/.env (chmod 600)"

# ══════════════════════════════════════════════
#  STEP 7 — Systemd service
# ══════════════════════════════════════════════
step "Creating systemd service"
(cat > /etc/systemd/system/bot.service << 'SVCEOF'
[Unit]
Description=UnixBot Discord Bot
After=network.target

[Service]
User=root
WorkingDirectory=/root
ExecStart=/usr/bin/python3 /root/bot.pyc
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SVCEOF
sleep 0.3) & spinner $! "Writing service file"; ok "Done"

step "Starting bot service"
(systemctl daemon-reload > /dev/null 2>&1) & spinner $! "Reloading daemon"
(systemctl enable bot > /dev/null 2>&1) & spinner $! "Enabling on boot"
(systemctl restart bot > /dev/null 2>&1 && sleep 0.5) & spinner $! "Starting bot"
systemctl is-active --quiet bot && ok "Bot is running" || warn "Check: systemctl status bot"

# ══════════════════════════════════════════════
#  DONE
# ══════════════════════════════════════════════
echo ""
echo -e "  ${CYAN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "  ${CYAN}║${RESET}  ${GREEN}✔  Installation complete!${RESET}                   ${CYAN}║${RESET}"
echo -e "  ${CYAN}╠══════════════════════════════════════════════╣${RESET}"
echo -e "  ${CYAN}║${RESET}  ${WHITE}LXD backend :${RESET} ${LIGHT_BLUE}${STORAGE_BACKEND}$(  [[ $POOL_SIZE ]] && echo " (${POOL_SIZE})" )${RESET}$(printf '%*s' $(( 30 - ${#STORAGE_BACKEND} - ${#POOL_SIZE} - 1 )) '')${CYAN}║${RESET}"
echo -e "  ${CYAN}║${RESET}  ${WHITE}Server IP   :${RESET} ${LIGHT_BLUE}${YOUR_SERVER_IP}${RESET}$(printf '%*s' $(( 30 - ${#YOUR_SERVER_IP} )) '')${CYAN}║${RESET}"
echo -e "  ${CYAN}║${RESET}  ${WHITE}.env        :${RESET} ${LIGHT_BLUE}/root/.env${RESET}                     ${CYAN}║${RESET}"
echo -e "  ${CYAN}╠══════════════════════════════════════════════╣${RESET}"
echo -e "  ${CYAN}║${RESET}  ${LIGHT_BLUE}systemctl status bot${RESET}   — check status        ${CYAN}║${RESET}"
echo -e "  ${CYAN}║${RESET}  ${LIGHT_BLUE}systemctl restart bot${RESET}  — restart              ${CYAN}║${RESET}"
echo -e "  ${CYAN}║${RESET}  ${LIGHT_BLUE}journalctl -u bot -f${RESET}   — live logs           ${CYAN}║${RESET}"
echo -e "  ${CYAN}║${RESET}  ${LIGHT_BLUE}lxc list${RESET}               — list containers      ${CYAN}║${RESET}"
echo -e "  ${CYAN}╚══════════════════════════════════════════════╝${RESET}"
echo ""
