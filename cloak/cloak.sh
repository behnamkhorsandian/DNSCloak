#!/bin/bash
#===============================================================================
# Cloak — Offline Desktop Client for Vany
# The complete censorship bypass suite, available offline.
#
# Usage:
#   cloak                     Interactive TUI (inside tmux)
#   cloak tui                 Interactive TUI (inline, no tmux)
#   cloak box [create|open]   SafeBox encrypted dead-drop
#   cloak faucet              Network relay -> free VPN
#   cloak cfray               Find clean Cloudflare IPs
#   cloak findns              Find working DNS resolvers
#   cloak tracer              IP/ISP/ASN lookup
#   cloak speedtest           Bandwidth test
#   cloak install <proto>     Install protocol server (root)
#   cloak add <proto> <user>  Add user to protocol
#   cloak remove <proto> <u>  Remove user
#   cloak list [proto]        List users
#   cloak links <user> [p]    Show connection configs
#   cloak status              Container status
#   cloak mirrors             Fallback access methods
#   cloak update              Self-update from GitHub
#   cloak uninstall           Remove Cloak from system
#   cloak version             Print version
#   cloak help                Show this help
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# Resolve CLOAK_HOME
#-------------------------------------------------------------------------------

# If installed, CLOAK_HOME is where cloak lives
# If running from repo, resolve relative to this script
if [[ -n "${CLOAK_HOME:-}" ]]; then
    : # already set
elif [[ -d "$HOME/.cloak" ]]; then
    CLOAK_HOME="$HOME/.cloak"
else
    # Running from repo checkout
    CLOAK_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

export CLOAK_HOME
CLOAK_VERSION_FILE="$CLOAK_HOME/.version"
CLOAK_VERSION="dev"
[[ -f "$CLOAK_VERSION_FILE" ]] && CLOAK_VERSION="$(cat "$CLOAK_VERSION_FILE")"

#-------------------------------------------------------------------------------
# Colors (subset of theme.sh for standalone use)
#-------------------------------------------------------------------------------

G='\033[38;5;36m'     # green
LG='\033[38;5;115m'   # light green
D='\033[2m'           # dim
B='\033[1m'           # bold
R='\033[0m'           # reset
RED='\033[38;5;130m'  # red
Y='\033[38;5;186m'    # yellow
P='\033[38;5;141m'    # purple
C='\033[38;5;73m'     # cyan

#-------------------------------------------------------------------------------
# Helpers
#-------------------------------------------------------------------------------

die() { echo -e "  ${RED}$*${R}" >&2; exit 1; }

need_root() {
    [[ $EUID -eq 0 ]] || die "This command requires root. Try: sudo cloak $*"
}

resolve_tmux() {
    # Prefer bundled tmux, then system tmux
    if [[ -x "$CLOAK_HOME/bin/tmux" ]]; then
        echo "$CLOAK_HOME/bin/tmux"
    elif command -v tmux &>/dev/null; then
        command -v tmux
    else
        echo ""
    fi
}

resolve_script() {
    local name="$1"
    local candidates=(
        "$CLOAK_HOME/scripts/$name"
        "$CLOAK_HOME/../scripts/$name"
    )
    for c in "${candidates[@]}"; do
        if [[ -f "$c" ]]; then
            echo "$c"
            return 0
        fi
    done
    die "Script not found: $name"
}

resolve_tool() {
    local name="$1"
    local candidates=(
        "$CLOAK_HOME/scripts/tools/$name"
        "$CLOAK_HOME/../scripts/tools/$name"
    )
    for c in "${candidates[@]}"; do
        if [[ -f "$c" ]]; then
            echo "$c"
            return 0
        fi
    done
    die "Tool not found: $name"
}

resolve_protocol_script() {
    local name="$1"
    local candidates=(
        "$CLOAK_HOME/scripts/protocols/$name"
        "$CLOAK_HOME/../scripts/protocols/$name"
    )
    for c in "${candidates[@]}"; do
        if [[ -f "$c" ]]; then
            echo "$c"
            return 0
        fi
    done
    die "Protocol script not found: $name"
}

