import argon2 from 'argon2-browser/dist/argon2-bundled.min.js';
import nacl from 'tweetnacl';
import type { RoomMode } from '@/lib/sos-types';

export const EMOJI_SET = [
  '🔥', '🌙', '⭐', '🎯', '🌊', '💎', '🍀', '🎲',
  '🚀', '🌈', '⚡', '🎵', '🔑', '🌸', '🍄', '🦋',
  '🎪', '🌵', '🍎', '🐋', '🦊', '🌻', '🎭', '🔔',
  '🏔️', '🌴', '🍕', '🐙', '🦉', '🌺', '🎨', '🔮'
];

export const EMOJI_PHONETICS: Record<string, string> = {
  '🔥': 'fire', '🌙': 'moon', '⭐': 'star', '🎯': 'target',
  '🌊': 'wave', '💎': 'gem', '🍀': 'clover', '🎲': 'dice',
  '🚀': 'rocket', '🌈': 'rainbow', '⚡': 'bolt', '🎵': 'music',
  '🔑': 'key', '🌸': 'bloom', '🍄': 'shroom', '🦋': 'butterfly',
  '🎪': 'circus', '🌵': 'cactus', '🍎': 'apple', '🐋': 'whale',
  '🦊': 'fox', '🌻': 'sunflower', '🎭': 'mask', '🔔': 'bell',
  '🏔️': 'mountain', '🌴': 'palm', '🍕': 'pizza', '🐙': 'octopus',
  '🦉': 'owl', '🌺': 'hibiscus', '🎨': 'palette', '🔮': 'crystal'
};

const encoder = new TextEncoder();

export function generatePin() {
  let pin = '';
  for (let i = 0; i < 6; i += 1) {
    pin += Math.floor(Math.random() * 10).toString();
  }
  return pin;
}

export async function sha256(data: string | Uint8Array | string[]) {
  let dataBytes: Uint8Array;
  if (data instanceof Uint8Array) {
    dataBytes = data;
  } else if (typeof data === 'string') {
    dataBytes = encoder.encode(data);
  } else if (Array.isArray(data)) {
    dataBytes = encoder.encode(data.join(''));
  } else {
    dataBytes = encoder.encode(String(data));
  }

  if (typeof crypto !== 'undefined' && crypto.subtle) {
    const hashBuffer = await crypto.subtle.digest('SHA-256', dataBytes);
    return new Uint8Array(hashBuffer);
  }

  return sha256Fallback(dataBytes);
}

function sha256Fallback(message: Uint8Array) {
  const K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ];

  let H = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];

  const rotr = (x: number, n: number) => ((x >>> n) | (x << (32 - n))) >>> 0;
  const ch = (x: number, y: number, z: number) => ((x & y) ^ (~x & z)) >>> 0;
  const maj = (x: number, y: number, z: number) => ((x & y) ^ (x & z) ^ (y & z)) >>> 0;
  const sigma0 = (x: number) => (rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22)) >>> 0;
  const sigma1 = (x: number) => (rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25)) >>> 0;
  const gamma0 = (x: number) => (rotr(x, 7) ^ rotr(x, 18) ^ (x >>> 3)) >>> 0;
  const gamma1 = (x: number) => (rotr(x, 17) ^ rotr(x, 19) ^ (x >>> 10)) >>> 0;

  const readU32 = (arr: number[], i: number) => ((arr[i] << 24) | (arr[i + 1] << 16) | (arr[i + 2] << 8) | arr[i + 3]) >>> 0;

  const msg = Array.from(message);
  const msgLen = msg.length;
  const bitLen = msgLen * 8;

  msg.push(0x80);
  while ((msg.length % 64) !== 56) msg.push(0);

  for (let i = 7; i >= 0; i -= 1) {
    msg.push((bitLen / Math.pow(256, i)) & 0xff);
  }

  for (let offset = 0; offset < msg.length; offset += 64) {
    const W = new Array(64);
    for (let t = 0; t < 16; t += 1) {
      W[t] = readU32(msg, offset + t * 4);
    }
    for (let t = 16; t < 64; t += 1) {
      W[t] = (gamma1(W[t - 2]) + W[t - 7] + gamma0(W[t - 15]) + W[t - 16]) >>> 0;
    }

    let [a, b, c, d, e, f, g, h] = H;
    for (let t = 0; t < 64; t += 1) {
      const T1 = (h + sigma1(e) + ch(e, f, g) + K[t] + W[t]) >>> 0;
      const T2 = (sigma0(a) + maj(a, b, c)) >>> 0;
      h = g; g = f; f = e; e = (d + T1) >>> 0;
      d = c; c = b; b = a; a = (T1 + T2) >>> 0;
    }

    H[0] = (H[0] + a) >>> 0; H[1] = (H[1] + b) >>> 0;
    H[2] = (H[2] + c) >>> 0; H[3] = (H[3] + d) >>> 0;
    H[4] = (H[4] + e) >>> 0; H[5] = (H[5] + f) >>> 0;
    H[6] = (H[6] + g) >>> 0; H[7] = (H[7] + h) >>> 0;
  }

  const result = new Uint8Array(32);
  for (let i = 0; i < 8; i += 1) {
    result[i * 4] = (H[i] >>> 24) & 0xff;
    result[i * 4 + 1] = (H[i] >>> 16) & 0xff;
    result[i * 4 + 2] = (H[i] >>> 8) & 0xff;
    result[i * 4 + 3] = H[i] & 0xff;
  }
  return result;
}

