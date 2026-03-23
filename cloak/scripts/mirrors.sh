#!/bin/bash
#===============================================================================
# Cloak Mirrors — Fallback Access Methods
# Shows all ways to reach vany.sh when the primary domain is blocked
#
# Usage:
#   cloak mirrors              Show all access methods
#   cloak mirrors --test       Test which methods work from your network
#   cloak mirrors --rescue     Auto-try every method until one works
#===============================================================================

set -e

G='\033[38;5;36m'
LG='\033[38;5;115m'
D='\033[2m'
B='\033[1m'
R='\033[0m'
RED='\033[38;5;130m'
Y='\033[38;5;186m'
C='\033[38;5;73m'

DOH_URLS=(
    "https://1.1.1.1/dns-query"
    "https://8.8.8.8/resolve"
    "https://9.9.9.9:5053/dns-query"
)

CF_IPS=("104.16.0.1" "104.17.0.1" "172.67.0.1")

#-------------------------------------------------------------------------------
# Show all methods
#-------------------------------------------------------------------------------

show_methods() {
    echo ""
    echo -e "  ${G}${B}Vany Access Methods${R}"
    echo -e "  ${D}Ways to reach vany.sh when the primary domain is blocked${R}"
    echo ""
    echo -e "  ${B}1. Direct${R}"
    echo -e "     ${LG}curl vany.sh | sudo bash${R}"
    echo -e "     ${D}Works unless domain is blocked${R}"
    echo ""
    echo -e "  ${B}2. DoH Bypass${R} ${D}(DNS-over-HTTPS)${R}"
    echo -e "     ${LG}curl --doh-url https://1.1.1.1/dns-query vany.sh | sudo bash${R}"
    echo -e "     ${D}Bypasses DNS poisoning (curl 7.62+)${R}"
    echo ""
    echo -e "  ${B}3. Cloudflare Pages${R} ${D}(shared *.pages.dev domain)${R}"
    echo -e "     ${LG}curl vany-agg.pages.dev | sudo bash${R}"
    echo -e "     ${D}Very hard to block — shared domain${R}"
    echo ""
    echo -e "  ${B}4. GitHub Raw${R} ${D}(different CDN)${R}"
    echo -e "     ${LG}curl -sL https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/start.sh | sudo bash${R}"
    echo -e "     ${D}Different CDN, different IPs${R}"
    echo ""
    echo -e "  ${B}5. Cloudflare WARP${R} ${D}(1.1.1.1 app)${R}"
    echo -e "     ${D}Install the 1.1.1.1 app, enable, then curl vany.sh works${R}"
    echo -e "     ${C}iOS:${R}     ${D}https://apps.apple.com/app/1-1-1-1-faster-internet/id1423538627${R}"
    echo -e "     ${C}Android:${R} ${D}https://play.google.com/store/apps/details?id=com.cloudflare.onedotonedotonedotone${R}"
    echo -e "     ${C}Desktop:${R} ${D}https://1.1.1.1/${R}"
    echo -e "     ${C}Linux:${R}   ${D}https://pkg.cloudflareclient.com/${R}"
    echo ""
    echo -e "  ${B}6. Offline / Cloak${R}"
    echo -e "     ${D}You already have Cloak installed. All tools work offline.${R}"
    echo -e "     ${D}Share the installer with others who need it.${R}"
    echo ""
    echo -e "  ${D}Rescue (auto-tries all methods):${R}"
    echo -e "  ${LG}cloak mirrors --rescue${R}"
    echo ""
}

#-------------------------------------------------------------------------------
# Test methods
#-------------------------------------------------------------------------------

test_method() {
    local name="$1" url="$2"
    printf "  %-22s" "$name"
    if curl -sf -m 5 -o /dev/null "$url" 2>/dev/null; then
        echo -e "${G}OK${R}"
        return 0
    else
        echo -e "${RED}BLOCKED${R}"
        return 1
    fi
}

