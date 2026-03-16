#!/bin/bash
#===============================================================================
# DNSCloak TUI - User Management Page
# Uses unified frame with persistent sidebar
#===============================================================================

TUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TUI_DIR/engine.sh"

#-------------------------------------------------------------------------------
# User list page — unified frame layout
# Returns: 0 on back, 1 on quit
#-------------------------------------------------------------------------------

page_users() {
    local selected=0
    _SIDEBAR_PAGE="users"
    _SIDEBAR_SEL=0
    _SIDEBAR_DIM=0
    FRAME_BANNER="logo"
    FRAME_BANNER_COLOR="$C_PURPLE"

    while true; do
        tui_get_size
        tui_compute_layout

        # Get user list
        local users=()
        local user_protos=()
        if [[ -f "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" ]] && type jq &>/dev/null; then
            local users_json
            users_json=$(jq -r '.users // {} | keys[]' "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
            while IFS= read -r uname; do
                [[ -z "$uname" ]] && continue
                users+=("$uname")
                local protos
                protos=$(jq -r ".users[\"$uname\"].protocols // {} | keys | join(\", \")" \
                    "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
                user_protos+=("$protos")
            done <<< "$users_json"
        fi

        local user_count=${#users[@]}

        # Build content
        FRAME_CONTENT=()
        FRAME_CONTENT+=("${C_ORANGE}${C_BOLD}User Management${C_RST}")
        FRAME_CONTENT+=("")

        if [[ $user_count -eq 0 ]]; then
            FRAME_CONTENT+=("${C_LGRAY}No users configured yet.${C_RST}")
            FRAME_CONTENT+=("${C_LGRAY}Install a protocol first, then add users.${C_RST}")
        else
            # Table header
            FRAME_CONTENT+=("$(printf '%b%-22s%b %b%s%b' "$C_ORANGE" "Username" "$C_RST" "$C_ORANGE" "Protocols" "$C_RST")")
            FRAME_CONTENT+=("${C_DGRAY}$(repeat_str "$BOX_H" 36)${C_RST}")

            local i=0
            for uname in "${users[@]}"; do
                local prefix="  "
                local ucolor="$C_TEXT"
                if [[ $i -eq $selected && $selected -lt $user_count ]]; then
                    prefix="${C_GREEN}>${C_RST} "
                    ucolor="${C_GREEN}${C_BOLD}"
                fi
                FRAME_CONTENT+=("$(printf '%s%b%-20s%b %b%s%b' "$prefix" "$ucolor" "$uname" "$C_RST" "$C_LGRAY" "${user_protos[$i]}" "$C_RST")")
                (( i++ ))
            done
        fi

        FRAME_CONTENT+=("")

        # Separator
        local sep_w=30
        (( sep_w > _CONTENT_INNER_W - 4 )) && sep_w=$(( _CONTENT_INNER_W - 4 ))
        FRAME_CONTENT+=("${C_DGRAY}$(repeat_str "$BOX_H" "$sep_w")${C_RST}")
        FRAME_CONTENT+=("")

        # Action menu
        local actions=("Add User" "Remove User" "Show User Links" "Back")
        local action_ids=("add" "remove" "links" "back")
        local action_offset=$user_count
        local action_count=${#actions[@]}
        local total_items=$(( user_count + action_count ))

        local a=0
        for action in "${actions[@]}"; do
            local idx=$(( action_offset + a ))
            local prefix="   "
            local acolor="$C_TEXT"
            if [[ $selected -eq $idx ]]; then
                prefix=" ${C_GREEN}>${C_RST}"
                acolor="${C_GREEN}${C_BOLD}"
            fi
            FRAME_CONTENT+=("${prefix} ${acolor}${action}${C_RST}")
            (( a++ ))
        done

        # Footer
        FRAME_FOOTER="${C_DGRAY}^/v${C_RST}${C_DIM} navigate${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}Enter${C_RST}${C_DIM} select${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}Esc${C_RST}${C_DIM} back${C_RST}  "
        FRAME_FOOTER+="${C_DGRAY}q${C_RST}${C_DIM} quit${C_RST}"

        tui_render_frame

        # Key handling
        local key
        key=$(tui_read_key)

        case "$key" in
            UP)
                (( selected-- ))
                (( selected < 0 )) && selected=$(( total_items - 1 ))
                ;;
            DOWN)
                (( selected++ ))
                (( selected >= total_items )) && selected=0
                ;;
            ENTER)
                if (( selected < user_count )); then
                    _show_user_links_page "${users[$selected]}"
                else
                    local action_idx=$(( selected - action_offset ))
                    case "${action_ids[$action_idx]}" in
                        add)    _add_user_page; selected=0 ;;
                        remove) _remove_user_page; selected=0 ;;
                        links)
                            if [[ $user_count -gt 0 ]]; then
                                _show_user_links_page "${users[0]}"
                            fi
                            ;;
                        back) return 0 ;;
                    esac
                fi
                ;;
            ESC)
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
        # Filter to specific protocol if given
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
# Remove user sub-page
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
    printf '\033[?25h'
    if tui_confirm "Remove user '$username' from all protocols?"; then
        printf '\033[?25l'
        for proto in "${PROTOCOL_IDS[@]}"; do
            if [[ -n "$proto_filter" && "$proto" != "$proto_filter" ]]; then
                continue
            fi
            local remove_fn="remove_${proto}_user"
            [[ "$proto" == "wg" ]] && remove_fn="remove_wg_user"
            if type "$remove_fn" &>/dev/null; then
                "$remove_fn" "$username" 2>/dev/null && \
                    printf '  %b[+]%b Removed from %s\n' "$C_GREEN" "$C_RST" "${PROTOCOL_NAMES[$proto]}"
            fi
        done
        printf '\n  %b[+]%b User "%s" removed\n' "$C_GREEN" "$C_RST" "$username"
    else
        printf '\033[?25l'
    fi

    press_any_key
}

