# SnowLuma.Docker.Framework

SnowLuma 鐨?Linux Docker 杩愯妗嗘灦锛岀粨鏋勫弬鑰?`NapCat.Docker.Framework`锛氬鍣ㄥ唴瀹夎 Linux QQ銆乆vfb銆乂NC/noVNC銆乻upervisord锛屽苟杩愯 SnowLuma 鐨?Node.js 鍙戣浜х墿銆?
## 鏀寔骞冲彴

- [x] Linux/Amd64
- [x] Linux/Arm64

## 绔彛

- `5900`: VNC
- `6081`: noVNC
- `5099`: SnowLuma WebUI
- `3000`: OneBot HTTP 榛樿绔彛
- `3001`: OneBot WebSocket 榛樿绔彛

## 棰勭紪璇戜骇鐗?
杩欎釜 Docker 妗嗘灦**涓嶇紪璇?SnowLuma 婧愮爜**锛屽彧娑堣垂 SnowLuma 涓讳粨搴?GitHub Release 涓婄殑棰勭紪璇?`lite` tarball锛?
- `SnowLuma-<TAG>-linux-x64-lite.tar.gz`
- `SnowLuma-<TAG>-linux-arm64-lite.tar.gz`

闀滃儚鍩虹鏄?`node:22-bookworm-slim`锛堝凡鑷甫 Node.js 杩愯鏃讹級锛屾墍浠ユ寫 `lite` 鐗堟湰锛?*涓嶉渶瑕?*甯?`node` 浜岃繘鍒剁殑瀹屾暣鐗堛€?
鏋勫缓鏃舵妸瀵瑰簲鏋舵瀯鐨?tarball 閲嶅懡鍚嶄负 `SnowLuma.Framework.tar.gz` 鏀惧埌浠撳簱鏍圭洰褰曪紝Dockerfile 浼?`COPY` 杩涘幓骞舵寜 `dpkg --print-architecture` 鏍￠獙褰撳墠鏋舵瀯鐨?native 鏂囦欢榻愬叏銆侰I 涓?`scripts/build-image.sh` 閮戒細鑷姩鐢?`gh release download` 鎷夊彇锛屾棤闇€鎵嬪姩鎿嶄綔銆?
## 鏈湴鏋勫缓

鏈€绠€锛氫粠 SnowLuma release 鑷姩涓嬭浇骞舵瀯寤猴紙榛樿 `linux/amd64`銆乣load` 鍒版湰鍦?Docker锛夛細

```bash
SNOWLUMA_TAG=v1.6.35 ./scripts/build-image.sh
```

闇€瑕佹湰鏈哄凡瑁?[`gh` CLI](https://cli.github.com/)锛堢敤浜庝笅杞?release 璧勪骇锛変互鍙?Docker buildx銆?
鏋勫缓骞舵帹閫佸埌闀滃儚浠撳簱锛?
```bash
IMAGE=motricseven7/snowluma:v1.6.35 PUSH=1 SNOWLUMA_TAG=v1.6.35 ./scripts/build-image.sh
```

鍒囨崲鏋舵瀯锛?
```bash
PLATFORM=linux/arm64 SNOWLUMA_TAG=v1.6.35 ./scripts/build-image.sh
```

> Multi-arch manifest 鐨勫悎骞惰璧?CI锛坄.github/workflows/docker-image.yml`锛夆€?鏈湴鑴氭湰鍙敮鎸佸崟骞冲彴銆?
濡傛灉浣?*鎵嬪姩鍑嗗** `SnowLuma.Framework.tar.gz` 鏀惧湪浠撳簱鏍圭洰褰曪紝鍙互鐪佺暐 `SNOWLUMA_TAG`锛岃剼鏈細澶嶇敤鐜版湁鏂囦欢銆?
## CI 鑷姩鏋勫缓

SnowLuma 涓讳粨搴撴瘡娆″彂 tag 閮戒細鑷姩娲惧彂 workflow_dispatch 鍒版湰浠撳簱鐨?`docker-image.yml`锛屽弬鏁板寘鍚?`snowluma_tag` / `snowluma_repository`銆俉orkflow 鍦?`ubuntu-22.04` 鍜?`ubuntu-22.04-arm` 鍘熺敓 runner 涓婂垎鍒瀯寤?amd64 / arm64锛屾渶鍚庣敤 `docker buildx imagetools` 鍚堝苟 manifest 鎺ㄥ埌 Docker Hub銆?
涔熷彲浠ュ湪 Actions 椤垫墜鍔ㄨЕ鍙?`docker-publish` 宸ヤ綔娴侊紝瀵逛换鎰忓凡鍙戝竷鐨?SnowLuma tag 閲嶆墦闀滃儚銆?
## 鍚姩

```bash
./scripts/run.sh
```

鎴栦娇鐢ㄥ凡鍙戝竷闀滃儚锛?
```bash
docker compose up -d
```

## docker run 绀轰緥

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

## 甯哥敤鍛戒护

杩涘叆瀹瑰櫒锛?
```bash
docker exec -it snowluma bash
```

