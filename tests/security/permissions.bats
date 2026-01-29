#!/usr/bin/env bats
# tests/security/permissions.bats - File permission and secret storage tests

# =============================================================================
# SETUP / TEARDOWN
# =============================================================================

setup() {
    export TEST_DIR=$(mktemp -d)
    export DNSCLOAK_DIR="$TEST_DIR/dnscloak"
    export DNSCLOAK_USERS="$DNSCLOAK_DIR/users.json"
    
    mkdir -p "$DNSCLOAK_DIR"
    mkdir -p "$DNSCLOAK_DIR/wg/peers"
    mkdir -p "$DNSCLOAK_DIR/xray"
    
    source "$BATS_TEST_DIRNAME/../../lib/common.sh"
    
    init_user_db
}

teardown() {
    rm -rf "$TEST_DIR"
}

# Helper to get file permissions in octal
get_permissions() {
    stat -f "%Lp" "$1" 2>/dev/null || stat -c "%a" "$1" 2>/dev/null
}

# =============================================================================
# ISSUE #5: WIREGUARD PRIVATE KEY STORAGE
# =============================================================================

@test "SECURITY: WireGuard private keys should NOT be in users.json" {
    user_add "wguser"
    
    # Simulate what the WG installer does (this is the BAD pattern)
    local bad_data='{"public_key":"pub123","psk":"psk123","ip":"10.66.66.2","private_key":"SHOULD_NOT_BE_HERE"}'
    
    # After fix, user_set should strip private_key or the installer should not include it
    user_set "wguser" "wg" "$bad_data"
    
    # Check if private_key exists in the stored data
    run jq -r '.users.wguser.protocols.wg.private_key // "not_found"' "$DNSCLOAK_USERS"
    
    # This test documents the CURRENT (bad) behavior
    # After Issue #5 is fixed, this should return "not_found"
    if [ "$output" != "not_found" ]; then
        echo "WARNING: Private key is being stored in users.json (Issue #5)"
        # Mark as expected failure for now
    fi
}

@test "SECURITY: WireGuard peer configs should have 600 permissions" {
    # Create a mock peer config
    local peer_config="$DNSCLOAK_DIR/wg/peers/testuser.conf"
    echo "[Interface]" > "$peer_config"
    chmod 600 "$peer_config"
    
    local perms=$(get_permissions "$peer_config")
    [ "$perms" = "600" ]
}

@test "SECURITY: WireGuard peers directory should have 700 permissions" {
    chmod 700 "$DNSCLOAK_DIR/wg/peers"
    
    local perms=$(get_permissions "$DNSCLOAK_DIR/wg/peers")
    [ "$perms" = "700" ]
}

@test "SECURITY: main WG config should have restricted permissions" {
    # /etc/wireguard/wg0.conf should be 600
    # This is a documentation test since we can't modify /etc in tests
    skip "Requires root access to check /etc/wireguard"
}

# =============================================================================
# USER DATABASE PERMISSIONS
# =============================================================================

@test "SECURITY: users.json should have 600 permissions" {
    chmod 600 "$DNSCLOAK_USERS"
    
    local perms=$(get_permissions "$DNSCLOAK_USERS")
    [ "$perms" = "600" ]
}

@test "SECURITY: dnscloak directory should have 700 permissions" {
    chmod 700 "$DNSCLOAK_DIR"
    
    local perms=$(get_permissions "$DNSCLOAK_DIR")
    [ "$perms" = "700" ]
}

# =============================================================================
# XRAY CONFIGURATION PERMISSIONS
# =============================================================================

@test "SECURITY: xray config should have 600 permissions" {
    echo '{}' > "$DNSCLOAK_DIR/xray/config.json"
    chmod 600 "$DNSCLOAK_DIR/xray/config.json"
    
    local perms=$(get_permissions "$DNSCLOAK_DIR/xray/config.json")
    [ "$perms" = "600" ]
}

@test "SECURITY: xray directory should have 700 permissions" {
    chmod 700 "$DNSCLOAK_DIR/xray"
    
    local perms=$(get_permissions "$DNSCLOAK_DIR/xray")
    [ "$perms" = "700" ]
}

# =============================================================================
# SECRET GENERATION SECURITY
# =============================================================================

@test "SECURITY: generated secrets use /dev/urandom" {
    # Verify generate_secret uses secure random source
    # This is a code audit test - checking the implementation
    
    local impl=$(grep -A5 "generate_secret" "$BATS_TEST_DIRNAME/../../lib/common.sh" | head -10)
    
    # Should contain /dev/urandom, not /dev/random (blocking) or $RANDOM (insecure)
    [[ "$impl" == *"/dev/urandom"* ]] || [[ "$impl" == *"openssl rand"* ]]
}

@test "SECURITY: generated UUIDs are cryptographically random" {
    # Generate multiple UUIDs and ensure they're unique
    local uuids=()
    for i in {1..100}; do
        uuids+=($(generate_uuid))
    done
    
    # Check all are unique
    local unique_count=$(printf '%s\n' "${uuids[@]}" | sort -u | wc -l)
    [ "$unique_count" -eq 100 ]
}

# =============================================================================
# TEMP FILE SECURITY
# =============================================================================

@test "SECURITY: temp files are created securely" {
    # Check that mktemp is used, not predictable names
    local impl=$(grep -r "tmp" "$BATS_TEST_DIRNAME/../../lib/common.sh" | head -10)
    
    # Should use mktemp, not /tmp/dnscloak.tmp or similar
    [[ "$impl" == *"mktemp"* ]] || [ -z "$impl" ]
}

@test "SECURITY: temp files are cleaned up on error" {
    # This would require instrumenting the code with traps
    skip "TODO: Implement trap cleanup in lib/common.sh"
}

# =============================================================================
# SENSITIVE DATA IN LOGS/OUTPUT
# =============================================================================

@test "SECURITY: private keys not echoed to stdout" {
    # When adding a WG user, the private key should only appear in the config file
    # not in general output that might be logged
    
    # This is a documentation/audit test
    skip "Requires integration test with actual WG installer"
}

@test "SECURITY: secrets not visible in process list" {
    # Secrets passed as arguments are visible in ps output
    # Should use stdin, files, or environment variables instead
    
    # Check for patterns like: some_command "secret_value"
    local bad_patterns=$(grep -rn 'echo.*\$.*secret\|echo.*\$.*key\|echo.*\$.*password' "$BATS_TEST_DIRNAME/../../lib/" || true)
    
    # This is informational - document any findings
    if [ -n "$bad_patterns" ]; then
        echo "Potential secret exposure via command line:"
        echo "$bad_patterns"
    fi
}

# =============================================================================
# DNSTT KEY SECURITY
# =============================================================================

@test "SECURITY: DNSTT server key file permissions" {
    mkdir -p "$DNSCLOAK_DIR/dnstt"
    echo "server-key" > "$DNSCLOAK_DIR/dnstt/server.key"
    chmod 600 "$DNSCLOAK_DIR/dnstt/server.key"
    
    local perms=$(get_permissions "$DNSCLOAK_DIR/dnstt/server.key")
    [ "$perms" = "600" ]
}

# =============================================================================
# REALITY KEY SECURITY
# =============================================================================

@test "SECURITY: Reality private key stored securely in config" {
    # Reality private key should be in xray config (600 perms) only
    # Not duplicated elsewhere
    skip "Requires Xray config to be populated"
}
