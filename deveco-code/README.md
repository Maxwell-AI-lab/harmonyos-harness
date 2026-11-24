# DevEco Code（Linux 版）装进 harness-dev 镜像

DevEco Code 官方只发布 Windows / macOS 包。本目录是从上游源码构建 Linux 版、装进 `harness-dev:2.1` 并做功能验证的全部材料。

| 项 | 值 |
|---|---|
| 产物镜像 | `harness-dev:2.2`（bms173 上，22.3GB；= 2.1 + 约 1.4GB）。其他机器按下文“怎么重建”生成，约 6 分钟 |
| 源码 | `gitcode.com/openharmony-sig/deveco-code` @ `b164c1a`（2026-11-23 16:22） |
| DevEco Code 版本 | 1.17.9（内含 deveco-cli 1.3.12-Test.2、插件 deveco-harness 0.2.0-test.13） |
| 二进制 | `/opt/deveco/bin/deveco`，178MB，sha256 `8e60219c…33fac85`（同参数构建可复现） |
| 测试报告 | [DevEco Code Linux 版功能测试报告](../docs/DEVECO-CODE-LINUX-TEST-REPORT.html)（[Markdown 版](../docs/DEVECO-CODE-LINUX-TEST-REPORT.md)） |

## 目录内容

```
Dockerfile               harness-dev:2.2 的镜像定义（FROM harness-dev:2.1）
deveco-entrypoint.sh     容器入口：自动拉起 Xvfb 虚拟显示器，再执行原命令
build-in-container.sh    完整构建脚本（在 harness-dev:2.1 容器内执行）
apply_linux_patch.py     Linux 构建补丁（3 处改动 / 2 个文件，锚点断言式，可重复执行）
emulator-state/
  prepare.sh             生成预置模拟器实例的脚本（Huawei/ 目录是它的产物，未入库，约 0.8GB）
selfcheck.sh             镜像自检脚本（47 项，在全新容器里跑，有失败时退出码为 1）
enable-lint.py            让新建工程的 Lint 默认生效（改 devecocli 的工程模板，可重复执行）
tools/ctx.py             只读分析工具：在压缩后的 JS 里按关键词取上下文
tools/html2md.py         HTML 报告 → Markdown 的转换脚本（仓库 docs/ 下的 .md 报告由它生成；改了 HTML 版后在本目录重新跑一遍）
build/                   构建溯源：BUILD-INFO、linux-build.patch、sha256、依赖清单
e2e/                     上游官方实机用例（cli 类）两轮运行日志与汇总
evidence/                测试截图与自检日志
```

## 怎么重建

前提：x86_64 机器、Docker、`/dev/kvm`，本机已有 `harness-dev:2.1`（构建方法见仓库根目录的 README），能访问 gitcode 和华为云镜像站。全程不需要登录华为账号。

```bash
git clone https://github.com/Maxwell-AI-lab/harmonyos-harness.git && cd harmonyos-harness/deveco-code
B=/root/deveco-build
mkdir -p $B/{src,scripts,out,image/emulator-state/Huawei}
cp build-in-container.sh apply_linux_patch.py $B/scripts/
cp Dockerfile deveco-entrypoint.sh enable-lint.py $B/image/

# 1) 构建 DevEco Code（约 2 分钟；产物在 $B/out/deveco-linux-x64，溯源文件一并生成）
docker run -d --name deveco-build -v $B/src:/work/src -v $B/scripts:/work/scripts:ro \
  -v $B/out:/work/out harness-dev:2.1 sleep infinity
docker exec deveco-build bash /work/scripts/build-in-container.sh
docker rm -f deveco-build

# 2) 组装镜像（约 30 秒）。此时 emulator-state/Huawei 是空目录，得到的是“不带预置模拟器实例”的版本
cp -a $B/out/deveco-linux-x64 $B/out/BUILD-INFO.txt $B/out/linux-build.patch $B/image/
docker build -t harness-dev:2.2 $B/image

# 3) 预置模拟器实例（可选，约 2 分钟），然后再构建一次得到最终镜像（约 40 秒）
bash emulator-state/prepare.sh                   # 用上一步的 harness-dev:2.2 生成 emulator-state/Huawei
# 第 2 步留下的空目录要先删掉再拷,否则 cp 会把 Huawei/ 整个放进这个空目录里,变成 Huawei/Huawei/
rmdir $B/image/emulator-state/Huawei && cp -a emulator-state/Huawei $B/image/emulator-state/
docker build -t harness-dev:2.2 $B/image
```

