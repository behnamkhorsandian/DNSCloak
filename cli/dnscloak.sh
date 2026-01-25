#!/bin/bash
#===============================================================================
# DNSCloak - Unified Management CLI
# https://github.com/behnamkhorsandian/DNSCloak
#
# Usage: dnscloak <command> [service] [options]
#
# Commands:
#   add <service> <username>     - Add user to service
#   remove <service> <username>  - Remove user from service
#   list [service]               - List users (optionally filter by service)
#   links <username> [service]   - Show connection links for user
#   status [service]             - Show service status
#   restart <service>            - Restart a service
#   uninstall <service>          - Uninstall a service
#   services                     - List installed services
#   install <service>            - Install a new service
#   help                         - Show this help
#
# Services: reality, ws, wg, dnstt, mtp, vray
#===============================================================================

set -e

# Paths
DNSCLOAK_DIR="/opt/dnscloak"
DNSCLOAK_USERS="$DNSCLOAK_DIR/users.json"
LIB_DIR="$DNSCLOAK_DIR/lib"
GITHUB_RAW="https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main"

# Version
VERSION="2.0.0"

#-------------------------------------------------------------------------------
# Source Libraries
#-------------------------------------------------------------------------------

source_libs() {
    if [[ -f "$LIB_DIR/common.sh" ]]; then
        source "$LIB_DIR/common.sh"
        source "$LIB_DIR/cloud.sh"
        source "$LIB_DIR/xray.sh" 2>/dev/null || true
    else
        # Download libs if not available
        mkdir -p "$LIB_DIR"
        curl -sL "$GITHUB_RAW/lib/common.sh" -o "$LIB_DIR/common.sh"
        curl -sL "$GITHUB_RAW/lib/cloud.sh" -o "$LIB_DIR/cloud.sh"
        curl -sL "$GITHUB_RAW/lib/xray.sh" -o "$LIB_DIR/xray.sh"
        source "$LIB_DIR/common.sh"
        source "$LIB_DIR/cloud.sh"
        source "$LIB_DIR/xray.sh" 2>/dev/null || true
    fi
}

#-------------------------------------------------------------------------------
# Colors (if not already loaded)
#-------------------------------------------------------------------------------

if [[ -z "$RED" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    GRAY='\033[0;90m'
    RESET='\033[0m'
    BOLD='\033[1m'
fi

#-------------------------------------------------------------------------------
# Utility Functions
#-------------------------------------------------------------------------------

error() {
    echo -e "${RED}Error:${RESET} $1" >&2
    exit 1
}

info() {
    echo -e "${BLUE}[*]${RESET} $1"
}

success() {
    echo -e "${GREEN}[+]${RESET} $1"
}

warn() {
    echo -e "${YELLOW}[!]${RESET} $1"
}

#-------------------------------------------------------------------------------
# Validation
#-------------------------------------------------------------------------------

require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This command requires root privileges. Use: sudo dnscloak $*"
    fi
}

validate_service() {
    local service="$1"
    local valid_services="reality ws wg dnstt mtp vray"
    
    if [[ ! " $valid_services " =~ " $service " ]]; then
        error "Unknown service: $service. Valid services: $valid_services"
    fi
}

#-------------------------------------------------------------------------------
# Service Detection
#-------------------------------------------------------------------------------

is_service_installed() {
    local service="$1"
    case "$service" in
        reality)
            [[ -f "$DNSCLOAK_DIR/xray/config.json" ]] && \
            grep -q '"tag": "reality-in"' "$DNSCLOAK_DIR/xray/config.json" 2>/dev/null
            ;;
        ws)
            [[ -f "$DNSCLOAK_DIR/xray/config.json" ]] && \
            grep -q '"tag": "ws-in"' "$DNSCLOAK_DIR/xray/config.json" 2>/dev/null
            ;;
        vray)
            [[ -f "$DNSCLOAK_DIR/xray/config.json" ]] && \
            grep -q '"tag": "vray-in"' "$DNSCLOAK_DIR/xray/config.json" 2>/dev/null
            ;;
        wg)
            [[ -f "$DNSCLOAK_DIR/wg/wg0.conf" ]]
            ;;
        dnstt)
            [[ -f "$DNSCLOAK_DIR/dnstt/server.key" ]]
            ;;
        mtp)
            [[ -f "$DNSCLOAK_DIR/mtp/config.py" ]] || systemctl is-active --quiet mtprotoproxy 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

