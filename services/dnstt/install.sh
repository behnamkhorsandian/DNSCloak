#!/bin/bash
#===============================================================================
# DNSCloak - DNSTT (DNS Tunnel) Service Installer
# https://github.com/behnamkhorsandian/DNSCloak
#
# Usage: curl -sSL dnstt.dnscloak.net | sudo bash
#
# Requires:
#   - Domain with ability to set NS records
#   - NOT behind Cloudflare proxy (needs direct DNS)
#   - Port 53/UDP open
#===============================================================================

# Cleanup old cached files for fresh install
rm -rf /tmp/dnscloak-lib /tmp/dnscloak* 2>/dev/null || true

# Download and source libraries
LIB_DIR="/tmp/dnscloak-lib"
mkdir -p "$LIB_DIR"
GITHUB_RAW="https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main"

echo "Downloading libraries..."

# Download each library with error checking
for lib in common.sh cloud.sh bootstrap.sh; do
    if ! curl -sfL "$GITHUB_RAW/lib/$lib" -o "$LIB_DIR/$lib"; then
        echo "ERROR: Failed to download $lib"
        exit 1
    fi
done

# Source libraries with error checking
for lib in common.sh cloud.sh bootstrap.sh; do
    if [[ ! -f "$LIB_DIR/$lib" ]]; then
        echo "ERROR: Library not found: $LIB_DIR/$lib"
        exit 1
    fi
    # shellcheck source=/dev/null
    . "$LIB_DIR/$lib"
done

set -e

#-------------------------------------------------------------------------------
# DNSTT Configuration
#-------------------------------------------------------------------------------

SERVICE_NAME="dnstt"
DNSTT_DIR="$DNSCLOAK_DIR/dnstt"
DNSTT_PORT=5300      # Internal port (53 redirected here)
SOCKS_PORT=10800     # SOCKS5 proxy port for forwarded traffic
DNSTT_VERSION="0.20220315.0"

#-------------------------------------------------------------------------------
# Installation Check
#-------------------------------------------------------------------------------

is_dnstt_installed() {
    [[ -f "$DNSTT_DIR/dnstt-server" ]] && systemctl is-active --quiet dnstt 2>/dev/null
}

#-------------------------------------------------------------------------------
# Download DNSTT Binary
#-------------------------------------------------------------------------------

download_dnstt() {
    print_step "Installing dnstt-server"
    
    mkdir -p "$DNSTT_DIR"
    
    # Method 1: Try to install via Go
    if command -v go &>/dev/null || install_go; then
        print_info "Building dnstt from source..."
        
        export GOPATH="/tmp/go"
        export PATH="$PATH:/usr/local/go/bin:$GOPATH/bin"
        mkdir -p "$GOPATH"
        
        # Install dnstt
        if go install www.bamsoftware.com/git/dnstt.git/dnstt-server@latest 2>/dev/null; then
            mv "$GOPATH/bin/dnstt-server" "$DNSTT_DIR/"
            chmod +x "$DNSTT_DIR/dnstt-server"
            rm -rf "$GOPATH"
            print_success "Built dnstt-server from source"
            return 0
        fi
    fi
    
    # Method 2: Download pre-built binary from GitHub mirror
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *)
            print_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac
    
    # Try GitHub releases (community builds)
    local urls=(
        "https://github.com/nicholasmhughes/dnstt/releases/latest/download/dnstt-server-linux-${arch}"
        "https://github.com/nicholasmhughes/dnstt/releases/download/v0.20220315.0/dnstt-server-linux-${arch}"
    )
    
    for url in "${urls[@]}"; do
        if curl -sfL "$url" -o "$DNSTT_DIR/dnstt-server" 2>/dev/null; then
            chmod +x "$DNSTT_DIR/dnstt-server"
            print_success "Downloaded dnstt-server"
            return 0
        fi
    done
    
    print_error "Failed to download dnstt. Please install Go and retry."
    echo ""
    echo "  Manual installation:"
    echo "  1. Install Go: apt install golang-go"
    echo "  2. Run: go install www.bamsoftware.com/git/dnstt.git/dnstt-server@latest"
    echo "  3. Copy to: $DNSTT_DIR/dnstt-server"
    return 1
}

install_go() {
    print_info "Installing Go..."
    apt-get update
    apt-get install -y golang-go
    return $?
}

#-------------------------------------------------------------------------------
# Generate Keys
#-------------------------------------------------------------------------------