#-------------------------------------------------------------------------------
# Show user links sub-page
#-------------------------------------------------------------------------------

_show_user_links_page() {
    local username="$1"
    local filter_proto="${2:-}"

    tui_get_size
    tui_compute_layout

    clear_screen
    printf '\n'
    local title="Links for: $username"
    [[ -n "$filter_proto" ]] && title="${PROTOCOL_NAMES[$filter_proto]:-$filter_proto} Links for: $username"
    draw_box_top "" "$title"
    draw_box_empty

    if [[ -f "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" ]] && type jq &>/dev/null; then
        local protos
        if [[ -n "$filter_proto" ]]; then
            if jq -e ".users[\"$username\"].protocols[\"$filter_proto\"]" \
                    "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" &>/dev/null; then
                protos="$filter_proto"
            else
                protos=""
            fi
        else
            protos=$(jq -r ".users[\"$username\"].protocols // {} | keys[]" \
                "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
        fi

        if [[ -z "$protos" ]]; then
            draw_box_row " ${C_LGRAY}No protocols configured for this user.${C_RST}"
        else
            while IFS= read -r proto; do
                local show_fn="show_${proto}_links"
                if ! type "$show_fn" &>/dev/null; then
                    _source_protocol "$proto" 2>/dev/null
                fi

                draw_box_row " ${C_ORANGE}${PROTOCOL_NAMES[$proto]:-$proto}${C_RST}"
                draw_box_sep

                if type "$show_fn" &>/dev/null; then
                    "$show_fn" "$username" 2>/dev/null | while IFS= read -r line; do
                        draw_box_row " $line"
                    done
                else
                    local config
                    config=$(jq ".users[\"$username\"].protocols[\"$proto\"]" \
                        "${DNSCLOAK_USERS:-/opt/dnscloak/users.json}" 2>/dev/null)
                    while IFS= read -r line; do
                        draw_box_row " ${C_TEXT}$line${C_RST}"
                    done <<< "$config"
                fi
                draw_box_empty
            done <<< "$protos"
        fi
    else
        draw_box_row " ${C_LGRAY}User database not found or jq not installed.${C_RST}"
    fi

    draw_box_bottom
    printf '\n'
    press_any_key
}
