// ---------------------------------------------------------------------------
// Vany SafeBox — Encrypted Dead-Drop with Alphanumeric Access
//
// Flow (all encryption is client-side):
//   1. Client generates 6-char box ID [A-Z0-9], user sets their own password
//   2. Client derives AES-256-GCM key via PBKDF2(boxId+":"+password, 100K iterations)
//   3. Client encrypts plaintext, computes box_hash = SHA256(boxId)[:16]
//   4. Client POSTs {box_hash, ciphertext, iv} to /box
//   5. Server stores opaque blob in KV with TTL=24h
//   6. Recipient GETs /box/:id, decrypts client-side with password
//
// Routes:
//   POST /box           → store {box_hash, ciphertext, iv}
//   GET  /box/:id       → fetch {ciphertext, iv, created_at, expires_at}
//   GET  /box           → web UI (browser) or CLI help (curl)
// ---------------------------------------------------------------------------

const CHARSET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
const BOX_ID_LENGTH = 6;
const BOX_ID_REGEX = /^[A-Z0-9]{6}$/;

/** Validate box ID: exactly 6 uppercase alphanumeric chars */
function validateBoxId(id: string): boolean {
  return BOX_ID_REGEX.test(id);
}

/** SHA-256(boxId)[:16] → KV address */
async function hashBoxId(boxId: string): Promise<string> {
  const data = new TextEncoder().encode(boxId);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, "0")).join("").slice(0, 16);
}

interface BoxData {
  ciphertext: string;
  iv: string;
  created_at: number;
  expires_at: number;
}

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

const BOX_TTL = 86400; // 24h
const MAX_CIPHERTEXT_SIZE = 100000; // ~50KB plaintext after base64

// ---- Handlers ----

/** POST /box — store encrypted box (client already encrypted) */
export async function handleBoxCreate(request: Request, kv: KVNamespace): Promise<Response> {
  let body: { box_hash?: string; ciphertext?: string; iv?: string };
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400, headers: CORS_HEADERS });
  }

  if (!body.box_hash || !body.ciphertext || !body.iv) {
    return Response.json({ error: "Missing box_hash, ciphertext, or iv" }, { status: 400, headers: CORS_HEADERS });
  }

  // Validate box_hash is hex, 16 chars
  if (!/^[0-9a-f]{16}$/.test(body.box_hash)) {
    return Response.json({ error: "Invalid box_hash format" }, { status: 400, headers: CORS_HEADERS });
  }

  if (body.ciphertext.length > MAX_CIPHERTEXT_SIZE) {
    return Response.json({ error: "Content too large (max ~50KB)" }, { status: 413, headers: CORS_HEADERS });
  }

  // Check collision
  const existing = await kv.get(`box:${body.box_hash}`);
  if (existing) {
    return Response.json({ error: "Box ID collision. Try again." }, { status: 409, headers: CORS_HEADERS });
  }

  const now = Date.now();
  const data: BoxData = {
    ciphertext: body.ciphertext,
    iv: body.iv,
    created_at: now,
    expires_at: now + BOX_TTL * 1000,
  };

  await kv.put(`box:${body.box_hash}`, JSON.stringify(data), { expirationTtl: BOX_TTL });

  return Response.json({
    ok: true,
    box_hash: body.box_hash,
    expires_at: data.expires_at,
    ttl: BOX_TTL,
  }, { headers: CORS_HEADERS });
}

/** GET /box/:id — fetch encrypted box */
export async function handleBoxFetch(boxIdSegment: string, kv: KVNamespace): Promise<Response> {
  const boxId = decodeURIComponent(boxIdSegment).toUpperCase();
  if (!validateBoxId(boxId)) {
    return Response.json(
      { error: "Invalid box ID. Use 6 characters (A-Z, 0-9), e.g. A3K9X2" },
      { status: 400, headers: CORS_HEADERS },
    );
  }

  const boxHash = await hashBoxId(boxId);
  const raw = await kv.get(`box:${boxHash}`);
  if (!raw) {
    return Response.json({ error: "Box not found or expired" }, { status: 404, headers: CORS_HEADERS });
  }

  const data: BoxData = JSON.parse(raw);
  return Response.json({
    ciphertext: data.ciphertext,
    iv: data.iv,
    created_at: data.created_at,
    expires_at: data.expires_at,
  }, { headers: CORS_HEADERS });
}

