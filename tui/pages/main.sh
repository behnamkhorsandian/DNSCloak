#!/bin/bash
#===============================================================================
# DNSCloak TUI - Main Page (Protocol Browser)
# Unified view: sidebar selects protocol, content shows detail + actions
# Merges the old main.sh + protocol.sh into one cohesive page
#===============================================================================

TUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TUI_DIR/engine.sh"

#-------------------------------------------------------------------------------
# Protocol guide text (moved from protocol.sh)
#-------------------------------------------------------------------------------

declare -A PROTOCOL_GUIDE

PROTOCOL_GUIDE[reality]="VLESS + REALITY uses Xray-core to create a
proxy that mimics legitimate HTTPS traffic.

How it works:
  Your server pretends to be a normal website
  (like google.com or apple.com). Censors see
  what looks like regular HTTPS connections.

When to use:
  * First choice for most users
  * Works without a domain name
  * Very fast, low overhead
  * Hard to detect and block

Port used: 443 (HTTPS)"

PROTOCOL_GUIDE[wg]="WireGuard is a modern VPN protocol. It creates
an encrypted tunnel for ALL device traffic.

How it works:
  Lightweight kernel-level VPN. Uses public key
  cryptography. Extremely fast handshakes.

When to use:
  * You want a full VPN (all traffic tunneled)
  * You need native app support (iOS/Android)
  * You want simplicity and speed
  * May be blocked by DPI in some countries

Port used: 51820 (UDP)"

PROTOCOL_GUIDE[ws]="VLESS + WebSocket routes traffic through
Cloudflare's CDN network.

How it works:
  Traffic goes: Client -> Cloudflare CDN ->
  Your server. Censors only see Cloudflare IPs.
  Your real server IP stays completely hidden.

When to use:
  * Your server IP is already blocked
  * You want IP protection via CDN
  * You have a domain on Cloudflare

Requires: Domain name with Cloudflare DNS
Port used: 80 (HTTP, Cloudflare handles TLS)"

PROTOCOL_GUIDE[mtp]="MTProto Proxy is Telegram's built-in proxy
protocol. It only works for Telegram.

How it works:
  Runs a proxy server that speaks Telegram's
  native protocol. Supports Fake-TLS mode to
  disguise traffic as HTTPS.

When to use:
  * You only need Telegram access
  * Users don't want to install extra apps
  * Simple, single-purpose solution

Port used: Custom (you choose during setup)"

PROTOCOL_GUIDE[dnstt]="DNS Tunnel encodes data inside DNS queries.
This is an emergency backup protocol.

How it works:
  All traffic is encoded as DNS lookups to your
  domain. Works even when all other protocols
  are blocked because DNS queries are essential.

When to use:
  * Total internet blackout
  * All other protocols are blocked
  * Emergency backup (VERY slow: ~50 KB/s)

Requires: Domain with NS record configured
Port used: 53 (DNS)"

PROTOCOL_GUIDE[conduit]="Conduit turns your server into a volunteer
relay node for the Psiphon network.

How it works:
  Runs a Docker container that relays traffic
  for Psiphon users. You donate bandwidth to
  help people in censored regions.

When to use:
  * You want to help others bypass censorship
  * You have spare bandwidth to donate
  * No client configuration needed

Requires: Docker
Port used: Assigned automatically"

PROTOCOL_GUIDE[vray]="VLESS + TLS is the classic V2Ray setup with
proper TLS certificates.

How it works:
  Standard proxy with real TLS certificate from
  Let's Encrypt. Looks like any HTTPS website.

When to use:
  * You have a domain name
  * You want maximum compatibility
  * Standard V2Ray/Xray setup

Requires: Domain name + valid DNS
Port used: 443 (HTTPS)"

PROTOCOL_GUIDE[sos]="SOS is an encrypted emergency chat system
that works over DNS tunnels.

How it works:
  Messages are encrypted end-to-end using NaCl.
  They travel through the DNSTT tunnel, making
  them nearly impossible to block.

When to use:
  * Emergency communication during blackouts
  * Needs DNSTT service running first
  * Available as TUI app or web interface

Requires: DNSTT service running, Python 3.8+"

#-------------------------------------------------------------------------------
# Build content lines for selected protocol
#-------------------------------------------------------------------------------