get_installed_services() {
    local installed=""
    for svc in reality ws wg dnstt mtp vray; do
        if is_service_installed "$svc"; then
            installed="$installed $svc"
        fi
    done
    echo "$installed" | xargs
}

#-------------------------------------------------------------------------------
# User Management Helpers
#-------------------------------------------------------------------------------

# Generic add user function - routes to service-specific handler
add_user() {
    local service="$1"
    local username="$2"
    
    if [[ -z "$username" ]]; then
        error "Username required. Usage: dnscloak add $service <username>"
    fi
    
    if ! is_service_installed "$service"; then
        error "Service '$service' is not installed. Install it first: dnscloak install $service"
    fi
    
    case "$service" in
        reality)
            add_reality_user "$username"
            ;;
        ws)
            add_ws_user "$username"
            ;;
        wg)
            add_wg_user "$username"
            ;;
        dnstt)
            add_dnstt_user "$username"
            ;;
        *)
            error "Add user not implemented for service: $service"
            ;;
    esac
}

# Generic remove user function
remove_user() {
    local service="$1"
    local username="$2"
    
    if [[ -z "$username" ]]; then
        error "Username required. Usage: dnscloak remove $service <username>"
    fi
    
    if ! is_service_installed "$service"; then
        error "Service '$service' is not installed"
    fi
    
    case "$service" in
        reality)
            remove_reality_user "$username"
            ;;
        ws)
            remove_ws_user "$username"
            ;;
        wg)
            remove_wg_user "$username"
            ;;
        dnstt)
            remove_dnstt_user "$username"
            ;;
        *)
            error "Remove user not implemented for service: $service"
            ;;
    esac
}

#-------------------------------------------------------------------------------
# Service-Specific User Functions
#-------------------------------------------------------------------------------

# Reality
add_reality_user() {
    local username="$1"
    source_libs
    
    if user_exists "$username" "reality"; then
        error "User '$username' already exists in Reality"
    fi
    
    local uuid
    uuid=$(random_uuid)
    
    xray_add_client "reality-in" "$uuid" "${username}@dnscloak" "xtls-rprx-vision"
    user_add "$username" "reality" "{\"uuid\": \"$uuid\", \"flow\": \"xtls-rprx-vision\"}"
    xray_reload
    
    success "User '$username' added to Reality"
    echo ""
    show_reality_links "$username"
}

remove_reality_user() {
    local username="$1"
    source_libs
    
    if ! user_exists "$username" "reality"; then
        error "User '$username' not found in Reality"
    fi
    
    xray_remove_client "reality-in" "${username}@dnscloak"
    user_remove "$username" "reality"
    xray_reload
    
    success "User '$username' removed from Reality"
}

show_reality_links() {
    local username="$1"
    source_libs
    
    local uuid server_address pubkey target sid
    uuid=$(user_get "$username" "reality" "uuid")
    server_address=$(server_get "reality_address")
    [[ -z "$server_address" || "$server_address" == "null" ]] && server_address=$(server_get "ip")
    pubkey=$(server_get "reality_public_key")
    target=$(server_get "reality_target")
    sid=$(server_get "reality_short_id")
    
    local link
    link="vless://${uuid}@${server_address}:443?type=tcp&security=reality&pbk=${pubkey}&fp=chrome&sni=${target}&sid=${sid}&flow=xtls-rprx-vision#${username}"
    
    echo -e "${BOLD}Reality Link for '$username'${RESET}"
    echo "================================================"
    echo ""
    echo -e "${CYAN}$link${RESET}"
    echo ""
    
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$link"
    fi
}

# WebSocket
add_ws_user() {
    local username="$1"
    source_libs
    
    if user_exists "$username" "ws"; then
        error "User '$username' already exists in WS"
    fi
    
    local uuid
    uuid=$(random_uuid)
    
    xray_add_client "ws-in" "$uuid" "${username}@dnscloak"
    user_add "$username" "ws" "{\"uuid\": \"$uuid\"}"
    xray_reload
    
    success "User '$username' added to WS+CDN"
    echo ""
    show_ws_links "$username"
}

