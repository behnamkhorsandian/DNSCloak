#!/bin/bash
#===============================================================================
# Vany - Common Functions Library
# https://github.com/behnamkhorsandian/Vanyshsh
#===============================================================================

# Version
VANY_VERSION="2.0.0"

# Paths (respect environment overrides for testing)
VANY_DIR="${VANY_DIR:-/opt/vany}"
VANY_USERS="${VANY_USERS:-$VANY_DIR/users.json}"
VANY_BIN="${VANY_BIN:-/usr/local/bin/vany}"
GITHUB_RAW="https://raw.githubusercontent.com/behnamkhorsandian/Vanyshsh/main"

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
    local banner_file="/opt/vany/banners/${banner_name}.txt"
    local banner_url="${GITHUB_RAW}/banners/${banner_name}.txt"
    
    # Try local file first
    if [[ -f "$banner_file" ]]; then
        cat "$banner_file"
    # Try temp directory (during installation)
    elif [[ -f "/tmp/vany-banners/${banner_name}.txt" ]]; then
        cat "/tmp/vany-banners/${banner_name}.txt"
    # Download from GitHub
    else
        mkdir -p /tmp/vany-banners
        if curl -sL "$banner_url" -o "/tmp/vany-banners/${banner_name}.txt" 2>/dev/null; then
            cat "/tmp/vany-banners/${banner_name}.txt"
        else
            # Fallback to hardcoded
            echo "  Vany v${VANY_VERSION}"
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
    if [[ ! -f "$VANY_USERS" ]]; then
        mkdir -p "$VANY_DIR"
        cat > "$VANY_USERS" <<EOF
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
        chmod 600 "$VANY_USERS"
    fi
}

# Check if user exists
# Usage: user_exists "username" ["protocol"]
user_exists() {
    local username="$1"
    local protocol="${2:-}"
    
    if [[ -n "$protocol" ]]; then
        jq -e ".users[\"$username\"].protocols[\"$protocol\"]" "$VANY_USERS" >/dev/null 2>&1
    else
        jq -e ".users[\"$username\"]" "$VANY_USERS" >/dev/null 2>&1
    fi
}

