# DNSCloak Development Instructions

## Project Overview

DNSCloak is a multi-protocol censorship bypass platform. Each protocol runs as an independent service, all managed via the unified `dnscloak` CLI with a shared user database.

## Implementation Checklist

### Phase 1: Core Libraries [COMPLETE - v2.0.0]
- [x] `lib/cloud.sh` - Cloud provider detection and firewall auto-config
- [x] `lib/bootstrap.sh` - VM setup, prerequisites, Xray-core install
- [x] `lib/common.sh` - Shared utilities, colors, user CRUD on users.json
- [x] `lib/xray.sh` - Multi-inbound config manager for shared Xray instance
- [x] `lib/selector.sh` - Domain detection and service recommendation

### Phase 2: Services [COMPLETE]
- [x] `services/reality/install.sh` - VLESS+REALITY (no domain needed) ✅ TESTED
- [x] `services/ws/install.sh` - VLESS+WebSocket+CDN (Cloudflare) ✅ TESTED
- [x] `services/dnstt/install.sh` - DNS tunnel (emergency backup) ✅ TESTED
- [x] `services/wg/install.sh` - WireGuard VPN ✅ CREATED
- [x] `services/conduit/install.sh` - Psiphon relay node ✅ TESTED
- [x] `services/sos/install.sh` - Emergency secure chat over DNSTT ✅ TESTED
- [ ] `services/mtp/install.sh` - Refactor existing MTProto
- [ ] `services/vray/install.sh` - VLESS+TCP+TLS (requires domain)

### Phase 3: CLI and Workers [COMPLETE]
- [x] `cli/dnscloak.sh` - Unified management CLI ✅ CREATED
- [x] `workers/` - Unified Cloudflare Worker for all services ✅ DEPLOYED
  - Routes: mtp, reality, wg, vray, ws, dnstt, sos subdomains
  - DNSTT client setup: /client, /setup/linux, /setup/macos, /setup/windows
  - SOS: TUI emergency chat launcher
- [x] `www/` - Landing page on Cloudflare Pages

### Phase 4: Documentation [COMPLETE]
- [x] `docs/firewall.md` - Cloud provider firewall guides
- [x] `docs/dns.md` - DNS setup for each protocol
- [x] `docs/workers.md` - Cloudflare Workers deployment
- [x] `docs/self-hosting.md` - Self-hosting guide
- [x] `docs/protocols/reality.md` - VLESS+REALITY state machine
- [x] `docs/protocols/wg.md` - WireGuard state machine
- [x] `docs/protocols/mtp.md` - MTProto state machine
- [x] `docs/protocols/vray.md` - V2Ray state machine
- [x] `docs/protocols/ws.md` - WebSocket+CDN state machine
- [x] `docs/protocols/dnstt.md` - DNStt state machine
- [x] `docs/protocols/conduit.md` - Conduit Psiphon relay
- [x] `docs/protocols/sos.md` - SOS emergency secure chat

## Architecture

### Directory Structure (Repository)
```
lib/
  cloud.sh          # Provider detection, firewall APIs
  bootstrap.sh      # VM prep, prerequisites
  common.sh         # Shared functions, user management
  xray.sh           # Xray config management
  selector.sh       # Service recommendation
services/
  reality/install.sh
  wg/install.sh
  mtp/install.sh
  vray/install.sh
  ws/install.sh
  dnstt/install.sh
  conduit/install.sh
  sos/install.sh
src/
  sos/              # Python TUI client for emergency chat
    app.py          # Textual app with WelcomeScreen, ChatRoomScreen
    room.py         # Emoji OTP input, room state
    transport.py    # DNSTT SOCKS5 polling
    crypto.py       # NaCl encryption, Argon2id key derivation
    relay.py        # Server-side relay daemon
cli/
  dnscloak.sh       # Unified CLI
workers/
  reality/
  wg/
  mtp/
  vray/
  ws/
  dnstt/
docs/
  firewall.md
  dns.md
  workers.md
  protocols/
```

