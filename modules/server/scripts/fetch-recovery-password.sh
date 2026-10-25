#!/usr/bin/env bash
# this script exists because cloud-init creates a password at boot that nobody, not even the operator
# knows. terraform will local-exec this script to give this password for the operator to save somewhere safe
set -euo pipefail

ip="${1:?usage: fetch-recovery-password.sh <ip> <ssh_port> <admin_username> <key_path>}"
ssh_port="${2:?usage: fetch-recovery-password.sh <ip> <ssh_port> <admin_username> <key_path>}"
admin_username="${3:?usage: fetch-recovery-password.sh <ip> <ssh_port> <admin_username> <key_path>}"
key_path="${4:?usage: fetch-recovery-password.sh <ip> <ssh_port> <admin_username> <key_path>}"

remote_cmd='sudo cat /root/.console-recovery-password && sudo rm -f /root/.console-recovery-password'

password="$(ssh -i "${key_path}" -p "${ssh_port}" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes \
  "${admin_username}@${ip}" "${remote_cmd}")"

echo "=== admin console-recovery password for ${admin_username}@${ip} (save this now; it will not be shown again) ===" >&2
printf '%s\n' "${password}"
echo "=== end admin console-recovery password ===" >&2
