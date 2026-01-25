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
SCRIPT_VERSION="1.3.0"
INSTALL_DIR="/opt/telegram-proxy"
CONFIG_FILE="$INSTALL_DIR/config.py"
SERVICE_NAME="telegram-proxy"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
DATA_FILE="$INSTALL_DIR/proxy_data.sh"
STATS_FILE="$INSTALL_DIR/stats.json"
STATS_COLLECTOR="$INSTALL_DIR/stats_collector.py"
STATS_PORT=8888

# Proxy modes
MODE_TLS="tls"          # Fake-TLS (ee prefix) - traffic looks like HTTPS
MODE_SECURE="secure"    # Random padding (dd prefix) - harder to detect

# ============== HELPER FUNCTIONS ==============

print_banner() {
    clear
    echo -e "${GREEN}"                                                                                      
    echo '                                                                                                    '
    echo '                                                . ....                                              '
    echo '                                                =:.%.%@:                                            '
    echo '                                             .:%@@-@@*.@%                                           '
    echo '                                            ..+..==*+::.@@.                                         '
    echo '                                           ..*  ..@+.-.+*@@.                                        '
    echo '                                           ..  +#:.. ....+@+.                                       '
    echo '                                         :.* #.+.       ..:@.                                       '
    echo '                                         :   .           :..::                                      '
    echo '                                       .:@ ..              -==.                                     '
    echo '                                       - *-                .%@*                                     '
    echo '                                      .#:: .                 --.                                    '
    echo '                                       ..--:                #-+-                                    '
    echo '                                   .:..   .                ..* :=.                                  '
    echo '                                   .=# .     ...          :- :.-@**                                 '
    echo '                                  :=**. ..            ..@. :.:@@*%%.                                '
    echo '                                 .-.    . .-    %        ..#:-=..=-=                                '
    echo '                                 :@= .   :@%@-....    ..::=@.#:%.=**.                               '
    echo '                                 :  ..   :-=:% @=:    -.#*##--@=--#@-.                              '
    echo '                                .+% +   =@.* #@.*..   .=::.==. %.@*=*:                              '
    echo '                                :#      . *#:* -==     :@#%#@.+ @:==@:                              '
    echo '                               :# @: .  ==+@:-*.-.     *-.#=+@-@ #=@.:.                             '
    echo '                               =.## . ..-:@-++-@@       =:#+:*..:=-=%@*                             '
    echo '                              .* *:    =.-:=-:..+.      -.#%=*+%+:-=.@=..                           '
    echo '                             .=@:*    :#%.#.* =@-       . *+=.*+=*-.#%@-.                           '
    echo '                             .=-*+# @.-@@**: ::@.        -:**-%.-=%@ :=:-                           '
    echo '                             :=  .  @-= ==:  +*..        .:+..-.@....:@:=:                          '
    echo '                           .:-:   : -:.+-. =:--.         .:.@+@@ @=+@++.#=.                         '
    echo '                           .%@   -@  @=@*@ *+@-           .- +*+-*+*#*%-*+..                        '
    echo '                           .:.  .:-.:+:-:@.:.:            .-.-::.:.: =@ #@.                         '
    echo '                          :=@ @..-#: @=.  :@@.             ::@*:@@@+----+**-                        '
    echo '                         .-= @% : :#@#. :*:=.                ++#=-. .-+==++#.                       '
    echo '                         . @*:    . -* : .%.                .= +-::    .--.+..                      '
    echo '                        .@#*: . . @%* :.:=%                  :-+%@+.  @.%*%*@-                      '
    echo '                       .:*: :  *-=** .=@#:-  .=              .:::---..:*=#:-:.:                     '
    echo '                      .=@+ :. .%-+.  @*:=.   @:.    :         -.=%-**- . *-.+*=.                    '
    echo '                     .=:.-*@ -...+--:+..    :       *    .    ::@ +*+:: :#::+.-..                   '
    echo '                    .*--. #.-@%.  @@-.         :  . -         . *- #-#: :.=*=   .                   '
    echo '                   .: :@. -+:=  #*+.                           :@  @:%@. =@@                        '
    echo '                       . ++=*:#+#+.               ::*#  ..    .:*@ 8 3 h n 4 m .                        '
    echo '                         ++. %-:                       .===#:@.@:=-..#+.@% %.                       '
    echo '                         @@@-.                            .     :-=:+-@.-:                          '
    echo '                        =..                                     .*+**:.:..                          '
    echo '                       ..                                        .-..                               '
    echo '                       .                                         .%:.                               '
    echo '                                                                 .%                                 '
    echo '                                                                  .                                 '                                                                      
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

# Check if IP has changed and return status
# Returns: 0 if IP changed, 1 if same, 2 if error
check_ip_changed() {
    if [[ ! -f "$DATA_FILE" ]]; then
        return 2
    fi
    
    source "$DATA_FILE"
    local current_ip=$(get_public_ip)
    
    if [[ -z "$current_ip" ]]; then
        return 2
    fi
    
    if [[ "$current_ip" != "$PROXY_IP" ]]; then
        echo "$current_ip"
        return 0
    fi
    
    return 1
}

# Update IP address in all config files
update_ip() {
    print_banner
    echo -e "  ${BOLD}${WHITE}🔄 UPDATE IP ADDRESS${RESET}"
    print_line
    echo ""
    
    if ! is_installed; then
        print_error "Proxy is not installed"
        press_enter
        return
    fi
    
    source "$DATA_FILE"
    
    local old_ip="$PROXY_IP"
    local new_ip=$(get_public_ip)
    
    if [[ -z "$new_ip" ]]; then
        print_error "Could not detect current public IP"
        press_enter
        return
    fi
    
    echo -e "  ${WHITE}Old IP:${RESET} $old_ip"
    echo -e "  ${WHITE}New IP:${RESET} $new_ip"
    echo ""
    
    if [[ "$old_ip" == "$new_ip" ]]; then
        print_success "IP address hasn't changed"
        press_enter
        return
    fi
    
    print_warning "IP address has changed!"
    echo ""
    
    if confirm "Update proxy configuration with new IP?" "y"; then
        echo ""
        print_step "Updating configuration..."
        
        # Update proxy_data.sh
        PROXY_IP="$new_ip"
        save_proxy_data "$PROXY_IP" "$PROXY_DOMAIN" "$PROXY_PORT" "$PROXY_MODE" "$TLS_DOMAIN" "$RANDOM_PADDING" "${PROXY_USERS[@]}"
        
        print_success "Configuration updated"
        
        # Restart service
        print_step "Restarting proxy..."
        systemctl restart "$SERVICE_NAME"
        sleep 2
        
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            print_success "Proxy restarted successfully"
        else
            print_error "Failed to restart proxy"
        fi
        
        echo ""
        print_success "IP updated to: $new_ip"
        echo ""
        
        # Remind about DNS
        if [[ -n "$PROXY_DOMAIN" && "$PROXY_DOMAIN" != "none" ]]; then
            echo -e "  ${YELLOW}⚠️  IMPORTANT: Update your DNS!${RESET}"
            echo ""
            echo -e "  Your domain ${WHITE}$PROXY_DOMAIN${RESET} needs to point to:"
            echo -e "  ${GREEN}$new_ip${RESET}"
            echo ""
            echo -e "  Update this in your DNS provider (Cloudflare, etc.)"
        fi
        
        echo ""
        echo -e "  ${WHITE}New proxy links will use IP:${RESET} $new_ip"
        echo -e "  ${GRAY}Use 'View Proxy Links' to see updated links${RESET}"
    else
        print_info "Update cancelled"
    fi
    
    press_enter
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

# ============== NETWORK OPTIMIZATION ==============

configure_network_keepalive() {
    print_step "Configuring network keepalive settings..."
    
    # Create sysctl configuration for persistent settings
    local SYSCTL_FILE="/etc/sysctl.d/99-telegram-proxy.conf"
    
    cat > "$SYSCTL_FILE" << 'EOF'
# Telegram Proxy Network Optimization
# Keeps connections alive to prevent intermittent disconnections

# TCP Keepalive - Send keepalive probes after 60s of idle
net.ipv4.tcp_keepalive_time = 60

# Send keepalive probes every 10 seconds after first probe
net.ipv4.tcp_keepalive_intvl = 10

# Give up after 6 failed keepalive probes (60s total)
net.ipv4.tcp_keepalive_probes = 6

# Allow more simultaneous connections
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# Faster connection handling
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1

# More available local ports for outgoing connections
net.ipv4.ip_local_port_range = 1024 65535

# Larger network buffers
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF

    # Apply settings immediately
    sysctl -p "$SYSCTL_FILE" > /dev/null 2>&1 || true
    
    print_success "Network keepalive configured"
}

# ============== STATS TRACKING ==============

create_stats_collector() {
    print_step "Creating stats collector..."
    
    cat > "$STATS_COLLECTOR" << 'STATS_SCRIPT'
#!/usr/bin/env python3
"""
DNSCloak Stats Collector
Collects metrics from mtprotoproxy and maintains user statistics
"""

import json
import os
import time
import urllib.request
from datetime import datetime
from pathlib import Path

STATS_FILE = "/opt/telegram-proxy/stats.json"
PROMETHEUS_URL = "http://127.0.0.1:8888/metrics"

def load_stats():
    """Load existing stats or create new"""
    if os.path.exists(STATS_FILE):
        try:
            with open(STATS_FILE, 'r') as f:
                return json.load(f)
        except:
            pass
    return {
        "start_time": time.time(),
        "last_update": time.time(),
        "total_connections": 0,
        "total_bytes_in": 0,
        "total_bytes_out": 0,
        "users": {}
    }

def save_stats(stats):
    """Save stats to file"""
    stats["last_update"] = time.time()
    with open(STATS_FILE, 'w') as f:
        json.dump(stats, f, indent=2)

def parse_prometheus_metrics(text):
    """Parse Prometheus format metrics"""
    metrics = {}
    for line in text.split('\n'):
        if line.startswith('#') or not line.strip():
            continue
        try:
            if ' ' in line:
                key, value = line.rsplit(' ', 1)
                # Handle labels like mtprotoproxy_user_bytes{user="user1",direction="out"}
                if '{' in key:
                    base_name = key.split('{')[0]
                    labels_str = key.split('{')[1].rstrip('}')
                    labels = {}
                    for part in labels_str.split(','):
                        if '=' in part:
                            k, v = part.split('=', 1)
                            labels[k] = v.strip('"')
                    metrics.setdefault(base_name, []).append({
                        "labels": labels,
                        "value": float(value)
                    })
                else:
                    metrics[key] = float(value)
        except:
            continue
    return metrics

def fetch_metrics():
    """Fetch metrics from mtprotoproxy Prometheus endpoint"""
    try:
        req = urllib.request.Request(PROMETHEUS_URL, headers={'User-Agent': 'DNSCloak-Stats/1.0'})
        with urllib.request.urlopen(req, timeout=5) as response:
            return parse_prometheus_metrics(response.read().decode('utf-8'))
    except Exception as e:
        return None

def update_stats():
    """Update stats from proxy metrics"""
    stats = load_stats()
    metrics = fetch_metrics()
    
    if metrics:
        # Update global counters
        if 'mtprotoproxy_connections' in metrics:
            stats['current_connections'] = int(metrics.get('mtprotoproxy_connections', 0))
        
        # Get user-specific metrics
        user_bytes = metrics.get('mtprotoproxy_user_bytes', [])
        user_conns = metrics.get('mtprotoproxy_user_connections', [])
        
        # Process user bytes (in/out)
        for item in user_bytes:
            user = item['labels'].get('user', 'unknown')
            direction = item['labels'].get('direction', 'in')
            value = int(item['value'])
            
            if user not in stats['users']:
                stats['users'][user] = {
                    "bytes_in": 0,
                    "bytes_out": 0,
                    "connections": 0,
                    "current_connections": 0,
                    "last_seen": None,
                    "first_seen": time.time()
                }
            
            if direction == 'in':
                if value > stats['users'][user].get('bytes_in', 0):
                    stats['users'][user]['last_seen'] = time.time()
                stats['users'][user]['bytes_in'] = value
            else:
                stats['users'][user]['bytes_out'] = value
        
        # Process user connections
        for item in user_conns:
            user = item['labels'].get('user', 'unknown')
            value = int(item['value'])
            
            if user not in stats['users']:
                stats['users'][user] = {
                    "bytes_in": 0,
                    "bytes_out": 0,
                    "connections": 0,
                    "current_connections": 0,
                    "last_seen": None,
                    "first_seen": time.time()
                }
            
            # Check if connection count increased (new connection)
            prev_conns = stats['users'][user].get('total_connections', 0)
            if value > prev_conns:
                stats['users'][user]['last_seen'] = time.time()
            stats['users'][user]['total_connections'] = value
            stats['users'][user]['current_connections'] = value
        
        # Calculate totals
        stats['total_bytes_in'] = sum(u.get('bytes_in', 0) for u in stats['users'].values())
        stats['total_bytes_out'] = sum(u.get('bytes_out', 0) for u in stats['users'].values())
        stats['total_connections'] = sum(u.get('total_connections', 0) for u in stats['users'].values())
    
    save_stats(stats)
    return stats

def get_stats():
    """Get current stats (for display)"""
    if os.path.exists(STATS_FILE):
        with open(STATS_FILE, 'r') as f:
            return json.load(f)
    return None

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "update":
        stats = update_stats()
        print(json.dumps(stats, indent=2))
    elif len(sys.argv) > 1 and sys.argv[1] == "show":
        stats = get_stats()
        if stats:
            print(json.dumps(stats, indent=2))
        else:
            print("{}")
    else:
        # Continuous collection mode
        while True:
            update_stats()
            time.sleep(10)
STATS_SCRIPT

    chmod +x "$STATS_COLLECTOR"
    print_success "Stats collector created"
}

create_stats_service() {
    print_step "Creating stats collector service..."
    
    local STATS_SERVICE="/etc/systemd/system/telegram-proxy-stats.service"
    
    tee "$STATS_SERVICE" > /dev/null << EOF
[Unit]
Description=Telegram Proxy Stats Collector
After=telegram-proxy.service
Requires=telegram-proxy.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $STATS_COLLECTOR
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable telegram-proxy-stats > /dev/null 2>&1
    systemctl start telegram-proxy-stats 2>/dev/null || true
    
    print_success "Stats collector service created"
}

format_bytes() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}") GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}") MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1024}") KB"
    else
        echo "$bytes B"
    fi
}

