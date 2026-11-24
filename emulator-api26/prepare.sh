#!/bin/bash
# 生成 harness-dev:2.3 的构建输入:API 26 系统镜像 + 两套预置实例状态。约 6 分钟,主要花在下载和首次开机上。
#
# 用法(需 root、Docker、/dev/kvm,本机已有 harness-dev:2.2):
#   bash prepare.sh [输出目录]        默认输出到本目录下的 build-inputs/
#
# 做的事:
#   1. 在一个临时的 harness-dev:2.2 容器里,用 devecocli 下载官方系统镜像 HarmonyOS 7.0.0(26.0.0)(手机,x86)
#   2. 取出 2.2 预置的 API 24 实例状态,原样保存
#   3. 用新镜像新建一个实例并启动一次到开机完成,再正常停止 —— 这一步每个新实例只需做一次;
#      做过之后,以后每个新容器的首次启动就是正常开机(约 1 分钟),而不是首次初始化(约 2 分钟,还会触发命令行的超时提示)
#   4. 导出实例状态:关掉热启动(isHotBoot=false)、去掉内存快照和日志,实例改名为 deveco_phone
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/build-inputs}"
OS="HarmonyOS 7.0.0(26.0.0)"
NAME=deveco_phone26
C=deveco-prepare-$$
trap 'docker rm -f "$C" >/dev/null 2>&1 || true' EXIT
log() { echo "[$(date +%H:%M:%S)] $*"; }

mkdir -p "$OUT/system-image" "$OUT/emulator-state/api26" "$OUT/emulator-state/api24"
rm -rf "$OUT/system-image/HarmonyOS-7.0.0" "$OUT/emulator-state/api26/deveco_phone" "$OUT/emulator-state/api24/deveco_phone"

log "起一个临时容器(基于 harness-dev:2.2,带 KVM)"
docker run -d --name "$C" --device /dev/kvm --shm-size=4g harness-dev:2.2 sleep infinity >/dev/null
sleep 2

log "1/4 下载系统镜像 $OS"
docker exec "$C" bash -c "cd /tmp && NO_COLOR=1 devecocli emulator image download --device-type phone --os-version '$OS'" 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r' | grep -v '^$' | tail -1

log "2/4 取出 API 24 的实例状态"
docker cp "$C:/root/.Huawei/Emulator/deployed/deveco_phone" "$OUT/emulator-state/api24/deveco_phone"

log "3/4 新建 API 26 实例并完成首次启动"
docker exec -i "$C" bash -s <<'INNER'
set -eu
export NO_COLOR=1
cd /tmp
NAME=deveco_phone26
OS="HarmonyOS 7.0.0(26.0.0)"
devecocli emulator create "$NAME" --device-type phone --os-version "$OS" --image-root /opt/emu-images --memory 4 --storage 32 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r' | tail -1
# 全新实例首次启动约 2 分钟,命令行只等 60 秒(会提示超时,但模拟器会继续启动)。这里以系统自己的开机完成标记为准。
nohup devecocli emulator start "$NAME" >/tmp/first-boot.log 2>&1 &
booted=""
for _ in $(seq 1 120); do
  T="$(hdc list targets 2>/dev/null | tr -d '\r' | grep -v '^\[Empty\]$' | grep -v '^$' | head -1)"
  if [ -n "$T" ] && [ "$(hdc -t "$T" shell param get bootevent.boot.completed 2>/dev/null | tr -d '\r\n ')" = "true" ]; then booted=1; break; fi
  sleep 5
done
[ -n "$booted" ] || { echo "首次启动没有在 10 分钟内完成开机"; tail -5 /tmp/first-boot.log; exit 1; }
echo "首次启动完成;系统 API 级别 $(hdc -t "$T" shell param get const.ohos.apiversion 2>/dev/null | tr -d '\r')"
sleep 15
devecocli emulator stop "$NAME" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r' | tail -1
# 停止命令返回时进程可能还没退干净,等它退出再导出
for _ in $(seq 1 60); do pgrep -f "Emulator -start" >/dev/null 2>&1 || break; sleep 1; done
INNER

log "4/4 导出实例状态和系统镜像"
docker cp "$C:/root/.Huawei/Emulator/deployed/$NAME" "$OUT/emulator-state/api26/deveco_phone"
INST="$OUT/emulator-state/api26/deveco_phone"
rm -f "$INST/ram.bin"          # 停止时保存的内存快照(约 2.5GB)。从快照恢复后调试服务偶尔起不来,所以不用它
rm -rf "$INST/Log"
sed -i -e "s/^name=.*/name=deveco_phone/" \
       -e "s#^instancePath=.*#instancePath=/root/.Huawei/Emulator/deployed/deveco_phone#" \
       -e "s/^isHotBoot=.*/isHotBoot=false/" "$INST/config.ini"
docker cp "$C:/opt/emu-images/system-image/HarmonyOS-7.0.0" "$OUT/system-image/HarmonyOS-7.0.0"

log "完成。构建输入在 $OUT:"
du -sh "$OUT/system-image" "$OUT/emulator-state/api26" "$OUT/emulator-state/api24" | sed 's/^/         /'
echo "         API 26 实例: $(sed -n 's/^os\.osVersion=/系统 /p; s/^isHotBoot=/热启动 /p' "$INST/config.ini" | tr '\n' ' ')"
