#!/bin/bash
#===============================================================================
# DNSCloak - Conduit (Psiphon Inproxy) Service Installer
# https://github.com/behnamkhorsandian/DNSCloak
#
# Conduit is a volunteer-run proxy relay node for the Psiphon network.
# It helps users in censored regions access the open internet.
#
# Usage: curl -sSL conduit.dnscloak.net | sudo bash
#===============================================================================

set -e

# Version
CONDUIT_VERSION="e421eff"
CONDUIT_RELEASE_URL="https://github.com/ssmirr/conduit/releases/download/${CONDUIT_VERSION}"

# Determine script location (works for both local and piped execution)
if [[ -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LIB_DIR="$(dirname "$SCRIPT_DIR")/../lib"
else
    # Piped execution - download libs
    LIB_DIR="/tmp/dnscloak-lib"
    mkdir -p "$LIB_DIR"
    GITHUB_RAW="https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main"
    curl -sL "$GITHUB_RAW/lib/common.sh" -o "$LIB_DIR/common.sh"
    curl -sL "$GITHUB_RAW/lib/cloud.sh" -o "$LIB_DIR/cloud.sh"
    curl -sL "$GITHUB_RAW/lib/bootstrap.sh" -o "$LIB_DIR/bootstrap.sh"
fi

# Source libraries
source "$LIB_DIR/common.sh"
source "$LIB_DIR/cloud.sh"
source "$LIB_DIR/bootstrap.sh"

#-------------------------------------------------------------------------------
# Conduit Configuration
#-------------------------------------------------------------------------------

SERVICE_NAME="conduit"
CONDUIT_DIR="$DNSCLOAK_DIR/conduit"
CONDUIT_BIN="/usr/local/bin/conduit"
CONDUIT_DATA="$CONDUIT_DIR/data"

# Default settings
DEFAULT_MAX_CLIENTS=200
DEFAULT_BANDWIDTH=5  # Mbps

#-------------------------------------------------------------------------------
# Installation Check
#-------------------------------------------------------------------------------

is_conduit_installed() {
    [[ -f "$CONDUIT_BIN" ]] && systemctl is-enabled --quiet conduit 2>/dev/null
}

is_conduit_running() {
    systemctl is-active --quiet conduit 2>/dev/null
}

#-------------------------------------------------------------------------------
# Detect Architecture
#-------------------------------------------------------------------------------

detect_arch() {
    local arch
    arch=$(uname -m)
    
    case "$arch" in
        x86_64|amd64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            print_info "Conduit supports: x86_64 (amd64), aarch64 (arm64)"
            exit 1
            ;;
    esac
}

#-------------------------------------------------------------------------------
# Download Conduit Binary
#-------------------------------------------------------------------------------

download_conduit() {
    print_step "Downloading Conduit binary"
    
    local arch
    arch=$(detect_arch)
    
    local download_url="${CONDUIT_RELEASE_URL}/conduit-linux-${arch}"
    local tmp_file="/tmp/conduit-$$"
    
    print_info "Architecture: linux-${arch}"
    print_info "URL: $download_url"
    
    if ! curl -L --fail --progress-bar -o "$tmp_file" "$download_url"; then
        print_error "Failed to download Conduit"
        rm -f "$tmp_file"
        exit 1
    fi
    
    # Make executable and move to bin
    chmod +x "$tmp_file"
    mv "$tmp_file" "$CONDUIT_BIN"
    
    # Verify binary works
    if ! "$CONDUIT_BIN" --version &>/dev/null; then
        print_error "Downloaded binary is not executable"
        rm -f "$CONDUIT_BIN"
        exit 1
    fi
    
    local version
    version=$("$CONDUIT_BIN" --version 2>/dev/null | head -1)
    print_success "Conduit installed: $version"
}

#-------------------------------------------------------------------------------
# Configure Conduit Settings
#-------------------------------------------------------------------------------

configure_settings() {
    print_step "Configuring Conduit settings"
    
    echo ""
    echo -e "  ${BOLD}Conduit relays traffic for Psiphon users in censored regions.${RESET}"
    echo -e "  ${GRAY}The more resources you share, the more users you can help.${RESET}"
    echo ""
    
    # Max clients
    echo -e "  ${CYAN}Max concurrent clients:${RESET}"
    echo "  Recommended: 200-500 for most servers"
    echo "  Higher values help more users but use more resources"
    echo ""
    get_input "Max clients" "$DEFAULT_MAX_CLIENTS" max_clients
    
    # Validate
    if ! [[ "$max_clients" =~ ^[0-9]+$ ]] || [[ "$max_clients" -lt 1 ]]; then
        max_clients=$DEFAULT_MAX_CLIENTS
    fi
    
    echo ""
    
    # Bandwidth
    echo -e "  ${CYAN}Bandwidth limit (Mbps):${RESET}"
    echo "  Recommended: 5-40 Mbps depending on your server"
    echo "  Set 0 for unlimited (not recommended)"
    echo ""
    get_input "Bandwidth (Mbps)" "$DEFAULT_BANDWIDTH" bandwidth
    
    # Validate
    if ! [[ "$bandwidth" =~ ^[0-9]+$ ]]; then
        bandwidth=$DEFAULT_BANDWIDTH
    fi
    
    # Save settings
    CONDUIT_MAX_CLIENTS="$max_clients"
    CONDUIT_BANDWIDTH="$bandwidth"
    
    # Store in users.json
    server_set "conduit_max_clients" "$max_clients"
    server_set "conduit_bandwidth" "$bandwidth"
    
    print_success "Settings configured"
    echo "  - Max clients: $max_clients"
    echo "  - Bandwidth: ${bandwidth} Mbps"
}

#-------------------------------------------------------------------------------
# Create Systemd Service
#-------------------------------------------------------------------------------

create_systemd_service() {
    print_step "Creating systemd service"
    
    local bandwidth_arg=""
    if [[ "$CONDUIT_BANDWIDTH" -gt 0 ]]; then
        bandwidth_arg="--bandwidth $CONDUIT_BANDWIDTH"
    fi
    
    cat > /etc/systemd/system/conduit.service <<EOF
[Unit]
Description=Conduit - Psiphon Volunteer Relay Node
Documentation=https://github.com/ssmirr/conduit
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${CONDUIT_BIN} start --data-dir ${CONDUIT_DATA} --max-clients ${CONDUIT_MAX_CLIENTS} ${bandwidth_arg}
Restart=always
RestartSec=5
LimitNOFILE=65535

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${CONDUIT_DIR}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    print_success "Systemd service created"
}

#-------------------------------------------------------------------------------
# Start Conduit Service
#-------------------------------------------------------------------------------

start_conduit() {
    print_step "Starting Conduit service"
    
    systemctl enable conduit
    systemctl start conduit
    
    # Wait for startup
    sleep 3
    
    if is_conduit_running; then
        print_success "Conduit is running"
    else
        print_error "Conduit failed to start"
        print_info "Check logs: journalctl -u conduit -n 50"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Show Status
#-------------------------------------------------------------------------------

show_status() {
    echo ""
    echo -e "  ${BOLD}${WHITE}Conduit Status${RESET}"
    print_line
    echo ""
    
    if is_conduit_running; then
        echo -e "  Status:      ${GREEN}Running${RESET}"
    else
        echo -e "  Status:      ${RED}Stopped${RESET}"
    fi
    
    local max_clients bandwidth
    max_clients=$(server_get "conduit_max_clients")
    bandwidth=$(server_get "conduit_bandwidth")
    
    echo "  Max Clients: ${max_clients:-$DEFAULT_MAX_CLIENTS}"
    echo "  Bandwidth:   ${bandwidth:-$DEFAULT_BANDWIDTH} Mbps"
    echo "  Data Dir:    $CONDUIT_DATA"
    echo ""
    
    # Show conduit key info if available
    if [[ -f "$CONDUIT_DATA/conduit_key.json" ]]; then
        echo -e "  ${CYAN}Node Identity:${RESET}"
        echo "  Your node has a unique identity stored in:"
        echo "  $CONDUIT_DATA/conduit_key.json"
        echo ""
        echo -e "  ${YELLOW}Important: Back up this file!${RESET}"
        echo "  The Psiphon broker tracks your reputation by this key."
        echo "  If you lose it, you'll need to build reputation from scratch."
    fi
    echo ""
}

#-------------------------------------------------------------------------------
# Live Statistics
#-------------------------------------------------------------------------------

show_live_stats() {
    print_info "Showing live statistics (Ctrl+C to exit)"
    echo ""
    
    "$CONDUIT_BIN" service status -f 2>/dev/null || \
    journalctl -u conduit -f --no-pager
}

#-------------------------------------------------------------------------------
# Install Conduit
#-------------------------------------------------------------------------------

install_conduit() {
    print_banner "conduit"
    echo -e "  ${BOLD}${WHITE}Conduit - Psiphon Volunteer Relay Node${RESET}"
    print_line
    echo ""
    echo -e "  ${CYAN}What is Conduit?${RESET}"
    echo "  Conduit is a volunteer-run proxy that relays traffic for"
    echo "  Psiphon users in censored regions, helping them access"
    echo "  the open internet."
    echo ""
    echo -e "  ${CYAN}How it works:${RESET}"
    echo "  - Your server becomes a relay node in the Psiphon network"
    echo "  - Users connect through Psiphon apps (not directly to you)"
    echo "  - The broker assigns clients based on your reputation"
    echo "  - No user management needed - it's automatic"
    echo ""
    
    if ! confirm "Install Conduit relay node?"; then
        echo "Installation cancelled"
        exit 0
    fi
    
    # Bootstrap (updates, prerequisites)
    bootstrap
    
    if is_conduit_installed; then
        print_warning "Conduit is already installed"
        if confirm "Reinstall?"; then
            uninstall_conduit_quiet
        else
            show_menu
            return
        fi
    fi
    
    # Create directories
    print_step "Creating directories"
    mkdir -p "$CONDUIT_DIR" "$CONDUIT_DATA"
    chmod 700 "$CONDUIT_DIR" "$CONDUIT_DATA"
    print_success "Directories created"
    
    # Download binary
    download_conduit
    
    # Configure settings
    configure_settings
    
    # Create service
    create_systemd_service
    
    # Start service
    start_conduit
    
    # Show results
    print_line
    print_success "Conduit installation complete!"
    echo ""
    show_status
    
    echo ""
    echo -e "  ${BOLD}${WHITE}Useful Commands${RESET}"
    print_line
    echo "  dnscloak status conduit     - Show status"
    echo "  dnscloak restart conduit    - Restart service"
    echo "  conduit service status -f   - Live statistics"
    echo "  journalctl -u conduit -f    - View logs"
    echo ""
    
    echo -e "  ${GREEN}Thank you for helping users in censored regions!${RESET}"
    echo ""
}

#-------------------------------------------------------------------------------
# Uninstall
#-------------------------------------------------------------------------------

uninstall_conduit_quiet() {
    systemctl stop conduit 2>/dev/null || true
    systemctl disable conduit 2>/dev/null || true
    rm -f /etc/systemd/system/conduit.service
    systemctl daemon-reload
    rm -f "$CONDUIT_BIN"
}

uninstall_conduit() {
    print_banner "conduit"
    echo -e "  ${BOLD}${WHITE}Uninstall Conduit${RESET}"
    print_line
    echo ""
    
    if ! is_conduit_installed; then
        print_error "Conduit is not installed"
        return 1
    fi
    
    echo -e "  ${YELLOW}Warning: This will:${RESET}"
    echo "  - Stop and remove the Conduit service"
    echo "  - Remove the Conduit binary"
    echo ""
    echo -e "  ${CYAN}Your node identity will be preserved in:${RESET}"
    echo "  $CONDUIT_DATA/conduit_key.json"
    echo ""
    
    if ! confirm "Uninstall Conduit?"; then
        return 0
    fi
    
    print_step "Stopping service"
    systemctl stop conduit 2>/dev/null || true
    systemctl disable conduit 2>/dev/null || true
    print_success "Service stopped"
    
    print_step "Removing service"
    rm -f /etc/systemd/system/conduit.service
    systemctl daemon-reload
    print_success "Service removed"
    
    print_step "Removing binary"
    rm -f "$CONDUIT_BIN"
    print_success "Binary removed"
    
    if confirm "Remove data directory (including node identity)?"; then
        rm -rf "$CONDUIT_DIR"
        print_success "Data directory removed"
    else
        print_info "Data preserved at: $CONDUIT_DIR"
    fi
    
    print_success "Conduit uninstalled"
}

#-------------------------------------------------------------------------------
# Reconfigure Settings
#-------------------------------------------------------------------------------

reconfigure_settings() {
    if ! is_conduit_installed; then
        print_error "Conduit is not installed"
        return 1
    fi
    
    print_step "Reconfiguring Conduit settings"
    
    # Get current settings
    local current_max_clients current_bandwidth
    current_max_clients=$(server_get "conduit_max_clients")
    current_bandwidth=$(server_get "conduit_bandwidth")
    
    echo ""
    echo "  Current settings:"
    echo "  - Max clients: ${current_max_clients:-$DEFAULT_MAX_CLIENTS}"
    echo "  - Bandwidth: ${current_bandwidth:-$DEFAULT_BANDWIDTH} Mbps"
    echo ""
    
    # Get new settings
    get_input "Max clients" "${current_max_clients:-$DEFAULT_MAX_CLIENTS}" max_clients
    get_input "Bandwidth (Mbps)" "${current_bandwidth:-$DEFAULT_BANDWIDTH}" bandwidth
    
    # Validate
    if ! [[ "$max_clients" =~ ^[0-9]+$ ]] || [[ "$max_clients" -lt 1 ]]; then
        max_clients="${current_max_clients:-$DEFAULT_MAX_CLIENTS}"
    fi
    if ! [[ "$bandwidth" =~ ^[0-9]+$ ]]; then
        bandwidth="${current_bandwidth:-$DEFAULT_BANDWIDTH}"
    fi
    
    CONDUIT_MAX_CLIENTS="$max_clients"
    CONDUIT_BANDWIDTH="$bandwidth"
    
    # Save settings
    server_set "conduit_max_clients" "$max_clients"
    server_set "conduit_bandwidth" "$bandwidth"
    
    # Recreate service
    create_systemd_service
    
    # Restart
    print_step "Restarting Conduit"
    systemctl restart conduit
    
    if is_conduit_running; then
        print_success "Conduit restarted with new settings"
    else
        print_error "Conduit failed to start"
        print_info "Check logs: journalctl -u conduit -n 50"
    fi
}

#-------------------------------------------------------------------------------
# Menu
#-------------------------------------------------------------------------------

show_menu() {
    while true; do
        print_banner "conduit"
        echo -e "  ${BOLD}${WHITE}Conduit Management${RESET}"
        print_line
        echo ""
        echo "  1) Show status"
        echo "  2) Live statistics"
        echo "  3) View logs"
        echo "  4) Reconfigure settings"
        echo "  5) Restart service"
        echo "  6) Uninstall Conduit"
        echo "  0) Exit"
        echo ""
        
        get_input "Select option" "0" choice
        
        case "$choice" in
            1)
                show_status
                press_enter
                ;;
            2)
                show_live_stats
                ;;
            3)
                echo ""
                print_info "Showing last 50 log lines (Ctrl+C to exit live mode)"
                journalctl -u conduit -n 50 --no-pager
                echo ""
                if confirm "Follow logs in real-time?"; then
                    journalctl -u conduit -f --no-pager
                fi
                press_enter
                ;;
            4)
                reconfigure_settings
                press_enter
                ;;
            5)
                print_step "Restarting Conduit"
                systemctl restart conduit
                sleep 2
                if is_conduit_running; then
                    print_success "Conduit restarted"
                else
                    print_error "Conduit failed to start"
                fi
                press_enter
                ;;
            6)
                uninstall_conduit
                press_enter
                ;;
            0|"")
                echo ""
                print_info "Bye! Thank you for supporting internet freedom!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    check_root
    check_os
    
    if is_conduit_installed; then
        show_menu
    else
        install_conduit
        echo ""
        if confirm "Open management menu?"; then
            show_menu
        fi
    fi
}

# Run
main "$@"
