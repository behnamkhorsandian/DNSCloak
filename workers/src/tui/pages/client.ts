// ---------------------------------------------------------------------------
// Vany TUI — Client Page
// Connect to VPN protocols from terminal (client mode).
// ---------------------------------------------------------------------------

import { GREEN, ORANGE, RED, BOLD, DIM, TEXT, LGREEN, DGRAY, RST, BLUE } from "../theme.js";
import { keyHint } from "../layout.js";
import { repeat } from "../ansi.js";

interface ClientProtocol {
  name: string;
  app: string;
  connectCmd: string;
}

const CLIENT_PROTOCOLS: ClientProtocol[] = [
  {
    name: "VLESS+REALITY",
    app: "Hiddify / Nekoray / sing-box",
    connectCmd: "Paste vless:// link into Hiddify",
  },
  {
    name: "VLESS+WS+CDN",
    app: "Hiddify / Nekoray / sing-box",
    connectCmd: "Paste vless:// link into Hiddify",
  },
  {
    name: "Hysteria v2",
    app: "Hiddify / Nekoray / sing-box",
    connectCmd: "Paste hysteria2:// link into Hiddify",
  },
  {
    name: "WireGuard",
    app: "WireGuard (official)",
    connectCmd: "Import .conf file or scan QR code",
  },
  {
    name: "HTTP Obfuscation",
    app: "Hiddify / Nekoray",
    connectCmd: "Paste vless:// link + set clean IP as address",
  },
  {
    name: "SSH Tunnel",
    app: "Built-in SSH",
    connectCmd: "ssh -D 1080 user@server",
  },
];

/** Render the client connection page */
export function pageClient(
  subpage: string,
  state: Record<string, unknown> = {},
): string {
  if (subpage === "import") {
    return pageImport();
  }
  return clientOverview();
}

function clientOverview(): string {
  const lines: string[] = [];

  lines.push(`  ${BOLD}${GREEN}CLIENT MODE${RST}`);
  lines.push(`  ${DIM}Connect to VPN protocols from your terminal${RST}`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}HOW TO CONNECT${RST}`);
  lines.push("");
  lines.push(`    ${GREEN}1.${RST} ${TEXT}Get your connection link from the VPS owner${RST}`);
  lines.push(`    ${GREEN}2.${RST} ${TEXT}Download the recommended client app for your platform${RST}`);
  lines.push(`    ${GREEN}3.${RST} ${TEXT}Import the link and connect${RST}`);
  lines.push("");

  // Protocol table
  const cName = 18, cApp = 30;
  lines.push(`  ${BOLD}${ORANGE}SUPPORTED PROTOCOLS${RST}`);
  lines.push("");
  lines.push(`    ${ORANGE}${"Protocol".padEnd(cName)}${RST}${DGRAY}│${RST} ${ORANGE}${"Client App".padEnd(cApp)}${RST}${DGRAY}│${RST} ${ORANGE}Connect${RST}`);
  lines.push(`    ${DGRAY}${repeat("─", cName)}┼${repeat("─", cApp + 2)}┼${repeat("─", 40)}${RST}`);

  for (const p of CLIENT_PROTOCOLS) {
    lines.push(`    ${LGREEN}${p.name.padEnd(cName)}${RST}${DGRAY}│${RST} ${DIM}${p.app.padEnd(cApp)}${RST}${DGRAY}│${RST} ${TEXT}${p.connectCmd}${RST}`);
  }
  lines.push("");

  // Recommended apps
  lines.push(`  ${BOLD}${ORANGE}RECOMMENDED APPS${RST}`);
  lines.push("");
  lines.push(`    ${LGREEN}Hiddify${RST}     ${DIM}iOS / Android / Windows / macOS / Linux${RST}`);
  lines.push(`                 ${BLUE}https://hiddify.com${RST}`);
  lines.push(`    ${LGREEN}Nekoray${RST}     ${DIM}Windows / Linux${RST}`);
  lines.push(`                 ${BLUE}https://github.com/MatsuriDayo/nekoray${RST}`);
  lines.push(`    ${LGREEN}WireGuard${RST}   ${DIM}iOS / Android / Windows / macOS / Linux${RST}`);
  lines.push(`                 ${BLUE}https://wireguard.com/install${RST}`);
  lines.push("");

  lines.push(`  ${keyHint("m", "import config")}  ${keyHint("f", "cfray scanner")}  ${keyHint("Esc", "back")}`);

  return lines.join("\r\n");
}

function pageImport(): string {
  const lines: string[] = [];

  lines.push(`  ${BOLD}${GREEN}IMPORT CONFIG${RST}`);
  lines.push(`  ${DIM}Paste a connection link to connect${RST}`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}SUPPORTED FORMATS${RST}`);
  lines.push("");
  lines.push(`    ${LGREEN}vless://${RST}${DIM}...${RST}       VLESS (Reality, WS, TLS)`);
  lines.push(`    ${LGREEN}hysteria2://${RST}${DIM}...${RST}   Hysteria v2`);
  lines.push(`    ${LGREEN}wg://${RST}${DIM}...${RST}          WireGuard`);
  lines.push(`    ${LGREEN}ss://${RST}${DIM}...${RST}          Shadowsocks`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}USAGE${RST}`);
  lines.push("");
  lines.push(`    ${TEXT}1. Copy the connection link from your VPS owner${RST}`);
  lines.push(`    ${TEXT}2. Paste into your client app (Hiddify, Nekoray)${RST}`);
  lines.push(`    ${TEXT}3. Or use: ${LGREEN}curl vany.sh | bash${RST} ${TEXT}and paste when prompted${RST}`);
  lines.push("");

  lines.push(`  ${keyHint("Esc", "back")}`);

  return lines.join("\r\n");
}
