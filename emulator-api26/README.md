# 鸿蒙模拟器升级到 API 26（harness-dev:2.3）

基于 `harness-dev:2.2`，把鸿蒙模拟器的系统从 HarmonyOS 6.1.1（API 24）换成 **HarmonyOS 7.0.0（API 26）**，和命令行工具自带的 SDK（API 26）配成同一代。

| 项 | 值 |
|---|---|
| 镜像 | `harness-dev:2.3`（6d2657372fb0，29.9GB；= 2.2 + 7.6GB） |
| 系统镜像 | HarmonyOS 7.0.0(26.0.0)，包版本 7.0.0.107，从官方目录下载（`devecocli emulator image download`） |
| 默认实例 | `deveco_phone`（API 26），新容器首次启动 41～51 秒（服务器负载 45～60 时） |
| 切换系统版本 | `/opt/scripts/switch-emulator.sh 24\|26\|reset\|show` |
| 自检 | `/opt/scripts/selfcheck.sh`，72 项，2026-11-24 在最终镜像上全部通过 |
| 使用指南 | [harness-dev:2.3 使用指南](../docs/USAGE-harness-dev-2.3.md) |

## 为什么要换

2.2 里构建用的 SDK 是 API 26，模拟器的系统是 API 24，两者差两代。实测这会带来两个问题：

| | 2.2（模拟器 API 24） | 2.3（模拟器 API 26） |
|---|---|---|
| 默认新建的工程（API 26）装到模拟器上 | 失败，`9568297 install failed due to older sdk version in the device`；必须带 `--api-level 24` 新建 | 成功 |
| 代码里用 API 26 才有的接口 | 构建、ArkTS 检查、Lint 都不提示，运行时崩溃 `xxx is not callable` | 正常工作 |
| 按 API 24 做的工程 | 能装能跑 | 能装能跑（新系统兼容旧工程） |

也就是说，换成 API 26 的模拟器之后，2.2 文档里“新建工程必须指定 API 24”“不要用 API 26 才有的接口”这两条规则都不再需要。

## 目录内容

```
Dockerfile            harness-dev:2.3 的镜像定义（FROM harness-dev:2.2）
prepare.sh            生成构建输入：下载 API 26 系统镜像、新建实例并完成首次启动、导出两套实例状态
switch-emulator.sh    切换系统版本的脚本（打进镜像的 /opt/scripts/）
selfcheck.sh          镜像自检脚本（打进镜像的 /opt/scripts/）
build/BUILD-INFO.txt  构建溯源：各组件版本、文件大小、镜像 ID、导出包校验和
evidence/             自检日志、自检截图、真实迁移工程的测试日志
```

`build-inputs/` 是 `prepare.sh` 的产物（约 6.3GB），不入库。

## 怎么重建

前提：x86_64 机器、Docker、`/dev/kvm`，本机已有 `harness-dev:2.2`，能访问华为的服务器。

这个目录合并到 main 之前只在分支 `feat/harness-dev-2.3` 上，克隆时要带上分支名；合并之后可以去掉 `-b` 那一段。

```bash
git clone -b feat/harness-dev-2.3 https://github.com/Maxwell-AI-lab/harmonyos-harness.git && cd harmonyos-harness/emulator-api26
bash prepare.sh                 # 约 6 分钟；产物在 ./build-inputs/
docker build -t harness-dev:2.3 build-inputs
```

`prepare.sh` 做了四件事：

1. 在一个临时的 `harness-dev:2.2` 容器里，用 `devecocli` 下载官方系统镜像 `HarmonyOS 7.0.0(26.0.0)`（手机，x86，4.6GB）。
2. 取出 2.2 预置的 API 24 实例状态，原样保存。
3. 用新镜像新建一个实例，启动一次到开机完成，再正常停止。这一步每个实例只需做一次；做过之后，以后每个新容器的首次启动是正常开机（约 1 分钟），而不是首次初始化（约 2 分钟）。
4. 导出实例状态：关掉热启动、去掉内存快照和日志，实例改名为 `deveco_phone`。

## 设计上的几个决定