# Validate username
# Returns 1 if username contains dangerous characters or is too long
validate_username() {
    local username="$1"
    [[ -z "$username" ]] && return 1
    [[ ${#username} -gt 128 ]] && return 1
    # Reject newlines, carriage returns, control characters
    [[ "$username" == *$'\n'* ]] && return 1
    [[ "$username" == *$'\r'* ]] && return 1
    # Reject null bytes (check via printf since bash can't hold \0 in strings)
    if printf '%s' "$username" | grep -qP '\x00' 2>/dev/null; then
        return 1
    fi
    return 0
}

# Add user with protocol credentials
# Usage: user_add "username" "protocol" '{"key":"value"}'
user_add() {
    local username="$1"
    local protocol="${2:-}"
    local creds="${3:-}"
    
    validate_username "$username" || return 1
    
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    users_init
    
    # If user doesn't exist, create entry
    if ! user_exists "$username"; then
        local tmp
        tmp=$(mktemp)
        jq ".users[\"$username\"] = {\"created\": \"$now\", \"protocols\": {}}" \
            "$VANY_USERS" > "$tmp" && mv "$tmp" "$VANY_USERS"
    fi
    
    # Add protocol credentials if provided
    if [[ -n "$protocol" && -n "$creds" ]]; then
        local tmp
        tmp=$(mktemp)
        jq ".users[\"$username\"].protocols[\"$protocol\"] = $creds" \
            "$VANY_USERS" > "$tmp" && mv "$tmp" "$VANY_USERS"
    fi
    
    chmod 600 "$VANY_USERS"
}

# Set/update protocol credentials for existing user
# Usage: user_set "username" "protocol" '{"key":"value"}'
user_set() {
    local username="$1"
    local protocol="$2"
    local creds="$3"
    
    users_init
    
    # Create user if needed
    if ! user_exists "$username"; then
        user_add "$username"
    fi
    
    local tmp
    tmp=$(mktemp)
    jq ".users[\"$username\"].protocols[\"$protocol\"] = $creds" \
        "$VANY_USERS" > "$tmp" && mv "$tmp" "$VANY_USERS"
    chmod 600 "$VANY_USERS"
}

# Remove user from protocol or entirely
# Usage: user_remove "username" ["protocol"]
user_remove() {
    local username="$1"
    local protocol="${2:-}"
    
    if [[ ! -f "$VANY_USERS" ]]; then
        return 1
    fi
    
    # Check user exists before removing
    if ! user_exists "$username"; then
        return 1
    fi
    
    local tmp
    tmp=$(mktemp)
    
    if [[ -n "$protocol" ]]; then
        # Remove from specific protocol
        jq "del(.users[\"$username\"].protocols[\"$protocol\"])" \
            "$VANY_USERS" > "$tmp" && mv "$tmp" "$VANY_USERS"
        
        # If no protocols left, remove user entirely
        local remaining
        remaining=$(jq ".users[\"$username\"].protocols | length" "$VANY_USERS")
        if [[ "$remaining" == "0" ]]; then
            tmp=$(mktemp)
            jq "del(.users[\"$username\"])" \
                "$VANY_USERS" > "$tmp" && mv "$tmp" "$VANY_USERS"
        fi
    else
        # Remove user entirely
        jq "del(.users[\"$username\"])" \
            "$VANY_USERS" > "$tmp" && mv "$tmp" "$VANY_USERS"
    fi
    
    chmod 600 "$VANY_USERS"
}

# Get user credentials for protocol
# Usage: user_get "username" "protocol" ["key"]
user_get() {
    local username="$1"
    local protocol="$2"
    local key="${3:-}"
    
    if [[ -n "$key" ]]; then
        jq -r ".users[\"$username\"].protocols[\"$protocol\"][\"$key\"]" "$VANY_USERS" 2>/dev/null
    else
        jq -r ".users[\"$username\"].protocols[\"$protocol\"]" "$VANY_USERS" 2>/dev/null
    fi
}

# List all users
# Usage: user_list ["protocol"]
user_list() {
    local protocol="${1:-}"
    
    if [[ ! -f "$VANY_USERS" ]]; then
        return
    fi
    
    if [[ -n "$protocol" ]]; then
        jq -r ".users | to_entries[] | select(.value.protocols[\"$protocol\"]) | .key" \
            "$VANY_USERS" 2>/dev/null
    else
        jq -r ".users | keys[]" "$VANY_USERS" 2>/dev/null
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
        "$VANY_USERS" > "$tmp" && mv "$tmp" "$VANY_USERS"
    chmod 600 "$VANY_USERS"
}

# Get server info
# Usage: server_get "key"
server_get() {
    local key="$1"
    jq -r ".server[\"$key\"] // empty" "$VANY_USERS" 2>/dev/null
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

# Aliases for backward compatibility
generate_secret() { random_hex "$@"; }

# Generate UUID
random_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# Alias for backward compatibility
generate_uuid() { random_uuid "$@"; }

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
            [[ -f "$VANY_DIR/xray/config.json" ]] && \
            grep -q "\"tag\": \"${service}-in\"" "$VANY_DIR/xray/config.json" 2>/dev/null
            ;;
        mtp)
            [[ -f "$VANY_DIR/mtp/config.py" ]] || \
            systemctl is-active --quiet mtprotoproxy 2>/dev/null || \
            systemctl is-active --quiet telegram-proxy 2>/dev/null
            ;;
        wg)
            [[ -f "$VANY_DIR/wg/wg0.conf" ]]
            ;;
        dnstt)
            [[ -f "$VANY_DIR/dnstt/server.key" ]]
            ;;
        conduit)
            docker ps -a 2>/dev/null | grep -q conduit
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if service is running
service_running() {
    local service="$1"
    case "$service" in
        reality|vray|ws)
            systemctl is-active --quiet xray 2>/dev/null
            ;;
        mtp)
            systemctl is-active --quiet mtprotoproxy 2>/dev/null || \
            systemctl is-active --quiet telegram-proxy 2>/dev/null
            ;;
        wg)
            systemctl is-active --quiet wg-quick@wg0 2>/dev/null
            ;;
        dnstt)
            systemctl is-active --quiet dnstt 2>/dev/null
            ;;
        conduit)
            docker ps 2>/dev/null | grep -q conduit
            ;;
        *)
            return 1
            ;;
    esac
}

# List installed services
services_list() {
    local services=""
    for svc in reality vray ws mtp wg dnstt conduit; do
        if service_installed "$svc"; then
            services="$services $svc"
        fi
    done
    echo "$services" | xargs
}

#-------------------------------------------------------------------------------
# TUI Functions (Interactive Terminal UI)
# Uses /dev/tty for keyboard input (works when piped from curl)
#-------------------------------------------------------------------------------

# Terminal state variables
_TUI_ACTIVE=0
_TUI_OLD_STTY=""

# Initialize TUI mode - save terminal state, enter raw mode
tui_init() {
    if [[ $_TUI_ACTIVE -eq 1 ]]; then
        return 0
    fi
    
    # Open /dev/tty for keyboard input (fd 3)
    exec 3</dev/tty 2>/dev/null || {
        # Fallback: can't open tty, use basic input
        return 1
    }
    
    # Save terminal settings
    _TUI_OLD_STTY=$(stty -g <&3 2>/dev/null)
    
    # Hide cursor
    printf '\033[?25l'
    
    _TUI_ACTIVE=1
}

