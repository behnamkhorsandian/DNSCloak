#!/bin/bash
#===============================================================================
# DNSCloak TUI - User Management Page
# Table with per-protocol columns, sorting, scrollable in-frame links
#===============================================================================

TUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TUI_DIR/engine.sh"

#-------------------------------------------------------------------------------
# User list page — unified frame layout with table and hotkeys
# Returns: 0 on back, 1 on quit
#-------------------------------------------------------------------------------

page_users() {
    local selected=0
    local sort_mode="name"   # "name" or "date"
    _SIDEBAR_PAGE="users"
    _SIDEBAR_SEL=0
    _SIDEBAR_DIM=0
    FRAME_BANNER="logo"
    FRAME_BANNER_COLOR="$C_PURPLE"

    while true; do
        tui_get_size
        tui_compute_layout

        # Get user list from JSON
        local -a users=()
        local -a user_dates=()
        local -A user_proto_map=()

        if [[ -f "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" ]] && type jq &>/dev/null; then
            local raw_users
            if [[ "$sort_mode" == "date" ]]; then
                raw_users=$(jq -r '.users // {} | to_entries | sort_by(.value.created) | reverse | .[].key' \
                    "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
            else
                raw_users=$(jq -r '.users // {} | keys[]' \
                    "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
            fi

            while IFS= read -r uname; do
                [[ -z "$uname" ]] && continue
                users+=("$uname")
                local created
                created=$(jq -r ".users[\"$uname\"].created // \"\"" \
                    "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
                # Format date: show just date portion
                if [[ -n "$created" && "$created" != "null" ]]; then
                    user_dates+=("${created%%T*}")
                else
                    user_dates+=("-")
                fi
                # Track which protocols this user has
                local protos
                protos=$(jq -r ".users[\"$uname\"].protocols // {} | keys[]" \
                    "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
                user_proto_map["$uname"]="$protos"
            done <<< "$raw_users"
        fi

        local user_count=${#users[@]}

        # Clamp selection
        if (( selected >= user_count )); then
            selected=$(( user_count > 0 ? user_count - 1 : 0 ))
        fi

        # Detect installed protocols for column headers
        local -a installed_protos=()
        for proto in "${PROTOCOL_IDS[@]}"; do
            if type service_installed &>/dev/null && service_installed "$proto" 2>/dev/null; then
                installed_protos+=("$proto")
            fi
        done

        # Build content
        FRAME_CONTENT=()
        tui_scroll_reset

        FRAME_CONTENT+=("${C_ORANGE}${C_BOLD}User Management${C_RST}  ${C_DGRAY}(${user_count} user$( (( user_count != 1 )) && echo "s"))${C_RST}")
        FRAME_CONTENT+=("")

        if [[ $user_count -eq 0 ]]; then
            FRAME_CONTENT+=("${C_LGRAY}No users configured yet.${C_RST}")
            FRAME_CONTENT+=("${C_LGRAY}Install a protocol first, then add users.${C_RST}")
        else
            # Build table with per-protocol columns
            local -a tbl_headers=("Username" "Created")
            for p in "${installed_protos[@]}"; do
                tbl_headers+=("${PROTOCOL_SHORT[$p]:-$p}")
            done

            local -a tbl_rows=()
            local i=0
            for uname in "${users[@]}"; do
                local row_data="${uname}|${user_dates[$i]}"
                local user_protos="${user_proto_map[$uname]}"
                for p in "${installed_protos[@]}"; do
                    if echo "$user_protos" | grep -q "^${p}$"; then
                        row_data+="|${C_GREEN}${DOT_ON}${C_RST}"
                    else
                        row_data+="|${C_DGRAY}${DOT_NONE}${C_RST}"
                    fi
                done

                # Highlight selected row
                if [[ $i -eq $selected ]]; then
                    row_data="${C_GREEN}${C_BOLD}${uname}${C_RST}|${user_dates[$i]}"
                    for p in "${installed_protos[@]}"; do
                        if echo "$user_protos" | grep -q "^${p}$"; then
                            row_data+="|${C_GREEN}${DOT_ON}${C_RST}"
                        else
                            row_data+="|${C_DGRAY}${DOT_NONE}${C_RST}"
                        fi
                    done
                fi

                tbl_rows+=("$row_data")
                (( i++ ))
            done

            local sort_label
            if [[ "$sort_mode" == "date" ]]; then
                sort_label="Users (sorted by date)"
            else
                sort_label="Users (sorted by name)"
            fi
            tui_render_table "$sort_label" tbl_headers tbl_rows
        fi

        # Footer with hotkeys
        FRAME_FOOTER="${C_DGRAY}^/v${C_RST}${C_DIM} select${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}a${C_RST}${C_DIM} add${C_RST}  "
        if [[ $user_count -gt 0 ]]; then
            FRAME_FOOTER+="${C_DGRAY}r${C_RST}${C_DIM} remove${C_RST}  "
            FRAME_FOOTER+="${C_DGRAY}l${C_RST}${C_DIM} links${C_RST}  "
        fi
        FRAME_FOOTER+="${C_DGRAY}t${C_RST}${C_DIM} sort${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}Esc${C_RST}${C_DIM} back${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}q${C_RST}${C_DIM} quit${C_RST}"

        tui_render_frame

        # Key handling
        local key
        key=$(tui_read_key)

        case "$key" in
            UP)
                if [[ $user_count -gt 0 ]]; then
                    (( selected-- ))
                    (( selected < 0 )) && selected=$(( user_count - 1 ))
                fi
                ;;
            DOWN)
                if [[ $user_count -gt 0 ]]; then
                    (( selected++ ))
                    (( selected >= user_count )) && selected=0
                fi
                ;;
            a|A)
                _add_user_page
                selected=0
                ;;
            r|R)
                if [[ $user_count -gt 0 ]]; then
                    _remove_user_confirm "${users[$selected]}"
                    selected=0
                fi
                ;;
            l|L|ENTER)
                if [[ $user_count -gt 0 ]]; then
                    _show_user_links_inframe "${users[$selected]}"
                    local lrc=$?
                    [[ $lrc -eq 1 ]] && return 1
                fi
                ;;
            t|T)
                # Toggle sort mode
                if [[ "$sort_mode" == "name" ]]; then
                    sort_mode="date"
                else
                    sort_mode="name"
                fi
                selected=0
                ;;
            ESC|BACKSPACE)
                return 0
                ;;
            q|Q)
                return 1
                ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# Add user sub-page
