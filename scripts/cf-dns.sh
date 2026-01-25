#!/bin/bash
#===============================================================================
# DNSCloak - Cloudflare DNS Manager
# Automates DNS record creation for all services
#
# Usage: ./scripts/cf-dns.sh [command] [options]
#
# Commands:
#   setup       - Create all DNS records for services
#   add         - Add a single DNS record
#   list        - List all DNS records
#   status      - Show current DNS configuration
#
# Requires: CF_API_TOKEN and CF_ZONE_ID in .env or environment
#===============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

#-------------------------------------------------------------------------------
# Load Environment
#-------------------------------------------------------------------------------

load_env() {
    if [[ -f "$ROOT_DIR/.env" ]]; then
        source "$ROOT_DIR/.env"
    fi
    
    if [[ -z "$CF_API_TOKEN" ]]; then
        echo -e "${RED}Error: CF_API_TOKEN not set${RESET}"
        echo "Add to .env file or export CF_API_TOKEN=your-token"
        exit 1
    fi
    
    if [[ -z "$CF_ZONE_ID" ]]; then
        echo -e "${RED}Error: CF_ZONE_ID not set${RESET}"
        echo "Add to .env file or export CF_ZONE_ID=your-zone-id"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Cloudflare API
#-------------------------------------------------------------------------------

CF_API="https://api.cloudflare.com/client/v4"

cf_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local args=(-s -X "$method")
    args+=(-H "Authorization: Bearer $CF_API_TOKEN")
    args+=(-H "Content-Type: application/json")
    
    if [[ -n "$data" ]]; then
        args+=(-d "$data")
    fi
    
    local response
    response=$(curl "${args[@]}" "${CF_API}${endpoint}")
    
    # Check for auth errors
    local success
    success=$(echo "$response" | jq -r '.success' 2>/dev/null)
    if [[ "$success" == "false" ]]; then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"' 2>/dev/null)
        if [[ "$error_msg" == *"Authentication"* ]]; then
            echo -e "${RED}Authentication failed. Your API token may not have DNS permissions.${RESET}" >&2
            echo "" >&2
            echo "Create a new token at: https://dash.cloudflare.com/profile/api-tokens" >&2
            echo "Use template: 'Edit zone DNS' for zone dnscloak.net" >&2
            exit 1
        fi
    fi
    
    echo "$response"
}

# Get DNS record ID by name
get_record_id() {
    local name="$1"
    local type="${2:-A}"
    
    local response
    response=$(cf_request GET "/zones/$CF_ZONE_ID/dns_records?name=$name&type=$type")
    
    echo "$response" | jq -r '.result[0].id // empty'
}

# Create or update DNS record
upsert_record() {
    local type="$1"
    local name="$2"
    local content="$3"
    local proxied="${4:-false}"
    local ttl="${5:-1}"  # 1 = auto
    
    local record_id
    record_id=$(get_record_id "$name" "$type")
    
    local data
    data=$(jq -n \
        --arg type "$type" \
        --arg name "$name" \
        --arg content "$content" \
        --argjson proxied "$proxied" \
        --argjson ttl "$ttl" \
        '{type: $type, name: $name, content: $content, proxied: $proxied, ttl: $ttl}')
    
    local response
    if [[ -n "$record_id" ]]; then
        # Update existing
        response=$(cf_request PATCH "/zones/$CF_ZONE_ID/dns_records/$record_id" "$data")
        local success=$(echo "$response" | jq -r '.success')
        if [[ "$success" == "true" ]]; then
            echo -e "  ${GREEN}✓${RESET} Updated: $name ($type) → $content"
        else
            echo -e "  ${RED}✗${RESET} Failed to update $name: $(echo "$response" | jq -r '.errors[0].message')"
            return 1
        fi
    else
        # Create new
        response=$(cf_request POST "/zones/$CF_ZONE_ID/dns_records" "$data")
        local success=$(echo "$response" | jq -r '.success')
        if [[ "$success" == "true" ]]; then
            echo -e "  ${GREEN}✓${RESET} Created: $name ($type) → $content"
        else
            echo -e "  ${RED}✗${RESET} Failed to create $name: $(echo "$response" | jq -r '.errors[0].message')"
            return 1
        fi
    fi
}