_build_protocol_content() {
    local proto="$1"
    local action_sel="$2"   # -1 = no action focus, 0..N = action index
    local proto_name="${PROTOCOL_NAMES[$proto]}"
    local guide="${PROTOCOL_GUIDE[$proto]}"
    local desc="${PROTOCOL_DESC[$proto]}"
    local reqs="${PROTOCOL_REQS[$proto]}"
    local clients="${PROTOCOL_CLIENTS[$proto]}"

    FRAME_CONTENT=()

    # Title
    FRAME_CONTENT+=("${C_ORANGE}${C_BOLD}${proto_name}${C_RST}")
    FRAME_CONTENT+=("")

    # Status badge
    local is_installed=0
    local is_running=0
    if type service_installed &>/dev/null && service_installed "$proto" 2>/dev/null; then
        is_installed=1
        if type service_running &>/dev/null && service_running "$proto" 2>/dev/null; then
            is_running=1
        fi
    fi

    if [[ $is_installed -eq 1 ]]; then
        if [[ $is_running -eq 1 ]]; then
            FRAME_CONTENT+=("Status: $badge_running")
        else
            FRAME_CONTENT+=("Status: $badge_stopped")
        fi
    else
        FRAME_CONTENT+=("Status: $badge_not_installed")
    fi
    FRAME_CONTENT+=("")

    # Guide text
    while IFS= read -r line; do
        FRAME_CONTENT+=("${C_TEXT}${line}${C_RST}")
    done <<< "$guide"
    FRAME_CONTENT+=("")

    # Requirements
    FRAME_CONTENT+=("${C_LGREEN}Requirements:${C_RST}")
    while IFS= read -r line; do
        line=$(printf '%b' "$line")
        FRAME_CONTENT+=("${C_LGRAY}${line}${C_RST}")
    done <<< "$(printf '%b' "$reqs")"
    FRAME_CONTENT+=("")

    # Client apps
    FRAME_CONTENT+=("${C_LGREEN}Client Apps:${C_RST}")
    while IFS= read -r line; do
        line=$(printf '%b' "$line")
        FRAME_CONTENT+=("${C_LGRAY}${line}${C_RST}")
    done <<< "$(printf '%b' "$clients")"
    FRAME_CONTENT+=("")

    # Separator before actions
    local sep_w=$(( _CONTENT_INNER_W - 4 ))
    (( sep_w < 10 )) && sep_w=10
    (( sep_w > 40 )) && sep_w=40
    FRAME_CONTENT+=("${C_DGRAY}$(repeat_str "$BOX_H" "$sep_w")${C_RST}")
    FRAME_CONTENT+=("")

    # Action buttons
    _PROTO_ACTIONS=()
    _PROTO_ACTION_IDS=()
    if [[ $is_installed -eq 0 ]]; then
        _PROTO_ACTIONS+=("Install ${proto_name}")
        _PROTO_ACTION_IDS+=("install")
    else
        _PROTO_ACTIONS+=("Add User" "Remove User" "Show User Links" "Restart Service" "Uninstall")
        _PROTO_ACTION_IDS+=("add_user" "remove_user" "show_links" "restart" "uninstall")
    fi

    local a=0
    for action in "${_PROTO_ACTIONS[@]}"; do
        local prefix="   "
        local acolor="$C_TEXT"
        if [[ $action_sel -ge 0 && $a -eq $action_sel ]]; then
            prefix=" ${C_GREEN}>${C_RST}"
            acolor="${C_GREEN}${C_BOLD}"
        fi
        FRAME_CONTENT+=("${prefix} ${acolor}${action}${C_RST}")
        (( a++ ))
    done
}

#-------------------------------------------------------------------------------
# Main page — protocol browser with unified frame
# Returns 0 on action selection, 1 on quit
# Sets: SELECTED_PROTOCOL, PROTOCOL_ACTION
#-------------------------------------------------------------------------------