#-------------------------------------------------------------------------------

_add_user_page() {
    local proto_filter="${1:-}"

    tui_get_size
    tui_compute_layout

    clear_screen
    printf '\n'
    draw_box_top "" "Add User"
    draw_box_empty
    draw_box_row " ${C_TEXT}Enter a username for the new user.${C_RST}"
    draw_box_row " ${C_LGRAY}They will be added to all installed protocols.${C_RST}"
    draw_box_empty
    draw_box_sep
    draw_box_row " ${C_DGRAY}Enter username  |  Esc back${C_RST}"
    draw_box_empty

    local username=""
    tui_read_line_boxed "Username" "" username
    local input_rc=$?
    draw_box_bottom
    [[ $input_rc -ne 0 || -z "$username" ]] && return

    printf '\n'

    local added=0
    for proto in "${PROTOCOL_IDS[@]}"; do
        if [[ -n "$proto_filter" && "$proto" != "$proto_filter" ]]; then
            continue
        fi

        if type service_installed &>/dev/null && service_installed "$proto"; then
            local add_fn="add_${proto}_user"
            [[ "$proto" == "wg" ]] && add_fn="add_wg_user"
            if type "$add_fn" &>/dev/null; then
                printf '  %b[+]%b Adding to %s... ' "$C_GREEN" "$C_RST" "${PROTOCOL_NAMES[$proto]}"
                "$add_fn" "$username" 2>/dev/null && {
                    printf '%b done%b\n' "$C_GREEN" "$C_RST"
                    (( added++ ))
                } || printf '%b failed%b\n' "$C_RED" "$C_RST"
            fi
        fi
    done

    if [[ $added -eq 0 ]]; then
        printf '  %b[!]%b No installed protocols found. Install a protocol first.\n' "$C_YELLOW" "$C_RST"
    else
        printf '\n  %b[+]%b User "%s" added to %d protocol(s)\n' "$C_GREEN" "$C_RST" "$username" "$added"
    fi

    press_any_key
}