# Restore terminal state
tui_cleanup() {
    if [[ $_TUI_ACTIVE -eq 0 ]]; then
        return 0
    fi
    
    # Restore terminal settings
    if [[ -n "$_TUI_OLD_STTY" ]]; then
        stty "$_TUI_OLD_STTY" <&3 2>/dev/null
    fi
    
    # Show cursor
    printf '\033[?25h'
    
    # Close fd 3
    exec 3<&- 2>/dev/null
    
    _TUI_ACTIVE=0
}

# Read a single keypress (supports arrow keys)
# Outputs: UP, DOWN, LEFT, RIGHT, ENTER, or the character pressed
tui_read_key() {
    local c1 c2 c3
    
    # Set raw mode for single char reads
    stty -echo -icanon min 1 time 0 <&3 2>/dev/null
    
    # Read first character
    IFS= read -rsn1 c1 <&3
    
    # Restore cooked mode
    stty echo icanon <&3 2>/dev/null
    
    # Handle special keys
    if [[ "$c1" == $'\033' ]]; then
        # Escape sequence - read more
        stty -echo -icanon min 1 time 0 <&3 2>/dev/null
        IFS= read -rsn1 -t 0.1 c2 <&3 2>/dev/null || true
        if [[ "$c2" == "[" ]]; then
            IFS= read -rsn1 -t 0.1 c3 <&3 2>/dev/null || true
            stty echo icanon <&3 2>/dev/null
            case "$c3" in
                A) echo "UP";    return ;;
                B) echo "DOWN";  return ;;
                C) echo "RIGHT"; return ;;
                D) echo "LEFT";  return ;;
            esac
        fi
        stty echo icanon <&3 2>/dev/null
        echo "ESC"
        return
    fi
    
    # Enter key
    if [[ "$c1" == "" ]]; then
        echo "ENTER"
        return
    fi
    
    echo "$c1"
}

