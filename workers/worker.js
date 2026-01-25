// DNSCloak MTProto Proxy - Cloudflare Worker
// Copy this entire file into your Cloudflare Worker editor
// 
// Usage: curl -sSL mtp.dnscloak.net | sudo bash

export default {
  async fetch(request) {
    const response = await fetch(
      'https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main/setup.sh'
    );
    
    if (!response.ok) {
      return new Response('Error fetching setup script', { status: 502 });
    }
    
    return new Response(await response.text(), {
      headers: {
        'Content-Type': 'text/plain',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
      }
    });
  }
}
