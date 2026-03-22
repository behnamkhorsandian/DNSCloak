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
    "   ░░▓▓  "
];

// Star rating helper
function stars(n: number): string {
  const filled = "■".repeat(n);
  const empty = "·".repeat(5 - n);
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
  port: string;
  domain: string;
  resilience: number;
  speed: number;
  note: string;
}

const SERVER_PROTOCOLS: LandingProto[] = [
  { name: "VLESS+REALITY",   port: "443",    domain: "No",  resilience: 4, speed: 5, note: "Recommended. TLS camouflage" },
  { name: "VLESS+WS+CDN",    port: "80",     domain: "Yes", resilience: 5, speed: 4, note: "IP hidden behind Cloudflare" },
  { name: "Hysteria v2",     port: "UDP",    domain: "No",  resilience: 3, speed: 5, note: "QUIC-based, fastest protocol" },
  { name: "WireGuard",       port: "51820",  domain: "No",  resilience: 2, speed: 5, note: "Full device VPN tunnel" },
  { name: "VLESS+TLS",       port: "443",    domain: "Yes", resilience: 4, speed: 5, note: "Classic V2Ray + real certs" },
  { name: "HTTP Obfuscation",port: "80",     domain: "CDN", resilience: 5, speed: 4, note: "Host header spoofing via CDN" },
  { name: "MTProto",         port: "443",    domain: "No",  resilience: 3, speed: 4, note: "Telegram only, no extra app" },
  { name: "SSH Tunnel",      port: "22",     domain: "No",  resilience: 2, speed: 3, note: "Basic, universally available" },
];

const EMERGENCY_PROTOCOLS: LandingProto[] = [
  { name: "DNSTT",           port: "53",     domain: "Yes", resilience: 5, speed: 1, note: "~42 KB/s, last resort tunnel" },
  { name: "Slipstream",      port: "53",     domain: "Yes", resilience: 5, speed: 2, note: "~63 KB/s, QUIC+TLS over DNS" },
  { name: "NoizDNS",         port: "53",     domain: "Yes", resilience: 5, speed: 2, note: "DPI-resistant DNSTT fork" },
];

const RELAY_PROTOCOLS: LandingProto[] = [
  { name: "Conduit",         port: "auto",   domain: "No",  resilience: 5, speed: 4, note: "Psiphon volunteer relay" },
  { name: "Tor Bridge",      port: "9001",   domain: "No",  resilience: 4, speed: 2, note: "obfs4 bridge for Tor network" },
  { name: "Snowflake",       port: "--",     domain: "No",  resilience: 4, speed: 2, note: "WebRTC Tor relay, zero config" },
  { name: "SOS Chat",        port: "8899",   domain: "Yes", resilience: 5, speed: 1, note: "E2E encrypted emergency chat" },
];

interface ToolDef {
  name: string;
  purpose: string;
  runsFrom: string;
}

const CLIENT_TOOLS: ToolDef[] = [
  { name: "VPN Connect",   purpose: "Connect to any VPN protocol",     runsFrom: "Client menu (paste config link)" },
  { name: "cfray",         purpose: "Find clean Cloudflare IPs",       runsFrom: "Tools menu (run from Iran)" },
  { name: "findns",        purpose: "Find working DNS resolvers",      runsFrom: "Tools menu (run from Iran)" },
  { name: "IP Tracer",     purpose: "Trace route, show ASNs and ISPs", runsFrom: "Tools menu" },
  { name: "Speed Test",    purpose: "Test VPN connection throughput",   runsFrom: "Tools menu" },
  { name: "Config Import", purpose: "Paste VLESS/WG/Hysteria config",  runsFrom: "Client menu" },
];

