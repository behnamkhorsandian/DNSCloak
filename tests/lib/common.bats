#!/usr/bin/env bats
# tests/lib/common.bats - User management and utility function tests

# =============================================================================
# SETUP / TEARDOWN
# =============================================================================

setup() {
    # Create isolated test environment
    export TEST_DIR=$(mktemp -d)
    export DNSCLOAK_DIR="$TEST_DIR/dnscloak"
    export DNSCLOAK_USERS="$DNSCLOAK_DIR/users.json"
    
    mkdir -p "$DNSCLOAK_DIR"
    
    # Source the library
    source "$BATS_TEST_DIRNAME/../../lib/common.sh"
    
    # Initialize empty user database
    init_user_db
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# USER DATABASE INITIALIZATION
# =============================================================================

@test "init_user_db creates valid JSON structure" {
    run jq '.' "$DNSCLOAK_USERS"
    [ "$status" -eq 0 ]
}

@test "init_user_db creates users object" {
    run jq -e '.users' "$DNSCLOAK_USERS"
    [ "$status" -eq 0 ]
}

@test "init_user_db creates server object" {
    run jq -e '.server' "$DNSCLOAK_USERS"
    [ "$status" -eq 0 ]
}

@test "init_user_db preserves existing database" {
    echo '{"users":{"existing":{"created":"2026-01-01"}},"server":{}}' > "$DNSCLOAK_USERS"
    init_user_db
    run jq -e '.users.existing' "$DNSCLOAK_USERS"
    [ "$status" -eq 0 ]
}

# =============================================================================
# USER CRUD OPERATIONS
# =============================================================================

@test "user_add creates new user" {
    run user_add "testuser"
    [ "$status" -eq 0 ]
    run jq -e '.users.testuser' "$DNSCLOAK_USERS"
    [ "$status" -eq 0 ]
}

@test "user_add sets created timestamp" {
    user_add "testuser"
    run jq -r '.users.testuser.created' "$DNSCLOAK_USERS"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "user_add initializes empty protocols" {
    user_add "testuser"
    run jq '.users.testuser.protocols | keys | length' "$DNSCLOAK_USERS"
    [ "$output" = "0" ]
}

@test "user_exists returns 0 for existing user" {
    user_add "testuser"
    run user_exists "testuser"
    [ "$status" -eq 0 ]
}

@test "user_exists returns 1 for non-existing user" {
    run user_exists "nonexistent"
    [ "$status" -eq 1 ]
}

@test "user_exists with protocol checks protocol-specific existence" {
    user_add "testuser"
    user_set "testuser" "reality" '{"uuid":"test-uuid"}'
    run user_exists "testuser" "reality"
    [ "$status" -eq 0 ]
    run user_exists "testuser" "wg"
    [ "$status" -eq 1 ]
}

@test "user_remove deletes user" {
    user_add "testuser"
    run user_remove "testuser"
    [ "$status" -eq 0 ]
    run user_exists "testuser"
    [ "$status" -eq 1 ]
}

@test "user_remove fails for non-existing user" {
    run user_remove "nonexistent"
    [ "$status" -eq 1 ]
}

@test "user_list returns all users" {
    user_add "user1"
    user_add "user2"
    user_add "user3"
    run user_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"user1"* ]]
    [[ "$output" == *"user2"* ]]
    [[ "$output" == *"user3"* ]]
}

@test "user_list filters by protocol" {
    user_add "user1"
    user_add "user2"
    user_set "user1" "reality" '{"uuid":"uuid1"}'
    run user_list "reality"
    [ "$status" -eq 0 ]
    [[ "$output" == *"user1"* ]]
    [[ "$output" != *"user2"* ]] || [ -z "$output" ]
}

@test "user_get retrieves protocol data" {
    user_add "testuser"
    user_set "testuser" "reality" '{"uuid":"test-uuid-123"}'
    run user_get "testuser" "reality"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-uuid-123"* ]]
}

@test "user_get retrieves specific key" {
    user_add "testuser"
    user_set "testuser" "reality" '{"uuid":"test-uuid-123","flow":"xtls-rprx-vision"}'
    run user_get "testuser" "reality" "uuid"
    [ "$status" -eq 0 ]
    [ "$output" = "test-uuid-123" ]
}

@test "user_set updates protocol data" {
    user_add "testuser"
    user_set "testuser" "ws" '{"uuid":"ws-uuid","path":"/ws"}'
    run jq -r '.users.testuser.protocols.ws.path' "$DNSCLOAK_USERS"
    [ "$output" = "/ws" ]
}

# =============================================================================
# SERVER CONFIGURATION
# =============================================================================

@test "server_set stores value" {
    server_set "ip" "1.2.3.4"
    run jq -r '.server.ip' "$DNSCLOAK_USERS"
    [ "$output" = "1.2.3.4" ]
}

@test "server_get retrieves value" {
    server_set "domain" "example.com"
    run server_get "domain"
    [ "$status" -eq 0 ]
    [ "$output" = "example.com" ]
}

@test "server_get returns empty for missing key" {
    run server_get "nonexistent"
    [ -z "$output" ]
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

@test "generate_uuid produces valid UUID format" {
    run generate_uuid
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]]
}

@test "generate_secret produces correct length" {
    run generate_secret 32
    [ "$status" -eq 0 ]
    [ ${#output} -eq 64 ]  # 32 bytes = 64 hex chars
}

@test "generate_secret produces hex characters only" {
    run generate_secret 16
    [[ "$output" =~ ^[a-f0-9]+$ ]]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "handles empty username gracefully" {
    run user_add ""
    [ "$status" -eq 1 ]
}

@test "handles special characters in protocol data" {
    user_add "testuser"
    user_set "testuser" "test" '{"key":"value with spaces and \"quotes\""}'
    run jq -e '.users.testuser.protocols.test' "$DNSCLOAK_USERS"
    [ "$status" -eq 0 ]
}

@test "concurrent modifications don't corrupt database" {
    # Add multiple users in quick succession
    for i in {1..10}; do
        user_add "user$i" &
    done
    wait
    
    # Verify database is valid JSON
    run jq '.' "$DNSCLOAK_USERS"
    [ "$status" -eq 0 ]
}
