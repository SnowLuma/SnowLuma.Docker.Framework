#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Mode: "run" (default, docker run) or "compose" (write .env + docker compose up).
MODE="${1:-run}"
case "${MODE}" in
  run|--run) MODE=run ;;
  compose|--compose) MODE=compose ;;
  *) echo "Usage: $0 [run|compose]" >&2; exit 1 ;;
esac

IMAGE="${IMAGE:-snowluma-docker-framework:latest}"
NAME="${NAME:-snowluma}"
SNOWLUMA_WEBUI_HOST="${SNOWLUMA_WEBUI_HOST:-0.0.0.0}"
SNOWLUMA_WEBUI_PORT="${SNOWLUMA_WEBUI_PORT:-5099}"
SNOWLUMA_WEBUI_HOST_PORT="${SNOWLUMA_WEBUI_HOST_PORT:-5099}"

# ── device identity (hostname + MAC) ──────────────────────────────────────
# QQ treats the container hostname and NIC MAC as part of its device
# fingerprint. Docker changes both on every recreate by default, so QQ forces a
# re-scan even when machine-id is persisted. This resolver keeps them stable and
# unique per deployment, without hardcoding a shared default:
#   1. operator override: SNOWLUMA_HOSTNAME / SNOWLUMA_MAC_ADDRESS, if set;
#   2. persisted value:   /app/data/config/device-identity in the data volume;
#   3. otherwise:         generate once, persist to the volume, and reuse.
# The volume is the source of truth: the resolved identity is written back
# whenever it differs from the stored value (so overrides also become the
# deployment identity), and a failed persist is fatal (otherwise the next
# recreate would regenerate a different identity and QQ would re-scan).
resolve_device_identity() {
  local vol="${DEVICE_IDENTITY_VOL:?DEVICE_IDENTITY_VOL must be set}"
  local image="${DEVICE_IDENTITY_IMAGE:?DEVICE_IDENTITY_IMAGE must be set}"

  SNOWLUMA_HOSTNAME="${SNOWLUMA_HOSTNAME:-}"
  SNOWLUMA_MAC_ADDRESS="${SNOWLUMA_MAC_ADDRESS:-}"

  local stored="" stored_hostname="" stored_mac=""
  stored=$(docker run --rm --entrypoint sh -v "${vol}:/app/data" "${image}" -c 'cat /app/data/config/device-identity 2>/dev/null || true' 2>/dev/null || true)
  stored_hostname=$(printf '%s\n' "${stored}" | sed -n 's/^hostname=//p' | head -n 1)
  stored_mac=$(printf '%s\n' "${stored}" | sed -n 's/^mac=//p' | head -n 1)

  [ -n "${SNOWLUMA_HOSTNAME}" ] || SNOWLUMA_HOSTNAME="${stored_hostname}"
  [ -n "${SNOWLUMA_MAC_ADDRESS}" ] || SNOWLUMA_MAC_ADDRESS="${stored_mac}"

  if [ -z "${SNOWLUMA_HOSTNAME}" ]; then
    SNOWLUMA_HOSTNAME="snowluma-$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
    [ -n "${SNOWLUMA_HOSTNAME}" ] || SNOWLUMA_HOSTNAME="snowluma-$$"
  fi
  if [ -z "${SNOWLUMA_MAC_ADDRESS}" ]; then
    local mac=""
    mac=$(od -An -N5 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    if [ -n "${mac}" ]; then
      # 02: = locally-administered unicast; unique per deployment.
      SNOWLUMA_MAC_ADDRESS="02:$(printf '%s' "${mac}" | sed 's/\(..\)/\1:/g; s/:$//')"
    else
      # Last-resort (no od): derive a stable unicast MAC from the generated
      # hostname hash so it is still unique per deployment, never a shared value.
      local h
      h=$(printf '%s' "${SNOWLUMA_HOSTNAME}" | md5sum 2>/dev/null | cut -c1-10)
      [ -n "${h}" ] || h="0000000000"
      SNOWLUMA_MAC_ADDRESS="02:$(printf '%s' "${h}" | sed 's/\(..\)/\1:/g; s/:$//')"
    fi
  fi

  if [ "${SNOWLUMA_HOSTNAME}" != "${stored_hostname}" ] || [ "${SNOWLUMA_MAC_ADDRESS}" != "${stored_mac}" ]; then
    if ! docker run --rm --entrypoint sh -v "${vol}:/app/data" "${image}" \
      -c 'mkdir -p /app/data/config && printf "hostname=%s\nmac=%s\n" "$1" "$2" > /app/data/config/device-identity' \
      _ "${SNOWLUMA_HOSTNAME}" "${SNOWLUMA_MAC_ADDRESS}"; then
      echo "ERROR: failed to persist device identity to ${vol} (/app/data/config/device-identity); a future recreate would change QQ's device fingerprint." >&2
      return 1
    fi
  fi
}

if [ "${MODE}" = "compose" ]; then
  # Compose entry: ensure the per-deployment identity (.env) exists, then up.
  COMPOSE_IMAGE="${SNOWLUMA_IMAGE:-motricseven7/snowluma:latest}"
  docker pull "${COMPOSE_IMAGE}" >/dev/null 2>&1 || true
  docker volume create qq-gateway-data >/dev/null 2>&1 || true
  DEVICE_IDENTITY_VOL=qq-gateway-data
  DEVICE_IDENTITY_IMAGE="${COMPOSE_IMAGE}"
  resolve_device_identity
  cat > "${FRAMEWORK_DIR}/.env" <<EOF
SNOWLUMA_HOSTNAME=${SNOWLUMA_HOSTNAME}
SNOWLUMA_MAC_ADDRESS=${SNOWLUMA_MAC_ADDRESS}
EOF
  echo "Wrote ${FRAMEWORK_DIR}/.env: SNOWLUMA_HOSTNAME=${SNOWLUMA_HOSTNAME} SNOWLUMA_MAC_ADDRESS=${SNOWLUMA_MAC_ADDRESS}"
  cd "${FRAMEWORK_DIR}"
  exec docker compose up -d "${@:2}"
fi

# ── run mode (docker run) ─────────────────────────────────────────────────
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
docker volume create qq-client-config >/dev/null
docker volume create qq-client-data >/dev/null

DEVICE_IDENTITY_VOL=qq-gateway-data
DEVICE_IDENTITY_IMAGE="${IMAGE}"
resolve_device_identity

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