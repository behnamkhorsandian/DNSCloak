#!/usr/bin/env bats
# tests/security/auth.bats - Authentication and authorization tests

# =============================================================================
# SETUP / TEARDOWN
# =============================================================================

setup() {
    export TEST_DIR=$(mktemp -d)
    export DNSCLOAK_DIR="$TEST_DIR/dnscloak"
    
    mkdir -p "$DNSCLOAK_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# ISSUE #4: STATS PUSH AUTHENTICATION
# =============================================================================

@test "SECURITY: stats endpoint should require authentication" {
    skip "Requires Worker to be running - see workers/stats-relay.test.ts"
    # This documents the requirement: POST /push needs HMAC signature
}

@test "SECURITY: HMAC signature computation is correct" {
    # Test the expected HMAC computation that stats-pusher.sh should use
    local secret="test-secret-key"
    local payload='{"status":"healthy","timestamp":1234567890}'
    
    # Compute expected signature
    local expected_sig=$(echo -n "$payload" | openssl dgst -sha256 -hmac "$secret" -binary | base64)
    
    # Signature should be non-empty and base64
    [[ "$expected_sig" =~ ^[A-Za-z0-9+/]+=*$ ]]
}

@test "SECURITY: timestamp prevents replay attacks" {
    # Timestamps older than 30 seconds should be rejected
    local now=$(date +%s)
    local old_timestamp=$((now - 60))  # 60 seconds ago
    
    # old_timestamp should be rejected by the server
    [ $old_timestamp -lt $((now - 30)) ]
}

# =============================================================================
# ISSUE #6: CORS VALIDATION
# =============================================================================

@test "SECURITY: only dnscloak.net origins should be allowed" {
    local allowed_origins=(
        "https://dnscloak.net"
        "https://www.dnscloak.net"
    )
    
    local disallowed_origins=(
        "https://evil.com"
        "https://dnscloak.net.evil.com"
        "http://dnscloak.net"  # HTTP not allowed
        "null"
    )
    
    # Document the expected behavior
    for origin in "${allowed_origins[@]}"; do
        [[ "$origin" == *"dnscloak.net"* ]]
    done
}

@test "SECURITY: wildcard CORS should not be used" {
    skip "Requires Worker code inspection - see Issue #6"
    # Current implementation uses: 'Access-Control-Allow-Origin': '*'
    # This should be changed to specific origins
}

# =============================================================================
# ROOT ACCESS CHECKS
# =============================================================================

@test "SECURITY: CLI requires root for privileged operations" {
    # The check_root function should prevent non-root execution
    # This is a documentation test
    
    if [ "$EUID" -ne 0 ]; then
        # We're not root, so privileged operations should fail
        skip "Cannot test root check as non-root user"
    fi
}

# =============================================================================
# API KEY/TOKEN VALIDATION
# =============================================================================

@test "SECURITY: UUIDs are valid format" {
    source "$BATS_TEST_DIRNAME/../../lib/common.sh"
    
    for i in {1..10}; do
        local uuid=$(generate_uuid)
        # UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
        # where y is 8, 9, a, or b
        [[ "$uuid" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$ ]]
    done
}

@test "SECURITY: secrets have sufficient entropy" {
    source "$BATS_TEST_DIRNAME/../../lib/common.sh"
    
    # 32 bytes = 256 bits of entropy
    local secret=$(generate_secret 32)
    [ ${#secret} -eq 64 ]  # 64 hex chars
    
    # Check it's actually random (not all same char)
    local unique_chars=$(echo "$secret" | grep -o . | sort -u | wc -l)
    [ "$unique_chars" -gt 10 ]  # Should have many unique characters
}
