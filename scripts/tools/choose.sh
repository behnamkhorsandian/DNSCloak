#!/bin/bash
#===============================================================================
# Vany Protocol Chooser - Interactive questionnaire
# Usage: curl vany.sh/choose | bash
#===============================================================================

# ── Colors (Vany theme) ──────────────────────────────────────────────────────
G='\033[38;5;42m'
LG='\033[38;5;48m'
O='\033[38;5;214m'
D='\033[38;5;240m'
R='\033[0m'
B='\033[1m'
DM='\033[2m'
RED='\033[38;5;130m'
YELLOW='\033[38;5;220m'
BLUE='\033[38;5;39m'

W=70

hr() { printf "  ${D}"; printf '─%.0s' $(seq 1 "$W"); printf "${R}\n"; }

clear 2>/dev/null || true
echo ""
echo -e "  ${G}░█▀▀░█░█░█▀█░█▀█░█▀▀░█▀▀${R}"
echo -e "  ${G}░█░░░█▀█░█░█░█░█░▀▀█░█▀▀${R}"
echo -e "  ${G}░▀▀▀░▀░▀░▀▀▀░▀▀▀░▀▀▀░▀▀▀${R}"
echo ""
echo -e "  ${O}${B}Vany Protocol Chooser${R}"
echo -e "  ${D}Answer a few questions to find your best protocol${R}"
echo ""
hr
echo ""

# ── State ─────────────────────────────────────────────────────────────────────
HAS_DOMAIN="no"
HAS_CDN="no"
HAS_CLEAN_IP="no"
CENSORSHIP_LEVEL="moderate"  # light, moderate, heavy, total
USE_CASE="general"           # general, telegram, tor, emergency
SPEED_PRIORITY="balanced"    # speed, stealth, balanced

ask() {
    local prompt="$1"
    local var="$2"
    local options="$3"
    echo -e "  ${LG}${B}?${R} ${prompt}"
    echo -e "  ${D}${options}${R}"
    read -rp "  > " answer
    echo ""
    eval "$var=\"$answer\""
}

# ── Questions ─────────────────────────────────────────────────────────────────

echo -e "  ${O}${B}Q1.${R} Do you have a domain name?"
echo -e "  ${D}(e.g. example.com - needed for CDN-based protocols)${R}"
echo -e "    ${LG}1${R}  Yes, I have a domain"
echo -e "    ${LG}2${R}  No domain"
echo ""
read -rp "  > " q1
echo ""

case "$q1" in
    1) HAS_DOMAIN="yes" ;;
    *) HAS_DOMAIN="no" ;;
esac

if [[ "$HAS_DOMAIN" == "yes" ]]; then
    echo -e "  ${O}${B}Q2.${R} Is your domain on Cloudflare CDN?"
    echo -e "  ${D}(Required for WS+CDN and HTTP Obfuscation)${R}"
    echo -e "    ${LG}1${R}  Yes, Cloudflare"
    echo -e "    ${LG}2${R}  Other CDN or no CDN"
    echo ""
    read -rp "  > " q2
    echo ""
    case "$q2" in
        1) HAS_CDN="yes" ;;
        *) HAS_CDN="no" ;;
    esac
fi

echo -e "  ${O}${B}Q3.${R} How severe is the censorship in your country?"
echo -e "    ${LG}1${R}  Light   ${D}(some sites blocked, DNS filtering)${R}"
echo -e "    ${LG}2${R}  Moderate ${D}(VPNs partially blocked, DPI active)${R}"
echo -e "    ${LG}3${R}  Heavy   ${D}(most VPNs blocked, active probing, Iran/Russia)${R}"
echo -e "    ${LG}4${R}  Total   ${D}(internet shutdown, only DNS works)${R}"
echo ""
read -rp "  > " q3
echo ""

case "$q3" in
    1) CENSORSHIP_LEVEL="light" ;;
    2) CENSORSHIP_LEVEL="moderate" ;;
    3) CENSORSHIP_LEVEL="heavy" ;;
    4) CENSORSHIP_LEVEL="total" ;;
esac

