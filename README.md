# 🚀 TelegramProxy

A simple, one-command setup for **MTProto Proxy with Fake-TLS** support. Perfect for helping people in restricted regions access Telegram.

![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Linux-blue)

## ✨ Features

- 🔒 **Fake-TLS Support** - Traffic disguised as HTTPS to popular websites
- 🌐 **Domain Support** - Use your own domain for better reliability
- 👥 **Multi-User** - Create multiple proxy users with different secrets
- 📱 **Cross-Platform** - Works on iOS, Android, Desktop, and Web
- ☁️ **Cloud Agnostic** - Works with GCP, AWS, DigitalOcean, Vultr, etc.
- 🎯 **Interactive Setup** - Guided installation with clear instructions

## 🚀 Quick Start

SSH into your VPS and run:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/YOUR_USERNAME/TelegramProxy/main/setup.sh)
```

Or clone and run:

```bash
git clone https://github.com/YOUR_USERNAME/TelegramProxy.git
cd TelegramProxy
chmod +x setup.sh
./setup.sh
```

## 📋 Requirements

- Ubuntu 20.04+ or Debian 11+
- Root access or sudo privileges
- A VPS with public IP
- (Optional) A domain name

## 🔧 What It Does

1. Installs required dependencies
2. Sets up [mtprotoproxy](https://github.com/alexbers/mtprotoproxy) with Fake-TLS
3. Creates systemd service for auto-start
4. Generates secure proxy secrets
5. Provides ready-to-use proxy links
6. Guides you through firewall and DNS setup

## 📖 Post-Installation

After running the script, you'll need to:

1. **Open port 443** on your cloud provider's firewall
2. **Configure DNS** (optional) - Point your domain to your VPS IP
3. **Share the links** with your users

The script provides detailed instructions for each step!

## 🔄 Management

After installation, run the script again to:

- View proxy status and links
- Add/remove users
- Change settings
- Uninstall

## 📱 Client Setup

The script generates links in multiple formats:

- `tg://proxy?...` - Direct Telegram link
- `https://t.me/proxy?...` - Web link (shareable)

Works with:
- Telegram iOS/Android
- Telegram Desktop
- Telegram Web
- Third-party clients (Nekogram, Plus Messenger, etc.)

## ⚠️ Disclaimer

This tool is for educational purposes and to help people access information freely. Please use responsibly and in accordance with your local laws.

## 📜 License

MIT License - See [LICENSE](LICENSE) file

## 🙏 Credits

- [mtprotoproxy](https://github.com/alexbers/mtprotoproxy) by alexbers
- Inspired by [MTPulse](https://github.com/Erfan-XRay/MTPulse)

## 💬 Support

If you find this useful, please ⭐ star the repo!