#-------------------------------------------------------------------------------
# Source libraries (if available)
#-------------------------------------------------------------------------------

source_lib() {
    local name="$1"
    local candidates=(
        "$CLOAK_HOME/lib/$name"
        "$CLOAK_HOME/../lib/$name"
    )
    for c in "${candidates[@]}"; do
        if [[ -f "$c" ]]; then
            # shellcheck source=/dev/null
            source "$c"
            return 0
        fi
    done
    return 1
}

#-------------------------------------------------------------------------------
# tmux session management
#-------------------------------------------------------------------------------

tmux_launch() {
    local tmux_bin
    tmux_bin="$(resolve_tmux)"

    if [[ -z "$tmux_bin" ]]; then
        # No tmux available — fall through to inline TUI
        cmd_tui
        return
    fi

    local conf="$CLOAK_HOME/etc/tmux.conf"
    local tmux_args=()
    [[ -f "$conf" ]] && tmux_args+=(-f "$conf")

    # If already inside a cloak tmux session, just run TUI
    if [[ "${TMUX:-}" == *"cloak"* ]]; then
        cmd_tui
        return
    fi

    # Attach to existing session or create new one
    if "$tmux_bin" "${tmux_args[@]}" has-session -t cloak 2>/dev/null; then
        exec "$tmux_bin" "${tmux_args[@]}" attach-session -t cloak
    else
        exec "$tmux_bin" "${tmux_args[@]}" new-session -s cloak -n tui \
            "$CLOAK_HOME/bin/cloak" tui
    fi
}

tmux_open_window() {
    local name="$1"
    shift
    local tmux_bin
    tmux_bin="$(resolve_tmux)"

    if [[ -z "$tmux_bin" || -z "${TMUX:-}" ]]; then
        # Not in tmux — run inline
        "$@"
        return
    fi

    # Open a new tmux window with the command
    "$tmux_bin" new-window -t cloak -n "$name" "$@"
}

#-------------------------------------------------------------------------------
# Update check (background, non-blocking)
#-------------------------------------------------------------------------------

check_update_bg() {
    # Only check once per day
    local marker="$CLOAK_HOME/.last-update-check"
    if [[ -f "$marker" ]]; then
        local last
        last=$(cat "$marker")
        local now
        now=$(date +%s)
        if (( now - last < 86400 )); then
            # Show pending update notice if cached
            if [[ -f "$CLOAK_HOME/.update-available" ]]; then
                local new_ver
                new_ver=$(cat "$CLOAK_HOME/.update-available")
                echo -e "  ${Y}Update available:${R} ${B}$new_ver${R} ${D}(current: $CLOAK_VERSION)${R}"
                echo -e "  ${D}Run:${R} ${LG}cloak update${R}"
                echo ""
            fi
            return
        fi
    fi

    # Background check
    (
        date +%s > "$marker"
        local resp
        resp=$(curl -s --max-time 5 \
            "https://api.github.com/repos/behnamkhorsandian/Vanysh/releases?per_page=5" 2>/dev/null) || return
        local latest
        latest=$(echo "$resp" | grep -o '"tag_name":"cloak-v[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/^cloak-v//')
        if [[ -n "$latest" && "$latest" != "$CLOAK_VERSION" ]]; then
            echo "$latest" > "$CLOAK_HOME/.update-available"
        else
            rm -f "$CLOAK_HOME/.update-available"
        fi
    ) &>/dev/null &
    disown 2>/dev/null || true

    # Show if already cached
    if [[ -f "$CLOAK_HOME/.update-available" ]]; then
        local new_ver
        new_ver=$(cat "$CLOAK_HOME/.update-available")
        echo -e "  ${Y}Update available:${R} ${B}$new_ver${R} ${D}(current: $CLOAK_VERSION)${R}"
        echo -e "  ${D}Run:${R} ${LG}cloak update${R}"
        echo ""
    fi
}

#-------------------------------------------------------------------------------
# Subcommands
#-------------------------------------------------------------------------------

