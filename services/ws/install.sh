#!/bin/bash
#===============================================================================
# DNSCloak - VLESS + WebSocket + CDN Service Installer
# https://github.com/behnamkhorsandian/DNSCloak
#
# Usage: curl -sSL ws.dnscloak.net | sudo bash
#
# Requires:
#   - Domain with Cloudflare DNS (free plan works)
#   - DNS A record pointing to server (Proxied/orange cloud)
#===============================================================================

# Download and source libraries
LIB_DIR="/tmp/dnscloak-lib"
mkdir -p "$LIB_DIR"
GITHUB_RAW="https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main"

# Always download fresh copies when piped
curl -sL "$GITHUB_RAW/lib/common.sh" -o "$LIB_DIR/common.sh"
curl -sL "$GITHUB_RAW/lib/cloud.sh" -o "$LIB_DIR/cloud.sh"
curl -sL "$GITHUB_RAW/lib/bootstrap.sh" -o "$LIB_DIR/bootstrap.sh"
curl -sL "$GITHUB_RAW/lib/xray.sh" -o "$LIB_DIR/xray.sh"

# Source libraries
source "$LIB_DIR/common.sh"
source "$LIB_DIR/cloud.sh"
source "$LIB_DIR/bootstrap.sh"
source "$LIB_DIR/xray.sh"

set -e

#-------------------------------------------------------------------------------
# WS+CDN Configuration
#-------------------------------------------------------------------------------

SERVICE_NAME="ws"
WS_PORT=443
CERT_DIR="/opt/dnscloak/certs"

#-------------------------------------------------------------------------------
# Installation Check
#-------------------------------------------------------------------------------

is_ws_installed() {
    xray_inbound_exists "ws-in"
}

#-------------------------------------------------------------------------------
# Domain Validation
#-------------------------------------------------------------------------------

validate_domain() {
    local domain="$1"
    
    # Check format
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*\.)+[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    
    return 0
}

check_domain_dns() {
    local domain="$1"
    local server_ip
    server_ip=$(get_public_ip)
    
    print_step "Checking DNS for $domain"
    
    # Get resolved IP
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
    
    # Check if it resolves to Cloudflare
    local cf_check
    cf_check=$(curl -sI "https://$domain" 2>/dev/null | grep -i "cf-ray" || true)
    
    if [[ -z "$cf_check" ]]; then
        print_warning "Domain does not appear to be proxied through Cloudflare"
        echo ""
        echo "  The orange cloud (Proxy) must be ENABLED in Cloudflare DNS."
        echo "  This is required to hide your server IP."
        echo ""
        echo -e "  Resolved to: ${YELLOW}$resolved_ip${RESET}"
        echo -e "  Server IP:   ${CYAN}$server_ip${RESET}"
        echo ""
        return 1
    fi
    
    print_success "Domain is proxied through Cloudflare"
    return 0
}

#-------------------------------------------------------------------------------
# Certificate Management (Let's Encrypt via acme.sh)
#-------------------------------------------------------------------------------

install_acme() {
    if command -v "$HOME/.acme.sh/acme.sh" &>/dev/null; then
        print_success "acme.sh already installed"
        return 0
    fi
    
    print_step "Installing acme.sh"
    curl -sL https://get.acme.sh | sh -s email=admin@localhost 2>/dev/null
    source "$HOME/.acme.sh/acme.sh.env" 2>/dev/null || true
    print_success "acme.sh installed"
}

obtain_certificate() {
    local domain="$1"
    local cert_path="$CERT_DIR/$domain"
    
    mkdir -p "$cert_path"
    
    # Check if cert exists and is valid
    if [[ -f "$cert_path/fullchain.pem" ]]; then
        local expiry
        expiry=$(openssl x509 -in "$cert_path/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        if [[ -n "$expiry" ]]; then
            local expiry_epoch
            expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null)
            local now_epoch
            now_epoch=$(date +%s)
            local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
            
            if [[ $days_left -gt 7 ]]; then
                print_success "Certificate valid for $days_left more days"
                return 0
            fi
        fi
    fi
    
    print_step "Obtaining Let's Encrypt certificate for $domain"
    
    # We need to temporarily stop any service using port 80
    local port80_pid
    port80_pid=$(lsof -ti:80 2>/dev/null || true)
    if [[ -n "$port80_pid" ]]; then
        print_warning "Port 80 in use, attempting standalone mode with webroot"
    fi
    
    # Try standalone mode first (quickest)
    if "$HOME/.acme.sh/acme.sh" --issue -d "$domain" --standalone \
        --keylength ec-256 \
        --cert-file "$cert_path/cert.pem" \
        --key-file "$cert_path/privkey.pem" \
        --fullchain-file "$cert_path/fullchain.pem" \
        --force 2>/dev/null; then
        print_success "Certificate obtained"
        return 0
    fi
    
    # Fallback: DNS mode instructions
    print_error "Could not obtain certificate automatically"
    echo ""
    echo "  Options:"
    echo "  1. Ensure port 80 is open and not in use"
    echo "  2. Use Cloudflare API token for DNS validation:"
    echo ""
    echo "     export CF_Token=\"your-api-token\""
    echo "     export CF_Zone_ID=\"your-zone-id\""
    echo "     acme.sh --issue -d $domain --dns dns_cf"
    echo ""
    return 1
}

