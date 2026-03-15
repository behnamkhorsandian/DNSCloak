#!/bin/bash
#===============================================================================
# DNSCloak TUI - Rendering Engine
# Core functions for building full-screen terminal UIs
# Modeled after 432.sh's frame.js / box.js / layout.js
#===============================================================================

# Source theme if not already loaded
if [[ -z "$C_RST" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/theme.sh"
fi

#-------------------------------------------------------------------------------
# Terminal Detection
#-------------------------------------------------------------------------------

_TERM_COLS=80
_TERM_ROWS=24
_TUI_FD=3
_TUI_ACTIVE=0
_TUI_OLD_STTY=""

# Layout constants
_MAX_FRAME_W=120         # Max frame width
_COMPACT_COLS=100        # Below this: single-column stacked layout
_CHROME_ROWS=6           # Banner + nav bar + borders overhead
_BANNER_HEIGHT=0         # Set by render_banner()

# Detect terminal size
tui_get_size() {
    if [[ -e /dev/tty ]]; then
        _TERM_COLS=$(tput cols </dev/tty 2>/dev/null || echo 80)
        _TERM_ROWS=$(tput lines </dev/tty 2>/dev/null || echo 24)
    else
        _TERM_COLS=${COLUMNS:-80}
        _TERM_ROWS=${LINES:-24}
    fi
    # Clamp to reasonable range
    (( _TERM_COLS < 60 )) && _TERM_COLS=60
    (( _TERM_COLS > 220 )) && _TERM_COLS=220
    (( _TERM_ROWS < 20 )) && _TERM_ROWS=20
    (( _TERM_ROWS > 80 )) && _TERM_ROWS=80
    return 0
}

# Compute frame width, compact flag, and horizontal margin
# Sets: _FRAME_W, _COMPACT, _MARGIN
tui_compute_layout() {
    local max="${1:-$_MAX_FRAME_W}"
    _FRAME_W=$(( _TERM_COLS - 2 ))
    (( _FRAME_W > max )) && _FRAME_W=$max
    # Snap to even for clean splits
    (( _FRAME_W % 2 == 1 )) && (( _FRAME_W-- )) || true
    _COMPACT=0
    (( _FRAME_W < _COMPACT_COLS )) && _COMPACT=1
    _MARGIN=$(( (_TERM_COLS - _FRAME_W) / 2 ))
    (( _MARGIN < 0 )) && _MARGIN=0
    return 0
}

# Print margin spaces (used to center-align all frame output)
_m() {
    (( _MARGIN > 0 )) && printf '%*s' "$_MARGIN" ""
    return 0
}

#-------------------------------------------------------------------------------
# TUI Lifecycle
#-------------------------------------------------------------------------------

# Initialize TUI mode — alternate screen, hide cursor, raw input
tui_init() {
    if [[ $_TUI_ACTIVE -eq 1 ]]; then
        return 0
    fi

    # Check /dev/tty is accessible
    if [[ ! -r /dev/tty ]]; then
        echo "tui_init: /dev/tty not readable" >&2
        return 1
    fi

    # Open /dev/tty for keyboard (stdin may be a pipe from curl)
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
    return 0
}

# Restore terminal state
tui_cleanup() {
    if [[ $_TUI_ACTIVE -eq 0 ]]; then
        return 0
    fi
    if [[ -n "$_TUI_OLD_STTY" ]]; then
        stty "$_TUI_OLD_STTY" <&3 2>/dev/null
    fi
    printf '\033[?25h'     # show cursor
    printf '\033[?1049l'   # leave alternate screen
    exec 3<&- 2>/dev/null
    _TUI_ACTIVE=0
}

#-------------------------------------------------------------------------------
# ANSI Utilities
#-------------------------------------------------------------------------------

# Strip ANSI escape codes from a string
strip_ansi() {
    printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# Visible length of a string (ignoring ANSI codes)
visible_len() {
    local stripped
    stripped=$(strip_ansi "$1")
    printf '%d' "${#stripped}"
}

# Repeat a character N times
repeat_char() {
    local ch="$1"
    local n="$2"
    (( n <= 0 )) && return
    printf "%${n}s" "" | tr ' ' "$ch"
}

# Repeat a multi-byte string N times (for Unicode box chars)
repeat_str() {
    local str="$1"
    local n="$2"
    local i
    for (( i = 0; i < n; i++ )); do
        printf '%s' "$str"
    done
}

# Pad a string with spaces to a target visible width
pad_right() {
    local text="$1"
    local target_width="$2"
    local vlen
    vlen=$(visible_len "$text")
    local pad=$(( target_width - vlen ))
    printf '%s' "$text"
    (( pad > 0 )) && printf '%*s' "$pad" ""
}

# Truncate a string (ANSI-aware) to max visible width
truncate_str() {
    local text="$1"
    local max_width="$2"
    local vlen
    vlen=$(visible_len "$text")
    if (( vlen <= max_width )); then
        printf '%s' "$text"
        return
    fi
    # Brute force: strip ANSI, truncate, lose colors at truncation point
    local stripped
    stripped=$(strip_ansi "$text")
    printf '%s' "${stripped:0:$((max_width - 1))}.${C_RST}"
}

# Move cursor to position
cursor_to() {
    local row="$1"
    local col="$2"
    printf '\033[%d;%dH' "$row" "$col"
}

# Clear screen and move to top
clear_screen() {
    printf '\033[2J\033[H'
}

#-------------------------------------------------------------------------------
# Box Drawing
#   ┌─ Title ──────────────┐
#   │ content              │
#   ├──────────────────────┤
#   │ more content         │
#   └──────────────────────┘
#-------------------------------------------------------------------------------

# Draw top border with optional title
# Usage: draw_box_top [width] [title] [border_color]
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

# Draw bottom border
draw_box_bottom() {
    local width="${1:-$_FRAME_W}"
    local bc="${2:-$C_DGRAY}"
    local inner=$(( width - 2 ))

    _m; printf '%b%s' "$bc" "$BOX_BL"
    repeat_str "$BOX_H" "$inner"
    printf '%s%b\n' "$BOX_BR" "$C_RST"
}

# Draw horizontal separator
draw_box_sep() {
    local width="${1:-$_FRAME_W}"
    local bc="${2:-$C_DGRAY}"
    local inner=$(( width - 2 ))

    _m; printf '%b%s' "$bc" "$BOX_ML"
    repeat_str "$BOX_H" "$inner"
    printf '%s%b\n' "$BOX_MR" "$C_RST"
}

# Draw a content row with left/right borders
# Usage: draw_box_row "text" [width] [border_color]
draw_box_row() {
    local text="$1"
    local width="${2:-$_FRAME_W}"
    local bc="${3:-$C_DGRAY}"
    local inner=$(( width - 2 ))

    local vlen
    vlen=$(visible_len "$text")
    local max_content=$(( inner - 1 ))  # 1 char leading space
    # Truncate if text exceeds available width
    if (( vlen > max_content )); then
        text=$(truncate_str "$text" "$max_content")
        vlen=$(visible_len "$text")
    fi
    local pad=$(( inner - vlen - 1 ))  # -1 for leading space
    (( pad < 0 )) && pad=0

    _m; printf '%b%s%b %b%*s%b%s%b\n' \
        "$bc" "$BOX_V" "$C_RST" \
        "$text" "$pad" "" \
        "$bc" "$BOX_V" "$C_RST"
}

# Draw an empty row
draw_box_empty() {
    local width="${1:-$_FRAME_W}"
    local bc="${2:-$C_DGRAY}"
    local inner=$(( width - 2 ))

    _m; printf '%b%s%b%*s%b%s%b\n' \
        "$bc" "$BOX_V" "$C_RST" \
        "$inner" "" \
        "$bc" "$BOX_V" "$C_RST"
}

#-------------------------------------------------------------------------------
# Split Layout (side-by-side columns)
#   ┌─────────────────────────┬──────────────┐
#   │  Left content (65%)     │ Right (35%)  │
#   └─────────────────────────┴──────────────┘
#-------------------------------------------------------------------------------

# Compute column widths
# Usage: compute_split total_width ratio
# Output: sets SPLIT_LEFT_W and SPLIT_RIGHT_W
compute_split() {
    local total="$1"
    local ratio="${2:-55}"
    local inner=$(( total - 2 ))
    SPLIT_LEFT_W=$(( inner * ratio / 100 ))
    SPLIT_RIGHT_W=$(( inner - SPLIT_LEFT_W - 1 ))  # -1 for middle border
}

# Draw split top border
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

# Draw a split content row (left | right)
draw_split_row() {
    local left_text="$1"
    local right_text="$2"
    local width="${3:-$_FRAME_W}"
    local bc="${4:-$C_DGRAY}"

    compute_split "$width"

    local left_vlen right_vlen left_pad right_pad
    left_vlen=$(visible_len "$left_text")
    right_vlen=$(visible_len "$right_text")

    # Truncate if text exceeds column width (with 1 char leading space)
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

    left_pad=$(( SPLIT_LEFT_W - left_vlen - 1 ))  # -1 for leading space
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

# Draw split empty row
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

# Draw split separator
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

# Draw split bottom
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

# Transition: split -> full-width (merge columns)
#   ├──────────────┴──────────────┤
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

# Transition: full-width -> split (introduce columns)
#   ├──────────────┬──────────────┤
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

#-------------------------------------------------------------------------------
# Navigation Bar
#   ── [0] Main  [1] Reality  [2] WireGuard  ... ── q quit  h help ──
#-------------------------------------------------------------------------------

# Draw navigation bar at the bottom
# Usage: draw_nav_bar current_index page_names_array width
draw_nav_bar() {
    local current="$1"
    shift
    local width="${!#}"  # last argument is width
    local pages=("${@:1:$#-1}")  # all but last

    local bc="$C_DGRAY"
    local inner=$(( width - 2 ))

    # Separator line
    printf '%b%s' "$bc" "$BOX_ML"
    repeat_str "$BOX_H" "$inner"
    printf '%s%b\n' "$BOX_MR" "$C_RST"

    # Page tabs
    local tabs=" "
    local i=0
    for page in "${pages[@]}"; do
        if [[ $i -eq $current ]]; then
            tabs+="${C_GREEN}${C_BOLD}[$i] ${page}${C_RST}  "
        else
            tabs+="${C_LGREEN}[$i]${C_RST} ${C_TEXT}${page}${C_RST}  "
        fi
        (( i++ ))
    done

    draw_box_row "$tabs" "$width"

    # Key hints
    local hints=" ${C_DGRAY}0-9${C_RST}${C_DIM} navigate${C_RST}  "
    hints+="${C_DGRAY}Enter${C_RST}${C_DIM} select${C_RST}  "
    hints+="${C_DGRAY}Esc${C_RST}${C_DIM} back${C_RST}  "
    hints+="${C_DGRAY}q${C_RST}${C_DIM} quit${C_RST}"

    draw_box_row "$hints" "$width"
}

#-------------------------------------------------------------------------------
# Input Handling
# Works when stdin is a pipe (curl | bash) by reading from /dev/tty via fd 3
#-------------------------------------------------------------------------------

# Read a single keypress — returns: UP, DOWN, LEFT, RIGHT, ENTER, ESC, TAB, or char
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

# Read a line of text input (shows cursor, allows typing)
# Usage: tui_read_line "prompt" "default" result_var
tui_read_line() {
    local prompt="$1"
    local default="$2"
    local result_var="$3"

    printf '\033[?25h'  # show cursor

    if [[ -n "$default" ]]; then
        printf '  %b[>]%b %s %b[%s]%b: ' \
            "$C_GREEN" "$C_RST" "$prompt" "$C_DGRAY" "$default" "$C_RST"
    else
        printf '  %b[>]%b %s: ' "$C_GREEN" "$C_RST" "$prompt"
    fi

    local input=""
    read -r input <&3

    printf '\033[?25l'  # hide cursor again

    if [[ -z "$input" && -n "$default" ]]; then
        input="$default"
    fi
    eval "$result_var=\$input"
}

# Yes/No confirmation prompt
# Usage: tui_confirm "Question?" [default: y|n]
# Returns 0 for yes, 1 for no
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

#-------------------------------------------------------------------------------
# Progress Display
#-------------------------------------------------------------------------------

# Show a spinner while a command runs
# Usage: tui_spinner "message" command args...
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

# Simple progress bar
# Usage: tui_progress current total [width]
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

#-------------------------------------------------------------------------------
# Banner Rendering
#-------------------------------------------------------------------------------

# Load and display an ASCII banner
# Usage: render_banner "banner_name" [color] [width]
render_banner() {
    local name="$1"
    local color="${2:-$C_GREEN}"
    local width="${3:-$_TERM_COLS}"

    local banner_text=""

    # Try local file first
    if [[ -n "${BANNER_DIR:-}" && -f "${BANNER_DIR}/${name}.txt" ]]; then
        banner_text=$(cat "${BANNER_DIR}/${name}.txt")
    elif [[ -f "/opt/dnscloak/banners/${name}.txt" ]]; then
        banner_text=$(cat "/opt/dnscloak/banners/${name}.txt")
    elif [[ -f "/tmp/dnscloak-banners/${name}.txt" ]]; then
        banner_text=$(cat "/tmp/dnscloak-banners/${name}.txt")
    elif [[ -f "$(dirname "${BASH_SOURCE[0]}")/../banners/${name}.txt" ]]; then
        banner_text=$(cat "$(dirname "${BASH_SOURCE[0]}")/../banners/${name}.txt")
    else
        # Download from GitHub
        mkdir -p /tmp/dnscloak-banners
        local url="${GITHUB_RAW:-https://raw.githubusercontent.com/behnamkhorsandian/DNSCloak/main}/banners/${name}.txt"
        if curl -sL "$url" -o "/tmp/dnscloak-banners/${name}.txt" 2>/dev/null; then
            banner_text=$(cat "/tmp/dnscloak-banners/${name}.txt")
        fi
    fi

    _BANNER_HEIGHT=0
    if [[ -n "$banner_text" ]]; then
        # On short terminals, skip large banners
        local banner_lines=0
        while IFS= read -r _; do
            (( banner_lines++ ))
        done <<< "$banner_text"

        if (( _TERM_ROWS < 30 && banner_lines > 5 )); then
            # Very short terminal: show just the version line
            _m; printf '%b  DNSCloak v%s%b\n' "$C_GREEN" "${DNSCLOAK_VERSION:-2.0.0}" "$C_RST"
            _BANNER_HEIGHT=1
        elif (( _TERM_ROWS < 40 && banner_lines > 10 )); then
            # Medium terminal: show last 6 lines of banner
            local skip=$(( banner_lines - 6 ))
            local count=0
            while IFS= read -r line; do
                (( count++ ))
                (( count <= skip )) && continue
                _m; printf '%b%s%b\n' "$color" "$line" "$C_RST"
                (( _BANNER_HEIGHT++ ))
            done <<< "$banner_text"
        else
            while IFS= read -r line; do
                _m; printf '%b%s%b\n' "$color" "$line" "$C_RST"
                (( _BANNER_HEIGHT++ ))
            done <<< "$banner_text"
        fi
    fi
}

#-------------------------------------------------------------------------------
# Word wrapping helper
#-------------------------------------------------------------------------------

# Wrap text to max width
# Usage: word_wrap "text" max_width
word_wrap() {
    local text="$1"
    local max_width="${2:-50}"

    # Use fold for simple word wrapping
    printf '%s' "$text" | fold -s -w "$max_width"
}

#-------------------------------------------------------------------------------
# Menu helper: renders a list with highlight and returns selected index
# Usage: tui_select_menu title selected_var item1 item2 ...
# Items format: "Label|description|badge"
# This is the main menu drawing loop used by pages
#-------------------------------------------------------------------------------

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

        # Banner
        render_banner "logo" "$C_GREEN"
        printf '\n'

        # Box
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

        # Vertical fill
        # Chrome: newline(1) + top(1) + empty(1) + empty(1) + sep(1) + hints(1) + bottom(1) = 7
        local chrome_rows=$(( _BANNER_HEIGHT + 1 + 6 + count ))
        local avail=$(( _TERM_ROWS - chrome_rows ))
        while (( avail-- > 0 )); do draw_box_empty; done

        draw_box_sep
        local hints=" ${C_DGRAY}Up/Down${C_RST}${C_DIM} navigate${C_RST}  "
        hints+="${C_DGRAY}Enter${C_RST}${C_DIM} select${C_RST}  "
        hints+="${C_DGRAY}q${C_RST}${C_DIM} quit${C_RST}"
        draw_box_row "$hints"
        draw_box_bottom

        # Read key
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

#-------------------------------------------------------------------------------
# Wait for keypress
#-------------------------------------------------------------------------------

press_any_key() {
    local msg="${1:-Press any key to continue...}"
    printf '\n'
    _m; printf '  %b%s%b' "$C_DGRAY" "$msg" "$C_RST"
    printf '\033[?25h'
    tui_read_key >/dev/null
    printf '\033[?25l'
}

#-------------------------------------------------------------------------------
# Output area for showing command output within the TUI
# Captures output and displays it in a scrollable box
#-------------------------------------------------------------------------------

# Run a command and display its output in a box
# Usage: tui_run_cmd "description" command args...
tui_run_cmd() {
    local desc="$1"
    shift

    printf '\n  %b%s %b%s%b\n' "$C_PURPLE" "$MARKER_STEP" "$C_BOLD" "$desc" "$C_RST"

    # Show output with a prefix
    "$@" 2>&1 | while IFS= read -r line; do
        printf '  %b|%b %s\n' "$C_DGRAY" "$C_RST" "$line"
    done
    local rc=${PIPESTATUS[0]}

    if [[ $rc -eq 0 ]]; then
        printf '  %b[+]%b %s\n' "$C_GREEN" "$C_RST" "$desc"
    else
        printf '  %b[-]%b %s (exit code: %d)\n' "$C_RED" "$C_RST" "$desc" "$rc"
    fi
    return $rc
}
