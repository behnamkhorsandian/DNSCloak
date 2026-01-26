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
UPDATE_MODE=false
for arg in "$@"; do
    case "$arg" in
        --server|-s) SERVER_MODE=true ;;
        --update|-u) UPDATE_MODE=true; SERVER_MODE=true ;;
    esac
done

# Paths
if $SERVER_MODE; then
    SOS_DIR="/opt/dnscloak/sos"
else
    SOS_DIR="/tmp/sos-chat"
fi

# Use jsDelivr CDN (auto-purges on new commits, more reliable than raw.githubusercontent)
# Add timestamp for cache busting
CACHE_BUST="?t=$(date +%s)"
GITHUB_RAW="https://cdn.jsdelivr.net/gh/behnamkhorsandian/DNSCloak@main"
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
    
    # Download all client files (with cache busting)
    local files=("app.py" "room.py" "transport.py" "crypto.py" "__init__.py")
    
    for file in "${files[@]}"; do
        if ! curl -sfL "${GITHUB_RAW}/src/sos/${file}${CACHE_BUST}" -o "$SOS_DIR/sos/$file"; then
            print_error "Failed to download $file"
            exit 1
        fi
    done
    
    # Download CSS
    curl -sfL "${GITHUB_RAW}/src/sos/app.tcss${CACHE_BUST}" -o "$SOS_DIR/sos/app.tcss" 2>/dev/null || true
    
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

# Cloud provider detection for firewall
detect_cloud_provider() {
    # AWS
    if curl -s -m 2 http://169.254.169.254/latest/meta-data/ &>/dev/null; then
        echo "aws"
        return
    fi
    # GCP
    if curl -s -m 2 -H "Metadata-Flavor: Google" http://metadata.google.internal/ &>/dev/null; then
        echo "gcp"
        return
    fi
    # Azure
    if curl -s -m 2 -H "Metadata: true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" &>/dev/null; then
        echo "azure"
        return
    fi
    # DigitalOcean
    if curl -s -m 2 http://169.254.169.254/metadata/v1/ &>/dev/null; then
        echo "digitalocean"
        return
    fi
    # Oracle Cloud
    if curl -s -m 2 http://169.254.169.254/opc/v1/instance/ &>/dev/null; then
        echo "oracle"
        return
    fi
    echo "unknown"
}

configure_firewall() {
    print_step "Configuring firewall for port $SOS_RELAY_PORT..."
    
    local provider
    provider=$(detect_cloud_provider)
    
    case "$provider" in
        gcp)
            if command -v gcloud &>/dev/null; then
                gcloud compute firewall-rules create dnscloak-sos-relay \
                    --allow="tcp:${SOS_RELAY_PORT}" \
                    --source-ranges=0.0.0.0/0 \
                    --description="SOS Relay for DNSCloak" \
                    --quiet 2>/dev/null && print_success "GCP firewall rule created" || print_info "GCP firewall rule may already exist"
            else
                print_info "gcloud not found, using local firewall"
                _configure_local_firewall
            fi
            ;;
        aws)
            # AWS security groups require more context, use local firewall
            print_info "AWS detected - configure Security Group manually or using local firewall"
            _configure_local_firewall
            ;;
        oracle)
            # Oracle Cloud - iptables + cloud console
            print_info "Oracle Cloud detected - also add ingress rule in Cloud Console"
            _configure_local_firewall
            ;;
        *)
            _configure_local_firewall
            ;;
    esac
}

_configure_local_firewall() {
    # Try ufw first (Ubuntu/Debian)
    if command -v ufw &>/dev/null; then
        ufw allow "$SOS_RELAY_PORT/tcp" 2>/dev/null && print_success "UFW: Port $SOS_RELAY_PORT opened" || true
        return
    fi
    
    # Try firewalld (CentOS/RHEL/Fedora)
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="${SOS_RELAY_PORT}/tcp" 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        print_success "firewalld: Port $SOS_RELAY_PORT opened"
        return
    fi
    
    # Fall back to iptables
    if command -v iptables &>/dev/null; then
        iptables -I INPUT -p tcp --dport "$SOS_RELAY_PORT" -j ACCEPT 2>/dev/null || true
        # Try to save rules
        if command -v iptables-save &>/dev/null; then
            iptables-save > /etc/iptables.rules 2>/dev/null || true
        fi
        print_success "iptables: Port $SOS_RELAY_PORT opened"
        return
    fi
    
    print_info "No firewall tool found - port may already be open"
}

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
    mkdir -p "$SOS_DIR/www"
    
    # Download relay and crypto module (with cache busting)
    curl -sfL "${GITHUB_RAW}/src/sos/relay.py${CACHE_BUST}" -o "$SOS_DIR/relay.py" || {
        print_error "Failed to download relay.py"
        exit 1
    }
    curl -sfL "${GITHUB_RAW}/src/sos/crypto.py${CACHE_BUST}" -o "$SOS_DIR/crypto.py" || {
        print_error "Failed to download crypto.py"
        exit 1
    }
    
    print_success "Relay downloaded"
    
    # Download web client (with cache busting)
    print_step "Downloading web client..."
    
    curl -sfL "${GITHUB_RAW}/src/sos/www/index.html${CACHE_BUST}" -o "$SOS_DIR/www/index.html" || {
        print_error "Failed to download index.html"
        exit 1
    }
    curl -sfL "${GITHUB_RAW}/src/sos/www/app.js${CACHE_BUST}" -o "$SOS_DIR/www/app.js" || {
        print_error "Failed to download app.js"
        exit 1
    }
    
    print_success "Web client downloaded"
}

