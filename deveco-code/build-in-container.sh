#!/bin/bash
# 在构建容器内执行(基于 harness-dev:2.1):装 Node 22 + Bun 1.4.2 → 取源码 → 打补丁 → bun install → 构建 linux-x64 单文件。
# 配方对齐上游官方 CI(.gitcode/workflows/publish.yml): ubuntu + Node 22 + bun@1.4.2 + 华为云 npm 镜像。
# 目录约定: /work/src=源码  /work/scripts=本脚本所在目录(只读)  /work/out=产物与日志
set -euo pipefail
export NPM_CONFIG_REGISTRY=https://mirrors.huaweicloud.com/repository/npm/
export NODEJS_ORG_MIRROR=https://mirrors.huaweicloud.com/nodejs
OUT=/work/out; SRC=/work/src
log() { echo "[$(date +%H:%M:%S)] $*"; }

# 协议门开关(默认开启)。上游构建脚本自带 `--skip-agreement`,把 DEVECO_SKIP_AGREEMENT 编译成 true:
# 每次模型请求前的产品协议检查直接放行,不再依赖本地的接受状态文件。上游注释写明它用于“源码/内部构建”,
# 发布版固定为 false。本镜像只在内部使用,所以开启(用户 2026-11-23 确认)。
# 需要与官方发布版行为一致的二进制时,执行 SKIP_AGREEMENT=0 bash build-in-container.sh。
SKIP_AGREEMENT="${SKIP_AGREEMENT:-1}"
BUILD_FLAGS="--single"
[ "$SKIP_AGREEMENT" = "0" ] || BUILD_FLAGS="$BUILD_FLAGS --skip-agreement"

log "1/6 Node 22(仅构建容器内使用,不进最终镜像)"
FILE=$(curl -fsSL "$NODEJS_ORG_MIRROR/latest-v22.x/SHASUMS256.txt" | awk '/linux-x64\.tar\.xz$/{print $2; exit}')
mkdir -p /opt/node22
curl -fsSL "$NODEJS_ORG_MIRROR/latest-v22.x/$FILE" | tar -xJ -C /opt/node22 --strip-components=1
export PATH=/opt/node22/bin:$PATH
log "node: $(node -v)"

log "2/6 Bun 1.4.2"
npm install -g bun@1.4.2 > "$OUT/bun-install.log" 2>&1 || { tail -20 "$OUT/bun-install.log"; exit 1; }
log "bun: $(bun --version)"

log "3/6 源码(钉住已审阅的提交 b164c1a;服务器不允许按 SHA 浅取则退回默认分支并如实记录)"
PIN=b164c1a581ded7e596327493c3014ecdf2ee8784
if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$SRC"
  if ! git clone --depth 1 https://gitcode.com/openharmony-sig/deveco-code.git "$SRC" > "$OUT/clone.log" 2>&1; then
    tail -20 "$OUT/clone.log"; exit 1
  fi
fi
if git -C "$SRC" fetch --depth 1 origin "$PIN" > "$OUT/pin.log" 2>&1 && git -C "$SRC" checkout --detach FETCH_HEAD >> "$OUT/pin.log" 2>&1; then
  Pinned="pinned=yes ($PIN)"
else
  Pinned="pinned=no (按 SHA 浅取失败,使用默认分支 HEAD)"
fi
# 版本号:官方发布流程通过 DEVECO_VERSION 注入;不设则生成 0.0.0-<时间戳> 的预览版。取 opencode 包的声明版本。
DEVECO_VERSION=$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$SRC/packages/opencode/package.json" | head -1)
export DEVECO_VERSION
[ -n "$DEVECO_VERSION" ] || { echo "取不到 DEVECO_VERSION"; exit 1; }
{ echo "repo=https://gitcode.com/openharmony-sig/deveco-code"; echo "base_image=harness-dev:2.1"; echo "built_at=$(date -Is)";
  echo "$Pinned"; echo "deveco_version=$DEVECO_VERSION"; echo "build_flags=$BUILD_FLAGS"; echo "node=$(node -v) bun=$(bun --version)"; git -C "$SRC" log -1 --format='commit=%H%ndate=%ad%nsubject=%s' --date=iso; } > "$OUT/BUILD-INFO.txt"
cat "$OUT/BUILD-INFO.txt"

log "4/6 Linux 构建补丁"
python3 -I /work/scripts/apply_linux_patch.py "$SRC"
# 只归档补丁本身的两个文件(bun install 还会改写 bun.lock 的镜像地址并规范化 package.json 空白,不属于补丁)
PATCH_FILES="packages/opencode/script/build.ts packages/opencode/script/postinstall.ts"
# shellcheck disable=SC2086
git -C "$SRC" diff --stat -- $PATCH_FILES | tee "$OUT/patch-stat.txt"
# shellcheck disable=SC2086
git -C "$SRC" diff -- $PATCH_FILES > "$OUT/linux-build.patch"

log "5/6 bun install(全量日志见 install.log)"
cd "$SRC"
bun install > "$OUT/install.log" 2>&1 || { echo "bun install 失败,日志尾部:"; tail -60 "$OUT/install.log"; exit 1; }
tail -8 "$OUT/install.log"

log "6/6 构建 deveco-linux-x64(--single = 仅当前平台 linux-x64 glibc;完整参数见 BUILD-INFO 的 build_flags)"
cd "$SRC/packages/opencode"
# shellcheck disable=SC2086
bun run script/build.ts $BUILD_FLAGS > "$OUT/compile.log" 2>&1 || { echo "构建失败,日志尾部:"; tail -60 "$OUT/compile.log"; exit 1; }
tail -15 "$OUT/compile.log"
ls -la dist/ | tee "$OUT/dist-listing.txt"

rm -rf "$OUT/deveco-linux-x64"
cp -a dist/deveco-linux-x64 "$OUT/"

log "7/7 安装平台包声明的运行时依赖"
# 二进制里并不包含全部功能:鸿蒙能力(构建 / 运行 / 设备 / 界面验证)由内建插件 @deveco-test/deveco-harness 提供,
# 它是平台包 package.json 里的普通 npm 依赖。官方 npm 安装会自动带上;手动构建必须补装,否则二进制能启动
# (--version / --help / --serve 都正常)但 "plugins: none",鸿蒙工具一个都没有。
# 二进制启动时从自身所在目录的上一级按 Node 模块解析查找它,所以依赖要装进产物目录自己的 node_modules。
cd "$OUT/deveco-linux-x64"
npm install --omit=dev --ignore-scripts --no-audit --no-fund > "$OUT/npm-install.log" 2>&1 || { echo "npm install 失败,日志尾部:"; tail -40 "$OUT/npm-install.log"; exit 1; }
ls node_modules node_modules/@deveco-test 2>/dev/null | tee "$OUT/runtime-deps.txt"
du -sh node_modules | tee -a "$OUT/runtime-deps.txt"

sha256sum "$OUT/deveco-linux-x64/bin/deveco" | tee "$OUT/deveco.sha256"
log "BUILD DONE → $OUT/deveco-linux-x64"
