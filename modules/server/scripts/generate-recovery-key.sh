#!/usr/bin/env bash
set -euo pipefail

label="${1:?usage: generate-recovery-key.sh <label>}"
key_path="${HOME}/.ssh/id_ed25519_${label}-recovery"

if [[ -f "${key_path}" ]]; then
  echo "generate-recovery-key.sh: recovery key for label '${label}' already exists at ${key_path}, reusing it." >&2
else
  ssh-keygen -t ed25519 -N '' -C "recovery@${label}" -f "${key_path}"
fi

cat "${key_path}.pub"
