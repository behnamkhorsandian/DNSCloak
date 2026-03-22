#!/bin/bash
#===============================================================================
# Vany Speed Test - Quick bandwidth test via Cloudflare
# Usage: curl vany.sh/tools/speedtest | bash
#===============================================================================

set -e

TIMEOUT=10

# Colors
G='\033[38;5;42m'
O='\033[38;5;214m'
D='\033[38;5;240m'
R='\033[0m'
B='\033[1m'

echo ""
echo -e "  ${G}${B}Speed Test${R} ${D}v1.0${R}"
echo -e "  ${D}Quick bandwidth test via Cloudflare Workers${R}"
echo ""

# Download test using Cloudflare's speed test endpoint
run_download_test() {
    local size="$1"
    local label="$2"

    local start end elapsed speed_bps speed_mbps
    start=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time()*1e9))" 2>/dev/null || echo 0)

    local bytes
    bytes=$(curl -s --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT * 3))" \
        -o /dev/null -w "%{size_download}" \
        "https://speed.cloudflare.com/__down?bytes=$size" 2>/dev/null) || bytes=0

    end=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time()*1e9))" 2>/dev/null || echo 0)

    if [[ "$start" == "0" || "$end" == "0" || "$bytes" == "0" ]]; then
        echo "  $label: failed"
        return
    fi

    elapsed=$(( (end - start) / 1000000 ))  # ms
    if [[ $elapsed -gt 0 ]]; then
        speed_bps=$(( bytes * 8 * 1000 / elapsed ))
        speed_mbps=$(( speed_bps / 1000000 ))
        local remainder=$(( (speed_bps % 1000000) / 10000 ))
        printf "  %-12s ${G}%d.%02d Mbps${R}  ${D}(%d ms, %d bytes)${R}\n" "$label:" "$speed_mbps" "$remainder" "$elapsed" "$bytes"
    else
        echo -e "  $label: ${D}too fast to measure${R}"
    fi
}

# Latency test
echo -e "  ${O}${B}Latency${R}"
echo -e "  ${D}────────────────────────────────────${R}"

LATENCIES=()
for i in 1 2 3 4 5; do
    start=$(date +%s%N 2>/dev/null || echo 0)
    curl -s --connect-timeout 5 -o /dev/null "https://speed.cloudflare.com/__down?bytes=0" 2>/dev/null || true
    end=$(date +%s%N 2>/dev/null || echo 0)

    if [[ "$start" != "0" && "$end" != "0" ]]; then
        lat=$(( (end - start) / 1000000 ))
        LATENCIES+=("$lat")
        printf "  Ping %d:     ${D}%d ms${R}\n" "$i" "$lat"
    fi
done

if [[ ${#LATENCIES[@]} -gt 0 ]]; then
    total=0
    for l in "${LATENCIES[@]}"; do total=$((total + l)); done
    avg=$((total / ${#LATENCIES[@]}))
    echo -e "  ${G}Average:    ${avg} ms${R}"
fi

# Download speed tests
echo ""
echo -e "  ${O}${B}Download Speed${R}"
echo -e "  ${D}────────────────────────────────────${R}"

run_download_test 102400 "100 KB"
run_download_test 1048576 "1 MB"
run_download_test 10485760 "10 MB"

# Upload test (POST to Cloudflare)
echo ""
echo -e "  ${O}${B}Upload Speed${R}"
echo -e "  ${D}────────────────────────────────────${R}"

upload_test() {
    local size="$1"
    local label="$2"

    # Generate random data
    local start end elapsed speed_bps speed_mbps
    start=$(date +%s%N 2>/dev/null || echo 0)

    local bytes
    bytes=$(dd if=/dev/urandom bs="$size" count=1 2>/dev/null | \
        curl -s --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT * 3))" \
        -o /dev/null -w "%{size_upload}" \
        -X POST --data-binary @- \
        "https://speed.cloudflare.com/__up" 2>/dev/null) || bytes=0

    end=$(date +%s%N 2>/dev/null || echo 0)

    if [[ "$start" == "0" || "$end" == "0" || "$bytes" == "0" ]]; then
        echo "  $label: failed"
        return
    fi

    elapsed=$(( (end - start) / 1000000 ))
    if [[ $elapsed -gt 0 ]]; then
        speed_bps=$(( bytes * 8 * 1000 / elapsed ))
        speed_mbps=$(( speed_bps / 1000000 ))
        local remainder=$(( (speed_bps % 1000000) / 10000 ))
        printf "  %-12s ${G}%d.%02d Mbps${R}  ${D}(%d ms, %d bytes)${R}\n" "$label:" "$speed_mbps" "$remainder" "$elapsed" "$bytes"
    else
        echo -e "  $label: ${D}too fast to measure${R}"
    fi
}

upload_test 102400 "100 KB"
upload_test 1048576 "1 MB"

echo ""
echo -e "  ${D}Results may vary. Run multiple times for accuracy.${R}"
echo ""
