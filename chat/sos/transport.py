"""
SOS Transport - Communication layer over DNSTT SOCKS5 tunnel

Handles:
- HTTP requests through SOCKS5 proxy (DNSTT)
- Polling for new messages (1.5s interval)
- Reconnection with exponential backoff
- Message queue for offline-then-sync
"""

import os
import time
import asyncio
import json
from typing import Optional, Callable, Any
from dataclasses import dataclass, field
from enum import Enum

import httpx


class ConnectionState(Enum):
    DISCONNECTED = "disconnected"
    CONNECTING = "connecting"
    CONNECTED = "connected"
    RECONNECTING = "reconnecting"
    ERROR = "error"


@dataclass
class Message:
    """Chat message structure"""
    id: str
    sender: str
    content: str  # Encrypted content (base64)
    timestamp: float
    
    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "sender": self.sender,
            "content": self.content,
            "timestamp": self.timestamp
        }
    
    @classmethod
    def from_dict(cls, data: dict) -> "Message":
        return cls(
            id=data["id"],
            sender=data["sender"],
            content=data["content"],
            timestamp=data["timestamp"]
        )


@dataclass
class RoomState:
    """Room state from server"""
    room_hash: str
    mode: str
    created_at: float
    expires_at: float
    members: list[str] = field(default_factory=list)
    message_count: int = 0


