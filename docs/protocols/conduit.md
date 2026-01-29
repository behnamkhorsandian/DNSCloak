# Conduit - Psiphon Volunteer Relay

> 🧪 **Experimental**: This service is under active development.

Help users in censored regions access the open internet by running a volunteer relay node.

## What is Conduit?

Conduit turns your server into a relay node for the [Psiphon network](https://psiphon.ca). Unlike other DNSCloak services that create personal VPNs, Conduit helps **many users** by relaying their traffic through the Psiphon network.

**You don't manage users.** Psiphon handles everything—you just provide the bandwidth.

## Install

```bash
curl -sSL conduit.dnscloak.net | sudo bash
```

That's it. The script will:
1. Install Docker (if needed)
2. Ask for your settings (max clients, bandwidth)
3. Start the Conduit container
4. Show you the management dashboard

## Dashboard

Run the same command again to open the dashboard:

```bash
curl -sSL conduit.dnscloak.net | sudo bash
```

```
╔═══════════════════════════════════════════════════════════════════╗
║          CONDUIT - PSIPHON VOLUNTEER RELAY                        ║
╚═══════════════════════════════════════════════════════════════════╝

  Status: ● Running
  Max Clients: 200
  Bandwidth: Unlimited

  [STATS] Connecting: 5 | Connected: 312 | Up: 145 GB | Down: 1.5 TB

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1) View live stats
  2) View peers by country
  3) Start / Stop / Restart
  4) Change settings
  5) Update Conduit
  6) Uninstall
  0) Exit
```

## CLI Commands

You can also use the `conduit` command directly:

```bash
conduit status     # Show status and latest stats
conduit stats      # Live [STATS] stream
conduit logs       # All container logs
conduit peers      # Live peer countries (requires sudo)
conduit start      # Start container
conduit stop       # Stop container
conduit restart    # Restart container
conduit uninstall  # Remove everything
```

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Max Clients | 1000 | How many users can connect at once |
| Bandwidth | Unlimited (-1) | Speed limit in Mbps per user |

### Recommended by Server Size

| Server | RAM | Max Clients | Bandwidth |
|--------|-----|-------------|-----------|
| Small | 1 GB | 100-200 | 5-10 Mbps |
| Medium | 2 GB | 200-400 | 10-20 Mbps |
| Large | 4+ GB | 400-1000 | Unlimited |

## New Node Warming Up

⏳ **New nodes take time to receive clients!**

When you first start Conduit, you'll see messages like:
```
[ERROR] inproxy.(*Proxy).proxyOneClient#715: limited
[ERROR] inproxy.(*Proxy).proxyOneClient#719: no match
```

**This is normal!** Psiphon is testing your node's reliability before sending real traffic. This can take hours or even days. Just keep your node running 24/7.

Once clients start connecting, you'll see:
```
2026-01-29 14:24:51 [STATS] Connecting: 12 | Connected: 312 | Up: 145.1 GB | Down: 1.5 TB | Uptime: 63h29m3s
```

## Node Identity

Your node's identity key is stored in a Docker volume:

```
conduit-data:/home/conduit/data/conduit_key.json
```

**Don't delete the volume!** Psiphon tracks your node's reputation by this key. Deleting it resets your reputation to zero.

## How It Works

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│  Psiphon User   │──────│  Your Conduit   │──────│   Internet      │
│  (in Iran, etc) │      │  Relay Node     │      │                 │
└─────────────────┘      └─────────────────┘      └─────────────────┘
         │                        │
         ▼                        ▼
   ┌───────────┐            ┌───────────┐
   │  Psiphon  │◄──────────►│  Psiphon  │
   │  Client   │            │  Broker   │
   └───────────┘            └───────────┘
```

1. User in censored country downloads Psiphon app
2. Psiphon broker assigns your node to the user
3. Traffic flows through your Conduit relay
4. User accesses the open internet

## Differences from Other Services

| | Conduit | Reality/WS/etc |
|---|---------|----------------|
| **Purpose** | Help many users | Personal VPN |
| **User management** | Automatic (Psiphon) | You create users |
| **Client apps** | Psiphon only | Hiddify, v2rayNG, etc |
| **Connection** | Via Psiphon broker | Direct to your server |
| **Domain needed** | No | Depends |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| No stats showing | Wait for node to warm up (hours/days) |
| `limited` errors | Normal for new nodes, keep running |
| Container won't start | Run `docker logs conduit` to check |
| High resource usage | Lower max-clients or bandwidth in settings |

## Uninstall

From dashboard: Choose option **6) Uninstall**

Or via CLI:
```bash
sudo conduit uninstall
```

## Credits & Resources

- [Conduit](https://github.com/ssmirr/conduit) by **ssmirr** — Docker image for Psiphon Conduit
- [Conduit Manager](https://github.com/SamNet-dev/conduit-manager) by **SamNet** — Feature-rich alternative with multi-container support
- [Psiphon](https://psiphon.ca) — Circumvention tool trusted by millions

---

## Thank You! 🙏

By running a Conduit node, you're helping people in censored regions access the free and open internet. Every relay makes a difference.