cmd_tui() {
    local tui_main=""
    local candidates=(
        "$CLOAK_HOME/tui/main.sh"
        "$CLOAK_HOME/../tui/main.sh"
    )
    for c in "${candidates[@]}"; do
        if [[ -f "$c" ]]; then
            tui_main="$c"
            break
        fi
    done

    if [[ -z "$tui_main" ]]; then
        die "TUI not found. Try reinstalling: cloak update"
    fi

    # Set environment so TUI knows it's running under Cloak
    export CLOAK_MODE=1
    export CLOAK_VERSION
    export TUI_DIR="$(dirname "$tui_main")"
    export BANNER_DIR="$CLOAK_HOME/banners"
    [[ ! -d "$BANNER_DIR" ]] && BANNER_DIR="$CLOAK_HOME/../banners"
    export BANNER_DIR

    # Source libs for TUI
    source_lib "common.sh" || true
    source_lib "cloud.sh" || true
    source_lib "xray.sh" || true

    # shellcheck source=/dev/null
    source "$tui_main"
    vany_tui_main "$@"
}

cmd_box() {
    local script
    script="$(resolve_script "box.sh")"
    bash "$script" "$@"
}

cmd_faucet() {
    local script
    script="$(resolve_script "faucet.sh")"
    bash "$script" "$@"
}

cmd_mirrors() {
    local script
    script="$(resolve_script "mirrors.sh")"
    bash "$script" "$@"
}

cmd_tool() {
    local tool_name="$1"
    shift
    local script
    script="$(resolve_tool "${tool_name}.sh")"
    bash "$script" "$@"
}

cmd_install() {
    local proto="${1:-}"
    [[ -z "$proto" ]] && die "Usage: cloak install <protocol>"
    need_root "install $proto"

    # Bootstrap Docker if needed
    local bootstrap
    bootstrap="$(resolve_script "docker-bootstrap.sh" 2>/dev/null || true)"
    if [[ -n "$bootstrap" && -f "$bootstrap" ]]; then
        # shellcheck source=/dev/null
        source "$bootstrap"
    fi

    local script
    script="$(resolve_protocol_script "install-${proto}.sh")"
    # shellcheck source=/dev/null
    source "$script"

    # Call the install function (convention: install_<proto>)
    local fn="install_${proto//-/_}"
    if type "$fn" &>/dev/null; then
        "$fn"
    else
        die "Install function $fn not found in $script"
    fi
}

cmd_user_action() {
    local action="$1"
    shift
    source_lib "common.sh" || die "common.sh library not found"

    case "$action" in
        add)
            local proto="${1:-}"; local user="${2:-}"
            [[ -z "$proto" || -z "$user" ]] && die "Usage: cloak add <protocol> <user>"
            need_root "add $proto $user"
            user_add "$user" "$proto"
            ;;
        remove)
            local proto="${1:-}"; local user="${2:-}"
            [[ -z "$proto" || -z "$user" ]] && die "Usage: cloak remove <protocol> <user>"
            need_root "remove $proto $user"
            user_remove "$user" "$proto"
            ;;
        list)
            local proto="${1:-}"
            if [[ -n "$proto" ]]; then
                user_list "$proto"
            else
                user_list
            fi
            ;;
        links)
            local user="${1:-}"; local proto="${2:-}"
            [[ -z "$user" ]] && die "Usage: cloak links <user> [protocol]"
            user_links "$user" "$proto"
            ;;
    esac
}

cmd_status() {
    local script
    script="$(resolve_protocol_script "status-containers.sh")"
    bash "$script" "$@"
}

cmd_update() {
    local script
    script="$(resolve_script "self-update.sh")"
    bash "$script"
}

