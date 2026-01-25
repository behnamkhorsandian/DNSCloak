# DNSCloak Development Instructions

## Project Overview

DNSCloak is a multi-protocol censorship bypass platform. Each protocol runs as an independent service, all managed via the unified `dnscloak` CLI with a shared user database.

## Implementation Checklist

### Phase 1: Core Libraries
- [ ] `lib/cloud.sh` - Cloud provider detection and firewall auto-config
- [ ] `lib/bootstrap.sh` - VM setup, prerequisites, Xray-core install
- [ ] `lib/common.sh` - Shared utilities, colors, user CRUD on users.json
- [ ] `lib/xray.sh` - Multi-inbound config manager for shared Xray instance
- [ ] `lib/selector.sh` - Domain detection and service recommendation

### Phase 2: Services
- [ ] `services/reality/install.sh` - VLESS+REALITY (no domain needed)
- [ ] `services/wg/install.sh` - WireGuard VPN
- [ ] `services/mtp/install.sh` - Refactor existing MTProto
- [ ] `services/vray/install.sh` - VLESS+TCP+TLS (requires domain)
- [ ] `services/ws/install.sh` - VLESS+WebSocket+CDN (requires Cloudflare)
- [ ] `services/dnstt/install.sh` - DNS tunnel (emergency backup)

### Phase 3: CLI and Workers
- [ ] `cli/dnscloak.sh` - Unified management CLI
- [ ] `workers/reality/` - Cloudflare Worker for reality.dnscloak.net
- [ ] `workers/wg/` - Cloudflare Worker for wg.dnscloak.net
- [ ] `workers/mtp/` - Update existing worker
- [ ] `workers/vray/` - Cloudflare Worker for vray.dnscloak.net
- [ ] `workers/ws/` - Cloudflare Worker for ws.dnscloak.net
- [ ] `workers/dnstt/` - Cloudflare Worker for dnstt.dnscloak.net

### Phase 4: Documentation
- [ ] `docs/firewall.md` - Cloud provider firewall guides
- [ ] `docs/dns.md` - DNS setup for each protocol
- [ ] `docs/workers.md` - Cloudflare Workers deployment
- [ ] `docs/protocols/reality.md` - VLESS+REALITY state machine
- [ ] `docs/protocols/wg.md` - WireGuard state machine
- [ ] `docs/protocols/mtp.md` - MTProto state machine
- [ ] `docs/protocols/vray.md` - V2Ray state machine
- [ ] `docs/protocols/ws.md` - WebSocket+CDN state machine
- [ ] `docs/protocols/dnstt.md` - DNStt state machine

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
