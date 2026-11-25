# harness-dev:2.2-skillsrsi 使用指南

`harness-dev:2.2-skillsrsi` 在 `harness-dev:2.2` 之上叠了一层，把 SkillsRSI 0.4.1 和它依赖的东西装进了镜像。SkillsRSI 是一个“让模型自己改进迁移技能”的本地闭环工具：用一个小任务让 DevEco Code 照着技能手册迁移一遍并评测，再让模型诊断手册哪里有问题、改写、复验。这一页面向第一次用这个镜像的人：怎么拿到、怎么跑起来、怎么读结果。

- 只想赶紧跑起来：直接看下面的“一分钟版”。
- 想知道它测过什么、有哪些坑：看[测试报告](SKILLSRSI-IMAGE-TEST-REPORT.md)。
- 想知道镜像怎么做的、怎么重建、为什么这么做：看 [skillsrsi/README.md](../skillsrsi/README.md)。

如果你只是想在容器里用 DevEco Code 做鸿蒙开发，不需要这个镜像，用 `harness-dev:2.2` 就够了（[2.2 使用指南](USAGE-harness-dev-2.2.md)）。

## 一分钟版（在 173 服务器上）

```bash
# 1) 不花模型额度的自检：用“假模型”把整条流水线跑一遍，约 2 分钟
docker run --rm --device /dev/kvm --cpus 8 --memory 16g \
  -v /root/skillsrsi-selftest:/work/skillsrsi-selftest-out \
  harness-dev:2.2-skillsrsi /opt/scripts/skillsrsi-selftest.sh

# 2) 用真实模型跑一轮，约 3 分钟
docker run --rm --device /dev/kvm --cpus 8 --memory 16g \
  -e SKILLS_RSI_API_KEY="你的 Key" \
  -e SKILLS_RSI_BASE_URL="https://你的模型服务/v1" \
  -e SKILLS_RSI_MODEL="模型名" \
  -v /root/skillsrsi-out:/work/skillsrsi-out \
  harness-dev:2.2-skillsrsi /opt/scripts/skillsrsi-run.sh
```

