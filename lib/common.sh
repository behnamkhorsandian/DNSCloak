#!/bin/bash
#===============================================================================
# DNSCloak - Common Functions Library
# https://github.com/behnamkhorsandian/DNSCloak
#===============================================================================

# Version
DNSCLOAK_VERSION="2.0.0"

# Paths
DNSCLOAK_DIR="/opt/dnscloak"
DNSCLOAK_USERS="$DNSCLOAK_DIR/users.json"
DNSCLOAK_BIN="/usr/local/bin/dnscloak"
GITHUB_RAW="https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main"

#-------------------------------------------------------------------------------
# Colors (No emojis - ASCII only)
#-------------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
RESET='\033[0m'
BOLD='\033[1m'

#-------------------------------------------------------------------------------
# Banner Functions
#-------------------------------------------------------------------------------

# Load banner from file (local or remote)
# Usage: load_banner "setup" or load_banner "menu" or load_banner "reality"
load_banner() {
    local banner_name="$1"
    local banner_file="/opt/dnscloak/banners/${banner_name}.txt"
    local banner_url="${GITHUB_RAW}/banners/${banner_name}.txt"
    
    # Try local file first
    if [[ -f "$banner_file" ]]; then
        cat "$banner_file"
    # Try temp directory (during installation)
    elif [[ -f "/tmp/dnscloak-banners/${banner_name}.txt" ]]; then
        cat "/tmp/dnscloak-banners/${banner_name}.txt"
    # Download from GitHub
    else
        mkdir -p /tmp/dnscloak-banners
        if curl -sL "$banner_url" -o "/tmp/dnscloak-banners/${banner_name}.txt" 2>/dev/null; then
            cat "/tmp/dnscloak-banners/${banner_name}.txt"
        else
            # Fallback to hardcoded
            echo "  DNSCloak v${DNSCLOAK_VERSION}"
        fi
    fi
}

#-------------------------------------------------------------------------------
# Output Functions
#-------------------------------------------------------------------------------

print_banner() {
    local banner_type="${1:-setup}"
    clear
    echo -e "${CYAN}"
    load_banner "$banner_type"
    echo -e "${RESET}"
    echo ""
}

print_line() {
    echo -e "${CYAN}  ------------------------------------------------------------${RESET}"
}

print_success() {
    echo -e "  ${GREEN}[+]${RESET} $1"
}

print_error() {
    echo -e "  ${RED}[-]${RESET} $1"
}

print_warning() {
    echo -e "  ${YELLOW}[!]${RESET} $1"
}

print_info() {
    echo -e "  ${BLUE}[*]${RESET} $1"
}

print_step() {
    echo -e "\n  ${MAGENTA}>>>${RESET} ${BOLD}$1${RESET}"
}

print_item() {
    echo -e "  ${CYAN}  -${RESET} $1"
}

#-------------------------------------------------------------------------------
# Input Functions
#-------------------------------------------------------------------------------

# Wait for enter key
press_enter() {
    echo ""
    echo -e -n "  ${GRAY}Press Enter to continue...${RESET}"
    read -r </dev/tty
}

# Yes/No confirmation
# Usage: confirm "Question?" [default: y/n]
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    echo -e -n "  ${YELLOW}[?]${RESET} $prompt"
    read -r answer </dev/tty
    
    if [[ -z "$answer" ]]; then
        answer="$default"
    fi
    
    [[ "$answer" =~ ^[Yy]$ ]]
}

# Get text input
# Usage: get_input "Prompt" "default" var_name
get_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [[ -n "$default" ]]; then
        echo -e -n "  ${CYAN}[>]${RESET} $prompt ${GRAY}[$default]${RESET}: "
    else
        echo -e -n "  ${CYAN}[>]${RESET} $prompt: "
    fi
    
    read -r input </dev/tty
    
    if [[ -z "$input" && -n "$default" ]]; then
        input="$default"
    fi
    
    eval "$var_name='$input'"
}

# Get password (hidden input)
# Usage: get_password "Prompt" var_name
get_password() {
    local prompt="$1"
    local var_name="$2"
    
    echo -e -n "  ${CYAN}[>]${RESET} $prompt: "
    read -rs input </dev/tty
    echo ""
    
    eval "$var_name='$input'"
}

