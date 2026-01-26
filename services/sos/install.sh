#!/bin/bash
#===============================================================================
# DNSCloak - SOS Emergency Secure Chat Installer
# https://github.com/behnamkhorsandian/DNSCloak
#
# Usage: curl -sSL sos.dnscloak.net | sudo bash
#
# Creates encrypted chat rooms over DNS tunnel (DNSTT) that:
#   - Use 6 emojis as room ID + 6-digit key (rotating or fixed)
#   - Auto-wipe after 1 hour
#   - Cache messages for reconnection
#   - Perfect for emergency communication in blackouts
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'
BOLD='\033[1m'

print_step() { echo -e "\n  ${BLUE}>>>${RESET} ${BOLD}$1${RESET}"; }
print_success() { echo -e "  ${GREEN}[+]${RESET} $1"; }
print_error() { echo -e "  ${RED}[-]${RESET} $1"; }
print_info() { echo -e "  ${CYAN}[*]${RESET} $1"; }

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------

SOS_DIR="/tmp/sos-chat"
GITHUB_RAW="https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main"
PYTHON_MIN_VERSION="3.8"

# DNSTT relay server configuration
SOS_RELAY_HOST="${SOS_RELAY_HOST:-relay.dnscloak.net}"
SOS_RELAY_PORT="${SOS_RELAY_PORT:-8899}"

#-------------------------------------------------------------------------------
# Banner
#-------------------------------------------------------------------------------

show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
      ▒▒▒▒▒▒▒╗ ▒▒▒▒▒▒╗ ▒▒▒▒▒▒▒╗
      ▒▒╔════╝▒▒╔═══▒▒╗▒▒╔════╝
      ▒▒▒▒▒▒▒╗▒▒║   ▒▒║▒▒▒▒▒▒▒╗
      ╚════▒▒║▒▒║   ▒▒║╚════▒▒║
      ▒▒▒▒▒▒▒║╚▒▒▒▒▒▒╔╝▒▒▒▒▒▒▒║
      ╚══════╝ ╚═════╝ ╚══════╝

        Emergency Secure Chat
    Encrypted rooms over DNS tunnel
EOF
    echo -e "${RESET}"
}

#-------------------------------------------------------------------------------
# System Detection
#-------------------------------------------------------------------------------

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        OS="unknown"
    fi
    echo "$OS"
}

#-------------------------------------------------------------------------------
# Python Detection & Installation
#-------------------------------------------------------------------------------

check_python() {
    local python_cmd=""
    
    # Check for python3
    if command -v python3 &>/dev/null; then
        python_cmd="python3"
    elif command -v python &>/dev/null; then
        # Check if python is python3
        local ver
        ver=$(python --version 2>&1 | grep -oP '\d+' | head -1)
        if [[ "$ver" -ge 3 ]]; then
            python_cmd="python"
        fi
    fi
    
    if [[ -z "$python_cmd" ]]; then
        return 1
    fi
    
    # Check version
    local version
    version=$($python_cmd -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    local major minor
    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)
    
    if [[ "$major" -ge 3 ]] && [[ "$minor" -ge 8 ]]; then
        echo "$python_cmd"
        return 0
    fi
    
    return 1
}

install_python() {
    local os
    os=$(detect_os)
    
    print_step "Installing Python 3..."
    
    case "$os" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y python3 python3-pip python3-venv
            ;;
        centos|rhel|fedora)
            dnf install -y python3 python3-pip || yum install -y python3 python3-pip
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm python python-pip
            ;;
        macos)
            if command -v brew &>/dev/null; then
                brew install python3
            else
                print_error "Please install Homebrew first: https://brew.sh"
                exit 1
            fi
            ;;
        *)
            print_error "Unsupported OS. Please install Python 3.8+ manually."
            exit 1
            ;;
    esac
}

#-------------------------------------------------------------------------------
# Dependencies Installation
#-------------------------------------------------------------------------------

install_dependencies() {
    local python_cmd="$1"
    
    print_step "Installing dependencies..."
    
    # Create virtual environment
    mkdir -p "$SOS_DIR"
    $python_cmd -m venv "$SOS_DIR/venv" 2>/dev/null || {
        # If venv fails, try installing python3-venv
        apt-get install -y python3-venv 2>/dev/null || true
        $python_cmd -m venv "$SOS_DIR/venv"
    }
    
    # Activate and install
    source "$SOS_DIR/venv/bin/activate"
    
    pip install --quiet --upgrade pip
    pip install --quiet textual pynacl httpx[socks] argon2-cffi
    
    print_success "Dependencies installed"
}

#-------------------------------------------------------------------------------
# Download TUI Client
#-------------------------------------------------------------------------------

download_client() {
    print_step "Downloading SOS client..."
    
    mkdir -p "$SOS_DIR/sos"
    
    # Download all client files
    local files=("app.py" "room.py" "transport.py" "crypto.py" "__init__.py")
    
    for file in "${files[@]}"; do
        if ! curl -sfL "$GITHUB_RAW/src/sos/$file" -o "$SOS_DIR/sos/$file"; then
            print_error "Failed to download $file"
            exit 1
        fi
    done
    
    # Download CSS
    curl -sfL "$GITHUB_RAW/src/sos/app.tcss" -o "$SOS_DIR/sos/app.tcss" 2>/dev/null || true
    
    print_success "Client downloaded"
}

#-------------------------------------------------------------------------------
# Launch TUI
#-------------------------------------------------------------------------------

launch_tui() {
    local python_cmd="$1"
    
    print_step "Launching SOS Chat..."
    echo ""
    print_info "Room ID: 6 emojis (share verbally)"
    print_info "Key: 6 digits (rotating every 15s or fixed)"
    print_info "Room expires: 1 hour"
    echo ""
    
    sleep 1
    
    # Activate venv and run
    source "$SOS_DIR/venv/bin/activate"
    
    # Set environment variables for relay connection
    export SOS_RELAY_HOST="$SOS_RELAY_HOST"
    export SOS_RELAY_PORT="$SOS_RELAY_PORT"
    
    cd "$SOS_DIR"
    python -m sos.app
}

#-------------------------------------------------------------------------------
# Cleanup
#-------------------------------------------------------------------------------

cleanup() {
    # Don't remove on exit during normal operation
    # Only cleanup old installations
    rm -rf /tmp/sos-chat-old 2>/dev/null || true
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    # Check if running as root (optional for client)
    # Not required since we install to /tmp
    
    clear
    show_banner
    
    # Cleanup old installation
    if [[ -d "$SOS_DIR" ]]; then
        mv "$SOS_DIR" /tmp/sos-chat-old 2>/dev/null || rm -rf "$SOS_DIR"
    fi
    
    # Check/install Python
    local python_cmd
    python_cmd=$(check_python) || {
        print_info "Python 3.8+ not found"
        install_python
        python_cmd=$(check_python) || {
            print_error "Failed to install Python"
            exit 1
        }
    }
    print_success "Found Python: $python_cmd"
    
    # Install dependencies
    install_dependencies "$python_cmd"
    
    # Download client
    download_client
    
    # Launch TUI
    launch_tui "$python_cmd"
    
    # Cleanup on exit
    cleanup
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n\n  ${YELLOW}[!]${RESET} Chat ended. Stay safe.\n"; exit 0' INT

main "$@"
