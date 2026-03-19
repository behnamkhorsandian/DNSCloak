#!/bin/bash
#===============================================================================
# Vany - WireGuard VPN Functions
# Sourced by start.sh or install.sh - do not run directly
#===============================================================================

SERVICE_NAME="wg"
WG_PORT=51820
WG_INTERFACE="wg0"
WG_DIR="$VANY_DIR/wg"
WG_CONFIG="$WG_DIR/wg0.conf"
WG_PEERS_DIR="$WG_DIR/peers"
WG_NETWORK="10.66.66.0/24"
WG_SERVER_IP="10.66.66.1"
WG_DNS="1.1.1.1, 8.8.8.8"

#-------------------------------------------------------------------------------
# Checks
#-------------------------------------------------------------------------------

is_wg_installed() {
    [[ -f "$WG_CONFIG" ]] && systemctl is-active --quiet "wg-quick@${WG_INTERFACE}"
}

#-------------------------------------------------------------------------------
# Package Install
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
# Key Generation
#-------------------------------------------------------------------------------

generate_wg_server_keys() {
    print_step "Generating server keypair"

    if [[ -f "$WG_DIR/server.key" && -f "$WG_DIR/server.pub" ]]; then
        print_info "Server keys already exist"
        SERVER_PRIVATE_KEY=$(cat "$WG_DIR/server.key")
        SERVER_PUBLIC_KEY=$(cat "$WG_DIR/server.pub")
        return 0
    fi

    mkdir -p "$WG_DIR"
    chmod 700 "$WG_DIR"

    local priv_key pub_key
    priv_key=$(wg genkey)
    pub_key=$(echo "$priv_key" | wg pubkey)

    echo "$priv_key" > "$WG_DIR/server.key"
    echo "$pub_key" > "$WG_DIR/server.pub"
    chmod 600 "$WG_DIR/server.key" "$WG_DIR/server.pub"

    SERVER_PRIVATE_KEY="$priv_key"
    SERVER_PUBLIC_KEY="$pub_key"

    print_success "Server keys generated"
}

#-------------------------------------------------------------------------------
# Config
#-------------------------------------------------------------------------------

get_wg_default_interface() {
    ip route | grep default | awk '{print $5}' | head -1
}

create_wg_config() {
    print_step "Creating WireGuard configuration"

    local main_iface
    main_iface=$(get_wg_default_interface)

    mkdir -p "$WG_PEERS_DIR"
    chmod 700 "$WG_PEERS_DIR"

    cat > "$WG_CONFIG" <<EOF
# Vany WireGuard Configuration
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

[Interface]
Address = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}

# NAT rules
PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${main_iface} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${main_iface} -j MASQUERADE
EOF

    chmod 600 "$WG_CONFIG"

    server_set "wg_public_key" "$SERVER_PUBLIC_KEY"
    server_set "wg_port" "$WG_PORT"

    print_success "WireGuard configuration created"
}

get_wg_next_ip() {
    local last_octet=1

    if [[ -f "$VANY_USERS" ]]; then
        local ips
        ips=$(jq -r '.users[].protocols.wg.ip // empty' "$VANY_USERS" 2>/dev/null | sort -t. -k4 -n | tail -1)
        if [[ -n "$ips" ]]; then
            last_octet=$(echo "$ips" | cut -d. -f4)
        fi
    fi

    ((last_octet++))

    if [[ $last_octet -gt 254 ]]; then
        print_error "Maximum number of clients reached (254)"
        return 1
    fi

    echo "10.66.66.${last_octet}"
}

#-------------------------------------------------------------------------------
# Reload
#-------------------------------------------------------------------------------

wg_reload() {
    if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}"; then
        wg syncconf "$WG_INTERFACE" <(wg-quick strip "$WG_CONFIG") 2>/dev/null || \
        systemctl restart "wg-quick@${WG_INTERFACE}"
    else
        systemctl start "wg-quick@${WG_INTERFACE}"
    fi
}

regenerate_wg_config() {
    local exclude_user="$1"

    local main_iface
    main_iface=$(get_wg_default_interface)

    cat > "$WG_CONFIG" <<EOF
# Vany WireGuard Configuration
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

[Interface]
Address = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY:-$(cat "$WG_DIR/server.key")}

PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${main_iface} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${main_iface} -j MASQUERADE
EOF

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
# Non-interactive install (called by TUI wizard)
#-------------------------------------------------------------------------------

install_wireguard_service() {
    install_wireguard_package
    generate_wg_server_keys
    create_wg_config

    # Open firewall
    if type cloud_open_port &>/dev/null; then
        cloud_open_port "$WG_PORT" "udp"
    fi

    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1 2>/dev/null || true
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi

    # Start service
    systemctl enable "wg-quick@${WG_INTERFACE}" 2>/dev/null
    systemctl start "wg-quick@${WG_INTERFACE}"

    sleep 2
    if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}"; then
        print_success "WireGuard started"
    else
        print_error "WireGuard failed to start"
        journalctl -u "wg-quick@${WG_INTERFACE}" -n 20 --no-pager 2>/dev/null || true
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Interactive install (standalone / CLI mode)
#-------------------------------------------------------------------------------

