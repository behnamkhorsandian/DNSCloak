#!/bin/bash
#===============================================================================
# DNSCloak TUI - Entry Point
# Unified interactive installer & management tool
#
# Usage:
#   curl dnscloak.net | bash           # Interactive menu
#   curl dnscloak.net/reality | bash   # Jump to Reality
#   bash dnscloak.sh --page reality    # Direct protocol page
#===============================================================================

#-------------------------------------------------------------------------------
# Constants
#-------------------------------------------------------------------------------

DNSCLOAK_VERSION="2.0.0"
DNSCLOAK_DIR="/opt/dnscloak"
DNSCLOAK_USERS="${DNSCLOAK_DIR}/users.json"
GITHUB_RAW="${GITHUB_RAW:-https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main}"

#-------------------------------------------------------------------------------
# Resolve script directory (works when sourced or concatenated by worker)
#-------------------------------------------------------------------------------

if [[ -n "${TUI_DIR:-}" ]]; then
    SCRIPT_DIR="$TUI_DIR"
elif [[ -f "$(dirname "${BASH_SOURCE[0]}")/engine.sh" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    # Running from concatenated worker output — everything is inline
    SCRIPT_DIR=""
fi

#-------------------------------------------------------------------------------
# Source modules (when running from repo checkout, not concatenated)
#-------------------------------------------------------------------------------

_source_if_exists() {
    [[ -n "$1" && -f "$1" ]] && source "$1" || true
}

if [[ -n "$SCRIPT_DIR" ]]; then
    source "$SCRIPT_DIR/theme.sh"
    source "$SCRIPT_DIR/engine.sh"

    # Library modules (user management, cloud detection)
    _source_if_exists "$SCRIPT_DIR/../lib/common.sh"
    _source_if_exists "$SCRIPT_DIR/../lib/cloud.sh"
    _source_if_exists "$SCRIPT_DIR/../lib/bootstrap.sh"
    _source_if_exists "$SCRIPT_DIR/../lib/xray.sh"

    # Pages
    source "$SCRIPT_DIR/pages/main.sh"
    source "$SCRIPT_DIR/pages/protocol.sh"
    source "$SCRIPT_DIR/pages/install_wizard.sh"
    source "$SCRIPT_DIR/pages/users.sh"
    source "$SCRIPT_DIR/pages/status.sh"
fi

#-------------------------------------------------------------------------------
# Parse arguments
#-------------------------------------------------------------------------------

START_PAGE=""
START_PROTOCOL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --page|-p)
            START_PAGE="protocol"
            START_PROTOCOL="$2"
            shift 2
            ;;
        --status|-s)
            START_PAGE="status"
            shift
            ;;
        --users|-u)
            START_PAGE="users"
            shift
            ;;
        --version|-v)
            echo "DNSCloak TUI v${DNSCLOAK_VERSION}"
            exit 0
            ;;
        --help|-h)
            cat <<EOF
DNSCloak - Multi-Protocol Censorship Bypass Platform

Usage:
  dnscloak                       Interactive TUI menu
  dnscloak --page <protocol>     Jump to protocol page
  dnscloak --status              Show service status
  dnscloak --users               Manage users
  dnscloak --version             Show version

Protocols: reality, wg, ws, mtp, dnstt, conduit, vray, sos
EOF
            exit 0
            ;;
        *)
            # Treat bare argument as protocol name
            if [[ " ${PROTOCOL_IDS[*]:-} " == *" $1 "* ]]; then
                START_PAGE="protocol"
                START_PROTOCOL="$1"
            fi
            shift
            ;;
    esac
done

#-------------------------------------------------------------------------------
# Preflight checks
#-------------------------------------------------------------------------------

