#!/bin/bash
#===============================================================================
# DNSCloak - Conduit Installer
# Usage: curl -sSL conduit.dnscloak.net | sudo bash
#===============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Config
CONDUIT_IMAGE="ghcr.io/ssmirr/conduit/conduit:latest"
INSTALL_DIR="/opt/conduit"

# Reopen stdin from tty for interactive input when piped
exec 3</dev/tty 2>/dev/null || exec 3<&0

#-------------------------------------------------------------------------------
# Helpers
#-------------------------------------------------------------------------------

log_info() { echo -e "${CYAN}[*]${NC} $1"; }
log_ok() { echo -e "${GREEN}[✓]${NC} $1"; }
log_err() { echo -e "${RED}[✗]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_err "Run as root: sudo bash $0"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Install Docker if needed
#-------------------------------------------------------------------------------

install_docker() {
    if command -v docker &>/dev/null; then
        log_ok "Docker already installed"
        return 0
    fi
    
    log_info "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    log_ok "Docker installed"
}

#-------------------------------------------------------------------------------
# Install monitoring dependencies
#-------------------------------------------------------------------------------

install_deps() {
    log_info "Installing dependencies..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq tcpdump geoip-bin geoip-database >/dev/null 2>&1 || true
    log_ok "Dependencies installed"
}

#-------------------------------------------------------------------------------
# Get user settings
#-------------------------------------------------------------------------------

get_settings() {
    echo ""
    echo -e "${BOLD}Conduit Configuration${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Max clients
    echo -e "${CYAN}Max clients:${NC} (default: 1000, recommended: 200-1000)"
    echo -n "  Enter value: "
    read max_clients <&3 || max_clients=""
    MAX_CLIENTS=${max_clients:-1000}
    
    echo ""
    
    # Bandwidth
    echo -e "${CYAN}Bandwidth limit:${NC} (Mbps, -1 for unlimited, default: -1)"
    echo -n "  Enter value: "
    read bandwidth <&3 || bandwidth=""
    BANDWIDTH=${bandwidth:--1}
    
    echo ""
    echo -e "Settings: max-clients=${GREEN}${MAX_CLIENTS}${NC}, bandwidth=${GREEN}${BANDWIDTH}${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# Run Conduit container
#-------------------------------------------------------------------------------

run_conduit() {
    log_info "Pulling Conduit image..."
    docker pull "$CONDUIT_IMAGE"
    
    # Remove old container if exists
    docker rm -f conduit 2>/dev/null || true
    
    # Create volume and fix permissions
    docker volume create conduit-data 2>/dev/null || true
    docker run --rm -v conduit-data:/home/conduit/data alpine \
        sh -c "chown -R 1000:1000 /home/conduit/data" 2>/dev/null || true
    
    log_info "Starting Conduit container..."
    docker run -d \
        --name conduit \
        --restart unless-stopped \
        --log-opt max-size=15m \
        --log-opt max-file=3 \
        -v conduit-data:/home/conduit/data \
        --network host \
        "$CONDUIT_IMAGE" \
        start --max-clients "$MAX_CLIENTS" --bandwidth "$BANDWIDTH" --stats-file
    
    sleep 3
    
    if docker ps | grep -q conduit; then
        log_ok "Conduit is running"
    else
        log_err "Failed to start. Check: docker logs conduit"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Install CLI script
#-------------------------------------------------------------------------------

install_cli() {
    log_info "Installing CLI..."
    mkdir -p "$INSTALL_DIR"
    
    # Save settings
    cat > "$INSTALL_DIR/settings.conf" <<EOF
MAX_CLIENTS=$MAX_CLIENTS
BANDWIDTH=$BANDWIDTH
EOF
    
    # Download monitoring script
    curl -sL "https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main/services/conduit/monitoring-script.sh" \
        -o /usr/local/bin/conduit
    chmod +x /usr/local/bin/conduit
    
    log_ok "CLI installed: conduit"
}

#-------------------------------------------------------------------------------
# Show completion message
#-------------------------------------------------------------------------------

show_complete() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Conduit installed successfully!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Commands:"
    echo "    conduit status    - Show status"
    echo "    conduit logs      - Live connection stats"
    echo "    conduit peers     - See connected countries"
    echo "    conduit restart   - Restart container"
    echo "    conduit uninstall - Remove everything"
    echo ""
    echo -e "  ${CYAN}Thank you for helping users in censored regions!${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# Show menu for already installed
#-------------------------------------------------------------------------------

show_menu() {
    while true; do
        clear
        echo ""
        echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${CYAN}║${NC}          ${BOLD}CONDUIT - PSIPHON VOLUNTEER RELAY${NC}                      ${BOLD}${CYAN}║${NC}"
        echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # Show status
        if docker ps 2>/dev/null | grep -q conduit; then
            echo -e "  Status: ${GREEN}● Running${NC}"
        else
            echo -e "  Status: ${RED}○ Stopped${NC}"
        fi
        
        # Show settings
        if [[ -f "$INSTALL_DIR/settings.conf" ]]; then
            source "$INSTALL_DIR/settings.conf"
            echo -e "  Max Clients: ${CYAN}${MAX_CLIENTS:-1000}${NC}"
            if [[ "${BANDWIDTH:--1}" == "-1" ]]; then
                echo -e "  Bandwidth: ${CYAN}Unlimited${NC}"
            else
                echo -e "  Bandwidth: ${CYAN}${BANDWIDTH} Mbps${NC}"
            fi
        fi
        
        # Show latest stats if running
        if docker ps 2>/dev/null | grep -q conduit; then
            local stats
            stats=$(docker logs --tail 100 conduit 2>&1 | grep "\[STATS\]" | tail -1)
            if [[ -n "$stats" ]]; then
                echo ""
                echo -e "  ${CYAN}$stats${NC}"
            fi
        fi
        
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "  1) View live stats"
        echo "  2) View peers by country"
        echo "  3) Start / Stop / Restart"
        echo "  4) Change settings"
        echo "  5) Update Conduit"
        echo "  6) Uninstall"
        echo "  0) Exit"
        echo ""
        echo -n "  Choice: "
        read choice <&3 || choice="0"
        
        case $choice in
            1)
                clear
                echo -e "${CYAN}═══ LIVE STATS (Ctrl+C to return) ═══${NC}"
                echo ""
                trap 'break' SIGINT
                docker logs -f --tail 20 conduit 2>&1 | grep --line-buffered "\[STATS\]" || true
                trap - SIGINT
                ;;
            2)
                # Run peers in subshell
                (
                    local local_ip
                    local_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -1)
                    
                    trap 'echo ""; return' SIGINT
                    
                    while true; do
                        declare -A countries
                        local total=0
                        
                        while read -r ip; do
                            [[ -z "$ip" ]] && continue
                            [[ "$ip" == "$local_ip" ]] && continue
                            [[ "$ip" =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|127\.) ]] && continue
                            
                            local country
                            country=$(geoiplookup "$ip" 2>/dev/null | head -1 | cut -d: -f2- | sed 's/^ *//')
                            [[ -z "$country" || "$country" == *"not found"* ]] && country="Unknown"
                            [[ "$country" == *"Iran"* ]] && country="🇮🇷 Free Iran"
                            
                            ((countries["$country"]++))
                            ((total++))
                        done < <(timeout 5 tcpdump -i any -n -l 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)
                        
                        clear
                        echo -e "${CYAN}═══ LIVE PEERS (Ctrl+C to return) ═══${NC}"
                        echo "  $(date '+%H:%M:%S') | IPs: $total"
                        echo ""
                        
                        for c in "${!countries[@]}"; do
                            printf "  %-40s %5d\n" "$c" "${countries[$c]}"
                        done | sort -t' ' -k2 -rn
                        
                        [[ ${#countries[@]} -eq 0 ]] && echo "  Waiting for connections..."
                        
                        unset countries
                        sleep 1
                    done
                ) || true
                ;;
            3)
                echo ""
                echo "  s) Start"
                echo "  t) Stop"
                echo "  r) Restart"
                echo ""
                echo -n "  Action: "
                read action <&3 || action=""
                case $action in
                    s) docker start conduit 2>/dev/null && log_ok "Started" || log_err "Failed" ;;
                    t) docker stop conduit 2>/dev/null && log_ok "Stopped" ;;
                    r) docker restart conduit 2>/dev/null && log_ok "Restarted" || log_err "Failed" ;;
                esac
                sleep 2
                ;;
            4)
                get_settings
                log_info "Recreating container with new settings..."
                docker rm -f conduit 2>/dev/null || true
                run_conduit
                # Update settings file
                cat > "$INSTALL_DIR/settings.conf" <<EOF
