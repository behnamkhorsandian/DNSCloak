#!/bin/bash
#===============================================================================
# Vany - DNSTT (DNS Tunnel) Functions
# Sourced by start.sh or install.sh - do not run directly
#===============================================================================

SERVICE_NAME="dnstt"
DNSTT_DIR="$VANY_DIR/dnstt"
DNSTT_PORT=5300
SOCKS_PORT=10800

#-------------------------------------------------------------------------------
# Checks
#-------------------------------------------------------------------------------

is_dnstt_installed() {
    [[ -f "$DNSTT_DIR/dnstt-server" ]] && systemctl is-active --quiet dnstt 2>/dev/null
}

#-------------------------------------------------------------------------------
# Download / Build
#-------------------------------------------------------------------------------

download_dnstt() {
    print_step "Installing dnstt-server"

    mkdir -p "$DNSTT_DIR"

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

    print_info "Installing Go 1.21..."

    local go_version="1.21.6"
    local go_url="https://go.dev/dl/go${go_version}.linux-${arch}.tar.gz"

    if curl -sfL "$go_url" -o "/tmp/go.tar.gz"; then
        rm -rf /usr/local/go
        tar -C /usr/local -xzf /tmp/go.tar.gz
        rm /tmp/go.tar.gz

        export PATH="/usr/local/go/bin:$PATH"
        export GOPATH="/tmp/gopath"
        export GOCACHE="/tmp/gocache"
        mkdir -p "$GOPATH" "$GOCACHE"

        print_info "Building dnstt from source..."

        if /usr/local/go/bin/go install www.bamsoftware.com/git/dnstt.git/dnstt-server@latest 2>&1; then
            if [[ -f "$GOPATH/bin/dnstt-server" ]]; then
                mv "$GOPATH/bin/dnstt-server" "$DNSTT_DIR/"
                chmod +x "$DNSTT_DIR/dnstt-server"
                rm -rf "$GOPATH" "$GOCACHE"
                print_success "Built dnstt-server from source"
                return 0
            fi
        fi

        print_info "Trying alternative build method..."
        apt-get install -y git 2>/dev/null || true

        rm -rf /tmp/dnstt-build
        if git clone https://www.bamsoftware.com/git/dnstt.git /tmp/dnstt-build 2>/dev/null; then
            cd /tmp/dnstt-build/dnstt-server
            if /usr/local/go/bin/go build -o "$DNSTT_DIR/dnstt-server" . 2>&1; then
                chmod +x "$DNSTT_DIR/dnstt-server"
                cd - >/dev/null
                rm -rf /tmp/dnstt-build "$GOPATH" "$GOCACHE"
                print_success "Built dnstt-server from source"
                return 0
            fi
            cd - >/dev/null
        fi
    fi

    print_error "Failed to build dnstt"
    return 1
}

#-------------------------------------------------------------------------------
# Keys
#-------------------------------------------------------------------------------

generate_dnstt_keys() {
    print_step "Generating encryption keys"

    if [[ -f "$DNSTT_DIR/server.key" ]]; then
        print_info "Keys already exist"
        return 0
    fi

    "$DNSTT_DIR/dnstt-server" -gen-key -privkey-file "$DNSTT_DIR/server.key" -pubkey-file "$DNSTT_DIR/server.pub"
    chmod 600 "$DNSTT_DIR/server.key"
    chmod 644 "$DNSTT_DIR/server.pub"

    print_success "Keys generated"
}

#-------------------------------------------------------------------------------
# DNS Verification
#-------------------------------------------------------------------------------

check_dnstt_dns_records() {
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

    local ns_ip
    ns_ip=$(dig +short "ns1.$domain" A 2>/dev/null | head -1)

    if [[ "$ns_ip" == "$server_ip" ]]; then
        print_success "ns1.$domain resolves correctly to $server_ip"
    else
        print_warning "ns1.$domain resolves to '$ns_ip' (expected $server_ip)"
        return 1
    fi

    local ns_record
    ns_record=$(dig +short "t.$domain" NS 2>/dev/null | head -1)

    if [[ "$ns_record" == "ns1.$domain." ]]; then
        print_success "t.$domain NS record is correct"
    else
        print_warning "t.$domain NS record shows '$ns_record' (expected ns1.$domain.)"
        return 1
    fi

    return 0
}

