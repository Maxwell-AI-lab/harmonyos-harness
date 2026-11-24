#!/bin/bash
# harness-dev:2.2 容器入口:先备好一块虚拟显示器,再执行容器原本的命令。
#
# 为什么需要它:DevEco Code / devecocli 以窗口模式启动鸿蒙模拟器时要有 X11 显示。这套镜像里无窗口模式
# (-noWindow)模拟器无法注册到 hdc(端口开了、hdc 里是空的),所以服务器上的批量环境也走窗口模式——
# 用 Xvfb 提供"看不见的显示器",需要看画面时再用 x11vnc 连进来。
#
# 行为与镜像自带的 /opt/scripts/start-harmony.sh 保持一致(同一个 :0、同样的 1600x900x24),两者可以共存:
# 任何一方先启动了 Xvfb,另一方都会直接复用。
# 不想要这个行为时:docker run --entrypoint bash ...
set -eu

if [ ! -S /tmp/.X11-unix/X0 ]; then
  nohup Xvfb :0 -screen 0 1600x900x24 >/tmp/xvfb.log 2>&1 &
  # 等 X 的 socket 出现(最多约 5 秒);socket 没出来之前启动 openbox 会连不上显示而退出
  for _ in $(seq 1 50); do
    [ -S /tmp/.X11-unix/X0 ] && break
    sleep 0.1
  done
  sleep 0.3
fi

if ! pgrep -x openbox >/dev/null 2>&1; then
  nohup openbox >/tmp/openbox.log 2>&1 &
fi

exec "$@"