MAX_CLIENTS=$MAX_CLIENTS
BANDWIDTH=$BANDWIDTH
EOF
                sleep 2
                ;;
            5)
                log_info "Updating Conduit..."
                docker pull "$CONDUIT_IMAGE"
                docker rm -f conduit 2>/dev/null || true
                [[ -f "$INSTALL_DIR/settings.conf" ]] && source "$INSTALL_DIR/settings.conf"
                MAX_CLIENTS=${MAX_CLIENTS:-1000}
                BANDWIDTH=${BANDWIDTH:--1}
                run_conduit
                # Also update CLI
                curl -sL "https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main/services/conduit/monitoring-script.sh" \
                    -o /usr/local/bin/conduit
                chmod +x /usr/local/bin/conduit
                log_ok "Updated to latest version"
                sleep 2
                ;;
            6)
                echo ""
                echo -n "  Remove Conduit completely? (y/N): "
                read confirm <&3 || confirm=""
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    docker stop conduit 2>/dev/null || true
                    docker rm conduit 2>/dev/null || true
                    echo -n "  Remove data too? (y/N): "
                    read rm_data <&3 || rm_data=""
                    [[ "$rm_data" == "y" || "$rm_data" == "Y" ]] && docker volume rm conduit-data 2>/dev/null
                    rm -rf "$INSTALL_DIR"
                    rm -f /usr/local/bin/conduit
                    log_ok "Uninstalled"
                    exit 0
                fi
                ;;
            0|"")
                echo ""
                echo -e "  ${CYAN}Run 'conduit' anytime to manage${NC}"
                echo ""
                exit 0
                ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    echo ""
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${NC}          ${BOLD}CONDUIT - PSIPHON VOLUNTEER RELAY${NC}                      ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    check_root
    
    # Check if already installed - show menu
    if docker ps -a 2>/dev/null | grep -q conduit; then
        show_menu
        exit 0
    fi
    
    # Fresh install
    install_docker
    install_deps
    get_settings
    run_conduit
    install_cli
    show_complete
    
    echo ""
    echo -n "  Open dashboard? (Y/n): "
    read open_dash <&3 || open_dash="y"
    if [[ "$open_dash" != "n" && "$open_dash" != "N" ]]; then
        show_menu
    fi
}

main "$@"
