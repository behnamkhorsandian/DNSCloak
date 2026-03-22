// ---------------------------------------------------------------------------
// Vany TUI — Tools Page
// Network scanner tools for users in restricted countries.
// ---------------------------------------------------------------------------

import { GREEN, ORANGE, RED, BOLD, DIM, TEXT, LGREEN, DGRAY, RST, BLUE, YELLOW } from "../theme.js";
import { keyHint } from "../layout.js";
import { repeat } from "../ansi.js";

/** Render a tool page */
export function pageTools(
  tool: string,
  state: Record<string, unknown> = {},
): string {
  switch (tool) {
    case "cfray":
      return pageCfray();
    case "findns":
      return pageFindns();
    case "tracer":
      return pageTracer();
    case "speedtest":
      return pageSpeedtest();
    default:
      return toolsOverview();
  }
}

function toolsOverview(): string {
  const lines: string[] = [];

  lines.push(`  ${BOLD}${GREEN}NETWORK TOOLS${RST}`);
  lines.push(`  ${DIM}Scanners and diagnostics for censored networks${RST}`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}AVAILABLE TOOLS${RST}`);
  lines.push("");

  const cName = 16, cDesc = 45;
  lines.push(`    ${ORANGE}${"Tool".padEnd(cName)}${RST}${DGRAY}│${RST} ${ORANGE}${"Description".padEnd(cDesc)}${RST}${DGRAY}│${RST} ${ORANGE}Key${RST}`);
  lines.push(`    ${DGRAY}${repeat("─", cName)}┼${repeat("─", cDesc + 2)}┼${repeat("─", 6)}${RST}`);

  lines.push(`    ${LGREEN}${"cfray".padEnd(cName)}${RST}${DGRAY}│${RST} ${TEXT}${"Find clean Cloudflare IPs for WS+CDN/HTTP Obfs".padEnd(cDesc)}${RST}${DGRAY}│${RST} ${LGREEN} f${RST}`);
  lines.push(`    ${LGREEN}${"findns".padEnd(cName)}${RST}${DGRAY}│${RST} ${TEXT}${"Find working DNS resolvers in your network".padEnd(cDesc)}${RST}${DGRAY}│${RST} ${LGREEN} n${RST}`);
  lines.push(`    ${LGREEN}${"IP Tracer".padEnd(cName)}${RST}${DGRAY}│${RST} ${TEXT}${"Trace route, show ASNs and ISPs".padEnd(cDesc)}${RST}${DGRAY}│${RST} ${LGREEN} t${RST}`);
  lines.push(`    ${LGREEN}${"Speed Test".padEnd(cName)}${RST}${DGRAY}│${RST} ${TEXT}${"Test VPN connection throughput".padEnd(cDesc)}${RST}${DGRAY}│${RST} ${LGREEN} b${RST}`);
  lines.push("");

  lines.push(`  ${YELLOW}Note:${RST} ${TEXT}cfray and findns should be run from a restricted country.${RST}`);
  lines.push(`  ${TEXT}They scan for IPs/resolvers that work from your network.${RST}`);
  lines.push("");

  lines.push(`  ${keyHint("f", "cfray")}  ${keyHint("n", "findns")}  ${keyHint("t", "tracer")}  ${keyHint("b", "speed test")}  ${keyHint("Esc", "back")}`);

  return lines.join("\r\n");
}

function pageCfray(): string {
  const lines: string[] = [];

  lines.push(`  ${BOLD}${GREEN}CFRAY — Clean Cloudflare IP Scanner${RST}`);
  lines.push(`  ${DIM}Find Cloudflare IPs that are not blocked in your network${RST}`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}WHAT IT DOES${RST}`);
  lines.push(`    ${TEXT}Scans Cloudflare IP ranges to find ones that respond from your network.${RST}`);
  lines.push(`    ${TEXT}These "clean" IPs can be used with WS+CDN or HTTP Obfuscation protocols${RST}`);
  lines.push(`    ${TEXT}instead of the domain's default IP, bypassing IP-based blocking.${RST}`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}HOW TO USE${RST}`);
  lines.push(`    ${GREEN}1.${RST} ${TEXT}Run this tool from inside the restricted country${RST}`);
  lines.push(`    ${GREEN}2.${RST} ${TEXT}Wait for scan to complete (tests ~100 IPs)${RST}`);
  lines.push(`    ${GREEN}3.${RST} ${TEXT}Copy working IPs to your VPN client config${RST}`);
  lines.push(`    ${GREEN}4.${RST} ${TEXT}Set the clean IP as "address" in your VLESS config${RST}`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}RUN${RST}`);
  lines.push(`    ${LGREEN}curl vany.sh/tools/cfray | bash${RST}`);
  lines.push("");

  // Embedded command for TUI client
  lines.push(`\x1b]vany;cmd;${btoa("curl -sS https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/scripts/tools/cfray.sh | bash")}\x07`);

  lines.push(`  ${keyHint("Enter", "run scan")}  ${keyHint("Esc", "back")}`);

  return lines.join("\r\n");
}

