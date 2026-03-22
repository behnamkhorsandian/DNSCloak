#!/bin/bash
#===============================================================================
# Vany - Install SSH Tunnel (restricted user for SOCKS5 proxy)
#===============================================================================

set -e

VANY_DIR="/opt/vany"
STATE_FILE="$VANY_DIR/state.json"

install_ssh_tunnel() {
    local ssh_user="${SSH_USER:-vany}"

    echo "  Setting up SSH tunnel user..."

    # Create restricted user for tunnel-only access
    if ! id "$ssh_user" &>/dev/null; then
        useradd -m -s /usr/sbin/nologin "$ssh_user"
    fi

    # Generate SSH key for the user
    local ssh_dir="/home/$ssh_user/.ssh"
    mkdir -p "$ssh_dir"

    if [[ ! -f "$ssh_dir/id_ed25519" ]]; then
        ssh-keygen -t ed25519 -f "$ssh_dir/id_ed25519" -N "" -q
        cat "$ssh_dir/id_ed25519.pub" >> "$ssh_dir/authorized_keys"
        chmod 600 "$ssh_dir/authorized_keys"
        chown -R "$ssh_user:$ssh_user" "$ssh_dir"
    fi

    # Configure SSH to allow tunnel-only for this user
    local sshd_config="/etc/ssh/sshd_config"
    if ! grep -q "Match User $ssh_user" "$sshd_config" 2>/dev/null; then
        cat >> "$sshd_config" <<EOF

# Vany SSH Tunnel - restricted user
Match User $ssh_user
    AllowTcpForwarding yes
    X11Forwarding no
    AllowAgentForwarding no
    ForceCommand /bin/false
    PermitTunnel no
EOF
        systemctl reload sshd 2>/dev/null || service ssh reload 2>/dev/null || true
    fi

    # Copy private key for distribution
    cp "$ssh_dir/id_ed25519" "$VANY_DIR/ssh-tunnel-key"
    chmod 600 "$VANY_DIR/ssh-tunnel-key"

    # Update state
    local server_ip
    server_ip=$(jq -r '.server.ip // ""' "$STATE_FILE")

    jq --arg user "$ssh_user" \
        '.protocols["ssh-tunnel"] = {"status": "running", "container": "--", "ports": ["22/tcp"]}' \
        "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

    echo "  SSH tunnel user '$ssh_user' configured"
    echo "  Client connects with: ssh -D 1080 -i key $ssh_user@$server_ip"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_ssh_tunnel
fi
