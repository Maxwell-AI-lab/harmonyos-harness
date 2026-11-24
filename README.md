# Harness 一体化开发镜像(harness-dev:2.1 / 2.2 / 2.3)

一个镜像 = 开发构建(安卓+鸿蒙)+ 模拟器运行(安卓+鸿蒙)+ AI 编程工具。

| 版本 | 内容 | 文档 |
|---|---|---|
| `harness-dev:2.1` | 基础镜像:双端工具链 + 双端模拟器 + devecocli / Claude Code | 本页 |
| `harness-dev:2.2` | 2.1 + DevEco Code 1.17.9(Linux 版,从源码构建)+ 预置模拟器实例 + Lint 默认生效 | **[使用指南](docs/USAGE-harness-dev-2.2.md)**、[deveco-code/README.md](deveco-code/README.md)、[测试报告](docs/DEVECO-CODE-LINUX-TEST-REPORT.md) |
| `harness-dev:2.3` | 2.2 + 鸿蒙模拟器升级到 API 26(HarmonyOS 7.0.0),和构建工具版本一致;可一键切回 API 24。**推荐用这个** | **[使用指南](docs/USAGE-harness-dev-2.3.md)**、[emulator-api26/README.md](emulator-api26/README.md)、[测试报告](docs/DEVECO-CODE-LINUX-TEST-REPORT.md) |

**验证服务器**:119.3.230.173(hmbot1119 · 88核 / 376G / KVM)

**镜像在哪、怎么拿**:

- 三个版本的镜像都在 173 的 Docker 里。能登录这台机器的人不用传任何东西,直接 `docker run`。
- 别的机器要用,从 173 拷导出包,再 `docker load -i` 导入:
  - `scp root@119.3.230.173:/root/harness-release/harness-dev-2.3.tar.gz .`(11.3G)
  - `scp root@119.3.230.173:/root/harness-release/harness-dev-2.2.tar.gz .`(8.1G)
  - `scp root@119.3.230.173:/root/harness-release/harness-dev-2.1.tar.gz .`(7.5G)
- **第一次用,请看[2.3 使用指南](docs/USAGE-harness-dev-2.3.md)**:机器要求、拿到镜像、起容器、配模型、开始干活、常见问题,一步一步都写了。还在用 2.2 的看[ 2.2 使用指南](docs/USAGE-harness-dev-2.2.md)。

下文“镜像分层”到“验证状态”两部分对三个版本都适用。

## 镜像分层

| 层 | 内容 |
|---|---|
| 通用开发 | Git 2.43 / Python 3.12 / Node 24 / pnpm 10 / ripgrep / jq / GCC 13 / CMake 3.28 / JDK 21+17 |
| 安卓构建 | SDK cmdline-tools、platforms 35+36、build-tools 35+36、platform-tools(adb 1.0.41) |
| 安卓模拟器 | Android Emulator + system image(android-34 google_apis x86_64)|
| 鸿蒙构建 | CLT 26.0.0.821(SDK API 26 / ohpm 26.0.0.630 / hvigor / hdc 3.2.0f),已设区域 CN |
| 鸿蒙模拟器 | HarmonyOS Emulator 26.0.0.400 + 系统镜像 6.1.1(API 24);2.3 另加 7.0.0(API 26),并作为默认 |
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
2. **鸿蒙装包版本(只适用于 2.1 / 2.2)**:HAP 的 targetSdkVersion 不得超过 "6.1.1(24)"(镜像内系统版本);CLT26 脚手架默认 26,构建前请调整 build-profile.json5。2.3 的默认系统是 API 26,没有这个限制
3. **鸿蒙截图路径**:必须 `/data/local/tmp/` 下
4. **装包时机**:鸿蒙模拟器开机后等待约 60 秒再执行 bm install
5. **Gradle**:镜像未预装(按清单口径,工程自带 ./gradlew 优先);安卓最小构建链 aapt2/zipalign/apksigner 已内置并验证
6. **单实例端口**:每次启动一个鸿蒙实例占 2 个端口(5555 递增);多实例同容器内可行,跨容器请自行规划端口

## 验证状态

2.1 的 6 项验证全部通过(安卓模拟器/鸿蒙模拟器/鸿蒙构建/安卓构建链/端到端闭环/工具链),详见 [docs/VERIFICATION-REPORT.md](docs/VERIFICATION-REPORT.md)。2.2 的验证见[测试报告](docs/DEVECO-CODE-LINUX-TEST-REPORT.md);2.3 的验证见同一份报告的第十三节。

## harness-dev:2.3 — 鸿蒙模拟器升级到 API 26

2.1 / 2.2 里,构建工具(SDK)是 API 26,模拟器的系统却是 API 24。结果是不带参数新建的工程装不上模拟器,代码里用了 API 26 才有的接口还会在运行时崩溃。2.3 把模拟器的系统换成官方的 HarmonyOS 7.0.0(API 26),两边版本一致,这两个问题都没有了。

