#!/bin/bash

# ─────────────────────────────────────────────
#  AstraCloud Bot Installer
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
    local var=$1 label=$2 default=$3
    [[ -n "$default" ]] \
        && echo -ne "  ${LIGHT_BLUE}▸${RESET} ${WHITE}${label}${RESET} ${DIM}[${default}]:${RESET} " \
        || echo -ne "  ${LIGHT_BLUE}▸${RESET} ${WHITE}${label}${RESET}: "
    read -r input
    [[ -z "$input" && -n "$default" ]] && eval "$var=\"$default\"" || eval "$var=\"$input\""
}

prompt_secret() {
    local var=$1 label=$2
    echo -ne "  ${LIGHT_BLUE}▸${RESET} ${WHITE}${label}${RESET}: "
    read -rs input; echo ""
    eval "$var=\"$input\""
}

zfs_is_functional() {
    zfs list > /dev/null 2>&1
}

# ══════════════════════════════════════════════
#  BANNER
# ══════════════════════════════════════════════
clear
echo -e "${LIGHT_BLUE}"
cat << 'EOF'
               _              _____ _                 _ 
     /\       | |            / ____| |               | |
    /  \   ___| |_ _ __ __ _| |    | | ___  _   _  __| |
   / /\ \ / __| __| '__/ _` | |    | |/ _ \| | | |/ _` |
  / ____ \\__ \ |_| | | (_| | |____| | (_) | |_| | (_| |
 /_/    \_\___/\__|_|  \__,_|\_____|_|\___/ \__,_|\__,_|
                                                        
                                                        
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
        if [[ $REMAINING -gt 0 ]]; then
            echo -e "  ${RED}✘  Invalid key. ${REMAINING} attempt(s) remaining.${RESET}\n"; sleep 2
        else
            echo -e "\n  ${RED}╔══════════════════════════════════════════════╗${RESET}"
            echo -e "  ${RED}║   ✘  Access denied — too many attempts.      ║${RESET}"
            echo -e "  ${RED}╚══════════════════════════════════════════════╝${RESET}\n"
            exit 1
        fi
    fi
done

[[ "$EUID" -ne 0 ]] && fail "Please run as root or with sudo."

# ══════════════════════════════════════════════
#  CONFIGURATION WIZARD
# ══════════════════════════════════════════════
echo -e "  ${CYAN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "  ${CYAN}║${RESET}  ${LIGHT_BLUE}⚙  Bot Configuration${RESET}                        ${CYAN}║${RESET}"
echo -e "  ${CYAN}║${RESET}  ${DIM}Press Enter to accept [defaults]${RESET}            ${CYAN}║${RESET}"
echo -e "  ${CYAN}╚══════════════════════════════════════════════╝${RESET}"
echo ""

echo -e "  ${WHITE}── Discord ──────────────────────────────────${RESET}"
prompt_secret DISCORD_TOKEN  "Bot Token (discord.com/developers)"
prompt        BOT_NAME       "Bot display name"           "AstraCloud"
prompt        PREFIX         "Command prefix"             "!"
prompt        BOT_VERSION    "Bot version"                "v1.0-PRO"
prompt        BOT_DEVELOPER  "Developer name"             "Hopingboz"
prompt        LOGO_URL       "Bot logo URL (embed thumbnail)" "https://i.imgur.com/dpatuSj.png"

echo ""
echo -e "  ${WHITE}── Admin ────────────────────────────────────${RESET}"
prompt MAIN_ADMIN_ID      "Your Discord User ID"               ""
prompt VPS_USER_ROLE_ID   "VPS User Role ID (0 = auto-create)" "0"

echo ""
echo -e "  ${WHITE}── Server ───────────────────────────────────${RESET}"
DETECTED_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
[[ -n "$DETECTED_IP" ]] && info "Detected public IP: ${DETECTED_IP}"
prompt YOUR_SERVER_IP "Server public IP" "${DETECTED_IP:-127.0.0.1}"

echo ""
echo -e "  ${WHITE}── Thresholds ───────────────────────────────${RESET}"
prompt CPU_THRESHOLD "CPU usage threshold (%)" "90"
prompt RAM_THRESHOLD "RAM usage threshold (%)" "90"

echo ""
echo -e "  ${WHITE}── Economy ──────────────────────────────────${RESET}"
prompt COINS_PER_INVITE          "Coins per invite"              "50"
prompt COINS_PER_MESSAGE         "Coins per message"             "1"
prompt COINS_PER_VOICE_MINUTE    "Coins per voice minute"        "2"
prompt COINS_DAILY_REWARD        "Daily reward coins"            "100"
prompt DEFAULT_VPS_DURATION_DAYS "Default VPS duration (days)"   "7"
echo ""

# ══════════════════════════════════════════════
#  COUNTDOWN
# ══════════════════════════════════════════════
echo -e "  ${DIM}Starting installation in...${RESET}"
for i in 3 2 1; do echo -ne "  ${LIGHT_BLUE}${i}${RESET}\r"; sleep 1; done
echo -e "  ${GREEN}Go!${RESET}\n"

# ══════════════════════════════════════════════
#  STEP 1 — System packages
# ══════════════════════════════════════════════
step "Updating system packages"
(apt-get update -qq > /dev/null 2>&1) & spinner $! "Refreshing apt cache"
ok "Done"

step "Installing base dependencies"
(apt-get install -y python3-pip wget snapd curl -qq > /dev/null 2>&1) & spinner $! "Installing apt packages"
ok "Done"

step "Configuring pip"
(mkdir -p ~/.config/pip && echo -e "[global]\nbreak-system-packages = true" > ~/.config/pip/pip.conf) &
spinner $! "Writing pip config"; ok "Done"

step "Installing Python packages"
(pip3 install discord PyNaCl requests -q > /dev/null 2>&1) & spinner $! "Installing discord PyNaCl requests"
ok "Done"

# ══════════════════════════════════════════════
#  STEP 2 — ZFS detection
# ══════════════════════════════════════════════
step "Detecting ZFS support"

STORAGE_BACKEND="dir"
POOL_SIZE=""

if ! command -v zfs &>/dev/null; then
    apt-get install -y zfsutils-linux -qq > /dev/null 2>&1
fi

if zfs_is_functional; then
    FREE_KB=$(df / | awk 'NR==2 {print $4}')
    FREE_GB=$(( FREE_KB / 1024 / 1024 ))
    if [[ $FREE_GB -gt 6 ]]; then
        LOOP_GB=$(( FREE_GB - 5 ))
        STORAGE_BACKEND="zfs"
        POOL_SIZE="${LOOP_GB}GB"
        ok "ZFS functional — pool: ${LOOP_GB}GB (${FREE_GB}GB free, 5GB reserved)"
    else
        warn "ZFS works but only ${FREE_GB}GB free — falling back to dir"
    fi
else
    warn "ZFS not supported on this system — using directory backend"
    info "(/dev/zfs unavailable — unprivileged container or no ZFS kernel module)"
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
#  STEP 5 — Download bot.py
# ══════════════════════════════════════════════
step "Downloading bot.py"
(wget -q "https://raw.githubusercontent.com/StriderCraft315/lol/main/bot.py" -O /root/bot.py 2>/dev/null) &
spinner $! "Fetching bot.py"
[[ -f /root/bot.py && -s /root/bot.py ]] && ok "bot.py downloaded to /root/bot.py" || fail "Download failed — check repo visibility."

# ══════════════════════════════════════════════
#  STEP 6 — Patch bot.py (inject config, remove dotenv)
# ══════════════════════════════════════════════
step "Patching bot.py with your configuration"

# Escape special chars for use in python string literals
esc() { printf '%s' "$1" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g"; }

TOKEN_ESC=$(esc "$DISCORD_TOKEN")
NAME_ESC=$(esc "$BOT_NAME")
PREFIX_ESC=$(esc "$PREFIX")
IP_ESC=$(esc "$YOUR_SERVER_IP")
VER_ESC=$(esc "$BOT_VERSION")
DEV_ESC=$(esc "$BOT_DEVELOPER")
LOGO_ESC=$(esc "$LOGO_URL")

(python3 - << PYEOF
import re

with open('/root/bot.py', 'r') as f:
    src = f.read()

# ── 1. Remove dotenv import and load_dotenv() calls ──────────────────────────
src = re.sub(r'from dotenv import load_dotenv\n', '', src)
src = re.sub(r'load_dotenv\(.*?\)\n', '', src)

# ── 2. Replace the config block (lines 23-34) with hardcoded values ──────────
old_block = re.search(
    r"DISCORD_TOKEN = os\.getenv\('DISCORD_TOKEN'\).*?BOT_DEVELOPER = os\.getenv\('BOT_DEVELOPER'.*?\)",
    src, re.DOTALL
)
if old_block:
    new_block = """DISCORD_TOKEN = '${TOKEN_ESC}'
if not DISCORD_TOKEN:
    raise ValueError("DISCORD_TOKEN is not set.")

BOT_NAME = '${NAME_ESC}'
PREFIX = '${PREFIX_ESC}'
YOUR_SERVER_IP = '${IP_ESC}'
MAIN_ADMIN_ID = ${MAIN_ADMIN_ID}
VPS_USER_ROLE_ID = ${VPS_USER_ROLE_ID}
DEFAULT_STORAGE_POOL = 'default'
BOT_VERSION = '${VER_ESC}'
BOT_DEVELOPER = '${DEV_ESC}'"""
    src = src[:old_block.start()] + new_block + src[old_block.end():]

# ── 3. Replace all remaining os.getenv calls for these vars ──────────────────
replacements = {
    r"os\.getenv\('DISCORD_TOKEN'\)":             "'${TOKEN_ESC}'",
    r"os\.getenv\('BOT_NAME',\s*'[^']*'\)":       "'${NAME_ESC}'",
    r"os\.getenv\('PREFIX',\s*'[^']*'\)":         "'${PREFIX_ESC}'",
    r"os\.getenv\('YOUR_SERVER_IP',\s*'[^']*'\)": "'${IP_ESC}'",
    r"os\.getenv\('MAIN_ADMIN_ID',\s*'[^']*'\)":  "'${MAIN_ADMIN_ID}'",
    r"os\.getenv\('VPS_USER_ROLE_ID',\s*'[^']*'\)": "'${VPS_USER_ROLE_ID}'",
    r"os\.getenv\('DEFAULT_STORAGE_POOL',\s*'[^']*'\)": "'default'",
    r"os\.getenv\('BOT_VERSION',\s*'[^']*'\)":    "'${VER_ESC}'",
    r"os\.getenv\('BOT_DEVELOPER',\s*'[^']*'\)":  "'${DEV_ESC}'",
    r"os\.getenv\('CPU_THRESHOLD',\s*'[^']*'\)":  "'${CPU_THRESHOLD}'",
    r"os\.getenv\('RAM_THRESHOLD',\s*'[^']*'\)":  "'${RAM_THRESHOLD}'",
}
for pattern, replacement in replacements.items():
    src = re.sub(pattern, replacement, src)

# ── 4. Replace hardcoded thumbnail URLs with user's logo ─────────────────────
src = src.replace('https://i.imgur.com/dpatuSj.png', '${LOGO_ESC}')

# ── 5. Patch reload-env command — no longer reads from .env ──────────────────
src = src.replace(
    'load_dotenv(override=True)',
    '# config is baked in — no .env to reload'
)

with open('/root/bot.py', 'w') as f:
    f.write(src)

print("ok")
PYEOF
sleep 0.3) & spinner $! "Injecting config into bot.py"

# Verify patch worked
if python3 -c "import ast; ast.parse(open('/root/bot.py').read())" 2>/dev/null; then
    ok "bot.py patched and syntax verified"
else
    fail "bot.py has a syntax error after patching — check your token/config for special characters"
fi

# ══════════════════════════════════════════════
#  STEP 7 — Systemd service (unixbot)
# ══════════════════════════════════════════════
step "Creating systemd service"
cat > /etc/systemd/system/unixbot.service << 'SVCEOF'
[Unit]
Description=UnixBot Discord Bot
After=network.target

[Service]
User=root
WorkingDirectory=/root
Environment="PYTHONUNBUFFERED=1"
ExecStart=/usr/bin/python3 /root/bot.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF
ok "Service file written to /etc/systemd/system/unixbot.service"

step "Starting unixbot service"
(systemctl daemon-reload > /dev/null 2>&1) & spinner $! "Reloading daemon"
(systemctl enable unixbot > /dev/null 2>&1) & spinner $! "Enabling on boot"
(systemctl restart unixbot > /dev/null 2>&1 && sleep 0.8) & spinner $! "Starting bot"
systemctl is-active --quiet unixbot && ok "Bot is running" || warn "Check: systemctl status unixbot"

# ══════════════════════════════════════════════
#  DONE
# ══════════════════════════════════════════════
echo ""
echo -e "  ${CYAN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "  ${CYAN}║${RESET}  ${GREEN}✔  Installation complete!${RESET}                   ${CYAN}║${RESET}"
echo -e "  ${CYAN}╠══════════════════════════════════════════════╣${RESET}"
echo -e "  ${CYAN}║${RESET}  ${WHITE}LXD backend :${RESET} ${LIGHT_BLUE}${STORAGE_BACKEND}$(  [[ $POOL_SIZE ]] && echo " (${POOL_SIZE})" )${RESET}$(printf '%*s' $(( 30 - ${#STORAGE_BACKEND} - ${#POOL_SIZE} - 1 )) '')${CYAN}║${RESET}"
echo -e "  ${CYAN}║${RESET}  ${WHITE}Server IP   :${RESET} ${LIGHT_BLUE}${YOUR_SERVER_IP}${RESET}$(printf '%*s' $(( 30 - ${#YOUR_SERVER_IP} )) '')${CYAN}║${RESET}"
echo -e "  ${CYAN}║${RESET}  ${WHITE}Bot file    :${RESET} ${LIGHT_BLUE}/root/bot.py${RESET}                   ${CYAN}║${RESET}"
echo -e "  ${CYAN}╠══════════════════════════════════════════════╣${RESET}"
echo -e "  ${CYAN}║${RESET}  ${LIGHT_BLUE}systemctl status unixbot${RESET}  — check status    ${CYAN}║${RESET}"
echo -e "  ${CYAN}║${RESET}  ${LIGHT_BLUE}systemctl restart unixbot${RESET} — restart         ${CYAN}║${RESET}"
echo -e "  ${CYAN}║${RESET}  ${LIGHT_BLUE}journalctl -u unixbot -f${RESET}  — live logs       ${CYAN}║${RESET}"
echo -e "  ${CYAN}║${RESET}  ${LIGHT_BLUE}lxc list${RESET}                  — containers       ${CYAN}║${RESET}"
echo -e "  ${CYAN}╚══════════════════════════════════════════════╝${RESET}"
echo ""