generate_dnstt_keys() {
    print_step "Generating encryption keys"
    
    if [[ -f "$DNSTT_DIR/server.key" ]]; then
        print_info "Keys already exist"
        return 0
    fi
    
    # dnstt-server -gen-key generates keypair
    "$DNSTT_DIR/dnstt-server" -gen-key -privkey-file "$DNSTT_DIR/server.key" -pubkey-file "$DNSTT_DIR/server.pub"
    chmod 600 "$DNSTT_DIR/server.key"
    chmod 644 "$DNSTT_DIR/server.pub"
    
    print_success "Keys generated"
}

#-------------------------------------------------------------------------------
# DNS Verification
#-------------------------------------------------------------------------------

check_dns_records() {
    local domain="$1"
    local server_ip
    server_ip=$(cloud_get_public_ip)
    
    print_step "Checking DNS records for $domain"
    
    echo ""
    echo -e "  ${BOLD}${WHITE}Required DNS Setup:${RESET}"
    print_line
    echo ""
    echo "  1. A Record (Nameserver):"
    echo -e "     Type: ${CYAN}A${RESET}"
    echo -e "     Name: ${CYAN}ns1${RESET}"
    echo -e "     Value: ${GREEN}$server_ip${RESET}"
    echo -e "     Proxy: ${RED}OFF (DNS only / grey cloud)${RESET}"
    echo ""
    echo "  2. NS Record (Tunnel subdomain):"
    echo -e "     Type: ${CYAN}NS${RESET}"
    echo -e "     Name: ${CYAN}t${RESET}"
    echo -e "     Value: ${GREEN}ns1.$domain${RESET}"
    echo ""
    
    # Check if ns1 resolves to server IP
    local ns_ip
    ns_ip=$(dig +short "ns1.$domain" A 2>/dev/null | head -1)
    
    if [[ "$ns_ip" == "$server_ip" ]]; then
        print_success "ns1.$domain resolves correctly to $server_ip"
    else
        print_warning "ns1.$domain resolves to '$ns_ip' (expected $server_ip)"
        echo ""
        echo "  Please add the A record and wait for DNS propagation."
        return 1
    fi
    
    # Check NS record
    local ns_record
    ns_record=$(dig +short "t.$domain" NS 2>/dev/null | head -1)
    
    if [[ "$ns_record" == "ns1.$domain." ]]; then
        print_success "t.$domain NS record is correct"
    else
        print_warning "t.$domain NS record shows '$ns_record' (expected ns1.$domain.)"
        echo ""
        echo "  Please add the NS record and wait for DNS propagation."
        return 1
    fi
    
    return 0
}

#-------------------------------------------------------------------------------
# Setup Port Forwarding
#-------------------------------------------------------------------------------

setup_port_forward() {
    print_step "Setting up port forwarding (53 -> $DNSTT_PORT)"
    
    # Install iptables if needed
    if ! command -v iptables &>/dev/null; then
        apt-get update && apt-get install -y iptables
    fi
    
    # Remove existing rules for port 53
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-port $DNSTT_PORT 2>/dev/null || true
    
    # Add redirect rule
    iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-port $DNSTT_PORT
    
    # Save rules
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save
    elif [[ -f /etc/iptables/rules.v4 ]]; then
        iptables-save > /etc/iptables/rules.v4
    fi
    
    print_success "Port 53 redirected to $DNSTT_PORT"
}

#-------------------------------------------------------------------------------
# Create Systemd Service
#-------------------------------------------------------------------------------

create_dnstt_service() {
    local domain="$1"
    
    print_step "Creating systemd service"
    
    cat > /etc/systemd/system/dnstt.service <<EOF
[Unit]
Description=DNStt DNS Tunnel Server
After=network.target

[Service]
Type=simple
ExecStart=$DNSTT_DIR/dnstt-server \\
    -udp :$DNSTT_PORT \\
    -privkey-file $DNSTT_DIR/server.key \\
    t.$domain \\
    127.0.0.1:$SOCKS_PORT
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    print_success "Service created"
}

#-------------------------------------------------------------------------------
# Install SOCKS5 Server (Dante)
#-------------------------------------------------------------------------------

