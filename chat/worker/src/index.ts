const ROOM_TTL_SECONDS = 3600;
const MAX_MESSAGES = 500;
const RATE_LIMIT_COOLDOWN_SECONDS = 1800;
const RATE_LIMIT_DELAYS_SECONDS = [0, 10, 30, 60, 180, 300];

interface Env {
  SOS_ROOM: DurableObjectNamespace;
  SOS_RATE: DurableObjectNamespace;
}

type RoomMode = 'fixed';

type RoomData = {
  room_hash: string;
  mode: RoomMode;
  created_at: number;
  expires_at: number;
  members: Record<string, string>;
  messages: Array<{ id: string; sender: string; content: string; timestamp: number }>;
};

type RateEntry = { count: number; last_attempt: number };

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Max-Age': '3600'
};

function nowSeconds() {
  return Date.now() / 1000;
}

function jsonResponse(data: unknown, status = 200, extraHeaders?: Record<string, string>) {
  const headers = new Headers({ 'Content-Type': 'application/json', ...corsHeaders, ...extraHeaders });
  return new Response(JSON.stringify(data), { status, headers });
}

function textResponse(text: string, status = 200, extraHeaders?: Record<string, string>) {
  const headers = new Headers({ 'Content-Type': 'text/plain; charset=utf-8', ...corsHeaders, ...extraHeaders });
  return new Response(text, { status, headers });
}

async function readJson(request: Request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

function getClientIp(request: Request) {
  const cfIp = request.headers.get('CF-Connecting-IP');
  if (cfIp) return cfIp;
  const xff = request.headers.get('X-Forwarded-For');
  if (xff) return xff.split(',')[0]?.trim() || 'unknown';
  const xri = request.headers.get('X-Real-IP');
  if (xri) return xri;
  return 'unknown';
}

function randomId(length: number) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  let out = '';
  for (let i = 0; i < length; i += 1) {
    out += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return out;
}

async function checkRateLimit(env: Env, ip: string) {
  const stub = env.SOS_RATE.get(env.SOS_RATE.idFromName('global'));
  const response = await stub.fetch('https://rate/check', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ip })
  });
  if (!response.ok) {
    return { allowed: true, retry_after: 0 };
  }
  return response.json() as Promise<{ allowed: boolean; retry_after: number }>;
}

async function resetRateLimit(env: Env, ip: string) {
  const stub = env.SOS_RATE.get(env.SOS_RATE.idFromName('global'));
  await stub.fetch('https://rate/reset', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ip })
  });
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    if (url.pathname === '/health') {
      return jsonResponse({ status: 'ok', timestamp: Date.now() });
    }

    if (url.pathname === '/') {
      return textResponse('SOS Chat relay is running.');
    }

    if (url.pathname === '/room' && request.method === 'POST') {
      const ip = getClientIp(request);
      const rate = await checkRateLimit(env, ip);
      if (!rate.allowed) {
        return jsonResponse({ error: 'rate_limited', retry_after: rate.retry_after }, 429);
      }

      const data = await readJson(request);
      if (!data || typeof data.room_hash !== 'string' || data.room_hash.length !== 16) {
        return jsonResponse({ error: 'invalid_room_hash' }, 400);
      }

      const roomHash = data.room_hash;
      const stub = env.SOS_ROOM.get(env.SOS_ROOM.idFromName(roomHash));
      const response = await stub.fetch(`https://room/room/${roomHash}/create`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ room_hash: roomHash, mode: 'fixed' })
      });

      const payload = await response.text();
      return new Response(payload, {
        status: response.status,
        headers: { 'Content-Type': 'application/json', ...corsHeaders }
      });
    }

    if (url.pathname.startsWith('/room/')) {
      const parts = url.pathname.split('/').filter(Boolean);
      const roomHash = parts[1];

      if (!roomHash || roomHash.length !== 16) {
        return jsonResponse({ error: 'invalid_room_hash' }, 400);
      }

      const stub = env.SOS_ROOM.get(env.SOS_ROOM.idFromName(roomHash));
      const forward = new Request(url.toString(), request);
      const response = await stub.fetch(forward);

      if (parts[2] === 'join' && response.ok) {
        const ip = getClientIp(request);
        ctx.waitUntil(resetRateLimit(env, ip));
      }

      const payload = await response.text();
      return new Response(payload, {
        status: response.status,
        headers: { 'Content-Type': 'application/json', ...corsHeaders }
      });
    }

    return jsonResponse({ error: 'not_found' }, 404);
  }
};

