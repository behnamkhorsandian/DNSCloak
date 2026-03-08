#!/bin/bash
#===============================================================================
# DNSCloak - Unified Management CLI
# https://github.com/behnamkhorsandian/DNSCloak
#
# Usage:
#   dnscloak                         - Interactive TUI menu
#   dnscloak <command> [service] [options]
#
# Commands:
#   add <service> <username>     - Add user to service
#   remove <service> <username>  - Remove user from service
#   list [service]               - List users (optionally filter by service)
#   links <username> [service]   - Show connection links for user
#   status [service]             - Show service status
#   restart <service>            - Restart a service
#   install <service>            - Install a service
#   manage <service>             - Open service management menu
#   uninstall <service>          - Uninstall a service
#   services                     - List installed services
#   help                         - Show this help
#
# Services: reality, ws, wg, dnstt, mtp, vray, conduit
#===============================================================================

set -e

# Paths (respect environment overrides for testing)
DNSCLOAK_DIR="${DNSCLOAK_DIR:-/opt/dnscloak}"
DNSCLOAK_USERS="${DNSCLOAK_USERS:-$DNSCLOAK_DIR/users.json}"
LIB_DIR="${LIB_DIR:-$DNSCLOAK_DIR/lib}"
SERVICES_DIR="${SERVICES_DIR:-$DNSCLOAK_DIR/services}"
BANNERS_DIR="${BANNERS_DIR:-$DNSCLOAK_DIR/banners}"
GITHUB_RAW="https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main"

# Version
VERSION="2.1.0"

# All protocols
ALL_PROTOCOLS="reality ws wg dnstt mtp vray conduit"

#-------------------------------------------------------------------------------
# Source Libraries
#-------------------------------------------------------------------------------

source_libs() {
    if [[ -f "$LIB_DIR/common.sh" ]]; then
        source "$LIB_DIR/common.sh"
        source "$LIB_DIR/cloud.sh" 2>/dev/null || true
        source "$LIB_DIR/xray.sh" 2>/dev/null || true
    else
        # Try repo-relative path (for development/testing)
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local repo_lib="$script_dir/../lib"
        if [[ -f "$repo_lib/common.sh" ]]; then
            source "$repo_lib/common.sh"
            source "$repo_lib/cloud.sh" 2>/dev/null || true
            source "$repo_lib/xray.sh" 2>/dev/null || true
        else
            # Download libs if not available
            mkdir -p "$LIB_DIR"
            curl -sL "$GITHUB_RAW/lib/common.sh" -o "$LIB_DIR/common.sh"
            curl -sL "$GITHUB_RAW/lib/cloud.sh" -o "$LIB_DIR/cloud.sh"
            curl -sL "$GITHUB_RAW/lib/xray.sh" -o "$LIB_DIR/xray.sh"
            source "$LIB_DIR/common.sh"
            source "$LIB_DIR/cloud.sh" 2>/dev/null || true
            source "$LIB_DIR/xray.sh" 2>/dev/null || true
        fi
    fi
}

source_service_functions() {
    local service="$1"
    local func_file="$SERVICES_DIR/$service/functions.sh"

    if [[ -f "$func_file" ]]; then
        source "$func_file"
        return 0
    fi

    # Download if not on disk
    mkdir -p "$SERVICES_DIR/$service"
    if curl -sL "$GITHUB_RAW/services/$service/functions.sh" -o "$func_file" 2>/dev/null; then
        source "$func_file"
        return 0
    fi

    return 1
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
    if [[ ! " $ALL_PROTOCOLS " =~ " $service " ]]; then
        error "Unknown service: $service. Valid services: $ALL_PROTOCOLS"
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
        conduit)
            [[ -f "/usr/local/bin/conduit" ]] && systemctl is-enabled --quiet conduit 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

get_installed_services() {
    local installed=""
    for svc in reality ws wg dnstt mtp vray conduit; do
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
    
    if [[ "$service" == "conduit" ]]; then
        error "Conduit is a relay node and doesn't support per-user management."
    fi
    
    if [[ -z "$username" ]]; then
        error "Username required. Usage: dnscloak add $service <username>"
    fi
    
    if ! is_service_installed "$service"; then
        error "Service '$service' is not installed. Install it first: dnscloak install $service"
    fi
    
    source_libs
    source_service_functions "$service" || error "Functions not available for $service"

    local func_name="add_${service}_user"
    if declare -f "$func_name" >/dev/null 2>&1; then
        "$func_name" "$username"
    else
        error "Add user not implemented for service: $service"
    fi
}

