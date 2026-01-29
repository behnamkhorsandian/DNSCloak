/**
 * DNSCloak - Stats Relay Durable Object
 * 
 * Receives stats from VPS via POST /push
 * Broadcasts to connected WebSocket clients
 * Serves current stats via GET /current
 */

export interface StatsData {
  uptime: string;
  connecting: number;
  connected: number;
  up: string;
  down: string;
  countries: Array<{ code: string; count: number }>;
  system?: {
    machine: string;
    vcpus: number;
    ram: string;
    bandwidth: string;
  };
  timestamp: number;
}

export class StatsRelay implements DurableObject {
  private sessions: Set<WebSocket> = new Set();
  private latestStats: StatsData | null = null;
  private state: DurableObjectState;

  constructor(state: DurableObjectState) {
    this.state = state;
    
    // Restore latest stats from storage on startup
    this.state.blockConcurrencyWhile(async () => {
      const stored = await this.state.storage.get<StatsData>('latestStats');
      if (stored) {
        this.latestStats = stored;
      }
    });
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // CORS headers
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    // WebSocket upgrade for clients
    if (path === '/' || path === '/ws') {
      const upgradeHeader = request.headers.get('Upgrade');
      if (upgradeHeader?.toLowerCase() === 'websocket') {
        return this.handleWebSocket(request);
      }
      
      // Non-WebSocket request to root - return info
      return Response.json({
        service: 'stats-relay',
        description: 'DNSCloak live stats WebSocket relay',
        endpoints: {
          websocket: 'wss://stats.dnscloak.net/',
          current: 'https://stats.dnscloak.net/current',
          push: 'POST https://stats.dnscloak.net/push',
        },
        connected_clients: this.sessions.size,
      }, { headers: corsHeaders });
    }

    // POST /push - receive stats from VPS
    if (path === '/push' && request.method === 'POST') {
      return this.handlePush(request, corsHeaders);
    }

    // GET /current - return latest stats
    if (path === '/current' && request.method === 'GET') {
      return this.handleCurrent(corsHeaders);
    }

    return new Response('Not found', { status: 404, headers: corsHeaders });
  }

  /**
   * Handle WebSocket upgrade
   */
  private handleWebSocket(request: Request): Response {
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    // Accept the WebSocket
    this.state.acceptWebSocket(server);
    this.sessions.add(server);

    // Send current stats immediately if available
    if (this.latestStats) {
      server.send(JSON.stringify(this.latestStats));
    }

    return new Response(null, {
      status: 101,
      webSocket: client,
    });
  }

  /**
   * Handle incoming stats from VPS
   */
  private async handlePush(request: Request, corsHeaders: Record<string, string>): Promise<Response> {
    try {
      const stats: StatsData = await request.json();
      
      // Validate required fields
      if (typeof stats.uptime !== 'string' || 
          typeof stats.connecting !== 'number' ||
          typeof stats.connected !== 'number') {
        return Response.json({ error: 'Invalid stats format' }, { 
          status: 400, 
          headers: corsHeaders 
        });
      }

      // Store stats
      this.latestStats = stats;
      await this.state.storage.put('latestStats', stats);

      // Broadcast to all connected clients
      const message = JSON.stringify(stats);
      const deadSessions: WebSocket[] = [];

      for (const ws of this.sessions) {
        try {
          ws.send(message);
        } catch {
          // Connection dead, mark for removal
          deadSessions.push(ws);
        }
      }

      // Clean up dead connections
      for (const ws of deadSessions) {
        this.sessions.delete(ws);
      }

      return Response.json({ 
        success: true, 
        clients_notified: this.sessions.size 
      }, { headers: corsHeaders });

    } catch (error) {
      return Response.json({ 
        error: 'Failed to process stats',
        message: error instanceof Error ? error.message : 'Unknown error'
      }, { status: 500, headers: corsHeaders });
    }
  }

  /**
   * Return current stats
   */
  private handleCurrent(corsHeaders: Record<string, string>): Response {
    if (!this.latestStats) {
      return Response.json({ 
        error: 'No stats available yet' 
      }, { status: 404, headers: corsHeaders });
    }

    return Response.json(this.latestStats, { headers: corsHeaders });
  }

  /**
   * Handle WebSocket messages (not used - clients are read-only)
   */
  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    // Clients are read-only, ignore incoming messages
    // Could add ping/pong here if needed
  }

  /**
   * Handle WebSocket close
   */
  async webSocketClose(ws: WebSocket, code: number, reason: string, wasClean: boolean): Promise<void> {
    this.sessions.delete(ws);
  }

  /**
   * Handle WebSocket error
   */
  async webSocketError(ws: WebSocket, error: unknown): Promise<void> {
    this.sessions.delete(ws);
  }
}
