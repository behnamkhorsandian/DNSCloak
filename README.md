# DNSCloak

MTProto Proxy with **Fake-TLS** support. Helps people in restricted regions access Telegram.

## How It Works

Your traffic is disguised as HTTPS to a legitimate website (e.g., google.com), bypassing deep packet inspection (DPI).

| Secret Prefix | Mode | Description |
|---------------|------|-------------|
| `ee` | Fake-TLS | Looks like HTTPS traffic. Most secure. |
| `dd` | Secure | Random padding added. Backup option. |

---

## Quick Install

SSH into your VPS and run:

```bash
curl -sSL mtp.dnscloak.net | sudo bash
```

The script asks for:
- **Port** (default: 443)
- **Domain** (optional, for easier IP changes)
- **Fake-TLS domain** (default: google.com)
- **Username**

Then shows your proxy link immediately.

---

## Setup Checklist

### 1. Create a VPS

Any cloud provider works (GCP, AWS, DigitalOcean, Vultr, etc.)
- **OS**: Ubuntu 20.04+ or Debian 11+
- **RAM**: 512MB minimum (1GB recommended)

### 2. Run the Script

```bash
curl -sSL mtp.dnscloak.net | sudo bash
```

### 3. Open Firewall Port ⚠️

**Required!** Open TCP port 443 in your cloud provider's firewall:

| Provider | Where to Configure |
|----------|-------------------|
| **GCP** | VPC Network → Firewall → Create rule → TCP 443, Source: 0.0.0.0/0 |
| **AWS** | EC2 → Security Groups → Inbound rules → TCP 443 |
| **DigitalOcean** | Networking → Firewalls → TCP 443 |
| **Vultr** | Firewall → Add rule → TCP 443 |

### 4. DNS Setup (Optional)

Using a domain makes your proxy harder to block. If your IP gets blocked, just update the DNS to a new server.

**Cloudflare:**
1. Add A record: `tg` → Your server IP
2. **Important:** Set proxy to "DNS only" (gray cloud, not orange)

> MTProto needs direct connection. Cloudflare's orange cloud proxy won't work.

---

## Using the Proxy

**Mobile (iOS/Android):** Click the `tg://proxy?...` link → Telegram opens → Tap "Connect"

**Desktop:** Click the link, or: Settings → Advanced → Connection → Add MTProto Proxy

**Manual setup:** Server + Port + Secret (the full string starting with `ee...`)

---

## Management

Run the script again for the menu:

```bash
curl -sSL mtp.dnscloak.net | sudo bash
```

**Menu options:**
1. **Proxy Links & Users** - View links, add users
2. **Status & Restart** - Check/restart service
3. **View Logs** - Debug issues
4. **Update IP** - After VM IP change
5. **Uninstall**

**Quick commands:**
```bash
sudo systemctl status telegram-proxy   # Status
sudo journalctl -u telegram-proxy -f   # Logs
sudo systemctl restart telegram-proxy  # Restart
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Telegram shows "unavailable" | Check firewall port is open |
| Works then stops | Check if VM IP changed (use Update IP option) |
| Using Cloudflare domain | Make sure cloud is **gray** (DNS only) |
| Service not running | Run `sudo journalctl -u telegram-proxy -n 50` |

---

## License

MIT - See [LICENSE](LICENSE)

## Credits

[mtprotoproxy](https://github.com/alexbers/mtprotoproxy) by alexbers
