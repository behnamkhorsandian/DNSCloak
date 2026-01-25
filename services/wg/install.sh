#!/bin/bash
#===============================================================================
# DNSCloak - WireGuard VPN Service Installer
# https://github.com/behnamkhorsandian/DNSCloak
#
# Usage: curl -sSL wg.dnscloak.net | sudo bash
#===============================================================================

set -e

# Determine script location (works for both local and piped execution)
if [[ -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LIB_DIR="$(dirname "$SCRIPT_DIR")/../lib"
else
    # Piped execution - download libs
    LIB_DIR="/tmp/dnscloak-lib"
    mkdir -p "$LIB_DIR"
    GITHUB_RAW="https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main"
    curl -sL "$GITHUB_RAW/lib/common.sh" -o "$LIB_DIR/common.sh"
    curl -sL "$GITHUB_RAW/lib/cloud.sh" -o "$LIB_DIR/cloud.sh"
    curl -sL "$GITHUB_RAW/lib/bootstrap.sh" -o "$LIB_DIR/bootstrap.sh"
fi

# Source libraries
source "$LIB_DIR/common.sh"
source "$LIB_DIR/cloud.sh"
source "$LIB_DIR/bootstrap.sh"

#-------------------------------------------------------------------------------
# WireGuard Configuration
#-------------------------------------------------------------------------------

SERVICE_NAME="wg"
WG_PORT=51820
WG_INTERFACE="wg0"
WG_DIR="$DNSCLOAK_DIR/wg"
WG_CONFIG="$WG_DIR/wg0.conf"
WG_PEERS_DIR="$WG_DIR/peers"

# Network configuration
WG_NETWORK="10.66.66.0/24"
WG_SERVER_IP="10.66.66.1"
WG_DNS="1.1.1.1, 8.8.8.8"

#-------------------------------------------------------------------------------
# Installation Check
#-------------------------------------------------------------------------------

is_wg_installed() {
    [[ -f "$WG_CONFIG" ]] && systemctl is-active --quiet "wg-quick@${WG_INTERFACE}"
}

#-------------------------------------------------------------------------------
# Install WireGuard Package
#-------------------------------------------------------------------------------

install_wireguard_package() {
    print_step "Installing WireGuard"
    
    if command -v wg &>/dev/null; then
        print_info "WireGuard already installed"
        return 0
    fi
    
    apt-get update -qq
    apt-get install -y -qq wireguard wireguard-tools
    
    print_success "WireGuard installed"
}

#-------------------------------------------------------------------------------
# Generate Server Keys
#-------------------------------------------------------------------------------

generate_server_keys() {
    print_step "Generating server keypair"
    
    local priv_key pub_key
    
    # Check if keys already exist
    if [[ -f "$WG_DIR/server.key" && -f "$WG_DIR/server.pub" ]]; then
        print_info "Server keys already exist"
        SERVER_PRIVATE_KEY=$(cat "$WG_DIR/server.key")
        SERVER_PUBLIC_KEY=$(cat "$WG_DIR/server.pub")
        return 0
    fi
    
    mkdir -p "$WG_DIR"
    chmod 700 "$WG_DIR"
    
    # Generate keys
    priv_key=$(wg genkey)
    pub_key=$(echo "$priv_key" | wg pubkey)
    
    # Save keys
    echo "$priv_key" > "$WG_DIR/server.key"
    echo "$pub_key" > "$WG_DIR/server.pub"
    chmod 600 "$WG_DIR/server.key" "$WG_DIR/server.pub"
    
    SERVER_PRIVATE_KEY="$priv_key"
    SERVER_PUBLIC_KEY="$pub_key"
    
    print_success "Server keys generated"
}

#-------------------------------------------------------------------------------
# Get Main Network Interface
#-------------------------------------------------------------------------------

get_default_interface() {
    ip route | grep default | awk '{print $5}' | head -1
}

#-------------------------------------------------------------------------------
# Create WireGuard Configuration
#-------------------------------------------------------------------------------

create_wg_config() {
    print_step "Creating WireGuard configuration"
    
    local main_iface
    main_iface=$(get_default_interface)
    
    mkdir -p "$WG_PEERS_DIR"
    chmod 700 "$WG_PEERS_DIR"
    
    cat > "$WG_CONFIG" <<EOF
# DNSCloak WireGuard Configuration
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

[Interface]
Address = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}

# NAT rules
PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${main_iface} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${main_iface} -j MASQUERADE

# Peers are added below by dnscloak
EOF

    chmod 600 "$WG_CONFIG"
    
    # Save server info
    server_set "wg_public_key" "$SERVER_PUBLIC_KEY"
    server_set "wg_port" "$WG_PORT"
    
    print_success "WireGuard configuration created"
}

#-------------------------------------------------------------------------------
# Get Next Available IP
#-------------------------------------------------------------------------------

get_next_ip() {
    local last_octet=1  # Server is .1
    
    # Find highest used IP
    if [[ -f "$DNSCLOAK_USERS" ]]; then
        local ips
        ips=$(jq -r '.users[].protocols.wg.ip // empty' "$DNSCLOAK_USERS" 2>/dev/null | sort -t. -k4 -n | tail -1)
        if [[ -n "$ips" ]]; then
            last_octet=$(echo "$ips" | cut -d. -f4)
        fi
    fi
    
    # Increment
    ((last_octet++))
    
    # Check bounds (max 254 clients)
    if [[ $last_octet -gt 254 ]]; then
        print_error "Maximum number of clients reached (254)"
        return 1
    fi
    
    echo "10.66.66.${last_octet}"
}

#-------------------------------------------------------------------------------
# Add User
#-------------------------------------------------------------------------------

add_wg_user() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        print_error "Username required"
        return 1
    fi
    
    # Check if user exists in this protocol
    if user_exists "$username" "wg"; then
        print_warning "User '$username' already exists in WireGuard"
        return 1
    fi
    
    print_info "Adding user '$username'..."
    
    # Generate client keypair
    local client_priv client_pub psk client_ip
    client_priv=$(wg genkey)
    client_pub=$(echo "$client_priv" | wg pubkey)
    psk=$(wg genpsk)
    client_ip=$(get_next_ip)
    
    if [[ -z "$client_ip" ]]; then
        return 1
    fi
    
    # Save client config
    local client_conf="$WG_PEERS_DIR/${username}.conf"
    local server_ip
    server_ip=$(server_get "ip")
    
    cat > "$client_conf" <<EOF
[Interface]
PrivateKey = ${client_priv}
Address = ${client_ip}/32
DNS = ${WG_DNS}

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
PresharedKey = ${psk}
Endpoint = ${server_ip}:${WG_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    chmod 600 "$client_conf"
    
    # Add peer to server config
    cat >> "$WG_CONFIG" <<EOF

# ${username}
[Peer]
PublicKey = ${client_pub}
PresharedKey = ${psk}
AllowedIPs = ${client_ip}/32
EOF

    # Save to users.json
    user_add "$username" "wg" "{\"public_key\": \"$client_pub\", \"psk\": \"$psk\", \"ip\": \"$client_ip\", \"private_key\": \"$client_priv\"}"
    
    # Reload WireGuard
    wg_reload
    
    print_success "User '$username' added to WireGuard"
}

#-------------------------------------------------------------------------------
# Remove User
#-------------------------------------------------------------------------------

remove_wg_user() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        print_error "Username required"
        return 1
    fi
    
    if ! user_exists "$username" "wg"; then
        print_error "User '$username' not found in WireGuard"
        return 1
    fi
    
    # Get user's public key to remove from config
    local pub_key
    pub_key=$(user_get "$username" "wg" "public_key")
    
    # Remove peer from config (remove the block for this public key)
    local tmp
    tmp=$(mktemp)
    awk -v pk="$pub_key" '
        /^# / { username_line=$0; next_peer=1 }
        /^\[Peer\]/ && next_peer { peer_start=1; buffer=username_line"\n"$0"\n"; next }
        peer_start && /^PublicKey/ && $0 ~ pk { skip_peer=1; next }
        peer_start && /^PublicKey/ && $0 !~ pk { skip_peer=0; print buffer; print; peer_start=0; next }
        peer_start && !skip_peer { buffer=buffer $0 "\n"; next }
        peer_start && /^$/ {
            if (!skip_peer) { print buffer }
            peer_start=0; skip_peer=0; buffer=""
            next
        }
        /^\[Peer\]/ && !next_peer { print; next }
        !peer_start && !skip_peer { print }
    ' "$WG_CONFIG" > "$tmp" && mv "$tmp" "$WG_CONFIG"
    
    # Simpler approach - recreate config from scratch
    regenerate_wg_config "$username"
    
    # Remove client config file
    rm -f "$WG_PEERS_DIR/${username}.conf"
    
    # Remove from users.json
    user_remove "$username" "wg"
    
    # Reload WireGuard
    wg_reload
    
    print_success "User '$username' removed from WireGuard"
}

