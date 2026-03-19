#!/bin/bash
#===============================================================================
# DNSCloak TUI - Help Page
# Keyboard shortcuts, icon legend, protocol comparison, getting started
#===============================================================================

TUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TUI_DIR/engine.sh"

#-------------------------------------------------------------------------------
# Help page — scrollable reference card
# Returns: 0 on back, 1 on quit
#-------------------------------------------------------------------------------

page_help() {
    _SIDEBAR_PAGE="help"
    _SIDEBAR_SEL=0
    _SIDEBAR_DIM=0
    FRAME_BANNER="logo"
    FRAME_BANNER_COLOR="$C_ORANGE"

    while true; do
        tui_get_size
        tui_compute_layout

        FRAME_CONTENT=()

        # ── Keyboard Shortcuts ───────────────────────────────────────
        local -a kb_headers=("Key" "Action")
        local -a kb_rows=(
            "^/v|Navigate sidebar / scroll content"
            "Enter|Primary action (install or show links)"
            "i|Install selected protocol"
            "a|Add user to selected protocol"
            "r|Remove user"
            "l|Show user connection links"
            "x|Restart service"
            "d|Uninstall service"
            "s|Open status dashboard"
            "u|Open user management"
            "t|Toggle sort order (users page)"
            "h|Open this help page"
            "Esc|Back to main menu"
            "del|Go back one step"
            "q|Quit DNSCloak"
        )
        tui_render_table "Keyboard Shortcuts" kb_headers kb_rows
        FRAME_CONTENT+=("")

        # ── Icon Legend ──────────────────────────────────────────────
        local -a icon_headers=("Icon" "Meaning")
        local -a icon_rows=(
            "${DOT_ON}|Service running"
            "${DOT_OFF}|Service stopped"
            "${DOT_NONE}|Not installed"
        )
        tui_render_table "Status Icons" icon_headers icon_rows
        FRAME_CONTENT+=("")

        # ── Protocol Comparison ──────────────────────────────────────
        local -a proto_headers=("Protocol" "Port" "Domain?" "Speed" "Stealth")
        local -a proto_rows=(
            "REALITY|443|No|Fast|High"
            "WireGuard|51820|No|Very fast|Low"
            "WS+CDN|80|Yes|Medium|Very high"
            "MTProto|Custom|No|Medium|Medium"
            "DNSTT|53|Yes|Very slow|Very high"
            "Conduit|Auto|No|Varies|Medium"
            "V2Ray TLS|443|Yes|Fast|High"
            "SOS Chat|DNSTT|Yes*|Slow|Very high"
        )
        tui_render_table "Protocol Comparison" proto_headers proto_rows
        FRAME_CONTENT+=("")

        # ── Getting Started ──────────────────────────────────────────
        FRAME_CONTENT+=("${C_ORANGE}${C_BOLD}Getting Started${C_RST}")
        FRAME_CONTENT+=("")
        FRAME_CONTENT+=("${C_TEXT}1. Select a protocol from the sidebar${C_RST}")
        FRAME_CONTENT+=("${C_TEXT}2. Press ${C_GREEN}i${C_RST}${C_TEXT} to install it${C_RST}")
        FRAME_CONTENT+=("${C_TEXT}3. Press ${C_GREEN}a${C_RST}${C_TEXT} to add users${C_RST}")
        FRAME_CONTENT+=("${C_TEXT}4. Press ${C_GREEN}l${C_RST}${C_TEXT} to view connection links${C_RST}")
        FRAME_CONTENT+=("${C_TEXT}5. Share the links with your users${C_RST}")
        FRAME_CONTENT+=("")
        FRAME_CONTENT+=("${C_LGRAY}Recommended: Start with REALITY (no domain needed)${C_RST}")
        FRAME_CONTENT+=("${C_LGRAY}If your IP gets blocked, add WS+CDN behind Cloudflare${C_RST}")
        FRAME_CONTENT+=("${C_LGRAY}Emergency backup: DNSTT works even during blackouts${C_RST}")
        FRAME_CONTENT+=("")
        FRAME_CONTENT+=("${C_DGRAY}DNSCloak v${DNSCLOAK_VERSION:-2.0.0}${C_RST}")

        FRAME_FOOTER="${C_DGRAY}Esc${C_RST}${C_DIM} back${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}q${C_RST}${C_DIM} quit${C_RST}"

        tui_render_frame

        local key
        key=$(tui_read_key)

        case "$key" in

            ESC|BACKSPACE|ENTER)
                return 0
                ;;
            q|Q)
                return 1
                ;;
        esac
    done
}