page_main_menu() {
    _SIDEBAR_SEL=0
    _SIDEBAR_PAGE="protocols"
    _SIDEBAR_DIM=0

    # Banner color per protocol
    local -A _PROTO_BANNER_COLOR=(
        [reality]="$C_GREEN"
        [wg]="$C_BLUE"
        [ws]="$C_ORANGE"
        [mtp]="$C_PURPLE"
        [dnstt]="$C_RED"
        [conduit]="$C_PURPLE"
        [vray]="$C_LGREEN"
        [sos]="$C_RED"
    )

    local focus="sidebar"   # "sidebar" or "content"
    local action_sel=0
    local proto_count=${#PROTOCOL_IDS[@]}

    # Pre-select protocol if START_PROTOCOL is set (from --page argument)
    if [[ -n "${START_PROTOCOL:-}" ]]; then
        local i=0
        for pid in "${PROTOCOL_IDS[@]}"; do
            if [[ "$pid" == "$START_PROTOCOL" ]]; then
                _SIDEBAR_SEL=$i
                break
            fi
            (( i++ ))
        done
        START_PROTOCOL=""
    fi

    while true; do
        tui_get_size

        local proto="${PROTOCOL_IDS[$_SIDEBAR_SEL]}"

        # Set banner to selected protocol
        FRAME_BANNER="$proto"
        FRAME_BANNER_COLOR="${_PROTO_BANNER_COLOR[$proto]:-$C_GREEN}"

        tui_compute_layout

        # Build content for selected protocol
        if [[ $focus == "content" ]]; then
            _build_protocol_content "$proto" "$action_sel"
        else
            _build_protocol_content "$proto" -1
        fi

        # Footer
        if [[ $focus == "sidebar" ]]; then
            FRAME_FOOTER="${C_DGRAY}^/v${C_RST}${C_DIM} navigate${C_RST}  "
            FRAME_FOOTER+="${C_DGRAY}Enter${C_RST}${C_DIM} actions${C_RST}  "
            FRAME_FOOTER+="${C_DGRAY}s${C_RST}${C_DIM} status${C_RST}  "
            FRAME_FOOTER+="${C_DGRAY}u${C_RST}${C_DIM} users${C_RST}  "
            FRAME_FOOTER+="${C_DGRAY}q${C_RST}${C_DIM} quit${C_RST}"
        else
            FRAME_FOOTER="${C_DGRAY}^/v${C_RST}${C_DIM} navigate${C_RST}  "
            FRAME_FOOTER+="${C_DGRAY}Enter${C_RST}${C_DIM} select${C_RST}  "
            FRAME_FOOTER+="${C_DGRAY}Esc${C_RST}${C_DIM} back${C_RST}  "
            FRAME_FOOTER+="${C_DGRAY}q${C_RST}${C_DIM} quit${C_RST}"
        fi

        tui_render_frame

        # Read key
        local key
        key=$(tui_read_key)

        if [[ $focus == "sidebar" ]]; then
            case "$key" in
                UP)
                    (( _SIDEBAR_SEL-- ))
                    (( _SIDEBAR_SEL < 0 )) && _SIDEBAR_SEL=$(( proto_count - 1 ))
                    action_sel=0
                    ;;
                DOWN)
                    (( _SIDEBAR_SEL++ ))
                    (( _SIDEBAR_SEL >= proto_count )) && _SIDEBAR_SEL=0
                    action_sel=0
                    ;;
                ENTER|RIGHT)
                    focus="content"
                    action_sel=0
                    ;;
                s|S)
                    SELECTED_PROTOCOL="_status"
                    return 0
                    ;;
                u|U)
                    SELECTED_PROTOCOL="_users"
                    return 0
                    ;;
                q|Q|ESC)
                    return 1
                    ;;
                [0-7])
                    if (( key < proto_count )); then
                        _SIDEBAR_SEL=$key
                        action_sel=0
                    fi
                    ;;
            esac
        else
            # Content focus — navigate action buttons
            local action_count=${#_PROTO_ACTIONS[@]}
            case "$key" in
                UP)
                    (( action_sel-- ))
                    (( action_sel < 0 )) && action_sel=$(( action_count - 1 ))
                    ;;
                DOWN)
                    (( action_sel++ ))
                    (( action_sel >= action_count )) && action_sel=0
                    ;;
                ENTER)
                    SELECTED_PROTOCOL="${PROTOCOL_IDS[$_SIDEBAR_SEL]}"
                    PROTOCOL_ACTION="${_PROTO_ACTION_IDS[$action_sel]}"
                    return 0
                    ;;
                ESC|LEFT)
                    focus="sidebar"
                    ;;
                q|Q)
                    return 1
                    ;;
            esac
        fi
    done
}
