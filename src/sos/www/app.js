/**
 * SOS Emergency Chat - Web Client
 * 
 * End-to-end encrypted chat rooms over DNS tunnel.
 * Compatible with TUI client (same crypto spec).
 * 
 * Crypto Spec (must match crypto.py exactly):
 * - Room ID: 6 emojis from 32-emoji set
 * - Room hash: SHA256(emojis)[:16] hex
 * - Salt: SHA256("sos-chat-v1:" + emojis + [":" + timestamp])[:16]
 * - Password: emojis + ":" + pin (UTF-8)
 * - KDF: Argon2id (time=2, mem=64MB, p=1, hashLen=32)
 * - Encryption: NaCl SecretBox (XSalsa20-Poly1305)
 * - Nonce: 24 bytes, prepended to ciphertext
 */

// ============================================================================
// CONFIGURATION
// ============================================================================

const CONFIG = {
  // Relay server (relative URL when served from relay, absolute for testing)
  RELAY_URL: '',  // Empty = same origin
  
  // Polling interval (ms)
  POLL_INTERVAL: 1500,
  
  // PIN rotation window (seconds)
  PIN_WINDOW: 15,
  
  // Room TTL (seconds)
  ROOM_TTL: 3600,
  
  // Max message length
  MAX_MESSAGE_LENGTH: 2000
};

// ============================================================================
// EMOJI SET (must match crypto.py exactly, same order)
// ============================================================================

const EMOJI_SET = [
  "🔥", "🌙", "⭐", "🎯", "🌊", "💎", "🍀", "🎲",
  "🚀", "🌈", "⚡", "🎵", "🔑", "🌸", "🍄", "🦋",
  "🎪", "🌵", "🍎", "🐋", "🦊", "🌻", "🎭", "🔔",
  "🏔️", "🌴", "🍕", "🐙", "🦉", "🌺", "🎨", "🔮"
];

const EMOJI_PHONETICS = {
  "🔥": "fire", "🌙": "moon", "⭐": "star", "🎯": "target",
  "🌊": "wave", "💎": "gem", "🍀": "clover", "🎲": "dice",
  "🚀": "rocket", "🌈": "rainbow", "⚡": "bolt", "🎵": "music",
  "🔑": "key", "🌸": "bloom", "🍄": "shroom", "🦋": "butterfly",
  "🎪": "circus", "🌵": "cactus", "🍎": "apple", "🐋": "whale",
  "🦊": "fox", "🌻": "sunflower", "🎭": "mask", "🔔": "bell",
  "🏔️": "mountain", "🌴": "palm", "🍕": "pizza", "🐙": "octopus",
  "🦉": "owl", "🌺": "hibiscus", "🎨": "palette", "🔮": "crystal"
};

// ============================================================================
// STATE
// ============================================================================

let state = {
  mode: 'welcome',  // 'welcome', 'create', 'join', 'chat'
  
  // Room setup
  selectedEmojis: [],
  keyMode: 'rotating',  // 'rotating' or 'fixed'
  
  // Room session
  roomHash: null,
  roomEmojis: null,
  memberId: null,
  nickname: 'anon',
  createdAt: null,
  expiresAt: null,
  encryptionKey: null,
  fixedPin: null,
  
  // Chat state
  messages: [],
  lastMessageTs: 0,
  pollInterval: null,
  isConnected: false,
  
  // PIN timer
  pinTimerInterval: null,
  currentPin: null
};

// ============================================================================
// CRYPTO FUNCTIONS (matching crypto.py exactly)
// ============================================================================

/**
 * Generate random emojis for room ID
 */
function generateRoomId() {
  const emojis = [];
  for (let i = 0; i < 6; i++) {
    const idx = Math.floor(Math.random() * EMOJI_SET.length);
    emojis.push(EMOJI_SET[idx]);
  }
  return emojis;
}

/**
 * Generate 6-digit PIN
 */