remove_ws_user() {
    local username="$1"
    source_libs
    
    if ! user_exists "$username" "ws"; then
        error "User '$username' not found in WS"
    fi
    
    xray_remove_client "ws-in" "${username}@dnscloak"
    user_remove "$username" "ws"
    xray_reload
    
    success "User '$username' removed from WS+CDN"
}

show_ws_links() {
    local username="$1"
    source_libs
    
    local uuid domain path
    uuid=$(user_get "$username" "ws" "uuid")
    domain=$(server_get "ws_domain")
    path=$(server_get "ws_path")
    
    local link
    link="vless://${uuid}@${domain}:443?type=ws&security=tls&path=${path}&host=${domain}&sni=${domain}#${username}"
    
    echo -e "${BOLD}WS+CDN Link for '$username'${RESET}"
    echo "================================================"
    echo ""
    echo -e "${CYAN}$link${RESET}"
    echo ""
    
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$link"
    fi
}

# WireGuard
add_wg_user() {
    local username="$1"
    source_libs
    
    if user_exists "$username" "wg"; then
        error "User '$username' already exists in WireGuard"
    fi
    
    # WireGuard needs full installer for keygen
    if [[ -f "$DNSCLOAK_DIR/wg/server.pub" ]]; then
        local server_pub
        server_pub=$(cat "$DNSCLOAK_DIR/wg/server.pub")
    else
        error "WireGuard server keys not found. Reinstall WireGuard."
    fi
    
    local client_priv client_pub psk client_ip
    client_priv=$(wg genkey)
    client_pub=$(echo "$client_priv" | wg pubkey)
    psk=$(wg genpsk)
    
    # Get next IP
    local last_octet=1
    local ips
    ips=$(jq -r '.users[].protocols.wg.ip // empty' "$DNSCLOAK_USERS" 2>/dev/null | sort -t. -k4 -n | tail -1)
    if [[ -n "$ips" ]]; then
        last_octet=$(echo "$ips" | cut -d. -f4)
    fi
    ((last_octet++))
    client_ip="10.66.66.${last_octet}"
    
    # Create client config
    local server_ip wg_port
    server_ip=$(server_get "ip")
    wg_port=$(server_get "wg_port")
    [[ -z "$wg_port" ]] && wg_port=51820
    
    mkdir -p "$DNSCLOAK_DIR/wg/peers"
    cat > "$DNSCLOAK_DIR/wg/peers/${username}.conf" <<EOF
[Interface]
PrivateKey = ${client_priv}
Address = ${client_ip}/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = ${server_pub}
PresharedKey = ${psk}
Endpoint = ${server_ip}:${wg_port}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
    chmod 600 "$DNSCLOAK_DIR/wg/peers/${username}.conf"
    
    # Add peer to server
    cat >> "$DNSCLOAK_DIR/wg/wg0.conf" <<EOF

# ${username}
[Peer]
PublicKey = ${client_pub}
PresharedKey = ${psk}
AllowedIPs = ${client_ip}/32
EOF

    # Save to users.json
    user_add "$username" "wg" "{\"public_key\": \"$client_pub\", \"psk\": \"$psk\", \"ip\": \"$client_ip\", \"private_key\": \"$client_priv\"}"
    
    # Reload WireGuard
    wg syncconf wg0 <(wg-quick strip "$DNSCLOAK_DIR/wg/wg0.conf") 2>/dev/null || \
    systemctl restart wg-quick@wg0
    
    success "User '$username' added to WireGuard"
    echo ""
    show_wg_links "$username"
}

remove_wg_user() {
    local username="$1"
    source_libs
    
    if ! user_exists "$username" "wg"; then
        error "User '$username' not found in WireGuard"
    fi
    
    local pub_key
    pub_key=$(user_get "$username" "wg" "public_key")
    
    # Remove peer from running config
    wg set wg0 peer "$pub_key" remove 2>/dev/null || true
    
    # Regenerate config file
    regenerate_wg_config "$username"
    
    # Remove client config
    rm -f "$DNSCLOAK_DIR/wg/peers/${username}.conf"
    
    # Remove from users.json
    user_remove "$username" "wg"
    
    success "User '$username' removed from WireGuard"
}