鏌ョ湅鏃ュ織锛?
```bash
docker logs -f snowluma
```

鏌ョ湅 supervisor 杩涚▼鐘舵€侊細

```bash
docker exec snowluma supervisorctl status
```

蹇€熸煡鎵?SnowLuma WebUI 涓存椂瀵嗙爜锛?
```bash
docker logs snowluma 2>&1 | grep -E "涓存椂瀵嗙爜|initial credentials" | tail -n 1
```

鍙緭鍑哄瘑鐮佹湰韬細

```bash
docker logs snowluma 2>&1 | sed -nE 's/.*(涓存椂瀵嗙爜: |initial credentials: user=admin password=)([^[:space:]]+).*/\2/p' | tail -n 1
```

濡傛灉鍚姩鏃惰嚜瀹氫箟浜嗗鍣ㄥ悕锛岃鎶婂懡浠ら噷鐨?`snowluma` 鏇挎崲鎴愬疄闄呭鍣ㄥ悕銆備复鏃跺瘑鐮佸彧浼氬湪鍏ㄦ柊鐨?`snowluma-data` 鍗烽娆″惎鍔ㄦ椂杈撳嚭涓€娆★紱鍚庣画閲嶅惎鎴栧鐢ㄦ棫鍗锋椂涓嶄細鍐嶇敓鎴愭柊鐨勬槑鏂囧瘑鐮併€?
noVNC 鍦板潃锛?
```text
http://IP:6081/
```

SnowLuma WebUI 鍦板潃锛?
```text
http://IP:5099/
```

SnowLuma 鐨勯厤缃拰 OneBot 閰嶇疆榛樿鎸佷箙鍖栧湪 `/app/snowluma-data/config`銆?
## 鑷姩娉ㄥ叆

