#!/bin/bash
#===============================================================================
# Vany - Install Hysteria v2 Docker container
#===============================================================================

set -e

VANY_DIR="/opt/vany"
STATE_FILE="$VANY_DIR/state.json"
DOCKER_DIR="$VANY_DIR/docker/hysteria"

source "$(dirname "$0")/../scripts/docker-bootstrap.sh" 2>/dev/null || true

install_hysteria() {
    local port="${HYSTERIA_PORT:-8443}"
    local domain="${HYSTERIA_DOMAIN:-}"
    local username="${FIRST_USERNAME:-user1}"

    echo "  Installing Hysteria v2 container..."

    mkdir -p "$VANY_DIR/hysteria"

    # Generate password for auth
    local password
    password=$(openssl rand -hex 16)

    # Generate self-signed cert if no domain
    local tls_config
    if [[ -n "$domain" ]]; then
        tls_config="\"acme\": { \"domains\": [\"$domain\"], \"email\": \"admin@$domain\" }"
    else
        # Self-signed
        if [[ ! -f "$VANY_DIR/hysteria/server.key" ]]; then
            openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
                -keyout "$VANY_DIR/hysteria/server.key" \
                -out "$VANY_DIR/hysteria/server.crt" \
                -days 3650 -nodes -subj "/CN=vany"
        fi
        tls_config="\"cert\": \"/etc/hysteria/server.crt\", \"key\": \"/etc/hysteria/server.key\""
    fi

    # Generate config
    cat > "$VANY_DIR/hysteria/config.yaml" <<EOF
listen: :${port}

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: ${password}

masquerade:
  type: proxy
  proxy:
    url: https://www.google.com
    rewriteHost: true
EOF

    docker compose -f "$DOCKER_DIR/docker-compose.yml" up -d --build

    # Open firewall
    if command -v ufw &>/dev/null; then
        ufw allow "${port}/udp" 2>/dev/null || true
    fi

    # Update state
    jq --arg port "$port" --arg pw "$password" \
        '.protocols.hysteria = {"status": "running", "container": "vany-hysteria", "ports": [$port + "/udp"], "password": $pw}' \
        "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

    # Add user
    local server_ip
    server_ip=$(jq -r '.server.ip // empty' "$STATE_FILE")
    echo ""
    echo "  Hysteria v2 installed on UDP port $port"
    echo "  Password: $password"
    echo ""
    echo "  Connection: hysteria2://$password@${domain:-$server_ip}:$port/?insecure=1#vany-hysteria"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_hysteria
fi
