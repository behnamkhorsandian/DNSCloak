# Vany
[![Build SOS Binaries](https://github.com/behnamkhorsandian/Vanysh/actions/workflows/sos-build.yml/badge.svg)](https://github.com/behnamkhorsandian/Vanysh/actions/workflows/sos-build.yml)
[![Deploy](https://github.com/behnamkhorsandian/Vanysh/actions/workflows/deploy.yml/badge.svg)](https://github.com/behnamkhorsandian/Vanysh/actions/workflows/deploy.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Website](https://img.shields.io/website?down_color=red&down_message=offline&up_color=green&up_message=online&url=https%3A%2F%2Fvany.sh)](https://www.vany.sh)

Multi-protocol censorship bypass toolkit. Deploy proxy services on any VM, connect from restricted networks, and scan for clean routes -- all from the terminal.

**Website:** [vany.sh](https://www.vany.sh)

## Three Entry Points

```bash
curl vany.sh                        # Browse protocol catalog (static ANSI page)
curl vany.sh | sudo bash            # Server TUI: install & manage protocols
curl vany.sh/tools/cfray | bash     # Client tools: scanners & diagnostics
```

## Protocol Catalog

### Server Protocols (install on VPS)

| Protocol | Transport | Domain | Resilience | Speed | Install |
|----------|-----------|--------|------------|-------|---------|
| Reality | VLESS+XTLS | No | High | Fast | `curl vany.sh/reality \| sudo bash` |
| WS+CDN | VLESS+WS | Yes (CF) | High | Medium | `curl vany.sh/ws \| sudo bash` |
| Hysteria v2 | QUIC/UDP | Optional | Medium | Very Fast | `curl vany.sh/hysteria \| sudo bash` |
| WireGuard | UDP | No | Low | Very Fast | `curl vany.sh/wg \| sudo bash` |
| V2Ray | VLESS+TLS | Yes | Medium | Fast | `curl vany.sh/vray \| sudo bash` |
| HTTP Obfs | WS+CDN + Clean IPs | Yes (CF) | Very High | Medium | `curl vany.sh/http-obfs \| sudo bash` |
| MTProto | Telegram Proxy | Optional | Medium | Fast | `curl vany.sh/mtp \| sudo bash` |
| SSH Tunnel | SSH SOCKS5 | No | Low | Fast | `curl vany.sh/ssh-tunnel \| sudo bash` |

### Emergency / DNS Tunnels

| Protocol | Transport | Domain | Resilience | Speed | Install |
|----------|-----------|--------|------------|-------|---------|
| DNSTT | DNS queries | Yes (NS) | Very High | Slow | `curl vany.sh/dnstt \| sudo bash` |
| Slipstream | DNS tunnel | Yes (NS) | Very High | Slow | `curl vany.sh/slipstream \| sudo bash` |
| NoizDNS | DNS (DPI-resistant) | Yes (NS) | Very High | Slow | `curl vany.sh/noizdns \| sudo bash` |

### Relay / Community

| Protocol | Type | Domain | Install |
|----------|------|--------|---------|
| Conduit | Psiphon relay | No | `curl vany.sh/conduit \| sudo bash` |
| Tor Bridge | obfs4 bridge | No | `curl vany.sh/tor-bridge \| sudo bash` |
| Snowflake | Tor relay proxy | No | `curl vany.sh/snowflake \| sudo bash` |
| SOS | Emergency chat | Yes (NS) | `curl vany.sh/sos \| bash` |

### Client Tools (run from restricted network)

| Tool | Purpose | Command |
|------|---------|---------|
| CFRay | Find clean Cloudflare IPs | `curl vany.sh/tools/cfray \| bash` |
| FindNS | Discover accessible DNS resolvers | `curl vany.sh/tools/findns \| bash` |
| IP Tracer | Detect ISP, ASN, VPN leaks | `curl vany.sh/tools/tracer \| bash` |
| Speed Test | Bandwidth test via Cloudflare | `curl vany.sh/tools/speedtest \| bash` |

## Quick Start

### Server Setup (VPS owner)

```bash
# SSH into your VPS, pick a protocol:
curl vany.sh/reality | sudo bash

# Manage users:
vany add reality alice
vany links alice
vany status
```

### Client Connection (restricted country)

```bash
# Find clean Cloudflare IPs for HTTP Obfuscation:
curl vany.sh/tools/cfray | bash

# Check your connection:
curl vany.sh/tools/tracer | bash
```

Use connection links from your VPS in apps like **Hiddify**, **v2rayNG**, or **WireGuard**.

## Requirements

- **Server:** VPS with Ubuntu 20.04+ or Debian 11+, root access, 512MB RAM
- **Client tools:** Any terminal with `curl` and `bash`
- **Domain:** Required for WS+CDN, HTTP Obfs, DNS tunnels. Optional for others.

## User Management

```bash
vany add reality alice        # Add user to Reality
vany add wg bob               # Add user to WireGuard
vany users                    # List all users
vany links alice              # Show connection links
vany remove reality alice     # Remove user
vany status                   # All services status
vany uninstall reality        # Remove service
```

## Client Apps

| Platform | Apps |
|----------|------|
| iOS | Hiddify, Shadowrocket, Streisand, WireGuard |
| Android | Hiddify, v2rayNG, WireGuard |
| Windows | Hiddify, v2rayN, WireGuard |
| macOS | Hiddify, V2rayU, WireGuard |
| Linux | v2rayA, WireGuard |

## Architecture

```
curl vany.sh                     curl vany.sh | sudo bash
     |                                |
     v                                v
 CF Worker (static ANSI)       CF Worker -> bash TUI client
                                      |
                               Docker containers on VPS
                               /opt/vany/state.json
```

```
Port 443 (TCP)
    +-> SNI: camouflage.com    -> Reality (VLESS+XTLS)
    +-> SNI: yourdomain.com    -> V2Ray (VLESS+TLS)
    +-> Path: /ws-path         -> WebSocket (VLESS+WS)
    +-> Fallback               -> Fake website

Port 8443 (UDP)                -> Hysteria v2 (QUIC)
Port 51820 (UDP)               -> WireGuard
Port 53 (UDP)                  -> DNS Tunnels (DNSTT/Slipstream/NoizDNS)
Port 9001 (TCP)                -> Tor Bridge (obfs4)
Port 22 (TCP)                  -> SSH Tunnel (SOCKS5)
```

## Documentation

- [Self-Hosting Guide](docs/self-hosting.md)
- [Firewall Setup](docs/firewall.md)
- [DNS Setup](docs/dns.md)
- [Workers Deployment](docs/workers.md)
- [Spot VM Recovery](docs/spot-vm-recovery.md)
- Protocol Guides: [Reality](docs/protocols/reality.md) | [WS+CDN](docs/protocols/ws.md) | [WireGuard](docs/protocols/wg.md) | [DNSTT](docs/protocols/dnstt.md) | [V2Ray](docs/protocols/vray.md) | [MTP](docs/protocols/mtp.md) | [Conduit](docs/protocols/conduit.md) | [SOS](docs/protocols/sos.md)

## License

MIT - See [LICENSE](LICENSE)

## Credits

- [Xray-core](https://github.com/XTLS/Xray-core)
- [Hysteria](https://github.com/apernet/hysteria)
- [dnstt](https://www.bamsoftware.com/software/dnstt/)
- [WireGuard](https://www.wireguard.com/)
- [Tor Project](https://www.torproject.org/)
- [Conduit](https://github.com/nickolasburr/conduit)
- [mtprotoproxy](https://github.com/alexbers/mtprotoproxy)
