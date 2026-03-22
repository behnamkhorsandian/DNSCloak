#!/bin/bash
#===============================================================================
# Vany - Install Tor Bridge (obfs4) Docker container
#===============================================================================

set -e

VANY_DIR="/opt/vany"
STATE_FILE="$VANY_DIR/state.json"
DOCKER_DIR="$VANY_DIR/docker/tor-bridge"

source "$(dirname "$0")/../scripts/docker-bootstrap.sh" 2>/dev/null || true

install_tor_bridge() {
    local or_port="${TOR_OR_PORT:-9001}"
    local contact="${TOR_CONTACT:-}"

    echo "  Installing Tor Bridge container..."

    mkdir -p "$VANY_DIR/tor-bridge"

    # Create torrc
    cat > "$VANY_DIR/tor-bridge/torrc" <<EOF
BridgeRelay 1
ORPort ${or_port}
ServerTransportPlugin obfs4 exec /usr/bin/obfs4proxy
ServerTransportListenAddr obfs4 0.0.0.0:${or_port}
ExtORPort auto
${contact:+ContactInfo ${contact}}
Nickname VanyBridge
DataDirectory /var/lib/tor
Log notice stdout
EOF

    docker compose -f "$DOCKER_DIR/docker-compose.yml" up -d --build

    # Open firewall port
    if command -v ufw &>/dev/null; then
        ufw allow "$or_port/tcp" 2>/dev/null || true
    fi

    # Update state
    jq --arg port "$or_port" \
        '.protocols["tor-bridge"] = {"status": "running", "container": "vany-tor-bridge", "ports": [$port + "/tcp"]}' \
        "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

    echo "  Tor Bridge container started on port $or_port"
    echo "  Bridge line will appear in logs after bootstrapping (~30s)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_tor_bridge
fi
