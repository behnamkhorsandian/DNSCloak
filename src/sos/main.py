#!/usr/bin/env python3
"""
SOS - Emergency Secure Chat

Standalone binary entry point that:
1. Starts bundled DNSTT client in background
2. Launches TUI chat interface
3. Cleans up DNSTT on exit

Usage:
    ./sos              # Start TUI chat (auto-manages DNSTT)
    ./sos --proxy      # Proxy-only mode (DNSTT for 1 hour)
    ./sos --help       # Show help
"""

import os
import sys
import time
import signal
import atexit
import argparse
import subprocess
import tempfile
import shutil
from pathlib import Path
from typing import Optional


# DNSTT Configuration
DNSTT_DOH_URL = "https://cloudflare-dns.com/dns-query"
DNSTT_DOMAIN = "t.dnscloak.net"
# Pubkey: Embedded at build time via GitHub Actions, or read from env for dev
DNSTT_PUBKEY = os.environ.get("DNSTT_PUBKEY", "")
DNSTT_SOCKS_PORT = 10800
PROXY_TIMEOUT_HOURS = 1

# Global process reference for cleanup
_dnstt_process: Optional[subprocess.Popen] = None
_dnstt_binary_path: Optional[Path] = None


def get_bundled_dnstt_path() -> Optional[Path]:
    """
    Get path to bundled dnstt-client binary.
    
    When running as PyInstaller bundle, binaries are in _MEIPASS.
    When running from source, look in known locations.
    """
    # PyInstaller bundle
    if hasattr(sys, '_MEIPASS'):
        base_path = Path(sys._MEIPASS)
    else:
        # Running from source - check relative paths
        base_path = Path(__file__).parent.parent.parent
    
    # Platform-specific binary name
    if sys.platform == 'win32':
        binary_name = 'dnstt-client.exe'
    else:
        binary_name = 'dnstt-client'
    
    # Check bundled location
    bundled = base_path / 'bin' / binary_name
    if bundled.exists():
        return bundled
    
    # Check system PATH
    system_binary = shutil.which('dnstt-client')
    if system_binary:
        return Path(system_binary)
    
    return None


def extract_dnstt_binary() -> Optional[Path]:
    """
    Extract bundled DNSTT binary to temp directory.
    Returns path to extracted binary.
    """
    global _dnstt_binary_path
    
    bundled = get_bundled_dnstt_path()
    if not bundled:
        return None
    
    # If it's already in PATH, use directly
    if bundled.parent.name != 'bin':
        return bundled
    
    # Extract to temp directory
    temp_dir = Path(tempfile.mkdtemp(prefix='sos-dnstt-'))
    if sys.platform == 'win32':
        extracted = temp_dir / 'dnstt-client.exe'
    else:
        extracted = temp_dir / 'dnstt-client'
    
    shutil.copy2(bundled, extracted)
    
    # Make executable on Unix
    if sys.platform != 'win32':
        os.chmod(extracted, 0o755)
    
    _dnstt_binary_path = extracted
    return extracted


def start_dnstt() -> bool:
    """
    Start DNSTT client in background.
    Returns True if started successfully.
    """
    global _dnstt_process
    
    dnstt_path = extract_dnstt_binary()
    if not dnstt_path:
        print("\n  [!] DNSTT client not found.")
        print("      For development, install dnstt-client in PATH.")
        print("      For production, use the pre-built binary.\n")
        return False
    
    # Build command
    cmd = [
        str(dnstt_path),
        '-doh', DNSTT_DOH_URL,
    ]
    
    # Add pubkey if configured
    if DNSTT_PUBKEY:
        cmd.extend(['-pubkey-file', '-'])  # Will pipe pubkey
    
    cmd.extend([
        DNSTT_DOMAIN,
        f'127.0.0.1:{DNSTT_SOCKS_PORT}'
    ])
    
    try:
        # Start DNSTT process
        if DNSTT_PUBKEY:
            _dnstt_process = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            _dnstt_process.stdin.write(DNSTT_PUBKEY.encode())
            _dnstt_process.stdin.close()
        else:
            _dnstt_process = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        
        # Wait for SOCKS proxy to be ready
        time.sleep(2)
        
        if _dnstt_process.poll() is not None:
            print("\n  [!] DNSTT client failed to start.\n")
            return False
        
        return True
        
    except FileNotFoundError:
        print(f"\n  [!] Could not execute: {dnstt_path}\n")
        return False
    except Exception as e:
        print(f"\n  [!] Failed to start DNSTT: {e}\n")
        return False