format_duration() {
    local seconds=$1
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    if [[ $days -gt 0 ]]; then
        echo "${days}d ${hours}h ${minutes}m"
    elif [[ $hours -gt 0 ]]; then
        echo "${hours}h ${minutes}m ${secs}s"
    elif [[ $minutes -gt 0 ]]; then
        echo "${minutes}m ${secs}s"
    else
        echo "${secs}s"
    fi
}

format_timestamp() {
    local ts=$1
    if [[ -z "$ts" || "$ts" == "null" ]]; then
        echo "Never"
    else
        date -d "@${ts%.*}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -r "${ts%.*}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown"
    fi
}

time_ago() {
    local ts=$1
    if [[ -z "$ts" || "$ts" == "null" ]]; then
        echo "Never"
        return
    fi
    
    local now=$(date +%s)
    local diff=$((now - ${ts%.*}))
    
    if [[ $diff -lt 60 ]]; then
        echo "Just now"
    elif [[ $diff -lt 3600 ]]; then
        echo "$((diff / 60)) min ago"
    elif [[ $diff -lt 86400 ]]; then
        echo "$((diff / 3600)) hours ago"
    else
        echo "$((diff / 86400)) days ago"
    fi
}

show_stats() {
    print_banner
    echo -e "  ${BOLD}${WHITE}📊 PROXY STATISTICS${RESET}"
    print_line
    echo ""
    
    # Update stats first
    python3 "$STATS_COLLECTOR" update > /dev/null 2>&1
    
    # Check if stats file exists
    if [[ ! -f "$STATS_FILE" ]]; then
        print_warning "No statistics available yet"
        print_info "Stats are collected every 10 seconds"
        press_enter
        return
    fi
    
    # Read stats
    local stats=$(cat "$STATS_FILE")
    
    # Parse JSON with python
    local start_time=$(echo "$stats" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('start_time', 0))" 2>/dev/null)
    local total_bytes_in=$(echo "$stats" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('total_bytes_in', 0))" 2>/dev/null)
    local total_bytes_out=$(echo "$stats" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('total_bytes_out', 0))" 2>/dev/null)
    local current_conns=$(echo "$stats" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('current_connections', 0))" 2>/dev/null)
    local total_conns=$(echo "$stats" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('total_connections', 0))" 2>/dev/null)
    
    # Calculate uptime
    local now=$(date +%s)
    local uptime_secs=$((now - ${start_time%.*}))
    
    # Also get systemd uptime as fallback
    local service_uptime=$(systemctl show -p ActiveEnterTimestamp "$SERVICE_NAME" 2>/dev/null | cut -d'=' -f2)
    if [[ -n "$service_uptime" && "$service_uptime" != "" ]]; then
        local service_start=$(date -d "$service_uptime" +%s 2>/dev/null || echo "")
        if [[ -n "$service_start" ]]; then
            uptime_secs=$((now - service_start))
        fi
    fi
    
    # Display overview
    echo -e "  ${BOLD}${CYAN}═══ Overview ═══${RESET}"
    echo ""
    echo -e "  ${WHITE}Uptime:${RESET}              $(format_duration $uptime_secs)"
    echo -e "  ${WHITE}Active Connections:${RESET}  ${GREEN}${current_conns:-0}${RESET}"
    echo -e "  ${WHITE}Total Connections:${RESET}   ${total_conns:-0}"
    echo ""
    echo -e "  ${WHITE}Data Received:${RESET}       $(format_bytes ${total_bytes_in:-0})"
    echo -e "  ${WHITE}Data Sent:${RESET}           $(format_bytes ${total_bytes_out:-0})"
    echo -e "  ${WHITE}Total Transfer:${RESET}      $(format_bytes $((${total_bytes_in:-0} + ${total_bytes_out:-0})))"
    echo ""
    
    # Per-user stats
    echo -e "  ${BOLD}${CYAN}═══ User Statistics ═══${RESET}"
    echo ""
    
    # Get user list
    local users=$(echo "$stats" | python3 -c "
import sys, json
d = json.load(sys.stdin)
users = d.get('users', {})
for name, data in users.items():
    bytes_in = data.get('bytes_in', 0)
    bytes_out = data.get('bytes_out', 0)
    total_conns = data.get('total_connections', 0)
    current_conns = data.get('current_connections', 0)
    last_seen = data.get('last_seen', '')
    first_seen = data.get('first_seen', '')
    print(f'{name}|{bytes_in}|{bytes_out}|{total_conns}|{current_conns}|{last_seen}|{first_seen}')
" 2>/dev/null)
    
    if [[ -z "$users" ]]; then
        echo -e "  ${GRAY}No user activity recorded yet${RESET}"
    else
        printf "  ${WHITE}%-12s %-8s %-12s %-12s %-16s${RESET}\n" "USER" "ACTIVE" "DOWNLOAD" "UPLOAD" "LAST SEEN"
        echo -e "  ${GRAY}────────────────────────────────────────────────────────────────${RESET}"
        
        while IFS='|' read -r name bytes_in bytes_out total_conns current_conns last_seen first_seen; do
            if [[ -n "$name" ]]; then
                local active_indicator="${GRAY}○${RESET}"
                if [[ "$current_conns" -gt 0 ]]; then
                    active_indicator="${GREEN}●${RESET}"
                fi
                
                local last_seen_str=$(time_ago "$last_seen")
                
                printf "  %-12s ${active_indicator} %-6s %-12s %-12s %-16s\n" \
                    "$name" \
                    "$current_conns" \
                    "$(format_bytes ${bytes_in:-0})" \
                    "$(format_bytes ${bytes_out:-0})" \
                    "$last_seen_str"
            fi
        done <<< "$users"
    fi
    
    echo ""
    print_line
    echo ""
    echo -e "  ${GRAY}Stats update every 10 seconds${RESET}"
    echo ""
    
    press_enter
}

show_live_stats() {
    # Live updating stats display
    while true; do
        clear
        print_banner
        echo -e "  ${BOLD}${WHITE}📊 LIVE STATISTICS${RESET} ${GRAY}(Press Ctrl+C to exit)${RESET}"
        print_line
        echo ""
        
        # Update stats
        python3 "$STATS_COLLECTOR" update > /dev/null 2>&1
        
        if [[ -f "$STATS_FILE" ]]; then
            local stats=$(cat "$STATS_FILE")
            
            local current_conns=$(echo "$stats" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('current_connections', 0))" 2>/dev/null)
            local total_bytes_in=$(echo "$stats" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('total_bytes_in', 0))" 2>/dev/null)
            local total_bytes_out=$(echo "$stats" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('total_bytes_out', 0))" 2>/dev/null)
            
            # Get systemd uptime
            local now=$(date +%s)
            local service_uptime=$(systemctl show -p ActiveEnterTimestamp "$SERVICE_NAME" 2>/dev/null | cut -d'=' -f2)
            local uptime_secs=0
            if [[ -n "$service_uptime" && "$service_uptime" != "" ]]; then
                local service_start=$(date -d "$service_uptime" +%s 2>/dev/null || echo "")
                if [[ -n "$service_start" ]]; then
                    uptime_secs=$((now - service_start))
                fi
            fi
            
            echo -e "  ┌─────────────────────────────────────────────┐"
            echo -e "  │  ${WHITE}Uptime:${RESET}    $(printf '%-30s' "$(format_duration $uptime_secs)") │"
            echo -e "  │  ${WHITE}Active:${RESET}    ${GREEN}$(printf '%-30s' "${current_conns:-0} connections")${RESET} │"
            echo -e "  │  ${WHITE}Download:${RESET}  $(printf '%-30s' "$(format_bytes ${total_bytes_in:-0})") │"
            echo -e "  │  ${WHITE}Upload:${RESET}    $(printf '%-30s' "$(format_bytes ${total_bytes_out:-0})") │"
            echo -e "  └─────────────────────────────────────────────┘"
            echo ""
            
            # Show active users
            echo -e "  ${BOLD}${CYAN}Active Users:${RESET}"
            echo ""
            
            local users=$(echo "$stats" | python3 -c "
import sys, json
d = json.load(sys.stdin)
users = d.get('users', {})
for name, data in users.items():
    if data.get('current_connections', 0) > 0:
        print(f\"{name}: {data.get('current_connections', 0)} conn\")
" 2>/dev/null)
            
            if [[ -z "$users" ]]; then
                echo -e "  ${GRAY}No active connections${RESET}"
            else
                while read -r line; do
                    echo -e "  ${GREEN}●${RESET} $line"
                done <<< "$users"
            fi
        else
            echo -e "  ${GRAY}Waiting for stats...${RESET}"
        fi
        
        sleep 3
    done
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

# Stats - enable Prometheus metrics on localhost
STATS_HOST = "127.0.0.1"
STATS_PORT = $STATS_PORT
EOF

    print_success "Configuration created"
}

create_service() {
    print_step "Creating systemd service..."
    
    tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Telegram MTProto Proxy (Fake-TLS)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 -u $INSTALL_DIR/mtprotoproxy.py
Restart=always
RestartSec=3
User=root
LimitNOFILE=65536

# Watchdog - restart if service becomes unresponsive
WatchdogSec=60
NotifyAccess=all

# Memory management - restart if using too much memory
MemoryMax=512M
MemoryHigh=384M

# Performance tuning
Nice=-5
IOSchedulingClass=realtime
IOSchedulingPriority=0

# Keep connections alive
Environment="PYTHONUNBUFFERED=1"

# TCP keepalive settings via sysctl wrapper
ExecStartPre=/bin/sh -c 'sysctl -w net.ipv4.tcp_keepalive_time=60 2>/dev/null || true'
ExecStartPre=/bin/sh -c 'sysctl -w net.ipv4.tcp_keepalive_intvl=10 2>/dev/null || true'
ExecStartPre=/bin/sh -c 'sysctl -w net.ipv4.tcp_keepalive_probes=6 2>/dev/null || true'

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
    
    # Use domain if available, otherwise IP
    local server="$ip"
    if [[ -n "$domain" && "$domain" != "none" ]]; then
        server="$domain"
    fi
    
    # Encode TLS domain to hex for fake-TLS secrets
    local tls_domain_hex=""
    if [[ -n "$tls_domain" ]]; then
        if command -v xxd &>/dev/null; then
            tls_domain_hex=$(printf '%s' "$tls_domain" | xxd -p | tr -d '\n')
        else
            tls_domain_hex=$(printf '%s' "$tls_domain" | od -An -tx1 | tr -d ' \n')
        fi
    fi
    
    for user in "${users[@]}"; do
        IFS=':' read -r name raw_secret mode <<< "$user"
        
        echo -e "  ${BOLD}${CYAN}━━━ User: $name ━━━${RESET}"
        echo ""
        
        # Clean the secret (remove any existing prefix)
        local clean_secret="${raw_secret#ee}"
        clean_secret="${clean_secret#dd}"
        clean_secret="${clean_secret:0:32}"
        
        # Build both secrets
        local dd_secret="dd${clean_secret}"
        local ee_secret="ee${clean_secret}${tls_domain_hex}"
        
        # Secure mode link (dd)
        echo -e "  ${WHITE}Secure Mode (dd)${RESET} ${GRAY}- Random padding, harder to detect${RESET}"
        echo -e "  ${GREEN}tg://proxy?server=${server}&port=${port}&secret=${dd_secret}${RESET}"
        echo ""
        
        # Fake-TLS mode link (ee)
        echo -e "  ${WHITE}Fake-TLS Mode (ee)${RESET} ${GRAY}- Looks like HTTPS to ${tls_domain}${RESET}"
        echo -e "  ${GREEN}tg://proxy?server=${server}&port=${port}&secret=${ee_secret}${RESET}"
        echo ""
        
        print_line
        echo ""
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
    echo -e "  ${BOLD}${WHITE}🚀 INSTALL${RESET}"
    print_line
    echo ""
    
    # Get public IP
    PUBLIC_IP=$(get_public_ip)
    if [[ -z "$PUBLIC_IP" ]]; then
        get_input "Server IP" "" PUBLIC_IP
    else
        echo -e "  IP: ${WHITE}$PUBLIC_IP${RESET}"
    fi
    echo ""
    
    # Port
    local default_port="443"
    if ! check_port_available 443; then
        default_port="8443"
    fi
    get_input "Port" "$default_port" PROXY_PORT
    echo ""
    
    # Domain (optional)
    get_input "Domain (optional, press enter to skip)" "" PROXY_DOMAIN
    if [[ -z "$PROXY_DOMAIN" ]]; then
        PROXY_DOMAIN="none"
    else
        PROXY_DOMAIN=$(echo "$PROXY_DOMAIN" | sed 's|https\?://||' | sed 's|/.*||')
    fi
    echo ""
    
    # Fake-TLS domain
    get_input "Fake-TLS domain (traffic disguise)" "google.com" TLS_DOMAIN
    echo ""
    
    # First user
    get_input "First username" "user1" username
    local secret=$(generate_secret)
    declare -a USERS
    USERS+=("${username}:${secret}:tls")
    echo ""
    
    # Install
    print_step "Installing..."
    install_dependencies
    clone_mtprotoproxy
    configure_network_keepalive
    create_stats_collector
    
    local PROXY_MODE="tls"
    local RANDOM_PADDING="yes"
    
    create_config "$PROXY_PORT" "$TLS_DOMAIN" "$PROXY_MODE" "$RANDOM_PADDING" "${USERS[@]}"
    create_service
    create_stats_service
    save_proxy_data "$PUBLIC_IP" "$PROXY_DOMAIN" "$PROXY_PORT" "$PROXY_MODE" "$TLS_DOMAIN" "$RANDOM_PADDING" "${USERS[@]}"
    
    if start_service; then
        echo ""
        print_success "Installed!"
        echo ""
        
        # Use domain if available
        local server="$PUBLIC_IP"
        if [[ -n "$PROXY_DOMAIN" && "$PROXY_DOMAIN" != "none" ]]; then
            server="$PROXY_DOMAIN"
        fi
        
        local tls_domain_hex=$(printf '%s' "$TLS_DOMAIN" | xxd -p | tr -d '\n')
        
        echo -e "  ${BOLD}Your proxy link:${RESET}"
        echo -e "  ${GREEN}tg://proxy?server=${server}&port=${PROXY_PORT}&secret=ee${secret}${tls_domain_hex}${RESET}"
        echo ""
        
        print_line
        echo ""
        echo -e "  ${BOLD}${YELLOW}⚠️  IMPORTANT:${RESET}"
        echo ""
        echo -e "  ${WHITE}1. Firewall:${RESET} Open port ${CYAN}$PROXY_PORT${RESET} in your cloud provider"
        if [[ -n "$PROXY_DOMAIN" && "$PROXY_DOMAIN" != "none" ]]; then
            echo -e "  ${WHITE}2. DNS:${RESET} Point ${CYAN}$PROXY_DOMAIN${RESET} → ${CYAN}$PUBLIC_IP${RESET}"
        fi
        echo ""
    fi
    
    press_enter
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
    
    # Use domain if available, otherwise IP
    local server="$PROXY_IP"
    if [[ -n "$PROXY_DOMAIN" && "$PROXY_DOMAIN" != "none" ]]; then
        server="$PROXY_DOMAIN"
    fi
    
    # Build secrets for display
    local tls_domain_hex=""
    if [[ -n "$TLS_DOMAIN" ]]; then
        tls_domain_hex=$(printf '%s' "$TLS_DOMAIN" | xxd -p | tr -d '\n')
    fi
    
    local dd_secret="dd${secret}"
    local ee_secret="ee${secret}${tls_domain_hex}"
    
    # Show links for new user
    echo -e "  ${WHITE}Secure Mode (dd)${RESET} ${GRAY}- Random padding, harder to detect${RESET}"
    echo -e "  ${GREEN}tg://proxy?server=${server}&port=${PROXY_PORT}&secret=${dd_secret}${RESET}"
    echo ""
    
    echo -e "  ${WHITE}Fake-TLS Mode (ee)${RESET} ${GRAY}- Looks like HTTPS to ${TLS_DOMAIN}${RESET}"
    echo -e "  ${GREEN}tg://proxy?server=${server}&port=${PROXY_PORT}&secret=${ee_secret}${RESET}"
    
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
    echo -e "  • Stats collector service"
    echo -e "  • All configuration"
    echo -e "  • All user data and statistics"
    echo ""
    
    if confirm "Are you sure you want to uninstall?"; then
        echo ""
        print_step "Stopping services..."
        systemctl stop telegram-proxy-stats 2>/dev/null || true
        systemctl disable telegram-proxy-stats 2>/dev/null || true
        rm -f /etc/systemd/system/telegram-proxy-stats.service 2>/dev/null || true
        
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        
        # Wait for port to be released
        sleep 2
        
        print_step "Removing files..."
        rm -f "$SERVICE_FILE"
        rm -rf "$INSTALL_DIR"
        rm -f /etc/sysctl.d/99-telegram-proxy.conf 2>/dev/null || true
        
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
                echo -e "  Status: ${GREEN}● Running${RESET}"
            else
                echo -e "  Status: ${RED}● Stopped${RESET}"
            fi
            
            if [[ -f "$DATA_FILE" ]]; then
                source "$DATA_FILE"
                echo -e "  Server: ${WHITE}${PROXY_DOMAIN:-$PROXY_IP}:$PROXY_PORT${RESET}"
                echo -e "  Users: ${WHITE}${#PROXY_USERS[@]}${RESET}"
                
                # Check for IP change
                local new_ip
                new_ip=$(check_ip_changed)
                if [[ $? -eq 0 ]]; then
                    echo ""
                    echo -e "  ${RED}⚠️  IP CHANGED: $PROXY_IP → $new_ip${RESET}"
                fi
            fi
        else
            echo -e "  Status: ${YELLOW}● Not installed${RESET}"
        fi
        
        echo ""
        print_line
        echo ""
        
        if is_installed; then
            echo -e "  ${CYAN}1)${RESET} Proxy Links & Users"
            echo -e "  ${CYAN}2)${RESET} Statistics & Monitoring"
            echo -e "  ${CYAN}3)${RESET} Status & Restart"
            echo -e "  ${CYAN}4)${RESET} View Logs"
            echo -e "  ${CYAN}5)${RESET} Update IP"
            echo -e "  ${RED}6)${RESET} Uninstall"
        else
            echo -e "  ${CYAN}1)${RESET} Install Proxy"
        fi
        
        echo -e "  ${CYAN}0)${RESET} Exit"
        echo ""
        
        get_input "Select" "" choice
        
        if is_installed; then
            case $choice in
                1) manage_users ;;
                2) stats_menu ;;
                3) status_menu ;;
                4) view_logs ;;
                5) update_ip ;;
                6) uninstall_proxy ;;
                0) echo ""; exit 0 ;;
                *) print_error "Invalid option" ;;
            esac
        else
            case $choice in
                1) install_proxy ;;
                0) echo ""; exit 0 ;;
                *) print_error "Invalid option" ;;
            esac
        fi
    done
}

