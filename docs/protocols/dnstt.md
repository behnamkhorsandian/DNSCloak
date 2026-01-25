# DNS Tunnel (DNStt)

Emergency protocol for extreme censorship. Tunnels data through DNS queries.

## Why DNS Tunnel

- Works when everything else is blocked
- DNS usually remains open (required for basic internet)
- Last resort during digital blackouts
- Very difficult to block without breaking internet

## Limitations

- Very slow (50-150 kbps typical)
- High latency (500ms+)
- Requires domain with NS records
- Complex setup

## When to Use

- Total internet shutdown (except DNS)
- All other protocols blocked
- Emergency communication only
- Not for daily use

## How It Works

```text
+--------+            +---------+            +--------+            +--------+
| Client |  DNS Query | Local   |  DNS Query | Auth   |  DNS Query | Your   |
| Device |----------->| ISP DNS |----------->| DNS    |----------->| Server |
+--------+            +---------+            | (CF)   |            +--------+
     ^                                       +--------+                 |
     |                                                                  |
     +---------------------------DNS Response---------------------------+
                         (Data encoded in DNS)
```

Data is encoded in DNS queries:
- Requests: encoded in subdomain (e.g., `abc123.t.yourdomain.com`)
- Responses: encoded in TXT/NULL records

## State Machine

```text
                +-------------+
                |    INIT     |
                +------+------+
                       |
                       | DNS Query to
                       | t.yourdomain.com
                       v
                +------+------+
                | NS LOOKUP   |
                | (Find auth  |
                |  server)    |
                +------+------+
                       |
                       | Query to ns1.yourdomain.com
                       v
                +------+------+
                | DNSTT       |
                | HANDSHAKE   |
                +------+------+
                       |
                       v
                +------+------+
                | TUNNEL      |
                | ESTABLISHED |
                +------+------+
                       |
                       | Encoded DNS queries
                       v
                +------+------+
                | SOCKS5      |
                | AVAILABLE   |
                | 127.0.0.1:  |
                | 1080        |
                +-------------+
```

## Prerequisites

- Domain with DNS control
- Ability to set NS records
- Not behind Cloudflare (needs direct DNS)

## DNS Setup

### Step 1: A Record for Nameserver

```text
Type: A
Name: ns1
Value: <your-server-ip>
TTL: Auto
```

### Step 2: NS Record for Tunnel Subdomain

```text
Type: NS
Name: t
Value: ns1.yourdomain.com
TTL: Auto
```

### Verification

```bash
# Should return your server IP
dig ns1.yourdomain.com

# Should show ns1.yourdomain.com
dig NS t.yourdomain.com
```

## Installation

```bash
curl -sSL dnstt.dnscloak.net | sudo bash
```

During setup:
1. Enter your domain (yourdomain.com)
2. Script verifies DNS records
3. Generates keypair
4. Starts dnstt-server

## Server Components

```text
/opt/dnscloak/dnstt/
    server.key          # Server private key
    server.pub          # Server public key (share with clients)
    dnstt-server        # Server binary
```

## Client Setup

DNStt requires a native client on user's device.

### Linux/macOS

```bash
# Download client
curl -LO https://github.com/nicholasmhughes/dnstt/releases/latest/download/dnstt-client-linux-amd64

# Run
./dnstt-client-linux-amd64 \
  -udp <local-dns-server>:53 \
  -pubkey <server-public-key> \
  t.yourdomain.com 127.0.0.1:1080
```

### Windows

```powershell
# Download from releases
# Run in PowerShell
.\dnstt-client-windows-amd64.exe `
  -udp 8.8.8.8:53 `
  -pubkey <server-public-key> `
  t.yourdomain.com 127.0.0.1:1080
```

### Android (HTTP Injector)

1. Install HTTP Injector
2. Add SSH tunnel:
   - Host: 127.0.0.1
   - Port: 1080
3. Configure DNS tunnel (advanced)

## Using the Tunnel

Once client is running, configure apps to use SOCKS5:
- Server: 127.0.0.1
- Port: 1080

### Browser Setup

Firefox:
1. Settings > Network Settings
2. Manual proxy > SOCKS Host: 127.0.0.1, Port: 1080
3. SOCKS v5, Proxy DNS when using SOCKS

### System-wide (Linux)

```bash
export http_proxy=socks5://127.0.0.1:1080
export https_proxy=socks5://127.0.0.1:1080
```

## Server Configuration

Location: `/opt/dnscloak/dnstt/`

Service file: `/etc/systemd/system/dnstt.service`

```ini
[Unit]
Description=DNStt Server
After=network.target

[Service]
Type=simple
ExecStart=/opt/dnscloak/dnstt/dnstt-server \
  -udp :5300 \
  -privkey-file /opt/dnscloak/dnstt/server.key \
  t.yourdomain.com \
  127.0.0.1:1080
Restart=always

[Install]
WantedBy=multi-user.target
```

## Port Forwarding

DNS uses port 53, but we run on 5300 and redirect:

```bash
# Redirect UDP 53 to 5300
iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-port 5300
```

## Commands

```bash
# Status
sudo systemctl status dnstt

# Logs
sudo journalctl -u dnstt -f

# Restart
sudo systemctl restart dnstt
```

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "no such host" | NS record not set | Verify DNS setup |
| Connection timeout | UDP 53 blocked | Use different upstream DNS |
| Very slow | Normal for DNS tunnel | Expected, not for heavy use |
| Client can't resolve | Dante SOCKS not running | Check Dante service |

## Performance Tips

- Use DNS server geographically close to your server
- Avoid DNS servers with aggressive caching
- Good upstream DNS: 8.8.8.8, 1.1.1.1, 9.9.9.9

## Security Notes

- Server key is sensitive - keep private
- Public key can be shared openly
- Traffic is encrypted (Noise protocol)
- DNS providers can see query metadata
- No user authentication (single-user per server)

## Comparison

| Aspect | DNStt | Reality | WireGuard |
|--------|-------|---------|-----------|
| Speed | Very slow | Fast | Very fast |
| Works when blocked | Usually | Sometimes | Often blocked |
| Setup complexity | High | Low | Low |
| Domain required | Yes (NS) | No | No |
| Use case | Emergency | Daily use | Daily use |