#-------------------------------------------------------------------------------
# Regenerate Config (after user removal)
#-------------------------------------------------------------------------------

regenerate_wg_config() {
    local exclude_user="$1"
    
    local main_iface
    main_iface=$(get_default_interface)
    
    # Recreate base config
    cat > "$WG_CONFIG" <<EOF
# DNSCloak WireGuard Configuration
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

[Interface]
Address = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY:-$(cat "$WG_DIR/server.key")}

# NAT rules
PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${main_iface} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${main_iface} -j MASQUERADE
EOF

    # Add all peers except the excluded one
    local users
    users=$(user_list "wg")
    
    while IFS= read -r username; do
        [[ -z "$username" ]] && continue
        [[ "$username" == "$exclude_user" ]] && continue
        
        local pub_key psk client_ip
        pub_key=$(user_get "$username" "wg" "public_key")
        psk=$(user_get "$username" "wg" "psk")
        client_ip=$(user_get "$username" "wg" "ip")
        
        cat >> "$WG_CONFIG" <<EOF

# ${username}
[Peer]
PublicKey = ${pub_key}
PresharedKey = ${psk}
AllowedIPs = ${client_ip}/32
EOF
    done <<< "$users"
    
    chmod 600 "$WG_CONFIG"
}

#-------------------------------------------------------------------------------
# Reload WireGuard
#-------------------------------------------------------------------------------