def stop_dnstt():
    """Stop DNSTT client and cleanup."""
    global _dnstt_process, _dnstt_binary_path
    
    if _dnstt_process:
        try:
            _dnstt_process.terminate()
            _dnstt_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            _dnstt_process.kill()
        except Exception:
            pass
        _dnstt_process = None
    
    # Cleanup extracted binary
    if _dnstt_binary_path and _dnstt_binary_path.exists():
        try:
            temp_dir = _dnstt_binary_path.parent
            shutil.rmtree(temp_dir)
        except Exception:
            pass
        _dnstt_binary_path = None


def signal_handler(signum, frame):
    """Handle interrupt signals gracefully."""
    stop_dnstt()
    sys.exit(0)


def run_proxy_mode():
    """
    Run in proxy-only mode.
    Starts DNSTT and keeps it running for 1 hour.
    """
    print("\n  SOS - Proxy Mode")
    print("  ================\n")
    
    print("  [*] Starting DNSTT tunnel...")
    
    if not start_dnstt():
        return 1
    
    print(f"  [+] SOCKS5 proxy running on 127.0.0.1:{DNSTT_SOCKS_PORT}")
    print(f"  [*] Auto-disconnect in {PROXY_TIMEOUT_HOURS} hour(s).")
    print("  [*] Press Ctrl+C to stop.\n")
    print("  Usage examples:")
    print(f"    curl --socks5 127.0.0.1:{DNSTT_SOCKS_PORT} http://example.com")
    print(f"    Browser: Set SOCKS5 proxy to 127.0.0.1:{DNSTT_SOCKS_PORT}")
    print("")
    
    try:
        # Wait for timeout or interrupt
        end_time = time.time() + (PROXY_TIMEOUT_HOURS * 3600)
        while time.time() < end_time:
            if _dnstt_process and _dnstt_process.poll() is not None:
                print("\n  [!] DNSTT process died unexpectedly.\n")
                return 1
            time.sleep(1)
        
        print("\n  [*] Timeout reached. Disconnecting...\n")
        
    except KeyboardInterrupt:
        print("\n\n  [*] Interrupted. Disconnecting...\n")
    
    return 0


def run_tui_mode():
    """
    Run TUI chat mode.
    Starts DNSTT, launches TUI, cleans up on exit.
    """
    print("\n  [*] Starting DNSTT tunnel...")
    
    if not start_dnstt():
        # For development without DNSTT, allow running with direct relay
        relay_host = os.environ.get('SOS_RELAY_HOST')
        if relay_host:
            print(f"  [*] Using direct relay connection to {relay_host}")
        else:
            print("  [!] Set SOS_RELAY_HOST for direct connection (dev mode)")
            return 1
    else:
        print(f"  [+] DNSTT tunnel ready (SOCKS5 on :{DNSTT_SOCKS_PORT})")
    
    print("  [*] Launching SOS Chat...\n")
    time.sleep(1)
    
    try:
        # Import and run the TUI app
        from .app import SOSApp
        app = SOSApp()
        app.run()
        return 0
        
    except ImportError as e:
        print(f"\n  [!] Failed to import TUI: {e}")
        print("      Make sure textual is installed: pip install textual\n")
        return 1
    except Exception as e:
        print(f"\n  [!] TUI error: {e}\n")
        return 1


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='SOS - Emergency Secure Chat over DNS Tunnel',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  ./sos              Start chat (auto-manages DNSTT tunnel)
  ./sos --proxy      Proxy-only mode (SOCKS5 for 1 hour)
  
During blackouts, SOS tunnels all traffic through DNS queries,
bypassing HTTPS blocks and deep packet inspection.
        """
    )
    
    parser.add_argument(
        '--proxy', '-p',
        action='store_true',
        help='Run in proxy-only mode (SOCKS5 proxy for 1 hour)'
    )
    
    parser.add_argument(
        '--version', '-v',
        action='version',
        version='SOS 1.0.0'
    )
    
    args = parser.parse_args()
    
    # Register cleanup handlers
    atexit.register(stop_dnstt)
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        if args.proxy:
            return run_proxy_mode()
        else:
            return run_tui_mode()
    finally:
        stop_dnstt()


if __name__ == '__main__':
    sys.exit(main())
