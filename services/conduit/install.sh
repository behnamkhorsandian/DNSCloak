#!/bin/bash
#===============================================================================
# DNSCloak - Conduit (Psiphon Inproxy) Service Installer
# https://github.com/behnamkhorsandian/DNSCloak
#
# Conduit is a volunteer-run proxy relay node for the Psiphon network.
# It helps users in censored regions access the open internet.
#
# Usage: curl -sSL conduit.dnscloak.net | sudo bash
#
# Requirements: Docker (auto-installed if not present)
# Commands: conduit status | logs | peers
#===============================================================================

set -e

# Docker Image
CONDUIT_IMAGE="ghcr.io/ssmirr/conduit/conduit:latest"

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
CONDUIT_MONITORING_SCRIPT="/usr/local/bin/conduit"
CONDUIT_VOLUME="conduit-data"

# Default settings
DEFAULT_MAX_CLIENTS=200
DEFAULT_BANDWIDTH=5  # Mbps (-1 for unlimited)

#-------------------------------------------------------------------------------
# Installation Check
#-------------------------------------------------------------------------------

is_conduit_installed() {
    docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^conduit$"
}

is_conduit_running() {
    docker ps --filter "name=conduit" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -q "^conduit$"
}

#-------------------------------------------------------------------------------
# Install Monitoring Script
#-------------------------------------------------------------------------------

install_monitoring_script() {
    print_step "Installing monitoring script"
    
    # Get the script content (from same directory during installation)
    local script_dir
    if [[ -f "${BASH_SOURCE[0]}" ]]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    else
        script_dir="/tmp/dnscloak-conduit"
        mkdir -p "$script_dir"
        # Download from GitHub
        local script_url="https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main/services/conduit/monitoring-script.sh"
        curl -sL "$script_url" -o "$script_dir/monitoring-script.sh"
    fi
    
    # Install to /usr/local/bin
    if [[ -f "$script_dir/monitoring-script.sh" ]]; then
        cp "$script_dir/monitoring-script.sh" "$CONDUIT_MONITORING_SCRIPT"
        chmod +x "$CONDUIT_MONITORING_SCRIPT"
        print_success "Monitoring script installed"
    else
        print_warning "Could not find monitoring script, skipping"
    fi
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
    echo "  Set -1 for unlimited (not recommended)"
    echo ""
    get_input "Bandwidth (Mbps)" "$DEFAULT_BANDWIDTH" bandwidth
    
    # Validate
    if ! [[ "$bandwidth" =~ ^-?[0-9]+$ ]]; then
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
    if [[ "$bandwidth" == "-1" ]]; then
        echo "  - Bandwidth: Unlimited"
    else
        echo "  - Bandwidth: ${bandwidth} Mbps"
    fi
}

#-------------------------------------------------------------------------------
# Start Conduit Container
#-------------------------------------------------------------------------------

