#!/bin/bash
#===============================================================================
# Vany - Install NoizDNS Docker container (DPI-resistant DNSTT fork)
#===============================================================================

set -e

VANY_DIR="/opt/vany"
STATE_FILE="$VANY_DIR/state.json"
DOCKER_DIR="$VANY_DIR/docker/noizdns"

source "$(dirname "$0")/../scripts/docker-bootstrap.sh" 2>/dev/null || true

install_noizdns() {
    local domain="${NOIZDNS_DOMAIN:?Domain required for NoizDNS}"

    echo "  Installing NoizDNS container..."

    # Check for port 53 conflict
    if docker ps --format '{{.Names}}' | grep -qE 'vany-dnstt|vany-slipstream'; then
        echo "  ERROR: Another DNS tunnel is running on port 53."
        echo "  Only one DNS tunnel can be active at a time."
        echo "  Stop the existing one first: docker stop vany-dnstt / vany-slipstream"
        return 1
    fi

    mkdir -p "$VANY_DIR/noizdns"

    # Generate server keypair
    if [[ ! -f "$VANY_DIR/noizdns/server.key" ]]; then
        openssl genrsa -out "$VANY_DIR/noizdns/server.key" 2048 2>/dev/null
        openssl rsa -in "$VANY_DIR/noizdns/server.key" -pubout -out "$VANY_DIR/noizdns/server.pub" 2>/dev/null
    fi

    # Write domain config
    echo "$domain" > "$VANY_DIR/noizdns/domain.conf"

    docker compose -f "$DOCKER_DIR/docker-compose.yml" up -d --build

    # Open firewall port
    if command -v ufw &>/dev/null; then
        ufw allow 53/udp 2>/dev/null || true
        ufw allow 53/tcp 2>/dev/null || true
    fi

    # Update state
    jq --arg domain "$domain" \
        '.protocols.noizdns = {"status": "running", "container": "vany-noizdns", "ports": ["53/udp"], "domain": $domain}' \
        "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

    echo "  NoizDNS container started"
    echo "  Domain: t.$domain -> NS -> ns1.$domain"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_noizdns
fi
