#!/bin/bash
#===============================================================================
# DNSCloak - SOS Emergency Secure Chat
# https://github.com/behnamkhorsandian/DNSCloak
#
# USAGE:
#   Client (users): curl -sSL sos.dnscloak.net | bash
#   Server (admin): curl -sSL sos.dnscloak.net | sudo bash -s -- --server
#
# CLIENT MODE (default):
#   Launches TUI for creating/joining encrypted chat rooms
#
# SERVER MODE (--server):
#   Installs and runs the SOS relay daemon on your DNSTT server
#   Required: DNSTT server already installed, Redis (optional)
#
# Features:
#   - 6-emoji room ID + 6-digit key (rotating or fixed)
#   - Auto-wipe after 1 hour
#   - Message caching for reconnection
#   - E2E encrypted with NaCl + Argon2id
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

# Mode detection
SERVER_MODE=false
if [[ "$1" == "--server" ]] || [[ "$1" == "-s" ]]; then
    SERVER_MODE=true
fi

# Paths
if $SERVER_MODE; then
    SOS_DIR="/opt/dnscloak/sos"
else
    SOS_DIR="/tmp/sos-chat"
fi

GITHUB_RAW="https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main"
PYTHON_MIN_VERSION="3.8"

# Relay server configuration
SOS_RELAY_HOST="${SOS_RELAY_HOST:-127.0.0.1}"  # Default to localhost for DNSTT tunnel
SOS_RELAY_PORT="${SOS_RELAY_PORT:-8899}"

# Server mode settings
SOS_SYSTEMD_SERVICE="/etc/systemd/system/sos-relay.service"

#-------------------------------------------------------------------------------
# Banner
#-------------------------------------------------------------------------------

show_banner() {
    echo -e "${RED}"
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
    
    if $SERVER_MODE; then
        echo -e "  ${RED}>>> SERVER MODE <<<${RESET}"
        echo -e "  Installing SOS Relay Daemon"
        echo ""
    else
        echo -e "  ${GREEN}>>> CLIENT MODE <<<${RESET}"
        echo ""
    fi
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

#-------------------------------------------------------------------------------
# Server Mode Functions
#-------------------------------------------------------------------------------

install_server_dependencies() {
    local python_cmd="$1"
    
    print_step "Installing server dependencies..."
    
    # Create directory
    mkdir -p "$SOS_DIR"
    
    # Create virtual environment
    $python_cmd -m venv "$SOS_DIR/venv" 2>/dev/null || {
        apt-get install -y python3-venv 2>/dev/null || true
        $python_cmd -m venv "$SOS_DIR/venv"
    }
    
    # Activate and install
    source "$SOS_DIR/venv/bin/activate"
    
    pip install --quiet --upgrade pip
    pip install --quiet aiohttp pynacl argon2-cffi redis
    
    print_success "Server dependencies installed"
}

download_relay() {
    print_step "Downloading SOS relay..."
    
    mkdir -p "$SOS_DIR"
    
    # Download relay and crypto module
    curl -sfL "$GITHUB_RAW/src/sos/relay.py" -o "$SOS_DIR/relay.py" || {
        print_error "Failed to download relay.py"
        exit 1
    }
    curl -sfL "$GITHUB_RAW/src/sos/crypto.py" -o "$SOS_DIR/crypto.py" || {
        print_error "Failed to download crypto.py"
        exit 1
    }
    
    print_success "Relay downloaded"
}

create_systemd_service() {
    print_step "Creating systemd service..."
    
    cat > "$SOS_SYSTEMD_SERVICE" << EOF
[Unit]
Description=SOS Emergency Chat Relay Daemon
After=network.target dnstt-server.service
Wants=dnstt-server.service

[Service]
Type=simple
User=root
WorkingDirectory=$SOS_DIR
Environment="PATH=$SOS_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=$SOS_DIR/venv/bin/python $SOS_DIR/relay.py --host 0.0.0.0 --port $SOS_RELAY_PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable sos-relay
    systemctl start sos-relay
    
    print_success "Service created and started"
}

show_server_status() {
    echo ""
    print_step "SOS Relay Status"
    echo ""
    systemctl status sos-relay --no-pager -l || true
    echo ""
    print_success "SOS Relay is running on port $SOS_RELAY_PORT"
    print_info "Users can now create rooms via DNSTT tunnel"
    echo ""
    print_info "Commands:"
    echo "    systemctl status sos-relay   # Check status"
    echo "    systemctl restart sos-relay  # Restart"
    echo "    journalctl -u sos-relay -f   # View logs"
    echo ""
}

main() {
    clear
    show_banner
    
    if $SERVER_MODE; then
        # Server mode - requires root
        if [[ $EUID -ne 0 ]]; then
            print_error "Server mode requires root. Run with sudo."
            exit 1
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
        
        # Install server dependencies
        install_server_dependencies "$python_cmd"
        
        # Download relay
        download_relay
        
        # Create and start service
        create_systemd_service
        
        # Show status
        show_server_status
        
    else
        # Client mode - does not require root
        
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
    fi
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n\n  ${YELLOW}[!]${RESET} Chat ended. Stay safe.\n"; exit 0' INT

main "$@"
