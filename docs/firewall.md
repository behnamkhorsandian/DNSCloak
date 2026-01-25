# Firewall Configuration Guide

DNSCloak auto-detects your cloud provider and configures firewall rules. This guide covers manual setup if needed.

## Required Ports

| Service | Port | Protocol | Notes |
|---------|------|----------|-------|
| Reality | 443 | TCP | Shared with V2Ray, WS |
| V2Ray | 443 | TCP | Shared with Reality, WS |
| WS+CDN | 443 | TCP | Shared with Reality, V2Ray |
| MTP | 443 | TCP | Can use different port |
| WireGuard | 51820 | UDP | Configurable |
| DNStt | 53 | UDP | Must be 53 |
| SSH | 22 | TCP | Keep open for access |

## Cloud Provider Setup

### AWS (EC2)

1. Go to EC2 Dashboard > Security Groups
2. Select your instance's security group
3. Edit inbound rules:

```text
Type        Protocol    Port    Source
SSH         TCP         22      Your IP or 0.0.0.0/0
HTTPS       TCP         443     0.0.0.0/0
Custom UDP  UDP         51820   0.0.0.0/0
DNS (UDP)   UDP         53      0.0.0.0/0
```

CLI method:
```bash
# Get security group ID
SG_ID=$(aws ec2 describe-instances --instance-id <id> \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

# Add rules
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol udp --port 51820 --cidr 0.0.0.0/0
```

### Google Cloud (GCP)

1. Go to VPC Network > Firewall
2. Create firewall rule:

```text
Name: allow-dnscloak
Direction: Ingress
Targets: All instances / Specific tags
Source: 0.0.0.0/0
Protocols: tcp:443, udp:51820, udp:53
```

CLI method:
```bash
gcloud compute firewall-rules create allow-dnscloak \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:443,udp:51820,udp:53 \
  --source-ranges=0.0.0.0/0
```

### Azure

1. Go to Virtual Machine > Networking
2. Add inbound port rules:

```text
Priority    Name            Port    Protocol
100         Allow-HTTPS     443     TCP
110         Allow-WG        51820   UDP
120         Allow-DNS       53      UDP
```

CLI method:
```bash
az network nsg rule create \
  --resource-group <rg> \
  --nsg-name <nsg> \
  --name allow-dnscloak \
  --priority 100 \
  --destination-port-ranges 443 51820 53 \
  --protocol '*' \
  --access Allow
```

### DigitalOcean

1. Go to Networking > Firewalls
2. Create or edit firewall:

```text
Inbound Rules:
TCP     443     All IPv4, All IPv6
UDP     51820   All IPv4, All IPv6
UDP     53      All IPv4, All IPv6
```

CLI method:
```bash
doctl compute firewall create \
  --name dnscloak \
  --inbound-rules "protocol:tcp,ports:443,address:0.0.0.0/0 \
                   protocol:udp,ports:51820,address:0.0.0.0/0 \
                   protocol:udp,ports:53,address:0.0.0.0/0"
```

### Vultr

1. Go to Products > Firewall
2. Add firewall group with rules:

```text
Protocol    Port        Source
TCP         443         0.0.0.0/0
UDP         51820       0.0.0.0/0
UDP         53          0.0.0.0/0
```

### Hetzner Cloud

1. Go to Firewalls
2. Create firewall with rules:

```bash
hcloud firewall create --name dnscloak
hcloud firewall add-rule dnscloak --direction in --protocol tcp --port 443 --source-ips 0.0.0.0/0
hcloud firewall add-rule dnscloak --direction in --protocol udp --port 51820 --source-ips 0.0.0.0/0
hcloud firewall add-rule dnscloak --direction in --protocol udp --port 53 --source-ips 0.0.0.0/0
```

### Oracle Cloud

1. Go to Networking > Virtual Cloud Networks > Security Lists
2. Add ingress rules:

```text
Stateless   Source        Protocol    Dest Port
No          0.0.0.0/0     TCP         443
No          0.0.0.0/0     UDP         51820
No          0.0.0.0/0     UDP         53
```

Note: Oracle also requires iptables rules on the VM:
```bash
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 51820 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 53 -j ACCEPT
sudo netfilter-persistent save
```

### Linode

1. Go to Linodes > [Your Linode] > Network > Firewall
2. Add inbound rules or use Cloud Firewall

## Fallback: Local Firewall (ufw/firewalld)

If no cloud firewall detected, DNSCloak uses local firewall:

### UFW (Ubuntu/Debian)
```bash
sudo ufw allow 443/tcp
sudo ufw allow 51820/udp
sudo ufw allow 53/udp
sudo ufw reload
```

### firewalld (CentOS/RHEL/Fedora)
```bash
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=51820/udp
sudo firewall-cmd --permanent --add-port=53/udp
sudo firewall-cmd --reload
```

### iptables (Direct)
```bash
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 51820 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT
```

## Verifying Firewall

Test if ports are open:

```bash
# From your local machine
nc -zv <server-ip> 443
nc -zuv <server-ip> 51820

# From the server itself
ss -tlnp | grep 443
ss -ulnp | grep 51820
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Connection timeout | Check cloud firewall rules exist |
| Connection refused | Service not running, check `dnscloak status` |
| Works locally, not remotely | Cloud firewall blocking, not local |
| Oracle Cloud specific | Remember to add iptables rules too |