# Combined users management
manage_users() {
    while true; do
        print_banner
        source "$DATA_FILE" 2>/dev/null
        
        # Use domain if available
        local server="$PROXY_IP"
        if [[ -n "$PROXY_DOMAIN" && "$PROXY_DOMAIN" != "none" ]]; then
            server="$PROXY_DOMAIN"
        fi
        
        # Encode TLS domain
        local tls_domain_hex=""
        if [[ -n "$TLS_DOMAIN" ]]; then
            tls_domain_hex=$(printf '%s' "$TLS_DOMAIN" | xxd -p | tr -d '\n')
        fi
        
        echo -e "  ${BOLD}${WHITE}🔗 PROXY LINKS${RESET}"
        print_line
        echo ""
        
        for user in "${PROXY_USERS[@]}"; do
            IFS=':' read -r name raw_secret mode <<< "$user"
            local clean_secret="${raw_secret#ee}"
            clean_secret="${clean_secret#dd}"
            clean_secret="${clean_secret:0:32}"
            
            echo -e "  ${CYAN}$name${RESET}"
            echo -e "  ${GRAY}dd (secure):${RESET} tg://proxy?server=${server}&port=${PROXY_PORT}&secret=dd${clean_secret}"
            echo -e "  ${GRAY}ee (fake-tls):${RESET} tg://proxy?server=${server}&port=${PROXY_PORT}&secret=ee${clean_secret}${tls_domain_hex}"
            echo ""
        done
        
        print_line
        echo ""
        echo -e "  ${CYAN}1)${RESET} Add User"
        echo -e "  ${CYAN}0)${RESET} Back"
        echo ""
        
        get_input "Select" "" choice
        
        case $choice in
            1) add_user_simple ;;
            0) return ;;
            *) ;;
        esac
    done
}