install_socks_server() {
    print_step "Installing SOCKS5 server (Dante)"
    
    apt-get update
    apt-get install -y dante-server
    
    # Configure Dante
    cat > /etc/danted.conf <<EOF
logoutput: syslog
internal: 127.0.0.1 port = $SOCKS_PORT
external: eth0
clientmethod: none
socksmethod: none
user.privileged: root
user.notprivileged: nobody

client pass {
    from: 127.0.0.1/32 to: 0.0.0.0/0
    log: connect disconnect
}

socks pass {
    from: 127.0.0.1/32 to: 0.0.0.0/0
    log: connect disconnect
}
EOF
    
    systemctl enable danted
    systemctl restart danted
    
    print_success "SOCKS5 server configured on port $SOCKS_PORT"
}

#-------------------------------------------------------------------------------
# Install DNSTT
#-------------------------------------------------------------------------------

install_dnstt() {
    clear
    load_banner "dnstt" 2>/dev/null || echo -e "\n${BOLD}${CYAN}=== DNSCloak DNSTT ===${RESET}\n"
    
    # Check root
    check_root
    
    # Check if already installed
    if is_dnstt_installed; then
        print_warning "DNSTT is already installed"
        if ! confirm "Reinstall?"; then
            show_dnstt_menu
            return 0
        fi
    fi
    
    # Warn about speed
    echo ""
    echo -e "  ${YELLOW}WARNING: DNS Tunnel is very slow!${RESET}"
    print_line
    echo ""
    echo "  Speed: 50-150 kbps (vs 50+ Mbps for Reality)"
    echo "  Latency: 500ms+ (very noticeable)"
    echo "  Use case: Emergency only, when all else is blocked"
    echo ""
    
    if ! confirm "Continue with DNSTT setup?"; then
        return 0
    fi
    
    # Get domain
    echo ""
    echo -e "  ${BOLD}${WHITE}Domain Setup${RESET}"
    print_line
    echo ""
    echo "  DNSTT requires a domain where you can set NS records."
    echo "  The domain must NOT be proxied through Cloudflare."
    echo ""
    
    local domain=""
    while true; do
        get_input "Enter your domain (e.g., dnscloak.net)" "" domain
        
        if [[ -z "$domain" ]]; then
            print_error "Domain cannot be empty"
            continue
        fi
        
        # Remove any subdomain prefix - we need the base domain
        domain=$(echo "$domain" | sed 's/^[^.]*\.//' | grep -E '\.' || echo "$domain")
        
        if check_dns_records "$domain"; then
            break
        fi
        
        echo ""
        if confirm "DNS not ready. Try anyway (for testing)?"; then
            break
        fi
    done
    
    # Bootstrap
    print_step "Setting up prerequisites"
    bootstrap
    create_directories
    cloud_detect
    
    # Download DNSTT
    download_dnstt
    
    # Generate keys
    generate_dnstt_keys
    
    # Install SOCKS server
    install_socks_server
    
    # Create service
    create_dnstt_service "$domain"
    
    # Open firewall
    print_step "Configuring firewall"
    cloud_open_port 53 udp
    
    # Setup port forwarding
    setup_port_forward
    
    # Save config
    server_set "ip" "$(cloud_get_public_ip)"
    server_set "dnstt_domain" "$domain"
    server_set "dnstt_pubkey" "$(cat "$DNSTT_DIR/server.pub")"
    
    # Start service
    print_step "Starting DNSTT service"
    systemctl enable dnstt
    systemctl start dnstt
    
    sleep 2
    if systemctl is-active --quiet dnstt; then
        print_success "DNSTT is running"
    else
        print_error "DNSTT failed to start"
        journalctl -u dnstt -n 20 --no-pager
        exit 1
    fi
    
    # Show connection info
    show_dnstt_info
    show_dnstt_menu
}

#-------------------------------------------------------------------------------
# Show Connection Info
#-------------------------------------------------------------------------------

