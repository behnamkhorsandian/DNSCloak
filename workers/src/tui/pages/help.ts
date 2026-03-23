// ---------------------------------------------------------------------------
// Vany TUI — Help Page
// ---------------------------------------------------------------------------

import { GREEN, ORANGE, BOLD, DIM, TEXT, LGREEN, DGRAY, BLUE, RST } from "../theme.js";
import { box } from "../box.js";
import { keyHint } from "../layout.js";
import { repeat } from "../ansi.js";

function stars(n: number): string {
  const filled = "■".repeat(n);
  const empty = "·".repeat(5 - n);
  return `${GREEN}${filled}${RST}${DGRAY}${empty}${RST}`;
}

function helpDivider(title: string): string {
  return `  ${DGRAY}──${RST} ${ORANGE}${BOLD}${title}${RST} ${DGRAY}${repeat("─", 60)}${RST}`;
}

interface HelpProto {
  name: string;
  port: string;
  resilience: number;
  speed: number;
  note: string;
}

const PROTOS_SERVER: HelpProto[] = [
  { name: "Reality",         port: "443",    resilience: 4, speed: 5, note: "TLS camouflage, no domain" },
  { name: "WS+CDN",          port: "80",     resilience: 5, speed: 4, note: "IP hidden behind Cloudflare" },
  { name: "Hysteria v2",     port: "UDP",    resilience: 3, speed: 5, note: "QUIC, fastest protocol" },
  { name: "WireGuard",       port: "51820",  resilience: 2, speed: 5, note: "Full device tunnel" },
  { name: "VLESS+TLS",       port: "443",    resilience: 4, speed: 5, note: "V2Ray + real certs" },
  { name: "HTTP Obfs",       port: "80/CDN", resilience: 5, speed: 4, note: "Host header spoofing" },
  { name: "MTProto",         port: "443",    resilience: 3, speed: 4, note: "Telegram proxy" },
  { name: "SSH Tunnel",      port: "22",     resilience: 2, speed: 3, note: "Universal fallback" },
];

const PROTOS_EMERG: HelpProto[] = [
  { name: "DNSTT",           port: "53",     resilience: 5, speed: 1, note: "~42 KB/s last resort" },
  { name: "Slipstream",      port: "53",     resilience: 5, speed: 2, note: "~63 KB/s QUIC+TLS" },
  { name: "NoizDNS",         port: "53",     resilience: 5, speed: 2, note: "DPI-resistant DNSTT" },
];

const PROTOS_RELAY: HelpProto[] = [
  { name: "Conduit",         port: "auto",   resilience: 5, speed: 4, note: "Psiphon relay" },
  { name: "Tor Bridge",      port: "9001",   resilience: 4, speed: 2, note: "obfs4 bridge" },
  { name: "Snowflake",       port: "--",     resilience: 4, speed: 2, note: "WebRTC Tor relay" },
  { name: "SOS Chat",        port: "8899",   resilience: 5, speed: 1, note: "E2E encrypted chat" },
];

function renderHelpTable(protos: HelpProto[]): string[] {
  const cName = 16, cPort = 8, cRes = 11, cSpd = 11;
  const lines: string[] = [];
  lines.push(`    ${ORANGE}${"Protocol".padEnd(cName)}${RST}${DGRAY}│${RST} ${ORANGE}${"Port".padEnd(cPort)}${RST}${DGRAY}│${RST} ${ORANGE}${"Resist.".padEnd(cRes)}${RST}${DGRAY}│${RST} ${ORANGE}${"Speed".padEnd(cSpd)}${RST}${DGRAY}│${RST} ${ORANGE}Notes${RST}`);
  lines.push(`    ${DGRAY}${repeat("─", cName)}┼${repeat("─", cPort + 2)}┼${repeat("─", cRes + 2)}┼${repeat("─", cSpd + 2)}┼${repeat("─", 26)}${RST}`);
  for (const p of protos) {
    lines.push(`    ${LGREEN}${p.name.padEnd(cName)}${RST}${DGRAY}│${RST} ${DIM}${p.port.padEnd(cPort)}${RST}${DGRAY}│${RST} ${stars(p.resilience)}  ${DGRAY}│${RST} ${stars(p.speed)}  ${DGRAY}│${RST} ${DIM}${p.note}${RST}`);
  }
  return lines;
}