#-------------------------------------------------------------------------------
# Generate WS Path
#-------------------------------------------------------------------------------

generate_ws_path() {
    local random_suffix
    random_suffix=$(openssl rand -hex 4)
    echo "/ws-${random_suffix}"
}

#-------------------------------------------------------------------------------
# Install WS+CDN
#-------------------------------------------------------------------------------

install_ws() {
    clear
    load_banner "ws" 2>/dev/null || echo -e "\n${BOLD}${CYAN}=== DNSCloak WS+CDN ===${RESET}\n"
    
    # Check root
    check_root
    
    # Check if already installed
    if is_ws_installed; then
        print_warning "WS+CDN is already installed"
        if ! confirm "Reinstall?"; then
            return 0
        fi
    fi
    
    # Get domain
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
        
        if ! validate_domain "$domain"; then
            print_error "Invalid domain format"
            continue
        fi
        
        if check_domain_dns "$domain"; then
            break
        fi
        
        if confirm "Try anyway?"; then
            break
        fi
    done
    
    # Bootstrap
    print_step "Setting up prerequisites"
    bootstrap_system
    setup_dnscloak_dirs
    detect_cloud_provider
    
    # Install Xray
    install_xray
    
    # Install acme.sh and get certificate
    install_acme
    if ! obtain_certificate "$domain"; then
        print_error "Cannot proceed without a valid certificate"
        exit 1
    fi
    
    # Generate WS path
    local ws_path
    ws_path=$(generate_ws_path)
    
    # Create initial user
    echo ""
    echo -e "  ${BOLD}${WHITE}Create First User${RESET}"
    print_line
    get_input "Username" "user1" first_user
    
    local uuid
    uuid=$(generate_uuid)
    
    # Configure Xray
    print_step "Configuring Xray for WS+CDN"
    
    local cert_path="$CERT_DIR/$domain"
    
    # Create inbound config
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
        "email": "${first_user}@dnscloak"
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
    "security": "tls",
    "tlsSettings": {
      "serverName": "$domain",
      "certificates": [
        {
          "certificateFile": "$cert_path/fullchain.pem",
          "keyFile": "$cert_path/privkey.pem"
        }
      ]
    }
  }
}
EOF
)
    
    xray_add_inbound "$inbound_config"
    
    # Save config to users.json
    local server_ip
    server_ip=$(get_public_ip)
    
    json_set ".server.ip" "$server_ip"
    json_set ".server.ws_domain" "$domain"
    json_set ".server.ws_path" "$ws_path"
    
    # Add user
    user_add "$first_user" "ws" "uuid" "$uuid"
    
    # Configure firewall
    print_step "Configuring firewall"
    configure_firewall $WS_PORT tcp
    configure_firewall 80 tcp  # For certificate renewal
    
    # Start/restart Xray
    print_step "Starting Xray service"
    systemctl enable xray 2>/dev/null || true
    systemctl restart xray
    
    # Verify
    sleep 2
    if systemctl is-active --quiet xray; then
        print_success "Xray is running"
    else
        print_error "Xray failed to start"
        journalctl -u xray -n 20 --no-pager
        exit 1
    fi
    
    # Show result
    show_ws_user_links "$first_user"
    show_ws_menu
}

#-------------------------------------------------------------------------------
# User Management
#-------------------------------------------------------------------------------

add_ws_user() {
    local username
    get_input "New username" "" username
    
    if [[ -z "$username" ]]; then
        print_error "Username cannot be empty"
        return 1
    fi
    
    if user_exists "$username" "ws"; then
        print_error "User '$username' already exists"
        return 1
    fi
    
    local uuid
    uuid=$(generate_uuid)
    
    # Add to Xray config
    xray_add_client "ws-in" "$uuid" "${username}@dnscloak"
    
    # Save to users.json
    user_add "$username" "ws" "uuid" "$uuid"
    
    # Reload Xray
    systemctl reload xray 2>/dev/null || systemctl restart xray
    
    print_success "User '$username' added"
    show_ws_user_links "$username"
}

