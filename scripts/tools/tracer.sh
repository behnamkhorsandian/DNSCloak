#!/bin/bash
#===============================================================================
# Vany IP Tracer - Detect ISP, ASN, and routing info
# Usage: curl vany.sh/tools/tracer | bash
#        curl vany.sh/tools/tracer | bash -s -- --save   (save baseline)
#        curl vany.sh/tools/tracer | bash -s -- --compare (compare with baseline)
#===============================================================================

set -e

TIMEOUT=5
SAVE_FILE="/tmp/.vany-tracer-baseline"
MODE="normal"

# Parse args
for arg in "$@"; do
    case "$arg" in
        --save)    MODE="save" ;;
        --compare) MODE="compare" ;;
    esac
done

# Colors
G='\033[38;5;42m'
O='\033[38;5;214m'
D='\033[38;5;240m'
R='\033[0m'
B='\033[1m'
RED='\033[38;5;130m'

echo ""
echo -e "  ${G}${B}IP Tracer${R} ${D}v2.0${R}"
echo -e "  ${D}Detect your IP, ISP, ASN, and routing path${R}"
echo ""

# Get IP info from multiple sources (fallback chain)
get_ip_info() {
    local info=""

    # Try ip-api.com (no API key needed, JSON, includes lat/lon/timezone)
    info=$(curl -s --connect-timeout "$TIMEOUT" "http://ip-api.com/json/?fields=query,isp,org,as,country,countryCode,regionName,city,lat,lon,timezone,reverse,mobile,proxy,hosting" 2>/dev/null) || true

    if [[ -n "$info" ]] && echo "$info" | grep -q '"query"'; then
        echo "$info"
        return 0
    fi

    # Fallback: ipinfo.io
    info=$(curl -s --connect-timeout "$TIMEOUT" "https://ipinfo.io/json" 2>/dev/null) || true

    if [[ -n "$info" ]] && echo "$info" | grep -q '"ip"'; then
        local ip org city region country loc timezone hostname
        ip=$(echo "$info" | grep -o '"ip": *"[^"]*"' | cut -d'"' -f4)
        org=$(echo "$info" | grep -o '"org": *"[^"]*"' | cut -d'"' -f4)
        city=$(echo "$info" | grep -o '"city": *"[^"]*"' | cut -d'"' -f4)
        region=$(echo "$info" | grep -o '"region": *"[^"]*"' | cut -d'"' -f4)
        country=$(echo "$info" | grep -o '"country": *"[^"]*"' | cut -d'"' -f4)
        loc=$(echo "$info" | grep -o '"loc": *"[^"]*"' | cut -d'"' -f4)
        timezone=$(echo "$info" | grep -o '"timezone": *"[^"]*"' | cut -d'"' -f4)
        hostname=$(echo "$info" | grep -o '"hostname": *"[^"]*"' | cut -d'"' -f4)
        local lat="" lon=""
        if [[ -n "$loc" ]]; then
            lat=$(echo "$loc" | cut -d, -f1)
            lon=$(echo "$loc" | cut -d, -f2)
        fi
        echo "{\"query\":\"$ip\",\"isp\":\"$org\",\"org\":\"$org\",\"as\":\"$org\",\"country\":\"$country\",\"countryCode\":\"$country\",\"regionName\":\"$region\",\"city\":\"$city\",\"lat\":\"${lat:-0}\",\"lon\":\"${lon:-0}\",\"timezone\":\"${timezone:-unknown}\",\"reverse\":\"${hostname:-}\",\"proxy\":false,\"hosting\":false,\"mobile\":false}"
        return 0
    fi

    # Last resort: just get IP
    local my_ip
    my_ip=$(curl -s --connect-timeout "$TIMEOUT" "https://ifconfig.me" 2>/dev/null || curl -s --connect-timeout "$TIMEOUT" "https://api.ipify.org" 2>/dev/null || echo "unknown")
    echo "{\"query\":\"$my_ip\",\"isp\":\"unknown\",\"org\":\"unknown\",\"as\":\"unknown\",\"country\":\"unknown\",\"countryCode\":\"\",\"regionName\":\"\",\"city\":\"\",\"lat\":\"0\",\"lon\":\"0\",\"timezone\":\"unknown\",\"reverse\":\"\",\"proxy\":false,\"hosting\":false,\"mobile\":false}"
}

