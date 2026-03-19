#!/bin/bash
#===============================================================================
# Vany - VLESS + REALITY Functions
# Sourced by start.sh or install.sh - do not run directly
#===============================================================================

SERVICE_NAME="reality"
REALITY_PORT=443

CAMOUFLAGE_TARGETS=(
    "www.google.com"
    "www.microsoft.com"
    "www.apple.com"
    "www.cloudflare.com"
    "www.mozilla.org"
    "www.amazon.com"
)

#-------------------------------------------------------------------------------
# Checks
#-------------------------------------------------------------------------------

is_reality_installed() {
    xray_inbound_exists "reality-in"
}

#-------------------------------------------------------------------------------
# Key Generation
#-------------------------------------------------------------------------------

generate_reality_keys() {
    print_step "Generating x25519 keypair"

    local keys
    keys=$("$XRAY_BIN" x25519 2>/dev/null)

    REALITY_PRIVATE_KEY=$(echo "$keys" | grep "Private key:" | awk '{print $3}')
    REALITY_PUBLIC_KEY=$(echo "$keys" | grep "Public key:" | awk '{print $3}')

    if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_PUBLIC_KEY" ]]; then
        print_error "Failed to generate keys"
        return 1
    fi

    print_success "Keys generated"
}

#-------------------------------------------------------------------------------
# Camouflage Target
#-------------------------------------------------------------------------------

select_camouflage_target() {
    print_step "Selecting camouflage target"

    echo ""
    echo "  Available targets:"
    local i=1
    for target in "${CAMOUFLAGE_TARGETS[@]}"; do
        echo "    $i) $target"
        ((i++))
    done
    echo ""

    get_input "Select target (1-${#CAMOUFLAGE_TARGETS[@]})" "1" choice

    if [[ "$choice" -ge 1 && "$choice" -le "${#CAMOUFLAGE_TARGETS[@]}" ]]; then
        REALITY_TARGET="${CAMOUFLAGE_TARGETS[$((choice-1))]}"
    else
        REALITY_TARGET="${CAMOUFLAGE_TARGETS[0]}"
    fi

    print_success "Target: $REALITY_TARGET"
}

#-------------------------------------------------------------------------------
# Connection Address
#-------------------------------------------------------------------------------

