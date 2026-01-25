# WireGuard VPN

WireGuard is a fast, modern VPN protocol. Simple configuration, excellent performance.

## Why WireGuard

- Fastest VPN protocol available
- Simple configuration (vs OpenVPN)
- Built into Linux kernel
- Native apps on all platforms
- Strong cryptography (Curve25519, ChaCha20)

## Limitations

- UDP-based (may be blocked in some networks)
- Distinctive handshake pattern (detectable by DPI)
- For heavy censorship, use Reality instead

## How It Works

```text
+--------+                    +--------+
| Client |   UDP Encrypted    | Server |
| Phone  |<==================>| VPS    |
+--------+    WireGuard       +--------+
     |         Tunnel              |
     |   10.66.66.2          10.66.66.1
     |                             |
     +-------- Internet -----------+
```

## State Machine

```text
                +-------------+
                |    IDLE     |
                +------+------+
                       |
                       | Handshake Init
                       v
                +------+------+
                | HANDSHAKE   |
                | (DH Key     |
                |  Exchange)  |
                +------+------+
                       |
          +------------+------------+
          |                         |
          v                         v
   +------+------+          +-------+-------+
   | ESTABLISHED |          | FAILED        |
   | (Tunnel Up) |          | (Timeout/     |
   +------+------+          |  Auth Error)  |
          |                 +---------------+
          |
          v
   +------+------+
   | DATA FLOW   |
   | (Encrypted) |
   +------+------+
          |
          | Keepalive every 25s
          v
   +------+------+
   | ACTIVE      |<----+
   +------+------+     | Persistent
          |            | Keepalive
          +------------+
```

## Installation

```bash
curl -sSL wg.dnscloak.net | sudo bash
```

## Network Layout

```text
Server: 10.66.66.1/24 (gateway)
User 1: 10.66.66.2/32
User 2: 10.66.66.3/32
User 3: 10.66.66.4/32
...
```

## User Management

Add user:
```bash
dnscloak add wg alice
```

Generates:
- Client keypair
- Preshared key (extra security)
- Assigns IP (10.66.66.x)
- Adds peer to server config
- Outputs client config + QR

## Client Configuration

Generated config for user:

```ini
[Interface]
PrivateKey = <client-private-key>
Address = 10.66.66.2/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = <server-public-key>
PresharedKey = <preshared-key>
Endpoint = <server-ip>:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

## Client Setup

### iOS

1. Install WireGuard from App Store
2. Add Tunnel > Create from QR code
3. Scan QR shown by `dnscloak links username`
4. Enable tunnel

### Android

1. Install WireGuard from Play Store
2. Add Tunnel > Scan QR
3. Scan QR code
4. Enable tunnel

### Windows/macOS/Linux

1. Download WireGuard from wireguard.com
2. Import tunnel > paste config or import file
3. Activate

## Server Configuration

Location: `/opt/dnscloak/wg/wg0.conf`

```ini
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = <server-private-key>
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
# alice
PublicKey = <alice-public-key>
PresharedKey = <preshared-key>
AllowedIPs = 10.66.66.2/32

[Peer]
# bob
PublicKey = <bob-public-key>
PresharedKey = <preshared-key>
AllowedIPs = 10.66.66.3/32
```

## Commands

```bash
# Check interface status
sudo wg show

# Restart WireGuard
sudo systemctl restart wg-quick@wg0

# View connected peers
sudo wg show wg0 latest-handshakes
```

## Port Configuration

Default: UDP 51820

To use different port:
```bash
# During installation, specify port
# Or edit /opt/dnscloak/wg/wg0.conf
ListenPort = 12345
```

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Handshake timeout | UDP blocked | Try different port or use Reality |
| No internet after connect | NAT not configured | Check PostUp iptables rules |
| Slow speeds | MTU issues | Lower MTU to 1280 in client config |
| Keeps disconnecting | No keepalive | Ensure PersistentKeepalive = 25 |

## Security Notes

- Private keys never leave device where generated
- Preshared keys add post-quantum resistance
- Server only stores public keys
- Each peer has unique keypair
