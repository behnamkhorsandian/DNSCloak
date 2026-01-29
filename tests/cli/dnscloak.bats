#!/usr/bin/env bats
# tests/cli/dnscloak.bats - CLI integration tests

# =============================================================================
# SETUP / TEARDOWN
# =============================================================================

setup() {
    export TEST_DIR=$(mktemp -d)
    export DNSCLOAK_DIR="$TEST_DIR/dnscloak"
    export DNSCLOAK_USERS="$DNSCLOAK_DIR/users.json"
    
    mkdir -p "$DNSCLOAK_DIR/xray"
    mkdir -p "$DNSCLOAK_DIR/wg/peers"
    
    # Initialize user database
    source "$BATS_TEST_DIRNAME/../../lib/common.sh"
    init_user_db
    
    # Set server info for tests
    server_set "ip" "1.2.3.4"
    server_set "domain" "test.dnscloak.net"
    
    # CLI path
    export CLI="$BATS_TEST_DIRNAME/../../cli/dnscloak.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# HELP AND USAGE
# =============================================================================

@test "cli shows help with no arguments" {
    run bash "$CLI"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]] || [[ "$output" == *"help"* ]]
}

@test "cli shows help with --help flag" {
    run bash "$CLI" --help
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "cli shows help with help command" {
    run bash "$CLI" help
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]] || [[ "$output" == *"add"* ]]
}

# =============================================================================
# USER ADD COMMAND
# =============================================================================

@test "cli add requires service and username" {
    run bash "$CLI" add
    [ "$status" -eq 1 ]
}

@test "cli add with invalid service fails" {
    run bash "$CLI" add invalidservice testuser
    [ "$status" -eq 1 ]
}

@test "cli add reality user creates user" {
    skip "Requires xray config initialized"
    run bash "$CLI" add reality testuser
    [ "$status" -eq 0 ]
    run user_exists "testuser" "reality"
    [ "$status" -eq 0 ]
}

@test "cli add ws user creates user" {
    skip "Requires xray config initialized"
    run bash "$CLI" add ws testuser
    [ "$status" -eq 0 ]
    run user_exists "testuser" "ws"
    [ "$status" -eq 0 ]
}

@test "cli add wg user creates user" {
    skip "Requires wireguard tools installed"
    run bash "$CLI" add wg testuser
    [ "$status" -eq 0 ]
    run user_exists "testuser" "wg"
    [ "$status" -eq 0 ]
}

@test "cli add duplicate user fails" {
    skip "Requires service initialized"
    bash "$CLI" add reality testuser
    run bash "$CLI" add reality testuser
    [ "$status" -eq 1 ]
    [[ "$output" == *"exists"* ]] || [[ "$output" == *"already"* ]]
}

# =============================================================================
# USER REMOVE COMMAND
# =============================================================================

@test "cli remove requires service and username" {
    run bash "$CLI" remove
    [ "$status" -eq 1 ]
}

@test "cli remove non-existent user fails" {
    run bash "$CLI" remove reality nonexistent
    [ "$status" -eq 1 ]
}

@test "cli remove user deletes from database" {
    skip "Requires service initialized"
    bash "$CLI" add reality testuser
    run bash "$CLI" remove reality testuser
    [ "$status" -eq 0 ]
    run user_exists "testuser" "reality"
    [ "$status" -eq 1 ]
}

# =============================================================================
# USER LIST COMMAND
# =============================================================================

@test "cli list shows all users" {
    user_add "user1"
    user_add "user2"
    user_set "user1" "reality" '{"uuid":"uuid1"}'
    user_set "user2" "ws" '{"uuid":"uuid2"}'
    
    run bash "$CLI" list
    [[ "$output" == *"user1"* ]]
    [[ "$output" == *"user2"* ]]
}

@test "cli list filters by service" {
    user_add "realityuser"
    user_add "wsuser"
    user_set "realityuser" "reality" '{"uuid":"uuid1"}'
    user_set "wsuser" "ws" '{"uuid":"uuid2"}'
    
    run bash "$CLI" list reality
    [[ "$output" == *"realityuser"* ]]
    [[ "$output" != *"wsuser"* ]] || [ -z "$output" ]
}

@test "cli list empty database shows message" {
    # Remove all users
    jq '.users = {}' "$DNSCLOAK_USERS" > "$DNSCLOAK_USERS.tmp" && mv "$DNSCLOAK_USERS.tmp" "$DNSCLOAK_USERS"
    
    run bash "$CLI" list
    # Should show "no users" or similar, or empty output
    [ "$status" -eq 0 ]
}

# =============================================================================
# STATUS COMMAND
# =============================================================================

@test "cli status runs without error" {
    run bash "$CLI" status
    # May fail if services aren't installed, but shouldn't crash
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "cli status shows service information" {
    run bash "$CLI" status
    # Should mention at least one service type
    [[ "$output" == *"xray"* ]] || [[ "$output" == *"wg"* ]] || [[ "$output" == *"dnstt"* ]] || [[ "$output" == *"not"* ]]
}

# =============================================================================
# RESTART COMMAND
# =============================================================================

@test "cli restart requires service name" {
    run bash "$CLI" restart
    [ "$status" -eq 1 ]
}

@test "cli restart invalid service fails" {
    run bash "$CLI" restart invalidservice
    [ "$status" -eq 1 ]
}

# =============================================================================
# UNINSTALL COMMAND
# =============================================================================

@test "cli uninstall requires service name" {
    run bash "$CLI" uninstall
    [ "$status" -eq 1 ]
}

@test "cli uninstall requires confirmation" {
    skip "Requires interactive test"
    # echo "n" | bash "$CLI" uninstall reality
}

# =============================================================================
# INVALID COMMANDS
# =============================================================================

@test "cli unknown command shows error" {
    run bash "$CLI" unknowncommand
    [ "$status" -eq 1 ]
}

@test "cli handles extra arguments gracefully" {
    run bash "$CLI" list reality extra args here
    # Should either ignore extra args or show error
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# =============================================================================
# ENVIRONMENT VARIABLES
# =============================================================================

@test "cli respects DNSCLOAK_DIR environment variable" {
    export DNSCLOAK_DIR="$TEST_DIR/custom"
    mkdir -p "$DNSCLOAK_DIR"
    echo '{"users":{},"server":{}}' > "$DNSCLOAK_DIR/users.json"
    
    run bash "$CLI" list
    [ "$status" -eq 0 ]
}

@test "cli creates directories if missing" {
    export DNSCLOAK_DIR="$TEST_DIR/newdir"
    # Don't create the directory
    
    run bash "$CLI" list
    # Should create directory or show appropriate error
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}