# Delete DNS record
delete_record() {
    local name="$1"
    local type="${2:-A}"
    
    local record_id
    record_id=$(get_record_id "$name" "$type")
    
    if [[ -z "$record_id" ]]; then
        echo -e "  ${YELLOW}⚠${RESET} Record not found: $name ($type)"
        return 0
    fi
    
    local response
    response=$(cf_request DELETE "/zones/$CF_ZONE_ID/dns_records/$record_id")
    local success=$(echo "$response" | jq -r '.success')
    
    if [[ "$success" == "true" ]]; then
        echo -e "  ${GREEN}✓${RESET} Deleted: $name ($type)"
    else
        echo -e "  ${RED}✗${RESET} Failed to delete $name"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Commands
#-------------------------------------------------------------------------------

cmd_setup() {
    local server_ip="${1:-}"
    local domain="${CF_DOMAIN:-dnscloak.net}"
    
    if [[ -z "$server_ip" ]]; then
        echo -e "${CYAN}Enter your server IP:${RESET}"
        read -rp "  IP: " server_ip
    fi
    
    if [[ ! "$server_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Invalid IP address${RESET}"
        exit 1
    fi
    
    echo ""
    echo -e "${BOLD}Setting up DNS records for $domain${RESET}"
    echo -e "${CYAN}Server IP: $server_ip${RESET}"
    echo ""
    
    # Services that need A records pointing to server
    # Note: Worker routes are managed separately in Cloudflare dashboard
    
    echo -e "${BOLD}A Records (Direct to Server):${RESET}"
    
    # proxy.domain - for Reality (direct connection, no CF proxy)
    upsert_record "A" "proxy.$domain" "$server_ip" false
    
    # ws.domain - for WS+CDN (MUST be proxied through CF)
    # This is the key one for WS service!
    upsert_record "A" "ws-origin.$domain" "$server_ip" true
    
    echo ""
    echo -e "${BOLD}Notes:${RESET}"
    echo "  - Worker routes (mtp, reality, wg, etc.) serve install scripts"
    echo "  - proxy.$domain: Direct connection for Reality clients"
    echo "  - ws-origin.$domain: Proxied for WS+CDN service"
    echo ""
    echo -e "${GREEN}DNS setup complete!${RESET}"
}

cmd_add() {
    local type="$1"
    local name="$2"
    local content="$3"
    local proxied="${4:-false}"
    
    if [[ -z "$type" || -z "$name" || -z "$content" ]]; then
        echo "Usage: cf-dns.sh add <type> <name> <content> [proxied]"
        echo "Example: cf-dns.sh add A proxy.dnscloak.net 1.2.3.4 false"
        exit 1
    fi
    
    load_env
    upsert_record "$type" "$name" "$content" "$proxied"
}

cmd_list() {
    load_env
    
    echo ""
    echo -e "${BOLD}DNS Records for zone $CF_ZONE_ID${RESET}"
    echo ""
    
    local response
    response=$(cf_request GET "/zones/$CF_ZONE_ID/dns_records?per_page=100")
    
    echo "$response" | jq -r '.result[] | "\(.type)\t\(.name)\t\(.content)\t\(if .proxied then "Proxied" else "DNS only" end)"' | \
        column -t -s $'\t'
    
    echo ""
}

cmd_status() {
    load_env
    
    local domain="${CF_DOMAIN:-dnscloak.net}"
    
    echo ""
    echo -e "${BOLD}DNSCloak DNS Status${RESET}"
    echo ""
    
    # Check each service subdomain
    local subdomains=("proxy" "ws-origin" "mtp" "reality" "wg" "vray" "ws" "dnstt")
    
    for sub in "${subdomains[@]}"; do
        local fqdn="${sub}.${domain}"
        local resolved
        resolved=$(dig +short "$fqdn" A 2>/dev/null | head -1)
        
        if [[ -n "$resolved" ]]; then
            # Check if proxied (CF IPs)
            if [[ "$resolved" =~ ^(104\.|172\.|141\.) ]]; then
                echo -e "  ${GREEN}✓${RESET} $fqdn → CF Proxy"
            else
                echo -e "  ${GREEN}✓${RESET} $fqdn → $resolved"
            fi
        else
            echo -e "  ${YELLOW}○${RESET} $fqdn → (not resolved)"
        fi
    done
    
    echo ""
}

cmd_help() {
    echo "DNSCloak Cloudflare DNS Manager"
    echo ""
    echo "Usage: ./scripts/cf-dns.sh <command> [options]"
    echo ""
    echo "Commands:"
    echo "  setup [ip]     Create/update DNS records for server"
    echo "  add            Add a single DNS record"
    echo "  list           List all DNS records"
    echo "  status         Show DNS resolution status"
    echo "  help           Show this help"
    echo ""
    echo "Environment:"
    echo "  CF_API_TOKEN   Cloudflare API token (required)"
    echo "  CF_ZONE_ID     Cloudflare zone ID (required)"
    echo "  CF_DOMAIN      Domain name (default: dnscloak.net)"
    echo ""
    echo "Examples:"
    echo "  ./scripts/cf-dns.sh setup 34.185.221.241"
    echo "  ./scripts/cf-dns.sh add A myapp.dnscloak.net 1.2.3.4 true"
    echo "  ./scripts/cf-dns.sh list"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    local cmd="${1:-help}"
    shift || true
    
    case "$cmd" in
        setup)
            load_env
            cmd_setup "$@"
            ;;
        add)
            cmd_add "$@"
            ;;
        list)
            cmd_list "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            echo -e "${RED}Unknown command: $cmd${RESET}"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