export function bytesToHex(bytes: Uint8Array) {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function roomIdToHash(emojis: string[]) {
  const emojiStr = emojis.join('');
  const hash = await sha256(emojiStr);
  return bytesToHex(hash).slice(0, 16);
}

export async function deriveRoomKey(emojis: string[], pin: string, timestamp: number) {
  const emojiStr = emojis.join('');
  const saltInput = `sos-chat-v1:${emojiStr}:${Math.floor(timestamp)}`;
  const saltHash = await sha256(saltInput);
  const salt = saltHash.slice(0, 16);
  const password = `${emojiStr}:${pin}`;

  const result = await argon2.hash({
    pass: password,
    salt,
    time: 2,
    mem: 65536,
    parallelism: 1,
    hashLen: 32,
    type: argon2.ArgonType.Argon2id
  });

  return result.hash;
}

export async function getEncryptionKey(emojis: string[], pin: string, mode: RoomMode, createdAt: number) {
  if (mode !== 'fixed') {
    return deriveRoomKey(emojis, pin, createdAt);
  }
  return deriveRoomKey(emojis, pin, createdAt);
}

export function encryptMessage(message: string, key: Uint8Array) {
  const messageBytes = encoder.encode(message);
  const nonce = nacl.randomBytes(nacl.secretbox.nonceLength);
  const ciphertext = nacl.secretbox(messageBytes, nonce, key);
  const result = new Uint8Array(nonce.length + ciphertext.length);
  result.set(nonce);
  result.set(ciphertext, nonce.length);
  return result;
}

export function decryptMessage(encrypted: Uint8Array, key: Uint8Array) {
  try {
    const nonce = encrypted.slice(0, nacl.secretbox.nonceLength);
    const ciphertext = encrypted.slice(nacl.secretbox.nonceLength);
    const decrypted = nacl.secretbox.open(ciphertext, nonce, key);
    if (!decrypted) return null;
    return new TextDecoder().decode(decrypted);
  } catch {
    return null;
  }
}

export async function tryDecrypt(
  encrypted: Uint8Array,
  emojis: string[],
  mode: RoomMode,
  createdAt: number,
  fixedPin?: string | null
) {
  if (!fixedPin) return null;
  const key = await deriveRoomKey(emojis, fixedPin, createdAt);
  return decryptMessage(encrypted, key);
}

export function base64FromBytes(bytes: Uint8Array) {
  const binString = String.fromCharCode(...bytes);
  return btoa(binString);
}

export function bytesFromBase64(base64: string) {
  const binString = atob(base64);
  return Uint8Array.from(binString, (c) => c.charCodeAt(0));
}
