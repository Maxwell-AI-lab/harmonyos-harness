# SkillsRSI 沙箱：harness-dev:2.2-skillsrsi

> 本目录是 `harness-dev:2.2-skillsrsi` 的材料。这个镜像在 `harness-dev:2.2` 之上叠了一层，把 SkillsRSI 0.4.1 及其依赖装进镜像，让“技能自优化”的完整流程可以在 Linux 容器里无人值守地跑。
>
> - 只是想用这个镜像：看 [使用指南](../docs/USAGE-harness-dev-2.2-skillsrsi.md)。
> - 想知道它测过什么、有哪些坑：看[测试报告](../docs/SKILLSRSI-IMAGE-TEST-REPORT.md)。
> - 想知道镜像怎么做的、怎么重建、为什么这么做：看本页。

## SkillsRSI 是什么

SkillsRSI 是一个本地闭环工具：拿一个小迁移任务，让 DevEco Code 照着一份“迁移技能”（写给模型看的操作手册）迁移一遍并评测；模型读迁移轨迹和评测结果，诊断手册哪里有问题；如果发现问题，就改写手册，再用同一个任务复验，成绩不降且至少一项变好才采用新手册。被优化的对象只有那份技能手册的 Markdown，模型和 DevEco Code 本身不变。

一轮完整流程有八个阶段：冻结材料 → 冻结评测包 → 设备预检 → 基线迁移和评测 → 诊断 → 改写技能 → 候选迁移和评测 → 选择版本。

## 目录内容

| 路径 | 作用 |
|---|---|
| `Dockerfile` | 镜像定义：`FROM harness-dev:2.2`，复制下面的文件后执行 `build.sh` |
| `build.sh` | 构建步骤：校验并安装 SkillsRSI、装 HMBot、准备示例、确认评测包、预热编译缓存 |
| `scripts/skillsrsi` | SkillsRSI 命令行入口（用 DevEco 自带的新版 Node） |
| `scripts/skillsrsi-run.sh` | 在容器里跑一轮：开模拟器、生成配方、运行、把结果拷到输出目录 |
| `scripts/skillsrsi-selftest.sh` | 不花模型额度的自检 |
| `selftest/mock_model.py` | 自检用的“假模型”：按剧本回答 SkillsRSI 的四类请求 |
| `selftest/NumberFormatter.ets` | 自检用的“迁移产物”：让假模型写出来的、能通过示例任务 15 项检查的实现 |
| `evidence/` | 在最终镜像上跑出来的证据 |
| `build/BUILD-INFO.txt` | 最终镜像里的构建信息（各组件版本与指纹） |

**SkillsRSI 的发布包不在这个仓库里。** 它是内部项目的运行包，需要单独获取（见下面的“重建镜像”）。

## 镜像里做了什么

`build.sh` 在 2.2 之上做了六件事：

| 步骤 | 做了什么 | 不做会怎样 |
|---|---|---|
| 1 | 校验 `skills-rsi-0.4.1.tgz` 的 SHA-256 后解压到 `/opt/skills-rsi` | — |
| 2 | 补一个软链接 `/opt/deveco-home/jbr/Contents/Home` 指向系统 JDK 21 | SkillsRSI 的准备脚本按 DevEco Studio 的目录结构找 Java，找不到就报“缺 JBR” |
| 3 | 用 `/opt/deveco-home/tools/node/bin/node`（24.14.1）运行安装和准备 | 镜像自带的系统 Node 是 24.0.0，SkillsRSI 要求 24.9 以上 |
| 4 | 安装 HMBot 0.1.6（官方包，构建时联网下载并校验）、准备 OpenCalc 示例 | — |
| 5 | 确认内置评测包，确认人默认是 `skillsrsi-sandbox-image` | 0.4.1 要求评测包被确认后才能使用，否则第一个阶段就失败 |
| 6 | 用一份能通过检查的实现跑一次评测器，把 hvigor 和 npm 的缓存预热 | 第一次编译要联网下载 pnpm，网络不通时会卡满 4 分钟后失败 |

另外，`/opt/skills-rsi-home/examples/opencalc` 是一个固定名字的软链接，指向准备脚本生成的那份示例目录（它的名字带随机后缀），方便脚本和文档用固定路径引用。

镜像里**没有**任何模型凭据，也**没有** `rsi.agents` 标签：rsi 的调度器不会把普通任务派到这个镜像上。

## 重建镜像

前提：

- 本机已有 `harness-dev:2.2`（ID 以 `01ef464e` 开头；导入方法见 [2.2 使用指南](../docs/USAGE-harness-dev-2.2.md)）。
- 拿到 SkillsRSI 的发布包 `skills-rsi-0.4.1.tgz`（内部项目，请向发布该包的子平台或作者索取），放在本目录下。它的 SHA-256 应为：

  ```
  9aedc5909c205c6e45cb7cdfd4f035704c15005d1829f98bf8c126eb721cd62c
  ```

  构建时会核对，不一致会直接失败。
- 构建时能访问 npm 源和 GitHub（codeload.github.com）：构建过程中要下载 HMBot 包和 OpenCalc 源码。

```bash
# 把 skills-rsi-0.4.1.tgz 放进 skillsrsi/ 之后，在本目录执行
docker build -t harness-dev:2.2-skillsrsi .

# 想把评测包的“确认人”换成自己的名字
docker build -t harness-dev:2.2-skillsrsi --build-arg REVIEWER="你的名字" .
```

构建本身约 25 秒，加上下载和预热，实测一分钟以内。构建完可以直接跑自检验证（见使用指南第 4 节）。

`*.tgz` 已在仓库的 `.gitignore` 里，发布包不会被误提交。

## 几个设计上的取舍

- **叠一层，不改 2.2。** 2.2 的入口脚本、预置模拟器、环境变量都没动，原有用法不受影响；SkillsRSI 的东西全部通过新增的 `/opt/scripts/skillsrsi*` 入口使用。
- **模拟器沿用 2.2 的启动方式。** 脚本调用的是 `devecocli emulator start deveco_phone`，和 2.2 使用指南一致。评测脚本不会自己唤醒屏幕，所以脚本在模拟器就绪后把它设成常亮并回到桌面。
- **模型地址只认 https 或本机回环。** 这是 SkillsRSI 自己的限制。如果给它的是容器网络里的 http 地址，`skillsrsi-run.sh` 会用 `socat` 在本机 `127.0.0.1:18080` 转一层。
- **输出只带证据。** 一次运行的完整目录约 200M，几乎全是每轮迁移时的工作副本和编译中间产物；脚本只拷出运行记录、截图、裁判和诊断的原话、生成的代码，约 5M。
- **自检用的“迁移产物”是为本仓库专门写的。** 它按示例任务的 13 项行为检查实现，没有使用 OpenCalc 的源码（OpenCalc 是 GPL-3.0，本仓库是 MIT）。

## 自检用的假模型回答什么

| 请求 | 假模型的回答 |
|---|---|
| 迁移（DevEco Code 发起，带工具） | 先调用 `skill` 加载技能，再调用 `write` 写出 `selftest/NumberFormatter.ets`，然后结束 |
| 裁判打分 | 照抄机械回放和页面取证的结果，不做语义判断 |
| 诊断（带工具的多轮取证） | 第一轮调用 `list`，第二轮调用 `submit_analysis` 交一份占位的分析 |
| 改写技能 | 在技能手册末尾追加一段占位文字 |
| 其他（如 DevEco Code 生成会话标题） | 固定回复 |

所以自检的结论永远是“两边满分，保留基线”。它只能说明环境是通的，不能说明优化有没有效果。
