/**
 * DNSCloak MTProto Proxy - Cloudflare Workers Install Script Server
 * 
 * Serves the setup.sh script at api.dnscloak.net
 * Usage: curl -sSL api.dnscloak.net | sudo bash
 */

export interface Env {
  // Environment bindings (add if needed)
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    
    // CORS headers
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    };

    // Handle CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    // Serve setup script at root (for: curl -sSL api.dnscloak.net | sudo bash)
    if (url.pathname === "/" || url.pathname === "/setup" || url.pathname === "/setup.sh" || url.pathname === "/install") {
      // Fetch the latest setup.sh from GitHub (bypasses caching)
      const timestamp = Date.now();
      const githubUrl = `https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main/setup.sh?t=${timestamp}`;
      
      try {
        const response = await fetch(githubUrl, {
          headers: {
            "User-Agent": "DNSCloak-Worker/1.0",
            "Cache-Control": "no-cache",
          },
        });
        
        if (!response.ok) {
          throw new Error(`GitHub returned ${response.status}`);
        }
        
        const script = await response.text();
        
        return new Response(script, {
          headers: {
            ...corsHeaders,
            "Content-Type": "text/plain; charset=utf-8",
            "Cache-Control": "no-cache, no-store, must-revalidate",
          },
        });
      } catch (error) {
        // Fallback: redirect to GitHub raw
        return Response.redirect(
          "https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main/setup.sh",
          302
        );
      }
    }

    // Health check
    if (url.pathname === "/health") {
      return Response.json({
        status: "ok",
        service: "dnscloak-mtproto",
        timestamp: Date.now(),
      }, { headers: corsHeaders });
    }

    // Version endpoint
    if (url.pathname === "/version") {
      // Fetch version from setup.sh
      try {
        const response = await fetch(
          "https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main/setup.sh"
        );
        const script = await response.text();
        const versionMatch = script.match(/SCRIPT_VERSION="([^"]+)"/);
        const version = versionMatch ? versionMatch[1] : "unknown";
        
        return Response.json({
          version,
          repo: "https://github.com/behnamkhorsandian/DNSCloak",
        }, { headers: corsHeaders });
      } catch {
        return Response.json({ version: "unknown" }, { headers: corsHeaders });
      }
    }

    // Info page (for browsers)
    if (url.pathname === "/info" || request.headers.get("Accept")?.includes("text/html")) {
      const html = `<!DOCTYPE html>
<html>
<head>
  <title>DNSCloak - MTProto Proxy</title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      color: #eee;
      min-height: 100vh;
      margin: 0;
      display: flex;
      justify-content: center;
      align-items: center;
    }
    .container {
      max-width: 600px;
      padding: 40px;
      text-align: center;
    }
    h1 {
      color: #2eb787;
      font-size: 2.5em;
      margin-bottom: 10px;
    }
    .tagline {
      color: #888;
      margin-bottom: 30px;
    }
    .code {
      background: #0d1117;
      border: 1px solid #2eb787;
      border-radius: 8px;
      padding: 20px;
      font-family: 'Monaco', 'Menlo', monospace;
      font-size: 1.1em;
      color: #2eb787;
      margin: 20px 0;
      user-select: all;
      cursor: pointer;
    }
    .code:hover {
      border-color: #4fd1a5;
    }
    .features {
      text-align: left;
      margin: 30px 0;
    }
    .features li {
      margin: 10px 0;
      color: #aaa;
    }
    .features li::marker {
      color: #2eb787;
    }
    a {
      color: #2eb787;
      text-decoration: none;
    }
    a:hover {
      text-decoration: underline;
    }
    .footer {
      margin-top: 40px;
      color: #666;
      font-size: 0.9em;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>🛡️ DNSCloak</h1>
    <p class="tagline">MTProto Proxy with Fake-TLS Support</p>
    
    <p>SSH into your VPS and run:</p>
    <div class="code" onclick="navigator.clipboard.writeText('curl -sSL mtp.dnscloak.net | sudo bash')">
      curl -sSL mtp.dnscloak.net | sudo bash
    </div>
    <p style="color: #666; font-size: 0.9em;">Click to copy</p>
    
    <ul class="features">
      <li><strong>Fake-TLS (ee)</strong> - Traffic looks like HTTPS</li>
      <li><strong>Secure Mode (dd)</strong> - Random padding obfuscation</li>
      <li><strong>Port Analysis</strong> - Check open ports & firewall</li>
      <li><strong>Multi-User</strong> - Create multiple proxy users</li>
      <li><strong>Auto-Start</strong> - Systemd service included</li>
    </ul>
    
    <p class="footer">
      <a href="https://github.com/behnamkhorsandian/DNSCloak">GitHub</a> • 
      <a href="https://dnscloak.net">Website</a>
    </p>
  </div>
</body>
</html>`;
      
      return new Response(html, {
        headers: {
          ...corsHeaders,
          "Content-Type": "text/html; charset=utf-8",
        },
      });
    }

    // Default: serve setup script
    return Response.redirect(url.origin + "/", 302);
  },
};
