#!/bin/bash

#===============================================================================
#
#                  ____  _   _______    ________            __  
#                 / __ \/ | / / ___/   / ____/ /___  ____ _/ /__
#                / / / /  |/ /\__ \   / /   / / __ \/ __ `/ //_/
#               / /_/ / /|  /___/ /  / /___/ / /_/ / /_/ / ,<   
#              /_____/_/ |_//____/   \____/_/\____/\__,_/_/|_| 
#                           PROXY SETUP SCRIPT
#
#   MTProto Proxy with Fake-TLS Support
#   https://github.com/behnamkhorsandian/DNSCloak
#   https://dnscloak.net
#
#===============================================================================

# Note: Not using 'set -e' to allow interactive reads to work when piped

# ============== COLORS ==============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
RESET='\033[0m'
BOLD='\033[1m'

# ============== GLOBAL VARS ==============
SCRIPT_VERSION="1.1.0"
INSTALL_DIR="/opt/telegram-proxy"
CONFIG_FILE="$INSTALL_DIR/config.py"
SERVICE_NAME="telegram-proxy"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
DATA_FILE="$INSTALL_DIR/proxy_data.sh"

# Proxy modes
MODE_TLS="tls"          # Fake-TLS (ee prefix) - traffic looks like HTTPS
MODE_SECURE="secure"    # Random padding (dd prefix) - harder to detect

# ============== HELPER FUNCTIONS ==============

print_banner() {
    clear
    echo -e "${CYAN}"
    echo '  ╔══════════════════════════════════════════════════════════╗'
    echo '  ║         ____  _   _______    ________            __      ║'
    echo '  ║        / __ \/ | / / ___/   / ____/ /___  ____ _/ /__    ║'
    echo '  ║       / / / /  |/ /\__ \   / /   / / __ \/ __ `/ //_/    ║'
    echo '  ║      / /_/ / /|  /___/ /  / /___/ / /_/ / /_/ / ,<       ║'
    echo '  ║     /_____/_/ |_//____/   \____/_/\____/\__,_/_/|_|      ║'
    echo '  ║                                                          ║'
    echo '  ╚══════════════════════════════════════════════════════════╝'
    echo -e "${RESET}"
    echo -e "  ${GRAY}Version: ${WHITE}$SCRIPT_VERSION${GRAY} | MTProto Proxy with Fake-TLS${RESET}"
    echo ""
}

print_line() {
    echo -e "${CYAN}  ════════════════════════════════════════════════════════════${RESET}"
}

print_success() {
    echo -e "  ${GREEN}✓${RESET} $1"
}

print_error() {
    echo -e "  ${RED}✗${RESET} $1"
}

print_warning() {
    echo -e "  ${YELLOW}!${RESET} $1"
}

print_info() {
    echo -e "  ${BLUE}ℹ${RESET} $1"
}

print_step() {
    echo -e "\n  ${MAGENTA}▶${RESET} ${BOLD}$1${RESET}"
}

press_enter() {
    echo ""
    echo -e -n "  ${GRAY}Press Enter to continue...${RESET}"
    read </dev/tty
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    echo -e -n "  ${YELLOW}?${RESET} $prompt"
    read answer </dev/tty
    
    if [[ -z "$answer" ]]; then
        answer="$default"
    fi
    
    [[ "$answer" =~ ^[Yy]$ ]]
}

get_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [[ -n "$default" ]]; then
        echo -e -n "  ${CYAN}→${RESET} $prompt ${GRAY}[$default]${RESET}: "
    else
        echo -e -n "  ${CYAN}→${RESET} $prompt: "
    fi
    
    read input </dev/tty
    
    if [[ -z "$input" && -n "$default" ]]; then
        input="$default"
    fi
    
    eval "$var_name='$input'"
}

# ============== SYSTEM CHECKS ==============

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            print_error "This script only supports Ubuntu and Debian"
            print_info "Detected: $PRETTY_NAME"
            exit 1
        fi
    else
        print_error "Cannot detect OS. /etc/os-release not found"
        exit 1
    fi
}

get_public_ip() {
    local ip=""
    # Try multiple services
    ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null) || \
    ip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null) || \
    ip=$(curl -s --max-time 5 https://icanhazip.com 2>/dev/null) || \
    ip=$(curl -s --max-time 5 https://ipecho.net/plain 2>/dev/null)
    
    echo "$ip"
}

check_port_available() {
    local port=$1
    if ss -tlnp | grep -q ":${port} "; then
        return 1
    fi
    return 0
}

# ============== PORT & FIREWALL ANALYSIS ==============

# Get list of open ports with details
get_open_ports_info() {
    echo ""
    echo -e "  ${BOLD}${WHITE}📡 OPEN PORTS ANALYSIS${RESET}"
    print_line
    echo ""
    
    # Get all listening TCP ports
    echo -e "  ${BOLD}${CYAN}Listening TCP Ports:${RESET}"
    echo ""
    
    local port_list=$(ss -tlnp 2>/dev/null | grep LISTEN | awk '{print $4}' | sed 's/.*://' | sort -n | uniq)
    
    if [[ -z "$port_list" ]]; then
        echo -e "  ${GRAY}No listening ports found${RESET}"
    else
        printf "  ${WHITE}%-10s %-20s %-30s${RESET}\n" "PORT" "PROCESS" "DETAILS"
        echo -e "  ${GRAY}─────────────────────────────────────────────────────────${RESET}"
        
        while read -r port; do
            if [[ -n "$port" && "$port" =~ ^[0-9]+$ ]]; then
                local ss_line=$(ss -tlnp 2>/dev/null | grep ":${port} " | head -1)
                local process_info=$(echo "$ss_line" | grep -oP 'users:\(\("\K[^"]+' 2>/dev/null || echo "unknown")
                local pid=$(echo "$ss_line" | grep -oP 'pid=\K[0-9]+' 2>/dev/null | head -1)
                
                local details=""
                if [[ -n "$pid" ]]; then
                    details="PID: $pid"
                fi
                
                # Highlight common ports
                local port_color="${WHITE}"
                case $port in
                    22) details="SSH"; port_color="${GREEN}" ;;
                    80) details="HTTP"; port_color="${CYAN}" ;;
                    443) details="HTTPS/TLS"; port_color="${CYAN}" ;;
                    3306) details="MySQL"; port_color="${YELLOW}" ;;
                    5432) details="PostgreSQL"; port_color="${YELLOW}" ;;
                    6379) details="Redis"; port_color="${YELLOW}" ;;
                    8080|8443) details="Alt HTTP/HTTPS"; port_color="${CYAN}" ;;
                esac
                
                # Check if it's our proxy
                if echo "$ss_line" | grep -q "telegram-proxy\|mtprotoproxy\|python3"; then
                    if [[ -f "$CONFIG_FILE" ]] && grep -q "PORT = $port" "$CONFIG_FILE" 2>/dev/null; then
                        process_info="telegram-proxy"
                        details="${details:+$details | }${GREEN}DNSCloak Proxy${RESET}"
                        port_color="${GREEN}"
                    fi
                fi
                
                printf "  ${port_color}%-10s${RESET} %-20s %-30b\n" "$port" "$process_info" "$details"
            fi
        done <<< "$port_list"
    fi
    
    echo ""
}

