#!/bin/bash
#===============================================================================
# Cloak Installer (post-extraction)
# Runs after makeself archive extracts to set up ~/.cloak and symlinks.
#
# This script is called by:
#   1. makeself --postextract: after self-extracting archive decompresses
#   2. Manual: ./install.sh [--prefix DIR]
#===============================================================================

set -e

G='\033[38;5;36m'
LG='\033[38;5;115m'
D='\033[2m'
B='\033[1m'
R='\033[0m'
RED='\033[38;5;130m'
Y='\033[38;5;186m'

INSTALL_DIR="$HOME/.cloak"

#-------------------------------------------------------------------------------
# Parse args
#-------------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)  INSTALL_DIR="$2"; shift 2 ;;
        --prefix=*) INSTALL_DIR="${1#*=}"; shift ;;
        --help|-h)
            echo "Usage: install.sh [--prefix DIR]"
            echo "  Default install dir: ~/.cloak"
            exit 0
            ;;
        *) shift ;;
    esac
done

#-------------------------------------------------------------------------------
# Install
#-------------------------------------------------------------------------------

echo ""
echo -e "  ${G}${B}Installing Cloak${R}"
echo ""

# If running inside makeself extraction, USER_PWD is the extract dir
EXTRACT_DIR="${USER_PWD:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# If we're already where we need to be (update mode), skip copy
if [[ "${CLOAK_UPDATE:-}" == "1" ]]; then
    echo -e "  ${D}Update mode — files already in place${R}"
else
    # Create install dir
    mkdir -p "$INSTALL_DIR"

    # Copy everything from extract dir to install dir
    if [[ "$EXTRACT_DIR" != "$INSTALL_DIR" ]]; then
        echo -e "  ${D}Installing to ${INSTALL_DIR}${R}"
        cp -a "$EXTRACT_DIR/." "$INSTALL_DIR/"
    fi
fi

# Make scripts executable
find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
[[ -f "$INSTALL_DIR/bin/tmux" ]] && chmod +x "$INSTALL_DIR/bin/tmux"

#-------------------------------------------------------------------------------
# Symlink to PATH
#-------------------------------------------------------------------------------

link_cloak() {
    local target="$INSTALL_DIR/cloak.sh"
    local link_name="cloak"

    # Try common bin dirs in order
    local dirs=("$HOME/.local/bin" "$HOME/bin" "/usr/local/bin")

    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]] || mkdir -p "$dir" 2>/dev/null; then
            ln -sf "$target" "$dir/$link_name" 2>/dev/null && {
                echo -e "  ${D}Linked: ${dir}/${link_name} → cloak.sh${R}"
                # Check if dir is in PATH
                if [[ ":$PATH:" != *":$dir:"* ]]; then
                    echo -e "  ${Y}Add to your shell profile:${R}"
                    echo -e "    ${LG}export PATH=\"$dir:\$PATH\"${R}"
                fi
                return 0
            }
        fi
    done

    echo -e "  ${Y}Could not create symlink. Add manually:${R}"
    echo -e "    ${LG}ln -s $target /usr/local/bin/cloak${R}"
    echo -e "  ${D}or add to PATH:${R}"
    echo -e "    ${LG}export PATH=\"$INSTALL_DIR:\$PATH\"${R}"
}

link_cloak

#-------------------------------------------------------------------------------
# Write version if not present
#-------------------------------------------------------------------------------

if [[ ! -f "$INSTALL_DIR/.version" ]]; then
    echo "dev" > "$INSTALL_DIR/.version"
fi

#-------------------------------------------------------------------------------
# Done
#-------------------------------------------------------------------------------

VERSION=$(cat "$INSTALL_DIR/.version")

echo ""
echo -e "  ${G}${B}Cloak v${VERSION} installed${R}"
echo ""
echo -e "  ${D}Usage:${R}"
echo -e "    ${LG}cloak${R}              ${D}— Launch TUI${R}"
echo -e "    ${LG}cloak help${R}         ${D}— Show all commands${R}"
echo -e "    ${LG}cloak tmux${R}         ${D}— Launch in tmux session${R}"
echo ""
echo -e "  ${D}Install dir: ${INSTALL_DIR}${R}"
echo ""
