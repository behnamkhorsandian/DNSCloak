#!/bin/bash
#===============================================================================
# Vany - Conduit (Psiphon Relay) Functions
# Sourced by start.sh or install.sh - do not run directly
#===============================================================================

SERVICE_NAME="conduit"
CONDUIT_IMAGE="ghcr.io/ssmirr/conduit/conduit:latest"
CONDUIT_DIR="/opt/conduit"

#-------------------------------------------------------------------------------
# Checks
#-------------------------------------------------------------------------------

is_conduit_installed() {
    docker ps -a 2>/dev/null | grep -q conduit
}

#-------------------------------------------------------------------------------
# Docker
#-------------------------------------------------------------------------------

install_conduit_docker() {
    if command -v docker &>/dev/null; then
        print_info "Docker already installed"
        return 0
    fi

    print_step "Installing Docker"
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    print_success "Docker installed"
}

install_conduit_deps() {
    print_step "Installing dependencies"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq tcpdump geoip-bin geoip-database >/dev/null 2>&1 || true
    print_success "Dependencies installed"
}

#-------------------------------------------------------------------------------
# Settings
#-------------------------------------------------------------------------------

get_conduit_settings() {
    echo ""
    echo -e "  ${BOLD}${WHITE}Conduit Configuration${RESET}"
    print_line
    echo ""

    get_input "Max clients (recommended: 200-1000)" "1000" CONDUIT_MAX_CLIENTS
    get_input "Bandwidth limit in Mbps (-1 for unlimited)" "-1" CONDUIT_BANDWIDTH
}

#-------------------------------------------------------------------------------
# Container
#-------------------------------------------------------------------------------

run_conduit_container() {
    print_step "Pulling Conduit image"
    docker pull "$CONDUIT_IMAGE"

    docker rm -f conduit 2>/dev/null || true

    docker volume create conduit-data 2>/dev/null || true
    docker run --rm -v conduit-data:/home/conduit/data alpine \
        sh -c "chown -R 1000:1000 /home/conduit/data" 2>/dev/null || true

    print_step "Starting Conduit container"
    docker run -d \
        --name conduit \
        --restart unless-stopped \
        --log-opt max-size=15m \
        --log-opt max-file=3 \
        -v conduit-data:/home/conduit/data \
        --network host \
        "$CONDUIT_IMAGE" \
        start -m "${CONDUIT_MAX_CLIENTS:-1000}" -b "${CONDUIT_BANDWIDTH:--1}" -vv -s

    sleep 3

    if docker ps | grep -q conduit; then
        print_success "Conduit is running"
    else
        print_error "Failed to start. Check: docker logs conduit"
        return 1
    fi
}

install_conduit_cli() {
    mkdir -p "$CONDUIT_DIR"

    cat > "$CONDUIT_DIR/settings.conf" <<EOF
MAX_CLIENTS=${CONDUIT_MAX_CLIENTS:-1000}
BANDWIDTH=${CONDUIT_BANDWIDTH:--1}
EOF

    curl -sL "https://raw.githubusercontent.com/behnamkhorsandian/Vanyshsh/main/services/conduit/monitoring-script.sh" \
        -o /usr/local/bin/conduit
    chmod +x /usr/local/bin/conduit

    print_success "CLI installed: conduit"
}

#-------------------------------------------------------------------------------
# Non-interactive install (called by TUI wizard)
# Usage: install_conduit_service <max_clients> <bandwidth>
#-------------------------------------------------------------------------------

install_conduit_service() {
    local max_clients="${1:-300}"
    local bandwidth="${2:--1}"

    CONDUIT_MAX_CLIENTS="$max_clients"
    CONDUIT_BANDWIDTH="$bandwidth"

    install_conduit_docker
    install_conduit_deps
    run_conduit_container
    install_conduit_cli

    print_success "Conduit installed successfully"
}

#-------------------------------------------------------------------------------
# Interactive install (standalone / CLI mode)
#-------------------------------------------------------------------------------

install_conduit() {
    clear
    load_banner "conduit" 2>/dev/null || true
    echo -e "  ${BOLD}${WHITE}Conduit (Psiphon Relay) Installation${RESET}"
    print_line
    echo ""
    echo "  Conduit turns your server into a Psiphon volunteer relay."
    echo "  It helps users in censored regions access the open internet."
    echo "  No per-user management needed - it is fully automated."
    echo ""

    if ! confirm "Install Conduit relay?"; then
        return 0
    fi

    install_conduit_docker
    install_conduit_deps
    get_conduit_settings
    run_conduit_container
    install_conduit_cli

    echo ""
    print_success "Conduit installed successfully!"
    print_line
    echo ""
    echo "  Commands:"
    echo "    conduit status    - Show status"
    echo "    conduit logs      - Live connection stats"
    echo "    conduit peers     - See connected countries"
    echo "    conduit restart   - Restart container"
    echo "    conduit uninstall - Remove everything"
    echo ""

    if confirm "Open management menu?"; then
        manage_conduit
    fi
}

