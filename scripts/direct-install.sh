#!/bin/bash
#===============================================================================
# Vany - Direct Protocol Installer
# Standalone installer/manager for a single protocol.
# Usage: VANY_PROTOCOL=reality bash direct-install.sh
#===============================================================================

set -e

PROTOCOL="${VANY_PROTOCOL:-}"
VANY_DIR="/opt/vany"
STATE_FILE="$VANY_DIR/state.json"
USERS_FILE="$VANY_DIR/users.json"
GITHUB_RAW="https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main"

# ── Colors (Vany theme) ──────────────────────────────────────────────────────
G='\033[38;5;42m'      # Green
LG='\033[38;5;48m'     # Light green
O='\033[38;5;214m'     # Orange
D='\033[38;5;240m'     # Dark gray
R='\033[0m'            # Reset
B='\033[1m'            # Bold
DM='\033[2m'           # Dim
RED='\033[38;5;130m'   # Red/warning
BLUE='\033[38;5;39m'   # Blue
YELLOW='\033[38;5;220m'

W=70  # Width

# ── Helpers ───────────────────────────────────────────────────────────────────

hr() { printf "  ${D}"; printf '─%.0s' $(seq 1 "$W"); printf "${R}\n"; }
section() { echo -e "\n  ${O}${B}$1${R}"; hr; }
step()    { echo -e "  ${G}>${R} $1"; }
ok()      { echo -e "  ${G}*${R} $1"; }
err()     { echo -e "  ${RED}!${R} $1"; }
info()    { echo -e "  ${D}  $1${R}"; }

# ── ASCII Art Banners ─────────────────────────────────────────────────────────

declare -A BANNERS
BANNERS[reality]='░█▀▄░█▀▀░█▀█░█░░░▀█▀░▀█▀░█░█
░█▀▄░█▀▀░█▀█░█░░░░█░░░█░░░█░
░▀░▀░▀▀▀░▀░▀░▀▀▀░▀▀▀░░▀░░░▀░'

BANNERS[ws]='░█░█░█▀▀░░░█░█▀▀░█▀▄░█▀█
░█▄█░▀▀█░▄▀░░█░░░█░█░█░█
░▀░▀░▀▀▀░▀░░░▀▀▀░▀▀░░▀░▀'

BANNERS[hysteria]='░█░█░█░█░█▀▀░▀█▀░█▀▀░█▀▄░▀█▀░█▀█
░█▀█░░█░░▀▀█░░█░░█▀▀░█▀▄░░█░░█▀█
░▀░▀░░▀░░▀▀▀░░▀░░▀▀▀░▀░▀░▀▀▀░▀░▀'

BANNERS[wg]='░█░█░▀█▀░█▀▄░█▀▀░█▀▀░█░█░█▀█░█▀▄░█▀▄
░█▄█░░█░░█▀▄░█▀▀░█░█░█░█░█▀█░█▀▄░█░█
░▀░▀░▀▀▀░▀░▀░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀░▀░▀▀░'

BANNERS[vray]='░█░█░█▀▄░█▀█░█░█
░▀▄▀░█▀▄░█▀█░░█░
░░▀░░▀░▀░▀░▀░░▀░'

BANNERS[http-obfs]='░█░█░▀█▀░▀█▀░█▀█░░░█▀█░█▀▄░█▀▀░█▀▀
░█▀█░░█░░░█░░█▀▀░░░█░█░█▀▄░█▀▀░▀▀█
░▀░▀░░▀░░░▀░░▀░░░░░▀▀▀░▀▀░░▀░░░▀▀▀'

BANNERS[mtp]='░█▄█░▀█▀░█▀█░█▀▄░█▀█░▀█▀░█▀█
░█░█░░█░░█▀▀░█▀▄░█░█░░█░░█░█
░▀░▀░░▀░░▀░░░▀░▀░▀▀▀░░▀░░▀▀▀'

