#!/usr/bin/env bash
# SnowLuma Linux installer — official, first-party.
# Interactive (TTY) or flags. Safe to run from a one-liner without cloning.
set -euo pipefail

INSTALLER_REPO="${SNOWLUMA_INSTALLER_REPO:-SnowLuma/SnowLuma.Docker.Framework}"
INSTALLER_REF="${SNOWLUMA_INSTALLER_REF:-main}"

_src="${BASH_SOURCE[0]:-}"
if [[ -n "${_src}" && -f "${_src}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${_src}")" && pwd)"
else
  SCRIPT_DIR=""
fi
TEMPLATE_DIR=""

MODE="${MODE:-}"
INSTALL_DIR="${INSTALL_DIR:-}"
BOT_NETWORK="${SNOWLUMA_BOT_NETWORK:-maim_bot}"
IMAGE="${SNOWLUMA_IMAGE:-motricseven7/snowluma:latest}"
SNOWLUMA_TAG="${SNOWLUMA_TAG:-}"
DRY_RUN=0
ASSUME_YES=0
SKIP_PROBE=0
NO_COLOR="${NO_COLOR:-}"

QQ_VERSION="3.2.32_260812"
QQ_CHANNEL="3f89efc5"
QQ_BASE_URL="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.33/release/${QQ_CHANNEL}"
QQ_MIRROR_URL="https://github.com/Rodert/qq-versions/releases/download/qq-packages-20260813-1d08f1d4"
QQ_AMD64_SHA256="d085dd89397225061eb9f194308f688129818ed445777e97a4a0a16e13d7b0e8"
QQ_ARM64_SHA256="8796ccfd66acc025ef18db37185532d40bc8c58921e17da6d28c295acbcf8f92"
NODE_DIST_VERSION="v24.21.0"

OS_ID=""
OS_LIKE=""
OS_VERSION_ID=""
ARCH=""
PKG=""
DOCKER_ARCH=""
LITE_ARCH=""
QQ_ARCH=""

usage() {
  cat <<'EOF'
SnowLuma Linux 安装器（官方）

一条命令（交互会问模式；不克隆仓库）:
  curl -fsSL https://raw.githubusercontent.com/SnowLuma/SnowLuma.Docker.Framework/main/install.sh | bash

带参数:
  curl -fsSL https://raw.githubusercontent.com/SnowLuma/SnowLuma.Docker.Framework/main/install.sh | bash -s -- --mode docker --yes
  curl -fsSL https://raw.githubusercontent.com/SnowLuma/SnowLuma.Docker.Framework/main/install.sh | bash -s -- --mode compose --network maim_bot --yes

仓库里也可以:
  ./install.sh
  ./install.sh --mode docker --yes

模式:
  docker    独立官方镜像（空机器 / 空 VPS）
  compose   sidecar，加入已有机器人 compose 网络，不改对方文件
  host      进阶：本机安装 QQ + SnowLuma，不用 Docker（非官方支持）

选项:
  --mode NAME        docker | compose | host（--yes 且未指定时默认 docker）
  --dir PATH         写入目录（docker/compose 默认 ~/snowluma，host 默认 /opt/snowluma）
  --network NAME     compose 模式要加入的外部网络（默认 maim_bot）
  --image REF        镜像（默认 motricseven7/snowluma:latest）
  --tag TAG          host 模式拉取的 SnowLuma lite 版本（如 v1.14.15）
  --yes, -y          非交互
  --dry-run          只打印将要做的事
  --skip-probe       跳过出网探测
  -h, --help
EOF
}

# ── UI ──────────────────────────────────────────────────────────

if [[ -z "${NO_COLOR}" && -t 1 && "${TERM:-dumb}" != dumb ]]; then
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_CYAN=$'\033[36m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_BLUE=$'\033[34m'
else
  C_RESET="" C_DIM="" C_BOLD="" C_CYAN="" C_GREEN="" C_YELLOW="" C_RED="" C_BLUE=""
fi

have() { command -v "$1" >/dev/null 2>&1; }
prompt_src() {
  if [[ -t 0 ]]; then printf '%s\n' /dev/stdin
  elif [[ -c /dev/tty ]]; then printf '%s\n' /dev/tty
  else printf '\n'
  fi
}

log() { printf '%s\n' "$*"; }
err() { printf '%s错误:%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; }
die() { err "$*"; exit 1; }
ok() { printf '  %s✓%s %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
warn() { printf '  %s!%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
fail_line() { printf '  %s✗%s %s\n' "${C_RED}" "${C_RESET}" "$*"; }
step() { printf '\n%s▸%s %s%s%s\n' "${C_CYAN}" "${C_RESET}" "${C_BOLD}" "$*" "${C_RESET}"; }
note() { printf '  %s%s%s\n' "${C_DIM}" "$*" "${C_RESET}"; }

banner() {
  printf '%s\n' "${C_CYAN}${C_BOLD}"
  cat <<'EOF'
  ┌──────────────────────────────────────────┐
  │           SnowLuma  Linux 安装器          │
  │      协议端 · 官方镜像 / sidecar / 本机     │
  └──────────────────────────────────────────┘
EOF
  printf '%s' "${C_RESET}"
}

confirm() {
  local prompt="$1"
  local src reply
  if [[ "${ASSUME_YES}" -eq 1 ]]; then return 0; fi
  src="$(prompt_src)"
  [[ -n "${src}" ]] || die '非交互环境请加上 --yes'
  if have gum && [[ -t 0 && -t 1 ]]; then gum confirm "${prompt}"; return; fi
  printf '%s [y/N] ' "${prompt}"
  read -r reply <"${src}" || true
  [[ "${reply}" == [yY] || "${reply}" == yes || "${reply}" == 是 ]]
}

choose_from() {
  local header="$1"
  shift
  local items=("$@")
  local i choice src
  if have gum && [[ -t 0 && -t 1 ]]; then
    gum choose --header "${header}" "${items[@]}"
    return
  fi
  src="$(prompt_src)"
  [[ -n "${src}" ]] || die '非交互环境请指定 --mode，并加上 --yes'
  log "${header}"
  i=1
  for it in "${items[@]}"; do
    printf '  %s) %s\n' "${i}" "${it}"
    i=$((i + 1))
  done
  printf '选择 [1]: '
  read -r choice <"${src}" || true
  if [[ -z "${choice}" ]]; then
    printf '%s\n' "${items[0]}"
    return
  fi
  if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
    printf '%s\n' "${items[$((choice - 1))]}"
    return
  fi
  printf '%s\n' "${choice}"
}

run_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif have sudo; then
    sudo "$@"
  else
    die "需要 root 才能执行: $*"
  fi
}

run_as_user() {
  local user="$1"
  shift
  if [[ "$(id -u)" -eq 0 ]]; then
    if have runuser; then runuser -u "${user}" -- "$@"
    else su -s /bin/bash -c "$(printf '%q ' "$@")" "${user}"
    fi
  else
    sudo -u "${user}" "$@"
  fi
}

# ── retry / download ────────────────────────────────────────────

retry() {
  local attempts="$1" delay="$2"
  shift 2
  local n=1
  while true; do
    if "$@"; then return 0; fi
    if (( n >= attempts )); then return 1; fi
    warn "第 ${n}/${attempts} 次失败，${delay}s 后重试"
    sleep "${delay}"
    delay=$((delay * 2))
    if (( delay > 30 )); then delay=30; fi
    n=$((n + 1))
  done
}

curl_get() {
  curl -fL --retry 2 --retry-delay 2 --connect-timeout 8 --max-time 120 \
    -A 'SnowLuma-Installer' "$@"
}

download_to() {
  local dest="$1"
  shift
  local url
  for url in "$@"; do
    note "GET ${url}"
    if retry 3 2 curl_get -o "${dest}" "${url}"; then
      ok "下载完成"
      return 0
    fi
    warn "失败: ${url}"
  done
  return 1
}

github_urls() {
  local rest="$1"
  printf '%s\n' \
    "https://ghfast.top/https://github.com/${rest}" \
    "https://gh-proxy.com/https://github.com/${rest}" \
    "https://gh.llkk.cc/https://github.com/${rest}" \
    "https://github.com/${rest}"
}

sha256_file() {
  if have sha256sum; then sha256sum "$1" | awk '{print $1}'
  elif have shasum; then shasum -a 256 "$1" | awk '{print $1}'
  else die '本机没有 sha256sum / shasum，无法校验下载。'
  fi
}

verify_sha256() {
  local file="$1" expect="$2"
  local got
  got="$(sha256_file "${file}")"
  if [[ "${got}" != "${expect}" ]]; then
    fail_line "校验失败 ${file}"
    note "期望 ${expect}"
    note "实际 ${got}"
    return 1
  fi
  ok "校验通过"
}

# ── OS ──────────────────────────────────────────────────────────

detect_os() {
  ARCH="$(uname -m)"
  case "${ARCH}" in
    x86_64|amd64) DOCKER_ARCH=amd64; LITE_ARCH=x64; QQ_ARCH=amd64; ARCH=x86_64 ;;
    aarch64|arm64) DOCKER_ARCH=arm64; LITE_ARCH=arm64; QQ_ARCH=arm64; ARCH=aarch64 ;;
    *) die "不支持的架构 ${ARCH}。只要 x86_64 / aarch64。" ;;
  esac
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_LIKE="${ID_LIKE:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
  else
    die '读不到 /etc/os-release。'
  fi
  case "${OS_ID}" in
    ubuntu|debian|linuxmint|uos|kylin) PKG=apt ;;
    fedora) PKG=dnf ;;
    rhel|centos|rocky|almalinux|ol) PKG=dnf ;;
    opencloudos|openeuler|anolis) PKG=dnf ;;
    arch|manjaro) PKG=pacman ;;
    alpine) die 'Alpine / musl 不支持。请换 glibc 发行版，或改用 Docker 模式。' ;;
    *)
      case " ${OS_LIKE} " in
        *' debian '*) PKG=apt ;;
        *' rhel '*|*' fedora '*|*' centos '*) PKG=dnf ;;
        *' arch '*) PKG=pacman ;;
        *) die "未适配发行版 ID=${OS_ID} ID_LIKE=${OS_LIKE}。请用 Docker 模式或开 issue。" ;;
      esac
      ;;
  esac
}