echo -e "  ${O}${B}Q4.${R} What's your primary use case?"
echo -e "    ${LG}1${R}  General browsing + apps"
echo -e "    ${LG}2${R}  Telegram only"
echo -e "    ${LG}3${R}  Contributing to Tor network"
echo -e "    ${LG}4${R}  Emergency communication during blackout"
echo ""
read -rp "  > " q4
echo ""

case "$q4" in
    1) USE_CASE="general" ;;
    2) USE_CASE="telegram" ;;
    3) USE_CASE="tor" ;;
    4) USE_CASE="emergency" ;;
esac

if [[ "$USE_CASE" == "general" ]]; then
    echo -e "  ${O}${B}Q5.${R} What matters more to you?"
    echo -e "    ${LG}1${R}  Speed          ${D}(streaming, downloads, gaming)${R}"
    echo -e "    ${LG}2${R}  Stealth        ${D}(avoid detection at all costs)${R}"
    echo -e "    ${LG}3${R}  Balanced       ${D}(good speed + hard to detect)${R}"
    echo ""
    read -rp "  > " q5
    echo ""

    case "$q5" in
        1) SPEED_PRIORITY="speed" ;;
        2) SPEED_PRIORITY="stealth" ;;
        *) SPEED_PRIORITY="balanced" ;;
    esac
fi

if [[ "$HAS_CDN" == "yes" ]]; then
    echo -e "  ${O}${B}Q6.${R} Do you already have a clean Cloudflare IP?"
    echo -e "  ${D}(An IP that isn't blocked by your ISP)${R}"
    echo -e "    ${LG}1${R}  Yes"
    echo -e "    ${LG}2${R}  No / Not sure"
    echo ""
    read -rp "  > " q6
    echo ""
    case "$q6" in
        1) HAS_CLEAN_IP="yes" ;;
        *) HAS_CLEAN_IP="no" ;;
    esac
fi

# ── Recommendation Engine ─────────────────────────────────────────────────────

hr
echo ""
echo -e "  ${G}${B}Recommended Protocols${R}"
echo -e "  ${D}Based on your answers:${R}"
echo ""

# Score-based recommendation
declare -A SCORES
SCORES=()

recommend() {
    local proto="$1"
    local score="$2"
    local reason="$3"
    SCORES[$proto]=$(( ${SCORES[$proto]:-0} + score ))
    REASONS[$proto]="${REASONS[$proto]:+${REASONS[$proto]}; }$reason"
}

declare -A REASONS

# Telegram only
if [[ "$USE_CASE" == "telegram" ]]; then
    recommend "mtp" 100 "Built for Telegram"
    recommend "reality" 30 "Also works for Telegram"
fi

# Tor contribution
if [[ "$USE_CASE" == "tor" ]]; then
    recommend "tor-bridge" 100 "Direct Tor bridge relay"
    recommend "snowflake" 80 "Zero-config Tor proxy"
fi

# Emergency / blackout
if [[ "$USE_CASE" == "emergency" || "$CENSORSHIP_LEVEL" == "total" ]]; then
    recommend "dnstt" 90 "Works during internet shutdowns"
    recommend "noizdns" 85 "DPI-resistant DNS tunnel"
    recommend "slipstream" 80 "Faster DNS tunnel"
    recommend "sos" 70 "Emergency encrypted chat"
fi

# General use - score based on conditions
if [[ "$USE_CASE" == "general" ]]; then
    # Domain + CDN = WS+CDN is great
    if [[ "$HAS_CDN" == "yes" ]]; then
        recommend "ws" 80 "IP hidden behind Cloudflare"
        recommend "http-obfs" 70 "CDN host header spoofing"
    fi

    # No domain = REALITY is king
    if [[ "$HAS_DOMAIN" == "no" ]]; then
        recommend "reality" 90 "No domain needed, TLS camouflage"
    fi

    # Heavy censorship
    if [[ "$CENSORSHIP_LEVEL" == "heavy" ]]; then
        recommend "reality" 80 "Immune to active probing"
        [[ "$HAS_CDN" == "yes" ]] && recommend "ws" 85 "CDN makes IP unblockable"
        recommend "hysteria" 40 "QUIC may be blocked in heavy censorship"
    fi

    # Light/moderate censorship
    if [[ "$CENSORSHIP_LEVEL" == "light" || "$CENSORSHIP_LEVEL" == "moderate" ]]; then
        recommend "hysteria" 75 "Fastest protocol on QUIC"
        recommend "wg" 65 "Fast kernel-level VPN"
        recommend "reality" 60 "Good balance of speed + stealth"
    fi

    # Speed priority
    if [[ "$SPEED_PRIORITY" == "speed" ]]; then
        recommend "hysteria" 30 "QUIC optimized for speed"
        recommend "wg" 25 "WireGuard has lowest overhead"
    fi

    # Stealth priority
    if [[ "$SPEED_PRIORITY" == "stealth" ]]; then
        recommend "reality" 30 "Looks like real HTTPS traffic"
        [[ "$HAS_CDN" == "yes" ]] && recommend "ws" 25 "Hidden behind CDN"
    fi

    # Fallbacks
    recommend "ssh-tunnel" 10 "Universal fallback"
