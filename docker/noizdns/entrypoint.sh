#!/bin/sh
set -e

DOMAIN="${NOIZDNS_DOMAIN:-t.example.com}"
FORWARD="${NOIZDNS_FORWARD:-127.0.0.1:10800}"

echo "Starting NoizDNS server..."
echo "  Domain: $DOMAIN"
echo "  Forward: $FORWARD"

exec noizdns-server \
    -domain "$DOMAIN" \
    -forward "$FORWARD" \
    -key /etc/noizdns/server.key