# Simplified add user
add_user_simple() {
    echo ""
    source "$DATA_FILE"
    
    get_input "Username" "" username
    
    if [[ -z "$username" ]]; then
        print_error "Username required"
        press_enter
        return
    fi
    
    # Check duplicate
    for existing_user in "${PROXY_USERS[@]}"; do
        IFS=':' read -r existing_name _ _ <<< "$existing_user"
        if [[ "$existing_name" == "$username" ]]; then
            print_error "User '$username' already exists"
            press_enter
            return
        fi
    done
    
    local secret=$(generate_secret)
    local new_user="${username}:${secret}:${PROXY_MODE:-tls}"
    
    # Add to config
    awk -v user="$username" -v secret="$secret" '
        /^USERS = \{/ { in_users=1 }
        in_users && /^\}$/ {
            print "    \"" user "\": \"" secret "\","
            in_users=0
        }
        { print }
    ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    PROXY_USERS+=("$new_user")
    save_proxy_data "$PROXY_IP" "$PROXY_DOMAIN" "$PROXY_PORT" "$PROXY_MODE" "$TLS_DOMAIN" "$RANDOM_PADDING" "${PROXY_USERS[@]}"
    
    systemctl restart "$SERVICE_NAME"
    print_success "User '$username' added"
    sleep 1
}

