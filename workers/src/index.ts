/**
 * Vany - Unified Cloudflare Worker
 *
 * Path-based routing (primary):
 *   curl vany.sh            -> Static landing page (logo + endpoints)
 *   curl vany.sh | sudo bash -> Thin TUI client (via /tui/client)
 *   curl vany.sh/reality    -> start.sh with VANY_PROTOCOL="reality"
 *   curl vany.sh/tui/*      -> Server-rendered ANSI TUI pages
 *   curl vany.sh/dnstt/setup/linux -> DNSTT client setup script
 *
 * Subdomain routing (backward compat):
 *   curl reality.vany.sh    -> same as vany.sh/reality
 */

import { handleTuiRequest } from './tui/index.js';
import { pageLandingBash } from './tui/pages/landing.js';
import { handleBoxCreate, handleBoxFetch, handleBoxPage } from './safebox.js';

const GITHUB_RAW = 'https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main';

interface Env {
  SAFEBOX: KVNamespace;
}

// Service configurations
interface ServiceConfig {
  name: string;
  description: string;
  clientApps: Record<string, string>;
}

const SERVICES: Record<string, ServiceConfig> = {
  mtp: {
    name: 'MTProto Proxy',
    description: 'Telegram proxy with Fake-TLS support',
    clientApps: {
      note: 'Built into Telegram - just click the link!',
    },
  },
  reality: {
    name: 'VLESS + REALITY',
    description: 'Advanced proxy with TLS camouflage. No domain needed.',
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
    clientApps: {
      note: 'Requires native client binary.',
      setup: 'https://vany.sh/dnstt/client',
    },
  },
  conduit: {
    name: 'Conduit (Psiphon Relay)',
    description: 'Volunteer relay node for Psiphon network. Help users in censored regions.',
    clientApps: {
      note: 'No client needed. Users connect via Psiphon apps.',
      psiphon: 'https://psiphon.ca/download.html',
    },
  },
  hysteria: {
    name: 'Hysteria v2',
    description: 'QUIC-based proxy. Fastest on lossy/throttled networks.',
    clientApps: {
      ios: 'https://apps.apple.com/app/hiddify-proxy-vpn/id6596777532',
      android: 'https://play.google.com/store/apps/details?id=app.hiddify.com',
      windows: 'https://github.com/hiddify/hiddify-next/releases',
      macos: 'https://github.com/hiddify/hiddify-next/releases',
    },
  },
  'http-obfs': {
    name: 'HTTP Obfuscation',
    description: 'CDN host header spoofing. Hides behind popular domains.',
    clientApps: {
      ios: 'https://apps.apple.com/app/hiddify-proxy-vpn/id6596777532',
      android: 'https://play.google.com/store/apps/details?id=app.hiddify.com',
      windows: 'https://github.com/hiddify/hiddify-next/releases',
      macos: 'https://github.com/hiddify/hiddify-next/releases',
    },
  },
  'ssh-tunnel': {
    name: 'SSH Tunnel',
    description: 'Basic SOCKS5 proxy over SSH. Universal fallback.',
    clientApps: {
      note: 'Built-in: ssh -D 1080 user@server',
    },
  },
  slipstream: {
    name: 'Slipstream',
    description: 'Enhanced DNS tunnel with QUIC+TLS. ~63 KB/s.',
    clientApps: {
      note: 'Requires slipstream client binary.',
    },
  },
  noizdns: {
    name: 'NoizDNS',
    description: 'DPI-resistant DNSTT fork with noise and padding.',
    clientApps: {
      note: 'Requires noizdns client binary.',
    },
  },
  'tor-bridge': {
    name: 'Tor Bridge (obfs4)',
    description: 'obfs4 pluggable transport bridge for the Tor network.',
    clientApps: {
      note: 'Tor users connect via BridgeDB. No manual setup.',
      tor: 'https://www.torproject.org/download/',
    },
  },
  snowflake: {
    name: 'Snowflake Proxy',
    description: 'WebRTC Tor relay. Zero config, minimal resources.',
    clientApps: {
      note: 'Tor users connect automatically.',
      tor: 'https://www.torproject.org/download/',
    },
  },
  sos: {
    name: 'SafeBox',
    description: 'Encrypted dead-drop with emoji access. 24h TTL.',
    clientApps: {
      browser: 'https://vany.sh/box',
      cli: 'curl vany.sh/box',
    },
  },
};