### Directory Structure (Runtime on VM)
```
/opt/dnscloak/
  users.json        # Unified user database
  xray/
    config.json     # Merged Xray config (reality + vray + ws)
    access.log
    error.log
  mtp/
    config.py
    proxy_data.sh
  wg/
    wg0.conf
    peers/
  dnstt/
    server.key
    server.pub
  sos/
    relay.py        # Chat relay daemon (runs alongside DNSTT)
/usr/local/bin/
  dnscloak          # CLI symlink
  xray              # Shared Xray binary
```

## Coding Standards

### Bash Scripts
- Use `#!/bin/bash` shebang
- Quote all variables: `"$var"` not `$var`
- Use `[[ ]]` for conditionals, not `[ ]`
- Functions: `function_name() { }` with snake_case
- Constants: UPPER_SNAKE_CASE
- Local variables: `local var_name`
- Error handling: check return codes, provide clear messages
- No emojis in output - use ASCII symbols (*, >, -, etc.)

### User Management
- All users stored in `/opt/dnscloak/users.json`
- Format:
```json
{
  "users": {
    "username": {
      "created": "2026-01-25T12:00:00Z",
      "protocols": {
        "mtp": { "secret": "hex32", "mode": "tls" },
        "reality": { "uuid": "uuid-here", "flow": "xtls-rprx-vision" },
        "wg": { "public_key": "...", "psk": "...", "ip": "10.66.66.2" }
      }
    }
  },
  "server": {
    "ip": "1.2.3.4",
    "domain": "example.com",
    "provider": "aws"
  }
}
```

### Xray Config Management
- Single config at `/opt/dnscloak/xray/config.json`
- Multiple inbounds share port 443 via SNI/path routing
- Functions in `lib/xray.sh` to add/remove inbounds and clients
- Reload via `systemctl reload xray` after changes

### Cloud Provider Detection Order
1. AWS: `curl -s http://169.254.169.254/latest/meta-data/`
2. GCP: `curl -H "Metadata-Flavor: Google" http://metadata.google.internal/`
3. Azure: `curl -H "Metadata: true" http://169.254.169.254/metadata/instance`
4. DigitalOcean: `curl -s http://169.254.169.254/metadata/v1/`
5. Vultr: `curl -s http://169.254.169.254/v1/`
6. Hetzner: `curl -s http://169.254.169.254/hetzner/v1/metadata`
7. Oracle: `curl -s http://169.254.169.254/opc/v1/instance/`
8. Linode: `curl -s http://169.254.169.254/v1/`
9. Fallback: ufw/firewalld/iptables

## Git Workflow

### Commit Messages
- `feat(scope): description` - New features
- `fix(scope): description` - Bug fixes
- `docs(scope): description` - Documentation
- `refactor(scope): description` - Code restructuring
- `test(scope): description` - Test additions

### Tags
- `v1.0.0` - Stable release
- `v1.0.0-alpha` - Pre-release testing
- `v1.0.0-lit` - Deploy to production (triggers CI/CD)

### Branch Strategy
- `main` - Stable, tested code
- `dev` - Integration branch
- `feat/*` - Feature branches

## Testing

### Local Testing
```bash
# Syntax check all scripts
find . -name "*.sh" -exec bash -n {} \;

# Shellcheck
shellcheck lib/*.sh services/*/*.sh cli/*.sh
```

### VM Testing
1. Spin up fresh Ubuntu 22.04 VM
2. Run installer: `curl -sSL <service>.dnscloak.net | sudo bash`
3. Add test user: `dnscloak add <service> testuser`
4. Verify connection from client device
5. Test user removal: `dnscloak remove <service> testuser`
6. Test uninstall: `dnscloak uninstall <service>`

