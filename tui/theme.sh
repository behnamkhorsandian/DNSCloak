#!/bin/bash
#===============================================================================
# Vany TUI - Theme & Drawing Constants
# 256-color palette matching the 432.sh design language
#===============================================================================

# ── Colors (256-color) ───────────────────────────────────────────────────────
C_TEXT='\033[38;5;253m'       # white #e7e7e7 — body text
C_GREEN='\033[38;5;36m'       # main green #2eb787 — primary brand
C_LGREEN='\033[38;5;115m'     # light green #9acfa0 — commands, keys
C_DGREEN='\033[38;5;65m'      # dark green #466242 — subtle accents
C_BLUE='\033[38;5;68m'        # blue #6090e3 — links, URLs
C_RED='\033[38;5;130m'        # red #a25138 — errors
C_ORANGE='\033[38;5;172m'     # orange #d59719 — headings
C_YELLOW='\033[38;5;186m'     # yellow #e5e885 — highlights
C_PURPLE='\033[38;5;141m'     # purple #a492ff — emphasis
C_LGRAY='\033[38;5;151m'      # light gray #9ab0a6 — meta info
C_DGRAY='\033[38;5;236m'      # dark gray #343434 — borders, dim
C_WHITE='\033[1;37m'          # bold white — titles
C_RST='\033[0m'               # reset
C_BOLD='\033[1m'              # bold
C_DIM='\033[2m'               # dim
C_ITALIC='\033[3m'            # italic

# ── Box-Drawing Characters (single-line Unicode) ────────────────────────────
BOX_H="─"    # horizontal
BOX_V="│"    # vertical
BOX_TL="┌"   # top-left
BOX_TR="┐"   # top-right
BOX_BL="└"   # bottom-left
BOX_BR="┘"   # bottom-right
BOX_ML="├"   # middle-left
BOX_MR="┤"   # middle-right
BOX_TJ="┬"   # top-junction
BOX_BJ="┴"   # bottom-junction
BOX_CJ="┼"   # cross

# Background colors
C_BG_DARK='\033[48;5;235m'   # dark background for status bar

# ── Status Dots (Unicode — overridden by icons.json when loaded) ─────────────
DOT_ON="${C_GREEN}◍${C_RST}"         # running
DOT_OFF="${C_YELLOW}○${C_RST}"       # stopped / installed but not running
DOT_ERR="${C_RED}◍${C_RST}"          # error
DOT_NONE="${C_DGRAY}◌${C_RST}"       # not installed
DOT_REC="${C_BLUE}◍${C_RST}"         # recommended (fallback tag)

# ── Status Badges ────────────────────────────────────────────────────────────
badge_running="${C_GREEN}[running]${C_RST}"
badge_stopped="${C_YELLOW}[stopped]${C_RST}"
badge_installed="${C_LGREEN}[installed]${C_RST}"
badge_not_installed="${C_DGRAY}[not installed]${C_RST}"
badge_recommended="${C_BLUE}[recommended]${C_RST}"
badge_needs_domain="${C_ORANGE}[needs domain]${C_RST}"
badge_emergency="${C_RED}[emergency]${C_RST}"
badge_relay="${C_PURPLE}[relay]${C_RST}"

# ── Bullet/Marker Characters ────────────────────────────────────────────────
MARKER_ARROW=">"
MARKER_DOT="*"
MARKER_CHECK="+"
MARKER_CROSS="x"
MARKER_INFO="i"
MARKER_WARN="!"
MARKER_STEP=">>>"

# ── Protocol Metadata (fallback — overridden by tui/content/protocols.json) ──

# Protocol IDs (order = display order in main menu)
PROTOCOL_IDS=( reality wg ws mtp dnstt conduit vray sos )

# Display names
declare -A PROTOCOL_NAMES=(
    [reality]="VLESS + REALITY"
    [wg]="WireGuard"
    [ws]="VLESS + WS + CDN"
    [mtp]="MTProto Proxy"
    [dnstt]="DNS Tunnel"
    [conduit]="Conduit (Psiphon)"
    [vray]="VLESS + TLS"
    [sos]="SOS Emergency Chat"
)

# Short names for sidebar (max ~16 chars)
declare -A PROTOCOL_SHORT=(
    [reality]="REALITY"
    [wg]="WireGuard"
    [ws]="WS + CDN"
    [mtp]="MTProto"
    [dnstt]="DNS Tunnel"
    [conduit]="Conduit"
    [vray]="VLESS+TLS"
    [sos]="SOS Chat"
)

# Short descriptions (shown in main menu sidebar)
declare -A PROTOCOL_DESC=(
    [reality]="Advanced proxy with TLS camouflage.\nNo domain needed. Very fast.\nHides traffic as normal HTTPS."
    [wg]="Fast VPN tunnel with native apps.\nFull device tunnel. Simple setup.\nBest for daily use."
    [ws]="Route through Cloudflare CDN.\nHides your server IP completely.\nRequires a domain name."
    [mtp]="Telegram-specific proxy.\nBuilt into Telegram apps.\nNo extra client needed."
    [dnstt]="Emergency DNS tunnel.\nWorks during total blackouts.\nVery slow but unblockable."
    [conduit]="Psiphon volunteer relay.\nHelp users in censored regions.\nNo client configuration needed."
    [vray]="Classic V2Ray setup with TLS.\nRequires domain + certificate.\nGood compatibility."
    [sos]="Encrypted emergency chat.\nWorks over DNS tunnel.\nNo internet needed."
)

# Requirements (shown in protocol detail page)
declare -A PROTOCOL_REQS=(
    [reality]="- Server with public IP\n- Port 443 open"
    [wg]="- Server with public IP\n- UDP port 51820 open"
    [ws]="- Domain name\n- Cloudflare DNS (free)\n- Port 80 open"
    [mtp]="- Server with public IP\n- Custom port open"
    [dnstt]="- Domain name\n- NS record configured\n- Port 53 open (or forwarded)"
    [conduit]="- Docker installed\n- Any open port"
    [vray]="- Domain name\n- Port 443 open\n- TLS certificate"
    [sos]="- DNSTT service running\n- Python 3.8+"
)

# Tags for menu badges
declare -A PROTOCOL_TAGS=(
    [reality]="recommended"
    [wg]=""
    [ws]="needs_domain"
    [mtp]=""
    [dnstt]="emergency"
    [conduit]="relay"
    [vray]="needs_domain"
    [sos]="emergency"
)

# Client apps info
declare -A PROTOCOL_CLIENTS=(
    [reality]="iOS: Hiddify  Android: Hiddify\nWindows: Hiddify  macOS: Hiddify"
    [wg]="iOS: WireGuard  Android: WireGuard\nWindows: WireGuard  macOS: WireGuard"
    [ws]="iOS: Hiddify  Android: Hiddify\nWindows: Hiddify  macOS: Hiddify"
    [mtp]="Built into Telegram apps.\nJust click the proxy link!"
    [dnstt]="Requires dnstt-client binary.\nSee docs for setup."
    [conduit]="No client needed.\nUsers connect via Psiphon apps."
    [vray]="iOS: Hiddify  Android: Hiddify\nWindows: Hiddify  macOS: Hiddify"
    [sos]="Terminal: pip install vany-sos\nBrowser: navigate to relay URL"
)