function generatePin() {
  let pin = '';
  for (let i = 0; i < 6; i++) {
    pin += Math.floor(Math.random() * 10).toString();
  }
  return pin;
}

/**
 * Compute SHA256 hash (with fallback for non-HTTPS)
 * crypto.subtle only works in secure contexts (HTTPS/localhost)
 */
async function sha256(data) {
  const encoder = new TextEncoder();
  const dataBytes = typeof data === 'string' ? encoder.encode(data) : data;
  
  // Try Web Crypto API first (only works in HTTPS/localhost)
  if (typeof crypto !== 'undefined' && crypto.subtle) {
    const hashBuffer = await crypto.subtle.digest('SHA-256', dataBytes);
    return new Uint8Array(hashBuffer);
  }
  
  // Fallback: Pure JS SHA256 implementation
  return sha256Fallback(dataBytes);
}

/**
 * Pure JavaScript SHA256 implementation (for HTTP contexts)
 * Based on FIPS 180-4 specification
 */
function sha256Fallback(message) {
  // Constants
  const K = new Uint32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ]);

  // Initial hash values
  let H = new Uint32Array([
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  ]);

  // Helper functions
  const rotr = (x, n) => (x >>> n) | (x << (32 - n));
  const ch = (x, y, z) => (x & y) ^ (~x & z);
  const maj = (x, y, z) => (x & y) ^ (x & z) ^ (y & z);
  const sigma0 = x => rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
  const sigma1 = x => rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
  const gamma0 = x => rotr(x, 7) ^ rotr(x, 18) ^ (x >>> 3);
  const gamma1 = x => rotr(x, 17) ^ rotr(x, 19) ^ (x >>> 10);

  // Pre-processing: adding padding bits
  const msgLen = message.length;
  const bitLen = msgLen * 8;
  
  // Message needs to be padded to 512-bit blocks (64 bytes)
  // Padding: 1 bit, then 0s, then 64-bit length
  const padLen = ((msgLen + 8) % 64 === 0) ? 64 : 64 - ((msgLen + 8) % 64);
  const paddedLen = msgLen + 1 + padLen + 8;
  const padded = new Uint8Array(paddedLen);
  
  padded.set(message);
  padded[msgLen] = 0x80;
  
  // Append length in bits as 64-bit big-endian
  const view = new DataView(padded.buffer);
  view.setUint32(paddedLen - 4, bitLen, false);

  // Process each 512-bit block
  const W = new Uint32Array(64);
  
  for (let offset = 0; offset < paddedLen; offset += 64) {
    // Prepare message schedule
    for (let t = 0; t < 16; t++) {
      W[t] = view.getUint32(offset + t * 4, false);
    }
    for (let t = 16; t < 64; t++) {
      W[t] = (gamma1(W[t-2]) + W[t-7] + gamma0(W[t-15]) + W[t-16]) >>> 0;
    }

    // Initialize working variables
    let [a, b, c, d, e, f, g, h] = H;

    // Main loop
    for (let t = 0; t < 64; t++) {
      const T1 = (h + sigma1(e) + ch(e, f, g) + K[t] + W[t]) >>> 0;
      const T2 = (sigma0(a) + maj(a, b, c)) >>> 0;
      h = g;
      g = f;
      f = e;
      e = (d + T1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (T1 + T2) >>> 0;
    }

    // Update hash values
    H[0] = (H[0] + a) >>> 0;
    H[1] = (H[1] + b) >>> 0;
    H[2] = (H[2] + c) >>> 0;
    H[3] = (H[3] + d) >>> 0;
    H[4] = (H[4] + e) >>> 0;
    H[5] = (H[5] + f) >>> 0;
    H[6] = (H[6] + g) >>> 0;
    H[7] = (H[7] + h) >>> 0;
  }

  // Produce final hash
  const result = new Uint8Array(32);
  for (let i = 0; i < 8; i++) {
    result[i * 4] = (H[i] >>> 24) & 0xff;
    result[i * 4 + 1] = (H[i] >>> 16) & 0xff;
    result[i * 4 + 2] = (H[i] >>> 8) & 0xff;
    result[i * 4 + 3] = H[i] & 0xff;
  }
  
  return result;
}

