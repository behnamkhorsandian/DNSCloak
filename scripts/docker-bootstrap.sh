#!/bin/bash
#===============================================================================
# Vany - Docker Bootstrap
# First-time VM setup: Docker, prerequisites, directory structure, state file
# https://github.com/behnamkhorsandian/Vanysh
#===============================================================================

set -e

VANY_DIR="/opt/vany"
STATE_FILE="$VANY_DIR/state.json"
USERS_FILE="$VANY_DIR/users.json"
BOOTSTRAP_FLAG="$VANY_DIR/.bootstrapped"
GITHUB_RAW="https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main"

#-------------------------------------------------------------------------------
# Colors
#-------------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

print_step()    { echo -e "  ${CYAN}> ${RESET}$1"; }
print_success() { echo -e "  ${GREEN}* ${RESET}$1"; }
print_error()   { echo -e "  ${RED}! ${RESET}$1"; }
print_info()    { echo -e "  ${DIM}  $1${RESET}"; }
print_warning() { echo -e "  ${YELLOW}~ ${RESET}$1"; }

#-------------------------------------------------------------------------------
# Pre-checks
#-------------------------------------------------------------------------------

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Unsupported OS (no /etc/os-release)"
        exit 1
    fi
    source /etc/os-release
    case "$ID" in
        ubuntu|debian) ;;
        *)
            print_warning "Untested OS: $ID. Proceeding anyway..."
            ;;
    esac
}

#-------------------------------------------------------------------------------
# Apt helpers
#-------------------------------------------------------------------------------

wait_for_apt_lock() {
    local max_wait=60 waited=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
        [[ $waited -eq 0 ]] && print_info "Waiting for apt lock..."
        sleep 2
        ((waited+=2))
        [[ $waited -ge $max_wait ]] && break
    done
}

#-------------------------------------------------------------------------------
# System Update
#-------------------------------------------------------------------------------

system_update() {
    print_step "Updating system packages"
    export DEBIAN_FRONTEND=noninteractive
    wait_for_apt_lock
    apt-get update -qq
    apt-get upgrade -y -qq
    print_success "System updated"
}

#-------------------------------------------------------------------------------
# Prerequisites
#-------------------------------------------------------------------------------

install_prerequisites() {
    print_step "Installing prerequisites"
    local packages=(curl wget jq qrencode openssl xxd ca-certificates gnupg lsb-release unzip iptables)
    apt-get install -y -qq "${packages[@]}"
    print_success "Prerequisites installed"
}

#-------------------------------------------------------------------------------
# Docker Installation
#-------------------------------------------------------------------------------

install_docker() {
    if command -v docker &>/dev/null; then
        local ver
        ver=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
        print_info "Docker $ver already installed"
        return 0
    fi

    print_step "Installing Docker"
    export DEBIAN_FRONTEND=noninteractive
    wait_for_apt_lock

    apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release

    mkdir -p /etc/apt/keyrings
    # Detect distro: use debian for Debian, ubuntu for Ubuntu
    local docker_distro
    docker_distro=$(. /etc/os-release && echo "$ID")
    [[ "$docker_distro" != "ubuntu" && "$docker_distro" != "debian" ]] && docker_distro="debian"

    curl -fsSL "https://download.docker.com/linux/${docker_distro}/gpg" | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${docker_distro} $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list >/dev/null

    wait_for_apt_lock
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin

    systemctl start docker
    systemctl enable docker

    if docker --version &>/dev/null; then
        local ver
        ver=$(docker --version | awk '{print $3}' | tr -d ',')
        print_success "Docker $ver installed"
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

    cat > /etc/sysctl.d/99-vany.conf <<'EOF'
# Vany network optimizations
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF

    sysctl -p /etc/sysctl.d/99-vany.conf 2>/dev/null || true
    print_success "Network optimized (BBR, TCP FastOpen, IP forwarding)"
}

#-------------------------------------------------------------------------------
# Directory Structure
#-------------------------------------------------------------------------------

create_directories() {
    print_step "Creating directory structure"
    mkdir -p "$VANY_DIR"/{xray,wg,dnstt,conduit,sos,certs}
    chmod 700 "$VANY_DIR"
    print_success "Directories created at $VANY_DIR"
}

