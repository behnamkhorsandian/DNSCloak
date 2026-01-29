#!/bin/bash
#===============================================================================
# DNSCloak - Bootstrap Script
# First-time VM setup: updates, prerequisites, Xray installation
# https://github.com/behnamkhorsandian/DNSCloak
#===============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/cloud.sh"

#-------------------------------------------------------------------------------
# Bootstrap Flag
#-------------------------------------------------------------------------------

BOOTSTRAP_FLAG="$DNSCLOAK_DIR/.bootstrapped"

is_bootstrapped() {
    [[ -f "$BOOTSTRAP_FLAG" ]]
}

mark_bootstrapped() {
    touch "$BOOTSTRAP_FLAG"
}

#-------------------------------------------------------------------------------
# System Update
#-------------------------------------------------------------------------------

wait_for_apt_lock() {
    local max_wait=60
    local waited=0
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
        if [[ $waited -eq 0 ]]; then
            print_info "Waiting for other apt process to finish..."
        fi
        sleep 2
        ((waited+=2))
        if [[ $waited -ge $max_wait ]]; then
            print_warning "Apt lock timeout, attempting to continue..."
            break
        fi
    done
}

system_update() {
    print_step "Updating system packages"
    
    export DEBIAN_FRONTEND=noninteractive
    
    # Wait for any existing apt processes
    wait_for_apt_lock
    
    apt-get update -qq
    apt-get upgrade -y -qq
    
    print_success "System updated"
}

#-------------------------------------------------------------------------------
# Install Prerequisites
#-------------------------------------------------------------------------------

install_prerequisites() {
    print_step "Installing prerequisites"
    
    local packages=(
        curl
        wget
        jq
        qrencode
        openssl
        xxd
        ca-certificates
        gnupg
        lsb-release
        unzip
    )
    
    apt-get install -y -qq "${packages[@]}"
    
    print_success "Prerequisites installed"
}

#-------------------------------------------------------------------------------
# Install Docker
#-------------------------------------------------------------------------------

install_docker() {
    # Check if Docker is already installed
    if command -v docker &>/dev/null; then
        local docker_ver
        docker_ver=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
        print_info "Docker $docker_ver already installed"
        return 0
    fi
    
    print_step "Installing Docker"
    
    export DEBIAN_FRONTEND=noninteractive
    wait_for_apt_lock
    
    # Install dependencies
    apt-get install -y -qq \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    
    # Set up Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list >/dev/null
    
    # Install Docker Engine
    wait_for_apt_lock
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Verify installation
    if docker --version &>/dev/null; then
        local docker_ver
        docker_ver=$(docker --version | awk '{print $3}' | tr -d ',')
        print_success "Docker $docker_ver installed"
    else
        print_error "Docker installation failed"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Network Optimization
#-------------------------------------------------------------------------------

configure_sysctl() {
    print_step "Configuring network optimizations"
    
    cat > /etc/sysctl.d/99-dnscloak.conf <<EOF
# DNSCloak network optimizations

# TCP keepalive
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# TCP performance
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3

# Connection tracking
net.netfilter.nf_conntrack_max = 131072

# IP forwarding (for WireGuard)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Buffer sizes
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF

    sysctl -p /etc/sysctl.d/99-dnscloak.conf 2>/dev/null || true
    
    print_success "Network optimized"
}

#-------------------------------------------------------------------------------
# Directory Structure
#-------------------------------------------------------------------------------

create_directories() {
    print_step "Creating directory structure"
    
    mkdir -p "$DNSCLOAK_DIR"/{xray,mtp,wg,dnstt,certs}
    chmod 700 "$DNSCLOAK_DIR"
    
    print_success "Directories created at $DNSCLOAK_DIR"
}

#-------------------------------------------------------------------------------
# Install Xray-core
#-------------------------------------------------------------------------------

XRAY_VERSION="1.8.24"
XRAY_BIN="/usr/local/bin/xray"

install_xray() {
    if [[ -f "$XRAY_BIN" ]]; then
        local current_ver
        current_ver=$("$XRAY_BIN" version 2>/dev/null | head -1 | awk '{print $2}')
        if [[ "$current_ver" == "$XRAY_VERSION" ]]; then
            print_info "Xray $XRAY_VERSION already installed"
            return 0
        fi
    fi
    
    print_step "Installing Xray-core v$XRAY_VERSION"
    
    local arch
    arch=$(get_arch)
    local url="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-${arch}.zip"
    
    local tmp_dir
    tmp_dir=$(mktemp -d)
    
    curl -sL "$url" -o "$tmp_dir/xray.zip"
    unzip -q "$tmp_dir/xray.zip" -d "$tmp_dir"
    
    mv "$tmp_dir/xray" "$XRAY_BIN"
    chmod +x "$XRAY_BIN"
    
    # Install geoip and geosite
    mv "$tmp_dir/geoip.dat" "$DNSCLOAK_DIR/xray/" 2>/dev/null || true
    mv "$tmp_dir/geosite.dat" "$DNSCLOAK_DIR/xray/" 2>/dev/null || true
    
    rm -rf "$tmp_dir"
    
    # Create systemd service
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$XRAY_BIN run -config $DNSCLOAK_DIR/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    
    print_success "Xray v$XRAY_VERSION installed"
}

#-------------------------------------------------------------------------------
# Initialize Empty Xray Config
#-------------------------------------------------------------------------------

init_xray_config() {
    local config="$DNSCLOAK_DIR/xray/config.json"
    
    if [[ -f "$config" ]]; then
        return 0
    fi
    
    print_step "Initializing Xray configuration"
    
    cat > "$config" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "$DNSCLOAK_DIR/xray/access.log",
    "error": "$DNSCLOAK_DIR/xray/error.log"
  },
  "inbounds": [],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
    
    chmod 600 "$config"
    print_success "Xray config initialized"
}