# Generic remove user function
remove_user() {
    local service="$1"
    local username="$2"
    
    if [[ "$service" == "conduit" ]]; then
        error "Conduit is a relay node and doesn't support per-user management."
    fi
    
    if [[ -z "$username" ]]; then
        error "Username required. Usage: dnscloak remove $service <username>"
    fi
    
    if ! is_service_installed "$service"; then
        error "Service '$service' is not installed"
    fi
    
    source_libs
    source_service_functions "$service" || error "Functions not available for $service"

    local func_name="remove_${service}_user"
    if declare -f "$func_name" >/dev/null 2>&1; then
        "$func_name" "$username"
    else
        error "Remove user not implemented for service: $service"
    fi
}

#-------------------------------------------------------------------------------
# List Users
#-------------------------------------------------------------------------------

list_users() {
    local service="$1"
    source_libs
    users_init

    local users
    users=$(user_list "$service")

    echo ""
    if [[ -n "$service" ]]; then
        echo -e "${BOLD}Users ($service)${RESET}"
    else
        echo -e "${BOLD}All Users${RESET}"
    fi
    echo "================================================"

    if [[ -z "$users" ]]; then
        echo "  No users found"
    else
        while IFS= read -r username; do
            local protocols
            protocols=$(jq -r ".users[\"$username\"].protocols | keys | join(\", \")" "$DNSCLOAK_USERS" 2>/dev/null)
            echo "  $username  [$protocols]"
        done <<< "$users"
    fi
    echo ""
}

#-------------------------------------------------------------------------------
# Show Links (dispatches to service functions.sh)
#-------------------------------------------------------------------------------

show_links() {
    local username="$1"
    local service="$2"
    source_libs

    if [[ -z "$username" ]]; then
        error "Username required. Usage: dnscloak links <username> [service]"
    fi

    if [[ -n "$service" ]]; then
        source_service_functions "$service" || error "Functions not available for $service"
        local func_name="show_${service}_links"
        if declare -f "$func_name" >/dev/null 2>&1; then
            "$func_name" "$username"
        else
            error "Links not implemented for service: $service"
        fi
    else
        # Show links for all services user is in
        for svc in $ALL_PROTOCOLS; do
            if user_exists "$username" "$svc" 2>/dev/null; then
                source_service_functions "$svc" 2>/dev/null || continue
                local func_name="show_${svc}_links"
                if declare -f "$func_name" >/dev/null 2>&1; then
                    "$func_name" "$username"
                fi
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
        for svc in reality ws wg dnstt mtp vray conduit; do
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
                    conduit)
                        if systemctl is-active --quiet conduit 2>/dev/null; then
                            status_text="running"
                        fi
                        ;;
                esac
                
                # Conduit doesn't have per-user management
                if [[ "$svc" == "conduit" ]]; then
                    echo -e "  $status_icon $svc: $status_text (relay node)"
                else
                    local user_count
                    user_count=$(user_list "$svc" | wc -l | tr -d ' ')
                    echo -e "  $status_icon $svc: $status_text ($user_count users)"
                fi
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
        conduit)
            echo "  Service: conduit"
            echo "  Status: $(systemctl is-active conduit 2>/dev/null || echo 'unknown')"
            local max_clients bandwidth
            source_libs
            max_clients=$(server_get "conduit_max_clients")
            bandwidth=$(server_get "conduit_bandwidth")
            echo "  Max Clients: ${max_clients:-200}"
            echo "  Bandwidth: ${bandwidth:-5} Mbps"
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
        conduit)
            systemctl restart conduit
            success "Conduit restarted"
            ;;
    esac
}

#-------------------------------------------------------------------------------
# Install Service
#-------------------------------------------------------------------------------

install_service() {
    local service="$1"
    
    validate_service "$service"
    source_libs
    source_service_functions "$service" || error "Functions not available for $service"

    local func_name="install_${service}"
    if declare -f "$func_name" >/dev/null 2>&1; then
        "$func_name"
    else
        error "Install not implemented for service: $service"
    fi
}

#-------------------------------------------------------------------------------
# Manage Service (interactive menu)
#-------------------------------------------------------------------------------

manage_service() {
    local service="$1"

    validate_service "$service"
    source_libs
    source_service_functions "$service" || error "Functions not available for $service"

    local func_name="manage_${service}"
    if declare -f "$func_name" >/dev/null 2>&1; then
        "$func_name"
    else
        error "Manage not implemented for service: $service"
    fi
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
    
    source_libs
    source_service_functions "$service" || error "Functions not available for $service"

    local func_name="uninstall_${service}"
    if declare -f "$func_name" >/dev/null 2>&1; then
        "$func_name"
    else
        error "Uninstall not implemented for service: $service"
    fi
}

#-------------------------------------------------------------------------------
# Help
#-------------------------------------------------------------------------------