# Statistics menu
stats_menu() {
    while true; do
        print_banner
        echo -e "  ${BOLD}${WHITE}📊 STATISTICS & MONITORING${RESET}"
        print_line
        echo ""
        
        # Quick stats preview
        if [[ -f "$STATS_FILE" ]]; then
            local stats=$(cat "$STATS_FILE" 2>/dev/null)
            local current_conns=$(echo "$stats" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('current_connections', 0))" 2>/dev/null || echo "0")
            local total_bytes=$(echo "$stats" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('total_bytes_in', 0) + d.get('total_bytes_out', 0))" 2>/dev/null || echo "0")
            
            echo -e "  Active Connections: ${GREEN}${current_conns}${RESET}"
            echo -e "  Total Transfer: $(format_bytes ${total_bytes})"
            echo ""
        fi
        
        print_line
        echo ""
        echo -e "  ${CYAN}1)${RESET} View Full Statistics"
        echo -e "  ${CYAN}2)${RESET} Live Monitor (auto-refresh)"
        echo -e "  ${CYAN}3)${RESET} User Statistics"
        echo -e "  ${CYAN}4)${RESET} Reset Statistics"
        echo -e "  ${CYAN}0)${RESET} Back"
        echo ""
        
        get_input "Select" "" choice
        
        case $choice in
            1) show_stats ;;
            2) show_live_stats ;;
            3) show_user_stats ;;
            4) reset_stats ;;
            0) return ;;
            *) print_error "Invalid option" ;;
        esac
    done
}

