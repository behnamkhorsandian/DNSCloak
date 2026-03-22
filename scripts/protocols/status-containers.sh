#!/bin/bash
#===============================================================================
# Vany - Docker Container Status
# Usage: status-containers.sh [protocol]
# Returns JSON status for all or one container
#===============================================================================

VANY_DIR="/opt/vany"
STATE_FILE="$VANY_DIR/state.json"

CONTAINERS=("vany-xray" "vany-wireguard" "vany-dnstt" "vany-conduit" "vany-sos" "vany-hysteria" "vany-slipstream" "vany-noizdns" "vany-tor-bridge" "vany-snowflake")

get_container_status() {
    local name="$1"

    if ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
        echo "not_installed"
        return
    fi

    local state
    state=$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null)
    echo "${state:-unknown}"
}

get_container_stats() {
    local name="$1"

    if [[ "$(get_container_status "$name")" != "running" ]]; then
        echo '{"cpu": "-", "mem": "-", "uptime": "-"}'
        return
    fi

    local stats
    stats=$(docker stats --no-stream --format '{"cpu":"{{.CPUPerc}}","mem":"{{.MemUsage}}"}' "$name" 2>/dev/null)
    if [[ -z "$stats" ]]; then
        echo '{"cpu": "-", "mem": "-"}'
        return
    fi

    local started
    started=$(docker inspect --format '{{.State.StartedAt}}' "$name" 2>/dev/null)

    echo "$stats" | jq --arg started "$started" '. + {"started": $started}'
}

PROTO="${1:-}"

if [[ -n "$PROTO" ]]; then
    case "$PROTO" in
        xray|reality|ws|vray) NAME="vany-xray" ;;
        wireguard|wg)         NAME="vany-wireguard" ;;
        dnstt)                NAME="vany-dnstt" ;;
        conduit)              NAME="vany-conduit" ;;
        sos)                  NAME="vany-sos" ;;
        hysteria)             NAME="vany-hysteria" ;;
        http-obfs)            NAME="vany-xray" ;;
        ssh-tunnel)           NAME="--" ;;
        slipstream)           NAME="vany-slipstream" ;;
        noizdns)              NAME="vany-noizdns" ;;
        tor-bridge)           NAME="vany-tor-bridge" ;;
        snowflake)            NAME="vany-snowflake" ;;
        *)                    NAME="vany-$PROTO" ;;
    esac

    STATUS=$(get_container_status "$NAME")
    STATS=$(get_container_stats "$NAME")

    jq -n --arg name "$NAME" --arg status "$STATUS" --argjson stats "$STATS" \
        '{"container": $name, "status": $status, "stats": $stats}'
else
    # All containers
    echo "{"
    first=true
    for name in "${CONTAINERS[@]}"; do
        STATUS=$(get_container_status "$name")
        STATS=$(get_container_stats "$name")

        proto="${name#vany-}"
        [[ "$first" != "true" ]] && echo ","
        first=""

        echo "  \"$proto\": $(jq -n --arg status "$STATUS" --argjson stats "$STATS" \
            '{"status": $status, "stats": $stats}')"
    done
    echo "}"
fi