regenerate_wg_config() {
    local exclude_user="$1"
    local server_priv
    server_priv=$(cat "$DNSCLOAK_DIR/wg/server.key" 2>/dev/null)
    local main_iface
    main_iface=$(ip route | grep default | awk '{print $5}' | head -1)
    
    cat > "$DNSCLOAK_DIR/wg/wg0.conf" <<EOF
# DNSCloak WireGuard Configuration
# Regenerated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = ${server_priv}

PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${main_iface} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${main_iface} -j MASQUERADE
EOF

    local users
    users=$(user_list "wg")
    
    while IFS= read -r uname; do
        [[ -z "$uname" ]] && continue
        [[ "$uname" == "$exclude_user" ]] && continue
        
        local pub_key psk client_ip
        pub_key=$(user_get "$uname" "wg" "public_key")
        psk=$(user_get "$uname" "wg" "psk")
        client_ip=$(user_get "$uname" "wg" "ip")
        
        cat >> "$DNSCLOAK_DIR/wg/wg0.conf" <<EOF

# ${uname}
[Peer]
PublicKey = ${pub_key}
PresharedKey = ${psk}
AllowedIPs = ${client_ip}/32
EOF
    done <<< "$users"
    
    chmod 600 "$DNSCLOAK_DIR/wg/wg0.conf"
}

show_wg_links() {
    local username="$1"
    source_libs
    
    local conf_file="$DNSCLOAK_DIR/wg/peers/${username}.conf"
    
    if [[ ! -f "$conf_file" ]]; then
        error "Config file not found for '$username'"
    fi
    
    echo -e "${BOLD}WireGuard Config for '$username'${RESET}"
    echo "================================================"
    echo ""
    cat "$conf_file"
    echo ""
    
    if command -v qrencode &>/dev/null; then
        echo "QR Code:"
        qrencode -t ANSIUTF8 < "$conf_file"
    fi
}

# DNSTT
add_dnstt_user() {
    local username="$1"
    source_libs
    
    if user_exists "$username" "dnstt"; then
        error "User '$username' already exists in DNSTT"
    fi
    
    local token
    token=$(head -c 16 /dev/urandom | xxd -p)
    
    user_add "$username" "dnstt" "{\"token\": \"$token\"}"
    
    success "User '$username' added to DNSTT"
    echo ""
    show_dnstt_links "$username"
}

remove_dnstt_user() {
    local username="$1"
    source_libs
    
    if ! user_exists "$username" "dnstt"; then
        error "User '$username' not found in DNSTT"
    fi
    
    user_remove "$username" "dnstt"
    success "User '$username' removed from DNSTT"
}

show_dnstt_links() {
    local username="$1"
    source_libs
    
    local pubkey ns_domain
    pubkey=$(cat "$DNSCLOAK_DIR/dnstt/server.pub" 2>/dev/null)
    ns_domain=$(server_get "dnstt_domain")
    
    echo -e "${BOLD}DNSTT Setup for '$username'${RESET}"
    echo "================================================"
    echo ""
    echo "Public Key: $pubkey"
    echo "NS Domain: $ns_domain"
    echo ""
    echo "Client setup: https://dnstt.dnscloak.net/client?key=${pubkey}&domain=${ns_domain}"
}

#-------------------------------------------------------------------------------
# List Functions
#-------------------------------------------------------------------------------

list_users() {
    local service="$1"
    source_libs
    
    echo ""
    if [[ -n "$service" ]]; then
        echo -e "${BOLD}Users for $service${RESET}"
        echo "================================================"
        local users
        users=$(user_list "$service")
        if [[ -z "$users" ]]; then
            echo "  No users"
        else
            echo "$users" | while read -r u; do
                echo "  - $u"
            done
        fi
    else
        echo -e "${BOLD}All Users${RESET}"
        echo "================================================"
        
        if [[ ! -f "$DNSCLOAK_USERS" ]]; then
            echo "  No users configured"
            return
        fi
        
        jq -r '.users | to_entries[] | "\(.key): \(.value.protocols | keys | join(", "))"' \
            "$DNSCLOAK_USERS" 2>/dev/null | while read -r line; do
            echo "  $line"
        done
    fi
    echo ""
}