install_wg() {
    clear
    load_banner "wireguard" 2>/dev/null || true
    echo -e "  ${BOLD}${WHITE}WireGuard VPN Installation${RESET}"
    print_line
    echo ""

    bootstrap

    if is_wg_installed; then
        print_warning "WireGuard is already installed"
        if confirm "Reinstall?"; then
            uninstall_wg_quiet
        else
            manage_wg
            return
        fi
    fi

    install_wireguard_package
    generate_wg_server_keys
    create_wg_config

    print_step "Opening firewall port"
    cloud_open_port "$WG_PORT" "udp"
    print_success "Port $WG_PORT/udp opened"

    print_step "Starting WireGuard service"
    systemctl enable "wg-quick@${WG_INTERFACE}" 2>/dev/null
    systemctl start "wg-quick@${WG_INTERFACE}"
    sleep 2

    if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}"; then
        print_success "WireGuard started"
    else
        print_error "WireGuard failed to start"
        print_info "Check logs: journalctl -u wg-quick@${WG_INTERFACE} -n 50"
        return 1
    fi

    echo ""
    print_step "Create first user"
    get_input "Username" "user1" first_username
    add_wg_user "$first_username"

    print_line
    print_success "WireGuard installation complete!"
    echo ""
    show_wg_links "$first_username"

    echo ""
    print_info "Add more users: vany add wg <username>"
    echo ""

    if confirm "Open management menu?"; then
        manage_wg
    fi
}

#-------------------------------------------------------------------------------
# User CRUD
#-------------------------------------------------------------------------------

add_wg_user() {
    local username="$1"

    if [[ -z "$username" ]]; then
        print_error "Username required"
        return 1
    fi

    if user_exists "$username" "wg"; then
        print_warning "User '$username' already exists in WireGuard"
        return 1
    fi

    print_info "Adding user '$username'..."

    local client_priv client_pub psk client_ip
    client_priv=$(wg genkey)
    client_pub=$(echo "$client_priv" | wg pubkey)
    psk=$(wg genpsk)
    client_ip=$(get_wg_next_ip)

    if [[ -z "$client_ip" ]]; then
        return 1
    fi

    local server_ip
    server_ip=$(server_get "ip")

    # Load server public key
    if [[ -z "${SERVER_PUBLIC_KEY:-}" ]]; then
        SERVER_PUBLIC_KEY=$(cat "$WG_DIR/server.pub" 2>/dev/null)
    fi

    local client_conf="$WG_PEERS_DIR/${username}.conf"

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

    cat >> "$WG_CONFIG" <<EOF

# ${username}
[Peer]
PublicKey = ${client_pub}
PresharedKey = ${psk}
AllowedIPs = ${client_ip}/32
EOF

    user_add "$username" "wg" "{\"public_key\": \"$client_pub\", \"psk\": \"$psk\", \"ip\": \"$client_ip\", \"private_key\": \"$client_priv\"}"
    wg_reload

    print_success "User '$username' added to WireGuard"
}

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

    regenerate_wg_config "$username"
    rm -f "$WG_PEERS_DIR/${username}.conf"
    user_remove "$username" "wg"
    wg_reload

    print_success "User '$username' removed from WireGuard"
}

show_wg_links() {
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
}

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
            local ip status handshake
            ip=$(user_get "$username" "wg" "ip")

            handshake=$(wg show "$WG_INTERFACE" latest-handshakes 2>/dev/null | grep "$(user_get "$username" "wg" "public_key")" | awk '{print $2}')

            if [[ -n "$handshake" && "$handshake" != "0" ]]; then
                local now diff
                now=$(date +%s)
                diff=$((now - handshake))
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
# Uninstall
#-------------------------------------------------------------------------------

uninstall_wg_quiet() {
    systemctl stop "wg-quick@${WG_INTERFACE}" 2>/dev/null || true
    systemctl disable "wg-quick@${WG_INTERFACE}" 2>/dev/null || true
    rm -rf "$WG_DIR"

    local users
    users=$(user_list "wg")
    while IFS= read -r username; do
        [[ -n "$username" ]] && user_remove "$username" "wg"
    done <<< "$users"
}

uninstall_wg() {
    echo ""
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
# Status
#-------------------------------------------------------------------------------

show_wg_status() {
    echo ""
    echo -e "  ${BOLD}${WHITE}WireGuard Status${RESET}"
    print_line
    echo ""

    if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}"; then
        echo -e "  Service: ${GREEN}running${RESET}"
    else
        echo -e "  Service: ${RED}stopped${RESET}"
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
# Manage (Menu)
#-------------------------------------------------------------------------------

manage_wg() {
    # Load server keys if available
    if [[ -f "$WG_DIR/server.key" ]]; then
        SERVER_PRIVATE_KEY=$(cat "$WG_DIR/server.key")
    fi
    if [[ -f "$WG_DIR/server.pub" ]]; then
        SERVER_PUBLIC_KEY=$(cat "$WG_DIR/server.pub")
    fi

    while true; do
        clear
        load_banner "wireguard" 2>/dev/null || true
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
        echo "  0) Back"
        echo ""

        get_input "Select option" "0" choice

        case "$choice" in
            1) list_wg_users; press_enter ;;
            2)
                echo ""
                get_input "Username" "" new_user
                if [[ -n "$new_user" ]]; then
                    add_wg_user "$new_user"
                    show_wg_links "$new_user"
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
                    show_wg_links "$show_user"
                fi
                press_enter
                ;;
            5) show_wg_status; press_enter ;;
            6)
                systemctl restart "wg-quick@${WG_INTERFACE}"
                print_success "WireGuard restarted"
                press_enter
                ;;
            7) uninstall_wg; return 0 ;;
            0|"") return 0 ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}
