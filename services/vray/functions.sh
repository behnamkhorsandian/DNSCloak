#!/bin/bash
#===============================================================================
# Vany - VLESS + TCP + TLS (V2Ray) Functions
# Sourced by start.sh or install.sh - do not run directly
#===============================================================================

SERVICE_NAME="vray"
VRAY_PORT=443
VRAY_TAG="vray-in"
CERT_DIR="$VANY_DIR/xray/certs"

#-------------------------------------------------------------------------------
# Checks
#-------------------------------------------------------------------------------

is_vray_installed() {
    xray_inbound_exists "$VRAY_TAG"
}

#-------------------------------------------------------------------------------
# TLS Certificate (Let's Encrypt via acme.sh)
#-------------------------------------------------------------------------------

install_acme() {
    if [[ -f "$HOME/.acme.sh/acme.sh" ]]; then
        print_info "acme.sh already installed"
        return 0
    fi

    print_step "Installing acme.sh"
    curl https://get.acme.sh | sh -s email="admin@$(hostname -f 2>/dev/null || echo 'localhost')" 2>/dev/null

    if [[ ! -f "$HOME/.acme.sh/acme.sh" ]]; then
        print_error "Failed to install acme.sh"
        return 1
    fi

    "$HOME/.acme.sh/acme.sh" --set-default-ca --server letsencrypt 2>/dev/null
    print_success "acme.sh installed"
}

issue_certificate() {
    local domain="$1"

    mkdir -p "$CERT_DIR"
    print_step "Issuing TLS certificate for $domain"

    # Stop anything on port 80 temporarily for standalone verification
    local port80_pid
    port80_pid=$(ss -tlnp 2>/dev/null | grep ':80 ' | grep -oP 'pid=\K\d+' | head -1)

    if [[ -n "$port80_pid" ]]; then
        print_info "Temporarily stopping service on port 80"
        kill "$port80_pid" 2>/dev/null
        sleep 1
    fi

    "$HOME/.acme.sh/acme.sh" --issue -d "$domain" --standalone \
        --keylength ec-256 \
        --fullchain-file "$CERT_DIR/fullchain.pem" \
        --key-file "$CERT_DIR/privkey.pem" \
        --reloadcmd "systemctl reload xray 2>/dev/null || true"

    if [[ ! -f "$CERT_DIR/fullchain.pem" ]]; then
        print_error "Certificate issuance failed"
        print_info "Make sure:"
        echo "  - Domain $domain points to this server"
        echo "  - Port 80 is open for verification"
        return 1
    fi

    chmod 600 "$CERT_DIR/privkey.pem"
    print_success "Certificate issued for $domain"
}

#-------------------------------------------------------------------------------
# Domain Validation
#-------------------------------------------------------------------------------

