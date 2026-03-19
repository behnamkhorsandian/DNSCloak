#!/bin/bash
#===============================================================================
# Vany TUI - Step-by-Step Install Wizard
# Renders within unified frame with dimmed sidebar + scrolling log panel
#===============================================================================

TUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TUI_DIR/engine.sh"

#-------------------------------------------------------------------------------
# Wizard Step Types:
#   choice  - Pick from a list
#   input   - Free text input
#   confirm - Yes/No question
#   info    - Display-only (press Enter to continue)
#   action  - Run a command with progress display
#-------------------------------------------------------------------------------

# Each protocol defines its wizard steps as arrays of pipe-delimited fields:
#   "type|variable|prompt|default|help_text|options"
#
# For choice type, options = "opt1,opt2,opt3"
# For action type, prompt = description, options = function_name

#-------------------------------------------------------------------------------
# Protocol wizard step definitions
#-------------------------------------------------------------------------------

define_wizard_steps() {
    local proto="$1"

    WIZARD_STEPS=()

    # Try to load from JSON data (populated by engine.sh _load_wizard_steps_json)
    if type _load_wizard_steps_json &>/dev/null; then
        _load_wizard_steps_json "$proto"
        if [[ ${#WIZARD_STEPS[@]} -gt 0 ]]; then
            return
        fi
    fi

    # Fallback: hardcoded step definitions
    case "$proto" in
        reality)
            WIZARD_STEPS=(
                "info||VLESS + REALITY Setup||This will install Xray-core and configure a REALITY proxy that disguises your traffic as normal HTTPS. No domain name is needed. Port 443 must be available.|"
                "choice|REALITY_TARGET_IDX|Select camouflage target|0|Your server will impersonate this website. Censors will see what looks like traffic to this site. All options work well.|www.google.com,www.microsoft.com,www.apple.com,www.cloudflare.com,www.mozilla.org,www.amazon.com"
                "confirm|USE_DOMAIN|Use a domain instead of IP in client links?|n|If you have a domain pointing to this server (Cloudflare proxy OFF), you can use it in connection links. Otherwise your server IP will be used.|"
                "input|CONNECTION_DOMAIN|Enter your domain|proxy.example.com|Create an A record pointing to your server IP. Make sure Cloudflare proxy is OFF (gray cloud). Leave empty to use server IP.|"
                "input|FIRST_USERNAME|Create first username|user1|This will be the first user who can connect. You can add more users later from the management menu.|"
                "action||Installing REALITY||install_reality_automated|install_reality_automated"
            )
            ;;
        wg)
            WIZARD_STEPS=(
                "info||WireGuard VPN Setup||This will install WireGuard and create a VPN tunnel. All device traffic will be routed through your server. UDP port 51820 must be open.|"
                "input|FIRST_USERNAME|Create first username|user1|This will be the first VPN user. A config file and QR code will be generated for easy mobile setup.|"
                "action||Installing WireGuard||install_wg_automated|install_wg_automated"
            )
            ;;
        ws)
            WIZARD_STEPS=(
                "info||VLESS + WebSocket + CDN Setup||This routes traffic through Cloudflare's CDN, hiding your server IP. You need a domain name on Cloudflare (free plan works). Set Cloudflare SSL mode to 'Flexible'.|"
                "input|WS_DOMAIN|Enter your domain|ws.example.com|Your domain must be on Cloudflare with the proxy enabled (orange cloud). SSL mode in Cloudflare must be set to 'Flexible'. The domain should resolve to your server IP.|"
                "input|FIRST_USERNAME|Create first username|user1|This will be the first user. Connection links will use your Cloudflare-proxied domain.|"
                "action||Installing WebSocket + CDN||install_ws_automated|install_ws_automated"
            )
            ;;
        mtp)
            WIZARD_STEPS=(
                "info||MTProto Proxy Setup||This installs a Telegram-specific proxy. Users won't need any extra apps - they just click a link in Telegram to connect.|"
                "input|MTP_PORT|Select port for MTProto proxy|443|Port 443 is recommended (looks like HTTPS). If 443 is in use, try 8443. Any port works but 443 is least likely to be blocked.|"
                "choice|MTP_MODE_IDX|Select proxy mode|0|Fake-TLS makes traffic look like real HTTPS. Secure mode uses random padding. Fake-TLS is recommended for most cases.|Fake-TLS (recommended),Secure (random padding)"
                "input|MTP_TLS_DOMAIN|TLS camouflage domain|www.google.com|When using Fake-TLS mode, traffic will look like HTTPS to this domain. Use a popular website for best results.|"
                "input|FIRST_USERNAME|Create first username|user1|A proxy link will be generated that users can click in Telegram to start using the proxy.|"
                "action||Installing MTProto||install_mtp_automated|install_mtp_automated"
            )
            ;;
        dnstt)
            WIZARD_STEPS=(
                "info||DNS Tunnel Setup||DNSTT encodes traffic inside DNS queries. This is an EMERGENCY protocol - very slow (~50 KB/s) but nearly impossible to block. Use only when everything else fails.|"
                "confirm|DNSTT_CONTINUE|This protocol is very slow. Continue?|y|DNSTT is designed for emergency situations where all other protocols are blocked. Normal browsing will be very slow. Consider installing Reality or WireGuard for daily use.|"
                "input|DNSTT_DOMAIN|Enter your domain|example.com|You need a domain where you can set DNS records. Required: 1) A record for ns1.domain -> your server IP. 2) NS record for t.domain -> ns1.domain. The domain must NOT be behind Cloudflare proxy.|"
                "action||Installing DNS Tunnel||install_dnstt_automated|install_dnstt_automated"
            )
            ;;
        conduit)
            WIZARD_STEPS=(
                "info||Conduit (Psiphon Relay) Setup||This turns your server into a volunteer relay for the Psiphon network. You'll be helping users in censored regions access the internet. Docker will be installed if not present.|"
                "input|CONDUIT_MAX_CLIENTS|Maximum connected clients|300|How many simultaneous users can relay through your server. More clients = more bandwidth used. Recommended: 200-1000.|"
                "input|CONDUIT_BW_LIMIT|Bandwidth limit in Mbps (-1 = unlimited)|-1|Set a bandwidth cap to control costs. -1 means no limit. Set based on your VM's bandwidth allowance.|"
                "action||Installing Conduit||install_conduit_automated|install_conduit_automated"
            )
            ;;
        vray)
            WIZARD_STEPS=(
                "info||VLESS + TLS Setup||This is a classic V2Ray setup with real TLS certificates from Let's Encrypt. Requires a domain name pointing to your server.|"
                "input|VRAY_DOMAIN|Enter your domain|proxy.example.com|Your domain must have an A record pointing to this server. A free TLS certificate will be obtained from Let's Encrypt.|"
                "input|FIRST_USERNAME|Create first username|user1|Connection links will use your domain with proper TLS encryption.|"
                "action||Installing VLESS + TLS||install_vray_automated|install_vray_automated"
            )
            ;;
        sos)
            WIZARD_STEPS=(
                "info||SOS Emergency Chat Setup||This installs the SOS relay daemon for encrypted emergency chat. Messages are encrypted end-to-end and travel through DNS tunnels. Requires DNSTT to be running first.|"
                "action||Installing SOS Relay||install_sos_automated|install_sos_automated"
            )
            ;;
    esac
}

