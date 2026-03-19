# SOS - Emergency Secure Chat

> 🧪 **Experimental**: This service is under active development.

**Encrypted chat rooms over DNS tunnel for emergency communication.**

---

## Quick Start

SOS works even during **total internet blackouts** because it tunnels through DNS queries. There are three ways to connect:

| Method | Best For | Censorship Resistance |
|--------|----------|----------------------|
| **Web Client via DNSTT** | When HTTP/HTTPS is blocked | ⭐⭐⭐ Maximum |
| **TUI Client** | Terminal users, quick setup | ⭐⭐ High |
| **Direct Web Access** | Testing, no censorship | ⭐ None |

---

## DNSTT Client Setup (Required for Censored Networks)

Before using the Web Client via DNSTT, you need to set up the DNSTT tunnel client on your machine:

### Linux
```bash
curl vany.sh/dnstt/setup/linux | bash
```

### macOS
```bash
curl vany.sh/dnstt/setup/macos | bash
```

This creates a SOCKS5 proxy on `127.0.0.1:10800` that tunnels all traffic through DNS queries.

---

## Three Connection Methods

### Method 1: Web Client via DNSTT (Most Uncensorable)

**Prerequisites**: DNSTT client running (see setup above)

1. **Configure browser SOCKS5 proxy**:
   - **Firefox**: Settings → Network → Manual proxy → SOCKS Host: `127.0.0.1`, Port: `10800`
   - **Chrome**: Use extension like SwitchyOmega
   - **macOS System**: System Settings → Network → Proxies → SOCKS Proxy

2. **Navigate to relay**:
   ```
   http://relay.vany.sh:8899/
   ```

The web client features:
- **Single-page app** - No downloads, works in any browser
- **Fully encrypted** - TweetNaCl.js for client-side E2E encryption
- **TUI compatible** - Same rooms work with TUI and web clients!
- **Offline-ready** - All dependencies inlined (~100KB total)

### Method 2: TUI Client (Terminal)

Run directly in your terminal:
```bash
curl vany.sh/sos | bash
```

This downloads the Python TUI client. Features:
- Auto-connects to `relay.vany.sh:8899`
- Auto-falls back to direct connection if DNSTT unavailable
- Works in any terminal emulator

### Method 3: Direct Web Access (No Censorship Bypass)

For testing or when no censorship bypass is needed:
```
http://relay.vany.sh:8899/
```

> ⚠️ **Warning**: Direct access does NOT bypass censorship. Use only when the relay is directly accessible.

---

## Download Standalone Binary (Pre-Download Before Blackouts)

For maximum reliability, download the binary **before** an internet blackout:

| Platform | Download |
|----------|----------|
| **Windows** (64-bit) | `sos-windows-amd64.exe` |
| **macOS** (Apple Silicon) | `sos-darwin-arm64` |
| **macOS** (Intel) | `sos-darwin-amd64` |
| **Linux** (64-bit) | `sos-linux-amd64` |
| **Linux** (ARM64) | `sos-linux-arm64` |