#-------------------------------------------------------------------------------
# Install DNSCloak CLI
#-------------------------------------------------------------------------------

install_cli() {
    print_step "Installing dnscloak CLI"
    
    local cli_url="${GITHUB_RAW}/cli/dnscloak.sh"
    local lib_dir="$DNSCLOAK_DIR/lib"
    
    # Download CLI
    curl -sL "$cli_url" -o "$DNSCLOAK_BIN"
    chmod +x "$DNSCLOAK_BIN"
    
    # Download libraries for CLI use
    mkdir -p "$lib_dir"
    curl -sL "${GITHUB_RAW}/lib/common.sh" -o "$lib_dir/common.sh"
    curl -sL "${GITHUB_RAW}/lib/cloud.sh" -o "$lib_dir/cloud.sh"
    curl -sL "${GITHUB_RAW}/lib/xray.sh" -o "$lib_dir/xray.sh"
    chmod 600 "$lib_dir"/*.sh
    
    print_success "dnscloak CLI installed"
}

#-------------------------------------------------------------------------------
# Cloud Detection and Firewall
#-------------------------------------------------------------------------------

setup_cloud() {
    print_step "Detecting cloud provider"
    
    cloud_detect
    
    if [[ "$CLOUD_PROVIDER" != "unknown" && -n "$CLOUD_PROVIDER" ]]; then
        local region_info=""
        [[ -n "$CLOUD_REGION" ]] && region_info=" ($CLOUD_REGION)"
        print_success "Detected: $CLOUD_PROVIDER$region_info"
    else
        CLOUD_PROVIDER="unknown"
        print_info "Unknown provider, using local firewall"
    fi
    
    # Get and store public IP
    local ip
    ip=$(cloud_get_public_ip)
    
    # Validate IP before storing
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        server_set "ip" "$ip"
        server_set "provider" "$CLOUD_PROVIDER"
        print_success "Public IP: $ip"
    else
        print_warning "Could not determine public IP"
    fi
    
    # Configure firewall
    print_step "Configuring firewall"
    cloud_configure_firewall
    print_success "Firewall configured"
}

#-------------------------------------------------------------------------------
# Main Bootstrap Function
#-------------------------------------------------------------------------------

bootstrap() {
    print_banner
    echo -e "  ${BOLD}${WHITE}First-Time Setup${RESET}"
    print_line
    echo ""
    
    check_root
    check_os
    
    if is_bootstrapped; then
        print_info "System already bootstrapped"
        # Still run cloud detection in case IP changed
        setup_cloud
        return 0
    fi
    
    print_info "Setting up DNSCloak on $PRETTY_NAME"
    echo ""
    
    system_update
    install_prerequisites
    configure_sysctl
    create_directories
    install_xray
    init_xray_config
    install_cli
    setup_cloud
    
    # Initialize users database
    users_init
    
    mark_bootstrapped
    
    print_line
    print_success "Bootstrap complete!"
    echo ""
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bootstrap
fi
