# SOS - Emergency Secure Chat

**Encrypted chat rooms over DNS tunnel for emergency communication.**

---

## Two Ways to Use SOS

### Option 1: Be a User (Join Public Relay)

Just run:
```bash
curl -sSL sos.dnscloak.net | bash
```

This downloads the TUI client and connects to the public DNSCloak relay. Best for:
- Users who just need to chat during emergencies
- Testing the system
- Those who don't have their own server

### Option 2: Run Your Own Relay (For Communities)

If you have a DNSTT server and want to host a relay for your community:

**Step 1**: Ensure DNSTT is installed on your VM
```bash
curl -sSL dnstt.dnscloak.net | sudo bash
```

**Step 2**: Install SOS relay daemon
```bash
curl -sSL sos.dnscloak.net | sudo bash -s -- --server
```

**Step 3**: Tell users how to connect
```bash
# Users connect by setting your relay address:
SOS_RELAY_HOST=your-server.com curl -sSL sos.dnscloak.net | bash
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SOS ARCHITECTURE                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   USER A (Creator)                            USER B (Joiner)                │
│   ┌──────────────┐                           ┌──────────────┐                │
│   │   SOS TUI    │                           │   SOS TUI    │                │
│   │   (Client)   │                           │   (Client)   │                │
│   └──────┬───────┘                           └───────┬──────┘                │
│          │                                           │                       │
│          │  DNS Queries (DNSTT tunnel)               │                       │
│          │  abc123.t.dnscloak.net                    │                       │
│          ▼                                           ▼                       │
│   ┌──────────────────────────────────────────────────────────┐               │
│   │                    DNSTT SERVER (VM)                      │               │
│   │  ┌─────────────────────────────────────────────────────┐ │               │
│   │  │              SOS Relay Daemon (relay.py)            │ │               │
│   │  │  - Creates/manages rooms (1hr TTL)                  │ │               │
│   │  │  - Stores encrypted messages (max 500)              │ │               │
│   │  │  - Rate limiting (exponential backoff)              │ │               │
│   │  │  - Redis or in-memory storage                       │ │               │
│   │  └─────────────────────────────────────────────────────┘ │               │
│   └──────────────────────────────────────────────────────────┘               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Features

| Feature | Description |
|---------|-------------|
| **6-Emoji Room ID** | Easy to share verbally (e.g., "fire moon star target wave gem") |
| **6-Digit PIN** | Rotating every 15 seconds (secure) or fixed (for delays) |
| **1-Hour TTL** | Rooms auto-wipe after 1 hour, no traces left |
| **Message Cache** | Reconnect and see missed messages (up to 500) |
| **E2E Encrypted** | NaCl (XSalsa20-Poly1305) + Argon2id key derivation |
| **DNS Transport** | Works when HTTP/HTTPS is blocked during blackouts |

---

## User Guide

### Creating a Room

1. Run: `curl -sSL sos.dnscloak.net | bash`

2. Select **key mode**:
   - **🔄 Rotating** (recommended) — PIN changes every 15 seconds
   - **📌 Fixed** — Static PIN (less secure, use only if necessary)

3. Press **Create Room**

4. Share with your contact:
   - **Room ID**: 6 emojis (read phonetically)
   - **PIN**: Current 6-digit code

### Joining a Room

1. Run: `curl -sSL sos.dnscloak.net | bash`

2. Press **Join Room**

3. Enter the 6 emojis using the picker

4. Enter the 6-digit PIN

5. Start chatting!

---

## Emoji Set (32 Emojis)

Use these phonetic names when sharing room IDs verbally:

| Emoji | Phonetic | Emoji | Phonetic | Emoji | Phonetic | Emoji | Phonetic |
|-------|----------|-------|----------|-------|----------|-------|----------|
| 🔥 | fire | 🌙 | moon | ⭐ | star | 🎯 | target |
| 🌊 | wave | 💎 | gem | 🍀 | clover | 🎲 | dice |
| 🚀 | rocket | 🌈 | rainbow | ⚡ | bolt | 🎵 | music |
| 🔑 | key | 🌸 | bloom | 🍄 | shroom | 🦋 | butterfly |
| 🎪 | circus | 🌵 | cactus | 🍎 | apple | 🐋 | whale |
| 🦊 | fox | 🌻 | sunflower | 🎭 | mask | 🔔 | bell |
| 🏔️ | mountain | 🌴 | palm | 🍕 | pizza | 🐙 | octopus |
| 🦉 | owl | 🌺 | hibiscus | 🎨 | palette | 🔮 | crystal |

**Example verbal share:**
> "Room is: fire, moon, star, target, wave, gem. PIN is eight-four-seven-two-nine-one."

---

## Key Modes Explained

### 🔄 Rotating Mode (Recommended)

- PIN changes every **15 seconds**
- Creator reads current PIN to joiner over phone/radio
- Even if intercepted, key rotates quickly
- **Best for**: Live communication (phone call, radio)

### 📌 Fixed Mode

- PIN stays **constant** for room lifetime
- Creator shares PIN once, joiner enters later
- Less secure: if intercepted, room is compromised
- **Best for**: When live communication isn't possible

> ⚠️ **Warning**: Fixed mode should only be used when absolutely necessary.

---

## Server Setup (Relay Operators)

### Prerequisites

- Ubuntu 22.04 VM with public IP
- DNSTT server already installed
- Optional: Redis for persistent storage

### Installation

```bash
# SSH to your server
ssh root@your-server-ip

