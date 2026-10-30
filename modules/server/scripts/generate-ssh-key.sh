#!/usr/bin/env bash
set -euo pipefail

kind="${1:?usage: generate-ssh-key.sh <admin|recovery> <label>}"
label="${2:?usage: generate-ssh-key.sh <admin|recovery> <label>}"

case "${kind}" in
  admin)
    key_path="${HOME}/.ssh/id_ed25519_${label}"
    passphrase_flag=()
    ;;
  recovery)
    key_path="${HOME}/.ssh/id_ed25519_${label}-recovery"
    passphrase_flag=(-N '')
    ;;
  *)
    echo "generate-ssh-key.sh: unknown kind '${kind}', expected 'admin' or 'recovery'" >&2
    exit 1
    ;;
esac

if [[ -f "${key_path}" ]]; then
  echo "generate-ssh-key.sh: ${kind} key for label '${label}' already exists at ${key_path}, reusing it." >&2
else
  ssh-keygen -t ed25519 "${passphrase_flag[@]}" -C "${kind}@${label}" -f "${key_path}"
fi

cat "${key_path}.pub"
