#!/bin/bash
#===============================================================================
# Cloak SafeBox — Encrypted Dead-Drop CLI
# Standalone version extracted from Vany Worker
#
# Usage:
#   cloak box              Interactive mode (create or open)
#   cloak box create       Create a new box
#   cloak box open <ID>    Open existing box
#   cloak box <ID>         Shorthand open (auto-detects 8-char ID)
#===============================================================================

set -e

G='\033[0;32m'; P='\033[0;35m'; D='\033[2m'; B='\033[1m'; R='\033[0m'
Y='\033[0;33m'; RED='\033[0;31m'; C='\033[38;5;73m'

BASE="https://vany.sh"

die() { echo -e "  ${RED}$*${R}" >&2; exit 1; }

#-------------------------------------------------------------------------------
# Network check
#-------------------------------------------------------------------------------

check_online() {
    if ! curl -s --max-time 3 -o /dev/null "$BASE/health" 2>/dev/null; then
        echo ""
        echo -e "  ${RED}${B}Offline${R}"
        echo -e "  ${D}SafeBox requires an internet connection to vany.sh${R}"
        echo -e "  ${D}The server stores encrypted boxes in Cloudflare KV.${R}"
        echo ""
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Create box
#-------------------------------------------------------------------------------

do_create() {
    check_online
    echo ""
    read -rsp "  Password: " pass < /dev/tty; echo ""
    [[ -z "$pass" ]] && die "Password required."
    echo -e "  ${D}Message (Ctrl-D when done):${R}"
    msg=$(cat < /dev/tty)
    [[ -z "$msg" ]] && { echo ""; die "Message required."; }
    echo ""
    echo -e "  ${D}Encrypting...${R}"
    if command -v jq &>/dev/null; then
        json=$(jq -n --arg p "$pass" --arg m "$msg" '{plaintext:$m,password:$p}')
    elif command -v python3 &>/dev/null; then
        json=$(printf '%s' "$msg" | python3 -c "import json,sys;print(json.dumps({'plaintext':sys.stdin.read(),'password':sys.argv[1]}))" "$pass")
    else
        die "jq or python3 required for JSON encoding."
    fi
    resp=$(curl -s -w '\n%{http_code}' -X POST "$BASE/box" -H "Content-Type: application/json" -d "$json")
    code=$(echo "$resp" | tail -1)
    body=$(echo "$resp" | sed '$d')
    if [[ "$code" != "200" ]]; then
        err=$(echo "$body" | grep -o '"error":"[^"]*"' | head -1 | cut -d'"' -f4)
        die "${err:-Request failed ($code)}"
    fi
    box_id=$(echo "$body" | grep -o '"box_id":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo ""
    echo -e "  ${G}${B}Box created!${R}"
    echo ""
    echo -e "  Box ID:   ${P}${B}${box_id}${R}"
    echo -e "  Expires:  ${Y}24 hours${R}"
    echo ""
    echo -e "  ${D}Retrieve:${R}"
    echo "  curl -s \"${BASE}/box/${box_id}?pass=YOUR_PASSWORD\""
    echo -e "  ${D}Or:${R} ${C}cloak box ${box_id}${R}"
    echo ""
}

#-------------------------------------------------------------------------------
# Open box
#-------------------------------------------------------------------------------

do_open() {
    local box_id="${1:-}"

    check_online
    echo ""

    if [[ -z "$box_id" ]]; then
        read -rp "  Box ID: " box_id < /dev/tty
    fi

    box_id=$(echo "$box_id" | tr '[:lower:]' '[:upper:]')
    [[ ! "$box_id" =~ ^[A-Z0-9]{8}$ ]] && die "Invalid box ID (8 chars, A-Z 0-9)."

    local pass=""
    if [[ -n "${2:-}" && "${2:-}" == "--pass" && -n "${3:-}" ]]; then
        pass="$3"
    else
        read -rsp "  Password: " pass < /dev/tty; echo ""
    fi

    [[ -z "$pass" ]] && die "Password required."
    echo ""
    echo -e "  ${D}Decrypting...${R}"
    resp=$(curl -s -w '\n%{http_code}' -G "$BASE/box/$box_id" --data-urlencode "pass=$pass")
    code=$(echo "$resp" | tail -1)
    body=$(echo "$resp" | sed '$d')
    if [[ "$code" != "200" ]]; then
        err=$(echo "$body" | grep -o '"error":"[^"]*"' | head -1 | cut -d'"' -f4)
        die "${err:-Failed (HTTP $code)}"
    fi
    echo ""
    echo -e "  ${G}${B}Content:${R}"
    echo ""
    echo "$body"
    echo ""
}

#-------------------------------------------------------------------------------
# Interactive mode
#-------------------------------------------------------------------------------

do_interactive() {
    echo ""
    echo -e "  ${P}${B}SafeBox${R} ${D}— Encrypted Dead-Drop${R}"
    echo -e "  ${D}8-char ID + password. Auto-expires in 24h.${R}"
    echo ""
    echo -e "  ${G}1${R}) Create a new box"
    echo -e "  ${G}2${R}) Open an existing box"
    echo ""
    read -rp "  Choose [1/2]: " choice < /dev/tty
    case "$choice" in
        1) do_create ;;
        2) do_open ;;
        *) die "Invalid choice." ;;
    esac
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

cmd="${1:-}"
shift 2>/dev/null || true

case "$cmd" in
    create)         do_create ;;
    open)           do_open "$@" ;;
    "")             do_interactive ;;
    *)
        # If it looks like a box ID, treat as shorthand open
        if [[ "$cmd" =~ ^[A-Za-z0-9]{8}$ ]]; then
            do_open "$cmd" "$@"
        else
            echo -e "  ${D}Usage:${R}"
            echo "    cloak box              Interactive mode"
            echo "    cloak box create       Create a new box"
            echo "    cloak box open <ID>    Open existing box"
            echo "    cloak box <ID>         Shorthand open"
            exit 1
        fi
        ;;
esac