## TODO (Post-MVP)
- Hysteria 2 - QUIC-based protocol for lossy networks
- AmneziaWG - Obfuscated WireGuard for Russia/Iran DPI
- Traffic limits - Per-user bandwidth quotas
- Expiry dates - Time-limited user accounts
- Subscription URLs - Auto-updating client configs
- Web dashboard - Browser-based management
- Telegram bot - User self-service

### Security Audit (stats.dnscloak.net WebSocket)
- [ ] HMAC-signed push requests from VPS (prevent spoofing)
- [ ] Origin validation (only allow dnscloak.net origins)
- [ ] Rate limiting per IP (prevent DoS)
- [ ] Cloudflare threat score filtering (block high-risk)
- [ ] Enable Bot Fight Mode on stats subdomain
- [ ] WAF rules for additional protection

## SOS Roadmap (Emergency Chat)

### Current State (v1.0 - Testing)
- Cloudflare Worker serves install script at `sos.dnscloak.net`
- TUI client downloads via curl, then connects to relay via DNSTT
- **Limitation**: Initial download CAN be blocked (uses Cloudflare HTTPS)

### Vision: Fully Unblockable SOS
The goal is for SOS to work even during TOTAL internet blackouts:
1. **VPS Owner** runs `--server` to become a relay provider over DNSTT
2. **Users** access via curl OR browser, served THROUGH DNSTT tunnel
3. Even if main website is blocked, SOS subdomain works via DNS queries

### Phase 1: Offline Executables [NEXT]
Pre-compiled binaries users download BEFORE blackout:
- [ ] `sos-linux-amd64` - Linux binary
- [ ] `sos-linux-arm64` - Linux ARM (Raspberry Pi)
- [ ] `sos-darwin-amd64` - macOS Intel
- [ ] `sos-darwin-arm64` - macOS Apple Silicon  
- [ ] `sos-windows-amd64.exe` - Windows binary

**Key Features of Offline Binary:**
1. **Bundled DNSTT Client** - No separate install needed
2. **Auto-connect on launch** - Starts DNSTT in background, shows TUI
3. **Auto-disconnect on exit** - Kills DNSTT when TUI closes
4. **Proxy-only mode** - `./sos --proxy` keeps DNSTT running for 1 hour as SOCKS5 proxy

**Architecture:**
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     OFFLINE BINARY FLOW                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   USER RUNS: ./sos-darwin-arm64                                              │
│                                                                              │
│   1. STARTUP                                                                 │
│      ┌─────────────────────────────────────────────────────────┐            │
│      │  Binary extracts bundled dnstt-client                   │            │
│      │  Spawns: dnstt-client -doh ... t.dnscloak.net :10800    │            │
│      │  Waits for SOCKS5 proxy to be ready                     │            │
│      └─────────────────────────────────────────────────────────┘            │
│                              │                                               │
│   2. TUI LAUNCH                                                              │
│      ┌─────────────────────────────────────────────────────────┐            │
│      │  SOS TUI connects to relay via SOCKS5 :10800            │            │
│      │  User creates/joins room, chats                         │            │
│      └─────────────────────────────────────────────────────────┘            │
│                              │                                               │
│   3. EXIT                                                                    │
│      ┌─────────────────────────────────────────────────────────┐            │
│      │  User quits (q or Ctrl+C)                               │            │
│      │  TUI sends SIGTERM to dnstt-client subprocess           │            │
│      │  Clean exit, no orphan processes                        │            │
│      └─────────────────────────────────────────────────────────┘            │
│                                                                              │
│   PROXY-ONLY MODE: ./sos --proxy                                             │
│      ┌─────────────────────────────────────────────────────────┐            │
│      │  Starts DNSTT, prints SOCKS5 proxy address              │            │
│      │  "SOCKS5 proxy running on 127.0.0.1:10800"              │            │
│      │  "Auto-disconnect in 1 hour. Ctrl+C to stop."           │            │
│      │  User can use proxy for any app (browser, curl, etc.)   │            │
│      └─────────────────────────────────────────────────────────┘            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Build Process:**
- Use PyInstaller with `--onefile` flag
- Bundle dnstt-client binary for each platform
- Cross-compile or use GitHub Actions for multi-platform builds
- Distribute via GitHub Releases