Download from: [GitHub Releases](https://github.com/behnamkhorsandian/Vanyshsh/releases)

**macOS Users**: Run this to bypass Gatekeeper:
```bash
cd ~/Downloads && xattr -d com.apple.quarantine sos-darwin-arm64 && chmod +x sos-darwin-arm64 && ./sos-darwin-arm64
```

The binary:
- **Auto-connects** to `relay.vany.sh:8899`
- **Auto-falls back** to direct connection if DNSTT tunnel unavailable
- **Bundles DNSTT client** for maximum censorship resistance

---

## Run Your Own Relay (For Communities)

If you have a VPS and want to host a relay for your community:

**Step 1**: Ensure DNSTT is installed on your VM
```bash
curl vany.sh/dnstt | sudo bash
```

**Step 2**: Install SOS relay daemon (includes web client)
```bash
curl vany.sh/sos | sudo bash -s -- --server
```

This installs:
- Relay daemon at `/opt/vany/sos/relay.py`
- Web client at `/opt/vany/sos/www/`
- Systemd service `sos-relay`

**Step 3**: Access methods for your users

| Method | URL | Notes |
|--------|-----|-------|
| **Web (via DNSTT)** | `http://YOUR_IP:8899/` | Through SOCKS5 proxy |
| **Web (direct)** | `http://YOUR_IP:8899/` | No tunnel (less private) |
| **TUI** | `SOS_RELAY_HOST=YOUR_IP curl vany.sh/sos \| bash` | Terminal client |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         SOS ARCHITECTURE                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   USER A (TUI Client)                         USER B (Web Client)   │
│   ┌──────────────┐                           ┌──────────────┐       │
│   │   SOS TUI    │                           │   Browser    │       │
│   │   (Python)   │                           │   (app.js)   │       │
│   └──────┬───────┘                           └───────┬──────┘       │
│          │                                           │              │
│          │  DNSTT Tunnel (SOCKS5 :10800)             │              │
│          │  DNS queries to t.vany.sh            │              │
│          ▼                                           ▼              │
│   ┌──────────────────────────────────────────────────────────┐      │
│   │                    DNSTT SERVER (VM)                     │      │
│   │  ┌─────────────────────────────────────────────────────┐ │      │
│   │  │              SOS Relay Daemon (relay.py:8899)       │ │      │
│   │  │  GET /            → Web client (index.html)         │ │      │
│   │  │  POST /room       → Create room API                 │ │      │
│   │  │  GET /room/X/poll → Poll messages API               │ │      │
│   │  │  - Rooms auto-expire (1hr TTL)                      │ │      │
│   │  │  - Encrypted messages (max 500/room)                │ │      │
│   │  │  - Rate limiting (exponential backoff)              │ │      │
│   │  └─────────────────────────────────────────────────────┘ │      │
│   └──────────────────────────────────────────────────────────┘      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## TUI ↔ Web Interoperability

**TUI and Web clients can chat in the same rooms!** Both use identical crypto:

| Specification | TUI (Python) | Web (JavaScript) |
|---------------|--------------|------------------|
| Emoji set | 32 emojis in `crypto.py` | Same 32, same order |
| Room hash | `SHA256(emojis)[:16]` hex | Same formula |
| Salt | `SHA256("sos-chat-v1:"+emojis+[":"+ts])[:16]` | Same formula |
| KDF | Argon2id (time=2, mem=64MB) | PBKDF2 fallback* |
| Encryption | NaCl SecretBox | TweetNaCl.js |
| Wire format | `Base64(nonce + ciphertext)` | Same format |

> *Web uses PBKDF2 fallback in browsers without WASM support. Full Argon2id compatibility requires loading argon2-browser.

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
| **Web Client** | Browser-based access, no install required |
| **Multi-Client** | TUI and Web users can chat in the same room |

---

## User Guide

### Creating a Room

1. Run: `curl vany.sh/sos | bash`

2. Select **key mode**:
   - **🔄 Rotating** (recommended) — PIN changes every 15 seconds
   - **📌 Fixed** — Static PIN (less secure, use only if necessary)

3. Press **Create Room**

4. Share with your contact:
   - **Room ID**: 6 emojis (read phonetically)
   - **PIN**: Current 6-digit code

### Joining a Room

1. Run: `curl vany.sh/sos | bash`

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
curl vany.sh/sos | sudo bash -s -- --server
```

This installs:
- `/opt/vany/sos/relay.py` - Relay daemon
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
curl vany.sh/sos | bash

# Method 2: One-liner
SOS_RELAY_HOST=your-domain.com curl vany.sh/sos | bash
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

### "Could not resolve host: vany.sh/sos"

Your local DNS may be slow to update. Try these workarounds:

```bash
# Option 1: Flush DNS cache (macOS)
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder

# Option 2: Force resolve via curl
curl --resolve vany.sh/sos:443:188.114.97.6 https://vany.sh/sos | bash

# Option 3: Use Google DNS
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

### "Failed to connect to relay" / TUI Keeps Beeping

The standalone binary now **auto-falls back** to direct connection:

1. **If DNSTT pubkey is embedded** (production build) → tries DNSTT tunnel first
2. **If DNSTT fails or unavailable** → falls back to direct `relay.vany.sh:8899`
3. **If no pubkey** (dev build) → uses direct connection immediately

**Connection flow:**
```
Binary Start
     │
     ▼
┌─────────────────────┐
│ DNSTT pubkey set?   │──No──▶ Direct to relay.vany.sh:8899
└─────────────────────┘
     │ Yes
     ▼
┌─────────────────────┐
│ Start DNSTT tunnel  │──Fail──▶ Fallback to direct connection
└─────────────────────┘
     │ Success
     ▼
  Use SOCKS5 proxy (:10800)
```

**To override relay address:**
```bash
# Use a custom relay
SOS_RELAY_HOST=your-relay.com:8899 ./sos-darwin-arm64
```

**Verify relay service on server:**
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

SOS is part of the Vany project:

- **Repository**: https://github.com/behnamkhorsandian/Vanyshsh
- **Issues**: Report bugs or request features
- **Pull requests**: Welcome!

## License

MIT License - See [LICENSE](../../LICENSE)
