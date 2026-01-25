# DNS Configuration Guide

Some DNSCloak services require domain configuration. This guide covers setup for each service type.

## Services by DNS Requirement

| Service | Domain Required | DNS Type | Cloudflare Proxy |
|---------|-----------------|----------|------------------|
| Reality | No | - | - |
| WireGuard | No | - | - |
| MTP | Optional | A record | Gray cloud (DNS only) |
| V2Ray | Yes | A record | Gray cloud (DNS only) |
| WS+CDN | Yes | A record | Orange cloud (Proxied) |
| DNStt | Yes | A + NS records | Not supported |

## Cloudflare Setup

### Basic A Record (MTP, V2Ray)

1. Log into Cloudflare Dashboard
2. Select your domain
3. Go to DNS > Records
4. Add record:

```text
Type: A
Name: proxy (or your subdomain)
IPv4: <your-server-ip>
Proxy: DNS only (gray cloud)
TTL: Auto
```

Result: `proxy.yourdomain.com` points directly to your server.

### CDN-Proxied Record (WS+CDN)

1. Same steps as above, but:

```text
Type: A
Name: ws (or your subdomain)
IPv4: <your-server-ip>
Proxy: Proxied (orange cloud)   <-- Important!
TTL: Auto
```

2. Go to SSL/TLS > Overview
3. Set mode to "Full" or "Full (Strict)"

4. Go to Network
5. Enable WebSockets

Result: Traffic goes through Cloudflare CDN, hiding your server IP.

### API Token for Automation

DNSCloak can auto-configure Cloudflare if you provide an API token:

1. Go to My Profile > API Tokens
2. Create Token > Edit zone DNS template
3. Permissions:
   - Zone > DNS > Edit
4. Zone Resources:
   - Include > Specific zone > yourdomain.com
5. Create and copy token

Use during installation when prompted, or set:
```bash
export CF_API_TOKEN="your-token-here"
```

## DNStt NS Record Setup

DNStt requires special NS (nameserver) records to route DNS queries to your server.

### Step 1: Create A Record for Nameserver

```text
Type: A
Name: ns1
IPv4: <your-server-ip>
Proxy: DNS only (gray cloud)
TTL: Auto
```

Result: `ns1.yourdomain.com` = your server IP

### Step 2: Create NS Record for Tunnel Subdomain

```text
Type: NS
Name: t (tunnel subdomain)
Nameserver: ns1.yourdomain.com
TTL: Auto
```

Result: All DNS queries for `*.t.yourdomain.com` go to your server.

### Step 3: Verify

```bash
# Should return your server IP
dig ns1.yourdomain.com

# Should show ns1.yourdomain.com as nameserver
dig NS t.yourdomain.com

# Should reach your dnstt server (after installation)
dig test.t.yourdomain.com
```

### DNStt DNS Diagram

```text
Client                    ISP DNS           Authoritative       Your Server
  |                          |              (Cloudflare)            |
  |--dig x.t.example.com---->|                   |                  |
  |                          |--NS query-------->|                  |
  |                          |<--ns1.example.com-|                  |
  |                          |                   |                  |
  |                          |--query to ns1-----|----------------->|
  |                          |<--response--------|------------------|
  |<--response---------------|                   |                  |
```

## Other DNS Providers

### Namecheap

1. Domain List > Manage > Advanced DNS
2. Add A Record:
   - Host: proxy
   - Value: <server-ip>
   - TTL: Automatic

### Google Domains

1. DNS > Manage custom records
2. Create new record:
   - Host name: proxy
   - Type: A
   - TTL: 3600
   - Data: <server-ip>

### Route 53 (AWS)

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "proxy.yourdomain.com",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "<server-ip>"}]
      }
    }]
  }'
```

## Verifying DNS

```bash
# Check A record
dig +short proxy.yourdomain.com

# Check NS record (for DNStt)
dig +short NS t.yourdomain.com

# Check propagation worldwide
# Visit: https://dnschecker.org
```

## DNS Propagation

Changes take time to propagate:
- Cloudflare: Usually immediate to 5 minutes
- Other providers: Up to 48 hours (usually 1-4 hours)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| DNS not resolving | Wait for propagation, check record exists |
| Wrong IP returned | Clear local DNS cache: `sudo systemd-resolve --flush-caches` |
| Cloudflare orange cloud issues | Some services need gray cloud (DNS only) |
| DNStt not working | Verify NS record points to A record, not IP directly |
