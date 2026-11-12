#!/usr/bin/env bash
set -euo pipefail

key_path="${1:?usage: print-and-delete-recovery-key.sh <key_path> <label>}"
label="${2:?usage: print-and-delete-recovery-key.sh <key_path> <label>}"

echo "=== recovery SSH private key for ${label} (save this now; it will not be shown again) ===" >&2
cat "${key_path}"
echo "=== end recovery SSH private key ===" >&2

rm -f "${key_path}" "${key_path}.pub"
