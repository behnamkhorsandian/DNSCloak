#!/bin/bash
#===============================================================================
# Vany IP Tracer - Detect ISP, ASN, and routing info
# Usage: curl vany.sh/tools/tracer | bash
#===============================================================================

set -e

TIMEOUT=5

# Colors
G='\033[38;5;42m'
O='\033[38;5;214m'
D='\033[38;5;240m'
R='\033[0m'
B='\033[1m'

echo ""
echo -e "  ${G}${B}IP Tracer${R} ${D}v1.0${R}"
echo -e "  ${D}Detect your IP, ISP, ASN, and routing path${R}"
echo ""

# Get IP info from multiple sources (fallback chain)
get_ip_info() {
    local info=""

    # Try ip-api.com (no API key needed, JSON)
    info=$(curl -s --connect-timeout "$TIMEOUT" "http://ip-api.com/json/?fields=query,isp,org,as,country,regionName,city" 2>/dev/null) || true

    if [[ -n "$info" ]] && echo "$info" | grep -q '"query"'; then
        echo "$info"
        return 0
    fi

    # Fallback: ipinfo.io
    info=$(curl -s --connect-timeout "$TIMEOUT" "https://ipinfo.io/json" 2>/dev/null) || true

    if [[ -n "$info" ]] && echo "$info" | grep -q '"ip"'; then
        # Normalize to ip-api format
        local ip isp org city region country
        ip=$(echo "$info" | grep -o '"ip": *"[^"]*"' | cut -d'"' -f4)
        org=$(echo "$info" | grep -o '"org": *"[^"]*"' | cut -d'"' -f4)
        city=$(echo "$info" | grep -o '"city": *"[^"]*"' | cut -d'"' -f4)
        region=$(echo "$info" | grep -o '"region": *"[^"]*"' | cut -d'"' -f4)
        country=$(echo "$info" | grep -o '"country": *"[^"]*"' | cut -d'"' -f4)
        echo "{\"query\":\"$ip\",\"isp\":\"$org\",\"org\":\"$org\",\"as\":\"$org\",\"country\":\"$country\",\"regionName\":\"$region\",\"city\":\"$city\"}"
        return 0
    fi

    # Last resort: just get IP
    local my_ip
    my_ip=$(curl -s --connect-timeout "$TIMEOUT" "https://ifconfig.me" 2>/dev/null || curl -s --connect-timeout "$TIMEOUT" "https://api.ipify.org" 2>/dev/null || echo "unknown")
    echo "{\"query\":\"$my_ip\",\"isp\":\"unknown\",\"org\":\"unknown\",\"as\":\"unknown\",\"country\":\"unknown\",\"regionName\":\"\",\"city\":\"\"}"
}

echo -e "  ${D}Detecting...${R}"

INFO=$(get_ip_info)

# Parse JSON (portable, no jq dependency)
parse_field() {
    echo "$INFO" | grep -o "\"$1\": *\"[^\"]*\"" | cut -d'"' -f4
}

IP=$(parse_field "query")
ISP=$(parse_field "isp")
ORG=$(parse_field "org")
ASN=$(parse_field "as")
COUNTRY=$(parse_field "country")
REGION=$(parse_field "regionName")
CITY=$(parse_field "city")

echo ""
echo -e "  ${O}${B}Your Connection${R}"
echo -e "  ${D}────────────────────────────────────${R}"
printf "  %-14s ${G}%s${R}\n" "IP Address:" "$IP"
printf "  %-14s %s\n" "ISP:" "$ISP"
printf "  %-14s %s\n" "Organization:" "$ORG"
printf "  %-14s %s\n" "ASN:" "$ASN"
printf "  %-14s %s\n" "Location:" "${CITY:+$CITY, }${REGION:+$REGION, }$COUNTRY"

# Check if behind VPN/Proxy
echo ""
echo -e "  ${O}${B}VPN Detection${R}"
echo -e "  ${D}────────────────────────────────────${R}"

# Simple heuristics
if echo "$ISP" | grep -qiE 'cloudflare|warp|vpn|proxy|tunnel|hosting|data ?center|server|cloud'; then
    echo -e "  ${G}Likely behind VPN/Proxy${R}"
else
    echo -e "  ${O}Likely direct connection (no VPN detected)${R}"
fi

# Test DNS leak
echo ""
echo -e "  ${O}${B}DNS Resolver${R}"
echo -e "  ${D}────────────────────────────────────${R}"

if command -v dig &>/dev/null; then
    DNS_IP=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | head -1) || DNS_IP=""
    if [[ -n "$DNS_IP" ]]; then
        if [[ "$DNS_IP" == "$IP" ]]; then
            echo -e "  DNS resolves through same IP ${D}(no leak)${R}"
        else
            echo -e "  DNS exit: ${G}$DNS_IP${R}"
            [[ "$DNS_IP" != "$IP" ]] && echo -e "  ${O}DNS may be leaking through different path${R}"
        fi
    else
        echo -e "  ${D}Could not determine DNS resolver${R}"
    fi
else
    echo -e "  ${D}Install 'dig' for DNS leak detection${R}"
fi

echo ""