class SOSTransport:
    """
    Transport layer for SOS chat over DNSTT.
    
    Uses HTTP API through SOCKS5 proxy provided by DNSTT client.
    Falls back to direct connection if SOCKS not available.
    """
    
    # Relay server configuration
    # Default: public relay domain (direct connection when DNSTT unavailable)
    DEFAULT_RELAY = "relay.dnscloak.net:8899"
    _relay_env = os.environ.get("SOS_RELAY_HOST", DEFAULT_RELAY)
    if ":" in _relay_env:
        RELAY_HOST, _port = _relay_env.rsplit(":", 1)
        RELAY_PORT = int(_port)
    else:
        RELAY_HOST = _relay_env
        RELAY_PORT = int(os.environ.get("SOS_RELAY_PORT", "8899"))
    
    # DNSTT SOCKS5 proxy (local)
    SOCKS_HOST = "127.0.0.1"
    SOCKS_PORT = 10800
    
    # Polling interval
    POLL_INTERVAL = 1.5  # seconds
    
    # Reconnection backoff
    BACKOFF_INITIAL = 1.0
    BACKOFF_MAX = 30.0
    BACKOFF_MULTIPLIER = 2.0
    
    def __init__(self):
        self.state = ConnectionState.DISCONNECTED
        self.client: Optional[httpx.AsyncClient] = None
        self.room_hash: Optional[str] = None
        self.member_id: Optional[str] = None
        self.last_message_ts: float = 0
        
        # Callbacks
        self.on_message: Optional[Callable[[Message], Any]] = None
        self.on_state_change: Optional[Callable[[ConnectionState], Any]] = None
        self.on_members_update: Optional[Callable[[list[str]], Any]] = None
        self.on_room_expire: Optional[Callable[[], Any]] = None
        
        # Polling task
        self._poll_task: Optional[asyncio.Task] = None
        self._running = False
        
        # Message queue for offline
        self._pending_messages: list[dict] = []
        
        # Backoff state
        self._backoff = self.BACKOFF_INITIAL
    
    @property
    def base_url(self) -> str:
        return f"http://{self.RELAY_HOST}:{self.RELAY_PORT}"
    
    async def _create_client(self) -> httpx.AsyncClient:
        """Create HTTP client, with SOCKS5 proxy if available"""
        # Check if direct mode is forced (DNSTT not available)
        use_direct = os.environ.get('SOS_USE_DIRECT', '') == '1'
        
        if not use_direct:
            # Try SOCKS5 proxy first (DNSTT tunnel)
            socks_url = f"socks5://{self.SOCKS_HOST}:{self.SOCKS_PORT}"
            
            try:
                client = httpx.AsyncClient(
                    proxy=socks_url,
                    timeout=httpx.Timeout(10.0, connect=5.0)
                )
                await client.get(f"{self.base_url}/health", timeout=3.0)
                return client
            except Exception:
                pass
        
        # Direct connection (no SOCKS proxy)
        return httpx.AsyncClient(
            timeout=httpx.Timeout(10.0, connect=5.0)
        )
    
    def _set_state(self, state: ConnectionState):
        """Update connection state and notify callback"""
        if self.state != state:
            self.state = state
            if self.on_state_change:
                self.on_state_change(state)
    
    async def connect(self) -> bool:
        """Initialize connection to relay"""
        self._set_state(ConnectionState.CONNECTING)
        
        try:
            self.client = await self._create_client()
            self._set_state(ConnectionState.CONNECTED)
            self._backoff = self.BACKOFF_INITIAL
            return True
        except Exception as e:
            self._set_state(ConnectionState.ERROR)
            return False
    
    async def create_room(self, room_hash: str, mode: str = "rotating") -> Optional[RoomState]:
        """
        Create a new room on the relay server.
        
        Args:
            room_hash: SHA256 hash of emoji room ID (16 chars)
            mode: "rotating" or "fixed"
        
        Returns:
            RoomState if successful, None otherwise
        """
        if not self.client:
            if not await self.connect():
                return None
        
        try:
            response = await self.client.post(
                f"{self.base_url}/room",
                json={"room_hash": room_hash, "mode": mode}
            )
            
            if response.status_code == 200:
                data = response.json()
                self.room_hash = room_hash
                self.member_id = data.get("member_id")
                return RoomState(
                    room_hash=room_hash,
                    mode=data["mode"],
                    created_at=data["created_at"],
                    expires_at=data["expires_at"],
                    members=data.get("members", []),
                    message_count=0
                )
            elif response.status_code == 429:
                # Rate limited
                retry_after = response.json().get("retry_after", 10)
                raise RateLimitError(retry_after)
            else:
                return None
                
        except httpx.RequestError:
            self._set_state(ConnectionState.RECONNECTING)
            return None
    
    async def join_room(self, room_hash: str, nickname: str = "anon") -> Optional[RoomState]:
        """
        Join an existing room.
        
        Args:
            room_hash: SHA256 hash of emoji room ID
            nickname: Display name in room
        
        Returns:
            RoomState if successful, None otherwise
        """
        if not self.client:
            if not await self.connect():
                return None
        
        try:
            response = await self.client.post(
                f"{self.base_url}/room/{room_hash}/join",
                json={"nickname": nickname}
            )
            
            if response.status_code == 200:
                data = response.json()
                self.room_hash = room_hash
                self.member_id = data.get("member_id")
                self.last_message_ts = data.get("last_message_ts", 0)
                return RoomState(
                    room_hash=room_hash,
                    mode=data["mode"],
                    created_at=data["created_at"],
                    expires_at=data["expires_at"],
                    members=data.get("members", []),
                    message_count=data.get("message_count", 0)
                )
            elif response.status_code == 404:
                raise RoomNotFoundError()
            elif response.status_code == 401:
                raise InvalidKeyError()
            else:
                return None
                
        except httpx.RequestError:
            self._set_state(ConnectionState.RECONNECTING)
            return None
    
    async def send_message(self, content: str, sender: str = "me") -> bool:
        """
        Send an encrypted message to the room.
        
        Args:
            content: Encrypted message content (base64)
            sender: Sender identifier
        
        Returns:
            True if sent successfully
        """
        if not self.room_hash:
            return False
        
        if not self.client or self.state != ConnectionState.CONNECTED:
            # Queue for later
            self._pending_messages.append({
                "content": content,
                "sender": sender,
                "queued_at": time.time()
            })
            return False
        
        try:
            response = await self.client.post(
                f"{self.base_url}/room/{self.room_hash}/send",
                json={
                    "content": content,
                    "sender": sender,
                    "member_id": self.member_id
                }
            )
            return response.status_code == 200
            
        except httpx.RequestError:
            # Queue and mark reconnecting
            self._pending_messages.append({
                "content": content,
                "sender": sender,
                "queued_at": time.time()
            })
            self._set_state(ConnectionState.RECONNECTING)
            return False
    
    async def poll_messages(self) -> list[Message]:
        """
        Poll for new messages since last check.
        
        Returns:
            List of new messages
        """
        if not self.room_hash or not self.client:
            return []
        
        try:
            response = await self.client.get(
                f"{self.base_url}/room/{self.room_hash}/poll",
                params={"since": self.last_message_ts, "member_id": self.member_id}
            )
            
            if response.status_code == 200:
                data = response.json()
                messages = [Message.from_dict(m) for m in data.get("messages", [])]
                
                if messages:
                    self.last_message_ts = max(m.timestamp for m in messages)
                
                # Update members if changed
                members = data.get("members", [])
                if self.on_members_update and members:
                    self.on_members_update(members)
                
                # Check expiry
                expires_at = data.get("expires_at", 0)
                if expires_at and time.time() > expires_at:
                    if self.on_room_expire:
                        self.on_room_expire()
                
                return messages
                
            elif response.status_code == 404:
                # Room expired or doesn't exist
                if self.on_room_expire:
                    self.on_room_expire()
                return []
            else:
                return []
                
        except httpx.RequestError:
            self._set_state(ConnectionState.RECONNECTING)
            return []
    
    async def start_polling(self):
        """Start background polling for messages"""
        self._running = True
        self._poll_task = asyncio.create_task(self._poll_loop())
    
    async def stop_polling(self):
        """Stop background polling"""
        self._running = False
        if self._poll_task:
            self._poll_task.cancel()
            try:
                await self._poll_task
            except asyncio.CancelledError:
                pass
    
    async def _poll_loop(self):
        """Background polling loop with reconnection"""
        while self._running:
            try:
                if self.state == ConnectionState.CONNECTED:
                    messages = await self.poll_messages()
                    for msg in messages:
                        if self.on_message:
                            self.on_message(msg)
                    
                    # Flush pending messages
                    await self._flush_pending()
                    
                    self._backoff = self.BACKOFF_INITIAL
                    
                elif self.state == ConnectionState.RECONNECTING:
                    # Try to reconnect
                    if await self.connect():
                        self._set_state(ConnectionState.CONNECTED)
                    else:
                        await asyncio.sleep(self._backoff)
                        self._backoff = min(self._backoff * self.BACKOFF_MULTIPLIER, self.BACKOFF_MAX)
                
                await asyncio.sleep(self.POLL_INTERVAL)
                
            except asyncio.CancelledError:
                break
            except Exception:
                await asyncio.sleep(self.POLL_INTERVAL)
    
    async def _flush_pending(self):
        """Send queued messages after reconnection"""
        while self._pending_messages:
            msg = self._pending_messages.pop(0)
            # Only send if not too old (< 5 minutes)
            if time.time() - msg["queued_at"] < 300:
                await self.send_message(msg["content"], msg["sender"])
    
    async def leave_room(self):
        """Leave current room and cleanup"""
        self._running = False
        await self.stop_polling()
        
        if self.client and self.room_hash:
            try:
                await self.client.post(
                    f"{self.base_url}/room/{self.room_hash}/leave",
                    json={"member_id": self.member_id}
                )
            except Exception:
                pass
        
        self.room_hash = None
        self.member_id = None
        
        if self.client:
            await self.client.aclose()
            self.client = None
        
        self._set_state(ConnectionState.DISCONNECTED)
    
    async def get_room_info(self) -> Optional[dict]:
        """Get current room information"""
        if not self.room_hash or not self.client:
            return None
        
        try:
            response = await self.client.get(
                f"{self.base_url}/room/{self.room_hash}/info"
            )
            if response.status_code == 200:
                return response.json()
            return None
        except Exception:
            return None


class RateLimitError(Exception):
    """Raised when rate limited by server"""
    def __init__(self, retry_after: int):
        self.retry_after = retry_after
        super().__init__(f"Rate limited. Retry after {retry_after} seconds.")


class RoomNotFoundError(Exception):
    """Raised when room doesn't exist or expired"""
    pass


class InvalidKeyError(Exception):
    """Raised when room key is invalid"""
    pass