两条命令跑完都在屏幕上留一行 `SkillsRSI 结束: 退出码 0 …`，结果在挂出来的目录里。模型服务需要满足什么条件见[第 5 节](#5-用真实模型跑一轮)。

## 1. 机器要求

| 项目 | 要求 | 不满足会怎样 |
|---|---|---|
| CPU | x86_64 | 镜像只有 x86_64 版 |
| KVM | 有 `/dev/kvm`，且当前用户可读写 | 模拟器起不来，第一轮迁移之后的评测无法进行 |
| Docker | 较新的版本即可 | — |
| 磁盘 | 导入镜像前至少 35G 可用（镜像 22.4G，导入包 8.1G） | `docker load` 中途失败 |
| 内存 | 每个容器建议留 16G（鸿蒙模拟器自己就占 4G） | 模拟器启动很慢，或被系统杀掉 |
| 网络 | 容器能访问你要用的模型服务 | 模型请求失败，这一轮以失败结束 |

跑一轮**不需要**访问外网：HMBot 包、示例源码和编译缓存在构建镜像时已经装好或预热过。

## 2. 拿到镜像

镜像没有推到镜像仓库，以导出包的形式分发。导出包在 173 的 `/root/harness-release/harness-dev-2.2-skillsrsi.tar.gz`，旁边有同名的 `.sha256` 文件。

**在 173 服务器（119.3.230.173）上**：镜像已经在那里，名字是 `harness-dev:2.2-skillsrsi`，直接跳到[第 3 节](#3-跑之前要知道的三件事)。需要有在这台机器上执行 `docker` 命令的权限。

**在其他机器上**：先导入。

```bash
scp root@119.3.230.173:/root/harness-release/harness-dev-2.2-skillsrsi.tar.gz .
scp root@119.3.230.173:/root/harness-release/harness-dev-2.2-skillsrsi.tar.gz.sha256 .
sha256sum -c harness-dev-2.2-skillsrsi.tar.gz.sha256   # 应为 8a0d32a796fc75f0191b9bab2cfac4b248d3bfc4771c394658f60b107298a025（macOS 上用 shasum -a 256）
docker load -i harness-dev-2.2-skillsrsi.tar.gz       # 镜像较大，需要几分钟
docker images harness-dev                             # 应看到 2.2-skillsrsi，镜像 ID 以 42ae0b9c1792 开头
```

导入后可以跑一次[第 4 节](#4-跑自检不需要模型)的自检，确认这台机器上的环境是通的。

## 3. 跑之前要知道的三件事

1. **必须用镜像自带的入口脚本启动。** 不要加 `--entrypoint`。入口脚本负责启动那块“看不见的显示器”，绕过它模拟器起不来。
2. **模型凭据只通过环境变量传入。** 镜像里、配方里、结果目录里都没有凭据。每轮的模型请求走 SkillsRSI 自己起的一个本机中转，DevEco Code 拿到的是一次性令牌，不是你的 Key。
3. **评测包已经预先确认过了。** SkillsRSI 0.4.1 要求“评测包被人确认过”才能使用，而它的命令行没有确认命令。镜像构建时代为确认了内置的 OpenCalc 评测包，确认人写的是 `skillsrsi-sandbox-image`。想换成自己的名字，运行时加环境变量 `SKILLS_RSI_REVIEWER="你的名字"`。

## 4. 跑自检（不需要模型）

```bash
docker run --rm --device /dev/kvm --cpus 8 --memory 16g \
  -v /root/skillsrsi-selftest:/work/skillsrsi-selftest-out \
  harness-dev:2.2-skillsrsi /opt/scripts/skillsrsi-selftest.sh
```

自检用一个“假模型”代替真实模型：它按剧本回答，让流程从头走到尾。因此自检的结论永远是“两边满分，保留基线”，这只说明环境是通的，**不说明优化有没有效果**。

正常的自检是这样的：

| 看什么 | 正常的结果 |
|---|---|
| 屏幕上最后几行 | 先出现 `127.0.0.1:5555`（模拟器已就绪），最后是 `SkillsRSI 结束: 退出码 0,用时 1xx 秒` |
| 总耗时 | 模拟器启动约 40 到 60 秒，运行约 110 秒 |
| `run/run.json` 里的 `status` | `completed` |
| `run/run.json` 里的 `verdict` | `no-verified-improvement` |
| `run/run.json` 里的 `stages` | 8 个阶段，每个都是 `completed` |

如果卡在模拟器启动，先确认容器里有 `/dev/kvm`、没有加 `--entrypoint`。

## 5. 用真实模型跑一轮

```bash
docker run --rm --device /dev/kvm --cpus 8 --memory 16g \
  -e SKILLS_RSI_API_KEY="你的 Key" \
  -e SKILLS_RSI_BASE_URL="https://你的模型服务/v1" \
  -e SKILLS_RSI_MODEL="模型名" \
  -v /root/skillsrsi-out:/work/skillsrsi-out \
  harness-dev:2.2-skillsrsi /opt/scripts/skillsrsi-run.sh
```

### 5.1 模型服务要满足什么

SkillsRSI 通过 OpenAI 兼容的 `/chat/completions` 接口调用模型，一轮里用到三种调用方式，模型服务都要支持：

| 调用方式 | 用在哪 | 具体要求 |
|---|---|---|
| 流式的工具调用 | 迁移（由 DevEco Code 发起） | 支持流式输出和工具调用 |
| 强制的工具调用 | 诊断 | 支持 `tool_choice: "required"` 和 `parallel_tool_calls: false`，一轮诊断最多 48 次 |
| JSON 输出 | 裁判打分、改写技能 | 支持 `response_format: {"type": "json_object"}` |

实测通过的模型是 `deepseek-v4.1-flash`（经 OpenAI 兼容的网关调用）。

**关于地址**：SkillsRSI 只接受 `https` 地址或本机回环地址（`127.0.0.1`、`localhost`）。如果模型服务是容器网络里的 http 地址（比如 `http://某个网关:3000/v1`），用 `--network` 把容器接到那个网络，地址照填，脚本会自动在容器本机转一层。

**关于思考模式**：默认 `SKILLS_RSI_THINKING=disabled`，会随请求发 `thinking: {"type": "disabled"}`。不支持这个参数的服务请设成 `provider-default`。

### 5.2 可以调的参数

| 环境变量 | 必填 | 说明 |
|---|---|---|
| `SKILLS_RSI_API_KEY` | 是 | 模型凭据 |
| `SKILLS_RSI_BASE_URL` | 是 | OpenAI 兼容接口的根地址 |
| `SKILLS_RSI_MODEL` | 是 | 模型名 |
| `SKILLS_RSI_OPTIMIZER` | 否 | `arkts-routed-bc`（默认）或 `skillopt`。两者只在“改写技能”这一步不同 |
| `SKILLS_RSI_THINKING` | 否 | `disabled`（默认）、`enabled`、`provider-default` |
| `SKILLS_RSI_TITLE` | 否 | 实验名称，写进运行记录 |
| `SKILLS_RSI_REVIEWER` | 否 | 填了就用这个名字重新确认评测包 |
| `SKILLS_RSI_DEVICE` | 否 | 鸿蒙设备号，默认 `127.0.0.1:5555` |
| `OUT_DIR` | 否 | 容器内的结果目录，默认 `/work/skillsrsi-out`，记得挂出来 |

### 5.3 耗时和模型请求次数

一轮真实运行约 3 分钟（含模拟器启动）。模型请求约 49 次：裁判 1 次，诊断最多 48 次，迁移期间 DevEco Code 自己发起的请求另算（实测 10 到 15 次）。排任务时按这个量估计额度。

## 6. 怎么读结果

结果在挂出来的目录里，约 5M：

| 文件 | 内容 |
|---|---|
| `recipe.json` | 这一轮实际用的配方，不含凭据 |
| `cli.log` | 命令行的完整输出 |
| `run/run.json` | 运行记录：各阶段用时、结论、模型请求次数、裁判的逐项判断、诊断结论 |
| `run/artifacts/baseline/pages/P01.jpeg`、`run/artifacts/baseline/replay/C01-2.jpeg`、`C02-3.jpeg` | 鸿蒙模拟器上的实际截图 |
| `run/baseline-judge-model.json` | 裁判模型的原话 |
| `run/artifacts/v2/analysis/analysis.json` | 诊断结论；同目录的 `tool-transcript.jsonl` 是诊断取证的每一步 |
| `run/artifacts/baseline/migration-trace.jsonl` | DevEco Code 的完整执行轨迹（调用了哪些工具） |
| `run/baseline/workspace/` | 迁移出来的代码和模型先写的规格说明 |
| `run/candidate-skills/` | 改写后的技能手册（只有走到“改写技能”这一步才有） |

`run/run.json` 里的 `verdict` 是最终结论：

| 值 | 含义 |
|---|---|
| `improved` | 已验证改善，采用了新手册。需要先做裁判校准，默认配置下不会出现 |
| `no-verified-improvement` | 生成了新手册，但复验后没有可验证的提升，保留原手册 |
| `no-actionable-work` | 诊断没有发现问题，没有生成新手册 |
| `candidate-gate-rejected` | 新手册没通过结构检查（比如改了不该改的部分） |
| `inconclusive` | 证据不足，没法下结论 |

`status` 是这一轮有没有跑完，`completed` 才算正常；`failed` 时同一个文件里的 `error` 有原因。

## 7. 已知限制

- **示例任务对强模型来说太简单。** 镜像里自带的示例只迁移一个文件。实测无论用哪种模型、哪种优化器，基线都是满分，结论都是“无可执行工作项”。想看到“改写技能”那一步真的起作用，需要一个基线会出错的任务，并为此另外制作评测包。
- **默认是“影子评分”。** 裁判没有经过校准，即使候选手册更好，也只会记录成绩、不会标记为正式采用。
- **一个容器同时只能跑一轮。** 实验目录有进程锁。要并发就开多个容器，每个容器独占一个模拟器，按每个 16G 内存估。
- **只支持内置的这一个示例。** 要优化你自己的应用，需要按 SkillsRSI 的格式制作评测包，并自己确认；这部分不在本镜像的验证范围内。
- **执行顺序审计的结果不稳定。** 0.4.1 新增的这道审计，实测在“违规”“需要人工复核”之间变化，取决于模型先写规格还是先写代码。默认的影子评分下它不阻断流程。

## 8. 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| 一启动就报“模拟器启动超时”，或日志里有 `did not appear in hdc list targets` | 容器里没有 `/dev/kvm`；或者加了 `--entrypoint`，容器里没有“看不见的显示器” | 加上 `--device /dev/kvm`；去掉 `--entrypoint`，用镜像自带的入口 |
| 报 `需要通过环境变量 SKILLS_RSI_…` | 三个必填的环境变量没给全 | 按第 5 节把 Key、地址、模型名传进去 |
| 报 `模型接口需要 HTTPS 或本机回环 HTTP` | 传给 `SKILLS_RSI_BASE_URL` 的不是 https 地址，也不是本机回环地址，而且不是 `http://主机:端口/...` 这种形式 | 用 https 地址；或确认地址以 `http://` 开头且带端口，让脚本自动转发 |
| 模型请求返回 400 或 404 | 模型名不对，或者这个服务不支持三种调用方式里的某一种 | 换成实测过的模型；或对照 5.1 节逐项确认 |
| 报 `此实验目录已有控制台或 CLI 进程` | 同一个容器里已经在跑一轮 | 一个容器只跑一轮；并发就开多个容器 |
| 评测阶段报 `HarmonyOS device is not connected` | 模拟器没就绪就进入了评测 | 重跑一次；仍不行就查容器里的 `/tmp/skillsrsi-emulator.log` |
| 想看模拟器画面 | — | 和 2.2 一样，可以接 VNC，见 [2.2 使用指南的 5.4 节](USAGE-harness-dev-2.2.md) |

## 9. 自己重建镜像

需要先拿到 SkillsRSI 的发布包（内部项目，不在本仓库），然后在本目录执行 `docker build`。步骤和原因见 [skillsrsi/README.md](../skillsrsi/README.md)。