/** GET /box — web UI (browser) or CLI help (curl) */
export function handleBoxPage(isCli: boolean): Response {
  if (isCli) {
    return new Response(CLI_HELP, { headers: { ...CORS_HEADERS, "Content-Type": "text/plain; charset=utf-8" } });
  }
  return new Response(WEB_PAGE, { headers: { ...CORS_HEADERS, "Content-Type": "text/html; charset=utf-8" } });
}

const CLI_HELP = `# Vany SafeBox - Encrypted Dead-Drop
# Store encrypted text with alphanumeric box ID + your own password. Auto-expires in 24h.
# All encryption is client-side (PBKDF2 + AES-256-GCM). Server never sees plaintext.
#
# WEB INTERFACE:
#   Open https://vany.sh/box in your browser
#
# RETRIEVE A BOX:
#   curl -s "https://vany.sh/box/A3K9X2"
#
# Returns JSON: { ciphertext, iv, created_at, expires_at }
# Decrypt client-side with your password.
#
# Box ID: 6 characters (A-Z, 0-9), randomly generated
# Password: Your own text, chosen when creating the box
`;

const WEB_PAGE = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Vany SafeBox - Encrypted Dead-Drop</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>&#x1F510;</text></svg>">
<style>
:root {
  --bg: #232323; --bg2: #343434; --bg3: #404040;
  --text: #e7e7e7; --dim: #9ab0a6; --muted: #6a7a70;
  --green: #2eb787; --lgreen: #9acfa0; --blue: #6090e3;
  --orange: #d59719; --red: #a25138; --purple: #a492ff;
  --yellow: #e5e885; --border: #4a4a4a;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'SF Mono', Monaco, Consolas, monospace; background: var(--bg); color: var(--text); min-height: 100vh; display: flex; justify-content: center; padding: 20px; }
.app { max-width: 520px; width: 100%; }
h1 { color: var(--green); font-size: 18px; margin-bottom: 4px; }
.subtitle { color: var(--dim); font-size: 12px; margin-bottom: 24px; }
.section { background: var(--bg2); border: 1px solid var(--border); padding: 16px; margin-bottom: 16px; }
.section h2 { color: var(--orange); font-size: 13px; margin-bottom: 12px; border-bottom: 1px solid var(--border); padding-bottom: 8px; }
label { display: block; color: var(--dim); font-size: 11px; margin-bottom: 4px; }
textarea { width: 100%; background: var(--bg); border: 1px solid var(--border); color: var(--text); font-family: inherit; font-size: 12px; padding: 10px; resize: vertical; min-height: 100px; }
textarea:focus { outline: none; border-color: var(--green); }
.btn { display: inline-block; padding: 10px 20px; font-family: inherit; font-size: 12px; cursor: pointer; border: 1px solid var(--border); background: var(--bg); color: var(--green); transition: all 0.15s; }
.btn:hover { border-color: var(--green); background: rgba(46,183,135,0.1); }
.btn:disabled { opacity: 0.4; cursor: not-allowed; }
.btn-primary { background: var(--green); color: var(--bg); border-color: var(--green); }
.btn-primary:hover { background: #25a078; }
.id-display { font-size: 28px; letter-spacing: 6px; text-align: center; padding: 12px; background: var(--bg); border: 1px solid var(--border); margin: 8px 0; user-select: all; font-weight: bold; color: var(--green); }
.result-box { background: var(--bg); border: 1px solid var(--green); padding: 16px; margin: 12px 0; }
.result-box .label { color: var(--orange); font-size: 11px; margin-bottom: 4px; }
.result-box .value { color: var(--lgreen); font-size: 11px; word-break: break-all; }
input[type=text], input[type=password] { width: 100%; background: var(--bg); border: 1px solid var(--border); color: var(--text); font-family: inherit; font-size: 12px; padding: 10px; }
input[type=text]:focus, input[type=password]:focus { outline: none; border-color: var(--green); }
.status { padding: 8px 12px; font-size: 11px; margin: 8px 0; }
.status.ok { background: rgba(46,183,135,0.1); border: 1px solid var(--green); color: var(--green); }
.status.err { background: rgba(162,81,56,0.1); border: 1px solid var(--red); color: var(--red); }
.status.warn { background: rgba(213,151,25,0.1); border: 1px solid var(--orange); color: var(--orange); }
.ttl { color: var(--yellow); font-size: 11px; text-align: center; }
.row { display: flex; gap: 8px; margin-top: 8px; }
.row .btn { flex: 1; text-align: center; }
.hidden { display: none; }
.tab-bar { display: flex; border-bottom: 1px solid var(--border); margin-bottom: 16px; }
.tab { flex: 1; padding: 10px; text-align: center; font-size: 12px; color: var(--dim); cursor: pointer; border-bottom: 2px solid transparent; }
.tab.active { color: var(--green); border-bottom-color: var(--green); }
.tab:hover { color: var(--text); }
.footer { text-align: center; margin-top: 24px; }
.footer a { color: var(--blue); text-decoration: none; font-size: 11px; }
.copy-btn { cursor: pointer; color: var(--dim); font-size: 11px; }
.copy-btn:hover { color: var(--green); }
.pass-label { color: var(--dim); font-size: 11px; text-align: center; margin-bottom: 8px; }
</style>
</head>
<body>
<div class="app">
  <h1>&#x1F510; Vany SafeBox</h1>
  <p class="subtitle">Encrypted dead-drop. 6-char box ID + your password. Auto-expires in 24h.</p>

  <div class="tab-bar">
    <div class="tab active" onclick="switchTab('create')" id="tab-create">Create Box</div>
    <div class="tab" onclick="switchTab('open')" id="tab-open">Open Box</div>
  </div>

  <!-- CREATE TAB -->
  <div id="panel-create">
    <div class="section">
      <h2>DROP YOUR SECRET</h2>
      <label>Message (encrypted client-side, server never sees plaintext)</label>
      <textarea id="msg-input" placeholder="Type or paste your secret text here..." maxlength="50000"></textarea>
      <div style="text-align:right;margin-top:4px;"><span id="char-count" style="color:var(--muted);font-size:10px;">0 / 50,000</span></div>
      <label style="margin-top:8px;">Password (you choose — remember it to decrypt later)</label>
      <input type="text" id="create-password" placeholder="Enter a password..." />
      <div class="row">
        <button class="btn btn-primary" id="create-btn" onclick="createBox()">Create SafeBox</button>
      </div>
    </div>
    <div id="create-result" class="hidden">
      <div class="section">
        <h2>YOUR BOX CREDENTIALS</h2>
        <div class="status warn">Save these! They cannot be recovered. Box expires in 24 hours.</div>
        <div class="result-box">
          <div class="label">BOX ID (share this)</div>
          <div class="id-display" id="res-box-id"></div>
        </div>
        <div class="result-box">
          <div class="label">PASSWORD (keep secret)</div>
          <div class="pass-label" id="res-password"></div>
        </div>
        <div class="result-box">
          <div class="label">CLI COMMAND <span class="copy-btn" onclick="copyCli()">[copy]</span></div>
          <div class="value" id="res-cli" style="font-size:10px;"></div>
        </div>
        <div class="ttl" id="res-ttl"></div>
      </div>
    </div>
  </div>

  <!-- OPEN TAB -->
  <div id="panel-open" class="hidden">
    <div class="section">
      <h2>OPEN A BOX</h2>
      <label>Box ID (6 characters, A-Z / 0-9)</label>
      <input type="text" id="open-box-id" placeholder="e.g. A3K9X2" maxlength="6" style="text-transform:uppercase;letter-spacing:4px;font-size:16px;text-align:center;" />
      <label style="margin-top:8px;">Password</label>
      <input type="text" id="open-password" placeholder="Enter the password..." />
      <div class="row">
        <button class="btn btn-primary" onclick="openBox()">Decrypt</button>
      </div>
    </div>
    <div id="open-result" class="hidden">
      <div class="section">
        <h2>DECRYPTED CONTENT</h2>
        <textarea id="open-content" readonly style="min-height:150px;color:var(--lgreen);"></textarea>
        <div class="ttl" id="open-ttl" style="margin-top:8px;"></div>
      </div>
    </div>
    <div id="open-error" class="hidden">
      <div class="status err" id="open-error-msg"></div>
    </div>
  </div>

  <div class="footer">
    <a href="https://vany.sh">vany.sh</a> &middot; <a href="https://github.com/behnamkhorsandian/Vanysh">github</a>
    <br><span style="color:var(--muted);font-size:10px;">All crypto runs in your browser. Server stores only ciphertext.</span>
  </div>
</div>

<script>
const CHARSET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

function generateId() {
  const a = new Uint32Array(6);
  crypto.getRandomValues(a);
  return Array.from(a, v => CHARSET[v % CHARSET.length]).join("");
}

async function boxHash(id) {
  const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(id));
  return Array.from(new Uint8Array(h)).map(b => b.toString(16).padStart(2,"0")).join("").slice(0,16);
}

async function deriveKey(boxId, pass) {
  const raw = new TextEncoder().encode(boxId + ":" + pass);
  const km = await crypto.subtle.importKey("raw", raw, "PBKDF2", false, ["deriveKey"]);
  return crypto.subtle.deriveKey(
    { name: "PBKDF2", salt: new TextEncoder().encode("vany-safebox-v1"), iterations: 100000, hash: "SHA-256" },
    km, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]
  );
}