#-------------------------------------------------------------------------------
# Render a single wizard step and collect input
# Returns 0 = next, 1 = back, 2 = cancel
# Sets the step's variable to the collected value
#-------------------------------------------------------------------------------

# Build a text progress bar for FRAME_CONTENT
_wizard_progress_line() {
    local current=$1
    local total=$2
    local bar_w=20
    local pct=0
    (( total > 0 )) && pct=$(( current * 100 / total ))
    local filled=0
    (( total > 0 )) && filled=$(( bar_w * current / total ))
    local empty=$(( bar_w - filled ))

    local bar="${C_GREEN}"
    local i
    for (( i = 0; i < filled; i++ )); do bar+="$BOX_H"; done
    bar+="${C_DGRAY}"
    for (( i = 0; i < empty; i++ )); do bar+="$BOX_H"; done
    bar+="${C_RST}"

    printf '%bStep %d of %d%b  [%b]  %b%d%%%b' \
        "$C_ORANGE" "$current" "$total" "$C_RST" \
        "$bar" \
        "$C_TEXT" "$pct" "$C_RST"
}

# Build common wizard FRAME_CONTENT header (title, progress, help text)
_wizard_build_header() {
    local proto_name="$1"
    local step_prompt="$2"
    local step_num="$3"
    local total_steps="$4"
    local step_help="$5"

    FRAME_CONTENT=()
    FRAME_CONTENT+=("${C_ORANGE}${C_BOLD}${proto_name}${C_RST}")
    FRAME_CONTENT+=("")
    FRAME_CONTENT+=("$(_wizard_progress_line "$step_num" "$total_steps")")
    FRAME_CONTENT+=("")
    FRAME_CONTENT+=("${C_LGREEN}${step_prompt}${C_RST}")
    FRAME_CONTENT+=("")

    if [[ -n "$step_help" ]]; then
        local help_width=$(( _CONTENT_INNER_W - 4 ))
        (( help_width < 20 )) && help_width=20
        while IFS= read -r line; do
            FRAME_CONTENT+=("${C_LGRAY}${line}${C_RST}")
        done <<< "$(word_wrap "$step_help" "$help_width")"
        FRAME_CONTENT+=("")
    fi
}