#-------------------------------------------------------------------------------
# Remove user with confirmation (pre-filled from selection)
#-------------------------------------------------------------------------------

_remove_user_confirm() {
    local username="$1"
    [[ -z "$username" ]] && return

    printf '\033[?25h'
    if tui_confirm "Remove user '$username' from all protocols?"; then
        printf '\033[?25l'
        for proto in "${PROTOCOL_IDS[@]}"; do
            local remove_fn="remove_${proto}_user"
            [[ "$proto" == "wg" ]] && remove_fn="remove_wg_user"
            if type "$remove_fn" &>/dev/null; then
                "$remove_fn" "$username" 2>/dev/null && \
                    printf '  %b[+]%b Removed from %s\n' "$C_GREEN" "$C_RST" "${PROTOCOL_NAMES[$proto]}"
            fi
        done
        printf '\n  %b[+]%b User "%s" removed\n' "$C_GREEN" "$C_RST" "$username"
        press_any_key
    else
        printf '\033[?25l'
    fi
}

#-------------------------------------------------------------------------------
# Remove user sub-page (manual username entry, kept for navigation router)
#-------------------------------------------------------------------------------

_remove_user_page() {
    local proto_filter="${1:-}"

    tui_get_size
    tui_compute_layout

    clear_screen
    printf '\n'
    draw_box_top "" "Remove User"
    draw_box_empty
    draw_box_row " ${C_TEXT}Enter the username to remove.${C_RST}"
    draw_box_row " ${C_RED}This will remove them from ALL protocols.${C_RST}"
    draw_box_empty
    draw_box_sep
    draw_box_row " ${C_DGRAY}Enter username  |  Esc back${C_RST}"
    draw_box_empty

    local username=""
    tui_read_line_boxed "Username" "" username
    local input_rc=$?
    draw_box_bottom
    [[ $input_rc -ne 0 || -z "$username" ]] && return

    printf '\n'
    _remove_user_confirm "$username"
}

#-------------------------------------------------------------------------------
# Show user links — protocol picker then single-protocol view
# Returns: 0 on back (BACKSPACE), 1 on quit (q)
#-------------------------------------------------------------------------------

