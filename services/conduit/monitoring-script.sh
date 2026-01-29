#!/bin/bash
#===============================================================================
# Conduit Monitoring Script
# Installed at /usr/local/bin/conduit
# Commands: status, logs, peers, start, stop, restart
#===============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# Configuration
CONDUIT_IMAGE="ghcr.io/ssmirr/conduit/conduit:latest"
CONDUIT_VOLUME="conduit-data"

#-------------------------------------------------------------------------------
# Check Root
#-------------------------------------------------------------------------------

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This command requires root. Use: sudo conduit $1${RESET}"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Check Dependencies
#-------------------------------------------------------------------------------

check_dependencies() {
    local deps=("$@")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Installing dependencies: ${missing[*]}${RESET}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq 2>/dev/null
        apt-get install -y -qq "${missing[@]}" geoip-database 2>/dev/null || true
    fi
}

#-------------------------------------------------------------------------------
# Show Status
#-------------------------------------------------------------------------------

show_status() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}             ${BOLD}CONDUIT - PSIPHON RELAY NODE${RESET}                       ${CYAN}║${RESET}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    
    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^conduit$"; then
        echo -e "  ${RED}Container not found${RESET}"
        echo "  Run: curl -sSL conduit.dnscloak.net | sudo bash"
        echo ""
        return 1
    fi
    
    # Get container status
    local status
    status=$(docker inspect -f '{{.State.Status}}' conduit 2>/dev/null)
    
    if [[ "$status" == "running" ]]; then
        echo -e "  Status:       ${GREEN}● Running${RESET}"
        
        # Get uptime
        local started
        started=$(docker inspect -f '{{.State.StartedAt}}' conduit 2>/dev/null | cut -d'.' -f1 | sed 's/T/ /')
        echo "  Started:      $started"
        
        # Get latest stats from logs
        echo ""
        echo -e "  ${CYAN}Latest Statistics:${RESET}"
        local stats_line
        stats_line=$(docker logs --tail 100 conduit 2>&1 | grep "\[STATS\]" | tail -1)
        
        if [[ -n "$stats_line" ]]; then
            # Parse and display stats nicely
            local connected connecting upload download
            connected=$(echo "$stats_line" | grep -oP 'Connected:\s*\K[0-9]+' || echo "0")
            connecting=$(echo "$stats_line" | grep -oP 'Connecting:\s*\K[0-9]+' || echo "0")
            upload=$(echo "$stats_line" | grep -oP 'Up:\s*\K[0-9.]+\s*[A-Za-z]+' || echo "0 B")
            download=$(echo "$stats_line" | grep -oP 'Down:\s*\K[0-9.]+\s*[A-Za-z]+' || echo "0 B")
            
            echo -e "  Clients:      ${GREEN}$connected${RESET} connected, ${YELLOW}$connecting${RESET} connecting"
            echo "  Upload:       $upload"
            echo "  Download:     $download"
        else
            echo "  Waiting for statistics... (may take a few minutes)"
        fi
    else
        echo -e "  Status:       ${RED}● $status${RESET}"
        echo ""
        echo "  To start: sudo conduit start"
    fi
    
    # Get configuration from container args
    local args_output
    args_output=$(docker inspect -f '{{range .Args}}{{println .}}{{end}}' conduit 2>/dev/null)
    
    local max_clients bandwidth
    max_clients=$(echo "$args_output" | grep -A1 -- "-m" | tail -1 | tr -d '\n')
    bandwidth=$(echo "$args_output" | grep -A1 -- "-b" | tail -1 | tr -d '\n')
    
    echo ""
    echo -e "  ${CYAN}Configuration:${RESET}"
    echo "  Max Clients:  ${max_clients:-200}"
    if [[ "$bandwidth" == "-1" ]]; then
        echo "  Bandwidth:    Unlimited"
    else
        echo "  Bandwidth:    ${bandwidth:-5} Mbps"
    fi
    echo "  Data Volume:  $CONDUIT_VOLUME"
    echo ""
    echo -e "  ${DIM}Run 'conduit logs' to see live statistics${RESET}"
    echo ""
}

#-------------------------------------------------------------------------------
# Show Live Logs
#-------------------------------------------------------------------------------

