"""
SOS Relay - Server-side message relay daemon

Runs on DNSTT server, accessible through SOCKS5 tunnel.
Manages ephemeral chat rooms with:
- Redis storage with 1-hour TTL auto-expiration
- Exponential rate limiting per IP
- Message caching for reconnection
- Web client serving (GET /, /app.js)

Install: Part of DNSTT service with --with-sos flag
Run: systemctl start sos-relay

Web Access: Browse to http://<relay-ip>:8899/ through DNSTT SOCKS5 proxy
"""

import os
import time
import json
import uuid
import hashlib
import asyncio
from pathlib import Path
from typing import Optional
from dataclasses import dataclass, field, asdict

from aiohttp import web


# Static file paths
WWW_DIR = Path(__file__).parent / "www"


# Configuration
REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379")
HOST = os.environ.get("SOS_HOST", "0.0.0.0")
PORT = int(os.environ.get("SOS_PORT", "8899"))
ROOM_TTL = 3600  # 1 hour
MAX_MESSAGES = 500  # Max messages per room
RATE_LIMIT_COOLDOWN = 1800  # 30 min cooldown reset

# Rate limit delays: [0, 10, 30, 60, 180, 300] seconds
RATE_LIMIT_DELAYS = [0, 10, 30, 60, 180, 300]


@dataclass
class RoomData:
    """Room storage structure"""
    room_hash: str
    mode: str  # "rotating" or "fixed"
    created_at: float
    expires_at: float
    members: dict = field(default_factory=dict)  # member_id -> nickname
    messages: list = field(default_factory=list)
    
    def to_dict(self) -> dict:
        return asdict(self)
    
    @classmethod
    def from_dict(cls, data: dict) -> "RoomData":
        return cls(**data)


@dataclass
class MessageData:
    """Message storage structure"""
    id: str
    sender: str
    content: str  # Encrypted, base64
    timestamp: float
    
    def to_dict(self) -> dict:
        return asdict(self)


class RateLimiter:
    """
    Exponential rate limiter per IP.
    Delays: [0, 10, 30, 60, 180, 300] seconds
    Resets after 30 min of no attempts.
    """
    
    def __init__(self):
        self._attempts: dict[str, dict] = {}  # ip -> {count, last_attempt}
    
    def check(self, ip: str) -> tuple[bool, int]:
        """
        Check if IP can proceed.
        Returns (allowed, retry_after_seconds)
        """
        now = time.time()
        
        if ip not in self._attempts:
            self._attempts[ip] = {"count": 0, "last_attempt": now}
            return (True, 0)
        
        data = self._attempts[ip]
        
        # Check cooldown reset
        if now - data["last_attempt"] > RATE_LIMIT_COOLDOWN:
            data["count"] = 0
            data["last_attempt"] = now
            return (True, 0)
        
        # Get required delay
        delay_idx = min(data["count"], len(RATE_LIMIT_DELAYS) - 1)
        required_delay = RATE_LIMIT_DELAYS[delay_idx]
        
        elapsed = now - data["last_attempt"]
        
        if elapsed >= required_delay:
            # Allowed - increment counter
            data["count"] += 1
            data["last_attempt"] = now
            return (True, 0)
        else:
            # Not allowed - return retry_after
            return (False, int(required_delay - elapsed))
    
    def reset(self, ip: str):
        """Reset rate limit for IP (on successful join)"""
        if ip in self._attempts:
            del self._attempts[ip]