# Check firewall status
check_firewall_status() {
    echo -e "  ${BOLD}${CYAN}Firewall Status:${RESET}"
    echo ""
    
    local firewall_found=false
    
    # Check UFW (Ubuntu Firewall)
    if command -v ufw &> /dev/null; then
        firewall_found=true
        local ufw_status=$(sudo ufw status 2>/dev/null | head -1)
        if echo "$ufw_status" | grep -qi "active"; then
            echo -e "  ${YELLOW}●${RESET} UFW: ${GREEN}Active${RESET}"
            echo ""
            echo -e "  ${WHITE}UFW Rules:${RESET}"
            sudo ufw status numbered 2>/dev/null | head -15 | sed 's/^/    /'
        else
            echo -e "  ${GRAY}●${RESET} UFW: ${GRAY}Inactive${RESET}"
        fi
        echo ""
    fi
    
    # Check iptables
    if command -v iptables &> /dev/null; then
        firewall_found=true
        local iptables_rules=$(sudo iptables -L INPUT -n 2>/dev/null | grep -c "ACCEPT\|DROP\|REJECT" || echo "0")
        if [[ "$iptables_rules" -gt 2 ]]; then
            echo -e "  ${YELLOW}●${RESET} iptables: ${GREEN}Rules configured${RESET} ($iptables_rules rules)"
        else
            echo -e "  ${GRAY}●${RESET} iptables: ${GRAY}Default/minimal rules${RESET}"
        fi
        echo ""
    fi
    
    # Check firewalld (CentOS/RHEL style)
    if command -v firewall-cmd &> /dev/null; then
        firewall_found=true
        if systemctl is-active --quiet firewalld 2>/dev/null; then
            echo -e "  ${YELLOW}●${RESET} firewalld: ${GREEN}Active${RESET}"
            echo ""
            echo -e "  ${WHITE}Open ports:${RESET}"
            sudo firewall-cmd --list-ports 2>/dev/null | sed 's/^/    /'
        else
            echo -e "  ${GRAY}●${RESET} firewalld: ${GRAY}Inactive${RESET}"
        fi
        echo ""
    fi
    
    # Check nftables
    if command -v nft &> /dev/null; then
        local nft_rules=$(sudo nft list ruleset 2>/dev/null | grep -c "accept\|drop\|reject" || echo "0")
        if [[ "$nft_rules" -gt 0 ]]; then
            firewall_found=true
            echo -e "  ${YELLOW}●${RESET} nftables: ${GREEN}Rules configured${RESET} ($nft_rules rules)"
            echo ""
        fi
    fi
    
    if ! $firewall_found; then
        echo -e "  ${GRAY}No local firewall detected${RESET}"
        echo ""
    fi
    
    # Cloud provider note
    echo -e "  ${YELLOW}⚠️  Note:${RESET} Cloud providers (AWS, GCP, Azure, etc.) have their own firewalls"
    echo -e "     that must be configured separately from the VM's firewall."
    echo ""
}

# Check if a specific port is likely accessible
check_port_accessibility() {
    local port=$1
    
    echo -e "  ${BOLD}${CYAN}Port $port Accessibility:${RESET}"
    echo ""
    
    # Check if port is in use
    if check_port_available "$port"; then
        echo -e "  ${GRAY}●${RESET} Port status: ${GRAY}Not in use${RESET}"
    else
        local usage_info=$(get_port_usage_info "$port")
        echo -e "  ${GREEN}●${RESET} Port status: ${GREEN}In use${RESET} by $usage_info"
    fi
    
    # Check UFW rules for this port
    if command -v ufw &> /dev/null; then
        if sudo ufw status 2>/dev/null | grep -q "^$port"; then
            echo -e "  ${GREEN}●${RESET} UFW: ${GREEN}Port allowed${RESET}"
        elif sudo ufw status 2>/dev/null | grep -qi "active"; then
            echo -e "  ${RED}●${RESET} UFW: ${RED}Port not explicitly allowed${RESET}"
        fi
    fi
    
    # Check iptables for this port
    if command -v iptables &> /dev/null; then
        if sudo iptables -L INPUT -n 2>/dev/null | grep -q "dpt:$port"; then
            if sudo iptables -L INPUT -n 2>/dev/null | grep "dpt:$port" | grep -qi "ACCEPT"; then
                echo -e "  ${GREEN}●${RESET} iptables: ${GREEN}Port allowed${RESET}"
            else
                echo -e "  ${RED}●${RESET} iptables: ${RED}Port may be blocked${RESET}"
            fi
        fi
    fi
    
    echo ""
}

# Show comprehensive port analysis during installation
show_port_analysis() {
    print_banner
    echo -e "  ${BOLD}${WHITE}🔍 PORT & FIREWALL ANALYSIS${RESET}"
    print_line
    
    get_open_ports_info
    print_line
    echo ""
    check_firewall_status
    print_line
    echo ""
    
    press_enter
}

# Get detailed information about what's using a port
get_port_usage_info() {
    local port=$1
    local info=""
    
    # Get process info using ss
    local ss_output=$(ss -tlnp 2>/dev/null | grep ":${port} " | head -1)
    
    if [[ -n "$ss_output" ]]; then
        # Extract PID and process name
        local pid=$(echo "$ss_output" | grep -oP 'pid=\K[0-9]+' | head -1)
        local process_name=$(echo "$ss_output" | grep -oP 'users:\(\("\K[^"]+' | head -1)
        
        if [[ -z "$process_name" && -n "$pid" ]]; then
            process_name=$(ps -p "$pid" -o comm= 2>/dev/null)
        fi
        
        if [[ -n "$pid" ]]; then
            info="PID: $pid"
            if [[ -n "$process_name" ]]; then
                info="$process_name ($info)"
            fi
        fi
    fi
    
    echo "$info"
}

# Check if port is used by our own telegram-proxy service
is_port_used_by_telegram_proxy() {
    local port=$1
    local ss_output=$(ss -tlnp 2>/dev/null | grep ":${port} ")
    
    if echo "$ss_output" | grep -q "telegram-proxy\|mtprotoproxy"; then
        return 0
    fi
    
    # Also check if our service is configured for this port
    if [[ -f "$CONFIG_FILE" ]] && grep -q "PORT = $port" "$CONFIG_FILE" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Stop and clean up our existing telegram-proxy service
cleanup_existing_proxy() {
    print_info "Stopping existing Telegram Proxy service..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    sleep 1
    print_success "Existing service stopped"
}

# Handle port conflict with smart options
handle_port_conflict() {
    local port=$1
    local usage_info=$(get_port_usage_info "$port")
    local pid=$(ss -tlnp 2>/dev/null | grep ":${port} " | grep -oP 'pid=\K[0-9]+' | head -1)
    
    echo ""
    print_warning "Port $port is already in use!"
    echo ""
    
    # Check if it's our own service
    if is_port_used_by_telegram_proxy "$port"; then
        echo -e "  ${CYAN}ℹ${RESET}  Used by: ${WHITE}DNSCloak/Telegram Proxy (previous installation)${RESET}"
        if [[ -n "$pid" ]]; then
            echo -e "  ${CYAN}ℹ${RESET}  PID: ${WHITE}$pid${RESET}"
        fi
        echo ""
        echo -e "  ${BOLD}Options:${RESET}"
        echo -e "  ${CYAN}1)${RESET} Replace existing installation ${GREEN}(recommended)${RESET}"
        echo -e "  ${CYAN}2)${RESET} Use a different port"
        echo -e "  ${CYAN}3)${RESET} Cancel installation"
        echo ""
        
        get_input "Select option" "1" conflict_choice
        
        case $conflict_choice in
            1)
                cleanup_existing_proxy
                # Also kill by PID if still running
                if [[ -n "$pid" ]] && ! check_port_available "$port"; then
                    print_info "Killing process $pid..."
                    kill -9 "$pid" 2>/dev/null || true
                    sleep 1
                fi
                if check_port_available "$port"; then
                    print_success "Port $port is now available"
                    return 0
                else
                    print_error "Could not free up port $port"
                    return 1
                fi
                ;;
            2)
                return 1  # Signal to ask for new port
                ;;
            *)
                return 2  # Cancel
                ;;
        esac
    else
        # Port used by something else
        if [[ -n "$usage_info" ]]; then
            echo -e "  ${CYAN}ℹ${RESET}  Used by: ${WHITE}$usage_info${RESET}"
        else
            echo -e "  ${CYAN}ℹ${RESET}  Used by: ${WHITE}Unknown process${RESET}"
        fi
        if [[ -n "$pid" ]]; then
            echo -e "  ${CYAN}ℹ${RESET}  PID: ${WHITE}$pid${RESET}"
        fi
        echo ""
        echo -e "  ${BOLD}Options:${RESET}"
        echo -e "  ${CYAN}1)${RESET} Use a different port ${GREEN}(recommended)${RESET}"
        if [[ -n "$pid" ]]; then
            echo -e "  ${CYAN}2)${RESET} Kill process (PID: $pid) and use this port"
        else
            echo -e "  ${CYAN}2)${RESET} Try to stop the service and use this port"
        fi
        echo -e "  ${CYAN}3)${RESET} Cancel installation"
        echo ""
        
        get_input "Select option" "1" conflict_choice
        
        case $conflict_choice in
            1)
                return 1  # Signal to ask for new port
                ;;
            2)
                if [[ -n "$pid" ]]; then
                    echo ""
                    echo -e "  ${YELLOW}⚠️  Warning:${RESET} This will kill the process using port $port"
                    echo -e "  ${GRAY}Process: $usage_info${RESET}"
                    echo ""
                    if confirm "Kill process $pid and use port $port?" "n"; then
                        print_info "Killing process $pid..."
                        kill -9 "$pid" 2>/dev/null || true
                        sleep 2
                        
                        if check_port_available "$port"; then
                            print_success "Port $port is now available"
                            return 0
                        else
                            print_error "Could not free up port $port"
                            print_info "The process may have respawned. Try stopping its service first."
                            return 1
                        fi
                    else
                        return 1  # Ask for different port
                    fi
                else
                    print_error "Could not identify the process PID"
                    return 1
                fi
                ;;
            *)
                return 2  # Cancel
                ;;
        esac
    fi
}

