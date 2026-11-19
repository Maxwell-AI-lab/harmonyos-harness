#!/bin/bash
# start-vnc.sh — 在容器内启动 VNC 远程桌面(需先启动鸿蒙模拟器)
# 用法: /opt/scripts/start-vnc.sh [密码] [端口]
# 之后在本地用 VNC 客户端连接:vnc://localhost:5900
PASS=${1:-Zcode2026}
PORT=${2:-5900}

export DISPLAY=:0

# 确保有虚拟屏
if [ ! -S /tmp/.X11-unix/X0 ]; then
  echo "错误:请先运行 /opt/scripts/start-harmony.sh 启动模拟器(需要虚拟屏)"
  exit 1
fi

# 启动 x11vnc(如果已在跑就跳过)
if pgrep x11vnc >/dev/null; then
  echo "VNC 已在运行(端口 $PORT)"
else
  nohup x11vnc -display :0 -forever -shared -rfbport $PORT -passwd $PASS \
    -noxdamage -repeat -cursor arrow </dev/null >/tmp/x11vnc.log 2>&1 &
  sleep 2
  if pgrep x11vnc >/dev/null; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  VNC 远程桌面已启动"
    echo "  端口: $PORT"
    echo "  密码: $PASS"
    echo ""
    echo "  本地连接方式:"
    echo "    Mac:   打开访达 → ⌘K → vnc://localhost:$PORT"
    echo "    Linux: remmina 或 vncviewer localhost::$PORT"
    echo "    Win:   VNC Viewer → localhost:$PORT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  else
    echo "VNC 启动失败,查看 /tmp/x11vnc.log"
    exit 1
  fi
fi