show_dnstt_info() {
    local domain pubkey server_ip
    domain=$(server_get "dnstt_domain")
    pubkey=$(server_get "dnstt_pubkey")
    server_ip=$(server_get "ip")
    
    clear
    load_banner "dnstt" 2>/dev/null || echo -e "\n${BOLD}${CYAN}=== DNSCloak DNSTT ===${RESET}\n"
    
    echo ""
    echo -e "  ${BOLD}${WHITE}DNSTT Connection Info${RESET}"
    print_line
    echo ""
    echo -e "  ${BOLD}Domain:${RESET} t.$domain"
    echo -e "  ${BOLD}Public Key:${RESET}"
    echo -e "  ${GREEN}$pubkey${RESET}"
    echo ""
    echo -e "  ${BOLD}${WHITE}Client Commands${RESET}"
    print_line
    echo ""
    echo -e "  ${CYAN}Linux/macOS:${RESET}"
    echo "  ./dnstt-client -udp 8.8.8.8:53 -pubkey $pubkey t.$domain 127.0.0.1:1080"
    echo ""
    echo -e "  ${GREEN}Windows:${RESET}"
    echo "  .\\dnstt-client.exe -udp 8.8.8.8:53 -pubkey $pubkey t.$domain 127.0.0.1:1080"
    echo ""
    echo -e "  ${BOLD}${WHITE}Download Client${RESET}"
    print_line
    echo "  https://www.bamsoftware.com/software/dnstt/"
    echo ""
    echo -e "  ${BOLD}${WHITE}After Running Client${RESET}"
    print_line
    echo "  Configure apps to use SOCKS5 proxy:"
    echo "  Server: 127.0.0.1"
    echo "  Port: 1080"
    echo ""
    echo -e "  ${DIM}Note: DNS tunnel is slow (50-150 kbps). For emergency use only.${RESET}"
    echo ""
}

#-------------------------------------------------------------------------------
# Menu
#-------------------------------------------------------------------------------

show_dnstt_menu() {
    while true; do
        echo ""
        echo -e "  ${BOLD}${WHITE}DNSTT Management${RESET}"
        print_line
        echo ""
        echo "  1) Show connection info"
        echo "  2) Regenerate keys"
        echo "  3) Service status"
        echo "  4) View logs"
        echo "  5) Test DNS"
        echo "  6) Uninstall"
        echo "  0) Exit"
        echo ""
        
        local choice
        get_input "Select [0-6]" "0" choice
        
        case "$choice" in
            1) show_dnstt_info ;;
            2) regenerate_keys ;;
            3) systemctl status dnstt --no-pager ;;
            4) journalctl -u dnstt -n 50 --no-pager ;;
            5) test_dns ;;
            6) uninstall_dnstt; break ;;
            0) break ;;
            *) print_error "Invalid option" ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# Regenerate Keys
#-------------------------------------------------------------------------------

regenerate_keys() {
    print_warning "This will invalidate all existing client configs!"
    
    if ! confirm "Regenerate keys?"; then
        return 0
    fi
    
    rm -f "$DNSTT_DIR/server.key" "$DNSTT_DIR/server.pub"
    generate_dnstt_keys
    
    # Update saved pubkey
    server_set "dnstt_pubkey" "$(cat "$DNSTT_DIR/server.pub")"
    
    # Restart service
    systemctl restart dnstt
    
    print_success "Keys regenerated"
    show_dnstt_info
}

#-------------------------------------------------------------------------------
# Test DNS
#-------------------------------------------------------------------------------

test_dns() {
    local domain
    domain=$(server_get "dnstt_domain")
    
    echo ""
    print_step "Testing DNS resolution"
    echo ""
    
    echo "Testing ns1.$domain:"
    dig +short "ns1.$domain" A
    
    echo ""
    echo "Testing t.$domain NS record:"
    dig +short "t.$domain" NS
    
    echo ""
    echo "Testing direct query to server:"
    dig @localhost -p $DNSTT_PORT "test.t.$domain" TXT +short 2>/dev/null || echo "(No response - normal if no client connected)"
    
    echo ""
}

#-------------------------------------------------------------------------------
# Uninstall
#-------------------------------------------------------------------------------

uninstall_dnstt() {
    echo ""
    echo -e "  ${BOLD}${RED}Uninstall DNSTT${RESET}"
    print_line
    echo ""
    echo "  This will remove:"
    echo "  - DNSTT server and keys"
    echo "  - Dante SOCKS server"
    echo "  - Port forwarding rules"
    echo ""
    
    if ! confirm "Continue?"; then
        return 0
    fi
    
    # Stop services
    systemctl stop dnstt 2>/dev/null || true
    systemctl disable dnstt 2>/dev/null || true
    systemctl stop danted 2>/dev/null || true
    systemctl disable danted 2>/dev/null || true
    
    # Remove files
    rm -rf "$DNSTT_DIR"
    rm -f /etc/systemd/system/dnstt.service
    systemctl daemon-reload
    
    # Remove port forwarding
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-port $DNSTT_PORT 2>/dev/null || true
    
    # Clear from users.json
    server_set "dnstt_domain" ""
    server_set "dnstt_pubkey" ""
    
    print_success "DNSTT uninstalled"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    if is_dnstt_installed; then
        show_dnstt_menu
    else
        install_dnstt
    fi
}

main "$@"
