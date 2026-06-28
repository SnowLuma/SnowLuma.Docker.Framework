#!/usr/bin/env bash
set -euo pipefail

: "${VNC_PASSWD:=vncpasswd}"
: "${SNOWLUMA_UID:=1000}"
: "${SNOWLUMA_GID:=1000}"
: "${SNOWLUMA_HOME:=/app/snowluma}"
: "${SNOWLUMA_DATA:=/app/snowluma-data}"
: "${SNOWLUMA_WEBUI_PORT:=5099}"
: "${SNOWLUMA_LOG_LEVEL:=info}"
: "${SNOWLUMA_SCREEN:=1920x1080x24}"
: "${SNOWLUMA_HOOK_AUTOLOAD:=1}"
: "${SNOWLUMA_EXTRA_QQ_HOMES:=}"
: "${SNOWLUMA_QQ_FLAGS:=--disable-gpu --disable-software-rasterizer --disable-gpu-compositing}"

export DISPLAY="${DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/snowluma-${SNOWLUMA_UID}}"
export SNOWLUMA_HOOK_RUNTIME_DIR="${SNOWLUMA_HOOK_RUNTIME_DIR:-${XDG_RUNTIME_DIR}}"
export SNOWLUMA_LOG_LEVEL SNOWLUMA_HOOK_AUTOLOAD SNOWLUMA_EXTRA_QQ_HOMES SNOWLUMA_QQ_FLAGS

DISPLAY_NUM="${DISPLAY#:}"
DISPLAY_NUM="${DISPLAY_NUM%%.*}"

chmod 1777 /tmp || true
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix || true
rm -f /run/dbus/pid /run/dbus/system_bus_socket "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}" /tmp/dbus-*

mkdir -p \
  /var/run/dbus \
  /root/.vnc \
  "${XDG_RUNTIME_DIR}" \
  "${SNOWLUMA_DATA}/config" \
  /app/.cache \
  /app/.config \
  /app/.local/share \
  /etc/supervisor/conf.d

ensure_machine_id() {
  local target="/etc/machine-id"
  local persistent="${SNOWLUMA_DATA}/config/machine-id"

  mkdir -p "$(dirname "$persistent")" || { echo "FATAL: 无法创建 machine-id 持久化目录" >&2; exit 1; }

  if [ -f "$persistent" ]; then
    cp -p "$persistent" "$target" || { echo "FATAL: 无法从 $persistent 恢复 machine-id" >&2; exit 1; }
  else
    dbus-uuidgen --ensure="$target" || { echo "FATAL: dbus-uuidgen 生成 machine-id 失败" >&2; exit 1; }
    local tmpf; tmpf="$(mktemp "${persistent}.XXXXXX")" || { echo "FATAL: mktemp 创建临时文件失败" >&2; exit 1; }
    cp -p "$target" "$tmpf" || { echo "FATAL: 无法写入临时 machine-id 文件" >&2; exit 1; }
    mv "$tmpf" "$persistent" || { echo "FATAL: 无法持久化 machine-id" >&2; exit 1; }
  fi
}

ensure_machine_id

groupmod -o -g "${SNOWLUMA_GID}" snowluma
usermod -o -u "${SNOWLUMA_UID}" -g "${SNOWLUMA_GID}" snowluma

chown -R "${SNOWLUMA_UID}:${SNOWLUMA_GID}" \
  /app \
  /opt/QQ \
  "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"

# Docker restart can preserve stale AF_UNIX socket nodes in the container
# writable layer. Remove them before QQ starts so PID reuse cannot make a dead
# hook socket look like a live SnowLuma injection.
find "${XDG_RUNTIME_DIR}" -maxdepth 1 -type s -name 'mojo.*.*.sock' -delete 2>/dev/null || true