# Suggest alternative ports
suggest_alternative_port() {
    local preferred_ports=(443 8443 2053 8080 8880 2083 2087 2096)
    
    for port in "${preferred_ports[@]}"; do
        if check_port_available "$port"; then
            echo "$port"
            return
        fi
    done
    
    # Find any available port in common range
    for port in {1024..65535}; do
        if check_port_available "$port"; then
            echo "$port"
            return
        fi
    done
    
    echo "443"  # Fallback
}

is_installed() {
    [[ -f "$SERVICE_FILE" ]] && [[ -d "$INSTALL_DIR" ]]
}

# Check for orphaned/stale installations that may not have been cleaned up properly
check_stale_installation() {
    local stale=false
    local issues=()
    
    # Check if service file exists but service is not running
    if [[ -f "$SERVICE_FILE" ]]; then
        if ! systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            if ! systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
                stale=true
                issues+=("Orphaned service file found")
            fi
        fi
    fi
    
    # Check if install dir exists but service doesn't
    if [[ -d "$INSTALL_DIR" ]] && [[ ! -f "$SERVICE_FILE" ]]; then
        stale=true
        issues+=("Orphaned installation directory found")
    fi
    
    if $stale && [[ ${#issues[@]} -gt 0 ]]; then
        echo ""
        print_warning "Detected incomplete previous installation:"
        for issue in "${issues[@]}"; do
            echo -e "    ${GRAY}• $issue${RESET}"
        done
        echo ""
        
        if confirm "Clean up stale installation files?" "y"; then
            cleanup_stale_installation
            print_success "Cleanup completed"
        fi
        echo ""
    fi
}

# Clean up any stale installation artifacts
cleanup_stale_installation() {
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "$SERVICE_FILE" 2>/dev/null || true
    rm -rf "$INSTALL_DIR" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
}

# ============== INSTALLATION ==============

install_dependencies() {
    print_step "Installing dependencies..."
    
    apt-get update -qq
    apt-get install -y -qq python3 python3-pip git curl wget > /dev/null 2>&1
    
    print_success "Dependencies installed"
}

clone_mtprotoproxy() {
    print_step "Downloading MTProto Proxy..."
    
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
    fi
    
    git clone -q https://github.com/alexbers/mtprotoproxy.git "$INSTALL_DIR"
    
    print_success "MTProto Proxy downloaded"
}

generate_secret() {
    head -c 16 /dev/urandom | xxd -p | tr -d '\n'
}

create_config() {
    local port=$1
    local tls_domain=$2
    local proxy_mode=$3
    local random_padding=$4
    shift 4
    local users=("$@")
    
    print_step "Creating configuration..."
    
    # Determine modes based on selection
    local mode_classic="False"
    local mode_secure="False"
    local mode_tls="False"
    
    if [[ "$proxy_mode" == "tls" ]]; then
        mode_tls="True"
        # If random padding enabled with TLS, also enable secure mode
        if [[ "$random_padding" == "yes" ]]; then
            mode_secure="True"
        fi
    elif [[ "$proxy_mode" == "secure" ]]; then
        mode_secure="True"
    fi
    
    cat > "$CONFIG_FILE" << EOF
# MTProto Proxy Configuration
# Generated by DNSCloak Setup Script v${SCRIPT_VERSION}

PORT = $port

USERS = {
EOF

    # Add users (secrets are stored without prefix in config)
    for user in "${users[@]}"; do
        IFS=':' read -r name secret mode <<< "$user"
        # Remove any prefix (ee/dd) from secret for config file
        local clean_secret="${secret#ee}"
        clean_secret="${clean_secret#dd}"
        # Ensure it's 32 chars
        clean_secret="${clean_secret:0:32}"
        echo "    \"$name\": \"$clean_secret\"," >> "$CONFIG_FILE"
    done

    cat >> "$CONFIG_FILE" << EOF
}

# Proxy Modes
MODES = {
    # Classic mode, easy to detect
    "classic": $mode_classic,

    # Secure mode with random padding (dd prefix)
    # Makes the proxy harder to detect
    "secure": $mode_secure,

    # Fake-TLS mode (ee prefix)
    # Makes the proxy even harder to detect
    # Traffic looks like HTTPS to the TLS_DOMAIN
    "tls": $mode_tls
}

# The domain for TLS mode - traffic will look like HTTPS to this site
# Bad clients are proxied there, so use a real website
TLS_DOMAIN = "$tls_domain"

# Performance settings
PREFER_IPV6 = False
FAST_MODE = True
EOF

    print_success "Configuration created"
}

create_service() {
    print_step "Creating systemd service..."
    
    tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Telegram MTProto Proxy (Fake-TLS)
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/mtprotoproxy.py
Restart=always
RestartSec=5
User=root
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" > /dev/null 2>&1
    
    print_success "Service created and enabled"
}

save_proxy_data() {
    local public_ip=$1
    local domain=$2
    local port=$3
    local proxy_mode=$4
    local tls_domain=$5
    local random_padding=$6
    shift 6
    local users=("$@")
    
    cat > "$DATA_FILE" << EOF
# Proxy Data - Do not edit manually
PROXY_IP="$public_ip"
PROXY_DOMAIN="$domain"
PROXY_PORT="$port"
PROXY_MODE="$proxy_mode"
TLS_DOMAIN="$tls_domain"
RANDOM_PADDING="$random_padding"
PROXY_USERS=(
EOF

    for user in "${users[@]}"; do
        echo "    \"$user\"" >> "$DATA_FILE"
    done

    echo ")" >> "$DATA_FILE"
}

start_service() {
    print_step "Starting proxy service..."
    
    systemctl start "$SERVICE_NAME"
    sleep 2
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "Proxy is running!"
        return 0
    else
        print_error "Failed to start proxy"
        echo ""
        journalctl -u "$SERVICE_NAME" -n 10 --no-pager
        return 1
    fi
}

# ============== FIREWALL INSTRUCTIONS ==============

show_firewall_instructions() {
    local port=$1
    
    print_banner
    echo -e "  ${BOLD}${WHITE}🔥 FIREWALL CONFIGURATION${RESET}"
    print_line
    echo ""
    echo -e "  ${YELLOW}You MUST open port ${WHITE}$port${YELLOW} on your cloud provider's firewall.${RESET}"
    echo ""
    echo -e "  ${BOLD}Choose your cloud provider:${RESET}"
    echo ""
    echo -e "  ${CYAN}1)${RESET} Google Cloud Platform (GCP)"
    echo -e "  ${CYAN}2)${RESET} Amazon Web Services (AWS)"
    echo -e "  ${CYAN}3)${RESET} DigitalOcean"
    echo -e "  ${CYAN}4)${RESET} Vultr"
    echo -e "  ${CYAN}5)${RESET} Linode / Akamai"
    echo -e "  ${CYAN}6)${RESET} Hetzner"
    echo -e "  ${CYAN}7)${RESET} Azure"
    echo -e "  ${CYAN}8)${RESET} Oracle Cloud"
    echo -e "  ${CYAN}9)${RESET} Other / I'll figure it out"
    echo ""
    
    get_input "Select provider" "9" provider_choice
    
    print_banner
    echo -e "  ${BOLD}${WHITE}🔥 FIREWALL INSTRUCTIONS${RESET}"
    print_line
    echo ""
    
    case $provider_choice in
        1) # GCP
            echo -e "  ${BOLD}${CYAN}Google Cloud Platform:${RESET}"
            echo ""
            echo -e "  ${WHITE}1.${RESET} Go to: ${BLUE}https://console.cloud.google.com/networking/firewalls${RESET}"
            echo -e "  ${WHITE}2.${RESET} Click ${GREEN}\"CREATE FIREWALL RULE\"${RESET}"
            echo -e "  ${WHITE}3.${RESET} Configure:"
            echo -e "      • Name: ${WHITE}allow-telegram-proxy${RESET}"
            echo -e "      • Direction: ${WHITE}Ingress${RESET}"
            echo -e "      • Targets: ${WHITE}All instances in the network${RESET}"
            echo -e "      • Source IP ranges: ${WHITE}0.0.0.0/0${RESET}"
            echo -e "      • Protocols and ports: ${WHITE}TCP: $port${RESET}"
            echo -e "  ${WHITE}4.${RESET} Click ${GREEN}\"CREATE\"${RESET}"
            ;;
        2) # AWS
            echo -e "  ${BOLD}${CYAN}Amazon Web Services (AWS):${RESET}"
            echo ""
            echo -e "  ${WHITE}1.${RESET} Go to: ${BLUE}EC2 Dashboard → Security Groups${RESET}"
            echo -e "  ${WHITE}2.${RESET} Select your instance's security group"
            echo -e "  ${WHITE}3.${RESET} Click ${GREEN}\"Edit inbound rules\"${RESET}"
            echo -e "  ${WHITE}4.${RESET} Add rule:"
            echo -e "      • Type: ${WHITE}Custom TCP${RESET}"
            echo -e "      • Port range: ${WHITE}$port${RESET}"
            echo -e "      • Source: ${WHITE}0.0.0.0/0${RESET} (Anywhere IPv4)"
            echo -e "  ${WHITE}5.${RESET} Click ${GREEN}\"Save rules\"${RESET}"
            ;;
        3) # DigitalOcean
            echo -e "  ${BOLD}${CYAN}DigitalOcean:${RESET}"
            echo ""
            echo -e "  ${WHITE}Option A - Cloud Firewall (Recommended):${RESET}"
            echo -e "  ${WHITE}1.${RESET} Go to: ${BLUE}Networking → Firewalls${RESET}"
            echo -e "  ${WHITE}2.${RESET} Create or edit firewall"
            echo -e "  ${WHITE}3.${RESET} Add inbound rule: ${WHITE}TCP port $port from All IPv4${RESET}"
            echo -e "  ${WHITE}4.${RESET} Apply to your droplet"
            echo ""
            echo -e "  ${WHITE}Option B - No firewall by default:${RESET}"
            echo -e "  If you haven't set up a firewall, ports are open by default."
            ;;
        4) # Vultr
            echo -e "  ${BOLD}${CYAN}Vultr:${RESET}"
            echo ""
            echo -e "  ${WHITE}1.${RESET} Go to: ${BLUE}Products → Firewall${RESET}"
            echo -e "  ${WHITE}2.${RESET} Create or select firewall group"
            echo -e "  ${WHITE}3.${RESET} Add rule:"
            echo -e "      • Protocol: ${WHITE}TCP${RESET}"
            echo -e "      • Port: ${WHITE}$port${RESET}"
            echo -e "      • Source: ${WHITE}anywhere${RESET}"
            echo -e "  ${WHITE}4.${RESET} Link firewall to your instance"
            ;;
        5) # Linode
            echo -e "  ${BOLD}${CYAN}Linode / Akamai:${RESET}"
            echo ""
            echo -e "  ${WHITE}1.${RESET} Go to: ${BLUE}Linodes → Your Linode → Network${RESET}"
            echo -e "  ${WHITE}2.${RESET} Click on ${GREEN}\"Firewall\"${RESET} tab"
            echo -e "  ${WHITE}3.${RESET} Add inbound rule:"
            echo -e "      • Type: ${WHITE}Custom${RESET}"
            echo -e "      • Protocol: ${WHITE}TCP${RESET}"
            echo -e "      • Port: ${WHITE}$port${RESET}"
            echo -e "      • Sources: ${WHITE}All IPv4${RESET}"
            ;;
        6) # Hetzner
            echo -e "  ${BOLD}${CYAN}Hetzner:${RESET}"
            echo ""
            echo -e "  ${WHITE}1.${RESET} Go to: ${BLUE}Cloud Console → Firewalls${RESET}"
            echo -e "  ${WHITE}2.${RESET} Create or edit firewall"
            echo -e "  ${WHITE}3.${RESET} Add inbound rule:"
            echo -e "      • Protocol: ${WHITE}TCP${RESET}"
            echo -e "      • Port: ${WHITE}$port${RESET}"
            echo -e "      • Source IPs: ${WHITE}Any${RESET}"
            echo -e "  ${WHITE}4.${RESET} Apply to your server"
            ;;
        7) # Azure
            echo -e "  ${BOLD}${CYAN}Microsoft Azure:${RESET}"
            echo ""
            echo -e "  ${WHITE}1.${RESET} Go to: ${BLUE}Virtual Machines → Your VM → Networking${RESET}"
            echo -e "  ${WHITE}2.${RESET} Click ${GREEN}\"Add inbound port rule\"${RESET}"
            echo -e "  ${WHITE}3.${RESET} Configure:"
            echo -e "      • Destination port ranges: ${WHITE}$port${RESET}"
            echo -e "      • Protocol: ${WHITE}TCP${RESET}"
            echo -e "      • Action: ${WHITE}Allow${RESET}"
            echo -e "      • Name: ${WHITE}Allow-Telegram-Proxy${RESET}"
            echo -e "  ${WHITE}4.${RESET} Click ${GREEN}\"Add\"${RESET}"
            ;;
        8) # Oracle
            echo -e "  ${BOLD}${CYAN}Oracle Cloud:${RESET}"
            echo ""
            echo -e "  ${WHITE}1.${RESET} Go to: ${BLUE}Networking → Virtual Cloud Networks${RESET}"
            echo -e "  ${WHITE}2.${RESET} Select your VCN → Security Lists"
            echo -e "  ${WHITE}3.${RESET} Add ingress rule:"
            echo -e "      • Source CIDR: ${WHITE}0.0.0.0/0${RESET}"
            echo -e "      • Protocol: ${WHITE}TCP${RESET}"
            echo -e "      • Destination Port: ${WHITE}$port${RESET}"
            echo ""
            echo -e "  ${YELLOW}Also check iptables on the VM:${RESET}"
            echo -e "  ${WHITE}sudo iptables -I INPUT -p tcp --dport $port -j ACCEPT${RESET}"
            ;;
        *)
            echo -e "  ${BOLD}${CYAN}Generic Instructions:${RESET}"
            echo ""
            echo -e "  You need to allow inbound TCP traffic on port ${WHITE}$port${RESET}"
            echo ""
            echo -e "  Look for:"
            echo -e "  • Security Groups"
            echo -e "  • Firewall Rules"
            echo -e "  • Network Security"
            echo -e "  • Access Control Lists"
            echo ""
            echo -e "  Allow: ${WHITE}TCP port $port from 0.0.0.0/0 (anywhere)${RESET}"
            ;;
    esac
    
    echo ""
    print_line
    echo ""
    echo -e "  ${YELLOW}⚠️  The proxy will NOT work until you complete this step!${RESET}"
    
    press_enter
}

