#!/usr/bin/env bash
set -euo pipefail

# Modern hosts inherit fs.nr_open (~1e9) as RLIMIT_NOFILE. Several
# desktop helpers walk 0..limit during startup and never finish the
# remote-desktop handshake. Lower an excessive ceiling only; never
# raise a small existing limit.
NOFILE_SOFT="$(ulimit -Sn)"
NOFILE_HARD="$(ulimit -Hn)"
if [ "${NOFILE_SOFT}" = "unlimited" ] || [ "${NOFILE_SOFT}" -gt 65536 ] 2>/dev/null; then
  ulimit -Sn 65536 || true
fi
if [ "${NOFILE_HARD}" = "unlimited" ] || [ "${NOFILE_HARD}" -gt 1048576 ] 2>/dev/null; then
  ulimit -Hn 1048576 || true
fi

: "${VNC_PASSWD:=}"
: "${SNOWLUMA_ONEBOT_HOST:=0.0.0.0}"
: "${SNOWLUMA_UID:=1000}"
: "${SNOWLUMA_GID:=1000}"
: "${SNOWLUMA_HOME:=/app/runtime}"
: "${SNOWLUMA_DATA:=/app/data}"
: "${SNOWLUMA_WEBUI_PORT:=5099}"
: "${SNOWLUMA_LOG_LEVEL:=info}"
: "${SNOWLUMA_SCREEN:=1920x1080x24}"
: "${SNOWLUMA_HOOK_AUTOLOAD:=1}"
: "${SNOWLUMA_EXTRA_QQ_HOMES:=}"
: "${SNOWLUMA_QQ_FLAGS:=--disable-gpu --disable-software-rasterizer --disable-gpu-compositing}"

export DISPLAY="${DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-${SNOWLUMA_UID}}"
export SNOWLUMA_HOOK_RUNTIME_DIR="${SNOWLUMA_HOOK_RUNTIME_DIR:-${XDG_RUNTIME_DIR}}"
export SNOWLUMA_LOG_LEVEL SNOWLUMA_HOOK_AUTOLOAD SNOWLUMA_EXTRA_QQ_HOMES SNOWLUMA_QQ_FLAGS
export SNOWLUMA_ONEBOT_HOST VNC_PASSWD

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
  local persistent="${SNOWLUMA_DATA}/config/machine-id"

  mkdir -p "$(dirname "$persistent")" || { echo "FATAL: cannot create machine-id persistent directory" >&2; exit 1; }

  if [ ! -f "$persistent" ]; then
    dbus-uuidgen > "$persistent" || { echo "FATAL: dbus-uuidgen failed to generate machine-id" >&2; exit 1; }
  fi

  ln -sf "$persistent" /etc/machine-id || { echo "FATAL: cannot symlink machine-id" >&2; exit 1; }
}

ensure_machine_id

groupmod -o -g "${SNOWLUMA_GID}" snowluma
usermod -o -u "${SNOWLUMA_UID}" -g "${SNOWLUMA_GID}" snowluma

# Only persistent state follows the configurable account. Recursively changing
# ownership of bundled application trees would copy hundreds of megabytes into
# the container writable layer on every first start.
chown "${SNOWLUMA_UID}:${SNOWLUMA_GID}" /app
chown -R "${SNOWLUMA_UID}:${SNOWLUMA_GID}" \
  "${SNOWLUMA_DATA}" \
  /app/.cache \
  /app/.config \
  /app/.local/share \
  "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"

# Docker restart can preserve stale AF_UNIX socket nodes in the container
# writable layer. Remove them before QQ starts so PID reuse cannot make a dead
# hook socket look like a live SnowLuma injection.
find "${XDG_RUNTIME_DIR}" -maxdepth 1 -type s -name 'mojo.*.*.sock' -delete 2>/dev/null || true

# Freeze the bundled QQ version. QQ has two update paths: the "立即更新" full-update
# dialog (click-gated -> never fires headless) and a SILENT hot-update channel
# (hotUpdateApi -> qqpatch.gtimg.cn) that swaps QQ files in the background. Only
# the silent one can change bytes without us, which would break the version-pinned
# nnphook. Black-hole that single host so the hot-update download can never land.
# QQ's main-process hot-update resolves via getaddrinfo, which honours /etc/hosts;
# Docker writes /etc/hosts once at container start and never rewrites it after, so
# this append is durable for the container's lifetime. Runs as root before QQ.
if ! grep -q 'qqpatch\.gtimg\.cn' /etc/hosts 2>/dev/null; then
  printf '0.0.0.0 qqpatch.gtimg.cn\n' >> /etc/hosts
fi

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
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const dataDir = process.env.SNOWLUMA_DATA || '/app/data';
const configDir = path.join(dataDir, 'config');
const runtimeConfigPath = path.join(configDir, 'runtime.json');
const vncPasswordPath = path.join(configDir, 'vnc-password');
const requestedPort = Number(process.env.SNOWLUMA_WEBUI_PORT || 5099);
const webuiPort = Number.isInteger(requestedPort) && requestedPort > 0 && requestedPort <= 65535
  ? requestedPort
  : 5099;
const onebotHost = (process.env.SNOWLUMA_ONEBOT_HOST || '0.0.0.0').trim() || '0.0.0.0';
const KNOWN_VNC_DEFAULT = 'vncpasswd';
const LOOPBACK = new Set(['', '127.0.0.1', '::1', 'localhost']);

fs.mkdirSync(configDir, { recursive: true });

let runtimeConfig = {};
try {
  runtimeConfig = JSON.parse(fs.readFileSync(runtimeConfigPath, 'utf8'));
} catch {
  runtimeConfig = {};
}