/**
 * Convert bytes to hex string
 */
function bytesToHex(bytes) {
  return Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Convert hex string to bytes
 */
function hexToBytes(hex) {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
  }
  return bytes;
}

/**
 * Calculate room hash from emojis
 * Hash = SHA256(emojis)[:16] as hex
 */
async function roomIdToHash(emojis) {
  const emojiStr = emojis.join('');
  const hash = await sha256(emojiStr);
  return bytesToHex(hash).slice(0, 16);
}

/**
 * Get current PIN for rotating mode
 * PIN = SHA256(roomId + ":" + bucket)[:6] -> each hex char mod 10
 */
async function getCurrentPin(emojis) {
  const roomId = emojis.join('');
  const bucket = Math.floor(Date.now() / 1000 / CONFIG.PIN_WINDOW);
  const seed = `${roomId}:${bucket}`;
  const hash = await sha256(seed);
  const hashHex = bytesToHex(hash);
  
  let pin = '';
  for (let i = 0; i < 6; i++) {
    pin += (parseInt(hashHex[i], 16) % 10).toString();
  }
  return pin;
}

/**
 * Get time remaining until next PIN rotation
 */
function getTimeRemaining() {
  return CONFIG.PIN_WINDOW - (Math.floor(Date.now() / 1000) % CONFIG.PIN_WINDOW);
}

/**
 * Derive encryption key using Argon2id (or PBKDF2 fallback)
 * 
 * Salt = SHA256("sos-chat-v1:" + emojis + [":" + timestamp])[:16]
 * Password = emojis + ":" + pin
 */
async function deriveRoomKey(emojis, pin, timestamp = null) {
  const emojiStr = emojis.join('');
  
  // Build salt input (must match Python exactly)
  let saltInput = `sos-chat-v1:${emojiStr}`;
  if (timestamp !== null) {
    saltInput += `:${Math.floor(timestamp)}`;
  }
  
  // Salt = SHA256(saltInput)[:16]
  const saltHash = await sha256(saltInput);
  const salt = saltHash.slice(0, 16);
  
  // Password = emojis:pin
  const password = `${emojiStr}:${pin}`;
  
  // Derive key using Argon2id (or fallback)
  const result = await argon2.hash({
    pass: password,
    salt: salt,
    time: 2,
    mem: 65536,  // 64 MB
    parallelism: 1,
    hashLen: 32,
    type: argon2.ArgonType.Argon2id
  });
  
  return result.hash;
}

/**
 * Get encryption key based on mode
 */
async function getEncryptionKey(emojis, pin, mode, createdAt) {
  if (mode === 'fixed') {
    // Fixed mode: use room creation timestamp
    return await deriveRoomKey(emojis, pin, createdAt);
  } else {
    // Rotating mode: use current time bucket
    const bucket = Math.floor(Date.now() / 1000 / CONFIG.PIN_WINDOW) * CONFIG.PIN_WINDOW;
    return await deriveRoomKey(emojis, pin, bucket);
  }
}

/**
 * Encrypt message using NaCl SecretBox
 * Output: nonce (24 bytes) + ciphertext
 */
function encryptMessage(message, key) {
  const messageBytes = new TextEncoder().encode(message);
  const nonce = nacl.randomBytes(nacl.secretbox.nonceLength);  // 24 bytes
  const ciphertext = nacl.secretbox(messageBytes, nonce, key);
  
  // Prepend nonce to ciphertext
  const result = new Uint8Array(nonce.length + ciphertext.length);
  result.set(nonce);
  result.set(ciphertext, nonce.length);
  
  return result;
}

