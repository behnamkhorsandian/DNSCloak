# MTProto Proxy

MTProto Proxy with Fake-TLS makes Telegram accessible in restricted regions by disguising traffic as HTTPS.

## Why MTProto

- Native Telegram support (no extra apps)
- Simple user experience
- Built specifically for Telegram
- Fake-TLS bypasses basic DPI

## Limitations

- Telegram only (not general proxy)
- Well-known protocol (targeted by censors)
- May be blocked during heavy crackdowns

## How It Works

```
+--------+           +--------+           +----------+
| Tele-  | Fake-TLS  | MTP    |  MTProto  | Telegram |
| gram   |---------->| Proxy  |---------->| Servers  |
| App    |           | Server |           |          |
+--------+           +--------+           +----------+
     |                   |
     | Looks like HTTPS  |
     | to google.com     |
     |                   |
```

## State Machine

```
                +-------------+
                |    INIT     |
                +------+------+
                       |
                       | TCP Connect
                       v
                +------+------+
                | TLS HELLO   |
                | SNI=fake    |
                | domain      |
                +------+------+
                       |
          +------------+------------+
          |                         |
          v                         v
   +------+------+          +-------+-------+
   | SECRET OK   |          | SECRET WRONG  |
   | (ee+secret) |          | (rejected)    |
   +------+------+          +---------------+
          |
          v
   +------+------+
   | MTPROTO     |
   | ESTABLISHED |
   +------+------+
          |
          v
   +------+------+
   | DATA FLOW   |
   | (Telegram)  |
   +-------------+
```

## Secret Types

| Prefix | Mode | Description |
|--------|------|-------------|
| `ee` | Fake-TLS | Traffic looks like HTTPS. Recommended. |
| `dd` | Secure | Random padding. Fallback option. |

## Installation

```bash
curl -sSL mtp.dnscloak.net | sudo bash
```

## User Management

Add user:
```bash
dnscloak add mtp alice
```

Generates:
- 32-character hex secret
- tg:// proxy link
- QR code

## Share Link Format

```
tg://proxy?server=SERVER&port=443&secret=ee<SECRET><DOMAIN_HEX>
```

| Part | Description |
|------|-------------|
| server | Server IP or domain |
| port | Listening port (default 443) |
| secret | ee + 32-char hex + domain in hex |

Example with google.com:
```
tg://proxy?server=1.2.3.4&port=443&secret=ee1234567890abcdef1234567890abcdef676f6f676c652e636f6d
```

Where `676f6f676c652e636f6d` is "google.com" in hex.

## Client Setup

### Mobile (iOS/Android)

1. Click the tg:// link
2. Telegram opens automatically
3. Tap "Connect Proxy"
4. Done

### Desktop

1. Click the tg:// link, or
2. Settings > Advanced > Connection type > Use custom proxy
3. Add MTProto Proxy
4. Enter: Server, Port, Secret

## Server Configuration

Location: `/opt/dnscloak/mtp/config.py`

```python
PORT = 443

USERS = {
    "alice": "1234567890abcdef1234567890abcdef",
    "bob": "fedcba0987654321fedcba0987654321",
}

MODES = {
    "classic": False,
    "secure": True,
    "tls": True,
}

TLS_DOMAIN = "google.com"

STATS_PORT = 8888
```

## Commands

```bash
# Check status
sudo systemctl status telegram-proxy

# View logs
sudo journalctl -u telegram-proxy -f

# Restart
sudo systemctl restart telegram-proxy
```

## Fake-TLS Domains

Good choices:
- google.com (default)
- microsoft.com
- apple.com
- cloudflare.com

Requirements:
- Popular site (blends in)
- TLS 1.3 support
- Not blocked in target country

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "Proxy unavailable" | Firewall blocking | Open port 443 TCP |
| Connection drops | IP changed | Run `dnscloak update-ip` |
| Using domain + CF orange cloud | CF proxying breaks MTP | Use gray cloud (DNS only) |
| Link not working | Wrong secret format | Regenerate with `dnscloak links user` |

## Comparison with Reality

| Aspect | MTProto | Reality |
|--------|---------|---------|
| Apps supported | Telegram only | All apps |
| Extra app needed | No | Yes (Hiddify/v2rayNG) |
| Detection resistance | Medium | High |
| Setup complexity | Low | Medium |
| Best for | Telegram users | Full internet access |

## Security Notes

- Secrets are per-user
- Server logs can be enabled for debugging
- Stats available on port 8888 (local only)
- Promoted channels shown to users (Telegram feature)
