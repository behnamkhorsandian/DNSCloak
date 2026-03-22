# Vany Project Overview

## Concept
Vany is a multi-protocol censorship bypass toolkit. It serves both VPS owners (protocol installation) and clients in restricted countries (VPN connection + network scanners) -- all from the terminal.

Three entry points:
- `curl vany.sh` -- browse protocol catalog (static ANSI page)
- `curl vany.sh | sudo bash` -- server TUI for installing and managing protocols
- `curl vany.sh/tools/cfray | bash` -- client tools for scanning and diagnostics

15 protocols across four categories:
- **Server Protocols:** Reality, WS+CDN, Hysteria v2, WireGuard, V2Ray, HTTP Obfs, MTProto, SSH Tunnel
- **DNS Tunnels:** DNSTT, Slipstream, NoizDNS
- **Relay/Community:** Conduit, Tor Bridge, Snowflake, SOS

## Architecture

### 1) Delivery Layer (Cloudflare Workers)
- `workers/src/index.ts` routes requests by path or subdomain.
- Protocol routes (`/reality`, `/hysteria`, etc.) fetch install scripts from GitHub raw.
- Tool routes (`/tools/cfray`, `/tools/findns`, etc.) serve client scanner scripts.
- TUI routes (`/tui/*`) serve ANSI pages to the bash client.
- Static route (`curl vany.sh` without pipe) returns the landing page catalog.

### 2) Installation Layer (Docker containers + bash scripts)
- Each protocol has an install script in `scripts/protocols/install-<name>.sh`.
- Docker compose files live in `docker/<protocol>/`.
- `scripts/docker-bootstrap.sh` handles Docker setup, sysctl, cloud detection, state init.
- Shared Xray container serves Reality, WS+CDN, V2Ray, and HTTP Obfs together.
- DNS tunnels (DNSTT, Slipstream, NoizDNS) share port 53 -- only one at a time.

### 3) Runtime Layer (Containers on VPS)
- All protocols run in Docker containers under `/opt/vany/docker/`.
- State tracked in `/opt/vany/state.json`, users in `/opt/vany/users.json`.
- Containers: vany-xray, vany-wireguard, vany-dnstt, vany-hysteria, vany-slipstream, vany-noizdns, vany-conduit, vany-tor-bridge, vany-snowflake, vany-sos.
- SSH tunnel is the only non-container protocol (creates restricted OS user).

### 4) Management Layer (CLI + TUI)
- `cli/vany.sh` manages users, links, service status locally.
- Worker TUI provides 7-tab navigation: Protocols, Status, Users, Install, Help, Connect, Tools.

### 5) Client Tools Layer
- Scripts in `scripts/tools/` run on the client machine (restricted country).
- CFRay: scans for clean Cloudflare IPs for HTTP Obfuscation.
- FindNS: discovers accessible DNS resolvers for DNS tunnel transport.
- Tracer: detects ISP, ASN, VPN leaks.
- Speed Test: bandwidth test via Cloudflare.

## Flow

### Server Install Flow
```
VPS owner runs: curl vany.sh/reality | sudo bash
    -> Cloudflare Worker fetches scripts/protocols/install-xray.sh
    -> Script sources docker-bootstrap.sh (Docker, sysctl, cloud detect)
    -> Creates Docker container, configures protocol
    -> Updates /opt/vany/state.json
    -> Outputs connection link
```

### Client Connection Flow
```
User in restricted country:
    1. curl vany.sh/tools/cfray | bash    # Find clean CF IPs
    2. Gets connection link from VPS owner
    3. Imports link into Hiddify/v2rayNG/WireGuard
    4. Uses clean IP as address (for HTTP Obfs)
```

### Port Map
```
Port 443 (TCP)   -> Xray (Reality, V2Ray, WS+CDN, HTTP Obfs)
Port 8443 (UDP)  -> Hysteria v2 (QUIC)
Port 51820 (UDP) -> WireGuard
Port 53 (UDP)    -> DNS Tunnels (DNSTT/Slipstream/NoizDNS, one at a time)
Port 9001 (TCP)  -> Tor Bridge (obfs4)
Port 22 (TCP)    -> SSH Tunnel (SOCKS5)
Port 8899 (TCP)  -> SOS Relay
```

