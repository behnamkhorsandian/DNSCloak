#!/bin/bash
#===============================================================================
# DNSCloak - Conduit Installer
# Usage: curl -sSL conduit.dnscloak.net | sudo bash
#===============================================================================

set -e

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
    read -p "  Enter value: " max_clients < /dev/tty
    MAX_CLIENTS=${max_clients:-1000}
    
    echo ""
    
    # Bandwidth
    echo -e "${CYAN}Bandwidth limit:${NC} (Mbps, -1 for unlimited, default: -1)"
    read -p "  Enter value: " bandwidth < /dev/tty
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
        --network host \
        --restart unless-stopped \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        -v conduit-data:/home/conduit/data \
        "$CONDUIT_IMAGE" \
        start --data-dir /home/conduit/data -m "$MAX_CLIENTS" -b "$BANDWIDTH" -vv --stats-file
    
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
# Main
#-------------------------------------------------------------------------------

main() {
    echo ""
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${NC}          ${BOLD}CONDUIT - PSIPHON VOLUNTEER RELAY${NC}                      ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    check_root
    
    # Check if already installed
    if docker ps -a 2>/dev/null | grep -q conduit; then
        log_warn "Conduit already installed"
        echo ""
        echo "  1) Reinstall"
        echo "  2) Open CLI (conduit)"
        echo "  0) Exit"
        echo ""
        read -p "  Choice: " choice < /dev/tty
        case $choice in
            1) docker rm -f conduit 2>/dev/null || true ;;
            2) exec conduit ;;
            *) exit 0 ;;
        esac
    fi
    
    install_docker
    install_deps
    get_settings
    run_conduit
    install_cli
    show_complete
}

main "$@"