BANNERS[ssh-tunnel]='░█▀▀░█▀▀░█░█░░░▀█▀░█░█░█▀█░█▀█░█▀▀░█░░
░▀▀█░▀▀█░█▀█░░░░█░░█░█░█░█░█░█░█▀▀░█░░
░▀▀▀░▀▀▀░▀░▀░░░░▀░░▀▀▀░▀░▀░▀░▀░▀▀▀░▀▀▀'

BANNERS[dnstt]='░█▀▄░█▀█░█▀▀░▀█▀░▀█▀
░█░█░█░█░▀▀█░░█░░░█░
░▀▀░░▀░▀░▀▀▀░░▀░░░▀░'

BANNERS[slipstream]='░█▀▀░█░░░▀█▀░█▀█░█▀▀░▀█▀░█▀▄░█▀▀░█▀█░█▄█
░▀▀█░█░░░░█░░█▀▀░▀▀█░░█░░█▀▄░█▀▀░█▀█░█░█
░▀▀▀░▀▀▀░▀▀▀░▀░░░▀▀▀░░▀░░▀░▀░▀▀▀░▀░▀░▀░▀'

BANNERS[noizdns]='░█▀█░█▀█░▀█▀░▀█▀░█▀▄░█▀█░█▀▀
░█░█░█░█░░█░░░█░░█░█░█░█░▀▀█
░▀░▀░▀▀▀░▀▀▀░▀▀▀░▀▀░░▀░▀░▀▀▀'

BANNERS[conduit]='░█▀▀░█▀█░█▀█░█▀▄░█░█░▀█▀░▀█▀
░█░░░█░█░█░█░█░█░█░█░░█░░░█░
░▀▀▀░▀▀▀░▀░▀░▀▀░░▀▀▀░▀▀▀░░▀░'

BANNERS[tor-bridge]='░▀█▀░█▀█░█▀▄░░░█▀▄░█▀▄░▀█▀░█▀▄░█▀▀░█▀▀
░░█░░█░█░█▀▄░░░█▀▄░█▀▄░░█░░█░█░█░█░█▀▀
░░▀░░▀▀▀░▀░▀░░░▀▀░░▀░▀░▀▀▀░▀▀░░▀▀▀░▀▀▀'

BANNERS[snowflake]='░█▀▀░█▀█░█▀█░█░█░█▀▀░█░░░█▀█░█░█░█▀▀
░▀▀█░█░█░█░█░█▄█░█▀▀░█░░░█▀█░█▀▄░█▀▀
░▀▀▀░▀░▀░▀▀▀░▀░▀░▀░░░▀▀▀░▀░▀░▀░▀░▀▀▀'

BANNERS[sos]='░█▀▀░█▀█░█▀▀
░▀▀█░█░█░▀▀█
░▀▀▀░▀▀▀░▀▀▀'

# ── Protocol Metadata ─────────────────────────────────────────────────────────

declare -A PROTO_NAME PROTO_DESC PROTO_PORTS PROTO_NEEDS_DOMAIN PROTO_SCRIPT

PROTO_NAME[reality]="VLESS + REALITY"
PROTO_DESC[reality]="TLS camouflage proxy. Borrows real website certificates."
PROTO_PORTS[reality]="443/tcp"
PROTO_NEEDS_DOMAIN[reality]="No"
PROTO_SCRIPT[reality]="install-xray.sh"

PROTO_NAME[ws]="VLESS + WS + CDN"
PROTO_DESC[ws]="WebSocket proxy behind Cloudflare CDN. IP fully hidden."
PROTO_PORTS[ws]="80/tcp 443/tcp"
PROTO_NEEDS_DOMAIN[ws]="Yes"
PROTO_SCRIPT[ws]="install-xray.sh"

PROTO_NAME[hysteria]="Hysteria v2"
PROTO_DESC[hysteria]="QUIC-based proxy. Fastest on lossy/throttled networks."
PROTO_PORTS[hysteria]="8443/udp"
PROTO_NEEDS_DOMAIN[hysteria]="No"
PROTO_SCRIPT[hysteria]="install-hysteria.sh"

