#!/bin/bash
#===============================================================================
# Vany - VLESS + WebSocket + CDN Functions
# Sourced by start.sh or install.sh - do not run directly
#===============================================================================

SERVICE_NAME="ws"
WS_PORT=80
CERT_DIR="/opt/vany/certs"

#-------------------------------------------------------------------------------
# Checks
#-------------------------------------------------------------------------------

is_ws_installed() {
    xray_inbound_exists "ws-in"
}

#-------------------------------------------------------------------------------
# Domain Validation
#-------------------------------------------------------------------------------

validate_ws_domain() {
    local domain="$1"
    [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*\.)+[a-zA-Z]{2,}$ ]]
}

check_ws_domain_dns() {
    local domain="$1"
    local server_ip
    server_ip=$(cloud_get_public_ip)

    print_step "Checking DNS for $domain"

    local resolved_ip
    resolved_ip=$(dig +short "$domain" A 2>/dev/null | head -1)

    if [[ -z "$resolved_ip" ]]; then
        print_warning "Domain does not resolve. Please set up DNS first."
        echo ""
        echo -e "  ${BOLD}Required DNS record:${RESET}"
        echo -e "  Type: A"
        echo -e "  Name: ${CYAN}$domain${RESET}"
        echo -e "  Value: ${CYAN}$server_ip${RESET}"
        echo -e "  Proxy: ${GREEN}Proxied (orange cloud)${RESET}"
        echo ""
        return 1
    fi

    local cf_check
    cf_check=$(curl -sI "https://$domain" 2>/dev/null | grep -i "cf-ray" || true)

    if [[ -z "$cf_check" ]]; then
        print_warning "Domain does not appear to be proxied through Cloudflare"
        echo ""
        echo "  The orange cloud (Proxy) must be ENABLED in Cloudflare DNS."
        echo ""
        return 1
    fi

    print_success "Domain is proxied through Cloudflare"
    return 0
}

#-------------------------------------------------------------------------------
# Certificate
#-------------------------------------------------------------------------------

generate_ws_self_signed_cert() {
    local domain="$1"
    local cert_path="$CERT_DIR/$domain"

    mkdir -p "$cert_path"

    if [[ -f "$cert_path/fullchain.pem" ]]; then
        local expiry expiry_epoch now_epoch days_left
        expiry=$(openssl x509 -in "$cert_path/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        if [[ -n "$expiry" ]]; then
            expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null)
            now_epoch=$(date +%s)
            days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
            if [[ $days_left -gt 7 ]]; then
                print_success "Certificate valid for $days_left more days"
                return 0
            fi
        fi
    fi

    print_step "Generating TLS certificate for $domain"

    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout "$cert_path/privkey.pem" \
        -out "$cert_path/fullchain.pem" \
        -sha256 -days 3650 \
        -subj "/CN=$domain" \
        -addext "subjectAltName=DNS:$domain" \
        2>/dev/null

    if [[ -f "$cert_path/fullchain.pem" ]]; then
        print_success "Certificate generated"
        return 0
    else
        print_error "Failed to generate certificate"
        return 1
    fi
}

generate_ws_path() {
    local random_suffix
    random_suffix=$(openssl rand -hex 4)
    echo "/ws-${random_suffix}"
}

#-------------------------------------------------------------------------------
# Non-interactive install (called by TUI wizard)
# Usage: install_ws_service <domain>
#-------------------------------------------------------------------------------

install_ws_service() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        print_error "Domain required"
        return 1
    fi

    if type bootstrap &>/dev/null; then
        bootstrap
    fi

    local uuid ws_path
    uuid=$(random_uuid)
    ws_path=$(generate_ws_path)

    local inbound_config
    inbound_config=$(cat <<EOF
{
  "tag": "ws-in",
  "port": $WS_PORT,
  "protocol": "vless",
  "settings": {
    "clients": [],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "ws",
    "wsSettings": {
      "path": "$ws_path",
      "headers": {
        "Host": "$domain"
      }
    },
    "security": "none"
  }
}
EOF
)

    xray_add_inbound "$inbound_config"

    local server_ip
    server_ip=$(cloud_get_public_ip 2>/dev/null || server_get "ip")

    server_set "ip" "$server_ip" 2>/dev/null || true
    server_set "ws_domain" "$domain"
    server_set "ws_path" "$ws_path"

    # Open firewall
    if type cloud_open_port &>/dev/null; then
        cloud_open_port $WS_PORT tcp
    fi

    # Start Xray
    systemctl enable xray 2>/dev/null || true
    systemctl restart xray

    sleep 2
    if systemctl is-active --quiet xray; then
        print_success "Xray is running with WS+CDN"
    else
        print_error "Xray failed to start"
        journalctl -u xray -n 20 --no-pager 2>/dev/null || true
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Interactive install (standalone / CLI mode)
#-------------------------------------------------------------------------------

