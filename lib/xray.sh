#!/bin/bash
#===============================================================================
# DNSCloak - Xray Configuration Manager
# Manages multi-inbound Xray config with SNI/path routing
# https://github.com/behnamkhorsandian/DNSCloak
#===============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common if not already loaded
if [[ -z "$DNSCLOAK_DIR" ]]; then
    source "$SCRIPT_DIR/common.sh"
fi

XRAY_CONFIG="$DNSCLOAK_DIR/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"

#-------------------------------------------------------------------------------
# Config Validation
#-------------------------------------------------------------------------------

xray_validate() {
    if [[ ! -f "$XRAY_CONFIG" ]]; then
        print_error "Xray config not found"
        return 1
    fi
    
    "$XRAY_BIN" run -test -config "$XRAY_CONFIG" 2>/dev/null
}

#-------------------------------------------------------------------------------
# Reload Xray
#-------------------------------------------------------------------------------

xray_reload() {
    if ! xray_validate; then
        print_error "Config validation failed, not reloading"
        return 1
    fi
    
    systemctl reload xray 2>/dev/null || systemctl restart xray
}

#-------------------------------------------------------------------------------
# Inbound Management
#-------------------------------------------------------------------------------

# Check if inbound exists
# Usage: xray_inbound_exists "reality-in"
xray_inbound_exists() {
    local tag="$1"
    jq -e ".inbounds[] | select(.tag == \"$tag\")" "$XRAY_CONFIG" >/dev/null 2>&1
}

# Add REALITY inbound
# Usage: xray_add_reality_inbound "private_key" "public_key" "target_domain" "short_ids"
xray_add_reality_inbound() {
    local private_key="$1"
    local target="${2:-www.google.com}"
    local short_ids="${3:-[\"\"]}"
    
    if xray_inbound_exists "reality-in"; then
        print_info "Reality inbound already exists"
        return 0
    fi
    
    local inbound
    inbound=$(cat <<EOF
{
  "tag": "reality-in",
  "port": 443,
  "protocol": "vless",
  "settings": {
    "clients": [],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "show": false,
      "dest": "${target}:443",
      "xver": 0,
      "serverNames": ["${target}"],
      "privateKey": "${private_key}",
      "shortIds": ${short_ids}
    }
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls"]
  }
}
EOF
)

    local tmp
    tmp=$(mktemp)
    jq ".inbounds += [$inbound]" "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    chmod 600 "$XRAY_CONFIG"
}

# Add V2Ray (VLESS+TLS) inbound
# Usage: xray_add_vray_inbound "domain" "cert_path" "key_path"
xray_add_vray_inbound() {
    local domain="$1"
    local cert="$2"
    local key="$3"
    
    if xray_inbound_exists "vray-in"; then
        print_info "V2Ray inbound already exists"
        return 0
    fi
    
    local inbound
    inbound=$(cat <<EOF
{
  "tag": "vray-in",
  "port": 443,
  "protocol": "vless",
  "settings": {
    "clients": [],
    "decryption": "none",
    "fallbacks": [
      {"dest": 8080}
    ]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "tls",
    "tlsSettings": {
      "serverName": "${domain}",
      "certificates": [
        {
          "certificateFile": "${cert}",
          "keyFile": "${key}"
        }
      ]
    }
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls"]
  }
}
EOF
)

    local tmp
    tmp=$(mktemp)
    jq ".inbounds += [$inbound]" "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    chmod 600 "$XRAY_CONFIG"
}

# Add WebSocket inbound
# Usage: xray_add_ws_inbound "domain" "path" "cert_path" "key_path"
xray_add_ws_inbound() {
    local domain="$1"
    local path="$2"
    local cert="$3"
    local key="$4"
    
    if xray_inbound_exists "ws-in"; then
        print_info "WebSocket inbound already exists"
        return 0
    fi
    
    local inbound
    inbound=$(cat <<EOF
{
  "tag": "ws-in",
  "port": 443,
  "protocol": "vless",
  "settings": {
    "clients": [],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "ws",
    "wsSettings": {
      "path": "${path}",
      "headers": {
        "Host": "${domain}"
      }
    },
    "security": "tls",
    "tlsSettings": {
      "serverName": "${domain}",
      "certificates": [
        {
          "certificateFile": "${cert}",
          "keyFile": "${key}"
        }
      ]
    }
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls"]
  }
}
EOF
)

    local tmp
    tmp=$(mktemp)
    jq ".inbounds += [$inbound]" "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    chmod 600 "$XRAY_CONFIG"
}

# Add generic inbound from JSON
# Usage: xray_add_inbound '{"tag": "...", ...}'
xray_add_inbound() {
    local inbound="$1"
    
    # Extract tag from JSON to check if exists
    local tag
    tag=$(echo "$inbound" | jq -r '.tag' 2>/dev/null)
    
    if [[ -n "$tag" ]] && xray_inbound_exists "$tag"; then
        print_info "Inbound '$tag' already exists"
        return 0
    fi
    
    local tmp
    tmp=$(mktemp)
    jq ".inbounds += [$inbound]" "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    chmod 600 "$XRAY_CONFIG"
}