cmd_uninstall() {
    echo ""
    echo -e "  ${Y}${B}Uninstall Cloak?${R}"
    echo -e "  ${D}This will remove ~/.cloak and the 'cloak' command.${R}"
    echo -e "  ${D}Installed protocols and user data in /opt/vany/ are NOT affected.${R}"
    echo ""
    read -rp "  Continue? [y/N]: " confirm < /dev/tty
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Kill tmux session if exists
        local tmux_bin
        tmux_bin="$(resolve_tmux)"
        if [[ -n "$tmux_bin" ]]; then
            "$tmux_bin" kill-session -t cloak 2>/dev/null || true
        fi

        # Remove symlink
        for link in /usr/local/bin/cloak "$HOME/.local/bin/cloak" "$HOME/bin/cloak"; do
            if [[ -L "$link" ]]; then
                rm -f "$link" 2>/dev/null || sudo rm -f "$link" 2>/dev/null || true
            fi
        done

        # Remove install directory
        rm -rf "$HOME/.cloak"

        echo -e "  ${G}Cloak removed.${R}"
    else
        echo -e "  ${D}Cancelled.${R}"
    fi
}

cmd_version() {
    echo -e "  ${G}${B}Cloak${R} ${D}v${CLOAK_VERSION}${R}"
    echo -e "  ${D}Vany offline suite — https://vany.sh${R}"
}

cmd_help() {
    cat <<EOF

  $(echo -e "${G}${B}Cloak${R}") $(echo -e "${D}v${CLOAK_VERSION}${R}") — Vany offline suite

  $(echo -e "${B}USAGE${R}")
    cloak                       Interactive TUI (tmux session)
    cloak tui                   Interactive TUI (inline)

  $(echo -e "${B}TOOLS${R}")
    cloak box [create|open]     SafeBox encrypted dead-drop
    cloak faucet                Network relay -> free VPN
    cloak cfray                 Find clean Cloudflare IPs
    cloak findns                Find working DNS resolvers
    cloak tracer                IP/ISP/ASN lookup
    cloak speedtest             Bandwidth test
    cloak mirrors               Fallback access methods

  $(echo -e "${B}SERVER${R}") $(echo -e "${D}(requires root)${R}")
    cloak install <protocol>    Install protocol server
    cloak add <proto> <user>    Add user to protocol
    cloak remove <proto> <user> Remove user from protocol
    cloak list [protocol]       List users
    cloak links <user> [proto]  Show connection configs
    cloak status                Container status

  $(echo -e "${B}SYSTEM${R}")
    cloak update                Self-update from GitHub
    cloak uninstall             Remove Cloak
    cloak version               Print version

  $(echo -e "${B}PROTOCOLS${R}")
    reality    ws         hysteria   wireguard  vray
    http-obfs  mtp        ssh-tunnel dnstt      slipstream
    noizdns    conduit    tor-bridge snowflake

  $(echo -e "${D}https://vany.sh${R}")
EOF
}

#-------------------------------------------------------------------------------
# Main router
#-------------------------------------------------------------------------------

main() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    case "$cmd" in
        "")
            check_update_bg
            tmux_launch
            ;;
        tui)
            check_update_bg
            cmd_tui "$@"
            ;;
        box)        cmd_box "$@" ;;
        faucet)     cmd_faucet "$@" ;;
        mirrors)    cmd_mirrors "$@" ;;

        # Tools
        cfray)      cmd_tool "cfray" "$@" ;;
        findns)     cmd_tool "findns" "$@" ;;
        tracer)     cmd_tool "tracer" "$@" ;;
        speedtest)  cmd_tool "speedtest" "$@" ;;

        # Server management
        install)    cmd_install "$@" ;;
        add)        cmd_user_action "add" "$@" ;;
        remove)     cmd_user_action "remove" "$@" ;;
        list)       cmd_user_action "list" "$@" ;;
        links)      cmd_user_action "links" "$@" ;;
        status)     cmd_status "$@" ;;

        # System
        update)     cmd_update ;;
        uninstall)  cmd_uninstall ;;
        version|-v|--version)
                    cmd_version ;;
        help|-h|--help)
                    cmd_help ;;

        *)
            echo -e "  ${RED}Unknown command:${R} $cmd"
            echo -e "  ${D}Run 'cloak help' for usage.${R}"
            exit 1
            ;;
    esac
}

main "$@"
