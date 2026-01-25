#!/bin/bash
#===============================================================================
# DNSCloak - Cloud Provider Detection and Firewall Configuration
# https://github.com/behnamkhorsandian/DNSCloak
#===============================================================================

# Detect cloud provider via metadata endpoints
# Sets CLOUD_PROVIDER and CLOUD_REGION variables

CLOUD_PROVIDER=""
CLOUD_REGION=""
CLOUD_INSTANCE_ID=""
PUBLIC_IP=""

# Metadata endpoint timeout (seconds)
METADATA_TIMEOUT=2

#-------------------------------------------------------------------------------
# Provider Detection Functions
#-------------------------------------------------------------------------------

detect_aws() {
    local token
    # IMDSv2 requires token
    token=$(curl -s --max-time "$METADATA_TIMEOUT" -X PUT \
        "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
    
    if [[ -n "$token" ]]; then
        local check
        check=$(curl -s --max-time "$METADATA_TIMEOUT" \
            -H "X-aws-ec2-metadata-token: $token" \
            "http://169.254.169.254/latest/meta-data/instance-id" 2>/dev/null)
        if [[ -n "$check" && "$check" != *"404"* ]]; then
            CLOUD_PROVIDER="aws"
            CLOUD_INSTANCE_ID="$check"
            CLOUD_REGION=$(curl -s --max-time "$METADATA_TIMEOUT" \
                -H "X-aws-ec2-metadata-token: $token" \
                "http://169.254.169.254/latest/meta-data/placement/region" 2>/dev/null)
            return 0
        fi
    fi
    return 1
}

detect_gcp() {
    local check
    check=$(curl -s --max-time "$METADATA_TIMEOUT" \
        -H "Metadata-Flavor: Google" \
        "http://metadata.google.internal/computeMetadata/v1/instance/id" 2>/dev/null)
    
    if [[ -n "$check" && "$check" =~ ^[0-9]+$ ]]; then
        CLOUD_PROVIDER="gcp"
        CLOUD_INSTANCE_ID="$check"
        local zone
        zone=$(curl -s --max-time "$METADATA_TIMEOUT" \
            -H "Metadata-Flavor: Google" \
            "http://metadata.google.internal/computeMetadata/v1/instance/zone" 2>/dev/null)
        CLOUD_REGION=$(echo "$zone" | awk -F'/' '{print $NF}' | sed 's/-[a-z]$//')
        return 0
    fi
    return 1
}

detect_azure() {
    local check
    check=$(curl -s --max-time "$METADATA_TIMEOUT" \
        -H "Metadata: true" \
        "http://169.254.169.254/metadata/instance/compute/vmId?api-version=2021-02-01&format=text" 2>/dev/null)
    
    if [[ -n "$check" && ${#check} -gt 10 ]]; then
        CLOUD_PROVIDER="azure"
        CLOUD_INSTANCE_ID="$check"
        CLOUD_REGION=$(curl -s --max-time "$METADATA_TIMEOUT" \
            -H "Metadata: true" \
            "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text" 2>/dev/null)
        return 0
    fi
    return 1
}

detect_digitalocean() {
    local check
    check=$(curl -s --max-time "$METADATA_TIMEOUT" \
        "http://169.254.169.254/metadata/v1/id" 2>/dev/null)
    
    if [[ -n "$check" && "$check" =~ ^[0-9]+$ ]]; then
        CLOUD_PROVIDER="digitalocean"
        CLOUD_INSTANCE_ID="$check"
        CLOUD_REGION=$(curl -s --max-time "$METADATA_TIMEOUT" \
            "http://169.254.169.254/metadata/v1/region" 2>/dev/null)
        return 0
    fi
    return 1
}

detect_vultr() {
    local check
    check=$(curl -s --max-time "$METADATA_TIMEOUT" \
        "http://169.254.169.254/v1/instanceid" 2>/dev/null)
    
    if [[ -n "$check" && ${#check} -gt 5 ]]; then
        CLOUD_PROVIDER="vultr"
        CLOUD_INSTANCE_ID="$check"
        CLOUD_REGION=$(curl -s --max-time "$METADATA_TIMEOUT" \
            "http://169.254.169.254/v1/region/regioncode" 2>/dev/null)
        return 0
    fi
    return 1
}

detect_hetzner() {
    local check
    check=$(curl -s --max-time "$METADATA_TIMEOUT" \
        "http://169.254.169.254/hetzner/v1/metadata/instance-id" 2>/dev/null)
    
    if [[ -n "$check" && "$check" =~ ^[0-9]+$ ]]; then
        CLOUD_PROVIDER="hetzner"
        CLOUD_INSTANCE_ID="$check"
        CLOUD_REGION=$(curl -s --max-time "$METADATA_TIMEOUT" \
            "http://169.254.169.254/hetzner/v1/metadata/region" 2>/dev/null)
        return 0
    fi
    return 1
}

detect_oracle() {
    local check
    check=$(curl -s --max-time "$METADATA_TIMEOUT" \
        "http://169.254.169.254/opc/v1/instance/id" 2>/dev/null)
    
    if [[ -n "$check" && ${#check} -gt 10 ]]; then
        CLOUD_PROVIDER="oracle"
        CLOUD_INSTANCE_ID="$check"
        CLOUD_REGION=$(curl -s --max-time "$METADATA_TIMEOUT" \
            "http://169.254.169.254/opc/v1/instance/region" 2>/dev/null)
        return 0
    fi
    return 1
}

detect_linode() {
    local check
    check=$(curl -s --max-time "$METADATA_TIMEOUT" \
        "http://169.254.169.254/v1/instance-id" 2>/dev/null)
    
    if [[ -n "$check" && "$check" =~ ^[0-9]+$ ]]; then
        CLOUD_PROVIDER="linode"
        CLOUD_INSTANCE_ID="$check"
        CLOUD_REGION=$(curl -s --max-time "$METADATA_TIMEOUT" \
            "http://169.254.169.254/v1/region" 2>/dev/null)
        return 0
    fi
    return 1
}

#-------------------------------------------------------------------------------
# Main Detection Function
#-------------------------------------------------------------------------------

cloud_detect() {
    # Try each provider in order
    detect_aws && return 0
    detect_gcp && return 0
    detect_azure && return 0
    detect_digitalocean && return 0
    detect_vultr && return 0
    detect_hetzner && return 0
    detect_oracle && return 0
    detect_linode && return 0
    
    # Fallback - unknown provider
    CLOUD_PROVIDER="unknown"
    return 1
}

#-------------------------------------------------------------------------------
# Get Public IP
#-------------------------------------------------------------------------------

cloud_get_public_ip() {
    local ip=""
    
    # Try provider-specific first
    case "$CLOUD_PROVIDER" in
        aws)
            local token
            token=$(curl -s --max-time 2 -X PUT \
                "http://169.254.169.254/latest/api/token" \
                -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
            ip=$(curl -s --max-time 2 \
                -H "X-aws-ec2-metadata-token: $token" \
                "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null)
            ;;
        gcp)
            ip=$(curl -s --max-time 2 \
                -H "Metadata-Flavor: Google" \
                "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" 2>/dev/null)
            ;;
        azure)
            ip=$(curl -s --max-time 2 \
                -H "Metadata: true" \
                "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text" 2>/dev/null)
            ;;
        digitalocean)
            ip=$(curl -s --max-time 2 \
                "http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address" 2>/dev/null)
            ;;
        vultr)
            ip=$(curl -s --max-time 2 \
                "http://169.254.169.254/v1/interfaces/0/ipv4/address" 2>/dev/null)
            ;;
        hetzner)
            ip=$(curl -s --max-time 2 \
                "http://169.254.169.254/hetzner/v1/metadata/public-ipv4" 2>/dev/null)
            ;;
        oracle)
            # Oracle metadata doesn't provide public IP, use external service
            ;;
        linode)
            ip=$(curl -s --max-time 2 \
                "http://169.254.169.254/v1/network/interfaces/eth0/ipv4/first/address" 2>/dev/null)
            ;;
    esac
    
    # Fallback to external services
    if [[ -z "$ip" || "$ip" == "null" ]]; then
        ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null) || \
        ip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null) || \
        ip=$(curl -s --max-time 5 https://icanhazip.com 2>/dev/null)
    fi
    
    PUBLIC_IP="$ip"
    echo "$ip"
}

#-------------------------------------------------------------------------------
# Firewall Configuration
#-------------------------------------------------------------------------------

# Open a port on the cloud provider's firewall
# Usage: cloud_open_port <port> <protocol>
cloud_open_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    case "$CLOUD_PROVIDER" in
        aws)
            _aws_open_port "$port" "$protocol"
            ;;
        gcp)
            _gcp_open_port "$port" "$protocol"
            ;;
        azure)
            _azure_open_port "$port" "$protocol"
            ;;
        digitalocean)
            _do_open_port "$port" "$protocol"
            ;;
        vultr)
            _vultr_open_port "$port" "$protocol"
            ;;
        hetzner)
            _hetzner_open_port "$port" "$protocol"
            ;;
        oracle)
            _oracle_open_port "$port" "$protocol"
            ;;
        linode)
            _linode_open_port "$port" "$protocol"
            ;;
        *)
            _local_open_port "$port" "$protocol"
            ;;
    esac
}