几点说明：

- `$B/out/deveco-linux-x64` 已经有了（或从别的机器拷一份过来）就可以跳过第 1 步。同源码同脚本构建出的二进制 sha256 逐字节一致。
- 第 3 步要排在第 2 步之后：`prepare.sh` 是从 `harness-dev:2.2` 起容器来生成实例的（模拟器要窗口模式，用的是镜像入口自动拉起的虚拟显示器），所以得先有第 2 步的镜像。
- 不做第 3 步，镜像功能完全一样，只是没有现成的 `deveco_phone` 实例。新容器里要先建再启动：

  ```bash
  devecocli emulator create deveco_phone --device-type phone --os-version "HarmonyOS 6.1.1(24)" \
    --image-root /opt/emu-images --memory 4 --storage 32
  devecocli emulator start deveco_phone     # 全新实例首次启动约 85 秒;CLI 在 60 秒时会提示超时,之后会启动完成
  ```

- 按以上步骤重建出的实例约 0.8GB，比当前 `harness-dev:2.2` 里的大 60MB 左右（差在缓存分区文件 `cache.img`，不影响使用）。
- 这套步骤在 2026-11-24 完整跑过一遍，结果见下文“自检”。过程中发现并修掉了 `prepare.sh` 的一个问题：它导出的目录多一层 `.Huawei/`，照它重建出的镜像里找不到实例。现在脚本在导出后会核对布局。自检脚本里也有三项判定不严（安卓截图、界面验证、agent 安装启动），一并改成了看实际结果。

构建配方对齐上游 CI（`.gitcode/workflows/publish.yml`）：Ubuntu + Node 22 + bun 1.4.2 + 华为云 npm 镜像。

构建脚本默认带 **`--skip-agreement`**（上游构建脚本自带的开关）。需要与官方发布版行为一致的二进制时，用环境变量关掉：`docker exec -e SKIP_AGREEMENT=0 deveco-build bash /work/scripts/build-in-container.sh`。

## 用法

```bash
# 起容器（要 KVM；入口脚本会自动备好虚拟显示器）
docker run -d --name mydev --device /dev/kvm --shm-size=4g harness-dev:2.2 sleep infinity
docker exec -it mydev bash

deveco                                        # TUI
deveco serve --port 4096                      # 无头服务
deveco run --agent build --auto "构建这个工程"  # 无头 agent（--auto 自动批准工具权限）

devecocli emulator start deveco_phone         # 启动预置的模拟器(空载约 30 秒;服务器满载时实测 40～55 秒)
devecocli create --project-path ./Demo --app-name Demo --api-level 24   # 新建工程
```

### 模型配置