### Phase 2: Web Mode via DNSTT [IMPLEMENTED ✅]
Browser-based chat served entirely through DNSTT tunnel:
- [x] Relay daemon serves static HTML/JS at `/` (root)
- [x] Single-page app with inlined TweetNaCl.js + Argon2 (PBKDF2 fallback)
- [x] User configures browser SOCKS5 proxy → DNSTT client
- [x] Navigate to `http://relay:8899/` through tunnel
- [x] Full crypto interop with TUI client (same rooms!)
- [x] Polling-based messaging (1.5s interval)
- [ ] **TODO**: WebSocket for real-time chat (future enhancement)
- [ ] **TODO**: `hotline.dnscloak.net` subdomain setup

**Web Client Files:**
- `src/sos/www/index.html` - SPA with all CSS inlined (~100KB)
- `src/sos/www/app.js` - Chat logic + crypto (TweetNaCl + Argon2/PBKDF2)

Architecture for Phase 2:
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     PHASE 2: WEB MODE VIA DNSTT                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   USER'S BROWSER                                                             │
│   ┌──────────────────────────────────────────────────────────────┐           │
│   │ http://relay:8899/  (through SOCKS5 proxy)                   │           │
│   └──────────────────────────────────────────────────────────────┘           │
│                              │                                               │
│                              ▼                                               │
│   ┌──────────────────────────────────────────────────────────────┐           │
│   │         DNSTT Client (SOCKS5 proxy on localhost:10800)       │           │
│   └──────────────────────────────────────────────────────────────┘           │
│                              │                                               │
│                              │ DNS Queries (unblockable)                     │
│                              ▼                                               │
│   ┌──────────────────────────────────────────────────────────────┐           │
│   │                    DNSTT SERVER (VM)                          │           │
│   │  ┌─────────────────────────────────────────────────────────┐ │           │
│   │  │           SOS Relay Daemon (relay.py:8899)              │ │           │
│   │  │  GET /             → Serves index.html (SPA)            │ │           │
│   │  │  GET /app.js       → Serves client JavaScript           │ │           │
│   │  │  POST /room        → Create room API                    │ │           │
│   │  │  GET /room/{h}/poll → Poll messages API                 │ │           │
│   │  └─────────────────────────────────────────────────────────┘ │           │
│   └──────────────────────────────────────────────────────────────┘           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Crypto Interop (TUI ↔ Web):**
| Spec | Python (TUI) | JavaScript (Web) |
|------|--------------|------------------|
| Emoji set | 32 emojis (crypto.py) | Same 32, same order |
| Room hash | SHA256(emojis)[:16] hex | Same formula |
| KDF | Argon2id (time=2, mem=64MB) | PBKDF2 fallback* |
| Encryption | NaCl SecretBox | TweetNaCl.js |
| Wire format | Base64(nonce+ciphertext) | Same format |

*Note: Web uses PBKDF2 fallback for Argon2id. For true interop, load full argon2-browser WASM.

### Why This Matters
- **Phase 1** (Offline binaries): Users pre-download, run during blackout
- **Phase 2** (Web via DNSTT): Zero pre-download needed, browser-only access
- Both phases: Chat traffic goes through DNSTT, unblockable by DPI/IP blocks