function renderProtoTable(protocols: LandingProto[], W: number): string[] {
  const lines: string[] = [];
  // Column widths
  const cName = 18, cPort = 7, cDom = 8, cRes = 11, cSpd = 11, cNote = W - cName - cPort - cDom - cRes - cSpd - 15;

  // Header
  const hdr = `  ${ORANGE}${BOLD}${"Protocol".padEnd(cName)}${RST}`
    + `${DGRAY}│${RST} ${ORANGE}${BOLD}${"Port".padEnd(cPort)}${RST}`
    + `${DGRAY}│${RST} ${ORANGE}${BOLD}${"Domain".padEnd(cDom)}${RST}`
    + `${DGRAY}│${RST} ${ORANGE}${BOLD}${"Resist.".padEnd(cRes)}${RST}`
    + `${DGRAY}│${RST} ${ORANGE}${BOLD}${"Speed".padEnd(cSpd)}${RST}`
    + `${DGRAY}│${RST} ${ORANGE}${BOLD}Notes${RST}`;
  lines.push(hdr);

  const sep = `  ${DGRAY}${repeat("─", cName)}┼${repeat("─", cPort + 2)}┼${repeat("─", cDom + 2)}┼${repeat("─", cRes + 2)}┼${repeat("─", cSpd + 2)}┼${repeat("─", Math.max(cNote, 10))}${RST}`;
  lines.push(sep);

  for (const p of protocols) {
    const row = `  ${LGREEN}${p.name.padEnd(cName)}${RST}`
      + `${DGRAY}│${RST} ${DIM}${p.port.padEnd(cPort)}${RST}`
      + `${DGRAY}│${RST} ${DIM}${p.domain.padEnd(cDom)}${RST}`
      + `${DGRAY}│${RST} ${stars(p.resilience)}  `
      + `${DGRAY}│${RST} ${stars(p.speed)}  `
      + `${DGRAY}│${RST} ${TEXT}${p.note}${RST}`;
    lines.push(row);
  }
  return lines;
}

export function pageLanding(): string {
  const W = 90;
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
  lines.push(`  ${ORANGE}${BOLD}${"Tool".padEnd(tName)}${RST}${DGRAY}│${RST} ${ORANGE}${BOLD}${"Purpose".padEnd(tPurp)}${RST}${DGRAY}│${RST} ${ORANGE}${BOLD}Runs From${RST}`);
  lines.push(`  ${DGRAY}${repeat("─", tName)}┼${repeat("─", tPurp + 2)}┼${repeat("─", 34)}${RST}`);
  for (const t of CLIENT_TOOLS) {
    lines.push(`  ${LGREEN}${t.name.padEnd(tName)}${RST}${DGRAY}│${RST} ${TEXT}${t.purpose.padEnd(tPurp)}${RST}${DGRAY}│${RST} ${DIM}${t.runsFrom}${RST}`);
  }
  lines.push("");

  // Quick install
  lines.push(divider("QUICK INSTALL", W));
  lines.push("");
  lines.push(`    ${LGREEN}curl vany.sh/reality | sudo bash${RST}   ${DIM}Install REALITY on your VPS${RST}`);
  lines.push(`    ${LGREEN}curl vany.sh/ws | sudo bash${RST}        ${DIM}Install WS+CDN on your VPS${RST}`);
  lines.push(`    ${LGREEN}curl vany.sh/hysteria | sudo bash${RST}  ${DIM}Install Hysteria v2 on your VPS${RST}`);
  lines.push(`    ${LGREEN}curl vany.sh/wg | sudo bash${RST}        ${DIM}Install WireGuard on your VPS${RST}`);
  lines.push("");

  // Rating legend
  lines.push(`  ${DIM}Ratings: ${GREEN}■${RST}${DIM} = capability level out of 5    Resist. = censorship resilience    Speed = throughput${RST}`);
  lines.push("");

  // Footer
  const gh = "github.com/behnamkhorsandian/Vanysh";
  const web = "https://vany.sh";
  const footer = `${BLUE}${gh}${RST}${DIM}  |  ${RST}${BLUE}${web}${RST}`;
  lines.push(`  ${footer}`);
  lines.push("");

  return lines.join("\r\n");
}