# ============== DNS INSTRUCTIONS ==============

show_dns_instructions() {
    local ip=$1
    local domain=$2
    
    if [[ -z "$domain" || "$domain" == "none" ]]; then
        return
    fi
    
    print_banner
    echo -e "  ${BOLD}${WHITE}🌐 DNS CONFIGURATION${RESET}"
    print_line
    echo ""
    echo -e "  ${WHITE}Configure DNS to point your domain to your server.${RESET}"
    echo ""
    echo -e "  ${BOLD}Add this DNS record:${RESET}"
    echo ""
    echo -e "  ┌─────────────────────────────────────────────────────────┐"
    echo -e "  │  Type: ${GREEN}A${RESET}                                               │"
    echo -e "  │  Name: ${GREEN}${domain%%.*}${RESET} (or your subdomain)                       │"
    echo -e "  │  IPv4: ${GREEN}$ip${RESET}                                   │"
    echo -e "  │  Proxy: ${RED}OFF${RESET} (DNS only - gray cloud in Cloudflare)   │"
    echo -e "  └─────────────────────────────────────────────────────────┘"
    echo ""
    echo -e "  ${BOLD}${CYAN}Cloudflare Users - IMPORTANT:${RESET}"
    echo ""
    echo -e "  ${YELLOW}⚠️  You MUST disable the orange cloud (proxy)!${RESET}"
    echo ""
    echo -e "  1. Go to your domain's DNS settings"
    echo -e "  2. Add an A record pointing to ${WHITE}$ip${RESET}"
    echo -e "  3. Click the ${YELLOW}orange cloud${RESET} to make it ${GRAY}gray${RESET}"
    echo -e "     (This changes from 'Proxied' to 'DNS only')"
    echo ""
    echo -e "  ${GRAY}Why? Cloudflare's proxy only supports HTTP/HTTPS traffic."
    echo -e "  MTProto is a different protocol that needs direct connection.${RESET}"
    echo ""
    print_line
    
    press_enter
}

