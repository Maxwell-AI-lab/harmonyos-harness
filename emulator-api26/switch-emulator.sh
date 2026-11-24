#!/bin/bash
# 切换默认模拟器实例 deveco_phone 的系统版本:24(HarmonyOS 6.1.1)或 26(HarmonyOS 7.0.0)。
#
# 用法:
#   switch-emulator.sh 24      换成 API 24 的系统(HarmonyOS 6.1.1)
#   switch-emulator.sh 26      换成 API 26 的系统(HarmonyOS 7.0.0,镜像默认)
#   switch-emulator.sh reset   版本不变,把当前实例恢复成干净的那一套
#   switch-emulator.sh show    只查看当前是哪个版本
#
# 做的事:停掉正在运行的模拟器,把 /root/.Huawei/Emulator/deployed/deveco_phone 换成 /opt/emulator-state 里
# 那套“只启动过一次”的干净实例。当前实例里安装过的应用和数据会被丢弃。换完之后执行
# `devecocli emulator start deveco_phone` 启动(负载高时约 1 分钟)。
set -eu

DEPLOYED=/root/.Huawei/Emulator/deployed
INST="$DEPLOYED/deveco_phone"
STATES=/opt/emulator-state

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

current() { sed -n 's/^os\.osVersion=//p' "$INST/config.ini" 2>/dev/null | head -1; }

case "${1:-}" in
  show)
    [ -f "$INST/config.ini" ] && echo "当前系统: $(current)" || echo "当前没有默认实例 $INST"
    exit 0
    ;;
  24|26) SRC="$STATES/api$1" ;;
  reset)
    # 按当前实例的 API 级别决定恢复哪一套(两套实例的写法不同:一套是 26.0.0,一套是 24)
    case "$(sed -n 's/^os\.apiVersion=//p' "$INST/config.ini" 2>/dev/null | head -1)" in
      26|26.0.0) SRC="$STATES/api26" ;;
      24) SRC="$STATES/api24" ;;
      *) echo "当前没有默认实例,无法判断要恢复哪一套。请用 24 或 26 指定。" >&2; exit 1 ;;
    esac
    ;;
  *) usage ;;
esac

[ -d "$SRC/deveco_phone" ] || { echo "镜像里没有这套实例状态: $SRC" >&2; exit 1; }
CUR="$(current)"
WANT="$(sed -n 's/^os\.osVersion=//p' "$SRC/deveco_phone/config.ini" | head -1)"
if [ "$1" != "reset" ] && [ "$CUR" = "$WANT" ]; then echo "当前已经是 $CUR,不用切换"; exit 0; fi

# 模拟器在跑就先停掉。停止命令返回时进程可能还没退干净,等到进程消失为止,超时再强杀。
if pgrep -f "Emulator -start" >/dev/null 2>&1; then
  (cd /tmp && timeout 120 devecocli emulator stop deveco_phone >/dev/null 2>&1) || true
  for _ in $(seq 1 60); do pgrep -f "Emulator -start" >/dev/null 2>&1 || break; sleep 1; done
  pkill -9 -f "Emulator -start" 2>/dev/null || true
  sleep 2
fi

rm -rf "$INST"
cp -a "$SRC/deveco_phone" "$INST"
printf 'hvd.ini.encoding=UTF-8\npath=%s\n' "$INST" > "$DEPLOYED/deveco_phone.ini"
if [ "$1" = "reset" ]; then
  echo "已把 $(current) 的实例恢复成干净状态。执行 devecocli emulator start deveco_phone 启动。"
else
  echo "已从 ${CUR:-无} 切换到 $(current)。执行 devecocli emulator start deveco_phone 启动。"
fi