/**
 * Decrypt message using NaCl SecretBox
 */
function decryptMessage(encrypted, key) {
  try {
    const nonce = encrypted.slice(0, nacl.secretbox.nonceLength);
    const ciphertext = encrypted.slice(nacl.secretbox.nonceLength);
    const decrypted = nacl.secretbox.open(ciphertext, nonce, key);
    
    if (!decrypted) return null;
    return new TextDecoder().decode(decrypted);
  } catch (e) {
    console.error('Decryption failed:', e);
    return null;
  }
}

/**
 * Try decrypting with multiple keys (for rotating mode, try current and previous buckets)
 */
async function tryDecrypt(encrypted, emojis, mode, createdAt) {
  const keys = [];
  
  if (mode === 'fixed') {
    // Fixed mode: only one key
    const pin = state.fixedPin;
    if (pin) {
      keys.push(await deriveRoomKey(emojis, pin, createdAt));
    }
  } else {
    // Rotating mode: try current and previous buckets
    const now = Date.now() / 1000;
    for (let offset = 0; offset <= 2; offset++) {
      const bucket = Math.floor((now - offset * CONFIG.PIN_WINDOW) / CONFIG.PIN_WINDOW) * CONFIG.PIN_WINDOW;
      const pin = await getCurrentPinForBucket(emojis, bucket);
      keys.push(await deriveRoomKey(emojis, pin, bucket));
    }
  }
  
  for (const key of keys) {
    const decrypted = decryptMessage(encrypted, key);
    if (decrypted !== null) {
      return decrypted;
    }
  }
  
  return null;
}

/**
 * Get PIN for a specific time bucket
 */
async function getCurrentPinForBucket(emojis, bucket) {
  const roomId = emojis.join('');
  const bucketNum = Math.floor(bucket / CONFIG.PIN_WINDOW);
  const seed = `${roomId}:${bucketNum}`;
  const hash = await sha256(seed);
  const hashHex = bytesToHex(hash);
  
  let pin = '';
  for (let i = 0; i < 6; i++) {
    pin += (parseInt(hashHex[i], 16) % 10).toString();
  }
  return pin;
}

// ============================================================================
// API FUNCTIONS
// ============================================================================

async function apiRequest(endpoint, method = 'GET', body = null) {
  const url = CONFIG.RELAY_URL + endpoint;
  const options = {
    method,
    headers: { 'Content-Type': 'application/json' }
  };
  
  if (body) {
    options.body = JSON.stringify(body);
  }
  
  try {
    const response = await fetch(url, options);
    const data = await response.json();
    
    if (!response.ok) {
      throw new Error(data.error || `HTTP ${response.status}`);
    }
    
    return data;
  } catch (e) {
    console.error(`API error (${endpoint}):`, e);
    throw e;
  }
}

async function createRoom(roomHash, mode) {
  return await apiRequest('/room', 'POST', { room_hash: roomHash, mode });
}

async function joinRoom(roomHash, nickname) {
  return await apiRequest(`/room/${roomHash}/join`, 'POST', { nickname });
}

async function sendMessageApi(roomHash, content, sender, memberId) {
  return await apiRequest(`/room/${roomHash}/send`, 'POST', {
    content,
    sender,
    member_id: memberId
  });
}

async function pollMessages(roomHash, since, memberId) {
  const params = new URLSearchParams({ since: since.toString() });
  if (memberId) params.append('member_id', memberId);
  return await apiRequest(`/room/${roomHash}/poll?${params}`);
}

async function leaveRoomApi(roomHash, memberId) {
  return await apiRequest(`/room/${roomHash}/leave`, 'POST', { member_id: memberId });
}

async function getRoomInfo(roomHash) {
  return await apiRequest(`/room/${roomHash}/info`);
}

// ============================================================================
// UI FUNCTIONS
// ============================================================================

