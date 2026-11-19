# Harness 一体化开发镜像(harness-dev:2.1)

一个镜像 = 开发构建(安卓+鸿蒙)+ 模拟器运行(安卓+鸿蒙)+ AI 编程工具。

**验证服务器**:119.3.230.173(hmbot1119 · 88核 / 376G / KVM)
**镜像包下载**:`scp root@119.3.230.173:/root/harness-release/harness-dev-2.1.tar.gz .`

## 镜像分层

| 层 | 内容 |
|---|---|
| 通用开发 | Git 2.43 / Python 3.12 / Node 24 / pnpm 10 / ripgrep / jq / GCC 13 / CMake 3.28 / JDK 21+17 |
| 安卓构建 | SDK cmdline-tools、platforms 35+36、build-tools 35+36、platform-tools(adb 1.0.41) |
| 安卓模拟器 | Android Emulator + system image(android-34 google_apis x86_64)|
| 鸿蒙构建 | CLT 26.0.0.821(SDK API 26 / ohpm 26.0.0.630 / hvigor / hdc 3.2.0f),已设区域 CN |
| 鸿蒙模拟器 | HarmonyOS Emulator 26.0.0.400 + 系统镜像 6.1.1(API 24)|
| AI 工具 | devecocli 1.3.12、claude-code(运行时注入密钥)|

## 快速开始

```bash
# 1. 交互进入(纯开发/构建,无需 KVM)
docker run -it --rm -v $PWD:/work harness-dev:2.1

# 2. 跑安卓模拟器(需要 KVM,无头模式,约1-2分钟就绪)
docker run --rm --device /dev/kvm harness-dev:2.1 /opt/scripts/start-android.sh

# 3. 跑鸿蒙模拟器(需要 KVM,虚拟屏窗口模式,约1-2分钟就绪)
docker run --rm --device /dev/kvm harness-dev:2.1 /opt/scripts/start-harmony.sh

# 4. Claude Code 无头执行任务(密钥运行时注入)
docker run --rm -e ANTHROPIC_API_KEY=你的密钥 -v $PWD:/work \
  harness-dev:2.1 claude -p "任务描述" --output-format json

# 5. 鸿蒙工程构建(工程放 /work)
cd /work/你的工程 && hvigorw assembleHap --mode module -p module=entry@default
```

## 重要注意事项

1. **模拟器必须挂 KVM**:`--device /dev/kvm`,宿主机需支持虚拟化(云主机需开嵌套虚拟化,裸金属天然支持)
2. **鸿蒙装包版本**:HAP 的 targetSdkVersion 不得超过 "6.1.1(24)"(镜像内系统版本);CLT26 脚手架默认 26,构建前请调整 build-profile.json5
3. **鸿蒙截图路径**:必须 `/data/local/tmp/` 下
4. **装包时机**:鸿蒙模拟器开机后等待约 60 秒再执行 bm install
5. **Gradle**:镜像未预装(按清单口径,工程自带 ./gradlew 优先);安卓最小构建链 aapt2/zipalign/apksigner 已内置并验证
6. **单实例端口**:每次启动一个鸿蒙实例占 2 个端口(5555 递增);多实例同容器内可行,跨容器请自行规划端口

## 验证状态

本镜像 6 项验证全部通过(安卓模拟器/鸿蒙模拟器/鸿蒙构建/安卓构建链/端到端闭环/工具链),详见同目录 VERIFICATION-REPORT.md。

## 重建镜像(如需)

构建上下文需要:cmdtools.zip(安卓命令行工具)、clt/(鸿蒙 CLT 26.0.0.821,去 emulator)、clt-emu/(鸿蒙 Emulator 二进制)、emu-images/(鸿蒙系统镜像 6.1.1)、start-*.sh。执行 `docker build -t harness-dev:2.1 .`
