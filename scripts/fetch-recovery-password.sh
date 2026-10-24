#!/usr/bin/env bash
set -euo pipefail

ip="${1:?usage: fetch-recovery-password.sh <ip> <ssh_port> <admin_username> <key_path>}"
ssh_port="${2:?usage: fetch-recovery-password.sh <ip> <ssh_port> <admin_username> <key_path>}"
admin_username="${3:?usage: fetch-recovery-password.sh <ip> <ssh_port> <admin_username> <key_path>}"
key_path="${4:?usage: fetch-recovery-password.sh <ip> <ssh_port> <admin_username> <key_path>}"

remote_cmd='sudo cat /root/.console-recovery-password && sudo rm -f /root/.console-recovery-password'

password="$(ssh -i "${key_path}" -p "${ssh_port}" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes \
  "${admin_username}@${ip}" "${remote_cmd}")"

printf '%s\n' "${password}"