async function enc(text, boxId, pass) {
  const key = await deriveKey(boxId, pass);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(text));
  return { ct: btoa(String.fromCharCode(...new Uint8Array(ct))), iv: btoa(String.fromCharCode(...iv)) };
}

async function dec(ct64, iv64, boxId, pass) {
  const key = await deriveKey(boxId, pass);
  const ct = Uint8Array.from(atob(ct64), c => c.charCodeAt(0));
  const iv = Uint8Array.from(atob(iv64), c => c.charCodeAt(0));
  return new TextDecoder().decode(await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ct));
}

function switchTab(tab) {
  document.getElementById("panel-create").classList.toggle("hidden", tab !== "create");
  document.getElementById("panel-open").classList.toggle("hidden", tab !== "open");
  document.getElementById("tab-create").classList.toggle("active", tab === "create");
  document.getElementById("tab-open").classList.toggle("active", tab === "open");
}
document.getElementById("msg-input").addEventListener("input", function() {
  document.getElementById("char-count").textContent = this.value.length + " / 50,000";
});

async function createBox() {
  const msg = document.getElementById("msg-input").value.trim();
  const pass = document.getElementById("create-password").value;
  if (!msg) return;
  if (!pass) { alert("Please enter a password."); return; }
  const btn = document.getElementById("create-btn");
  btn.disabled = true; btn.textContent = "Encrypting...";
  try {
    const boxId = generateId();
    const { ct, iv } = await enc(msg, boxId, pass);
    const bh = await boxHash(boxId);
    const resp = await fetch("/box", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ box_hash: bh, ciphertext: ct, iv })
    });
    const data = await resp.json();
    if (!resp.ok) throw new Error(data.error || "Failed");
    document.getElementById("res-box-id").textContent = boxId;
    document.getElementById("res-password").textContent = pass;
    document.getElementById("res-cli").textContent = 'curl -s "https://vany.sh/box/' + boxId + '"';
    document.getElementById("res-ttl").textContent = "Expires: " + new Date(data.expires_at).toLocaleString();
    document.getElementById("create-result").classList.remove("hidden");
  } catch (e) { alert("Error: " + e.message); }
  finally { btn.disabled = false; btn.textContent = "Create SafeBox"; }
}

