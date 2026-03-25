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
import { handleVless } from './vless.js';

const GITHUB_RAW = 'https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main';

interface Env {
  SAFEBOX: KVNamespace;
}

/** Fire-and-forget KV counter increment */
function incrStat(kv: KVNamespace, key: string, ctx: ExecutionContext): void {
  ctx.waitUntil(
    kv.get(key).then(v => kv.put(key, String((parseInt(v || '0', 10) || 0) + 1)))
  );
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
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
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

      // Stats endpoint: aggregate counters from KV
      if (url.pathname === '/stats') {
        const corsJson = { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' };
        const keys = ['stats:visits', 'stats:boxes', 'stats:connects', 'stats:downloads'];
        const vals = await Promise.all(keys.map(k => env.SAFEBOX.get(k)));
        return Response.json({
          visits: parseInt(vals[0] || '0', 10),
          boxes: parseInt(vals[1] || '0', 10),
          connects: parseInt(vals[2] || '0', 10),
          downloads: parseInt(vals[3] || '0', 10),
          uptime: '99.9%',
        }, { headers: corsJson });
      }

      // Alternative access mirrors for restricted networks
      if (url.pathname === '/mirrors') {
        const mirrors = {
          primary: 'https://vany.sh',
          alternatives: [
            { name: 'GitHub Raw', url: 'https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/start.sh', usage: 'curl -sL https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/start.sh | sudo bash', note: 'Fastly CDN — completely different network than Cloudflare' },
            { name: 'Cloudflare Pages', url: 'https://vany-agg.pages.dev', usage: 'curl -sL https://vany-agg.pages.dev | sudo bash', note: '*.pages.dev shared domain — very hard to block' },
          ],
          rescue: 'curl -m5 vany.sh||curl -sL https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/start.sh||curl vany-agg.pages.dev',
          access_methods: [
            { name: 'Direct', cmd: 'curl vany.sh | sudo bash', note: 'Works unless domain is blocked' },
            { name: 'GitHub Raw', cmd: 'curl -sL https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/start.sh | sudo bash', note: 'Fastly CDN — NOT Cloudflare, often works when CF is fully blocked' },
            { name: 'Direct IP', cmd: 'curl --resolve vany.sh:443:104.16.0.1 https://vany.sh | sudo bash', note: 'Skip DNS — connect to known Cloudflare IPs directly' },
            { name: 'DoH bypass', cmd: 'curl --doh-url https://1.1.1.1/dns-query vany.sh | sudo bash', note: 'Bypasses DNS poisoning (curl 7.62+)' },
            { name: 'CF Pages', cmd: 'curl -sL vany-agg.pages.dev | sudo bash', note: 'Shared *.pages.dev domain, hard to block' },
            { name: 'WARP (1.1.1.1)', cmd: 'Install 1.1.1.1 app, enable, then curl vany.sh | sudo bash', note: 'Free Cloudflare VPN, bypasses all blocks' },
            { name: 'Offline', cmd: 'sudo bash start.sh', note: 'Ask someone to send you start.sh directly' },
          ],
          windows: {
            note: 'Windows CMD cannot pipe to bash. Use WSL or download the script file.',
            methods: [
              { name: 'WSL', cmd: 'wsl --install && wsl', note: 'Install WSL, then use Linux commands inside' },
              { name: 'Direct IP (CMD)', cmd: 'curl.exe --resolve vany.sh:443:104.16.0.1 https://vany.sh', note: 'Skip DNS in Windows CMD' },
              { name: 'GitHub download', cmd: 'curl.exe -sL https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/start.sh -o start.sh', note: 'Download via Fastly CDN, then copy to VPS' },
            ],
          },
          warp: {
            note: 'Cloudflare WARP (1.1.1.1) is a free VPN that routes through Cloudflare. Once enabled, all blocked Cloudflare sites become accessible.',
            ios: 'https://apps.apple.com/app/1-1-1-1-faster-internet/id1423538627',
            android: 'https://play.google.com/store/apps/details?id=com.cloudflare.onedotonedotonedotone',
            windows: 'https://1.1.1.1/',
            macos: 'https://1.1.1.1/',
            linux: 'https://pkg.cloudflareclient.com/',
          },
          bootstrap: 'The rescue bootstrap auto-tries: direct → GitHub (Fastly) → CF IPs → DoH → Pages. If all fail, install WARP or get the script offline.',
          offline: 'Ask someone to send you the start.sh file directly — it works offline after first download. Run: sudo bash start.sh',
        };
        return Response.json(mirrors, { headers: corsHeaders });
      }

      // Bootstrap: self-contained rescue script with all fallbacks embedded
      if (url.pathname === '/bootstrap') {
        const script = `#!/bin/bash
# Vany Rescue Bootstrap — tries every access method automatically
set -euo pipefail
GITHUB_RAW="https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/start.sh"
DOH_URLS=("https://1.1.1.1/dns-query" "https://8.8.8.8/resolve" "https://9.9.9.9:5053/dns-query")
CF_IPS=("104.16.0.1" "104.17.0.1" "172.67.0.1")
echo "Vany — finding a working connection..."

# Method 1: Direct
if curl -sf -m 5 -o /dev/null https://vany.sh/health 2>/dev/null; then
    echo "Direct connection OK"
    exec bash <(curl -sSf https://vany.sh 2>/dev/null)
fi
echo "Direct blocked. Trying GitHub (Fastly CDN)..."

# Method 2: GitHub raw (Fastly CDN — NOT Cloudflare, often works when CF is blocked)
if curl -sf -m 5 -o /dev/null "\$GITHUB_RAW" 2>/dev/null; then
    echo "GitHub OK (Fastly CDN)"
    exec bash <(curl -sSf "\$GITHUB_RAW" 2>/dev/null)
fi
echo "GitHub blocked. Trying direct IPs..."

# Method 3: Known CF anycast IPs (skip DNS entirely)
for cfip in "\${CF_IPS[@]}"; do
    if curl -sf -m 5 -o /dev/null --resolve "vany.sh:443:\$cfip" https://vany.sh/health 2>/dev/null; then
        echo "CF IP \$cfip works"
        exec bash <(curl -sSf --resolve "vany.sh:443:\$cfip" https://vany.sh 2>/dev/null)
    fi
done
echo "CF IPs blocked. Trying DoH..."

# Method 4: DoH resolve + --resolve flag
for doh in "\${DOH_URLS[@]}"; do
    ip=\$(curl -sf -m 5 -H "accept: application/dns-json" "\${doh}?name=vany.sh&type=A" 2>/dev/null \\
        | grep -oE '"data":"[0-9.]+"' | head -1 | grep -oE '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+' || true)
    if [[ -n "\$ip" ]]; then
        if curl -sf -m 5 -o /dev/null --resolve "vany.sh:443:\$ip" https://vany.sh/health 2>/dev/null; then
            echo "DoH resolved to \$ip"
            exec bash <(curl -sSf --resolve "vany.sh:443:\$ip" https://vany.sh 2>/dev/null)
        fi
    fi
done
echo "DoH failed. Trying alternate domain..."

# Method 5: Cloudflare Pages (*.pages.dev — shared domain, hard to block)
if curl -sf -m 5 -o /dev/null https://vany-agg.pages.dev/ 2>/dev/null; then
    echo "Pages mirror OK"
    exec bash <(curl -sSf https://vany-agg.pages.dev/ 2>/dev/null)
fi

echo ""
echo "All methods failed. Your network blocks everything."
echo ""
echo "Last resort options:"
echo "  1. Install Cloudflare WARP (1.1.1.1 app): https://1.1.1.1/"
echo "     Then run: curl vany.sh | sudo bash"
echo "  2. Ask someone to send you the start.sh file directly"
echo "     Then run: sudo bash start.sh"
exit 1
`;
        return new Response(script, {
          headers: {
            ...corsHeaders,
            'Content-Type': 'text/plain; charset=utf-8',
            'Cache-Control': 'no-cache, no-store, must-revalidate',
          },
        });
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
          incrStat(env.SAFEBOX, 'stats:boxes', ctx);
          return handleBoxCreate(request, env.SAFEBOX);
        }
        if (boxSegments.length === 1 && request.method === 'GET') {
          const ua = (request.headers.get('User-Agent') || '').toLowerCase();
          const isCli = ua.includes('curl') || ua.includes('wget') || ua.includes('fetch');
          return handleBoxPage(isCli);
        }
        if (boxSegments.length === 2 && request.method === 'GET') {
          const pass = url.searchParams.get('pass') || undefined;
          return handleBoxFetch(boxSegments[1], env.SAFEBOX, pass);
        }
        return new Response('Not found', { status: 404 });
      }

      // VLESS-over-WebSocket proxy: /vless → handled entirely in-Worker (no VPS)
      if (url.pathname === '/vless') {
        return handleVless(request, env);
      }

      // Network Faucet: /faucet/relay → WebSocket relay mesh + VPN reward
      if (url.pathname === '/faucet/relay') {
        const upgradeHeader = request.headers.get('Upgrade');
        if (!upgradeHeader || upgradeHeader.toLowerCase() !== 'websocket') {
          return new Response('Expected WebSocket', { status: 426 });
        }
        const pair = new WebSocketPair();
        const [client, server] = Object.values(pair);
        (server as WebSocket).accept();
        incrStat(env.SAFEBOX, 'stats:connects', ctx);

        // Generate ephemeral UUID for this relay session
        const sessionId = crypto.randomUUID().slice(0, 8);

        (server as WebSocket).addEventListener('message', (event: MessageEvent) => {
          try {
            const msg = JSON.parse(typeof event.data === 'string' ? event.data : '');
            if (msg.type === 'register') {
              // Build VLESS+WS link as reward (proxied by this Worker, no VPS needed)
              const uuid = crypto.randomUUID();
              const kvKey = `faucet:client:${uuid}`;
              const meta = JSON.stringify({ node: msg.node, session: sessionId, created: Date.now() });
              ctx.waitUntil(env.SAFEBOX.put(kvKey, meta, { expirationTtl: 120 }));

              const domain = url.hostname;
              const link = `vless://${uuid}@${domain}:443?type=ws&security=tls&path=%2Fvless&host=${domain}&sni=${domain}#faucet-${msg.node}`;
              (server as WebSocket).send(JSON.stringify({
                type: 'welcome',
                node: msg.node,
                vpn: { link, uuid, ttl: 120 },
              }));
            } else if (msg.type === 'ping') {
              // Refresh KV TTL — keep VPN alive as long as faucet is open
              if (msg.uuid) {
                const kvKey = `faucet:client:${msg.uuid}`;
                ctx.waitUntil(env.SAFEBOX.get(kvKey).then(v => {
                  if (v) env.SAFEBOX.put(kvKey, v, { expirationTtl: 120 });
                }));
              }
              (server as WebSocket).send(JSON.stringify({ type: 'pong' }));
            } else if (msg.type === 'ack') {
              // Relay acknowledgement from node
            }
          } catch { /* ignore malformed */ }
        });

        (server as WebSocket).addEventListener('close', () => {
          // KV entry will auto-expire in ~2 min, VPN access dies with it
        });

        return new Response(null, { status: 101, webSocket: client });
      }

      // Faucet active clients: /faucet/active → JSON list of active UUIDs (for VPS Xray sync)
      if (url.pathname === '/faucet/active') {
        const corsJson = { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' };
        if (request.method === 'OPTIONS') {
          return new Response(null, { headers: corsJson });
        }
        // List all active faucet client keys
        const list = await env.SAFEBOX.list({ prefix: 'faucet:client:' });
        const uuids = list.keys.map(k => k.name.replace('faucet:client:', ''));
        return Response.json({ count: uuids.length, uuids }, { headers: corsJson });
      }

      // Faucet CLI script: /faucet → bash script for terminal relay
      if (url.pathname === '/faucet') {
        return new Response(faucetCliScript(), {
          headers: { 'Content-Type': 'text/plain; charset=utf-8', ...corsHeaders },
        });
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
          incrStat(env.SAFEBOX, 'stats:visits', ctx);
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
          incrStat(env.SAFEBOX, 'stats:downloads', ctx);
          return serveDirectInstaller(firstSegment);
        }
        // Unknown path: 404 (don't fall back to start.sh)
        return new Response('Not found', { status: 404 });
      }

      // Browsers: redirect to www
      incrStat(env.SAFEBOX, 'stats:visits', ctx);
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

function faucetCliScript(): string {
  return `#!/bin/bash
# Vany Network Faucet - Terminal Relay Node
# Relay SafeBox traffic, get a free VPN in exchange
# Usage: curl -s vany.sh/faucet | bash

set -e

GREEN="\\033[38;5;35m"
LGREEN="\\033[38;5;114m"
DIM="\\033[2m"
BOLD="\\033[1m"
RST="\\033[0m"
RED="\\033[38;5;167m"
YELLOW="\\033[38;5;185m"
BLUE="\\033[38;5;68m"
CYAN="\\033[38;5;73m"

RELAY_URL="wss://vany.sh/faucet/relay"
NODE_ID=\$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \\n')
START_TIME=\$(date +%s)
WSPID=""
VPN_LINK=""
FIFO=""
OUTFILE=""

cleanup() {
  echo ""
  [[ -n "\$WSPID" ]] && kill "\$WSPID" 2>/dev/null || true
  [[ -p "\$FIFO" ]] && rm -f "\$FIFO" 2>/dev/null || true
  [[ -f "\$OUTFILE" ]] && rm -f "\$OUTFILE" 2>/dev/null || true
  exec 3>&- 2>/dev/null || true
  ELAPSED=\$((\$(date +%s) - START_TIME))
  MINS=\$((ELAPSED / 60))
  SECS=\$((ELAPSED % 60))
  echo -e "  \${DIM}Session ended after \${MINS}m\${SECS}s.\${RST}"
  if [[ -n "\$VPN_LINK" ]]; then
    echo -e "  \${DIM}VPN link expired. Open Faucet again to get a new one.\${RST}"
  fi
  exit 0
}

trap cleanup INT TERM EXIT

clear
echo ""
echo -e "  \${GREEN}\${BOLD}VANY NETWORK FAUCET\${RST}"
echo -e "  \${DIM}Relay SafeBox traffic -> get free VPN\${RST}"
echo ""
echo -e "  \${DIM}Node ID:    \${RST}\${LGREEN}node-\${NODE_ID}\${RST}"
echo -e "  \${DIM}Relay URL:  \${RST}\${BLUE}\${RELAY_URL}\${RST}"
echo ""
echo -e "  \${DIM}You relay encrypted SafeBox packets for censored regions.\${RST}"
echo -e "  \${DIM}In exchange, you get a free VPN link while Faucet is open.\${RST}"
echo ""
echo -e "  \${YELLOW}Press Ctrl+C to stop.\${RST}"
echo ""

# Check for websocat
if ! command -v websocat &>/dev/null; then
  echo -e "  \${RED}websocat not found.\${RST}"
  echo ""
  if [[ "\$(uname)" == "Darwin" ]]; then
    echo -e "    \${LGREEN}brew install websocat\${RST}"
  else
    echo -e "    \${LGREEN}wget -qO /usr/local/bin/websocat https://github.com/vi/websocat/releases/latest/download/websocat.x86_64-unknown-linux-musl\${RST}"
    echo -e "    \${LGREEN}chmod +x /usr/local/bin/websocat\${RST}"
  fi
  echo ""
  echo -e "  \${DIM}Or open \${BLUE}https://vany.sh\${RST} \${DIM}and click\${RST} \${LGREEN}Faucet\${RST}"
  echo ""
  exit 1
fi

echo -e "  \${DIM}Connecting...\${RST}"

# Create FIFO for sending to websocat
FIFO=\$(mktemp -u /tmp/vany-fc-XXXXXX)
mkfifo "\$FIFO"

# Output file for receiving from websocat
OUTFILE=\$(mktemp /tmp/vany-fc-out-XXXXXX)

# Start websocat in background (opens FIFO for reading)
websocat -t --ping-interval 25 "\${RELAY_URL}" < "\$FIFO" > "\$OUTFILE" 2>/dev/null &
WSPID=\$!

# Now open write end — unblocks websocat's read end
exec 3>"\$FIFO"
sleep 1

# Verify connection
if ! kill -0 \$WSPID 2>/dev/null; then
  echo -e "  \${RED}Connection failed.\${RST}"
  exit 1
fi

# Send registration
echo '{"type":"register","node":"'"\${NODE_ID}"'"}' >&3

# Wait for welcome response with VPN link
for i in 1 2 3 4 5; do
  sleep 1
  if grep -q '"link"' "\$OUTFILE" 2>/dev/null; then
    break
  fi
done

VPN_LINK=\$(grep -o '"link":"[^"]*"' "\$OUTFILE" 2>/dev/null | head -1 | cut -d'"' -f4 || true)

echo ""
echo -e "  \${GREEN}\${BOLD}CONNECTED\${RST} \${DIM}-- relay active\${RST}"
echo ""

if [[ -n "\$VPN_LINK" ]]; then
  echo -e "  \${GREEN}-----------------------------------------------\${RST}"
  echo -e "  \${GREEN}\${BOLD}  FREE VPN EARNED\${RST}"
  echo -e "  \${GREEN}-----------------------------------------------\${RST}"
  echo ""
  echo -e "  \${DIM}Import into v2rayNG, Hiddify, or Streisand:\${RST}"
  echo ""
  echo -e "  \${LGREEN}\${VPN_LINK}\${RST}"
  echo ""
  echo -e "  \${DIM}Or connect directly from terminal:\${RST}"
  echo ""

  # Extract UUID and params from the VLESS link for terminal connect
  VPN_UUID=\$(echo "\$VPN_LINK" | sed 's|vless://||' | cut -d'@' -f1)
  VPN_HOST=\$(echo "\$VPN_LINK" | cut -d'@' -f2 | cut -d':' -f1)
  VPN_PATH=\$(echo "\$VPN_LINK" | grep -o 'path=[^&]*' | cut -d= -f2 | python3 -c "import sys,urllib.parse;print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null || echo "/ws")

  if command -v xray &>/dev/null; then
    echo -e "    \${CYAN}# xray-core (SOCKS5 on 127.0.0.1:1080):\${RST}"
    echo -e "    \${DIM}xray run -c /dev/stdin <<'XCONF'\${RST}"
    echo -e '    \${DIM}{"inbounds":[{"port":1080,"protocol":"socks","settings":{"udp":true}}],"outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"'\$VPN_HOST'","port":443,"users":[{"id":"'\$VPN_UUID'","encryption":"none"}]}]},"streamSettings":{"network":"ws","wsSettings":{"path":"'\$VPN_PATH'","headers":{"Host":"'\$VPN_HOST'"}},"security":"tls","tlsSettings":{"serverName":"'\$VPN_HOST'"}}}]}\${RST}'
    echo -e "    \${DIM}XCONF\${RST}"
  elif command -v sing-box &>/dev/null; then
    echo -e "    \${CYAN}# sing-box (SOCKS5 on 127.0.0.1:1080):\${RST}"
    echo -e "    \${DIM}sing-box run -c /dev/stdin <<'SCONF'\${RST}"
    echo -e '    \${DIM}{"inbounds":[{"type":"socks","listen":"127.0.0.1","listen_port":1080}],"outbounds":[{"type":"vless","server":"'\$VPN_HOST'","server_port":443,"uuid":"'\$VPN_UUID'","tls":{"enabled":true,"server_name":"'\$VPN_HOST'"},"transport":{"type":"ws","path":"'\$VPN_PATH'","headers":{"Host":"'\$VPN_HOST'"}}}]}\${RST}'
    echo -e "    \${DIM}SCONF\${RST}"
  else
    echo -e "    \${CYAN}# Install xray-core or sing-box, then:\${RST}"
    echo -e "    \${DIM}export ALL_PROXY=socks5://127.0.0.1:1080\${RST}"
    echo -e "    \${DIM}curl -x socks5://127.0.0.1:1080 https://ifconfig.me\${RST}"
  fi

  echo ""
  echo -e "  \${DIM}VPN stays active while Faucet runs. Expires ~2 min after stop.\${RST}"
  echo -e "  \${GREEN}-----------------------------------------------\${RST}"
  echo ""
fi

# Heartbeat loop with live metrics
PING_COUNT=0
while kill -0 \$WSPID 2>/dev/null; do
  ELAPSED=\$((\$(date +%s) - START_TIME))
  MINS=\$((ELAPSED / 60))
  SECS=\$((ELAPSED % 60))
  MSGS=\$(wc -l < "\$OUTFILE" 2>/dev/null | tr -d ' ' || echo 0)
  printf "\\r  \${GREEN}*\${RST} \${LGREEN}Relaying\${RST} \${DIM}|\${RST} \${CYAN}\${MINS}m\${SECS}s\${RST} \${DIM}|\${RST} \${CYAN}\${MSGS}\${RST} \${DIM}msgs |\${RST} \${CYAN}\${PING_COUNT}\${RST} \${DIM}pings\${RST}    "
  echo '{"type":"ping","uuid":"'"\${VPN_UUID}"'"}' >&3 2>/dev/null || break
  PING_COUNT=\$((PING_COUNT + 1))
  sleep 30
done

cleanup
`;
}

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
