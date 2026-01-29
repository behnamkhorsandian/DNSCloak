#!/usr/bin/env bats
# tests/lib/xray.bats - Xray configuration management tests

# =============================================================================
# SETUP / TEARDOWN
# =============================================================================

setup() {
    export TEST_DIR=$(mktemp -d)
    export DNSCLOAK_DIR="$TEST_DIR/dnscloak"
    export DNSCLOAK_USERS="$DNSCLOAK_DIR/users.json"
    export XRAY_CONFIG="$DNSCLOAK_DIR/xray/config.json"
    
    mkdir -p "$DNSCLOAK_DIR/xray"
    
    source "$BATS_TEST_DIRNAME/../../lib/common.sh"
    source "$BATS_TEST_DIRNAME/../../lib/xray.sh"
    
    init_user_db
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# CONFIG INITIALIZATION
# =============================================================================

@test "xray_init_config creates valid JSON" {
    xray_init_config
    run jq '.' "$XRAY_CONFIG"
    [ "$status" -eq 0 ]
}

@test "xray_init_config includes log section" {
    xray_init_config
    run jq -e '.log' "$XRAY_CONFIG"
    [ "$status" -eq 0 ]
}

@test "xray_init_config includes empty inbounds array" {
    xray_init_config
    run jq '.inbounds | type' "$XRAY_CONFIG"
    [ "$output" = '"array"' ]
}

@test "xray_init_config includes empty outbounds" {
    xray_init_config
    run jq -e '.outbounds' "$XRAY_CONFIG"
    [ "$status" -eq 0 ]
}

# =============================================================================
# SECURITY: IP LOGGING (Issue #8)
# =============================================================================

@test "SECURITY: access log is disabled or anonymized" {
    xray_init_config
    local access_log=$(jq -r '.log.access // "none"' "$XRAY_CONFIG")
    # Should be empty string, "none", or not contain a file path
    [[ "$access_log" == "" || "$access_log" == "none" || "$access_log" == "null" ]]
}

@test "SECURITY: log level is warning or higher" {
    xray_init_config
    local log_level=$(jq -r '.log.loglevel // "warning"' "$XRAY_CONFIG")
    [[ "$log_level" == "warning" || "$log_level" == "error" || "$log_level" == "none" ]]
}

# =============================================================================
# REALITY INBOUND
# =============================================================================

@test "xray_add_reality_inbound creates valid inbound" {
    xray_init_config
    xray_add_reality_inbound 443 "www.google.com:443" "www.google.com" "test-private-key" "test-public-key"
    run jq '.inbounds | length' "$XRAY_CONFIG"
    [ "$output" = "1" ]
}

@test "xray_add_reality_inbound sets correct port" {
    xray_init_config
    xray_add_reality_inbound 8443 "www.google.com:443" "www.google.com" "priv" "pub"
    run jq '.inbounds[0].port' "$XRAY_CONFIG"
    [ "$output" = "8443" ]
}

@test "xray_add_reality_inbound sets VLESS protocol" {
    xray_init_config
    xray_add_reality_inbound 443 "www.google.com:443" "www.google.com" "priv" "pub"
    run jq -r '.inbounds[0].protocol' "$XRAY_CONFIG"
    [ "$output" = "vless" ]
}

@test "xray_add_reality_inbound configures reality settings" {
    xray_init_config
    xray_add_reality_inbound 443 "www.google.com:443" "www.google.com" "priv" "pub"
    run jq -r '.inbounds[0].streamSettings.security' "$XRAY_CONFIG"
    [ "$output" = "reality" ]
}

@test "xray_add_reality_inbound sets correct SNI" {
    xray_init_config
    xray_add_reality_inbound 443 "www.google.com:443" "www.google.com" "priv" "pub"
    run jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$XRAY_CONFIG"
    [ "$output" = "www.google.com" ]
}

# =============================================================================
# WEBSOCKET INBOUND
# =============================================================================

@test "xray_add_ws_inbound creates valid inbound" {
    xray_init_config
    xray_add_ws_inbound 80 "/ws-path"
    run jq '.inbounds | length' "$XRAY_CONFIG"
    [ "$output" = "1" ]
}

@test "xray_add_ws_inbound sets WebSocket transport" {
    xray_init_config
    xray_add_ws_inbound 80 "/ws-path"
    run jq -r '.inbounds[0].streamSettings.network' "$XRAY_CONFIG"
    [ "$output" = "ws" ]
}

@test "xray_add_ws_inbound sets correct path" {
    xray_init_config
    xray_add_ws_inbound 80 "/custom-path"
    run jq -r '.inbounds[0].streamSettings.wsSettings.path' "$XRAY_CONFIG"
    [ "$output" = "/custom-path" ]
}

# =============================================================================
# CLIENT MANAGEMENT
# =============================================================================

@test "xray_add_client adds client to inbound" {
    xray_init_config
    xray_add_reality_inbound 443 "www.google.com:443" "www.google.com" "priv" "pub"
    local uuid=$(generate_uuid)
    xray_add_client "reality-in" "$uuid"
    run jq '.inbounds[0].settings.clients | length' "$XRAY_CONFIG"
    [ "$output" = "1" ]
}

@test "xray_add_client sets correct UUID" {
    xray_init_config
    xray_add_reality_inbound 443 "www.google.com:443" "www.google.com" "priv" "pub"
    xray_add_client "reality-in" "test-uuid-12345"
    run jq -r '.inbounds[0].settings.clients[0].id' "$XRAY_CONFIG"
    [ "$output" = "test-uuid-12345" ]
}

@test "xray_add_client supports flow parameter" {
    xray_init_config
    xray_add_reality_inbound 443 "www.google.com:443" "www.google.com" "priv" "pub"
    xray_add_client "reality-in" "test-uuid" "xtls-rprx-vision"
    run jq -r '.inbounds[0].settings.clients[0].flow' "$XRAY_CONFIG"
    [ "$output" = "xtls-rprx-vision" ]
}

@test "xray_remove_client removes client from inbound" {
    xray_init_config
    xray_add_reality_inbound 443 "www.google.com:443" "www.google.com" "priv" "pub"
    xray_add_client "reality-in" "uuid-to-remove"
    xray_add_client "reality-in" "uuid-to-keep"
    xray_remove_client "reality-in" "uuid-to-remove"
    run jq '.inbounds[0].settings.clients | length' "$XRAY_CONFIG"
    [ "$output" = "1" ]
    run jq -r '.inbounds[0].settings.clients[0].id' "$XRAY_CONFIG"
    [ "$output" = "uuid-to-keep" ]
}

@test "xray_get_client_count returns correct count" {
    xray_init_config
    xray_add_reality_inbound 443 "www.google.com:443" "www.google.com" "priv" "pub"
    xray_add_client "reality-in" "uuid1"
    xray_add_client "reality-in" "uuid2"
    xray_add_client "reality-in" "uuid3"
    run xray_get_client_count "reality-in"
    [ "$output" = "3" ]
}

# =============================================================================
# MULTIPLE INBOUNDS
# =============================================================================

@test "multiple inbounds can coexist" {
    xray_init_config
    xray_add_reality_inbound 443 "www.google.com:443" "www.google.com" "priv" "pub"
    xray_add_ws_inbound 80 "/ws"
    run jq '.inbounds | length' "$XRAY_CONFIG"
    [ "$output" = "2" ]
}

@test "clients added to correct inbound by tag" {
    xray_init_config
    xray_add_reality_inbound 443 "www.google.com:443" "www.google.com" "priv" "pub"
    xray_add_ws_inbound 80 "/ws"
    xray_add_client "reality-in" "reality-uuid"
    xray_add_client "ws-in" "ws-uuid"
    
    # Check reality inbound has correct client
    run jq -r '.inbounds[] | select(.tag == "reality-in") | .settings.clients[0].id' "$XRAY_CONFIG"
    [ "$output" = "reality-uuid" ]
    
    # Check ws inbound has correct client
    run jq -r '.inbounds[] | select(.tag == "ws-in") | .settings.clients[0].id' "$XRAY_CONFIG"
    [ "$output" = "ws-uuid" ]
}

# =============================================================================
# CONFIG VALIDATION
# =============================================================================

@test "generated config passes xray test" {
    skip "Requires xray binary installed"
    xray_init_config
    xray_add_reality_inbound 443 "www.google.com:443" "www.google.com" "priv" "pub"
    run xray test -config "$XRAY_CONFIG"
    [ "$status" -eq 0 ]
}

@test "config remains valid JSON after modifications" {
    xray_init_config
    xray_add_reality_inbound 443 "www.google.com:443" "www.google.com" "priv" "pub"
    xray_add_client "reality-in" "uuid1"
    xray_add_client "reality-in" "uuid2"
    xray_remove_client "reality-in" "uuid1"
    xray_add_ws_inbound 80 "/ws"
    
    run jq '.' "$XRAY_CONFIG"
    [ "$status" -eq 0 ]
}