# ============== USAGE INSTRUCTIONS ==============

show_proxy_links() {
    local ip=$1
    local domain=$2
    local port=$3
    local proxy_mode=$4
    local tls_domain=$5
    shift 5
    local users=("$@")
    
    print_banner
    echo -e "  ${BOLD}${WHITE}🔗 YOUR PROXY LINKS${RESET}"
    print_line
    echo ""
    
    # Encode TLS domain to hex for fake-TLS secrets
    # Use printf + od as fallback if xxd not available
    local tls_domain_hex=""
    if [[ -n "$tls_domain" ]]; then
        if command -v xxd &>/dev/null; then
            tls_domain_hex=$(printf '%s' "$tls_domain" | xxd -p | tr -d '\n')
        else
            # Fallback using od
            tls_domain_hex=$(printf '%s' "$tls_domain" | od -An -tx1 | tr -d ' \n')
        fi
    fi
    
    # Debug: show domain hex (uncomment if needed)
    # echo -e "  ${GRAY}DEBUG: TLS Domain: $tls_domain -> Hex: $tls_domain_hex${RESET}"
    # echo ""
    
    local user_num=1
    for user in "${users[@]}"; do
        IFS=':' read -r name raw_secret mode <<< "$user"
        
        echo -e "  ${BOLD}${CYAN}User: $name${RESET}"
        echo ""
        
        # Clean the secret (remove any existing prefix)
        local clean_secret="${raw_secret#ee}"
        clean_secret="${clean_secret#dd}"
        clean_secret="${clean_secret:0:32}"
        
        # Build the full secret based on mode
        local full_secret=""
        local link_type=""
        
        if [[ "$mode" == "tls" || "$proxy_mode" == "tls" ]]; then
            # Fake-TLS mode: ee + secret + domain_hex
            full_secret="ee${clean_secret}${tls_domain_hex}"
            link_type="Fake-TLS (ee)"
        elif [[ "$mode" == "secure" || "$proxy_mode" == "secure" ]]; then
            # Secure mode with random padding: dd + secret
            full_secret="dd${clean_secret}"
            link_type="Secure/Random Padding (dd)"
        else
            # Classic mode (not recommended)
            full_secret="${clean_secret}"
            link_type="Classic"
        fi
        
        echo -e "  ${WHITE}Mode:${RESET} ${GREEN}$link_type${RESET}"
        echo ""
        
        # IP-based link
        local ip_link="tg://proxy?server=${ip}&port=${port}&secret=${full_secret}"
        local ip_web="https://t.me/proxy?server=${ip}&port=${port}&secret=${full_secret}"
        
        echo -e "  ${WHITE}Direct Link (IP):${RESET}"
        echo -e "  ${GREEN}$ip_link${RESET}"
        echo ""
        echo -e "  ${WHITE}Web Link:${RESET}"
        echo -e "  ${BLUE}$ip_web${RESET}"
        
        # Domain-based link
        if [[ -n "$domain" && "$domain" != "none" ]]; then
            local domain_link="tg://proxy?server=${domain}&port=${port}&secret=${full_secret}"
            local domain_web="https://t.me/proxy?server=${domain}&port=${port}&secret=${full_secret}"
            
            echo ""
            echo -e "  ${WHITE}Domain Link:${RESET}"
            echo -e "  ${GREEN}$domain_link${RESET}"
            echo ""
            echo -e "  ${WHITE}Domain Web Link:${RESET}"
            echo -e "  ${BLUE}$domain_web${RESET}"
        fi
        
        # Show secret details for debugging
        echo ""
        echo -e "  ${GRAY}Secret breakdown:${RESET}"
        echo -e "  ${GRAY}  Mode: ${mode:-$proxy_mode}${RESET}"
        echo -e "  ${GRAY}  Base secret (32 chars): ${clean_secret}${RESET}"
        if [[ "$link_type" == *"ee"* ]]; then
            echo -e "  ${GRAY}  TLS Domain: $tls_domain${RESET}"
            echo -e "  ${GRAY}  Domain Hex: $tls_domain_hex${RESET}"
            echo -e "  ${GRAY}  Full secret length: ${#full_secret} chars${RESET}"
        fi
        
        echo ""
        print_line
        echo ""
        ((user_num++))
    done
}