# Install SOS relay (requires DNSTT already running)
curl -sSL sos.dnscloak.net | sudo bash -s -- --server
```

This installs:
- `/opt/dnscloak/sos/relay.py` - Relay daemon
- `/etc/systemd/system/sos-relay.service` - Systemd service
- Dependencies: aiohttp, pynacl, argon2-cffi, redis

### Managing the Service

```bash
# Check status
systemctl status sos-relay

# View logs
journalctl -u sos-relay -f

# Restart
systemctl restart sos-relay

# Stop
systemctl stop sos-relay
```

### Telling Users Your Relay Address

Users connect to your relay by setting environment variables:

```bash
# Method 1: Environment variable
export SOS_RELAY_HOST="your-dnstt-domain.com"
export SOS_RELAY_PORT="8899"
curl -sSL sos.dnscloak.net | bash

# Method 2: One-liner
SOS_RELAY_HOST=your-domain.com curl -sSL sos.dnscloak.net | bash
```

---

## Security Model

### Encryption

1. **Key Derivation**: `Argon2id(emoji_codepoints + pin + timestamp_bucket)`
   - `timestamp_bucket = floor(time / 15) * 15` for rotating mode
   - `timestamp_bucket = room_created_at` for fixed mode

2. **Message Encryption**: NaCl SecretBox
   - Cipher: XSalsa20-Poly1305
   - 24-byte random nonce per message
   - Authenticated encryption (AEAD)

3. **Room ID Hash**: `SHA256(emoji_string)[:16]`
   - Server never sees actual emoji sequence

### What the Server Sees

| Data | Visible? |
|------|----------|
| Room emoji IDs | ❌ (only hash) |
| Message contents | ❌ (E2E encrypted) |
| PIN values | ❌ |
| Room hash | ✅ |
| Member count | ✅ |
| Message timestamps | ✅ |
| Client IPs (via DNSTT) | ✅ |

---

## Rate Limiting

To prevent abuse, room creation is rate-limited per IP:

| Attempt | Delay |
|---------|-------|
| 1st | Immediate |
| 2nd | 10 seconds |
| 3rd | 30 seconds |
| 4th | 60 seconds |
| 5th | 3 minutes |
| 6th+ | 5 minutes each |

- Rate limit resets after **30 minutes** of inactivity
- Successful room **join** resets rate limit immediately

---

## Troubleshooting

### "Could not resolve host: sos.dnscloak.net"

DNS might be blocked. Try:
```bash
# Use Google DNS
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

### "Failed to connect to relay"

1. Check if DNSTT is working:
   ```bash
   curl --socks5 127.0.0.1:10800 http://ifconfig.me
   ```

2. Verify relay service is running:
   ```bash
   systemctl status sos-relay
   ```

### "Could not decrypt message"

- **Rotating mode**: Both parties must enter PIN within same 15-second window
- **Fixed mode**: Verify PIN matches exactly
- Check both selected same key mode

### TUI doesn't launch

```bash
# Check Python version (need 3.8+)
python3 --version

# Manual install
pip3 install textual pynacl httpx argon2-cffi
python3 -c "from sos.app import SOSApp; SOSApp().run()"
```

---

## Emergency Checklist

### For Total Internet Blackouts

SOS works because DNS often remains functional when HTTP/HTTPS is blocked:

- [ ] ISP blocks ports 80/443 → DNSTT uses port 53 (DNS)
- [ ] DPI enabled → DNS queries look legitimate
- [ ] IP blocking → DNS uses distributed resolution

### Quick Setup

- [ ] DNSTT server running outside censored region
- [ ] DNS records configured (NS + A record)
- [ ] Both parties can resolve DNS (`nslookup google.com`)
- [ ] Share room ID + PIN through second channel (phone, radio, in-person)

---

## Contributing

SOS is part of the DNSCloak project:

- **Repository**: https://github.com/behnamkhorsandian/DNSCloak
- **Issues**: Report bugs or request features
- **Pull requests**: Welcome!

## License

MIT License - See [LICENSE](../../LICENSE)