/**
 * Fetch start.sh from GitHub and optionally prepend VANY_PROTOCOL env var.
 */
async function serveStartScript(protocol?: string): Promise<Response> {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };

  try {
    const scriptUrl = `${GITHUB_RAW}/start.sh`;
    const response = await fetch(scriptUrl);

    if (!response.ok) {
      return new Response('Script not found', { status: 404 });
    }

    let script = await response.text();

    // For per-protocol shortcuts, prepend export so start.sh auto-selects the protocol
    if (protocol) {
      script = `export VANY_PROTOCOL="${protocol}"\n${script}`;
    }

    return new Response(script, {
      headers: {
        ...corsHeaders,
        'Content-Type': 'text/plain; charset=utf-8',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
      },
    });
  } catch {
    return new Response('Error fetching script', { status: 502 });
  }
}

/**
 * Fetch direct-install.sh from GitHub with VANY_PROTOCOL prepended.
 * Standalone installer/manager for a single protocol — bypasses the full TUI.
 */
async function serveDirectInstaller(protocol: string): Promise<Response> {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };

  try {
    const scriptUrl = `${GITHUB_RAW}/scripts/direct-install.sh`;
    const response = await fetch(scriptUrl);

    if (!response.ok) {
      return new Response('Installer not found', { status: 404 });
    }

    let script = await response.text();
    script = `export VANY_PROTOCOL="${protocol}"\n${script}`;

    return new Response(script, {
      headers: {
        ...corsHeaders,
        'Content-Type': 'text/plain; charset=utf-8',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
      },
    });
  } catch {
    return new Response('Error fetching installer', { status: 502 });
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const hostname = url.hostname;

    // www subdomain: proxy to Cloudflare Pages
    if (hostname === 'www.vany.sh') {
      const pagesUrl = new URL(request.url);
      pagesUrl.hostname = 'vany-agg.pages.dev';
      return fetch(new Request(pagesUrl, request));
    }

    // Root domain: path-based protocol routing
    // curl vany.sh/reality | sudo bash  →  start.sh with VANY_PROTOCOL="reality"
    // curl vany.sh | sudo bash          →  start.sh (interactive menu)
    if (hostname === 'vany.sh') {
      const corsHeaders = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
      };

      if (request.method === 'OPTIONS') {
        return new Response(null, { headers: corsHeaders });
      }

      if (url.pathname === '/health') {
        return Response.json({ status: 'ok', timestamp: Date.now() }, { headers: corsHeaders });
      }

      // Alternative access mirrors for restricted networks
      if (url.pathname === '/mirrors') {
        const mirrors = {
          primary: 'https://vany.sh',
          alternatives: [
            { name: 'GitHub Raw', url: 'https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/start.sh', usage: 'curl -sL <url> | sudo bash' },
            { name: 'Cloudflare Pages', url: 'https://vany-agg.pages.dev', usage: 'Visit in browser' },
          ],
          bootstrap: 'If all HTTPS access is blocked, use Cloudflare WARP (1.1.1.1 app) first, then curl vany.sh',
          offline: 'Ask someone to send you the start.sh file directly — it works offline after first download',
        };
        return Response.json(mirrors, { headers: corsHeaders });
      }

      // TUI routes: /tui/*
      if (url.pathname.startsWith('/tui/') || url.pathname === '/tui') {
        const tuiResponse = await handleTuiRequest(request, env, url.pathname, url);
        if (tuiResponse) return tuiResponse;
      }

      // SafeBox routes: /box, /box/:id
      if (url.pathname === '/box' || url.pathname.startsWith('/box/')) {
        if (request.method === 'OPTIONS') {
          return new Response(null, { headers: corsHeaders });
        }
        const boxSegments = url.pathname.slice(1).split('/').filter(Boolean); // ["box", ...rest]
        if (boxSegments.length === 1 && request.method === 'POST') {
          return handleBoxCreate(request, env.SAFEBOX);
        }
        if (boxSegments.length === 1 && request.method === 'GET') {
          const ua = (request.headers.get('User-Agent') || '').toLowerCase();
          const isCli = ua.includes('curl') || ua.includes('wget') || ua.includes('fetch');
          return handleBoxPage(isCli);
        }
        if (boxSegments.length === 2 && request.method === 'GET') {
          return handleBoxFetch(boxSegments[1], env.SAFEBOX);
        }
        return new Response('Not found', { status: 404 });
      }

      // WS+CDN Quick Connect: /ws/connect → ephemeral VLESS+WS link
      if (url.pathname === '/ws/connect') {
        const corsJson = { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' };
        if (request.method === 'OPTIONS') {
          return new Response(null, { headers: corsJson });
        }
        // Try to get active config from KV
        const raw = await env.SAFEBOX.get('ws:quickconnect');
        if (raw) {
          try {
            const cfg = JSON.parse(raw);
            return Response.json(cfg, { headers: corsJson });
          } catch { /* fall through */ }
        }
        return Response.json({
          link: null,
          message: 'Service is starting up. Check back soon.',
        }, { headers: corsJson });
      }

      // Scripts proxy: /scripts/* → GitHub raw (for bootstrap + protocol scripts)
      if (url.pathname.startsWith('/scripts/')) {
        const scriptPath = url.pathname.slice(1); // "scripts/docker-bootstrap.sh"
        const scriptUrl = `${GITHUB_RAW}/${scriptPath}`;
        try {
          const resp = await fetch(scriptUrl);
          if (!resp.ok) return new Response('Script not found', { status: 404 });
          return new Response(resp.body, {
            headers: {
              ...corsHeaders,
              'Content-Type': 'text/plain; charset=utf-8',
              'Cache-Control': 'no-cache, no-store, must-revalidate',
            },
          });
        } catch {
          return new Response('Error fetching script', { status: 502 });
        }
      }

      const segments = url.pathname.slice(1).split('/').filter(Boolean);
      const firstSegment = segments[0] || '';
      const config = SERVICES[firstSegment];

      // DNSTT special sub-routes: vany.sh/dnstt/client, vany.sh/dnstt/setup/<platform>
      if (firstSegment === 'dnstt' && segments.length > 1) {
        if (segments[1] === 'client') {
          return new Response(getDnsttClientPage(
            url.searchParams.get('key') || '',
            url.searchParams.get('domain') || 't.example.com',
          ), { headers: { ...corsHeaders, 'Content-Type': 'text/html; charset=utf-8' } });
        }
        if (segments[1] === 'setup' && segments[2]) {
          const pubkey = url.searchParams.get('key') || '';
          const domain = url.searchParams.get('domain') || '';
          if (!pubkey || !domain) {
            return new Response('Missing key or domain parameter', { status: 400 });
          }
          const script = getDnsttSetupScript(segments[2], pubkey, domain);
          return script
            ? new Response(script, { headers: { ...corsHeaders, 'Content-Type': 'text/plain; charset=utf-8' } })
            : new Response('Unknown platform', { status: 404 });
        }
      }

      // Protocol info/version pages: vany.sh/reality/info
      if (config && segments[1] === 'info') {
        return new Response(getInfoPage(firstSegment, config), {
          headers: { ...corsHeaders, 'Content-Type': 'text/html; charset=utf-8' },
        });
      }
      if (config && segments[1] === 'version') {
        return Response.json({
          service: firstSegment, name: config.name,
          repo: 'https://github.com/behnamkhorsandian/Vanysh',
        }, { headers: corsHeaders });
      }

      // CLI tools: serve thin TUI client or protocol-specific start.sh
      const ua = (request.headers.get('User-Agent') || '').toLowerCase();
      const isCli = ua.includes('curl') || ua.includes('wget') || ua.includes('fetch');
      if (isCli) {
        // Root path: polyglot — catalog for curl, full TUI for sudo bash
        if (!firstSegment) {
          return new Response(pageLandingBash(), {
            headers: {
              ...corsHeaders,
              'Content-Type': 'text/plain; charset=utf-8',
              'Cache-Control': 'no-cache',
            },
          });
        }
        // Tools: vany.sh/tools/cfray | bash → serve tool script from GitHub
        if (firstSegment === 'tools' && segments[1]) {
          const toolScript = `${GITHUB_RAW}/scripts/tools/${segments[1]}.sh`;
          try {
            const resp = await fetch(toolScript);
            if (resp.ok) {
              return new Response(resp.body, {
                headers: {
                  ...corsHeaders,
                  'Content-Type': 'text/plain; charset=utf-8',
                  'Cache-Control': 'no-cache',
                },
              });
            }
          } catch { /* fall through */ }
          return new Response('Tool not found', { status: 404 });
        }
        // Protocol chooser questionnaire: vany.sh/choose | bash
        if (firstSegment === 'choose') {
          try {
            const resp = await fetch(`${GITHUB_RAW}/scripts/tools/choose.sh`);
            if (resp.ok) {
              return new Response(resp.body, {
                headers: {
                  ...corsHeaders,
                  'Content-Type': 'text/plain; charset=utf-8',
                  'Cache-Control': 'no-cache',
                },
              });
            }
          } catch { /* fall through */ }
        }
        // Known protocol: serve standalone direct installer
        if (config) {
          return serveDirectInstaller(firstSegment);
        }
        // Unknown path: 404 (don't fall back to start.sh)
        return new Response('Not found', { status: 404 });
      }

      // Browsers: redirect to www
      return Response.redirect('https://www.vany.sh/', 301);
    }

    // Extract subdomain (e.g., "reality" from "reality.vany.sh")
    const subdomain = hostname.split('.')[0];

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

    // Health check (any subdomain)
    if (url.pathname === '/health') {
      return Response.json({
        status: 'ok',
        subdomain,
        timestamp: Date.now(),
      }, { headers: corsHeaders });
    }

    // Main entry point: start.vany.sh -> serves start.sh (backward compat)
    if (subdomain === 'start') {
      return serveStartScript();
    }

    // Per-protocol (backward compat for subdomain URLs)
    const config = SERVICES[subdomain];

    if (config && url.pathname === '/info') {
      return new Response(getInfoPage(subdomain, config), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'text/html; charset=utf-8',
        },
      });
    }

    // Version endpoint
    if (config && url.pathname === '/version') {
      return Response.json({
        service: subdomain,
        name: config.name,
        repo: 'https://github.com/behnamkhorsandian/Vanysh',
      }, { headers: corsHeaders });
    }

    // DNSTT client setup page
    if (subdomain === 'dnstt' && url.pathname === '/client') {
      const pubkey = url.searchParams.get('key') || '';
      const domain = url.searchParams.get('domain') || 't.example.com';
      return new Response(getDnsttClientPage(pubkey, domain), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'text/html; charset=utf-8',
        },
      });
    }

    // DNSTT one-liner scripts for different platforms
    if (subdomain === 'dnstt' && url.pathname.startsWith('/setup/')) {
      const platform = url.pathname.split('/')[2];
      const pubkey = url.searchParams.get('key') || '';
      const domain = url.searchParams.get('domain') || '';

      if (!pubkey || !domain) {
        return new Response('Missing key or domain parameter', { status: 400 });
      }

      const script = getDnsttSetupScript(platform, pubkey, domain);
      if (!script) {
        return new Response('Unknown platform', { status: 404 });
      }

      return new Response(script, {
        headers: {
          ...corsHeaders,
          'Content-Type': 'text/plain; charset=utf-8',
        },
      });
    }

    // Per-protocol shortcut (backward compat): curl reality.vany.sh | sudo bash
    // Primary format is now: curl vany.sh/reality | sudo bash
    if (config) {
      const ua = (request.headers.get('User-Agent') || '').toLowerCase();
      const isCli = ua.includes('curl') || ua.includes('wget') || ua.includes('fetch');
      if (isCli) {
        return serveDirectInstaller(subdomain);
      }
      // Browsers: show info page
      return new Response(getInfoPage(subdomain, config), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'text/html; charset=utf-8',
        },
      });
    }

    return new Response(`Unknown service: ${subdomain}`, { status: 404 });
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
  <title>Vany - ${config.name}</title>
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
    <h1>Vany - ${config.name}</h1>
    <p class="description">${config.description}</p>
    
    <div class="services">
      <a href="https://vany.sh/info">All Protocols</a>
      <a href="https://vany.sh/reality/info" ${service === 'reality' ? 'class="active"' : ''}>Reality</a>
      <a href="https://vany.sh/wg/info" ${service === 'wg' ? 'class="active"' : ''}>WireGuard</a>
      <a href="https://vany.sh/mtp/info" ${service === 'mtp' ? 'class="active"' : ''}>MTProto</a>
      <a href="https://vany.sh/vray/info" ${service === 'vray' ? 'class="active"' : ''}>V2Ray</a>
      <a href="https://vany.sh/ws/info" ${service === 'ws' ? 'class="active"' : ''}>WS+CDN</a>
      <a href="https://vany.sh/dnstt/info" ${service === 'dnstt' ? 'class="active"' : ''}>DNStt</a>
      <a href="https://vany.sh/conduit/info" ${service === 'conduit' ? 'class="active"' : ''}>Conduit</a>
    </div>
    
    <div class="install-box">
      <h2>Install on your VPS</h2>
      <p style="color:#8b949e;margin-bottom:10px;">Install this protocol directly:</p>
      <code>curl vany.sh/${service} | sudo bash</code>
      <p style="color:#8b949e;margin-top:15px;">Or install the full interactive menu:</p>
      <code>curl vany.sh | sudo bash</code>
    </div>
    
    <div class="apps">
      <h2>Client Apps</h2>
      <ul>
        ${appLinks}
      </ul>
    </div>
    
    <div class="footer">
      <p>
        <a href="https://github.com/behnamkhorsandian/Vanysh">GitHub</a> |
        <a href="https://github.com/behnamkhorsandian/Vanysh/blob/main/docs/protocols/${service}.md">Documentation</a>
      </p>
    </div>
  </div>