## Project Map

### Docker configs
- `docker/xray/` - Shared Xray (Reality+WS+VRAY+HTTP-Obfs)
- `docker/hysteria/` - Hysteria v2 (QUIC)
- `docker/wireguard/` - WireGuard
- `docker/dnstt/` - DNSTT server (Go build)
- `docker/slipstream/` - Slipstream DNS tunnel (Go build)
- `docker/noizdns/` - NoizDNS (DPI-resistant DNSTT fork)
- `docker/conduit/` - Conduit Psiphon relay
- `docker/tor-bridge/` - Tor Bridge (obfs4)
- `docker/snowflake/` - Snowflake Proxy
- `docker/sos/` - SOS relay daemon

### Install scripts
- `scripts/protocols/install-xray.sh` - Xray + Reality/WS/HTTP-Obfs
- `scripts/protocols/install-hysteria.sh` - Hysteria v2
- `scripts/protocols/install-wireguard.sh` - WireGuard
- `scripts/protocols/install-dnstt.sh` - DNSTT
- `scripts/protocols/install-slipstream.sh` - Slipstream
- `scripts/protocols/install-noizdns.sh` - NoizDNS
- `scripts/protocols/install-http-obfs.sh` - HTTP Obfuscation
- `scripts/protocols/install-ssh-tunnel.sh` - SSH Tunnel
- `scripts/protocols/install-conduit.sh` - Conduit
- `scripts/protocols/install-tor-bridge.sh` - Tor Bridge
- `scripts/protocols/install-snowflake.sh` - Snowflake
- `scripts/protocols/install-sos.sh` - SOS
- `scripts/protocols/status-containers.sh` - JSON status for all containers
- `scripts/protocols/remove-container.sh` - Container removal + firewall cleanup

### Client tools
- `scripts/tools/cfray.sh` - Cloudflare clean IP scanner
- `scripts/tools/findns.sh` - DNS resolver scanner
- `scripts/tools/tracer.sh` - IP/ISP/ASN tracer
- `scripts/tools/speedtest.sh` - Bandwidth test

### Worker TUI pages
- `workers/src/tui/pages/landing.ts` - Static catalog (curl vany.sh)
- `workers/src/tui/pages/protocols.ts` - Protocol list with live status
- `workers/src/tui/pages/install.ts` - Install wizard (15 protocols)
- `workers/src/tui/pages/help.ts` - Help with protocol comparison tables
- `workers/src/tui/pages/client.ts` - Client connection guide
- `workers/src/tui/pages/tools.ts` - Network scanner tools

### Core libraries (legacy, ported to Docker scripts)
- `lib/common.sh` - constants, IO helpers, shared paths
- `lib/bootstrap.sh` - OS prep, dependencies
- `lib/cloud.sh` - provider detection, firewall helpers
- `lib/xray.sh` - config management

### Workers and web
- `workers/src/index.ts` - Cloudflare Worker router (15 protocols + tools)
- `www/` - Landing page (Cloudflare Pages)

### Docs
- `docs/protocols/*.md` - Protocol-specific guides
- `docs/dns.md` / `docs/firewall.md` - DNS and firewall setup
- `docs/self-hosting.md` - Self-hosting guide
- `docs/spot-vm-recovery.md` - Spot VM auto-recovery
- `tui/content/docs/` - Protocol descriptions for TUI

## Suggested First-Time Path
1. Start with Reality (no domain needed, strongest DPI bypass).
2. Add WS+CDN with Cloudflare if IP hiding needed.
3. Use HTTP Obfuscation + CFRay scanner for advanced CDN bypass.
4. Keep DNSTT as emergency fallback during blackouts.
5. Use Hysteria v2 for maximum speed on lossy networks.
6. Run Conduit/Tor Bridge/Snowflake to contribute to the community.
