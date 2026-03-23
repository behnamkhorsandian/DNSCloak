#!/bin/bash
#===============================================================================
# Cloak Faucet — Network Relay Node
# Relay SafeBox traffic, get a free VPN in exchange
# Standalone version extracted from Vany Worker
#
# Usage:
#   cloak faucet          Start relay node
#===============================================================================

set -e

GREEN="\033[38;5;35m"
LGREEN="\033[38;5;114m"
DIM="\033[2m"
BOLD="\033[1m"
RST="\033[0m"
RED="\033[38;5;167m"
YELLOW="\033[38;5;185m"
BLUE="\033[38;5;68m"
CYAN="\033[38;5;73m"

RELAY_URL="wss://vany.sh/faucet/relay"
NODE_ID=$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')
START_TIME=$(date +%s)
WSPID=""
VPN_LINK=""
VPN_UUID=""
FIFO=""
OUTFILE=""

cleanup() {
    echo ""
    [[ -n "$WSPID" ]] && kill "$WSPID" 2>/dev/null || true
    [[ -p "$FIFO" ]] && rm -f "$FIFO" 2>/dev/null || true
    [[ -f "$OUTFILE" ]] && rm -f "$OUTFILE" 2>/dev/null || true
    exec 3>&- 2>/dev/null || true
    ELAPSED=$(( $(date +%s) - START_TIME ))
    MINS=$(( ELAPSED / 60 ))
    SECS=$(( ELAPSED % 60 ))
    echo -e "  ${DIM}Session ended after ${MINS}m${SECS}s.${RST}"
    if [[ -n "$VPN_LINK" ]]; then
        echo -e "  ${DIM}VPN link expired. Open Faucet again to get a new one.${RST}"
    fi
    exit 0
}

trap cleanup INT TERM EXIT

# Network check
if ! curl -s --max-time 3 -o /dev/null "https://vany.sh/health" 2>/dev/null; then
    echo ""
    echo -e "  ${RED}${BOLD}Offline${RST}"
    echo -e "  ${DIM}Faucet requires an internet connection to vany.sh${RST}"
    echo -e "  ${DIM}It relays encrypted SafeBox traffic through the WebSocket mesh.${RST}"
    echo ""
    exit 1
fi

clear
echo ""
echo -e "  ${GREEN}${BOLD}VANY NETWORK FAUCET${RST}"
echo -e "  ${DIM}Relay SafeBox traffic -> get free VPN${RST}"
echo ""
echo -e "  ${DIM}Node ID:    ${RST}${LGREEN}node-${NODE_ID}${RST}"
echo -e "  ${DIM}Relay URL:  ${RST}${BLUE}${RELAY_URL}${RST}"
echo ""
echo -e "  ${DIM}You relay encrypted SafeBox packets for censored regions.${RST}"
echo -e "  ${DIM}In exchange, you get a free VPN link while Faucet is open.${RST}"
echo ""
echo -e "  ${YELLOW}Press Ctrl+C to stop.${RST}"
echo ""

# Check for websocat
if ! command -v websocat &>/dev/null; then
    echo -e "  ${RED}websocat not found.${RST}"
    echo ""
    if [[ "$(uname)" == "Darwin" ]]; then
        echo -e "    ${LGREEN}brew install websocat${RST}"
    else
        echo -e "    ${LGREEN}wget -qO /usr/local/bin/websocat https://github.com/vi/websocat/releases/latest/download/websocat.x86_64-unknown-linux-musl${RST}"
        echo -e "    ${LGREEN}chmod +x /usr/local/bin/websocat${RST}"
    fi
    echo ""
    echo -e "  ${DIM}Or open ${BLUE}https://vany.sh${RST} ${DIM}and click${RST} ${LGREEN}Faucet${RST}"
    echo ""
    exit 1
fi

echo -e "  ${DIM}Connecting...${RST}"

# Create FIFO for sending to websocat
FIFO=$(mktemp -u /tmp/vany-fc-XXXXXX)
mkfifo "$FIFO"

# Output file for receiving from websocat
OUTFILE=$(mktemp /tmp/vany-fc-out-XXXXXX)

# Start websocat in background (opens FIFO for reading)
websocat -t --ping-interval 25 "${RELAY_URL}" < "$FIFO" > "$OUTFILE" 2>/dev/null &
WSPID=$!

# Now open write end — unblocks websocat's read end
exec 3>"$FIFO"
sleep 1

# Verify connection
if ! kill -0 $WSPID 2>/dev/null; then
    echo -e "  ${RED}Connection failed.${RST}"
    exit 1
fi

# Send registration
echo '{"type":"register","node":"'"${NODE_ID}"'"}' >&3

# Wait for welcome response with VPN link
for i in 1 2 3 4 5; do
    sleep 1
    if grep -q '"link"' "$OUTFILE" 2>/dev/null; then
        break
    fi
