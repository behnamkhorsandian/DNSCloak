# Vany Development Instructions

## Project Overview

Vany is a multi-protocol censorship bypass platform. All protocols run in Docker containers, managed via a JS Cloudflare Worker TUI (server-rendered ANSI) and local bash scripts. `curl vany.sh | sudo bash` serves a thin bash client that streams UI from the Worker and executes Docker commands locally.

## Implementation Checklist

### Phase 1: Core Libraries [LEGACY]
- [x] `lib/cloud.sh` - Cloud provider detection and firewall auto-config
- [x] `lib/bootstrap.sh` - VM setup, prerequisites (superseded by docker-bootstrap.sh)
- [x] `lib/common.sh` - Shared utilities, colors, user CRUD on users.json
- [x] `lib/xray.sh` - Multi-inbound config manager for shared Xray instance
- [x] `lib/selector.sh` - Domain detection and service recommendation

### Phase 2A: Docker Infrastructure [v3.0.0]
- [x] `docker/xray/` - Shared Xray container (Reality+WS+VRAY+HTTP-Obfs)
- [x] `docker/wireguard/` - WireGuard container
- [x] `docker/dnstt/` - DNSTT server (built from source)
- [x] `docker/conduit/` - Conduit Psiphon relay
- [x] `docker/sos/` - SOS relay daemon
- [x] `docker/hysteria/` - Hysteria v2 (QUIC)
- [x] `docker/slipstream/` - Slipstream DNS tunnel
- [x] `docker/noizdns/` - NoizDNS (DPI-resistant DNSTT fork)
- [x] `docker/tor-bridge/` - Tor Bridge (obfs4)
- [x] `docker/snowflake/` - Snowflake Proxy
- [x] `scripts/docker-bootstrap.sh` - Docker install, sysctl, cloud detection, state init
- [x] `scripts/protocols/install-xray.sh` - Xray container + Reality/WS/HTTP-Obfs inbounds
- [x] `scripts/protocols/install-wireguard.sh` - WireGuard container + peer management
- [x] `scripts/protocols/install-dnstt.sh` - DNSTT container
- [x] `scripts/protocols/install-conduit.sh` - Conduit container
- [x] `scripts/protocols/install-sos.sh` - SOS relay container
- [x] `scripts/protocols/install-hysteria.sh` - Hysteria v2 container
- [x] `scripts/protocols/install-http-obfs.sh` - HTTP Obfuscation (WS+CDN + clean IPs)
- [x] `scripts/protocols/install-ssh-tunnel.sh` - SSH tunnel (restricted user)
- [x] `scripts/protocols/install-slipstream.sh` - Slipstream DNS tunnel
- [x] `scripts/protocols/install-noizdns.sh` - NoizDNS container
- [x] `scripts/protocols/install-tor-bridge.sh` - Tor Bridge container
- [x] `scripts/protocols/install-snowflake.sh` - Snowflake Proxy container
- [x] `scripts/protocols/update-container.sh` - Generic container update
- [x] `scripts/protocols/remove-container.sh` - Generic container removal
- [x] `scripts/protocols/status-containers.sh` - Container status (JSON)
- [x] `scripts/tools/cfray.sh` - Cloudflare clean IP scanner
- [x] `scripts/tools/findns.sh` - DNS resolver scanner
- [x] `scripts/tools/tracer.sh` - IP/ISP/ASN tracer
- [x] `scripts/tools/speedtest.sh` - Bandwidth test

