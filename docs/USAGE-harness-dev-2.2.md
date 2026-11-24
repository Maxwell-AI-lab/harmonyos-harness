# harness-dev:2.2 使用指南

> 这是 2.2 的指南。新做的 `harness-dev:2.3` 在 2.2 的基础上把鸿蒙模拟器升级到了 API 26，新建工程不用再带 `--api-level 24`，用法更简单，请看 [2.3 使用指南](USAGE-harness-dev-2.3.md)。下面“必须带 `--api-level 24`”“不要用 API 26 才有的接口”这两条只适用于 2.1 / 2.2。

`harness-dev:2.2` 是一个“鸿蒙 + 安卓”一体化开发环境的 Docker 镜像：两端的构建工具链、两端的模拟器、AI 编程工具（DevEco Code、devecocli、Claude Code）都已经装好。这一页面向第一次用这个镜像的人：怎么拿到、怎么跑起来、怎么开始干活。

- 只想赶紧跑起来：直接看下面的“一分钟版”。
- 想知道它测过什么、有哪些坑：看[测试报告](DEVECO-CODE-LINUX-TEST-REPORT.md)。
- 想知道镜像怎么做的、怎么重建、怎么自检：看 [deveco-code/README.md](../deveco-code/README.md)。

## 一分钟版（在 173 服务器上）

```bash
docker run -d --name my-dev --device /dev/kvm --shm-size=4g harness-dev:2.2 sleep infinity
docker exec -it my-dev bash

devecocli emulator start deveco_phone       # 启动预置的模拟器，约 30 秒
deveco run --agent build --auto "构建这个工程并安装到模拟器上启动"    # 要先在工程里配好模型
```