pkg_install() {
  case "${PKG}" in
    apt)
      run_root env DEBIAN_FRONTEND=noninteractive apt-get update -y
      run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
      ;;
    dnf) run_root dnf install -y "$@" ;;
    pacman) run_root pacman -Sy --noconfirm "$@" ;;
    *) die "未知包管理器 ${PKG}" ;;
  esac
}

mem_kb() { awk '/MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null || echo 0; }
disk_kb() {
  df -Pk "${INSTALL_DIR:-/}" 2>/dev/null | awk 'NR==2 { print $4; exit }' || echo 0
}

port_in_use() {
  local p="$1"
  if have ss; then ss -ltn 2>/dev/null | grep -qE ":${p}[[:space:]]"; return; fi
  if have lsof; then lsof -nP -iTCP:"${p}" -sTCP:LISTEN >/dev/null 2>&1; return; fi
  return 1
}

panel_kind() {
  if have 1pctl || [[ -d /opt/1panel ]] || systemctl is-active --quiet 1panel 2>/dev/null; then
    printf '1panel'
    return
  fi
  if [[ -x /etc/init.d/bt || -d /www/server/panel ]]; then
    printf 'baota'
    return
  fi
  printf ''
}

# ── probes ──────────────────────────────────────────────────────

probe_http() {
  local name="$1" url="$2"
  if curl -fsI --connect-timeout 5 --max-time 8 -o /dev/null "${url}"; then
    ok "${name}"
    return 0
  fi
  fail_line "${name} 不通  (${url})"
  return 1
}

probe_network() {
  [[ "${SKIP_PROBE}" -eq 1 ]] && { note '已跳过出网探测'; return 0; }
  step '出网探测（失败只说明这一跳，不会立刻退出）'
  local hub_ok=0 gh_ok=0 qq_ok=0
  probe_http 'DNS/TLS 基础' 'https://www.gstatic.com/generate_204' || true
  if probe_http 'Docker Hub' 'https://registry-1.docker.io/v2/'; then hub_ok=1; fi
  if probe_http 'GitHub' 'https://github.com/'; then gh_ok=1; fi
  if probe_http 'QQ 官方包' "${QQ_BASE_URL}/"; then qq_ok=1; fi
  if [[ "${hub_ok}" -eq 0 ]]; then
    warn 'Docker Hub 不通。稍后拉镜像会改走国内前缀（1ms / 轩辕 / DaoCloud）。'
  fi
  if [[ "${gh_ok}" -eq 0 && "${MODE}" == host ]]; then
    warn 'GitHub 不通。host 模式拉 lite 包会改走 ghfast / gh-proxy。'
  fi
  if [[ "${qq_ok}" -eq 0 && "${MODE}" == host ]]; then
    warn 'QQ 官网 CDN 不通。将尝试 GitHub 上钉死的同名备份包。'
  fi
}

# ── Docker CE ───────────────────────────────────────────────────

docker_ok() {
  have docker && docker info >/dev/null 2>&1
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    printf 'docker compose'
  elif have docker-compose; then
    printf 'docker-compose'
  else
    printf ''
  fi
}

is_snap_docker() {
  docker_ok || return 1
  docker info 2>/dev/null | grep -qi 'snap' && return 0
  [[ "$(command -v docker)" == /snap/* ]] && return 0
  return 1
}

install_docker_apt() {
  local repo_id="$1"
  run_root install -m 0755 -d /etc/apt/keyrings
  local gpg=/etc/apt/keyrings/docker.asc
  download_to /tmp/docker-ce.gpg \
    "https://mirrors.aliyun.com/docker-ce/linux/${repo_id}/gpg" \
    "https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/${repo_id}/gpg" \
    "https://download.docker.com/linux/${repo_id}/gpg" \
    || die 'Docker CE 公钥下载失败（apt 仓库这一跳）。'
  run_root cp /tmp/docker-ce.gpg "${gpg}"
  run_root chmod a+r "${gpg}"
  local codename
  codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")"
  [[ -n "${codename}" ]] || die "无法识别 ${repo_id} 的 VERSION_CODENAME。"
  printf 'deb [arch=%s signed-by=%s] https://mirrors.aliyun.com/docker-ce/linux/%s %s stable\n' \
    "${DOCKER_ARCH}" "${gpg}" "${repo_id}" "${codename}" | run_root tee /etc/apt/sources.list.d/docker.list >/dev/null
  pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_dnf() {
  local releasever="${1:-}"
  local repo
  repo="$(mktemp)"
  cat >"${repo}" <<EOF
[docker-ce-stable]
name=Docker CE Stable
baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/${releasever:-\$releasever}/\$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/docker-ce/linux/centos/gpg
EOF
  run_root cp "${repo}" /etc/yum.repos.d/docker-ce.repo
  rm -f "${repo}"
  if [[ "${OS_ID}" == opencloudos || "${OS_ID}" == openeuler ]]; then
    warn "${OS_ID} 官方 Docker CE 不认这个版本号，仓库按 centos/${releasever:-8} 走。"
  fi
  run_root dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_engine() {
  if docker_ok; then
    ok 'Docker 已可用，跳过安装。'
    if is_snap_docker; then
      die '检测到 snap 版 Docker。请卸掉 snap 的 docker，改用 Docker CE 后再跑。'
    fi
    local cc
    cc="$(compose_cmd)"
    [[ -n "${cc}" ]] || die '有 docker 但没有 compose 插件。请安装 docker-compose-plugin。'
    ok "compose: ${cc}"
    return
  fi
  local panel
  panel="$(panel_kind)"
  if [[ -n "${panel}" ]]; then
    die "检测到 ${panel}，但 Docker 当前不可用。请先在面板里安装 Docker。本脚本不会在面板机器上重装 Docker，也不会改 daemon.json。"
  fi
  confirm '未检测到 Docker，将用国内 Docker CE 源安装。继续？' || die '已取消。'
  step "安装 Docker CE（${OS_ID} / ${PKG}）"
  case "${PKG}" in
    apt)
      case "${OS_ID}" in
        debian) install_docker_apt debian ;;
        *) install_docker_apt ubuntu ;;
      esac
      ;;
    dnf)
      case "${OS_ID}" in
        fedora) install_docker_dnf "${OS_VERSION_ID%%.*}" ;;
        opencloudos|openeuler|anolis) install_docker_dnf 8 ;;
        *) install_docker_dnf 9 ;;
      esac
      ;;
    pacman) pkg_install docker docker-compose docker-buildx ;;
  esac
  if have systemctl; then
    run_root systemctl enable --now docker || run_root systemctl start docker || true
  fi
  if [[ "$(id -u)" -ne 0 ]] && have usermod; then
    run_root usermod -aG docker "$(id -un)" || true
    warn '已把当前用户加入 docker 组。若现在 docker info 仍失败，请重新登录后再跑一次。'
  fi
  docker_ok || {
    warn 'CE 仓库安装后 Docker 仍不可用，改走 get.docker.com --mirror Aliyun'
    local gd
    gd="$(mktemp)"
    download_to "${gd}" https://get.docker.com || die 'get.docker.com 下载失败（脚本源这一跳）。'
    run_root sh "${gd}" --mirror Aliyun
    rm -f "${gd}"
  }
  docker_ok || die 'Docker 安装结束仍不可用。请看上面的报错，不要重复管道安装来路不明的脚本。'
  ok 'Docker 可用'
}

pull_image() {
  step "拉取镜像 ${IMAGE}"
  local refs=(
    "${IMAGE}"
    "docker.1ms.run/${IMAGE#docker.io/}"
    "docker.xuanyuan.me/${IMAGE#docker.io/}"
    "docker.m.daocloud.io/${IMAGE#docker.io/}"
  )
  local ref
  for ref in "${refs[@]}"; do
    note "docker pull ${ref}"
    if retry 3 3 docker pull "${ref}"; then
      if [[ "${ref}" != "${IMAGE}" ]]; then
        docker tag "${ref}" "${IMAGE}"
        ok "已标记为 ${IMAGE}"
      else
        ok '直连拉取成功'
      fi
      return 0
    fi
    warn "这一跳失败: ${ref}"
  done
  die "镜像拉取失败。这是 Docker Hub / 镜像前缀这一跳。下一步：在云厂商或面板加镜像加速，或 docker load 离线包。"
}

# ── preflight ───────────────────────────────────────────────────

preflight() {
  step '检查机器'
  [[ "$(uname -s)" == Linux ]] || die '只支持 Linux。macOS / Windows 请看文档里的对应路径。'
  detect_os
  ok "${OS_ID} ${OS_VERSION_ID}  ${ARCH}  包管理 ${PKG}"
  local kb dk
  kb="$(mem_kb)"
  if [[ "${kb}" -gt 0 && "${kb}" -lt 1900000 ]]; then
    die "内存约 $((kb / 1024)) MB，低于 2 GB。QQ 桌面跑不起来。"
  fi
  [[ "${kb}" -gt 0 ]] && ok "内存 $((kb / 1024)) MB"
  dk="$(disk_kb)"
  if [[ "${dk}" -gt 0 && "${dk}" -lt 2500000 ]]; then
    die "可用磁盘约 $((dk / 1024)) MB，至少需要约 2.5 GB。"
  fi
  [[ "${dk}" -gt 0 ]] && ok "可用磁盘 $((dk / 1024)) MB"
  local panel
  panel="$(panel_kind)"
  [[ -n "${panel}" ]] && note "面板: ${panel}（不会改 daemon.json）"
  if [[ -f /proc/sys/kernel/yama/ptrace_scope ]]; then
    local scope
    scope="$(tr -d '[:space:]' < /proc/sys/kernel/yama/ptrace_scope)"
    if [[ "${scope}" == 3 ]]; then
      die "kernel.yama.ptrace_scope=3，注入会被内核直接拒绝。请改为 0/1/2 后再装。"
    fi
    ok "ptrace_scope=${scope}"
  fi
  if have getenforce && [[ "$(getenforce 2>/dev/null)" == Enforcing ]]; then
    warn 'SELinux Enforcing。若启动后注入失败，再查审计日志。'
  fi
  local p
  for p in 6081 5099 3000 3001; do
    if port_in_use "${p}"; then
      warn "端口 ${p} 已被占用。compose 里改对应的宿主端口，或先停掉占用进程。"
    fi
  done
}

choose_mode() {
  if [[ -n "${MODE}" ]]; then return; fi
  local picked
  picked="$(choose_from '安装模式' \
    'docker   独立官方镜像（推荐，空 VPS）' \
    'compose  接入已有 MaiBot/AstrBot 网络' \
    'host     本机安装 QQ（进阶，非官方）')"
  case "${picked}" in
    compose*) MODE=compose ;;
    host*) MODE=host ;;
    *) MODE=docker ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --mode=*) MODE="${1#*=}"; shift ;;
      --mode) MODE="${2:-}"; shift 2 ;;
      --dir=*) INSTALL_DIR="${1#*=}"; shift ;;
      --dir) INSTALL_DIR="${2:-}"; shift 2 ;;
      --network=*) BOT_NETWORK="${1#*=}"; shift ;;
      --network) BOT_NETWORK="${2:-}"; shift 2 ;;
      --image=*) IMAGE="${1#*=}"; shift ;;
      --image) IMAGE="${2:-}"; shift 2 ;;
      --tag=*) SNOWLUMA_TAG="${1#*=}"; shift ;;
      --tag) SNOWLUMA_TAG="${2:-}"; shift 2 ;;
      --yes|-y) ASSUME_YES=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --skip-probe) SKIP_PROBE=1; shift ;;
      *) die "未知参数: $1" ;;
    esac
  done
}

fetch_template_file() {
  local rel="$1" dest="$2"
  mkdir -p "$(dirname "${dest}")"
  download_to "${dest}" \
    "https://cdn.jsdelivr.net/gh/${INSTALLER_REPO}@${INSTALLER_REF}/${rel}" \
    "https://ghfast.top/https://raw.githubusercontent.com/${INSTALLER_REPO}/${INSTALLER_REF}/${rel}" \
    "https://raw.githubusercontent.com/${INSTALLER_REPO}/${INSTALLER_REF}/${rel}" \
    || die "下载模板失败: ${rel}"
}

emit_compose_standalone() {
  cat <<'YAML'
services:
  snowluma:
    image: ${SNOWLUMA_IMAGE:-motricseven7/snowluma:latest}
    container_name: ${SNOWLUMA_CONTAINER:-snowluma}
    restart: unless-stopped
    shm_size: 1gb
    ulimits:
      nofile:
        soft: 65536
        hard: 1048576
    cap_add:
      - SYS_PTRACE
    security_opt:
      - seccomp=unconfined
    environment:
      VNC_PASSWD: ${VNC_PASSWD:-}
      SNOWLUMA_ONEBOT_HOST: ${SNOWLUMA_ONEBOT_HOST:-0.0.0.0}
      SNOWLUMA_UID: ${SNOWLUMA_UID:-1000}
      SNOWLUMA_GID: ${SNOWLUMA_GID:-1000}
      SNOWLUMA_WEBUI_HOST: ${SNOWLUMA_WEBUI_HOST:-0.0.0.0}
      SNOWLUMA_WEBUI_PORT: ${SNOWLUMA_WEBUI_PORT:-5099}
      SNOWLUMA_LOG_LEVEL: ${SNOWLUMA_LOG_LEVEL:-info}
      SNOWLUMA_SCREEN: ${SNOWLUMA_SCREEN:-1920x1080x24}
      SNOWLUMA_HOOK_AUTOLOAD: ${SNOWLUMA_HOOK_AUTOLOAD:-1}
      SNOWLUMA_EXTRA_QQ_HOMES: "${SNOWLUMA_EXTRA_QQ_HOMES:-}"
      SNOWLUMA_QQ_FLAGS: "${SNOWLUMA_QQ_FLAGS:---disable-gpu --disable-software-rasterizer --disable-gpu-compositing}"
    ports:
      - "${NOVNC_PORT:-6081}:6081"
      - "${SNOWLUMA_WEBUI_HOST_PORT:-5099}:${SNOWLUMA_WEBUI_PORT:-5099}"
      - "${ONEBOT_HTTP_PORT:-3000}:3000"
      - "${ONEBOT_WS_PORT:-3001}:3001"
    volumes:
      - qq-gateway-data:/app/data
      - qq-client-config:/app/.config
      - qq-client-data:/app/.local/share

volumes:
  qq-gateway-data:
    name: qq-gateway-data
  qq-client-config:
    name: qq-client-config
  qq-client-data:
    name: qq-client-data
YAML
}

emit_compose_sidecar() {
  cat <<'YAML'
services:
  snowluma:
    image: ${SNOWLUMA_IMAGE:-motricseven7/snowluma:latest}
    container_name: ${SNOWLUMA_CONTAINER:-snowluma}
    restart: unless-stopped
    shm_size: 1gb
    ulimits:
      nofile:
        soft: 65536
        hard: 1048576
    cap_add:
      - SYS_PTRACE
    security_opt:
      - seccomp=unconfined
    environment:
      VNC_PASSWD: ${VNC_PASSWD:-}
      SNOWLUMA_ONEBOT_HOST: ${SNOWLUMA_ONEBOT_HOST:-0.0.0.0}
      SNOWLUMA_UID: ${SNOWLUMA_UID:-1000}
      SNOWLUMA_GID: ${SNOWLUMA_GID:-1000}
      SNOWLUMA_WEBUI_HOST: ${SNOWLUMA_WEBUI_HOST:-0.0.0.0}
      SNOWLUMA_WEBUI_PORT: ${SNOWLUMA_WEBUI_PORT:-5099}
      SNOWLUMA_LOG_LEVEL: ${SNOWLUMA_LOG_LEVEL:-info}
      SNOWLUMA_SCREEN: ${SNOWLUMA_SCREEN:-1920x1080x24}
      SNOWLUMA_HOOK_AUTOLOAD: ${SNOWLUMA_HOOK_AUTOLOAD:-1}
      SNOWLUMA_EXTRA_QQ_HOMES: "${SNOWLUMA_EXTRA_QQ_HOMES:-}"
      SNOWLUMA_QQ_FLAGS: "${SNOWLUMA_QQ_FLAGS:---disable-gpu --disable-software-rasterizer --disable-gpu-compositing}"
    ports:
      - "${NOVNC_PORT:-6081}:6081"
      - "${SNOWLUMA_WEBUI_HOST_PORT:-5099}:${SNOWLUMA_WEBUI_PORT:-5099}"
      - "${ONEBOT_HTTP_PORT:-3000}:3000"
      - "${ONEBOT_WS_PORT:-3001}:3001"
    volumes:
      - snowluma-gateway-data:/app/data
      - snowluma-client-config:/app/.config
      - snowluma-client-data:/app/.local/share
    networks:
      - botnet

volumes:
  snowluma-gateway-data:
    name: ${SNOWLUMA_VOLUME_PREFIX:-snowluma}-gateway-data
  snowluma-client-config:
    name: ${SNOWLUMA_VOLUME_PREFIX:-snowluma}-client-config
  snowluma-client-data:
    name: ${SNOWLUMA_VOLUME_PREFIX:-snowluma}-client-data

networks:
  botnet:
    external: true
    name: ${SNOWLUMA_BOT_NETWORK:-maim_bot}
YAML
}

ensure_templates() {
  if [[ -n "${TEMPLATE_DIR}" && -d "${TEMPLATE_DIR}" ]]; then
    return
  fi
  if [[ -n "${SCRIPT_DIR}" && -d "${SCRIPT_DIR}/templates" ]]; then
    TEMPLATE_DIR="${SCRIPT_DIR}/templates"
    return
  fi
  TEMPLATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/snowluma-templates.XXXXXX")"
  case "${MODE}" in
    compose) emit_compose_sidecar > "${TEMPLATE_DIR}/compose.sidecar.yml" ;;
    docker) emit_compose_standalone > "${TEMPLATE_DIR}/compose.yml" ;;
    host)
      local f
      mkdir -p "${TEMPLATE_DIR}/host"
      note "host 模式从 ${INSTALLER_REF} 拉取 systemd 单元"
      for f in snowluma.target snowluma-xvfb.service snowluma-wm.service \
               snowluma-vnc.service snowluma-novnc.service snowluma-qq.service snowluma.service; do
        fetch_template_file "templates/host/${f}" "${TEMPLATE_DIR}/host/${f}"
      done
      ;;
  esac
}

# ── docker / compose write ──────────────────────────────────────

default_install_dir() {
  if [[ -n "${INSTALL_DIR}" ]]; then return; fi
  if [[ "${MODE}" == host ]]; then
    INSTALL_DIR=/opt/snowluma
  else
    INSTALL_DIR="${HOME}/snowluma"
  fi
}

write_env_file() {
  local dest="$1"
  cat >"${dest}" <<EOF
SNOWLUMA_IMAGE=${IMAGE}
SNOWLUMA_CONTAINER=snowluma
SNOWLUMA_UID=$(id -u)
SNOWLUMA_GID=$(id -g)
SNOWLUMA_WEBUI_HOST=0.0.0.0
SNOWLUMA_WEBUI_PORT=5099
SNOWLUMA_WEBUI_HOST_PORT=5099
SNOWLUMA_LOG_LEVEL=info
SNOWLUMA_SCREEN=1920x1080x24
SNOWLUMA_HOOK_AUTOLOAD=1
SNOWLUMA_ONEBOT_HOST=0.0.0.0
NOVNC_PORT=6081
ONEBOT_HTTP_PORT=3000
ONEBOT_WS_PORT=3001
SNOWLUMA_BOT_NETWORK=${BOT_NETWORK}
SNOWLUMA_VOLUME_PREFIX=snowluma
EOF
}

write_stack() {
  local template dest_compose
  dest_compose="${INSTALL_DIR}/docker-compose.yml"
  ensure_templates
  if [[ "${MODE}" == compose ]]; then
    template="${TEMPLATE_DIR}/compose.sidecar.yml"
  else
    template="${TEMPLATE_DIR}/compose.yml"
  fi
  [[ -f "${template}" ]] || die "找不到模板 ${template}。"
  step "写入 ${INSTALL_DIR}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    note "将复制 ${template}"
    note "镜像 ${IMAGE}  网络 ${BOT_NETWORK}"
    return
  fi
  mkdir -p "${INSTALL_DIR}"
  cp "${template}" "${dest_compose}"
  if [[ ! -f "${INSTALL_DIR}/.env" ]]; then
    write_env_file "${INSTALL_DIR}/.env"
  fi
  ok "docker-compose.yml + .env"
}

compose_up() {
  local cc
  cc="$(compose_cmd)"
  [[ -n "${cc}" ]] || die '没有 docker compose。'
  if [[ "${MODE}" == compose ]]; then
    if ! docker network inspect "${BOT_NETWORK}" >/dev/null 2>&1; then
      die "找不到外部网络 ${BOT_NETWORK}。先把机器人那一套 compose 拉起来，或 docker network ls 后把 --network 换成实际名字。"
    fi
    ok "外部网络 ${BOT_NETWORK}"
  fi
  if docker ps -a --format '{{.Names}}' | grep -qx snowluma; then
    confirm '已有名为 snowluma 的容器。删除并重建？（数据卷会保留）' || die '已取消。'
    docker rm -f snowluma >/dev/null
  fi
  step '启动 compose'
  (cd "${INSTALL_DIR}" && ${cc} --env-file .env up -d)
  ok '容器已拉起'
}

print_docker_next() {
  local name="snowluma"
  if [[ -f "${INSTALL_DIR}/.env" ]]; then
    name="$(awk -F= '/^SNOWLUMA_CONTAINER=/{print $2; exit}' "${INSTALL_DIR}/.env")"
    name="${name:-snowluma}"
  fi
  log
  printf '%s下一步%s\n' "${C_BOLD}" "${C_RESET}"
  log "  目录   ${INSTALL_DIR}"
  log "  noVNC  http://<主机IP>:6081/"
  log "  WebUI  http://<主机IP>:5099/"
  if [[ "${MODE}" == compose ]]; then
    log "  正向WS ws://snowluma:3001   （在机器人容器里用服务名 snowluma）"
    log "  反向WS 把 SnowLuma 配到 ws://<机器人服务>:端口/路径"
  fi
  log
  log "  密码（远程桌面 / WebUI 临时）："
  log "    docker logs ${name} 2>&1 | grep -E '远程桌面密码:|remote desktop password:|临时密码|initial credentials' | tail -n 8"
}

# ── host mode ───────────────────────────────────────────────────

need_host_packages() {
  case "${PKG}" in
    apt)
      local alsa=libasound2
      if have apt-cache && apt-cache show libasound2t64 >/dev/null 2>&1; then alsa=libasound2t64; fi
      printf '%s\n' curl ca-certificates tar xz-utils dbus-x11 xvfb x11vnc fluxbox \
        novnc websockify "${alsa}" libnss3 libgtk-3-0 libgbm1 libdrm2 libxkbcommon0 \
        libxdamage1 libxshmfence1 fontconfig fonts-noto-cjk fonts-wqy-zenhei \
        libcap2-bin procps iproute2
      ;;
    dnf)
      printf '%s\n' curl ca-certificates tar xz dbus-x11 xorg-x11-server-Xvfb x11vnc fluxbox \
        alsa-lib nss gtk3 libgbm libdrm libxkbcommon libXdamage fontconfig google-noto-sans-cjk-fonts \
        libcap procps-ng iproute
      ;;
    pacman)
      printf '%s\n' curl ca-certificates tar xz dbus xorg-server-xvfb x11vnc fluxbox \
        libpulse nss gtk3 mesa libdrm libxkbcommon fontconfig noto-fonts-cjk libcap procps-ng iproute2
      ;;
  esac
}

find_novnc() {
  local c
  for c in /usr/share/novnc/utils/novnc_proxy /usr/share/novnc/utils/launch.sh /usr/bin/novnc_proxy; do
    if [[ -x "${c}" ]]; then printf '%s' "${c}"; return 0; fi
  done
  if have websockify && [[ -d /usr/share/novnc ]]; then
    printf 'websockify'
    return 0
  fi
  return 1
}

install_node_host() {
  if have node; then
    local major
    major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
    if [[ "${major}" -ge 24 ]]; then
      ok "已有 Node $(node -v)"
      printf '%s' "$(readlink -f "$(command -v node)")"
      return
    fi
    warn "已有 Node $(node -v)，低于 24，将安装官方二进制 ${NODE_DIST_VERSION}"
  fi
  local tarball="node-${NODE_DIST_VERSION}-linux-${LITE_ARCH}.tar.xz"
  local dest=/tmp/${tarball}
  local prefix=/usr/local
  download_to "${dest}" \
    "https://npmmirror.com/mirrors/node/${NODE_DIST_VERSION}/${tarball}" \
    "https://mirrors.tuna.tsinghua.edu.cn/nodejs-release/${NODE_DIST_VERSION}/${tarball}" \
    "https://nodejs.org/dist/${NODE_DIST_VERSION}/${tarball}" \
    || die 'Node 二进制下载失败（npmmirror / TUNA / nodejs.org 这一跳）。'
  run_root tar -xJf "${dest}" -C /usr/local --strip-components=1
  rm -f "${dest}"
  have node || die 'Node 解压后仍不在 PATH。'
  ok "Node $(node -v)"
  printf '%s' "$(readlink -f "$(command -v node)")"
}

install_qq_host() {
  if [[ -x /opt/QQ/qq ]]; then
    ok '已有 /opt/QQ/qq'
    return
  fi
  local pkg sha url_main url_mirror
  sha="${QQ_AMD64_SHA256}"
  [[ "${QQ_ARCH}" == arm64 ]] && sha="${QQ_ARM64_SHA256}"
  if [[ "${PKG}" == apt ]]; then
    pkg="QQ_${QQ_VERSION}_${QQ_ARCH}_01.deb"
  else
    local rpm_arch=x86_64
    [[ "${QQ_ARCH}" == arm64 ]] && rpm_arch=aarch64
    pkg="QQ_${QQ_VERSION}_${rpm_arch}_01.rpm"
  fi
  url_main="${QQ_BASE_URL}/${pkg}"
  url_mirror="${QQ_MIRROR_URL}/${pkg}"
  local tmp=/tmp/${pkg}
  download_to "${tmp}" "${url_main}" "${url_mirror}" \
    || die "Linux QQ 包下载失败。官网 CDN 和钉死的备份都没拿到 ${pkg}。"
  verify_sha256 "${tmp}" "${sha}" || die 'Linux QQ 包校验失败，已中止（不要强装）。'
  step '安装 Linux QQ'
  if [[ "${PKG}" == apt ]]; then
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${tmp}" \
      || run_root env DEBIAN_FRONTEND=noninteractive apt-get -f install -y
  else
    run_root rpm -Uvh --force "${tmp}" || run_root dnf install -y "${tmp}"
  fi
  [[ -x /opt/QQ/qq ]] || die 'QQ 安装后找不到 /opt/QQ/qq。'
  ok '/opt/QQ/qq'
  rm -f "${tmp}"
}

freeze_qq_update() {
  if grep -q 'qqpatch\.gtimg\.cn' /etc/hosts 2>/dev/null; then
    ok '已冻结静默更新域名'
    return
  fi
  printf '0.0.0.0 qqpatch.gtimg.cn\n' | run_root tee -a /etc/hosts >/dev/null
  ok '已写入 qqpatch.gtimg.cn 黑洞'
}

latest_lite_tag() {
  if [[ -n "${SNOWLUMA_TAG}" ]]; then
    printf '%s' "${SNOWLUMA_TAG}"
    return
  fi
  local json tmp
  tmp="$(mktemp)"
  if download_to "${tmp}" \
    "https://ghfast.top/https://api.github.com/repos/SnowLuma/SnowLuma/releases/latest" \
    "https://gh-proxy.com/https://api.github.com/repos/SnowLuma/SnowLuma/releases/latest" \
    "https://api.github.com/repos/SnowLuma/SnowLuma/releases/latest"; then
    SNOWLUMA_TAG="$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' "${tmp}" | head -n 1)"
  fi
  rm -f "${tmp}"
  [[ -n "${SNOWLUMA_TAG}" ]] || die '无法确定 lite 包版本。请加 --tag vX.Y.Z。'
  printf '%s' "${SNOWLUMA_TAG}"
}

install_lite() {
  local tag asset dest
  tag="$(latest_lite_tag)"
  asset="SnowLuma-${tag}-linux-${LITE_ARCH}-lite.tar.gz"
  dest="/tmp/${asset}"
  step "下载 SnowLuma ${tag} lite"
  local rest="SnowLuma/SnowLuma/releases/download/${tag}/${asset}"
  # shellcheck disable=SC2046
  download_to "${dest}" $(github_urls "${rest}") \
    || die "lite 包下载失败（GitHub / 加速前缀这一跳）。文件名 ${asset}"
  mkdir -p "${INSTALL_DIR}/runtime" "${INSTALL_DIR}/data"
  tar -xzf "${dest}" -C "${INSTALL_DIR}/runtime" --strip-components=1 2>/dev/null \
    || tar -xzf "${dest}" -C "${INSTALL_DIR}/runtime"
  rm -f "${dest}"
  [[ -f "${INSTALL_DIR}/runtime/index.mjs" ]] || die 'lite 包解开后没有 index.mjs。'
  ok "runtime ${INSTALL_DIR}/runtime"
}

ensure_snowluma_user() {
  if id snowluma >/dev/null 2>&1; then
    ok '用户 snowluma 已存在'
  else
    run_root useradd --system --create-home --home-dir /var/lib/snowluma/qq \
      --shell /usr/sbin/nologin snowluma
    ok '已创建用户 snowluma'
  fi
  run_root mkdir -p /var/lib/snowluma/qq /var/lib/snowluma/vnc \
    "${INSTALL_DIR}/runtime" "${INSTALL_DIR}/data"
  run_root chown -R snowluma:snowluma /var/lib/snowluma "${INSTALL_DIR}"
}

write_host_vnc_password() {
  local pass file
  file=/var/lib/snowluma/vnc/passwd
  pass="$(openssl rand -hex 10 2>/dev/null || true)"
  [[ -n "${pass}" ]] || pass="$(dd if=/dev/urandom bs=10 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  run_root mkdir -p /var/lib/snowluma/vnc
  run_root chmod 700 /var/lib/snowluma/vnc
  printf '%s\n' "${pass}" | run_root tee /var/lib/snowluma/vnc/password.txt >/dev/null
  run_root chmod 600 /var/lib/snowluma/vnc/password.txt
  run_root chown snowluma:snowluma /var/lib/snowluma/vnc/password.txt
  run_as_user snowluma x11vnc -storepasswd "${pass}" "${file}" >/dev/null
  run_root chown snowluma:snowluma "${file}"
  printf '%s\n' "${C_BOLD}远程桌面密码: ${pass}${C_RESET}"
  printf '%s\n' "remote desktop password: ${pass}"
}

install_host_units() {
  ensure_templates
  local unit_dir="${TEMPLATE_DIR}/host"
  [[ -d "${unit_dir}" ]] || die "找不到 ${unit_dir}"
  local novnc node_bin
  novnc="$(find_novnc)" || die '找不到 noVNC 启动器。Debian/Ubuntu 包名 novnc；其它发行版请自行确认路径。'
  if [[ "${novnc}" == websockify ]]; then
    novnc="/usr/bin/websockify --web=/usr/share/novnc 6081 localhost:5900"
  fi
  node_bin="$(readlink -f "$(command -v node)")"
  local f dest
  for f in snowluma.target snowluma-xvfb.service snowluma-wm.service \
           snowluma-vnc.service snowluma-novnc.service snowluma-qq.service snowluma.service; do
    dest="/etc/systemd/system/${f}"
    run_root sed \
      -e "s|__QQ_HOME__|/var/lib/snowluma/qq|g" \
      -e "s|__VNC_AUTH__|/var/lib/snowluma/vnc/passwd|g" \
      -e "s|__NOVNC_BIN__|${novnc}|g" \
      -e "s|__NODE_BIN__|${node_bin}|g" \
      -e "s|__RUNTIME__|${INSTALL_DIR}/runtime|g" \
      -e "s|__DATA__|${INSTALL_DIR}/data|g" \
      "${unit_dir}/${f}" | run_root tee "${dest}" >/dev/null
  done
  run_root systemctl daemon-reload
  run_root systemctl enable --now snowluma.target
  ok '已 enable snowluma.target'
}

run_host() {
  if [[ "$(id -u)" -ne 0 ]] && ! have sudo; then
    die 'host 模式需要 root / sudo。'
  fi
  if ! have systemctl; then
    die 'host 模式需要 systemd。OpenRC / 无 systemd 的环境请改用 docker 模式。'
  fi
  step '安装本机依赖'
  # shellcheck disable=SC2046
  pkg_install $(need_host_packages)
  freeze_qq_update
  install_qq_host
  install_node_host >/dev/null || true
  have node || die 'Node 未安装成功。'
  ensure_snowluma_user
  install_lite
  write_host_vnc_password
  install_host_units
  log
  printf '%s下一步%s\n' "${C_BOLD}" "${C_RESET}"
  log "  这是进阶 / 非官方路径。出问题请优先改回 docker 模式。"
  log "  noVNC  http://<主机IP>:6081/"
  log "  WebUI  http://<主机IP>:5099/"
  log "  状态   systemctl status snowluma.target"
  log "  日志   journalctl -u snowluma -f"
}

# ── main ────────────────────────────────────────────────────────

parse_args "$@"
banner
if [[ -z "${MODE}" && "${ASSUME_YES}" -eq 1 ]]; then
  MODE=docker
  note '未指定 --mode，非交互默认 docker'
fi
choose_mode
case "${MODE}" in
  docker|compose|host) ;;
  *) die "未知模式: ${MODE}" ;;
esac
default_install_dir

log
note "模式 ${MODE}  ·  目录 ${INSTALL_DIR}  ·  镜像 ${IMAGE}"
[[ "${MODE}" == compose ]] && note "外部网络 ${BOT_NETWORK}"
[[ "${DRY_RUN}" -eq 1 ]] && warn 'dry-run：不会安装、不会写服务、不会拉镜像'

if [[ "${DRY_RUN}" -eq 1 ]]; then
  if [[ "$(uname -s)" == Linux && -f /etc/os-release ]]; then
    detect_os
    note "探测到 ${OS_ID} ${OS_VERSION_ID} ${ARCH} ${PKG}"
  else
    note "当前不是 Linux，dry-run 只打印步骤。"
    case "$(uname -m)" in
      x86_64|amd64) LITE_ARCH=x64 ;;
      aarch64|arm64) LITE_ARCH=arm64 ;;
      *) LITE_ARCH=x64 ;;
    esac
  fi
  if [[ "${MODE}" == docker || "${MODE}" == compose ]]; then
    write_stack
  else
    note "host 将安装：Docker 以外的 QQ、Node 24、Xvfb/VNC、lite 包、systemd 单元"
    note "QQ ${QQ_VERSION}  Node ${NODE_DIST_VERSION}  lite arch ${LITE_ARCH:-?}"
  fi
  log 'dry-run 结束。'
  exit 0
fi

preflight
probe_network

case "${MODE}" in
  docker|compose)
    install_docker_engine
    write_stack
    pull_image
    compose_up
    print_docker_next
    ;;
  host)
    warn 'host 模式是进阶路径，官方支持仍是 Docker。'
    confirm '确认在本机直接安装 QQ 和 SnowLuma？' || die '已取消。'
    run_host
    ;;
esac