remove_ws_user() {
    local users
    users=$(user_list "ws")
    
    if [[ -z "$users" ]]; then
        print_warning "No users found"
        return
    fi
    
    echo ""
    echo -e "  ${BOLD}${WHITE}Current Users${RESET}"
    print_line
    echo "$users" | while read -r u; do
        echo "  - $u"
    done
    echo ""
    
    local username
    get_input "Username to remove" "" username
    
    if ! user_exists "$username" "ws"; then
        print_error "User '$username' not found"
        return 1
    fi
    
    # Remove from Xray (using email format)
    xray_remove_client "ws-in" "${username}@dnscloak"
    
    # Remove from users.json
    user_remove "$username" "ws"
    
    # Reload Xray
    systemctl reload xray 2>/dev/null || systemctl restart xray
    
    print_success "User '$username' removed"
}

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
# Show User Links
#-------------------------------------------------------------------------------

show_ws_user_links() {
    local username="$1"
    
    if ! user_exists "$username" "ws"; then
        print_error "User '$username' not found"
        return 1
    fi
    
    local uuid domain ws_path
    uuid=$(user_get "$username" "ws" "uuid")
    domain=$(json_get ".server.ws_domain")
    ws_path=$(json_get ".server.ws_path")
    
    # Build VLESS link
    # vless://UUID@HOST:PORT?type=ws&security=tls&path=PATH&host=HOST&sni=HOST#NAME
    local encoded_path
    encoded_path=$(printf '%s' "$ws_path" | sed 's/\//%2F/g')
    
    local vless_link="vless://${uuid}@${domain}:443?type=ws&security=tls&path=${encoded_path}&host=${domain}&sni=${domain}#${username}-ws"
    
    clear
    load_banner "ws" 2>/dev/null || echo -e "\n${BOLD}${CYAN}=== DNSCloak WS+CDN ===${RESET}\n"
    
    echo ""
    echo -e "  ${BOLD}${WHITE}Connection Details: ${CYAN}$username${RESET}"
    print_line
    echo ""
    echo -e "  ${BOLD}VLESS Link:${RESET}"
    echo ""
    echo -e "  ${GREEN}$vless_link${RESET}"
    echo ""
    
    # QR Code
    if command -v qrencode &>/dev/null; then
        echo -e "  ${BOLD}${WHITE}QR Code:${RESET}"
        echo ""
        qrencode -t ANSIUTF8 "$vless_link" | sed 's/^/  /'
    fi
    
    # Manual configuration
    echo ""
    echo -e "  ${BOLD}${WHITE}Manual Configuration${RESET}"
    print_line
    echo "  Protocol: VLESS"
    echo "  Address: $domain"
    echo "  Port: 443"
    echo "  UUID: $uuid"
    echo "  Network: ws (WebSocket)"
    echo "  Path: $ws_path"
    echo "  Security: tls"
    echo "  SNI: $domain"
    echo ""
    
    # Client instructions
    echo -e "  ${BOLD}${WHITE}How to Connect${RESET}"
    print_line
    echo -e "  ${CYAN}iOS/macOS:${RESET} Hiddify (App Store) > + > Scan QR or paste link"
    echo -e "  ${GREEN}Android:${RESET}  Hiddify (Play Store) or v2rayNG > + > Scan/Import"
    echo -e "  ${BLUE}Windows:${RESET}  Hiddify (hiddify.com) > + > Paste clipboard"
    echo -e "  ${MAGENTA}Linux:${RESET}    nekoray or sing-box with config import"
    echo ""
    echo -e "  ${DIM}Tip: Traffic routes through Cloudflare - server IP is hidden${RESET}"
    echo ""
}

#-------------------------------------------------------------------------------
# Show All Links
#-------------------------------------------------------------------------------

show_all_ws_links() {
    local users
    users=$(user_list "ws")
    
    if [[ -z "$users" ]]; then
        print_warning "No users found"
        return
    fi
    
    echo "$users" | while read -r username; do
        show_ws_user_links "$username"
        echo ""
        echo -e "  ${DIM}---${RESET}"
    done
}

#-------------------------------------------------------------------------------
# Uninstall
#-------------------------------------------------------------------------------