show_logs() {
    # Check if container is running
    if ! docker ps --filter "name=conduit" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -q "^conduit$"; then
        echo -e "${RED}Conduit is not running${RESET}"
        echo "Start with: sudo conduit start"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}              ${BOLD}LIVE CONDUIT STATISTICS${RESET}                            ${CYAN}║${RESET}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${DIM}Press Ctrl+C to exit${RESET}"
    echo ""
    
    # Follow logs and filter for STATS lines, format them nicely
    docker logs -f --tail 20 conduit 2>&1 | grep --line-buffered "\[STATS\]" | while read -r line; do
        # Extract values
        local connected connecting upload download
        connected=$(echo "$line" | grep -oP 'Connected:\s*\K[0-9]+' || echo "?")
        connecting=$(echo "$line" | grep -oP 'Connecting:\s*\K[0-9]+' || echo "?")
        upload=$(echo "$line" | grep -oP 'Up:\s*\K[0-9.]+\s*[A-Za-z]+' || echo "? B")
        download=$(echo "$line" | grep -oP 'Down:\s*\K[0-9.]+\s*[A-Za-z]+' || echo "? B")
        
        # Get timestamp
        local timestamp
        timestamp=$(date '+%H:%M:%S')
        
        # Print formatted line
        printf "  [%s] Clients: ${GREEN}%s${RESET} | Connecting: ${YELLOW}%s${RESET} | Up: %s | Down: %s\n" \
            "$timestamp" "$connected" "$connecting" "$upload" "$download"
    done
}

#-------------------------------------------------------------------------------
# Show Live Peers (Country Monitoring)
#-------------------------------------------------------------------------------

