# VLESS + REALITY Protocol

REALITY is the most advanced censorship bypass protocol. It "borrows" TLS certificates from legitimate websites, making detection nearly impossible.

## Why REALITY

- No domain or certificate needed
- Immune to active probing attacks
- Traffic indistinguishable from visiting real websites
- Works in Iran, Russia, and China

## How It Works

```
+--------+          +--------+          +---------------+
| Client |  TLS 1.3 | Server |  TLS 1.3 | Camouflage    |
| (User) |--------->| (Xray) |--------->| (google.com)  |
+--------+          +--------+          +---------------+
     |                   |                     |
     |  1. ClientHello   |                     |
     |  SNI: google.com  |                     |
     |------------------>|                     |
     |                   |  2. Fetch real cert |
     |                   |-------------------->|
     |                   |<--------------------|
     |  3. ServerHello   |                     |
     |  Real google cert |                     |
     |<------------------|                     |
     |                   |                     |
     |  4. VLESS data    |                     |
     |  (encrypted)      |                     |
     |<----------------->|                     |
```

## State Machine

```
                    +-------------+
                    |    INIT     |
                    +------+------+
                           |
                           v
                    +------+------+
                    | TLS HELLO   |
                    | SNI=target  |
                    +------+------+
                           |
              +------------+------------+
              |                         |
              v                         v
       +------+------+          +-------+-------+
       | VALID CLIENT|          | INVALID/PROBE |
       | (has UUID)  |          | (no UUID)     |
       +------+------+          +-------+-------+
              |                         |
              v                         v
       +------+------+          +-------+-------+
       | VLESS PROXY |          | FORWARD TO    |
       | ESTABLISHED |          | REAL SITE     |
       +------+------+          +-------+-------+
              |                         |
              v                         v
       +------+------+          +-------+-------+
       | DATA FLOW   |          | LOOKS NORMAL  |
       +-------------+          +---------------+
```

## Installation

```bash
curl -sSL reality.dnscloak.net | sudo bash
```

## Configuration

Server generates:
- x25519 keypair (public key shared with clients)
- Short IDs for additional authentication
- Camouflage target selection

### Camouflage Targets

Good targets (fast, reliable TLS 1.3):
- www.google.com
- www.microsoft.com
- www.apple.com
- www.cloudflare.com
- www.mozilla.org

Requirements for target:
- TLS 1.3 support
- HTTP/2 support
- No redirects on port 443
- Low latency from server location

## User Management

Add user:
```bash
dnscloak add reality username
```

This generates:
- UUID for the user
- vless:// share link
- QR code for mobile apps

## Share Link Format

```
vless://UUID@SERVER:443?
  type=tcp&
  security=reality&
  pbk=PUBLIC_KEY&
  fp=chrome&
  sni=www.google.com&
  sid=SHORT_ID&
  flow=xtls-rprx-vision
  #USERNAME
```

| Parameter | Description |
|-----------|-------------|
| UUID | User's unique identifier |
| SERVER | Server IP address |
| pbk | Server's public key (base64) |
| fp | Browser fingerprint (chrome/firefox/safari) |
| sni | Camouflage target domain |
| sid | Short ID (hex string) |
| flow | Flow control (xtls-rprx-vision) |

## Client Setup

### Hiddify (iOS/Android/Desktop)

1. Copy vless:// link
2. Open Hiddify > Add profile from clipboard
3. Connect

### v2rayNG (Android)

1. Copy vless:// link
2. Menu > Import config from clipboard
3. Select config and connect

### Shadowrocket (iOS)

1. Copy vless:// link
2. Open Shadowrocket (auto-imports)
3. Enable connection

## Server Configuration

Location: `/opt/dnscloak/xray/config.json`

```json
{
  "inbounds": [{
    "tag": "reality-in",
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [
        {"id": "uuid-here", "email": "user@dnscloak", "flow": "xtls-rprx-vision"}
      ],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "dest": "www.google.com:443",
        "serverNames": ["www.google.com"],
        "privateKey": "server-private-key",
        "shortIds": ["", "abcd1234"]
      }
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
```

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Connection timeout | Firewall blocking 443 | Check `dnscloak firewall` |
| TLS handshake failed | Bad camouflage target | Try different target site |
| Invalid user | Wrong UUID | Regenerate link with `dnscloak links user` |
| Slow connection | Target site slow from server | Pick closer target |

## Security Notes

- Keep private key secure (never share)
- Public key is safe to distribute
- Each user gets unique UUID
- Short IDs add extra authentication layer