function showScreen(screenId) {
  document.querySelectorAll('.screen').forEach(s => s.classList.remove('active'));
  document.getElementById(screenId).classList.add('active');
}

function showWelcome() {
  state.mode = 'welcome';
  state.selectedEmojis = [];
  clearInterval(state.pinTimerInterval);
  clearInterval(state.pollInterval);
  showScreen('welcome-screen');
}

function showCreateRoom() {
  state.mode = 'create';
  state.selectedEmojis = generateRoomId();
  state.keyMode = 'rotating';
  state.fixedPin = generatePin();
  
  // Update UI
  document.getElementById('setup-title').textContent = 'Create Room';
  document.getElementById('setup-action-btn').textContent = 'Create Room';
  
  // Show create UI, hide join UI
  document.getElementById('create-room-id').classList.remove('hidden');
  document.getElementById('join-room-id').classList.add('hidden');
  document.getElementById('create-pin').classList.remove('hidden');
  document.getElementById('join-pin').classList.add('hidden');
  document.getElementById('mode-section').classList.remove('hidden');
  document.getElementById('pin-section-title').textContent = 'Current PIN (share with joiner)';
  
  // Display emojis
  updateEmojiDisplay();
  
  // Start PIN timer
  updatePinDisplay();
  startPinTimer();
  
  // Clear status
  hideStatus();
  
  showScreen('setup-screen');
}

function showJoinRoom() {
  state.mode = 'join';
  state.selectedEmojis = [];
  state.keyMode = 'rotating';  // Will be determined from room
  
  // Update UI
  document.getElementById('setup-title').textContent = 'Join Room';
  document.getElementById('setup-action-btn').textContent = 'Join Room';
  
  // Show join UI, hide create UI
  document.getElementById('create-room-id').classList.add('hidden');
  document.getElementById('join-room-id').classList.remove('hidden');
  document.getElementById('create-pin').classList.add('hidden');
  document.getElementById('join-pin').classList.remove('hidden');
  document.getElementById('mode-section').classList.add('hidden');
  document.getElementById('pin-section-title').textContent = 'Enter PIN';
  
  // Build emoji picker
  buildEmojiPicker();
  
  // Update selected emojis display
  updateSelectedEmojisDisplay();
  
  // Setup PIN inputs
  setupPinInputs();
  
  // Clear status
  hideStatus();
  
  showScreen('setup-screen');
}

function buildEmojiPicker() {
  const picker = document.getElementById('emoji-picker');
  picker.innerHTML = '';
  
  EMOJI_SET.forEach(emoji => {
    const btn = document.createElement('button');
    btn.className = 'emoji-btn';
    btn.textContent = emoji;
    btn.title = EMOJI_PHONETICS[emoji];
    btn.onclick = () => selectEmoji(emoji);
    picker.appendChild(btn);
  });
}

function selectEmoji(emoji) {
  if (state.selectedEmojis.length < 6) {
    state.selectedEmojis.push(emoji);
    updateSelectedEmojisDisplay();
  }
}

function removeLastEmoji() {
  if (state.selectedEmojis.length > 0) {
    state.selectedEmojis.pop();
    updateSelectedEmojisDisplay();
  }
}

function updateSelectedEmojisDisplay() {
  const container = document.getElementById('selected-emojis');
  
  if (state.selectedEmojis.length === 0) {
    container.innerHTML = '<span style="color: var(--text-dim); font-size: 12px;">Click emojis above (need 6)</span>';
    return;
  }
  
  container.innerHTML = state.selectedEmojis.map((e, i) => 
    `<span onclick="removeEmojiAt(${i})" title="Click to remove">${e}</span>`
  ).join('');
  
  if (state.selectedEmojis.length < 6) {
    container.innerHTML += `<span style="color: var(--text-dim);">(${6 - state.selectedEmojis.length} more)</span>`;
  }
}

function removeEmojiAt(index) {
  state.selectedEmojis.splice(index, 1);
  updateSelectedEmojisDisplay();
}

