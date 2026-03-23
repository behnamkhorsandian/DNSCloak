// ---------------------------------------------------------------------------
// Vany TUI — Landing Page
//
// Static ANSI response for: curl vany.sh
// Full protocol catalog with comparison tables, ratings, and usage guide.
// ---------------------------------------------------------------------------

import { GREEN, LGREEN, DIM, TEXT, BOLD, RST, ORANGE, DGRAY, BLUE, LGRAY, YELLOW, PURPLE, RED } from "../theme.js";
import { repeat } from "../ansi.js";

const LOGO = [
    "░░▓▓▓  ░░▓▓▓ ",
    " ░▓▓▓   ░▓▓▓ ",
    " ░░▓▓▓  ▓▓▓  ",
    "  ░░░▓▓▓▓░   ",
    "    ░░▓▓     "
];

// Star rating helper
function stars(n: number): string {
  const filled = "■".repeat(n);
  const empty = "□".repeat(5 - n);
  return `${GREEN}${filled}${RST}${DGRAY}${empty}${RST}`;
}

// Render a section divider
function divider(title: string, W: number): string {
  const titleLen = title.length + 2;
  const lineLen = Math.max(0, W - titleLen - 4);
  const left = Math.floor(lineLen / 2);
  const right = lineLen - left;
  return `  ${DGRAY}${repeat("─", left)}${RST} ${ORANGE}${BOLD}${title}${RST} ${DGRAY}${repeat("─", right)}${RST}`;
}

// Protocol definition for the landing table
interface LandingProto {
  name: string;
  slug: string;
  desc: string;
  port: string;
  domain: string;
  resilience: number;
  speed: number;
}

const SERVER_PROTOCOLS: LandingProto[] = [
  { name: "VLESS+REALITY",   slug: "reality",    desc: "TLS camouflage, borrows certs",  port: "443",    domain: "No",  resilience: 4, speed: 5 },
  { name: "VLESS+WS+CDN",    slug: "ws",         desc: "WebSocket behind Cloudflare",    port: "80",     domain: "Yes", resilience: 5, speed: 4 },
  { name: "Hysteria v2",     slug: "hysteria",    desc: "QUIC, fast on lossy networks",   port: "UDP",    domain: "No",  resilience: 3, speed: 5 },
  { name: "WireGuard",       slug: "wg",          desc: "Kernel-level full-device VPN",   port: "51820",  domain: "No",  resilience: 2, speed: 5 },
  { name: "VLESS+TLS",       slug: "vray",        desc: "V2Ray with real TLS certs",      port: "443",    domain: "Yes", resilience: 4, speed: 5 },
  { name: "HTTP Obfuscation",slug: "http-obfs",   desc: "CDN host header spoofing",       port: "80",     domain: "CDN", resilience: 5, speed: 4 },
  { name: "MTProto",         slug: "mtp",         desc: "Telegram-only, Fake-TLS",        port: "443",    domain: "No",  resilience: 3, speed: 4 },
  { name: "SSH Tunnel",      slug: "ssh-tunnel",  desc: "Basic SOCKS5 over SSH",          port: "22",     domain: "No",  resilience: 2, speed: 3 },
];

const EMERGENCY_PROTOCOLS: LandingProto[] = [
  { name: "DNSTT",           slug: "dnstt",       desc: "DNS tunnel, works in shutdowns", port: "53",     domain: "Yes", resilience: 5, speed: 1 },
  { name: "Slipstream",      slug: "slipstream",  desc: "Fast DNS tunnel with QUIC",      port: "53",     domain: "Yes", resilience: 5, speed: 2 },
  { name: "NoizDNS",         slug: "noizdns",     desc: "DPI-resistant DNS tunnel",       port: "53",     domain: "Yes", resilience: 5, speed: 2 },
];

const RELAY_PROTOCOLS: LandingProto[] = [
  { name: "Conduit",         slug: "conduit",     desc: "Psiphon relay, auto-config",     port: "auto",   domain: "No",  resilience: 5, speed: 4 },
  { name: "Tor Bridge",      slug: "tor-bridge",  desc: "obfs4 bridge for Tor network",   port: "9001",   domain: "No",  resilience: 4, speed: 2 },
  { name: "Snowflake",       slug: "snowflake",   desc: "WebRTC Tor relay, zero conf",    port: "--",     domain: "No",  resilience: 4, speed: 2 },
  { name: "SafeBox",         slug: "box",         desc: "Encrypted dead-drop, 24h TTL",   port: "443",    domain: "No",  resilience: 5, speed: 5 },
];

