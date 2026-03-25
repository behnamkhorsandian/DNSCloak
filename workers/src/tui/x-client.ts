// ---------------------------------------------------------------------------
// Vany TUI — Thin Bash Client
//
// Served when user runs: curl vany.sh | sudo bash
// Pattern from 432.sh x-client: stdin is the pipe, /dev/tty (fd 3)
// handles keyboard I/O. Worker-rendered pages stream via background curl.
// Local pages (status, users) render directly from Docker/state files.
// ---------------------------------------------------------------------------

export const VANY_CLIENT_SCRIPT = `#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Vany — Interactive Terminal Client
# Usage: curl vany.sh | sudo bash
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

VANY_DIR="/opt/vany"
STATE_FILE="\$VANY_DIR/state.json"
USERS_FILE="\$VANY_DIR/users.json"
BASE_FILE="\$VANY_DIR/.base_url"
CURRENT="protocols"
STREAM_PID=""

# Protocol map for install number keys (matches INSTALL_INFO order)
PROTO_MAP=("reality" "ws" "wg" "dnstt" "conduit" "sos")

# -- Colors ----------------------------------------------------------------
C_RST="\\033[0m"
C_GREEN="\\033[38;5;36m"
C_LGREEN="\\033[38;5;115m"
C_DGRAY="\\033[38;5;236m"
C_TEXT="\\033[38;5;253m"
C_ORANGE="\\033[38;5;172m"
C_RED="\\033[38;5;130m"
C_BOLD="\\033[1m"
C_DIM="\\033[2m"

# -- Check root ------------------------------------------------------------
if [[ "\$(id -u)" -ne 0 ]]; then
    echo -e "\${C_RED}Error: Run as root (sudo).\${C_RST}"
    exit 1
fi

# -- Resilient reach: multi-layer fallback to find a working base URL ------
# Tries: direct -> DNS-over-HTTPS resolve -> CF Pages -> GitHub raw
# Stores the working URL for future sessions in /opt/vany/.base_url

# Known Cloudflare anycast IPs (from https://www.cloudflare.com/ips/)
CF_IPS=("104.16.0.1" "104.17.0.1" "172.67.0.1")
DOH_PROVIDERS=("https://1.1.1.1/dns-query" "https://8.8.8.8/resolve" "https://9.9.9.9:5053/dns-query")
FALLBACK_URLS=(
    "https://vany.sh"
    "https://vany-agg.pages.dev"
)
GITHUB_RAW_URL="https://raw.githubusercontent.com/behnamkhorsandian/Vanysh/main"

# Resolve vany.sh via DNS-over-HTTPS, returns IP or empty string
doh_resolve() {
    local doh_url="\$1"
    local ip=""
    ip=\$(curl -sf -m 5 -H "accept: application/dns-json" "\${doh_url}?name=vany.sh&type=A" 2>/dev/null \\
        | grep -oE '"data":"[0-9.]+"' | head -1 | grep -oE '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+' || true)
    echo "\$ip"
}

# Test if a base URL is reachable (returns 0 on success)
test_base() {
    local url="\$1"
    curl -sf -m 5 -o /dev/null "\${url}/health" 2>/dev/null
}

# Find a working base URL with multi-layer fallback
find_base() {
    mkdir -p "\$VANY_DIR"

    # Try cached base URL first
    if [[ -f "\$BASE_FILE" ]]; then
        local cached
        cached=\$(cat "\$BASE_FILE" 2>/dev/null || true)
        if [[ -n "\$cached" ]] && test_base "\$cached"; then
            echo "\$cached"
            return 0
        fi
    fi

    echo -e "\${C_DIM}  Connecting...\${C_RST}" >&2

    # Layer 1: Direct HTTPS to vany.sh
    if test_base "https://vany.sh"; then
        echo "https://vany.sh" > "\$BASE_FILE"
        echo "https://vany.sh"
        return 0
    fi

    echo -e "\${C_DIM}  Direct blocked. Trying GitHub (Fastly CDN)...\${C_RST}" >&2

    # Layer 2: GitHub Raw (Fastly CDN — completely different network than Cloudflare)
    # This often works when Cloudflare is fully blocked (e.g. Iran digital blackout)
    if curl -sf -m 5 -o /dev/null "\${GITHUB_RAW_URL}/start.sh" 2>/dev/null; then
        echo "\${GITHUB_RAW_URL}" > "\$BASE_FILE"
        echo "\${GITHUB_RAW_URL}"
        return 0
    fi

    echo -e "\${C_DIM}  GitHub blocked. Trying direct Cloudflare IPs...\${C_RST}" >&2

    # Layer 3: Use known CF anycast IPs with --resolve (bypasses DNS entirely)
    for cfip in "\${CF_IPS[@]}"; do
        if curl -sf -m 5 -o /dev/null --resolve "vany.sh:443:\${cfip}" "https://vany.sh/health" 2>/dev/null; then
            echo "\$cfip" > "\$VANY_DIR/.resolved_ip"
            echo "https://vany.sh" > "\$BASE_FILE"
            echo "https://vany.sh"
            return 0
        fi
    done

    echo -e "\${C_DIM}  Direct IPs failed. Trying DNS-over-HTTPS...\${C_RST}" >&2

    # Layer 4: Resolve via DoH, then use --resolve to bypass DNS poisoning
    for doh in "\${DOH_PROVIDERS[@]}"; do
        local resolved_ip
        resolved_ip=\$(doh_resolve "\$doh")
        if [[ -n "\$resolved_ip" ]]; then
            if curl -sf -m 5 -o /dev/null --resolve "vany.sh:443:\${resolved_ip}" "https://vany.sh/health" 2>/dev/null; then
                echo "\$resolved_ip" > "\$VANY_DIR/.resolved_ip"
                echo "https://vany.sh" > "\$BASE_FILE"
                echo "https://vany.sh"
                return 0
            fi
        fi
    done

    echo -e "\${C_DIM}  DoH failed. Trying alternate domains...\${C_RST}" >&2

    # Layer 5: Alternate domains (*.pages.dev is hard to block)
    for alt in "\${FALLBACK_URLS[@]}"; do
        if test_base "\$alt"; then
            echo "\$alt" > "\$BASE_FILE"
            echo "\$alt"
            return 0
        fi
    done

    echo -e "\${C_RED}  All access methods failed.\${C_RST}" >&2
    echo -e "\${C_ORANGE}  Try: Install 1.1.1.1 (WARP) app, then run this again.\${C_RST}" >&2
    echo -e "\${C_ORANGE}  Or:  curl -sL \${GITHUB_RAW_URL}/start.sh | sudo bash\${C_RST}" >&2
    return 1
}

# Wrapper for curl that auto-applies --resolve if we have a resolved IP
vany_curl() {
    local resolve_flag=""
    if [[ -f "\$VANY_DIR/.resolved_ip" ]]; then
        local rip
        rip=\$(cat "\$VANY_DIR/.resolved_ip" 2>/dev/null || true)
        if [[ -n "\$rip" ]]; then
            resolve_flag="--resolve vany.sh:443:\${rip}"
        fi
    fi
    if [[ -n "\$resolve_flag" ]]; then
        curl \$resolve_flag "\$@"
    else
        curl "\$@"
    fi
}

# -- Discover working base URL ---------------------------------------------
BASE=\$(find_base) || exit 1

# -- Bootstrap if needed ---------------------------------------------------
if ! command -v docker &>/dev/null; then
    echo -e "\${C_GREEN}First run detected. Installing Docker...\${C_RST}"
    BOOTSTRAP_URL="\${BASE}/scripts/docker-bootstrap.sh"
    vany_curl -sf "\$BOOTSTRAP_URL" | bash
fi

# -- Initialize state if missing ------------------------------------------
if [[ ! -f "\$STATE_FILE" ]]; then
    mkdir -p "\$VANY_DIR"
    PUBLIC_IP=\$(curl -sf https://ifconfig.me || curl -sf https://ipinfo.io/ip || echo "unknown")
    MACHINE_ID=""
    [[ -f /etc/machine-id ]] && MACHINE_ID=\$(cat /etc/machine-id)
    cat > "\$STATE_FILE" <<STATEEOF
{
  "machine_id": "\$MACHINE_ID",
  "ip": "\$PUBLIC_IP",
  "provider": "unknown",
  "protocols": {}
}
STATEEOF
fi

# -- Keyboard from /dev/tty ------------------------------------------------
exec 3</dev/tty

# -- Terminal cleanup ------------------------------------------------------
OLD_STTY=""
cleanup() {
    kill_stream
    [[ -n "\$OLD_STTY" ]] && stty "\$OLD_STTY" <&3 2>/dev/null
    printf "\\033[?25h"
    printf "\\033[?1049l"
    printf "\\r\\n"
    printf "%b\\r\\n" "\${C_GREEN}  Vany - vany.sh"
    printf "%b\\r\\n" "  Goodbye.\${C_RST}"
    printf "\\r\\n"
    exec 3<&- 2>/dev/null
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

# -- Terminal setup --------------------------------------------------------
OLD_STTY=\$(stty -g <&3 2>/dev/null || true)
stty -icanon -echo <&3 2>/dev/null || true
printf "\\033[?1049h"
printf "\\033[?25l"

# -- Output helper (safe for raw-ish mode) ---------------------------------
# Prints a line with CR+LF to handle any terminal mode
out() {
    printf "%s\\r\\n" "\$1"
}
oute() {
    printf "%b\\r\\n" "\$1"
}

# -- Terminal size ---------------------------------------------------------
get_size() {
    cols=\$(tput cols  <&3 2>/dev/null || echo 100)
    rows=\$(tput lines <&3 2>/dev/null || echo 40)
}

# -- Encode state for Worker (fast — just base64 the state file) -----------
encode_state() {
    if [[ -f "\$STATE_FILE" ]]; then
        cat "\$STATE_FILE" | base64 -w0 2>/dev/null || cat "\$STATE_FILE" | base64 2>/dev/null
    else
        echo "e30="
    fi
}

# -- Stream management -----------------------------------------------------
kill_stream() {
    if [[ -n "\$STREAM_PID" ]]; then
        kill "\$STREAM_PID" 2>/dev/null || true
        disown "\$STREAM_PID" 2>/dev/null || true
        STREAM_PID=""
    fi
}

start_stream() {
    local endpoint="\$1"
    kill_stream
    printf "\\033[2J\\033[H"
    get_size
    local state_b64
    state_b64=\$(encode_state)
    vany_curl -sN "\${BASE}/tui/\${endpoint}?cols=\${cols}&rows=\${rows}&stream=1&interactive=1&state=\${state_b64}" 2>/dev/null &
    STREAM_PID=\$!
}

# -- Local page: Docker status ---------------------------------------------
show_status() {
    kill_stream
    CURRENT="status"
    printf "\\033[2J\\033[H"
    get_size

    oute "\${C_GREEN}\${C_BOLD}  DOCKER STATUS\${C_RST}"
    out ""

    # Header and separator - format without ANSI, colorize separately
    local hdr sep
    hdr=\$(printf "  %-20s %-12s %-20s %-15s" "CONTAINER" "STATUS" "IMAGE" "UPTIME")
    sep=\$(printf "  %-20s %-12s %-20s %-15s" "───────────────────" "────────────" "────────────────────" "───────────────")
    oute "\${C_ORANGE}\${hdr}\${C_RST}"
    oute "\${C_DGRAY}\${sep}\${C_RST}"

    local containers=("vany-xray" "vany-wireguard" "vany-dnstt" "vany-conduit" "vany-sos")

    for c in "\${containers[@]}"; do
        local status="--" image="--" uptime="--" color="\${C_DGRAY}"
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^\${c}\$"; then
            status=\$(docker inspect --format '{{.State.Status}}' "\$c" 2>/dev/null || echo "--")
            image=\$(docker inspect --format '{{.Config.Image}}' "\$c" 2>/dev/null | cut -d: -f1 | rev | cut -d/ -f1 | rev)
            uptime=\$(docker inspect --format '{{.State.StartedAt}}' "\$c" 2>/dev/null | cut -dT -f1)
            [[ "\$status" == "running" ]] && color="\${C_GREEN}"
            [[ "\$status" == "exited" ]] && color="\${C_RED}"
        fi
        # Format text first (no ANSI in printf format), then colorize
        local line
        line=\$(printf "  %-20s %-12s %-20s %-15s" "\$c" "\$status" "\$image" "\$uptime")
        oute "\${color}\${line}\${C_RST}"
    done

    out ""
    oute "  \${C_LGREEN}[p]\${C_RST} \${C_TEXT}Protocols\${C_RST}  \${C_LGREEN}[u]\${C_RST} \${C_TEXT}Users\${C_RST}  \${C_LGREEN}[i]\${C_RST} \${C_TEXT}Install\${C_RST}  \${C_LGREEN}[h]\${C_RST} \${C_TEXT}Help\${C_RST}  \${C_LGREEN}[q]\${C_RST} \${C_TEXT}Quit\${C_RST}"
    oute "  \${C_DIM}Press any key to go back\${C_RST}"
}

# -- Local page: Users list ------------------------------------------------
show_users() {
    kill_stream
    CURRENT="users"
    printf "\\033[2J\\033[H"

    oute "\${C_GREEN}\${C_BOLD}  USERS\${C_RST}"
    out ""

    if [[ ! -f "\$USERS_FILE" ]]; then
        oute "  \${C_DIM}No users database found.\${C_RST}"
        out ""
        oute "  \${C_LGREEN}[p]\${C_RST} \${C_TEXT}Protocols\${C_RST}  \${C_LGREEN}[s]\${C_RST} \${C_TEXT}Status\${C_RST}  \${C_LGREEN}[h]\${C_RST} \${C_TEXT}Help\${C_RST}  \${C_LGREEN}[q]\${C_RST} \${C_TEXT}Quit\${C_RST}"
        oute "  \${C_DIM}Press any key to go back\${C_RST}"
        return
    fi

    local usercount
    usercount=\$(jq '.users | length' "\$USERS_FILE" 2>/dev/null || echo 0)

    if [[ "\$usercount" -eq 0 ]]; then
        oute "  \${C_DIM}No users configured.\${C_RST}"
    else
        local hdr sep
        hdr=\$(printf "  %-20s %-15s %-30s" "USERNAME" "PROTOCOLS" "CREATED")
        sep=\$(printf "  %-20s %-15s %-30s" "───────────────────" "──────────────" "────────────────────────────")
        oute "\${C_ORANGE}\${hdr}\${C_RST}"
        oute "\${C_DGRAY}\${sep}\${C_RST}"

        jq -r '.users | to_entries[] | [.key, (.value.protocols | keys | join(",")), .value.created] | @tsv' "\$USERS_FILE" 2>/dev/null | \\
        while IFS=\$'\\t' read -r name protos created; do
            local line
            line=\$(printf "  %-20s %-15s %-30s" "\$name" "\$protos" "\$created")
            oute "\${C_TEXT}\${line}\${C_RST}"
        done
    fi

    out ""
    oute "  \${C_TEXT}Total: \${C_GREEN}\$usercount\${C_RST} users"
    out ""
    oute "  \${C_LGREEN}[p]\${C_RST} \${C_TEXT}Protocols\${C_RST}  \${C_LGREEN}[s]\${C_RST} \${C_TEXT}Status\${C_RST}  \${C_LGREEN}[h]\${C_RST} \${C_TEXT}Help\${C_RST}  \${C_LGREEN}[q]\${C_RST} \${C_TEXT}Quit\${C_RST}"
    oute "  \${C_DIM}Press any key to go back\${C_RST}"
}

# -- Worker-rendered pages -------------------------------------------------
show_worker_page() {
    local page="\$1"
    CURRENT="\$page"
    start_stream "\$page"
}

# -- Install execution ------------------------------------------------------
# Maps protocol name to install script URL, downloads and runs it
declare -A INSTALL_SCRIPTS=(
    [reality]="install-xray.sh"
    [ws]="install-xray.sh"
    [wg]="install-wireguard.sh"
    [dnstt]="install-dnstt.sh"
    [conduit]="install-conduit.sh"
    [sos]="install-sos.sh"
)

run_install() {
    local proto="\$1"
    kill_stream
    printf "\\033[2J\\033[H"

    local script_name="\${INSTALL_SCRIPTS[\$proto]}"
    if [[ -z "\$script_name" ]]; then
        oute "\${C_RED}  Unknown protocol: \$proto\${C_RST}"
        out ""
        oute "  \${C_DIM}Press any key to continue\${C_RST}"
        IFS= read -rsn1 _ <&3
        navigate "install"
        return
    fi

    oute "\${C_GREEN}\${C_BOLD}  INSTALLING: \$proto\${C_RST}"
    out ""
    oute "  \${C_DIM}Downloading \$script_name ...\${C_RST}"
    out ""

    local script_url="\${BASE}/scripts/protocols/\${script_name}"
    local script
    script=\$(vany_curl -sf "\$script_url" 2>/dev/null || true)
    if [[ -z "\$script" ]]; then
        oute "  \${C_RED}Failed to download install script.\${C_RST}"
        out ""
        oute "  \${C_DIM}Press any key to continue\${C_RST}"
        IFS= read -rsn1 _ <&3
        navigate "install"
        return
    fi

    # Save script locally so functions can source other local files
    mkdir -p /opt/vany/scripts/protocols
    echo "\$script" > "/opt/vany/scripts/protocols/\${script_name}"
    chmod +x "/opt/vany/scripts/protocols/\${script_name}"

    oute "  \${C_LGREEN}Running installer ...\${C_RST}"
    out ""

    # Execute via bash
    if bash "/opt/vany/scripts/protocols/\${script_name}" 2>&1 | while IFS= read -r line; do
        out "  \$line"
    done; then
        oute ""
        oute "\${C_GREEN}  Installation complete.\${C_RST}"
    else
        oute ""
        oute "\${C_RED}  Installation failed (exit code: \${PIPESTATUS[0]}).\${C_RST}"
    fi

    out ""
    oute "  \${C_DIM}Press any key to continue\${C_RST}"
    IFS= read -rsn1 _ <&3
    navigate "protocols"
}

# -- Navigate --------------------------------------------------------------
navigate() {
    case "\$1" in
        protocols)     show_worker_page "protocols" ;;
        status)        show_status ;;
        users)         show_users ;;
        install)       show_worker_page "install" ;;
        install/*)     show_worker_page "\$1" ;;
        help)          show_worker_page "help" ;;
    esac
}

# -- Embedded command handler -----------------------------------------------
# Worker sends: \\x1b]vany;cmd;<base64-command>\\x07
# Client detects, decodes, executes, shows result
handle_embedded_cmd() {
    local encoded="\$1"
    local cmd
    cmd=\$(echo "\$encoded" | base64 -d 2>/dev/null)
    if [[ -z "\$cmd" ]]; then
        return 1
    fi

    printf "\\033[2J\\033[H"
    oute "\${C_GREEN}\${C_BOLD}  EXECUTING\${C_RST}"
    out ""
    oute "  \${C_DIM}\$cmd\${C_RST}"
    out ""

    # Execute the command
    if eval "\$cmd" 2>&1 | while IFS= read -r line; do
        out "  \$line"
    done; then
        oute "\${C_GREEN}  Done.\${C_RST}"
    else
        oute "\${C_RED}  Failed.\${C_RST}"
    fi

    out ""
    oute "  \${C_DIM}Press any key to continue\${C_RST}"
    IFS= read -rsn1 _ <&3
    navigate "protocols"
}

# -- Read keypress from /dev/tty -------------------------------------------
read_key() {
    local c1 c2 c3
    IFS= read -rsn1 -t 1 c1 <&3 || { echo "TICK"; return; }

    if [[ "\$c1" == \$'\\033' ]]; then
        IFS= read -rsn1 -t 0.1 c2 <&3 || true
        if [[ "\$c2" == "[" ]]; then
            IFS= read -rsn1 -t 0.1 c3 <&3 || true
            case "\$c3" in
                A) echo "UP";    return ;;
                B) echo "DOWN";  return ;;
                C) echo "RIGHT"; return ;;
                D) echo "LEFT";  return ;;
            esac
        fi
        echo "ESC"
        return
    fi

    if [[ -z "\$c1" || "\$c1" == \$'\\r' || "\$c1" == \$'\\n' ]]; then
        echo "ENTER"
        return
    fi
    echo "\$c1"
}

# -- Handle key input -------------------------------------------------------
handle_key() {
    local key="\$1"
    case "\$key" in
        p|P) navigate "protocols" ;;
        s|S) navigate "status"    ;;
        u|U) navigate "users"     ;;
        i|I) navigate "install"   ;;
        h|H) navigate "help"      ;;
        r|R) navigate "\$CURRENT"  ;;
        q|Q) exit 0               ;;
        TICK) ;;
        # Number keys on install page select a protocol
        [1-6])
            if [[ "\$CURRENT" == "install" ]]; then
                local idx=\$(( key - 1 ))
                local proto="\${PROTO_MAP[\$idx]}"
                navigate "install/\$proto"
            fi
            ;;
        ENTER)
            # On install detail page, run the install
            if [[ "\$CURRENT" == install/* ]]; then
                local proto="\${CURRENT#install/}"
                run_install "\$proto"
            fi
            ;;
        ESC)
            # ESC goes back: install detail -> install overview, else -> protocols
            if [[ "\$CURRENT" == install/* ]]; then
                navigate "install"
            else
                navigate "protocols"
            fi
            ;;
        *)
            # On local pages, any key goes back to protocols
            if [[ "\$CURRENT" == "status" || "\$CURRENT" == "users" ]]; then
                navigate "protocols"
            fi
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

# Show splash briefly
get_size
vany_curl -sf "\${BASE}/tui/splash?cols=\${cols}&rows=\${rows}" 2>/dev/null
sleep 1

# Start on protocols page
navigate "protocols"

# Input loop
while true; do
    key=\$(read_key)
    handle_key "\$key"
done
`;
