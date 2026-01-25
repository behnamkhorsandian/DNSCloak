/**
 * DNSCloak - Multi-Service Cloudflare Worker
 * 
 * Serves installation scripts for all DNSCloak services
 * Routes based on subdomain: reality.dnscloak.net, wg.dnscloak.net, etc.
 */

const GITHUB_RAW = 'https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main';

// Service configurations
interface ServiceConfig {
  name: string;
  description: string;
  script: string;
  clientApps: Record<string, string>;
}

const SERVICES: Record<string, ServiceConfig> = {
  mtp: {
    name: 'MTProto Proxy',
    description: 'Telegram proxy with Fake-TLS support',
    script: 'setup.sh', // Legacy path for MTP
    clientApps: {
      note: 'Built into Telegram - just click the link!',
    },
  },
  reality: {
    name: 'VLESS + REALITY',
    description: 'Advanced proxy with TLS camouflage. No domain needed.',
    script: 'services/reality/install.sh',
    clientApps: {
      ios: 'https://apps.apple.com/app/hiddify-proxy-vpn/id6596777532',
      android: 'https://play.google.com/store/apps/details?id=app.hiddify.com',
      windows: 'https://github.com/hiddify/hiddify-next/releases',
      macos: 'https://github.com/hiddify/hiddify-next/releases',
    },
  },
  wg: {
    name: 'WireGuard',
    description: 'Fast VPN tunnel with native app support.',
    script: 'services/wg/install.sh',
    clientApps: {
      ios: 'https://apps.apple.com/app/wireguard/id1441195209',
      android: 'https://play.google.com/store/apps/details?id=com.wireguard.android',
      windows: 'https://www.wireguard.com/install/',
      macos: 'https://apps.apple.com/app/wireguard/id1451685025',
    },
  },
  vray: {
    name: 'VLESS + TLS',
    description: 'Classic V2Ray setup. Requires domain with certificate.',
    script: 'services/vray/install.sh',
    clientApps: {
      ios: 'https://apps.apple.com/app/hiddify-proxy-vpn/id6596777532',
      android: 'https://play.google.com/store/apps/details?id=app.hiddify.com',
      windows: 'https://github.com/hiddify/hiddify-next/releases',
      macos: 'https://github.com/hiddify/hiddify-next/releases',
    },
  },
  ws: {
    name: 'VLESS + WebSocket + CDN',
    description: 'Route through Cloudflare CDN. Hides server IP.',
    script: 'services/ws/install.sh',
    clientApps: {
      ios: 'https://apps.apple.com/app/hiddify-proxy-vpn/id6596777532',
      android: 'https://play.google.com/store/apps/details?id=app.hiddify.com',
      windows: 'https://github.com/hiddify/hiddify-next/releases',
      macos: 'https://github.com/hiddify/hiddify-next/releases',
    },
  },
  dnstt: {
    name: 'DNS Tunnel',
    description: 'Emergency backup for total blackouts. Very slow.',
    script: 'services/dnstt/install.sh',
    clientApps: {
      note: 'Requires native client binary. See docs.',
      download: 'https://www.bamsoftware.com/software/dnstt/',
    },
  },
};

export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const hostname = url.hostname;
    
    // Extract service from subdomain (e.g., "reality" from "reality.dnscloak.net")
    const service = hostname.split('.')[0];
    
    // CORS headers
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    // Health check
    if (url.pathname === '/health') {
      return Response.json({
        status: 'ok',
        service: service,
        timestamp: Date.now(),
      }, { headers: corsHeaders });
    }

    // Get service config
    const config = SERVICES[service];
    if (!config) {
      return new Response(`Unknown service: ${service}`, { status: 404 });
    }

    // Info page (for browsers)
    if (url.pathname === '/info') {
      return new Response(getInfoPage(service, config), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'text/html; charset=utf-8',
        },
      });
    }

    // Version endpoint
    if (url.pathname === '/version') {
      return Response.json({
        service: service,
        name: config.name,
        repo: 'https://github.com/behnamkhorsandian/DNSCloak',
      }, { headers: corsHeaders });
    }

    // Default: serve installation script
    try {
      const scriptUrl = `${GITHUB_RAW}/${config.script}`;
      const response = await fetch(scriptUrl);
      
      if (!response.ok) {
        return new Response(`Script not found: ${config.script}`, { status: 404 });
      }
      
      return new Response(await response.text(), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'text/plain; charset=utf-8',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
        },
      });
    } catch (error) {
      return new Response('Error fetching script', { status: 502 });
    }
  },
};