interface ToolDef {
  name: string;
  slug: string;
  purpose: string;
}

const CLIENT_TOOLS: ToolDef[] = [
  { name: "IP Tracer",     slug: "tools/tracer",    purpose: "Trace IP, ISP, ASN, detect VPN" },
  { name: "CFRay Scanner", slug: "tools/cfray",     purpose: "Find clean Cloudflare IPs" },
  { name: "FindNS",        slug: "tools/findns",    purpose: "Discover working DNS resolvers" },
  { name: "Speed Test",    slug: "tools/speedtest",  purpose: "Test bandwidth via Cloudflare" },
];

function renderProtoTable(protocols: LandingProto[], W: number): string[] {
  const lines: string[] = [];
  const cName = 18, cDesc = 30, cPort = 7, cDom = 5, cRes = 7, cSpd = 7;

  // Header
  lines.push(`  ${ORANGE}${BOLD}${"Protocol".padEnd(cName)}${"Description".padEnd(cDesc)}${"Port".padEnd(cPort)} ${"Dom".padEnd(cDom)}${"Res".padEnd(cRes)}${"Spd".padEnd(cSpd)}${RST}${ORANGE}${BOLD}Install${RST}`);
  lines.push(`  ${DGRAY}${repeat("─", cName)}${repeat("─", cDesc)}${repeat("─", cPort + 1)}${repeat("─", cDom + 1)}${repeat("─", cRes)}${repeat("─", cSpd)}${repeat("─", 30)}${RST}`);

  for (const p of protocols) {
    const dom = p.domain === "No" ? "-" : p.domain;
    const cmd = `curl vany.sh/${p.slug} | sudo bash`;
    const row = `  ${LGREEN}${p.name.padEnd(cName)}${RST}`
      + `${DIM}${p.desc.padEnd(cDesc)}${RST}`
      + `${TEXT}${p.port.padEnd(cPort)}${RST} `
      + `${TEXT}${dom.padEnd(cDom)}${RST}`
      + `${stars(p.resilience)} `
      + `${stars(p.speed)} `
      + `${DIM}${cmd}${RST}`;
    lines.push(row);
  }
  return lines;
}

