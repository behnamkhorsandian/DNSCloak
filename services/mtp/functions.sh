#!/bin/bash
#===============================================================================
# Vany - MTProto Proxy Functions
# Sourced by start.sh or install.sh - do not run directly
#===============================================================================

SERVICE_NAME="mtp"
MTP_DIR="$VANY_DIR/mtp"
MTP_CONFIG="$MTP_DIR/config.py"
MTP_SERVICE="telegram-proxy"
MTP_DEFAULT_PORT=443

MODE_TLS="tls"
MODE_SECURE="secure"

#-------------------------------------------------------------------------------
# Checks
#-------------------------------------------------------------------------------

is_mtp_installed() {
    [[ -f "/etc/systemd/system/${MTP_SERVICE}.service" ]] && [[ -d "$MTP_DIR" ]]
}

#-------------------------------------------------------------------------------
# Secret Generation
#-------------------------------------------------------------------------------

generate_mtp_secret() {
    head -c 16 /dev/urandom | xxd -p
}

#-------------------------------------------------------------------------------
# Install MTProto Proxy
#-------------------------------------------------------------------------------

install_mtp_prerequisites() {
    print_step "Installing MTProto prerequisites"
    apt-get update -qq
    apt-get install -y -qq python3 python3-pip git >/dev/null 2>&1 || true
    print_success "Prerequisites installed"
}

clone_mtp_proxy() {
    print_step "Downloading MTProto proxy"

    if [[ -d "$MTP_DIR/mtprotoproxy" ]]; then
        print_info "Proxy source already exists"
        return 0
    fi

    mkdir -p "$MTP_DIR"
    git clone https://github.com/alexbers/mtprotoproxy.git "$MTP_DIR/mtprotoproxy" 2>/dev/null

    if [[ ! -f "$MTP_DIR/mtprotoproxy/mtprotoproxy.py" ]]; then
        print_error "Failed to download proxy"
        return 1
    fi

    print_success "Proxy downloaded"
}

generate_mtp_config() {
    local port="$1"
    local mode="$2"
    local first_secret="$3"
    local first_user="$4"
    local tls_domain="${5:-www.google.com}"

    print_step "Generating configuration"

    local secret_prefix=""
    if [[ "$mode" == "tls" ]]; then
        secret_prefix="ee"
    else
        secret_prefix="dd"
    fi

    cat > "$MTP_CONFIG" <<PYEOF
PORT = $port

USERS = {
    "$first_user": "${secret_prefix}${first_secret}",
}

# Proxy settings
SECURE_ONLY = True
STATS_PORT = 8888

# TLS domain for Fake-TLS mode
$( [[ "$mode" == "tls" ]] && echo "TLS_DOMAIN = \"$tls_domain\"" || echo "# TLS_DOMAIN not used in secure mode" )

# Performance tuning
FAST_MODE = True
PREFER_IPV6 = False
PYEOF

    chmod 600 "$MTP_CONFIG"
    print_success "Configuration generated"
}

create_mtp_service() {
    print_step "Creating systemd service"

    cat > "/etc/systemd/system/${MTP_SERVICE}.service" <<EOF
[Unit]
Description=Vany MTProto Proxy
After=network.target

[Service]
Type=simple
WorkingDirectory=$MTP_DIR/mtprotoproxy
ExecStart=/usr/bin/python3 $MTP_DIR/mtprotoproxy/mtprotoproxy.py
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    print_success "Service created"
}

#-------------------------------------------------------------------------------
# Non-interactive install (called by TUI wizard)
# Usage: install_mtp_service <port> <mode> <tls_domain>
#-------------------------------------------------------------------------------

