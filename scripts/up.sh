#!/usr/bin/env bash
set -euo pipefail
# Recommended entry point for Compose users: generate/refresh the per-deployment
# device identity (.env) first, then start the stack. Ensures SNOWLUMA_HOSTNAME /
# SNOWLUMA_MAC_ADDRESS are always present before `docker compose up`.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

"${SCRIPT_DIR}/init-device-identity.sh"
cd "${FRAMEWORK_DIR}"
exec docker compose up -d "$@"