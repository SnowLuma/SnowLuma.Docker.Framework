#!/usr/bin/env bash
set -euo pipefail
# Generate / refresh the per-deployment device identity (hostname + MAC) and
# write it to .env so `docker compose up` picks it up.
#
# Reuses the value already persisted in the qq-gateway-data volume
# (/app/data/config/device-identity) so it stays stable across recreates; only
# generates a fresh one if none exists. Never falls back to a shared default.
# Override via SNOWLUMA_HOSTNAME / SNOWLUMA_MAC_ADDRESS.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE="${IMAGE:-motricseven7/snowluma:latest}"

docker pull "${IMAGE}" >/dev/null 2>&1 || true
docker volume create qq-gateway-data >/dev/null 2>&1 || true

DEVICE_IDENTITY_VOL=qq-gateway-data
DEVICE_IDENTITY_IMAGE="${IMAGE}"
# shellcheck source=scripts/device-identity.sh
. "${SCRIPT_DIR}/device-identity.sh"
resolve_device_identity

cat > "${FRAMEWORK_DIR}/.env" <<EOF
SNOWLUMA_HOSTNAME=${SNOWLUMA_HOSTNAME}
SNOWLUMA_MAC_ADDRESS=${SNOWLUMA_MAC_ADDRESS}
EOF
echo "Wrote ${FRAMEWORK_DIR}/.env:"
echo "  SNOWLUMA_HOSTNAME=${SNOWLUMA_HOSTNAME}"
echo "  SNOWLUMA_MAC_ADDRESS=${SNOWLUMA_MAC_ADDRESS}"
echo "Now run: docker compose up -d"