test_methods() {
    echo ""
    echo -e "  ${G}${B}Testing Access Methods${R}"
    echo -e "  ${D}Checking which methods work from your network...${R}"
    echo ""

    local working=0

    test_method "Direct" "https://vany.sh/health" && ((working++)) || true
    test_method "CF Pages" "https://vany-agg.pages.dev/" && ((working++)) || true
    test_method "GitHub Raw" "https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/start.sh" && ((working++)) || true

    # DoH test
    printf "  %-22s" "DoH (1.1.1.1)"
    local ip
    ip=$(curl -sf -m 5 -H "accept: application/dns-json" "https://1.1.1.1/dns-query?name=vany.sh&type=A" 2>/dev/null \
        | grep -oE '"data":"[0-9.]+"' | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
    if [[ -n "$ip" ]]; then
        echo -e "${G}OK${R} ${D}(resolved to $ip)${R}"
        ((working++))
    else
        echo -e "${RED}BLOCKED${R}"
    fi

    echo ""
    if [[ $working -gt 0 ]]; then
        echo -e "  ${G}$working method(s) available${R}"
    else
        echo -e "  ${RED}No methods work. Install Cloudflare WARP (1.1.1.1 app).${R}"
    fi
    echo ""
}

#-------------------------------------------------------------------------------
# Rescue mode — auto-try every method
#-------------------------------------------------------------------------------

rescue() {
    echo ""
    echo -e "  ${Y}${B}Rescue Mode${R}"
    echo -e "  ${D}Auto-trying every access method...${R}"
    echo ""

    # Method 1: Direct
    echo -e "  ${D}Trying direct...${R}"
    if curl -sf -m 5 -o /dev/null https://vany.sh/health 2>/dev/null; then
        echo -e "  ${G}Direct works!${R}"
        exec bash <(curl -sSf https://vany.sh 2>/dev/null)
    fi

    # Method 2: DoH
    echo -e "  ${D}Trying DoH...${R}"
    for doh in "${DOH_URLS[@]}"; do
        local ip
        ip=$(curl -sf -m 5 -H "accept: application/dns-json" "${doh}?name=vany.sh&type=A" 2>/dev/null \
            | grep -oE '"data":"[0-9.]+"' | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
        if [[ -n "$ip" ]]; then
            if curl -sf -m 5 -o /dev/null --resolve "vany.sh:443:$ip" https://vany.sh/health 2>/dev/null; then
                echo -e "  ${G}DoH resolved to $ip${R}"
                exec bash <(curl -sSf --resolve "vany.sh:443:$ip" https://vany.sh 2>/dev/null)
            fi
        fi
    done

    # Method 3: CF IPs
    echo -e "  ${D}Trying Cloudflare IPs...${R}"
    for cfip in "${CF_IPS[@]}"; do
        if curl -sf -m 5 -o /dev/null --resolve "vany.sh:443:$cfip" https://vany.sh/health 2>/dev/null; then
            echo -e "  ${G}CF IP $cfip works${R}"
            exec bash <(curl -sSf --resolve "vany.sh:443:$cfip" https://vany.sh 2>/dev/null)
        fi
    done

    # Method 4: CF Pages
    echo -e "  ${D}Trying Cloudflare Pages...${R}"
    if curl -sf -m 5 -o /dev/null https://vany-agg.pages.dev/ 2>/dev/null; then
        echo -e "  ${G}Pages mirror works!${R}"
        exec bash <(curl -sSf https://vany-agg.pages.dev/ 2>/dev/null)
    fi

    # Method 5: GitHub
    echo -e "  ${D}Trying GitHub...${R}"
    if curl -sf -m 5 -o /dev/null https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/start.sh 2>/dev/null; then
        echo -e "  ${G}GitHub works!${R}"
        exec bash <(curl -sSf https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/start.sh 2>/dev/null)
    fi

    echo ""
    echo -e "  ${RED}All methods failed.${R}"
    echo -e "  ${D}Install Cloudflare WARP (1.1.1.1 app), then run:${R}"
    echo -e "  ${LG}curl vany.sh | sudo bash${R}"
    echo ""
    exit 1
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

case "${1:-}" in
    --test|-t)    test_methods ;;
    --rescue|-r)  rescue ;;
    *)            show_methods ;;
esac