start_conduit() {
    print_step "Starting Conduit container"
    
    if docker start conduit &>/dev/null; then
        # Wait for startup
        sleep 3
        
        if is_conduit_running; then
            print_success "Conduit is running"
        else
            print_error "Conduit failed to start"
            print_info "Check logs: docker logs conduit"
            exit 1
        fi
    else
        print_error "Failed to start container"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Stop Conduit Container
#-------------------------------------------------------------------------------

stop_conduit() {
    print_step "Stopping Conduit container"
    
    if docker stop conduit &>/dev/null; then
        print_success "Conduit stopped"
    else
        print_error "Failed to stop container"
        return 1
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
    
    if ! is_conduit_installed; then
        echo -e "  Status:      ${RED}Not Installed${RESET}"
        return 1
    fi
    
    if is_conduit_running; then
        echo -e "  Status:      ${GREEN}Running${RESET}"
    else
        echo -e "  Status:      ${RED}Stopped${RESET}"
    fi
    
    local max_clients bandwidth
    max_clients=$(server_get "conduit_max_clients")
    bandwidth=$(server_get "conduit_bandwidth")
    
    echo "  Max Clients: ${max_clients:-$DEFAULT_MAX_CLIENTS}"
    if [[ "${bandwidth:-$DEFAULT_BANDWIDTH}" == "-1" ]]; then
        echo "  Bandwidth:   Unlimited"
    else
        echo "  Bandwidth:   ${bandwidth:-$DEFAULT_BANDWIDTH} Mbps"
    fi
    echo "  Data Volume: $CONDUIT_VOLUME"
    echo ""
    
    # Show latest stats from logs
    if is_conduit_running; then
        echo -e "  ${CYAN}Latest Statistics:${RESET}"
        docker logs conduit 2>&1 | grep "\[STATS\]" | tail -1 || echo "  No stats available yet"
        echo ""
    fi
    
    # Show node identity info
    echo -e "  ${CYAN}Node Identity:${RESET}"
    echo "  Your node has a unique identity stored in Docker volume"
    echo "  Volume: $CONDUIT_VOLUME"
    echo ""
    echo -e "  ${YELLOW}Important: Back up this volume!${RESET}"
    echo "  The Psiphon broker tracks your reputation by this key."
    echo "  If you lose it, you'll need to build reputation from scratch."
    echo ""
}

#-------------------------------------------------------------------------------
# Live Statistics
#-------------------------------------------------------------------------------

show_live_stats() {
    print_info "Showing live statistics (Ctrl+C to exit)"
    echo ""
    
    if command -v conduit &>/dev/null; then
        conduit logs
    else
        docker logs -f conduit 2>&1 | grep --line-buffered "\[STATS\]"
    fi
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
    
    # Ensure Docker is installed
    if ! command -v docker &>/dev/null; then
        install_docker
    else
        print_info "Docker is already installed"
    fi
    
    # Pull Docker image
    print_step "Pulling Conduit Docker image"
    if docker pull "$CONDUIT_IMAGE"; then
        print_success "Docker image pulled"
    else
        print_error "Failed to pull Docker image"
        exit 1
    fi
    
    # Configure settings
    configure_settings
    
    # Create directories (for compatibility)
    print_step "Creating directories"
    mkdir -p "$CONDUIT_DIR"
    chmod 700 "$CONDUIT_DIR"
    print_success "Directories created"
    
    # Create and start Docker container
    print_step "Creating Conduit container"
    
    local bandwidth_flag="-b ${CONDUIT_BANDWIDTH}"
    
    if docker run -d --name conduit \
        -v "$CONDUIT_VOLUME":/home/conduit/data \
        --restart unless-stopped \
        "$CONDUIT_IMAGE" \
        start --data-dir /home/conduit/data -m "$CONDUIT_MAX_CLIENTS" $bandwidth_flag -vv; then
        print_success "Container created"
    else
        print_error "Failed to create container"
        exit 1
    fi
    
    # Wait for startup
    sleep 3
    
    if ! is_conduit_running; then
        print_error "Conduit failed to start"
        print_info "Check logs: docker logs conduit"
        exit 1
    fi
    
    # Install monitoring script
    install_monitoring_script
    
    # Show results
    print_line
    print_success "Conduit installation complete!"
    echo ""
    show_status
    
    echo ""
    echo -e "  ${BOLD}${WHITE}Useful Commands${RESET}"
    print_line
    echo "  conduit status              - Show status and stats"
    echo "  conduit logs                - Live statistics"
    echo "  conduit peers               - Live country monitoring"
    echo "  docker logs conduit         - View all logs"
    echo "  docker restart conduit      - Restart container"
    echo ""
    
    echo -e "  ${GREEN}Thank you for helping users in censored regions!${RESET}"
    echo ""
}

#-------------------------------------------------------------------------------
# Uninstall
#-------------------------------------------------------------------------------

uninstall_conduit_quiet() {
    docker stop conduit 2>/dev/null || true
    docker rm conduit 2>/dev/null || true
    rm -f "$CONDUIT_MONITORING_SCRIPT"
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
    echo "  - Stop and remove the Conduit container"
    echo "  - Remove the monitoring script"
    echo ""
    echo -e "  ${CYAN}Your node identity will be preserved in Docker volume:${RESET}"
    echo "  $CONDUIT_VOLUME"
    echo ""
    
    if ! confirm "Uninstall Conduit?"; then
        return 0
    fi
    
    print_step "Stopping container"
    docker stop conduit 2>/dev/null || true
    print_success "Container stopped"
    
    print_step "Removing container"
    docker rm conduit 2>/dev/null || true
    print_success "Container removed"
    
    print_step "Removing monitoring script"
    rm -f "$CONDUIT_MONITORING_SCRIPT"
    print_success "Monitoring script removed"
    
    if confirm "Remove data volume (including node identity)?"; then
        docker volume rm "$CONDUIT_VOLUME" 2>/dev/null || true
        print_success "Data volume removed"
    else
        print_info "Data preserved in volume: $CONDUIT_VOLUME"
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
    if [[ "${current_bandwidth:-$DEFAULT_BANDWIDTH}" == "-1" ]]; then
        echo "  - Bandwidth: Unlimited"
    else
        echo "  - Bandwidth: ${current_bandwidth:-$DEFAULT_BANDWIDTH} Mbps"
    fi
    echo ""
    
    # Get new settings
    get_input "Max clients" "${current_max_clients:-$DEFAULT_MAX_CLIENTS}" max_clients
    get_input "Bandwidth (Mbps, -1 for unlimited)" "${current_bandwidth:-$DEFAULT_BANDWIDTH}" bandwidth
    
    # Validate
    if ! [[ "$max_clients" =~ ^[0-9]+$ ]] || [[ "$max_clients" -lt 1 ]]; then
        max_clients="${current_max_clients:-$DEFAULT_MAX_CLIENTS}"
    fi
    if ! [[ "$bandwidth" =~ ^-?[0-9]+$ ]]; then
        bandwidth="${current_bandwidth:-$DEFAULT_BANDWIDTH}"
    fi
    
    CONDUIT_MAX_CLIENTS="$max_clients"
    CONDUIT_BANDWIDTH="$bandwidth"
    
    # Save settings
    server_set "conduit_max_clients" "$max_clients"
    server_set "conduit_bandwidth" "$bandwidth"
    
    # Stop and remove container
    print_step "Stopping container"
    docker stop conduit 2>/dev/null || true
    docker rm conduit 2>/dev/null || true
    
    # Recreate container with new settings
    print_step "Creating container with new settings"
    
    local bandwidth_flag="-b ${CONDUIT_BANDWIDTH}"
    
    if docker run -d --name conduit \
        -v "$CONDUIT_VOLUME":/home/conduit/data \
        --restart unless-stopped \
        "$CONDUIT_IMAGE" \
        start --data-dir /home/conduit/data -m "$CONDUIT_MAX_CLIENTS" $bandwidth_flag -vv; then
        print_success "Container created with new settings"
    else
        print_error "Failed to create container"
        return 1
    fi
    
    # Wait and check
    sleep 3
    if is_conduit_running; then
        print_success "Conduit restarted with new settings"
    else
        print_error "Conduit failed to start"
        print_info "Check logs: docker logs conduit"
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
        echo "  4) View peers (country monitoring)"
        echo "  5) Reconfigure settings"
        echo "  6) Restart service"
        echo "  7) Uninstall Conduit"
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
                print_info "Showing last 50 log lines (Ctrl+C to exit)"
                docker logs --tail 50 conduit
                echo ""
                if confirm "Follow logs in real-time?"; then
                    docker logs -f conduit
                fi
                press_enter
                ;;
            4)
                if command -v conduit &>/dev/null; then
                    conduit peers
                else
                    print_warning "Monitoring script not installed"
                    print_info "Reinstall Conduit to get monitoring commands"
                fi
                press_enter
                ;;
            5)
                reconfigure_settings
                press_enter
                ;;
            6)
                print_step "Restarting Conduit"
                docker restart conduit
                sleep 2
                if is_conduit_running; then
                    print_success "Conduit restarted"
                else
                    print_error "Conduit failed to start"
                fi
                press_enter
                ;;
            7)
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