在项目根写 `deveco.json`（或全局 `~/.config/deveco/deveco.json`）。内置的 `@ai-sdk/anthropic` 可直接用，**地址必须带 `/v1`**（不带会打到网关的网页路由，表现为“模型响应意外结束”）：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "my-gateway": {
      "npm": "@ai-sdk/anthropic",
      "options": { "baseURL": "http://<网关>:3000/v1", "apiKey": "<令牌>" },
      "models": {
        "claude-sonnet-4-5": {},
        "deepseek-v4.1-flash": {}
      }
    }
  },
  "model": "my-gateway/claude-sonnet-4-5",
  "agent": { "ui_verification": { "model": "my-gateway/deepseek-v4.1-flash" } }
}
```

- 主对话模型：`model` 指定的那个，走 Anthropic 协议。
- 界面验证工具 `verify_ui` / `save_ui_screenshot` 需要**能看图的模型**：`agent.ui_verification.model`。它固定用 OpenAI 兼容协议去调“所配供应商的地址 + 所配的模型名”，所以这个模型名必须是网关在 `/v1/chat/completions` 路由上认识的真实名字。

### 看模拟器画面

窗口模式已经有虚拟显示器，用镜像自带的 x11vnc 暴露出来即可（起容器时加 `-p 5900:5900`）：

```bash
docker exec -d mydev x11vnc -display :0 -rfbport 5900 -passwd <密码> -forever -shared
# 本地用 VNC 客户端连 <服务器>:5900
```

## 镜像里做了哪些“非默认”的事

| 项 | 内容 | 原因 |
|---|---|---|
| 运行时依赖 | `/opt/deveco/node_modules`（341MB） | 鸿蒙能力由 npm 依赖形式的内建插件提供，不在二进制里。缺了它 deveco 能启动，但鸿蒙工具一个都没有 |
| `DEVECO_HOME` 适配目录 | `/opt/deveco-home`（软链接 + product-info.json） | 宿主层按 DevEco Studio 的外形识别工具链；实际构建走 `DEVECO_CLI_CLT_PATH` 的命令行工具模式 |
| 编译期开关 `--skip-agreement` | 产品协议的硬性检查直接放行 | 上游构建脚本自带的开关，注释写明用于源码/内部构建，发布版固定关闭。本镜像仅内部使用，所以开启（内部使用前已确认）。无头运行不再依赖本地的协议接受文件；实测删掉该文件后 agent 对话照常进行 |
| 协议接受 | 模拟器许可；另保留产品协议的接受记录 | 许可必须接受。产品协议的硬性检查已被上面的开关绕过，保留接受记录只是因为交互式界面（TUI）的引导流程只看本地记录、不看那个开关 |
| 隐私 | 关闭数据统计、工具改进计划、CLI 遥测、自动更新检查 | 三者默认开启；服务器上批量跑不向华为上报使用数据 |
| 冒烟等待 | `DEVECO_CLI_SMOKE_WAIT_MS=10000`（默认 3000） | 模拟器冷启动时应用首次启动可能超过 3 秒，会被 `devecocli run` 误判为 FAIL_CRASH |
| 窗口模式 | 入口脚本自动拉起 Xvfb :0，`DISPLAY=:0` | 无窗口模式在这套镜像里模拟器无法注册到 hdc；截图对比和 VNC 也要窗口模式 |
| 系统镜像软链接 | `/root/Library/Huawei/Sdk/system-image` | CLI 启动模拟器不带 `-imageRoot`，默认到这个位置找镜像 |
| 预置模拟器实例 | `deveco_phone`（已完成首次启动，0.76GB） | 全新实例首次启动约 85 秒，超过 CLI 的 60 秒等待；预置后首次启动 30 秒 |
| Lint 默认生效 | 给 `devecocli create` 的配置模板加一条规则 | 上游的默认配置会被检查器跳过，新建工程的 Lint 什么都不查却显示“无问题”。见下文 |

## 批量运行前必须知道的四条

**1. 用脚本直接调 CLI 新建工程时要指定 `--api-level 24`。** 命令行工具自带的 SDK 是 API 26，模拟器系统是 API 24（官方远端镜像目录里最新的就是 API 24，没有 26 的）。不指定时工程默认 API 26，能构建成功，但装到模拟器上会失败：`code:9568297 install failed due to older sdk version in the device`。已有工程则把 `build-profile.json5` 里的 `targetSdkVersion` / `compatibleSdkVersion` 设为 `"6.1.1(24)"`。

让 DevEco Code 的 agent 自己建工程则不需要操心：实测不给提示，它会自己发现并改成 `6.1.1(24)`，只是多花一点时间。想让它第一次就做对，可以写一条全局指令（`/root/.config/deveco/AGENTS.md`），镜像里目前没有加。

**2. 宿主机的 inotify 监听限额要放宽。** 所有容器都以 root 运行，共用同一份 inotify 额度；老内核默认只有 8192 个 watch，几个 hvigor 构建并发就会报 `ENOSPC: System limit for number of file watchers reached`。bms173 已设为 1048576 并写入 `/etc/sysctl.d/90-inotify-limits.conf`，换到别的机器要同样设置。

**3. 一个容器里只留一个模拟器实例，或者启动时指定设备。** 存在多个实例（哪怕是停止状态）时，`devecocli run` 会报 `DEVICE_SELECTION_REQUIRED`，需要加 `--device <名字或序列号>`。

**4. 鸿蒙和安卓模拟器同在一个容器时，安卓设备的名字会顺延。** 鸿蒙模拟器先占了 5555 端口，安卓模拟器会改用 5556/5557，在 adb 里显示为 `emulator-5556` 而不是常见的 `emulator-5554`。写死了设备名的脚本要用 `adb devices` 动态取，或者显式 `adb -s <序列号>`。

## 自检

换镜像、改 Dockerfile 之后跑一遍，确认没有把东西弄坏：

```bash
docker run -d --name selfcheck --device /dev/kvm --shm-size=4g harness-dev:2.2 sleep infinity
docker cp selfcheck.sh selfcheck:/opt/scripts/selfcheck.sh
# 不带模型（跳过 agent 部分）
docker exec selfcheck bash /opt/scripts/selfcheck.sh
# 带模型（agent 部分，需要网关令牌）
docker exec -e SELFCHECK_GATEWAY_TOKEN=<令牌> selfcheck bash /opt/scripts/selfcheck.sh
docker rm -f selfcheck
```

共 47 项，分五部分：静态配置、运行环境、基础功能（含安卓模拟器回归、双端共存、Lint）、agent、遥测。全部通过时退出码为 0。脚本里写死了二进制的 sha256，重新构建后要同步更新 `EXPECTED_SHA`。2026-11-24 在最终镜像（含 Lint 启用）上的结果：47 通过 / 0 失败 / 0 跳过，日志见 `evidence/selfcheck-20261124.log`。

有三项看的是实际结果，不是“命令没报错”：

- **安卓截图**：安卓系统刚报开机完成时桌面还没画出第一帧，这时截到的是全黑图（实测要再等 15～30 秒）。自检会等到画面不是纯色再截图。
- **界面验证**：agent 自己试探命令时的报错（比如敲了不存在的 `devecocli devices`）不代表工具失败。自检看的是工具调用记录在、没有工具级错误、截图确实落盘。
- **agent 自主安装启动**：前一部分已经把应用装上并启动过，进程本来就在。自检会先把应用停掉，再让 agent 做，跑完后进程活着才算数。

鸿蒙截图一项仍然只判断文件大小：截图命令只能输出 JPEG，镜像里没有现成的解码工具，做不了“画面是不是纯色”的检查。

agent 部分每次的完整输出保存在容器的 `/tmp/selfcheck-agent-1.log` ～ `-3.log`，有失败时可以进容器回看。

同一天另外按上文“怎么重建”只用本仓库的文件重建了一遍镜像（第 1 步沿用已有产物），在全新容器里不带模型令牌跑自检：44 通过 / 0 失败 / 1 跳过（跳过的是 agent 那一组，计 1 项），预置实例冷启动 40 秒，日志见 `evidence/selfcheck-rebuild-20261124.log`。那一次用的脚本还没加强上面三项的判定。

## 其他说明

- 1.17.9 已移除 `build_project` / `start_app` 这类内建工具，构建和运行由 agent 通过 bash 调 `devecocli`。现存的内建鸿蒙工具是 `verify_ui` / `get_ui_verification_log` / `save_ui_screenshot`。
- 只允许中国大陆 IP 使用（DevEco Code 的地区限制）。
- 不需要登录华为账号：构建、运行、模拟器、界面检查、配合自有模型对话都不需要。只有用华为提供的模型时才需要登录（且要求实名认证）。
- 语言服务（LSP）不可用：agent 拿不到即时代码诊断和格式化，只能靠构建发现编译错误。
- 命令沙箱不生效：agent 执行的命令不受“只读 / 仅工作区可写”约束，全部直接执行。用 `--auto` 无人值守时，容器就是唯一的安全边界。
- `check compat` 不可用：要求命令行工具 ≥ 26.0.1。
- **Lint 在这个镜像里默认生效，但要知道上游原版的行为。** 上游新建工程自带的 `code-linter.json5` 与检查器内置的默认配置完全相同，命令行模式下检查器遇到默认配置会跳过 ESLint 引擎，结果是“检查了 0 个文件、无问题”，是一个假的“全部通过”。镜像里用 `enable-lint.py` 给工程模板加了一条规则（`@typescript-eslint/no-unused-vars`，不检查未使用的函数参数，因为模板自己的 `EntryAbility.ets` 就有两个未使用的回调参数），之后新建工程的 Lint 默认就会执行推荐规则集和安全规则。只对镜像里新建的工程生效；已有的工程如果配置还是上游默认内容，需要自己改动一条规则或用 `--config-path`。汇总里的 `Files checked` 是有问题的文件数，引擎被跳过和检查过没问题时都显示 0，不能用它判断 Lint 是否真的跑了。
- 镜像设置了 `ENTRYPOINT`，会先启动虚拟显示器再执行命令。`docker run -it 镜像` 直接进 bash；`docker run 镜像 <命令> <参数>` 会经入口脚本执行该命令（`docker run 镜像 node server.js` 这类用法不受影响）；要跑 `bash -c` 请把 `bash` 显式写出来。不想要入口时用 `docker run --entrypoint bash ...`，此时虚拟显示器不会自动启动。