install_mtp_service() {
    local port="${1:-$MTP_DEFAULT_PORT}"
    local mode="${2:-$MODE_TLS}"
    local tls_domain="${3:-www.google.com}"

    if type bootstrap &>/dev/null; then
        bootstrap
    fi

    if is_mtp_installed; then
        systemctl stop "$MTP_SERVICE" 2>/dev/null || true
    fi

    install_mtp_prerequisites
    clone_mtp_proxy

    # Generate a temporary secret for config (first user adds theirs later)
    local tmp_secret
    tmp_secret=$(generate_mtp_secret)
    local secret_prefix=""
    [[ "$mode" == "tls" ]] && secret_prefix="ee" || secret_prefix="dd"

    generate_mtp_config "$port" "$mode" "$tmp_secret" "_placeholder" "$tls_domain"
    create_mtp_service

    # Save server settings
    local server_ip
    server_ip=$(cloud_get_public_ip 2>/dev/null || server_get "ip")
    server_set "ip" "$server_ip" 2>/dev/null || true
    server_set "mtp_port" "$port"
    server_set "mtp_mode" "$mode"
    server_set "mtp_tls_domain" "$tls_domain"

    # Open firewall
    if type cloud_open_port &>/dev/null; then
        cloud_open_port "$port" tcp
    fi

    # Start service
    systemctl enable "$MTP_SERVICE" 2>/dev/null
    systemctl start "$MTP_SERVICE"

    sleep 2
    if systemctl is-active --quiet "$MTP_SERVICE"; then
        print_success "MTProto proxy is running on port $port"
    else
        print_error "MTProto proxy failed to start"
        journalctl -u "$MTP_SERVICE" -n 20 --no-pager 2>/dev/null || true
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Interactive install (standalone / CLI mode)
#-------------------------------------------------------------------------------

install_mtp() {
    clear
    load_banner "mtp" 2>/dev/null || true
    echo -e "  ${BOLD}${WHITE}MTProto Proxy Installation${RESET}"
    print_line
    echo ""
    echo "  MTProto proxy lets Telegram users bypass censorship."
    echo "  Supports Fake-TLS mode (traffic looks like HTTPS)."
    echo ""

    bootstrap

    if is_mtp_installed; then
        print_warning "MTProto is already installed"
        if ! confirm "Reinstall?"; then
            manage_mtp
            return
        fi
        # Stop existing
        systemctl stop "$MTP_SERVICE" 2>/dev/null || true
    fi

    install_mtp_prerequisites
    clone_mtp_proxy

    # Port selection
    echo ""
    echo -e "  ${BOLD}${WHITE}Port Configuration${RESET}"
    print_line
    echo ""

    local port="$MTP_DEFAULT_PORT"
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        print_warning "Port $port is already in use"
        get_input "Choose a different port" "8443" port
    else
        get_input "Port for MTProto" "$MTP_DEFAULT_PORT" port
    fi

    # Mode selection
    echo ""
    echo -e "  ${BOLD}${WHITE}Proxy Mode${RESET}"
    print_line
    echo ""
    echo "  1) Fake-TLS (recommended) - Traffic looks like HTTPS"
    echo "  2) Secure - Random padding, harder to detect"
    echo ""
    get_input "Select mode" "1" mode_choice

    local mode="$MODE_TLS"
    local tls_domain="www.google.com"

    if [[ "$mode_choice" == "2" ]]; then
        mode="$MODE_SECURE"
    else
        echo ""
        get_input "TLS camouflage domain" "www.google.com" tls_domain
    fi

    # First user
    echo ""
    echo -e "  ${BOLD}${WHITE}Create First User${RESET}"
    print_line
    get_input "Username" "user1" first_user

    local secret
    secret=$(generate_mtp_secret)

    # Generate config
    generate_mtp_config "$port" "$mode" "$secret" "$first_user" "$tls_domain"

    # Save to users.json
    local server_ip
    server_ip=$(cloud_get_public_ip)
    server_set "ip" "$server_ip"
    server_set "mtp_port" "$port"
    server_set "mtp_mode" "$mode"
    server_set "mtp_tls_domain" "$tls_domain"

    local secret_prefix=""
    [[ "$mode" == "tls" ]] && secret_prefix="ee" || secret_prefix="dd"
    user_add "$first_user" "mtp" "{\"secret\": \"${secret_prefix}${secret}\", \"mode\": \"$mode\"}"

    # Create service
    create_mtp_service

    # Open firewall
    print_step "Configuring firewall"
    cloud_open_port "$port" tcp

    # Start
    print_step "Starting MTProto proxy"
    systemctl enable "$MTP_SERVICE" 2>/dev/null
    systemctl start "$MTP_SERVICE"

    sleep 2
    if systemctl is-active --quiet "$MTP_SERVICE"; then
        print_success "MTProto proxy is running"
    else
        print_error "MTProto proxy failed to start"
        journalctl -u "$MTP_SERVICE" -n 20 --no-pager
        return 1
    fi

    echo ""
    print_success "MTProto installation complete!"
    echo ""
    show_mtp_links "$first_user"

    echo ""
    if confirm "Open management menu?"; then
        manage_mtp
    fi
}

#-------------------------------------------------------------------------------
# User CRUD
#-------------------------------------------------------------------------------

add_mtp_user() {
    local username="$1"

    if [[ -z "$username" ]]; then
        print_error "Username required"
        return 1
    fi

    if user_exists "$username" "mtp"; then
        print_warning "User '$username' already exists in MTProto"
        return 1
    fi

    local mode
    mode=$(server_get "mtp_mode")
    local secret
    secret=$(generate_mtp_secret)

    local secret_prefix=""
    [[ "$mode" == "tls" ]] && secret_prefix="ee" || secret_prefix="dd"
    local full_secret="${secret_prefix}${secret}"

    # Add to config.py
    if [[ -f "$MTP_CONFIG" ]]; then
        # Insert new user before the closing brace of USERS dict
        sed -i "/^}$/i\\    \"$username\": \"$full_secret\"," "$MTP_CONFIG"
    fi

    user_add "$username" "mtp" "{\"secret\": \"$full_secret\", \"mode\": \"$mode\"}"

    systemctl restart "$MTP_SERVICE" 2>/dev/null

    print_success "User '$username' added to MTProto"
}

remove_mtp_user() {
    local username="$1"

    if [[ -z "$username" ]]; then
        print_error "Username required"
        return 1
    fi

    if ! user_exists "$username" "mtp"; then
        print_error "User '$username' not found in MTProto"
        return 1
    fi

    # Remove from config.py
    if [[ -f "$MTP_CONFIG" ]]; then
        sed -i "/\"$username\":/d" "$MTP_CONFIG"
    fi

    user_remove "$username" "mtp"
    systemctl restart "$MTP_SERVICE" 2>/dev/null

    print_success "User '$username' removed from MTProto"
}

show_mtp_links() {
    local username="$1"

    if ! user_exists "$username" "mtp"; then
        print_error "User '$username' not found in MTProto"
        return 1
    fi

    local secret server_ip port
    secret=$(user_get "$username" "mtp" "secret")
    server_ip=$(server_get "ip")
    port=$(server_get "mtp_port")

    # tg:// link format
    local tg_link="tg://proxy?server=${server_ip}&port=${port}&secret=${secret}"
    # https link
    local https_link="https://t.me/proxy?server=${server_ip}&port=${port}&secret=${secret}"

    echo ""
    echo -e "  ${BOLD}${WHITE}MTProto Links for '$username'${RESET}"
    print_line
    echo ""
    echo -e "  ${CYAN}Telegram Link:${RESET}"
    echo "  $tg_link"
    echo ""
    echo -e "  ${CYAN}Web Link:${RESET}"
    echo "  $https_link"
    echo ""

    if command -v qrencode &>/dev/null; then
        echo "  QR Code:"
        qrencode -t ANSIUTF8 "$tg_link" | sed 's/^/  /'
    fi

    echo ""
    echo "  Manual Configuration:"
    echo "  ---------------------"
    echo "  Server: $server_ip"
    echo "  Port: $port"
    echo "  Secret: $secret"
    echo ""
    echo -e "  ${BOLD}${WHITE}How to Connect${RESET}"
    print_line
    echo -e "  Open one of the links above in Telegram."
    echo -e "  Or go to: Telegram > Settings > Data and Storage > Proxy"
    echo -e "  Add proxy with the server, port, and secret above."
    echo ""
}

list_mtp_users() {
    echo ""
    echo -e "  ${BOLD}${WHITE}MTProto Users${RESET}"
    print_line

    local users
    users=$(user_list "mtp")

    if [[ -z "$users" ]]; then
        echo "  No users found"
    else
        echo "$users" | while read -r username; do
            echo "  - $username"
        done
    fi
    echo ""
}

#-------------------------------------------------------------------------------
# Uninstall
#-------------------------------------------------------------------------------

uninstall_mtp() {
    echo ""
    echo -e "  ${BOLD}${RED}Uninstall MTProto${RESET}"
    print_line
    echo ""

    if ! is_mtp_installed; then
        print_error "MTProto is not installed"
        return 1
    fi

    if ! confirm "Remove MTProto proxy and all users?"; then
        return 0
    fi

    systemctl stop "$MTP_SERVICE" 2>/dev/null || true
    systemctl disable "$MTP_SERVICE" 2>/dev/null || true
    rm -f "/etc/systemd/system/${MTP_SERVICE}.service"
    systemctl daemon-reload

    rm -rf "$MTP_DIR"

    local users
    users=$(user_list "mtp")
    if [[ -n "$users" ]]; then
        echo "$users" | while read -r u; do
            user_remove "$u" "mtp"
        done
    fi

    print_success "MTProto uninstalled"
}

#-------------------------------------------------------------------------------
# Status
#-------------------------------------------------------------------------------

show_mtp_status() {
    echo ""
    echo -e "  ${BOLD}${WHITE}MTProto Status${RESET}"
    print_line
    echo ""

    if systemctl is-active --quiet "$MTP_SERVICE"; then
        echo -e "  Service: ${GREEN}Running${RESET}"
    else
        echo -e "  Service: ${RED}Stopped${RESET}"
    fi

    local port mode
    port=$(server_get "mtp_port")
    mode=$(server_get "mtp_mode")

    echo "  Port: $port"
    echo "  Mode: $mode"

    local user_count
    user_count=$(user_list "mtp" | wc -l | tr -d ' ')
    echo "  Users: $user_count"
    echo ""
}

#-------------------------------------------------------------------------------
# Manage (Menu)
#-------------------------------------------------------------------------------

manage_mtp() {
    while true; do
        clear
        load_banner "mtp" 2>/dev/null || true
        echo -e "  ${BOLD}${WHITE}MTProto Management${RESET}"
        print_line
        echo ""
        echo "  1) View users and links"
        echo "  2) Add user"
        echo "  3) Remove user"
        echo "  4) Service status"
        echo "  5) Restart service"
        echo "  6) Uninstall"
        echo "  0) Back"
        echo ""

        get_input "Select [0-6]" "0" choice

        case "$choice" in
            1)
                list_mtp_users
                echo ""
                get_input "Show links for user (or Enter to skip)" "" show_user
                if [[ -n "$show_user" ]]; then
                    show_mtp_links "$show_user"
                fi
                press_enter
                ;;
            2)
                echo ""
                get_input "Username" "" new_user
                if [[ -n "$new_user" ]]; then
                    add_mtp_user "$new_user"
                    show_mtp_links "$new_user"
                fi
                press_enter
                ;;
            3)
                list_mtp_users
                get_input "Username to remove" "" del_user
                if [[ -n "$del_user" ]]; then
                    remove_mtp_user "$del_user"
                fi
                press_enter
                ;;
            4) show_mtp_status; press_enter ;;
            5)
                systemctl restart "$MTP_SERVICE"
                print_success "MTProto restarted"
                press_enter
                ;;
            6) uninstall_mtp; return 0 ;;
            0|"") return 0 ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}
