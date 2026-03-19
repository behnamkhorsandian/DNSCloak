#!/bin/bash
#===============================================================================
# Vany - Service Selector
# Detects domain availability and recommends appropriate services
# https://github.com/behnamkhorsandian/Vanyshsh
#===============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common if not already loaded
if [[ -z "$VANY_DIR" ]]; then
    source "$SCRIPT_DIR/common.sh"
fi

#-------------------------------------------------------------------------------
# Domain Detection
#-------------------------------------------------------------------------------

# Check if server has a domain pointing to it
# Usage: detect_domain
detect_domain() {
    local ip
    ip=$(server_get "ip")
    
    if [[ -z "$ip" ]]; then
        return 1
    fi
    
    # Try reverse DNS
    local rdns
    rdns=$(dig +short -x "$ip" 2>/dev/null | sed 's/\.$//')
    
    if [[ -n "$rdns" && "$rdns" != "$ip" ]]; then
        # Verify forward lookup matches
        local forward
        forward=$(dig +short "$rdns" 2>/dev/null | head -1)
        if [[ "$forward" == "$ip" ]]; then
            echo "$rdns"
            return 0
        fi
    fi
    
    return 1
}

# Check if domain points to this server
# Usage: verify_domain "example.com"
verify_domain() {
    local domain="$1"
    local ip
    ip=$(server_get "ip")
    
    local resolved
    resolved=$(dig +short "$domain" 2>/dev/null | head -1)
    
    [[ "$resolved" == "$ip" ]]
}

# Check if domain is behind Cloudflare
# Usage: is_cloudflare_domain "example.com"
is_cloudflare_domain() {
    local domain="$1"
    
    # Check if resolves to Cloudflare IP ranges
    local ip
    ip=$(dig +short "$domain" 2>/dev/null | head -1)
    
    if [[ -z "$ip" ]]; then
        return 1
    fi
    
    # Cloudflare IP ranges (simplified check)
    # Full list at: https://www.cloudflare.com/ips/
    case "$ip" in
        104.16.*|104.17.*|104.18.*|104.19.*|104.20.*|104.21.*|104.22.*|104.23.*|104.24.*|104.25.*|104.26.*|104.27.*) return 0 ;;
        172.64.*|172.65.*|172.66.*|172.67.*|172.68.*|172.69.*|172.70.*|172.71.*) return 0 ;;
        162.158.*|162.159.*) return 0 ;;
        198.41.*) return 0 ;;
        *) return 1 ;;
    esac
}

#-------------------------------------------------------------------------------
# Service Recommendations
#-------------------------------------------------------------------------------

# Print service recommendation based on setup
# Usage: recommend_services [has_domain] [has_cloudflare]
recommend_services() {
    local has_domain="${1:-false}"
    local has_cloudflare="${2:-false}"
    
    echo ""
    echo "Recommended Services:"
    echo "---------------------"
    echo ""
    
    # Always recommend Reality (no domain needed)
    echo "  [RECOMMENDED] Reality (vany.sh/reality)"
    echo "      Best detection resistance, no domain needed"
    echo ""
    
    # Always recommend WireGuard
    echo "  [RECOMMENDED] WireGuard (vany.sh/wg)"
    echo "      Fast VPN, native app support"
    echo ""
    
    # MTP is always available
    echo "  [AVAILABLE] MTProto (vany.sh/mtp)"
    echo "      Telegram only"
    echo ""
    
    if [[ "$has_domain" == "true" ]]; then
        echo "  [AVAILABLE] V2Ray (vany.sh/vray)"
        echo "      Classic setup with Let's Encrypt cert"
        echo ""
        
        if [[ "$has_cloudflare" == "true" ]]; then
            echo "  [AVAILABLE] WS+CDN (vany.sh/ws)"
            echo "      Hide server IP behind Cloudflare"
            echo ""
        fi
        
        echo "  [EMERGENCY] DNStt (vany.sh/dnstt)"
        echo "      DNS tunnel for blackouts (slow)"
        echo ""
    else
        echo "  [REQUIRES DOMAIN] V2Ray, WS+CDN, DNStt"
        echo "      Add a domain to enable these services"
        echo ""
    fi
}

#-------------------------------------------------------------------------------
# Interactive Service Selection
#-------------------------------------------------------------------------------

select_service() {
    print_banner
    echo -e "  ${BOLD}${WHITE}Service Selection${RESET}"
    print_line
    echo ""
    
    # Detect setup
    local domain
    domain=$(detect_domain)
    local has_domain="false"
    local has_cloudflare="false"
    
    if [[ -n "$domain" ]]; then
        has_domain="true"
        print_info "Detected domain: $domain"
        
        if is_cloudflare_domain "$domain"; then
            has_cloudflare="true"
            print_info "Domain is behind Cloudflare"
        fi
    else
        print_info "No domain detected (using IP only)"
    fi
    
    recommend_services "$has_domain" "$has_cloudflare"
    
    echo "Available Commands:"
    echo "-------------------"
    echo ""
    echo "  curl vany.sh/reality | sudo bash"
    echo "  curl vany.sh/wg | sudo bash"
    echo "  curl vany.sh/mtp | sudo bash"
    
    if [[ "$has_domain" == "true" ]]; then
        echo "  curl vany.sh/vray | sudo bash"
        if [[ "$has_cloudflare" == "true" ]]; then
            echo "  curl vany.sh/ws | sudo bash"
        fi
        echo "  curl vany.sh/dnstt | sudo bash"
    fi
    
    echo ""
}

#-------------------------------------------------------------------------------
# Quick Check Functions
#-------------------------------------------------------------------------------

# Check what services can be installed
can_install() {
    local service="$1"
    
    case "$service" in
        reality|wg|mtp)
            # Always available
            return 0
            ;;
        vray|dnstt)
            # Need domain
            local domain
            domain=$(server_get "domain")
            [[ -n "$domain" ]]
            ;;
        ws)
            # Need Cloudflare domain
            local domain
            domain=$(server_get "domain")
            [[ -n "$domain" ]] && is_cloudflare_domain "$domain"
            ;;
        *)
            return 1
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    source "$SCRIPT_DIR/common.sh"
    select_service
fi