configure_connection_address() {
    local server_ip
    server_ip=$(server_get "ip")

    echo ""
    print_info "Your server IP: $server_ip"
    echo ""

    if confirm "Use a domain instead of IP in links?"; then
        echo ""
        echo -e "  ${YELLOW}Note: Create an A record pointing to $server_ip${RESET}"
        echo -e "  ${YELLOW}      Keep Cloudflare proxy OFF (gray cloud)${RESET}"
        echo ""

        get_input "Enter domain (e.g., proxy.example.com)" "" connection_domain

        if [[ -n "$connection_domain" ]]; then
            if [[ "$connection_domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
                server_set "reality_address" "$connection_domain"
                print_success "Will use domain: $connection_domain"
            else
                print_warning "Invalid domain format, using IP instead"
                server_set "reality_address" "$server_ip"
            fi
        else
            server_set "reality_address" "$server_ip"
        fi
    else
        server_set "reality_address" "$server_ip"
    fi
}

generate_short_id() {
    head -c 8 /dev/urandom | xxd -p | tr -d '\n'
}

#-------------------------------------------------------------------------------
# Install
#-------------------------------------------------------------------------------

install_reality() {
    clear
    load_banner "reality" 2>/dev/null || true
    echo -e "  ${BOLD}${WHITE}VLESS + REALITY Installation${RESET}"
    print_line
    echo ""

    bootstrap

    if is_reality_installed; then
        print_warning "Reality is already installed"
        if confirm "Reinstall?"; then
            xray_remove_inbound "reality-in"
        else
            manage_reality
            return
        fi
    fi

    generate_reality_keys
    select_camouflage_target
    configure_connection_address

    REALITY_SHORT_ID=$(generate_short_id)

    print_step "Configuring Xray"
    xray_add_reality_inbound "$REALITY_PRIVATE_KEY" "$REALITY_TARGET" "[\"$REALITY_SHORT_ID\"]"

    server_set "reality_public_key" "$REALITY_PUBLIC_KEY"
    server_set "reality_target" "$REALITY_TARGET"
    server_set "reality_short_id" "$REALITY_SHORT_ID"

    print_step "Starting Xray service"
    service_enable xray
    sleep 2

    if [[ "$(service_status xray)" == "active" ]]; then
        print_success "Xray started"
    else
        print_error "Xray failed to start"
        print_info "Check logs: journalctl -u xray -n 50"
        return 1
    fi

    echo ""
    print_step "Create first user"
    get_input "Username" "user1" first_username
    add_reality_user "$first_username"

    print_line
    print_success "Reality installation complete!"
    echo ""
    show_reality_links "$first_username"

    echo ""
    print_info "Add more users: vany add reality <username>"
    print_info "View links: vany links <username>"
    echo ""

    if confirm "Open management menu?"; then
        manage_reality
    fi
}

#-------------------------------------------------------------------------------
# User CRUD
#-------------------------------------------------------------------------------

add_reality_user() {
    local username="$1"

    if [[ -z "$username" ]]; then
        print_error "Username required"
        return 1
    fi

    if user_exists "$username" "reality"; then
        print_warning "User '$username' already exists in Reality"
        return 1
    fi

    local uuid
    uuid=$(random_uuid)

    xray_add_client "reality-in" "$uuid" "${username}@vany" "xtls-rprx-vision"
    user_add "$username" "reality" "{\"uuid\": \"$uuid\", \"flow\": \"xtls-rprx-vision\"}"
    xray_reload

    print_success "User '$username' added to Reality"
}

remove_reality_user() {
    local username="$1"

    if [[ -z "$username" ]]; then
        print_error "Username required"
        return 1
    fi

    xray_remove_client "reality-in" "${username}@vany"
    user_remove "$username" "reality"
    xray_reload

    print_success "User '$username' removed from Reality"
}

show_reality_links() {
    local username="$1"

    local creds
    creds=$(user_get "$username" "reality")
    if [[ -z "$creds" || "$creds" == "null" ]]; then
        print_error "User '$username' not found in Reality"
        return 1
    fi

    local uuid server_address pubkey target sid
    uuid=$(echo "$creds" | jq -r '.uuid')
    server_address=$(server_get "reality_address")
    if [[ -z "$server_address" || "$server_address" == "null" ]]; then
        server_address=$(server_get "ip")
    fi
    pubkey=$(server_get "reality_public_key")
    target=$(server_get "reality_target")
    sid=$(server_get "reality_short_id")

    local link
    link=$(xray_reality_link "$uuid" "$server_address" "$pubkey" "$target" "$sid" "$username")

    echo ""
    echo -e "  ${BOLD}${WHITE}Reality Link for '$username'${RESET}"
    print_line
    echo ""
    echo -e "  ${CYAN}$link${RESET}"
    echo ""

    if command -v qrencode &>/dev/null; then
        echo "  QR Code:"
        qrencode -t ANSIUTF8 "$link" | sed 's/^/  /'
    fi

    echo ""
    echo "  Manual Configuration:"
    echo "  ---------------------"
    echo "  Address: $server_address"
    echo "  Port: 443"
    echo "  UUID: $uuid"
    echo "  Flow: xtls-rprx-vision"
    echo "  Security: reality"
    echo "  SNI: $target"
    echo "  Public Key: $pubkey"
    echo "  Short ID: $sid"
    echo "  Fingerprint: chrome"
    echo ""
    echo -e "  ${BOLD}${WHITE}How to Connect${RESET}"
    print_line
    echo -e "  ${CYAN}iOS/macOS:${RESET} Hiddify (App Store) > + > Scan QR or paste link"
    echo -e "  ${GREEN}Android:${RESET}  Hiddify (Play Store) or v2rayNG > + > Scan/Import"
    echo -e "  ${BLUE}Windows:${RESET}  Hiddify (hiddify.com) > + > Paste clipboard"
    echo -e "  ${MAGENTA}Linux:${RESET}    nekoray or sing-box with config import"
    echo ""
}

list_reality_users() {
    echo ""
    echo -e "  ${BOLD}${WHITE}Reality Users${RESET}"
    print_line

    local users
    users=$(user_list "reality")

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

uninstall_reality() {
    echo ""
    echo -e "  ${BOLD}${WHITE}Uninstall Reality${RESET}"
    print_line
    echo ""

    if ! is_reality_installed; then
        print_error "Reality is not installed"
        return 1
    fi

    if ! confirm "Remove Reality service and all users?"; then
        return 0
    fi

    xray_remove_inbound "reality-in"

    local users
    users=$(user_list "reality")
    if [[ -n "$users" ]]; then
        echo "$users" | while read -r username; do
            [[ -n "$username" ]] && user_remove "$username" "reality"
        done
    fi

    local remaining_inbounds
    remaining_inbounds=$(jq '.inbounds | length' "$XRAY_CONFIG")

    if [[ "$remaining_inbounds" == "0" ]]; then
        service_disable xray
        print_info "Xray stopped (no remaining services)"
    else
        xray_reload
    fi

    print_success "Reality uninstalled"
}

#-------------------------------------------------------------------------------
# Change Address
#-------------------------------------------------------------------------------

change_reality_address() {
    local current_address server_ip
    current_address=$(server_get "reality_address")
    server_ip=$(server_get "ip")

    echo ""
    echo "  Current address in links: ${current_address:-$server_ip}"
    echo "  Server IP: $server_ip"
    echo ""
    echo "  1) Use IP address ($server_ip)"
    echo "  2) Use custom domain"
    echo "  0) Cancel"
    echo ""

    get_input "Select option" "0" addr_choice

    case "$addr_choice" in
        1)
            server_set "reality_address" "$server_ip"
            print_success "Links will now use IP: $server_ip"
            ;;
        2)
            echo ""
            echo -e "  ${YELLOW}Note: Create an A record pointing to $server_ip${RESET}"
            echo -e "  ${YELLOW}      Keep Cloudflare proxy OFF (gray cloud)${RESET}"
            echo ""
            get_input "Enter domain" "" new_domain
            if [[ -n "$new_domain" ]]; then
                if [[ "$new_domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
                    server_set "reality_address" "$new_domain"
                    print_success "Links will now use domain: $new_domain"
                else
                    print_error "Invalid domain format"
                fi
            fi
            ;;
    esac
}

#-------------------------------------------------------------------------------
# Manage (Menu)
#-------------------------------------------------------------------------------

manage_reality() {
    while true; do
        clear
        load_banner "reality" 2>/dev/null || true
        echo -e "  ${BOLD}${WHITE}Reality Management${RESET}"
        print_line
        echo ""
        echo "  1) View users and links"
        echo "  2) Add user"
        echo "  3) Remove user"
        echo "  4) Change connection address (IP/domain)"
        echo "  5) Show service status"
        echo "  6) Restart service"
        echo "  7) Uninstall Reality"
        echo "  0) Back"
        echo ""

        get_input "Select option" "0" choice

        case "$choice" in
            1)
                list_reality_users
                echo ""
                get_input "Show links for user (or Enter to skip)" "" show_user
                if [[ -n "$show_user" ]]; then
                    show_reality_links "$show_user"
                fi
                press_enter
                ;;
            2)
                echo ""
                get_input "Username" "" new_user
                if [[ -n "$new_user" ]]; then
                    add_reality_user "$new_user"
                    show_reality_links "$new_user"
                fi
                press_enter
                ;;
            3)
                list_reality_users
                get_input "Username to remove" "" del_user
                if [[ -n "$del_user" ]]; then
                    remove_reality_user "$del_user"
                fi
                press_enter
                ;;
            4)
                change_reality_address
                press_enter
                ;;
            5)
                echo ""
                echo "  Xray Status: $(service_status xray)"
                echo ""
                xray_status
                press_enter
                ;;
            6)
                service_restart xray
                print_success "Xray restarted"
                press_enter
                ;;
            7)
                uninstall_reality
                return 0
                ;;
            0|"")
                return 0
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}