show_usage_instructions() {
    print_banner
    echo -e "  ${BOLD}${WHITE}📱 HOW TO USE THE PROXY${RESET}"
    print_line
    echo ""
    
    echo -e "  ${BOLD}${CYAN}📱 Telegram Mobile (iOS/Android):${RESET}"
    echo ""
    echo -e "  ${WHITE}Method 1 - Click the link:${RESET}"
    echo -e "  • Open the ${GREEN}tg://proxy?...${RESET} link in a browser"
    echo -e "  • Telegram will open and ask to add the proxy"
    echo -e "  • Tap ${GREEN}\"Connect Proxy\"${RESET}"
    echo ""
    echo -e "  ${WHITE}Method 2 - Manual setup:${RESET}"
    echo -e "  • Settings → Data and Storage → Proxy"
    echo -e "  • Add Proxy → MTProto"
    echo -e "  • Enter server, port, and secret"
    echo ""
    print_line
    echo ""
    
    echo -e "  ${BOLD}${CYAN}💻 Telegram Desktop:${RESET}"
    echo ""
    echo -e "  ${WHITE}Method 1 - Click the link:${RESET}"
    echo -e "  • Open the ${GREEN}tg://proxy?...${RESET} link"
    echo -e "  • Telegram will prompt to enable proxy"
    echo ""
    echo -e "  ${WHITE}Method 2 - Manual setup:${RESET}"
    echo -e "  • Settings → Advanced → Connection type"
    echo -e "  • Add Proxy → MTProto"
    echo -e "  • Enter server, port, and secret"
    echo ""
    print_line
    echo ""
    
    echo -e "  ${BOLD}${CYAN}🌐 Telegram Web:${RESET}"
    echo ""
    echo -e "  • Open the ${BLUE}https://t.me/proxy?...${RESET} link"
    echo -e "  • Click ${GREEN}\"Enable Proxy\"${RESET}"
    echo ""
    print_line
    echo ""
    
    echo -e "  ${BOLD}${CYAN}📲 Third-Party Clients:${RESET}"
    echo ""
    echo -e "  Works with: Nekogram, Plus Messenger, Telegram X, etc."
    echo -e "  Use the same links or manual configuration."
    echo ""
    print_line
    echo ""
    
    echo -e "  ${BOLD}${YELLOW}� Secret Prefixes Explained:${RESET}"
    echo ""
    echo -e "  ${WHITE}ee${RESET} = Fake-TLS Mode (Recommended)"
    echo -e "      Traffic looks like HTTPS to a real website"
    echo -e "      Most resistant to DPI (Deep Packet Inspection)"
    echo -e "      Secret format: ee + 32-char-hex + domain-as-hex"
    echo ""
    echo -e "  ${WHITE}dd${RESET} = Secure Mode with Random Padding"
    echo -e "      Adds random padding to packets"
    echo -e "      Harder to detect than classic mode"
    echo -e "      Secret format: dd + 32-char-hex"
    echo ""
    echo -e "  ${WHITE}No prefix${RESET} = Classic Mode (Not Recommended)"
    echo -e "      Easy to detect and block"
    echo -e "      Only for compatibility with very old clients"
    echo ""
    print_line
    echo ""
    
    echo -e "  ${BOLD}${YELLOW}💡 Tips:${RESET}"
    echo ""
    echo -e "  • Share the ${BLUE}https://t.me/proxy?...${RESET} link for easy sharing"
    echo -e "  • Use domain links if your IP gets blocked"
    echo -e "  • Fake-TLS (ee) is the most censorship-resistant mode"
    echo -e "  • If Fake-TLS doesn't work, try Secure mode (dd)"
    echo ""
    
    press_enter
}

# ============== MAIN INSTALLATION FLOW ==============

