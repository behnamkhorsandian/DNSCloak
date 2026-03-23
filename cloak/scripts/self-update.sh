#!/bin/bash
#===============================================================================
# Cloak Self-Update
# Downloads and installs the latest Cloak release from GitHub
#
# Usage:
#   cloak update                 Update to latest
#   cloak update --check         Check only, don't install
#   cloak update --force         Reinstall even if current
#===============================================================================

set -e

CLOAK_HOME="${CLOAK_HOME:-$HOME/.cloak}"
CLOAK_VERSION_FILE="$CLOAK_HOME/.version"
CLOAK_VERSION="dev"
[[ -f "$CLOAK_VERSION_FILE" ]] && CLOAK_VERSION="$(cat "$CLOAK_VERSION_FILE")"

REPO="behnamkhorsandian/Vanysh"
API_URL="https://api.github.com/repos/$REPO/releases"

G='\033[38;5;36m'
LG='\033[38;5;115m'
D='\033[2m'
B='\033[1m'
R='\033[0m'
RED='\033[38;5;130m'
Y='\033[38;5;186m'

DOH_URLS=(
    "https://1.1.1.1/dns-query"
    "https://8.8.8.8/resolve"
    "https://9.9.9.9:5053/dns-query"
)

#-------------------------------------------------------------------------------
# Platform detection
#-------------------------------------------------------------------------------

detect_platform() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"

    case "$os" in
        linux)  os="linux" ;;
        darwin) os="darwin" ;;
        *)      echo -e "  ${RED}Unsupported OS: $os${R}"; exit 1 ;;
    esac

    case "$arch" in
        x86_64|amd64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)             echo -e "  ${RED}Unsupported arch: $arch${R}"; exit 1 ;;
    esac

    echo "${os}-${arch}"
}

#-------------------------------------------------------------------------------
# Fetch with DoH fallback
#-------------------------------------------------------------------------------

fetch() {
    local url="$1"
    local result

    # Try direct
    result=$(curl -sf --max-time 10 "$url" 2>/dev/null) && { echo "$result"; return 0; }

    # Try DoH
    for doh in "${DOH_URLS[@]}"; do
        result=$(curl -sf --max-time 10 --doh-url "$doh" "$url" 2>/dev/null) && { echo "$result"; return 0; }
    done

    return 1
}

download() {
    local url="$1" dest="$2"

    # Try direct
    curl -sfL --max-time 120 -o "$dest" "$url" 2>/dev/null && return 0

    # Try DoH
    for doh in "${DOH_URLS[@]}"; do
        curl -sfL --max-time 120 --doh-url "$doh" -o "$dest" "$url" 2>/dev/null && return 0
    done

    return 1
}

#-------------------------------------------------------------------------------
# Get latest release info
#-------------------------------------------------------------------------------

get_latest_version() {
    local resp
    resp=$(fetch "$API_URL?per_page=10") || { echo ""; return 1; }

    # Find latest cloak-v* tag
    echo "$resp" | grep -o '"tag_name":"cloak-v[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/^cloak-v//'
}

get_download_url() {
    local version="$1" platform="$2"
    local tag="cloak-v${version}"
    local asset_name="cloak-${platform}.sh"
    [[ "$platform" == *"windows"* ]] && asset_name="cloak-${platform}.zip"

    local resp
    resp=$(fetch "$API_URL/tags/$tag") || return 1

    echo "$resp" | grep -o '"browser_download_url":"[^"]*'"$asset_name"'"' | head -1 | cut -d'"' -f4
}

#-------------------------------------------------------------------------------
# Check for update
#-------------------------------------------------------------------------------

check_only() {
    echo ""
    echo -e "  ${G}${B}Cloak Update Check${R}"
    echo -e "  ${D}Current: v${CLOAK_VERSION}${R}"
    echo ""

    local latest
    latest=$(get_latest_version) || { echo -e "  ${RED}Cannot reach GitHub. Check your connection.${R}"; echo ""; exit 1; }

    if [[ -z "$latest" ]]; then
        echo -e "  ${RED}No Cloak releases found.${R}"
        echo ""
        exit 1
    fi

    if [[ "$latest" == "$CLOAK_VERSION" ]]; then
        echo -e "  ${G}You are on the latest version.${R}"
    else
        echo -e "  ${Y}Update available:${R} ${B}v${latest}${R}"
        echo -e "  ${D}Run:${R} ${LG}cloak update${R}"
    fi
    echo ""
}

#-------------------------------------------------------------------------------
# Do update
#-------------------------------------------------------------------------------

do_update() {
    local force="${1:-}"

    echo ""
    echo -e "  ${G}${B}Cloak Self-Update${R}"
    echo -e "  ${D}Current: v${CLOAK_VERSION}${R}"
    echo ""

    echo -e "  ${D}Checking for updates...${R}"
    local latest
    latest=$(get_latest_version) || { echo -e "  ${RED}Cannot reach GitHub. Check your connection.${R}"; echo ""; exit 1; }

    if [[ -z "$latest" ]]; then
        echo -e "  ${RED}No Cloak releases found.${R}"
        echo ""
        exit 1
    fi

    if [[ "$latest" == "$CLOAK_VERSION" && "$force" != "--force" ]]; then
        echo -e "  ${G}Already on latest version (v${CLOAK_VERSION}).${R}"
        echo ""
        rm -f "$CLOAK_HOME/.update-available"
        exit 0
    fi

    echo -e "  ${Y}Updating:${R} v${CLOAK_VERSION} → ${B}v${latest}${R}"
    echo ""

    local platform
    platform=$(detect_platform)
    echo -e "  ${D}Platform: ${platform}${R}"

    local url
    url=$(get_download_url "$latest" "$platform")
    if [[ -z "$url" ]]; then
        echo -e "  ${RED}No release asset for ${platform}. Check GitHub releases.${R}"
        echo ""
        exit 1
    fi

    # Download to temp
    local tmpfile
    tmpfile=$(mktemp /tmp/cloak-update-XXXXXX)
    trap 'rm -f "$tmpfile"' EXIT

    echo -e "  ${D}Downloading...${R}"
    if ! download "$url" "$tmpfile"; then
        echo -e "  ${RED}Download failed.${R}"
        exit 1
    fi

    echo -e "  ${D}Installing...${R}"

    if [[ "$platform" == *"windows"* ]]; then
        # ZIP for Windows
        unzip -qo "$tmpfile" -d "$CLOAK_HOME"
    else
        # Self-extracting shell archive — run it in update mode
        chmod +x "$tmpfile"
        CLOAK_UPDATE=1 bash "$tmpfile" --noexec --target "$CLOAK_HOME"
    fi

    # Write version
    echo "$latest" > "$CLOAK_VERSION_FILE"
    rm -f "$CLOAK_HOME/.update-available"
    rm -f "$CLOAK_HOME/.last-update-check"

    echo ""
    echo -e "  ${G}${B}Updated to v${latest}${R}"
    echo -e "  ${D}Restart your terminal or run:${R} ${LG}cloak version${R}"
    echo ""
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

case "${1:-}" in
    --check|-c)  check_only ;;
    --force|-f)  do_update "--force" ;;
    *)           do_update ;;
esac