# Remove inbound
# Usage: xray_remove_inbound "reality-in"
xray_remove_inbound() {
    local tag="$1"
    
    local tmp
    tmp=$(mktemp)
    jq "del(.inbounds[] | select(.tag == \"$tag\"))" "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    chmod 600 "$XRAY_CONFIG"
}

#-------------------------------------------------------------------------------
# Client Management
#-------------------------------------------------------------------------------

# Add client to inbound
# Usage: xray_add_client "reality-in" "uuid" "email" ["flow"]
xray_add_client() {
    local tag="$1"
    local uuid="$2"
    local email="$3"
    local flow="${4:-}"
    
    local client
    if [[ -n "$flow" ]]; then
        client="{\"id\": \"$uuid\", \"email\": \"$email\", \"flow\": \"$flow\"}"
    else
        client="{\"id\": \"$uuid\", \"email\": \"$email\"}"
    fi
    
    local tmp
    tmp=$(mktemp)
    jq "(.inbounds[] | select(.tag == \"$tag\") | .settings.clients) += [$client]" \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    chmod 600 "$XRAY_CONFIG"
}

# Remove client from inbound
# Usage: xray_remove_client "reality-in" "email"
xray_remove_client() {
    local tag="$1"
    local email="$2"
    
    local tmp
    tmp=$(mktemp)
    jq "(.inbounds[] | select(.tag == \"$tag\") | .settings.clients) |= map(select(.email != \"$email\"))" \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    chmod 600 "$XRAY_CONFIG"
}

# List clients in inbound
# Usage: xray_list_clients "reality-in"
xray_list_clients() {
    local tag="$1"
    jq -r ".inbounds[] | select(.tag == \"$tag\") | .settings.clients[].email" "$XRAY_CONFIG" 2>/dev/null
}

# Get client UUID
# Usage: xray_get_client_uuid "reality-in" "email"
xray_get_client_uuid() {
    local tag="$1"
    local email="$2"
    jq -r ".inbounds[] | select(.tag == \"$tag\") | .settings.clients[] | select(.email == \"$email\") | .id" \
        "$XRAY_CONFIG" 2>/dev/null
}

#-------------------------------------------------------------------------------
# Link Generation
#-------------------------------------------------------------------------------

# Generate VLESS Reality link
# Usage: xray_reality_link "uuid" "server" "public_key" "sni" "short_id" "name"
xray_reality_link() {
    local uuid="$1"
    local server="$2"
    local pubkey="$3"
    local sni="$4"
    local sid="${5:-}"
    local name="$6"
    
    local link="vless://${uuid}@${server}:443"
    link+="?type=tcp"
    link+="&security=reality"
    link+="&pbk=${pubkey}"
    link+="&fp=chrome"
    link+="&sni=${sni}"
    link+="&sid=${sid}"
    link+="&flow=xtls-rprx-vision"
    link+="#${name}"
    
    echo "$link"
}

# Generate VLESS TLS link (V2Ray)
# Usage: xray_vray_link "uuid" "server" "sni" "name"
xray_vray_link() {
    local uuid="$1"
    local server="$2"
    local sni="$3"
    local name="$4"
    
    local link="vless://${uuid}@${server}:443"
    link+="?type=tcp"
    link+="&security=tls"
    link+="&sni=${sni}"
    link+="&fp=chrome"
    link+="#${name}"
    
    echo "$link"
}

# Generate VLESS WebSocket link
# Usage: xray_ws_link "uuid" "server" "sni" "path" "name"
xray_ws_link() {
    local uuid="$1"
    local server="$2"
    local sni="$3"
    local path="$4"
    local name="$5"
    
    local encoded_path
    encoded_path=$(url_encode "$path")
    
    local link="vless://${uuid}@${server}:443"
    link+="?type=ws"
    link+="&security=tls"
    link+="&path=${encoded_path}"
    link+="&host=${sni}"
    link+="&sni=${sni}"
    link+="#${name}"
    
    echo "$link"
}

#-------------------------------------------------------------------------------
# Status
#-------------------------------------------------------------------------------

xray_status() {
    echo "Xray Configuration Status"
    echo "========================="
    echo ""
    
    if [[ ! -f "$XRAY_CONFIG" ]]; then
        echo "Config: Not found"
        return 1
    fi
    
    echo "Config: $XRAY_CONFIG"
    echo "Service: $(service_status xray || echo 'not running')"
    echo ""
    
    echo "Inbounds:"
    jq -r '.inbounds[] | "  - \(.tag): \(.protocol) on port \(.port)"' "$XRAY_CONFIG" 2>/dev/null || echo "  None"
    echo ""
    
    echo "Clients:"
    for tag in $(jq -r '.inbounds[].tag' "$XRAY_CONFIG" 2>/dev/null); do
        local count
        count=$(jq ".inbounds[] | select(.tag == \"$tag\") | .settings.clients | length" "$XRAY_CONFIG")
        echo "  - $tag: $count clients"
    done
}
