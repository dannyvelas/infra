#!/usr/bin/env bash
set -euo pipefail

label="${1:?usage: generate-ssh-key.sh <label>}"
key_path="${HOME}/.ssh/id_ed25519_${label}"

if [[ -f "${key_path}" ]]; then
  echo "generate-ssh-key.sh: key for label '${label}' already exists at ${key_path}, reusing it." >&2
else
  ssh-keygen -t ed25519 -f "${key_path}" -C "admin@${label}"
fi

cat "${key_path}.pub"
