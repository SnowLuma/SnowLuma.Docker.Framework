# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-bookworm-slim

ARG TARGETARCH
ARG QQ_VERSION=3.2.31-51102
ARG QQ_CHANNEL=c390e792
ARG QQ_BASE_URL=https://qqdl.gtimg.cn/qqfile/QQNT/9.9.32/beta

ENV DEBIAN_FRONTEND=noninteractive \
    VNC_PASSWD=vncpasswd \
    TZ=Asia/Shanghai \
    SNOWLUMA_HOME=/app/runtime \
    SNOWLUMA_DATA=/app/data \
    SNOWLUMA_WEBUI_PORT=5099 \
    SNOWLUMA_UID=1000 \
    SNOWLUMA_GID=1000 \
    SNOWLUMA_LOG_LEVEL=info \
    SNOWLUMA_SCREEN=1920x1080x24 \
    SNOWLUMA_HOOK_AUTOLOAD=1 \
    SNOWLUMA_EXTRA_QQ_HOMES="" \
    SNOWLUMA_QQ_FLAGS="--disable-gpu --disable-software-rasterizer --disable-gpu-compositing" \
    DISPLAY=:1

RUN rm -f /etc/apt/apt.conf.d/docker-clean; \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      aria2 \
      ca-certificates \
      curl \
      dbus-user-session \
      ffmpeg \
      fluxbox \
      fonts-wqy-zenhei \
      git \
      gnutls-bin \
      iproute2 \
      libasound2 \
      libatspi2.0-0 \
      libcap2-bin \
      libgbm1 \
      libgtk-3-0 \
      libnotify4 \
      libnss3 \
      libsecret-1-0 \
      openbox \
      procps \
      supervisor \
      tzdata \
      unzip \
      x11vnc \
      xdg-utils \
      xorg \
      xvfb && \
    echo "${TZ}" > /etc/timezone && \
    ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime && \
    cd /opt && git clone --depth=1 https://github.com/novnc/noVNC.git && \
    cd /opt/noVNC/utils && git clone --depth=1 https://github.com/novnc/websockify.git && \
    cp /opt/noVNC/vnc.html /opt/noVNC/index.html && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    qq_arch="$(dpkg --print-architecture)"; \
    case "${qq_arch}" in \
      amd64|arm64) ;; \
      *) echo "Unsupported Debian architecture: ${qq_arch}" >&2; exit 1 ;; \
    esac; \
    apt-get update && \
    aria2c --check-certificate=false -x16 -s16 -o /tmp/linuxqq.deb "${QQ_BASE_URL}/${QQ_CHANNEL}/linuxqq_${QQ_VERSION}_${qq_arch}.deb" && \
    (dpkg -i /tmp/linuxqq.deb || apt-get -f install -y --no-install-recommends) && \
    rm -f /tmp/linuxqq.deb && \
    chmod 777 /opt/QQ && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY SnowLuma.Framework.tar.gz /tmp/SnowLuma.Framework.tar.gz
COPY supervisord.conf /etc/supervisord.conf
COPY start.sh /root/start.sh

RUN chmod +x /root/start.sh && \
    groupadd --gid 1001 snowluma && \
    useradd --no-log-init --uid 1001 --gid 1001 --home-dir /app --shell /bin/bash snowluma && \
    mkdir -p "${SNOWLUMA_HOME}" "${SNOWLUMA_DATA}" /app/.cache /app/.config /app/.local/share /etc/supervisor/conf.d && \
    tar -xzf /tmp/SnowLuma.Framework.tar.gz -C "${SNOWLUMA_HOME}" && \
    case "$(dpkg --print-architecture)" in \
      amd64) native_arch="x64" ;; \
      arm64) native_arch="arm64" ;; \
      *) echo "Unsupported Debian architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac && \
    test -f "${SNOWLUMA_HOME}/index.mjs" && \
    test -f "${SNOWLUMA_HOME}/native/snowluma-linux-${native_arch}.node" && \
    test -f "${SNOWLUMA_HOME}/native/snowluma-linux-${native_arch}.so" && \
    test -f "${SNOWLUMA_HOME}/native/websocket-linux-${native_arch}.node" && \
    forbidden_dir="$(find "${SNOWLUMA_HOME}" -type d -iname '*snowluma*' -print -quit)" && \
    if [ -n "${forbidden_dir}" ]; then \
      echo "Framework archive contains a forbidden directory: ${forbidden_dir}" >&2; exit 1; \
    fi && \
    setcap cap_sys_ptrace+ep /usr/local/bin/node && \
    rm -f /tmp/SnowLuma.Framework.tar.gz && \
    chown -R snowluma:snowluma /app /opt/QQ

WORKDIR /app/data

EXPOSE 5900 6081 5099 3000 3001

VOLUME ["/app/data", "/app/.config", "/app/.local/share"]

CMD ["/root/start.sh"]
