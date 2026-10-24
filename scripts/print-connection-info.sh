#!/usr/bin/env bash
set -euo pipefail

label="${1:?usage: print-connection-info.sh <label> <ip> <ssh_port> <admin_username>}"
ip="${2:?usage: print-connection-info.sh <label> <ip> <ssh_port> <admin_username>}"
ssh_port="${3:?usage: print-connection-info.sh <label> <ip> <ssh_port> <admin_username>}"
admin_username="${4:?usage: print-connection-info.sh <label> <ip> <ssh_port> <admin_username>}"

cat <<EOF
label:          ${label}
ip_address:     ${ip}
admin_username: ${admin_username}
ssh_port:       ${ssh_port}
EOF
