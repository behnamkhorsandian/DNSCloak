#!/bin/bash
#===============================================================================
# SOS Binary Build Script
#
# Builds standalone executables for all platforms.
# Requires: PyInstaller, Go (for DNSTT), cross-compilation tools
#
# Usage:
#   ./build.sh              # Build for current platform
#   ./build.sh all          # Build for all platforms (requires Docker)
#   ./build.sh darwin-arm64 # Build for specific platform
#===============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/dist"
BIN_DIR="$PROJECT_ROOT/bin"

# DNSTT repository
DNSTT_REPO="https://www.bamsoftware.com/git/dnstt.git"
DNSTT_PUBKEY=""  # Get from your DNSTT server

# Platforms to build
PLATFORMS=(
    "linux-amd64"
    "linux-arm64"
    "darwin-amd64"
    "darwin-arm64"
    "windows-amd64"
)

print_step() { echo -e "\n>>> $1"; }
print_success() { echo "[+] $1"; }
print_error() { echo "[-] $1"; }

#-------------------------------------------------------------------------------
# Build DNSTT client binaries
#-------------------------------------------------------------------------------
build_dnstt() {
    local platform="$1"
    local goos goarch output
    
    case "$platform" in
        linux-amd64)   goos=linux;   goarch=amd64; output="dnstt-client-linux-amd64" ;;
        linux-arm64)   goos=linux;   goarch=arm64; output="dnstt-client-linux-arm64" ;;
        darwin-amd64)  goos=darwin;  goarch=amd64; output="dnstt-client-darwin-amd64" ;;
        darwin-arm64)  goos=darwin;  goarch=arm64; output="dnstt-client-darwin-arm64" ;;
        windows-amd64) goos=windows; goarch=amd64; output="dnstt-client-windows-amd64.exe" ;;
        *)
            print_error "Unknown platform: $platform"
            return 1
            ;;
    esac
    
    print_step "Building DNSTT client for $platform..."
    
    # Create temp dir for DNSTT build
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Clone DNSTT
    git clone --depth 1 "$DNSTT_REPO" "$temp_dir/dnstt" 2>/dev/null || {
        print_error "Failed to clone DNSTT"
        rm -rf "$temp_dir"
        return 1
    }
    
    # Build
    cd "$temp_dir/dnstt/dnstt-client"
    GOOS=$goos GOARCH=$goarch CGO_ENABLED=0 go build -ldflags="-s -w" -o "$BIN_DIR/$output" . || {
        print_error "Failed to build DNSTT for $platform"
        rm -rf "$temp_dir"
        return 1
    }
    
    # Cleanup
    rm -rf "$temp_dir"
    
    print_success "Built $output"
}

#-------------------------------------------------------------------------------
# Build SOS binary
#-------------------------------------------------------------------------------
build_sos() {
    local platform="$1"
    
    print_step "Building SOS for $platform..."
    
    cd "$PROJECT_ROOT"
    
    # Ensure dependencies
    pip install -q pyinstaller textual pynacl httpx argon2-cffi
    
    # Build with PyInstaller
    pyinstaller --clean --noconfirm src/sos/sos.spec
    
    print_success "Built SOS for $platform"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
main() {
    local target="${1:-current}"
    
    mkdir -p "$BIN_DIR" "$BUILD_DIR"
    
    case "$target" in
        all)
            for platform in "${PLATFORMS[@]}"; do
                build_dnstt "$platform"
            done
            print_step "Building SOS binaries..."
            print_error "Cross-platform PyInstaller builds require Docker. Use GitHub Actions instead."
            ;;
        current)
            # Detect current platform
            local os arch
            os=$(uname -s | tr '[:upper:]' '[:lower:]')
            arch=$(uname -m)
            [[ "$arch" == "x86_64" ]] && arch="amd64"
            [[ "$arch" == "aarch64" ]] && arch="arm64"
            
            local platform="${os}-${arch}"
            
            build_dnstt "$platform"
            build_sos "$platform"
            
            print_step "Done!"
            echo "Binary: $BUILD_DIR/sos-${platform}"
            ;;
        *)
            build_dnstt "$target"
            # For cross-platform SOS, need Docker
            if [[ "$target" == "$(uname -s | tr '[:upper:]' '[:lower:]')-"* ]]; then
                build_sos "$target"
            else
                print_error "Cross-platform SOS builds require Docker. Use GitHub Actions."
            fi
            ;;
    esac
}

main "$@"
