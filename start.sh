#!/bin/bash
#===============================================================================
# Vany - Unified VPN Protocol Setup
# https://github.com/behnamkhorsandian/Vanyshsh
#
# Usage:
#   curl vany.sh | sudo bash              # Interactive menu
#   curl vany.sh/reality | sudo bash      # Jump to specific protocol
#
# All-in-one: install, manage, and remove VPN protocols on your VM.
#===============================================================================

# Note: Not using 'set -e' to allow interactive reads to work when piped

#-------------------------------------------------------------------------------
# Argument Parsing
#-------------------------------------------------------------------------------

REQUESTED_PROTOCOL="${VANY_PROTOCOL:-}"
DO_UPDATE=0

for arg in "$@"; do
    case "$arg" in
        --protocol=*)
            REQUESTED_PROTOCOL="${arg#*=}"
            ;;
        --update)
            DO_UPDATE=1
            ;;
    esac
done

#-------------------------------------------------------------------------------
# Download Libraries & TUI
#-------------------------------------------------------------------------------

LIB_DIR="/tmp/vany-lib"
TUI_DL_DIR="/tmp/vany-tui"
GITHUB_RAW="https://raw.githubusercontent.com/behnamkhorsandian/Vanyshsh/main"

download_libs() {
    mkdir -p "$LIB_DIR"

    local libs="common.sh cloud.sh bootstrap.sh xray.sh selector.sh"
    for lib in $libs; do
        if ! curl -sfL "$GITHUB_RAW/lib/$lib" -o "$LIB_DIR/$lib" 2>/dev/null; then
            echo "ERROR: Failed to download $lib"
            exit 1
        fi
    done

    # Source libraries
    for lib in $libs; do
        # shellcheck source=/dev/null
        . "$LIB_DIR/$lib"
    done
}

download_tui() {
    mkdir -p "$TUI_DL_DIR/pages"
    mkdir -p "$TUI_DL_DIR/content/docs"

    local tui_files=(
        "tui/theme.sh"
        "tui/engine.sh"
        "tui/main.sh"
        "tui/pages/main.sh"
        "tui/pages/protocol.sh"
        "tui/pages/install_wizard.sh"
        "tui/pages/users.sh"
        "tui/pages/status.sh"
        "tui/pages/help.sh"
        "tui/content/protocols.json"
        "tui/content/icons.json"
    )

    for f in "${tui_files[@]}"; do
        local basename="${f#tui/}"
        local dest="$TUI_DL_DIR/$basename"
        if ! curl -sfL "$GITHUB_RAW/$f" -o "$dest" 2>/dev/null; then
            echo "ERROR: Failed to download $f"
            return 1
        fi
    done

    # Download banners
    mkdir -p "$TUI_DL_DIR/banners"
    for banner in logo menu setup reality ws wireguard dnstt mtp conduit sos lionsun; do
        curl -sfL "$GITHUB_RAW/banners/${banner}.txt" -o "$TUI_DL_DIR/banners/${banner}.txt" 2>/dev/null || true
    done

    # Download protocol doc files
    for doc in reality wg ws mtp dnstt conduit vray sos; do
        curl -sfL "$GITHUB_RAW/tui/content/docs/${doc}.txt" -o "$TUI_DL_DIR/content/docs/${doc}.txt" 2>/dev/null || true
    done

    return 0
}

# Download a service function library
download_service_functions() {
    local service="$1"
    local dest="$LIB_DIR/svc-${service}.sh"

    if [[ ! -f "$dest" ]]; then
        if ! curl -sfL "$GITHUB_RAW/services/${service}/functions.sh" -o "$dest" 2>/dev/null; then
            echo "ERROR: Failed to download ${service} functions"
            return 1
        fi
    fi

    # shellcheck source=/dev/null
    . "$dest"
}

#-------------------------------------------------------------------------------
# Update
#-------------------------------------------------------------------------------

do_update() {
    echo "  Updating Vany..."

    # Re-download libs to /opt/vany/lib/
    local permanent_lib="/opt/vany/lib"
    mkdir -p "$permanent_lib"

    for lib in common.sh cloud.sh bootstrap.sh xray.sh selector.sh; do
        echo "  Updating $lib"
        curl -sfL "$GITHUB_RAW/lib/$lib" -o "$permanent_lib/$lib" 2>/dev/null || \
            echo "  Warning: Failed to update $lib"
    done

    # Update CLI
    echo "  Updating CLI"
    curl -sfL "$GITHUB_RAW/cli/vany.sh" -o /usr/local/bin/vany 2>/dev/null && \
        chmod +x /usr/local/bin/vany || echo "  Warning: Failed to update CLI"

    # Update banners
    mkdir -p "/opt/vany/banners"
    for banner in logo menu setup reality ws wireguard dnstt mtp conduit sos lionsun; do
        curl -sfL "$GITHUB_RAW/banners/${banner}.txt" -o "/opt/vany/banners/${banner}.txt" 2>/dev/null || true
    done

    echo "  Vany updated to latest version"
    echo ""
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    # Check root
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This script must be run as root or with sudo"
        echo "Usage: curl vany.sh | sudo bash"
        exit 1
    fi

    # Download libraries
    download_libs

    # lib/bootstrap.sh enables set -e which kills TUI's (( )) && patterns
    set +e

    # Handle --update flag
    if [[ $DO_UPDATE -eq 1 ]]; then
        do_update
        exit 0
    fi

    # Download TUI
    echo "  Loading Vany..."

    if download_tui; then
        # Set TUI_DIR so modules find each other
        export TUI_DIR="$TUI_DL_DIR"
        export BANNER_DIR="$TUI_DL_DIR/banners"

        # Source the TUI entry point (it sources everything else)
        # shellcheck source=/dev/null
        . "$TUI_DL_DIR/main.sh"

        # Build TUI arguments
        local tui_args=()
        if [[ -n "$REQUESTED_PROTOCOL" ]]; then
            tui_args+=(--page "$REQUESTED_PROTOCOL")
        fi

        # Hand off to TUI main
        vany_tui_main "${tui_args[@]}"
    else
        echo "ERROR: Failed to download TUI. Check your internet connection."
        exit 1
    fi
}

main "$@"
