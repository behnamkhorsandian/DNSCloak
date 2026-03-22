// ---------------------------------------------------------------------------
// Vany TUI — Page Frame Renderer
//
// Renders a full page: header bar, content area, nav footer.
// Simpler than 432.sh frame (no live ticker/markets/weather).
//
// Usage:
//   frame({ content: bodyStr, cols: 80, rows: 40 })
// ---------------------------------------------------------------------------

import { DGRAY, GREEN, BOLD, DIM, TEXT, LGREEN, RST } from "./theme.js";
import { visibleLen, repeat } from "./ansi.js";

const H = "─", V = "│";
const TL = "┌", TR = "┐";
const BL = "└", BR = "┘";
const ML = "├", MR = "┤";

const BC = DGRAY;

interface FrameOpts {
  heading?: string;
  content: string;
  cols?: number;
  rows?: number;
  navIndex?: number;
  interactive?: boolean;
}

const NAV_PAGES = ["Protocols", "Status", "Users", "Install", "Help", "Connect", "Tools"];
const NAV_KEYS  = ["p",         "s",      "u",     "i",       "h",    "c",       "f"];

/**
 * Max width for the box — snapped to even, fits within terminal.
 */
function makeWidths(cols: number) {
  const MAX = 120;
  const MIN = 60;
  let W = Math.min(MAX, Math.max(MIN, cols - 2));
  if (W % 2 !== 0) W--;
  const IW = W - 2; // inner width (between vertical borders)
  const margin = Math.max(0, Math.floor((cols - W) / 2));
  return { W, IW, margin };
}

export function frame(opts: FrameOpts): string {
  const {
    heading = "",
    content,
    cols = 100,
    rows = 40,
    navIndex = -1,
    interactive = false,
  } = opts;

  const { W, IW, margin } = makeWidths(cols);
  const MG = margin > 0 ? repeat(" ", margin) : "";

  const out: string[] = [];

  // ── Header bar: ┌─ VANY ──────────────────────┐
  const brand = ` ${GREEN}${BOLD}VANY${RST} `;
  const brandVis = visibleLen(brand);
  const topFill = IW - brandVis;
  out.push(`${MG}${BC}${TL}${H}${RST}${brand}${BC}${repeat(H, topFill)}${TR}${RST}`);

  // ── Heading (optional, e.g. banner/splash) ──
  if (heading) {
    const headLines = heading.split(/\r?\n/);
    for (const hl of headLines) {
      const pad = Math.max(0, IW - visibleLen(hl));
      out.push(`${MG}${BC}${V}${RST}${hl}${repeat(" ", pad)}${BC}${V}${RST}`);
    }
    out.push(`${MG}${BC}${ML}${repeat(H, IW)}${MR}${RST}`);
  }

  // ── Content area ──
  const contentLines = content.split(/\r?\n/);

  // Calculate available height for content
  const chromeLines = heading
    ? 3 + heading.split(/\r?\n/).length + (interactive ? 3 : 1) // header + heading + sep + footer + nav
    : 2 + (interactive ? 3 : 1); // header + footer + nav
  const availableRows = Math.max(contentLines.length, rows - chromeLines);

  for (let i = 0; i < availableRows; i++) {
    const line = i < contentLines.length ? contentLines[i] : "";
    const pad = Math.max(0, IW - visibleLen(line));
    out.push(`${MG}${BC}${V}${RST}${line}${repeat(" ", pad)}${BC}${V}${RST}`);
  }

  // ── Bottom border ──
  out.push(`${MG}${BC}${BL}${repeat(H, IW)}${BR}${RST}`);

  // ── Nav bar (when interactive) ──
  if (interactive) {
    let nav = `${MG}  `;
    for (let i = 0; i < NAV_PAGES.length; i++) {
      // Add section separators
      if (i === 5) nav += `${DGRAY}|${RST} `; // before Connect
      if (i === navIndex) {
        nav += `${GREEN}${BOLD}[${NAV_KEYS[i]}] ${NAV_PAGES[i]}${RST}  `;
      } else {
        nav += `${LGREEN}[${NAV_KEYS[i]}]${RST} ${TEXT}${NAV_PAGES[i]}${RST}  `;
      }
    }
    out.push(nav);

    const guide = `${MG}  ${DIM}Navigate: keys above | q quit | r refresh${RST}`;
    out.push(guide);
  }

  return out.join("\r\n");
}