install_proxy() {
    print_banner
    echo -e "  ${BOLD}${WHITE}🚀 NEW INSTALLATION${RESET}"
    print_line
    echo ""
    
    # Get public IP
    print_info "Detecting your public IP..."
    PUBLIC_IP=$(get_public_ip)
    
    if [[ -z "$PUBLIC_IP" ]]; then
        print_error "Could not detect public IP"
        get_input "Enter your server's public IP" "" PUBLIC_IP
    else
        print_success "Detected IP: $PUBLIC_IP"
    fi
    echo ""
    
    # Ask if user wants to see port analysis
    if confirm "Show port & firewall analysis before continuing?" "y"; then
        show_port_analysis
    fi
    
    print_banner
    echo -e "  ${BOLD}${WHITE}🚀 CONFIGURATION${RESET}"
    print_line
    echo ""
    
    # Get port with smart conflict handling
    echo -e "  ${BOLD}Port Configuration:${RESET}"
    echo -e "  ${GRAY}Port 443 is recommended (looks like HTTPS traffic)${RESET}"
    echo ""
    
    # Show quick port summary
    echo -e "  ${WHITE}Common ports status:${RESET}"
    for check_port in 443 8443 2053 8080; do
        if check_port_available "$check_port"; then
            echo -e "    ${GREEN}●${RESET} Port $check_port: Available"
        else
            local usage=$(get_port_usage_info "$check_port")
            echo -e "    ${YELLOW}●${RESET} Port $check_port: In use ${GRAY}($usage)${RESET}"
        fi
    done
    echo ""
    
    # Determine default port (suggest available one)
    local default_port="443"
    if ! check_port_available 443; then
        if is_port_used_by_telegram_proxy 443; then
            default_port="443"  # We'll handle replacement
        else
            default_port=$(suggest_alternative_port)
            if [[ "$default_port" != "443" ]]; then
                print_info "Port 443 is in use, suggesting $default_port"
            fi
        fi
    fi
    
    while true; do
        get_input "Enter port number" "$default_port" PROXY_PORT
        
        if ! [[ "$PROXY_PORT" =~ ^[0-9]+$ ]] || (( PROXY_PORT < 1 || PROXY_PORT > 65535 )); then
            print_error "Invalid port number (must be 1-65535)"
            continue
        fi
        
        # Check if port is available
        if ! check_port_available "$PROXY_PORT"; then
            handle_port_conflict "$PROXY_PORT"
            local result=$?
            
            if [[ $result -eq 0 ]]; then
                # Continue with this port (conflict resolved)
                break
            elif [[ $result -eq 1 ]]; then
                # Ask for new port
                echo ""
                default_port=$(suggest_alternative_port)
                print_info "Suggested available port: $default_port"
                continue
            else
                # Cancel
                echo ""
                print_info "Installation cancelled"
                exit 0
            fi
        else
            break
        fi
    done
    
    # Check firewall for selected port
    echo ""
    check_port_accessibility "$PROXY_PORT"
    
    echo ""
    print_success "Using port: $PROXY_PORT"
    echo ""
    
    # Get domain (optional)
    echo -e "  ${BOLD}Domain Configuration (Optional):${RESET}"
    echo -e "  ${GRAY}Using a domain makes it harder to block your proxy${RESET}"
    echo ""
    
    get_input "Enter your domain (or 'none' to skip)" "none" PROXY_DOMAIN
    
    if [[ "$PROXY_DOMAIN" != "none" && -n "$PROXY_DOMAIN" ]]; then
        # Remove http:// or https:// if present
        PROXY_DOMAIN=$(echo "$PROXY_DOMAIN" | sed 's|https\?://||' | sed 's|/.*||')
    fi
    echo ""
    
    # ============== PROXY MODE SELECTION ==============
    echo -e "  ${BOLD}Proxy Mode Selection:${RESET}"
    echo ""
    echo -e "  ${CYAN}1)${RESET} ${GREEN}Fake-TLS (Recommended)${RESET}"
    echo -e "     Traffic looks like HTTPS to a real website"
    echo -e "     Most resistant to deep packet inspection (DPI)"
    echo -e "     Secret prefix: ${WHITE}ee${RESET}"
    echo ""
    echo -e "  ${CYAN}2)${RESET} Secure Mode with Random Padding"
    echo -e "     Adds random padding to packets"
    echo -e "     Good alternative if Fake-TLS is blocked"
    echo -e "     Secret prefix: ${WHITE}dd${RESET}"
    echo ""
    
    get_input "Select mode" "1" mode_choice
    
    local PROXY_MODE="tls"
    local RANDOM_PADDING="no"
    
    case $mode_choice in
        1)
            PROXY_MODE="tls"
            echo ""
            echo -e "  ${BOLD}Fake-TLS Configuration:${RESET}"
            echo -e "  ${GRAY}Your traffic will look like HTTPS to this website${RESET}"
            echo -e "  ${GRAY}Choose a popular site that's not blocked in target region${RESET}"
            echo ""
            echo -e "  ${WHITE}Suggestions:${RESET}"
            echo -e "  • www.google.com (default)"
            echo -e "  • www.cloudflare.com"
            echo -e "  • www.microsoft.com"
            echo -e "  • www.apple.com"
            echo -e "  • www.bing.com"
            echo ""
            
            get_input "Enter fake-TLS domain" "www.google.com" TLS_DOMAIN
            
            # Ask about random padding for TLS mode
            echo ""
            if confirm "Also enable random padding for extra obfuscation?" "y"; then
                RANDOM_PADDING="yes"
                print_success "Random padding enabled (dd mode will also work)"
            fi
            ;;
        2)
            PROXY_MODE="secure"
            TLS_DOMAIN="www.google.com"  # Not used but set for config
            print_success "Secure mode with random padding selected"
            ;;
        *)
            PROXY_MODE="tls"
            TLS_DOMAIN="www.google.com"
            ;;
    esac
    
    echo ""
    
    # Get number of users
    echo -e "  ${BOLD}User Configuration:${RESET}"
    echo -e "  ${GRAY}You can create multiple users with different secrets${RESET}"
    echo ""
    
    get_input "How many users to create?" "1" NUM_USERS
    
    if ! [[ "$NUM_USERS" =~ ^[0-9]+$ ]] || (( NUM_USERS < 1 || NUM_USERS > 100 )); then
        print_error "Invalid number (1-100)"
        exit 1
    fi
    
    # Create users
    declare -a USERS
    echo ""
    
    for ((i=1; i<=NUM_USERS; i++)); do
        get_input "Enter name for user $i" "user$i" username
        secret=$(generate_secret)
        # Store with mode info: name:secret:mode
        USERS+=("${username}:${secret}:${PROXY_MODE}")
        print_success "Created user: $username"
    done
    
    echo ""
    print_line
    echo ""
    
    # Confirm installation
    echo -e "  ${BOLD}Configuration Summary:${RESET}"
    echo ""
    echo -e "  Server IP:      ${WHITE}$PUBLIC_IP${RESET}"
    echo -e "  Port:           ${WHITE}$PROXY_PORT${RESET}"
    echo -e "  Domain:         ${WHITE}${PROXY_DOMAIN:-none}${RESET}"
    echo -e "  Proxy Mode:     ${WHITE}${PROXY_MODE}${RESET}"
    if [[ "$PROXY_MODE" == "tls" ]]; then
        echo -e "  Fake-TLS Host:  ${WHITE}$TLS_DOMAIN${RESET}"
    fi
    echo -e "  Random Padding: ${WHITE}$RANDOM_PADDING${RESET}"
    echo -e "  Users:          ${WHITE}$NUM_USERS${RESET}"
    echo ""
    
    if ! confirm "Proceed with installation?" "y"; then
        echo ""
        print_info "Installation cancelled"
        exit 0
    fi
    
    echo ""
    print_line
    echo ""
    
    # Install
    install_dependencies
    clone_mtprotoproxy
    create_config "$PROXY_PORT" "$TLS_DOMAIN" "$PROXY_MODE" "$RANDOM_PADDING" "${USERS[@]}"
    create_service
    save_proxy_data "$PUBLIC_IP" "$PROXY_DOMAIN" "$PROXY_PORT" "$PROXY_MODE" "$TLS_DOMAIN" "$RANDOM_PADDING" "${USERS[@]}"
    
    if start_service; then
        echo ""
        print_line
        echo ""
        print_success "${BOLD}Installation complete!${RESET}"
        echo ""
        
        press_enter
        
        # Show firewall instructions
        show_firewall_instructions "$PROXY_PORT"
        
        # Show DNS instructions
        show_dns_instructions "$PUBLIC_IP" "$PROXY_DOMAIN"
        
        # Show proxy links
        show_proxy_links "$PUBLIC_IP" "$PROXY_DOMAIN" "$PROXY_PORT" "$PROXY_MODE" "$TLS_DOMAIN" "${USERS[@]}"
        
        press_enter
        
        # Show usage instructions
        show_usage_instructions
    fi
}

# ============== MANAGEMENT FUNCTIONS ==============

show_status() {
    print_banner
    echo -e "  ${BOLD}${WHITE}📊 PROXY STATUS${RESET}"
    print_line
    echo ""
    
    if is_installed; then
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            echo -e "  Status: ${GREEN}● Running${RESET}"
        else
            echo -e "  Status: ${RED}● Stopped${RESET}"
        fi
        
        # Load saved data
        if [[ -f "$DATA_FILE" ]]; then
            source "$DATA_FILE"
            echo ""
            echo -e "  IP:           ${WHITE}$PROXY_IP${RESET}"
            echo -e "  Domain:       ${WHITE}${PROXY_DOMAIN:-none}${RESET}"
            echo -e "  Port:         ${WHITE}$PROXY_PORT${RESET}"
            echo -e "  Mode:         ${WHITE}${PROXY_MODE:-tls}${RESET}"
            if [[ "${PROXY_MODE:-tls}" == "tls" ]]; then
                echo -e "  TLS Domain:   ${WHITE}${TLS_DOMAIN:-www.google.com}${RESET}"
            fi
            echo -e "  Rand Padding: ${WHITE}${RANDOM_PADDING:-no}${RESET}"
            echo -e "  Users:        ${WHITE}${#PROXY_USERS[@]}${RESET}"
        fi
        
        echo ""
        print_line
        echo ""
        
        # Show service details
        echo -e "  ${BOLD}Service Details:${RESET}"
        echo ""
        systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null | head -15 | sed 's/^/  /'
    else
        echo -e "  Status: ${YELLOW}● Not installed${RESET}"
    fi
    
    echo ""
    press_enter
}

view_links() {
    if [[ -f "$DATA_FILE" ]]; then
        source "$DATA_FILE"
        show_proxy_links "$PROXY_IP" "$PROXY_DOMAIN" "$PROXY_PORT" "$PROXY_MODE" "$TLS_DOMAIN" "${PROXY_USERS[@]}"
        press_enter
    else
        print_error "No proxy data found. Install first."
        press_enter
    fi
}