wg_reload() {
    if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}"; then
        # Use wg syncconf for live reload without dropping connections
        wg syncconf "$WG_INTERFACE" <(wg-quick strip "$WG_CONFIG") 2>/dev/null || \
        systemctl restart "wg-quick@${WG_INTERFACE}"
    else
        systemctl start "wg-quick@${WG_INTERFACE}"
    fi
}

#-------------------------------------------------------------------------------
# Show User Links
#-------------------------------------------------------------------------------

show_user_links() {
    local username="$1"
    
    if ! user_exists "$username" "wg"; then
        print_error "User '$username' not found in WireGuard"
        return 1
    fi
    
    local conf_file="$WG_PEERS_DIR/${username}.conf"
    
    if [[ ! -f "$conf_file" ]]; then
        print_error "Config file not found for '$username'"
        return 1
    fi
    
    local client_ip
    client_ip=$(user_get "$username" "wg" "ip")
    
    echo ""
    echo -e "  ${BOLD}${WHITE}WireGuard Config for '$username'${RESET}"
    print_line
    echo ""
    echo "  Client IP: $client_ip"
    echo "  Server: $(server_get "ip"):$WG_PORT"
    echo ""
    echo -e "  ${CYAN}Configuration:${RESET}"
    print_line
    echo ""
    cat "$conf_file" | sed 's/^/  /'
    echo ""
    
    # QR Code
    if command -v qrencode &>/dev/null; then
        echo "  QR Code (scan with WireGuard app):"
        qrencode -t ANSIUTF8 < "$conf_file" | sed 's/^/  /'
    fi
    
    echo ""
    echo -e "  ${BOLD}${WHITE}How to Connect${RESET}"
    print_line
    echo -e "  ${CYAN}iOS:${RESET}      WireGuard (App Store) > + > Create from QR code"
    echo -e "  ${GREEN}Android:${RESET}  WireGuard (Play Store) > + > Scan from QR code"
    echo -e "  ${BLUE}Windows:${RESET}  wireguard.com > Import tunnel > paste config"
    echo -e "  ${MAGENTA}macOS:${RESET}    WireGuard (App Store) > Import from file"
    echo -e "  ${WHITE}Linux:${RESET}    Save config as /etc/wireguard/wg0.conf"
    echo ""
    echo -e "  ${GRAY}Tip: You can copy the config above or scan the QR code${RESET}"
    echo ""
}

