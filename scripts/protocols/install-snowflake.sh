#!/bin/bash
#===============================================================================
# Vany - Install Snowflake Proxy Docker container
#===============================================================================

set -e

VANY_DIR="/opt/vany"
STATE_FILE="$VANY_DIR/state.json"
DOCKER_DIR="$VANY_DIR/docker/snowflake"

source "$(dirname "$0")/../scripts/docker-bootstrap.sh" 2>/dev/null || true

install_snowflake() {
    echo "  Installing Snowflake Proxy container..."

    mkdir -p "$VANY_DIR/snowflake"

    docker compose -f "$DOCKER_DIR/docker-compose.yml" up -d

    # Update state
    jq '.protocols.snowflake = {"status": "running", "container": "vany-snowflake", "ports": []}' \
        "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

    echo "  Snowflake Proxy container started"
    echo "  No port forwarding needed (uses STUN/TURN)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_snowflake
fi
