const ROOM_TTL_SECONDS = 3600;
const MAX_MESSAGES = 500;
const RATE_LIMIT_COOLDOWN_SECONDS = 1800;
const RATE_LIMIT_DELAYS_SECONDS = [0, 10, 30, 60, 180, 300];
const GOSSIP_INTERVAL_SECONDS = 30;
const WORKER_FAIL_LIMIT = 5;
const MAX_GOSSIP_WORKERS = 200;
const MAX_GOSSIP_ROOMS = 200;
const GENESIS_WORKERS = ['https://dnscloak-sos-chat.pouriashy11.workers.dev'];

interface Env {
  SOS_ROOM: DurableObjectNamespace;
  SOS_RATE: DurableObjectNamespace;
  SOS_DIRECTORY: DurableObjectNamespace;
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

type WorkerEntry = {
  url: string;
  last_seen: number;
  last_ok: number;
  fail_count: number;
  is_genesis?: boolean;
};

type RoomEntry = {
  room_hash: string;
  emojis?: string[];
  description?: string;
  created_at: number;
  expires_at: number;
  worker: string;
};

type GossipPayload = {
  from: string;
  workers?: string[];
  rooms?: RoomEntry[];
  timestamp?: number;
};

type DirectoryState = {
  version: number;
  updated_at: number;
  workers_count: number;
  rooms_count: number;
  last_gossip_at: number;
};

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Max-Age': '3600'
};

function nowSeconds() {
  return Date.now() / 1000;
}

function getOrigin(request: Request) {
  try {
    return new URL(request.url).origin;
  } catch {
    return '';
  }
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

function directoryStub(env: Env) {
  return env.SOS_DIRECTORY.get(env.SOS_DIRECTORY.idFromName('global'));
}

async function ensureDirectory(env: Env, origin: string) {
  if (!origin) return;
  const stub = directoryStub(env);
  await stub.fetch('https://directory/ensure', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ self: origin, genesis: GENESIS_WORKERS })
  });
}

async function triggerGossip(env: Env, origin: string) {
  if (!origin) return;
  const stub = directoryStub(env);
  await stub.fetch('https://directory/tick', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ self: origin })
  });
}

async function registerRoomDirectory(
  env: Env,
  room: { room_hash: string; created_at: number; expires_at: number; emojis?: string[]; description?: string },
  workerUrl: string
) {
  const stub = directoryStub(env);
  await stub.fetch('https://directory/rooms/register', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ...room, worker: workerUrl })
  });
}

