#!/bin/bash
# 用法: start-harmony.sh [实例名] — 窗口模式(虚拟屏)启动鸿蒙模拟器并等待 hdc
NAME=${1:-hm_1}
IR=/opt/emu-images; IP=/root/hm-instances
export DISPLAY=:0 LIBGL_ALWAYS_SOFTWARE=1 LD_LIBRARY_PATH=/opt/command-line-tools/sdk/default/openharmony/toolchains
[ -S /tmp/.X11-unix/X0 ] || (Xvfb :0 -screen 0 1600x900x24 >/dev/null 2>&1 &)
pgrep openbox >/dev/null || (DISPLAY=:0 openbox >/dev/null 2>&1 &)
EMU=/opt/command-line-tools/emulator/Emulator
mkdir -p $IP
[ -d $IP/$NAME ] || $EMU -create $NAME -deviceType phone -osVersion "HarmonyOS 6.1.1(24)" -instancePath $IP -imageRoot $IR -memory 4 -storage 32 >/dev/null
nohup $EMU -start $NAME -instancePath $IP -imageRoot $IR >/tmp/$NAME.log 2>&1 &
HDC=/opt/command-line-tools/sdk/default/openharmony/toolchains/hdc
for i in $(seq 1 60); do
  ss -tln | grep -q "127.0.0.1:55" && { sleep 3; $HDC tconn 127.0.0.1:5555 >/dev/null 2>&1; echo "鸿蒙模拟器就绪: $NAME (hdc 127.0.0.1:5555)"; exit 0; }
  sleep 5
done
echo "启动超时,查 /tmp/$NAME.log"; exit 1
