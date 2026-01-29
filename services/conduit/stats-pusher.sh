#!/bin/bash
#===============================================================================
# DNSCloak - Health & Stats Pusher
# Pushes live stats and service health to stats.dnscloak.net
# Monitors: Conduit, Xray (Reality/WS/VRAY), DNSTT, WireGuard, SOS
# Usage: curl -sSL stats.dnscloak.net/setup | sudo bash
#===============================================================================

set -euo pipefail

# Config
STATS_ENDPOINT="https://stats.dnscloak.net/push"
PUSH_INTERVAL=5  # seconds
LOG_FILE="/var/log/conduit-stats.log"

#-------------------------------------------------------------------------------
# Check health of all DNSCloak services
#-------------------------------------------------------------------------------

get_services_health() {
    local services='{"conduit":"unknown","xray":"unknown","dnstt":"unknown","wireguard":"unknown","sos":"unknown"}'
    
    # Conduit (Docker)
    if docker ps -q -f name=conduit &>/dev/null && [[ -n "$(docker ps -q -f name=conduit)" ]]; then
        services=$(echo "$services" | sed 's/"conduit":"unknown"/"conduit":"up"/')
    elif docker ps -a -q -f name=conduit &>/dev/null && [[ -n "$(docker ps -a -q -f name=conduit)" ]]; then
        services=$(echo "$services" | sed 's/"conduit":"unknown"/"conduit":"down"/')
    else
        services=$(echo "$services" | sed 's/"conduit":"unknown"/"conduit":"not_installed"/')
    fi
    
    # Xray (Reality, WS, VRAY)
    if systemctl is-active xray &>/dev/null; then
        services=$(echo "$services" | sed 's/"xray":"unknown"/"xray":"up"/')
    elif systemctl list-unit-files xray.service &>/dev/null; then
        services=$(echo "$services" | sed 's/"xray":"unknown"/"xray":"down"/')
    else
        services=$(echo "$services" | sed 's/"xray":"unknown"/"xray":"not_installed"/')
    fi
    
    # DNSTT
    if systemctl is-active dnstt &>/dev/null || pgrep -f "dnstt-server" &>/dev/null; then
        services=$(echo "$services" | sed 's/"dnstt":"unknown"/"dnstt":"up"/')
    elif [[ -f /opt/dnscloak/dnstt/server.key ]]; then
        services=$(echo "$services" | sed 's/"dnstt":"unknown"/"dnstt":"down"/')
    else
        services=$(echo "$services" | sed 's/"dnstt":"unknown"/"dnstt":"not_installed"/')
    fi
    
    # WireGuard
    if systemctl is-active wg-quick@wg0 &>/dev/null || wg show wg0 &>/dev/null 2>&1; then
        services=$(echo "$services" | sed 's/"wireguard":"unknown"/"wireguard":"up"/')
    elif [[ -f /opt/dnscloak/wg/wg0.conf ]] || [[ -f /etc/wireguard/wg0.conf ]]; then
        services=$(echo "$services" | sed 's/"wireguard":"unknown"/"wireguard":"down"/')
    else
        services=$(echo "$services" | sed 's/"wireguard":"unknown"/"wireguard":"not_installed"/')
    fi
    
    # SOS Relay
    if systemctl is-active sos-relay &>/dev/null || pgrep -f "relay.py" &>/dev/null; then
        services=$(echo "$services" | sed 's/"sos":"unknown"/"sos":"up"/')
    elif [[ -f /opt/dnscloak/sos/relay.py ]]; then
        services=$(echo "$services" | sed 's/"sos":"unknown"/"sos":"down"/')
    else
        services=$(echo "$services" | sed 's/"sos":"unknown"/"sos":"not_installed"/')
    fi
    
    echo "$services"
}

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
    
    # Get system info (VM specs)
    local machine vcpus ram bandwidth
    if command -v curl &>/dev/null; then
        # Try GCP metadata
        machine=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/machine-type" 2>/dev/null | awk -F'/' '{print $NF}' || echo "")
    fi
    [[ -z "$machine" ]] && machine="unknown"
    vcpus=$(nproc 2>/dev/null || echo "?")
    ram=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' | sed 's/i$//' || echo "?")
    # Estimate bandwidth based on vCPUs (2 Gbps per vCPU, max 16 for most instances)
    if [[ "$vcpus" =~ ^[0-9]+$ ]]; then
        local bw=$((vcpus * 2))
        [[ $bw -gt 16 ]] && bw=16
        bandwidth="${bw} Gbps"
    else
        bandwidth="? Gbps"
    fi
    
    # Get services health
    local services
    services=$(get_services_health)
    
    # Build JSON
    cat <<EOF
{
  "uptime": "$uptime",
  "connecting": ${connecting:-0},
  "connected": ${connected:-0},
  "up": "$up",
  "down": "$down",
  "countries": $countries,
  "system": {
    "machine": "$machine",
    "vcpus": $vcpus,
    "ram": "$ram",
    "bandwidth": "$bandwidth"
  },
  "services": $services,
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
