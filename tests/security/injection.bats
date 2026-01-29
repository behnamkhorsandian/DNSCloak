#!/usr/bin/env bats
# tests/security/injection.bats - Security tests for injection vulnerabilities

# =============================================================================
# SETUP / TEARDOWN
# =============================================================================

setup() {
    export TEST_DIR=$(mktemp -d)
    export DNSCLOAK_DIR="$TEST_DIR/dnscloak"
    export DNSCLOAK_USERS="$DNSCLOAK_DIR/users.json"
    
    mkdir -p "$DNSCLOAK_DIR"
    
    source "$BATS_TEST_DIRNAME/../../lib/common.sh"
    
    init_user_db
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# ISSUE #7: JQ INJECTION TESTS
# =============================================================================

@test "SECURITY: username with double quotes is handled safely" {
    # This should either reject the username or properly escape it
    run user_add 'test"user'
    
    # If it succeeds, the database should still be valid JSON
    if [ "$status" -eq 0 ]; then
        run jq '.' "$DNSCLOAK_USERS"
        [ "$status" -eq 0 ]
    fi
    # If it fails, that's also acceptable (input validation)
}

@test "SECURITY: username with backslash is handled safely" {
    run user_add 'test\user'
    
    if [ "$status" -eq 0 ]; then
        run jq '.' "$DNSCLOAK_USERS"
        [ "$status" -eq 0 ]
    fi
}

@test "SECURITY: username with single quote is handled safely" {
    run user_add "test'user"
    
    if [ "$status" -eq 0 ]; then
        run jq '.' "$DNSCLOAK_USERS"
        [ "$status" -eq 0 ]
    fi
}

@test "SECURITY: username with newline is rejected" {
    # Newlines in usernames should definitely be rejected
    run user_add $'test\nuser'
    [ "$status" -eq 1 ]
}

@test "SECURITY: username with command substitution is safe" {
    # Attempt command injection via username
    run user_add '$(whoami)'
    
    if [ "$status" -eq 0 ]; then
        # Should be stored literally, not executed
        run jq -r '.users | keys[]' "$DNSCLOAK_USERS"
        [[ "$output" == *'$(whoami)'* ]]
        # And database should be valid
        run jq '.' "$DNSCLOAK_USERS"
        [ "$status" -eq 0 ]
    fi
}

@test "SECURITY: username with backticks is safe" {
    run user_add '`whoami`'
    
    if [ "$status" -eq 0 ]; then
        run jq '.' "$DNSCLOAK_USERS"
        [ "$status" -eq 0 ]
    fi
}

@test "SECURITY: username with null byte is rejected" {
    run user_add $'test\x00user'
    [ "$status" -eq 1 ]
}

@test "SECURITY: username with JSON array injection" {
    # Attempt to break JSON structure
    run user_add '","protocols":{"hacked":true},"x":"'
    
    if [ "$status" -eq 0 ]; then
        # Database must remain valid JSON
        run jq '.' "$DNSCLOAK_USERS"
        [ "$status" -eq 0 ]
        # And the injection should not have worked
        run jq '.users | to_entries | .[0].value.protocols.hacked // false' "$DNSCLOAK_USERS"
        [ "$output" = "false" ]
    fi
}

@test "SECURITY: protocol data with malicious JSON" {
    user_add "testuser"
    
    # Attempt to inject via protocol data
    run user_set "testuser" "test" '{"uuid":"valid"},"injected":{"bad":"data"}'
    
    # Should either fail or properly handle
    run jq '.' "$DNSCLOAK_USERS"
    [ "$status" -eq 0 ]
}

# =============================================================================
# SHELL INJECTION VIA DOMAIN/INPUT
# =============================================================================

@test "SECURITY: domain with semicolon is handled safely" {
    # Test in server_set which might be used with domain
    run server_set "domain" "example.com; rm -rf /"
    
    if [ "$status" -eq 0 ]; then
        run jq '.' "$DNSCLOAK_USERS"
        [ "$status" -eq 0 ]
        # Should be stored literally
        run server_get "domain"
        [[ "$output" == *"example.com; rm -rf /"* ]]
    fi
}

@test "SECURITY: domain with pipe is handled safely" {
    run server_set "domain" "example.com | cat /etc/passwd"
    
    if [ "$status" -eq 0 ]; then
        run jq '.' "$DNSCLOAK_USERS"
        [ "$status" -eq 0 ]
    fi
}

# =============================================================================
# PATH TRAVERSAL
# =============================================================================

@test "SECURITY: username with path traversal" {
    run user_add "../../../etc/passwd"
    
    if [ "$status" -eq 0 ]; then
        run jq '.' "$DNSCLOAK_USERS"
        [ "$status" -eq 0 ]
    fi
}

@test "SECURITY: username with absolute path" {
    run user_add "/etc/passwd"
    
    if [ "$status" -eq 0 ]; then
        run jq '.' "$DNSCLOAK_USERS"
        [ "$status" -eq 0 ]
    fi
}

# =============================================================================
# UNICODE / ENCODING ATTACKS
# =============================================================================

@test "SECURITY: username with unicode characters" {
    run user_add "tëst_üsér_日本語"
    
    if [ "$status" -eq 0 ]; then
        run jq '.' "$DNSCLOAK_USERS"
        [ "$status" -eq 0 ]
    fi
}

@test "SECURITY: username with zero-width characters" {
    # Zero-width space (U+200B)
    run user_add $'test\xe2\x80\x8buser'
    
    if [ "$status" -eq 0 ]; then
        run jq '.' "$DNSCLOAK_USERS"
        [ "$status" -eq 0 ]
    fi
}

# =============================================================================
# LARGE INPUT ATTACKS
# =============================================================================

@test "SECURITY: extremely long username is rejected" {
    local long_username=$(printf 'a%.0s' {1..10000})
    run user_add "$long_username"
    [ "$status" -eq 1 ]
}

@test "SECURITY: extremely long protocol data is handled" {
    user_add "testuser"
    local long_value=$(printf 'a%.0s' {1..100000})
    run user_set "testuser" "test" "{\"data\":\"$long_value\"}"
    
    # Should either reject or handle without crashing
    run jq '.' "$DNSCLOAK_USERS"
    [ "$status" -eq 0 ]
}

# =============================================================================
# INPUT VALIDATION RECOMMENDATIONS
# =============================================================================

@test "RECOMMENDATION: usernames should be alphanumeric with limited special chars" {
    # Valid usernames
    run user_add "validuser123"
    [ "$status" -eq 0 ]
    
    run user_add "valid-user"
    [ "$status" -eq 0 ]
    
    run user_add "valid_user"
    [ "$status" -eq 0 ]
    
    # These should ideally be rejected in a secure implementation
    # (marked as skip if current implementation allows them)
}

@test "RECOMMENDATION: implement username regex validation" {
    skip "TODO: Implement username validation with regex [a-zA-Z0-9_-]+"
    
    # After fix, these should all fail:
    run user_add 'user with spaces'
    [ "$status" -eq 1 ]
    
    run user_add 'user@domain.com'
    [ "$status" -eq 1 ]
    
    run user_add 'user<script>'
    [ "$status" -eq 1 ]
}
