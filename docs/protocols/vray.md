# VLESS + TCP + TLS (V2Ray)

Classic V2Ray setup with proper TLS certificates. Requires a domain.

## Why V2Ray/VLESS

- Well-established protocol
- Proper TLS (not borrowed like Reality)
- Good client support
- Can use with Cloudflare (gray cloud)

## When to Use

- You have a domain
- Reality is blocked (rare)
- Need proper certificate for compliance
- Prefer traditional TLS setup

## How It Works

```text
+--------+           +--------+           +----------+
| Client |   TLS 1.3 | Server |   Direct  | Internet |
| (App)  |---------->| (Xray) |---------->|          |
+--------+  VLESS    +--------+           +----------+
     |                   |
     | Real certificate  |
     | for your domain   |
     |                   |
```

## State Machine

```text
                +-------------+
                |    INIT     |
                +------+------+
                       |
                       | TCP + TLS Handshake
                       v
                +------+------+
                | TLS VERIFY  |
                | (Real cert) |
                +------+------+
                       |
          +------------+------------+
          |                         |
          v                         v
   +------+------+          +-------+-------+
   | CERT VALID  |          | CERT INVALID  |
   +------+------+          +---------------+
          |
          v
   +------+------+
   | VLESS AUTH  |
   | (UUID)      |
   +------+------+
          |
          v
   +------+------+
   | PROXY       |
   | ESTABLISHED |
   +------+------+
          |
          v
   +------+------+
   | DATA FLOW   |
   +-------------+
```

## Prerequisites

- Domain name (e.g., proxy.yourdomain.com)
- DNS A record pointing to server
- Port 443 available

## Installation

```bash
curl -sSL vray.dnscloak.net | sudo bash
```

During setup:
1. Enter your domain
2. Choose certificate method (auto Let's Encrypt or manual)
3. Create first user

## Certificate Management

### Automatic (Let's Encrypt)

Installer uses acme.sh:
```bash
# Certificates stored at
/opt/dnscloak/certs/yourdomain.com/fullchain.pem
/opt/dnscloak/certs/yourdomain.com/privkey.pem

# Auto-renewal via cron
0 0 * * * /root/.acme.sh/acme.sh --cron
```

### Manual Certificate

If you have existing certificates:
```bash
# Place at
/opt/dnscloak/certs/yourdomain.com/fullchain.pem
/opt/dnscloak/certs/yourdomain.com/privkey.pem
```

## User Management

Add user:
```bash
dnscloak add vray alice
```

Generates:
- UUID for user
- vless:// share link
- QR code

## Share Link Format

```text
vless://UUID@DOMAIN:443?
  type=tcp&
  security=tls&
  sni=DOMAIN&
  fp=chrome
  #USERNAME
```

| Parameter | Description |
|-----------|-------------|
| UUID | User's unique identifier |
| DOMAIN | Your domain name |
| security | tls (proper certificates) |
| sni | Server Name Indication |
| fp | Browser fingerprint |

## Client Setup

Same as Reality - use Hiddify, v2rayNG, or Shadowrocket.

1. Copy vless:// link
2. Import in app
3. Connect

## Server Configuration

Shares Xray instance with Reality.

Location: `/opt/dnscloak/xray/config.json`

```json
{
  "inbounds": [
    {
      "tag": "vray-in",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {"id": "uuid-here", "email": "alice@dnscloak"}
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "proxy.yourdomain.com",
          "certificates": [{
            "certificateFile": "/opt/dnscloak/certs/proxy.yourdomain.com/fullchain.pem",
            "keyFile": "/opt/dnscloak/certs/proxy.yourdomain.com/privkey.pem"
          }]
        }
      }
    }
  ]
}
```

## Port Sharing with Reality

When both Reality and V2Ray are installed:

```text
Port 443
    |
    +-- SNI: www.google.com --> Reality inbound
    |
    +-- SNI: proxy.yourdomain.com --> V2Ray inbound
```

Xray routes based on SNI automatically.

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Certificate error | DNS not pointing to server | Check A record |
| Let's Encrypt failed | Port 80 blocked | Open port 80 for verification |
| TLS handshake failed | Wrong SNI in client | Match domain exactly |
| Connection refused | Xray not running | Check `dnscloak status` |

## Comparison

| Aspect | V2Ray (TLS) | Reality |
|--------|-------------|---------|
| Domain required | Yes | No |
| Certificate | Real (Let's Encrypt) | Borrowed |
| Setup complexity | Medium | Low |
| Detection resistance | Good | Excellent |
| Active probing | Vulnerable | Immune |

## Security Notes

- Certificates renew automatically
- Private key permissions: 600
- Let's Encrypt rate limits: 50 certs/week per domain
