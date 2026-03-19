#!/bin/bash
#===============================================================================
# DNSCloak TUI - Status Dashboard Page
# Uses table renderer for structured data display
#===============================================================================

TUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TUI_DIR/engine.sh"

#-------------------------------------------------------------------------------
# Port check helper — returns 0 = open, 1 = closed
# Sets _PORT_STATUS ("open"/"closed") and _PORT_BADGE
#-------------------------------------------------------------------------------

_PORT_STATUS=""
_PORT_BADGE=""

_check_port() {
    local port="$1"
    _PORT_STATUS="closed"
    _PORT_BADGE="${C_DGRAY}closed${C_RST}"

    if type ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep -q ":${port} " && { _PORT_STATUS="open"; _PORT_BADGE="${C_GREEN}open${C_RST}"; return 0; }
    elif type netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | grep -q ":${port} " && { _PORT_STATUS="open"; _PORT_BADGE="${C_GREEN}open${C_RST}"; return 0; }
    fi
    return 1
}

#-------------------------------------------------------------------------------
# Status dashboard — unified frame layout with tables
# Returns: 0 on back, 1 on quit
#-------------------------------------------------------------------------------

page_status() {
    _SIDEBAR_PAGE="status"
    _SIDEBAR_SEL=0
    _SIDEBAR_DIM=0
    FRAME_BANNER="logo"
    FRAME_BANNER_COLOR="$C_ORANGE"

    while true; do
        tui_get_size
        tui_compute_layout

        # ── Gather data ──────────────────────────────────────────────
        local server_ip="unknown"
        local server_domain=""
        local server_provider="unknown"
        local user_count=0

        if [[ -f "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" ]] && type jq &>/dev/null; then
            server_ip=$(jq -r '.server.ip // "unknown"' "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
            server_domain=$(jq -r '.server.domain // ""' "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
            server_provider=$(jq -r '.server.provider // "unknown"' "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
            user_count=$(jq -r '.users // {} | keys | length' "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
        fi

        local uptime_str=""
        uptime_str=$(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | sed 's/,.*//')
        local load_avg=""
        load_avg=$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}' || echo "N/A")
        local mem_used="" mem_total=""
        if type free &>/dev/null; then
            mem_used=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3}')
            mem_total=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
        fi

        # ── Build content with tables ────────────────────────────────
        FRAME_CONTENT=()
        tui_scroll_reset

        # Server Info table
        local -a srv_headers=("Property" "Value")
        local -a srv_rows=()
        srv_rows+=("IP|${server_ip}")
        if [[ -n "$server_domain" && "$server_domain" != "null" ]]; then
            srv_rows+=("Domain|${server_domain}")
        fi
        srv_rows+=("Provider|${server_provider}")
        srv_rows+=("Users|${user_count}")
        srv_rows+=("Uptime|${uptime_str}")
        if [[ -n "$load_avg" && "$load_avg" != "N/A" ]]; then
            srv_rows+=("Load|${load_avg}")
        fi
        if [[ -n "$mem_used" ]]; then
            srv_rows+=("Memory|${mem_used} / ${mem_total}")
        fi
        tui_render_table "Server" srv_headers srv_rows
        FRAME_CONTENT+=("")

        # Services table
        local -a svc_headers=("Service" "Status")
        local -a svc_rows=()
        for proto in "${PROTOCOL_IDS[@]}"; do
            local name="${PROTOCOL_NAMES[$proto]}"
            local status_badge=""

            if type service_installed &>/dev/null && service_installed "$proto" 2>/dev/null; then
                if type service_running &>/dev/null && service_running "$proto" 2>/dev/null; then
                    status_badge="$badge_running"
                else
                    status_badge="$badge_stopped"
                fi
            else
                status_badge="$badge_not_installed"
            fi
            svc_rows+=("${name}|${status_badge}")
        done
        tui_render_table "Services" svc_headers svc_rows
        FRAME_CONTENT+=("")

        # Ports table
        local -a port_headers=("Port" "Protocol" "State")
        local -a port_rows=()

        _check_port 443 "" || true
        port_rows+=("443|HTTPS (Reality/VRay)|${_PORT_BADGE}")
        _check_port 80 "" || true
        port_rows+=("80|HTTP (WebSocket)|${_PORT_BADGE}")
        _check_port 51820 "" || true
        port_rows+=("51820|WireGuard (UDP)|${_PORT_BADGE}")
        _check_port 53 "" || true
        port_rows+=("53|DNS (DNSTT)|${_PORT_BADGE}")

        tui_render_table "Ports" port_headers port_rows

        # Footer
        FRAME_FOOTER="${C_DGRAY}r${C_RST}${C_DIM} refresh${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}Esc${C_RST}${C_DIM} back${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}q${C_RST}${C_DIM} quit${C_RST}"

        tui_render_frame

        # Key handling
        local key
        key=$(tui_read_key)

        case "$key" in
            r|R)    continue ;;

            ESC|BACKSPACE)    return 0 ;;
            q|Q)    return 1 ;;
            *)      continue ;;
        esac
    done
}
