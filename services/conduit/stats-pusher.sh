#!/bin/bash
#===============================================================================
# DNSCloak - Conduit Stats Pusher
# Pushes live stats to stats.dnscloak.net for website display
# Usage: curl -sSL stats.dnscloak.net/setup | sudo bash
#===============================================================================

set -euo pipefail

# Config
STATS_ENDPOINT="https://stats.dnscloak.net/push"
PUSH_INTERVAL=5  # seconds
LOG_FILE="/var/log/conduit-stats.log"

#-------------------------------------------------------------------------------
# Parse Conduit stats from Docker logs
#-------------------------------------------------------------------------------

get_stats() {
    local uptime connecting connected up down
    
    # Get container uptime
    if docker inspect conduit &>/dev/null; then
        local started_at
        started_at=$(docker inspect --format='{{.State.StartedAt}}' conduit 2>/dev/null || echo "")
        if [[ -n "$started_at" ]]; then
            local start_epoch now_epoch diff_seconds
            start_epoch=$(date -d "$started_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${started_at%%.*}" +%s 2>/dev/null || echo "0")
            now_epoch=$(date +%s)
            diff_seconds=$((now_epoch - start_epoch))
            
            local hours=$((diff_seconds / 3600))
            local minutes=$(((diff_seconds % 3600) / 60))
            uptime="${hours}h ${minutes}m"
        else
            uptime="0h 0m"
        fi
    else
        uptime="offline"
    fi
    
    # Parse latest [STATS] line from docker logs
    local stats_line
    stats_line=$(docker logs --tail 100 conduit 2>&1 | grep -oE '\[STATS\].*' | tail -1 || echo "")
    
    if [[ -n "$stats_line" ]]; then
        # Format: [STATS] Connecting: 12 | Connected: 312 | Up: 145.1 GB | Down: 1.5 TB
        connecting=$(echo "$stats_line" | grep -oE 'Connecting: [0-9]+' | grep -oE '[0-9]+' || echo "0")
        connected=$(echo "$stats_line" | grep -oE 'Connected: [0-9]+' | grep -oE '[0-9]+' || echo "0")
        up=$(echo "$stats_line" | grep -oE 'Up: [0-9.]+ [KMGT]?B' | sed 's/Up: //' || echo "0 B")
        down=$(echo "$stats_line" | grep -oE 'Down: [0-9.]+ [KMGT]?B' | sed 's/Down: //' || echo "0 B")
    else
        connecting="0"
        connected="0"
        up="0 B"
        down="0 B"
    fi
    
    # Get peer countries (if geoiplookup available)
    local countries="[]"
    if command -v geoiplookup &>/dev/null && command -v tcpdump &>/dev/null; then
        # Get unique IPs from recent connections and lookup countries
        local country_data
        country_data=$(timeout 2 tcpdump -i any -c 50 -nn 'tcp and port 443' 2>/dev/null | \
            grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
            sort -u | \
            head -20 | \
            while read -r ip; do
                geoiplookup "$ip" 2>/dev/null | grep -oE '[A-Z]{2},' | tr -d ','
            done | \
            sort | uniq -c | sort -rn | head -5 | \
            awk '{printf "{\"code\":\"%s\",\"count\":%d},", $2, $1}' || echo "")
        
        if [[ -n "$country_data" ]]; then
            countries="[${country_data%,}]"
        fi
    fi
    
    # Build JSON
    cat <<EOF
{
  "uptime": "$uptime",
  "connecting": ${connecting:-0},
  "connected": ${connected:-0},
  "up": "$up",
  "down": "$down",
  "countries": $countries,
  "timestamp": $(date +%s)
}
EOF
}

#-------------------------------------------------------------------------------
# Push stats to Worker
#-------------------------------------------------------------------------------

push_stats() {
    local stats
    stats=$(get_stats)
    
    # Push to endpoint (fire and forget, don't fail on error)
    curl -sSL -X POST "$STATS_ENDPOINT" \
        -H "Content-Type: application/json" \
        -d "$stats" \
        --connect-timeout 5 \
        --max-time 10 \
        >/dev/null 2>&1 || true
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pushed: $stats" >> "$LOG_FILE"
}

#-------------------------------------------------------------------------------
# Main loop
#-------------------------------------------------------------------------------

main() {
    echo "[*] Starting Conduit stats pusher..."
    echo "[*] Endpoint: $STATS_ENDPOINT"
    echo "[*] Interval: ${PUSH_INTERVAL}s"
    
    # Ensure log file exists
    touch "$LOG_FILE"
    
    while true; do
        push_stats
        sleep "$PUSH_INTERVAL"
    done
}

#-------------------------------------------------------------------------------
# Installer mode (when run with --install)
#-------------------------------------------------------------------------------

install_service() {
    echo "[*] Installing stats-pusher systemd service..."
    
    # Copy script to /opt/conduit
    mkdir -p /opt/conduit
    cp "$0" /opt/conduit/stats-pusher.sh
    chmod +x /opt/conduit/stats-pusher.sh
    
    # Create systemd service
    cat > /etc/systemd/system/conduit-stats.service <<EOF
[Unit]
Description=Conduit Stats Pusher
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/opt/conduit/stats-pusher.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start
    systemctl daemon-reload
    systemctl enable conduit-stats
    systemctl start conduit-stats
    
    echo "[+] Stats pusher installed and running!"
    echo "[*] View logs: journalctl -u conduit-stats -f"
}

#-------------------------------------------------------------------------------
# Entry point
#-------------------------------------------------------------------------------

case "${1:-}" in
    --install)
        install_service
        ;;
    *)
        main
        ;;
esac
