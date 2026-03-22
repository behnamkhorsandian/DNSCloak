// ---------------------------------------------------------------------------
// Vany TUI — TUI Route Handler
//
// Handles /tui/* endpoints:
//   GET /tui/protocols   → Protocols catalog ANSI page
//   GET /tui/install     → Install wizard ANSI page
//   GET /tui/help        → Help page ANSI
//   GET /tui/splash      → Splash/logo animation
//   GET /tui/client      → Thin bash client script
//
// Each page can be:
//   - Static: single ANSI response (one-shot render)
//   - Streaming: ReadableStream with periodic refreshes (?stream=1)
// ---------------------------------------------------------------------------

import { pageProtocols } from "./pages/protocols.js";
import { pageInstall } from "./pages/install.js";
import { pageHelp } from "./pages/help.js";
import { pageLanding } from "./pages/landing.js";
import { pageClient } from "./pages/client.js";
import { pageTools } from "./pages/tools.js";
import { splash } from "./splash.js";
import { CLEAR, HIDE_CURSOR, SHOW_CURSOR, HOME } from "./ansi.js";
import { frame } from "./frame.js";
import { VANY_CLIENT_SCRIPT } from "./x-client.js";

interface TuiEnv {}

/** Parse terminal dimensions and state from query params */
function parseParams(url: URL) {
  const cols = parseInt(url.searchParams.get("cols") || "100", 10);
  const rows = parseInt(url.searchParams.get("rows") || "40", 10);
  const stream = url.searchParams.get("stream") === "1";
  const interactive = url.searchParams.get("interactive") === "1";

  // VPS state (base64url-encoded JSON)
  let state: Record<string, unknown> = {};
  const stateParam = url.searchParams.get("state");
  if (stateParam) {
    try {
      state = JSON.parse(atob(stateParam));
    } catch { /* ignore malformed state */ }
  }

  return {
    cols: Math.min(300, Math.max(40, isNaN(cols) ? 100 : cols)),
    rows: Math.min(100, Math.max(10, isNaN(rows) ? 40 : rows)),
    stream,
    interactive,
    state,
  };
}

const TEXT_HEADERS = {
  "Content-Type": "text/plain; charset=utf-8",
  "Cache-Control": "no-cache",
  "X-Content-Type-Options": "nosniff",
};

const STREAM_HEADERS = {
  ...TEXT_HEADERS,
  "Transfer-Encoding": "chunked",
};

/** Handle a TUI request and return a Response */
export async function handleTuiRequest(
  request: Request,
  env: TuiEnv,
  path: string,
  url: URL,
): Promise<Response | null> {
  const { cols, rows, stream, interactive, state } = parseParams(url);

  // /tui/landing — static ANSI landing page (logo + endpoint table)
  if (path === "/tui/landing") {
    return new Response(pageLanding(), { headers: TEXT_HEADERS });
  }

  // /tui/client — serve the bash client script
  if (path === "/tui/client" || path === "/tui/x") {
    return new Response(VANY_CLIENT_SCRIPT, { headers: TEXT_HEADERS });
  }

  // /tui/splash — logo animation
  if (path === "/tui/splash") {
    const page = splash(cols, rows);
    return new Response(CLEAR + page, { headers: TEXT_HEADERS });
  }

  // /tui/protocols — protocol catalog table
  if (path === "/tui/protocols") {
    const content = pageProtocols(state);
    const page = frame({ content, cols, rows, navIndex: 0, interactive });
    if (stream) {
      return streamPage(() => {
        const c = pageProtocols(state);
        return frame({ content: c, cols, rows, navIndex: 0, interactive: true });
      });
    }
    return new Response(CLEAR + HIDE_CURSOR + page, { headers: TEXT_HEADERS });
  }

  // /tui/install[/<proto>] — install wizard
  if (path.startsWith("/tui/install")) {
    const proto = path.split("/")[3] || "";
    const content = pageInstall(proto, state);
    const page = frame({ content, cols, rows, navIndex: 3, interactive });
    return new Response(CLEAR + HIDE_CURSOR + page, { headers: TEXT_HEADERS });
  }

  // /tui/help — help page
  if (path === "/tui/help") {
    const content = pageHelp();
    const page = frame({ content, cols, rows, navIndex: 4, interactive });
    return new Response(CLEAR + HIDE_CURSOR + page, { headers: TEXT_HEADERS });
  }

  // /tui/client[/<subpage>] — client connection page
  if (path.startsWith("/tui/connect")) {
    const subpage = path.split("/")[3] || "";
    const content = pageClient(subpage, state);
    const page = frame({ content, cols, rows, navIndex: 5, interactive });
    return new Response(CLEAR + HIDE_CURSOR + page, { headers: TEXT_HEADERS });
  }

  // /tui/tools[/<tool>] — network tools page
  if (path.startsWith("/tui/tools")) {
    const tool = path.split("/")[3] || "";
    const content = pageTools(tool, state);
    const page = frame({ content, cols, rows, navIndex: 6, interactive });
    return new Response(CLEAR + HIDE_CURSOR + page, { headers: TEXT_HEADERS });
  }

  return null; // not a TUI route
}

/** Stream a page with periodic refreshes (overwrite in-place, zero flicker) */
function streamPage(renderFn: () => string, intervalMs = 2000): Response {
  const enc = new TextEncoder();
  let ticks = 0;
  const MAX_TICKS = 150; // ~5 minutes at 2s interval

  const stream = new ReadableStream({
    async pull(controller) {
      if (ticks >= MAX_TICKS) {
        controller.enqueue(enc.encode(SHOW_CURSOR));
        controller.close();
        return;
      }

      if (ticks > 0) {
        await new Promise((r) => setTimeout(r, intervalMs));
      }

      const page = renderFn();
      const prefix = ticks === 0 ? CLEAR + HIDE_CURSOR : HOME;
      controller.enqueue(enc.encode(prefix + page));
      ticks++;
    },
  });

  return new Response(stream, { headers: STREAM_HEADERS });
}
