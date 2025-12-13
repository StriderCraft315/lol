#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

DAEMON_DIR="/etc/daemon"
PANEL_DIR="/var/www/panel"
LOG_FILE="/tmp/airlink-install.log"

show_ascii_art1() {
    echo -e "${CYAN}"
    echo " ______                          "
    echo " |___  /                         "
    echo "    / /_   _  ___ _ __ ___  _ __ "
    echo "   / /| | | |/ __| '__/ _ \| '_ \\"
    echo "  / /_| |_| | (__| | | (_) | | | |"
    echo " /_____\__, |\___|_|  \___/|_| |_|"
    echo "        __/ |                     "
    echo "       |___/                      "
    echo -e "${NC}"
}

show_ascii_art2() {
    echo -e "${MAGENTA}"
    echo "  __  __ _      _                _ "
    echo " |  \/  (_)    | |              | |"
    echo " | \  / |_  ___| |__   __ _  ___| |"
    echo " | |\/| | |/ __| '_ \ / _\` |/ _ \\ |"
    echo " | |  | | | (__| | | | (_| |  __/ |"
    echo " |_|  |_|_|\___|_| |_|\__,_|\___|_|"
    echo -e "${NC}"
}

show_ascii_art3() {
    echo -e "${YELLOW}"
    echo "           _      _ _       _      _____           _   _       _           "
    echo "     /\   (_)    | (_)     | |    |_   _|         | | | |     | |          "
    echo "    /  \   _ _ __| |_ _ __ | | __   | |  _ __  ___| |_| | __ _| | ___ _ __ "
    echo "   / /\ \ | | '__| | | '_ \| |/ /   | | | '_ \/ __| __| |/ _\` | |/ _ \ '__|"
    echo "  / ____ \| | |  | | | | | |   <   _| |_| | | \__ \ |_| | (_| | |  __/ |   "
    echo " /_/    \_\_|_|  |_|_|_| |_|_|\_\ |_____|_| |_|___/\__|_|\__,_|_|\___|_|   "
    echo "                                                                            "
    echo -e "${NC}"
}

show_header() {
    clear
    show_ascii_art1
    echo -e "${BLUE}==========================================================${NC}"
    echo -e "${GREEN}           Airlink Panel Installation Script           ${NC}"
    echo -e "${BLUE}==========================================================${NC}"
    echo ""
}

log_message() {
    local message=$(echo "$1" | sed 's/\\033\[[0-9;]*m//g')
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOG_FILE"
    echo -e "$1"
}

run_command() {
    local cmd="$1"
    local description="$2"
    
    log_message "${YELLOW}Running: $description${NC}"
    
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        log_message "${GREEN}Success: $description${NC}"
        return 0
    else
        log_message "${RED}Failed: $description${NC}"
        return 1
    fi
}

install_daemon() {
    log_message "${GREEN}Starting Airlink Daemon installation...${NC}"
    
    clear
    show_ascii_art1
    echo -e "${CYAN}Step 1: Cloning Daemon Repository${NC}"
    echo ""
    
    run_command "cd /etc/" "Navigate to /etc directory"
    run_command "git clone https://github.com/AirlinkLabs/daemon.git" "Clone daemon repository"
    
    if [ ! -d "$DAEMON_DIR" ]; then
        log_message "${RED}Daemon directory not found after clone!${NC}"
        return 1
    fi
    
    sleep 1
    clear
    show_ascii_art2
    echo -e "${MAGENTA}Step 2: Setting Permissions${NC}"
    echo ""
    
    run_command "sudo chown -R www-data:www-data $DAEMON_DIR" "Set ownership for daemon"
    run_command "sudo chmod -R 755 $DAEMON_DIR" "Set permissions for daemon"
    
    sleep 1
    clear
    show_ascii_art3
    echo -e "${YELLOW}Step 3: Installing Dependencies${NC}"
    echo ""
    
    run_command "cd $DAEMON_DIR" "Navigate to daemon directory"
    run_command "npm install -g typescript" "Install TypeScript globally"
    run_command "npm install" "Install npm dependencies"
    
    sleep 1
    clear
    show_ascii_art1
    echo -e "${CYAN}Step 4: Configuration${NC}"
    echo ""
    
    run_command "cp example.env .env" "Copy environment file"
    
    echo -e "${RED}REQUIRED CONFIGURATION${NC}"
    echo -e "${YELLOW}The daemon requires a configuration command to run properly.${NC}"
    echo -e "${YELLOW}Example: node configure.js --token=YOUR_TOKEN --server=YOUR_SERVER${NC}"
    echo ""
    
    while true; do
        read -p "Enter your daemon configuration command: " config_cmd
        if [ -n "$config_cmd" ]; then
            if run_command "$config_cmd" "Run daemon configuration"; then
                echo -e "${GREEN}Configuration applied successfully${NC}"
                break
            else
                echo -e "${RED}Configuration failed. Please try again.${NC}"
            fi
        else
            echo -e "${RED}Configuration command cannot be empty!${NC}"
            echo -e "${YELLOW}The daemon will fail to run without proper configuration.${NC}"
        fi
    done
    
    sleep 1
    clear
    show_ascii_art2
    echo -e "${MAGENTA}Step 5: Building Daemon${NC}"
    echo ""
    
    run_command "npm run build" "Build daemon"
    
    sleep 1
    clear
    show_ascii_art3
    echo -e "${YELLOW}Step 6: Setting up PM2${NC}"
    echo ""
    
    run_command "npm install pm2 -g" "Install PM2 globally"
    run_command "pm2 start dist/app.js --name 'node'" "Start daemon with PM2"
    run_command "pm2 save" "Save PM2 process list"
    run_command "pm2 startup" "Generate PM2 startup script"
    
    echo -e "${GREEN}Daemon installation complete!${NC}"
    sleep 2
}