function updateEmojiDisplay() {
  const display = document.getElementById('room-emojis-display');
  const phonetic = document.getElementById('room-phonetic');
  
  display.innerHTML = state.selectedEmojis.map(e => `<span>${e}</span>`).join('');
  phonetic.textContent = state.selectedEmojis.map(e => EMOJI_PHONETICS[e]).join(' · ');
}

function selectMode(mode) {
  state.keyMode = mode;
  
  // Update UI
  document.querySelectorAll('.mode-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.mode === mode);
  });
  
  // Update PIN display
  updatePinDisplay();
}

async function updatePinDisplay() {
  const display = document.getElementById('pin-display');
  const timer = document.getElementById('pin-timer');
  
  let pin;
  if (state.keyMode === 'rotating') {
    pin = await getCurrentPin(state.selectedEmojis);
    timer.textContent = `Refreshes in ${getTimeRemaining()}s`;
    timer.classList.remove('fixed');
  } else {
    pin = state.fixedPin;
    timer.textContent = 'Fixed PIN (does not change)';
    timer.classList.add('fixed');
  }
  
  state.currentPin = pin;
  display.innerHTML = pin.split('').map(d => 
    `<div class="pin-digit filled">${d}</div>`
  ).join('');
}

function startPinTimer() {
  clearInterval(state.pinTimerInterval);
  
  state.pinTimerInterval = setInterval(async () => {
    if (state.keyMode === 'rotating') {
      await updatePinDisplay();
    }
  }, 1000);
}

function setupPinInputs() {
  const inputs = document.querySelectorAll('#join-pin .pin-digit');
  
  inputs.forEach((input, index) => {
    input.value = '';
    input.classList.remove('filled');
    
    input.addEventListener('input', (e) => {
      const val = e.target.value.replace(/[^0-9]/g, '');
      e.target.value = val.slice(0, 1);
      
      if (val && index < 5) {
        inputs[index + 1].focus();
      }
      
      input.classList.toggle('filled', val.length > 0);
    });
    
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Backspace' && !e.target.value && index > 0) {
        inputs[index - 1].focus();
      }
    });
  });
  
  // Focus first input
  inputs[0].focus();
}

function getEnteredPin() {
  const inputs = document.querySelectorAll('#join-pin .pin-digit');
  return Array.from(inputs).map(i => i.value).join('');
}

function showStatus(message, type = 'info') {
  const status = document.getElementById('setup-status');
  status.textContent = message;
  status.className = `status ${type}`;
  status.classList.remove('hidden');
}

function hideStatus() {
  document.getElementById('setup-status').classList.add('hidden');
}

async function performSetupAction() {
  const btn = document.getElementById('setup-action-btn');
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span> Working...';
  
  try {
    if (state.mode === 'create') {
      await doCreateRoom();
    } else {
      await doJoinRoom();
    }
  } catch (e) {
    showStatus(e.message || 'Operation failed', 'error');
  } finally {
    btn.disabled = false;
    btn.textContent = state.mode === 'create' ? 'Create Room' : 'Join Room';
  }
}

async function doCreateRoom() {
  const roomHash = await roomIdToHash(state.selectedEmojis);
  
  showStatus('Creating room...', 'info');
  
  const response = await createRoom(roomHash, state.keyMode);
  
  // Store session info
  state.roomHash = roomHash;
  state.roomEmojis = [...state.selectedEmojis];
  state.memberId = response.member_id;
  state.createdAt = response.created_at;
  state.expiresAt = response.expires_at;
  state.nickname = 'creator';
  
  // Derive encryption key
  const pin = state.keyMode === 'fixed' ? state.fixedPin : await getCurrentPin(state.roomEmojis);
  state.encryptionKey = await getEncryptionKey(state.roomEmojis, pin, state.keyMode, state.createdAt);
  
  // Enter chat
  enterChat();
}