validate_vray_domain() {
    local domain="$1"

    if [[ -z "$domain" ]] || [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        print_error "Invalid domain format"
        return 1
    fi

    local server_ip
    server_ip=$(cloud_get_public_ip)

    local dns_ip
    dns_ip=$(dig +short "$domain" 2>/dev/null | head -1)

    if [[ "$dns_ip" != "$server_ip" ]]; then
        print_warning "Domain '$domain' does not resolve to this server ($server_ip)"
        print_info "DNS shows: ${dns_ip:-no record}"
        echo ""
        echo "  Make sure you have an A record:"
        echo "  $domain -> $server_ip"
        echo ""
        if ! confirm "Continue anyway?"; then
            return 1
        fi
    else
        print_success "Domain '$domain' resolves correctly to $server_ip"
    fi
}

#-------------------------------------------------------------------------------
# Non-interactive install (called by TUI wizard)
# Usage: install_vray_service <domain>
#-------------------------------------------------------------------------------

install_vray_service() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        print_error "Domain required"
        return 1
    fi

    if type bootstrap &>/dev/null; then
        bootstrap
    fi

    if type install_xray &>/dev/null; then
        install_xray
    fi

    install_acme || return 1

    # Open port 80 for ACME challenge
    if type cloud_open_port &>/dev/null; then
        cloud_open_port 80 tcp
    fi

    issue_certificate "$domain" || return 1

    xray_add_vray_inbound "$domain" "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem"

    # Open port 443
    if type cloud_open_port &>/dev/null; then
        cloud_open_port "$VRAY_PORT" tcp
    fi

    local server_ip
    server_ip=$(cloud_get_public_ip 2>/dev/null || server_get "ip")
    server_set "ip" "$server_ip" 2>/dev/null || true
    server_set "vray_domain" "$domain"

    xray_reload

    sleep 2
    if systemctl is-active --quiet xray; then
        print_success "Xray is running with V2Ray TLS"
    else
        print_error "Xray failed to start"
        journalctl -u xray -n 20 --no-pager 2>/dev/null || true
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Interactive install (standalone / CLI mode)
#-------------------------------------------------------------------------------

install_vray() {
    clear
    load_banner "reality" 2>/dev/null || true
    echo -e "  ${BOLD}${WHITE}VLESS + TCP + TLS Installation${RESET}"
    print_line
    echo ""
    echo "  VLESS over TCP with real TLS certificate."
    echo "  Requires a domain pointing to this server."
    echo "  Uses Let's Encrypt for automatic TLS."
    echo ""

    bootstrap
    install_xray

    if is_vray_installed; then
        print_warning "V2Ray TLS is already installed"
        if ! confirm "Reinstall?"; then
            manage_vray
            return
        fi
        xray_remove_inbound "$VRAY_TAG"
    fi

    # Domain
    echo ""
    echo -e "  ${BOLD}${WHITE}Domain Configuration${RESET}"
    print_line
    echo ""
    echo "  You need a domain with an A record pointing to this server."
    echo "  The domain must NOT be proxied through Cloudflare."
    echo ""

    local domain
    get_input "Your domain" "" domain

    if [[ -z "$domain" ]]; then
        print_error "Domain is required"
        return 1
    fi

    validate_vray_domain "$domain" || return 1

    # TLS certificate
    echo ""
    echo -e "  ${BOLD}${WHITE}TLS Certificate${RESET}"
    print_line

    install_acme || return 1

    # Open port 80 for ACME challenge
    cloud_open_port 80 tcp
    issue_certificate "$domain" || return 1

    # First user
    echo ""
    echo -e "  ${BOLD}${WHITE}Create First User${RESET}"
    print_line
    get_input "Username" "user1" first_user

    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)

    # Add Xray inbound
    xray_add_vray_inbound "$domain" "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem"
    xray_add_client "$VRAY_TAG" "$uuid" "$first_user"

    # Open port 443
    cloud_open_port "$VRAY_PORT" tcp

    # Save to users.json
    local server_ip
    server_ip=$(cloud_get_public_ip)
    server_set "ip" "$server_ip"
    server_set "vray_domain" "$domain"

    user_add "$first_user" "vray" "{\"uuid\": \"$uuid\"}"

    # Reload
    xray_reload

    sleep 2
    if systemctl is-active --quiet xray; then
        print_success "Xray is running with V2Ray TLS"
    else
        print_error "Xray failed to start"
        journalctl -u xray -n 20 --no-pager
        return 1
    fi

    echo ""
    print_success "V2Ray TLS installation complete!"
    echo ""
    show_vray_links "$first_user"

    echo ""
    if confirm "Open management menu?"; then
        manage_vray
    fi
}

#-------------------------------------------------------------------------------
# User Management
#-------------------------------------------------------------------------------

add_vray_user() {
    local username="$1"

    if [[ -z "$username" ]]; then
        print_error "Username required"
        return 1
    fi

    if user_exists "$username" "vray"; then
        print_warning "User '$username' already exists in V2Ray"
        return 1
    fi

    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)

    xray_add_client "$VRAY_TAG" "$uuid" "$username"
    user_add "$username" "vray" "{\"uuid\": \"$uuid\"}"
    xray_reload

    print_success "User '$username' added to V2Ray"
}

remove_vray_user() {
    local username="$1"

    if [[ -z "$username" ]]; then
        print_error "Username required"
        return 1
    fi

    if ! user_exists "$username" "vray"; then
        print_error "User '$username' not found in V2Ray"
        return 1
    fi

    xray_remove_client "$VRAY_TAG" "$username"
    user_remove "$username" "vray"
    xray_reload

    print_success "User '$username' removed from V2Ray"
}