闀滃儚榛樿**寮€鍚?*鑷姩娉ㄥ叆锛坄SNOWLUMA_HOOK_AUTOLOAD=1`锛夈€傚鍣ㄤ竴鍚姩 SnowLuma 灏辨妸 hook 娉ㄥ叆鍒?QQ 涓昏繘绋嬶紝浣嗗彧鏄鍔ㄨ瀵燂紱绛変綘 VNC 杩涘幓鎵爜骞跺湪鎵嬫満涓婂畬鎴愮櫥褰曞悗锛宧ook 浼氳嚜鍔ㄨ瘑鍒湡瀹炵櫥褰曠姸鎬佸苟鍒囧埌宸ヤ綔妯″紡锛宺keys / 濂藉弸 / 缇や俊鎭細鑷姩鍔犺浇锛屾棤闇€鍦?WebUI 閲屾墜鍔ㄧ偣 Load銆俿upervisor 鎶?QQ 鑷姩閲嶅惎鍚庝篃鏄悓鏍锋祦绋嬨€?
### 鍏抽棴鑷姩娉ㄥ叆

濡傛灉浣犳兂淇濈暀鏃х殑"鎵嬪姩 Load"宸ヤ綔娴侊細

```bash
docker run -e SNOWLUMA_HOOK_AUTOLOAD=0 ... motricseven7/snowluma:latest
```

鎴栧湪 `docker-compose.yml` 閲岃 `SNOWLUMA_HOOK_AUTOLOAD: 0`锛屽啀鎴栬€呭湪鎸佷箙鍗?`/app/snowluma-data/config/runtime.json` 閲岃 `"hookAutoLoad": false`銆傜幆澧冨彉閲忎紭鍏堜簬 JSON 閰嶇疆銆?
## 澶氬紑 QQ

闀滃儚鏀寔閫氳繃鐙珛 `HOME` 鑷姩鎷夎捣澶氫釜 QQ 瀹炰緥銆傝缃?`SNOWLUMA_EXTRA_QQ_HOMES` 涓洪€楀彿鎴栫┖鏍煎垎闅旂殑 `/app/...` 瀹瑰櫒璺緞锛屽苟缁欐瘡涓矾寰勬寕鐙珛鎸佷箙鍗凤細

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

瀹瑰櫒鍚姩鏃朵細涓烘瘡涓澶?`HOME` 鐢熸垚涓€涓?supervisor program锛屼娇鐢?`snowluma` 鐢ㄦ埛銆佸悓涓€涓?`DISPLAY` 鍜屽悓涓€缁?`SNOWLUMA_QQ_FLAGS` 鍚姩 QQ銆傝繖鏍?SnowLuma 杩涚▼鍜屾墍鏈?QQ 杩涚▼鍚岀敤鎴疯繍琛岋紝hook 鑷姩娉ㄥ叆涓嶄細閬囧埌鎵嬪姩 `docker exec` 璇敤 root 甯︽潵鐨勬潈闄愰棶棰樸€?
涓存椂鎵嬪姩鍚姩绗簩涓处鍙蜂篃鍙互锛?
```bash
docker exec -u snowluma -e DISPLAY=:1 -e HOME=/app/qq-acct2 -d snowluma sh -lc 'qq --no-sandbox ${SNOWLUMA_QQ_FLAGS}'
```

娉ㄦ剰姣忎釜 QQ 瀹炰緥蹇呴』鐙崰鑷繁鐨?`HOME`锛屼笉瑕佽涓や釜瀹炰緥鍏辩敤 `/app` 鎴栧悓涓€涓?`/app/qq-acctN`銆?
## GPU / 鍐呭瓨锛圫wiftShader 杞欢娓叉煋娉勬紡锛?
瀹瑰櫒鍐呮病鏈夌‖浠?GPU锛孮Q锛堝熀浜?Electron锛夌殑 GPU 杩涚▼浼氶€€鍥?SwiftShader 杞欢娓叉煋銆傞暱鏃堕棿鍋滃湪鐧诲綍鐣岄潰锛堟湭鎵爜鐧诲綍锛夋椂锛孲wiftShader 浼氫笉鏂垎閰嶄笖涓嶅洖鏀跺唴瀛橈紝瀵艰嚧杩涚▼鍐呭瓨鍗曡皟涓婃定銆傞暅鍍忛粯璁ら€氳繃 `SNOWLUMA_QQ_FLAGS` 缁?QQ 鍏虫帀 GPU 涓?SwiftShader锛?
```text
SNOWLUMA_QQ_FLAGS="--disable-gpu --disable-software-rasterizer --disable-gpu-compositing"
```

姝ゆ椂鏀硅蛋绾?CPU 鍏夋爡锛圫kia锛夛紝鐧诲綍浜岀淮鐮佺収甯告覆鏌撱€佸彲姝ｅ父鎵爜锛屽彧鏄笉鍐嶆湁杞欢 GL 閭ｆ潯婕忓唴瀛樼殑璺緞銆?
濡傛灉浣犵粰瀹瑰櫒鍋氫簡 GPU 鐩撮€氥€佹兂鎭㈠纭欢鍔犻€燂紝鎶婂畠娓呯┖鎴栨崲鎴愯嚜宸辩殑鍙傛暟锛?
```bash
docker run -e SNOWLUMA_QQ_FLAGS="" ... motricseven7/snowluma:latest
```

鎴栧湪 `docker-compose.yml` 閲岃 `SNOWLUMA_QQ_FLAGS: ""`銆?
## 鐜鍙橀噺

| 鍙橀噺                     | 榛樿鍊?                                        | 璇存槑                                    |
| ------------------------ | ---------------------------------------------- | --------------------------------------- |
| `VNC_PASSWD`             | `vncpasswd`                                    | VNC / noVNC 鐧诲綍瀵嗙爜銆?*鍔″繀淇敼**銆?   |
| `SNOWLUMA_UID`           | `1000`                                         | 瀹瑰櫒鍐?`snowluma` 鐢ㄦ埛鐨?uid銆?         |
| `SNOWLUMA_GID`           | `1000`                                         | 瀹瑰櫒鍐?`snowluma` 鐢ㄦ埛鐨?gid銆?         |
| `SNOWLUMA_WEBUI_PORT`    | `5099`                                         | WebUI 鐩戝惉绔彛锛堝鍣ㄥ唴锛夈€?             |
| `SNOWLUMA_LOG_LEVEL`     | `info`                                         | 鏃ュ織绾у埆锛歚error` / `warn` / `info` / `debug`銆?|
| `SNOWLUMA_SCREEN`        | `1920x1080x24`                                 | Xvfb 鍒嗚鲸鐜?+ 鑹叉繁銆?                   |
| `SNOWLUMA_HOOK_AUTOLOAD` | `1`                                            | 鑷姩娉ㄥ叆寮€鍏炽€傝 `0` 鍒囧洖鎵嬪姩 Load銆?   |
| `SNOWLUMA_EXTRA_QQ_HOMES` | 绌?                                           | 澶氬紑 QQ 鐨勯澶?HOME 璺緞鍒楄〃銆?         |
| `SNOWLUMA_QQ_FLAGS`      | `--disable-gpu --disable-software-rasterizer --disable-gpu-compositing` | 浼犵粰 Linux QQ 鐨勫惎鍔ㄥ弬鏁般€?|
| `TZ`                     | `Asia/Shanghai`                                | 瀹瑰櫒鏃跺尯銆?                             |

鐜鍙橀噺浼樺厛绾ч珮浜?`runtime.json`銆?
## 娉ㄦ剰

SnowLuma 褰撳墠浣跨敤 native addon 瀵?QQ 杩涚▼杩涜鍔犺浇锛屽鍣ㄥ惎鍔ㄦ椂闇€瑕?`SYS_PTRACE` 鑳藉姏鍜?`seccomp=unconfined`銆傞暅鍍忓唴浼氱粰 `/usr/local/bin/node` 璁剧疆 `cap_sys_ptrace`锛屽洜姝ゆ甯告儏鍐典笅涓嶉渶瑕佸啀淇敼瀹夸富鏈?`kernel.yama.ptrace_scope`銆傝閬靛畧绗笁鏂硅蒋浠剁殑浣跨敤璁稿彲鍜屽紑婧愬崗璁€?