async function resolveRoomOwner(env: Env, roomHash: string) {
  try {
    const stub = directoryStub(env);
    const response = await stub.fetch(`https://directory/rooms/resolve?room_hash=${encodeURIComponent(roomHash)}`);
    if (!response.ok) return null;
    return (await response.json()) as { worker: string | null };
  } catch {
    return null;
  }
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
    const origin = getOrigin(request);

    ctx.waitUntil(ensureDirectory(env, origin));
    ctx.waitUntil(triggerGossip(env, origin));

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    if (url.pathname === '/health') {
      return jsonResponse({ status: 'ok', timestamp: Date.now() });
    }

    if (url.pathname === '/') {
      return textResponse('SOS Chat relay is running.');
    }

    if (url.pathname === '/workers' && request.method === 'GET') {
      const stub = directoryStub(env);
      const response = await stub.fetch('https://directory/workers');
      const payload = await response.text();
      return new Response(payload, {
        status: response.status,
        headers: { 'Content-Type': 'application/json', ...corsHeaders }
      });
    }

    if (url.pathname === '/rooms' && request.method === 'GET') {
      const stub = directoryStub(env);
      const response = await stub.fetch('https://directory/rooms');
      const payload = await response.text();
      return new Response(payload, {
        status: response.status,
        headers: { 'Content-Type': 'application/json', ...corsHeaders }
      });
    }

    if (url.pathname === '/gossip' && request.method === 'POST') {
      const stub = directoryStub(env);
      const response = await stub.fetch('https://directory/gossip', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(await readJson(request))
      });
      const payload = await response.text();
      return new Response(payload, {
        status: response.status,
        headers: { 'Content-Type': 'application/json', ...corsHeaders }
      });
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
      const emojis = Array.isArray(data.emojis) ? data.emojis.map((e: unknown) => String(e)).slice(0, 6) : undefined;
      const description = typeof data.description === 'string' ? data.description.trim().slice(0, 140) : undefined;
      const stub = env.SOS_ROOM.get(env.SOS_ROOM.idFromName(roomHash));
      const response = await stub.fetch(`https://room/room/${roomHash}/create`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ room_hash: roomHash, mode: 'fixed', nickname: data?.nickname })
      });

      const payload = await response.text();
      if (response.ok) {
        try {
          const parsed = JSON.parse(payload) as { room_hash: string; created_at: number; expires_at: number };
          ctx.waitUntil(
            registerRoomDirectory(
              env,
              {
                room_hash: parsed.room_hash,
                created_at: parsed.created_at,
                expires_at: parsed.expires_at,
                emojis,
                description
              },
              origin
            )
          );
        } catch {
          // ignore directory update failures
        }
      }
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

      if (origin) {
        const resolved = await resolveRoomOwner(env, roomHash);
        if (resolved?.worker && resolved.worker !== origin) {
          const proxyUrl = `${resolved.worker}${url.pathname}${url.search}`;
          const proxyResponse = await fetch(proxyUrl, request);
          if (parts[2] === 'join' && proxyResponse.ok) {
            const ip = getClientIp(request);
            ctx.waitUntil(resetRateLimit(env, ip));
          }
          const proxyPayload = await proxyResponse.text();
          return new Response(proxyPayload, {
            status: proxyResponse.status,
            headers: { 'Content-Type': 'application/json', ...corsHeaders }
          });
        }
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
    const nickname = (data?.nickname || 'creator').toString().slice(0, 20);

    const room: RoomData = {
      room_hash: roomHash,
      mode: 'fixed',
      created_at: now,
      expires_at: now + ROOM_TTL_SECONDS,
      members: { [memberId]: nickname },
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

export class SOSDirectory {
  private state: DurableObjectState;

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/ensure' && request.method === 'POST') {
      const data = await readJson(request);
      const selfUrl = typeof data?.self === 'string' ? data.self : '';
      const genesis = Array.isArray(data?.genesis) ? data.genesis : [];
      await this.ensure(selfUrl, genesis);
      return jsonResponse({ status: 'ok' });
    }

    if (url.pathname === '/tick' && request.method === 'POST') {
      const data = await readJson(request);
      const selfUrl = typeof data?.self === 'string' ? data.self : '';
      await this.tick(selfUrl);
      return jsonResponse({ status: 'ok' });
    }

    if (url.pathname === '/gossip' && request.method === 'POST') {
      const payload = (await readJson(request)) as GossipPayload | null;
      if (!payload || typeof payload.from !== 'string') {
        return jsonResponse({ error: 'invalid_gossip' }, 400);
      }
      await this.ingestGossip(payload);
      return jsonResponse({ status: 'ok' });
    }

    if (url.pathname === '/workers' && request.method === 'GET') {
      const workers = await this.getWorkers();
      return jsonResponse({ workers });
    }

    if (url.pathname === '/rooms' && request.method === 'GET') {
      const rooms = await this.getRooms();
      return jsonResponse({ rooms });
    }

    if (url.pathname === '/rooms/register' && request.method === 'POST') {
      const data = await readJson(request);
      if (!data || typeof data.room_hash !== 'string' || typeof data.worker !== 'string') {
        return jsonResponse({ error: 'invalid_room' }, 400);
      }
      const entry: RoomEntry = {
        room_hash: data.room_hash,
        emojis: Array.isArray(data.emojis) ? data.emojis.map((e: unknown) => String(e)).slice(0, 6) : undefined,
        description: typeof data.description === 'string' ? data.description.trim().slice(0, 140) : undefined,
        created_at: Number(data.created_at || nowSeconds()),
        expires_at: Number(data.expires_at || nowSeconds() + ROOM_TTL_SECONDS),
        worker: data.worker
      };
      await this.saveRoom(entry);
      return jsonResponse({ status: 'ok' });
    }

    if (url.pathname === '/rooms/resolve' && request.method === 'GET') {
      const roomHash = url.searchParams.get('room_hash');
      if (!roomHash) return jsonResponse({ worker: null });
      const room = await this.getRoom(roomHash);
      return jsonResponse({ worker: room?.worker ?? null });
    }

    return jsonResponse({ error: 'not_found' }, 404);
  }

  private async loadWorkers(): Promise<Record<string, WorkerEntry>> {
    return (await this.state.storage.get<Record<string, WorkerEntry>>('workers')) || {};
  }

  private async saveWorkers(workers: Record<string, WorkerEntry>) {
    await this.state.storage.put('workers', workers);
  }

  private async loadRooms(): Promise<Record<string, RoomEntry>> {
    return (await this.state.storage.get<Record<string, RoomEntry>>('rooms')) || {};
  }

  private async loadGenesis(): Promise<string[]> {
    return (await this.state.storage.get<string[]>('genesis')) || [];
  }

  private async saveGenesis(genesis: string[]) {
    await this.state.storage.put('genesis', genesis);
  }

  private isGenesis(url: string, genesis: string[]) {
    return genesis.includes(url);
  }

  private async saveRooms(rooms: Record<string, RoomEntry>) {
    await this.state.storage.put('rooms', rooms);
    await this.updateState(undefined, rooms);
  }

  private async ensure(selfUrl: string, genesis: string[]) {
    const workers = await this.loadWorkers();
    const genesisList = genesis.map((entry) => String(entry || '').trim()).filter(Boolean);
    await this.saveGenesis(genesisList);
    const now = nowSeconds();

    for (const url of genesisList) {
      const normalized = String(url || '').trim();
      if (!normalized) continue;
      if (!workers[normalized]) {
        workers[normalized] = { url: normalized, last_seen: now, last_ok: 0, fail_count: 0, is_genesis: true };
      } else {
        workers[normalized].is_genesis = true;
      }
    }

    if (selfUrl) {
      const current = workers[selfUrl];
      workers[selfUrl] = {
        url: selfUrl,
        last_seen: now,
        last_ok: current?.last_ok || now,
        fail_count: current?.fail_count || 0,
        is_genesis: current?.is_genesis || this.isGenesis(selfUrl, genesisList)
      };
    }

    await this.saveWorkers(workers);
    await this.updateState(workers, undefined);
  }

  private async tick(selfUrl: string) {
    const now = nowSeconds();
    const last = (await this.state.storage.get<number>('last_gossip')) || 0;
    if (now - last < GOSSIP_INTERVAL_SECONDS) return;
    await this.state.storage.put('last_gossip', now);

    const workers = await this.loadWorkers();
    const rooms = await this.loadRooms();
    const payload = this.buildGossipPayload(selfUrl, workers, rooms);

    for (const [url, entry] of Object.entries(workers)) {
      if (!url || url === selfUrl) continue;
      const ok = await this.sendGossip(url, payload);
      const updated = workers[url];
      if (!updated) continue;
      if (ok) {
        updated.fail_count = 0;
        updated.last_ok = now;
        updated.last_seen = now;
      } else {
        updated.fail_count += 1;
        updated.last_seen = now;
        if (updated.fail_count >= WORKER_FAIL_LIMIT) {
          delete workers[url];
        }
      }
    }

    await this.pruneRooms(rooms);
    await this.saveWorkers(workers);
    await this.saveRooms(rooms);
    await this.updateState(workers, rooms, now);
  }

  private buildGossipPayload(selfUrl: string, workers: Record<string, WorkerEntry>, rooms: Record<string, RoomEntry>): GossipPayload {
    const workerUrls = Object.keys(workers).slice(0, MAX_GOSSIP_WORKERS);
    const roomList = Object.values(rooms)
      .filter((room) => room.expires_at > nowSeconds())
      .sort((a, b) => b.created_at - a.created_at)
      .slice(0, MAX_GOSSIP_ROOMS);

    return {
      from: selfUrl,
      workers: workerUrls,
      rooms: roomList,
      timestamp: Date.now()
    };
  }

  private async sendGossip(target: string, payload: GossipPayload) {
    try {
      const response = await fetch(`${target}/gossip`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      return response.ok;
    } catch {
      return false;
    }
  }

  private async ingestGossip(payload: GossipPayload) {
    const workers = await this.loadWorkers();
    const rooms = await this.loadRooms();
    const genesis = await this.loadGenesis();
    const now = nowSeconds();

    const touchWorker = (url: string) => {
      const normalized = String(url || '').trim();
      if (!normalized) return;
      const existing = workers[normalized];
      workers[normalized] = {
        url: normalized,
        last_seen: now,
        last_ok: existing?.last_ok || now,
        fail_count: existing?.fail_count || 0,
        is_genesis: existing?.is_genesis || this.isGenesis(normalized, genesis)
      };
    };

    touchWorker(payload.from);
    for (const url of payload.workers || []) {
      touchWorker(url);
    }

    if (payload.rooms) {
      for (const incoming of payload.rooms) {
        if (!incoming || !incoming.room_hash) continue;
        if (incoming.expires_at <= now) continue;
        const existing = rooms[incoming.room_hash];
        if (!existing || incoming.expires_at > existing.expires_at) {
          rooms[incoming.room_hash] = {
            room_hash: incoming.room_hash,
            emojis: incoming.emojis?.slice(0, 6),
            description: incoming.description?.slice(0, 140),
            created_at: incoming.created_at,
            expires_at: incoming.expires_at,
            worker: incoming.worker
          };
        }
      }
    }

    await this.pruneRooms(rooms);
    await this.saveWorkers(workers);
    await this.saveRooms(rooms);
    await this.updateState(workers, rooms);
  }

  private async pruneRooms(rooms: Record<string, RoomEntry>) {
    const now = nowSeconds();
    for (const [hash, room] of Object.entries(rooms)) {
      if (room.expires_at <= now) {
        delete rooms[hash];
      }
    }
  }

  private async getWorkers() {
    const workers = await this.loadWorkers();
    const genesis = await this.loadGenesis();
    await this.updateState(workers, undefined);
    return Object.values(workers).map((entry) => ({
      ...entry,
      is_genesis: entry.is_genesis || this.isGenesis(entry.url, genesis)
    }));
  }

  private async getRooms() {
    const rooms = await this.loadRooms();
    await this.pruneRooms(rooms);
    await this.saveRooms(rooms);
    return Object.values(rooms).sort((a, b) => a.expires_at - b.expires_at);
  }

  private async saveRoom(room: RoomEntry) {
    const rooms = await this.loadRooms();
    rooms[room.room_hash] = room;
    await this.saveRooms(rooms);
  }

  private async getRoom(roomHash: string) {
    const rooms = await this.loadRooms();
    const room = rooms[roomHash];
    if (!room) return null;
    if (room.expires_at <= nowSeconds()) {
      delete rooms[roomHash];
      await this.saveRooms(rooms);
      return null;
    }
    return room;
  }

  private async updateState(
    workers?: Record<string, WorkerEntry>,
    rooms?: Record<string, RoomEntry>,
    lastGossipAt?: number
  ) {
    const existing = (await this.state.storage.get<DirectoryState>('directory_state')) || {
      version: 1,
      updated_at: nowSeconds(),
      workers_count: 0,
      rooms_count: 0,
      last_gossip_at: 0
    };

    const next: DirectoryState = {
      version: existing.version,
      updated_at: nowSeconds(),
      workers_count: workers ? Object.keys(workers).length : existing.workers_count,
      rooms_count: rooms ? Object.keys(rooms).length : existing.rooms_count,
      last_gossip_at: typeof lastGossipAt === 'number' ? lastGossipAt : existing.last_gossip_at
    };

    await this.state.storage.put('directory_state', next);
  }
}