render_wizard_step() {
    local step_def="$1"
    local step_num="$2"
    local total_steps="$3"
    local proto_name="$4"

    # Parse step definition
    IFS='|' read -r step_type step_var step_prompt step_default step_help step_options <<< "$step_def"

    tui_get_size
    tui_compute_layout

    case "$step_type" in
        info)
            _wizard_build_header "$proto_name" "$step_prompt" "$step_num" "$total_steps" "$step_help"
            FRAME_CONTENT+=("${C_TEXT}Press Enter to continue${C_RST}")

            FRAME_FOOTER="${C_DGRAY}Enter${C_RST}${C_DIM} continue${C_RST}  "
            FRAME_FOOTER+="${C_DGRAY}Esc${C_RST}${C_DIM} cancel${C_RST}"

            tui_render_frame

            while true; do
                local key
                key=$(tui_read_key)
                case "$key" in
                    ENTER) return 0 ;;
                    ESC|q|Q) return 2 ;;
                esac
            done
            ;;

        choice)
            IFS=',' read -ra options <<< "$step_options"
            local sel="${!step_var:-$step_default}"
            [[ -z "$sel" ]] && sel=0

            while true; do
                tui_get_size
                tui_compute_layout

                _wizard_build_header "$proto_name" "$step_prompt" "$step_num" "$total_steps" "$step_help"

                # Separator
                local sep_w=$(( _CONTENT_INNER_W - 4 ))
                (( sep_w > 40 )) && sep_w=40
                (( sep_w < 10 )) && sep_w=10
                FRAME_CONTENT+=("${C_DGRAY}$(repeat_str "$BOX_H" "$sep_w")${C_RST}")
                FRAME_CONTENT+=("")

                local i=0
                for opt in "${options[@]}"; do
                    local prefix="   "
                    local ocolor="$C_TEXT"
                    if [[ $i -eq $sel ]]; then
                        prefix=" ${C_GREEN}>${C_RST}"
                        ocolor="${C_GREEN}${C_BOLD}"
                    fi
                    FRAME_CONTENT+=("${prefix} ${ocolor}${opt}${C_RST}")
                    (( i++ ))
                done

                FRAME_FOOTER="${C_DGRAY}^/v${C_RST}${C_DIM} navigate${C_RST}  "
                FRAME_FOOTER+="${C_DGRAY}Enter${C_RST}${C_DIM} select${C_RST}  "
                FRAME_FOOTER+="${C_DGRAY}del${C_RST}${C_DIM} back${C_RST}  "
                FRAME_FOOTER+="${C_DGRAY}Esc${C_RST}${C_DIM} cancel${C_RST}"

                tui_render_frame

                local key
                key=$(tui_read_key)
                case "$key" in
                    UP)
                        (( sel-- ))
                        (( sel < 0 )) && sel=$(( ${#options[@]} - 1 ))
                        ;;
                    DOWN)
                        (( sel++ ))
                        (( sel >= ${#options[@]} )) && sel=0
                        ;;
                    ENTER)
                        eval "$step_var=$sel"
                        return 0
                        ;;
                    BACKSPACE) return 1 ;;
                    ESC|q|Q)   return 2 ;;
                esac
            done
            ;;

        input)
            _wizard_build_header "$proto_name" "$step_prompt" "$step_num" "$total_steps" "$step_help"

            local current_val="${!step_var:-$step_default}"
            FRAME_CONTENT+=("${C_DGRAY}Default: ${current_val}${C_RST}")
            FRAME_CONTENT+=("")

            # Record which content line the input prompt will be on
            local input_line_idx=${#FRAME_CONTENT[@]}
            FRAME_CONTENT+=("${C_GREEN}[>]${C_RST} ${step_prompt}: ")

            FRAME_FOOTER="${C_DIM}Type value${C_RST}  "
            FRAME_FOOTER+="${C_DGRAY}Enter${C_RST}${C_DIM} confirm${C_RST}  "
            FRAME_FOOTER+="${C_DGRAY}Esc${C_RST}${C_DIM} cancel${C_RST}"

            tui_render_frame

            # Position cursor at input field
            # Content rows start at screen row 4 (top border + status + split top)
            local screen_row=$(( 4 + input_line_idx ))
            local prompt_text="${C_GREEN}[>]${C_RST} ${step_prompt}: "
            local prompt_vlen
            prompt_vlen=$(visible_len " $prompt_text")
            local col_start
            if (( _COMPACT )); then
                col_start=$(( 2 + prompt_vlen ))
            else
                col_start=$(( _SIDEBAR_INNER_W + 3 + prompt_vlen ))
            fi

            printf '\033[?25h'
            cursor_to "$screen_row" "$col_start"

            # Read input character by character
            local input_val=""
            stty -echo -icanon min 1 time 0 <&3 2>/dev/null

            while true; do
                local ch=""
                IFS= read -rsn1 ch <&3

                if [[ "$ch" == $'\033' ]]; then
                    local c2=""
                    IFS= read -rsn1 -t 0.1 c2 <&3 2>/dev/null || true
                    if [[ -z "$c2" ]]; then
                        # Escape pressed — cancel wizard
                        stty echo icanon <&3 2>/dev/null
                        printf '\033[?25l'
                        return 2
                    fi
                    # Consume rest of escape sequence
                    [[ "$c2" == "[" ]] && IFS= read -rsn1 -t 0.1 _ <&3 2>/dev/null || true
                    continue
                fi

                if [[ "$ch" == "" ]]; then
                    # Enter pressed
                    break
                fi

                if [[ "$ch" == $'\177' || "$ch" == $'\b' ]]; then
                    if [[ -n "$input_val" ]]; then
                        input_val="${input_val%?}"
                        printf '\b \b'
                    fi
                    continue
                fi

                if [[ "$ch" =~ ^[[:print:]]$ ]]; then
                    input_val+="$ch"
                    printf '%s' "$ch"
                fi
            done

            stty echo icanon <&3 2>/dev/null
            printf '\033[?25l'

            if [[ -z "$input_val" && -n "$step_default" ]]; then
                input_val="$step_default"
            fi
            eval "$step_var=\$input_val"
            return 0
            ;;

        confirm)
            _wizard_build_header "$proto_name" "$step_prompt" "$step_num" "$total_steps" "$step_help"

            local sep_w=$(( _CONTENT_INNER_W - 4 ))
            (( sep_w > 40 )) && sep_w=40
            (( sep_w < 10 )) && sep_w=10
            FRAME_CONTENT+=("${C_DGRAY}$(repeat_str "$BOX_H" "$sep_w")${C_RST}")
            FRAME_CONTENT+=("")
            FRAME_CONTENT+=(" ${C_GREEN}[Y]${C_RST} ${C_TEXT}Yes${C_RST}    ${C_RED}[N]${C_RST} ${C_TEXT}No${C_RST}    ${C_DGRAY}Default: ${step_default}${C_RST}")

            FRAME_FOOTER="${C_DGRAY}y/n${C_RST}${C_DIM} answer${C_RST}  "
            FRAME_FOOTER+="${C_DGRAY}Enter${C_RST}${C_DIM} default${C_RST}  "
            FRAME_FOOTER+="${C_DGRAY}del${C_RST}${C_DIM} back${C_RST}  "
            FRAME_FOOTER+="${C_DGRAY}Esc${C_RST}${C_DIM} cancel${C_RST}"

            tui_render_frame

            while true; do
                local key
                key=$(tui_read_key)
                case "$key" in
                    y|Y)
                        eval "$step_var=y"
                        return 0
                        ;;
                    n|N)
                        eval "$step_var=n"
                        return 0
                        ;;
                    ENTER)
                        eval "$step_var=$step_default"
                        return 0
                        ;;
                    ESC)      return 2 ;;
                    BACKSPACE) return 1 ;;
                    q|Q)  return 2 ;;
                esac
            done
            ;;

        action)
            if ! type "$step_options" &>/dev/null; then
                _wizard_build_header "$proto_name" "Error" "$step_num" "$total_steps" ""
                FRAME_CONTENT+=("${C_RED}Install function \"${step_options}\" not found${C_RST}")
                FRAME_FOOTER="${C_DGRAY}Enter${C_RST}${C_DIM} back${C_RST}"
                tui_render_frame
                tui_read_key >/dev/null
                return 1
            fi

            # Use tui_run_cmd_framed for live log display
            FRAME_FOOTER="${C_DIM}Installing... please wait${C_RST}"
            tui_run_cmd_framed "Installing ${proto_name}" "$step_options"
            local rc=$?

            if [[ $rc -ne 0 ]]; then
                # Show failure in frame
                _wizard_build_header "$proto_name" "Installation Failed" "$step_num" "$total_steps" ""
                FRAME_CONTENT+=("${C_RED}Exit code: ${rc}${C_RST}")
                FRAME_CONTENT+=("")

                # Show last lines of log if available
                local logfile="/tmp/vany-install-$$.log"
                if [[ -f "$logfile" ]]; then
                    FRAME_CONTENT+=("${C_LGRAY}Last output:${C_RST}")
                    while IFS= read -r line; do
                        FRAME_CONTENT+=("${C_DGRAY}${line}${C_RST}")
                    done < <(tail -10 "$logfile" 2>/dev/null)
                    rm -f "$logfile"
                fi

                FRAME_FOOTER="${C_DGRAY}Enter${C_RST}${C_DIM} go back${C_RST}"
                tui_render_frame
                tui_read_key >/dev/null
                return 1
            fi

            # Show success in frame
            _wizard_build_header "$proto_name" "Complete" "$step_num" "$total_steps" ""
            FRAME_CONTENT+=("${C_GREEN}*${C_RST} ${C_TEXT}Installation completed successfully${C_RST}")
            FRAME_FOOTER="${C_DGRAY}Enter${C_RST}${C_DIM} continue${C_RST}"
            tui_render_frame
            tui_read_key >/dev/null
            return 0
            ;;
    esac
}

