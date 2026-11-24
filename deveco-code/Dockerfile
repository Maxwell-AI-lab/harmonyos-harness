# harness-dev:2.2 = harness-dev:2.1 + DevEco Code(Linux 版,从源码自行构建)
#
# DevEco Code 官方只发布 Windows / macOS 包(README:"暂不支持 Linux")。本镜像里的 Linux 版来自:
#   源码   https://gitcode.com/openharmony-sig/deveco-code(提交与构建时间见 /opt/deveco/BUILD-INFO.txt)
#   补丁   /opt/deveco/linux-build.patch(2 个文件 / 3 处改动:构建目标加 linux、ripgrep 走 npm 的 Linux 平台包)
#   构建   同目录 build-in-container.sh(配方对齐上游 CI:ubuntu + Node 22 + bun 1.4.2;同参数可复现,sha256 见构建日志)
#            默认带 --skip-agreement:上游构建脚本自带的开关,把“每次模型请求前的产品协议检查”编译为直接放行。
#            上游注释写明它用于源码/内部构建,发布版固定关闭。本镜像仅内部使用,故开启(用户 2026-11-23 确认)。
#
# 注意 /opt/deveco/node_modules 不能省:鸿蒙能力(构建 / 运行 / 设备 / 界面验证)由内建插件 deveco-harness 提供,
# 它不在二进制里,而是平台包 package.json 声明的 npm 依赖。缺了它,deveco 仍能启动(--version / --help / --serve 正常),
# 但插件列表为空、技能只有 2 个、鸿蒙工具一个都没有——这是只做冒烟测试最容易漏掉的坑。
# (另注:1.17.9 已移除 build_project / start_app 这类内建工具,构建和运行由 agent 经 bash 调 devecocli 完成。)
#
# Linux 上两个环境变量各管一层:
#   DEVECO_CLI_CLT_PATH  基础镜像已设(=/opt/command-line-tools)。DevEco Code 内置的 deveco-cli 在 Linux 上
#                        只支持这种"命令行工具"模式(其源码明确拒绝在 Linux 上使用 DevEco Studio),
#                        构建 / 运行 / 模拟器 / hdc 都走它,路径表与 CLT 目录逐一对应。
#   DEVECO_HOME          宿主层用它做两件事:解锁依赖工具链的 skill(hmos-arkui-develop-skill)、定位 hdc。
#                        宿主按 DevEco Studio 的"外形"识别它(tools/node/bin/node 与 product-info.json 必须存在,
#                        且 product-info.json 的 version >= 6.0.0)。Linux 上没有 Studio,所以下面用软链接
#                        把 CLT 摆成这个外形——仅用于通过识别,不参与实际构建。
FROM harness-dev:2.1

COPY deveco-linux-x64/ /opt/deveco/
COPY BUILD-INFO.txt linux-build.patch /opt/deveco/

ENV DEVECO_HOME=/opt/deveco-home \
    PATH=/opt/deveco/bin:$PATH

RUN set -eu; \
    C=/opt/command-line-tools; H=/opt/deveco-home; \
    V="$(sed -n 's/^# Version:[[:space:]]*//p' "$C/version.txt" | head -1)"; \
    [ -n "$V" ]; \
    mkdir -p "$H/tools"; \
    printf '%s\n' \
      '{' \
      '  "name": "Command Line Tools",' \
      "  \"version\": \"$V\"," \
      '  "note": "Linux adapter for DevEco Code: symlinks give the Command Line Tools the directory shape DevEco Code expects of a DevEco Studio install. Build/run/emulator use DEVECO_CLI_CLT_PATH natively."' \
      '}' > "$H/product-info.json"; \
    ln -s "$C/sdk"       "$H/sdk"; \
    ln -s "$C/tool/node" "$H/tools/node"; \
    ln -s "$C/ohpm"      "$H/tools/ohpm"; \
    ln -s "$C/hvigor"    "$H/tools/hvigor"; \
    ln -s "$C/emulator"  "$H/tools/emulator"; \
    chmod +x /opt/deveco/bin/deveco

# 批量运行相关的开关。必须设在下面几步之前:deveco-cli 默认开启遥测,构建过程本身就会产生遥测文件并烤进镜像。
#   DEVECO_CLI_DISABLE_TELEMETRY  关闭 deveco-cli 遥测(取值 1 或 true 生效)。
#   DEVECO_CLI_DISABLE_UPDATE     关闭 CLI 的更新检查与“有新版本”提示。
#   DEVECO_DISABLE_AUTOUPDATE     关闭 DevEco Code 启动时的自动更新检查。
#   DEVECO_CLI_SMOKE_WAIT_MS      devecocli run 的冒烟检查在启动应用后等待多久再查进程,默认 3000。
#                                 模拟器冷启动时应用首次启动可能超过 3 秒,会被误判为 FAIL_CRASH;放宽到 10 秒。
ENV DEVECO_CLI_DISABLE_TELEMETRY=1 \
    DEVECO_CLI_DISABLE_UPDATE=all \
    DEVECO_DISABLE_AUTOUPDATE=1 \
    DEVECO_CLI_SMOKE_WAIT_MS=10000

