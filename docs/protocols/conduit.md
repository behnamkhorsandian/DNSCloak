# Conduit Protocol Documentation

## Overview

Conduit is a volunteer-run proxy relay node for the Psiphon network. Unlike other DNSCloak services that provide individual user VPN connections, Conduit turns your server into a relay node that helps users in censored regions access the open internet through the Psiphon network.

## How It Works

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│  Psiphon User   │──────│  Your Conduit   │──────│   Internet      │
│  (censored)     │      │  Relay Node     │      │                 │
└─────────────────┘      └─────────────────┘      └─────────────────┘
         │                        │
         │                        │
         ▼                        ▼
   ┌───────────┐            ┌───────────┐
   │  Psiphon  │            │  Psiphon  │
   │  Client   │            │  Broker   │
   └───────────┘            └───────────┘
```

1. **User downloads Psiphon app** - Official apps from psiphon.ca
2. **Psiphon broker assigns nodes** - Based on availability and reputation
3. **Your Conduit relays traffic** - Users connect through Psiphon, not directly
4. **Internet access provided** - Censored users can access the open web

## State Machine

```
                                    ┌──────────────┐
                                    │    START     │
                                    └──────────────┘
                                           │
                                           ▼
                                    ┌──────────────┐
                               ┌────│  INSTALLING  │────┐
                               │    └──────────────┘    │
                               │           │            │
                               ▼           │            ▼
                        ┌──────────┐       │     ┌──────────┐
                        │  FAILED  │       │     │CONFIGURED│
                        └──────────┘       │     └──────────┘
                                           │           │
                                           ▼           │
                                    ┌──────────────┐   │
                                    │   STARTING   │◄──┘
                                    └──────────────┘
                                           │
                               ┌───────────┴───────────┐
                               ▼                       ▼
                        ┌──────────┐           ┌──────────────┐
                        │  ERROR   │           │   RUNNING    │◄─┐
                        └──────────┘           └──────────────┘  │
                               │                       │         │
                               │                       │  ┌──────┴─────┐
                               ▼                       │  │  CLIENTS   │
                        ┌──────────┐                   │  │ CONNECTING │
                        │  RETRY   │───────────────────┘  └────────────┘
                        └──────────┘
```

## Installation

### One-Line Install

```bash
curl -sSL conduit.dnscloak.net | sudo bash
```

### Manual Installation

```bash
# Download binary (x86_64)
curl -L -o conduit https://github.com/ssmirr/conduit/releases/download/e421eff/conduit-linux-amd64
chmod +x conduit

# Install as service
sudo mv conduit /usr/local/bin/
sudo conduit service install --max-clients 200 --bandwidth 10
sudo conduit service start
```

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `--max-clients` | 200 | Maximum concurrent client connections |
| `--bandwidth` | 5 | Bandwidth limit in Mbps (0 = unlimited) |
| `--data-dir` | `/opt/dnscloak/conduit/data` | Directory for node identity and state |
| `--stats-file` | `/opt/dnscloak/conduit/stats.json` | Statistics output file |

## Recommended Settings by Server Size

| Server Type | Max Clients | Bandwidth |
|-------------|-------------|-----------|
| Small VPS (1GB RAM) | 100 | 5 Mbps |
| Medium VPS (2GB RAM) | 200 | 10 Mbps |
| Large VPS (4GB+ RAM) | 500 | 20-40 Mbps |

## Node Identity & Reputation

Conduit generates a unique identity key on first run:

```
/opt/dnscloak/conduit/data/conduit_key.json
```

**Important:** Back up this file! The Psiphon broker tracks your node's reputation by this key. If you lose it, you'll need to build reputation from scratch.

### Reputation System

- New nodes start with low reputation
- Reputation increases over time with good uptime
- Higher reputation = more client assignments
- Keep your node running 24/7 for best results

## Management Commands

```bash
# Show status
dnscloak status conduit

# Restart service
dnscloak restart conduit

# Live statistics
conduit service status -f

# View logs
journalctl -u conduit -f

# Reconfigure (through installer menu)
curl -sSL conduit.dnscloak.net | sudo bash
```

## Statistics

Conduit writes statistics to `/opt/dnscloak/conduit/stats.json`:

```json
{
  "connectingClients": 5,
  "connectedClients": 12,
  "totalBytesUp": 1234567890,
  "totalBytesDown": 9876543210
}
```

## Differences from Other DNSCloak Services

| Feature | Conduit | Other Services |
|---------|---------|----------------|
| User management | None (automatic) | Per-user configs |
| Connection | Via Psiphon broker | Direct to server |
| Use case | Volunteer relay | Personal VPN |
| Client apps | Psiphon apps only | Various VPN apps |
| Domain needed | No | Depends on service |

## Security Considerations

1. **No direct user access** - Users connect through Psiphon, not directly to your server
2. **No user data stored** - Conduit doesn't log user identities or traffic
3. **Ephemeral connections** - Sessions are temporary
4. **Legal considerations** - Check your jurisdiction's laws about running relay nodes

## Troubleshooting

### Service won't start

```bash
# Check logs
journalctl -u conduit -n 100

# Verify binary
/usr/local/bin/conduit --version

# Check permissions
ls -la /opt/dnscloak/conduit/
```

### No clients connecting

- New nodes need time to build reputation (hours to days)
- Ensure your server has good network connectivity
- Check that no firewall is blocking outbound connections

### High resource usage

- Reduce `--max-clients` setting
- Lower `--bandwidth` limit
- Consider upgrading server resources

## Uninstallation

```bash
# Through installer menu
curl -sSL conduit.dnscloak.net | sudo bash
# Select option 6 (Uninstall)

# Or manually
sudo systemctl stop conduit
sudo systemctl disable conduit
sudo rm /etc/systemd/system/conduit.service
sudo rm /usr/local/bin/conduit
sudo systemctl daemon-reload
```

## Resources

- [Conduit GitHub](https://github.com/ssmirr/conduit)
- [Psiphon Website](https://psiphon.ca)
- [Psiphon Tunnel Core](https://github.com/Psiphon-Labs/psiphon-tunnel-core)

## Thank You

By running a Conduit node, you're helping people in censored regions access the free and open internet. Thank you for supporting internet freedom!