class SOSRelay:
    """
    SOS Chat Relay Server
    
    HTTP API endpoints:
    - GET  / - Web client (index.html)
    - GET  /app.js - Web client JavaScript
    - POST /room - Create room
    - POST /room/<hash>/join - Join room
    - POST /room/<hash>/send - Send message
    - GET  /room/<hash>/poll - Poll messages
    - POST /room/<hash>/leave - Leave room
    - GET  /room/<hash>/info - Room info
    - GET  /health - Health check
    """
    
    def __init__(self):
        self.rooms: dict[str, RoomData] = {}
        self.rate_limiter = RateLimiter()
        self._cleanup_task: Optional[asyncio.Task] = None
        self._redis = None  # Optional Redis connection
    
    @staticmethod
    @web.middleware
    async def cors_middleware(request: web.Request, handler):
        """Add CORS headers to all responses for browser access"""
        # Handle preflight OPTIONS requests
        if request.method == 'OPTIONS':
            response = web.Response()
        else:
            response = await handler(request)
        
        # Add CORS headers
        response.headers['Access-Control-Allow-Origin'] = '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
        response.headers['Access-Control-Max-Age'] = '3600'
        
        return response
    
    async def handle_index(self, request: web.Request) -> web.Response:
        """Serve web client index.html"""
        index_path = WWW_DIR / "index.html"
        if index_path.exists():
            return web.Response(
                text=index_path.read_text(encoding='utf-8'),
                content_type='text/html'
            )
        return web.Response(text="SOS Relay - Web client not installed", status=404)
    
    async def handle_app_js(self, request: web.Request) -> web.Response:
        """Serve web client JavaScript"""
        js_path = WWW_DIR / "app.js"
        if js_path.exists():
            return web.Response(
                text=js_path.read_text(encoding='utf-8'),
                content_type='application/javascript'
            )
        return web.Response(text="// app.js not found", content_type='application/javascript', status=404)
    
    async def start(self):
        """Start the relay server"""
        # Try to connect to Redis
        try:
            import aioredis
            self._redis = await aioredis.from_url(REDIS_URL)
            print(f"Connected to Redis at {REDIS_URL}")
        except Exception as e:
            print(f"Redis not available, using in-memory storage: {e}")
            self._redis = None
        
        # Start cleanup task
        self._cleanup_task = asyncio.create_task(self._cleanup_loop())
        
        # Create web app with CORS middleware
        app = web.Application(middlewares=[self.cors_middleware])
        
        # Static web client routes
        app.router.add_get("/", self.handle_index)
        app.router.add_get("/app.js", self.handle_app_js)
        
        # API routes
        app.router.add_get("/health", self.handle_health)
        app.router.add_post("/room", self.handle_create_room)
        app.router.add_post("/room/{room_hash}/join", self.handle_join_room)
        app.router.add_post("/room/{room_hash}/send", self.handle_send_message)
        app.router.add_get("/room/{room_hash}/poll", self.handle_poll)
        app.router.add_post("/room/{room_hash}/leave", self.handle_leave)
        app.router.add_get("/room/{room_hash}/info", self.handle_info)
        
        # OPTIONS handler for CORS preflight
        app.router.add_route('OPTIONS', '/{path:.*}', self._handle_options)
        
        # Start server
        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, HOST, PORT)
        await site.start()
        
        # Log web client availability
        if WWW_DIR.exists():
            print(f"SOS Relay running on http://{HOST}:{PORT}")
            print(f"Web client: http://{HOST}:{PORT}/")
        else:
            print(f"SOS Relay running on http://{HOST}:{PORT} (API only, www/ not found)")
        
        # Keep running
        while True:
            await asyncio.sleep(3600)
    
    async def _cleanup_loop(self):
        """Periodically clean up expired rooms"""
        while True:
            try:
                now = time.time()
                expired = [
                    h for h, r in self.rooms.items()
                    if now > r.expires_at
                ]
                for room_hash in expired:
                    del self.rooms[room_hash]
                    if self._redis:
                        await self._redis.delete(f"room:{room_hash}")
                    print(f"Cleaned up expired room: {room_hash[:8]}...")
                
                await asyncio.sleep(60)  # Check every minute
            except asyncio.CancelledError:
                break
            except Exception as e:
                print(f"Cleanup error: {e}")
                await asyncio.sleep(60)
    
    def _get_client_ip(self, request: web.Request) -> str:
        """Get client IP from request"""
        # Check X-Forwarded-For header first
        xff = request.headers.get("X-Forwarded-For")
        if xff:
            return xff.split(",")[0].strip()
        
        # Check X-Real-IP
        xri = request.headers.get("X-Real-IP")
        if xri:
            return xri
        
        # Fall back to peer
        peername = request.transport.get_extra_info("peername")
        if peername:
            return peername[0]
        
        return "unknown"
    
    async def _get_room(self, room_hash: str) -> Optional[RoomData]:
        """Get room from storage"""
        # Try memory first
        if room_hash in self.rooms:
            room = self.rooms[room_hash]
            if time.time() < room.expires_at:
                return room
            else:
                del self.rooms[room_hash]
                return None
        
        # Try Redis
        if self._redis:
            data = await self._redis.get(f"room:{room_hash}")
            if data:
                room = RoomData.from_dict(json.loads(data))
                if time.time() < room.expires_at:
                    self.rooms[room_hash] = room
                    return room
        
        return None
    
    async def _save_room(self, room: RoomData):
        """Save room to storage"""
        self.rooms[room.room_hash] = room
        
        if self._redis:
            ttl = int(room.expires_at - time.time())
            if ttl > 0:
                await self._redis.setex(
                    f"room:{room.room_hash}",
                    ttl,
                    json.dumps(room.to_dict())
                )
    
    async def handle_health(self, request: web.Request) -> web.Response:
        """Health check endpoint"""
        return web.json_response({
            "status": "ok",
            "rooms": len(self.rooms),
            "timestamp": time.time()
        })
    
    async def handle_create_room(self, request: web.Request) -> web.Response:
        """Create a new room"""
        ip = self._get_client_ip(request)
        
        # Rate limit check
        allowed, retry_after = self.rate_limiter.check(ip)
        if not allowed:
            return web.json_response(
                {"error": "rate_limited", "retry_after": retry_after},
                status=429
            )
        
        try:
            data = await request.json()
        except Exception:
            return web.json_response({"error": "invalid_json"}, status=400)
        
        room_hash = data.get("room_hash")
        mode = "fixed"
        
        if not room_hash or len(room_hash) != 16:
            return web.json_response({"error": "invalid_room_hash"}, status=400)
        
        if mode not in ("fixed",):
            return web.json_response({"error": "invalid_mode"}, status=400)
        
        # Check if room exists
        existing = await self._get_room(room_hash)
        if existing:
            return web.json_response({"error": "room_exists"}, status=409)
        
        # Create room
        now = time.time()
        member_id = str(uuid.uuid4())[:8]
        
        room = RoomData(
            room_hash=room_hash,
            mode=mode,
            created_at=now,
            expires_at=now + ROOM_TTL,
            members={member_id: "creator"},
            messages=[]
        )
        
        await self._save_room(room)
        
        return web.json_response({
            "room_hash": room_hash,
            "mode": mode,
            "created_at": room.created_at,
            "expires_at": room.expires_at,
            "member_id": member_id,
            "members": list(room.members.values())
        })
    
    async def handle_join_room(self, request: web.Request) -> web.Response:
        """Join an existing room"""
        room_hash = request.match_info["room_hash"]
        
        room = await self._get_room(room_hash)
        if not room:
            return web.json_response({"error": "room_not_found"}, status=404)
        
        try:
            data = await request.json()
        except Exception:
            data = {}
        
        nickname = data.get("nickname", "anon")[:20]  # Limit nickname length
        
        # Generate member ID
        member_id = str(uuid.uuid4())[:8]
        room.members[member_id] = nickname
        
        await self._save_room(room)
        
        # Reset rate limit on successful join
        ip = self._get_client_ip(request)
        self.rate_limiter.reset(ip)
        
        return web.json_response({
            "room_hash": room_hash,
            "mode": room.mode,
            "created_at": room.created_at,
            "expires_at": room.expires_at,
            "member_id": member_id,
            "members": list(room.members.values()),
            "message_count": len(room.messages),
            "last_message_ts": room.messages[-1]["timestamp"] if room.messages else 0
        })
    
    async def handle_send_message(self, request: web.Request) -> web.Response:
        """Send a message to the room"""
        room_hash = request.match_info["room_hash"]
        
        room = await self._get_room(room_hash)
        if not room:
            return web.json_response({"error": "room_not_found"}, status=404)
        
        try:
            data = await request.json()
        except Exception:
            return web.json_response({"error": "invalid_json"}, status=400)
        
        content = data.get("content")
        sender = data.get("sender", "anon")
        member_id = data.get("member_id")
        
        if not content:
            return web.json_response({"error": "missing_content"}, status=400)
        
        # Validate member
        if member_id and member_id in room.members:
            sender = room.members[member_id]
        
        # Create message
        msg = MessageData(
            id=str(uuid.uuid4())[:12],
            sender=sender,
            content=content,
            timestamp=time.time()
        )
        
        room.messages.append(msg.to_dict())
        
        # Trim old messages if over limit
        if len(room.messages) > MAX_MESSAGES:
            room.messages = room.messages[-MAX_MESSAGES:]
        
        await self._save_room(room)
        
        return web.json_response({
            "id": msg.id,
            "timestamp": msg.timestamp
        })
    
    async def handle_poll(self, request: web.Request) -> web.Response:
        """Poll for new messages"""
        room_hash = request.match_info["room_hash"]
        
        room = await self._get_room(room_hash)
        if not room:
            return web.json_response({"error": "room_not_found"}, status=404)
        
        since = float(request.query.get("since", 0))
        member_id = request.query.get("member_id")
        
        # Filter messages since timestamp
        messages = [
            m for m in room.messages
            if m["timestamp"] > since
        ]
        
        return web.json_response({
            "messages": messages,
            "members": list(room.members.values()),
            "expires_at": room.expires_at,
            "message_count": len(room.messages)
        })
    
    async def handle_leave(self, request: web.Request) -> web.Response:
        """Leave the room"""
        room_hash = request.match_info["room_hash"]
        
        room = await self._get_room(room_hash)
        if not room:
            return web.json_response({"error": "room_not_found"}, status=404)
        
        try:
            data = await request.json()
        except Exception:
            data = {}
        
        member_id = data.get("member_id")
        
        if member_id and member_id in room.members:
            del room.members[member_id]
            await self._save_room(room)
        
        return web.json_response({"status": "left"})
    
    async def handle_info(self, request: web.Request) -> web.Response:
        """Get room information"""
        room_hash = request.match_info["room_hash"]
        
        room = await self._get_room(room_hash)
        if not room:
            return web.json_response({"error": "room_not_found"}, status=404)
        
        return web.json_response({
            "room_hash": room_hash,
            "mode": room.mode,
            "created_at": room.created_at,
            "expires_at": room.expires_at,
            "members": list(room.members.values()),
            "message_count": len(room.messages),
            "time_remaining": max(0, int(room.expires_at - time.time()))
        })
    
    async def _handle_options(self, request: web.Request) -> web.Response:
        """Handle CORS preflight OPTIONS requests"""
        return web.Response()


async def main():
    """Entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="SOS Relay Server")
    parser.add_argument("--host", default=os.environ.get("SOS_HOST", "0.0.0.0"), 
                        help="Host to bind to (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=int(os.environ.get("SOS_PORT", "8899")),
                        help="Port to listen on (default: 8899)")
    args = parser.parse_args()
    
    # Override globals with CLI args
    global HOST, PORT
    HOST = args.host
    PORT = args.port
    
    relay = SOSRelay()
    await relay.start()


if __name__ == "__main__":
    asyncio.run(main())