async function doJoinRoom() {
  // Validate inputs
  if (state.selectedEmojis.length !== 6) {
    showStatus('Select all 6 emojis', 'error');
    return;
  }
  
  const pin = getEnteredPin();
  if (pin.length !== 6) {
    showStatus('Enter all 6 PIN digits', 'error');
    return;
  }
  
  const roomHash = await roomIdToHash(state.selectedEmojis);
  
  showStatus('Joining room...', 'info');
  
  // Get room info first to determine mode
  let roomInfo;
  try {
    roomInfo = await getRoomInfo(roomHash);
  } catch (e) {
    showStatus('Room not found', 'error');
    return;
  }
  
  // Join the room
  const response = await joinRoom(roomHash, state.nickname);
  
  // Store session info
  state.roomHash = roomHash;
  state.roomEmojis = [...state.selectedEmojis];
  state.memberId = response.member_id;
  state.createdAt = response.created_at;
  state.expiresAt = response.expires_at;
  state.keyMode = response.mode;
  state.fixedPin = response.mode === 'fixed' ? pin : null;
  
  // Derive encryption key
  state.encryptionKey = await getEncryptionKey(state.roomEmojis, pin, state.keyMode, state.createdAt);
  
  // Enter chat
  enterChat();
}

function enterChat() {
  state.mode = 'chat';
  state.messages = [];
  state.lastMessageTs = 0;
  state.isConnected = true;
  
  // Update chat header
  document.getElementById('chat-room-emojis').textContent = state.roomEmojis.join(' ');
  updateChatExpiry();
  
  // Clear messages
  document.getElementById('chat-messages').innerHTML = '';
  addSystemMessage('You joined the room. Messages are end-to-end encrypted.');
  
  // Setup connection status
  updateConnectionStatus(true);
  
  // Setup PIN overlay for creators
  if (state.keyMode === 'rotating') {
    setupPinOverlay();
  }
  
  // Start polling
  startPolling();
  
  // Focus message input
  document.getElementById('message-input').focus();
  
  // Setup enter key handler
  document.getElementById('message-input').onkeypress = (e) => {
    if (e.key === 'Enter') sendMessage();
  };
  
  showScreen('chat-screen');
}

function updateChatExpiry() {
  const expiry = document.getElementById('chat-expiry');
  const remaining = Math.max(0, Math.floor((state.expiresAt - Date.now() / 1000) / 60));
  expiry.textContent = `${remaining}m left`;
}

function updateConnectionStatus(connected) {
  state.isConnected = connected;
  const dot = document.getElementById('connection-dot');
  const text = document.getElementById('connection-text');
  
  dot.classList.remove('connected', 'error');
  if (connected) {
    dot.classList.add('connected');
    text.textContent = 'Connected';
  } else {
    dot.classList.add('error');
    text.textContent = 'Reconnecting...';
  }
}

function setupPinOverlay() {
  const overlay = document.getElementById('pin-overlay');
  
  async function updateOverlay() {
    if (state.keyMode !== 'rotating') {
      overlay.classList.remove('visible');
      return;
    }
    
    const pin = await getCurrentPin(state.roomEmojis);
    document.getElementById('overlay-pin').textContent = pin;
    document.getElementById('overlay-timer').textContent = getTimeRemaining();
    
    // Also update encryption key for new messages
    state.encryptionKey = await getEncryptionKey(state.roomEmojis, pin, state.keyMode, state.createdAt);
  }
  
  // Show overlay
  overlay.classList.add('visible');
  updateOverlay();
  
  // Update every second
  setInterval(updateOverlay, 1000);
}

function addSystemMessage(text) {
  const container = document.getElementById('chat-messages');
  const div = document.createElement('div');
  div.className = 'system-message';
  div.textContent = text;
  container.appendChild(div);
  container.scrollTop = container.scrollHeight;
}