export class SOSRoom {
  private state: DurableObjectState;

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const parts = url.pathname.split('/').filter(Boolean);

    if (parts[0] !== 'room' || parts.length < 2) {
      return jsonResponse({ error: 'not_found' }, 404);
    }

    const roomHash = parts[1];
    const action = parts[2] || '';

    if (action === 'create' && request.method === 'POST') {
      return this.handleCreate(roomHash, request);
    }

    if (action === 'join' && request.method === 'POST') {
      return this.handleJoin(roomHash, request);
    }

    if (action === 'send' && request.method === 'POST') {
      return this.handleSend(roomHash, request);
    }

    if (action === 'poll' && request.method === 'GET') {
      return this.handlePoll(roomHash, url);
    }

    if (action === 'leave' && request.method === 'POST') {
      return this.handleLeave(roomHash, request);
    }

    if (action === 'info' && request.method === 'GET') {
      return this.handleInfo(roomHash);
    }

    return jsonResponse({ error: 'not_found' }, 404);
  }

  private async getRoom(): Promise<RoomData | null> {
    const room = await this.state.storage.get<RoomData>('room');
    if (!room) return null;
    if (nowSeconds() > room.expires_at) {
      await this.state.storage.delete('room');
      return null;
    }
    return room;
  }

  private async saveRoom(room: RoomData) {
    await this.state.storage.put('room', room);
  }

  private async handleCreate(roomHash: string, request: Request): Promise<Response> {
    const existing = await this.getRoom();
    if (existing) {
      return jsonResponse({ error: 'room_exists' }, 409);
    }

    const data = await readJson(request);
    if (!data || data.room_hash !== roomHash) {
      return jsonResponse({ error: 'invalid_room_hash' }, 400);
    }

    const now = nowSeconds();
    const memberId = randomId(8);

    const room: RoomData = {
      room_hash: roomHash,
      mode: 'fixed',
      created_at: now,
      expires_at: now + ROOM_TTL_SECONDS,
      members: { [memberId]: 'creator' },
      messages: []
    };

    await this.saveRoom(room);

    return jsonResponse({
      room_hash: room.room_hash,
      mode: room.mode,
      created_at: room.created_at,
      expires_at: room.expires_at,
      member_id: memberId,
      members: Object.values(room.members)
    });
  }

  private async handleJoin(roomHash: string, request: Request): Promise<Response> {
    const room = await this.getRoom();
    if (!room || room.room_hash !== roomHash) {
      return jsonResponse({ error: 'room_not_found' }, 404);
    }

    const data = await readJson(request);
    const nickname = (data?.nickname || 'anon').toString().slice(0, 20);

    const memberId = randomId(8);
    room.members[memberId] = nickname;

    await this.saveRoom(room);

    const lastMessage = room.messages[room.messages.length - 1];

    return jsonResponse({
      room_hash: room.room_hash,
      mode: room.mode,
      created_at: room.created_at,
      expires_at: room.expires_at,
      member_id: memberId,
      members: Object.values(room.members),
      message_count: room.messages.length,
      last_message_ts: lastMessage ? lastMessage.timestamp : 0
    });
  }

  private async handleSend(roomHash: string, request: Request): Promise<Response> {
    const room = await this.getRoom();
    if (!room || room.room_hash !== roomHash) {
      return jsonResponse({ error: 'room_not_found' }, 404);
    }

    const data = await readJson(request);
    if (!data || !data.content) {
      return jsonResponse({ error: 'missing_content' }, 400);
    }

    const memberId = data.member_id;
    let sender = data.sender || 'anon';

    if (memberId && room.members[memberId]) {
      sender = room.members[memberId];
    }

    const msg = {
      id: randomId(12),
      sender: sender.toString(),
      content: data.content.toString(),
      timestamp: nowSeconds()
    };

    room.messages.push(msg);
    if (room.messages.length > MAX_MESSAGES) {
      room.messages = room.messages.slice(-MAX_MESSAGES);
    }

    await this.saveRoom(room);

    return jsonResponse({ id: msg.id, timestamp: msg.timestamp });
  }

  private async handlePoll(roomHash: string, url: URL): Promise<Response> {
    const room = await this.getRoom();
    if (!room || room.room_hash !== roomHash) {
      return jsonResponse({ error: 'room_not_found' }, 404);
    }

    const since = parseFloat(url.searchParams.get('since') || '0');
    const messages = room.messages.filter((msg) => msg.timestamp > since);

    return jsonResponse({
      messages,
      members: Object.values(room.members),
      expires_at: room.expires_at,
      message_count: room.messages.length
    });
  }

  private async handleLeave(roomHash: string, request: Request): Promise<Response> {
    const room = await this.getRoom();
    if (!room || room.room_hash !== roomHash) {
      return jsonResponse({ error: 'room_not_found' }, 404);
    }

    const data = await readJson(request);
    const memberId = data?.member_id;

    if (memberId && room.members[memberId]) {
      delete room.members[memberId];
      await this.saveRoom(room);
    }

    return jsonResponse({ status: 'left' });
  }

  private async handleInfo(roomHash: string): Promise<Response> {
    const room = await this.getRoom();
    if (!room || room.room_hash !== roomHash) {
      return jsonResponse({ error: 'room_not_found' }, 404);
    }

    const timeRemaining = Math.max(0, Math.floor(room.expires_at - nowSeconds()));

    return jsonResponse({
      room_hash: room.room_hash,
      mode: room.mode,
      created_at: room.created_at,
      expires_at: room.expires_at,
      members: Object.values(room.members),
      message_count: room.messages.length,
      time_remaining: timeRemaining
    });
  }
}