async function openBox() {
  const boxId = document.getElementById("open-box-id").value.trim().toUpperCase();
  const pass = document.getElementById("open-password").value;
  document.getElementById("open-result").classList.add("hidden");
  document.getElementById("open-error").classList.add("hidden");
  if (!/^[A-Z0-9]{6}$/.test(boxId)) { showErr("Invalid box ID. Must be 6 characters (A-Z, 0-9)."); return; }
  if (!pass) { showErr("Please enter the password."); return; }
  try {
    const resp = await fetch("/box/" + encodeURIComponent(boxId));
    const data = await resp.json();
    if (!resp.ok) throw new Error(data.error || "Box not found");
    const text = await dec(data.ciphertext, data.iv, boxId, pass);
    document.getElementById("open-content").value = text;
    document.getElementById("open-ttl").textContent = "Expires: " + new Date(data.expires_at).toLocaleString();
    document.getElementById("open-result").classList.remove("hidden");
  } catch (e) {
    if (e.name === "OperationError") showErr("Wrong password.");
    else showErr(e.message);
  }
}

function showErr(msg) {
  document.getElementById("open-error-msg").textContent = msg;
  document.getElementById("open-error").classList.remove("hidden");
}
function copyCli() {
  navigator.clipboard.writeText(document.getElementById("res-cli").textContent);
  document.querySelector(".copy-btn").textContent = "[copied!]";
  setTimeout(() => document.querySelector(".copy-btn").textContent = "[copy]", 2000);
}

// Direct open via URL params: ?id=A3K9X2&pass=mypassword
const sp = new URLSearchParams(location.search);
if (sp.has("id") && sp.has("pass")) {
  switchTab("open");
  document.getElementById("open-box-id").value = sp.get("id");
  document.getElementById("open-password").value = sp.get("pass");
  openBox();
}
</script>
</body>
</html>`;