#-------------------------------------------------------------------------------
# Port Forwarding
#-------------------------------------------------------------------------------

setup_dnstt_port_forward() {
    print_step "Setting up port forwarding (53 -> $DNSTT_PORT)"

    if ! command -v iptables &>/dev/null; then
        apt-get update && apt-get install -y iptables
    fi

    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-port $DNSTT_PORT 2>/dev/null || true
    iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-port $DNSTT_PORT

    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save
    elif [[ -f /etc/iptables/rules.v4 ]]; then
        iptables-save > /etc/iptables/rules.v4
    fi

    print_success "Port 53 redirected to $DNSTT_PORT"
}

#-------------------------------------------------------------------------------
# Systemd Service
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
# SOCKS5 (Dante)
#-------------------------------------------------------------------------------

install_dnstt_socks_server() {
    print_step "Installing SOCKS5 server (Dante)"

    apt-get update
    apt-get install -y dante-server

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
# Non-interactive install (called by TUI wizard)
# Usage: install_dnstt_service <domain>
#-------------------------------------------------------------------------------

install_dnstt_service() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        print_error "Domain required"
        return 1
    fi

    if type bootstrap &>/dev/null; then
        bootstrap
    fi

    download_dnstt
    generate_dnstt_keys
    install_dnstt_socks_server
    create_dnstt_service "$domain"

    # Open firewall
    if type cloud_open_port &>/dev/null; then
        cloud_open_port 53 udp
    fi

    setup_dnstt_port_forward

    local server_ip
    server_ip=$(cloud_get_public_ip 2>/dev/null || server_get "ip")
    server_set "ip" "$server_ip" 2>/dev/null || true
    server_set "dnstt_domain" "$domain"
    server_set "dnstt_pubkey" "$(cat "$DNSTT_DIR/server.pub")"

    systemctl enable dnstt
    systemctl start dnstt

    sleep 2
    if systemctl is-active --quiet dnstt; then
        print_success "DNSTT is running"
    else
        print_error "DNSTT failed to start"
        journalctl -u dnstt -n 20 --no-pager 2>/dev/null || true
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Interactive install (standalone / CLI mode)
#-------------------------------------------------------------------------------

install_dnstt() {
    clear
    load_banner "dnstt" 2>/dev/null || true
    echo -e "  ${BOLD}${WHITE}DNS Tunnel Installation${RESET}"
    print_line
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

    echo ""
    echo -e "  ${BOLD}${WHITE}Domain Setup${RESET}"
    print_line
    echo ""
    echo "  DNSTT requires a domain where you can set NS records."
    echo "  The domain must NOT be proxied through Cloudflare."
    echo ""

    local domain=""
    while true; do
        get_input "Enter your domain (e.g., vany.sh)" "" domain

        if [[ -z "$domain" ]]; then
            print_error "Domain cannot be empty"
            continue
        fi

        domain=$(echo "$domain" | sed 's/^[^.]*\.//' | grep -E '\.' || echo "$domain")

        if check_dnstt_dns_records "$domain"; then
            break
        fi

        echo ""
        if confirm "DNS not ready. Try anyway (for testing)?"; then
            break
        fi
    done

    bootstrap

    download_dnstt
    generate_dnstt_keys
    install_dnstt_socks_server
    create_dnstt_service "$domain"

    print_step "Configuring firewall"
    cloud_open_port 53 udp

    setup_dnstt_port_forward

    server_set "ip" "$(cloud_get_public_ip)"
    server_set "dnstt_domain" "$domain"
    server_set "dnstt_pubkey" "$(cat "$DNSTT_DIR/server.pub")"

    print_step "Starting DNSTT service"
    systemctl enable dnstt
    systemctl start dnstt

    sleep 2
    if systemctl is-active --quiet dnstt; then
        print_success "DNSTT is running"
    else
        print_error "DNSTT failed to start"
        journalctl -u dnstt -n 20 --no-pager
        return 1
    fi

    show_dnstt_info

    echo ""
    if confirm "Open management menu?"; then
        manage_dnstt
    fi
}

#-------------------------------------------------------------------------------
# Info
#-------------------------------------------------------------------------------

show_dnstt_info() {
    local domain pubkey
    domain=$(server_get "dnstt_domain")
    pubkey=$(server_get "dnstt_pubkey")

    local setup_url="https://vany.sh/dnstt/client?key=${pubkey}&domain=t.${domain}"

    echo ""
    echo -e "  ${BOLD}${WHITE}DNSTT Connection Info${RESET}"
    print_line
    echo ""
    echo -e "  ${BOLD}Domain:${RESET} t.$domain"
    echo -e "  ${BOLD}Public Key:${RESET}"
    echo -e "  ${GREEN}$pubkey${RESET}"
    echo ""
    echo -e "  ${BOLD}${YELLOW}Easy Client Setup${RESET}"
    print_line
    echo ""
    echo -e "  ${CYAN}$setup_url${RESET}"
    echo ""
    echo -e "  ${BOLD}${WHITE}Manual Client Commands${RESET}"
    print_line
    echo ""
    echo -e "  ${CYAN}Linux/macOS:${RESET}"
    echo "  ./dnstt-client -udp 8.8.8.8:53 -pubkey $pubkey t.$domain 127.0.0.1:1080"
    echo ""
    echo -e "  ${GREEN}Windows:${RESET}"
    echo "  .\\dnstt-client.exe -udp 8.8.8.8:53 -pubkey $pubkey t.$domain 127.0.0.1:1080"
    echo ""
    echo "  Then configure apps to use SOCKS5 proxy: 127.0.0.1:1080"
    echo ""
}

#-------------------------------------------------------------------------------
# Helpers
#-------------------------------------------------------------------------------

regenerate_dnstt_keys() {
    print_warning "This will invalidate all existing client configs!"

    if ! confirm "Regenerate keys?"; then
        return 0
    fi

    rm -f "$DNSTT_DIR/server.key" "$DNSTT_DIR/server.pub"
    generate_dnstt_keys

    server_set "dnstt_pubkey" "$(cat "$DNSTT_DIR/server.pub")"
    systemctl restart dnstt

    print_success "Keys regenerated"
    show_dnstt_info
}

test_dnstt_dns() {
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

    if ! is_dnstt_installed && [[ ! -d "$DNSTT_DIR" ]]; then
        print_error "DNSTT is not installed"
        return 1
    fi

    if ! confirm "Remove DNSTT and all related services?"; then
        return 0
    fi

    systemctl stop dnstt 2>/dev/null || true
    systemctl disable dnstt 2>/dev/null || true
    systemctl stop danted 2>/dev/null || true
    systemctl disable danted 2>/dev/null || true

    rm -rf "$DNSTT_DIR"
    rm -f /etc/systemd/system/dnstt.service
    systemctl daemon-reload

    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-port $DNSTT_PORT 2>/dev/null || true

    server_set "dnstt_domain" ""
    server_set "dnstt_pubkey" ""

    print_success "DNSTT uninstalled"
}

#-------------------------------------------------------------------------------
# Manage (Menu)
#-------------------------------------------------------------------------------

manage_dnstt() {
    while true; do
        clear
        load_banner "dnstt" 2>/dev/null || true
        echo -e "  ${BOLD}${WHITE}DNSTT Management${RESET}"
        print_line
        echo ""
        echo "  1) Show connection info"
        echo "  2) Regenerate keys"
        echo "  3) Service status"
        echo "  4) View logs"
        echo "  5) Test DNS"
        echo "  6) Uninstall"
        echo "  0) Back"
        echo ""

        local choice
        get_input "Select [0-6]" "0" choice

        case "$choice" in
            1) show_dnstt_info; press_enter ;;
            2) regenerate_dnstt_keys; press_enter ;;
            3) systemctl status dnstt --no-pager; press_enter ;;
            4) journalctl -u dnstt -n 50 --no-pager; press_enter ;;
            5) test_dnstt_dns; press_enter ;;
            6) uninstall_dnstt; return 0 ;;
            0|"") return 0 ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}