#-------------------------------------------------------------------------------
# Run the wizard for a protocol
# Usage: run_wizard "protocol_id"
# Returns: 0 on success, 1 on cancel
#-------------------------------------------------------------------------------

run_wizard() {
    local proto="$1"
    local proto_name="${PROTOCOL_NAMES[$proto]}"

    # Dim sidebar during wizard
    _SIDEBAR_DIM=1
    _SIDEBAR_PAGE="protocols"

    # Set banner to the protocol being installed
    FRAME_BANNER="${PROTOCOL_BANNER_FILE[$proto]:-$proto}"
    local bcolor="${PROTOCOL_BANNER_COLOR[$proto]:-green}"
    FRAME_BANNER_COLOR="${_COLOR_MAP[$bcolor]:-$C_GREEN}"

    define_wizard_steps "$proto"

    local step_count=${#WIZARD_STEPS[@]}
    if (( step_count == 0 )); then
        _SIDEBAR_DIM=0
        return 1
    fi

    local current_step=0

    while (( current_step < step_count )); do
        local step_def="${WIZARD_STEPS[$current_step]}"

        # Skip conditional steps
        if _should_skip_step "$proto" "$current_step"; then
            (( current_step++ ))
            continue
        fi

        render_wizard_step "$step_def" "$((current_step + 1))" "$step_count" "$proto_name"
        local rc=$?

        case $rc in
            0)  # Next
                (( current_step++ ))
                ;;
            1)  # Back
                (( current_step > 0 )) && (( current_step-- ))
                while (( current_step > 0 )) && _should_skip_step "$proto" "$current_step"; do
                    (( current_step-- ))
                done
                ;;
            2)  # Cancel
                _SIDEBAR_DIM=0
                return 1
                ;;
        esac
    done

    _SIDEBAR_DIM=0
    return 0
}