#-------------------------------------------------------------------------------
# List Users
#-------------------------------------------------------------------------------

list_wg_users() {
    echo ""
    echo -e "  ${BOLD}${WHITE}WireGuard Users${RESET}"
    print_line
    
    local users
    users=$(user_list "wg")
    
    if [[ -z "$users" ]]; then
        echo "  No users found"
    else
        printf "  %-15s %-15s %-10s\n" "USERNAME" "IP" "STATUS"
        print_line
        while IFS= read -r username; do
            [[ -z "$username" ]] && continue
            local ip status
            ip=$(user_get "$username" "wg" "ip")
            
            # Check if peer has recent handshake (within last 3 minutes)
            local handshake
            handshake=$(wg show "$WG_INTERFACE" latest-handshakes 2>/dev/null | grep "$(user_get "$username" "wg" "public_key")" | awk '{print $2}')
            
            if [[ -n "$handshake" && "$handshake" != "0" ]]; then
                local now=$(date +%s)
                local diff=$((now - handshake))
                if [[ $diff -lt 180 ]]; then
                    status="online"
                else
                    status="offline"
                fi
            else
                status="never"
            fi
            
            printf "  %-15s %-15s %-10s\n" "$username" "$ip" "$status"
        done <<< "$users"
    fi
    echo ""
}

#-------------------------------------------------------------------------------
# Open Firewall Port
#-------------------------------------------------------------------------------

open_wg_port() {
    print_step "Opening firewall port"
    cloud_open_port "$WG_PORT" "udp"
    print_success "Port $WG_PORT/udp opened"
}

#-------------------------------------------------------------------------------
# Install WireGuard
#-------------------------------------------------------------------------------

install_wg() {
    print_banner "wireguard"
    echo -e "  ${BOLD}${WHITE}WireGuard VPN Installation${RESET}"
    print_line
    echo ""
    
    # Bootstrap (updates, prerequisites)
    bootstrap
    
    if is_wg_installed; then
        print_warning "WireGuard is already installed"
        if confirm "Reinstall?"; then
            uninstall_wg_quiet
        else
            show_menu
            return
        fi
    fi
    
    # Install WireGuard package
    install_wireguard_package
    
    # Generate server keys
    generate_server_keys
    
    # Create configuration
    create_wg_config
    
    # Open firewall
    open_wg_port
    
    # Enable and start WireGuard
    print_step "Starting WireGuard service"
    systemctl enable "wg-quick@${WG_INTERFACE}" 2>/dev/null
    systemctl start "wg-quick@${WG_INTERFACE}"
    sleep 2
    
    if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}"; then
        print_success "WireGuard started"
    else
        print_error "WireGuard failed to start"
        print_info "Check logs: journalctl -u wg-quick@${WG_INTERFACE} -n 50"
        exit 1
    fi
    
    # Create first user
    echo ""
    print_step "Create first user"
    get_input "Username" "user1" first_username
    add_wg_user "$first_username"
    
    # Show results
    print_line
    print_success "WireGuard installation complete!"
    echo ""
    show_user_links "$first_username"
    
    echo ""
    print_info "Add more users: dnscloak add wg <username>"
    print_info "View config: dnscloak links <username>"
}

#-------------------------------------------------------------------------------
# Uninstall (quiet)
#-------------------------------------------------------------------------------

uninstall_wg_quiet() {
    systemctl stop "wg-quick@${WG_INTERFACE}" 2>/dev/null || true
    systemctl disable "wg-quick@${WG_INTERFACE}" 2>/dev/null || true
    rm -rf "$WG_DIR"
    
    # Remove users from wg protocol
    local users
    users=$(user_list "wg")
    while IFS= read -r username; do
        [[ -n "$username" ]] && user_remove "$username" "wg"
    done <<< "$users"
}

