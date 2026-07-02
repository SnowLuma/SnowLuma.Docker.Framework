# SnowLuma.Docker.Framework

SnowLuma 的 Linux Docker 运行框架，结构参考 `NapCat.Docker.Framework`：容器内安装 Linux QQ、Xvfb、VNC/noVNC、supervisord，并运行 SnowLuma 的 Node.js 发行产物。

## 支持平台

- [x] Linux/Amd64
- [x] Linux/Arm64

## 端口

- `5900`: VNC
- `6081`: noVNC
- `5099`: SnowLuma WebUI
- `3000`: OneBot HTTP 默认端口
- `3001`: OneBot WebSocket 默认端口

## 预编译产物

这个 Docker 框架**不编译 SnowLuma 源码**，只消费 SnowLuma 主仓库 GitHub Release 上的预编译 `lite` tarball：

- `SnowLuma-<TAG>-linux-x64-lite.tar.gz`
- `SnowLuma-<TAG>-linux-arm64-lite.tar.gz`

镜像基础是 `node:22-bookworm-slim`（已自带 Node.js 运行时），所以挑 `lite` 版本，**不需要**带 `node` 二进制的完整版。

构建时把对应架构的 tarball 重命名为 `SnowLuma.Framework.tar.gz` 放到仓库根目录，Dockerfile 会 `COPY` 进去并按 `dpkg --print-architecture` 校验当前架构的 native 文件齐全。CI 与 `scripts/build-image.sh` 都会自动用 `gh release download` 拉取，无需手动操作。

## 本地构建

最简：从 SnowLuma release 自动下载并构建（默认 `linux/amd64`、`load` 到本地 Docker）：

```bash
SNOWLUMA_TAG=v1.6.35 ./scripts/build-image.sh
```

