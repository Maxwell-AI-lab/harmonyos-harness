#!/bin/bash
# 生成 Dockerfile 里 COPY emulator-state/Huawei /root/.Huawei 所需的预置模拟器实例。
#
# 用法(需 root,本机已有 harness-dev:2.2 镜像和 /dev/kvm):
#   bash emulator-state/prepare.sh
#
# 做的事:从 harness-dev:2.2 起一个带 KVM 的临时容器 → 用 devecocli 创建实例 deveco_phone →
# 启动到系统就绪 → 停止 → 删除日志 → 把 /root/.Huawei 导出到本目录下的 Huawei/。
# 产物是“已完成首次启动”的干净实例(未安装任何应用),之后每个新容器首次启动约 31 秒。
set -eu

NAME=deveco_phone
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/Huawei"
C=deveco-prep-$$

docker rm -f "$C" >/dev/null 2>&1 || true
trap 'docker rm -f "$C" >/dev/null 2>&1 || true' EXIT

docker run -d --name "$C" --device /dev/kvm --shm-size=4g harness-dev:2.2 sleep infinity >/dev/null
sleep 2

docker exec "$C" bash -lc '
set -eu
export NO_COLOR=1
devecocli emulator create deveco_phone --device-type phone --os-version "HarmonyOS 6.1.1(24)" \
  --image-root /opt/emu-images --memory 4 --storage 32 --force 2>&1 | tail -1
S=$(date +%s)
# 全新实例首次启动约 85 秒,CLI 会在约 60 秒时提示超时;这里以系统自己的启动完成标记为准
timeout 480 devecocli emulator start deveco_phone >/dev/null 2>&1 || true
for _ in $(seq 1 40); do
  [ "$(hdc -t 127.0.0.1:5555 shell param get bootevent.boot.completed 2>/dev/null | tr -d "\r\n ")" = "true" ] && break
  sleep 5
done
echo "首次启动到系统就绪: $(( $(date +%s) - S )) 秒"
sleep 15
timeout 120 devecocli emulator stop deveco_phone 2>&1 | tail -1
rm -rf /root/.Huawei/Emulator/deployed/deveco_phone/Log
'

# 目标目录必须事先不存在:docker cp 在“目标已存在”时会把源目录整个放进去,产物就多出一层 .Huawei/,
# COPY 进镜像后 CLI 找不到实例。目标不存在时它直接把目标建成为 /root/.Huawei 的副本。
rm -rf "$OUT"
docker cp "$C:/root/.Huawei" "$OUT"
# 核对导出布局,不对就失败退出
[ -f "$OUT/Emulator/deployed/$NAME/config.ini" ] || { echo "导出布局不对(缺 Emulator/deployed/$NAME/config.ini): $OUT" >&2; exit 1; }
echo "已导出: $OUT ($(du -sh "$OUT" | cut -f1))"