_show_user_links_inframe() {
    local username="$1"
    local filter_proto="${2:-}"

    # If a specific protocol was given, show its links directly
    if [[ -n "$filter_proto" ]]; then
        _show_single_proto_links "$username" "$filter_proto"
        return $?
    fi

    # Get user's protocols
    local -a user_protos=()
    if [[ -f "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" ]] && type jq &>/dev/null; then
        while IFS= read -r p; do
            [[ -n "$p" ]] && user_protos+=("$p")
        done < <(jq -r ".users[\"$username\"].protocols // {} | keys[]" \
            "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
    fi

    if [[ ${#user_protos[@]} -eq 0 ]]; then
        # No protocols — show message and wait
        FRAME_CONTENT=()
        FRAME_CONTENT+=("${C_ORANGE}${C_BOLD}Links for: ${username}${C_RST}")
        FRAME_CONTENT+=("")
        FRAME_CONTENT+=("${C_LGRAY}No protocols configured for this user.${C_RST}")
        FRAME_FOOTER="${C_DGRAY}Esc${C_RST}${C_DIM} back${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}q${C_RST}${C_DIM} quit${C_RST}"
        tui_render_frame
        local key
        key=$(tui_read_key)
        case "$key" in
            q|Q) return 1 ;;
            *)   return 0 ;;
        esac
    fi

    if [[ ${#user_protos[@]} -eq 1 ]]; then
        # Only one protocol — show it directly
        _show_single_proto_links "$username" "${user_protos[0]}"
        return $?
    fi

    # Multiple protocols — show picker
    local proto_sel=0
    while true; do
        tui_get_size
        tui_compute_layout

        FRAME_CONTENT=()
        FRAME_CONTENT+=("${C_ORANGE}${C_BOLD}Links for: ${username}${C_RST}")
        FRAME_CONTENT+=("${C_LGRAY}Select a protocol to view connection links${C_RST}")
        FRAME_CONTENT+=("")

        local sep_w=$(( _CONTENT_INNER_W - 4 ))
        (( sep_w > 40 )) && sep_w=40
        (( sep_w < 10 )) && sep_w=10
        FRAME_CONTENT+=("${C_DGRAY}$(repeat_str "$BOX_H" "$sep_w")${C_RST}")
        FRAME_CONTENT+=("")

        local i=0
        for p in "${user_protos[@]}"; do
            local prefix="   "
            local pcolor="$C_TEXT"
            if [[ $i -eq $proto_sel ]]; then
                prefix=" ${C_GREEN}>${C_RST}"
                pcolor="${C_GREEN}${C_BOLD}"
            fi
            FRAME_CONTENT+=("${prefix} ${pcolor}${PROTOCOL_NAMES[$p]:-$p}${C_RST}")
            (( i++ ))
        done

        FRAME_FOOTER="${C_DGRAY}^/v${C_RST}${C_DIM} select${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}Enter${C_RST}${C_DIM} view${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}Esc${C_RST}${C_DIM} back${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}q${C_RST}${C_DIM} quit${C_RST}"

        tui_render_frame

        local key
        key=$(tui_read_key)

        case "$key" in
            UP)
                (( proto_sel-- ))
                (( proto_sel < 0 )) && proto_sel=$(( ${#user_protos[@]} - 1 ))
                ;;
            DOWN)
                (( proto_sel++ ))
                (( proto_sel >= ${#user_protos[@]} )) && proto_sel=0
                ;;
            ENTER)
                _show_single_proto_links "$username" "${user_protos[$proto_sel]}"
                local lrc=$?
                [[ $lrc -eq 1 ]] && return 1
                ;;
            ESC|BACKSPACE)
                return 0
                ;;
            q|Q)
                return 1
                ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# Show links for a single protocol (scrollable)
# Returns: 0 on back, 1 on quit
#-------------------------------------------------------------------------------

_show_single_proto_links() {
    local username="$1"
    local proto="$2"
    tui_scroll_reset

    while true; do
        tui_get_size
        tui_compute_layout

        FRAME_CONTENT=()
        FRAME_CONTENT+=("${C_ORANGE}${C_BOLD}${PROTOCOL_NAMES[$proto]:-$proto} — ${username}${C_RST}")
        FRAME_CONTENT+=("")

        local show_fn="show_${proto}_links"
        if ! type "$show_fn" &>/dev/null; then
            _source_protocol "$proto" 2>/dev/null
        fi

        local sep_w=$(( _CONTENT_INNER_W - 4 ))
        (( sep_w < 10 )) && sep_w=10
        (( sep_w > 50 )) && sep_w=50
        FRAME_CONTENT+=("${C_DGRAY}$(repeat_str "$BOX_H" "$sep_w")${C_RST}")

        if type "$show_fn" &>/dev/null; then
            while IFS= read -r line; do
                FRAME_CONTENT+=(" ${C_TEXT}${line}${C_RST}")
            done < <("$show_fn" "$username" 2>/dev/null)
        else
            local config
            config=$(jq ".users[\"$username\"].protocols[\"$proto\"]" \
                "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
            while IFS= read -r line; do
                FRAME_CONTENT+=(" ${C_TEXT}${line}${C_RST}")
            done <<< "$config"
        fi

        FRAME_FOOTER="${C_DGRAY}Esc${C_RST}${C_DIM} back${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}Esc${C_RST}${C_DIM} back${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}q${C_RST}${C_DIM} quit${C_RST}"

        tui_render_frame

        local key
        key=$(tui_read_key)

        case "$key" in
            ESC|BACKSPACE|ENTER)
                return 0
                ;;
            q|Q)
                return 1
                ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# Legacy wrapper for navigation router compatibility
#-------------------------------------------------------------------------------

_show_user_links_page() {
    _show_user_links_inframe "$@"
}
