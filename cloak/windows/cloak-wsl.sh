#!/bin/bash
#===============================================================================
# Cloak WSL Entry Point
# Called by cloak.bat — sets up environment and launches cloak.sh
#===============================================================================

set -e

# Resolve to the cloak directory (parent of windows/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOAK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export CLOAK_HOME="$CLOAK_ROOT"

# Ensure bash scripts are executable (Windows may strip +x)
find "$CLOAK_ROOT" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

exec bash "$CLOAK_ROOT/cloak.sh" "$@"