#-------------------------------------------------------------------------------
# Cloud Detection
#-------------------------------------------------------------------------------

detect_cloud_provider() {
    local provider="unknown"
    local region=""

    # GCP
    if curl -sf -m 2 -H "Metadata-Flavor: Google" \
        "http://metadata.google.internal/computeMetadata/v1/project/project-id" >/dev/null 2>&1; then
        provider="gcp"
        region=$(curl -sf -m 2 -H "Metadata-Flavor: Google" \
            "http://metadata.google.internal/computeMetadata/v1/instance/zone" 2>/dev/null | awk -F/ '{print $NF}')
    # AWS
    elif TOKEN=$(curl -sf -m 2 -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null) && [[ -n "$TOKEN" ]]; then
        provider="aws"
        region=$(curl -sf -m 2 -H "X-aws-ec2-metadata-token: $TOKEN" \
            "http://169.254.169.254/latest/meta-data/placement/availability-zone" 2>/dev/null)
    # Azure
    elif curl -sf -m 2 -H "Metadata: true" \
        "http://169.254.169.254/metadata/instance?api-version=2021-02-01" >/dev/null 2>&1; then
        provider="azure"
        region=$(curl -sf -m 2 -H "Metadata: true" \
            "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text" 2>/dev/null)
    # DigitalOcean
    elif curl -sf -m 2 "http://169.254.169.254/metadata/v1/id" >/dev/null 2>&1; then
        provider="digitalocean"
        region=$(curl -sf -m 2 "http://169.254.169.254/metadata/v1/region" 2>/dev/null)
    # Vultr
    elif curl -sf -m 2 "http://169.254.169.254/v1/location/region" >/dev/null 2>&1; then
        provider="vultr"
        region=$(curl -sf -m 2 "http://169.254.169.254/v1/location/region" 2>/dev/null)
    # Hetzner
    elif curl -sf -m 2 "http://169.254.169.254/hetzner/v1/metadata" >/dev/null 2>&1; then
        provider="hetzner"
        region=$(curl -sf -m 2 "http://169.254.169.254/hetzner/v1/metadata/availability-zone" 2>/dev/null)
    # Oracle
    elif curl -sf -m 2 "http://169.254.169.254/opc/v1/instance/" >/dev/null 2>&1; then
        provider="oracle"
        region=$(curl -sf -m 2 "http://169.254.169.254/opc/v1/instance/region" 2>/dev/null)
    fi

    echo "$provider|$region"
}