echo -e "  ${D}Detecting...${R}"

INFO=$(get_ip_info)

# Parse JSON (portable, no jq dependency)
parse_field() {
    echo "$INFO" | grep -o "\"$1\": *\"[^\"]*\"" | cut -d'"' -f4
}
parse_num() {
    echo "$INFO" | grep -o "\"$1\": *[0-9.e+-]*" | awk -F': *' '{print $2}'
}
parse_bool() {
    echo "$INFO" | grep -o "\"$1\": *[a-z]*" | awk -F: '{gsub(/[ ]/,"",$2); print $2}'
}

IP=$(parse_field "query")
ISP=$(parse_field "isp")
ORG=$(parse_field "org")
ASN=$(parse_field "as")
COUNTRY=$(parse_field "country")
COUNTRY_CODE=$(parse_field "countryCode")
REGION=$(parse_field "regionName")
CITY=$(parse_field "city")
LAT=$(parse_num "lat")
LON=$(parse_num "lon")
TZ=$(parse_field "timezone")
HOSTNAME=$(parse_field "reverse")
IS_PROXY=$(parse_bool "proxy")
IS_HOSTING=$(parse_bool "hosting")
IS_MOBILE=$(parse_bool "mobile")

# Build location string
LOCATION="${CITY:+$CITY, }${REGION:+$REGION, }$COUNTRY"

echo ""
echo -e "  ${O}${B}Your Connection${R}"
echo -e "  ${D}────────────────────────────────────────${R}"
printf "  %-16s ${G}%s${R}\n" "IP Address:" "$IP"
[[ -n "$HOSTNAME" ]] && printf "  %-16s %s\n" "Hostname:" "$HOSTNAME"
printf "  %-16s %s\n" "ISP:" "$ISP"
printf "  %-16s %s\n" "Organization:" "$ORG"
printf "  %-16s %s\n" "ASN:" "$ASN"
printf "  %-16s %s\n" "Location:" "$LOCATION"
[[ "$LAT" != "0" ]] && printf "  %-16s %s, %s\n" "Coordinates:" "$LAT" "$LON"
printf "  %-16s %s\n" "Timezone:" "$TZ"

# Connection type
echo ""
echo -e "  ${O}${B}Connection Type${R}"
echo -e "  ${D}────────────────────────────────────────${R}"

conn_type="Direct"
if [[ "$IS_PROXY" == "true" ]]; then
    conn_type="Proxy/VPN"
    echo -e "  ${G}* Proxy/VPN detected by provider${R}"
elif [[ "$IS_HOSTING" == "true" ]]; then
    conn_type="Hosting/DC"
    echo -e "  ${G}* Running on hosting/data center IP${R}"
elif echo "$ISP" | grep -qiE 'cloudflare|warp|vpn|proxy|tunnel|hosting|data ?center|server|cloud|digital.ocean|amazon|google.cloud|hetzner|vultr|linode|ovh'; then
    conn_type="Likely VPN/DC"
    echo -e "  ${G}* ISP name suggests VPN or data center${R}"
else
    echo -e "  ${O}* Direct connection (no VPN detected)${R}"
fi
[[ "$IS_MOBILE" == "true" ]] && echo -e "  ${D}* Mobile network detected${R}"

# DNS leak check
echo ""
echo -e "  ${O}${B}DNS Resolver${R}"
echo -e "  ${D}────────────────────────────────────────${R}"

