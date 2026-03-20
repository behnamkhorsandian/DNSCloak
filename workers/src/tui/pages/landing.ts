// ---------------------------------------------------------------------------
// Vany TUI — Landing Page
//
// Static ANSI response for: curl vany.sh
// Shows logo + endpoint table with concise descriptions.
// ---------------------------------------------------------------------------

import { GREEN, LGREEN, DIM, TEXT, BOLD, RST, ORANGE, DGRAY, BLUE, LGRAY } from "../theme.js";
import { repeat } from "../ansi.js";

const LOGO = [
    "░░▓▓▓  ░░▓▓▓ ",
    " ░▓▓▓   ░▓▓▓ ",
    " ░░▓▓▓  ▓▓▓  ",
    "  ░░░▓▓▓▓░   ",
    "  ░░▓▓  "
];

interface Row {
  endpoint: string;
  desc: string;
}

const ENDPOINTS: Row[] = [
  { endpoint: "curl vany.sh/reality",  desc: "VLESS+REALITY - TLS camouflage, no domain needed" },
  { endpoint: "curl vany.sh/ws",       desc: "VLESS+WebSocket+CDN - hides server IP via Cloudflare" },
  { endpoint: "curl vany.sh/wg",       desc: "WireGuard - fast VPN tunnel with native apps" },
  { endpoint: "curl vany.sh/dnstt",    desc: "DNS Tunnel - emergency backup for total blackouts" },
  { endpoint: "curl vany.sh/conduit",  desc: "Psiphon Relay - volunteer relay for censored regions" },
//   { endpoint: "curl vany.sh/sos",      desc: "SOS Chat - encrypted emergency chat over DNS" },
];

export function pageLanding(): string {
  const W = 72;
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

  // Table header
  const col1 = 32;
  const col2 = W - col1 - 3; // 3 for " | "
  const sep = `  ${DGRAY}${repeat("─", col1)}┬${repeat("─", col2 + 2)}${RST}`;
  const hdr = `  ${ORANGE}${BOLD}${"Endpoint".padEnd(col1)}${RST}${DGRAY}│${RST} ${ORANGE}${BOLD}Description${RST}`;

  lines.push(hdr);
  lines.push(sep);

  for (const row of ENDPOINTS) {
    const ep = `${LGREEN}${row.endpoint.padEnd(col1)}${RST}`;
    const ds = `${TEXT}${row.desc}${RST}`;
    lines.push(`  ${ep}${DGRAY}│${RST} ${ds}`);
  }

  lines.push(sep);
  lines.push("");

  // Usage hint
  lines.push(`  ${DIM}Install a protocol (beta):${RST}  ${LGREEN}curl vany.sh/reality | sudo bash${RST}`);
  lines.push(`  ${DIM}Interactive manager (beta):${RST}  ${LGREEN}curl vany.sh | sudo bash${RST}`);
  lines.push("");

  // Footer
  const footer = "github.com/behnamkhorsandian/Vanysh";
  const fPad = Math.max(0, Math.floor((W - footer.length) / 2));
  lines.push(`${repeat(" ", fPad)}${DGRAY}${footer}${RST}`);
  lines.push("");

  return lines.join("\r\n");
}
