#!/bin/bash
#===============================================================================
# DNSCloak TUI - Rendering Engine
# Unified frame model: status bar + sidebar + content + footer
# Inspired by 432.sh layout patterns, ported to bash
#===============================================================================

# Source theme if not already loaded
if [[ -z "$C_RST" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/theme.sh"
fi

#===============================================================================
# SECTION 1: Terminal Detection
#===============================================================================

_TERM_COLS=80
_TERM_ROWS=24
_TUI_FD=3
_TUI_ACTIVE=0
_TUI_OLD_STTY=""

tui_get_size() {
    if [[ -e /dev/tty ]]; then
        _TERM_COLS=$(tput cols </dev/tty 2>/dev/null || echo 80)
        _TERM_ROWS=$(tput lines </dev/tty 2>/dev/null || echo 24)
    else
        _TERM_COLS=${COLUMNS:-80}
        _TERM_ROWS=${LINES:-24}
    fi
    (( _TERM_COLS < 40 )) && _TERM_COLS=40
    (( _TERM_COLS > 300 )) && _TERM_COLS=300
    (( _TERM_ROWS < 15 )) && _TERM_ROWS=15
    (( _TERM_ROWS > 100 )) && _TERM_ROWS=100
    return 0
}

#===============================================================================
# SECTION 2: Layout Computation
#===============================================================================

# Layout globals
_FRAME_W=0            # Total frame width (= TERM_COLS)
_SIDEBAR_INNER_W=20   # Sidebar inner width (fixed)
_CONTENT_INNER_W=0    # Content inner width (computed)
_CONTENT_H=0          # Content area height (rows available)
_COMPACT=0            # 1 = no sidebar (narrow terminal)
_MARGIN=0             # Always 0 in new layout (edge-to-edge)

# Banner globals
FRAME_BANNER=""              # Banner name to display (e.g., "reality", "logo")
FRAME_BANNER_COLOR=""        # Color escape for banner text
_BANNER_LINES=()             # Cached banner lines (array)
_BANNER_H=0                  # Number of banner lines
_BANNER_CACHE_NAME=""        # Last loaded banner name (for caching)

# Base chrome rows: top(1) + status(1) + split_top(1) + split_bottom(1) + footer(1) + bottom(1) = 6
_CHROME_ROWS=6

#-------------------------------------------------------------------------------
# Load banner file into _BANNER_LINES array
# Caches by name — only reloads when FRAME_BANNER changes
#-------------------------------------------------------------------------------
_load_frame_banner() {
    # No banner requested
    if [[ -z "$FRAME_BANNER" ]]; then
        _BANNER_LINES=()
        _BANNER_H=0
        _BANNER_CACHE_NAME=""
        return
    fi

    # Already cached
    [[ "$FRAME_BANNER" == "$_BANNER_CACHE_NAME" ]] && return

    _BANNER_LINES=()
    _BANNER_H=0
    _BANNER_CACHE_NAME="$FRAME_BANNER"

    local banner_text=""
    local script_dir
    script_dir="$(dirname "${BASH_SOURCE[0]}")"

    if [[ -n "${BANNER_DIR:-}" && -f "${BANNER_DIR}/${FRAME_BANNER}.txt" ]]; then
        banner_text=$(cat "${BANNER_DIR}/${FRAME_BANNER}.txt")
    elif [[ -f "/opt/dnscloak/banners/${FRAME_BANNER}.txt" ]]; then
        banner_text=$(cat "/opt/dnscloak/banners/${FRAME_BANNER}.txt")
    elif [[ -f "/tmp/dnscloak-banners/${FRAME_BANNER}.txt" ]]; then
        banner_text=$(cat "/tmp/dnscloak-banners/${FRAME_BANNER}.txt")
    elif [[ -f "${script_dir}/../banners/${FRAME_BANNER}.txt" ]]; then
        banner_text=$(cat "${script_dir}/../banners/${FRAME_BANNER}.txt")
    else
        mkdir -p /tmp/dnscloak-banners
        local url="${GITHUB_RAW:-https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main}/banners/${FRAME_BANNER}.txt"
        if curl -sL "$url" -o "/tmp/dnscloak-banners/${FRAME_BANNER}.txt" 2>/dev/null; then
            banner_text=$(cat "/tmp/dnscloak-banners/${FRAME_BANNER}.txt")
        fi
    fi

    [[ -z "$banner_text" ]] && return

    while IFS= read -r line; do
        _BANNER_LINES+=("$line")
        (( _BANNER_H++ ))
    done <<< "$banner_text"
}

tui_compute_layout() {
    _FRAME_W=$_TERM_COLS

    if (( _TERM_COLS < 80 )); then
        _COMPACT=1
        _SIDEBAR_INNER_W=0
        _CONTENT_INNER_W=$(( _FRAME_W - 2 ))
    else
        _COMPACT=0
        _SIDEBAR_INNER_W=20
        # left border(1) + sidebar(20) + mid border(1) + content(?) + right border(1) = FRAME_W
        _CONTENT_INNER_W=$(( _FRAME_W - _SIDEBAR_INNER_W - 3 ))
    fi

    # Load banner and compute chrome
    _load_frame_banner
    if (( _BANNER_H > 0 )); then
        # base(6) + separator(1) + banner_lines
        _CHROME_ROWS=$(( 7 + _BANNER_H ))
    else
        _CHROME_ROWS=6
    fi

    _CONTENT_H=$(( _TERM_ROWS - _CHROME_ROWS ))
    (( _CONTENT_H < 5 )) && _CONTENT_H=5

    # _MARGIN is 0 — edge-to-edge rendering
    _MARGIN=0
    return 0
}

# Kept for backward compat (wizard, etc.)
_m() {
    return 0
}

#===============================================================================
# SECTION 3: ANSI Utilities
#===============================================================================

strip_ansi() {
    printf '%b' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

visible_len() {
    local stripped
    stripped=$(strip_ansi "$1")
    printf '%d' "${#stripped}"
}

repeat_char() {
    local ch="$1"
    local n="$2"
    (( n <= 0 )) && return
    printf "%${n}s" "" | tr ' ' "$ch"
}

repeat_str() {
    local str="$1"
    local n="$2"
    local i
    for (( i = 0; i < n; i++ )); do
        printf '%s' "$str"
    done
}

pad_right() {
    local text="$1"
    local target_width="$2"
    local vlen
    vlen=$(visible_len "$text")
    local pad=$(( target_width - vlen ))
    printf '%b' "$text"
    (( pad > 0 )) && printf '%*s' "$pad" ""
}

# Truncate string to max visible width, preserving reset at end
truncate_str() {
    local text="$1"
    local max_width="$2"
    local vlen
    vlen=$(visible_len "$text")
    if (( vlen <= max_width )); then
        printf '%b' "$text"
        return
    fi
    # Walk through characters, tracking visible count
    local stripped
    stripped=$(strip_ansi "$text")
    printf '%b' "${stripped:0:$((max_width - 2))}..${C_RST}"
}

cursor_to() {
    local row="$1"
    local col="$2"
    printf '\033[%d;%dH' "$row" "$col"
}

clear_screen() {
    printf '\033[2J\033[H'
}

word_wrap() {
    local text="$1"
    local max_width="${2:-50}"
    printf '%s' "$text" | fold -s -w "$max_width"
}

#===============================================================================
# SECTION 4: TUI Lifecycle
#===============================================================================

tui_init() {
    if [[ $_TUI_ACTIVE -eq 1 ]]; then
        return 0
    fi

    if [[ ! -r /dev/tty ]]; then
        echo "tui_init: /dev/tty not readable" >&2
        return 1
    fi

    if ! exec 3</dev/tty; then
        echo "tui_init: failed to open /dev/tty on fd 3" >&2
        return 1
    fi

    _TUI_OLD_STTY=$(stty -g <&3 2>/dev/null)
    printf '\033[?1049h'   # alternate screen buffer
    printf '\033[?25l'     # hide cursor
    printf '\033[2J'       # clear screen
    _TUI_ACTIVE=1
    tui_get_size

    # Handle terminal resize
    trap '_tui_on_resize' WINCH

    return 0
}

_tui_on_resize() {
    tui_get_size
    tui_compute_layout
    # Pages will re-render on next loop iteration
}

tui_cleanup() {
    if [[ $_TUI_ACTIVE -eq 0 ]]; then
        return 0
    fi
    trap '' WINCH
    if [[ -n "$_TUI_OLD_STTY" ]]; then
        stty "$_TUI_OLD_STTY" <&3 2>/dev/null
    fi
    printf '\033[?25h'     # show cursor
    printf '\033[?1049l'   # leave alternate screen
    exec 3<&- 2>/dev/null
    _TUI_ACTIVE=0
}

#===============================================================================
# SECTION 5: Unified Frame Renderer
#
# Layout:
#   ┌──────────────────────────────────────────────────────────────────────┐
#   │  DNSCLOAK  *  1.2.3.4  |  3 services  |  q quit              16:58 │
#   ├──────────────────┬───────────────────────────────────────────────────┤
#   │  Protocols       │  Content area...                                 │
#   │ > REALITY    *   │                                                  │
#   │   WireGuard  -   │                                                  │
#   │   ...            │                                                  │
#   │  ─────────────── │                                                  │
#   │  [s] Status      │                                                  │
#   │  [u] Users       │                                                  │
#   ├──────────────────┴───────────────────────────────────────────────────┤
#   │  ^/v navigate  Enter select  s status  u users  q quit              │
#   └──────────────────────────────────────────────────────────────────────┘
#===============================================================================

# Sidebar state (set by pages before calling tui_render_frame)
_SIDEBAR_SEL=0             # Which sidebar item is highlighted (0-based)
_SIDEBAR_PAGE=""           # "protocols", "status", "users" — which section is active
_SIDEBAR_DIM=0             # 1 = dim sidebar (during wizard)

# Frame content arrays (set by pages before calling tui_render_frame)
FRAME_CONTENT=()           # Content lines for right panel
FRAME_FOOTER=""            # Footer hint text

# Cached sidebar lines (built internally by _build_sidebar)
_SIDEBAR_LINES=()

#-------------------------------------------------------------------------------
# Build sidebar lines
#-------------------------------------------------------------------------------

_build_sidebar() {
    _SIDEBAR_LINES=()

    local dim_prefix=""
    [[ $_SIDEBAR_DIM -eq 1 ]] && dim_prefix="$C_DIM"

    # Section header
    _SIDEBAR_LINES+=("${dim_prefix}${C_ORANGE} Protocols${C_RST}")
    _SIDEBAR_LINES+=("")

    # Protocol list
    local i=0
    for proto in "${PROTOCOL_IDS[@]}"; do
        local name="${PROTOCOL_SHORT[$proto]}"
        local dot="$DOT_NONE"

        # Check live service status if functions available
        if type service_installed &>/dev/null; then
            if service_installed "$proto" 2>/dev/null; then
                if type service_running &>/dev/null && service_running "$proto" 2>/dev/null; then
                    dot="$DOT_ON"
                else
                    dot="$DOT_OFF"
                fi
            fi
        else
            # Fallback: use tag from theme
            case "${PROTOCOL_TAGS[$proto]}" in
                recommended) dot="$DOT_REC" ;;
                emergency)   dot="$DOT_ERR" ;;
            esac
        fi

        local prefix="  "
        local ncolor="${dim_prefix}${C_TEXT}"
        if [[ $_SIDEBAR_PAGE == "protocols" && $i -eq $_SIDEBAR_SEL ]]; then
            prefix="${C_GREEN}>${C_RST} "
            ncolor="${C_GREEN}${C_BOLD}"
        fi
        _SIDEBAR_LINES+=("${prefix}${ncolor}${name}${C_RST} ${dot}")
        (( i++ ))
    done

    # Blank line + separator
    _SIDEBAR_LINES+=("")
    local sep_w=$(( _SIDEBAR_INNER_W - 2 ))
    (( sep_w < 4 )) && sep_w=4
    _SIDEBAR_LINES+=(" ${dim_prefix}${C_DGRAY}$(repeat_str "$BOX_H" "$sep_w")${C_RST}")

    # Navigation items
    local s_prefix="  "
    local s_color="${dim_prefix}${C_TEXT}"
    if [[ $_SIDEBAR_PAGE == "status" ]]; then
        s_prefix="${C_GREEN}>${C_RST} "
        s_color="${C_GREEN}${C_BOLD}"
    fi
    _SIDEBAR_LINES+=("${s_prefix}${C_LGREEN}s${C_RST} ${s_color}Status${C_RST}")

    local u_prefix="  "
    local u_color="${dim_prefix}${C_TEXT}"
    if [[ $_SIDEBAR_PAGE == "users" ]]; then
        u_prefix="${C_GREEN}>${C_RST} "
        u_color="${C_GREEN}${C_BOLD}"
    fi
    _SIDEBAR_LINES+=("${u_prefix}${C_LGREEN}u${C_RST} ${u_color}Users${C_RST}")
}

#-------------------------------------------------------------------------------
# Build status bar text
#-------------------------------------------------------------------------------

_build_status_text() {
    local ip="?"
    local svc_count=0
    local user_count=0
    local clock=""

    # Read from users.json if available
    if [[ -f "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" ]] && type jq &>/dev/null; then
        ip=$(jq -r '.server.ip // "?"' "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
        user_count=$(jq -r '.users // {} | keys | length' "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
    fi

    # Count running services
    if type service_installed &>/dev/null && type service_running &>/dev/null; then
        for proto in "${PROTOCOL_IDS[@]}"; do
            service_running "$proto" 2>/dev/null && (( svc_count++ ))
        done
    fi

    # Clock
    clock=$(date +%H:%M 2>/dev/null || echo "--:--")

    # Overall health dot
    local health_dot="$DOT_NONE"
    if (( svc_count > 0 )); then
        health_dot="$DOT_ON"
    fi

    printf ' %bDNSCLOAK%b  %b  %b%s%b  %b|%b  %b%d%b svcs  %b|%b  %b%d%b users  %b|%b  %b%s%b' \
        "$C_GREEN" "$C_RST" \
        "$health_dot" \
        "$C_TEXT" "$ip" "$C_RST" \
        "$C_DGRAY" "$C_RST" \
        "$C_TEXT" "$svc_count" "$C_RST" \
        "$C_DGRAY" "$C_RST" \
        "$C_TEXT" "$user_count" "$C_RST" \
        "$C_DGRAY" "$C_RST" \
        "$C_LGRAY" "$clock" "$C_RST"
}

#-------------------------------------------------------------------------------
# Print helpers for frame rows
#-------------------------------------------------------------------------------

# Print a full-width row: │ text <padding> │
_print_full_row() {
    local text="$1"
    local inner=$(( _FRAME_W - 2 ))
    local vlen
    vlen=$(visible_len "$text")
    local pad=$(( inner - vlen ))
    (( pad < 0 )) && pad=0
    printf '%b%s%b%b%*s%b%s%b\n' \
        "$C_DGRAY" "$BOX_V" "$C_RST" \
        "$text" "$pad" "" \
        "$C_DGRAY" "$BOX_V" "$C_RST"
}

# Print a split row: │ sidebar <pad> │ content <pad> │
_print_split_row() {
    local sidebar_text="$1"
    local content_text="$2"
    local bc="$C_DGRAY"

    local sv cl sp cp
    sv=$(visible_len "$sidebar_text")
    cl=$(visible_len "$content_text")
    sp=$(( _SIDEBAR_INNER_W - sv ))
    cp=$(( _CONTENT_INNER_W - cl ))
    (( sp < 0 )) && sp=0
    (( cp < 0 )) && cp=0

    printf '%b%s%b%b%*s%b%s%b%b%*s%b%s%b\n' \
        "$bc" "$BOX_V" "$C_RST" \
        "$sidebar_text" "$sp" "" \
        "$bc" "$BOX_V" "$C_RST" \
        "$content_text" "$cp" "" \
        "$bc" "$BOX_V" "$C_RST"
}

#-------------------------------------------------------------------------------
# Main frame renderer
# Call this after setting FRAME_CONTENT[], FRAME_FOOTER, sidebar state globals
#-------------------------------------------------------------------------------

tui_render_frame() {
    local bc="$C_DGRAY"

    _build_sidebar

    # Pre-compute horizontal rules
    local h_full h_side h_cont
    h_full=$(repeat_str "$BOX_H" $(( _FRAME_W - 2 )))
    if (( ! _COMPACT )); then
        h_side=$(repeat_str "$BOX_H" "$_SIDEBAR_INNER_W")
        h_cont=$(repeat_str "$BOX_H" "$_CONTENT_INNER_W")
    fi

    # Build status bar text
    local status_text
    status_text=$(_build_status_text)

    # --- Render all at once via subshell to reduce flicker ---
    {
        printf '\033[H'  # cursor home (overwrite, no clear)

        # Row 1: Top border
        printf '%b%s%s%s%b\n' "$bc" "$BOX_TL" "$h_full" "$BOX_TR" "$C_RST"

        # Row 2: Status bar
        _print_full_row "$status_text"

        # Banner rows (if active)
        if (( _BANNER_H > 0 )); then
            # Separator between status bar and banner
            printf '%b%s%s%s%b\n' "$bc" "$BOX_ML" "$h_full" "$BOX_MR" "$C_RST"

            local bcolor="${FRAME_BANNER_COLOR:-$C_GREEN}"
            local banner_inner=$(( _FRAME_W - 2 ))
            local bi=0
            while (( bi < _BANNER_H )); do
                local bline="${_BANNER_LINES[$bi]:-}"
                local bvlen=${#bline}
                local bpad_l=$(( (banner_inner - bvlen) / 2 ))
                local bpad_r=$(( banner_inner - bvlen - bpad_l ))
                (( bpad_l < 0 )) && bpad_l=0
                (( bpad_r < 0 )) && bpad_r=0
                printf '%b%s%b%*s%b%s%b%*s%b%s%b\n' \
                    "$bc" "$BOX_V" "$C_RST" \
                    "$bpad_l" "" \
                    "$bcolor" "$bline" "$C_RST" \
                    "$bpad_r" "" \
                    "$bc" "$BOX_V" "$C_RST"
                (( bi++ ))
            done
        fi

        if (( _COMPACT )); then
            # Row 3: Separator
            printf '%b%s%s%s%b\n' "$bc" "$BOX_ML" "$h_full" "$BOX_MR" "$C_RST"

            # Content rows (full-width, no sidebar)
            local r=0
            while (( r < _CONTENT_H )); do
                _print_full_row " ${FRAME_CONTENT[$r]:-}"
                (( r++ ))
            done

            # Footer separator
            printf '%b%s%s%s%b\n' "$bc" "$BOX_ML" "$h_full" "$BOX_MR" "$C_RST"
        else
            # Row 3: Split top (├──────┬──────┤)
            printf '%b%s%s%s%s%s%b\n' "$bc" "$BOX_ML" "$h_side" "$BOX_TJ" "$h_cont" "$BOX_MR" "$C_RST"

            # Content rows (sidebar | content)
            local r=0
            while (( r < _CONTENT_H )); do
                _print_split_row " ${_SIDEBAR_LINES[$r]:-}" " ${FRAME_CONTENT[$r]:-}"
                (( r++ ))
            done

            # Footer separator (├──────┴──────┤)
            printf '%b%s%s%s%s%s%b\n' "$bc" "$BOX_ML" "$h_side" "$BOX_BJ" "$h_cont" "$BOX_MR" "$C_RST"
        fi

        # Footer row
        _print_full_row " $FRAME_FOOTER"

        # Bottom border
        printf '%b%s%s%s%b\n' "$bc" "$BOX_BL" "$h_full" "$BOX_BR" "$C_RST"
    }
}

#===============================================================================
# SECTION 6: Legacy Box Drawing (kept for wizard & dialogs)
#===============================================================================

draw_box_top() {
    local width="${1:-$_FRAME_W}"
    local title="$2"
    local bc="${3:-$C_DGRAY}"
    local inner=$(( width - 2 ))

    _m; printf '%b%s' "$bc" "$BOX_TL"
    if [[ -n "$title" ]]; then
        local tlen=${#title}
        printf '%s' "$BOX_H"
        printf '%b %s %b' "$C_ORANGE" "$title" "$bc"
        local used=$(( tlen + 3 ))
        repeat_str "$BOX_H" $(( inner - used ))
    else
        repeat_str "$BOX_H" "$inner"
    fi
    printf '%s%b\n' "$BOX_TR" "$C_RST"
}

draw_box_bottom() {
    local width="${1:-$_FRAME_W}"
    local bc="${2:-$C_DGRAY}"
    local inner=$(( width - 2 ))

    _m; printf '%b%s' "$bc" "$BOX_BL"
    repeat_str "$BOX_H" "$inner"
    printf '%s%b\n' "$BOX_BR" "$C_RST"
}

draw_box_sep() {
    local width="${1:-$_FRAME_W}"
    local bc="${2:-$C_DGRAY}"
    local inner=$(( width - 2 ))

    _m; printf '%b%s' "$bc" "$BOX_ML"
    repeat_str "$BOX_H" "$inner"
    printf '%s%b\n' "$BOX_MR" "$C_RST"
}

draw_box_row() {
    local text="$1"
    local width="${2:-$_FRAME_W}"
    local bc="${3:-$C_DGRAY}"
    local inner=$(( width - 2 ))

    local vlen
    vlen=$(visible_len "$text")
    local max_content=$(( inner - 1 ))
    if (( vlen > max_content )); then
        text=$(truncate_str "$text" "$max_content")
        vlen=$(visible_len "$text")
    fi
    local pad=$(( inner - vlen - 1 ))
    (( pad < 0 )) && pad=0

    _m; printf '%b%s%b %b%*s%b%s%b\n' \
        "$bc" "$BOX_V" "$C_RST" \
        "$text" "$pad" "" \
        "$bc" "$BOX_V" "$C_RST"
}

draw_box_empty() {
    local width="${1:-$_FRAME_W}"
    local bc="${2:-$C_DGRAY}"
    local inner=$(( width - 2 ))

    _m; printf '%b%s%b%*s%b%s%b\n' \
        "$bc" "$BOX_V" "$C_RST" \
        "$inner" "" \
        "$bc" "$BOX_V" "$C_RST"
}

# Legacy split functions (kept for wizard backward compat)
compute_split() {
    local total="$1"
    local ratio="${2:-55}"
    local inner=$(( total - 2 ))
    SPLIT_LEFT_W=$(( inner * ratio / 100 ))
    SPLIT_RIGHT_W=$(( inner - SPLIT_LEFT_W - 1 ))
}

draw_split_top() {
    local width="${1:-$_FRAME_W}"
    local left_title="$2"
    local right_title="$3"
    local bc="${4:-$C_DGRAY}"

    compute_split "$width"

    _m; printf '%b%s' "$bc" "$BOX_TL"
    if [[ -n "$left_title" ]]; then
        printf '%s' "$BOX_H"
        printf '%b %s %b' "$C_ORANGE" "$left_title" "$bc"
        local tlen=${#left_title}
        local used=$(( tlen + 3 ))
        repeat_str "$BOX_H" $(( SPLIT_LEFT_W - used ))
    else
        repeat_str "$BOX_H" "$SPLIT_LEFT_W"
    fi
    printf '%s' "$BOX_TJ"
    if [[ -n "$right_title" ]]; then
        printf '%s' "$BOX_H"
        printf '%b %s %b' "$C_ORANGE" "$right_title" "$bc"
        local tlen=${#right_title}
        local used=$(( tlen + 3 ))
        repeat_str "$BOX_H" $(( SPLIT_RIGHT_W - used ))
    else
        repeat_str "$BOX_H" "$SPLIT_RIGHT_W"
    fi
    printf '%s%b\n' "$BOX_TR" "$C_RST"
}

draw_split_row() {
    local left_text="$1"
    local right_text="$2"
    local width="${3:-$_FRAME_W}"
    local bc="${4:-$C_DGRAY}"

    compute_split "$width"

    local left_vlen right_vlen left_pad right_pad
    left_vlen=$(visible_len "$left_text")
    right_vlen=$(visible_len "$right_text")

    local left_max=$(( SPLIT_LEFT_W - 1 ))
    local right_max=$(( SPLIT_RIGHT_W - 1 ))
    if (( left_vlen > left_max )); then
        left_text=$(truncate_str "$left_text" "$left_max")
        left_vlen=$(visible_len "$left_text")
    fi
    if (( right_vlen > right_max )); then
        right_text=$(truncate_str "$right_text" "$right_max")
        right_vlen=$(visible_len "$right_text")
    fi

    left_pad=$(( SPLIT_LEFT_W - left_vlen - 1 ))
    right_pad=$(( SPLIT_RIGHT_W - right_vlen - 1 ))
    (( left_pad < 0 )) && left_pad=0
    (( right_pad < 0 )) && right_pad=0

    _m; printf '%b%s%b %b%*s%b%s%b %b%*s%b%s%b\n' \
        "$bc" "$BOX_V" "$C_RST" \
        "$left_text" "$left_pad" "" \
        "$bc" "$BOX_V" "$C_RST" \
        "$right_text" "$right_pad" "" \
        "$bc" "$BOX_V" "$C_RST"
}

draw_split_empty() {
    local width="${1:-$_FRAME_W}"
    local bc="${2:-$C_DGRAY}"
    compute_split "$width"

    _m; printf '%b%s%b%*s%b%s%b%*s%b%s%b\n' \
        "$bc" "$BOX_V" "$C_RST" \
        "$SPLIT_LEFT_W" "" \
        "$bc" "$BOX_V" "$C_RST" \
        "$SPLIT_RIGHT_W" "" \
        "$bc" "$BOX_V" "$C_RST"
}

draw_split_sep() {
    local width="${1:-$_FRAME_W}"
    local bc="${2:-$C_DGRAY}"
    compute_split "$width"

    _m; printf '%b%s' "$bc" "$BOX_ML"
    repeat_str "$BOX_H" "$SPLIT_LEFT_W"
    printf '%s' "$BOX_CJ"
    repeat_str "$BOX_H" "$SPLIT_RIGHT_W"
    printf '%s%b\n' "$BOX_MR" "$C_RST"
}

draw_split_bottom() {
    local width="${1:-$_FRAME_W}"
    local bc="${2:-$C_DGRAY}"
    compute_split "$width"

    _m; printf '%b%s' "$bc" "$BOX_BL"
    repeat_str "$BOX_H" "$SPLIT_LEFT_W"
    printf '%s' "$BOX_BJ"
    repeat_str "$BOX_H" "$SPLIT_RIGHT_W"
    printf '%s%b\n' "$BOX_BR" "$C_RST"
}

draw_split_to_box_sep() {
    local width="${1:-$_FRAME_W}"
    local bc="${2:-$C_DGRAY}"
    compute_split "$width"

    _m; printf '%b%s' "$bc" "$BOX_ML"
    repeat_str "$BOX_H" "$SPLIT_LEFT_W"
    printf '%s' "$BOX_BJ"
    repeat_str "$BOX_H" "$SPLIT_RIGHT_W"
    printf '%s%b\n' "$BOX_MR" "$C_RST"
}

draw_box_to_split_sep() {
    local width="${1:-$_FRAME_W}"
    local bc="${2:-$C_DGRAY}"
    compute_split "$width"

    _m; printf '%b%s' "$bc" "$BOX_ML"
    repeat_str "$BOX_H" "$SPLIT_LEFT_W"
    printf '%s' "$BOX_TJ"
    repeat_str "$BOX_H" "$SPLIT_RIGHT_W"
    printf '%s%b\n' "$BOX_MR" "$C_RST"
}

#===============================================================================
# SECTION 7: Input Handling
#===============================================================================

tui_read_key() {
    local c1 c2 c3

    stty -echo -icanon min 1 time 0 <&3 2>/dev/null
    IFS= read -rsn1 c1 <&3
    stty echo icanon <&3 2>/dev/null

    if [[ "$c1" == $'\033' ]]; then
        stty -echo -icanon min 1 time 0 <&3 2>/dev/null
        IFS= read -rsn1 -t 0.1 c2 <&3 2>/dev/null || true
        if [[ "$c2" == "[" ]]; then
            IFS= read -rsn1 -t 0.1 c3 <&3 2>/dev/null || true
            stty echo icanon <&3 2>/dev/null
            case "$c3" in
                A) echo "UP";    return ;;
                B) echo "DOWN";  return ;;
                C) echo "RIGHT"; return ;;
                D) echo "LEFT";  return ;;
            esac
            echo "ESC"; return
        fi
        stty echo icanon <&3 2>/dev/null
        echo "ESC"; return
    fi

    if [[ "$c1" == "" ]]; then
        echo "ENTER"; return
    fi
    if [[ "$c1" == $'\t' ]]; then
        echo "TAB"; return
    fi
    echo "$c1"
}

tui_read_line() {
    local prompt="$1"
    local default="$2"
    local result_var="$3"

    printf '\033[?25h'

    stty echo icanon <&3 2>/dev/null
    while read -rsn1 -t 0.05 _ <&3 2>/dev/null; do :; done

    if [[ -n "$default" ]]; then
        printf '  %b[>]%b %s %b[%s]%b: ' \
            "$C_GREEN" "$C_RST" "$prompt" "$C_DGRAY" "$default" "$C_RST"
    else
        printf '  %b[>]%b %s: ' "$C_GREEN" "$C_RST" "$prompt"
    fi

    local input=""
    read -r input <&3

    printf '\033[?25l'

    if [[ -z "$input" && -n "$default" ]]; then
        input="$default"
    fi
    eval "$result_var=\$input"
}

tui_read_line_boxed() {
    local prompt="$1"
    local default="$2"
    local result_var="$3"
    local width="${4:-$_FRAME_W}"
    local bc="${5:-$C_DGRAY}"

    printf '\033[?25h'

    stty echo icanon <&3 2>/dev/null
    while read -rsn1 -t 0.05 _ <&3 2>/dev/null; do :; done

    local prompt_text=""
    if [[ -n "$default" ]]; then
        prompt_text=" ${C_GREEN}[>]${C_RST} ${prompt} ${C_DGRAY}[${default}]${C_RST}: "
    else
        prompt_text=" ${C_GREEN}[>]${C_RST} ${prompt}: "
    fi

    _m; printf '%b%s%b%b' "$bc" "$BOX_V" "$C_RST" "$prompt_text"

    local input=""
    stty -echo -icanon min 1 time 0 <&3 2>/dev/null
    while true; do
        local ch=""
        IFS= read -rsn1 ch <&3

        if [[ "$ch" == $'\033' ]]; then
            local c2=""
            IFS= read -rsn1 -t 0.1 c2 <&3 2>/dev/null || true
            if [[ -z "$c2" ]]; then
                stty echo icanon <&3 2>/dev/null
                printf '\r'
                draw_box_empty "$width" "$bc"
                printf '\033[?25l'
                return 1
            fi
            if [[ "$c2" == "[" ]]; then
                IFS= read -rsn1 -t 0.1 _ <&3 2>/dev/null || true
            fi
            continue
        fi

        if [[ "$ch" == "" ]]; then
            break
        fi

        if [[ "$ch" == $'\177' || "$ch" == $'\b' ]]; then
            if [[ -n "$input" ]]; then
                input="${input%?}"
                printf '\b \b'
            fi
            continue
        fi

        if [[ "$ch" =~ ^[[:print:]]$ ]]; then
            input+="$ch"
            printf '%s' "$ch"
        fi
    done
    stty echo icanon <&3 2>/dev/null

    local display_val="${input:-$default}"
    printf '\r'
    draw_box_row " ${C_GREEN}[>]${C_RST} ${prompt}: ${C_TEXT}${display_val}${C_RST}" "$width" "$bc"
    printf '\033[?25l'

    if [[ -z "$input" && -n "$default" ]]; then
        input="$default"
    fi
    eval "$result_var=\$input"
    return 0
}

tui_confirm() {
    local prompt="$1"
    local default="${2:-n}"

    printf '\033[?25h'

    if [[ "$default" == "y" ]]; then
        printf '  %b[?]%b %s [Y/n]: ' "$C_YELLOW" "$C_RST" "$prompt"
    else
        printf '  %b[?]%b %s [y/N]: ' "$C_YELLOW" "$C_RST" "$prompt"
    fi

    local answer=""
    read -r answer <&3

    printf '\033[?25l'

    if [[ -z "$answer" ]]; then
        answer="$default"
    fi
    [[ "$answer" =~ ^[Yy]$ ]]
}

#===============================================================================
# SECTION 8: Progress Display
#===============================================================================

tui_spinner() {
    local msg="$1"
    shift
    local spin_chars='|/-\'
    local i=0

    "$@" &
    local pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        local ch="${spin_chars:$((i % 4)):1}"
        printf '\r  %b[%s]%b %s' "$C_GREEN" "$ch" "$C_RST" "$msg"
        sleep 0.1
        (( i++ ))
    done

    wait "$pid"
    local rc=$?

    if [[ $rc -eq 0 ]]; then
        printf '\r  %b[+]%b %s\n' "$C_GREEN" "$C_RST" "$msg"
    else
        printf '\r  %b[-]%b %s\n' "$C_RED" "$C_RST" "$msg"
    fi
    return $rc
}

tui_progress() {
    local current="$1"
    local total="$2"
    local bar_width="${3:-30}"
    local pct=0

    (( total > 0 )) && pct=$(( current * 100 / total ))
    local filled=$(( bar_width * current / total ))
    local empty=$(( bar_width - filled ))

    printf '%b[%b' "$C_DGRAY" "$C_RST"
    printf '%b' "$C_GREEN"
    repeat_str "$BOX_H" "$filled"
    printf '%b' "$C_DGRAY"
    repeat_str "$BOX_H" "$empty"
    printf '%b] %b%d%%%b' "$C_DGRAY" "$C_TEXT" "$pct" "$C_RST"
}

# Run a command with output displayed within frame content area
# Usage: tui_run_cmd_framed "description" command args...
# Captures output and displays last N lines in FRAME_CONTENT
tui_run_cmd_framed() {
    local desc="$1"
    shift
    local logfile="/tmp/dnscloak-install-$$.log"
    local max_lines=$(( _CONTENT_H - 6 ))
    (( max_lines < 5 )) && max_lines=5

    "$@" > "$logfile" 2>&1 &
    local pid=$!

    local spin_chars='|/-\'
    local spin_i=0

    while kill -0 "$pid" 2>/dev/null; do
        # Build content with log tail
        FRAME_CONTENT=()
        FRAME_CONTENT+=("${C_ORANGE}${C_BOLD}${desc}${C_RST}")
        FRAME_CONTENT+=("")

        local ch="${spin_chars:$((spin_i % 4)):1}"
        FRAME_CONTENT+=("${C_GREEN}[${ch}]${C_RST} ${C_TEXT}Installing...${C_RST}")
        FRAME_CONTENT+=("")

        # Show last N lines of log
        if [[ -f "$logfile" ]]; then
            while IFS= read -r line; do
                FRAME_CONTENT+=("${C_LGRAY}${line}${C_RST}")
            done < <(tail -n "$max_lines" "$logfile" 2>/dev/null)
        fi

        tui_render_frame
        sleep 0.3
        (( spin_i++ ))
    done

    wait "$pid"
    local rc=$?
    rm -f "$logfile"
    return $rc
}

#===============================================================================
# SECTION 9: Banner Rendering (legacy, for splash screen)
#===============================================================================

_BANNER_HEIGHT=0

render_banner() {
    local name="$1"
    local color="${2:-$C_GREEN}"
    local width="${3:-$_TERM_COLS}"

    local banner_text=""

    if [[ -n "${BANNER_DIR:-}" && -f "${BANNER_DIR}/${name}.txt" ]]; then
        banner_text=$(cat "${BANNER_DIR}/${name}.txt")
    elif [[ -f "/opt/dnscloak/banners/${name}.txt" ]]; then
        banner_text=$(cat "/opt/dnscloak/banners/${name}.txt")
    elif [[ -f "/tmp/dnscloak-banners/${name}.txt" ]]; then
        banner_text=$(cat "/tmp/dnscloak-banners/${name}.txt")
    elif [[ -f "$(dirname "${BASH_SOURCE[0]}")/../banners/${name}.txt" ]]; then
        banner_text=$(cat "$(dirname "${BASH_SOURCE[0]}")/../banners/${name}.txt")
    else
        mkdir -p /tmp/dnscloak-banners
        local url="${GITHUB_RAW:-https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main}/banners/${name}.txt"
        if curl -sL "$url" -o "/tmp/dnscloak-banners/${name}.txt" 2>/dev/null; then
            banner_text=$(cat "/tmp/dnscloak-banners/${name}.txt")
        fi
    fi

    _BANNER_HEIGHT=0
    if [[ -n "$banner_text" ]]; then
        while IFS= read -r line; do
            printf '%b%s%b\n' "$color" "$line" "$C_RST"
            (( _BANNER_HEIGHT++ ))
        done <<< "$banner_text"
    fi
}

#===============================================================================
# SECTION 10: Misc Helpers
#===============================================================================

press_any_key() {
    local msg="${1:-Press any key to continue...}"
    printf '  %b%s%b' "$C_DGRAY" "$msg" "$C_RST"
    tui_read_key >/dev/null
}

tui_select_menu() {
    local title="$1"
    local result_var="$2"
    shift 2
    local items=("$@")
    local count=${#items[@]}
    local selected=0

    (( count == 0 )) && return 1

    while true; do
        tui_get_size
        tui_compute_layout
        clear_screen

        draw_box_top "" "$title"
        draw_box_empty

        local i=0
        for item in "${items[@]}"; do
            local label="${item%%|*}"
            local rest="${item#*|}"
            local badge=""
            if [[ "$rest" == *"|"* ]]; then
                badge="${rest##*|}"
            fi

            local prefix="   "
            local lcolor="$C_TEXT"
            if [[ $i -eq $selected ]]; then
                prefix=" ${C_GREEN}>${C_RST}"
                lcolor="${C_GREEN}${C_BOLD}"
            fi

            local display="${prefix} ${lcolor}${label}${C_RST}"

            case "$badge" in
                running)       display+="  $badge_running" ;;
                stopped)       display+="  $badge_stopped" ;;
                installed)     display+="  $badge_installed" ;;
                recommended)   display+="  $badge_recommended" ;;
                needs_domain)  display+="  $badge_needs_domain" ;;
                emergency)     display+="  $badge_emergency" ;;
                relay)         display+="  $badge_relay" ;;
            esac

            draw_box_row "$display"
            (( i++ ))
        done

        local chrome_rows=$(( 5 + count ))
        local avail=$(( _TERM_ROWS - chrome_rows ))
        while (( avail-- > 0 )); do draw_box_empty; done

        draw_box_sep
        local hints=" ${C_DGRAY}Up/Down${C_RST}${C_DIM} navigate${C_RST}  "
        hints+="${C_DGRAY}Enter${C_RST}${C_DIM} select${C_RST}  "
        hints+="${C_DGRAY}q${C_RST}${C_DIM} quit${C_RST}"
        draw_box_row "$hints"
        draw_box_bottom

        local key
        key=$(tui_read_key)

        case "$key" in
            UP)
                (( selected-- ))
                (( selected < 0 )) && selected=$(( count - 1 ))
                ;;
            DOWN)
                (( selected++ ))
                (( selected >= count )) && selected=0
                ;;
            ENTER)
                eval "$result_var=$selected"
                return 0
                ;;
            q|Q)
                eval "$result_var=-1"
                return 0
                ;;
            [0-9])
                if (( key < count )); then
                    eval "$result_var=$key"
                    return 0
                fi
                ;;
        esac
    done
}
