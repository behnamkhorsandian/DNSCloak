# DNSCloak

**MTProto Proxy with Fake-TLS & Secure Mode** support. Perfect for helping people in restricted regions access Telegram.

![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Linux-blue)
![Version](https://img.shields.io/badge/version-1.1.0-blue)

##  Features

- **Fake-TLS Support (ee)** - Traffic disguised as HTTPS to popular websites (bypasses DPI)
- **Secure Mode with Random Padding (dd)** - Adds random padding for extra obfuscation
- **Domain Support** - Use your own domain for better reliability
- **Multi-User** - Create multiple proxy users with different secrets
- **Port & Firewall Analysis** - Check open ports, processes, and firewall status
- **Cross-Platform** - Works on iOS, Android, Desktop, and Web
- **Cloud Agnostic** - Works with GCP, AWS, DigitalOcean, Vultr, etc.
- **Interactive Setup** - Guided installation with clear instructions

---

## Secret Prefixes Explained

| Prefix | Mode | Description |
|--------|------|-------------|
| `ee` | Fake-TLS | Traffic looks like HTTPS. Format: `ee` + `32-char-secret` + `domain-as-hex` |
| `dd` | Secure | Random padding added. Format: `dd` + `32-char-secret` |
| none | Classic | Basic MTProto (easily detectable, not recommended) |

### Example Secrets

```
# Fake-TLS (ee) - Correct format:
ee7f45a9c40d648d9709c7fa40f27ad97777772e676f6f676c652e636f6d
   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   |                                 |
   32-char hex secret               "www.google.com" in hex

# Secure (dd) - Correct format:
dd7f45a9c40d648d9709c7fa40f27ad9
   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   |
   32-char hex secret
```

⚠️ **Common Mistake**: If your ee-prefixed secret doesn't include the domain hex at the end, the proxy won't work!

---

## Quick Start

SSH into your VPS and run:

```bash
curl -Ls https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main/setup.sh | sudo bash
```

Or clone and run:

```bash
git clone https://github.com/behnamkhorsandian/DNSCloak.git
cd DNSCloak
chmod +x setup.sh
sudo ./setup.sh
```

---

## Requirements

- Ubuntu 20.04+ or Debian 11+
- Root access or sudo privileges
- A VPS with public IP (GCP, AWS, DigitalOcean, Vultr, etc.)
- (Optional) A domain name with Cloudflare or any DNS provider

---

## Complete Walkthrough

### Step 1: Create a VPS

Create a VM instance on any cloud provider. Recommended specs:
- **OS**: Ubuntu 22.04 or Debian 12
- **RAM**: 512MB+ (even the smallest instance works)
- **Region**: Choose a location not blocked in your target region

### Step 2: Run the Setup Script

SSH into your VPS and run:

```bash
curl -Ls https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main/setup.sh | sudo bash
```

The script will:
1. Install dependencies (Python3, git, etc.)
2. Download [mtprotoproxy](https://github.com/alexbers/mtprotoproxy)
3. Create configuration with your settings
4. Set up systemd service for auto-start
5. Generate proxy links

### Step 3: Open Firewall Port

**⚠️ IMPORTANT: The proxy won't work until you open port 443!**

#### Google Cloud Platform (GCP)

1. Go to: https://console.cloud.google.com/networking/firewalls/add
2. Configure:
   | Setting | Value |
   |---------|-------|
   | Name | `allow-telegram-proxy` |
   | Network | `default` |
   | Direction | `Ingress` |
   | Targets | `All instances in the network` |
   | Source IP ranges | `0.0.0.0/0` |
   | Protocols and ports | ✅ TCP: `443` |
3. Click **CREATE**

#### Amazon Web Services (AWS)

1. Go to: EC2 Dashboard → Security Groups
2. Select your instance's security group
3. Click **Edit inbound rules**
4. Add rule:
   - Type: `Custom TCP`
   - Port range: `443`
   - Source: `0.0.0.0/0`
5. Click **Save rules**

#### DigitalOcean

1. Go to: Networking → Firewalls
2. Create or edit firewall
3. Add inbound rule: TCP port `443` from All IPv4
4. Apply to your droplet

#### Vultr

1. Go to: Products → Firewall
2. Create or select firewall group
3. Add rule: TCP, Port `443`, Source: anywhere
4. Link firewall to your instance

#### Other Providers

Look for Security Groups, Firewall Rules, or Network Security settings and allow **TCP port 443** from `0.0.0.0/0`.

### Step 4: Configure DNS (Optional but Recommended)

Using a domain makes your proxy harder to block. If your IP gets blocked, you can simply change the DNS record to a new server.

#### Cloudflare Setup

1. Go to your domain's **DNS settings**
2. Add a new record:
   | Setting | Value |
   |---------|-------|
   | Type | `A` |
   | Name | `tg` (or any subdomain) |
   | IPv4 | Your server IP (e.g., `203.0.113.50`) |
   | Proxy status | **DNS only** (gray cloud) ⬅️ **IMPORTANT!** |

3. Click the **orange cloud** to turn it **gray**

> **Why DNS only?** Cloudflare's proxy only supports HTTP/HTTPS. MTProto is a different protocol that needs a direct connection. If you leave the orange cloud enabled, the proxy will NOT work!

### Step 5: Get Your Proxy Links

After setup, the script shows your links. You can also check them anytime:

```bash
sudo systemctl status telegram-proxy
```

Or run the script again and select "View Proxy Links".

**Example links:**
```
tg://proxy?server=YOUR_IP&port=443&secret=eeXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX7777772e676f6f676c652e636f6d
```

> **Note**: The longest secret (starting with `eeee...` and ending with hex-encoded domain) is the **Fake-TLS** version. This is the most secure option that disguises traffic as regular HTTPS.

---

## How to Use the Proxy

### Telegram Mobile (iOS/Android)

**Method 1 - Click the link:**
1. Open the `tg://proxy?...` link in a browser
2. Telegram will open and ask to add the proxy
3. Tap **"Connect Proxy"**

**Method 2 - Manual setup:**
1. Go to Settings → Data and Storage → Proxy
2. Tap "Add Proxy" → Select "MTProto"
3. Enter server, port, and secret

### Telegram Desktop

**Method 1 - Click the link:**
1. Open the `tg://proxy?...` link
2. Telegram will prompt to enable proxy

**Method 2 - Manual setup:**
1. Go to Settings → Advanced → Connection type
2. Add Proxy → MTProto
3. Enter server, port, and secret

### Telegram Web

1. Open the `https://t.me/proxy?...` link
2. Click **"Enable Proxy"**

### Third-Party Clients

Works with: Nekogram, Plus Messenger, Telegram X, etc.
Use the same links or manual configuration.

---

## Management Commands

```bash
# Check status
sudo systemctl status telegram-proxy

# View logs
sudo journalctl -u telegram-proxy -n 50

# Restart proxy
sudo systemctl restart telegram-proxy

# Stop proxy
sudo systemctl stop telegram-proxy

# Start proxy
sudo systemctl start telegram-proxy
```

Or run the script again for an interactive menu:
```bash
sudo ./setup.sh
```

---

## Troubleshooting

### Proxy not connecting?

1. **Check if service is running:**
   ```bash
   sudo systemctl status telegram-proxy
   ```

2. **Check if port is open on the server:**
   ```bash
   ss -tlnp | grep 443
   ```

3. **Check cloud firewall:** Make sure you've created the firewall rule to allow TCP 443

4. **Check Cloudflare proxy:** If using a domain, make sure the cloud is **GRAY** (DNS only), not orange

### Service won't start?

Check the logs:
```bash
sudo journalctl -u telegram-proxy -n 50
```

### "Permission denied" errors?

Make sure you're running with `sudo`:
```bash
sudo ./setup.sh
```

---

## 🛡️ Security Notes

- **Fake-TLS** makes your traffic look like HTTPS to a legitimate website (e.g., google.com)
- The `ee` prefix in secrets enables Fake-TLS mode
- Each user gets a unique secret - you can revoke access by removing a user
- Use a domain so you can quickly switch servers if your IP gets blocked

---

## 🔄 For Contributors / Self-Hosting

### CI/CD Setup

This repo uses GitHub Actions for CI/CD. To set up auto-deployment to your own VM:

1. **Fork this repository**

2. **Add GitHub Secrets** (Settings → Secrets → Actions):
   | Secret | Description |
   |--------|-------------|
   | `VM_HOST` | Your VM's IP address |
   | `VM_USER` | SSH username |
   | `VM_SSH_KEY` | SSH private key (see `.env.example` for guide) |
   | `VM_SSH_PORT` | SSH port (optional, default: 22) |

3. **Deploy with tags**:
   ```bash
   # Create and push a deploy tag
   git tag v1.0.1-lit
   git push origin v1.0.1-lit
   ```

   Tags ending with `-lit` trigger deployment to your VM.

See [.env.example](.env.example) for detailed setup instructions.

---

## ⚠️ Disclaimer

This tool is for educational purposes and to help people access information freely. Please use responsibly and in accordance with your local laws.

---

## 📜 License

MIT License - See [LICENSE](LICENSE) file

---

## 🙏 Credits

- [mtprotoproxy](https://github.com/alexbers/mtprotoproxy) by alexbers
- Inspired by [MTPulse](https://github.com/Erfan-XRay/MTPulse)

---

## 💬 Support

- 🌐 Website: [dnscloak.net](https://dnscloak.net)
- ⭐ Star this repo if you find it useful!
- 🐛 Report issues on [GitHub Issues](https://github.com/behnamkhorsandian/DNSCloak/issues)