</body>
</html>`;
}

function getDnsttSetupScript(platform: string, pubkey: string, domain: string): string | null {
  const baseUrl = 'https://www.bamsoftware.com/software/dnstt';
  
  switch (platform) {
    case 'linux':
      return `#!/bin/bash
# Vany DNSTT Client Setup - Linux
# Run: curl "vany.sh/dnstt/setup/linux?key=${pubkey}&domain=${domain}" | bash

set -e
echo "=== Vany DNSTT Client Setup ==="

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Create directory
mkdir -p ~/.vany
cd ~/.vany

# Download client
echo "Downloading dnstt-client..."
GO_VERSION="1.21.6"
curl -sL "https://go.dev/dl/go\${GO_VERSION}.linux-\${ARCH}.tar.gz" | tar xz
export PATH="$PWD/go/bin:$PATH"
export GOPATH="$PWD/gopath"
go install www.bamsoftware.com/git/dnstt.git/dnstt-client@latest
mv gopath/bin/dnstt-client .
rm -rf go gopath

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To start the tunnel, run:"
echo "  ~/.vany/dnstt-client -udp 8.8.8.8:53 -pubkey ${pubkey} ${domain} 127.0.0.1:1080"
echo ""
echo "Then configure your apps to use SOCKS5 proxy:"
echo "  Server: 127.0.0.1"
echo "  Port: 1080"
echo ""
`;

    case 'macos':
      return `#!/bin/bash