#-------------------------------------------------------------------------------
# Conditional step logic
#-------------------------------------------------------------------------------

_should_skip_step() {
    local proto="$1"
    local step_idx="$2"

    case "$proto" in
        reality)
            # Step 3 (domain input): skip if USE_DOMAIN != y
            if [[ $step_idx -eq 3 && "${USE_DOMAIN:-n}" != "y" ]]; then
                return 0
            fi
            ;;
        mtp)
            # Step 3 (TLS domain): skip if mode is not Fake-TLS (index 0)
            if [[ $step_idx -eq 3 && "${MTP_MODE_IDX:-0}" != "0" ]]; then
                return 0
            fi
            ;;
        dnstt)
            # Step 2 (domain input): skip if DNSTT_CONTINUE != y
            if [[ $step_idx -eq 2 && "${DNSTT_CONTINUE:-y}" != "y" ]]; then
                return 0
            fi
            ;;
    esac
    return 1  # don't skip
}

#-------------------------------------------------------------------------------
# Automated install functions (called by wizard action steps)
# These bridge wizard-collected variables to existing install functions
#-------------------------------------------------------------------------------

install_reality_automated() {
    # Source the actual installer if available
    _source_protocol "reality" || return 1

    # Map wizard variables to what the installer expects
    local camouflage_targets=("www.google.com" "www.microsoft.com" "www.apple.com" "www.cloudflare.com" "www.mozilla.org" "www.amazon.com")
    REALITY_TARGET="${camouflage_targets[${REALITY_TARGET_IDX:-0}]}"

    # Bootstrap
    if type bootstrap &>/dev/null; then
        bootstrap
    fi

    # Generate keys
    generate_reality_keys

    # Configure short ID
    REALITY_SHORT_ID=$(generate_short_id)

    # Configure connection address
    if [[ "${USE_DOMAIN:-n}" == "y" && -n "${CONNECTION_DOMAIN:-}" ]]; then
        server_set "reality_address" "$CONNECTION_DOMAIN"
    else
        local server_ip
        server_ip=$(server_get "ip")
        server_set "reality_address" "$server_ip"
    fi

    # Add inbound
    xray_add_reality_inbound "$REALITY_PRIVATE_KEY" "$REALITY_TARGET" "[\"$REALITY_SHORT_ID\"]"
    server_set "reality_public_key" "$REALITY_PUBLIC_KEY"
    server_set "reality_target" "$REALITY_TARGET"
    server_set "reality_short_id" "$REALITY_SHORT_ID"

    # Start service
    service_enable xray
    sleep 2

    # Add first user
    add_reality_user "${FIRST_USERNAME:-user1}"
}