#-------------------------------------------------------------------------------
# System Checks
#-------------------------------------------------------------------------------

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            print_error "This script supports Ubuntu and Debian only"
            print_info "Detected: $PRETTY_NAME"
            exit 1
        fi
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
    else
        print_error "Cannot detect OS"
        exit 1
    fi
}

# Get architecture for Xray downloads (uses different naming)
get_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  echo "64" ;;      # Xray uses "64" not "amd64"
        aarch64) echo "arm64-v8a" ;;
        armv7l)  echo "arm32-v7a" ;;
        *)       echo "$arch" ;;
    esac
}

#-------------------------------------------------------------------------------
# Service Management
#-------------------------------------------------------------------------------

service_enable() {
    local name="$1"
    systemctl daemon-reload
    systemctl enable "$name" 2>/dev/null
    systemctl start "$name"
}

service_disable() {
    local name="$1"
    systemctl stop "$name" 2>/dev/null || true
    systemctl disable "$name" 2>/dev/null || true
}

service_restart() {
    local name="$1"
    systemctl daemon-reload
    systemctl restart "$name"
}

service_status() {
    local name="$1"
    systemctl is-active "$name" 2>/dev/null
}

#-------------------------------------------------------------------------------
# JSON User Management
#-------------------------------------------------------------------------------

# Initialize users.json if not exists
users_init() {
    if [[ ! -f "$DNSCLOAK_USERS" ]]; then
        mkdir -p "$DNSCLOAK_DIR"
        cat > "$DNSCLOAK_USERS" <<EOF
{
  "version": "1.0",
  "server": {
    "ip": "",
    "domain": "",
    "provider": ""
  },
  "users": {}
}
EOF
        chmod 600 "$DNSCLOAK_USERS"
    fi
}

# Check if user exists
# Usage: user_exists "username" ["protocol"]
user_exists() {
    local username="$1"
    local protocol="${2:-}"
    
    if [[ -n "$protocol" ]]; then
        jq -e ".users[\"$username\"].protocols[\"$protocol\"]" "$DNSCLOAK_USERS" >/dev/null 2>&1
    else
        jq -e ".users[\"$username\"]" "$DNSCLOAK_USERS" >/dev/null 2>&1
    fi
}

# Add user with protocol credentials
# Usage: user_add "username" "protocol" '{"key":"value"}'
user_add() {
    local username="$1"
    local protocol="$2"
    local creds="$3"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    users_init
    
    # If user doesn't exist, create entry
    if ! user_exists "$username"; then
        local tmp
        tmp=$(mktemp)
        jq ".users[\"$username\"] = {\"created\": \"$now\", \"protocols\": {}}" \
            "$DNSCLOAK_USERS" > "$tmp" && mv "$tmp" "$DNSCLOAK_USERS"
    fi
    
    # Add protocol credentials
    local tmp
    tmp=$(mktemp)
    jq ".users[\"$username\"].protocols[\"$protocol\"] = $creds" \
        "$DNSCLOAK_USERS" > "$tmp" && mv "$tmp" "$DNSCLOAK_USERS"
    
    chmod 600 "$DNSCLOAK_USERS"
}

# Remove user from protocol or entirely
# Usage: user_remove "username" ["protocol"]
user_remove() {
    local username="$1"
    local protocol="${2:-}"
    
    if [[ ! -f "$DNSCLOAK_USERS" ]]; then
        return 1
    fi
    
    local tmp
    tmp=$(mktemp)
    
    if [[ -n "$protocol" ]]; then
        # Remove from specific protocol
        jq "del(.users[\"$username\"].protocols[\"$protocol\"])" \
            "$DNSCLOAK_USERS" > "$tmp" && mv "$tmp" "$DNSCLOAK_USERS"
        
        # If no protocols left, remove user entirely
        local remaining
        remaining=$(jq ".users[\"$username\"].protocols | length" "$DNSCLOAK_USERS")
        if [[ "$remaining" == "0" ]]; then
            tmp=$(mktemp)
            jq "del(.users[\"$username\"])" \
                "$DNSCLOAK_USERS" > "$tmp" && mv "$tmp" "$DNSCLOAK_USERS"
        fi
    else
        # Remove user entirely
        jq "del(.users[\"$username\"])" \
            "$DNSCLOAK_USERS" > "$tmp" && mv "$tmp" "$DNSCLOAK_USERS"
    fi
    
    chmod 600 "$DNSCLOAK_USERS"
}

