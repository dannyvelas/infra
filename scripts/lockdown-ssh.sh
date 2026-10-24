#!/usr/bin/env bash
set -euo pipefail

ip="${1:?usage: lockdown-ssh.sh <ip> <ssh_port> <admin_username> <key_path>}"
ssh_port="${2:?usage: lockdown-ssh.sh <ip> <ssh_port> <admin_username> <key_path>}"
admin_username="${3:?usage: lockdown-ssh.sh <ip> <ssh_port> <admin_username> <key_path>}"
key_path="${4:?usage: lockdown-ssh.sh <ip> <ssh_port> <admin_username> <key_path>}"

remote_cmd="$(cat <<EOF
sudo tee /etc/ssh/sshd_config.d/00-admin.conf > /dev/null <<'CONF'
Port ${ssh_port}
PermitRootLogin no
PasswordAuthentication no
CONF
sudo systemctl is-active ssh.socket && sudo systemctl restart ssh.socket || sudo systemctl restart ssh
EOF
)"

ssh -i "${key_path}" -p "${ssh_port}" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes \
  "${admin_username}@${ip}" "${remote_cmd}"