# Draw a box with title
# Usage: tui_box "Title" width
tui_box_top() {
    local title="$1"
    local width="${2:-50}"
    local inner=$((width - 2))
    
    printf "  ${CYAN}\u2554"
    if [[ -n "$title" ]]; then
        local tlen=${#title}
        local pad=$(( (inner - tlen - 2) / 2 ))
        local pad2=$(( inner - tlen - 2 - pad ))
        printf '%0.s\u2550' $(seq 1 "$pad")
        printf " %s " "$title"
        printf '%0.s\u2550' $(seq 1 "$pad2")
    else
        printf '%0.s\u2550' $(seq 1 "$inner")
    fi
    printf "\u2557${RESET}\n"
}

tui_box_row() {
    local text="$1"
    local width="${2:-50}"
    local inner=$((width - 2))
    
    # Strip ANSI codes for length calculation
    local stripped
    stripped=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local tlen=${#stripped}
    local pad=$((inner - tlen))
    
    printf "  ${CYAN}\u2551${RESET} %b" "$text"
    printf '%*s' "$pad" ""
    printf "${CYAN}\u2551${RESET}\n"
}

tui_box_sep() {
    local width="${1:-50}"
    local inner=$((width - 2))
    
    printf "  ${CYAN}\u2560"
    printf '%0.s\u2550' $(seq 1 "$inner")
    printf "\u2563${RESET}\n"
}

tui_box_bottom() {
    local width="${1:-50}"
    local inner=$((width - 2))
    
    printf "  ${CYAN}\u255A"
    printf '%0.s\u2550' $(seq 1 "$inner")
    printf "\u255D${RESET}\n"
}

tui_box_empty() {
    local width="${1:-50}"
    local inner=$((width - 2))
    
    printf "  ${CYAN}\u2551${RESET}%*s${CYAN}\u2551${RESET}\n" "$inner" ""
}

# Draw an interactive menu and return the selected index
# Usage: tui_menu "Title" selected_var item1 item2 item3 ...
# Items can contain | separator: "label|tag|status"
# Returns: sets the variable named by selected_var to the chosen index (0-based)
tui_menu() {
    local title="$1"
    local result_var="$2"
    shift 2
    local items=("$@")
    local count=${#items[@]}
    local selected=0
    local width=52
    
    if [[ $count -eq 0 ]]; then
        return 1
    fi
    
    # Initialize TUI if not already active
    local tui_was_active=$_TUI_ACTIVE
    tui_init || {
        # Fallback to number-based selection
        echo ""
        echo -e "  ${BOLD}${WHITE}$title${RESET}"
        print_line
        local i=1
        for item in "${items[@]}"; do
            local label="${item%%|*}"
            echo "  $i) $label"
            ((i++))
        done
        echo ""
        get_input "Select [1-$count]" "1" _tui_choice
        eval "$result_var=$((_tui_choice - 1))"
        return 0
    }
    
    # Trap to cleanup on exit
    trap 'tui_cleanup' EXIT INT TERM
    
    while true; do
        # Move cursor to draw position (use relative positioning)
        printf '\033[2J\033[H'  # Clear screen, move to top
        
        # Print banner
        echo -e "${CYAN}"
        load_banner "logo" 2>/dev/null || echo "  Vany v${VANY_VERSION}"
        echo -e "${RESET}"
        echo ""
        
        # Draw menu box
        tui_box_top "$title" "$width"
        tui_box_empty "$width"
        
        local i=0
        for item in "${items[@]}"; do
            # Parse item: "label|tag|status"
            local label="${item%%|*}"
            local rest="${item#*|}"
            local tag="${rest%%|*}"
            local status=""
            if [[ "$rest" == *"|"* ]]; then
                status="${rest##*|}"
            fi
            
            # Build display line
            local prefix="   "
            local line_color="${RESET}"
            
            if [[ $i -eq $selected ]]; then
                prefix=" ${GREEN}>${RESET}"
                line_color="${GREEN}${BOLD}"
            fi
            
            local display="${prefix} ${line_color}${label}${RESET}"
            
            # Add status badge
            if [[ -n "$status" ]]; then
                case "$status" in
                    installed)  display="${display}  ${GREEN}[installed]${RESET}" ;;
                    running)    display="${display}  ${GREEN}[running]${RESET}" ;;
                    stopped)    display="${display}  ${YELLOW}[stopped]${RESET}" ;;
                    required)   display="${display}  ${YELLOW}(needs domain)${RESET}" ;;
                    recommended) display="${display}  ${CYAN}(recommended)${RESET}" ;;
                    emergency)  display="${display}  ${RED}(emergency)${RESET}" ;;
                    relay)      display="${display}  ${MAGENTA}(relay)${RESET}" ;;
                esac
            fi
            
            tui_box_row "$display" "$width"
            ((i++))
        done
        
        tui_box_empty "$width"
        tui_box_sep "$width"
        tui_box_row " ${GRAY}Up/Down: Navigate  Enter: Select  q: Quit${RESET}" "$width"
        tui_box_bottom "$width"
        
        # Read key
        local key
        key=$(tui_read_key)
        
        case "$key" in
            UP)
                ((selected--))
                [[ $selected -lt 0 ]] && selected=$((count - 1))
                ;;
            DOWN)
                ((selected++))
                [[ $selected -ge $count ]] && selected=0
                ;;
            ENTER)
                # Cleanup TUI if we started it
                if [[ $tui_was_active -eq 0 ]]; then
                    tui_cleanup
                fi
                eval "$result_var=$selected"
                return 0
                ;;
            q|Q)
                if [[ $tui_was_active -eq 0 ]]; then
                    tui_cleanup
                fi
                eval "$result_var=-1"
                return 0
                ;;
            [1-9])
                # Number key quick select
                local num=$((key - 1))
                if [[ $num -lt $count ]]; then
                    if [[ $tui_was_active -eq 0 ]]; then
                        tui_cleanup
                    fi
                    eval "$result_var=$num"
                    return 0
                fi
                ;;
        esac
    done
}

# Show a sub-menu for managing a specific service
# Usage: tui_service_menu "service_name"
tui_service_submenu() {
    local title="$1"
    shift
    local items=("$@")
    local result
    
    tui_menu "$title" result "${items[@]}"
    echo "$result"
}

# Get protocol display name
protocol_display_name() {
    case "$1" in
        reality)  echo "VLESS + REALITY" ;;
        ws)       echo "VLESS + WS + CDN" ;;
        wg)       echo "WireGuard" ;;
        vray)     echo "VLESS + TLS" ;;
        dnstt)    echo "DNS Tunnel" ;;
        mtp)      echo "MTProto" ;;
        conduit)  echo "Conduit (Psiphon)" ;;
        *)        echo "$1" ;;
    esac
}

# Get protocol status for menu display
protocol_status() {
    local proto="$1"
    if service_installed "$proto"; then
        if service_running "$proto"; then
            echo "running"
        else
            echo "stopped"
        fi
    else
        case "$proto" in
            reality)  echo "recommended" ;;
            ws|vray)  echo "required" ;;
            dnstt)    echo "emergency" ;;
            conduit)  echo "relay" ;;
            *)        echo "" ;;
        esac
    fi
}
