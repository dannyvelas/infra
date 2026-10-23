#!/usr/bin/env bash
set -euo pipefail

ip="${1:?usage: verify-admin-access.sh <ip> <ssh_port> <admin_username> <key_path>}"
ssh_port="${2:?usage: verify-admin-access.sh <ip> <ssh_port> <admin_username> <key_path>}"
admin_username="${3:?usage: verify-admin-access.sh <ip> <ssh_port> <admin_username> <key_path>}"
key_path="${4:?usage: verify-admin-access.sh <ip> <ssh_port> <admin_username> <key_path>}"

timeout_seconds=300
interval_seconds=5
elapsed=0

remote_check='id -nG | tr " " "\n" | grep -qx sudo && sudo -n whoami | grep -qx root'

while true; do
  if ssh -i "${key_path}" -p "${ssh_port}" \
      -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes \
      "${admin_username}@${ip}" "${remote_check}"; then
    exit 0
  fi

  elapsed=$((elapsed + interval_seconds))
  if [ "${elapsed}" -ge "${timeout_seconds}" ]; then
    echo "verify-admin-access.sh: timed out after ${timeout_seconds}s waiting for ${admin_username}@${ip}:${ssh_port} to accept the dedicated key with passwordless sudo." >&2
    echo "verify-admin-access.sh: root login and password authentication remain enabled, exactly as cloud-init left them." >&2
    exit 1
  fi
  sleep "${interval_seconds}"
done