export function pageHelp(): string {
  const lines: string[] = [];

  lines.push(`  ${BOLD}${GREEN}VANY${RST} ${DIM}v3.0.0${RST}`);
  lines.push(`  ${DIM}Multi-protocol censorship bypass platform${RST}`);
  lines.push("");

  // Navigation — Server
  lines.push(`  ${BOLD}${ORANGE}NAVIGATION${RST}`);
  lines.push(`    ${DGRAY}Server${RST}`);
  lines.push(`      ${keyHint("p", "protocols")}   Protocol catalog and status`);
  lines.push(`      ${keyHint("s", "status")}      Docker container status`);
  lines.push(`      ${keyHint("u", "users")}       User management`);
  lines.push(`      ${keyHint("i", "install")}     Install wizard`);
  lines.push(`    ${DGRAY}Client${RST}`);
  lines.push(`      ${keyHint("c", "connect")}     Connect to VPN (client mode)`);
  lines.push(`      ${keyHint("m", "import")}      Import config link`);
  lines.push(`    ${DGRAY}Tools${RST}`);
  lines.push(`      ${keyHint("f", "cfray")}       Find clean Cloudflare IPs`);
  lines.push(`      ${keyHint("n", "findns")}      Find working DNS resolvers`);
  lines.push(`      ${keyHint("t", "tracer")}      IP tracer (route, ASN, ISP)`);
  lines.push(`    ${DGRAY}General${RST}`);
  lines.push(`      ${keyHint("h", "help")}        This page`);
  lines.push(`      ${keyHint("r", "refresh")}     Refresh current page`);
  lines.push(`      ${keyHint("q", "quit")}        Exit`);
  lines.push("");

  // Architecture
  lines.push(`  ${BOLD}${ORANGE}ARCHITECTURE${RST}`);
  lines.push(`    ${TEXT}All protocols run in Docker containers on your VPS.${RST}`);
  lines.push(`    ${TEXT}Xray shared container handles: Reality, WS+CDN, VRAY, HTTP Obfs${RST}`);
  lines.push(`    ${TEXT}State: /opt/vany/state.json   Users: /opt/vany/users.json${RST}`);
  lines.push("");

  // Protocol tables
  lines.push(helpDivider("SERVER PROTOCOLS"));
  lines.push("");
  lines.push(...renderHelpTable(PROTOS_SERVER));
  lines.push("");

  lines.push(helpDivider("EMERGENCY / DNS TUNNELS"));
  lines.push("");
  lines.push(...renderHelpTable(PROTOS_EMERG));
  lines.push(`    ${DIM}Note: All DNS tunnels use port 53 -- only one can be active at a time${RST}`);
  lines.push("");

  lines.push(helpDivider("RELAY / COMMUNITY"));
  lines.push("");
  lines.push(...renderHelpTable(PROTOS_RELAY));
  lines.push("");

  // Client tools
  lines.push(helpDivider("CLIENT TOOLS"));
  lines.push("");
  lines.push(`    ${LGREEN}VPN Connect${RST}    ${DIM}Connect to any protocol from terminal (client mode)${RST}`);
  lines.push(`    ${LGREEN}cfray${RST}          ${DIM}Scan for clean Cloudflare IPs (run from restricted country)${RST}`);
  lines.push(`    ${LGREEN}findns${RST}         ${DIM}Find working DNS resolvers (run from restricted country)${RST}`);
  lines.push(`    ${LGREEN}IP Tracer${RST}      ${DIM}Trace route with ASN and ISP info${RST}`);
  lines.push(`    ${LGREEN}Speed Test${RST}     ${DIM}Test VPN throughput${RST}`);
  lines.push(`    ${LGREEN}Config Import${RST}  ${DIM}Paste VLESS/WG/Hysteria config to connect${RST}`);
  lines.push("");

  // Ratings legend
  lines.push(`  ${DIM}Ratings: ${GREEN}■${RST}${DIM} = capability out of 5   Resist. = censorship resilience   Speed = throughput${RST}`);
  lines.push("");

  // Links
  lines.push(`  ${BOLD}${ORANGE}LINKS${RST}`);
  lines.push(`    ${BLUE}https://github.com/behnamkhorsandian/Vanysh${RST}`);
  lines.push(`    ${BLUE}https://vany.sh${RST}`);
  lines.push("");

  // Access methods for restricted networks
  lines.push(helpDivider("UNSTOPPABLE ACCESS"));
  lines.push("");
  lines.push(`    ${TEXT}If you can't reach vany.sh, try these methods in order:${RST}`);
  lines.push("");
  lines.push(`    ${LGREEN}1.${RST} ${TEXT}Direct${RST}           ${DIM}curl vany.sh | sudo bash${RST}`);
  lines.push(`    ${LGREEN}2.${RST} ${TEXT}DoH bypass${RST}       ${DIM}curl --doh-url https://1.1.1.1/dns-query vany.sh | sudo bash${RST}`);
  lines.push(`    ${LGREEN}3.${RST} ${TEXT}CF Pages${RST}         ${DIM}curl vany-agg.pages.dev | sudo bash${RST}`);
  lines.push(`    ${LGREEN}4.${RST} ${TEXT}GitHub${RST}           ${DIM}curl -sL https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/start.sh | sudo bash${RST}`);
  lines.push(`    ${LGREEN}5.${RST} ${TEXT}WARP (1.1.1.1)${RST}   ${DIM}Install free 1.1.1.1 app, enable, then curl vany.sh${RST}`);
  lines.push("");
  lines.push(`    ${ORANGE}Rescue one-liner${RST} ${DIM}(share via SMS/Telegram):${RST}`);
  lines.push(`    ${LGREEN}curl -m5 vany.sh/bootstrap | sudo bash${RST}`);
  lines.push("");
  lines.push(`    ${ORANGE}Auto-rescue bootstrap${RST} ${DIM}(tries all methods automatically):${RST}`);
  lines.push(`    ${LGREEN}curl -m5 vany.sh||curl -m5 --doh-url https://1.1.1.1/dns-query vany.sh||curl vany-agg.pages.dev${RST}`);
  lines.push("");
  lines.push(`    ${DIM}The smart client already tries all these methods automatically.${RST}`);
  lines.push(`    ${DIM}ECH (Encrypted Client Hello) hides the domain from DPI when enabled on CF.${RST}`);

  return lines.join("\r\n");
}