uninstall_ws() {
    echo ""
    echo -e "  ${BOLD}${RED}Uninstall WS+CDN${RESET}"
    print_line
    echo ""
    echo "  This will remove:"
    echo "  - WS inbound from Xray config"
    echo "  - All WS users"
    echo "  - TLS certificates (optional)"
    echo ""
    
    if ! confirm "Continue?"; then
        return 0
    fi
    
    # Remove from Xray
    xray_remove_inbound "ws-in"
    
    # Remove all WS users from users.json
    local users
    users=$(user_list "ws")
    if [[ -n "$users" ]]; then
        echo "$users" | while read -r u; do
            user_remove "$u" "ws"
        done
    fi
    
    # Clear WS config from server
    json_set ".server.ws_domain" "null"
    json_set ".server.ws_path" "null"
    
    # Ask about certs
    if confirm "Remove TLS certificates?"; then
        rm -rf "$CERT_DIR" 2>/dev/null || true
        print_success "Certificates removed"
    fi
    
    # Reload Xray
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
    current_domain=$(json_get ".server.ws_domain")
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
        
        if ! validate_domain "$new_domain"; then
            print_error "Invalid domain format"
            continue
        fi
        
        if check_domain_dns "$new_domain"; then
            break
        fi
        
        if confirm "Try anyway?"; then
            break
        fi
    done
    
    # Get new certificate
    if ! obtain_certificate "$new_domain"; then
        print_error "Could not obtain certificate for $new_domain"
        return 1
    fi
    
    # Update Xray config
    local cert_path="$CERT_DIR/$new_domain"
    local ws_path
    ws_path=$(json_get ".server.ws_path")
    
    # We need to update the inbound config
    # Simplest approach: regenerate the inbound
    
    # Get existing clients
    local clients
    clients=$(jq -c '.inbounds[] | select(.tag == "ws-in") | .settings.clients' "$XRAY_CONFIG" 2>/dev/null || echo "[]")
    
    # Remove old inbound
    xray_remove_inbound "ws-in"
    
    # Create new inbound with updated domain
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
    "security": "tls",
    "tlsSettings": {
      "serverName": "$new_domain",
      "certificates": [
        {
          "certificateFile": "$cert_path/fullchain.pem",
          "keyFile": "$cert_path/privkey.pem"
        }
      ]
    }
  }
}
EOF
)
    
    xray_add_inbound "$inbound_config"
    
    # Update users.json
    json_set ".server.ws_domain" "$new_domain"
    
    # Reload Xray
    systemctl reload xray 2>/dev/null || systemctl restart xray
    
    print_success "Domain changed to $new_domain"
    echo ""
    echo "  All user links now use the new domain."
    echo ""
}

#-------------------------------------------------------------------------------
# Status
#-------------------------------------------------------------------------------

show_ws_status() {
    echo ""
    echo -e "  ${BOLD}${WHITE}WS+CDN Status${RESET}"
    print_line
    
    # Service status
    if systemctl is-active --quiet xray; then
        echo -e "  Xray:      ${GREEN}Running${RESET}"
    else
        echo -e "  Xray:      ${RED}Stopped${RESET}"
    fi
    
    # Domain
    local domain
    domain=$(json_get ".server.ws_domain")
    echo -e "  Domain:    ${CYAN}$domain${RESET}"
    
    # Certificate
    local cert_path="$CERT_DIR/$domain"
    if [[ -f "$cert_path/fullchain.pem" ]]; then
        local expiry
        expiry=$(openssl x509 -in "$cert_path/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        echo -e "  TLS Cert:  ${GREEN}Valid until $expiry${RESET}"
    else
        echo -e "  TLS Cert:  ${RED}Not found${RESET}"
    fi
    
    # User count
    local user_count
    user_count=$(user_list "ws" | wc -l | tr -d ' ')
    echo -e "  Users:     $user_count"
    
    # Test connection
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
# Menu
#-------------------------------------------------------------------------------

show_ws_menu() {
    while true; do
        echo ""
        echo -e "  ${BOLD}${WHITE}WS+CDN Management${RESET}"
        print_line
        echo ""
        echo "  1) Add user"
        echo "  2) Remove user"
        echo "  3) List users"
        echo "  4) Show user links"
        echo "  5) Show all links"
        echo "  6) Change domain"
        echo "  7) Service status"
        echo "  8) Renew certificate"
        echo "  9) Uninstall"
        echo "  0) Exit"
        echo ""
        
        local choice
        get_input "Select [0-9]" "" choice
        
        case $choice in
            1) add_ws_user ;;
            2) remove_ws_user ;;
            3) list_ws_users ;;
            4)
                local username
                get_input "Username" "" username
                show_ws_user_links "$username"
                ;;
            5) show_all_ws_links ;;
            6) change_ws_domain ;;
            7) show_ws_status ;;
            8)
                local domain
                domain=$(json_get ".server.ws_domain")
                obtain_certificate "$domain"
                systemctl reload xray 2>/dev/null || true
                ;;
            9) uninstall_ws; break ;;
            0) break ;;
            *) print_error "Invalid option" ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    clear
    
    # Check for existing installation
    if is_ws_installed; then
        load_banner "ws" 2>/dev/null || echo -e "\n${BOLD}${CYAN}=== DNSCloak WS+CDN ===${RESET}\n"
        show_ws_menu
    else
        install_ws
    fi
}

# Run main
main "$@"
