#!/bin/bash
#===============================================================================
# Vany - Install HTTP Obfuscation (WS+CDN with Host header spoofing)
# Server-side identical to WS+CDN. Difference is client config.
#===============================================================================

set -e

VANY_DIR="/opt/vany"
STATE_FILE="$VANY_DIR/state.json"

source "$(dirname "$0")/../scripts/docker-bootstrap.sh" 2>/dev/null || true

install_http_obfs() {
    local domain="${HTTP_OBFS_DOMAIN:-}"
    local username="${FIRST_USERNAME:-user1}"

    if [[ -z "$domain" ]]; then
        echo "  Error: HTTP_OBFS_DOMAIN is required"
        exit 1
    fi

    echo "  Installing HTTP Obfuscation (WS+CDN with Host spoofing)..."
    echo "  Note: Server-side is identical to WS+CDN."
    echo "  The difference is the client uses clean CDN IPs."

    # Reuse WS+CDN install (same xray inbound)
    export WS_DOMAIN="$domain"
    source "$(dirname "$0")/install-xray.sh"
    install_xray
    add_ws_inbound

    # Update state to also mark http-obfs as available
    jq --arg domain "$domain" \
        '.protocols["http-obfs"] = {"status": "running", "container": "vany-xray", "shared": "xray", "ports": ["80/tcp"], "domain": $domain}' \
        "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

    echo ""
    echo "  HTTP Obfuscation ready"
    echo "  Domain: $domain"
    echo ""
    echo "  Client setup:"
    echo "    1. Use 'cfray' tool to find clean Cloudflare IPs"
    echo "    2. Set clean IP as 'address' in VLESS config"
    echo "    3. Set '$domain' as 'Host' header"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_http_obfs
fi
