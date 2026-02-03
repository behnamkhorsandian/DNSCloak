# DNSCloak Project Overview

## Concept
DNSCloak is a multi-protocol censorship bypass platform that lets you deploy proxy services on a VPS with a single command. It focuses on practical, resilient access methods (VLESS+REALITY, WebSocket via CDN, DNS tunneling, WireGuard, MTProto, Psiphon relay, SOS chat) and wraps them with a consistent install workflow, shared libraries, and a unified CLI for user management.

At a high level:
- One-line installer per service (served via Cloudflare Workers).
- Shared bootstrap + config tooling for repeatable, reliable setup.
- Multiple protocols so operators can choose the best path for the local network conditions.

## Architecture
DNSCloak is split into delivery, install, runtime, and management layers.

### 1) Delivery Layer (Cloudflare Workers)
- `workers/src/index.ts` serves install scripts by subdomain (e.g., `reality.dnscloak.net`).
- The worker fetches scripts from GitHub raw and returns them to `curl`.
- Special endpoints: `/health`, `/info`, `/version`, and DNSTT client helpers.

### 2) Installation Layer (Service scripts + shared libs)
- Each service has `services/<service>/install.sh`.
- Shared library scripts live in `lib/`:
  - `lib/bootstrap.sh` sets up the system, installs dependencies, configures sysctl, installs Xray, etc.
  - `lib/cloud.sh` detects cloud providers and helps with firewall settings.
  - `lib/common.sh` provides logging, prompts, OS checks, and filesystem paths.
  - `lib/xray.sh` manages Xray inbounds/clients and builds share links.
  - `lib/selector.sh` recommends services based on domain availability.

### 3) Runtime Layer (Services)
- Xray-based services share a single Xray instance:
  - Reality (VLESS+REALITY), V2Ray (VLESS+TLS), WS+CDN (VLESS+WS).
- Non-Xray services run separately:
  - WireGuard (`wg-quick@wg0`), DNSTT, MTProto, Conduit (Psiphon relay), SOS.
- Standard state paths live under `/opt/dnscloak`.

### 4) Management Layer (CLI)
- `cli/dnscloak.sh` is the unified CLI for users, links, and service status.
- User data is stored in `/opt/dnscloak/users.json`.

## Flow

### Install Flow (one-line install)
```
User runs: curl -sSL reality.dnscloak.net | sudo bash
    -> Cloudflare Worker routes by subdomain
    -> Worker fetches services/reality/install.sh from GitHub
    -> Script downloads lib/* helpers (if piped)
    -> bootstrap.sh installs dependencies + Xray
    -> service installer configures service + users
    -> outputs share link / QR code
```

### Runtime Flow (Xray-based services)
```
Client App -> TCP/443
  - SNI or WS path selects inbound in Xray
  - VLESS auth validates user UUID
  - Proxy established to Internet
```

### Runtime Flow (DNSTT / SOS)
```
Client -> DNS queries (UDP/53)
  -> DNSTT tunnel on server
  -> Traffic exits to Internet
  -> SOS uses DNS tunnel for encrypted chat rooms
```

### Runtime Flow (WireGuard)
```
Client app -> UDP/51820
  -> wg-quick@wg0
  -> VPN tunnel established
```

## Features
- Multi-protocol service catalog (reality, ws, dnstt, wg, vray, mtp, conduit, sos).
- One-command installs via Cloudflare Workers.
- Shared bootstrap and config management across services.
- Automatic cloud provider detection.
- Unified CLI for users, links, status, and restarts.
- Xray multi-inbound management (SNI + path routing).
- DNS and CDN guidance in `docs/`.

## How to use it

### 1) Pick a service and install on your VPS
```
# Example: Reality (no domain required)
curl -sSL reality.dnscloak.net | sudo bash
```

### 2) Manage users via CLI
```
# Add user
dnscloak add reality alice

# List users
dnscloak list

# Show share link(s)
dnscloak links alice

# Service status
dnscloak status
```

### 3) Client apps
DNSCloak emits links/QRs for supported apps. Typical clients:
- Hiddify, v2rayNG, Shadowrocket for VLESS-based services
- WireGuard apps for WireGuard
- Psiphon apps for Conduit

## Extra: Project Map

### Service scripts
- `services/reality/install.sh` - VLESS+REALITY
- `services/ws/install.sh` - VLESS+WebSocket+CDN
- `services/dnstt/install.sh` - DNS tunnel
- `services/wg/install.sh` - WireGuard
- `services/mtp/install.sh` - MTProto
- `services/conduit/install.sh` - Psiphon relay
- `services/sos/install.sh` - SOS emergency chat
- `setup.sh` / `install.sh` - legacy MTProto installer (root-level)

### Core libraries
- `lib/common.sh` - constants, IO helpers, shared paths
- `lib/bootstrap.sh` - OS prep, dependencies, Xray install
- `lib/cloud.sh` - provider detection, firewall helpers
- `lib/xray.sh` - config management and share links
- `lib/selector.sh` - service recommendation logic

### Workers and web
- `workers/src/index.ts` - multi-service Cloudflare Worker
- `www/` - landing page assets

### Docs
- `docs/self-hosting.md` - how to deploy your own workers
- `docs/dns.md` / `docs/firewall.md` - DNS and firewall setup
- `docs/protocols/*.md` - protocol-specific guides

### Helper scripts
- `scripts/cf-dns.sh` - Cloudflare DNS automation

## Extra: Operational Notes
- OS support: Ubuntu 20.04+ / Debian 11+.
- Services have different DNS requirements; see `docs/dns.md`.
- Xray config lives at `/opt/dnscloak/xray/config.json`.
- The worker fetches scripts from GitHub raw, so updates are pulled automatically when users install.

## Extra: Implementation Status (from README)
- Ready: reality, ws, dnstt.
- Experimental: conduit, sos.
- Coming/partial: wg, mtp, vray (check scripts and docs for current state).

## Extra: Suggested First-Time Path
- Start with Reality (no domain needed).
- If you need IP hiding, use WS+CDN with Cloudflare.
- Keep DNSTT as emergency fallback.
- Use WireGuard for stable, fast tunneling when VPN is acceptable.
