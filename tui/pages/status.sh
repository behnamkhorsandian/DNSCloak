#!/bin/bash
#===============================================================================
# DNSCloak TUI - Status Dashboard Page
# Uses unified frame with persistent sidebar
#===============================================================================

TUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TUI_DIR/engine.sh"

#-------------------------------------------------------------------------------
# Port check helper
#-------------------------------------------------------------------------------

_PORT_LINE=""

_check_port() {
    local port="$1"
    local label="$2"
    local listening=0

    if type ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep -q ":${port} " && listening=1
    elif type netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | grep -q ":${port} " && listening=1
    fi

    if [[ $listening -eq 1 ]]; then
        _PORT_LINE="${C_GREEN}*${C_RST} ${C_TEXT}:${port}${C_RST} ${C_LGRAY}${label}${C_RST} ${C_GREEN}[open]${C_RST}"
        return 0
    else
        _PORT_LINE="${C_DGRAY}*${C_RST} ${C_TEXT}:${port}${C_RST} ${C_LGRAY}${label}${C_RST} ${C_DGRAY}[closed]${C_RST}"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Status dashboard — unified frame layout
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

        # ── Build content ────────────────────────────────────────────
        FRAME_CONTENT=()
        FRAME_CONTENT+=("${C_ORANGE}${C_BOLD}System Status${C_RST}")
        FRAME_CONTENT+=("")

        # Server info
        FRAME_CONTENT+=("${C_LGREEN}Server${C_RST}")
        FRAME_CONTENT+=("  ${C_LGRAY}IP:${C_RST}       ${C_TEXT}${server_ip}${C_RST}")
        if [[ -n "$server_domain" && "$server_domain" != "null" ]]; then
            FRAME_CONTENT+=("  ${C_LGRAY}Domain:${C_RST}   ${C_TEXT}${server_domain}${C_RST}")
        fi
        FRAME_CONTENT+=("  ${C_LGRAY}Provider:${C_RST} ${C_TEXT}${server_provider}${C_RST}")
        FRAME_CONTENT+=("  ${C_LGRAY}Users:${C_RST}    ${C_TEXT}${user_count}${C_RST}")
        FRAME_CONTENT+=("  ${C_LGRAY}Uptime:${C_RST}   ${C_TEXT}${uptime_str}${C_RST}")
        if [[ -n "$load_avg" && "$load_avg" != "N/A" ]]; then
            FRAME_CONTENT+=("  ${C_LGRAY}Load:${C_RST}     ${C_TEXT}${load_avg}${C_RST}")
        fi
        if [[ -n "$mem_used" ]]; then
            FRAME_CONTENT+=("  ${C_LGRAY}Memory:${C_RST}   ${C_TEXT}${mem_used} / ${mem_total}${C_RST}")
        fi
        FRAME_CONTENT+=("")

        # Service statuses
        FRAME_CONTENT+=("${C_LGREEN}Services${C_RST}")
        for proto in "${PROTOCOL_IDS[@]}"; do
            local name="${PROTOCOL_NAMES[$proto]}"
            local status_text=""

            if type service_installed &>/dev/null && service_installed "$proto" 2>/dev/null; then
                if type service_running &>/dev/null && service_running "$proto" 2>/dev/null; then
                    status_text=" $badge_running"
                else
                    status_text=" $badge_stopped"
                fi
            else
                status_text=" $badge_not_installed"
            fi

            FRAME_CONTENT+=("  ${C_TEXT}${name}${C_RST} ${status_text}")
        done
        FRAME_CONTENT+=("")

        # Port status
        FRAME_CONTENT+=("${C_LGREEN}Port Status${C_RST}")
        _check_port 443 "HTTPS (Reality/VRay)" || true
        FRAME_CONTENT+=("  ${_PORT_LINE}")
        _check_port 80 "HTTP (WebSocket)" || true
        FRAME_CONTENT+=("  ${_PORT_LINE}")
        _check_port 51820 "WireGuard (UDP)" || true
        FRAME_CONTENT+=("  ${_PORT_LINE}")
        _check_port 53 "DNS (DNSTT)" || true
        FRAME_CONTENT+=("  ${_PORT_LINE}")

        # Footer
        FRAME_FOOTER="${C_DGRAY}r${C_RST}${C_DIM} refresh${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}Esc${C_RST}${C_DIM} back${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}q${C_RST}${C_DIM} quit${C_RST}"

        tui_render_frame

        # Key handling
        local key
        key=$(tui_read_key)

        case "$key" in
            r|R)  continue ;;  # refresh
            ESC)  return 0 ;;
            q|Q)  return 1 ;;
            *)    continue ;;
        esac
    done
}