function getInfoPage(service: string, config: ServiceConfig): string {
  const appLinks = Object.entries(config.clientApps)
    .map(([platform, url]) => {
      if (platform === 'note') {
        return `<li><em>${url}</em></li>`;
      }
      return `<li><strong>${platform}:</strong> <a href="${url}" target="_blank">${url}</a></li>`;
    })
    .join('\n');

  return `<!DOCTYPE html>
<html>
<head>
  <title>DNSCloak - ${config.name}</title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      color: #eee;
      min-height: 100vh;
      margin: 0;
      padding: 20px;
    }
    .container {
      max-width: 700px;
      margin: 0 auto;
      padding: 40px 20px;
    }
    h1 {
      color: #00d4ff;
      margin-bottom: 10px;
    }
    .description {
      color: #aaa;
      font-size: 1.1em;
      margin-bottom: 30px;
    }
    .install-box {
      background: #0d1117;
      border: 1px solid #30363d;
      border-radius: 8px;
      padding: 20px;
      margin: 20px 0;
    }
    .install-box h2 {
      margin-top: 0;
      color: #58a6ff;
    }
    code {
      background: #161b22;
      padding: 15px 20px;
      border-radius: 6px;
      display: block;
      font-family: 'SF Mono', Monaco, monospace;
      font-size: 14px;
      color: #7ee787;
      overflow-x: auto;
    }
    .apps {
      margin-top: 30px;
    }
    .apps h2 {
      color: #58a6ff;
    }
    .apps ul {
      list-style: none;
      padding: 0;
    }
    .apps li {
      padding: 8px 0;
      border-bottom: 1px solid #30363d;
    }
    .apps a {
      color: #58a6ff;
      text-decoration: none;
    }
    .apps a:hover {
      text-decoration: underline;
    }
    .footer {
      margin-top: 40px;
      padding-top: 20px;
      border-top: 1px solid #30363d;
      color: #666;
      font-size: 14px;
    }
    .footer a {
      color: #58a6ff;
    }
    .services {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin: 20px 0;
    }
    .services a {
      background: #21262d;
      color: #c9d1d9;
      padding: 8px 16px;
      border-radius: 6px;
      text-decoration: none;
      font-size: 14px;
    }
    .services a:hover {
      background: #30363d;
    }
    .services a.active {
      background: #238636;
      color: #fff;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>DNSCloak - ${config.name}</h1>
    <p class="description">${config.description}</p>
    
    <div class="services">
      <a href="https://reality.dnscloak.net/info" ${service === 'reality' ? 'class="active"' : ''}>Reality</a>
      <a href="https://wg.dnscloak.net/info" ${service === 'wg' ? 'class="active"' : ''}>WireGuard</a>
      <a href="https://mtp.dnscloak.net/info" ${service === 'mtp' ? 'class="active"' : ''}>MTProto</a>
      <a href="https://vray.dnscloak.net/info" ${service === 'vray' ? 'class="active"' : ''}>V2Ray</a>
      <a href="https://ws.dnscloak.net/info" ${service === 'ws' ? 'class="active"' : ''}>WS+CDN</a>
      <a href="https://dnstt.dnscloak.net/info" ${service === 'dnstt' ? 'class="active"' : ''}>DNStt</a>
    </div>
    
    <div class="install-box">
      <h2>Install on your VPS</h2>
      <code>curl -sSL ${service}.dnscloak.net | sudo bash</code>
    </div>
    
    <div class="apps">
      <h2>Client Apps</h2>
      <ul>
        ${appLinks}
      </ul>
    </div>
    
    <div class="footer">
      <p>
        <a href="https://github.com/behnamkhorsandian/DNSCloak">GitHub</a> |
        <a href="https://github.com/behnamkhorsandian/DNSCloak/blob/main/docs/protocols/${service}.md">Documentation</a>
      </p>
    </div>
  </div>
</body>
</html>`;
}