PROTO_NAME[wg]="WireGuard"
PROTO_DESC[wg]="Full-device VPN tunnel. Kernel-level performance."
PROTO_PORTS[wg]="51820/udp"
PROTO_NEEDS_DOMAIN[wg]="No"
PROTO_SCRIPT[wg]="install-wireguard.sh"

PROTO_NAME[vray]="VLESS + TLS"
PROTO_DESC[vray]="Classic V2Ray with real TLS certificates."
PROTO_PORTS[vray]="443/tcp"
PROTO_NEEDS_DOMAIN[vray]="Yes"
PROTO_SCRIPT[vray]="install-xray.sh"

PROTO_NAME[http-obfs]="HTTP Obfuscation"
PROTO_DESC[http-obfs]="CDN host header spoofing. Hides behind popular domains."
PROTO_PORTS[http-obfs]="80/tcp"
PROTO_NEEDS_DOMAIN[http-obfs]="CDN"
PROTO_SCRIPT[http-obfs]="install-http-obfs.sh"

PROTO_NAME[mtp]="MTProto Proxy"
PROTO_DESC[mtp]="Telegram-only proxy with Fake-TLS camouflage."
PROTO_PORTS[mtp]="443/tcp"
PROTO_NEEDS_DOMAIN[mtp]="No"
PROTO_SCRIPT[mtp]="install-xray.sh"

PROTO_NAME[ssh-tunnel]="SSH Tunnel"
PROTO_DESC[ssh-tunnel]="Basic SOCKS5 proxy over SSH. Universally available."
PROTO_PORTS[ssh-tunnel]="22/tcp"
PROTO_NEEDS_DOMAIN[ssh-tunnel]="No"
PROTO_SCRIPT[ssh-tunnel]="install-ssh-tunnel.sh"

PROTO_NAME[dnstt]="DNSTT"
PROTO_DESC[dnstt]="DNS tunnel. ~42 KB/s, last resort when all else fails."
PROTO_PORTS[dnstt]="53/udp 53/tcp"
PROTO_NEEDS_DOMAIN[dnstt]="Yes"
PROTO_SCRIPT[dnstt]="install-dnstt.sh"

PROTO_NAME[slipstream]="Slipstream"
PROTO_DESC[slipstream]="Enhanced DNS tunnel with QUIC+TLS. ~63 KB/s."
PROTO_PORTS[slipstream]="53/udp"
PROTO_NEEDS_DOMAIN[slipstream]="Yes"
PROTO_SCRIPT[slipstream]="install-slipstream.sh"

PROTO_NAME[noizdns]="NoizDNS"
PROTO_DESC[noizdns]="DPI-resistant DNSTT fork with noise padding."
PROTO_PORTS[noizdns]="53/udp"
PROTO_NEEDS_DOMAIN[noizdns]="Yes"
PROTO_SCRIPT[noizdns]="install-noizdns.sh"

PROTO_NAME[conduit]="Conduit (Psiphon Relay)"
PROTO_DESC[conduit]="Psiphon volunteer relay. Auto-configures, zero maintenance."
PROTO_PORTS[conduit]="auto"
PROTO_NEEDS_DOMAIN[conduit]="No"
PROTO_SCRIPT[conduit]="install-conduit.sh"

PROTO_NAME[tor-bridge]="Tor Bridge (obfs4)"
PROTO_DESC[tor-bridge]="obfs4 pluggable transport bridge for the Tor network."
PROTO_PORTS[tor-bridge]="9001/tcp"
PROTO_NEEDS_DOMAIN[tor-bridge]="No"
PROTO_SCRIPT[tor-bridge]="install-tor-bridge.sh"

PROTO_NAME[snowflake]="Snowflake Proxy"
PROTO_DESC[snowflake]="WebRTC Tor relay. Zero config, minimal resources."
PROTO_PORTS[snowflake]="--"
PROTO_NEEDS_DOMAIN[snowflake]="No"
PROTO_SCRIPT[snowflake]="install-snowflake.sh"