install_ws() {
    clear
    load_banner "ws" 2>/dev/null || true
    echo -e "  ${BOLD}${WHITE}VLESS + WS + CDN Installation${RESET}"
    print_line
    echo ""

    bootstrap

    if is_ws_installed; then
        print_warning "WS+CDN is already installed"
        if ! confirm "Reinstall?"; then
            manage_ws
            return
        fi
    fi

    echo ""
    echo -e "  ${BOLD}${WHITE}Domain Setup${RESET}"
    print_line
    echo ""
    echo "  This service requires a domain proxied through Cloudflare."
    echo "  Your server IP will be hidden behind Cloudflare's network."
    echo ""

    local domain=""
    while true; do
        get_input "Enter your domain (e.g., ws.example.com)" "" domain

        if [[ -z "$domain" ]]; then
            print_error "Domain cannot be empty"
            continue
        fi

        if ! validate_ws_domain "$domain"; then
            print_error "Invalid domain format"
            continue
        fi

        if check_ws_domain_dns "$domain"; then
            break
        fi

        if confirm "Try anyway?"; then
            break
        fi
    done

    echo ""
    echo -e "  ${BOLD}${WHITE}Create First User${RESET}"
    print_line
    get_input "Username" "user1" first_user

    local uuid ws_path
    uuid=$(random_uuid)
    ws_path=$(generate_ws_path)

    print_step "Configuring Xray for WS+CDN"

    local inbound_config
    inbound_config=$(cat <<EOF
{
  "tag": "ws-in",
  "port": $WS_PORT,
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id": "$uuid",
        "email": "${first_user}@vany"
      }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "ws",
    "wsSettings": {
      "path": "$ws_path",
      "headers": {
        "Host": "$domain"
      }
    },
    "security": "none"
  }
}
EOF
)

    xray_add_inbound "$inbound_config"

    local server_ip
    server_ip=$(cloud_get_public_ip)

    server_set "ip" "$server_ip"
    server_set "ws_domain" "$domain"
    server_set "ws_path" "$ws_path"

    user_add "$first_user" "ws" "{\"uuid\": \"$uuid\"}"

    print_step "Configuring firewall"
    cloud_open_port $WS_PORT tcp

    print_step "Starting Xray service"
    systemctl enable xray 2>/dev/null || true
    systemctl restart xray

    sleep 2
    if systemctl is-active --quiet xray; then
        print_success "Xray is running"
    else
        print_error "Xray failed to start"
        journalctl -u xray -n 20 --no-pager
        return 1
    fi

    echo ""
    echo -e "  ${YELLOW}IMPORTANT: Cloudflare SSL/TLS Settings${RESET}"
    print_line
    echo "  Go to Cloudflare Dashboard > SSL/TLS > Overview"
    echo "  Set encryption mode to: ${BOLD}Flexible${RESET}"
    echo ""

    show_ws_user_links "$first_user"

    echo ""
    print_info "Add more users: vany add ws <username>"
    echo ""

    if confirm "Open management menu?"; then
        manage_ws
    fi
}

#-------------------------------------------------------------------------------
# User CRUD
#-------------------------------------------------------------------------------

add_ws_user() {
    local username="$1"

    if [[ -z "$username" ]]; then
        get_input "New username" "" username
    fi

    if [[ -z "$username" ]]; then
        print_error "Username cannot be empty"
        return 1
    fi

    if user_exists "$username" "ws"; then
        print_error "User '$username' already exists"
        return 1
    fi

    local uuid
    uuid=$(random_uuid)

    xray_add_client "ws-in" "$uuid" "${username}@vany"
    user_add "$username" "ws" "{\"uuid\": \"$uuid\"}"

    systemctl reload xray 2>/dev/null || systemctl restart xray

    print_success "User '$username' added"
    show_ws_user_links "$username"
}