#-------------------------------------------------------------------------------
# Uninstall
#-------------------------------------------------------------------------------

uninstall_conduit() {
    echo ""
    echo -e "  ${BOLD}${RED}Uninstall Conduit${RESET}"
    print_line
    echo ""

    if ! confirm "Remove Conduit completely?"; then
        return 0
    fi

    docker stop conduit 2>/dev/null || true
    docker rm conduit 2>/dev/null || true

    if confirm "Remove data volume too?"; then
        docker volume rm conduit-data 2>/dev/null || true
    fi

    rm -rf "$CONDUIT_DIR"
    rm -f /usr/local/bin/conduit

    print_success "Conduit uninstalled"
}

#-------------------------------------------------------------------------------
# Manage (Menu)
#-------------------------------------------------------------------------------

manage_conduit() {
    while true; do
        clear
        load_banner "conduit" 2>/dev/null || true
        echo -e "  ${BOLD}${WHITE}Conduit Management${RESET}"
        print_line
        echo ""

        if docker ps 2>/dev/null | grep -q conduit; then
            echo -e "  Status: ${GREEN}Running${RESET}"
        else
            echo -e "  Status: ${RED}Stopped${RESET}"
        fi

        if [[ -f "$CONDUIT_DIR/settings.conf" ]]; then
            # shellcheck source=/dev/null
            . "$CONDUIT_DIR/settings.conf"
            echo -e "  Max Clients: ${CYAN}${MAX_CLIENTS:-1000}${RESET}"
            if [[ "${BANDWIDTH:--1}" == "-1" ]]; then
                echo -e "  Bandwidth: ${CYAN}Unlimited${RESET}"
            else
                echo -e "  Bandwidth: ${CYAN}${BANDWIDTH} Mbps${RESET}"
            fi
        fi

        local stats
        stats=$(docker logs --tail 100 conduit 2>&1 | grep "\[STATS\]" | tail -1)
        if [[ -n "$stats" ]]; then
            echo ""
            echo -e "  ${GRAY}$stats${RESET}"
        fi

        echo ""
        print_line
        echo ""
        echo "  1) View live stats"
        echo "  2) Start / Stop / Restart"
        echo "  3) Change settings"
        echo "  4) Update Conduit"
        echo "  5) Uninstall"
        echo "  0) Back"
        echo ""

        get_input "Select [0-5]" "0" choice

        case "$choice" in
            1)
                clear
                echo -e "  ${CYAN}LIVE STATS (Ctrl+C to return)${RESET}"
                echo ""
                trap 'break' SIGINT
                docker logs -f --tail 20 conduit 2>&1 | grep --line-buffered "\[STATS\]" || true
                trap - SIGINT
                ;;
            2)
                echo ""
                echo "  s) Start"
                echo "  t) Stop"
                echo "  r) Restart"
                echo ""
                get_input "Action" "" action
                case "$action" in
                    s) docker start conduit 2>/dev/null && print_success "Started" || print_error "Failed" ;;
                    t) docker stop conduit 2>/dev/null && print_success "Stopped" ;;
                    r) docker restart conduit 2>/dev/null && print_success "Restarted" || print_error "Failed" ;;
                esac
                sleep 2
                ;;
            3)
                get_conduit_settings
                print_info "Recreating container with new settings..."
                docker rm -f conduit 2>/dev/null || true
                run_conduit_container
                cat > "$CONDUIT_DIR/settings.conf" <<EOF
MAX_CLIENTS=${CONDUIT_MAX_CLIENTS}
BANDWIDTH=${CONDUIT_BANDWIDTH}
EOF
                press_enter
                ;;
            4)
                print_step "Updating Conduit..."
                docker pull "$CONDUIT_IMAGE"
                docker rm -f conduit 2>/dev/null || true
                [[ -f "$CONDUIT_DIR/settings.conf" ]] && . "$CONDUIT_DIR/settings.conf"
                CONDUIT_MAX_CLIENTS="${MAX_CLIENTS:-1000}"
                CONDUIT_BANDWIDTH="${BANDWIDTH:--1}"
                run_conduit_container
                install_conduit_cli
                print_success "Updated to latest version"
                press_enter
                ;;
            5)
                uninstall_conduit
                return 0
                ;;
            0|"")
                return 0
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}