install_wg_automated() {
    _source_protocol "wg" || return 1
    if type bootstrap &>/dev/null; then
        bootstrap
    fi
    install_wireguard_service
    add_wg_user "${FIRST_USERNAME:-user1}"
}

install_ws_automated() {
    _source_protocol "ws" || return 1
    if type bootstrap &>/dev/null; then
        bootstrap
    fi
    WS_DOMAIN="${WS_DOMAIN:-}"
    install_ws_service "$WS_DOMAIN"
    add_ws_user "${FIRST_USERNAME:-user1}"
}

install_mtp_automated() {
    _source_protocol "mtp" || return 1
    local modes=("tls" "secure")
    MTP_MODE="${modes[${MTP_MODE_IDX:-0}]}"
    install_mtp_service "${MTP_PORT:-443}" "$MTP_MODE" "${MTP_TLS_DOMAIN:-www.google.com}"
    add_mtp_user "${FIRST_USERNAME:-user1}"
}

install_dnstt_automated() {
    if [[ "${DNSTT_CONTINUE:-y}" != "y" ]]; then
        return 1
    fi
    _source_protocol "dnstt" || return 1
    install_dnstt_service "${DNSTT_DOMAIN:-}"
}

install_conduit_automated() {
    _source_protocol "conduit" || return 1
    install_conduit_service "${CONDUIT_MAX_CLIENTS:-300}" "${CONDUIT_BW_LIMIT:--1}"
}