# Detailed user statistics
show_user_stats() {
    print_banner
    echo -e "  ${BOLD}${WHITE}👥 USER STATISTICS${RESET}"
    print_line
    echo ""
    
    # Update stats first
    python3 "$STATS_COLLECTOR" update > /dev/null 2>&1
    
    if [[ ! -f "$STATS_FILE" ]]; then
        print_warning "No statistics available yet"
        press_enter
        return
    fi
    
    local stats=$(cat "$STATS_FILE")
    
    # Get detailed user list
    echo "$stats" | python3 -c "
import sys, json
from datetime import datetime

d = json.load(sys.stdin)
users = d.get('users', {})

if not users:
    print('  No user data available yet')
else:
    for name, data in sorted(users.items()):
        bytes_in = data.get('bytes_in', 0)
        bytes_out = data.get('bytes_out', 0)
        total_conns = data.get('total_connections', 0)
        current_conns = data.get('current_connections', 0)
        last_seen = data.get('last_seen')
        first_seen = data.get('first_seen')
        
        def format_bytes(b):
            if b >= 1073741824:
                return f'{b/1073741824:.2f} GB'
            elif b >= 1048576:
                return f'{b/1048576:.2f} MB'
            elif b >= 1024:
                return f'{b/1024:.2f} KB'
            return f'{b} B'
        
        def format_time(ts):
            if not ts:
                return 'Never'
            try:
                return datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M:%S')
            except:
                return 'Unknown'
        
        status = '🟢 Online' if current_conns > 0 else '⚪ Offline'
        
        print(f'  ┌─────────────────────────────────────────────┐')
        print(f'  │  User: {name:<36} │')
        print(f'  ├─────────────────────────────────────────────┤')
        print(f'  │  Status:      {status:<28} │')
        print(f'  │  Active Conn: {current_conns:<28} │')
        print(f'  │  Total Conn:  {total_conns:<28} │')
        print(f'  │  Downloaded:  {format_bytes(bytes_in):<28} │')
        print(f'  │  Uploaded:    {format_bytes(bytes_out):<28} │')
        print(f'  │  Total:       {format_bytes(bytes_in + bytes_out):<28} │')
        print(f'  │  First Seen:  {format_time(first_seen):<28} │')
        print(f'  │  Last Active: {format_time(last_seen):<28} │')
        print(f'  └─────────────────────────────────────────────┘')
        print()
" 2>/dev/null
    
    press_enter
}