需要本机已装 [`gh` CLI](https://cli.github.com/)（用于下载 release 资产）以及 Docker buildx。

构建并推送到镜像仓库：

```bash
IMAGE=motricseven7/snowluma:v1.6.35 PUSH=1 SNOWLUMA_TAG=v1.6.35 ./scripts/build-image.sh
```

切换架构：

```bash
PLATFORM=linux/arm64 SNOWLUMA_TAG=v1.6.35 ./scripts/build-image.sh
```

> Multi-arch manifest 的合并请走 CI（`.github/workflows/docker-image.yml`）— 本地脚本只支持单平台。

如果你**手动准备** `SnowLuma.Framework.tar.gz` 放在仓库根目录，可以省略 `SNOWLUMA_TAG`，脚本会复用现有文件。

## CI 自动构建

SnowLuma 主仓库每次发 tag 都会自动派发 workflow_dispatch 到本仓库的 `docker-image.yml`，参数包含 `snowluma_tag` / `snowluma_repository`。Workflow 在 `ubuntu-22.04` 和 `ubuntu-22.04-arm` 原生 runner 上分别构建 amd64 / arm64，最后用 `docker buildx imagetools` 合并 manifest 推到 Docker Hub。

也可以在 Actions 页手动触发 `docker-publish` 工作流，对任意已发布的 SnowLuma tag 重打镜像。

## 启动

```bash
./scripts/run.sh
```

或使用已发布镜像：

```bash
docker compose up -d
```

## docker run 示例

```bash
docker run -d \
  --name snowluma \
  --restart unless-stopped \
  --shm-size=1g \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -e VNC_PASSWD=vncpasswd \
  -e SNOWLUMA_WEBUI_PORT=5099 \
  -e SNOWLUMA_QQ_FLAGS="--disable-gpu --disable-software-rasterizer --disable-gpu-compositing" \
  -e TZ=Asia/Shanghai \
  -p 5900:5900 \
  -p 6081:6081 \
  -p 5099:5099 \
  -p 3000:3000 \
  -p 3001:3001 \
  -v snowluma-data:/app/snowluma-data \
  -v snowluma-qq-config:/app/.config \
  -v snowluma-qq-data:/app/.local/share \
  motricseven7/snowluma:latest
```

## 常用命令

进入容器：

```bash
docker exec -it snowluma bash
```

查看日志：

```bash
docker logs -f snowluma
```

查看 supervisor 进程状态：

```bash
docker exec snowluma supervisorctl status
```

快速查找 SnowLuma WebUI 临时密码：

```bash
docker logs snowluma 2>&1 | grep -E "临时密码|initial credentials" | tail -n 1
```

只输出密码本身：

```bash
docker logs snowluma 2>&1 | sed -nE 's/.*(临时密码: |initial credentials: user=admin password=)([^[:space:]]+).*/\2/p' | tail -n 1
```

如果启动时自定义了容器名，请把命令里的 `snowluma` 替换成实际容器名。临时密码只会在全新的 `snowluma-data` 卷首次启动时输出一次；后续重启或复用旧卷时不会再生成新的明文密码。

noVNC 地址：

```text
http://IP:6081/
```

SnowLuma WebUI 地址：

```text
http://IP:5099/
```

SnowLuma 的配置和 OneBot 配置默认持久化在 `/app/snowluma-data/config`。

## 自动注入

镜像默认**开启**自动注入（`SNOWLUMA_HOOK_AUTOLOAD=1`）。容器一启动 SnowLuma 就把 hook 注入到 QQ 主进程，但只是被动观察；等你 VNC 进去扫码并在手机上完成登录后，hook 会自动识别真实登录状态并切到工作模式，rkeys / 好友 / 群信息会自动加载，无需在 WebUI 里手动点 Load。supervisor 把 QQ 自动重启后也是同样流程。

### 关闭自动注入

如果你想保留旧的"手动 Load"工作流：

```bash
docker run -e SNOWLUMA_HOOK_AUTOLOAD=0 ... motricseven7/snowluma:latest
```

或在 `docker-compose.yml` 里设 `SNOWLUMA_HOOK_AUTOLOAD: 0`，再或者在持久卷 `/app/snowluma-data/config/runtime.json` 里设 `"hookAutoLoad": false`。环境变量优先于 JSON 配置。

## 多开 QQ

镜像支持通过独立 `HOME` 自动拉起多个 QQ 实例。设置 `SNOWLUMA_EXTRA_QQ_HOMES` 为逗号或空格分隔的 `/app/...` 容器路径，并给每个路径挂独立持久卷：

```yaml
services:
  snowluma:
    environment:
      SNOWLUMA_EXTRA_QQ_HOMES: /app/qq-acct2,/app/qq-acct3
    volumes:
      - snowluma-data:/app/snowluma-data
      - snowluma-qq-config:/app/.config
      - snowluma-qq-data:/app/.local/share
      - snowluma-qq2:/app/qq-acct2
      - snowluma-qq3:/app/qq-acct3

volumes:
  snowluma-data:
  snowluma-qq-config:
  snowluma-qq-data:
  snowluma-qq2:
  snowluma-qq3:
```

容器启动时会为每个额外 `HOME` 生成一个 supervisor program，使用 `snowluma` 用户、同一个 `DISPLAY` 和同一组 `SNOWLUMA_QQ_FLAGS` 启动 QQ。这样 SnowLuma 进程和所有 QQ 进程同用户运行，hook 自动注入不会遇到手动 `docker exec` 误用 root 带来的权限问题。

临时手动启动第二个账号也可以：

```bash
docker exec -u snowluma -e DISPLAY=:1 -e HOME=/app/qq-acct2 -d snowluma sh -lc 'qq --no-sandbox ${SNOWLUMA_QQ_FLAGS}'
```

注意每个 QQ 实例必须独占自己的 `HOME`，不要让两个实例共用 `/app` 或同一个 `/app/qq-acctN`。

## GPU / 内存（SwiftShader 软件渲染泄漏）

容器内没有硬件 GPU，QQ（基于 Electron）的 GPU 进程会退回 SwiftShader 软件渲染。长时间停在登录界面（未扫码登录）时，SwiftShader 会不断分配且不回收内存，导致进程内存单调上涨。镜像默认通过 `SNOWLUMA_QQ_FLAGS` 给 QQ 关掉 GPU 与 SwiftShader：

```text
SNOWLUMA_QQ_FLAGS="--disable-gpu --disable-software-rasterizer --disable-gpu-compositing"
```

此时改走纯 CPU 光栅（Skia），登录二维码照常渲染、可正常扫码，只是不再有软件 GL 那条漏内存的路径。

如果你给容器做了 GPU 直通、想恢复硬件加速，把它清空或换成自己的参数：

```bash
docker run -e SNOWLUMA_QQ_FLAGS="" ... motricseven7/snowluma:latest
```

或在 `docker-compose.yml` 里设 `SNOWLUMA_QQ_FLAGS: ""`。

## 注意

SnowLuma 当前使用 native addon 对 QQ 进程进行加载，容器启动时需要 `SYS_PTRACE` 能力和 `seccomp=unconfined`。镜像内会给 `/usr/local/bin/node` 设置 `cap_sys_ptrace`，因此正常情况下不需要再修改宿主机 `kernel.yama.ptrace_scope`。请遵守第三方软件的使用许可和开源协议。
