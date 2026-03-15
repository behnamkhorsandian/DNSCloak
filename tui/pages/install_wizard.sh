#!/bin/bash
#===============================================================================
# DNSCloak TUI - Step-by-Step Install Wizard
# One question per screen, with guide text, progress indicator, and navigation
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

render_wizard_step() {
    local step_def="$1"
    local step_num="$2"
    local total_steps="$3"
    local proto_name="$4"

    # Parse step definition
    IFS='|' read -r step_type step_var step_prompt step_default step_help step_options <<< "$step_def"

    tui_get_size
    tui_compute_layout

    clear_screen

    # Progress bar
    printf '\n'
    _m; printf '  %b%s%b  Step %d of %d  ' "$C_ORANGE" "$proto_name" "$C_RST" "$step_num" "$total_steps"
    tui_progress "$step_num" "$total_steps" 20
    printf '\n\n'

    # Main content box
    draw_box_top "" "$step_prompt"
    draw_box_empty

    # Help text (word-wrapped inside box)
    if [[ -n "$step_help" ]]; then
        local help_width=$(( _FRAME_W - 6 ))
        while IFS= read -r line; do
            draw_box_row " ${C_LGRAY}${line}${C_RST}"
        done <<< "$(word_wrap "$step_help" "$help_width")"
        draw_box_empty
    fi

    case "$step_type" in
        info)
            draw_box_sep
            draw_box_row " ${C_DGRAY}Press Enter to continue  |  Esc to cancel${C_RST}"
            draw_box_bottom

            while true; do
                local key
                key=$(tui_read_key)
                case "$key" in
                    ENTER) return 0 ;;
                    ESC)   return 2 ;;
                    q|Q)   return 2 ;;
                esac
            done
            ;;

        choice)
            # Parse options
            IFS=',' read -ra options <<< "$step_options"
            local sel="${!step_var:-$step_default}"
            [[ -z "$sel" ]] && sel=0

            while true; do
                # Redraw options
                clear_screen
                printf '\n'
                _m; printf '  %b%s%b  Step %d of %d  ' "$C_ORANGE" "$proto_name" "$C_RST" "$step_num" "$total_steps"
                tui_progress "$step_num" "$total_steps" 20
                printf '\n\n'
                draw_box_top "" "$step_prompt"
                draw_box_empty

                if [[ -n "$step_help" ]]; then
                    local help_width=$(( _FRAME_W - 6 ))
                    while IFS= read -r line; do
                        draw_box_row " ${C_LGRAY}${line}${C_RST}"
                    done <<< "$(word_wrap "$step_help" "$help_width")"
                    draw_box_empty
                    draw_box_sep
                    draw_box_empty
                fi

                local i=0
                for opt in "${options[@]}"; do
                    local prefix="   "
                    local ocolor="$C_TEXT"
                    if [[ $i -eq $sel ]]; then
                        prefix=" ${C_GREEN}>${C_RST}"
                        ocolor="${C_GREEN}${C_BOLD}"
                    fi
                    draw_box_row "${prefix} ${ocolor}${opt}${C_RST}"
                    (( i++ ))
                done

                draw_box_empty
                draw_box_sep
                draw_box_row " ${C_DGRAY}Up/Down${C_RST}${C_DIM} navigate${C_RST}  ${C_DGRAY}Enter${C_RST}${C_DIM} select${C_RST}  ${C_DGRAY}Esc${C_RST}${C_DIM} back${C_RST}"
                draw_box_bottom

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
                    ESC)
                        return 1
                        ;;
                    q|Q)
                        return 2
                        ;;
                esac
            done
            ;;

        input)
            draw_box_sep
            draw_box_empty

            local current_val="${!step_var:-$step_default}"
            draw_box_row " ${C_DGRAY}Default: ${current_val}${C_RST}"
            draw_box_empty
            draw_box_sep
            draw_box_row " ${C_DGRAY}Enter value (or press Enter for default)  |  Esc back${C_RST}"
            draw_box_empty

            local input_val=""
            tui_read_line_boxed "$step_prompt" "$step_default" input_val
            local input_rc=$?
            draw_box_bottom
            if [[ $input_rc -ne 0 ]]; then
                return 1
            fi
            eval "$step_var=\$input_val"
            return 0
            ;;

        confirm)
            draw_box_sep
            draw_box_empty
            draw_box_row " ${C_GREEN}[Y]${C_RST} ${C_TEXT}Yes${C_RST}    ${C_RED}[N]${C_RST} ${C_TEXT}No${C_RST}    ${C_DGRAY}Default: ${step_default}${C_RST}"
            draw_box_empty
            draw_box_sep
            draw_box_row " ${C_DGRAY}y/n to answer  |  Esc back${C_RST}"
            draw_box_bottom

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
                    ESC)
                        return 1
                        ;;
                    q|Q)
                        return 2
                        ;;
                esac
            done
            ;;

        action)
            draw_box_sep
            draw_box_row " ${C_LGREEN}Installing... Please wait.${C_RST}"
            draw_box_bottom
            printf '\n'

            # Leave TUI mode temporarily to show install output
            printf '\033[?25h'  # show cursor

            # Call the installation function
            if type "$step_options" &>/dev/null; then
                "$step_options"
                local rc=$?
                if [[ $rc -ne 0 ]]; then
                    printf '\n  %b[-]%b Installation failed (exit code: %d)\n' "$C_RED" "$C_RST" "$rc"
                    press_any_key "Press any key to go back..."
                    printf '\033[?25l'
                    return 1
                fi
            else
                printf '  %b[-]%b Install function "%s" not found\n' "$C_RED" "$C_RST" "$step_options"
                press_any_key "Press any key to go back..."
                printf '\033[?25l'
                return 1
            fi

            printf '\033[?25l'  # hide cursor again
            printf '\n'
            press_any_key "Installation complete! Press any key..."
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

    define_wizard_steps "$proto"

    local step_count=${#WIZARD_STEPS[@]}
    (( step_count == 0 )) && return 1

    # Filter out conditional steps (e.g., domain input only if USE_DOMAIN=y)
    local current_step=0

    while (( current_step < step_count )); do
        local step_def="${WIZARD_STEPS[$current_step]}"
        local step_type="${step_def%%|*}"

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
                # Skip back past conditional steps too
                while (( current_step > 0 )) && _should_skip_step "$proto" "$current_step"; do
                    (( current_step-- ))
                done
                ;;
            2)  # Cancel
                return 1
                ;;
        esac
    done

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
    show_user_links "${FIRST_USERNAME:-user1}"
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

    # Directories to check for already-present files
    local search_dirs=(
        "/opt/dnscloak/services/$proto"
        "/tmp/dnscloak-services/$proto"
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

    # Pass 1: source from local paths
    for dir in "${search_dirs[@]}"; do
        if [[ $functions_sourced -eq 0 && -f "$dir/functions.sh" ]]; then
            source "$dir/functions.sh"
            functions_sourced=1
        fi
        if [[ $install_sourced -eq 0 && -f "$dir/install.sh" ]]; then
            # Source install.sh without running main()
            main() { :; }
            source "$dir/install.sh" 2>/dev/null
            unset -f main 2>/dev/null
            install_sourced=1
        fi
    done

    # If functions.sh was found locally, we're done
    if [[ $functions_sourced -eq 1 ]]; then
        return 0
    fi
    # install.sh alone is also acceptable (e.g. sos)
    if [[ $install_sourced -eq 1 ]]; then
        return 0
    fi

    # Pass 2: download from GitHub
    local dl_dir="/tmp/dnscloak-services/$proto"
    mkdir -p "$dl_dir"
    local base_url="${GITHUB_RAW:-https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main}/services/$proto"

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
