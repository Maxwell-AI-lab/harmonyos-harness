# harness-dev:2.3 = harness-dev:2.2 + 鸿蒙模拟器升级到 API 26(HarmonyOS 7.0.0)
#
# 改了什么:
#   1. 加入官方的系统镜像 HarmonyOS 7.0.0(26.0.0)(包版本 7.0.0.107)。它和命令行工具自带的 SDK(API 26)是同一代,
#      换上之后:新建的工程不用再带 --api-level 24;用 API 26 才有的接口也不会在运行时崩溃。
#      6.1.1(API 24)的系统镜像保留。
#   2. 默认预置实例 deveco_phone 换成 API 26 的。实例名不变,原来的启动命令不用改。
#   3. 两套“只启动过一次”的干净实例状态放在 /opt/emulator-state/api26 和 /opt/emulator-state/api24,
#      用 /opt/scripts/switch-emulator.sh 24|26 一键切换。
#   4. 带自检脚本 /opt/scripts/selfcheck.sh。
#
# 预置实例为什么关闭热启动(isHotBoot=false):
#   devecocli emulator create 新建的实例默认 isHotBoot=true:停止时保存内存快照(ram.bin 约 2.5GB),启动时从快照恢复。
#   实测从快照恢复后,来宾系统里的调试服务偶尔起不来,表现为 hdc 里一直看不到设备(5 次里 2 次)。
#   关掉后每次都是正常开机(服务器负载高时 40~55 秒),连续启停 4 次都正常,实例状态也只有约 0.9GB。
#
# 构建上下文(由 prepare.sh 生成):
#   system-image/HarmonyOS-7.0.0/   API 26 系统镜像(约 4.6GB)
#   emulator-state/api26/           API 26 的实例状态(约 0.9GB)
#   emulator-state/api24/           API 24 的实例状态(约 0.76GB,取自 harness-dev:2.2)
#   switch-emulator.sh  selfcheck.sh
# 构建:docker build -t harness-dev:2.3 <构建上下文目录>
FROM harness-dev:2.2

COPY system-image/HarmonyOS-7.0.0 /opt/emu-images/system-image/HarmonyOS-7.0.0

COPY emulator-state/api26 /opt/emulator-state/api26
COPY emulator-state/api24 /opt/emulator-state/api24

# 默认实例换成 API 26。/opt/emulator-state 里那套保持干净,留给切换脚本用,所以这里拷贝而不是移动。
RUN set -eu; \
    D=/root/.Huawei/Emulator/deployed; \
    rm -rf "$D/deveco_phone"; \
    cp -a /opt/emulator-state/api26/deveco_phone "$D/deveco_phone"; \
    printf 'hvd.ini.encoding=UTF-8\npath=%s\n' "$D/deveco_phone" > "$D/deveco_phone.ini"

COPY switch-emulator.sh /opt/scripts/switch-emulator.sh
COPY selfcheck.sh /opt/scripts/selfcheck.sh
RUN chmod +x /opt/scripts/switch-emulator.sh /opt/scripts/selfcheck.sh

LABEL org.opencontainers.image.title="harness-dev (Android + HarmonyOS API 26 emulator + DevEco Code)" \
      org.opencontainers.image.description="harness-dev:2.2 with the HarmonyOS 7.0.0 (API 26) emulator system image as the default deveco_phone instance; API 24 (6.1.1) switchable" \
      org.opencontainers.image.base.name="harness-dev:2.2"