show_vray_links() {
    local username="$1"

    if ! user_exists "$username" "vray"; then
        print_error "User '$username' not found in V2Ray"
        return 1
    fi

    local uuid domain server_ip
    uuid=$(user_get "$username" "vray" "uuid")
    domain=$(server_get "vray_domain")
    server_ip=$(server_get "ip")

    local link
    link=$(xray_vray_link "$uuid" "$domain" "$domain" "Vany-VRay-${username}")

    echo ""
    echo -e "  ${BOLD}${WHITE}V2Ray TLS Links for '$username'${RESET}"
    print_line
    echo ""
    echo -e "  ${CYAN}VLESS Link:${RESET}"
    echo "  $link"
    echo ""

    if command -v qrencode &>/dev/null; then
        echo "  QR Code:"
        qrencode -t ANSIUTF8 "$link" | sed 's/^/  /'
    fi

    echo ""
    echo "  Manual Configuration:"
    echo "  ---------------------"
    echo "  Protocol: VLESS"
    echo "  Address: $domain"
    echo "  Port: 443"
    echo "  UUID: $uuid"
    echo "  Transport: TCP"
    echo "  Security: TLS"
    echo "  SNI: $domain"
    echo ""
}

list_vray_users() {
    echo ""
    echo -e "  ${BOLD}${WHITE}V2Ray TLS Users${RESET}"
    print_line

    local users
    users=$(user_list "vray")

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
# Certificate Renewal
#-------------------------------------------------------------------------------

renew_vray_cert() {
    local domain
    domain=$(server_get "vray_domain")

    if [[ -z "$domain" ]]; then
        print_error "No domain configured"
        return 1
    fi

    print_step "Renewing certificate for $domain"
    "$HOME/.acme.sh/acme.sh" --renew -d "$domain" --ecc --force 2>/dev/null

    if [[ $? -eq 0 ]]; then
        print_success "Certificate renewed"
        xray_reload
    else
        print_error "Renewal failed"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Uninstall
#-------------------------------------------------------------------------------

uninstall_vray() {
    echo ""
    echo -e "  ${BOLD}${RED}Uninstall V2Ray TLS${RESET}"
    print_line
    echo ""

    if ! is_vray_installed; then
        print_error "V2Ray TLS is not installed"
        return 1
    fi

    if ! confirm "Remove V2Ray TLS inbound and all users?"; then
        return 0
    fi

    xray_remove_inbound "$VRAY_TAG"
    xray_reload

    # Remove certificates
    if [[ -d "$CERT_DIR" ]]; then
        rm -rf "$CERT_DIR"
    fi

    # Remove users
    local users
    users=$(user_list "vray")
    if [[ -n "$users" ]]; then
        echo "$users" | while read -r u; do
            user_remove "$u" "vray"
        done
    fi

    print_success "V2Ray TLS uninstalled"
}

#-------------------------------------------------------------------------------
# Manage (Menu)
#-------------------------------------------------------------------------------

manage_vray() {
    while true; do
        clear
        load_banner "reality" 2>/dev/null || true
        echo -e "  ${BOLD}${WHITE}V2Ray TLS Management${RESET}"
        print_line
        echo ""
        echo "  1) View users and links"
        echo "  2) Add user"
        echo "  3) Remove user"
        echo "  4) Renew TLS certificate"
        echo "  5) Restart Xray"
        echo "  6) Uninstall"
        echo "  0) Back"
        echo ""

        get_input "Select [0-6]" "0" choice

        case "$choice" in
            1)
                list_vray_users
                echo ""
                get_input "Show links for user (or Enter to skip)" "" show_user
                if [[ -n "$show_user" ]]; then
                    show_vray_links "$show_user"
                fi
                press_enter
                ;;
            2)
                echo ""
                get_input "Username" "" new_user
                if [[ -n "$new_user" ]]; then
                    add_vray_user "$new_user"
                    show_vray_links "$new_user"
                fi
                press_enter
                ;;
            3)
                list_vray_users
                get_input "Username to remove" "" del_user
                if [[ -n "$del_user" ]]; then
                    remove_vray_user "$del_user"
                fi
                press_enter
                ;;
            4) renew_vray_cert; press_enter ;;
            5)
                xray_reload
                print_success "Xray restarted"
                press_enter
                ;;
            6) uninstall_vray; return 0 ;;
            0|"") return 0 ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}