# Vany DNSTT Client Setup - macOS
# Run: curl "vany.sh/dnstt/setup/macos?key=${pubkey}&domain=${domain}" | bash

set -e
echo "=== Vany DNSTT Client Setup ==="

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Create directory
mkdir -p ~/.vany
cd ~/.vany

# Check if Go is installed
if ! command -v go &>/dev/null; then
  echo "Installing Go via Homebrew..."
  if command -v brew &>/dev/null; then
    brew install go
  else
    echo "Please install Homebrew first: https://brew.sh"
    exit 1
  fi
fi

# Build client
echo "Building dnstt-client..."
GOPATH="$PWD/gopath" go install www.bamsoftware.com/git/dnstt.git/dnstt-client@latest
mv gopath/bin/dnstt-client .
rm -rf gopath

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To start the tunnel, run:"
echo "  ~/.vany/dnstt-client -udp 8.8.8.8:53 -pubkey ${pubkey} ${domain} 127.0.0.1:1080"
echo ""
echo "Then configure your apps to use SOCKS5 proxy:"
echo "  Server: 127.0.0.1"
echo "  Port: 1080"
echo ""
`;

    case 'windows':
      return `# Vany DNSTT Client Setup - Windows PowerShell
# Run in PowerShell: iex (iwr "vany.sh/dnstt/setup/windows?key=${pubkey}&domain=${domain}").Content

