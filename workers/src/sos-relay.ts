/**
 * SOS Emergency Chat - Cloudflare Durable Object Relay
 *
 * Implements the full SOS relay API using SQLite-backed Durable Object storage.
 * Rooms auto-expire after 1 hour, max 500 messages per room.
 *
 * API endpoints (all under vany.sh/sos):
 *   GET  /            → web client (index.html, served from GitHub Raw)
 *   GET  /app.js      → web client JS (served from GitHub Raw)
 *   GET  /health      → relay health + room count
 *   POST /room        → create room
 *   POST /room/:h/join   → join room
 *   POST /room/:h/send   → send message
 *   GET  /room/:h/poll   → poll messages
 *   POST /room/:h/leave  → leave room
 *   GET  /room/:h/info   → room metadata
 */

const ROOM_TTL = 3600;      // 1 hour in seconds
const MAX_MESSAGES = 500;   // per room

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Max-Age': '3600',
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

function randomId(len = 8): string {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  let id = '';
  const bytes = crypto.getRandomValues(new Uint8Array(len));
  for (const b of bytes) id += chars[b % chars.length];
  return id;
}

// ---------------------------------------------------------------------------
// Durable Object
// ---------------------------------------------------------------------------

export class SosRelay {
  private sql: SqlStorage;

  constructor(readonly state: DurableObjectState) {
    this.sql = state.storage.sql;
    this.initSchema();
  }