show_help() {
    cat <<'EOF'

  +-----------------------------------------------------------+
  |                    DNSCloak CLI v2.1.0                     |
  +-----------------------------------------------------------+

  USAGE:
    dnscloak                         Interactive TUI menu
    dnscloak <command> [service] [options]

  COMMANDS:
    add <service> <username>     Add user to service
    remove <service> <username>  Remove user from service
    list [service]               List users (filter by service)
    links <username> [service]   Show connection links/configs
    status [service]             Show service status
    restart <service>            Restart a service
    install <service>            Install a service
    manage <service>             Open service management menu
    uninstall <service>          Uninstall a service
    services                     List installed services
    help                         Show this help

  SERVICES:
    reality   VLESS + REALITY (no domain, stealth)
    ws        VLESS + WebSocket + CDN (Cloudflare)
    wg        WireGuard VPN (fast, native apps)
    dnstt     DNS Tunnel (emergency, slow)
    mtp       MTProto Proxy (Telegram)
    vray      VLESS + TLS (requires domain)
    conduit   Psiphon relay node (volunteer proxy)

  EXAMPLES:
    dnscloak                          # Interactive menu
    dnscloak add reality alice        # Add Alice to Reality
    dnscloak manage wg                # Manage WireGuard
    dnscloak links alice              # Show all links for Alice
    dnscloak links alice wg           # Show WireGuard config
    dnscloak list                     # List all users
    dnscloak status                   # All services status
    dnscloak install reality          # Install Reality protocol

EOF
}

#-------------------------------------------------------------------------------
# Interactive TUI
#-------------------------------------------------------------------------------

interactive_menu() {
    source_libs

    while true; do
        clear

        load_banner "menu" 2>/dev/null || {
            echo ""
            echo -e "  ${BOLD}${WHITE}DNSCloak v${VERSION}${RESET}"
        }
        echo ""
        echo -e "  ${BOLD}${WHITE}Protocol Manager${RESET}"
        echo "  -------------------------------------------"
        echo ""

        local idx=1
        for proto in $ALL_PROTOCOLS; do
            local name status_text=""
            case "$proto" in
                reality) name="VLESS + REALITY" ;;
                ws)      name="VLESS + WS + CDN" ;;
                wg)      name="WireGuard" ;;
                dnstt)   name="DNS Tunnel" ;;
                mtp)     name="MTProto Proxy" ;;
                vray)    name="VLESS + TLS" ;;
                conduit) name="Conduit (Psiphon)" ;;
                *)       name="$proto" ;;
            esac

            if is_service_installed "$proto"; then
                status_text="${GREEN}[installed]${RESET}"
            else
                status_text="${GRAY}[not installed]${RESET}"
            fi

            printf "  %d) %-24s %b\n" "$idx" "$name" "$status_text"
            ((idx++))
        done

        echo ""
        echo "  s) Status overview"
        echo "  u) List all users"
        echo "  0) Exit"
        echo ""
        echo -n "  Select: "
        read -r choice

        case "$choice" in
            [1-7])
                local proto_arr=($ALL_PROTOCOLS)
                local selected="${proto_arr[$((choice - 1))]}"

                source_service_functions "$selected" 2>/dev/null || {
                    echo ""
                    warn "Functions not available for $selected"
                    echo "  Press Enter to continue..."
                    read -r
                    continue
                }

                if is_service_installed "$selected"; then
                    local func_name="manage_${selected}"
                    if declare -f "$func_name" >/dev/null 2>&1; then
                        "$func_name"
                    fi
                else
                    local func_name="install_${selected}"
                    if declare -f "$func_name" >/dev/null 2>&1; then
                        "$func_name"
                    fi
                fi
                ;;
            s|S)
                show_status
                echo "  Press Enter to continue..."
                read -r
                ;;
            u|U)
                list_users
                echo "  Press Enter to continue..."
                read -r
                ;;
            0|q|Q|"")
                echo ""
                exit 0
                ;;
            *)
                warn "Invalid option"
                sleep 1
                ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    # No arguments -> interactive TUI menu (requires root)
    if [[ $# -eq 0 ]]; then
        if [[ $EUID -ne 0 ]]; then
            show_help
            exit 0
        fi
        interactive_menu
        exit 0
    fi

    local command="$1"
    shift
    
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
            require_root
            local service="$1"
            install_service "$service"
            ;;
        manage)
            require_root
            local service="$1"
            manage_service "$service"
            ;;
        uninstall)
            require_root
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
        menu)
            require_root
            interactive_menu
            ;;
        version|-v|--version)
            echo "DNSCloak CLI v${VERSION}"
            ;;
        help|-h|--help)
            show_help
            ;;
        *)
            error "Unknown command: $command. Use 'dnscloak help' for usage."
            ;;
    esac
}

main "$@"