Write-Host "=== Vany DNSTT Client Setup ===" -ForegroundColor Cyan

$vany_dir = "$env:USERPROFILE\\.vany"
New-Item -ItemType Directory -Force -Path $vany_dir | Out-Null
Set-Location $vany_dir

# Download Go
Write-Host "Downloading Go..."
$go_version = "1.21.6"
Invoke-WebRequest -Uri "https://go.dev/dl/go$go_version.windows-amd64.zip" -OutFile "go.zip"
Expand-Archive -Path "go.zip" -DestinationPath "." -Force
Remove-Item "go.zip"

# Build client
Write-Host "Building dnstt-client..."
$env:GOPATH = "$vany_dir\\gopath"
$env:PATH = "$vany_dir\\go\\bin;$env:PATH"
& go install www.bamsoftware.com/git/dnstt.git/dnstt-client@latest
Move-Item "$vany_dir\\gopath\\bin\\dnstt-client.exe" "$vany_dir\\"
Remove-Item -Recurse -Force "$vany_dir\\go", "$vany_dir\\gopath"

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "To start the tunnel, run:"
Write-Host "  $vany_dir\\dnstt-client.exe -udp 8.8.8.8:53 -pubkey ${pubkey} ${domain} 127.0.0.1:1080" -ForegroundColor Yellow
Write-Host ""
Write-Host "Then configure your apps to use SOCKS5 proxy:"
Write-Host "  Server: 127.0.0.1"
Write-Host "  Port: 1080"
Write-Host ""
`;

    default:
      return null;
  }
}

function getDnsttClientPage(pubkey: string, domain: string): string {
  const hasConfig = pubkey && domain;
  const linuxCmd = hasConfig 
    ? `curl "vany.sh/dnstt/setup/linux?key=${pubkey}&domain=${domain}" | bash`
    : 'curl "vany.sh/dnstt/setup/linux?key=YOUR_KEY&domain=t.yourdomain.com" | bash';
  const macCmd = hasConfig
    ? `curl "vany.sh/dnstt/setup/macos?key=${pubkey}&domain=${domain}" | bash`
    : 'curl "vany.sh/dnstt/setup/macos?key=YOUR_KEY&domain=t.yourdomain.com" | bash';
  const winCmd = hasConfig
    ? `iex (iwr "vany.sh/dnstt/setup/windows?key=${pubkey}&domain=${domain}").Content`
    : 'iex (iwr "vany.sh/dnstt/setup/windows?key=YOUR_KEY&domain=t.yourdomain.com").Content';

  return `<!DOCTYPE html>
