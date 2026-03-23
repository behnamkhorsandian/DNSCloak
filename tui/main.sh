#!/bin/bash
#===============================================================================
# Vany TUI - Entry Point
# Unified interactive installer & management tool
#
# Usage:
#   curl vany.sh | bash           # Interactive menu
#   curl vany.sh/reality | bash   # Jump to Reality
#   bash vany.sh --page reality    # Direct protocol page
#===============================================================================

#-------------------------------------------------------------------------------
# Constants
#-------------------------------------------------------------------------------

VANY_VERSION="2.0.0"
VANY_DIR="/opt/vany"
VANY_USERS="${VANY_DIR}/users.json"
GITHUB_RAW="${GITHUB_RAW:-https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main}"

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
    source "$SCRIPT_DIR/pages/help.sh"
fi

#-------------------------------------------------------------------------------
# Parse arguments
#-------------------------------------------------------------------------------

START_PAGE=""
START_PROTOCOL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --page|-p)
            START_PAGE="main"
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
            echo "Vany TUI v${VANY_VERSION}"
            exit 0
            ;;
        --help|-h)
            cat <<EOF
Vany - Multi-Protocol Censorship Bypass Platform

Usage:
  vany                       Interactive TUI menu
  vany --page <protocol>     Jump to protocol page
  vany --status              Show service status
  vany --users               Manage users
  vany --version             Show version

