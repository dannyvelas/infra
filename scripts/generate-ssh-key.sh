#!/usr/bin/env bash
# Generates the dedicated, per-server SSH key pair described in FR-001/FR-002.
# One key per label, never reused across servers. The passphrase is set
# interactively by the operator and is never captured or persisted by this
# script — only the resulting key files exist on disk afterward.
set -euo pipefail

label="${1:?usage: generate-ssh-key.sh <label>}"
key_path="${HOME}/.ssh/id_ed25519_${label}"

if [[ -f "${key_path}" ]]; then
  echo "generate-ssh-key.sh: key for label '${label}' already exists at ${key_path}, reusing it." >&2
else
  ssh-keygen -t ed25519 -f "${key_path}" -C "admin@${label}"
fi

# Only the public key is safe to feed into Terraform-managed resources.
cat "${key_path}.pub"
