# VLESS + WebSocket + CDN

Route traffic through Cloudflare CDN. Hides server IP completely.

## Why WebSocket + CDN

- Server IP hidden behind Cloudflare
- Survives IP-based blocking
- Uses Cloudflare's global network
- Fallback when direct connections blocked

## When to Use

- Direct connections to server are blocked
- Need to hide server IP
- Have domain on Cloudflare
- As backup when Reality stops working

## How It Works

```text
+--------+           +-----------+           +--------+           +----------+
| Client |   HTTPS   | Cloudflare|  HTTPS    | Server |  Direct   | Internet |
| (App)  |---------->| CDN       |---------->| (Xray) |---------->|          |
+--------+  WS       +-----------+   WS      +--------+           +----------+
     |                     |                     |
     | WebSocket over      | CF terminates TLS   |
     | Cloudflare CDN      | Re-encrypts to      |
     |                     | origin              |
```

## State Machine

```text
                +-------------+
                |    INIT     |
                +------+------+
                       |
                       | HTTPS to Cloudflare
                       v
                +------+------+
                | CF EDGE     |
                | (TLS term)  |
                +------+------+
                       |
                       | WebSocket Upgrade
                       v
                +------+------+
                | WS TUNNEL   |
                | TO ORIGIN   |
                +------+------+
                       |
                       | VLESS Auth (UUID)
                       v
                +------+------+
                | PROXY       |
                | ESTABLISHED |
                +------+------+
                       |
                       v
                +------+------+
                | DATA FLOW   |
                | (via CDN)   |
                +-------------+
```

## Prerequisites

- Domain on Cloudflare (free plan works)
- DNS A record with orange cloud (Proxied)
- WebSockets enabled in Cloudflare

## Installation

```bash
curl -sSL ws.dnscloak.net | sudo bash
```

During setup:
1. Enter your Cloudflare domain
2. (Optional) Provide CF API token for auto-config
3. Create first user

## Cloudflare Configuration

### DNS Record

```text
Type: A
Name: ws (or subdomain of choice)
IPv4: <your-server-ip>
Proxy: Proxied (orange cloud)  <-- REQUIRED
```

### SSL/TLS Settings

1. Go to SSL/TLS > Overview
2. Set mode to "Full" or "Full (Strict)"

### Network Settings

1. Go to Network
2. Enable WebSockets: ON

### (Optional) Page Rules

For better caching:
```text
URL: ws.yourdomain.com/*
Settings:
  - Cache Level: Bypass
  - Browser Cache TTL: Bypass
```

## User Management

Add user:
```bash
dnscloak add ws alice
```

Generates:
- UUID for user
- vless:// link (CDN-compatible)
- QR code

## Share Link Format

```text
vless://UUID@ws.DOMAIN:443?
  type=ws&
  security=tls&
  path=/RANDOM_PATH&
  host=ws.DOMAIN&
  sni=ws.DOMAIN
  #USERNAME
```

| Parameter | Description |
|-----------|-------------|
| UUID | User's unique identifier |
| DOMAIN | Your Cloudflare domain |
| type | ws (WebSocket) |
| path | WebSocket path (randomized) |
| host | Host header |
| sni | Server Name Indication |

## Client Setup

Same as other VLESS services - use Hiddify, v2rayNG, or Shadowrocket.

## Server Configuration

Location: `/opt/dnscloak/xray/config.json`

```json
{
  "inbounds": [{
    "tag": "ws-in",
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [
        {"id": "uuid-here", "email": "alice@dnscloak"}
      ],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {
        "path": "/your-random-path",
        "headers": {"Host": "ws.yourdomain.com"}
      },
      "security": "tls",
      "tlsSettings": {
        "serverName": "ws.yourdomain.com",
        "certificates": [{
          "certificateFile": "/opt/dnscloak/certs/ws.yourdomain.com/fullchain.pem",
          "keyFile": "/opt/dnscloak/certs/ws.yourdomain.com/privkey.pem"
        }]
      }
    }
  }]
}
```

## Port Sharing

WS service shares port 443 via path-based routing:

```text
Port 443
    |
    +-- SNI: google.com      --> Reality (tcp)
    +-- SNI: yourdomain.com  --> V2Ray (tcp)
    +-- Path: /ws-path       --> WS (websocket)
```

## Cloudflare Limits (Free Plan)

| Limit | Value |
|-------|-------|
| WebSocket connections | Unlimited |
| WebSocket message size | 100 MB |
| Request timeout | 100 seconds |

For high traffic, consider Cloudflare Pro.

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| 502 Bad Gateway | Origin server down | Check Xray is running |
| 521 Web server down | Origin refused connection | Verify port 443 open |
| 525 SSL handshake failed | Certificate issue | Check TLS cert on origin |
| WebSocket error | WS not enabled in CF | Enable in Network settings |
| Slow speeds | Free plan limits | Use closer CF datacenter |

## Comparison

| Aspect | WS+CDN | Reality | V2Ray |
|--------|--------|---------|-------|
| Server IP visible | No (hidden) | Yes | Yes |
| Extra latency | Yes (+20-50ms) | No | No |
| Domain required | Yes | No | Yes |
| Survives IP block | Yes | No | No |
| Cloudflare account | Required | Not needed | Not needed |

## Security Notes

- Server IP never exposed to client
- Cloudflare sees metadata (not content due to TLS)
- Use unique path per deployment
- Enable Cloudflare firewall rules for extra protection