add_user() {
    print_banner
    echo -e "  ${BOLD}${WHITE}➕ ADD NEW USER${RESET}"
    print_line
    echo ""
    
    if ! is_installed; then
        print_error "Proxy is not installed"
        press_enter
        return
    fi
    
    source "$DATA_FILE"
    
    get_input "Enter name for new user" "" username
    
    if [[ -z "$username" ]]; then
        print_error "Username cannot be empty"
        press_enter
        return
    fi
    
    # Check for duplicate username
    for existing_user in "${PROXY_USERS[@]}"; do
        IFS=':' read -r existing_name _ _ <<< "$existing_user"
        if [[ "$existing_name" == "$username" ]]; then
            print_error "User '$username' already exists!"
            print_info "Use a different name or delete the existing user first"
            press_enter
            return
        fi
    done
    
    secret=$(generate_secret)
    
    # Store with mode info
    new_user="${username}:${secret}:${PROXY_MODE:-tls}"
    
    # Add to config file (config stores clean secret without prefix)
    # We need to insert the new user ONLY in the USERS block, not MODES
    # Use awk for reliable cross-platform editing
    awk -v user="$username" -v secret="$secret" '
        /^USERS = \{/ { in_users=1 }
        in_users && /^\}$/ {
            print "    \"" user "\": \"" secret "\","
            in_users=0
        }
        { print }
    ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    # Add to data file
    PROXY_USERS+=("$new_user")
    save_proxy_data "$PROXY_IP" "$PROXY_DOMAIN" "$PROXY_PORT" "$PROXY_MODE" "$TLS_DOMAIN" "$RANDOM_PADDING" "${PROXY_USERS[@]}"
    
    # Restart service
    systemctl restart "$SERVICE_NAME"
    
    print_success "User '$username' added!"
    echo ""
    
    # Build the full secret for display
    local full_secret=""
    local tls_domain_hex=""
    
    if [[ "$PROXY_MODE" == "tls" && -n "$TLS_DOMAIN" ]]; then
        tls_domain_hex=$(printf '%s' "$TLS_DOMAIN" | xxd -p | tr -d '\n')
        full_secret="ee${secret}${tls_domain_hex}"
    elif [[ "$PROXY_MODE" == "secure" ]]; then
        full_secret="dd${secret}"
    else
        full_secret="${secret}"
    fi
    
    echo -e "  ${WHITE}Mode:${RESET} ${PROXY_MODE:-tls}"
    echo -e "  ${WHITE}Base Secret:${RESET} ${secret}"
    echo ""
    
    # Show links for new user
    echo -e "  ${WHITE}Link:${RESET}"
    echo -e "  ${GREEN}tg://proxy?server=${PROXY_IP}&port=${PROXY_PORT}&secret=${full_secret}${RESET}"
    
    if [[ -n "$PROXY_DOMAIN" && "$PROXY_DOMAIN" != "none" ]]; then
        echo ""
        echo -e "  ${WHITE}Domain Link:${RESET}"
        echo -e "  ${GREEN}tg://proxy?server=${PROXY_DOMAIN}&port=${PROXY_PORT}&secret=${full_secret}${RESET}"
    fi
    
    echo ""
    press_enter
}

restart_service() {
    print_step "Restarting proxy..."
    systemctl restart "$SERVICE_NAME"
    sleep 2
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "Proxy restarted successfully"
    else
        print_error "Failed to restart proxy"
    fi
    
    press_enter
}

view_logs() {
    print_banner
    echo -e "  ${BOLD}${WHITE}📋 PROXY LOGS${RESET}"
    print_line
    echo ""
    
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager | sed 's/^/  /'
    
    echo ""
    press_enter
}

uninstall_proxy() {
    print_banner
    echo -e "  ${BOLD}${RED}⚠️  UNINSTALL PROXY${RESET}"
    print_line
    echo ""
    
    echo -e "  ${YELLOW}This will remove:${RESET}"
    echo -e "  • Proxy service"
    echo -e "  • All configuration"
    echo -e "  • All user data"
    echo ""
    
    if confirm "Are you sure you want to uninstall?"; then
        echo ""
        print_step "Stopping service..."
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        
        # Wait for port to be released
        sleep 2
        
        print_step "Removing files..."
        rm -f "$SERVICE_FILE"
        rm -rf "$INSTALL_DIR"
        
        systemctl daemon-reload
        
        # Verify cleanup
        sleep 1
        if [[ -f "$SERVICE_FILE" ]] || [[ -d "$INSTALL_DIR" ]]; then
            print_warning "Some files may not have been removed completely"
        else
            print_success "All files removed"
        fi
        
        print_success "Uninstalled successfully"
    else
        print_info "Uninstall cancelled"
    fi
    
    press_enter
}

# ============== MAIN MENU ==============

main_menu() {
    while true; do
        print_banner
        
        # Show quick status
        if is_installed; then
            if systemctl is-active --quiet "$SERVICE_NAME"; then
                echo -e "  Proxy Status: ${GREEN}● Running${RESET}"
            else
                echo -e "  Proxy Status: ${RED}● Stopped${RESET}"
            fi
            
            if [[ -f "$DATA_FILE" ]]; then
                source "$DATA_FILE"
                echo -e "  Server: ${WHITE}${PROXY_DOMAIN:-$PROXY_IP}:$PROXY_PORT${RESET}"
                echo -e "  Mode: ${WHITE}${PROXY_MODE:-tls}${RESET}"
                echo -e "  Users: ${WHITE}${#PROXY_USERS[@]}${RESET}"
            fi
        else
            echo -e "  Proxy Status: ${YELLOW}● Not installed${RESET}"
        fi
        
        echo ""
        print_line
        echo ""
        echo -e "  ${BOLD}Main Menu:${RESET}"
        echo ""
        
        if is_installed; then
            echo -e "  ${CYAN}1)${RESET} View Status"
            echo -e "  ${CYAN}2)${RESET} View Proxy Links"
            echo -e "  ${CYAN}3)${RESET} Add New User"
            echo -e "  ${CYAN}4)${RESET} Restart Proxy"
            echo -e "  ${CYAN}5)${RESET} View Logs"
            echo -e "  ${CYAN}6)${RESET} Port & Firewall Analysis"
            echo -e "  ${CYAN}7)${RESET} Firewall Instructions"
            echo -e "  ${CYAN}8)${RESET} DNS Instructions"
            echo -e "  ${CYAN}9)${RESET} Usage Instructions"
            echo -e "  ${CYAN}10)${RESET} Reinstall"
            echo -e "  ${RED}11)${RESET} Uninstall"
        else
            echo -e "  ${CYAN}1)${RESET} Install Proxy"
            echo -e "  ${CYAN}2)${RESET} Port & Firewall Analysis"
        fi
        
        echo -e "  ${CYAN}0)${RESET} Exit"
        echo ""
        print_line
        echo ""
        
        get_input "Select option" "" choice
        
        if is_installed; then
            case $choice in
                1) show_status ;;
                2) view_links ;;
                3) add_user ;;
                4) restart_service ;;
                5) view_logs ;;
                6) show_port_analysis ;;
                7) 
                    source "$DATA_FILE" 2>/dev/null
                    show_firewall_instructions "${PROXY_PORT:-443}"
                    ;;
                8)
                    source "$DATA_FILE" 2>/dev/null
                    show_dns_instructions "$PROXY_IP" "$PROXY_DOMAIN"
                    ;;
                9) show_usage_instructions ;;
                10) install_proxy ;;
                11) uninstall_proxy ;;
                0) 
                    echo ""
                    print_info "Goodbye!"
                    echo ""
                    exit 0
                    ;;
                *) print_error "Invalid option" ;;
            esac
        else
            case $choice in
                1) install_proxy ;;
                2) show_port_analysis ;;
                0)
                    echo ""
                    print_info "Goodbye!"
                    echo ""
                    exit 0
                    ;;
                *) print_error "Invalid option" ;;
            esac
        fi
    done
}

# ============== ENTRY POINT ==============

main() {
    # Check requirements
    check_root
    check_os
    
    # Install xxd if not present (needed for secret generation)
    if ! command -v xxd &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq xxd > /dev/null 2>&1
    fi
    
    # Check for stale/orphaned installations
    check_stale_installation
    
    # Run main menu
    main_menu
}

# Run
main "$@"