最后一行需要一个模型。模型怎么配见[第 4 节](#4-配模型)；`my-dev` 换成你自己的名字。

## 1. 机器要求

| 项目 | 要求 | 不满足会怎样 |
|---|---|---|
| CPU | x86_64 | 镜像只有 x86_64 版 |
| KVM | 有 `/dev/kvm`，且当前用户可读写 | 模拟器起不来。只构建、不跑模拟器可以不要 |
| Docker | 较新的版本即可 | — |
| 磁盘 | 导入镜像前至少 35G 可用（镜像 22.3G，导入包 8.1G） | `docker load` 中途失败 |
| 内存 | 跑模拟器时，建议每个容器留 8G 以上（鸿蒙模拟器自己就占 4G） | 模拟器启动很慢，或被系统杀掉 |
| 网络 | 中国大陆 IP（DevEco Code 的地区限制）；能访问你要用的模型服务 | DevEco Code 的 agent 拒绝运行 |
| 系统设置 | 放宽“文件监听数”上限，见下 | 多个构建并发时报 `System limit for number of file watchers reached` |

放宽文件监听数，在宿主机上执行一次：

```bash
sudo tee /etc/sysctl.d/90-inotify-limits.conf >/dev/null <<'EOF'
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 8192
EOF
sudo sysctl --system
```

原因：容器里的进程都以 root 身份运行，共用宿主机 root 的这一份额度，老内核默认只有 8192。放宽上限本身不占内存。173 上已经设置过。

## 2. 拿到镜像

镜像没有推到镜像仓库，以导出包的形式分发。导出包在 173 的 `/root/harness-release/harness-dev-2.2.tar.gz`（8.1G），旁边有同名的 `.sha256` 文件。

**在 173 服务器（119.3.230.173）上**：镜像已经在那里，名字是 `harness-dev:2.2`，直接跳到[第 3 节](#3-起容器)。需要有在这台机器上执行 `docker` 命令的权限。

**在别的机器上**：先把导入包拷过来，再导入。

```bash
scp root@119.3.230.173:/root/harness-release/harness-dev-2.2.tar.gz .
sha256sum harness-dev-2.2.tar.gz        # 应为 e9512407296bed5a293f10a603200797cbf3b34a6e4c39349b0f64109b1f3f95(macOS 上用 shasum -a 256)
docker load -i harness-dev-2.2.tar.gz   # 镜像较大，需要几分钟
docker images harness-dev               # 应看到 harness-dev  2.2  22.3GB
```

**通过 rsi 流水线用**：流水线和镜像在同一台服务器上，在任务配置里把镜像名指定成 `harness-dev:2.2` 就行，不用传包。

## 3. 起容器

```bash
docker run -d --name zhangsan-dev \
  --device /dev/kvm --shm-size=4g \
  -p 127.0.0.1:5901:5900 \
  -v "$PWD/myapp:/work" \
  harness-dev:2.2 sleep infinity

docker exec -it zhangsan-dev bash
```

| 参数 | 作用 |
|---|---|
| `--name` | 容器名。每人用自己的名字，别重复 |
| `--device /dev/kvm` | 模拟器必须要。只构建可以去掉 |
| `--shm-size=4g` | 模拟器需要的共享内存 |
| `-p 127.0.0.1:5901:5900` | 给“看模拟器画面”用的端口。不需要看画面可以去掉；多人共用一台机器时，`5901` 每人换一个没被占用的 |
| `-v "$PWD/myapp:/work"` | 把宿主机上的工程目录挂进容器的 `/work`。没有工程可以去掉 |
| `sleep infinity` | 让容器一直开着，你进去后手动操作 |

进去之后就是一个完整的命令行环境，工程在 `/work`。敲 `exit` 退出，容器还在后台跑，下次用 `docker exec -it zhangsan-dev bash` 再进来。不要了就 `docker rm -f zhangsan-dev`。

两个要知道的行为：

- 容器一启动就会自动拉起一块“看不见的显示器”，因为模拟器必须以窗口模式运行。你不用管它。
- 这个镜像设置了入口脚本：`docker run 镜像 <命令>` 会先起显示器再执行命令；想执行一串命令，要把 `bash` 写全，写成 `docker run 镜像 bash -c "…"`。

## 4. 配模型

DevEco Code 的 agent 需要一个大模型。**不需要登录华为账号**，用你们自己的模型服务就行。在工程根目录写一个 `deveco.json`（也可以写在全局 `~/.config/deveco/deveco.json`）：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "my-gateway": {
      "npm": "@ai-sdk/anthropic",
      "options": { "baseURL": "http://<网关地址>:3000/v1", "apiKey": "<令牌>" },
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

- `baseURL` **必须以 `/v1` 结尾**。少了它，对话会报“模型响应意外结束”。
- `model` 是主对话用的模型，走 Anthropic 协议。
- 让 agent 看界面（`verify_ui`、`save_ui_screenshot`）需要一个**能看图的模型**，配在 `agent.ui_verification.model`。这个名字必须是你的模型服务在 OpenAI 兼容接口上认识的真实名字。
- 令牌不要提交到代码仓库。
- 只用命令行工具（构建、装包、跑模拟器）不需要配模型。

## 5. 开始干活

下面的命令都在容器里执行。

### 5.1 启动模拟器

```bash
devecocli emulator start deveco_phone     # 启动预置的模拟器，空载约 30 秒
devecocli device list                     # 能看到 deveco_phone 就是好了
```

鸿蒙和安卓的模拟器都有。安卓的用 `/opt/scripts/start-android.sh` 启动。

### 5.2 用命令行新建一个工程

```bash
cd /work
devecocli create --project-path ./Demo --app-name Demo --api-level 24
cd Demo
devecocli build      # 构建
devecocli run        # 安装到模拟器并启动
```

`--api-level 24` 不能省，原因见[第 6 节](#6-批量运行和无人值守前必读)。工程建在 `/work` 下，宿主机的 `myapp` 目录里能直接看到。

### 5.3 让 agent 来做

```bash
cd /work/Demo
deveco run --agent build --auto "构建这个工程并安装到模拟器上启动"
```

`--auto` 表示自动批准 agent 的所有操作，不需要人在旁边确认。交互式的用法是直接敲 `deveco`。

### 5.4 看模拟器画面

不需要装任何东西，镜像里自带 VNC 服务。在宿主机上执行（把密码换成你自己的，密码里不要有空格）：

```bash
docker exec -d zhangsan-dev x11vnc -display :0 -rfbport 5900 -passwd 你的密码 -forever -shared -noxdamage -repeat -cursor arrow
```

- Docker 在你本机：用 VNC 客户端连 `localhost:5901`。
- Docker 在远程服务器上：先开一条隧道，再连本地端口（把地址换成你的服务器）。

  ```bash
  ssh -N -L 5901:127.0.0.1:5901 root@119.3.230.173     # 保持这个窗口开着
  ```

  然后 VNC 客户端连 `localhost:5901`。

只要截图、不要实时画面的话，不用 VNC：

```bash
hdc shell snapshot_display -f /data/local/tmp/screen.jpeg          # 鸿蒙
hdc file recv /data/local/tmp/screen.jpeg /work/screen.jpeg
adb exec-out screencap -p > /work/screen.png                       # 安卓
```

鸿蒙的截图必须先存到模拟器的 `/data/local/tmp/` 下，再取出来。

## 6. 批量运行和无人值守前必读

1. **新建工程要带 `--api-level 24`。** 命令行工具自带的 SDK 是 API 26，模拟器的系统是 API 24。不带这个参数，工程能构建成功，但装不上模拟器（报 `9568297`）。已有工程就把 `build-profile.json5` 里的 `targetSdkVersion`、`compatibleSdkVersion` 改成 `"6.1.1(24)"`。让 agent 自己建工程时不用管，它会自己改对。
2. **不要用 API 26 才有的接口。** 同样是这个版本差：代码里用了 API 26 才有的接口，构建和各项检查都不会提示，装到模拟器上一运行就崩（`xxx is not callable`）。
3. **宿主机要放宽文件监听数。** 见[第 1 节](#1-机器要求)。
4. **一个容器里只留一个模拟器实例。** 有多个实例时（停止的也算），`devecocli run` 会报 `DEVICE_SELECTION_REQUIRED`，需要加 `--device <名字>`。
5. **两种模拟器同在一个容器时，安卓设备名会顺延。** 鸿蒙先占了 5555 端口，安卓会变成 `emulator-5556`。脚本里要用 `adb devices` 动态取设备名。
6. **用 `--auto` 无人值守时，容器是唯一的安全边界。** DevEco Code 的命令沙箱在 Linux 上不生效，agent 执行的命令不受“只读”“只能写工作区”这类限制。

## 7. 常见问题

| 现象 | 原因 | 办法 |
|---|---|---|
| 装包报 `9568297 install failed due to older sdk version in the device` | 工程要求的系统版本（API 26）比模拟器（API 24）新 | 新建时带 `--api-level 24`；或把 `build-profile.json5` 里的两行改成 `"6.1.1(24)"` |
| 应用一启动就崩，日志里有 `xxx is not callable` | 用了 API 26 才有的接口 | 换成 API 24 也有的写法，或用 `try/catch` 包住 |
| `devecocli run` 报 `DEVICE_SELECTION_REQUIRED` | 容器里有多个模拟器实例 | 只留一个实例，或加 `--device <名字>` |
| `devecocli run` 报 `FAIL_CRASH`，但应用其实开着 | 模拟器冷启动时应用启动慢，被冒烟检查误判。镜像里已经把等待时间放宽到 10 秒，正常情况不会出现 | 确认应用在运行就可以忽略，或重新执行一次 |
| 并发构建报 `System limit for number of file watchers reached` | 宿主机的文件监听数上限太低 | 按第 1 节放宽 |
| 对话报“模型响应意外结束” | `deveco.json` 里的地址少了 `/v1` | 把 `baseURL` 改成以 `/v1` 结尾 |
| 界面验证提示未配置多模态模型 | 没配能看图的模型 | 在 `deveco.json` 里配 `agent.ui_verification.model` |
| `docker run 镜像 -c "…"` 没有执行 | 镜像有入口脚本，不会自动补 `bash` | 写成 `docker run 镜像 bash -c "…"` |
| 启动模拟器报 `was launched but did not appear in hdc list targets within the timeout` | 两种可能：一是你用 `--entrypoint` 绕过了入口脚本，容器里没有“看不见的显示器”；二是这是一个全新实例，第一次启动要约 85 秒，而命令只等 60 秒 | 前者：去掉 `--entrypoint`，让入口脚本自动起显示器。后者：是误报，稍等它会启动完成；预置的 `deveco_phone` 没有这个问题 |