PROTO_NAME[sos]="SOS Emergency Chat"
PROTO_DESC[sos]="E2E encrypted emergency chat over DNS tunnel."
PROTO_PORTS[sos]="8899/tcp"
PROTO_NEEDS_DOMAIN[sos]="Yes"
PROTO_SCRIPT[sos]="install-sos.sh"

# ── Validation ────────────────────────────────────────────────────────────────

if [[ -z "$PROTOCOL" ]]; then
    echo -e "\n  ${RED}! No protocol specified${R}"
    echo -e "  ${D}Usage: VANY_PROTOCOL=reality bash direct-install.sh${R}\n"
    exit 1
fi

if [[ -z "${PROTO_NAME[$PROTOCOL]+x}" ]]; then
    echo -e "\n  ${RED}! Unknown protocol: $PROTOCOL${R}"
    echo -e "  ${D}Valid: reality ws hysteria wg vray http-obfs mtp ssh-tunnel dnstt slipstream noizdns conduit tor-bridge snowflake sos${R}\n"
    exit 1
fi

# ── Root Check ────────────────────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
    echo -e "\n  ${RED}! This installer must be run as root${R}"
    echo -e "  ${D}Use: curl vany.sh/$PROTOCOL | sudo bash${R}\n"
    exit 1
fi

# ── Display Banner ────────────────────────────────────────────────────────────

clear 2>/dev/null || true
echo ""

