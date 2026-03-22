// ---------------------------------------------------------------------------
// Vany TUI — Install Wizard Page
// Renders install instructions. Actual installation happens client-side
// by executing embedded shell commands.
// ---------------------------------------------------------------------------

import { GREEN, ORANGE, RED, BOLD, DIM, TEXT, LGREEN, DGRAY, RST } from "../theme.js";
import { box } from "../box.js";
import { keyHint } from "../layout.js";

interface ProtocolInfo {
  name: string;
  steps: string[];
  ports: string;
  requirements: string[];
  command: string; // base64-encoded install command for client
}

const INSTALL_INFO: Record<string, ProtocolInfo> = {
  reality: {
    name: "VLESS + REALITY",
    steps: [
      "Generate Xray keys (x25519 keypair)",
      "Create Xray config with Reality inbound on port 443",
      "Build and start vany-xray Docker container",
      "Open port 443/tcp in firewall",
      "Register protocol in state.json",
    ],
    ports: "443/tcp",
    requirements: ["Docker installed", "Port 443 available"],
    command: btoa("source /opt/vany/scripts/install-xray.sh && install_xray && add_reality_inbound"),
  },
  ws: {
    name: "VLESS + WebSocket + CDN",
    steps: [
      "Create Xray config with WebSocket inbound on port 80",
      "Build and start vany-xray Docker container (if not running)",
      "Open port 80/tcp in firewall",
      "Configure Cloudflare DNS (ws-origin.vany.sh -> server IP)",
      "Set Cloudflare SSL mode to Flexible",
    ],
    ports: "80/tcp",
    requirements: ["Docker installed", "Cloudflare domain configured", "Port 80 available"],
    command: btoa("source /opt/vany/scripts/install-xray.sh && install_xray && add_ws_inbound"),
  },
  hysteria: {
    name: "Hysteria v2",
    steps: [
      "Download Hysteria v2 binary",
      "Generate config with QUIC settings",
      "Build and start vany-hysteria Docker container",
      "Open configured UDP port in firewall",
      "Generate client connection config",
    ],
    ports: "UDP (configurable)",
    requirements: ["Docker installed", "UDP port available"],
    command: btoa("source /opt/vany/scripts/protocols/install-hysteria.sh && install_hysteria"),
  },
  wg: {
    name: "WireGuard",
    steps: [
      "Generate server keypair",
      "Create wg0.conf with iptables masquerade rules",
      "Build and start vany-wireguard Docker container",
      "Open port 51820/udp in firewall",
    ],
    ports: "51820/udp",
    requirements: ["Docker installed", "Kernel WireGuard module", "Port 51820 available"],
    command: btoa("source /opt/vany/scripts/install-wireguard.sh && install_wireguard"),
  },
  vray: {
    name: "VLESS + TLS",
    steps: [
      "Obtain TLS certificate via Let's Encrypt",
      "Create Xray config with TCP+TLS inbound",
      "Build and start vany-xray Docker container (if not running)",
      "Open port 443/tcp in firewall",
    ],
    ports: "443/tcp",
    requirements: ["Docker installed", "Domain name", "Port 443 available"],
    command: btoa("source /opt/vany/scripts/install-xray.sh && install_xray && add_vray_inbound"),
  },
  "http-obfs": {
    name: "HTTP Obfuscation",
    steps: [
      "Create Xray config with WebSocket inbound (same as WS+CDN)",
      "Build and start vany-xray Docker container (if not running)",
      "Open port 80/tcp in firewall",
      "Configure Cloudflare domain proxy",
      "Generate client config with Host header spoofing",
    ],
    ports: "80/tcp",
    requirements: ["Docker installed", "Cloudflare domain", "Port 80 available"],
    command: btoa("source /opt/vany/scripts/install-xray.sh && install_xray && add_http_obfs_inbound"),
  },
  mtp: {
    name: "MTProto Proxy",
    steps: [
      "Generate MTProto secret",
      "Start vany-mtp Docker container",
      "Open configured port in firewall",
      "Generate Telegram proxy link",
    ],
    ports: "443/tcp (configurable)",
    requirements: ["Docker installed", "Port available"],
    command: btoa("source /opt/vany/scripts/protocols/install-mtp.sh && install_mtp"),
  },
  "ssh-tunnel": {
    name: "SSH Tunnel",
    steps: [
      "Create restricted tunnel-only user",
      "Configure SSH for tunnel access",
      "Generate client connection command",
    ],
    ports: "22/tcp",
    requirements: ["SSH server running"],
    command: btoa("source /opt/vany/scripts/protocols/install-ssh-tunnel.sh && install_ssh_tunnel"),
  },
  dnstt: {
    name: "DNS Tunnel",
    steps: [
      "Build DNSTT server from source (Go 1.21)",
      "Generate server keypair",
      "Start vany-dnstt Docker container",
      "Redirect port 53 -> 5300 via iptables",
      "Configure NS record: t.<domain> -> ns1.<domain>",
    ],
    ports: "53/udp (via 5300)",
    requirements: ["Docker installed", "Domain with NS record", "Port 53 available"],
    command: btoa("source /opt/vany/scripts/install-dnstt.sh && install_dnstt"),
  },
  slipstream: {
    name: "Slipstream",
    steps: [
      "Download Slipstream server binary",
      "Generate config with QUIC+TLS over DNS",
      "Start vany-slipstream Docker container",
      "Open port 53 in firewall",
      "Configure NS record for domain",
    ],
    ports: "53/udp",
    requirements: ["Docker installed", "Domain with NS record", "Port 53 available (no other DNS tunnel)"],
    command: btoa("source /opt/vany/scripts/protocols/install-slipstream.sh && install_slipstream"),
  },
  noizdns: {
    name: "NoizDNS",
    steps: [
      "Build NoizDNS from source",
      "Generate server keypair with noise config",
      "Start vany-noizdns Docker container",
      "Open port 53 in firewall",
      "Configure NS record for domain",
    ],
    ports: "53/udp",
    requirements: ["Docker installed", "Domain with NS record", "Port 53 available (no other DNS tunnel)"],
    command: btoa("source /opt/vany/scripts/protocols/install-noizdns.sh && install_noizdns"),
  },
  conduit: {
    name: "Conduit (Psiphon Relay)",
    steps: [
      "Pull Conduit Docker image",
      "Start vany-conduit container",
      "Psiphon network auto-discovers relay",
    ],
    ports: "automatic",
    requirements: ["Docker installed"],
    command: btoa("source /opt/vany/scripts/install-conduit.sh && install_conduit"),
  },
  "tor-bridge": {
    name: "Tor Bridge (obfs4)",
    steps: [
      "Pull Tor Docker image with obfs4proxy",
      "Generate bridge identity keys",
      "Start vany-tor-bridge Docker container",
      "Open OR port in firewall",
      "Register with BridgeDB",
    ],
    ports: "9001/tcp (configurable)",
    requirements: ["Docker installed", "Port 9001 available"],
    command: btoa("source /opt/vany/scripts/protocols/install-tor-bridge.sh && install_tor_bridge"),
  },
  snowflake: {
    name: "Snowflake Proxy",
    steps: [
      "Pull Snowflake proxy Docker image",
      "Start vany-snowflake container",
      "Snowflake broker auto-discovers relay",
    ],
    ports: "none (uses STUN/TURN)",
    requirements: ["Docker installed"],
    command: btoa("source /opt/vany/scripts/protocols/install-snowflake.sh && install_snowflake"),
  },
  sos: {
    name: "SOS Emergency Chat",
    steps: [
      "Build SOS relay from src/sos",
      "Start vany-sos Docker container on port 8899",
      "Open port 8899/tcp in firewall",
      "Relay accessible at relay.<domain>:8899",
    ],
    ports: "8899/tcp",
    requirements: ["Docker installed", "DNSTT running (for tunnel mode)", "Port 8899 available"],
    command: btoa("source /opt/vany/scripts/install-sos.sh && install_sos"),
  },
};

