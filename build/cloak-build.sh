#!/bin/bash
#===============================================================================
# Cloak Build Script
# Assembles the Cloak shell archive for a given platform.
#
# Usage:
#   ./build/cloak-build.sh <platform> [version]
#
# Platforms: linux-amd64, linux-arm64, darwin-amd64, darwin-arm64, windows-amd64
#
# Requires: makeself (unix), zip (windows)
# Produces: dist/cloak-<platform>.sh  (or .zip for windows)
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PLATFORM="${1:?Usage: cloak-build.sh <platform> [version]}"
VERSION="${2:-dev}"

DIST_DIR="$REPO_ROOT/dist"
STAGE_DIR="$REPO_ROOT/.build-stage/$PLATFORM"
TMUX_DIR="$REPO_ROOT/.build-stage/tmux"

# Static tmux download URLs (libtmux/tmux-static builds)
declare -A TMUX_URLS=(
    [linux-amd64]="https://github.com/mjakob-gh/build-static-tmux/releases/download/v3.5a/tmux-v3.5a-linux-amd64.tar.gz"
    [linux-arm64]="https://github.com/mjakob-gh/build-static-tmux/releases/download/v3.5a/tmux-v3.5a-linux-arm64.tar.gz"
    [darwin-amd64]=""
    [darwin-arm64]=""
)

# macOS has tmux via brew; we skip bundling and note it in docs

echo "=== Cloak Build ==="
echo "Platform: $PLATFORM"
echo "Version:  $VERSION"
echo ""

#-------------------------------------------------------------------------------
# Validate
#-------------------------------------------------------------------------------

if [[ "$PLATFORM" != "linux-amd64" && "$PLATFORM" != "linux-arm64" && \
      "$PLATFORM" != "darwin-amd64" && "$PLATFORM" != "darwin-arm64" && \
      "$PLATFORM" != "windows-amd64" ]]; then
    echo "ERROR: Unknown platform: $PLATFORM"
    echo "Valid: linux-amd64, linux-arm64, darwin-amd64, darwin-arm64, windows-amd64"
    exit 1
fi

#-------------------------------------------------------------------------------
# Clean and prepare staging dir
#-------------------------------------------------------------------------------

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$DIST_DIR"

echo "Staging files..."

#-------------------------------------------------------------------------------
# Copy Cloak core
#-------------------------------------------------------------------------------

cp -a "$REPO_ROOT/cloak/." "$STAGE_DIR/"

#-------------------------------------------------------------------------------
# Copy TUI system
#-------------------------------------------------------------------------------

mkdir -p "$STAGE_DIR/tui"
cp -a "$REPO_ROOT/tui/." "$STAGE_DIR/tui/"

#-------------------------------------------------------------------------------
# Copy libs
#-------------------------------------------------------------------------------

mkdir -p "$STAGE_DIR/lib"
for f in common.sh cloud.sh xray.sh; do
    [[ -f "$REPO_ROOT/lib/$f" ]] && cp "$REPO_ROOT/lib/$f" "$STAGE_DIR/lib/"
done

#-------------------------------------------------------------------------------
# Copy protocol install scripts
#-------------------------------------------------------------------------------

mkdir -p "$STAGE_DIR/scripts/protocols"
cp -a "$REPO_ROOT/scripts/protocols/." "$STAGE_DIR/scripts/protocols/"

#-------------------------------------------------------------------------------
# Copy tools (cfray, findns, tracer, speedtest)
#-------------------------------------------------------------------------------

mkdir -p "$STAGE_DIR/scripts/tools"
for tool in cfray.sh findns.sh tracer.sh speedtest.sh; do
    [[ -f "$REPO_ROOT/scripts/tools/$tool" ]] && cp "$REPO_ROOT/scripts/tools/$tool" "$STAGE_DIR/scripts/tools/"
done

#-------------------------------------------------------------------------------
# Copy Docker compose files
#-------------------------------------------------------------------------------