# Get user credentials for protocol
# Usage: user_get "username" "protocol" ["key"]
user_get() {
    local username="$1"
    local protocol="$2"
    local key="${3:-}"
    
    if [[ -n "$key" ]]; then
        jq -r ".users[\"$username\"].protocols[\"$protocol\"][\"$key\"]" "$DNSCLOAK_USERS" 2>/dev/null
    else
        jq -r ".users[\"$username\"].protocols[\"$protocol\"]" "$DNSCLOAK_USERS" 2>/dev/null
    fi
}

# List all users
# Usage: user_list ["protocol"]
user_list() {
    local protocol="${1:-}"
    
    if [[ ! -f "$DNSCLOAK_USERS" ]]; then
        return
    fi
    
    if [[ -n "$protocol" ]]; then
        jq -r ".users | to_entries[] | select(.value.protocols[\"$protocol\"]) | .key" \
            "$DNSCLOAK_USERS" 2>/dev/null
    else
        jq -r ".users | keys[]" "$DNSCLOAK_USERS" 2>/dev/null
    fi
}

# Update server info
# Usage: server_set "key" "value"
server_set() {
    local key="$1"
    local value="$2"
    
    users_init
    
    local tmp
    tmp=$(mktemp)
    jq ".server[\"$key\"] = \"$value\"" \
        "$DNSCLOAK_USERS" > "$tmp" && mv "$tmp" "$DNSCLOAK_USERS"
    chmod 600 "$DNSCLOAK_USERS"
}

# Get server info
# Usage: server_get "key"
server_get() {
    local key="$1"
    jq -r ".server[\"$key\"] // empty" "$DNSCLOAK_USERS" 2>/dev/null
}

#-------------------------------------------------------------------------------
# Utility Functions
#-------------------------------------------------------------------------------

# Generate random hex string
# Usage: random_hex [length=32]
random_hex() {
    local length="${1:-32}"
    head -c $((length / 2)) /dev/urandom | xxd -p | tr -d '\n'
}

# Generate UUID
random_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# Generate x25519 keypair
# Returns: "private_key public_key"
generate_x25519_keypair() {
    if command -v xray &>/dev/null; then
        xray x25519
    else
        print_error "Xray not installed, cannot generate keypair"
        return 1
    fi
}

# String to hex
# Usage: str_to_hex "string"
str_to_hex() {
    echo -n "$1" | xxd -p | tr -d '\n'
}

# URL encode
# Usage: url_encode "string"
url_encode() {
    local string="$1"
    python3 -c "import urllib.parse; print(urllib.parse.quote('$string', safe=''))"
}

# Generate QR code (ASCII)
# Usage: qr_code "data"
qr_code() {
    local data="$1"
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$data"
    else
        print_warning "qrencode not installed, skipping QR code"
    fi
}

# Check if port is in use
# Usage: port_in_use 443
port_in_use() {
    local port="$1"
    ss -tlnp | grep -q ":${port} " 2>/dev/null
}

# Get main network interface
get_main_interface() {
    ip route | grep default | awk '{print $5}' | head -1
}

#-------------------------------------------------------------------------------
# Installed Services Check
#-------------------------------------------------------------------------------

# Check if a service is installed
# Usage: service_installed "reality"
service_installed() {
    local service="$1"
    case "$service" in
        reality|vray|ws)
            [[ -f "$DNSCLOAK_DIR/xray/config.json" ]] && \
            grep -q "\"tag\": \"${service}-in\"" "$DNSCLOAK_DIR/xray/config.json" 2>/dev/null
            ;;
        mtp)
            [[ -f "$DNSCLOAK_DIR/mtp/config.py" ]]
            ;;
        wg)
            [[ -f "$DNSCLOAK_DIR/wg/wg0.conf" ]]
            ;;
        dnstt)
            [[ -f "$DNSCLOAK_DIR/dnstt/server.key" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# List installed services
services_list() {
    local services=""
    for svc in reality vray ws mtp wg dnstt; do
        if service_installed "$svc"; then
            services="$services $svc"
        fi
    done
    echo "$services" | xargs
}