install_panel() {
    log_message "${GREEN}Starting Airlink Panel installation...${NC}"
    
    clear
    show_ascii_art1
    echo -e "${CYAN}Step 1: Cloning Panel Repository${NC}"
    echo ""
    
    run_command "cd /var/www/" "Navigate to /var/www directory"
    run_command "git clone https://github.com/AirlinkLabs/panel.git" "Clone panel repository"
    
    if [ ! -d "$PANEL_DIR" ]; then
        log_message "${RED}Panel directory not found after clone!${NC}"
        return 1
    fi
    
    sleep 1
    clear
    show_ascii_art2
    echo -e "${MAGENTA}Step 2: Setting Permissions${NC}"
    echo ""
    
    run_command "sudo chown -R www-data:www-data $PANEL_DIR" "Set ownership for panel"
    run_command "sudo chmod -R 755 $PANEL_DIR" "Set permissions for panel"
    
    sleep 1
    clear
    show_ascii_art3
    echo -e "${YELLOW}Step 3: Installing Dependencies${NC}"
    echo ""
    
    run_command "cd $PANEL_DIR" "Navigate to panel directory"
    run_command "npm install -g typescript" "Install TypeScript globally"
    run_command "npm install --omit=dev" "Install npm dependencies"
    
    sleep 1
    clear
    show_ascii_art1
    echo -e "${CYAN}Step 4: Database Migration${NC}"
    echo ""
    
    run_command "npm run migrate:dev" "Run database migrations"
    
    sleep 1
    clear
    show_ascii_art2
    echo -e "${MAGENTA}Step 5: Building Panel${NC}"
    echo ""
    
    run_command "npm run build-ts" "Build TypeScript"
    
    sleep 1
    clear
    show_ascii_art3
    echo -e "${YELLOW}Step 6: Setting up PM2${NC}"
    echo ""
    
    run_command "npm install pm2 -g" "Install PM2 globally"
    run_command "pm2 start dist/app.js --name 'panel'" "Start panel with PM2"
    run_command "pm2 save" "Save PM2 process list"
    run_command "pm2 startup" "Generate PM2 startup script"
    
    echo -e "${GREEN}Panel installation complete!${NC}"
    sleep 2
}

run_uninstall() {
    log_message "${RED}Starting uninstallation process...${NC}"
    
    clear
    show_ascii_art1
    echo -e "${RED}Uninstalling Airlink Panel and Daemon${NC}"
    echo ""
    
    echo -e "${YELLOW}Step 1: Stopping PM2 processes${NC}"
    run_command "pm2 stop node panel" "Stop PM2 processes"
    run_command "pm2 delete node panel" "Delete PM2 processes"
    
    sleep 1
    clear
    show_ascii_art2
    echo -e "${YELLOW}Step 2: Removing installation directories${NC}"
    
    if [ -d "$DAEMON_DIR" ]; then
        run_command "rm -rf $DAEMON_DIR" "Remove daemon directory"
        echo -e "${GREEN}Removed daemon directory${NC}"
    else
        echo -e "${YELLOW}Daemon directory not found${NC}"
    fi
    
    if [ -d "$PANEL_DIR" ]; then
        run_command "rm -rf $PANEL_DIR" "Remove panel directory"
        echo -e "${GREEN}Removed panel directory${NC}"
    else
        echo -e "${YELLOW}Panel directory not found${NC}"
    fi
    
    sleep 1
    clear
    show_ascii_art3
    echo -e "${YELLOW}Step 3: Cleaning up PM2${NC}"
    
    run_command "pm2 save" "Save PM2 configuration"
    run_command "pm2 kill" "Kill PM2 daemon"
    
    echo -e "${GREEN}Uninstallation complete!${NC}"
    sleep 2
}