#-------------------------------------------------------------------------------
# Show Links
#-------------------------------------------------------------------------------

show_links() {
    local username="$1"
    local service="$2"
    source_libs
    
    if [[ -z "$username" ]]; then
        error "Username required. Usage: dnscloak links <username> [service]"
    fi
    
    if [[ -n "$service" ]]; then
        case "$service" in
            reality) show_reality_links "$username" ;;
            ws) show_ws_links "$username" ;;
            wg) show_wg_links "$username" ;;
            dnstt) show_dnstt_links "$username" ;;
            *) error "Links not implemented for service: $service" ;;
        esac
    else
        # Show links for all services user is in
        for svc in reality ws wg dnstt; do
            if user_exists "$username" "$svc"; then
                echo ""
                case "$svc" in
                    reality) show_reality_links "$username" ;;
                    ws) show_ws_links "$username" ;;
                    wg) show_wg_links "$username" ;;
                    dnstt) show_dnstt_links "$username" ;;
                esac
            fi
        done
    fi
}

#-------------------------------------------------------------------------------
# Status Functions
#-------------------------------------------------------------------------------

show_status() {
    local service="$1"
    
    echo ""
    if [[ -n "$service" ]]; then
        validate_service "$service"
        show_service_status "$service"
    else
        echo -e "${BOLD}DNSCloak Services Status${RESET}"
        echo "================================================"
        echo ""
        for svc in reality ws wg dnstt mtp vray; do
            local status_icon status_text
            if is_service_installed "$svc"; then
                status_icon="${GREEN}[+]${RESET}"
                status_text="installed"
                
                # Check if running
                case "$svc" in
                    reality|ws|vray)
                        if systemctl is-active --quiet xray 2>/dev/null; then
                            status_text="running"
                        fi
                        ;;
                    wg)
                        if systemctl is-active --quiet wg-quick@wg0 2>/dev/null; then
                            status_text="running"
                        fi
                        ;;
                    dnstt)
                        if systemctl is-active --quiet dnstt 2>/dev/null; then
                            status_text="running"
                        fi
                        ;;
                    mtp)
                        if systemctl is-active --quiet mtprotoproxy 2>/dev/null; then
                            status_text="running"
                        fi
                        ;;
                esac
                
                local user_count
                user_count=$(user_list "$svc" | wc -l | tr -d ' ')
                echo -e "  $status_icon $svc: $status_text ($user_count users)"
            else
                echo -e "  ${GRAY}[-]${RESET} $svc: not installed"
            fi
        done
    fi
    echo ""
}

show_service_status() {
    local service="$1"
    
    echo -e "${BOLD}$service Status${RESET}"
    echo "================================================"
    
    if ! is_service_installed "$service"; then
        echo "  Status: not installed"
        return
    fi
    
    case "$service" in
        reality|ws|vray)
            echo "  Service: xray"
            echo "  Status: $(systemctl is-active xray 2>/dev/null || echo 'unknown')"
            echo "  Users: $(user_list "$service" | wc -l | tr -d ' ')"
            ;;
        wg)
            echo "  Service: wg-quick@wg0"
            echo "  Status: $(systemctl is-active wg-quick@wg0 2>/dev/null || echo 'unknown')"
            echo "  Users: $(user_list "wg" | wc -l | tr -d ' ')"
            if command -v wg &>/dev/null && [[ -e /sys/class/net/wg0 ]]; then
                echo ""
                echo "  Interface:"
                wg show wg0 2>/dev/null | sed 's/^/    /'
            fi
            ;;
        dnstt)
            echo "  Service: dnstt"
            echo "  Status: $(systemctl is-active dnstt 2>/dev/null || echo 'unknown')"
            echo "  Users: $(user_list "dnstt" | wc -l | tr -d ' ')"
            ;;
        mtp)
            echo "  Service: mtprotoproxy"
            echo "  Status: $(systemctl is-active mtprotoproxy 2>/dev/null || echo 'unknown')"
            ;;
    esac
}

#-------------------------------------------------------------------------------
# Service Control
#-------------------------------------------------------------------------------

