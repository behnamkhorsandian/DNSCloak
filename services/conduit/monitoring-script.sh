#!/bin/bash
#===============================================================================
# Conduit CLI - Simple monitoring and management
# Usage: conduit [status|logs|peers|start|stop|restart|uninstall]
#===============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CONDUIT_IMAGE="ghcr.io/ssmirr/conduit/conduit:latest"
INSTALL_DIR="/opt/conduit"

#-------------------------------------------------------------------------------
# Status - Show if running and latest stats
#-------------------------------------------------------------------------------

cmd_status() {
    echo ""
    echo -e "${CYAN}═══ CONDUIT STATUS ═══${NC}"
    echo ""
    
    if ! docker ps -a 2>/dev/null | grep -q conduit; then
        echo -e "  Status: ${RED}Not installed${NC}"
        echo "  Run: curl -sSL conduit.dnscloak.net | sudo bash"
        echo ""
        return 1
    fi
    
    if docker ps 2>/dev/null | grep -q conduit; then
        echo -e "  Status: ${GREEN}Running${NC}"
    else
        echo -e "  Status: ${RED}Stopped${NC}"
        echo "  Start with: sudo conduit start"
        echo ""
        return 0
    fi
    
    # Get settings
    if [[ -f "$INSTALL_DIR/settings.conf" ]]; then
        source "$INSTALL_DIR/settings.conf"
        echo "  Max Clients: ${MAX_CLIENTS:-1000}"
        if [[ "${BANDWIDTH:--1}" == "-1" ]]; then
            echo "  Bandwidth: Unlimited"
        else
            echo "  Bandwidth: ${BANDWIDTH} Mbps"
        fi
    fi
    
    echo ""
    
    # Latest stats
    local stats
    stats=$(docker logs --tail 100 conduit 2>&1 | grep "\[STATS\]" | tail -1)
    
    if [[ -n "$stats" ]]; then
        echo -e "${CYAN}Latest Stats:${NC}"
        echo "  $stats"
    else
        echo -e "${YELLOW}Waiting for stats... (may take a few minutes)${NC}"
    fi
    echo ""
}

#-------------------------------------------------------------------------------
# Logs - Follow live stats
#-------------------------------------------------------------------------------

cmd_logs() {
    if ! docker ps 2>/dev/null | grep -q conduit; then
        echo -e "${RED}Conduit is not running${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}═══ LIVE STATS (Ctrl+C to exit) ═══${NC}"
    echo ""
    
    docker logs -f --tail 20 conduit 2>&1 | grep --line-buffered "\[STATS\]"
}

#-------------------------------------------------------------------------------
# Peers - Show connected countries
#-------------------------------------------------------------------------------