function addMessage(sender, content, timestamp, isOwn = false) {
  const container = document.getElementById('chat-messages');
  const div = document.createElement('div');
  div.className = `message${isOwn ? ' own' : ''}`;
  
  const time = new Date(timestamp * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  
  div.innerHTML = `
    <div class="message-sender">${escapeHtml(sender)}</div>
    <div class="message-content">${escapeHtml(content)}</div>
    <div class="message-time">${time}</div>
  `;
  
  container.appendChild(div);
  container.scrollTop = container.scrollHeight;
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

async function sendMessage() {
  const input = document.getElementById('message-input');
  const message = input.value.trim();
  
  if (!message || message.length > CONFIG.MAX_MESSAGE_LENGTH) return;
  
  const btn = document.getElementById('send-btn');
  btn.disabled = true;
  
  try {
    // Encrypt message
    const encrypted = encryptMessage(message, state.encryptionKey);
    const encryptedBase64 = btoa(String.fromCharCode(...encrypted));
    
    // Send to server
    await sendMessageApi(state.roomHash, encryptedBase64, state.nickname, state.memberId);
    
    // Clear input (message will appear via polling)
    input.value = '';
    
  } catch (e) {
    console.error('Send failed:', e);
    addSystemMessage('Failed to send message');
  } finally {
    btn.disabled = false;
    input.focus();
  }
}

async function startPolling() {
  clearInterval(state.pollInterval);
  
  async function poll() {
    try {
      const response = await pollMessages(state.roomHash, state.lastMessageTs, state.memberId);
      
      // Update connection status
      if (!state.isConnected) {
        updateConnectionStatus(true);
        addSystemMessage('Reconnected');
      }
      
      // Update expiry
      state.expiresAt = response.expires_at;
      updateChatExpiry();
      
      // Process new messages
      for (const msg of response.messages) {
        if (msg.timestamp <= state.lastMessageTs) continue;
        
        // Decrypt message content
        const encryptedBytes = Uint8Array.from(atob(msg.content), c => c.charCodeAt(0));
        const decrypted = await tryDecrypt(encryptedBytes, state.roomEmojis, state.keyMode, state.createdAt);
        
        if (decrypted !== null) {
          const isOwn = msg.sender === state.nickname;
          addMessage(msg.sender, decrypted, msg.timestamp, isOwn);
        } else {
          addMessage(msg.sender, '[Could not decrypt]', msg.timestamp, false);
        }
        
        state.lastMessageTs = msg.timestamp;
      }
      
      // Update members count
      document.getElementById('chat-members').textContent = ` · ${response.members.length} online`;
      
    } catch (e) {
      console.error('Poll failed:', e);
      updateConnectionStatus(false);
    }
  }
  
  // Initial poll
  await poll();
  
  // Continue polling
  state.pollInterval = setInterval(poll, CONFIG.POLL_INTERVAL);
}

async function leaveRoom() {
  clearInterval(state.pollInterval);
  clearInterval(state.pinTimerInterval);
  
  try {
    await leaveRoomApi(state.roomHash, state.memberId);
  } catch (e) {
    console.error('Leave failed:', e);
  }
  
  // Reset state
  state.roomHash = null;
  state.roomEmojis = null;
  state.memberId = null;
  state.encryptionKey = null;
  state.messages = [];
  
  // Hide PIN overlay
  document.getElementById('pin-overlay').classList.remove('visible');
  
  showWelcome();
}

// Make functions available globally
window.showWelcome = showWelcome;
window.showCreateRoom = showCreateRoom;
window.showJoinRoom = showJoinRoom;
window.selectMode = selectMode;
window.performSetupAction = performSetupAction;
window.sendMessage = sendMessage;
window.leaveRoom = leaveRoom;
window.removeEmojiAt = removeEmojiAt;

// Initialize
document.addEventListener('DOMContentLoaded', () => {
  console.log('SOS Web Client loaded');
  showWelcome();
});