export function pageLanding(): string {
  const W = 120;
  const lines: string[] = [];

  // Logo
  lines.push("");
  for (const l of LOGO) {
    const pad = Math.max(0, Math.floor((W - l.length) / 2));
    lines.push(`${repeat(" ", pad)}${GREEN}${l}${RST}`);
  }
  lines.push("");

  // Tagline
  const tagline = "Multi-protocol censorship bypass platform";
  const tagPad = Math.max(0, Math.floor((W - tagline.length) / 2));
  lines.push(`${repeat(" ", tagPad)}${DIM}${tagline}${RST}`);
  lines.push("");

  // Usage
  lines.push(`  ${BOLD}${ORANGE}USAGE${RST}`);
  lines.push(`    ${LGREEN}curl vany.sh | sudo bash${RST}   ${TEXT}Server mode - install protocols on your VPS${RST}`);
  lines.push(`    ${LGREEN}curl vany.sh | bash${RST}        ${TEXT}Client mode - connect to VPN from terminal${RST}`);
  lines.push("");

  // Server protocols
  lines.push(divider("SERVER PROTOCOLS", W));
  lines.push("");
  lines.push(...renderProtoTable(SERVER_PROTOCOLS, W));
  lines.push("");

  // Emergency / DNS tunnels
  lines.push(divider("EMERGENCY / DNS TUNNELS", W));
  lines.push("");
  lines.push(...renderProtoTable(EMERGENCY_PROTOCOLS, W));
  lines.push("");

  // Relay / community
  lines.push(divider("RELAY / COMMUNITY", W));
  lines.push("");
  lines.push(...renderProtoTable(RELAY_PROTOCOLS, W));
  lines.push("");

  // Client tools
  lines.push(divider("CLIENT TOOLS", W));
  lines.push("");
  const tName = 16, tPurp = 36;
  lines.push(`  ${ORANGE}${BOLD}${"Tool".padEnd(tName)}${RST}${DGRAY}│${RST} ${ORANGE}${BOLD}${"Purpose".padEnd(tPurp)}${RST}${DGRAY}│${RST} ${ORANGE}${BOLD}Command${RST}`);
  lines.push(`  ${DGRAY}${repeat("─", tName)}┼${repeat("─", tPurp + 1)}┼${repeat("─", 34)}${RST}`);
  for (const t of CLIENT_TOOLS) {
    const cmd = `curl vany.sh/${t.slug} | bash`;
    lines.push(`  ${LGREEN}${t.name.padEnd(tName)}${RST}${DGRAY}│${RST} ${TEXT}${t.purpose.padEnd(tPurp)}${RST}${DGRAY}│${RST} ${DIM}${cmd}${RST}`);
  }
  lines.push("");

  // Help choosing
  lines.push(divider("NEED HELP CHOOSING?", W));
  lines.push("");
  lines.push(`    ${LGREEN}curl vany.sh/choose | bash${RST}   ${DIM}Interactive questionnaire to pick the right protocol${RST}`);
  lines.push("");

  // Free services
  lines.push(divider("FREE SERVICES", W));
  lines.push("");
  lines.push(`  ${ORANGE}${BOLD}Free VPN (WS+CDN)${RST}       ${DIM}No account, no VPS needed. 1-hour sessions.${RST}`);
  lines.push(`    ${LGREEN}1.${RST} ${TEXT}Open ${BLUE}https://vany.sh${RST}  ${DIM}and click${RST} ${LGREEN}Quick Connect${RST}`);
  lines.push(`    ${LGREEN}2.${RST} ${TEXT}Hit${RST} ${LGREEN}Generate${RST}${TEXT}, copy the link${RST}`);
  lines.push(`    ${LGREEN}3.${RST} ${TEXT}Paste into ${BLUE}Hiddify${RST} ${DIM}(iOS/Android/Windows/macOS/Linux)${RST}`);
  lines.push("");
  lines.push(`  ${ORANGE}${BOLD}SafeBox (Encrypted Dead-Drop)${RST}  ${DIM}Share secrets with a 6-char box ID + password. 24h TTL.${RST}`);
  lines.push(`    ${LGREEN}Browser:${RST}  ${TEXT}Open ${BLUE}https://vany.sh${RST} ${DIM}and click the${RST} ${PURPLE}lock icon${RST}`);
  lines.push(`    ${LGREEN}CLI:${RST}      ${DIM}curl -s vany.sh/box${RST}   ${TEXT}(view help and create/open boxes)${RST}`);
  lines.push("");

  // Rating legend
  lines.push(`  ${DIM}Ratings: ${GREEN}■${RST}${DIM} = capability level out of 5    Resist. = censorship resilience    Speed = throughput${RST}`);
  lines.push("");

  // Unstoppable access
  lines.push(divider("CAN'T CONNECT?", W));
  lines.push("");
  lines.push(`  ${ORANGE}${BOLD}Rescue bootstrap${RST}  ${DIM}Tries all access methods automatically:${RST}`);
  lines.push(`    ${LGREEN}curl -m5 vany.sh/bootstrap | sudo bash${RST}`);
  lines.push("");
  lines.push(`  ${ORANGE}${BOLD}Manual fallbacks${RST}  ${DIM}(try in order if above fails):${RST}`);
  lines.push(`    ${LGREEN}1.${RST} ${DIM}curl --doh-url https://1.1.1.1/dns-query vany.sh | sudo bash${RST}   ${TEXT}(DNS-over-HTTPS)${RST}`);
  lines.push(`    ${LGREEN}2.${RST} ${DIM}curl vany-agg.pages.dev | sudo bash${RST}                           ${TEXT}(shared CF domain)${RST}`);
  lines.push(`    ${LGREEN}3.${RST} ${DIM}Install 1.1.1.1 app (WARP), enable, then curl vany.sh${RST}         ${TEXT}(free CF VPN)${RST}`);
  lines.push("");

  // Footer
  const gh = "github.com/behnamkhorsandian/Vanysh";
  const web = "https://vany.sh";
  const footer = `${BLUE}${gh}${RST}${DIM}  |  ${RST}${BLUE}${web}${RST}`;
  lines.push(`  ${footer}`);
  lines.push("");

  return lines.join("\n");
}

/** Root polyglot: valid bash + clean ANSI catalog.
 *  curl vany.sh           → ANSI hides 2-line preamble, renders catalog
 *  curl vany.sh | sudo bash → exec replaces shell with full TUI (start.sh)
 *  curl vany.sh | bash      → exits cleanly (not root)
 */
export function pageLandingBash(): string {
  const catalog = pageLanding();
  // ESC[2A = cursor up 2 lines, ESC[J = erase from cursor to end of screen
  // This overwrites the 2 bash lines so they're invisible in terminal output
  const cleanup = "\x1b[2A\x1b[J";
  return `#!/bin/bash
[[ \$(id -u) -eq 0 ]] && exec bash <(curl -sSf https://start.vany.sh/ 2>/dev/null); exit 0
${cleanup}${catalog}`;
}