restart_service() {
    local service="$1"
    
    validate_service "$service"
    
    if ! is_service_installed "$service"; then
        error "Service '$service' is not installed"
    fi
    
    case "$service" in
        reality|ws|vray)
            systemctl restart xray
            success "Xray restarted"
            ;;
        wg)
            systemctl restart wg-quick@wg0
            success "WireGuard restarted"
            ;;
        dnstt)
            systemctl restart dnstt
            success "DNSTT restarted"
            ;;
        mtp)
            systemctl restart mtprotoproxy
            success "MTProto restarted"
            ;;
    esac
}

#-------------------------------------------------------------------------------
# Install Service
#-------------------------------------------------------------------------------

install_service() {
    local service="$1"
    
    validate_service "$service"
    
    if is_service_installed "$service"; then
        warn "Service '$service' is already installed"
        return
    fi
    
    info "Installing $service..."
    echo "Run: curl -sSL ${service}.dnscloak.net | sudo bash"
}

#-------------------------------------------------------------------------------
# Uninstall Service
#-------------------------------------------------------------------------------

uninstall_service() {
    local service="$1"
    
    validate_service "$service"
    
    if ! is_service_installed "$service"; then
        error "Service '$service' is not installed"
    fi
    
    info "To uninstall $service, run the installer again and select uninstall:"
    echo "  curl -sSL ${service}.dnscloak.net | sudo bash"
}

#-------------------------------------------------------------------------------
# Help
#-------------------------------------------------------------------------------

show_help() {
    cat <<'EOF'

  ╔═══════════════════════════════════════════════════════════╗
  ║                    DNSCloak CLI v2.0.0                    ║
  ╚═══════════════════════════════════════════════════════════╝

  USAGE:
    dnscloak <command> [service] [options]

  COMMANDS:
    add <service> <username>     Add user to service
    remove <service> <username>  Remove user from service
    list [service]               List users (filter by service)
    links <username> [service]   Show connection links/configs
    status [service]             Show service status
    restart <service>            Restart a service
    install <service>            Install new service (prints URL)
    services                     List installed services
    help                         Show this help

  SERVICES:
    reality   VLESS + REALITY (no domain, stealth)
    ws        VLESS + WebSocket + CDN (Cloudflare)
    wg        WireGuard VPN (fast, native apps)
    dnstt     DNS Tunnel (emergency, slow)
    mtp       MTProto Proxy (Telegram)
    vray      VLESS + TLS (requires domain)

  EXAMPLES:
    dnscloak add reality alice        # Add Alice to Reality
    dnscloak links alice              # Show all links for Alice
    dnscloak links alice wg           # Show WireGuard config
    dnscloak list                     # List all users
    dnscloak list wg                  # List WireGuard users
    dnscloak status                   # All services status
    dnscloak restart wg               # Restart WireGuard

EOF
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        add)
            require_root
            local service="$1"
            local username="$2"
            validate_service "$service"
            add_user "$service" "$username"
            ;;
        remove|rm|del)
            require_root
            local service="$1"
            local username="$2"
            validate_service "$service"
            remove_user "$service" "$username"
            ;;
        list|ls)
            local service="$1"
            [[ -n "$service" ]] && validate_service "$service"
            list_users "$service"
            ;;
        links|link|show)
            local username="$1"
            local service="$2"
            [[ -n "$service" ]] && validate_service "$service"
            show_links "$username" "$service"
            ;;
        status|stat)
            local service="$1"
            show_status "$service"
            ;;
        restart)
            require_root
            local service="$1"
            restart_service "$service"
            ;;
        install)
            local service="$1"
            install_service "$service"
            ;;
        uninstall)
            local service="$1"
            uninstall_service "$service"
            ;;
        services)
            local installed
            installed=$(get_installed_services)
            echo ""
            echo -e "${BOLD}Installed Services${RESET}"
            echo "================================================"
            if [[ -z "$installed" ]]; then
                echo "  None"
            else
                for svc in $installed; do
                    echo "  - $svc"
                done
            fi
            echo ""
            ;;
        version|-v|--version)
            echo "DNSCloak CLI v${VERSION}"
            ;;
        help|-h|--help|"")
            show_help
            ;;
        *)
            error "Unknown command: $command. Use 'dnscloak help' for usage."
            ;;
    esac
}

main "$@"