# Reset statistics
reset_stats() {
    print_banner
    echo -e "  ${BOLD}${WHITE}🗑️  RESET STATISTICS${RESET}"
    print_line
    echo ""
    
    print_warning "This will reset all connection and usage statistics."
    print_info "Proxy links and configuration will NOT be affected."
    echo ""
    
    if confirm "Reset all statistics?" "n"; then
        rm -f "$STATS_FILE" 2>/dev/null
        systemctl restart telegram-proxy-stats 2>/dev/null || true
        print_success "Statistics reset"
    else
        print_info "Cancelled"
    fi
    
    press_enter
}

# Status submenu
status_menu() {
    print_banner
    echo -e "  ${BOLD}${WHITE}📊 STATUS${RESET}"
    print_line
    echo ""
    
    systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null | head -15 | sed 's/^/  /'
    
    echo ""
    print_line
    echo ""
    echo -e "  ${CYAN}1)${RESET} Restart Proxy"
    echo -e "  ${CYAN}2)${RESET} Optimize & Fix Disconnections"
    echo -e "  ${CYAN}0)${RESET} Back"
    echo ""
    
    get_input "Select" "" choice
    
    case "$choice" in
        1)
            systemctl restart "$SERVICE_NAME"
            sleep 2
            if systemctl is-active --quiet "$SERVICE_NAME"; then
                print_success "Restarted"
            else
                print_error "Failed to restart"
            fi
            press_enter
            ;;
        2)
            optimize_proxy
            ;;
    esac
}