# 窗口模式。模拟器以窗口模式启动(截图对比、VNC 看画面都需要),容器里由入口脚本自动拉起 Xvfb :0 虚拟显示器。
# 无窗口模式(-noWindow)在这套镜像里模拟器无法注册到 hdc,所以不用它。
# DISPLAY 同时设为环境变量,这样 docker exec 进去的会话也能直接用这块显示器。
COPY deveco-entrypoint.sh /opt/scripts/deveco-entrypoint.sh
ENV DISPLAY=:0 \
    LIBGL_ALWAYS_SOFTWARE=1
RUN chmod +x /opt/scripts/deveco-entrypoint.sh
ENTRYPOINT ["/opt/scripts/deveco-entrypoint.sh"]
# 设置 ENTRYPOINT 后基础镜像的默认命令(CMD)会被清空,这里补回来,保持 `docker run -it <镜像>` 直接进 bash 的习惯。
CMD ["/bin/bash"]

# 系统镜像的默认位置。Emulator 不带 -imageRoot 启动时(CLI 原生的 emulator start 就是如此)会到
# /root/Library/Huawei/Sdk 找镜像,找不到就报 "not exists or is not readable",hdc 端口也起不来。
# 基础镜像的系统镜像在 /opt/emu-images,这里在默认位置放一个软链接指过去。
RUN set -eu; mkdir -p /root/Library/Huawei/Sdk; \
    ln -s /opt/emu-images/system-image /root/Library/Huawei/Sdk/system-image

# 预置一个已完成首次启动的干净模拟器实例 deveco_phone(可选,约 0.76GB)。
# CLI 原生的 `devecocli emulator start` 只等约 60 秒;全新实例首次冷启动实测 85~86 秒,CLI 会报
# "did not appear in hdc list targets within the timeout"(模拟器其实还在继续启动)。实例有过一次启动记录后
# 再启动只要约 31 秒,CLI 正常报成功。批量场景每个容器都是全新的,所以把“首次启动”提前到构建镜像时做掉。
# 不需要时删掉下面这一行:镜像小 0.76GB,代价是每个新容器首次启动多等约 55 秒并看到上述超时提示。
# 实例数据由 emulator-state/prepare.sh 生成:创建 → 启动到系统就绪 → 停止 → 删除日志 → 导出。
COPY emulator-state/Huawei /root/.Huawei

# 协议接受。两者都是一次性的本地状态,按用户主目录记录;写进镜像后容器启动即已同意,不需要任何人工确认。
#   产品协议   -> /root/.local/state/deveco/product-agreement.json
#   模拟器许可 -> /root/.cache/Huawei/Emulator26.0/.emu_config
# 产品协议的硬性检查已由编译期开关 --skip-agreement 绕过(见文件头),无头运行并不依赖上面的文件。这里仍保留接受
# 这一步,是因为交互式界面(TUI)的引导流程只看本地有没有接受记录,不看那个开关;用户此前已确认同意。
# 模拟器许可是另一套独立的门,必须接受。DevEco Code 内置的 CLI 与镜像原有的独立 devecocli 各接受一次。
# 末尾删掉这几条命令产生的遥测目录,不让任何构建期数据进入镜像。
RUN set -eu; \
    deveco auth consent --accept; \
    DEVECO_CLI_AUTH_SOURCE=deveco-code DEVECO_CODE_AUTH_DIR=/root/.config/deveco DEVECO_CLI_DISABLE_UPDATE=all \
      node /opt/deveco/node_modules/@deveco-test/deveco-harness/dist/deveco-cli/proxy.js emulator license accept; \
    devecocli emulator license accept; \
    rm -rf /root/.local/share/deveco-cli/TraceLogData

# 隐私:按隐私声明 3.3 关闭“数据统计分析服务”和“工具改进计划”(两者默认开启;键名见 deveco-privacy-settings.ts)。
# 服务器上批量跑时不向华为上报使用数据。需要时删掉这一段即可恢复默认。
RUN set -eu; mkdir -p /root/.local/state/deveco; \
    printf '%s\n' \
      '{' \
      '  "analytics_enabled": false,' \
      '  "deveco_tool_improvement_enabled": false' \
      '}' > /root/.local/state/deveco/kv.json

# 让新建工程的 Lint 默认生效。
# CodeLinter 在命令行模式下遇到“与内置默认完全相同”的配置会跳过执行规则的 ESLint 引擎,而 devecocli create
# 用的模板恰好就是那份默认配置——新建工程直接跑 check lint,得到的是“0 个文件 / 无问题”,什么都没查。
# 这里给模板加一条规则让配置不再等于默认。规则参数设成不检查未使用的函数参数,因为模板自己的 EntryAbility.ets
# 就有两个未使用的回调参数,否则每个新工程一建出来就带两个“错误”。
# 想恢复成上游原样:删掉下面两行即可。原因与实验见 enable-lint.py 的说明。
COPY enable-lint.py /opt/deveco/enable-lint.py
RUN python3 -I /opt/deveco/enable-lint.py

LABEL org.opencontainers.image.title="harness-dev (Android + HarmonyOS + DevEco Code)" \
      org.opencontainers.image.description="harness-dev:2.1 plus a from-source Linux build of DevEco Code" \
      org.opencontainers.image.source="https://gitcode.com/openharmony-sig/deveco-code"