**默认实例关掉了热启动。** `devecocli emulator create` 新建的实例默认 `isHotBoot=true`：停止时保存内存快照（`ram.bin`，约 2.5GB），下次启动从快照恢复，只要十几秒。但实测从快照恢复后，来宾系统里的调试服务偶尔起不来，表现为 `hdc list targets` 里一直看不到设备，重启 hdc 服务也没用——同一个容器里停了再起，5 次里卡住 2 次。把实例配置里的 `isHotBoot` 改成 `false` 之后，每次都是正常开机，连续启停都正常，实例状态也从 3.4GB 降到约 0.9GB。代价是启动慢二三十秒。6.1.1 的预置实例本来就是这样配置的，所以它在 2.2 里一直很稳。

**实例名沿用 `deveco_phone`。** 同事原来用的 `devecocli emulator start deveco_phone` 不用改。

**API 24 保留，用切换脚本而不是两个实例并存。** 容器里有两个模拟器实例时（停止的也算），`devecocli run` 会报 `DEVICE_SELECTION_REQUIRED`，必须加 `--device`。所以镜像里默认只放一个实例，另一套状态放在 `/opt/emulator-state/api24`，要的时候用脚本换上去。同事的迁移工程是按 API 24 做的，这些工程在 API 26 上能跑；需要严格按 API 24 验证效果时（比如截图对比），切回去就行。

## 自检

换镜像、改 Dockerfile 之后跑一遍，确认没有把东西弄坏：

```bash
docker run -d --name selfcheck --device /dev/kvm --shm-size=4g harness-dev:2.3 sleep infinity
docker exec selfcheck bash /opt/scripts/selfcheck.sh                                  # 不带模型（跳过 agent 部分）
docker exec -e SELFCHECK_GATEWAY_TOKEN=<令牌> selfcheck bash /opt/scripts/selfcheck.sh # 带模型
docker rm -f selfcheck
```

2026-11-24 在最终镜像（`6d2657372fb0`）新起的容器里带模型跑的结果：**72 项通过，0 失败，0 跳过**，日志见 `evidence/selfcheck-2.3-20261124.log`。

另外拿同事流水线里 4 个真实的迁移工程（cofi、simple-calendar、omni-notes、mifareclassictool，都是按 API 24 做的）在 API 26 的模拟器上跑了一遍：全部构建成功、安装启动成功、界面正常显示。日志见 `evidence/real-migrated-apps-20261124.log`。这几个工程的截图是同事流水线的产物，没有放进公开仓库。

如实说明：自检脚本本身出过两轮错（读错了版本信息文件、少写了一个进入工程目录的命令、两处判定条件写得不对），都不是镜像的问题，修正之后才得到上面的结果。

有几项是专门为这次升级加的，都是看实际结果的：

- 默认工程（不指定 API 级别）能装到模拟器上并启动。
- 按 API 24 做的工程能装到 API 26 的模拟器上并启动。
- 调用 API 26 才有的接口 `fs.listFileExtSync` 能正常返回（在 API 24 的系统上它会崩）。
- 模拟器停掉之后能在同一个容器里重新启动。
- 切换到 API 24、启动、装 API 24 的工程、切回 API 26、启动、恢复成干净实例。

脚本里写死了二进制的 sha256 和系统镜像的包版本，重新构建或重新下载之后要同步更新 `EXPECTED_SHA`、`EXPECTED_IMG_VER`。

## 已知限制

- **启动比热启动慢。** 热启动（从内存快照恢复）只要十几秒，但不可靠，所以没用。预置实例每次是正常开机，负载 45～60 时实测 41～51 秒，切到 API 24 的实例是 36 秒。
- **自己新建的实例默认开着热启动。** 用 `devecocli emulator create` 另建实例后，按使用指南第 5.6 节把它关掉。
- **切换和恢复会丢数据。** `switch-emulator.sh` 的任何一种操作都会把当前实例换成一份干净的，里面装过的应用和数据没有了。需要保留的东西先取出来。
- **API 24 的系统镜像仍在镜像里。** 它在 2.2 的层里，删不掉；切换脚本要用它。
- **换系统版本后界面细节可能不同。** 同一个应用在 API 24 和 API 26 上的显示（字体、状态栏、锁屏等）可能有差别。做截图对比之类的验证时，要确认用的是哪一个版本。