# Auto-install dig if missing
if ! command -v dig &>/dev/null && ! command -v nslookup &>/dev/null; then
    echo -e "  ${D}Installing DNS tools...${R}"
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y -qq dnsutils 2>/dev/null || apt-get install -y -qq dnsutils 2>/dev/null || true
    elif command -v yum &>/dev/null; then
        sudo yum install -y -q bind-utils 2>/dev/null || yum install -y -q bind-utils 2>/dev/null || true
    elif command -v apk &>/dev/null; then
        sudo apk add --quiet bind-tools 2>/dev/null || apk add --quiet bind-tools 2>/dev/null || true
    elif command -v brew &>/dev/null; then
        brew install --quiet bind 2>/dev/null || true
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm bind-tools 2>/dev/null || pacman -S --noconfirm bind-tools 2>/dev/null || true
    fi
fi

if command -v dig &>/dev/null; then
    DNS_IP=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | head -1) || DNS_IP=""
    if [[ -n "$DNS_IP" ]]; then
        printf "  %-16s %s\n" "DNS Exit IP:" "$DNS_IP"
        if [[ "$DNS_IP" == "$IP" ]]; then
            echo -e "  ${D}DNS resolves through same IP (no leak)${R}"
        else
            echo -e "  ${RED}DNS exits through different IP - possible leak${R}"
        fi
    else
        echo -e "  ${D}Could not determine DNS resolver${R}"
    fi
elif command -v nslookup &>/dev/null; then
    DNS_SERVER=$(nslookup example.com 2>/dev/null | grep "Server:" | awk '{print $2}' | head -1) || DNS_SERVER=""
    [[ -n "$DNS_SERVER" ]] && printf "  %-16s %s\n" "DNS Server:" "$DNS_SERVER"
else
    echo -e "  ${D}Install 'dig' or 'nslookup' for DNS leak detection${R}"
fi

# Save/compare mode
if [[ "$MODE" == "save" ]]; then
    echo ""
    echo "$IP|$ISP|$COUNTRY_CODE|$CITY|$LAT|$LON|$TZ|$conn_type" > "$SAVE_FILE"
    echo -e "  ${G}Baseline saved.${R} Connect VPN, then run:"
    echo -e "  ${D}curl vany.sh/tools/tracer | bash -s -- --compare${R}"
fi

if [[ "$MODE" == "compare" ]] && [[ -f "$SAVE_FILE" ]]; then
    echo ""
    echo -e "  ${O}${B}Before/After Comparison${R}"
    echo -e "  ${D}────────────────────────────────────────${R}"

    IFS='|' read -r B_IP B_ISP B_CC B_CITY B_LAT B_LON B_TZ B_TYPE < "$SAVE_FILE"
    printf "  %-16s %-24s -> ${G}%s${R}\n" "IP:" "$B_IP" "$IP"
    printf "  %-16s %-24s -> ${G}%s${R}\n" "ISP:" "$B_ISP" "$ISP"
    printf "  %-16s %-24s -> ${G}%s${R}\n" "Location:" "$B_CITY ($B_CC)" "$CITY ($COUNTRY_CODE)"
    printf "  %-16s %-24s -> ${G}%s${R}\n" "Timezone:" "$B_TZ" "$TZ"
    printf "  %-16s %-24s -> ${G}%s${R}\n" "Type:" "$B_TYPE" "$conn_type"

    if [[ "$B_IP" != "$IP" ]]; then
        echo ""
        echo -e "  ${G}* IP changed - VPN is working${R}"
    else
        echo -e "  ${RED}* Same IP - VPN may not be active${R}"
    fi

    if [[ "$B_CC" != "$COUNTRY_CODE" ]]; then
        echo -e "  ${G}* Country changed: $B_CC -> $COUNTRY_CODE${R}"
    fi
fi

echo ""
echo -e "  ${D}Tip: Run with --save before VPN, --compare after${R}"
echo ""