runtimeConfig.webuiPort = webuiPort;
// The application default is loopback-only. A container must bind its own
// network namespace on all interfaces for an explicitly published host port
// to work. Seed this once, but preserve every later WebUI/operator choice.
if (typeof runtimeConfig.webuiHost !== 'string' || !runtimeConfig.webuiHost.trim()) {
  runtimeConfig.webuiHost = '0.0.0.0';
}
fs.writeFileSync(runtimeConfigPath, `${JSON.stringify(runtimeConfig, null, 2)}\n`, 'utf8');

function isLoopbackHost(host) {
  return LOOPBACK.has(String(host ?? '').trim().toLowerCase());
}

function newAccessToken() {
  return crypto.randomBytes(32).toString('base64url');
}

function seedOneBotFile(filePath) {
  let existed = true;
  let cfg = {};
  try {
    cfg = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    existed = false;
    cfg = {};
  }
  if (!cfg || typeof cfg !== 'object' || Array.isArray(cfg)) {
    existed = false;
    cfg = {};
  }
  if (!cfg.networks || typeof cfg.networks !== 'object' || Array.isArray(cfg.networks)) {
    cfg.networks = {};
  }
  const nets = cfg.networks;
  let changed = !existed;

  const bindPublishedHost = (adapter) => {
    if (!adapter || typeof adapter !== 'object') return false;
    if (!isLoopbackHost(adapter.host)) return false;
    adapter.host = onebotHost;
    return true;
  };

  // First boot only: missing file gets the published HTTP/WS listeners.
  // An existing empty list means the operator removed those adapters;
  // do not put them back on every container recreate.
  const ensureServers = (key, fallback) => {
    if (!Array.isArray(nets[key])) {
      if (!existed) {
        nets[key] = [fallback];
        changed = true;
      }
      return;
    }
    if (nets[key].length === 0) return;
    for (const adapter of nets[key]) {
      if (bindPublishedHost(adapter)) changed = true;
    }
  };

  ensureServers('httpServers', {
    name: 'http-default',
    host: onebotHost,
    port: 3000,
    path: '/',
    accessToken: newAccessToken(),
    messageFormat: 'array',
    reportSelfMessage: false,
  });
  ensureServers('wsServers', {
    name: 'ws-default',
    host: onebotHost,
    port: 3001,
    path: '/',
    role: 'Universal',
    accessToken: newAccessToken(),
    messageFormat: 'array',
    reportSelfMessage: false,
  });
  if (!existed) {
    if (!Array.isArray(nets.httpClients)) nets.httpClients = [];
    if (!Array.isArray(nets.wsClients)) nets.wsClients = [];
  }

  if (changed) fs.writeFileSync(filePath, `${JSON.stringify(cfg, null, 2)}\n`, 'utf8');
}

seedOneBotFile(path.join(configDir, 'onebot.json'));
for (const name of fs.readdirSync(configDir)) {
  if (/^onebot_.+\.json$/i.test(name)) {
    seedOneBotFile(path.join(configDir, name));
  }
}

function isKnownVncPassword(value) {
  return !value || value === KNOWN_VNC_DEFAULT;
}

let envPass = String(process.env.VNC_PASSWD || '').trim();
let filePass = '';
try {
  filePass = fs.readFileSync(vncPasswordPath, 'utf8').trim();
} catch {
  filePass = '';
}

let vncPass;
let announceVnc = false;
if (!isKnownVncPassword(envPass)) {
  vncPass = envPass;
  announceVnc = isKnownVncPassword(filePass) || filePass !== vncPass;
} else if (!isKnownVncPassword(filePass)) {
  vncPass = filePass;
} else {
  vncPass = crypto.randomBytes(15).toString('base64url');
  announceVnc = true;
}

fs.writeFileSync(vncPasswordPath, `${vncPass}\n`, { mode: 0o600 });
fs.chmodSync(vncPasswordPath, 0o600);
if (announceVnc) {
  console.log(`远程桌面密码: ${vncPass}`);
  console.log(`remote desktop password: ${vncPass}`);
}
NODE
# Node.js block above ran as root, so application JSON is owned by root.
# SnowLuma runs as snowluma and needs write access to its config files.
# The remote-desktop password file stays root-only.
chown "${SNOWLUMA_UID}:${SNOWLUMA_GID}" "${SNOWLUMA_DATA}/config" \
  "${SNOWLUMA_DATA}/config/runtime.json" \
  "${SNOWLUMA_DATA}/config/onebot.json"
if ls "${SNOWLUMA_DATA}/config"/onebot_*.json >/dev/null 2>&1; then
  chown "${SNOWLUMA_UID}:${SNOWLUMA_GID}" "${SNOWLUMA_DATA}/config"/onebot_*.json
fi
chown root:root "${SNOWLUMA_DATA}/config/vnc-password"
chmod 600 "${SNOWLUMA_DATA}/config/vnc-password"

VNC_STORE_PASS="$(tr -d '\n' < "${SNOWLUMA_DATA}/config/vnc-password")"
x11vnc -storepasswd "${VNC_STORE_PASS}" /root/.vnc/passwd >/dev/null
unset VNC_STORE_PASS

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
x11vnc -display "${DISPLAY}" -noxrecord -noxfixes -noxdamage -forever -threads -rfbauth /root/.vnc/passwd &
X11VNC_PID=$!
sleep 0.5
if ! kill -0 "${X11VNC_PID}" 2>/dev/null; then
  echo "x11vnc failed to start for display ${DISPLAY}." >&2
  exit 1
fi

nohup /opt/noVNC/utils/novnc_proxy --vnc localhost:5900 --listen 6081 --file-only >/var/log/novnc.log 2>&1 &

exec supervisord -c /etc/supervisord.conf