done

VPN_LINK=$(grep -o '"link":"[^"]*"' "$OUTFILE" 2>/dev/null | head -1 | cut -d'"' -f4 || true)

echo ""
echo -e "  ${GREEN}${BOLD}CONNECTED${RST} ${DIM}-- relay active${RST}"
echo ""

if [[ -n "$VPN_LINK" ]]; then
    echo -e "  ${GREEN}-----------------------------------------------${RST}"
    echo -e "  ${GREEN}${BOLD}  FREE VPN EARNED${RST}"
    echo -e "  ${GREEN}-----------------------------------------------${RST}"
    echo ""
    echo -e "  ${DIM}Import into v2rayNG, Hiddify, or Streisand:${RST}"
    echo ""
    echo -e "  ${LGREEN}${VPN_LINK}${RST}"
    echo ""
    echo -e "  ${DIM}Or connect directly from terminal:${RST}"
    echo ""

    # Extract UUID and params from the VLESS link
    VPN_UUID=$(echo "$VPN_LINK" | sed 's|vless://||' | cut -d'@' -f1)
    VPN_HOST=$(echo "$VPN_LINK" | cut -d'@' -f2 | cut -d':' -f1)
    VPN_PATH=$(echo "$VPN_LINK" | grep -o 'path=[^&]*' | cut -d= -f2 | python3 -c "import sys,urllib.parse;print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null || echo "/ws")

    if command -v xray &>/dev/null; then
        echo -e "    ${CYAN}# xray-core (SOCKS5 on 127.0.0.1:1080):${RST}"
        echo -e "    ${DIM}xray run -c /dev/stdin <<'XCONF'${RST}"
        echo -e "    ${DIM}{\"inbounds\":[{\"port\":1080,\"protocol\":\"socks\",\"settings\":{\"udp\":true}}],\"outbounds\":[{\"protocol\":\"vless\",\"settings\":{\"vnext\":[{\"address\":\"$VPN_HOST\",\"port\":443,\"users\":[{\"id\":\"$VPN_UUID\",\"encryption\":\"none\"}]}]},\"streamSettings\":{\"network\":\"ws\",\"wsSettings\":{\"path\":\"$VPN_PATH\",\"headers\":{\"Host\":\"$VPN_HOST\"}},\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"$VPN_HOST\"}}}]}${RST}"
        echo -e "    ${DIM}XCONF${RST}"
    elif command -v sing-box &>/dev/null; then
        echo -e "    ${CYAN}# sing-box (SOCKS5 on 127.0.0.1:1080):${RST}"
        echo -e "    ${DIM}sing-box run -c /dev/stdin <<'SCONF'${RST}"
        echo -e "    ${DIM}{\"inbounds\":[{\"type\":\"socks\",\"listen\":\"127.0.0.1\",\"listen_port\":1080}],\"outbounds\":[{\"type\":\"vless\",\"server\":\"$VPN_HOST\",\"server_port\":443,\"uuid\":\"$VPN_UUID\",\"tls\":{\"enabled\":true,\"server_name\":\"$VPN_HOST\"},\"transport\":{\"type\":\"ws\",\"path\":\"$VPN_PATH\",\"headers\":{\"Host\":\"$VPN_HOST\"}}}]}${RST}"
        echo -e "    ${DIM}SCONF${RST}"
    else
        echo -e "    ${CYAN}# Install xray-core or sing-box, then:${RST}"
        echo -e "    ${DIM}export ALL_PROXY=socks5://127.0.0.1:1080${RST}"
        echo -e "    ${DIM}curl -x socks5://127.0.0.1:1080 https://ifconfig.me${RST}"
    fi

    echo ""
    echo -e "  ${DIM}VPN stays active while Faucet runs. Expires ~2 min after stop.${RST}"
    echo -e "  ${GREEN}-----------------------------------------------${RST}"
    echo ""
fi

# Heartbeat loop with live metrics
PING_COUNT=0
while kill -0 $WSPID 2>/dev/null; do
    ELAPSED=$(( $(date +%s) - START_TIME ))
    MINS=$(( ELAPSED / 60 ))
    SECS=$(( ELAPSED % 60 ))
    MSGS=$(wc -l < "$OUTFILE" 2>/dev/null | tr -d ' ' || echo 0)
    printf "\r  ${GREEN}*${RST} ${LGREEN}Relaying${RST} ${DIM}|${RST} ${CYAN}${MINS}m${SECS}s${RST} ${DIM}|${RST} ${CYAN}${MSGS}${RST} ${DIM}msgs |${RST} ${CYAN}${PING_COUNT}${RST} ${DIM}pings${RST}    "
    echo '{"type":"ping","uuid":"'"${VPN_UUID}"'"}' >&3 2>/dev/null || break
    PING_COUNT=$((PING_COUNT + 1))
    sleep 30
done

cleanup
