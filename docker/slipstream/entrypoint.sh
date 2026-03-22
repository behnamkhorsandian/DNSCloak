#!/bin/sh
set -e

DOMAIN="${SLIPSTREAM_DOMAIN:-t.example.com}"
FORWARD="${SLIPSTREAM_FORWARD:-127.0.0.1:10800}"

echo "Starting Slipstream server..."
echo "  Domain: $DOMAIN"
echo "  Forward: $FORWARD"

exec slipstream-server \
    -domain "$DOMAIN" \
    -forward "$FORWARD" \
    -key /etc/slipstream/server.key
