# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-bookworm-slim

ARG TARGETARCH
ARG QQ_VERSION=3.2.32_260812
ARG QQ_CHANNEL=3f89efc5
ARG QQ_BASE_URL=https://qqdl.gtimg.cn/qqfile/QQNT/9.9.33/release
ARG QQ_MIRROR_URL=https://github.com/Rodert/qq-versions/releases/download/qq-packages-20260813-1d08f1d4
ARG QQ_AMD64_SHA256=d085dd89397225061eb9f194308f688129818ed445777e97a4a0a16e13d7b0e8
ARG QQ_ARM64_SHA256=8796ccfd66acc025ef18db37185532d40bc8c58921e17da6d28c295acbcf8f92

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

# 安装基础工具和依赖（合并为一条 RUN）
RUN apt-get update && apt-get install -y --no-install-recommends \
      aria2 \
      ca-certificates \
      curl \
      dbus-user-session \
      git \
      gnutls-bin \
      iproute2 \
      libcap2-bin \
      procps \
      supervisor \
      tzdata \
      unzip \
      xdg-utils \
      ffmpeg \
      fonts-wqy-zenhei \
      libasound2 \
      libatspi2.0-0 \
      libgbm1 \
      libgtk-3-0 \
      libnotify4 \
      libnss3 \
      libsecret-1-0 \
      fluxbox \
      openbox \
      x11vnc \
      xorg \
      xvfb \
    && echo "${TZ}" > /etc/timezone \
    && ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime \
    && setcap cap_sys_ptrace+ep /usr/local/bin/node \
    && groupadd --gid 1001 snowluma \
    && useradd --no-log-init --uid 1001 --gid 1001 --home-dir /app --shell /bin/bash snowluma \
    && install -d -o snowluma -g snowluma \
      "${SNOWLUMA_HOME}" \
      "${SNOWLUMA_DATA}" \
      /app/.cache \
      /app/.config \
      /app/.local/share \
    && mkdir -p /etc/supervisor/conf.d \
    && rm -rf /var/lib/apt/lists/*

# 安装 noVNC
RUN git clone --depth=1 https://github.com/novnc/noVNC.git /opt/noVNC \
    && git clone --depth=1 https://github.com/novnc/websockify.git /opt/noVNC/utils/websockify \
    && cp /opt/noVNC/vnc.html /opt/noVNC/index.html \
    && rm -rf /tmp/* /var/tmp/*

# 安装 QQ（合并为一个 RUN）
RUN set -eux; \
    qq_arch="$(dpkg --print-architecture)"; \
    case "${qq_arch}" in \
      amd64) qq_sha="${QQ_AMD64_SHA256}" ;; \
      arm64) qq_sha="${QQ_ARM64_SHA256}" ;; \
      *) echo "Unsupported Debian architecture: ${qq_arch}" >&2; exit 1 ;; \
    esac; \
    qq_deb="QQ_${QQ_VERSION}_${qq_arch}_01.deb"; \
    apt-get update; \
    download_ok=0; \
    for qq_url in \
      "${QQ_BASE_URL}/${QQ_CHANNEL}/${qq_deb}" \
      "${QQ_MIRROR_URL}/${qq_deb}"; do \
      rm -f /tmp/linuxqq.deb; \
      case "${qq_url}" in \
        *github.com*) \
          if curl -fL --retry 3 --retry-delay 2 -A 'SnowLuma-Docker' \
              -o /tmp/linuxqq.deb "${qq_url}"; then :; else continue; fi ;; \
        *) \
          if aria2c --check-certificate=false --allow-overwrite=true \
              --auto-file-renaming=false --max-tries=3 --retry-wait=2 \
              -x16 -s16 -o /tmp/linuxqq.deb "${qq_url}"; then :; else continue; fi ;; \
      esac; \
      if echo "${qq_sha}  /tmp/linuxqq.deb" | sha256sum -c -; then \
        download_ok=1; \
        break; \
      fi; \
    done; \
    [ "${download_ok}" = 1 ]; \
    dpkg -i /tmp/linuxqq.deb || apt-get -f install -y --no-install-recommends; \
    rm -f /tmp/linuxqq.deb; \
    chmod 777 /opt/QQ

# 复制所需文件（代替 --mount=type=bind）
COPY supervisord.conf /tmp/supervisord.conf
COPY start.sh /tmp/start.sh
COPY SnowLuma.Framework.tar.gz /tmp/framework.tar.gz

# 安装 SnowLuma 框架（合并为一个 RUN）
RUN install -m 644 /tmp/supervisord.conf /etc/supervisord.conf && \
    install -m 755 /tmp/start.sh /root/start.sh && \
    tar -xzf /tmp/framework.tar.gz -C "${SNOWLUMA_HOME}" && \
    chown -R snowluma:snowluma "${SNOWLUMA_HOME}" && \
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
    rm -f /tmp/supervisord.conf /tmp/start.sh /tmp/framework.tar.gz

WORKDIR /app/data

# 在 Railway 上 EXPOSE 和 VOLUME 需要手动注释（Railway 不支持 VOLUME，使用 Railway Volumes 代替）
EXPOSE 5900 6081 5099 3000 3001

VOLUME ["/app/data", "/app/.config", "/app/.local/share"]

CMD ["/root/start.sh"]
