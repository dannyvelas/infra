#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "==> terraform fmt -check"
terraform fmt -check -recursive

echo "==> terraform validate"
terraform init -backend=false -input=false >/dev/null
terraform validate

echo "==> shellcheck scripts/*.sh"
shellcheck scripts/*.sh

echo "All checks passed."