_preflight() {
    # Check root
    if [[ $EUID -ne 0 ]]; then
        printf '\033[31mError:\033[0m This installer must be run as root.\n'
        printf 'Try: curl dnscloak.net | sudo bash\n'
        exit 1
    fi

    # Check /dev/tty (required for interactive input when piped via curl)
    if [[ ! -e /dev/tty ]]; then
        printf '\033[31mError:\033[0m No terminal available (/dev/tty missing).\n'
        printf 'Run this in an interactive terminal session.\n'
        exit 1
    fi

    # Ensure jq is available for user management
    if ! command -v jq &>/dev/null; then
        printf 'Installing jq...\n'
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && apt-get install -y -qq jq >/dev/null 2>&1
        elif command -v yum &>/dev/null; then
            yum install -y -q jq >/dev/null 2>&1
        elif command -v dnf &>/dev/null; then
            dnf install -y -q jq >/dev/null 2>&1
        fi
    fi

    # Initialize users.json if missing
    if [[ ! -f "$DNSCLOAK_USERS" ]]; then
        mkdir -p "$DNSCLOAK_DIR"
        local server_ip
        server_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
        cat > "$DNSCLOAK_USERS" <<EOJSON
{
  "users": {},
  "server": {
    "ip": "${server_ip}",
    "domain": "",
    "provider": "unknown"
  }
}
EOJSON
    fi

    # Detect cloud provider if available
    if type cloud_detect &>/dev/null; then
        cloud_detect 2>/dev/null || true
    fi
}

#-------------------------------------------------------------------------------
# Service status helpers (used by pages)
# These check systemd services / docker containers
#-------------------------------------------------------------------------------

service_installed() {
    local proto="$1"
    case "$proto" in
        reality|vray|ws)
            # Xray-based protocols: check if inbound exists in config
            [[ -f /opt/dnscloak/xray/config.json ]] && \
                jq -e ".inbounds[] | select(.tag == \"${proto}-in\")" \
                    /opt/dnscloak/xray/config.json >/dev/null 2>&1
            ;;
        wg)
            [[ -f /etc/wireguard/wg0.conf ]] || [[ -f /opt/dnscloak/wg/wg0.conf ]]
            ;;
        mtp)
            [[ -f /opt/dnscloak/mtp/config.py ]] || systemctl is-enabled mtproto-proxy &>/dev/null
            ;;
        dnstt)
            [[ -f /opt/dnscloak/dnstt/server.key ]] || systemctl is-enabled dnstt &>/dev/null
            ;;
        conduit)
            docker inspect conduit &>/dev/null 2>&1 || systemctl is-enabled conduit &>/dev/null 2>&1
            ;;
        sos)
            [[ -f /opt/dnscloak/sos/relay.py ]] || systemctl is-enabled sos-relay &>/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

service_running() {
    local proto="$1"
    case "$proto" in
        reality|vray|ws)
            systemctl is-active xray &>/dev/null 2>&1
            ;;
        wg)
            ip link show wg0 &>/dev/null 2>&1
            ;;
        mtp)
            systemctl is-active mtproto-proxy &>/dev/null 2>&1
            ;;
        dnstt)
            systemctl is-active dnstt &>/dev/null 2>&1
            ;;
        conduit)
            docker inspect -f '{{.State.Running}}' conduit 2>/dev/null | grep -q true
            ;;
        sos)
            systemctl is-active sos-relay &>/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

service_restart() {
    local proto="$1"
    case "$proto" in
        reality|vray|ws) systemctl restart xray 2>/dev/null ;;
        wg) wg-quick down wg0 2>/dev/null; wg-quick up wg0 2>/dev/null ;;
        mtp) systemctl restart mtproto-proxy 2>/dev/null ;;
        dnstt) systemctl restart dnstt 2>/dev/null ;;
        conduit) docker restart conduit 2>/dev/null ;;
        sos) systemctl restart sos-relay 2>/dev/null ;;
    esac
}

service_uninstall() {
    local proto="$1"
    # Source protocol installer and call its uninstall function
    _source_protocol "$proto" 2>/dev/null
    if type "uninstall_${proto}" &>/dev/null; then
        "uninstall_${proto}"
    elif type "uninstall_${proto}_service" &>/dev/null; then
        "uninstall_${proto}_service"
    fi
}

#-------------------------------------------------------------------------------
# User link display helper (used by users page)
#-------------------------------------------------------------------------------

