# DNSCloak

Multi-protocol censorship bypass platform. Deploy proxy services on any VM with a single command.

## Services

| Service | Domain Required | Best For | Install Command |
|---------|-----------------|----------|-----------------|
| Reality | No | Primary proxy (all countries) | `curl -sSL reality.dnscloak.net \| sudo bash` |
| WireGuard | No | Fast VPN tunnel | `curl -sSL wg.dnscloak.net \| sudo bash` |
| MTP | Optional | Telegram access | `curl -sSL mtp.dnscloak.net \| sudo bash` |
| V2Ray | Yes | Classic proxy with TLS | `curl -sSL vray.dnscloak.net \| sudo bash` |
| WS+CDN | Yes (Cloudflare) | CDN fallback when blocked | `curl -sSL ws.dnscloak.net \| sudo bash` |
| DNStt | Yes (NS records) | Emergency during blackouts | `curl -sSL dnstt.dnscloak.net \| sudo bash` |

## Quick Start

SSH into your VPS and run:

```bash
curl -sSL reality.dnscloak.net | sudo bash
```

The script will:
1. Update system and install prerequisites
2. Auto-detect cloud provider and configure firewall
3. Install and configure the service
4. Create your first user
5. Display connection link/QR code

## Requirements

- VPS with Ubuntu 20.04+ or Debian 11+
- Root access (sudo)
- 512MB RAM minimum

## User Management

After installation, use the `dnscloak` CLI:

```bash
dnscloak add reality alice      # Add user to Reality
dnscloak add wg bob             # Add user to WireGuard
dnscloak users                  # List all users
dnscloak links alice            # Show all connection links for user
dnscloak remove reality alice   # Remove user from Reality
dnscloak status                 # Show all services status
dnscloak uninstall reality      # Remove Reality service
```

## Client Apps

| Platform | Apps |
|----------|------|
| iOS | Hiddify, Shadowrocket, Streisand, WireGuard |
| Android | Hiddify, v2rayNG, WireGuard |
| Windows | Hiddify, v2rayN, WireGuard |
| macOS | Hiddify, V2rayU, WireGuard |
| Linux | v2rayA, WireGuard |

## Documentation

- [Firewall Setup](docs/firewall.md) - Cloud provider firewall configuration
- [DNS Setup](docs/dns.md) - Domain and DNS record configuration
- [Workers Deployment](docs/workers.md) - Cloudflare Workers setup
- Protocol Guides:
  - [Reality](docs/protocols/reality.md) - VLESS+REALITY setup and flow
  - [WireGuard](docs/protocols/wg.md) - WireGuard VPN setup
  - [MTP](docs/protocols/mtp.md) - MTProto Proxy for Telegram
  - [V2Ray](docs/protocols/vray.md) - VLESS+TCP+TLS setup
  - [WS+CDN](docs/protocols/ws.md) - WebSocket over Cloudflare CDN
  - [DNStt](docs/protocols/dnstt.md) - DNS tunnel for emergencies

## Implementation Status

### Phase 1: Core Libraries
- [ ] lib/cloud.sh - Cloud provider detection and firewall
- [ ] lib/bootstrap.sh - VM setup and prerequisites
- [ ] lib/common.sh - Shared utilities and user management
- [ ] lib/xray.sh - Xray config management
- [ ] lib/selector.sh - Service recommendation

### Phase 2: Services
- [ ] services/reality - VLESS+REALITY
- [ ] services/wg - WireGuard
- [ ] services/mtp - MTProto (refactor)
- [ ] services/vray - VLESS+TCP+TLS
- [ ] services/ws - VLESS+WebSocket+CDN
- [ ] services/dnstt - DNS tunnel

### Phase 3: CLI and Workers
- [ ] cli/dnscloak.sh - Unified CLI
- [ ] workers/* - Cloudflare Workers

### Phase 4: Documentation
- [ ] docs/firewall.md
- [ ] docs/dns.md
- [ ] docs/workers.md
- [ ] docs/protocols/*.md

## Architecture

```
Port 443 (TCP)
    |
    +-> SNI: camouflage.com    -> Reality (VLESS+XTLS)
    +-> SNI: yourdomain.com    -> V2Ray (VLESS+TLS)
    +-> Path: /ws-path         -> WebSocket (VLESS+WS)
    +-> Fallback               -> Fake website

Port 51820 (UDP)               -> WireGuard

Port 53 (UDP)                  -> DNStt (emergency)
```

## License

MIT - See [LICENSE](LICENSE)

## Credits

- [Xray-core](https://github.com/XTLS/Xray-core)
- [mtprotoproxy](https://github.com/alexbers/mtprotoproxy)
- [dnstt](https://www.bamsoftware.com/software/dnstt/)
- [WireGuard](https://www.wireguard.com/)