get_public_ip() {
    local ip=""
    for endpoint in "https://ifconfig.me" "https://api.ipify.org" "https://icanhazip.com"; do
        ip=$(curl -sf -m 5 "$endpoint" 2>/dev/null | tr -d '[:space:]')
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

#-------------------------------------------------------------------------------
# Firewall Configuration
#-------------------------------------------------------------------------------

configure_firewall() {
    local provider="$1"

    print_step "Configuring firewall"

    # Always ensure iptables allows Docker traffic
    if command -v ufw &>/dev/null; then
        ufw allow 22/tcp 2>/dev/null || true
        ufw --force enable 2>/dev/null || true
        print_info "UFW enabled (SSH allowed)"
    fi

    print_success "Firewall configured"
}

open_port() {
    local port="$1"
    local proto="${2:-tcp}"

    if command -v ufw &>/dev/null; then
        ufw allow "$port/$proto" 2>/dev/null || true
    fi
    # iptables fallback
    iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
}

close_port() {
    local port="$1"
    local proto="${2:-tcp}"

    if command -v ufw &>/dev/null; then
        ufw delete allow "$port/$proto" 2>/dev/null || true
    fi
    iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
}

#-------------------------------------------------------------------------------
# State File
#-------------------------------------------------------------------------------

init_state() {
    print_step "Initializing VPS state"

    local machine_id=""
    if [[ -f /etc/machine-id ]]; then
        machine_id=$(cat /etc/machine-id)
    else
        machine_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d '-')
    fi

    local cloud_info
    cloud_info=$(detect_cloud_provider)
    local provider=$(echo "$cloud_info" | cut -d'|' -f1)
    local region=$(echo "$cloud_info" | cut -d'|' -f2)

    local ip
    ip=$(get_public_ip) || ip="unknown"

    if [[ -f "$STATE_FILE" ]]; then
        # Update mutable fields, keep protocols
        local tmp
        tmp=$(jq --arg ip "$ip" --arg provider "$provider" --arg region "$region" \
            '.ip = $ip | .provider = $provider | .region = $region | .updated = (now | todate)' \
            "$STATE_FILE")
        echo "$tmp" > "$STATE_FILE"
        print_info "State updated (IP: $ip, provider: $provider)"
    else
        cat > "$STATE_FILE" <<EOF
{
  "machine_id": "$machine_id",
  "ip": "$ip",
  "provider": "$provider",
  "region": "$region",
  "protocols": {},
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
        print_success "State initialized (ID: ${machine_id:0:8}..., IP: $ip)"
    fi

    chmod 600 "$STATE_FILE"
}

#-------------------------------------------------------------------------------
# Users Database
#-------------------------------------------------------------------------------

init_users() {
    if [[ -f "$USERS_FILE" ]]; then
        print_info "Users database exists"
        return 0
    fi

    print_step "Creating users database"

    local ip
    ip=$(jq -r '.ip // "unknown"' "$STATE_FILE" 2>/dev/null)
    local provider
    provider=$(jq -r '.provider // "unknown"' "$STATE_FILE" 2>/dev/null)

    cat > "$USERS_FILE" <<EOF
{
  "users": {},
  "server": {
    "ip": "$ip",
    "provider": "$provider"
  }
}
EOF
    chmod 600 "$USERS_FILE"
    print_success "Users database created"
}

#-------------------------------------------------------------------------------
# Download Protocol Docker Files
#-------------------------------------------------------------------------------

download_docker_files() {
    print_step "Downloading Docker configurations"

    local docker_dir="$VANY_DIR/docker"
    mkdir -p "$docker_dir"

    for proto in xray wireguard dnstt conduit sos; do
        mkdir -p "$docker_dir/$proto"
        curl -sfL "$GITHUB_RAW/docker/$proto/docker-compose.yml" -o "$docker_dir/$proto/docker-compose.yml" || true
        if [[ "$proto" != "conduit" ]]; then
            curl -sfL "$GITHUB_RAW/docker/$proto/Dockerfile" -o "$docker_dir/$proto/Dockerfile" 2>/dev/null || true
            curl -sfL "$GITHUB_RAW/docker/$proto/entrypoint.sh" -o "$docker_dir/$proto/entrypoint.sh" 2>/dev/null || true
        fi
    done

    print_success "Docker files downloaded"
}

#-------------------------------------------------------------------------------
# Download Protocol Scripts
#-------------------------------------------------------------------------------

download_protocol_scripts() {
    print_step "Downloading protocol management scripts"

    local scripts_dir="$VANY_DIR/scripts"
    mkdir -p "$scripts_dir"

    for action in install update remove status; do
        for proto in xray wireguard dnstt conduit sos; do
            curl -sfL "$GITHUB_RAW/scripts/protocols/${action}-${proto}.sh" \
                -o "$scripts_dir/${action}-${proto}.sh" 2>/dev/null || true
            [[ -f "$scripts_dir/${action}-${proto}.sh" ]] && chmod +x "$scripts_dir/${action}-${proto}.sh"
        done
    done

    print_success "Protocol scripts downloaded"
}

#-------------------------------------------------------------------------------
# Main Bootstrap
#-------------------------------------------------------------------------------

bootstrap() {
    echo ""
    echo -e "  ${BOLD}Vany - VPS Bootstrap${RESET}"
    echo -e "  ${DIM}Setting up your server...${RESET}"
    echo ""

    check_root
    check_os

    if [[ -f "$BOOTSTRAP_FLAG" ]]; then
        print_info "System already bootstrapped"
        init_state
        return 0
    fi

    source /etc/os-release 2>/dev/null || true
    print_info "OS: ${PRETTY_NAME:-Linux}"
    echo ""

    system_update
    install_prerequisites
    install_docker
    configure_sysctl
    create_directories
    init_state
    init_users
    configure_firewall "$(jq -r '.provider' "$STATE_FILE" 2>/dev/null)"
    download_docker_files
    download_protocol_scripts

    touch "$BOOTSTRAP_FLAG"

    echo ""
    print_success "Bootstrap complete!"
    echo ""
}

# Allow sourcing or direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bootstrap
fi
