# Vany
[![Build SOS Binaries](https://github.com/behnamkhorsandian/Vanyshsh/actions/workflows/sos-build.yml/badge.svg)](https://github.com/behnamkhorsandian/Vanyshsh/actions/workflows/sos-build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Website](https://img.shields.io/website?down_color=red&down_message=offline&up_color=green&up_message=online&url=https%3A%2F%2Fvany.sh)](https://www.vany.sh)

Multi-protocol censorship bypass platform. Deploy proxy services on any VM with a single command.

🌐 **Website:** [vany.sh](https://www.vany.sh)

## Services

| Service | Status | Domain Required | Best For | Install Command |
|---------|--------|-----------------|----------|-----------------|
| Reality | ✅ Ready | No | Primary proxy (all countries) | `curl vany.sh/reality \| sudo bash` |
| WS+CDN | ✅ Ready | Yes (Cloudflare) | IP hidden behind CDN | `curl vany.sh/ws \| sudo bash` |
| DNStt | ✅ Ready | Yes (NS records) | Emergency during blackouts | `curl vany.sh/dnstt \| sudo bash` |
| Conduit | 🧪 Experimental | No | Psiphon volunteer relay | `curl vany.sh/conduit \| sudo bash` |
| SOS | 🧪 Experimental | Yes (NS) | Emergency encrypted chat | `curl vany.sh/sos \| bash` |
| WireGuard | 🔜 Coming | No | Fast VPN tunnel | `curl vany.sh/wg \| sudo bash` |
| MTP | 🔜 Coming | Optional | Telegram access | `curl vany.sh/mtp \| sudo bash` |
| V2Ray | 🔜 Coming | Yes | Classic proxy with TLS | `curl vany.sh/vray \| sudo bash` |

## Quick Start

SSH into your VPS and run:

```bash
curl vany.sh/reality | sudo bash
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
- Domain (optional but recommended for some services)

## User Management

After installation, use the `vany` CLI:

```bash
vany add reality alice      # Add user to Reality
vany add wg bob             # Add user to WireGuard
vany users                  # List all users
vany links alice            # Show all connection links for user
vany remove reality alice   # Remove user from Reality
vany status                 # Show all services status
vany uninstall reality      # Remove Reality service
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

- [Self-Hosting Guide](docs/self-hosting.md) - Host your own Vany platform
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
  - [Conduit](docs/protocols/conduit.md) - Psiphon volunteer relay
  - [SOS](docs/protocols/sos.md) - Emergency encrypted chat over DNS

## Implementation Status

### Phase 1: Core Libraries ✅
- [x] lib/cloud.sh - Cloud provider detection and firewall
- [x] lib/bootstrap.sh - VM setup and prerequisites
- [x] lib/common.sh - Shared utilities and user management
- [x] lib/xray.sh - Xray config management
- [x] lib/selector.sh - Service recommendation

### Phase 2: Services (In Progress)
- [x] services/reality - VLESS+REALITY ✅ Tested
- [x] services/ws - VLESS+WebSocket+CDN ✅ Tested
- [x] services/dnstt - DNS tunnel ✅ Tested
- [x] services/conduit - Psiphon relay 🧪 Experimental
- [x] services/sos - Emergency chat 🧪 Experimental
- [ ] services/wg - WireGuard
- [ ] services/mtp - MTProto (refactor)
- [ ] services/vray - VLESS+TCP+TLS

### Phase 3: CLI and Workers ✅
- [ ] cli/vany.sh - Unified CLI
- [x] workers/* - Cloudflare Workers ✅ Deployed
- [x] www/* - Landing page ✅ Ready

### Phase 4: Documentation ✅
- [x] docs/firewall.md
- [x] docs/dns.md
- [x] docs/workers.md
- [x] docs/protocols/*.md

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
- [Conduit](https://github.com/ssmirr/conduit) by ssmirr
- [Conduit Manager](https://github.com/SamNet-dev/conduit-manager) by SamNet
