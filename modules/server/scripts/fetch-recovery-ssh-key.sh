#!/usr/bin/env bash
set -euo pipefail

ip="${1:?usage: fetch-recovery-ssh-key.sh <ip> <ssh_port> <admin_username> <key_path>}"
ssh_port="${2:?usage: fetch-recovery-ssh-key.sh <ip> <ssh_port> <admin_username> <key_path>}"
admin_username="${3:?usage: fetch-recovery-ssh-key.sh <ip> <ssh_port> <admin_username> <key_path>}"
key_path="${4:?usage: fetch-recovery-ssh-key.sh <ip> <ssh_port> <admin_username> <key_path>}"

remote_cmd='sudo cat /root/.ssh-recovery-key && sudo rm -f /root/.ssh-recovery-key'

recovery_key="$(ssh -i "${key_path}" -p "${ssh_port}" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes \
  "${admin_username}@${ip}" "${remote_cmd}")"

echo "=== recovery SSH private key for ${admin_username}@${ip} (save this now; it will not be shown again) ===" >&2
printf '%s\n' "${recovery_key}"
echo "=== end recovery SSH private key ===" >&2