# Provider-specific implementations
# These check for CLI tools and fall back to local firewall

_aws_open_port() {
    local port="$1"
    local protocol="$2"
    
    if command -v aws &>/dev/null; then
        # Get security group
        local token sg_id
        token=$(curl -s --max-time 2 -X PUT \
            "http://169.254.169.254/latest/api/token" \
            -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
        sg_id=$(curl -s --max-time 2 \
            -H "X-aws-ec2-metadata-token: $token" \
            "http://169.254.169.254/latest/meta-data/security-groups" 2>/dev/null | head -1)
        
        if [[ -n "$sg_id" ]]; then
            aws ec2 authorize-security-group-ingress \
                --group-name "$sg_id" \
                --protocol "$protocol" \
                --port "$port" \
                --cidr 0.0.0.0/0 2>/dev/null || true
            return 0
        fi
    fi
    
    _local_open_port "$port" "$protocol"
}

_gcp_open_port() {
    local port="$1"
    local protocol="$2"
    
    if command -v gcloud &>/dev/null; then
        local rule_name="dnscloak-${protocol}-${port}"
        gcloud compute firewall-rules create "$rule_name" \
            --allow="${protocol}:${port}" \
            --source-ranges=0.0.0.0/0 \
            --quiet 2>/dev/null || true
        return 0
    fi
    
    _local_open_port "$port" "$protocol"
}

_azure_open_port() {
    local port="$1"
    local protocol="$2"
    
    # Azure requires resource group and NSG name, complex to auto-detect
    # Fall back to local firewall
    _local_open_port "$port" "$protocol"
}

_do_open_port() {
    local port="$1"
    local protocol="$2"
    
    if command -v doctl &>/dev/null; then
        # DigitalOcean firewalls require manual setup via dashboard
        # Fall back to local
        :
    fi
    
    _local_open_port "$port" "$protocol"
}

_vultr_open_port() {
    local port="$1"
    local protocol="$2"
    
    # Vultr firewalls require manual setup
    _local_open_port "$port" "$protocol"
}

_hetzner_open_port() {
    local port="$1"
    local protocol="$2"
    
    if command -v hcloud &>/dev/null; then
        # Hetzner firewall management
        :
    fi
    
    _local_open_port "$port" "$protocol"
}

_oracle_open_port() {
    local port="$1"
    local protocol="$2"
    
    # Oracle requires iptables on the instance AND security list in VCN
    # Local firewall is essential
    _local_open_port "$port" "$protocol"
}

_linode_open_port() {
    local port="$1"
    local protocol="$2"
    
    # Linode Cloud Firewall is separate service
    _local_open_port "$port" "$protocol"
}

#-------------------------------------------------------------------------------
# Local Firewall (Fallback)
#-------------------------------------------------------------------------------

_local_open_port() {
    local port="$1"
    local protocol="$2"
    
    # Try ufw first (Ubuntu/Debian)
    if command -v ufw &>/dev/null; then
        ufw allow "${port}/${protocol}" 2>/dev/null || true
        return 0
    fi
    
    # Try firewalld (CentOS/RHEL/Fedora)
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="${port}/${protocol}" 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        return 0
    fi
    
    # Direct iptables
    if command -v iptables &>/dev/null; then
        iptables -C INPUT -p "$protocol" --dport "$port" -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p "$protocol" --dport "$port" -j ACCEPT 2>/dev/null || true
        
        # Save rules if possible
        if command -v netfilter-persistent &>/dev/null; then
            netfilter-persistent save 2>/dev/null || true
        fi
        return 0
    fi
    
    return 1
}

#-------------------------------------------------------------------------------
# Open All DNSCloak Ports
#-------------------------------------------------------------------------------

cloud_configure_firewall() {
    cloud_open_port 443 tcp      # Reality, V2Ray, WS, MTP
    cloud_open_port 51820 udp    # WireGuard
    cloud_open_port 53 udp       # DNStt
    cloud_open_port 22 tcp       # SSH (ensure not locked out)
}

#-------------------------------------------------------------------------------
# Export Info
#-------------------------------------------------------------------------------

cloud_info() {
    cat <<EOF
provider=$CLOUD_PROVIDER
region=$CLOUD_REGION
instance_id=$CLOUD_INSTANCE_ID
public_ip=$PUBLIC_IP
EOF
}