#-------------------------------------------------------------------------------
# Uninstall
#-------------------------------------------------------------------------------

uninstall_wg() {
    print_banner "wireguard"
    echo -e "  ${BOLD}${WHITE}Uninstall WireGuard${RESET}"
    print_line
    echo ""
    
    if ! is_wg_installed && [[ ! -f "$WG_CONFIG" ]]; then
        print_error "WireGuard is not installed"
        return 1
    fi
    
    if ! confirm "Remove WireGuard and all users?"; then
        return 0
    fi
    
    uninstall_wg_quiet
    
    print_success "WireGuard uninstalled"
}

#-------------------------------------------------------------------------------
# Show Status
#-------------------------------------------------------------------------------

show_status() {
    echo ""
    echo -e "  ${BOLD}${WHITE}WireGuard Status${RESET}"
    print_line
    echo ""
    
    if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}"; then
        echo "  Service: ${GREEN}running${RESET}"
    else
        echo "  Service: ${RED}stopped${RESET}"
    fi
    
    echo "  Interface: $WG_INTERFACE"
    echo "  Port: $WG_PORT/udp"
    echo "  Server IP: $WG_SERVER_IP"
    echo "  Public Key: $(cat "$WG_DIR/server.pub" 2>/dev/null || echo "N/A")"
    echo ""
    
    if command -v wg &>/dev/null && [[ -e "/sys/class/net/$WG_INTERFACE" ]]; then
        echo "  Interface Details:"
        wg show "$WG_INTERFACE" 2>/dev/null | sed 's/^/  /'
    fi
    echo ""
}

#-------------------------------------------------------------------------------
# Menu
#-------------------------------------------------------------------------------

show_menu() {
    while true; do
        print_banner "wireguard"
        echo -e "  ${BOLD}${WHITE}WireGuard Management${RESET}"
        print_line
        echo ""
        echo "  1) View users"
        echo "  2) Add user"
        echo "  3) Remove user"
        echo "  4) Show user config/QR"
        echo "  5) Show service status"
        echo "  6) Restart service"
        echo "  7) Uninstall WireGuard"
        echo "  0) Exit"
        echo ""
        
        get_input "Select option" "0" choice
        
        case "$choice" in
            1)
                list_wg_users
                press_enter
                ;;
            2)
                echo ""
                get_input "Username" "" new_user
                if [[ -n "$new_user" ]]; then
                    add_wg_user "$new_user"
                    show_user_links "$new_user"
                fi
                press_enter
                ;;
            3)
                list_wg_users
                get_input "Username to remove" "" del_user
                if [[ -n "$del_user" ]]; then
                    if confirm "Remove user '$del_user'?"; then
                        remove_wg_user "$del_user"
                    fi
                fi
                press_enter
                ;;
            4)
                list_wg_users
                get_input "Username" "" show_user
                if [[ -n "$show_user" ]]; then
                    show_user_links "$show_user"
                fi
                press_enter
                ;;
            5)
                show_status
                press_enter
                ;;
            6)
                systemctl restart "wg-quick@${WG_INTERFACE}"
                print_success "WireGuard restarted"
                press_enter
                ;;
            7)
                uninstall_wg
                if [[ ! -f "$WG_CONFIG" ]]; then
                    exit 0
                fi
                press_enter
                ;;
            0|"")
                echo ""
                print_info "Bye!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    check_root
    check_os
    
    # Load existing server keys if available
    if [[ -f "$WG_DIR/server.key" ]]; then
        SERVER_PRIVATE_KEY=$(cat "$WG_DIR/server.key")
    fi
    if [[ -f "$WG_DIR/server.pub" ]]; then
        SERVER_PUBLIC_KEY=$(cat "$WG_DIR/server.pub")
    fi
    
    if is_wg_installed; then
        show_menu
    else
        install_wg
        echo ""
        if confirm "Open management menu?"; then
            show_menu
        fi
    fi
}

# Run
main "$@"