remove_ws_user() {
    local username="$1"

    if [[ -z "$username" ]]; then
        local users
        users=$(user_list "ws")
        if [[ -z "$users" ]]; then
            print_warning "No users found"
            return
        fi
        echo ""
        echo -e "  ${BOLD}${WHITE}Current Users${RESET}"
        print_line
        echo "$users" | while read -r u; do echo "  - $u"; done
        echo ""
        get_input "Username to remove" "" username
    fi

    if ! user_exists "$username" "ws"; then
        print_error "User '$username' not found"
        return 1
    fi

    xray_remove_client "ws-in" "${username}@vany"
    user_remove "$username" "ws"
    systemctl reload xray 2>/dev/null || systemctl restart xray

    print_success "User '$username' removed"
}

show_ws_user_links() {
    local username="$1"

    if ! user_exists "$username" "ws"; then
        print_error "User '$username' not found"
        return 1
    fi

    local uuid domain ws_path
    uuid=$(user_get "$username" "ws" "uuid")
    domain=$(server_get "ws_domain")
    ws_path=$(server_get "ws_path")

    local encoded_path
    encoded_path=$(printf '%s' "$ws_path" | sed 's/\//%2F/g')
    local vless_link="vless://${uuid}@${domain}:443?type=ws&security=tls&path=${encoded_path}&host=${domain}&sni=${domain}#${username}-ws"

    echo ""
    echo -e "  ${BOLD}${WHITE}WS+CDN Link for '$username'${RESET}"
    print_line
    echo ""
    echo -e "  ${GREEN}$vless_link${RESET}"
    echo ""

    if command -v qrencode &>/dev/null; then
        echo "  QR Code:"
        qrencode -t ANSIUTF8 "$vless_link" | sed 's/^/  /'
    fi

    echo ""
    echo "  Manual Configuration:"
    echo "  ---------------------"
    echo "  Protocol: VLESS"
    echo "  Address: $domain"
    echo "  Port: 443"
    echo "  UUID: $uuid"
    echo "  Network: ws (WebSocket)"
    echo "  Path: $ws_path"
    echo "  Security: tls"
    echo "  SNI: $domain"
    echo ""
    echo -e "  ${BOLD}${WHITE}How to Connect${RESET}"
    print_line
    echo -e "  ${CYAN}iOS/macOS:${RESET} Hiddify (App Store) > + > Scan QR or paste link"
    echo -e "  ${GREEN}Android:${RESET}  Hiddify (Play Store) or v2rayNG > + > Scan/Import"
    echo -e "  ${BLUE}Windows:${RESET}  Hiddify (hiddify.com) > + > Paste clipboard"
    echo -e "  ${MAGENTA}Linux:${RESET}    nekoray or sing-box with config import"
    echo ""
}

# Alias for consistent naming with other protocols
show_ws_links() { show_ws_user_links "$@"; }