banner="${BANNERS[$PROTOCOL]}"
if [[ -n "$banner" ]]; then
    while IFS= read -r line; do
        local_len=${#line}
        pad=$(( (W - local_len) / 2 + 2 ))
        printf "%*s" "$pad" ""
        echo -e "${G}${line}${R}"
    done <<< "$banner"
    echo ""
fi

# ── Protocol Info ─────────────────────────────────────────────────────────────

name="${PROTO_NAME[$PROTOCOL]}"
desc="${PROTO_DESC[$PROTOCOL]}"
ports="${PROTO_PORTS[$PROTOCOL]}"
domain="${PROTO_NEEDS_DOMAIN[$PROTOCOL]}"

echo -e "  ${LG}${B}${name}${R}"
echo -e "  ${D}${desc}${R}"
echo ""
echo -e "  ${D}Ports: ${R}${ports}    ${D}Domain required: ${R}${domain}"
hr

# ── Check Current Status ─────────────────────────────────────────────────────

container_name=""
is_installed=false
is_running=false

check_status() {
    if [[ -f "$STATE_FILE" ]] && command -v jq &>/dev/null; then
        local proto_key="$PROTOCOL"
        [[ "$proto_key" == "ws" || "$proto_key" == "reality" || "$proto_key" == "vray" || "$proto_key" == "mtp" || "$proto_key" == "http-obfs" ]] && proto_key="xray"
        [[ "$proto_key" == "wg" ]] && proto_key="wireguard"

        local status
        status=$(jq -r ".protocols.${proto_key}.status // empty" "$STATE_FILE" 2>/dev/null)
        container_name=$(jq -r ".protocols.${proto_key}.container // empty" "$STATE_FILE" 2>/dev/null)

        if [[ -n "$status" ]]; then
            is_installed=true
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
                is_running=true
            fi
        fi
    fi
}

check_status

echo ""
if $is_running; then
    echo -e "  ${G}${B}Status:${R} ${G}Running${R}  ${D}(container: ${container_name})${R}"
elif $is_installed; then
    echo -e "  ${YELLOW}${B}Status:${R} ${YELLOW}Stopped${R}  ${D}(container: ${container_name})${R}"
else
    echo -e "  ${D}${B}Status:${R} ${D}Not installed${R}"
fi
echo ""

# ── Menu ──────────────────────────────────────────────────────────────────────

show_menu() {
    if $is_installed; then
        echo -e "  ${O}${B}What would you like to do?${R}"
        echo ""
        echo -e "    ${LG}1${R}  Reinstall / Update"
        echo -e "    ${LG}2${R}  Add user"
        echo -e "    ${LG}3${R}  Remove user"
        echo -e "    ${LG}4${R}  Show connection config"
        echo -e "    ${LG}5${R}  View logs"
        echo -e "    ${LG}6${R}  Restart"
        echo -e "    ${LG}7${R}  Uninstall"
        echo -e "    ${LG}q${R}  Quit"
    else
        echo -e "  ${O}${B}Ready to install?${R}"
        echo ""
        echo -e "    ${LG}1${R}  Install ${name}"
        echo -e "    ${LG}q${R}  Quit"
    fi
    echo ""
}

# ── Bootstrap System ──────────────────────────────────────────────────────────

do_bootstrap() {
    section "System Bootstrap"

    # Download and source bootstrap
    local bootstrap_file="/tmp/vany-bootstrap.sh"
    step "Downloading bootstrap..."
    if ! curl -sfL "$GITHUB_RAW/scripts/docker-bootstrap.sh" -o "$bootstrap_file"; then
        err "Failed to download bootstrap script"
        exit 1
    fi
    source "$bootstrap_file"
    bootstrap
    echo ""
}

# ── Download Protocol Script ──────────────────────────────────────────────────

do_download_script() {
    local script_name="${PROTO_SCRIPT[$PROTOCOL]}"
    local script_path="/tmp/vany-${script_name}"

    step "Downloading ${script_name}..."
    if ! curl -sfL "$GITHUB_RAW/scripts/protocols/${script_name}" -o "$script_path"; then
        err "Failed to download install script"
        exit 1
    fi
    chmod +x "$script_path"
    source "$script_path"
}

# ── Install Protocol ──────────────────────────────────────────────────────────

do_install() {
    section "Installing ${name}"

    do_bootstrap
    do_download_script

    # Call the appropriate install function
    case "$PROTOCOL" in
        reality)
            install_xray
            add_reality_inbound "" "" ""
            ;;
        ws)
            install_xray
            # WS inbound needs domain
            read -rp "  Enter your domain (e.g. ws.example.com): " ws_domain
            if [[ -n "$ws_domain" ]]; then
                add_ws_inbound "$ws_domain"
            fi
            ;;
        hysteria)
            install_hysteria
            ;;
        wg)
            install_wireguard
            ;;
        dnstt)
            install_dnstt
            ;;
        conduit)
            install_conduit
            ;;
        sos)
            install_sos
            ;;
        tor-bridge)
            install_tor_bridge
            ;;
        snowflake)
            install_snowflake
            ;;
        slipstream)
            install_slipstream
            ;;
        noizdns)
            install_noizdns
            ;;
        ssh-tunnel)
            install_ssh_tunnel
            ;;
        http-obfs)
            install_xray
            read -rp "  Enter CDN domain: " cdn_domain
            if [[ -n "$cdn_domain" ]]; then
                add_http_obfs_inbound "$cdn_domain"
            fi
            ;;
        vray)
            install_xray
            read -rp "  Enter your domain: " vray_domain
            if [[ -n "$vray_domain" ]]; then
                add_vray_inbound "$vray_domain"
            fi
            ;;
        mtp)
            install_xray
            add_mtp_inbound
            ;;
        *)
            err "Install function not implemented for: $PROTOCOL"
            return 1
            ;;
    esac

    echo ""
    ok "Installation complete!"
    echo ""

    # Refresh status
    check_status
}

# ── User Management ───────────────────────────────────────────────────────────

do_add_user() {
    section "Add User"
    read -rp "  Username: " username
    [[ -z "$username" ]] && { err "Username required"; return; }

    do_download_script

    case "$PROTOCOL" in
        reality)  add_reality_client "$username" ;;
        ws)       add_ws_client "$username" ;;
        wg)       add_wg_peer "$username" ;;
        hysteria) echo "  Hysteria uses shared password auth" ;;
        *)        info "User management not implemented for $PROTOCOL" ;;
    esac
}