<html>
<head>
  <title>Vany - DNSTT Client Setup</title>
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
      max-width: 800px;
      margin: 0 auto;
      padding: 40px 20px;
    }
    h1 { color: #ff6b6b; margin-bottom: 10px; }
    h2 { color: #58a6ff; margin-top: 30px; }
    .warning {
      background: #4a3728;
      border: 1px solid #f0ad4e;
      border-radius: 8px;
      padding: 15px;
      margin: 20px 0;
    }
    .warning strong { color: #f0ad4e; }
    .config-form {
      background: #0d1117;
      border: 1px solid #30363d;
      border-radius: 8px;
      padding: 20px;
      margin: 20px 0;
    }
    .config-form label {
      display: block;
      margin-bottom: 5px;
      color: #8b949e;
    }
    .config-form input {
      width: 100%;
      padding: 10px;
      margin-bottom: 15px;
      background: #161b22;
      border: 1px solid #30363d;
      border-radius: 6px;
      color: #c9d1d9;
      font-family: monospace;
    }
    .config-form button {
      background: #238636;
      color: white;
      border: none;
      padding: 10px 20px;
      border-radius: 6px;
      cursor: pointer;
      font-size: 16px;
    }
    .config-form button:hover { background: #2ea043; }
    .platform-box {
      background: #0d1117;
      border: 1px solid #30363d;
      border-radius: 8px;
      padding: 20px;
      margin: 15px 0;
    }
    .platform-box h3 {
      margin-top: 0;
      color: #7ee787;
    }
    code {
      background: #161b22;
      padding: 12px 15px;
      border-radius: 6px;
      display: block;
      font-family: 'SF Mono', Monaco, monospace;
      font-size: 13px;
      color: #7ee787;
      overflow-x: auto;
      white-space: pre-wrap;
      word-break: break-all;
    }
    .copy-btn {
      background: #21262d;
      color: #c9d1d9;
      border: 1px solid #30363d;
      padding: 5px 10px;
      border-radius: 4px;
      cursor: pointer;
      float: right;
      font-size: 12px;
    }
    .copy-btn:hover { background: #30363d; }
    .note {
      color: #8b949e;
      font-size: 14px;
      margin-top: 10px;
    }
    ${hasConfig ? '' : '.commands { opacity: 0.5; }'}
  </style>
</head>
<body>
  <div class="container">
    <h1>🚨 DNSTT Client Setup</h1>
    <p>Emergency DNS tunnel for when everything else is blocked.</p>
    
    <div class="warning">
      <strong>⚠️ Warning:</strong> DNS tunnel is very slow (50-150 kbps). 
      Use only when all other protocols are blocked.
    </div>
    
    ${!hasConfig ? `
    <div class="config-form">
      <h3>Enter Your Server Details</h3>
      <p class="note">Get these from your server admin or from the DNSTT menu on your server.</p>
      
      <label>Public Key:</label>
      <input type="text" id="pubkey" placeholder="0970668fb48c80d503f149a2d18ddbfd01101bc26f1e865f46ab7b2ab1280948">
      
      <label>Domain:</label>
      <input type="text" id="domain" placeholder="t.vany.sh">
      
      <button onclick="generateLinks()">Generate Setup Commands</button>
    </div>
    ` : `
    <div class="config-form">
      <h3>✅ Configuration Loaded</h3>
      <p><strong>Domain:</strong> ${domain}</p>
      <p><strong>Public Key:</strong> <code style="display:inline;padding:2px 6px;">${pubkey.substring(0, 20)}...</code></p>
    </div>
    `}
    
    <div class="commands">
      <h2>🐧 Linux</h2>
      <div class="platform-box">
        <h3>One-Line Setup</h3>
        <button class="copy-btn" onclick="copyCmd('linux-cmd')">Copy</button>
        <code id="linux-cmd">${linuxCmd}</code>
        <p class="note">Run in Terminal. Downloads and builds dnstt-client automatically.</p>
      </div>
      
      <h2>🍎 macOS</h2>
      <div class="platform-box">
        <h3>One-Line Setup</h3>
        <button class="copy-btn" onclick="copyCmd('mac-cmd')">Copy</button>
        <code id="mac-cmd">${macCmd}</code>
        <p class="note">Run in Terminal. Requires Homebrew for Go installation.</p>
      </div>
      
      <h2>🪟 Windows</h2>
      <div class="platform-box">
        <h3>PowerShell Setup</h3>
        <button class="copy-btn" onclick="copyCmd('win-cmd')">Copy</button>
        <code id="win-cmd">${winCmd}</code>
        <p class="note">Run in PowerShell as Administrator.</p>
      </div>
      
      <h2>📱 Mobile</h2>
      <div class="platform-box">
        <h3>Limited Support</h3>
        <p>DNSTT requires a native client and isn't directly supported on iOS/Android.</p>
        <p>Options:</p>
        <ul>
          <li>Run DNSTT client on a computer and share the SOCKS5 proxy over WiFi</li>
          <li>Use a Raspberry Pi as a tunnel gateway</li>
        </ul>
      </div>
    </div>
    
    <h2>After Setup</h2>
    <div class="platform-box">
      <p>Configure your apps to use <strong>SOCKS5 proxy</strong>:</p>
      <ul>
        <li><strong>Server:</strong> 127.0.0.1</li>
        <li><strong>Port:</strong> 1080</li>
      </ul>
      <p class="note">Firefox: Settings → Network Settings → Manual proxy → SOCKS Host</p>
    </div>
  </div>
  
  <script>
    function copyCmd(id) {
      const text = document.getElementById(id).innerText;
      navigator.clipboard.writeText(text);
      event.target.innerText = 'Copied!';
      setTimeout(() => event.target.innerText = 'Copy', 2000);
    }
    
    function generateLinks() {
      const pubkey = document.getElementById('pubkey').value.trim();
      const domain = document.getElementById('domain').value.trim();
      if (!pubkey || !domain) {
        alert('Please enter both public key and domain');
        return;
      }
      window.location.href = '/client?key=' + encodeURIComponent(pubkey) + '&domain=' + encodeURIComponent(domain);
    }
  </script>
</body>
</html>`;
}
