# SOS - Emergency Secure Chat

**One-liner emergency chat over DNS tunnel.**

```bash
curl -sSL sos.dnscloak.net | sudo bash
```

## Overview

SOS creates encrypted, ephemeral chat rooms that tunnel through DNS—working even during total internet blackouts when HTTP/HTTPS is blocked. Perfect for emergency communication in countries like Iran, China, and Russia during crackdowns.

### Key Features

- **6-Emoji Room ID** — Easy to share verbally (e.g., "fire moon star target wave gem")
- **6-Digit PIN** — Rotating every 15 seconds (secure) or fixed (for emergencies)
- **1-Hour TTL** — Rooms auto-wipe after 1 hour, no traces left
- **Message Cache** — Reconnect and see missed messages (up to 500)
- **E2E Encrypted** — NaCl (XSalsa20-Poly1305) + Argon2id key derivation
- **DNS Transport** — Works when all else is blocked

## How It Works

```
┌────────────────────────────────────────────────────┐
│                  SOS Architecture                  │
├────────────────────────────────────────────────────┤
│                                                    │
│   User A (Creator)              User B (Joiner)    │
│   ┌──────────────┐              ┌──────────────┐   │
│   │   TUI App    │              │   TUI App    │   │
│   │ ────────────▶│──────────────│◀──────────── │   │
│   │ Create Room  │    Share:    │  Enter Room  │   │
│   │  🦁🌞🫀🌱🕊️🗝️  │  "lion, sun, │  ID + PIN    │   │
│   │ PIN: 847291  │   heart..."  │              │   │
│   └──────┬───────┘              └──────┬───────┘   │
│          │                             │           │
│          │        E2E Encrypted        │           │
│          └──────────────┬──────────────┘           │
│                         │                          │
│                         ▼                          │
│              ┌──────────────────┐                  │
│              │   DNSTT Client   │                  │
│              │  (SOCKS5 proxy)  │                  │
│              └────────┬─────────┘                  │
│                       │                            │
│          ┌────────────┼────────────┐               │
│          │     DNS Queries         │               │
│          │  abc123.t.dnscloak.net  │               │
│          └────────────┼────────────┘               │
│                       │                            │
│                       ▼                            │
│     ┌─────────────────────────────────────┐        │
│     │         DNSTT Server                │        │
│     │   ┌───────────────────────────┐     │        │
│     │   │      SOS Relay Daemon     │     │        │
│     │   │  - Room management        │     │        │
│     │   │  - Message storage (1hr)  │     │        │
│     │   │  - Rate limiting          │     │        │
│     │   └───────────────────────────┘     │        │
│     └─────────────────────────────────────┘        │
│                                                    │
└────────────────────────────────────────────────────┘
```

## Usage

### Creating a Room

1. Run the installer:
   ```bash
   curl -sSL sos.dnscloak.net | sudo bash
   ```

2. Select **key mode**:
   - **🔄 Rotating** (recommended) — PIN changes every 15 seconds
   - **📌 Fixed** — Static PIN (less secure, use only if necessary)

3. Press **Create Room**

4. Share with your contact:
   - **Room ID**: 6 emojis (e.g., 🔥🌙⭐🎯🌊💎)
   - **Phonetic**: "fire moon star target wave gem"
   - **PIN**: Current 6-digit code (if rotating, read it live)

### Joining a Room

1. Run the installer (same command)

2. Press **Join Room**

3. Enter the 6 emojis using the picker

4. Enter the 6-digit PIN

5. Start chatting!

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

## Key Modes

### 🔄 Rotating Mode (Default)

- PIN changes every **15 seconds**
- Creator reads current PIN to joiner over phone/radio
- More secure: even if someone intercepts, key rotates
- Best for: secure communications where you can speak

### 📌 Fixed Mode

- PIN stays **constant** for room lifetime
- Creator can share PIN once, joiner enters later
- Less secure: if intercepted, room is compromised
- Best for: situations where live communication isn't possible

**Warning**: Fixed mode should only be used when absolutely necessary. The rotating mode provides significantly better security.

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
   - Can't reverse room ID from hash

### What the Server Sees

- ❌ Room emoji IDs (only hash)
- ❌ Message contents (E2E encrypted)
- ❌ PIN values
- ✅ Room hash, member count, message timestamps
- ✅ Client IP addresses (through DNSTT)

### Limitations

- If attacker knows room ID + has PIN, they can decrypt
- DNSTT provides transport security, not anonymity
- Messages cached for 1 hour (then wiped)
- 500 message limit per room

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

Rate limit resets after **30 minutes** of no attempts.
Successful room **join** resets rate limit immediately.

## Server Setup (Optional)

SOS uses the public DNSTT infrastructure by default. To run your own:

### 1. Install DNSTT with SOS Support

```bash
curl -sSL dnstt.dnscloak.net | sudo bash -- --with-sos
```

### 2. Manual SOS Relay Setup

If you already have DNSTT:

```bash
# Install Redis
apt install redis-server

# Install Python dependencies
pip3 install aiohttp aioredis

# Copy relay daemon
cp /path/to/relay.py /opt/dnscloak/sos/relay.py

# Create systemd service
cat > /etc/systemd/system/sos-relay.service << 'EOF'
[Unit]
Description=SOS Emergency Chat Relay
After=network.target redis.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/dnscloak/sos/relay.py
Restart=always
RestartSec=5
Environment=REDIS_URL=redis://localhost:6379
Environment=SOS_HOST=127.0.0.1
Environment=SOS_PORT=8899

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now sos-relay
```

### 3. Configure Client

Set environment variables before running:

```bash
export SOS_RELAY_HOST="your-server.com"
export SOS_RELAY_PORT="8899"
curl -sSL sos.dnscloak.net | sudo bash
```

## Troubleshooting

### "Failed to connect to relay"

1. Check if DNSTT tunnel is working:
   ```bash
   curl --socks5 127.0.0.1:10800 http://ifconfig.me
   ```

2. Verify relay is accessible through tunnel

3. Try running in offline mode (local-only chat)

### "Could not decrypt message"

- **Rotating mode**: Make sure both parties entered PIN within same 15-second window
- **Fixed mode**: Verify PIN matches exactly
- Check both parties selected same key mode

### "Rate limited"

Wait for the cooldown period. Successful joins reset the limit.

### TUI doesn't launch

1. Check Python version: `python3 --version` (need 3.8+)
2. Check Textual installed: `pip3 show textual`
3. Try manual install:
   ```bash
   pip3 install textual pynacl httpx argon2-cffi
   python3 -m sos.app
   ```

## Emergency Scenarios

### Total Internet Blackout

SOS works because DNS queries often remain functional when HTTP/HTTPS is blocked:

1. ISP blocks ports 80/443 → DNSTT uses port 53 (DNS)
2. Deep Packet Inspection → DNS queries look legitimate
3. IP blocking → DNS uses distributed resolution

### Quick Setup Checklist

- [ ] DNSTT server running somewhere outside censored region
- [ ] DNS records configured (NS + A record)
- [ ] Both parties can resolve DNS (test: `nslookup google.com`)
- [ ] Share room ID + PIN through a second channel (phone, radio, in-person)

## Contributing

SOS is part of the DNSCloak project:

- Repository: https://github.com/behnamkhorsandian/DNSCloak
- Issues: Report bugs or request features
- Pull requests welcome!

## License

MIT License - See [LICENSE](../../LICENSE)
