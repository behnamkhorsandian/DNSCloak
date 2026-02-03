#!/bin/bash
# SOS Emergency Chat - macOS Launcher
# Double-click this file to start SOS

# Get the directory where this script is located
DIR="$(cd "$(dirname "$0")" && pwd)"

# Find the binary
if [[ -f "$DIR/sos-darwin-arm64" ]]; then
    BINARY="$DIR/sos-darwin-arm64"
elif [[ -f "$DIR/sos-darwin-amd64" ]]; then
    BINARY="$DIR/sos-darwin-amd64"
else
    echo "Error: SOS binary not found!"
    echo "Make sure sos-darwin-arm64 or sos-darwin-amd64 is in the same folder."
    read -p "Press Enter to close..."
    exit 1
fi

# Make sure it's executable
chmod +x "$BINARY"

# Run SOS
"$BINARY"

# Keep terminal open on error
if [[ $? -ne 0 ]]; then
    echo ""
    read -p "Press Enter to close..."
fi