export class SOSRateLimiter {
  private state: DurableObjectState;

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/check' && request.method === 'POST') {
      const data = await readJson(request);
      const ip = data?.ip || 'unknown';
      const result = await this.check(ip.toString());
      return jsonResponse(result);
    }

    if (url.pathname === '/reset' && request.method === 'POST') {
      const data = await readJson(request);
      const ip = data?.ip || 'unknown';
      await this.reset(ip.toString());
      return jsonResponse({ status: 'ok' });
    }

    return jsonResponse({ error: 'not_found' }, 404);
  }

  private async check(ip: string) {
    const key = `ip:${ip}`;
    const entry = await this.state.storage.get<RateEntry>(key);
    const now = nowSeconds();

    if (!entry) {
      await this.state.storage.put(key, { count: 1, last_attempt: now });
      return { allowed: true, retry_after: 0 };
    }

    if (now - entry.last_attempt > RATE_LIMIT_COOLDOWN_SECONDS) {
      await this.state.storage.put(key, { count: 1, last_attempt: now });
      return { allowed: true, retry_after: 0 };
    }

    const delayIndex = Math.min(entry.count, RATE_LIMIT_DELAYS_SECONDS.length - 1);
    const requiredDelay = RATE_LIMIT_DELAYS_SECONDS[delayIndex];
    const elapsed = now - entry.last_attempt;

    if (elapsed >= requiredDelay) {
      await this.state.storage.put(key, { count: entry.count + 1, last_attempt: now });
      return { allowed: true, retry_after: 0 };
    }

    return { allowed: false, retry_after: Math.ceil(requiredDelay - elapsed) };
  }

  private async reset(ip: string) {
    const key = `ip:${ip}`;
    await this.state.storage.delete(key);
  }
}
