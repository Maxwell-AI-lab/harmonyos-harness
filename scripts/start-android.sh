#!/bin/bash
# 用法: start-android.sh [AVD名] — 无头启动安卓模拟器并等待 boot
AVD=${1:-test_avd}
export ANDROID_AVD_HOME=/root/.android/avd
[ -d $ANDROID_AVD_HOME/$AVD ] || echo no | avdmanager create avd -n $AVD -k "system-images;android-34;google_apis;x86_64" --device pixel_6 >/dev/null
nohup emulator -avd $AVD -no-window -gpu swiftshader_indirect -no-boot-anim -no-audio >/tmp/avd.log 2>&1 &
for i in $(seq 1 60); do
  boot=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  [ "$boot" = "1" ] && { echo "安卓模拟器就绪: $AVD"; exit 0; }
  sleep 5
done
echo "启动超时,查 /tmp/avd.log"; exit 1