show_peers() {
    # Check if container is running
    if ! docker ps --filter "name=conduit" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -q "^conduit$"; then
        echo -e "${RED}Conduit is not running${RESET}"
        echo "Start with: sudo conduit start"
        return 1
    fi
    
    # Install dependencies
    check_dependencies tcpdump geoiplookup
    
    # Get local IP to filter out
    local local_ip
    local_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -1)
    
    # Create temp file for capturing IPs
    local tmp_file
    tmp_file=$(mktemp)
    
    # Cleanup on exit
    local stop_peers=0
    trap 'stop_peers=1; rm -f "$tmp_file"; echo ""; echo "Stopped."; exit 0' SIGINT SIGTERM
    
    echo ""
    
    # Monitor traffic in 5-second intervals
    while [[ $stop_peers -eq 0 ]]; do
        # Clear temp file
        true > "$tmp_file"
        
        # Capture traffic for 5 seconds
        timeout 5 tcpdump -n -i any -c 200 2>/dev/null | \
            grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
            grep -v "^127\." | \
            grep -v "^10\." | \
            grep -v "^172\.(1[6-9]|2[0-9]|3[0-1])\." | \
            grep -v "^192\.168\." | \
            grep -v "^${local_ip}$" | \
            sort -u >> "$tmp_file" 2>/dev/null || true
        
        # Process IPs and count by country
        declare -A country_count
        local total_ips=0
        
        while IFS= read -r ip; do
            if [[ -n "$ip" ]]; then
                local country
                country=$(geoiplookup "$ip" 2>/dev/null | head -1 | cut -d':' -f2- | sed 's/^[A-Z][A-Z], //' | sed 's/^ *//;s/ *$//')
                
                # Handle special cases
                if [[ -z "$country" ]] || [[ "$country" == *"not found"* ]] || [[ "$country" == *"Address"* ]]; then
                    country="Unknown"
                fi
                
                # Replace "Iran, Islamic Republic of" with "Free Iran"
                if [[ "$country" == "Iran, Islamic Republic of" ]]; then
                    country="Free Iran"
                fi
                
                ((country_count["$country"]++))
                ((total_ips++))
            fi
        done < "$tmp_file"
        
        # Clear screen and display results
        clear
        echo ""
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║${RESET}              ${BOLD}LIVE PEER CONNECTIONS BY COUNTRY${RESET}                   ${CYAN}║${RESET}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        echo -e "  ${DIM}Updated: $(date '+%Y-%m-%d %H:%M:%S') | Total IPs: $total_ips${RESET}"
        echo ""
        
        if [[ ${#country_count[@]} -gt 0 ]]; then
            # Sort by count (descending) and display with bar chart
            for country in "${!country_count[@]}"; do
                local count=${country_count[$country]}
                local bar=""
                local bar_len=$((count / 2))
                [[ $bar_len -gt 30 ]] && bar_len=30
                for ((i=0; i<bar_len; i++)); do bar+="█"; done
                printf "  %-35s %5d ${CYAN}%s${RESET}\n" "$country" "$count" "$bar"
            done | sort -t'│' -k2 -rn | head -20
        else
            echo "  Waiting for peer connections..."
            echo ""
            echo "  Traffic will appear here once Psiphon broker"
            echo "  assigns clients to your node."
        fi
        
        echo ""
        echo -e "  ${DIM}Press Ctrl+C to stop${RESET}"
        
        # Clear associative array for next iteration
        unset country_count
        
        # Wait before next update
        sleep 5
    done
    
    rm -f "$tmp_file"
}

#-------------------------------------------------------------------------------
# Start Container
#-------------------------------------------------------------------------------

start_container() {
    check_root "start"
    
    if docker ps --filter "name=conduit" --filter "status=running" --format '{{.Names}}' | grep -q "^conduit$"; then
        echo -e "${YELLOW}Conduit is already running${RESET}"
        return 0
    fi
    
    echo -e "${CYAN}Starting Conduit...${RESET}"
    if docker start conduit 2>/dev/null; then
        sleep 2
        if docker ps --filter "name=conduit" --filter "status=running" --format '{{.Names}}' | grep -q "^conduit$"; then
            echo -e "${GREEN}Conduit started successfully${RESET}"
        else
            echo -e "${RED}Conduit failed to start. Check logs: docker logs conduit${RESET}"
        fi
    else
        echo -e "${RED}Container not found. Run installation script first.${RESET}"
    fi
}

#-------------------------------------------------------------------------------
# Stop Container
#-------------------------------------------------------------------------------

stop_container() {
    check_root "stop"
    
    echo -e "${CYAN}Stopping Conduit...${RESET}"
    if docker stop conduit 2>/dev/null; then
        echo -e "${GREEN}Conduit stopped${RESET}"
    else
        echo -e "${YELLOW}Conduit was not running${RESET}"
    fi
}

#-------------------------------------------------------------------------------
# Restart Container
#-------------------------------------------------------------------------------

restart_container() {
    check_root "restart"
    
    echo -e "${CYAN}Restarting Conduit...${RESET}"
    docker restart conduit 2>/dev/null
    sleep 2
    
    if docker ps --filter "name=conduit" --filter "status=running" --format '{{.Names}}' | grep -q "^conduit$"; then
        echo -e "${GREEN}Conduit restarted successfully${RESET}"
    else
        echo -e "${RED}Conduit failed to start. Check logs: docker logs conduit${RESET}"
    fi
}

#-------------------------------------------------------------------------------
# Show Help
#-------------------------------------------------------------------------------

show_help() {
    echo ""
    echo -e "${BOLD}${CYAN}Conduit - Psiphon Relay Node${RESET}"
    echo ""
    echo "Usage: conduit <command>"
    echo ""
    echo -e "${BOLD}Monitoring Commands:${RESET}"
    echo "  status       Show container status and latest statistics"
    echo "  logs         Follow live statistics (Ctrl+C to exit)"
    echo "  peers        Live country monitoring (requires root)"
    echo ""
    echo -e "${BOLD}Container Commands:${RESET}"
    echo "  start        Start the Conduit container"
    echo "  stop         Stop the Conduit container"
    echo "  restart      Restart the Conduit container"
    echo ""
    echo -e "${BOLD}Examples:${RESET}"
    echo "  conduit status          # Check if running and show stats"
    echo "  conduit logs            # Watch live connection statistics"
    echo "  sudo conduit peers      # Monitor connections by country"
    echo ""
    echo -e "${DIM}Thank you for supporting internet freedom!${RESET}"
    echo ""
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

case "${1:-help}" in
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    peers)
        check_root "peers"
        show_peers
        ;;
    start)
        start_container
        ;;
    stop)
        stop_container
        ;;
    restart)
        restart_container
        ;;
    help|-h|--help|*)
        show_help
        ;;
esac