show_user_links() {
    local username="$1"
    local proto="${2:-}"

    if [[ -n "$proto" ]]; then
        _source_protocol "$proto" 2>/dev/null
        if type "show_${proto}_links" &>/dev/null; then
            "show_${proto}_links" "$username"
        fi
    fi
}

#-------------------------------------------------------------------------------
# Navigation Router
#-------------------------------------------------------------------------------

_run_navigation() {
    local current_page="${START_PAGE:-main}"
    local current_proto="${START_PROTOCOL:-}"
    local _dbg="/tmp/dnscloak-debug.log"
    echo "[$(date)] _run_navigation: current_page=$current_page current_proto=$current_proto" >> "$_dbg"

    while true; do
        echo "[$(date)] _run_navigation loop: page=$current_page" >> "$_dbg"
        case "$current_page" in

            main)
                echo "[$(date)] calling page_main_menu" >> "$_dbg"
                page_main_menu 2>>"$_dbg"
                local rc=$?
                echo "[$(date)] page_main_menu returned rc=$rc SELECTED_PROTOCOL=${SELECTED_PROTOCOL:-}" >> "$_dbg"

                if [[ $rc -ne 0 ]]; then
                    # Quit
                    return 0
                fi

                case "$SELECTED_PROTOCOL" in
                    _status)
                        current_page="status"
                        ;;
                    _users)
                        current_page="users"
                        ;;
                    *)
                        current_page="protocol"
                        current_proto="$SELECTED_PROTOCOL"
                        ;;
                esac
                ;;

            protocol)
                page_protocol "$current_proto"

                case "${PROTOCOL_ACTION:-back}" in
                    install)
                        current_page="wizard"
                        ;;
                    add_user)
                        _add_user_page "$current_proto"
                        # Stay on protocol page
                        ;;
                    remove_user)
                        _remove_user_page "$current_proto"
                        ;;
                    show_links)
                        # Prompt for username and show links
                        printf '\033[?25h'
                        tui_get_size
                        local width=$(( _TERM_COLS > 100 ? 100 : _TERM_COLS ))
                        clear_screen
                        render_banner "logo" "$C_GREEN"
                        printf '\n'
                        draw_box_top "$width" "Show User Links"
                        draw_box_empty "$width"
                        draw_box_row "  ${C_TEXT}Enter username:${C_RST}" "$width"
                        draw_box_empty "$width"
                        draw_box_bottom "$width"
                        local link_user
                        link_user=$(tui_read_line "Username" "")
                        printf '\033[?25l'
                        if [[ -n "$link_user" ]]; then
                            _show_user_links_page "$link_user" "$current_proto"
                        fi
                        ;;
                    status)
                        current_page="status"
                        ;;
                    restart)
                        clear_screen
                        render_banner "logo" "$C_ORANGE"
                        printf '\n'
                        tui_run_cmd "Restarting ${PROTOCOL_NAMES[$current_proto]}" \
                            service_restart "$current_proto"
                        press_any_key
                        ;;
                    uninstall)
                        tui_confirm "Uninstall ${PROTOCOL_NAMES[$current_proto]}? This cannot be undone." "n"
                        if [[ $? -eq 0 ]]; then
                            clear_screen
                            render_banner "logo" "$C_RED"
                            printf '\n'
                            tui_run_cmd "Uninstalling ${PROTOCOL_NAMES[$current_proto]}" \
                                service_uninstall "$current_proto"
                            press_any_key
                        fi
                        current_page="main"
                        current_proto=""
                        ;;
                    quit)
                        return 0
                        ;;
                    back|*)
                        current_page="main"
                        current_proto=""
                        ;;
                esac
                ;;

            wizard)
                run_wizard "$current_proto"
                local wrc=$?
                if [[ $wrc -eq 0 ]]; then
                    # Install completed — show success
                    clear_screen
                    local banner_name="${current_proto}"
                    [[ "$current_proto" == "wg" ]] && banner_name="wireguard"
                    render_banner "$banner_name" "$C_GREEN" 2>/dev/null || render_banner "logo" "$C_GREEN"
                    printf '\n'

                    tui_get_size
                    local width=$(( _TERM_COLS > 100 ? 100 : _TERM_COLS ))
                    draw_box_top "$width" "Installation Complete"
                    draw_box_empty "$width"
                    draw_box_row "  ${C_GREEN}*${C_RST} ${PROTOCOL_NAMES[$current_proto]} has been installed successfully." "$width"
                    draw_box_empty "$width"
                    draw_box_row "  ${C_TEXT}Next steps:${C_RST}" "$width"
                    draw_box_row "    ${C_LGRAY}- Add users with the 'Add User' option${C_RST}" "$width"
                    draw_box_row "    ${C_LGRAY}- Share connection links with your users${C_RST}" "$width"
                    draw_box_row "    ${C_LGRAY}- Monitor status from the Status dashboard${C_RST}" "$width"
                    draw_box_empty "$width"
                    draw_box_bottom "$width"
                    press_any_key
                fi
                # Go back to protocol page
                current_page="protocol"
                ;;

            status)
                page_status
                local src=$?
                if [[ $src -ne 0 ]]; then
                    return 0  # quit from status
                fi
                current_page="main"
                current_proto=""
                ;;

            users)
                page_users
                local urc=$?
                if [[ $urc -ne 0 ]]; then
                    return 0  # quit from users
                fi
                current_page="main"
                current_proto=""
                ;;

            *)
                current_page="main"
                ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# Exit banner