  // -------------------------------------------------------------------------
  // Schema
  // -------------------------------------------------------------------------
  private initSchema(): void {
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS rooms (
        room_hash  TEXT PRIMARY KEY,
        mode       TEXT NOT NULL,
        created_at REAL NOT NULL,
        expires_at REAL NOT NULL
      );

      CREATE TABLE IF NOT EXISTS members (
        room_hash TEXT NOT NULL,
        member_id TEXT NOT NULL,
        nickname  TEXT NOT NULL,
        PRIMARY KEY (room_hash, member_id)
      );

      CREATE TABLE IF NOT EXISTS messages (
        id        TEXT NOT NULL,
        room_hash TEXT NOT NULL,
        sender    TEXT NOT NULL,
        content   TEXT NOT NULL,
        ts        REAL NOT NULL,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS idx_messages_room_ts
        ON messages (room_hash, ts);
    `);
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  private now(): number {
    return Date.now() / 1000;
  }

  private isAlive(expiresAt: number): boolean {
    return this.now() < expiresAt;
  }

  private getRoom(roomHash: string): { room_hash: string; mode: string; created_at: number; expires_at: number } | null {
    const rows = [...this.sql.exec(
      'SELECT room_hash, mode, created_at, expires_at FROM rooms WHERE room_hash = ?',
      roomHash,
    )];
    if (!rows.length) return null;
    const r = rows[0] as { room_hash: string; mode: string; created_at: number; expires_at: number };
    if (!this.isAlive(r.expires_at)) {
      this.deleteRoom(roomHash);
      return null;
    }
    return r;
  }

  private getMembers(roomHash: string): { member_id: string; nickname: string }[] {
    return [...this.sql.exec(
      'SELECT member_id, nickname FROM members WHERE room_hash = ?',
      roomHash,
    )] as { member_id: string; nickname: string }[];
  }

  private getMemberNicknames(roomHash: string): string[] {
    return this.getMembers(roomHash).map(m => m.nickname);
  }

  private deleteRoom(roomHash: string): void {
    this.sql.exec('DELETE FROM messages WHERE room_hash = ?', roomHash);
    this.sql.exec('DELETE FROM members WHERE room_hash = ?', roomHash);
    this.sql.exec('DELETE FROM rooms WHERE room_hash = ?', roomHash);
  }

  private pruneExpiredRooms(): void {
    const expired = [...this.sql.exec(
      'SELECT room_hash FROM rooms WHERE expires_at < ?',
      this.now(),
    )] as { room_hash: string }[];
    for (const { room_hash } of expired) this.deleteRoom(room_hash);
  }

  // -------------------------------------------------------------------------
  // Fetch handler (entry point)
  // -------------------------------------------------------------------------
  async fetch(request: Request): Promise<Response> {
    // Prune on every request (cheap; SQLite is fast for small tables)
    this.pruneExpiredRooms();

    const url = new URL(request.url);
    const path = url.pathname;

    // OPTIONS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }

    // Health
    if (path === '/health' && request.method === 'GET') {
      const [row] = [...this.sql.exec('SELECT COUNT(*) as n FROM rooms')] as { n: number }[];
      return json({ status: 'ok', rooms: row.n, timestamp: this.now() });
    }

    // POST /room  →  create
    if (path === '/room' && request.method === 'POST') {
      return this.handleCreateRoom(request);
    }

    // /room/:hash/**
    const roomMatch = path.match(/^\/room\/([a-f0-9]{16})(\/.*)?$/);
    if (roomMatch) {
      const roomHash = roomMatch[1];
      const sub = roomMatch[2] ?? '';

      if (sub === '/join' && request.method === 'POST')   return this.handleJoin(request, roomHash);
      if (sub === '/send' && request.method === 'POST')   return this.handleSend(request, roomHash);
      if (sub === '/poll' && request.method === 'GET')    return this.handlePoll(request, roomHash, url);
      if (sub === '/leave' && request.method === 'POST')  return this.handleLeave(request, roomHash);
      if (sub === '/info' && request.method === 'GET')    return this.handleInfo(roomHash);
    }

    return new Response('Not found', { status: 404, headers: CORS_HEADERS });
  }

  // -------------------------------------------------------------------------
  // POST /room
  // -------------------------------------------------------------------------
  private async handleCreateRoom(request: Request): Promise<Response> {
    let body: { room_hash?: string; mode?: string };
    try { body = await request.json(); } catch { return json({ error: 'invalid_json' }, 400); }

    const { room_hash, mode = 'rotating' } = body;

    if (!room_hash || !/^[a-f0-9]{16}$/.test(room_hash)) {
      return json({ error: 'invalid_room_hash' }, 400);
    }
    if (mode !== 'rotating' && mode !== 'fixed') {
      return json({ error: 'invalid_mode' }, 400);
    }

    // Already exists?
    if (this.getRoom(room_hash)) {
      return json({ error: 'room_exists' }, 409);
    }

    const now = this.now();
    const expiresAt = now + ROOM_TTL;
    const memberId = randomId(8);

    this.sql.exec(
      'INSERT INTO rooms (room_hash, mode, created_at, expires_at) VALUES (?, ?, ?, ?)',
      room_hash, mode, now, expiresAt,
    );
    this.sql.exec(
      'INSERT INTO members (room_hash, member_id, nickname) VALUES (?, ?, ?)',
      room_hash, memberId, 'creator',
    );

    return json({
      room_hash,
      mode,
      created_at: now,
      expires_at: expiresAt,
      member_id: memberId,
      members: ['creator'],
    });
  }

  // -------------------------------------------------------------------------
  // POST /room/:hash/join
  // -------------------------------------------------------------------------
  private async handleJoin(request: Request, roomHash: string): Promise<Response> {
    const room = this.getRoom(roomHash);
    if (!room) return json({ error: 'room_not_found' }, 404);

    let body: { nickname?: string } = {};
    try { body = await request.json(); } catch { /* nickname optional */ }

    const nickname = (body.nickname ?? 'anon').slice(0, 20);
    const memberId = randomId(8);

    this.sql.exec(
      'INSERT INTO members (room_hash, member_id, nickname) VALUES (?, ?, ?)',
      roomHash, memberId, nickname,
    );

    const lastMsgRow = [...this.sql.exec(
      'SELECT ts FROM messages WHERE room_hash = ? ORDER BY ts DESC LIMIT 1',
      roomHash,
    )] as { ts: number }[];
    const lastTs = lastMsgRow.length ? lastMsgRow[0].ts : 0;

    const [countRow] = [...this.sql.exec(
      'SELECT COUNT(*) as n FROM messages WHERE room_hash = ?', roomHash,
    )] as { n: number }[];

    return json({
      room_hash: roomHash,
      mode: room.mode,
      created_at: room.created_at,
      expires_at: room.expires_at,
      member_id: memberId,
      members: this.getMemberNicknames(roomHash),
      message_count: countRow.n,
      last_message_ts: lastTs,
    });
  }

  // -------------------------------------------------------------------------
  // POST /room/:hash/send
  // -------------------------------------------------------------------------
  private async handleSend(request: Request, roomHash: string): Promise<Response> {
    const room = this.getRoom(roomHash);
    if (!room) return json({ error: 'room_not_found' }, 404);

    let body: { content?: string; sender?: string; member_id?: string };
    try { body = await request.json(); } catch { return json({ error: 'invalid_json' }, 400); }

    const { content, member_id } = body;
    if (!content) return json({ error: 'missing_content' }, 400);

    // Resolve sender from member_id
    let sender = body.sender ?? 'anon';
    if (member_id) {
      const rows = [...this.sql.exec(
        'SELECT nickname FROM members WHERE room_hash = ? AND member_id = ?',
        roomHash, member_id,
      )] as { nickname: string }[];
      if (rows.length) sender = rows[0].nickname;
    }

    const msgId = randomId(12);
    const ts = this.now();

    this.sql.exec(
      'INSERT INTO messages (id, room_hash, sender, content, ts) VALUES (?, ?, ?, ?, ?)',
      msgId, roomHash, sender, content, ts,
    );

    // Trim to MAX_MESSAGES (keep newest)
    const [countRow] = [...this.sql.exec(
      'SELECT COUNT(*) as n FROM messages WHERE room_hash = ?', roomHash,
    )] as { n: number }[];
    if (countRow.n > MAX_MESSAGES) {
      this.sql.exec(`
        DELETE FROM messages
        WHERE room_hash = ?
          AND id NOT IN (
            SELECT id FROM messages WHERE room_hash = ?
            ORDER BY ts DESC LIMIT ?
          )
      `, roomHash, roomHash, MAX_MESSAGES);
    }

    return json({ id: msgId, timestamp: ts });
  }

  // -------------------------------------------------------------------------
  // GET /room/:hash/poll?since=&member_id=
  // -------------------------------------------------------------------------
  private handlePoll(request: Request, roomHash: string, url: URL): Response {
    const room = this.getRoom(roomHash);
    if (!room) return json({ error: 'room_not_found' }, 404);

    const since = parseFloat(url.searchParams.get('since') ?? '0') || 0;

    const messages = [...this.sql.exec(
      'SELECT id, sender, content, ts as timestamp FROM messages WHERE room_hash = ? AND ts > ? ORDER BY ts ASC',
      roomHash, since,
    )] as { id: string; sender: string; content: string; timestamp: number }[];

    const [countRow] = [...this.sql.exec(
      'SELECT COUNT(*) as n FROM messages WHERE room_hash = ?', roomHash,
    )] as { n: number }[];

    return json({
      messages,
      members: this.getMemberNicknames(roomHash),
      expires_at: room.expires_at,
      message_count: countRow.n,
    });
  }

  // -------------------------------------------------------------------------
  // POST /room/:hash/leave
  // -------------------------------------------------------------------------
  private async handleLeave(request: Request, roomHash: string): Promise<Response> {
    const room = this.getRoom(roomHash);
    if (!room) return json({ error: 'room_not_found' }, 404);

    let body: { member_id?: string } = {};
    try { body = await request.json(); } catch { /* ok */ }

    if (body.member_id) {
      this.sql.exec(
        'DELETE FROM members WHERE room_hash = ? AND member_id = ?',
        roomHash, body.member_id,
      );
    }

    return json({ status: 'left' });
  }

  // -------------------------------------------------------------------------
  // GET /room/:hash/info
  // -------------------------------------------------------------------------
  private handleInfo(roomHash: string): Response {
    const room = this.getRoom(roomHash);
    if (!room) return json({ error: 'room_not_found' }, 404);

    const [countRow] = [...this.sql.exec(
      'SELECT COUNT(*) as n FROM messages WHERE room_hash = ?', roomHash,
    )] as { n: number }[];

    return json({
      room_hash: roomHash,
      mode: room.mode,
      created_at: room.created_at,
      expires_at: room.expires_at,
      members: this.getMemberNicknames(roomHash),
      message_count: countRow.n,
      time_remaining: Math.max(0, Math.floor(room.expires_at - this.now())),
    });
  }
}