/** Render the install page — either overview or specific protocol */
export function pageInstall(
  proto: string,
  state: Record<string, unknown> = {},
): string {
  if (!proto) {
    return installOverview(state);
  }

  const info = INSTALL_INFO[proto];
  if (!info) {
    return `\r\n  ${RED}Unknown protocol: ${proto}${RST}\r\n\r\n  Available: ${Object.keys(INSTALL_INFO).join(", ")}`;
  }

  return installDetail(proto, info, state);
}

function installOverview(state: Record<string, unknown>): string {
  const protocols = (state.protocols || {}) as Record<string, { status?: string }>;

  const lines: string[] = [
    `  ${BOLD}${ORANGE}SELECT PROTOCOL TO INSTALL${RST}`,
    "",
  ];

  let idx = 1;
  for (const [key, info] of Object.entries(INSTALL_INFO)) {
    const installed = protocols[key]?.status === "running";
    const mark = installed ? `${GREEN}*${RST}` : " ";
    const label = installed ? `${DIM}${info.name} (installed)${RST}` : `${TEXT}${info.name}${RST}`;
    lines.push(`  ${mark} ${LGREEN}${idx}${RST}  ${label}`);
    idx++;
  }

  lines.push("");
  lines.push(`  ${DIM}* = already installed${RST}`);
  lines.push("");
  lines.push(`  ${keyHint("1-" + Object.keys(INSTALL_INFO).length, "select")}  ${keyHint("Esc", "back")}`);

  return lines.join("\r\n");
}

function installDetail(
  proto: string,
  info: ProtocolInfo,
  state: Record<string, unknown>,
): string {
  const lines: string[] = [];

  lines.push(`  ${BOLD}${GREEN}INSTALL: ${info.name}${RST}`);
  lines.push("");

  // Requirements
  lines.push(`  ${ORANGE}Requirements:${RST}`);
  for (const req of info.requirements) {
    lines.push(`    ${DGRAY}-${RST} ${TEXT}${req}${RST}`);
  }
  lines.push("");

  // Ports
  lines.push(`  ${ORANGE}Ports:${RST} ${TEXT}${info.ports}${RST}`);
  lines.push("");

  // Steps
  lines.push(`  ${ORANGE}Steps:${RST}`);
  for (let i = 0; i < info.steps.length; i++) {
    lines.push(`    ${GREEN}${i + 1}.${RST} ${TEXT}${info.steps[i]}${RST}`);
  }
  lines.push("");

  // Embedded command (client parses this escape sequence)
  lines.push(`\x1b]vany;cmd;${info.command}\x07`);

  lines.push(`  ${keyHint("Enter", "start install")}  ${keyHint("Esc", "back")}`);

  return lines.join("\r\n");
}