Protocols: reality, wg, ws, mtp, dnstt, conduit, vray, sos
EOF
            exit 0
            ;;
        *)
            # Treat bare argument as protocol name
            if [[ " ${PROTOCOL_IDS[*]:-} " == *" $1 "* ]]; then
                START_PAGE="main"
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
    # Cloak mode: skip root check and online-only preflight
    if [[ "${CLOAK_MODE:-}" == "1" ]]; then
        # Use Cloak version instead of VANY_VERSION
        [[ -n "${CLOAK_VERSION:-}" ]] && VANY_VERSION="$CLOAK_VERSION"

        # Check /dev/tty
        if [[ ! -e /dev/tty ]]; then
            printf '\033[31mError:\033[0m No terminal available (/dev/tty missing).\n'
            exit 1
        fi

        # Non-root Cloak can still do server ops if running with sudo
        # but we don't require it
        return 0
    fi

    # Check root
    if [[ $EUID -ne 0 ]]; then
        printf '\033[31mError:\033[0m This installer must be run as root.\n'
        printf 'Try: curl vany.sh | sudo bash\n'
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
    if [[ ! -f "$VANY_USERS" ]]; then
        mkdir -p "$VANY_DIR"
        local server_ip
        server_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
        cat > "$VANY_USERS" <<EOJSON
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
            [[ -f /opt/vany/xray/config.json ]] && \
                jq -e ".inbounds[] | select(.tag == \"${proto}-in\")" \
                    /opt/vany/xray/config.json >/dev/null 2>&1
            ;;
        wg)
            [[ -f /etc/wireguard/wg0.conf ]] || [[ -f /opt/vany/wg/wg0.conf ]]
            ;;
        mtp)
            [[ -f /opt/vany/mtp/config.py ]] || systemctl is-enabled telegram-proxy &>/dev/null
            ;;
        dnstt)
            [[ -f /opt/vany/dnstt/server.key ]] || systemctl is-enabled dnstt &>/dev/null
            ;;
        conduit)
            docker inspect conduit &>/dev/null 2>&1 || systemctl is-enabled conduit &>/dev/null 2>&1
            ;;
        sos)
            [[ -f /opt/vany/sos/relay.py ]] || systemctl is-enabled sos-relay &>/dev/null 2>&1
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
            systemctl is-active telegram-proxy &>/dev/null 2>&1
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
        mtp) systemctl restart telegram-proxy 2>/dev/null ;;
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

    while true; do
        case "$current_page" in

            main)
                page_main_menu
                local rc=$?

                if [[ $rc -ne 0 ]]; then
                    return 0
                fi

                case "$SELECTED_PROTOCOL" in
                    _status)
                        current_page="status"
                        ;;
                    _users)
                        current_page="users"
                        ;;
                    _help)
                        current_page="help"
                        ;;
                    _choose)
                        current_page="choose"
                        ;;
                    *)
                        current_proto="$SELECTED_PROTOCOL"
                        # Handle the action directly — no separate protocol page
                        case "${PROTOCOL_ACTION:-}" in
                            install)
                                current_page="wizard"
                                ;;
                            add_user)
                                _add_user_page "$current_proto"
                                ;;
                            remove_user)
                                _remove_user_page "$current_proto"
                                ;;
                            show_links)
                                tui_get_size
                                tui_compute_layout
                                clear_screen
                                printf '\n'
                                draw_box_top "" "Show User Links"
                                draw_box_empty
                                draw_box_row "  ${C_TEXT}Enter the username to view connection links.${C_RST}"
                                draw_box_empty
                                draw_box_sep
                                draw_box_row " ${C_DGRAY}Enter username  |  Esc back${C_RST}"
                                draw_box_empty
                                local link_user=""
                                tui_read_line_boxed "Username" "" link_user
                                local link_rc=$?
                                draw_box_bottom
                                if [[ $link_rc -eq 0 && -n "$link_user" ]]; then
                                    _show_user_links_page "$link_user" "$current_proto"
                                fi
                                ;;
                            restart)
                                _SIDEBAR_DIM=1
                                FRAME_CONTENT=()
                                FRAME_CONTENT+=("${C_ORANGE}${C_BOLD}Restarting ${PROTOCOL_NAMES[$current_proto]}${C_RST}")
                                FRAME_CONTENT+=("")
                                FRAME_CONTENT+=("${C_LGRAY}Please wait...${C_RST}")
                                FRAME_FOOTER="${C_DIM}Restarting service...${C_RST}"
                                tui_render_frame
                                service_restart "$current_proto"
                                FRAME_CONTENT+=("")
                                FRAME_CONTENT+=("${C_GREEN}*${C_RST} ${C_TEXT}Service restarted${C_RST}")
                                FRAME_FOOTER="${C_DGRAY}Enter${C_RST}${C_DIM} continue${C_RST}"
                                tui_render_frame
                                tui_read_key >/dev/null
                                _SIDEBAR_DIM=0
                                ;;
                            uninstall)
                                printf '\033[?25h'
                                if tui_confirm "Uninstall ${PROTOCOL_NAMES[$current_proto]}? This cannot be undone." "n"; then
                                    printf '\033[?25l'
                                    FRAME_FOOTER="${C_DIM}Uninstalling...${C_RST}"
                                    tui_run_cmd_framed "Uninstalling ${PROTOCOL_NAMES[$current_proto]}" \
                                        service_uninstall "$current_proto"
                                    tui_read_key >/dev/null
                                else
                                    printf '\033[?25l'
                                fi
                                ;;
                            *)
                                # Unknown or empty action, return to main
                                ;;
                        esac
                        # After handling action, return to main page
                        current_page="main"
                        current_proto=""
                        ;;
                esac
                ;;

            wizard)
                run_wizard "$current_proto"
                local wrc=$?
                if [[ $wrc -eq 0 ]]; then
                    # Show success in frame
                    tui_get_size
                    tui_compute_layout
                    _SIDEBAR_DIM=0
                    _SIDEBAR_PAGE="protocols"
                    FRAME_CONTENT=()
                    FRAME_CONTENT+=("${C_GREEN}${C_BOLD}Installation Complete${C_RST}")
                    FRAME_CONTENT+=("")
                    FRAME_CONTENT+=("${C_GREEN}*${C_RST} ${C_TEXT}${PROTOCOL_NAMES[$current_proto]} has been installed successfully.${C_RST}")
                    FRAME_CONTENT+=("")
                    FRAME_CONTENT+=("${C_LGREEN}Next steps:${C_RST}")
                    FRAME_CONTENT+=("  ${C_LGRAY}- Add users with the 'Add User' option${C_RST}")
                    FRAME_CONTENT+=("  ${C_LGRAY}- Share connection links with your users${C_RST}")
                    FRAME_CONTENT+=("  ${C_LGRAY}- Monitor status from the Status dashboard${C_RST}")
                    FRAME_FOOTER="${C_DGRAY}Enter${C_RST}${C_DIM} continue${C_RST}"
                    tui_render_frame
                    tui_read_key >/dev/null
                fi
                current_page="main"
                current_proto=""
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

            help)
                page_help
                local hrc=$?
                if [[ $hrc -ne 0 ]]; then
                    return 0  # quit from help
                fi
                current_page="main"
                current_proto=""
                ;;

            choose)
                # Run the interactive protocol chooser
                printf '\033[?25h'  # show cursor
                clear_screen
                local choose_script=""
                # In Cloak mode, use local file
                if [[ "${CLOAK_MODE:-}" == "1" ]]; then
                    local candidates=(
                        "${CLOAK_HOME:-}/scripts/tools/choose.sh"
                        "${SCRIPT_DIR:-}/../scripts/tools/choose.sh"
                    )
                    for c in "${candidates[@]}"; do
                        [[ -f "$c" ]] && { choose_script="$c"; break; }
                    done
                fi
                if [[ -z "$choose_script" ]]; then
                    choose_script="/tmp/vany-choose.sh"
                    curl -sfL "$GITHUB_RAW/scripts/tools/choose.sh" -o "$choose_script" 2>/dev/null || true
                fi
                if [[ -f "$choose_script" ]]; then
                    bash "$choose_script" </dev/tty
                else
                    echo "  Failed to load protocol chooser"
                fi
                echo ""
                echo -e "  ${C_DIM}Press any key to return to TUI...${C_RST}"
                read -rsn1 </dev/tty
                printf '\033[?25l'  # hide cursor
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
    if [[ "${CLOAK_MODE:-}" == "1" ]]; then
        printf '  %b*%b Cloak v%s\n' "$C_GREEN" "$C_RST" "$VANY_VERSION"
        printf '  %bOffline and unreachable.%b\n' "$C_DGRAY" "$C_RST"
    else
        printf '  %b*%b Vany v%s\n' "$C_GREEN" "$C_RST" "$VANY_VERSION"
        printf '  %bThe beacon remains lit.%b\n' "$C_DGRAY" "$C_RST"
    fi
    printf '\n'
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

vany_tui_main() {
    # Parse arguments passed from start.sh or command line
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

    # Disable set -e inherited from lib/bootstrap.sh — TUI uses (( )) && patterns
    # that return non-zero legitimately and must not terminate the script
    set +e

    _preflight

    # Trap for clean exit
    trap 'tui_cleanup 2>/dev/null; _show_exit_banner' EXIT
    trap 'tui_cleanup 2>/dev/null; exit 130' INT TERM

    if ! tui_init; then
        printf '\033[31mError:\033[0m Failed to initialize TUI. Check terminal capabilities.\n'
        return 1
    fi

    _run_navigation

    tui_cleanup
    _show_exit_banner
    trap - EXIT
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "$0" ]] || [[ -z "${BASH_SOURCE[0]}" ]]; then
    vany_tui_main "$@"
fi
