#!/bin/bash

# XMR Miner Setup Script for Debian 12
# Save this as: setup-xmr-miner.sh
# Make executable: chmod +x setup-xmr-miner.sh
# Run: ./setup-xmr-miner.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
POOL_URL="pool.supportxmr.com:443"
MINER_USER="debian-miner"
MINER_DIR="$HOME/xmr-miner"
CPU_THREADS=$(nproc)

print_status() {
    echo -e "${GREEN}[*]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [ "$EUID" -eq 0 ]; then
        print_warning "Script is running as root. It's better to run as a regular user."
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

check_dependencies() {
    print_status "Checking dependencies..."
    
    # Update package list
    sudo apt-get update > /dev/null 2>&1
    
    # Check and install required packages
    local missing_packages=()
    
    for package in wget curl git build-essential cmake libuv1-dev libssl-dev libhwloc-dev; do
        if ! dpkg -l | grep -q "^ii  $package"; then
            missing_packages+=($package)
        fi
    done
    
    if [ ${#missing_packages[@]} -ne 0 ]; then
        print_status "Installing missing packages: ${missing_packages[*]}"
        sudo apt-get install -y ${missing_packages[@]}
    fi
}

get_xmr_address() {
    echo "========================================"
    echo "Monero Miner Setup"
    echo "========================================"
    echo ""
    echo "You need a Monero wallet address to receive payments."
    echo "If you don't have one, you can create one at:"
    echo "- https://www.getmonero.org/downloads/"
    echo "- https://wallet.mymonero.com/"
    echo "- Or use a hardware wallet"
    echo ""
    
    while true; do
        read -p "Enter your Monero (XMR) address: " XMR_ADDRESS
        
        # Basic Monero address validation
        if [[ ${#XMR_ADDRESS} -ge 95 ]] && [[ ${XMR_ADDRESS:0:1} == "4" ]] || 
           [[ ${#XMR_ADDRESS} -ge 106 ]] && [[ ${XMR_ADDRESS:0:12} == "8" ]]; then
            echo ""
            print_status "Address format looks valid."
            echo "Address: ${XMR_ADDRESS:0:20}...${XMR_ADDRESS: -4}"
            read -p "Is this correct? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                break
            fi
        else
            print_error "Invalid Monero address format."
            print_warning "Standard addresses start with '4' (95 chars)"
            print_warning "Integrated addresses start with '4' (106 chars)"
            print_warning "Subaddresses start with '8' (95 chars)"
        fi
    done
}

choose_pool() {
    echo ""
    echo "========================================"
    echo "Select Mining Pool"
    echo "========================================"
    echo "1) supportXMR (pool.supportxmr.com:443) - Recommended for beginners"
    echo "2) MineXMR (pool.minexmr.com:443)"
    echo "3) Nanopool (xmr-eu1.nanopool.org:14433)"
    echo "4) Custom pool"
    echo ""
    
    while true; do
        read -p "Select pool (1-4): " POOL_CHOICE
        
        case $POOL_CHOICE in
            1)
                POOL_URL="pool.supportxmr.com:443"
                print_status "Selected supportXMR pool"
                break
                ;;
            2)
                POOL_URL="pool.minexmr.com:443"
                print_status "Selected MineXMR pool"
                break
                ;;
            3)
                POOL_URL="xmr-eu1.nanopool.org:14433"
                print_status "Selected Nanopool"
                break
                ;;
            4)
                read -p "Enter custom pool (host:port): " CUSTOM_POOL
                if [[ -n $CUSTOM_POOL ]]; then
                    POOL_URL="$CUSTOM_POOL"
                    print_status "Selected custom pool: $POOL_URL"
                    break
                else
                    print_error "Pool cannot be empty"
                fi
                ;;
            *)
                print_error "Invalid choice"
                ;;
        esac
    done
}

configure_threads() {
    echo ""
    echo "========================================"
    echo "CPU Configuration"
    echo "========================================"
    echo "Your system has $CPU_THREADS CPU threads available."
    echo ""
    
    while true; do
        read -p "How many CPU threads to use for mining? (1-$CPU_THREADS, or 'a' for all): " THREAD_INPUT
        
        if [[ "$THREAD_INPUT" == "a" ]] || [[ "$THREAD_INPUT" == "A" ]]; then
            MINER_THREADS=$CPU_THREADS
            break
        elif [[ "$THREAD_INPUT" =~ ^[0-9]+$ ]] && [ "$THREAD_INPUT" -ge 1 ] && [ "$THREAD_INPUT" -le "$CPU_THREADS" ]; then
            MINER_THREADS=$THREAD_INPUT
            break
        else
            print_error "Please enter a number between 1 and $CPU_THREADS, or 'a' for all"
        fi
    done
    
    # Reserve 1 thread for system if using all threads (unless single core)
    if [ "$MINER_THREADS" -eq "$CPU_THREADS" ] && [ "$CPU_THREADS" -gt 1 ]; then
        print_warning "Consider leaving 1 thread free for system stability. Using $((CPU_THREADS-1)) threads instead."
        read -p "Use $((CPU_THREADS-1)) threads instead? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            MINER_THREADS=$((CPU_THREADS-1))
        fi
    fi
    
    print_status "Will use $MINER_THREADS CPU threads for mining"
}

install_xmrig() {
    print_status "Creating miner directory..."
    mkdir -p "$MINER_DIR"
    cd "$MINER_DIR"
    
    print_status "Downloading XMRig..."
    
    # Get latest XMRig release from GitHub
    LATEST_RELEASE=$(curl -s https://api.github.com/repos/xmrig/xmrig/releases/latest | grep -o '"tag_name": "[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$LATEST_RELEASE" ]; then
        print_error "Failed to get latest XMRig version. Using fallback URL."
        # Fallback to direct download
        wget -q https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-linux-x64.tar.gz
        tar -xzf xmrig-6.21.0-linux-x64.tar.gz
        mv xmrig-6.21.0/* .
        rm -rf xmrig-6.21.0 xmrig-6.21.0-linux-x64.tar.gz
    else
        print_status "Latest XMRig version: $LATEST_RELEASE"
        VERSION_NUMBER=${LATEST_RELEASE#v}
        wget -q "https://github.com/xmrig/xmrig/releases/download/$LATEST_RELEASE/xmrig-$VERSION_NUMBER-linux-x64.tar.gz"
        tar -xzf "xmrig-$VERSION_NUMBER-linux-x64.tar.gz"
        mv "xmrig-$VERSION_NUMBER"/* .
        rm -rf "xmrig-$VERSION_NUMBER" "xmrig-$VERSION_NUMBER-linux-x64.tar.gz"
    fi
    
    # Verify download
    if [ -f "./xmrig" ]; then
        chmod +x ./xmrig
        print_status "XMRig downloaded successfully"
    else
        print_error "XMRig download failed"
        exit 1
    fi
}

create_config() {
    print_status "Creating mining configuration..."
    
    # Create config.json
    cat > config.json << EOF
{
    "autosave": true,
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "hw-aes": null,
        "priority": null,
        "memory-pool": false,
        "yield": true,
        "max-threads-hint": 100,
        "asm": true,
        "argon2-impl": null,
        "astrobwt-max-size": 550,
        "astrobwt-avx2": false,
        "cn/0": false,
        "cn-lite/0": false
    },
    "opencl": false,
    "cuda": false,
    "donate-level": 1,
    "donate-over-proxy": 1,
    "log-file": null,
    "pools": [
        {
            "algo": "rx/0",
            "coin": "monero",
            "url": "$POOL_URL",
            "user": "$XMR_ADDRESS",
            "pass": "x",
            "rig-id": null,
            "nicehash": false,
            "keepalive": true,
            "enabled": true,
            "tls": true,
            "tls-fingerprint": null,
            "daemon": false,
            "socks5": null,
            "self-select": null,
            "submit-to-origin": false
        }
    ],
    "print-time": 60,
    "health-print-time": 60,
    "dmi": true,
    "retries": 5,
    "retry-pause": 5,
    "syslog": false,
    "tls": {
        "enabled": true,
        "protocols": null,
        "cert": null,
        "cert_key": null,
        "ciphers": null,
        "ciphersuites": null,
        "dhparam": null
    },
    "user-agent": null,
    "verbose": 0,
    "watch": true,
    "pause-on-battery": false,
    "pause-on-active": false
}
EOF
    
    print_status "Configuration saved to $MINER_DIR/config.json"
}

create_service() {
    print_status "Creating systemd service..."
    
    # Create systemd service file
    sudo tee /etc/systemd/system/xmr-miner.service > /dev/null << EOF
[Unit]
Description=XMRig Monero Miner
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$MINER_DIR
ExecStart=$MINER_DIR/xmrig -c $MINER_DIR/config.json --threads=$MINER_THREADS
Restart=always
RestartSec=10
Nice=10
CPUSchedulingPolicy=idle
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd
    sudo systemctl daemon-reload
    
    print_status "Systemd service created"
}

start_miner() {
    echo ""
    echo "========================================"
    echo "Start Mining"
    echo "========================================"
    
    # Enable and start service
    sudo systemctl enable xmr-miner.service
    sudo systemctl start xmr-miner.service
    
    print_status "Miner started as a systemd service"
    print_status "Check status with: sudo systemctl status xmr-miner"
    print_status "View logs with: sudo journalctl -u xmr-miner -f"
    print_status "Stop mining with: sudo systemctl stop xmr-miner"
    
    # Show pool stats URL if using known pools
    if [[ "$POOL_URL" == *"supportxmr.com"* ]]; then
        echo ""
        print_status "Check your stats on supportXMR:"
        echo "https://supportxmr.com/#/dashboard/$XMR_ADDRESS"
    elif [[ "$POOL_URL" == *"minexmr.com"* ]]; then
        echo ""
        print_status "Check your stats on MineXMR:"
        echo "https://minexmr.com/dashboard?address=$XMR_ADDRESS"
    fi
}

show_manual_commands() {
    echo ""
    echo "========================================"
    echo "Manual Mining Commands"
    echo "========================================"
    echo "If you prefer to mine manually (not as service):"
    echo ""
    echo "Start mining:"
    echo "  cd $MINER_DIR"
    echo "  ./xmrig -c config.json --threads=$MINER_THREADS"
    echo ""
    echo "Or with custom command:"
    echo "  ./xmrig -o $POOL_URL -u $XMR_ADDRESS -p x --threads=$MINER_THREADS"
    echo ""
}

display_summary() {
    echo ""
    echo "========================================"
    echo "Setup Complete!"
    echo "========================================"
    echo "Miner directory: $MINER_DIR"
    echo "Monero address: ${XMR_ADDRESS:0:20}...${XMR_ADDRESS: -4}"
    echo "Mining pool: $POOL_URL"
    echo "CPU threads: $MINER_THREADS"
    echo "Systemd service: xmr-miner.service"
    echo ""
    echo "Important Commands:"
    echo "  Check status: sudo systemctl status xmr-miner"
    echo "  View logs: sudo journalctl -u xmr-miner -f"
    echo "  Stop mining: sudo systemctl stop xmr-miner"
    echo "  Start mining: sudo systemctl start xmr-miner"
    echo "  Disable auto-start: sudo systemctl disable xmr-miner"
    echo ""
    echo "Note: First payout may take several days depending on"
    echo "your hardware and the pool's minimum payout threshold."
}

main() {
    clear
    check_root
    
    print_status "Starting XMR miner setup for Debian 12"
    
    # Get user input
    get_xmr_address
    choose_pool
    configure_threads
    
    # Installation
    check_dependencies
    install_xmrig
    create_config
    
    # Ask about service setup
    echo ""
    read -p "Set up as a systemd service (runs automatically on boot)? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_service
        start_miner
    else
        print_status "Skipping systemd service setup"
        show_manual_commands
    fi
    
    display_summary
    
    echo ""
    print_warning "Remember to monitor your system's temperature!"
    print_warning "Mining increases CPU usage and power consumption."
}

# Run main function
main
