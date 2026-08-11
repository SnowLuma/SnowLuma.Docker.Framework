#!/usr/bin/env bash
# Shared per-deployment device identity resolver (hostname + MAC).
#
# QQ treats the container hostname and NIC MAC as part of its device
# fingerprint. Docker changes both on every recreate by default, so QQ forces a
# re-scan even when machine-id is persisted. This resolver keeps them stable and
# unique per deployment, without hardcoding a shared default:
#   1. operator override: SNOWLUMA_HOSTNAME / SNOWLUMA_MAC_ADDRESS, if set;
#   2. persisted value:   /app/data/config/device-identity in the data volume;
#   3. otherwise:         generate once, persist to the volume, and reuse.
#
# Usage (must run before the container is created, since MAC is fixed at
# container creation time):
#   DEVICE_IDENTITY_VOL=qq-gateway-data DEVICE_IDENTITY_IMAGE=<image> \
#     . "$SCRIPT_DIR/device-identity.sh"
#   resolve_device_identity
# Sets SNOWLUMA_HOSTNAME / SNOWLUMA_MAC_ADDRESS.

resolve_device_identity() {
  local vol="${DEVICE_IDENTITY_VOL:?DEVICE_IDENTITY_VOL must be set}"
  local image="${DEVICE_IDENTITY_IMAGE:?DEVICE_IDENTITY_IMAGE must be set}"

  SNOWLUMA_HOSTNAME="${SNOWLUMA_HOSTNAME:-}"
  SNOWLUMA_MAC_ADDRESS="${SNOWLUMA_MAC_ADDRESS:-}"

  if [ -z "${SNOWLUMA_HOSTNAME}" ] || [ -z "${SNOWLUMA_MAC_ADDRESS}" ]; then
    local stored=""
    stored=$(docker run --rm --entrypoint sh -v "${vol}:/app/data" "${image}" -c 'cat /app/data/config/device-identity 2>/dev/null || true' 2>/dev/null || true)
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
    generated=1
  fi

  if [ "${generated}" = "1" ]; then
    docker run --rm --entrypoint sh -v "${vol}:/app/data" "${image}" \
      -c 'mkdir -p /app/data/config && printf "hostname=%s\nmac=%s\n" "$1" "$2" > /app/data/config/device-identity' \
      _ "${SNOWLUMA_HOSTNAME}" "${SNOWLUMA_MAC_ADDRESS}" >/dev/null 2>&1 || true
  fi
}