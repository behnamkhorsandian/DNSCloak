# Self-Hosting DNSCloak

Complete guide to hosting your own DNSCloak platform with custom domain.

## Overview

DNSCloak uses Cloudflare Workers to serve installation scripts from GitHub. When a user runs `curl -sSL reality.dnscloak.net | sudo bash`, the request goes to your Cloudflare Worker, which fetches the script from your GitHub repo.

```
User's VM                 Cloudflare Worker              GitHub
    |                           |                          |
    |  curl reality.domain.com  |                          |
    |-------------------------->|                          |
    |                           |  fetch install.sh        |
    |                           |------------------------->|
    |                           |<-------------------------|
    |  bash script              |                          |
    |<--------------------------|                          |
```

## Prerequisites

- Domain name (e.g., dnscloak.net)
- Cloudflare account (free tier works)
- GitHub account
- Node.js 18+ (for Wrangler CLI)

## Step 1: Fork the Repository

1. Go to https://github.com/behnamkhorsandian/DNSCloak
2. Click "Fork"
3. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/DNSCloak.git
   cd DNSCloak
   ```

## Step 2: Add Domain to Cloudflare

1. Log into Cloudflare Dashboard
2. Add Site > Enter your domain
3. Select Free plan
4. Update nameservers at your registrar to Cloudflare's
5. Wait for activation (usually 5-30 minutes)

## Step 3: Install Wrangler CLI

```bash
npm install -g wrangler
wrangler login
```

## Step 4: Create Workers

### Reality Worker

```bash
cd workers
mkdir -p reality/src
cd reality
```

Create `wrangler.toml`:
```toml
name = "dnscloak-reality"
main = "src/index.ts"
compatibility_date = "2024-01-01"

routes = [
  { pattern = "reality.yourdomain.com", custom_domain = true }
]
```

Create `src/index.ts`:
```typescript
const GITHUB_RAW = 'https://raw.githubusercontent.com/YOUR_USERNAME/DNSCloak/main';

export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    
    if (url.pathname === '/health') {
      return new Response('ok');
    }
    
    if (url.pathname === '/info') {
      return new Response(INFO_HTML, {
        headers: { 'Content-Type': 'text/html' },
      });
    }
    
    // Serve installation script
    const response = await fetch(`${GITHUB_RAW}/services/reality/install.sh`);
    if (!response.ok) {
      return new Response('Script not found', { status: 404 });
    }
    
    return new Response(await response.text(), {
      headers: { 'Content-Type': 'text/plain', 'Cache-Control': 'no-cache' },
    });
  },
};

const INFO_HTML = `<!DOCTYPE html>
<html>
<head><title>DNSCloak - Reality</title></head>
<body>
<h1>Reality Proxy</h1>
<pre>curl -sSL reality.yourdomain.com | sudo bash</pre>
</body>
</html>`;
```

Deploy:
```bash
wrangler deploy
```

### Repeat for Other Services

Create workers for each service:

| Service | Worker Name | Script Path |
|---------|-------------|-------------|
| reality | dnscloak-reality | services/reality/install.sh |
| wg | dnscloak-wg | services/wg/install.sh |
| mtp | dnscloak-mtp | services/mtp/install.sh |
| vray | dnscloak-vray | services/vray/install.sh |
| ws | dnscloak-ws | services/ws/install.sh |
| dnstt | dnscloak-dnstt | services/dnstt/install.sh |

## Step 5: Configure Custom Domains

After deploying each worker:

1. Go to Workers & Pages > Your Worker > Settings > Triggers
2. Click "Add Custom Domain"
3. Enter subdomain (e.g., `reality.yourdomain.com`)
4. Cloudflare auto-creates DNS record

Verify DNS records exist:
```
CNAME  reality  ->  dnscloak-reality.your-subdomain.workers.dev
CNAME  wg       ->  dnscloak-wg.your-subdomain.workers.dev
CNAME  mtp      ->  dnscloak-mtp.your-subdomain.workers.dev
...
```

## Step 6: Test Workers

```bash
# Should return installation script
curl -sSL reality.yourdomain.com

# Should return "ok"
curl reality.yourdomain.com/health

# Should return HTML info page
curl reality.yourdomain.com/info
```

## Step 7: Test on VM

1. Get a VPS (DigitalOcean, Vultr, Hetzner, etc.)
2. SSH in
3. Run:
   ```bash
   curl -sSL reality.yourdomain.com | sudo bash
   ```

## Directory Structure

Your workers folder should look like:
```
workers/
  reality/
    wrangler.toml
    src/index.ts
  wg/
    wrangler.toml
    src/index.ts
  mtp/
    wrangler.toml
    src/index.ts
  ...
```

## Updating Scripts

When you update scripts in `services/`:

1. Commit and push to GitHub
2. Workers automatically fetch latest version (no redeploy needed)

If you update worker code:
```bash
cd workers/reality
wrangler deploy
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| 404 on curl | Check GitHub raw URL is correct |
| Custom domain not working | Wait 5 min for DNS propagation |
| Worker shows old script | GitHub raw has 5-min cache, wait |
| SSL error | Ensure SSL mode is "Full" in Cloudflare |

## Optional: Single Worker for All Services

Instead of one worker per service, use one worker with path routing:

```typescript
export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const host = url.hostname.split('.')[0]; // reality, wg, mtp, etc.
    
    const scriptUrl = `${GITHUB_RAW}/services/${host}/install.sh`;
    // ... fetch and return
  },
};
```

Then use wildcard DNS:
```
CNAME  *  ->  dnscloak-main.workers.dev
```

## Security Considerations

- Workers are public - anyone can fetch scripts
- Scripts should not contain secrets
- Secrets are generated on the user's VM during installation
- Consider rate limiting if needed (Cloudflare dashboard)

## Cost

Cloudflare Workers free tier:
- 100,000 requests/day
- More than enough for most deployments

If you need more, Workers Paid is $5/month for 10 million requests.
