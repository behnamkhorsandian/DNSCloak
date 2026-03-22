#!/bin/bash
#===============================================================================
# Vany FindNS Scanner - Discover non-sanctioned DNS resolvers
# Usage: curl vany.sh/tools/findns | bash
#        curl vany.sh/tools/findns | bash -s -- -n 20
#===============================================================================

set -e

COUNT=15
TIMEOUT=3
TEST_DOMAIN="google.com"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n) COUNT="$2"; shift 2 ;;
        -t) TIMEOUT="$2"; shift 2 ;;
        --help) echo "Usage: findns [-n count] [-t timeout]"; exit 0 ;;
        *) shift ;;
    esac
done

# Colors
G='\033[38;5;42m'
O='\033[38;5;214m'
D='\033[38;5;240m'
R='\033[0m'
B='\033[1m'

echo ""
echo -e "  ${G}${B}FindNS Scanner${R} ${D}v1.0${R}"
echo -e "  ${D}Find accessible DNS resolvers for DNS tunnel transport${R}"
echo ""

# Public DNS resolvers to test
DNS_SERVERS=(
    "8.8.8.8|Google"
    "8.8.4.4|Google-alt"
    "1.1.1.1|Cloudflare"
    "1.0.0.1|Cloudflare-alt"
    "9.9.9.9|Quad9"
    "149.112.112.112|Quad9-alt"
    "208.67.222.222|OpenDNS"
    "208.67.220.220|OpenDNS-alt"
    "94.140.14.14|AdGuard"
    "94.140.15.15|AdGuard-alt"
    "76.76.19.19|Alternate"
    "76.223.122.150|Alternate-alt"
    "185.228.168.9|CleanBrowsing"
    "185.228.169.9|CleanBrowsing-alt"
    "77.88.8.8|Yandex"
    "77.88.8.1|Yandex-alt"
    "64.6.64.6|Verisign"
    "64.6.65.6|Verisign-alt"
    "156.154.70.1|Neustar"
    "156.154.71.1|Neustar-alt"
    "45.11.45.11|dns0.eu"
    "193.110.81.0|dns0.eu-alt"
    "176.103.130.130|AdGuard-fam"
    "176.103.130.131|AdGuard-fam-alt"
    "114.114.114.114|114DNS"
    "223.5.5.5|Alibaba"
    "119.29.29.29|DNSPod"
    "180.76.76.76|Baidu"
    "101.226.4.6|360"
)

# Test a DNS server
test_dns() {
    local ip="$1"
    local name="$2"
    local start end latency result

    start=$(date +%s%N 2>/dev/null || echo 0)

    # Try dig first, fall back to nslookup
    if command -v dig &>/dev/null; then
        result=$(dig +short +time="$TIMEOUT" +tries=1 @"$ip" "$TEST_DOMAIN" A 2>/dev/null | head -1) || result=""
    elif command -v nslookup &>/dev/null; then
        result=$(nslookup -timeout="$TIMEOUT" "$TEST_DOMAIN" "$ip" 2>/dev/null | grep -A1 "Name:" | grep "Address" | head -1 | awk '{print $2}') || result=""
    else
        result=$(curl -s --connect-timeout "$TIMEOUT" "https://dns.google/resolve?name=$TEST_DOMAIN&type=A" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | cut -d'"' -f4) || result=""
    fi

    end=$(date +%s%N 2>/dev/null || echo 0)

    if [[ "$start" == "0" || "$end" == "0" ]]; then
        latency="?"
    else
        latency=$(( (end - start) / 1000000 ))
    fi

    echo "$ip|$name|${latency}|$result"
}

# Header
printf "  ${D}%-18s %-18s %-10s %-8s${R}\n" "DNS Server" "Provider" "Latency" "Status"
printf "  ${D}%-18s %-18s %-10s %-8s${R}\n" "──────────────" "────────────" "───────" "──────"

ACCESSIBLE=()
BLOCKED=()
TESTED=0

for entry in "${DNS_SERVERS[@]}"; do
    [[ $TESTED -ge $COUNT ]] && break
    TESTED=$((TESTED + 1))

    IFS='|' read -r ip name <<< "$entry"
    result=$(test_dns "$ip" "$name")
    IFS='|' read -r r_ip r_name r_lat r_result <<< "$result"

    if [[ -n "$r_result" && "$r_result" != "" ]]; then
        printf "  ${G}%-18s %-18s %-10s %-8s${R}\n" "$r_ip" "$r_name" "${r_lat}ms" "OK"
        ACCESSIBLE+=("$r_ip|$r_name|$r_lat")
    else
        printf "  ${D}%-18s %-18s %-10s %-8s${R}\n" "$r_ip" "$r_name" "${r_lat}ms" "BLOCKED"
        BLOCKED+=("$r_ip|$r_name")
    fi
done

echo ""
echo -e "  ${G}Accessible: ${#ACCESSIBLE[@]}${R}  ${D}Blocked: ${#BLOCKED[@]}  Tested: $TESTED${R}"

if [[ ${#ACCESSIBLE[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${O}${B}Fastest resolvers:${R}"
    printf '%s\n' "${ACCESSIBLE[@]}" | sort -t'|' -k3 -n | head -5 | while IFS='|' read -r ip name lat; do
        echo -e "    ${G}$ip${R}  ${D}$name  ${lat}ms${R}"
    done
fi

echo ""
echo -e "  ${D}Use accessible resolvers for DNSTT DoH transport${R}"
echo ""