list_ws_users() {
    echo ""
    echo -e "  ${BOLD}${WHITE}WS+CDN Users${RESET}"
    print_line

    local users
    users=$(user_list "ws")

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

uninstall_ws() {
    echo ""
    echo -e "  ${BOLD}${RED}Uninstall WS+CDN${RESET}"
    print_line
    echo ""

    if ! is_ws_installed; then
        print_error "WS+CDN is not installed"
        return 1
    fi

    if ! confirm "Remove WS+CDN service and all users?"; then
        return 0
    fi

    xray_remove_inbound "ws-in"

    local users
    users=$(user_list "ws")
    if [[ -n "$users" ]]; then
        echo "$users" | while read -r u; do
            user_remove "$u" "ws"
        done
    fi

    server_set "ws_domain" "null"
    server_set "ws_path" "null"

    if confirm "Remove TLS certificates?"; then
        rm -rf "$CERT_DIR" 2>/dev/null || true
        print_success "Certificates removed"
    fi

    systemctl reload xray 2>/dev/null || systemctl restart xray

    print_success "WS+CDN service uninstalled"
}

#-------------------------------------------------------------------------------
# Change Domain
#-------------------------------------------------------------------------------

change_ws_domain() {
    echo ""
    echo -e "  ${BOLD}${WHITE}Change WS Domain${RESET}"
    print_line

    local current_domain
    current_domain=$(server_get "ws_domain")
    echo ""
    echo -e "  Current domain: ${CYAN}$current_domain${RESET}"
    echo ""

    local new_domain=""
    while true; do
        get_input "New domain (e.g., ws.example.com)" "" new_domain

        if [[ -z "$new_domain" || "$new_domain" == "$current_domain" ]]; then
            echo "  Keeping current domain"
            return 0
        fi

        if ! validate_ws_domain "$new_domain"; then
            print_error "Invalid domain format"
            continue
        fi

        if check_ws_domain_dns "$new_domain"; then
            break
        fi

        if confirm "Try anyway?"; then
            break
        fi
    done

    local ws_path clients
    ws_path=$(server_get "ws_path")
    clients=$(jq -c '.inbounds[] | select(.tag == "ws-in") | .settings.clients' "$XRAY_CONFIG" 2>/dev/null || echo "[]")

    xray_remove_inbound "ws-in"

    local inbound_config
    inbound_config=$(cat <<EOF
{
  "tag": "ws-in",
  "port": $WS_PORT,
  "protocol": "vless",
  "settings": {
    "clients": $clients,
    "decryption": "none"
  },
  "streamSettings": {
    "network": "ws",
    "wsSettings": {
      "path": "$ws_path",
      "headers": {
        "Host": "$new_domain"
      }
    },
    "security": "none"
  }
}
EOF
)

    xray_add_inbound "$inbound_config"
    server_set "ws_domain" "$new_domain"
    systemctl reload xray 2>/dev/null || systemctl restart xray

    print_success "Domain changed to $new_domain"
}

#-------------------------------------------------------------------------------
# Status
#-------------------------------------------------------------------------------

show_ws_status() {
    echo ""
    echo -e "  ${BOLD}${WHITE}WS+CDN Status${RESET}"
    print_line

    if systemctl is-active --quiet xray; then
        echo -e "  Xray:      ${GREEN}Running${RESET}"
    else
        echo -e "  Xray:      ${RED}Stopped${RESET}"
    fi

    local domain
    domain=$(server_get "ws_domain")
    echo -e "  Domain:    ${CYAN}$domain${RESET}"

    local user_count
    user_count=$(user_list "ws" | wc -l | tr -d ' ')
    echo -e "  Users:     $user_count"

    echo ""
    echo -e "  ${DIM}Testing connection...${RESET}"
    if curl -sI "https://$domain" 2>/dev/null | grep -q "HTTP"; then
        echo -e "  Cloudflare: ${GREEN}Reachable${RESET}"
    else
        echo -e "  Cloudflare: ${YELLOW}Check DNS settings${RESET}"
    fi
    echo ""
}

#-------------------------------------------------------------------------------
# Manage (Menu)
#-------------------------------------------------------------------------------

manage_ws() {
    while true; do
        clear
        load_banner "ws" 2>/dev/null || true
        echo -e "  ${BOLD}${WHITE}WS+CDN Management${RESET}"
        print_line
        echo ""
        echo "  1) Add user"
        echo "  2) Remove user"
        echo "  3) List users"
        echo "  4) Show user links"
        echo "  5) Change domain"
        echo "  6) Service status"
        echo "  7) Restart Xray"
        echo "  8) Uninstall"
        echo "  0) Back"
        echo ""

        local choice
        get_input "Select [0-8]" "0" choice

        case $choice in
            1) add_ws_user ""; press_enter ;;
            2) remove_ws_user ""; press_enter ;;
            3) list_ws_users; press_enter ;;
            4)
                local username
                get_input "Username" "" username
                if [[ -n "$username" ]]; then
                    show_ws_user_links "$username"
                fi
                press_enter
                ;;
            5) change_ws_domain; press_enter ;;
            6) show_ws_status; press_enter ;;
            7)
                systemctl reload xray 2>/dev/null || systemctl restart xray
                print_success "Xray restarted"
                press_enter
                ;;
            8) uninstall_ws; return 0 ;;
            0|"") return 0 ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}