fi

# Sort and display top recommendations
echo -e "  ${O}${B}Rank  Protocol             Score  Install Command${R}"
hr

# Sort protocols by score
sorted=$(for proto in "${!SCORES[@]}"; do
    echo "${SCORES[$proto]}|$proto"
done | sort -t'|' -k1 -rn)

declare -A PROTO_NAMES
PROTO_NAMES[reality]="VLESS+REALITY"
PROTO_NAMES[ws]="VLESS+WS+CDN"
PROTO_NAMES[hysteria]="Hysteria v2"
PROTO_NAMES[wg]="WireGuard"
PROTO_NAMES[vray]="VLESS+TLS"
PROTO_NAMES[http-obfs]="HTTP Obfuscation"
PROTO_NAMES[mtp]="MTProto"
PROTO_NAMES[ssh-tunnel]="SSH Tunnel"
PROTO_NAMES[dnstt]="DNSTT"
PROTO_NAMES[slipstream]="Slipstream"
PROTO_NAMES[noizdns]="NoizDNS"
PROTO_NAMES[conduit]="Conduit"
PROTO_NAMES[tor-bridge]="Tor Bridge"
PROTO_NAMES[snowflake]="Snowflake"
PROTO_NAMES[sos]="SOS Chat"

rank=1
top_proto=""
while IFS='|' read -r score proto; do
    [[ -z "$proto" ]] && continue
    name="${PROTO_NAMES[$proto]:-$proto}"
    reason="${REASONS[$proto]}"
    marker=""
    if [[ $rank -eq 1 ]]; then
        marker=" ${G}${B}<-- BEST MATCH${R}"
        top_proto="$proto"
    fi

    printf "  ${LG}%-6s${R}%-21s${G}%-7s${R}${D}curl vany.sh/%-12s| sudo bash${R}%s\n" \
        "#$rank" "$name" "$score" "$proto " "$marker"

    if [[ -n "$reason" ]]; then
        echo -e "  ${D}      ${reason}${R}"
    fi
    echo ""
    ((rank++))
    [[ $rank -gt 5 ]] && break
done <<< "$sorted"

# No recommendations
if [[ -z "$top_proto" ]]; then
    echo -e "  ${D}No strong recommendation based on your answers.${R}"
    echo -e "  ${D}Try: curl vany.sh/reality | sudo bash  (good default)${R}"
    echo ""
fi

hr
echo ""

if [[ -n "$HAS_CDN" && "$HAS_CDN" == "no" && "$HAS_DOMAIN" == "yes" ]]; then
    echo -e "  ${YELLOW}Tip:${R} ${D}Move your domain to Cloudflare for more CDN-based options${R}"
    echo ""
fi

if [[ "$HAS_CDN" == "yes" && "$HAS_CLEAN_IP" == "no" ]]; then
    echo -e "  ${YELLOW}Tip:${R} ${D}Find a clean Cloudflare IP first:${R}"
    echo -e "       ${LG}curl vany.sh/tools/cfray | bash${R}"
    echo ""
fi

echo -e "  ${D}Full TUI:${R}  ${LG}curl vany.sh | sudo bash${R}"
echo -e "  ${D}Catalog:${R}   ${LG}curl vany.sh${R}"
echo ""
