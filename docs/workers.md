# Cloudflare Workers Deployment

Each DNSCloak service has its own Cloudflare Worker that serves the installation script.

## Worker Architecture

```
User runs: curl -sSL reality.dnscloak.net | sudo bash
                         |
                         v
            Cloudflare Worker (reality)
                         |
                         v
    Fetches from GitHub: raw/.../services/reality/install.sh
                         |
                         v
            Returns script to user's terminal
```

## Subdomains

| Subdomain | Worker Name | Script Path |
|-----------|-------------|-------------|
| reality.dnscloak.net | dnscloak-reality | services/reality/install.sh |
| wg.dnscloak.net | dnscloak-wg | services/wg/install.sh |
| mtp.dnscloak.net | dnscloak-mtp | services/mtp/install.sh |
| vray.dnscloak.net | dnscloak-vray | services/vray/install.sh |
| ws.dnscloak.net | dnscloak-ws | services/ws/install.sh |
| dnstt.dnscloak.net | dnscloak-dnstt | services/dnstt/install.sh |

## Worker Endpoints

Each worker responds to:

| Path | Response |
|------|----------|
| `/` | Installation script (bash) |
| `/info` | HTML page with service info and client app links |
| `/health` | Health check (returns "ok") |

## Setup Steps

### 1. Prerequisites

- Cloudflare account with dnscloak.net domain
- Node.js 18+ installed locally
- Wrangler CLI: `npm install -g wrangler`

### 2. Authenticate Wrangler

```bash
wrangler login
```

### 3. Create Worker

For each service, create a worker directory:

```bash
cd workers
mkdir reality
cd reality
npm init -y
```

### 4. Worker Code Template

Create `src/index.ts`:

```typescript
const GITHUB_RAW = 'https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main';
const SERVICE = 'reality';

export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    
    // Health check
    if (url.pathname === '/health') {
      return new Response('ok', { status: 200 });
    }
    
    // Info page
    if (url.pathname === '/info') {
      return new Response(getInfoHTML(), {
        headers: { 'Content-Type': 'text/html' },
      });
    }
    
    // Serve installation script
    try {
      const scriptUrl = `${GITHUB_RAW}/services/${SERVICE}/install.sh`;
      const response = await fetch(scriptUrl);
      
      if (!response.ok) {
        return new Response('Script not found', { status: 404 });
      }
      
      const script = await response.text();
      return new Response(script, {
        headers: {
          'Content-Type': 'text/plain',
          'Cache-Control': 'no-cache',
        },
      });
    } catch (error) {
      return new Response('Error fetching script', { status: 500 });
    }
  },
};

function getInfoHTML(): string {
  return `<!DOCTYPE html>
<html>
<head>
  <title>DNSCloak - Reality</title>
  <style>
    body { font-family: system-ui; max-width: 600px; margin: 50px auto; padding: 20px; }
    code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; }
    pre { background: #1a1a1a; color: #fff; padding: 15px; border-radius: 5px; overflow-x: auto; }
    a { color: #0066cc; }
  </style>
</head>
<body>
  <h1>DNSCloak - Reality</h1>
  <p>VLESS + REALITY proxy. No domain required.</p>
  
  <h2>Install</h2>
  <pre>curl -sSL reality.dnscloak.net | sudo bash</pre>
  
  <h2>Client Apps</h2>
  <ul>
    <li><strong>iOS:</strong> <a href="https://apps.apple.com/app/hiddify-proxy-vpn/id6596777532">Hiddify</a>, <a href="https://apps.apple.com/app/shadowrocket/id932747118">Shadowrocket</a></li>
    <li><strong>Android:</strong> <a href="https://play.google.com/store/apps/details?id=app.hiddify.com">Hiddify</a>, <a href="https://play.google.com/store/apps/details?id=com.v2ray.ang">v2rayNG</a></li>
    <li><strong>Windows:</strong> <a href="https://github.com/hiddify/hiddify-next/releases">Hiddify</a>, <a href="https://github.com/2dust/v2rayN/releases">v2rayN</a></li>
    <li><strong>macOS:</strong> <a href="https://github.com/hiddify/hiddify-next/releases">Hiddify</a></li>
  </ul>
  
  <h2>Source</h2>
  <p><a href="https://github.com/behnamkhorsandian/DNSCloak">GitHub</a></p>
</body>
</html>`;
}
```

### 5. Wrangler Configuration

Create `wrangler.toml`:

```toml
name = "dnscloak-reality"
main = "src/index.ts"
compatibility_date = "2024-01-01"

routes = [
  { pattern = "reality.dnscloak.net", custom_domain = true }
]
```

### 6. Deploy

```bash
wrangler deploy
```

### 7. Custom Domain Setup

After first deploy:

1. Go to Cloudflare Dashboard > Workers & Pages
2. Select worker > Settings > Triggers
3. Add Custom Domain: `reality.dnscloak.net`
4. Cloudflare auto-creates DNS record

## Deploying All Workers

Script to deploy all workers:

```bash
#!/bin/bash
SERVICES="reality wg mtp vray ws dnstt"

for service in $SERVICES; do
  echo "Deploying $service..."
  cd workers/$service
  wrangler deploy
  cd ../..
done
```

## Environment Variables

For workers that need configuration:

```bash
wrangler secret put GITHUB_TOKEN
```

## Monitoring

View logs:
```bash
wrangler tail dnscloak-reality
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| 404 on script | Check GitHub raw URL is correct |
| Custom domain not working | Wait 5 min, check DNS in Cloudflare |
| CORS errors | Add appropriate headers in worker |
| Rate limited | GitHub raw has limits; consider caching |

## Caching Strategy

For production, add caching:

```typescript
const cache = caches.default;
const cacheKey = new Request(url.toString(), request);
let response = await cache.match(cacheKey);

if (!response) {
  response = await fetch(scriptUrl);
  response = new Response(response.body, response);
  response.headers.set('Cache-Control', 'max-age=300'); // 5 min
  await cache.put(cacheKey, response.clone());
}
```
