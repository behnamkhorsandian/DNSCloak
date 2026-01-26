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
      note: 'Requires native client binary.',
      setup: 'https://dnstt.dnscloak.net/client',
    },
  },
  conduit: {
    name: 'Conduit (Psiphon Relay)',
    description: 'Volunteer relay node for Psiphon network. Help users in censored regions.',
    script: 'services/conduit/install.sh',
    clientApps: {
      note: 'No client needed. Users connect via Psiphon apps.',
      psiphon: 'https://psiphon.ca/download.html',
    },
  },
  sos: {
    name: 'SOS Emergency Chat',
    description: 'Encrypted chat rooms over DNS tunnel. Auto-wipes after 1 hour. For emergencies.',
    script: 'services/sos/install.sh',
    clientApps: {
      note: 'TUI client launches automatically after install.',
    },
  },
};

export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const hostname = url.hostname;

    // Redirect root domain to www
    if (hostname === 'dnscloak.net') {
      return Response.redirect('https://www.dnscloak.net/', 301);
    }
    
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

    // DNSTT client setup page
    if (service === 'dnstt' && url.pathname === '/client') {
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
    if (service === 'dnstt' && url.pathname.startsWith('/setup/')) {
      const platform = url.pathname.split('/')[2]; // /setup/linux, /setup/macos, /setup/windows
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

function getDnsttSetupScript(platform: string, pubkey: string, domain: string): string | null {
  const baseUrl = 'https://www.bamsoftware.com/software/dnstt';
  
  switch (platform) {
    case 'linux':
      return `#!/bin/bash
# DNSCloak DNSTT Client Setup - Linux
# Run: curl -sSL "dnstt.dnscloak.net/setup/linux?key=${pubkey}&domain=${domain}" | bash

set -e
echo "=== DNSCloak DNSTT Client Setup ==="

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Create directory
mkdir -p ~/.dnscloak
cd ~/.dnscloak

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
echo "  ~/.dnscloak/dnstt-client -udp 8.8.8.8:53 -pubkey ${pubkey} ${domain} 127.0.0.1:1080"
echo ""
echo "Then configure your apps to use SOCKS5 proxy:"
echo "  Server: 127.0.0.1"
echo "  Port: 1080"
echo ""
`;

    case 'macos':
      return `#!/bin/bash
# DNSCloak DNSTT Client Setup - macOS
# Run: curl -sSL "dnstt.dnscloak.net/setup/macos?key=${pubkey}&domain=${domain}" | bash

set -e
echo "=== DNSCloak DNSTT Client Setup ==="

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Create directory
mkdir -p ~/.dnscloak
cd ~/.dnscloak

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
echo "  ~/.dnscloak/dnstt-client -udp 8.8.8.8:53 -pubkey ${pubkey} ${domain} 127.0.0.1:1080"
echo ""
echo "Then configure your apps to use SOCKS5 proxy:"
echo "  Server: 127.0.0.1"
echo "  Port: 1080"
echo ""
`;

    case 'windows':
      return `# DNSCloak DNSTT Client Setup - Windows PowerShell
# Run in PowerShell: iex (iwr "dnstt.dnscloak.net/setup/windows?key=${pubkey}&domain=${domain}").Content

Write-Host "=== DNSCloak DNSTT Client Setup ===" -ForegroundColor Cyan

$dnscloak_dir = "$env:USERPROFILE\\.dnscloak"
New-Item -ItemType Directory -Force -Path $dnscloak_dir | Out-Null
Set-Location $dnscloak_dir

# Download Go
Write-Host "Downloading Go..."
$go_version = "1.21.6"
Invoke-WebRequest -Uri "https://go.dev/dl/go$go_version.windows-amd64.zip" -OutFile "go.zip"
Expand-Archive -Path "go.zip" -DestinationPath "." -Force
Remove-Item "go.zip"

# Build client
Write-Host "Building dnstt-client..."
$env:GOPATH = "$dnscloak_dir\\gopath"
$env:PATH = "$dnscloak_dir\\go\\bin;$env:PATH"
& go install www.bamsoftware.com/git/dnstt.git/dnstt-client@latest
Move-Item "$dnscloak_dir\\gopath\\bin\\dnstt-client.exe" "$dnscloak_dir\\"
Remove-Item -Recurse -Force "$dnscloak_dir\\go", "$dnscloak_dir\\gopath"

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "To start the tunnel, run:"
Write-Host "  $dnscloak_dir\\dnstt-client.exe -udp 8.8.8.8:53 -pubkey ${pubkey} ${domain} 127.0.0.1:1080" -ForegroundColor Yellow
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
    ? `curl -sSL "dnstt.dnscloak.net/setup/linux?key=${pubkey}&domain=${domain}" | bash`
    : 'curl -sSL "dnstt.dnscloak.net/setup/linux?key=YOUR_KEY&domain=t.yourdomain.com" | bash';
  const macCmd = hasConfig
    ? `curl -sSL "dnstt.dnscloak.net/setup/macos?key=${pubkey}&domain=${domain}" | bash`
    : 'curl -sSL "dnstt.dnscloak.net/setup/macos?key=YOUR_KEY&domain=t.yourdomain.com" | bash';
  const winCmd = hasConfig
    ? `iex (iwr "dnstt.dnscloak.net/setup/windows?key=${pubkey}&domain=${domain}").Content`
    : 'iex (iwr "dnstt.dnscloak.net/setup/windows?key=YOUR_KEY&domain=t.yourdomain.com").Content';

  return `<!DOCTYPE html>
<html>
<head>
  <title>DNSCloak - DNSTT Client Setup</title>
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
      <input type="text" id="domain" placeholder="t.dnscloak.net">
      
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