function pageFindns(): string {
  const lines: string[] = [];

  lines.push(`  ${BOLD}${GREEN}FINDNS — DNS Resolver Scanner${RST}`);
  lines.push(`  ${DIM}Find DNS resolvers that are not blocked or poisoned${RST}`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}WHAT IT DOES${RST}`);
  lines.push(`    ${TEXT}Tests a list of public DNS resolvers to find ones that work${RST}`);
  lines.push(`    ${TEXT}from your network. Useful for DNS tunnel protocols (DNSTT,${RST}`);
  lines.push(`    ${TEXT}Slipstream, NoizDNS) which need working recursive resolvers.${RST}`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}HOW TO USE${RST}`);
  lines.push(`    ${GREEN}1.${RST} ${TEXT}Run this tool from inside the restricted country${RST}`);
  lines.push(`    ${GREEN}2.${RST} ${TEXT}Wait for scan (tests ~50 resolvers)${RST}`);
  lines.push(`    ${GREEN}3.${RST} ${TEXT}Use working resolvers with your DNS tunnel client${RST}`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}RUN${RST}`);
  lines.push(`    ${LGREEN}curl vany.sh/tools/findns | bash${RST}`);
  lines.push("");

  lines.push(`\x1b]vany;cmd;${btoa("curl -sS https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/scripts/tools/findns.sh | bash")}\x07`);

  lines.push(`  ${keyHint("Enter", "run scan")}  ${keyHint("Esc", "back")}`);

  return lines.join("\r\n");
}

function pageTracer(): string {
  const lines: string[] = [];

  lines.push(`  ${BOLD}${GREEN}IP TRACER — Route and ASN Lookup${RST}`);
  lines.push(`  ${DIM}Trace network path, identify ISPs and autonomous systems${RST}`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}WHAT IT DOES${RST}`);
  lines.push(`    ${TEXT}Traces the network route to your server showing each hop,${RST}`);
  lines.push(`    ${TEXT}its ASN (autonomous system number), and ISP name. Helps${RST}`);
  lines.push(`    ${TEXT}identify where traffic is being filtered or rerouted.${RST}`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}HOW TO USE${RST}`);
  lines.push(`    ${GREEN}1.${RST} ${TEXT}Enter the target IP or domain${RST}`);
  lines.push(`    ${GREEN}2.${RST} ${TEXT}View the route with ASN annotations${RST}`);
  lines.push(`    ${GREEN}3.${RST} ${TEXT}Identify filtering points in the network${RST}`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}RUN${RST}`);
  lines.push(`    ${LGREEN}curl vany.sh/tools/tracer | bash${RST}`);
  lines.push("");

  lines.push(`\x1b]vany;cmd;${btoa("curl -sS https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/scripts/tools/tracer.sh | bash")}\x07`);

  lines.push(`  ${keyHint("Enter", "run tracer")}  ${keyHint("Esc", "back")}`);

  return lines.join("\r\n");
}

function pageSpeedtest(): string {
  const lines: string[] = [];

  lines.push(`  ${BOLD}${GREEN}SPEED TEST — VPN Throughput Test${RST}`);
  lines.push(`  ${DIM}Measure download and upload speed through your VPN${RST}`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}WHAT IT DOES${RST}`);
  lines.push(`    ${TEXT}Tests the throughput of your current VPN connection.${RST}`);
  lines.push(`    ${TEXT}Useful for comparing protocol performance and finding${RST}`);
  lines.push(`    ${TEXT}the fastest option for your network.${RST}`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}HOW TO USE${RST}`);
  lines.push(`    ${GREEN}1.${RST} ${TEXT}Connect to VPN first using your client app${RST}`);
  lines.push(`    ${GREEN}2.${RST} ${TEXT}Run the speed test${RST}`);
  lines.push(`    ${GREEN}3.${RST} ${TEXT}Compare results across protocols${RST}`);
  lines.push("");

  lines.push(`  ${BOLD}${ORANGE}RUN${RST}`);
  lines.push(`    ${LGREEN}curl vany.sh/tools/speedtest | bash${RST}`);
  lines.push("");

  lines.push(`\x1b]vany;cmd;${btoa("curl -sS https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main/scripts/tools/speedtest.sh | bash")}\x07`);

  lines.push(`  ${keyHint("Enter", "run test")}  ${keyHint("Esc", "back")}`);

  return lines.join("\r\n");
}
