"""
SOS Crypto - End-to-end encryption for emergency chat

Key derivation:
- Rotating mode: Argon2id(emoji_codepoints + pin + floor(time/15))
- Fixed mode: Argon2id(emoji_codepoints + pin + room_created_timestamp)

Encryption: NaCl SecretBox (XSalsa20-Poly1305)
"""

import time
import secrets
import hashlib
from typing import Optional, Tuple
from dataclasses import dataclass

from argon2.low_level import hash_secret_raw, Type
from nacl.secret import SecretBox
from nacl.utils import random as nacl_random
from nacl.exceptions import CryptoError


# 32 carefully chosen emojis - distinct, easily describable
EMOJI_SET = [
    "🔥", "🌙", "⭐", "🎯", "🌊", "💎", "🍀", "🎲",
    "🚀", "🌈", "⚡", "🎵", "🔑", "🌸", "🍄", "🦋",
    "🎪", "🌵", "🍎", "🐋", "🦊", "🌻", "🎭", "🔔",
    "🏔️", "🌴", "🍕", "🐙", "🦉", "🌺", "🎨", "🔮"
]

# Phonetic names for verbal communication
EMOJI_PHONETICS = {
    "🔥": "fire", "🌙": "moon", "⭐": "star", "🎯": "target",
    "🌊": "wave", "💎": "gem", "🍀": "clover", "🎲": "dice",
    "🚀": "rocket", "🌈": "rainbow", "⚡": "bolt", "🎵": "music",
    "🔑": "key", "🌸": "bloom", "🍄": "shroom", "🦋": "butterfly",
    "🎪": "circus", "🌵": "cactus", "🍎": "apple", "🐋": "whale",
    "🦊": "fox", "🌻": "sunflower", "🎭": "mask", "🔔": "bell",
    "🏔️": "mountain", "🌴": "palm", "🍕": "pizza", "🐙": "octopus",
    "🦉": "owl", "🌺": "hibiscus", "🎨": "palette", "🔮": "crystal"
}

# Reverse lookup
PHONETICS_TO_EMOJI = {v: k for k, v in EMOJI_PHONETICS.items()}


@dataclass
class RoomCredentials:
    """Room identification and encryption credentials"""
    room_id: str          # 6 emojis joined
    emojis: list[str]     # List of 6 emojis
    mode: str             # "rotating" or "fixed"
    created_at: float     # Unix timestamp
    fixed_pin: Optional[str] = None  # Only set for fixed mode


def generate_room_id() -> list[str]:
    """Generate 6 random emojis for room ID"""
    return [secrets.choice(EMOJI_SET) for _ in range(6)]


def generate_pin() -> str:
    """Generate 6-digit PIN"""
    return ''.join(str(secrets.randbelow(10)) for _ in range(6))


def get_current_pin(creds: RoomCredentials) -> str:
    """
    Get current valid PIN based on mode.
    
    - Rotating: Derived from time bucket (changes every 15s)
    - Fixed: Static PIN set at room creation
    """
    if creds.mode == "fixed":
        return creds.fixed_pin or generate_pin()
    
    # Rotating mode: derive PIN from time bucket
    bucket = int(time.time() // 15)
    seed = f"{creds.room_id}:{bucket}".encode()
    hash_val = hashlib.sha256(seed).hexdigest()
    # Take first 6 hex chars and convert to digits 0-9
    pin = ''.join(str(int(c, 16) % 10) for c in hash_val[:6])
    return pin


def get_time_remaining() -> int:
    """Seconds until next PIN rotation"""
    return 15 - (int(time.time()) % 15)


def derive_room_key(emojis: list[str], pin: str, timestamp: Optional[float] = None) -> bytes:
    """
    Derive encryption key using Argon2id.
    
    For rotating mode, timestamp should be floor(time/15)*15
    For fixed mode, timestamp is room creation time
    """
    # Build input: emoji codepoints + pin + optional timestamp
    emoji_str = ''.join(emojis)
    salt_input = f"sos-chat-v1:{emoji_str}"
    
    if timestamp:
        salt_input += f":{int(timestamp)}"
    
    password = f"{emoji_str}:{pin}".encode('utf-8')
    salt = hashlib.sha256(salt_input.encode()).digest()[:16]
    
    # Argon2id with moderate params (fast on client, still secure)
    key = hash_secret_raw(
        secret=password,
        salt=salt,
        time_cost=2,
        memory_cost=65536,  # 64 MB
        parallelism=1,
        hash_len=32,
        type=Type.ID
    )
    
    return key


def get_encryption_key(creds: RoomCredentials, pin: str) -> bytes:
    """Get the encryption key for current time window"""
    if creds.mode == "fixed":
        return derive_room_key(creds.emojis, pin, creds.created_at)
    else:
        # Rotating: use current time bucket
        bucket = int(time.time() // 15) * 15
        return derive_room_key(creds.emojis, pin, bucket)


def encrypt_message(message: str, key: bytes) -> bytes:
    """Encrypt a message using NaCl SecretBox"""
    box = SecretBox(key)
    nonce = nacl_random(SecretBox.NONCE_SIZE)
    encrypted = box.encrypt(message.encode('utf-8'), nonce)
    return encrypted


def decrypt_message(encrypted: bytes, key: bytes) -> Optional[str]:
    """Decrypt a message using NaCl SecretBox"""
    try:
        box = SecretBox(key)
        decrypted = box.decrypt(encrypted)
        return decrypted.decode('utf-8')
    except CryptoError:
        return None


def try_decrypt_rotating(encrypted: bytes, creds: RoomCredentials) -> Optional[Tuple[str, str]]:
    """
    Try to decrypt with current time bucket.
    Returns (message, pin_used) or None.
    
    Only accepts current time window (strict 15s).
    """
    current_pin = get_current_pin(creds)
    key = get_encryption_key(creds, current_pin)
    
    msg = decrypt_message(encrypted, key)
    if msg:
        return (msg, current_pin)
    
    return None


def room_id_to_hash(emojis: list[str]) -> str:
    """Convert emoji room ID to a hash for server-side storage"""
    emoji_str = ''.join(emojis)
    return hashlib.sha256(emoji_str.encode()).hexdigest()[:16]


def emojis_to_indices(emojis: list[str]) -> list[int]:
    """Convert emojis to their indices in EMOJI_SET"""
    return [EMOJI_SET.index(e) for e in emojis if e in EMOJI_SET]


def indices_to_emojis(indices: list[int]) -> list[str]:
    """Convert indices back to emojis"""
    return [EMOJI_SET[i] for i in indices if 0 <= i < len(EMOJI_SET)]


def get_phonetic(emoji: str) -> str:
    """Get phonetic name for an emoji"""
    return EMOJI_PHONETICS.get(emoji, emoji)


def get_phonetic_room_id(emojis: list[str]) -> str:
    """Get room ID as phonetic words (for verbal sharing)"""
    return ' '.join(get_phonetic(e) for e in emojis)
