#!/bin/bash
# tests/run-tests.sh - Main test runner for DNSCloak
#
# Usage:
#   ./tests/run-tests.sh              # Run all tests
#   ./tests/run-tests.sh bash         # Run only bash tests
#   ./tests/run-tests.sh workers      # Run only worker tests
#   ./tests/run-tests.sh security     # Run only security tests
#   ./tests/run-tests.sh --ci         # Run in CI mode (stricter)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
BASH_TESTS_PASSED=0
BASH_TESTS_FAILED=0
WORKER_TESTS_PASSED=0
WORKER_TESTS_FAILED=0

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_result() {
    if [ "$1" -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
    else
        echo -e "${RED}✗ $2${NC}"
    fi
}

# =============================================================================
# DEPENDENCY CHECKS
# =============================================================================

check_dependencies() {
    print_header "Checking Dependencies"
    
    local missing_deps=0
    
    # Check for bats
    if command -v bats &> /dev/null; then
        echo -e "${GREEN}✓ bats-core found${NC}"
    else
        echo -e "${YELLOW}! bats-core not found - installing...${NC}"
        if command -v brew &> /dev/null; then
            brew install bats-core
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y bats
        else
            echo -e "${RED}✗ Cannot install bats-core. Please install manually.${NC}"
            echo "   brew install bats-core  (macOS)"
            echo "   apt-get install bats    (Ubuntu/Debian)"
            missing_deps=1
        fi
    fi
    
    # Check for jq
    if command -v jq &> /dev/null; then
        echo -e "${GREEN}✓ jq found${NC}"
    else
        echo -e "${RED}✗ jq not found - required for tests${NC}"
        missing_deps=1
    fi
    
    # Check for Node.js (for worker tests)
    if command -v node &> /dev/null; then
        echo -e "${GREEN}✓ node found ($(node --version))${NC}"
    else
        echo -e "${YELLOW}! node not found - worker tests will be skipped${NC}"
    fi
    
    # Check for npm/pnpm
    if command -v pnpm &> /dev/null; then
        echo -e "${GREEN}✓ pnpm found${NC}"
    elif command -v npm &> /dev/null; then
        echo -e "${GREEN}✓ npm found${NC}"
    else
        echo -e "${YELLOW}! npm/pnpm not found - worker tests will be skipped${NC}"
    fi
    
    return $missing_deps
}

# =============================================================================
# BASH TESTS (lib/*.sh, cli/*.sh)
# =============================================================================

run_bash_tests() {
    print_header "Running Bash Tests"
    
    if ! command -v bats &> /dev/null; then
        echo -e "${YELLOW}Skipping bash tests - bats not installed${NC}"
        return 0
    fi
    
    local test_dirs=(
        "$SCRIPT_DIR/lib"
        "$SCRIPT_DIR/cli"
        "$SCRIPT_DIR/security"
    )
    
    local total_passed=0
    local total_failed=0
    
    for dir in "${test_dirs[@]}"; do
        if [ -d "$dir" ] && ls "$dir"/*.bats &> /dev/null 2>&1; then
            echo -e "${BLUE}Testing: $dir${NC}"
            
            for test_file in "$dir"/*.bats; do
                echo -e "  Running: $(basename "$test_file")"
                
                if bats --tap "$test_file"; then
                    ((total_passed++))
                else
                    ((total_failed++))
                fi
            done
        fi
    done
    
    BASH_TESTS_PASSED=$total_passed
    BASH_TESTS_FAILED=$total_failed
    
    echo ""
    if [ $total_failed -eq 0 ]; then
        echo -e "${GREEN}All bash tests passed ($total_passed test files)${NC}"
    else
        echo -e "${RED}$total_failed bash test file(s) failed${NC}"
    fi
    
    return $total_failed
}

# =============================================================================
# WORKER TESTS (TypeScript/Vitest)
# =============================================================================

run_worker_tests() {
    print_header "Running Worker Tests"
    
    if ! command -v node &> /dev/null; then
        echo -e "${YELLOW}Skipping worker tests - node not installed${NC}"
        return 0
    fi
    
    cd "$PROJECT_ROOT/workers"
    
    # Install dependencies if needed
    if [ ! -d "node_modules" ]; then
        echo "Installing worker dependencies..."
        if command -v pnpm &> /dev/null; then
            pnpm install
        else
            npm install
        fi
    fi
    
    # Run tests
    echo "Running vitest..."
    if command -v pnpm &> /dev/null; then
        if pnpm vitest run --reporter=verbose; then
            WORKER_TESTS_PASSED=1
        else
            WORKER_TESTS_FAILED=1
        fi
    else
        if npm run test 2>/dev/null || npx vitest run --reporter=verbose; then
            WORKER_TESTS_PASSED=1
        else
            WORKER_TESTS_FAILED=1
        fi
    fi
    
    cd "$PROJECT_ROOT"
    
    return $WORKER_TESTS_FAILED
}

# =============================================================================
# SECURITY-SPECIFIC TESTS
# =============================================================================

run_security_tests() {
    print_header "Running Security Tests"
    
    if ! command -v bats &> /dev/null; then
        echo -e "${YELLOW}Skipping security tests - bats not installed${NC}"
        return 0
    fi
    
    local security_dir="$SCRIPT_DIR/security"
    local failed=0
    
    if [ -d "$security_dir" ]; then
        for test_file in "$security_dir"/*.bats; do
            echo -e "${BLUE}Security Test: $(basename "$test_file")${NC}"
            
            if ! bats --tap "$test_file"; then
                ((failed++))
            fi
        done
    else
        echo -e "${YELLOW}No security tests found${NC}"
    fi
    
    return $failed
}

# =============================================================================
# SHELLCHECK LINTING
# =============================================================================

run_shellcheck() {
    print_header "Running ShellCheck"
    
    if ! command -v shellcheck &> /dev/null; then
        echo -e "${YELLOW}shellcheck not found - skipping lint${NC}"
        return 0
    fi
    
    local files_to_check=(
        "$PROJECT_ROOT/lib/"*.sh
        "$PROJECT_ROOT/cli/"*.sh
        "$PROJECT_ROOT/services/"*/*.sh
    )
    
    local errors=0
    
    for file in "${files_to_check[@]}"; do
        if [ -f "$file" ]; then
            echo -n "Checking $(basename "$file")... "
            if shellcheck -e SC1091 -e SC2034 "$file" 2>/dev/null; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}ISSUES${NC}"
                ((errors++))
            fi
        fi
    done
    
    if [ $errors -eq 0 ]; then
        echo -e "${GREEN}All files passed shellcheck${NC}"
    else
        echo -e "${YELLOW}$errors file(s) have shellcheck warnings${NC}"
    fi
    
    return 0  # Don't fail on shellcheck warnings
}

