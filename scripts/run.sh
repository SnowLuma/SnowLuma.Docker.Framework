#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE="${IMAGE:-snowluma-docker-framework:latest}"
NAME="${NAME:-snowluma}"
SNOWLUMA_WEBUI_HOST="${SNOWLUMA_WEBUI_HOST:-0.0.0.0}"
SNOWLUMA_WEBUI_PORT="${SNOWLUMA_WEBUI_PORT:-5099}"
SNOWLUMA_WEBUI_HOST_PORT="${SNOWLUMA_WEBUI_HOST_PORT:-5099}"
SNOWLUMA_HOSTNAME="${SNOWLUMA_HOSTNAME:-}"
SNOWLUMA_MAC_ADDRESS="${SNOWLUMA_MAC_ADDRESS:-}"

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  IMAGE="${IMAGE}" "${SCRIPT_DIR}/build-image.sh"
fi

if docker ps -a --format '{{.Names}}' | grep -qx "${NAME}"; then
  if [ "${RECREATE:-0}" = "1" ]; then
    docker rm -f "${NAME}" >/dev/null
  else
    echo "Container ${NAME} already exists. Set RECREATE=1 to replace it."
    exit 1
  fi
fi

docker volume create qq-gateway-data >/dev/null
# Stable per-deployment device identity (hostname + MAC) backed by the data
# volume, unless the operator overrides via SNOWLUMA_HOSTNAME /
# SNOWLUMA_MAC_ADDRESS. QQ treats hostname + NIC MAC as part of the device
# fingerprint, so a fixed value keeps auto-login across container recreates.
# Generating once and persisting to the volume keeps every deployment unique
# without hardcoding a shared fingerprint (same philosophy as machine-id).
resolve_device_identity() {
  local vol=qq-gateway-data
  local file=/app/data/config/device-identity

  if [ -z "${SNOWLUMA_HOSTNAME}" ] || [ -z "${SNOWLUMA_MAC_ADDRESS}" ]; then
    local stored=""
    stored=$(docker run --rm --entrypoint sh -v "${vol}:/app/data" "${IMAGE}" -c 'cat /app/data/config/device-identity 2>/dev/null || true' 2>/dev/null || true)
    if [ -z "${SNOWLUMA_HOSTNAME}" ]; then
      SNOWLUMA_HOSTNAME=$(printf '%s\n' "${stored}" | sed -n 's/^hostname=//p' | head -n 1)
    fi
    if [ -z "${SNOWLUMA_MAC_ADDRESS}" ]; then
      SNOWLUMA_MAC_ADDRESS=$(printf '%s\n' "${stored}" | sed -n 's/^mac=//p' | head -n 1)
    fi
  fi

  local generated=0
  if [ -z "${SNOWLUMA_HOSTNAME}" ]; then
    SNOWLUMA_HOSTNAME="snowluma-$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
    [ -n "${SNOWLUMA_HOSTNAME}" ] || SNOWLUMA_HOSTNAME="snowluma-$$"
    generated=1
  fi
  if [ -z "${SNOWLUMA_MAC_ADDRESS}" ]; then
    local mac=""
    mac=$(od -An -N5 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    if [ -n "${mac}" ]; then
      SNOWLUMA_MAC_ADDRESS="02:$(printf '%s' "${mac}" | sed 's/\(..\)/\1:/g; s/:$//')"
    fi
    [ -n "${SNOWLUMA_MAC_ADDRESS}" ] || SNOWLUMA_MAC_ADDRESS="02:42:ac:11:00:01"
    generated=1
  fi

  if [ "${generated}" = "1" ]; then
    docker run --rm --entrypoint sh -v "${vol}:/app/data" "${IMAGE}" -c 'mkdir -p /app/data/config && printf "hostname=%s\nmac=%s\n" "$1" "$2" > /app/data/config/device-identity' _ "${SNOWLUMA_HOSTNAME}" "${SNOWLUMA_MAC_ADDRESS}" >/dev/null 2>&1 || true
  fi
}

resolve_device_identity
docker volume create qq-client-config >/dev/null
docker volume create qq-client-data >/dev/null

docker run -d \
  --name "${NAME}" \
  --hostname "${SNOWLUMA_HOSTNAME}" \
  --mac-address "${SNOWLUMA_MAC_ADDRESS}" \
  --restart unless-stopped \
  --shm-size=1g \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -e VNC_PASSWD="${VNC_PASSWD:-vncpasswd}" \
  -e SNOWLUMA_UID="${SNOWLUMA_UID:-1000}" \
  -e SNOWLUMA_GID="${SNOWLUMA_GID:-1000}" \
  -e SNOWLUMA_WEBUI_HOST="${SNOWLUMA_WEBUI_HOST}" \
  -e SNOWLUMA_WEBUI_PORT="${SNOWLUMA_WEBUI_PORT}" \
  -e SNOWLUMA_LOG_LEVEL="${SNOWLUMA_LOG_LEVEL:-info}" \
  -e SNOWLUMA_SCREEN="${SNOWLUMA_SCREEN:-1920x1080x24}" \
  -e SNOWLUMA_HOOK_AUTOLOAD="${SNOWLUMA_HOOK_AUTOLOAD:-1}" \
  -e SNOWLUMA_EXTRA_QQ_HOMES="${SNOWLUMA_EXTRA_QQ_HOMES:-}" \
  -e SNOWLUMA_QQ_FLAGS="${SNOWLUMA_QQ_FLAGS:---disable-gpu --disable-software-rasterizer --disable-gpu-compositing}" \
  -p "${VNC_PORT:-5900}:5900" \
  -p "${NOVNC_PORT:-6081}:6081" \
  -p "${SNOWLUMA_WEBUI_HOST_PORT}:${SNOWLUMA_WEBUI_PORT}" \
  -p "${ONEBOT_HTTP_PORT:-3000}:3000" \
  -p "${ONEBOT_WS_PORT:-3001}:3001" \
  -v qq-gateway-data:/app/data \
  -v qq-client-config:/app/.config \
  -v qq-client-data:/app/.local/share \
  "${IMAGE}"

echo "Started ${NAME}"
echo "noVNC: http://127.0.0.1:${NOVNC_PORT:-6081}/"
echo "WebUI: http://127.0.0.1:${SNOWLUMA_WEBUI_HOST_PORT}/"
echo "Logs:  docker logs -f ${NAME}"
