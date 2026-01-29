#!/bin/bash
#===============================================================================
# Conduit Monitoring Script
# Installed at /usr/local/bin/conduit
# Commands: status, logs, peers
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'
BOLD='\033[1m'

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
        apt-get install -y -qq "${missing[@]}" 2>/dev/null
    fi
}

#-------------------------------------------------------------------------------
# Show Status
#-------------------------------------------------------------------------------

show_status() {
    echo ""
    echo -e "  ${BOLD}Conduit Container Status${RESET}"
    echo "  ------------------------------------------------------------"
    echo ""
    
    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^conduit$"; then
        echo -e "  ${RED}Container not found${RESET}"
        echo "  Run installation script to set up Conduit"
        return 1
    fi
    
    # Get container status
    local status
    status=$(docker inspect -f '{{.State.Status}}' conduit 2>/dev/null)
    
    if [[ "$status" == "running" ]]; then
        echo -e "  Status:      ${GREEN}Running${RESET}"
        
        # Get uptime
        local started
        started=$(docker inspect -f '{{.State.StartedAt}}' conduit | cut -d'.' -f1)
        echo "  Started:     $started"
        
        # Get latest stats from logs
        echo ""
        echo -e "  ${CYAN}Latest Statistics:${RESET}"
        docker logs conduit 2>&1 | grep "\[STATS\]" | tail -1 || echo "  No stats available yet"
    else
        echo -e "  Status:      ${RED}${status}${RESET}"
    fi
    
    # Get configuration
    local max_clients bandwidth
    max_clients=$(docker inspect -f '{{range .Args}}{{println .}}{{end}}' conduit | grep -A1 "\-m" | tail -1)
    bandwidth=$(docker inspect -f '{{range .Args}}{{println .}}{{end}}' conduit | grep -A1 "\-b" | tail -1)
    
    echo ""
    echo -e "  ${CYAN}Configuration:${RESET}"
    echo "  Max Clients: ${max_clients:-Unknown}"
    echo "  Bandwidth:   ${bandwidth:-Unknown} Mbps"
    echo "  Data Volume: conduit-data"
    echo ""
}

#-------------------------------------------------------------------------------
# Show Live Logs
#-------------------------------------------------------------------------------

show_logs() {
    echo ""
    echo -e "${CYAN}Following Conduit statistics (Ctrl+C to exit)${RESET}"
    echo ""
    
    # Follow logs and filter for STATS lines
    docker logs -f conduit 2>&1 | grep --line-buffered "\[STATS\]"
}

#-------------------------------------------------------------------------------
# Show Live Peers (Country Monitoring)
#-------------------------------------------------------------------------------

show_peers() {
    # Install dependencies
    check_dependencies tcpdump geoiplookup
    
    # Check if geoip database exists
    if [[ ! -f /usr/share/GeoIP/GeoIP.dat ]]; then
        echo -e "${YELLOW}Installing GeoIP database...${RESET}"
        apt-get install -y -qq geoip-database 2>/dev/null
    fi
    
    echo ""
    echo -e "${CYAN}${BOLD}Live Country Monitoring${RESET}"
    echo "  Press Ctrl+C to stop"
    echo "  ------------------------------------------------------------"
    echo ""
    
    # Create temp file for capturing IPs
    local tmp_file
    tmp_file=$(mktemp)
    
    # Cleanup on exit
    trap 'rm -f "$tmp_file"' EXIT
    
    # Monitor traffic in 5-second intervals
    while true; do
        # Clear temp file
        true > "$tmp_file"
        
        # Capture traffic for 5 seconds
        timeout 5 tcpdump -n -i any -c 100 2>/dev/null | \
            grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
            grep -v "^127\." | \
            grep -v "^10\." | \
            grep -v "^172\.(1[6-9]|2[0-9]|3[0-1])\." | \
            grep -v "^192\.168\." | \
            sort -u >> "$tmp_file" 2>/dev/null || true
        
        # Process IPs and count by country
        declare -A country_count
        
        while IFS= read -r ip; do
            if [[ -n "$ip" ]]; then
                local country
                country=$(geoiplookup "$ip" 2>/dev/null | cut -d':' -f2 | sed 's/^ *//' | cut -d',' -f1)
                
                # Replace "Iran, Islamic Republic of" with "Free Iran"
                if [[ "$country" == "Iran" ]]; then
                    country="Free Iran"
                fi
                
                if [[ -n "$country" && "$country" != "IP Address not found" ]]; then
                    ((country_count["$country"]++))
                fi
            fi
        done < "$tmp_file"
        
        # Clear screen and display results
        clear
        echo ""
        echo -e "${CYAN}${BOLD}Live Country Monitoring${RESET}"
        echo "  Updated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  ------------------------------------------------------------"
        echo ""
        
        if [[ ${#country_count[@]} -gt 0 ]]; then
            # Sort by count (descending) and display
            for country in "${!country_count[@]}"; do
                printf "  %-30s : %d\n" "$country" "${country_count[$country]}"
            done | sort -t':' -k2 -rn
        else
            echo "  No peer connections detected yet..."
        fi
        
        echo ""
        echo -e "  ${CYAN}Press Ctrl+C to stop${RESET}"
        
        # Wait before next update
        sleep 5
    done
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

case "${1:-}" in
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    peers)
        show_peers
        ;;
    *)
        echo "Conduit Monitoring Script"
        echo ""
        echo "Usage: conduit <command>"
        echo ""
        echo "Commands:"
        echo "  status    Show container status and latest stats"
        echo "  logs      Follow live statistics from container logs"
        echo "  peers     Live country monitoring (requires root)"
        echo ""
        exit 1
        ;;
esac