install_vray_automated() {
    _source_protocol "vray" || return 1
    if type bootstrap &>/dev/null; then
        bootstrap
    fi
    install_vray_service "${VRAY_DOMAIN:-}"
    add_vray_user "${FIRST_USERNAME:-user1}"
}

install_sos_automated() {
    _source_protocol "sos" || return 1
    install_sos_service
}

# Source a protocol's function library (downloads if needed)
_source_protocol() {
    local proto="$1"
    local functions_sourced=0
    local install_sourced=0

    # Directories to check for already-installed files (permanent locations only)
    local search_dirs=(
        "/opt/vany/services/$proto"
    )

    # Also check relative to the repo root (works when running from git checkout)
    local repo_dir=""
    if [[ -n "${TUI_DIR:-}" ]]; then
        repo_dir="$(cd "$TUI_DIR/.." 2>/dev/null && pwd)"
    else
        repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)"
    fi
    [[ -n "$repo_dir" && -d "$repo_dir/services/$proto" ]] && \
        search_dirs+=("$repo_dir/services/$proto")

    # Pass 1: source from local permanent paths
    for dir in "${search_dirs[@]}"; do
        if [[ $functions_sourced -eq 0 && -f "$dir/functions.sh" ]]; then
            source "$dir/functions.sh"
            functions_sourced=1
        fi
        if [[ $install_sourced -eq 0 && -f "$dir/install.sh" ]]; then
            main() { :; }
            source "$dir/install.sh" 2>/dev/null
            unset -f main 2>/dev/null
            install_sourced=1
        fi
    done

    if [[ $functions_sourced -eq 1 ]]; then
        return 0
    fi
    if [[ $install_sourced -eq 1 ]]; then
        return 0
    fi

    # Pass 2: download fresh from GitHub (clear stale cache first)
    local dl_dir="/tmp/vany-services/$proto"
    rm -rf "$dl_dir"
    mkdir -p "$dl_dir"
    local base_url="${GITHUB_RAW:-https://raw.githubusercontent.com/behnamkhorsandian/Vanyshsh/main}/services/$proto"

    # Try functions.sh first (preferred — non-interactive)
    if curl -sfL "$base_url/functions.sh" -o "$dl_dir/functions.sh" 2>/dev/null; then
        source "$dl_dir/functions.sh"
        functions_sourced=1
    fi

    # Also try install.sh (some protocols only have this, e.g. sos)
    if [[ $functions_sourced -eq 0 ]]; then
        if curl -sfL "$base_url/install.sh" -o "$dl_dir/install.sh" 2>/dev/null; then
            main() { :; }
            source "$dl_dir/install.sh" 2>/dev/null
            unset -f main 2>/dev/null
            install_sourced=1
        fi
    fi

    if [[ $functions_sourced -eq 0 && $install_sourced -eq 0 ]]; then
        printf '  %b[-]%b Failed to load %s service functions\n' "$C_RED" "$C_RST" "$proto"
        return 1
    fi
    return 0
}
