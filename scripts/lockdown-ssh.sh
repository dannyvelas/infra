#!/usr/bin/env bash
set -euo pipefail

ip="${1:?usage: lockdown-ssh.sh <ip> <ssh_port> <admin_username> <key_path>}"
ssh_port="${2:?usage: lockdown-ssh.sh <ip> <ssh_port> <admin_username> <key_path>}"
admin_username="${3:?usage: lockdown-ssh.sh <ip> <ssh_port> <admin_username> <key_path>}"
key_path="${4:?usage: lockdown-ssh.sh <ip> <ssh_port> <admin_username> <key_path>}"

# 1. we're using `tee` to write to the ssh config file instead of naively using shell redirection (>)
# this is because shell redirection gets interpreted before `sudo` and would fail with permission denied
# tee uses `sudo`
# 2. the lack of single-quotes around EOF and the apostrophes around CONF are load-bearing. it makes the
# ssh_port variable get interpreted by this outer shell (not the inner shell)
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