# Optimize proxy for better stability
optimize_proxy() {
    print_banner
    echo -e "  ${BOLD}${WHITE}🔧 OPTIMIZING PROXY${RESET}"
    print_line
    echo ""
    
    print_info "This will apply network optimizations and update the service"
    print_info "to fix intermittent disconnection issues."
    echo ""
    
    if ! confirm "Continue with optimization?" "y"; then
        return
    fi
    
    echo ""
    
    # Apply network keepalive settings
    configure_network_keepalive
    
    # Update systemd service with better settings
    print_step "Updating service configuration..."
    
    # Stop service first
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    
    # Recreate service with improved settings
    tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Telegram MTProto Proxy (Fake-TLS)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 -u $INSTALL_DIR/mtprotoproxy.py
Restart=always
RestartSec=3
User=root
LimitNOFILE=65536

# Watchdog - restart if service becomes unresponsive
WatchdogSec=60
NotifyAccess=all

# Memory management - restart if using too much memory
MemoryMax=512M
MemoryHigh=384M

# Performance tuning
Nice=-5
IOSchedulingClass=realtime
IOSchedulingPriority=0

# Keep connections alive
Environment="PYTHONUNBUFFERED=1"

# TCP keepalive settings via sysctl wrapper
ExecStartPre=/bin/sh -c 'sysctl -w net.ipv4.tcp_keepalive_time=60 2>/dev/null || true'
ExecStartPre=/bin/sh -c 'sysctl -w net.ipv4.tcp_keepalive_intvl=10 2>/dev/null || true'
ExecStartPre=/bin/sh -c 'sysctl -w net.ipv4.tcp_keepalive_probes=6 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    print_success "Service configuration updated"
    
    # Try to install performance modules for mtprotoproxy
    print_step "Installing performance optimizations..."
    pip3 install -q cryptography uvloop 2>/dev/null || true
    print_success "Performance modules installed"
    
    # Start service
    print_step "Starting optimized proxy..."
    systemctl start "$SERVICE_NAME"
    sleep 3
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo ""
        print_success "Proxy optimized and running!"
        echo ""
        echo -e "  ${GREEN}✓${RESET} TCP keepalive configured (60s)"
        echo -e "  ${GREEN}✓${RESET} Automatic restart on failure"
        echo -e "  ${GREEN}✓${RESET} Memory limits set (512MB max)"
        echo -e "  ${GREEN}✓${RESET} Network buffers optimized"
        echo -e "  ${GREEN}✓${RESET} Performance modules installed"
        echo ""
        print_info "The proxy should now be more stable!"
    else
        print_error "Failed to start proxy"
        echo ""
        journalctl -u "$SERVICE_NAME" -n 10 --no-pager
    fi
    
    # Also setup stats if not already done
    if [[ ! -f "$STATS_COLLECTOR" ]]; then
        echo ""
        print_step "Setting up statistics collector..."
        create_stats_collector
        create_stats_service
        
        # Update config to enable stats
        if ! grep -q "STATS_PORT" "$CONFIG_FILE" 2>/dev/null; then
            echo "" >> "$CONFIG_FILE"
            echo "# Stats - enable Prometheus metrics on localhost" >> "$CONFIG_FILE"
            echo "STATS_HOST = \"127.0.0.1\"" >> "$CONFIG_FILE"
            echo "STATS_PORT = $STATS_PORT" >> "$CONFIG_FILE"
            systemctl restart "$SERVICE_NAME"
        fi
        
        echo -e "  ${GREEN}✓${RESET} Statistics collector enabled"
    fi
    
    press_enter
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