run_installation() {
    log_message "${GREEN}Starting complete Airlink installation...${NC}"
    
    echo -e "${BLUE}This will install both Daemon and Panel${NC}"
    echo ""
    
    if install_daemon; then
        echo -e "${GREEN}Daemon installed successfully${NC}"
    else
        echo -e "${RED}Daemon installation failed${NC}"
        read -p "Continue with Panel installation? (y/N): " continue_choice
        if [[ ! $continue_choice =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    echo ""
    echo -e "${BLUE}Now installing Panel...${NC}"
    echo ""
    
    if install_panel; then
        echo -e "${GREEN}Panel installed successfully${NC}"
    else
        echo -e "${RED}Panel installation failed${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Installation Summary:${NC}"
    echo ""
    
    if [ -d "$DAEMON_DIR" ]; then
        echo -e "${GREEN}Daemon: Installed at $DAEMON_DIR${NC}"
    else
        echo -e "${RED}Daemon: Not installed${NC}"
    fi
    
    if [ -d "$PANEL_DIR" ]; then
        echo -e "${GREEN}Panel: Installed at $PANEL_DIR${NC}"
    else
        echo -e "${RED}Panel: Not installed${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Check log file: $LOG_FILE${NC}"
    read -p "Press Enter to continue..."
}

show_status() {
    log_message "${BLUE}Checking Airlink Panel status...${NC}"
    
    clear
    show_ascii_art1
    echo -e "${CYAN}Airlink Status Check${NC}"
    echo ""
    
    if [ -d "$DAEMON_DIR" ]; then
        echo -e "${GREEN}Daemon directory: $DAEMON_DIR${NC}"
    else
        echo -e "${RED}Daemon directory: Not found${NC}"
    fi
    
    if [ -d "$PANEL_DIR" ]; then
        echo -e "${GREEN}Panel directory: $PANEL_DIR${NC}"
    else
        echo -e "${RED}Panel directory: Not found${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}PM2 Processes:${NC}"
    if command -v pm2 &> /dev/null; then
        pm2 list
    else
        echo "PM2 not installed"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

show_main_menu() {
    while true; do
        show_header
        echo -e "${GREEN}Main Menu:${NC}"
        echo ""
        echo "1) Install Airlink (Daemon + Panel)"
        echo "2) Install Daemon Only"
        echo "3) Install Panel Only"
        echo "4) Uninstall"
        echo "5) Show Current Status"
        echo "0) Exit"
        echo ""
        echo -e "${BLUE}==========================================================${NC}"
        echo ""
        
        read -p "Please choose an option (0-5): " choice
        
        case $choice in
            1)
                run_installation
                ;;
            2)
                install_daemon
                ;;
            3)
                install_panel
                ;;
            4)
                show_header
                echo -e "${RED}WARNING: Uninstallation${NC}"
                echo ""
                echo -e "${YELLOW}This will remove Airlink from your system.${NC}"
                echo ""
                read -p "Are you sure? (y/N): " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    run_uninstall
                else
                    echo -e "${GREEN}Uninstallation cancelled.${NC}"
                    sleep 1
                fi
                ;;
            5)
                show_status
                ;;
            0)
                echo ""
                echo -e "${GREEN}Exiting... Thank you for using Airlink Panel!${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                sleep 2
                ;;
        esac
    done
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root (sudo).${NC}"
        echo -e "${YELLOW}Please run: sudo $0${NC}"
        exit 1
    fi
}

welcome_message() {
    clear
    show_ascii_art1
    echo -e "${BLUE}==========================================================${NC}"
    echo -e "${GREEN}        Welcome to Airlink Panel Installer!           ${NC}"
    echo -e "${BLUE}==========================================================${NC}"
    echo ""
    echo -e "${CYAN}This script will install and configure Airlink Panel and Daemon${NC}"
    echo ""
    echo -e "${YELLOW}System Information:${NC}"
    echo "OS: $(uname -s)"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "User: $(whoami)"
    echo ""
    echo -e "${BLUE}==========================================================${NC}"
    echo ""
    read -p "Press Enter to continue to the main menu..."
}

main() {
    check_root
    welcome_message
    show_main_menu
}

trap 'echo -e "\n${RED}Operation interrupted.${NC}"; exit 1' INT

main