cmd_peers() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Run as root: sudo conduit peers${NC}"
        exit 1
    fi
    
    if ! docker ps 2>/dev/null | grep -q conduit; then
        echo -e "${RED}Conduit is not running${NC}"
        return 1
    fi
    
    # Install deps if needed
    if ! command -v tcpdump &>/dev/null || ! command -v geoiplookup &>/dev/null; then
        echo -e "${YELLOW}Installing dependencies...${NC}"
        apt-get update -qq
        apt-get install -y -qq tcpdump geoip-bin geoip-database >/dev/null 2>&1
    fi
    
    local local_ip
    local_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -1)
    
    echo ""
    echo -e "${CYAN}═══ LIVE PEERS BY COUNTRY (Ctrl+C to exit) ═══${NC}"
    echo ""
    
    trap 'echo ""; echo "Stopped."; exit 0' SIGINT
    
    while true; do
        # Capture IPs for 5 seconds
        declare -A countries
        local total=0
        
        while read -r ip; do
            [[ -z "$ip" ]] && continue
            [[ "$ip" == "$local_ip" ]] && continue
            [[ "$ip" =~ ^10\. ]] && continue
            [[ "$ip" =~ ^192\.168\. ]] && continue
            [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && continue
            [[ "$ip" =~ ^127\. ]] && continue
            
            local country
            country=$(geoiplookup "$ip" 2>/dev/null | head -1 | cut -d: -f2- | sed 's/^[A-Z][A-Z], //' | sed 's/^ *//')
            
            [[ -z "$country" || "$country" == *"not found"* ]] && country="Unknown"
            [[ "$country" == "Iran, Islamic Republic of" ]] && country="Free Iran"
            
            ((countries["$country"]++))
            ((total++))
        done < <(timeout 5 tcpdump -i any -n -l 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)
        
        clear
        echo ""
        echo -e "${CYAN}═══ LIVE PEERS BY COUNTRY ═══${NC}"
        echo "  Updated: $(date '+%H:%M:%S') | Total IPs: $total"
        echo ""
        
        if [[ ${#countries[@]} -gt 0 ]]; then
            for c in "${!countries[@]}"; do
                printf "  %-40s %5d\n" "$c" "${countries[$c]}"
            done | sort -t' ' -k2 -rn
        else
            echo "  No connections yet..."
        fi
        
        echo ""
        echo -e "  ${CYAN}Press Ctrl+C to stop${NC}"
        
        unset countries
        sleep 1
    done
}

#-------------------------------------------------------------------------------
# Start/Stop/Restart
#-------------------------------------------------------------------------------

cmd_start() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Run as root: sudo conduit start${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Starting Conduit...${NC}"
    docker start conduit 2>/dev/null || echo -e "${RED}Container not found. Reinstall.${NC}"
    sleep 2
    docker ps | grep -q conduit && echo -e "${GREEN}Running${NC}" || echo -e "${RED}Failed${NC}"
}

cmd_stop() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Run as root: sudo conduit stop${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Stopping Conduit...${NC}"
    docker stop conduit 2>/dev/null && echo -e "${GREEN}Stopped${NC}"
}

cmd_restart() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Run as root: sudo conduit restart${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Restarting Conduit...${NC}"
    docker restart conduit 2>/dev/null
    sleep 2
    docker ps | grep -q conduit && echo -e "${GREEN}Running${NC}" || echo -e "${RED}Failed${NC}"
}

#-------------------------------------------------------------------------------
# Uninstall
#-------------------------------------------------------------------------------

cmd_uninstall() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Run as root: sudo conduit uninstall${NC}"
        exit 1
    fi
    
    echo ""
    echo -n "Remove Conduit? (y/N): "
    read confirm < /dev/tty || confirm="n"
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0
    
    echo -e "${CYAN}Removing...${NC}"
    docker stop conduit 2>/dev/null || true
    docker rm conduit 2>/dev/null || true
    
    echo -n "Remove data volume too? (y/N): "
    read rm_data < /dev/tty || rm_data="n"
    [[ "$rm_data" == "y" || "$rm_data" == "Y" ]] && docker volume rm conduit-data 2>/dev/null
    
    rm -rf "$INSTALL_DIR"
    rm -f /usr/local/bin/conduit
    
    echo -e "${GREEN}Uninstalled${NC}"
}

#-------------------------------------------------------------------------------
# Help
#-------------------------------------------------------------------------------

cmd_help() {
    echo ""
    echo -e "${BOLD}Conduit CLI${NC}"
    echo ""
    echo "Usage: conduit <command>"
    echo ""
    echo "Commands:"
    echo "  status     Show status and latest stats"
    echo "  logs       Follow live connection stats"
    echo "  peers      Show connected countries (requires root)"
    echo "  start      Start container"
    echo "  stop       Stop container"
    echo "  restart    Restart container"
    echo "  uninstall  Remove everything"
    echo ""
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

case "${1:-status}" in
    status)    cmd_status ;;
    logs)      cmd_logs ;;
    peers)     cmd_peers ;;
    start)     cmd_start ;;
    stop)      cmd_stop ;;
    restart)   cmd_restart ;;
    uninstall) cmd_uninstall ;;
    help|-h|--help) cmd_help ;;
    *) cmd_help ;;
esac