create_update_script() {
    print_step "Creating update script..."
    
    cat > "$SOS_DIR/update.sh" << 'UPDATEEOF'
#!/bin/bash
# SOS Relay Auto-Update Script
# Downloads latest files from CDN and restarts only if changed

set -e

SOS_DIR="/opt/dnscloak/sos"
CDN="https://cdn.jsdelivr.net/gh/behnamkhorsandian/DNSCloak@main"
BUST="?t=$(date +%s)"
LOG_FILE="/var/log/sos-update.log"
CHANGED=false

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

download_if_changed() {
    local url="$1"
    local dest="$2"
    local tmp="/tmp/sos-update-$$-$(basename "$dest")"
    
    if curl -sfL "${url}${BUST}" -o "$tmp" 2>/dev/null; then
        if [[ -f "$dest" ]]; then
            # Compare checksums
            local old_sum new_sum
            old_sum=$(md5sum "$dest" 2>/dev/null | cut -d' ' -f1)
            new_sum=$(md5sum "$tmp" 2>/dev/null | cut -d' ' -f1)
            
            if [[ "$old_sum" != "$new_sum" ]]; then
                mv "$tmp" "$dest"
                log "Updated: $dest"
                CHANGED=true
            else
                rm -f "$tmp"
            fi
        else
            mv "$tmp" "$dest"
            log "Created: $dest"
            CHANGED=true
        fi
    else
        rm -f "$tmp"
        log "Failed to download: $url"
    fi
}

# Update files
download_if_changed "${CDN}/src/sos/relay.py" "$SOS_DIR/relay.py"
download_if_changed "${CDN}/src/sos/crypto.py" "$SOS_DIR/crypto.py"
download_if_changed "${CDN}/src/sos/www/index.html" "$SOS_DIR/www/index.html"
download_if_changed "${CDN}/src/sos/www/app.js" "$SOS_DIR/www/app.js"

# Restart only if relay.py or crypto.py changed (web files don't need restart)
if [[ "$CHANGED" == "true" ]] && grep -q "relay.py\|crypto.py" "$LOG_FILE" 2>/dev/null; then
    log "Restarting sos-relay service..."
    systemctl restart sos-relay
    log "Service restarted"
fi

log "Update check completed (changed=$CHANGED)"
UPDATEEOF
    
    chmod +x "$SOS_DIR/update.sh"
    print_success "Update script created: $SOS_DIR/update.sh"
}

setup_auto_update() {
    print_step "Setting up hourly auto-update..."
    
    # Create cron job for hourly updates
    local cron_file="/etc/cron.d/sos-update"
    cat > "$cron_file" << EOF
# SOS Relay Auto-Update - runs hourly
# Downloads latest files from CDN, restarts only if changed
0 * * * * root $SOS_DIR/update.sh >/dev/null 2>&1
EOF
    
    chmod 644 "$cron_file"
    print_success "Auto-update cron job installed (hourly)"
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
    # Get public IP
    local public_ip
    public_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")
    
    echo ""
    print_step "SOS Relay Status"
    echo ""
    systemctl status sos-relay --no-pager -l || true
    echo ""
    print_success "SOS Relay is running on port $SOS_RELAY_PORT"
    echo ""
    
    echo -e "  ${CYAN}=== ACCESS METHODS ===${RESET}"
    echo ""
    echo -e "  ${GREEN}1. Web Client (via DNSTT tunnel)${RESET}"
    echo "     Configure browser SOCKS5 proxy -> 127.0.0.1:10800"
    echo "     Then browse to: http://${public_ip}:${SOS_RELAY_PORT}/"
    echo ""
    echo -e "  ${GREEN}2. TUI Client${RESET}"
    echo "     curl -sSL sos.dnscloak.net | bash"
    echo ""
    echo -e "  ${GREEN}3. Direct (no censorship bypass)${RESET}"
    echo "     http://${public_ip}:${SOS_RELAY_PORT}/"
    echo ""
    
    echo -e "  ${CYAN}=== MANAGEMENT ===${RESET}"
    echo ""
    echo "    systemctl status sos-relay   # Check status"
    echo "    systemctl restart sos-relay  # Restart"
    echo "    journalctl -u sos-relay -f   # View logs"
    echo ""
    echo -e "  ${CYAN}=== AUTO-UPDATE ===${RESET}"
    echo ""
    echo "    $SOS_DIR/update.sh           # Manual update"
    echo "    cat /var/log/sos-update.log  # Update logs"
    echo "    # Auto-updates hourly via cron"
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
        
        # Update mode - just run the update script
        if $UPDATE_MODE; then
            if [[ -x "$SOS_DIR/update.sh" ]]; then
                print_step "Running update..."
                "$SOS_DIR/update.sh"
                print_success "Update complete"
                echo ""
                cat /var/log/sos-update.log | tail -10
                exit 0
            else
                print_error "Update script not found. Run full install first."
                exit 1
            fi
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
        
        # Configure firewall (auto-detect cloud provider)
        configure_firewall
        
        # Create update script and cron job
        create_update_script
        setup_auto_update
        
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