**想用这个镜像:看[2.3 使用指南](docs/USAGE-harness-dev-2.3.md)。** 和 2.2 比,用法只有两处不同:

- 新建工程不用再带 `--api-level 24`。
- 想在 API 24 的系统上验证时,`/opt/scripts/switch-emulator.sh 24` 一条命令切回去,`26` 切回来。

```bash
docker run -d --name mydev --device /dev/kvm --shm-size=4g harness-dev:2.3 sleep infinity
docker exec -it mydev bash

devecocli emulator start deveco_phone         # 启动预置的模拟器(API 26),约 1 分钟
devecocli create --project-path ./Demo --app-name Demo   # 新建工程,不用指定 API 级别
```

- 使用指南(机器要求、拿到镜像、配模型、切换系统版本、常见问题):[docs/USAGE-harness-dev-2.3.md](docs/USAGE-harness-dev-2.3.md)
- 镜像怎么做的、重建步骤、自检方法:[emulator-api26/README.md](emulator-api26/README.md)

按 API 24 做的旧工程不用改,在 2.3 上照样能装能跑(已验证)。

## harness-dev:2.2 — 集成 DevEco Code(Linux 版)

DevEco Code 官方只发布 Windows / macOS 包。2.2 在 2.1 之上加入了从上游源码构建的 Linux 版 1.17.9,可以用自然语言驱动 agent 完成“建工程 → 构建 → 装到模拟器 → 看界面 → 截图”的闭环,全程不需要人工确认,也不需要登录华为账号(模型用自己配置的)。

**想用这个镜像:看[使用指南](docs/USAGE-harness-dev-2.2.md)。** 下面是最短的用法(在 173 上):

```bash
# 起容器(要 KVM;入口脚本自动拉起虚拟显示器,模拟器以窗口模式运行,可接 VNC 看画面)
docker run -d --name mydev --device /dev/kvm --shm-size=4g harness-dev:2.2 sleep infinity
docker exec -it mydev bash

deveco                                        # 交互界面(TUI)
devecocli emulator start deveco_phone         # 启动预置的模拟器,约 30 秒
deveco run --agent build --auto "构建这个工程并安装到模拟器上启动"   # 无人值守(需要先配模型)
```

- 使用指南(机器要求、拿到镜像、配模型、常见问题):[docs/USAGE-harness-dev-2.2.md](docs/USAGE-harness-dev-2.2.md)
- 镜像怎么做的、重建步骤、自检方法:[deveco-code/README.md](deveco-code/README.md)
- 完整测试结论与 44 个集成问题的清单:[测试报告](docs/DEVECO-CODE-LINUX-TEST-REPORT.md)([HTML 版](docs/DEVECO-CODE-LINUX-TEST-REPORT.html))

批量跑之前最容易踩的四个坑(**前两个只存在于 2.1 / 2.2;2.3 换成了 API 26 的模拟器,没有这两个问题**):

1. **脚本直接新建工程要带 `--api-level 24`**。命令行工具自带的 SDK 是 API 26,模拟器系统是 API 24;不指定时工程能构建成功,但装不上模拟器。
2. **不要用 API 26 才有的接口**。同样是这个版本差:代码里用了 API 26 才有的接口,构建和各项检查都不会提示,运行时才崩。目前的迁移结果里没有发现,详见测试报告第四节。
3. **宿主机的 inotify 监听限额要放宽**。所有容器共用 root 的额度,几个构建并发就会报 `System limit for number of file watchers reached`。
4. **用 `--auto` 无人值守时,容器是唯一的安全边界**。DevEco Code 的命令沙箱在 Linux 上不生效,agent 执行的命令不受“只读 / 仅工作区可写”约束。

另外,2.2 设置了 `ENTRYPOINT`(先起虚拟显示器再执行命令):`docker run -it 镜像` 直接进 bash;`docker run 镜像 <命令>` 照常执行;想执行一串命令要写成 `docker run 镜像 bash -c "…"`。可以用 `docker run --entrypoint bash ...` 绕过入口,但那样不会自动起虚拟显示器,模拟器就启动不了。

## 重建镜像(如需)

构建上下文需要:cmdtools.zip(安卓命令行工具)、clt/(鸿蒙 CLT 26.0.0.821,去 emulator)、clt-emu/(鸿蒙 Emulator 二进制)、emu-images/(鸿蒙系统镜像 6.1.1)、start-*.sh。执行 `docker build -t harness-dev:2.1 .`。2.2 在 2.1 之上重建,步骤见 [deveco-code/README.md](deveco-code/README.md);2.3 在 2.2 之上重建,步骤见 [emulator-api26/README.md](emulator-api26/README.md)。
