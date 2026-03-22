#!/bin/bash
#===============================================================================
# Vany CFRay Scanner - Find clean Cloudflare IPs
# Usage: curl vany.sh/tools/cfray | bash
#        curl vany.sh/tools/cfray | bash -s -- -n 20 -t 2
#===============================================================================

set -e

# Defaults
COUNT=10
TIMEOUT=3
TARGET_HOST="${CF_HOST:-speed.cloudflare.com}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n) COUNT="$2"; shift 2 ;;
        -t) TIMEOUT="$2"; shift 2 ;;
        -h|--host) TARGET_HOST="$2"; shift 2 ;;
        --help) echo "Usage: cfray [-n count] [-t timeout] [-h host]"; exit 0 ;;
        *) shift ;;
    esac
done

# Colors
G='\033[38;5;42m'   # Green
O='\033[38;5;214m'  # Orange
D='\033[38;5;240m'  # Dark gray
R='\033[0m'         # Reset
B='\033[1m'         # Bold

echo ""
echo -e "  ${G}${B}CFRay Scanner${R} ${D}v1.0${R}"
echo -e "  ${D}Find clean Cloudflare IPs for HTTP Obfuscation${R}"
echo ""

# Cloudflare IP ranges (v4)
CF_RANGES=(
    "104.16.0.0/13"
    "104.24.0.0/14"
    "172.64.0.0/13"
    "162.158.0.0/15"
    "198.41.128.0/17"
    "141.101.64.0/18"
    "190.93.240.0/20"
    "188.114.96.0/20"
    "197.234.240.0/22"
    "108.162.192.0/18"
    "131.0.72.0/22"
)

# Generate random IPs from Cloudflare ranges
random_cf_ip() {
    local range="${CF_RANGES[$((RANDOM % ${#CF_RANGES[@]}))]}"
    local base="${range%%/*}"
    local mask="${range##*/}"

    IFS='.' read -r a b c d <<< "$base"
    local base_int=$(( (a << 24) + (b << 16) + (c << 8) + d ))
    local host_bits=$(( 32 - mask ))
    local max_host=$(( (1 << host_bits) - 1 ))
    local rand_host=$(( RANDOM % max_host + 1 ))
    local ip_int=$(( base_int + rand_host ))

    echo "$(( (ip_int >> 24) & 255 )).$(( (ip_int >> 16) & 255 )).$(( (ip_int >> 8) & 255 )).$(( ip_int & 255 ))"
}

# Test an IP
test_ip() {
    local ip="$1"
    local start end latency http_code

    start=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time()*1e9))" 2>/dev/null || echo 0)

    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout "$TIMEOUT" \
        --max-time "$((TIMEOUT + 2))" \
        -H "Host: $TARGET_HOST" \
        "http://$ip/" 2>/dev/null) || http_code="000"

    end=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time()*1e9))" 2>/dev/null || echo 0)

    if [[ "$start" == "0" || "$end" == "0" ]]; then
        latency="?"
    else
        latency=$(( (end - start) / 1000000 ))
    fi

    echo "$ip|$http_code|${latency}ms"
}

# Header
printf "  ${D}%-18s %-8s %-10s %-8s${R}\n" "IP" "Status" "Latency" "Result"
printf "  ${D}%-18s %-8s %-10s %-8s${R}\n" "──────────────" "──────" "───────" "──────"

RESULTS=()
TESTED=0
FOUND=0
TOTAL_TO_TEST=$((COUNT * 3))

while [[ $FOUND -lt $COUNT && $TESTED -lt $TOTAL_TO_TEST ]]; do
    ip=$(random_cf_ip)
    TESTED=$((TESTED + 1))

    result=$(test_ip "$ip")
    IFS='|' read -r r_ip r_code r_latency <<< "$result"

    if [[ "$r_code" == "200" || "$r_code" == "301" || "$r_code" == "302" || "$r_code" == "403" ]]; then
        FOUND=$((FOUND + 1))
        printf "  ${G}%-18s %-8s %-10s %-8s${R}\n" "$r_ip" "$r_code" "$r_latency" "OK"
        RESULTS+=("$r_ip|$r_latency")
    else
        printf "  ${D}%-18s %-8s %-10s %-8s${R}\n" "$r_ip" "$r_code" "$r_latency" "skip"
    fi
done

echo ""
echo -e "  ${G}Found $FOUND clean IPs${R} ${D}(tested $TESTED)${R}"

# Sort results by latency and show top 5
if [[ ${#RESULTS[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${O}${B}Best IPs (by latency):${R}"
    printf '%s\n' "${RESULTS[@]}" | sort -t'|' -k2 -n | head -5 | while IFS='|' read -r ip lat; do
        echo -e "    ${G}$ip${R}  ${D}$lat${R}"
    done
fi

echo ""
echo -e "  ${D}Use these IPs as 'address' in your VLESS client config${R}"
echo -e "  ${D}Set your domain as 'Host' header${R}"
echo ""