generate_extra_qq_supervisor_conf() {
  local conf="/etc/supervisor/conf.d/extra-qq.conf"
  local homes="${SNOWLUMA_EXTRA_QQ_HOMES//,/ }"
  local home
  local index=1
  local delay

  rm -f "${conf}"

  for home in ${homes}; do
    [ -n "${home}" ] || continue

    case "${home}" in
      /app/*) ;;
      *)
        echo "Skipping extra QQ HOME '${home}': path must be under /app." >&2
        continue
        ;;
    esac

    case "${home}" in
      *[!A-Za-z0-9_@%+=:,./-]*)
        echo "Skipping extra QQ HOME '${home}': unsupported characters in path." >&2
        continue
        ;;
    esac

    mkdir -p "${home}"
    chown -R "${SNOWLUMA_UID}:${SNOWLUMA_GID}" "${home}"

    delay=$(( (index - 1) * 10 ))

    cat >> "${conf}" <<EOF
[program:qq-extra-${index}]
command=/bin/sh -c 'sleep ${delay}; exec qq --no-sandbox %(ENV_SNOWLUMA_QQ_FLAGS)s'
directory=/app
user=snowluma
priority=15
autostart=true
autorestart=true
startsecs=3
stopasgroup=true
killasgroup=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
environment=HOME="${home}",DISPLAY="%(ENV_DISPLAY)s",XDG_RUNTIME_DIR="%(ENV_XDG_RUNTIME_DIR)s",DBUS_SESSION_BUS_ADDRESS="%(ENV_DBUS_SESSION_BUS_ADDRESS)s",SNOWLUMA_HOOK_RUNTIME_DIR="%(ENV_SNOWLUMA_HOOK_RUNTIME_DIR)s"

EOF

    index=$((index + 1))
  done

  if [ "${index}" -gt 1 ]; then
    echo "Configured $((index - 1)) extra QQ instance(s): ${SNOWLUMA_EXTRA_QQ_HOMES}"
  fi
}

generate_extra_qq_supervisor_conf

node <<'NODE'
const fs = require('fs');
const path = require('path');

const dataDir = process.env.SNOWLUMA_DATA || '/app/snowluma-data';
const configDir = path.join(dataDir, 'config');
const runtimeConfigPath = path.join(configDir, 'runtime.json');
const requestedPort = Number(process.env.SNOWLUMA_WEBUI_PORT || 5099);
const webuiPort = Number.isInteger(requestedPort) && requestedPort > 0 && requestedPort <= 65535
  ? requestedPort
  : 5099;

fs.mkdirSync(configDir, { recursive: true });

let runtimeConfig = {};
try {
  runtimeConfig = JSON.parse(fs.readFileSync(runtimeConfigPath, 'utf8'));
} catch {
  runtimeConfig = {};
}

runtimeConfig.webuiPort = webuiPort;
fs.writeFileSync(runtimeConfigPath, `${JSON.stringify(runtimeConfig, null, 2)}\n`, 'utf8');
NODE
# Node.js block above ran as root, so runtime.json is owned by root.
# SnowLuma runs as snowluma user and needs write access to config/.
chown "${SNOWLUMA_UID}:${SNOWLUMA_GID}" "${SNOWLUMA_DATA}/config" "${SNOWLUMA_DATA}/config/runtime.json"

x11vnc -storepasswd "${VNC_PASSWD}" /root/.vnc/passwd >/dev/null

wait_for_xvfb() {
  local socket="/tmp/.X11-unix/X${DISPLAY_NUM}"

  for _ in {1..200}; do
    if [ -S "${socket}" ]; then
      return 0
    fi

    if ! kill -0 "${XVFB_PID}" 2>/dev/null; then
      echo "Xvfb exited before display ${DISPLAY} became ready." >&2
      return 1
    fi

    sleep 0.1
  done

  echo "Timed out waiting for Xvfb display ${DISPLAY}." >&2
  return 1
}

export DBUS_SESSION_BUS_ADDRESS=""
if DBUS_SESSION_BUS_ADDRESS=$(su -s /bin/bash -c 'dbus-daemon --session --fork --print-address' snowluma 2>/dev/null); then
  export DBUS_SESSION_BUS_ADDRESS
fi
dbus-daemon --config-file=/usr/share/dbus-1/system.conf --print-address &
Xvfb "${DISPLAY}" -screen 0 "${SNOWLUMA_SCREEN}" &
XVFB_PID=$!
wait_for_xvfb

fluxbox &
x11vnc -display "${DISPLAY}" -noxrecord -noxfixes -noxdamage -forever -rfbauth /root/.vnc/passwd &
X11VNC_PID=$!
sleep 0.5
if ! kill -0 "${X11VNC_PID}" 2>/dev/null; then
  echo "x11vnc failed to start for display ${DISPLAY}." >&2
  exit 1
fi

nohup /opt/noVNC/utils/novnc_proxy --vnc localhost:5900 --listen 6081 --file-only >/var/log/novnc.log 2>&1 &

exec supervisord -c /etc/supervisord.conf