# =============================================================================
# SYNTAX CHECK
# =============================================================================

run_syntax_check() {
    print_header "Running Syntax Check"
    
    local files_to_check=(
        "$PROJECT_ROOT/lib/"*.sh
        "$PROJECT_ROOT/cli/"*.sh
        "$PROJECT_ROOT/services/"*/*.sh
    )
    
    local errors=0
    
    for file in "${files_to_check[@]}"; do
        if [ -f "$file" ]; then
            echo -n "Syntax check $(basename "$file")... "
            if bash -n "$file" 2>/dev/null; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}ERROR${NC}"
                bash -n "$file"  # Show the actual error
                ((errors++))
            fi
        fi
    done
    
    return $errors
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local run_bash=true
    local run_workers=true
    local run_security=true
    local ci_mode=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            bash)
                run_workers=false
                run_security=false
                ;;
            workers)
                run_bash=false
                run_security=false
                ;;
            security)
                run_bash=false
                run_workers=false
                ;;
            --ci)
                ci_mode=true
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: $0 [bash|workers|security] [--ci]"
                exit 1
                ;;
        esac
        shift
    done
    
    print_header "DNSCloak Test Suite"
    
    # Check dependencies
    if ! check_dependencies; then
        echo -e "${RED}Missing dependencies. Please install and try again.${NC}"
        exit 1
    fi
    
    # Run syntax check first
    if ! run_syntax_check; then
        echo -e "${RED}Syntax errors found. Fix before running tests.${NC}"
        exit 1
    fi
    
    local total_failures=0
    
    # Run requested test suites
    if $run_bash; then
        if ! run_bash_tests; then
            ((total_failures++))
        fi
    fi
    
    if $run_security; then
        if ! run_security_tests; then
            ((total_failures++))
        fi
    fi
    
    if $run_workers; then
        if ! run_worker_tests; then
            ((total_failures++))
        fi
    fi
    
    # Run shellcheck (non-blocking)
    run_shellcheck
    
    # Print summary
    print_header "Test Summary"
    
    echo "Bash Tests:    $BASH_TESTS_PASSED passed, $BASH_TESTS_FAILED failed"
    echo "Worker Tests:  $WORKER_TESTS_PASSED passed, $WORKER_TESTS_FAILED failed"
    echo ""
    
    if [ $total_failures -eq 0 ]; then
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        echo -e "${GREEN}  All tests passed!                     ${NC}"
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        exit 0
    else
        echo -e "${RED}════════════════════════════════════════${NC}"
        echo -e "${RED}  $total_failures test suite(s) failed  ${NC}"
        echo -e "${RED}════════════════════════════════════════${NC}"
        exit 1
    fi
}

main "$@"