### Phase 2B: Worker TUI [v3.0.0]
- [x] `workers/src/tui/theme.ts` - Vany color palette (green #2eb787)
- [x] `workers/src/tui/ansi.ts` - ANSI utilities (stripAnsi, visibleLen, etc.)
- [x] `workers/src/tui/box.ts` - Unicode box drawing
- [x] `workers/src/tui/table.ts` - Table renderer
- [x] `workers/src/tui/layout.ts` - Layout helpers (sideBySide, wordWrap, etc.)
- [x] `workers/src/tui/frame.ts` - Page frame (header, content, 7-tab nav bar)
- [x] `workers/src/tui/splash.ts` - Logo splash screen
- [x] `workers/src/tui/x-client.ts` - Thin bash client script
- [x] `workers/src/tui/index.ts` - TUI route handler (/tui/*)
- [x] `workers/src/tui/pages/landing.ts` - Static ANSI catalog (curl vany.sh)
- [x] `workers/src/tui/pages/protocols.ts` - Protocol catalog table (15 protocols)
- [x] `workers/src/tui/pages/install.ts` - Install wizard (15 protocols)
- [x] `workers/src/tui/pages/help.ts` - Help page with protocol comparison
- [x] `workers/src/tui/pages/client.ts` - Client connection guide + config import
- [x] `workers/src/tui/pages/tools.ts` - Network scanner tools (cfray, findns, tracer, speedtest)

### Phase 3: Services [LEGACY - being migrated to Docker]
- [x] `services/reality/install.sh` - VLESS+REALITY ✅ TESTED
- [x] `services/ws/install.sh` - VLESS+WebSocket+CDN ✅ TESTED
- [x] `services/dnstt/install.sh` - DNS tunnel ✅ TESTED
- [x] `services/wg/install.sh` - WireGuard VPN ✅ CREATED
- [x] `services/conduit/install.sh` - Psiphon relay ✅ TESTED
- [x] `services/sos/install.sh` - Emergency chat ✅ TESTED

### Phase 4: CLI and Workers [COMPLETE]
- [x] `cli/vany.sh` - Unified management CLI ✅ CREATED
- [x] `workers/` - Unified Cloudflare Worker ✅ DEPLOYED
  - TUI routes: /tui/protocols, /tui/status, /tui/users, /tui/install, /tui/help, /tui/connect, /tui/tools, /tui/splash
  - Protocol routes: 15 protocol subdomains -> install scripts
  - Tool routes: /tools/cfray, /tools/findns, /tools/tracer, /tools/speedtest
  - Legacy routes: DNSTT setup, SOS, stats
- [x] `www/` - Landing page on Cloudflare Pages

### Phase 4: Documentation [COMPLETE]
- [x] `docs/firewall.md` - Cloud provider firewall guides
- [x] `docs/dns.md` - DNS setup for each protocol
- [x] `docs/workers.md` - Cloudflare Workers deployment
- [x] `docs/self-hosting.md` - Self-hosting guide
- [x] `docs/spot-vm-recovery.md` - Spot VM auto-recovery setup
- [x] `docs/protocols/reality.md` - VLESS+REALITY state machine
- [x] `docs/protocols/wg.md` - WireGuard state machine
- [x] `docs/protocols/mtp.md` - MTProto state machine
- [x] `docs/protocols/vray.md` - V2Ray state machine
- [x] `docs/protocols/ws.md` - WebSocket+CDN state machine
- [x] `docs/protocols/dnstt.md` - DNStt state machine
- [x] `docs/protocols/conduit.md` - Conduit Psiphon relay
- [x] `docs/protocols/sos.md` - SOS emergency secure chat

### Phase 5: Infrastructure & Operations [COMPLETE]
- [x] GCP Spot VM with static IP (`vany-static`)
- [x] GitHub Actions watchdog (`.github/workflows/spot-vm-watchdog.yml`)
- [x] Health monitoring endpoint (`stats.vany.sh/health`)
- [x] Health pusher script (`services/conduit/stats-pusher.sh`)
- [x] Website status popup with live service indicators
- [x] Service account for CI/CD (`github-vm-manager@noteefy-85339.iam.gserviceaccount.com`)

## Architecture

### Directory Structure (Repository)
```
docker/
  xray/             # Shared Xray container (Reality+WS+VRAY+HTTP-Obfs)
  wireguard/        # WireGuard container
  dnstt/            # DNSTT server (Go build from source)
  conduit/          # Conduit Psiphon relay
  sos/              # SOS relay daemon
  hysteria/         # Hysteria v2 (QUIC)
  slipstream/       # Slipstream DNS tunnel (Go build)
  noizdns/          # NoizDNS tunnel (Go build)
  tor-bridge/       # Tor Bridge (obfs4)
  snowflake/        # Snowflake Proxy
scripts/
  docker-bootstrap.sh       # VPS bootstrap: Docker, sysctl, cloud detection, state init
  protocols/
    install-xray.sh         # Xray container + Reality/WS/HTTP-Obfs inbound management
    install-wireguard.sh    # WireGuard container + peer management
    install-dnstt.sh        # DNSTT container
    install-conduit.sh      # Conduit container
    install-sos.sh          # SOS relay container
    install-hysteria.sh     # Hysteria v2 container
    install-http-obfs.sh    # HTTP Obfuscation (reuses WS+CDN)
    install-ssh-tunnel.sh   # SSH tunnel restricted user
    install-slipstream.sh   # Slipstream DNS tunnel
    install-noizdns.sh      # NoizDNS container
    install-tor-bridge.sh   # Tor Bridge container
    install-snowflake.sh    # Snowflake Proxy container
    update-container.sh     # Generic pull/rebuild + restart
    remove-container.sh     # Stop + remove + firewall cleanup
    status-containers.sh    # JSON status for all containers
  tools/
    cfray.sh                # Cloudflare clean IP scanner
    findns.sh               # DNS resolver scanner
    tracer.sh               # IP/ISP/ASN tracer
    speedtest.sh            # Bandwidth test via Cloudflare
workers/
  src/
    index.ts                # Main Worker router (15 protocols + tools)
    tui/
      index.ts              # TUI route handler (/tui/*)
      ansi.ts               # ANSI utilities
      box.ts                # Unicode box drawing
      table.ts              # Table renderer
      theme.ts              # Color palette
      layout.ts             # Layout helpers
      frame.ts              # Page frame renderer (7-tab nav)
      splash.ts             # Logo splash
      x-client.ts           # Thin bash client script
      pages/
        landing.ts          # Static ANSI catalog (curl vany.sh)
        protocols.ts        # Protocol catalog table (15 protocols)
        install.ts          # Install wizard (15 protocols)
        help.ts             # Help page with comparisons
        client.ts           # Client connection guide
        tools.ts            # Network scanner tools
lib/
  cloud.sh          # Provider detection, firewall APIs (legacy, ported to docker-bootstrap.sh)
  bootstrap.sh      # VM prep (legacy, superseded by docker-bootstrap.sh)
  common.sh         # Shared functions, user management
  xray.sh           # Xray config management (legacy, ported to install-xray.sh)
services/           # Legacy service scripts (being migrated to Docker)
src/
  sos/              # Python TUI client for emergency chat
cli/
  vany.sh           # Unified CLI
www/                # Landing page (Cloudflare Pages)
docs/               # Documentation
```

### Directory Structure (Runtime on VM)
```
/opt/vany/
  state.json        # VPS identity: machine_id, IP, provider, protocols
  users.json        # Unified user database
  docker/           # Docker compose files (downloaded by bootstrap)
    xray/
    wireguard/
    dnstt/
    conduit/
    sos/
    hysteria/
    slipstream/
    noizdns/
    tor-bridge/
    snowflake/
  scripts/          # Protocol management scripts (downloaded by bootstrap)
  xray/
    config.json     # Merged Xray config (reality + vray + ws + http-obfs)
  wg/
    wg0.conf
    peers/
  dnstt/
    server.key
    server.pub
  hysteria/
    config.yaml
    server.crt
    server.key
  slipstream/
    server.key
    domain.conf
  noizdns/
    server.key
    domain.conf
  tor-bridge/
    torrc
  sos/
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
- All users stored in `/opt/vany/users.json`
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
- Single config at `/opt/vany/xray/config.json`
- Multiple inbounds share port 443 via SNI/path routing
- Functions in `scripts/protocols/install-xray.sh` to add/remove inbounds and clients
- Reload via `docker exec vany-xray kill -HUP 1` after changes
- Xray runs in shared Docker container `vany-xray` (Reality+WS+VRAY)

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
2. Run installer: `curl vany.sh/<service> | sudo bash`
3. Add test user: `vany add <service> testuser`
4. Verify connection from client device
5. Test user removal: `vany remove <service> testuser`
6. Test uninstall: `vany uninstall <service>`

## TODO (Post-MVP)
- Hysteria 2 - QUIC-based protocol for lossy networks
- AmneziaWG - Obfuscated WireGuard for Russia/Iran DPI
- Traffic limits - Per-user bandwidth quotas
- Expiry dates - Time-limited user accounts
- Subscription URLs - Auto-updating client configs
- Web dashboard - Browser-based management
- Telegram bot - User self-service

### Security Audit (stats.vany.sh WebSocket)
- [ ] HMAC-signed push requests from VPS (prevent spoofing)
- [ ] Origin validation (only allow vany.sh origins)
- [ ] Rate limiting per IP (prevent DoS)
- [ ] Cloudflare threat score filtering (block high-risk)
- [ ] Enable Bot Fight Mode on stats subdomain
- [ ] WAF rules for additional protection

## SOS Roadmap (Emergency Chat)

### Current State (v1.0 - Testing)
- Cloudflare Worker serves install script at `vany.sh/sos`
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
│      │  Spawns: dnstt-client -doh ... t.vany.sh :10800    │            │
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
- [ ] **TODO**: `hotline.vany.sh` subdomain setup

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
1) as the VPS owner, i use the server tag to make my server a room provider over dnstt (in my case 'vany.sh/sos'
2) as user i have two option, either use this url via curl on terminal, or just out it in my browser. and since its served over dnstt, it can never be blocked (even if the main website don't work, this subdomain always loads the instant chatroom.

## Current Session Context (Updated 2026-01-30)

### Infrastructure
- **GCP Project**: `noteefy-85339` (Noteefy)
- **VM Name**: `vany`
- **Zone**: `europe-west3-c`
- **Machine Type**: `n2d-highcpu-8` (8 vCPU, 8GB RAM, 16 Gbps bandwidth)
- **VM Type**: **Spot VM** (60% cost savings, ~$42/month total)
- **Static IP**: `34.185.221.241` (named `vany-static`)
- **Disk**: 10GB boot disk from snapshot `vany-backup-20260129`

### Spot VM Auto-Recovery
- **Workflow**: `.github/workflows/spot-vm-watchdog.yml` - Runs every 5 minutes
- **Service Account**: `github-vm-manager@noteefy-85339.iam.gserviceaccount.com`
- **GitHub Secret**: `GCP_SA_KEY` - Service account JSON key
- **Recovery Time**: ~5 minutes max (cron interval)
- **Documentation**: `docs/spot-vm-recovery.md`

### Health Monitoring
- **Endpoint**: `https://stats.vany.sh/health` - Aggregated health status
- **Pusher**: `services/conduit/stats-pusher.sh` - Reports all service health every 5 seconds
- **Website**: Status popup on `vany.sh` (bottom-left button)
- **Services Monitored**: Conduit, Xray (Reality/WS/VRAY), DNSTT, WireGuard, SOS

### What's Working
- **Reality** (`services/reality/install.sh`) - Fully tested, works on GCP
- **WS+CDN** (`services/ws/install.sh`) - Fully tested, works with Cloudflare SSL "Flexible"
- **DNSTT** (`services/dnstt/install.sh`) - Fully tested, builds from source via Go 1.21
- **Conduit** (`services/conduit/install.sh`) - Psiphon relay, Docker-based
- **SOS** (`services/sos/install.sh`) - Emergency chat over DNSTT ✅ TESTED
  - TUI client with Textual framework
  - **Web client** (`src/sos/www/`) - Browser-based SPA served via relay
  - Standalone binaries (via GitHub Actions CI/CD)
  - Default relay: `relay.vany.sh:8899`
  - E2E encryption (NaCl + Argon2id)
- **WireGuard** (`services/wg/install.sh`) - Created, config exists but not running
- **CLI** (`cli/vany.sh`) - Unified management CLI

### Cloudflare Setup
- **Workers**: Deployed at `vany` worker, handles all subdomains
  - Routes: mtp, reality, wg, vray, ws, dnstt, conduit, sos, stats
  - Stats relay: `stats.vany.sh` with WebSocket and `/health` endpoint
- **Pages**: Landing page at `www.vany.sh` via direct upload of `www/` folder
- **DNS**: 
  - `*.vany.sh` - Worker routes
  - `www.vany.sh` - Cloudflare Pages
  - `ws-origin.vany.sh` - WS origin server (Proxied, SSL Flexible)
  - `ns1.vany.sh` - DNSTT nameserver (DNS only, NOT proxied)
  - `t.vany.sh` - NS record pointing to ns1.vany.sh
  - `relay.vany.sh` - SOS relay server (DNS only, NOT proxied) → 34.185.221.241
  - `stats.vany.sh` - Worker route for health/stats

### Key Technical Decisions
1. **Spot VM with auto-recovery** - 60% cost savings, GitHub Actions watchdog restarts if preempted
2. **WS+CDN uses port 80 (HTTP) on origin** - Cloudflare handles TLS at edge, SSL mode must be "Flexible"
3. **DNSTT builds from source** - Downloads Go 1.21 from go.dev, builds dnstt-server
4. **User database** - `/opt/vany/users.json` with format `{users: {name: {protocols: {ws: {uuid}}}}, server: {...}}`
5. **Health aggregation** - Single `/health` endpoint reports all services, used by watchdog and website
6. **WireGuard network** - Uses `10.66.66.0/24` subnet, server at `.1`, clients from `.2`

### Cost Summary (Monthly)
| Component | Cost |
|-----------|------|
| n2d-highcpu-8 Spot VM | ~$37 |
| Static IP | $4 |
| Boot disk (10GB) | $1 |
| GitHub Actions | FREE |
| **Total** | **~$42** |

### Services TODO
- [ ] `services/mtp/install.sh` - Refactor existing MTProto  
- [ ] `services/vray/install.sh` - VLESS+TCP+TLS with Let's Encrypt
- [ ] Start WireGuard service (config exists)

### Known Issues Fixed
- `user_exists()` now supports optional protocol parameter: `user_exists "name" "ws"`
- `user_get()` now supports optional key parameter: `user_get "name" "ws" "uuid"`
- WS installer uses correct function names from lib files
- Watchdog handles Cloudflare bot protection on health endpoint gracefully