do_remove_user() {
    section "Remove User"
    read -rp "  Username to remove: " username
    [[ -z "$username" ]] && { err "Username required"; return; }

    do_download_script

    case "$PROTOCOL" in
        reality)  remove_reality_client "$username" ;;
        ws)       remove_ws_client "$username" ;;
        wg)       remove_wg_peer "$username" ;;
        *)        info "User management not implemented for $PROTOCOL" ;;
    esac
}

# ── Show Config ───────────────────────────────────────────────────────────────

do_show_config() {
    section "Connection Config"

    local server_ip
    server_ip=$(jq -r '.ip // "unknown"' "$STATE_FILE" 2>/dev/null)

    case "$PROTOCOL" in
        reality)
            if [[ -f "$USERS_FILE" ]]; then
                echo -e "  ${D}Users with REALITY config:${R}"
                jq -r '.users | to_entries[] | select(.value.protocols.reality) | "  \(.key): \(.value.protocols.reality.uuid)"' "$USERS_FILE" 2>/dev/null
            fi
            ;;
        wg)
            if [[ -d "$VANY_DIR/wg/peers" ]]; then
                echo -e "  ${D}WireGuard peer configs:${R}"
                ls "$VANY_DIR/wg/peers/" 2>/dev/null
            fi
            ;;
        hysteria)
            local pw
            pw=$(jq -r '.protocols.hysteria.password // "unknown"' "$STATE_FILE" 2>/dev/null)
            echo -e "  hysteria2://${pw}@${server_ip}:8443/?insecure=1#vany-hysteria"
            ;;
        *)
            info "Config display not implemented for $PROTOCOL"
            ;;
    esac
    echo ""
}

# ── View Logs ─────────────────────────────────────────────────────────────────

do_logs() {
    section "Container Logs (last 30 lines)"
    if [[ -n "$container_name" ]]; then
        docker logs --tail 30 "$container_name" 2>&1 | while IFS= read -r line; do
            echo -e "  ${D}${line}${R}"
        done
    else
        info "Container not found"
    fi
    echo ""
}

# ── Restart ───────────────────────────────────────────────────────────────────

do_restart() {
    section "Restarting"
    if [[ -n "$container_name" ]]; then
        docker restart "$container_name"
        ok "Container restarted"
    else
        err "Container not found"
    fi
    echo ""
    check_status
}

# ── Uninstall ─────────────────────────────────────────────────────────────────

do_uninstall() {
    section "Uninstall ${name}"
    echo -e "  ${RED}This will stop and remove the container.${R}"
    read -rp "  Are you sure? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if [[ -n "$container_name" ]]; then
            docker stop "$container_name" 2>/dev/null || true
            docker rm "$container_name" 2>/dev/null || true
            ok "Container removed"
        fi

        # Clean state
        if [[ -f "$STATE_FILE" ]] && command -v jq &>/dev/null; then
            local proto_key="$PROTOCOL"
            [[ "$proto_key" == "ws" || "$proto_key" == "reality" || "$proto_key" == "vray" || "$proto_key" == "mtp" || "$proto_key" == "http-obfs" ]] && proto_key="xray"
            [[ "$proto_key" == "wg" ]] && proto_key="wireguard"
            jq "del(.protocols.${proto_key})" "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
        fi

        is_installed=false
        is_running=false
        ok "Uninstall complete"
    else
        info "Cancelled"
    fi
    echo ""
}

# ── Main Loop ─────────────────────────────────────────────────────────────────

while true; do
    show_menu
    read -rp "  > " choice
    echo ""

    case "$choice" in
        1)
            if $is_installed; then
                do_install  # Reinstall
            else
                do_install
            fi
            ;;
        2) $is_installed && do_add_user || do_install ;;
        3) $is_installed && do_remove_user ;;
        4) $is_installed && do_show_config ;;
        5) $is_installed && do_logs ;;
        6) $is_installed && do_restart ;;
        7) $is_installed && do_uninstall ;;
        q|Q|exit) echo -e "  ${D}Goodbye${R}\n"; exit 0 ;;
        *) err "Invalid option" ;;
    esac
done