#-------------------------------------------------------------------------------

_show_exit_banner() {
    printf '\n'
    printf '  %b*%b DNSCloak v%s\n' "$C_GREEN" "$C_RST" "$DNSCLOAK_VERSION"
    printf '  %bThe beacon remains lit.%b\n' "$C_DGRAY" "$C_RST"
    if [[ -f /tmp/dnscloak-debug.log ]]; then
        printf '  %bDebug log: /tmp/dnscloak-debug.log%b\n' "$C_DGRAY" "$C_RST"
    fi
    printf '\n'
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

dnscloak_tui_main() {
    # Debug log for troubleshooting
    local _dbg="/tmp/dnscloak-debug.log"
    echo "[$(date)] dnscloak_tui_main starting" > "$_dbg"
    echo "[$(date)] BASH_VERSION=$BASH_VERSION" >> "$_dbg"
    echo "[$(date)] TERM=$TERM EUID=$EUID" >> "$_dbg"
    echo "[$(date)] SCRIPT_DIR=$SCRIPT_DIR" >> "$_dbg"
    echo "[$(date)] START_PAGE=${START_PAGE:-} START_PROTOCOL=${START_PROTOCOL:-}" >> "$_dbg"

    _preflight
    echo "[$(date)] _preflight done" >> "$_dbg"

    # Trap for clean exit
    trap 'tui_cleanup 2>/dev/null; _show_exit_banner; echo "[$(date)] EXIT trap fired" >> /tmp/dnscloak-debug.log' EXIT
    trap 'tui_cleanup 2>/dev/null; exit 130' INT TERM

    echo "[$(date)] calling tui_init" >> "$_dbg"
    tui_init || {
        printf '\033[31mError:\033[0m Failed to initialize TUI. Check terminal capabilities.\n'
        echo "[$(date)] tui_init FAILED" >> "$_dbg"
        exit 1
    }
    echo "[$(date)] tui_init succeeded, _TUI_ACTIVE=$_TUI_ACTIVE _TERM_COLS=$_TERM_COLS _TERM_ROWS=$_TERM_ROWS" >> "$_dbg"

    echo "[$(date)] calling _run_navigation" >> "$_dbg"
    _run_navigation 2>>"$_dbg"
    echo "[$(date)] _run_navigation returned $?" >> "$_dbg"

    tui_cleanup
    _show_exit_banner
    trap - EXIT
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "$0" ]] || [[ -z "${BASH_SOURCE[0]}" ]]; then
    dnscloak_tui_main "$@"
fi