### TLDR:
1) as the VPS owner, i use the server tag to make my server a room provider over dnstt (in my case 'sos.dnscloak.net'
2) as user i have two option, either use this url via curl on terminal, or just out it in my browser. and since its served over dnstt, it can never be blocked (even if the main website don't work, this subdomain always loads the instant chatroom.

## Current Session Context (Updated 2026-01-26)

### What's Working
- **Reality** (`services/reality/install.sh`) - Fully tested, works on GCP
- **WS+CDN** (`services/ws/install.sh`) - Fully tested, works with Cloudflare SSL "Flexible"
- **DNSTT** (`services/dnstt/install.sh`) - Fully tested, builds from source via Go 1.21
- **WireGuard** (`services/wg/install.sh`) - Created, ready for testing
- **CLI** (`cli/dnscloak.sh`) - Unified management CLI created
- **SOS** (`services/sos/install.sh`) - Emergency chat over DNSTT ✅ TESTED
  - TUI client with Textual framework
  - **Web client** (`src/sos/www/`) - Browser-based SPA served via relay ✅ NEW
  - Standalone binaries (via GitHub Actions CI/CD)
  - Auto-fallback: DNSTT → Direct relay connection
  - Default relay: `relay.dnscloak.net:8899`
  - 6-emoji room IDs + 6-digit rotating/fixed PIN
  - E2E encryption (NaCl + Argon2id)
  - Auto-wipe after 1 hour
  - Rate limiting: exponential backoff [0, 10, 30, 60, 180, 300]s
  - **TUI ↔ Web interop**: Same rooms work across clients

### Cloudflare Setup
- **Workers**: Deployed at `dnscloak` worker, handles all subdomains (reality, ws, dnstt, mtp, wg, vray, sos)
- **Worker features**: 
  - `/` - Serves install script
  - `/info` - HTML info page
  - `/client` (dnstt only) - Client setup page with one-liner scripts
  - `/setup/linux|macos|windows` (dnstt only) - Platform-specific setup scripts
- **Pages**: Landing page at `www.dnscloak.net` via direct upload of `www/` folder
- **DNS**: 
  - `*.dnscloak.net` - Worker routes
  - `www.dnscloak.net` - Cloudflare Pages
  - `ws-origin.dnscloak.net` - WS origin server (Proxied, SSL Flexible)
  - `ns1.dnscloak.net` - DNSTT nameserver (DNS only, NOT proxied)
  - `t.dnscloak.net` - NS record pointing to ns1.dnscloak.net
  - `relay.dnscloak.net` - SOS relay server (DNS only, NOT proxied) → 34.185.221.241

### Key Technical Decisions
1. **WS+CDN uses port 80 (HTTP) on origin** - Cloudflare handles TLS at edge, SSL mode must be "Flexible"
2. **DNSTT builds from source** - Downloads Go 1.21 from go.dev, builds dnstt-server
3. **User database** - `/opt/dnscloak/users.json` with format `{users: {name: {protocols: {ws: {uuid}}}}, server: {...}}`
4. **Auto-cleanup** - Scripts clean `/tmp/dnscloak*` at start for fresh installs
5. **WireGuard network** - Uses `10.66.66.0/24` subnet, server at `.1`, clients from `.2`

### Testing Environment
- **Server**: GCP VM at `34.185.221.241` (europe-west3)
- **Domain**: `dnscloak.net` on Cloudflare

### Services TODO
- [x] `services/wg/install.sh` - WireGuard VPN ✅ CREATED
- [x] `cli/dnscloak.sh` - Unified management CLI ✅ CREATED
- [x] `services/sos/install.sh` - Emergency secure chat ✅ CREATED
- [x] `src/sos/` - Python TUI client (Textual) ✅ CREATED
- [ ] `services/mtp/install.sh` - Refactor existing MTProto  
- [ ] `services/vray/install.sh` - VLESS+TCP+TLS with Let's Encrypt

### Known Issues Fixed
- `user_exists()` now supports optional protocol parameter: `user_exists "name" "ws"`
- `user_get()` now supports optional key parameter: `user_get "name" "ws" "uuid"`
- WS installer uses correct function names from lib files (cloud_get_public_ip, bootstrap, create_directories, etc.)