mkdir -p "$STAGE_DIR/docker"
for proto_dir in "$REPO_ROOT/docker"/*/; do
    proto_name="$(basename "$proto_dir")"
    mkdir -p "$STAGE_DIR/docker/$proto_name"
    cp -a "$proto_dir." "$STAGE_DIR/docker/$proto_name/"
done

#-------------------------------------------------------------------------------
# Copy bootstrap script
#-------------------------------------------------------------------------------

[[ -f "$REPO_ROOT/scripts/docker-bootstrap.sh" ]] && cp "$REPO_ROOT/scripts/docker-bootstrap.sh" "$STAGE_DIR/scripts/"

#-------------------------------------------------------------------------------
# Copy banners
#-------------------------------------------------------------------------------

mkdir -p "$STAGE_DIR/banners"
cp -a "$REPO_ROOT/banners/." "$STAGE_DIR/banners/" 2>/dev/null || true

#-------------------------------------------------------------------------------
# Copy TUI content
#-------------------------------------------------------------------------------

if [[ -d "$REPO_ROOT/tui/content" ]]; then
    mkdir -p "$STAGE_DIR/tui/content"
    cp -a "$REPO_ROOT/tui/content/." "$STAGE_DIR/tui/content/"
fi

#-------------------------------------------------------------------------------
# Write version
#-------------------------------------------------------------------------------

echo "$VERSION" > "$STAGE_DIR/.version"

#-------------------------------------------------------------------------------
# Download static tmux (Linux only)
#-------------------------------------------------------------------------------

if [[ "$PLATFORM" == linux-* ]]; then
    TMUX_URL="${TMUX_URLS[$PLATFORM]:-}"
    if [[ -n "$TMUX_URL" ]]; then
        echo "Downloading static tmux for $PLATFORM..."
        mkdir -p "$TMUX_DIR"
        local_archive="$TMUX_DIR/tmux-$PLATFORM.tar.gz"
        if [[ ! -f "$local_archive" ]]; then
            curl -sfL -o "$local_archive" "$TMUX_URL"
        fi
        mkdir -p "$STAGE_DIR/bin"
        tar -xzf "$local_archive" -C "$STAGE_DIR/bin/" --strip-components=1 2>/dev/null || \
            tar -xzf "$local_archive" -C "$STAGE_DIR/bin/" 2>/dev/null
        # Ensure only the tmux binary is kept
        if [[ -f "$STAGE_DIR/bin/tmux" ]]; then
            chmod +x "$STAGE_DIR/bin/tmux"
            echo "  tmux bundled."
        else
            # Try finding it recursively
            local tmux_bin
            tmux_bin=$(find "$STAGE_DIR/bin" -name "tmux" -type f | head -1)
            if [[ -n "$tmux_bin" ]]; then
                mv "$tmux_bin" "$STAGE_DIR/bin/tmux"
                chmod +x "$STAGE_DIR/bin/tmux"
                echo "  tmux bundled."
            else
                echo "  WARNING: tmux binary not found in archive."
            fi
        fi
    fi
elif [[ "$PLATFORM" == darwin-* ]]; then
    echo "  macOS: tmux will use system install (brew install tmux)"
fi

#-------------------------------------------------------------------------------
# Make all scripts executable
#-------------------------------------------------------------------------------

find "$STAGE_DIR" -name "*.sh" -exec chmod +x {} \;

#-------------------------------------------------------------------------------
# Build archive
#-------------------------------------------------------------------------------

OUTPUT_NAME="cloak-${PLATFORM}"

if [[ "$PLATFORM" == "windows-amd64" ]]; then
    # Windows gets a zip with WSL bridge
    echo "Building ZIP for Windows..."
    (cd "$STAGE_DIR" && zip -qr "$DIST_DIR/${OUTPUT_NAME}.zip" .)
    echo "Output: dist/${OUTPUT_NAME}.zip"
else
    # Unix gets makeself self-extracting archive
    if ! command -v makeself &>/dev/null; then
        # Try local makeself
        if [[ -x "$REPO_ROOT/build/makeself.sh" ]]; then
            MAKESELF="$REPO_ROOT/build/makeself.sh"
        else
            echo "ERROR: makeself not found. Install: brew install makeself (mac) or apt install makeself (linux)"
            exit 1
        fi
    else
        MAKESELF="makeself"
    fi

    echo "Building self-extracting archive..."
    $MAKESELF \
        --gzip \
        --nox11 \
        "$STAGE_DIR" \
        "$DIST_DIR/${OUTPUT_NAME}.sh" \
        "Cloak v${VERSION} — Vany Offline Suite" \
        ./install.sh

    chmod +x "$DIST_DIR/${OUTPUT_NAME}.sh"
    echo "Output: dist/${OUTPUT_NAME}.sh"
fi

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------

echo ""
echo "=== Build Complete ==="
ls -lh "$DIST_DIR/${OUTPUT_NAME}"* 2>/dev/null
echo ""
