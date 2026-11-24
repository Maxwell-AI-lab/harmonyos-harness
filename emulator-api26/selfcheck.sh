#!/bin/bash
# harness-dev:2.3 自检脚本。在“用最终镜像新起的容器”里以 root 运行,输出每项 通过/失败/跳过,有失败时退出码为 1。
#
# 用法(镜像里自带这个脚本):
#   docker run -d --name selfcheck --device /dev/kvm --shm-size=4g harness-dev:2.3 sleep infinity
#   docker exec selfcheck bash /opt/scripts/selfcheck.sh                 # 不含需要模型的部分
#   docker exec -e SELFCHECK_GATEWAY_TOKEN=<令牌> selfcheck bash /opt/scripts/selfcheck.sh   # 含 agent 部分
#
# 环境变量(都可选):
#   SELFCHECK_GATEWAY_URL     OpenAI/Anthropic 兼容网关地址,须以 /v1 结尾;默认取容器默认网关的 3000 端口
#   SELFCHECK_GATEWAY_TOKEN   网关令牌
#   SELFCHECK_CHAT_MODEL      主对话模型名(默认 claude-sonnet-4-5)
#   SELFCHECK_VISION_MODEL    能看图的模型名,供界面验证用(默认 deepseek-v4.1-flash)
#
# 脚本会在 /tmp 下新建工程、启停模拟器、切换系统版本,只在一次性容器里跑。
set -u
export NO_COLOR=1

EXPECTED_SHA="8e60219c09f7e9b992707743a1e46d4063179e0f0f1e1c0d80739a7c033fac85"
EXPECTED_VERSION="1.17.9"
EXPECTED_OS="HarmonyOS 7.0.0(26.0.0)"     # 默认预置实例的系统版本
EXPECTED_OS_24="HarmonyOS 6.1.1(24)"      # 可切换到的另一个系统版本
EXPECTED_IMG_VER="7.0.0.107"              # API 26 系统镜像的包版本(重新下载后请同步更新)
PROJ=/tmp/selfcheck-proj                  # 默认工程(不指定 API 级别,即 API 26)
PROJ24=/tmp/selfcheck-proj24              # 指定 --api-level 24 的工程,用来验证旧工程能跑在新系统上
PROBE=/tmp/selfcheck-probe                # 调用 API 26 才有的接口的探针工程
BUNDLE=com.example.selfcheck
BUNDLE24=com.example.selfcheck24
BUNDLE_PROBE=com.example.selfcheckprobe
INST=/root/.Huawei/Emulator/deployed/deveco_phone
HDC_TARGET=""                             # hdc 目标(设备序列号),由 hdcc 自动找
API=""                                    # 模拟器系统的 API 级别,启动后赋值
PASS=0; FAIL=0; SKIP=0; FAILED=()
ok()   { PASS=$((PASS+1)); printf '  [通过] %s\n' "$1"; [ -z "${2:-}" ] || printf '         %s\n' "$2"; }
bad()  { FAIL=$((FAIL+1)); FAILED+=("$1"); printf '  [失败] %s\n' "$1"; [ -z "${2:-}" ] || printf '         %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  [跳过] %s\n' "$1"; [ -z "${2:-}" ] || printf '         %s\n' "$2"; }
sec()  { printf '\n===== %s =====\n' "$1"; }
clean() { sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r'; }

hdcc() {  # 所有 hdc 调用显式指定目标(模拟器重启后序列号可能变化)
  [ -n "$HDC_TARGET" ] || HDC_TARGET="$(hdc list targets 2>/dev/null | tr -d '\r' | grep -v '^\[Empty\]$' | grep -v '^$' | head -1)"
  [ -n "$HDC_TARGET" ] || return 1
  hdc -t "$HDC_TARGET" "$@"
}
wait_boot() {  # 等鸿蒙系统启动完成,最长 $1 秒。每次都重新找设备(重启或切换系统后目标可能变了)
  local deadline=$(( $(date +%s) + $1 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    HDC_TARGET=""
    [ "$(hdcc shell param get bootevent.boot.completed 2>/dev/null | tr -d '\r\n ')" = "true" ] && return 0
    sleep 5
  done
  return 1
}
emu_api() { hdcc shell param get const.ohos.apiversion 2>/dev/null | tr -d '\r\n '; }
emu_stop() {  # 停止模拟器并等进程退干净(停止命令返回时进程可能还在),超过 60 秒强杀
  (cd /tmp && timeout 120 devecocli emulator stop deveco_phone >/dev/null 2>&1) || true
  for _ in $(seq 1 60); do pgrep -f "Emulator -start" >/dev/null 2>&1 || break; sleep 1; done
  pkill -9 -f "Emulator -start" 2>/dev/null
  HDC_TARGET=""
  return 0
}
emu_start() {  # 启动预置实例并等开机;成功时输出启动用时(秒)。参数:最长等待秒数
  local t0=$(date +%s) out
  out="$(cd /tmp && timeout 300 devecocli emulator start deveco_phone 2>&1 | clean)"
  if wait_boot "$1"; then
    echo "$(( $(date +%s) - t0 ))|$(echo "$out" | grep -oE 'started successfully|did not appear[^.]*' | tail -1)"
    return 0
  fi
  echo "0|$(echo "$out" | tail -2 | tr '\n' ' ')"
  return 1
}
png_colors() {  # 输出 PNG 里抽样到的不同颜色数(纯色图接近 1)。只支持 8 位 RGB / RGBA 非隔行,解析不了输出空
  python3 -I - "$1" <<'PY'
import struct, sys, zlib
data = open(sys.argv[1], "rb").read()
if data[:8] != b"\x89PNG\r\n\x1a\n":
    sys.exit(1)
pos, idat, bpp, width = 8, [], 0, 0
while pos + 12 <= len(data):
    size, kind = struct.unpack(">I4s", data[pos:pos + 8])
    body = data[pos + 8:pos + 8 + size]
    if kind == b"IHDR":
        width, _, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
        if depth != 8 or interlace != 0 or ctype not in (2, 6):
            sys.exit(1)
        bpp = 4 if ctype == 6 else 3
    elif kind == b"IDAT":
        idat.append(body)
    elif kind == b"IEND":
        break
    pos += 12 + size
raw = zlib.decompress(b"".join(idat))
stride, prev, step, colors = width * bpp, bytearray(width * bpp), 16, set()
for y in range(len(raw) // (stride + 1)):  # 每行都要还原(滤波依赖上一行),只对其中一部分行抽样
    row = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
    kind = raw[y * (stride + 1)]
    if kind:
        for i in range(stride):
            a = row[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if kind == 1:
                row[i] = (row[i] + a) & 255
            elif kind == 2:
                row[i] = (row[i] + b) & 255
            elif kind == 3:
                row[i] = (row[i] + (a + b) // 2) & 255
            else:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                row[i] = (row[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
    if y % step == 0:
        for x in range(0, stride, bpp * step):
            colors.add(bytes(row[x:x + 3]))
    prev = row
print(len(colors))
PY
}

printf 'harness-dev 自检  %s\n' "$(date '+%F %T')"

# ---------------------------------------------------------------- 1
sec "1. 静态配置"
[ -x /opt/deveco/bin/deveco ] && ok "deveco 二进制存在且可执行" || bad "deveco 二进制缺失"
V="$(cd /tmp && timeout 60 deveco --version 2>&1 | clean | tail -1)"
[ "$V" = "$EXPECTED_VERSION" ] && ok "deveco --version" "$V" || bad "deveco --version" "期望 $EXPECTED_VERSION,实际 [$V]"
S="$(sha256sum /opt/deveco/bin/deveco | cut -c1-64)"
[ "$S" = "$EXPECTED_SHA" ] && ok "二进制 sha256 与构建记录一致" "$S" || bad "二进制 sha256 与构建记录不一致" "$S(若重新构建过,请同步更新脚本里的 EXPECTED_SHA)"
[ -f /opt/deveco/node_modules/@deveco-test/deveco-harness/package.json ] && ok "运行时依赖 deveco-harness 在位" || bad "运行时依赖 deveco-harness 缺失(鸿蒙工具将不可用)"
N="$(cd /tmp && timeout 90 deveco debug skill 2>/dev/null | python3 -I -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null)"
[ "$N" = "6" ] && ok "技能数 = 6(内建插件已加载)" || bad "技能数异常" "期望 6,实际 [$N]"
for p in /opt/deveco-home/sdk /opt/deveco-home/tools/node /opt/deveco-home/tools/ohpm /opt/deveco-home/tools/hvigor /opt/deveco-home/tools/emulator; do
  [ -e "$p" ] && ok "适配目录链接有效: ${p#/opt/deveco-home/}" || bad "适配目录链接失效: $p"
done
[ -x /opt/deveco-home/sdk/default/openharmony/toolchains/hdc ] && ok "hdc 可经 DEVECO_HOME 找到" "$(/opt/deveco-home/sdk/default/openharmony/toolchains/hdc version 2>&1 | clean | head -1)" || bad "DEVECO_HOME 下找不到 hdc"
for v in HarmonyOS-7.0.0 HarmonyOS-6.1.1; do
  [ -e "/root/Library/Huawei/Sdk/system-image/$v" ] && ok "系统镜像默认位置链接有效: $v" || bad "系统镜像默认位置链接失效: $v(CLI 原生启动模拟器会失败)"
done
IMG=/opt/emu-images/system-image/HarmonyOS-7.0.0/phone_all_x86
[ -f "$IMG/system.img" ] && ok "API 26 系统镜像文件在位" "$(du -sh "$IMG" | cut -f1)" || bad "API 26 系统镜像缺失"
IMGV="$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1]))["data"]; print(d.get("apiVersion"), d.get("version"), d.get("releaseType"))' "$IMG/sdk-pkg.json" 2>/dev/null)"
[ "$IMGV" = "26 $EXPECTED_IMG_VER Release" ] && ok "API 26 系统镜像的版本信息" "apiVersion $IMGV(若重新下载过,请同步更新脚本里的 EXPECTED_IMG_VER)" || bad "API 26 系统镜像版本不符" "期望 [26 $EXPECTED_IMG_VER Release],实际 [$IMGV]"
[ -d /opt/emu-images/system-image/HarmonyOS-6.1.1/phone_all_x86 ] && ok "API 24 系统镜像保留(6.1.1)" || bad "API 24 系统镜像缺失"
OSV="$(sed -n 's/^os\.osVersion=//p' "$INST/config.ini" 2>/dev/null | head -1)"
[ "$OSV" = "$EXPECTED_OS" ] && ok "默认预置实例是 API 26" "$OSV" || bad "默认预置实例的系统版本不对" "期望 $EXPECTED_OS,实际 [${OSV:-空}]"
[ "$(sed -n 's/^isHotBoot=//p' "$INST/config.ini" 2>/dev/null | head -1)" = "false" ] && ! [ -e "$INST/ram.bin" ] \
  && ok "默认实例关闭了热启动(没有内存快照)" || bad "默认实例开着热启动或带内存快照(从快照恢复后调试服务偶尔起不来)"
for a in 26 24; do
  f=/opt/emulator-state/api$a/deveco_phone/config.ini
  want=$EXPECTED_OS; [ "$a" = "24" ] && want=$EXPECTED_OS_24
  [ "$(sed -n 's/^os\.osVersion=//p' "$f" 2>/dev/null | head -1)" = "$want" ] && [ "$(sed -n 's/^isHotBoot=//p' "$f" | head -1)" = "false" ] && [ ! -e "/opt/emulator-state/api$a/deveco_phone/ram.bin" ] \
    && ok "预置实例状态在位: api$a" "$want" || bad "预置实例状态缺失或不对: api$a"
done
[ -x /opt/scripts/switch-emulator.sh ] && ok "切换脚本可执行" "/opt/scripts/switch-emulator.sh 24|26|show" || bad "切换脚本缺失或不可执行"
[ "$(sed -n 's/^path=//p' /root/.Huawei/Emulator/deployed/deveco_phone.ini 2>/dev/null | head -1)" = "$INST" ] && ok "实例注册项指向默认实例" || bad "实例注册项缺失或路径不对"
[ -f /opt/deveco/BUILD-INFO.txt ] && grep -q "build_flags=--single --skip-agreement" /opt/deveco/BUILD-INFO.txt && ok "构建记录在位,含 --skip-agreement" || bad "构建记录缺失或参数不符"
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("version")=="1" else 1)' /root/.local/state/deveco/product-agreement.json 2>/dev/null \
  && ok "产品协议接受记录在位" || bad "产品协议接受记录缺失"
[ "$(grep -c ':agree$' /root/.cache/Huawei/Emulator26.0/.emu_config 2>/dev/null)" -ge 2 ] && ok "模拟器许可已接受(两项)" || bad "模拟器许可未接受"
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("analytics_enabled") is False and d.get("deveco_tool_improvement_enabled") is False else 1)' /root/.local/state/deveco/kv.json 2>/dev/null \
  && ok "隐私设置:数据统计与工具改进计划已关闭" || bad "隐私设置未生效"
[ "${DEVECO_CLI_DISABLE_TELEMETRY:-}" = "1" ] && ok "环境变量 DEVECO_CLI_DISABLE_TELEMETRY=1" || bad "DEVECO_CLI_DISABLE_TELEMETRY 未设置"
[ ! -e /root/.local/share/deveco-cli/TraceLogData ] && ok "镜像内无遥测文件" || bad "镜像内存在遥测文件" "/root/.local/share/deveco-cli/TraceLogData"
MISSING=""
for t in node java hvigorw ohpm hdc Emulator devecocli deveco claude adb sdkmanager keytool python3 Xvfb openbox x11vnc; do
  command -v "$t" >/dev/null 2>&1 || MISSING="$MISSING $t"
done
[ -z "$MISSING" ] && ok "基础镜像的工具全部在位(15 个)" || bad "缺少工具" "$MISSING"
[ -z "$(ls -A /work 2>/dev/null)" ] && ok "工作目录 /work 为空(无遗留测试文件)" || bad "/work 有遗留文件" "$(ls -A /work | tr '\n' ' ')"

# ---------------------------------------------------------------- 2
sec "2. 运行环境"
[ "${DISPLAY:-}" = ":0" ] && ok "DISPLAY=:0" || bad "DISPLAY 未设置为 :0" "实际 [${DISPLAY:-空}](入口脚本未执行?)"
[ -S /tmp/.X11-unix/X0 ] && ok "虚拟显示器 X0 已就绪(入口脚本)" || bad "虚拟显示器未启动"
pgrep -x openbox >/dev/null 2>&1 && ok "窗口管理器 openbox 运行中" || bad "openbox 未运行"
if [ -w /dev/kvm ]; then ok "/dev/kvm 可用"; else bad "/dev/kvm 不可用" "容器需用 --device /dev/kvm 启动"; fi
[ "$(timeout 60 hdc version 2>&1 | clean | head -1 | grep -c 'Ver:')" = "1" ] && ok "hdc 可运行" || bad "hdc 无法运行"
L="$(timeout 90 devecocli emulator list 2>&1 | clean)"
echo "$L" | grep -q "deveco_phone" && [ "$(echo "$L" | grep -c 'deveco_phone ')" = "1" ] && ok "默认模拟器实例 deveco_phone 可见,且是唯一实例(有多个实例时运行要指定设备)" || bad "默认模拟器实例缺失,或有多余实例" "$(echo "$L" | grep deveco_phone | tr '\n' ' ')"
echo "$L" | grep "deveco_phone" | grep -q "HarmonyOS 7.0.0(26.0.0)" && ok "实例列表显示系统为 $EXPECTED_OS" || bad "实例列表里的系统版本不对" "$(echo "$L" | grep deveco_phone | tr '\n' ' ')"

# ---------------------------------------------------------------- 3
sec "3. 基础功能"
H="$(timeout 90 curl -s --max-time 10 http://127.0.0.1:4096/global/health 2>/dev/null)"
if [ -n "$H" ]; then bad "无头服务端口 4096 已被占用" "$H"; else
  (cd /tmp && nohup deveco serve --port 4096 --hostname 127.0.0.1 >/tmp/selfcheck-serve.log 2>&1 &)
  for _ in $(seq 1 30); do H="$(curl -s --max-time 3 http://127.0.0.1:4096/global/health 2>/dev/null)"; [ -n "$H" ] && break; sleep 1; done
  echo "$H" | grep -q "\"healthy\":true" && ok "deveco serve 无头服务" "$H" || bad "deveco serve 无头服务" "[$H] $(tail -3 /tmp/selfcheck-serve.log 2>/dev/null | tr '\n' ' ')"
fi
[ "$(timeout 30 devecocli --version 2>&1 | clean | tail -1)" = "1.3.12" ] && ok "devecocli --version 1.3.12" || bad "devecocli 版本异常"

EMUDOWN="模拟器不可用"
if [ -w /dev/kvm ]; then
  EMU="$(emu_start 240)"; ET="${EMU%%|*}"; EM="${EMU#*|}"
  if [ "$ET" -gt 0 ] 2>/dev/null; then
    ok "模拟器启动(窗口模式)并完成开机" "用时 $ET 秒;$EM"
  else bad "模拟器未在限时内完成开机" "$EM"; fi
  API="$(emu_api)"
  [ "$API" = "26" ] && ok "设备上的系统是 API 26" "$(hdcc shell param get const.product.software.version 2>/dev/null | tr -d '\r')" || bad "设备上的系统 API 级别不是 26" "实际 [${API:-空}]"
  timeout 60 devecocli device list 2>&1 | clean | grep -q "127.0.0.1:55[0-9][0-9].*emulator" && ok "devecocli device list 识别到模拟器" || bad "devecocli device list 未识别到模拟器"
  if hdcc shell snapshot_display -f /data/local/tmp/selfcheck.jpeg >/dev/null 2>&1 && hdcc file recv /data/local/tmp/selfcheck.jpeg /tmp/selfcheck-hm.jpeg >/dev/null 2>&1 && [ "$(stat -c %s /tmp/selfcheck-hm.jpeg 2>/dev/null || echo 0)" -gt 10000 ]; then
    ok "模拟器截图可用" "$(stat -c %s /tmp/selfcheck-hm.jpeg) 字节"
  else bad "模拟器截图失败"; fi
  timeout 90 devecocli ui layout --device "$HDC_TARGET" 2>&1 | clean | grep -qE "Stack|Text|Window" && ok "界面节点树可读" || bad "界面节点树读取失败"
else
  skip "模拟器相关检查" "容器没有 /dev/kvm"
fi

# 默认工程:不指定 API 级别(工具默认取 SDK 的 26)。在 2.2 镜像里这样建出来的工程装不上模拟器,2.3 应该能直接装。
rm -rf "$PROJ"
if timeout 180 devecocli create --project-path "$PROJ" --app-name SelfCheck --bundle-name "$BUNDLE" 2>&1 | clean | grep -q "created successfully"; then
  ok "新建工程(默认,不指定 API 级别)" "$(grep -o '"targetSdkVersion": "[^"]*"' "$PROJ/build-profile.json5")"
else bad "新建工程失败"; fi
if [ -f "$PROJ/build-profile.json5" ]; then
  [ "$(grep -o '"compatibleSdkVersion": "[^"]*"' "$PROJ/build-profile.json5")" = '"compatibleSdkVersion": "26.0.0"' ] && ok "工程声明的是 API 26(26.0.0)" || bad "工程声明的兼容版本不是 26.0.0" "$(grep -o '"compatibleSdkVersion": "[^"]*"' "$PROJ/build-profile.json5")"
  B="$(cd "$PROJ" && timeout 900 devecocli build 2>&1 | clean)"
  echo "$B" | grep -q "Build completed successfully" && ok "devecocli build" "$(echo "$B" | grep -oE 'BUILD SUCCESSFUL[^ ]*( in [0-9a-z. ]+)?' | tail -1)" || bad "devecocli build 失败" "$(echo "$B" | grep -iE 'error|fail' | head -3 | tr '\n' ' ')"
  HAP="$(find "$PROJ" -name 'entry-default-unsigned.hap' 2>/dev/null | head -1)"
  [ -n "$HAP" ] && ok "产物 HAP 已生成" "$(basename "$HAP")" || bad "产物 HAP 缺失"
  A="$(cd "$PROJ" && timeout 300 devecocli check arkts 2>&1 | clean)"
  echo "$A" | grep -q "No errors found" && ok "ArkTS 静态检查" "$(echo "$A" | tail -1)" || bad "ArkTS 静态检查异常" "$(echo "$A" | tail -1)"
  rm -rf "$PROJ/entry/build" "$PROJ/.hvigor"
  D="$(cd "$PROJ" && timeout 900 hvigorw assembleHap --no-daemon 2>&1 | clean)"
  echo "$D" | grep -q "BUILD SUCCESSFUL" && ok "直接 hvigorw 构建(HMBot 使用的方式)" "$(echo "$D" | grep -oE 'BUILD SUCCESSFUL[^ ]*( in [0-9a-z. ]+)?' | tail -1)" || bad "直接 hvigorw 构建失败" "$(echo "$D" | grep -iE 'error|fail' | head -3 | tr '\n' ' ')"
  # Lint:用工程自带的默认配置验证。上游原版的默认配置会被检查器跳过,结果恒为“0 个文件 / 无问题”;
  # 镜像已通过改模板让默认配置生效(见 enable-lint.py),这里守住两点:模板工程本身是干净的;埋下的问题能被报出。
  LN0="$(cd "$PROJ" && timeout 400 devecocli check lint entry/src/main/ets 2>&1 | clean)"
  echo "$LN0" | grep -q "Issues: 0" && ok "代码 Lint:干净的模板工程无问题" || bad "代码 Lint 在模板工程上报出了问题" "$(echo "$LN0" | grep -E 'Error|Warn' | head -3 | tr '\n' ' ')"
  printf 'export function lintProbe(): number {\n  const unusedVariable: number = 1\n  return 2\n}\n' > "$PROJ/entry/src/main/ets/pages/LintProbe.ets"
  LN="$(cd "$PROJ" && timeout 400 devecocli check lint entry/src/main/ets/pages/LintProbe.ets 2>&1 | clean)"
  echo "$LN" | grep -q "no-unused-vars" && ok "代码 Lint(工程默认配置)报出埋下的未使用变量" "$(echo "$LN" | grep -oE 'Files checked: [0-9]+' | tail -1)" || bad "代码 Lint 未报出埋下的未使用变量(默认配置被跳过?)" "$(echo "$LN" | tail -2 | tr '\n' ' ')"
  rm -f "$PROJ/entry/src/main/ets/pages/LintProbe.ets"
  if [ "$API" = "26" ]; then
    R="$(cd "$PROJ" && timeout 300 devecocli run --skip-build --device "$HDC_TARGET" 2>&1 | clean)"
    echo "$R" | grep -q "start ability successfully" && sleep 3 && [ -n "$(hdcc shell pidof $BUNDLE 2>/dev/null | tr -d '\r')" ] \
      && ok "安装并启动应用(默认工程,不用指定 API 级别)" "$(echo "$R" | grep -oE 'Smoke: [A-Z_]+' | tail -1)" || bad "安装或启动应用失败" "$(echo "$R" | grep -iE 'error|fail' | head -3 | tr '\n' ' ')"
  else skip "安装并启动应用(默认工程)" "$EMUDOWN"; fi
fi

# 按 API 24 建的工程(同事流水线里的工程都是这样)在新系统上要能照常运行。
rm -rf "$PROJ24"
if timeout 180 devecocli create --project-path "$PROJ24" --app-name SelfCheck24 --bundle-name "$BUNDLE24" --api-level 24 2>&1 | clean | grep -q "created successfully"; then
  ok "新建工程(--api-level 24)" "$(grep -o '"compatibleSdkVersion": "[^"]*"' "$PROJ24/build-profile.json5")"
else bad "新建工程(--api-level 24)失败"; fi
if [ -f "$PROJ24/build-profile.json5" ]; then
  B24="$(cd "$PROJ24" && timeout 900 devecocli build 2>&1 | clean)"
  echo "$B24" | grep -q "Build completed successfully" && ok "API 24 工程构建" "$(echo "$B24" | grep -oE 'BUILD SUCCESSFUL[^ ]*( in [0-9a-z. ]+)?' | tail -1)" || bad "API 24 工程构建失败" "$(echo "$B24" | grep -iE 'error|fail' | head -3 | tr '\n' ' ')"
  if [ "$API" = "26" ]; then
    R="$(cd "$PROJ24" && timeout 300 devecocli run --skip-build --device "$HDC_TARGET" 2>&1 | clean)"
    echo "$R" | grep -q "start ability successfully" && sleep 3 && [ -n "$(hdcc shell pidof $BUNDLE24 2>/dev/null | tr -d '\r')" ] \
      && ok "API 24 的工程能装到 API 26 模拟器上并运行" "$(echo "$R" | grep -oE 'Smoke: [A-Z_]+' | tail -1)" || bad "API 24 工程装不上 API 26 模拟器" "$(echo "$R" | grep -iE 'error|fail' | head -3 | tr '\n' ' ')"
  else skip "API 24 工程在 API 26 模拟器上运行" "$EMUDOWN"; fi
fi

# API 26 才有的接口:fs.listFileExtSync(@ohos.file.fs 里 @since 26)。在 API 24 的系统上调用它会崩(TypeError: … is not callable),
# 这里确认在 API 26 的系统上能正常调用。
rm -rf "$PROBE"
cat > /tmp/selfcheck-Index.ets <<'ETS'
import fs from '@ohos.file.fs';
import hilog from '@ohos.hilog';

const FILES_DIR: string = '/data/storage/el2/base/haps/entry/files';

@Entry
@Component
struct Index {
  @State message: string = 'probe';

  aboutToAppear(): void {
    let result: string = '';
    try {
      const names: string[] = fs.listFileExtSync(FILES_DIR);
      result = 'APIPROBE26 ok';
    } catch (e) {
      result = 'APIPROBE26 failed: ' + (e as Error).message;
    }
    hilog.info(0x0000, 'SELFCHECK', '%{public}s', result);
    this.message = result;
  }

  build() {
    RelativeContainer() {
      Text(this.message)
        .id('probe')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
    }
    .width('100%')
    .height('100%')
  }
}
ETS
if timeout 180 devecocli create --project-path "$PROBE" --app-name ApiProbe --bundle-name "$BUNDLE_PROBE" >/dev/null 2>&1 && cp /tmp/selfcheck-Index.ets "$PROBE/entry/src/main/ets/pages/Index.ets"; then
  PB="$(cd "$PROBE" && timeout 900 devecocli build 2>&1 | clean)"
  echo "$PB" | grep -q "Build completed successfully" && ok "调用 API 26 接口的探针工程构建" "$(echo "$PB" | grep -oE 'BUILD SUCCESSFUL[^ ]*( in [0-9a-z. ]+)?' | tail -1)" || bad "探针工程构建失败" "$(echo "$PB" | grep -iE 'error|fail' | head -3 | tr '\n' ' ')"
  if [ "$API" = "26" ] && echo "$PB" | grep -q "Build completed successfully"; then
    hdcc shell hilog -r >/dev/null 2>&1
    (cd "$PROBE" && timeout 300 devecocli run --skip-build --device "$HDC_TARGET" >/tmp/selfcheck-probe-run.log 2>&1)
    sleep 5
    PL="$(hdcc shell hilog -x 2>/dev/null | tr -d '\r' | grep 'SELFCHECK' | grep 'APIPROBE26' | tail -1 | sed 's/^.*APIPROBE26/APIPROBE26/')"
    echo "$PL" | grep -q "APIPROBE26 ok" && ok "API 26 才有的接口(fs.listFileExtSync)能正常调用" "$PL" || bad "API 26 接口调用失败" "[${PL:-没有读到日志}] $(grep -iE 'error|fail' /tmp/selfcheck-probe-run.log | head -2 | tr '\n' ' ')"
  else skip "API 26 接口调用" "$EMUDOWN"; fi
else bad "探针工程创建失败"; fi

if [ -w /dev/kvm ] && command -v adb >/dev/null 2>&1; then
  T0=$(date +%s)
  AND="$(timeout 420 /opt/scripts/start-android.sh selfcheck_avd 2>&1 | clean | tail -1)"
  if echo "$AND" | grep -q "安卓模拟器就绪"; then
    T1=$(date +%s)
    ok "安卓模拟器启动(基础镜像原有功能,回归)" "用时 $(( T1 - T0 )) 秒"
    # 截图:系统刚报开机完成时桌面还没画出第一帧,这时截到的是全黑图(实测还要再等约 15 秒)。
    # 等到画面不再是纯色为止,最长 90 秒。只看文件大小不行:全黑图约 15KB,按“大于 5000 字节”判它也算通过。
    COLORS=""
    for _ in $(seq 1 30); do
      adb exec-out screencap -p > /tmp/selfcheck-and.png 2>/dev/null
      if [ "$(stat -c %s /tmp/selfcheck-and.png 2>/dev/null || echo 0)" -ge 100000 ]; then  # 太小的不可能是正常画面,不必解析
        COLORS="$(png_colors /tmp/selfcheck-and.png)"
        [ -n "$COLORS" ] && [ "$COLORS" -gt 16 ] && break
      fi
      sleep 3
    done
    if [ -n "$COLORS" ] && [ "$COLORS" -gt 16 ]; then
      ok "安卓模拟器截图可用(画面不是纯色)" "抽样到 $COLORS 种颜色,$(stat -c %s /tmp/selfcheck-and.png) 字节;就绪后约 $(( $(date +%s) - T1 )) 秒"
    else bad "安卓模拟器截图是纯色或解析失败" "$(stat -c %s /tmp/selfcheck-and.png 2>/dev/null || echo 0) 字节,颜色数 [${COLORS:-空}]"; fi
    [ -n "$HDC_TARGET" ] && [ -n "$(hdcc shell echo alive 2>/dev/null | tr -d '\r')" ] \
      && ok "鸿蒙与安卓模拟器同时在线" "hdc $HDC_TARGET;adb $(adb devices 2>/dev/null | tr -d '\r' | awk '/emulator-/{print $1}' | tr '\n' ' ')" \
      || bad "双端共存检查失败"
  else bad "安卓模拟器启动失败" "$AND"; fi
else skip "安卓模拟器回归" "容器没有 /dev/kvm"; fi

# 同一个容器里停掉再启动:实例关闭了热启动,每次都是正常开机,不依赖内存快照。
if [ -w /dev/kvm ]; then
  emu_stop
  EMU="$(emu_start 240)"; ET="${EMU%%|*}"; EM="${EMU#*|}"
  if [ "$ET" -gt 0 ] 2>/dev/null && [ "$(emu_api)" = "26" ]; then
    ok "模拟器停止后能重新启动" "用时 $ET 秒;$EM"
  else bad "模拟器重新启动失败(从快照恢复后调试服务起不来?看是否误开了热启动)" "$EM"; fi
else skip "模拟器重启检查" "容器没有 /dev/kvm"; fi

# ---------------------------------------------------------------- 4
sec "4. agent(需要模型)"
TOKEN="${SELFCHECK_GATEWAY_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  skip "agent 相关检查" "未提供 SELFCHECK_GATEWAY_TOKEN"
elif [ ! -f "$PROJ/build-profile.json5" ]; then
  skip "agent 相关检查" "工程未创建成功"
elif [ "$(emu_api)" != "26" ]; then
  skip "agent 相关检查" "模拟器不可用"
else
  GW="${SELFCHECK_GATEWAY_URL:-}"
  [ -n "$GW" ] || GW="http://$(ip route 2>/dev/null | awk '/^default/ {print $3; exit}'):3000/v1"
  CHAT="${SELFCHECK_CHAT_MODEL:-claude-sonnet-4-5}"; VIS="${SELFCHECK_VISION_MODEL:-deepseek-v4.1-flash}"
  umask 077
  cat > "$PROJ/deveco.json" <<EOF
{"\$schema":"https://opencode.ai/config.json","provider":{"selfcheck-gw":{"npm":"@ai-sdk/anthropic","options":{"baseURL":"$GW","apiKey":"$TOKEN"},"models":{"$CHAT":{},"$VIS":{}}}},"model":"selfcheck-gw/$CHAT","agent":{"ui_verification":{"model":"selfcheck-gw/$VIS"}}}
EOF
  run_agent() { (cd "$PROJ" && timeout 900 deveco run --agent build --auto "$1" 2>&1 | clean); }
  # 每次 agent 的完整输出留在 /tmp/selfcheck-agent-N.log(仅 root 可读),失败时可以回看
  PA=/root/.local/state/deveco/product-agreement.json
  mv "$PA" "$PA.bak"
  O1="$(run_agent '只回复两个字:收到')"; mv "$PA.bak" "$PA"; echo "$O1" > /tmp/selfcheck-agent-1.log
  echo "$O1" | grep -q "收到" && ok "协议开关生效:删掉接受记录后仍可对话" || bad "协议开关未生效" "$(echo "$O1" | tail -3 | tr '\n' ' ')"
  # 先把第 3 部分启动的应用停掉:否则进程本来就在,下面“进程活着”检查不出 agent 有没有真的安装并启动
  hdcc shell aa force-stop "$BUNDLE" >/dev/null 2>&1
  for _ in $(seq 1 10); do [ -z "$(hdcc shell pidof $BUNDLE 2>/dev/null | tr -d '\r')" ] && break; sleep 1; done
  O2="$(run_agent "构建这个鸿蒙工程并安装到模拟器上启动")"; echo "$O2" > /tmp/selfcheck-agent-2.log
  if ! echo "$O2" | grep -q "^Error:" && [ -n "$(hdcc shell pidof $BUNDLE 2>/dev/null | tr -d '\r')" ]; then ok "agent 自主构建并安装启动"; else bad "agent 构建/安装启动失败" "$(echo "$O2" | tail -4 | tr '\n' ' ') 完整输出见 /tmp/selfcheck-agent-2.log"; fi
  # 界面验证:看最终结果,不看输出里有没有 error 字样。通过的条件:
  #   verify_ui 被调用,且这一次调用本身没有失败;
  #   截图确实落盘(存在工程目录里,或输出里 agent 报出来的路径);
  #   没有工具级错误(unavailable / execution_error),也没有顶层报错。
  # agent 自己试错的痕迹不算:比如先敲了不存在的 devecocli devices,或者给 save_ui_screenshot 指定了工程目录外的路径
  # 被内置的路径保护拒绝(“✗ … failed” + “Error: Path traversal detected …”),随后它改用默认路径重试成功。
  # 所以:工具级的失败行(前一行是“✗ … failed”)容忍;verify_ui 本身失败、或顶层报错,才算失败。
  # 截图存到哪里不固定(实测见过 screenshots/verify_ui_<编号>/、screenshots/、.deveco/ui-screenshots/、.cache/ui-screenshots/),
  # 所以不预设位置:先清掉旧截图,跑完后在整个工程目录里找,再加上输出里 agent 自己报出来的保存路径。
  find "$PROJ" -name 'screenshot_*.jpeg' -delete 2>/dev/null
  O3="$(run_agent "用 verify_ui 确认当前模拟器屏幕上显示的文字,并用 save_ui_screenshot 保存截图")"; echo "$O3" > /tmp/selfcheck-agent-3.log
  SHOTS=0
  for f in $( { find "$PROJ" -name 'screenshot_*.jpeg' -size +10k 2>/dev/null; echo "$O3" | grep -oE '/[^ `"]*screenshot_[0-9]+\.jpeg'; } | sort -u); do
    [ -f "$f" ] && [ "$(stat -c %s "$f" 2>/dev/null || echo 0)" -gt 10000 ] && SHOTS=$((SHOTS+1))
  done
  TOPERR="$(printf '%s\n' "$O3" | awk 'prev !~ /^✗/ && /^Error:/ {c++} {prev=$0} END{print c+0}')"
  if ! echo "$O3" | grep -qiE "unavailable|execution_error" && [ "$TOPERR" = "0" ] \
     && echo "$O3" | grep -q "⚙ verify_ui UI verification" && ! echo "$O3" | grep -q "✗ verify_ui" && [ "$SHOTS" -gt 0 ]; then
    ok "agent 调用内建界面验证工具" "verify_ui 调用成功,保存了 $SHOTS 张截图$(echo "$O3" | grep -q '^✗' && echo "(agent 另有 $(echo "$O3" | grep -c '^✗') 次工具调用被拒绝后重试成功)")"
  else bad "内建界面验证工具失败" "截图 $SHOTS 张;顶层报错 $TOPERR 处;$(echo "$O3" | grep -iE 'unavailable|execution_error|^✗|^Error:' | head -2 | tr '\n' ' ') 完整输出见 /tmp/selfcheck-agent-3.log"; fi
  rm -f "$PROJ/deveco.json"
fi

# ---------------------------------------------------------------- 5
sec "5. 切换系统版本"
if [ -w /dev/kvm ]; then
  emu_stop
  SW="$(/opt/scripts/switch-emulator.sh 24 2>&1 | tail -1)"
  EMU="$(emu_start 240)"; ET="${EMU%%|*}"; EM="${EMU#*|}"
  API24="$(emu_api)"
  if [ "$ET" -gt 0 ] 2>/dev/null && [ "$API24" = "24" ]; then
    ok "切换到 API 24 并启动" "用时 $ET 秒;$(hdcc shell param get const.product.software.version 2>/dev/null | tr -d '\r');$SW"
  else bad "切换到 API 24 后启动失败" "$(echo "$SW" | cut -c1-120) $EM"; fi
  if [ "$API24" = "24" ] && [ -n "$(find "$PROJ24" -name 'entry-default-unsigned.hap' 2>/dev/null | head -1)" ]; then
    R="$(cd "$PROJ24" && timeout 300 devecocli run --skip-build --device "$HDC_TARGET" 2>&1 | clean)"
    echo "$R" | grep -q "start ability successfully" && sleep 3 && [ -n "$(hdcc shell pidof $BUNDLE24 2>/dev/null | tr -d '\r')" ] \
      && ok "API 24 的系统上安装并启动 API 24 的工程" "$(echo "$R" | grep -oE 'Smoke: [A-Z_]+' | tail -1)" || bad "API 24 系统上运行 API 24 工程失败" "$(echo "$R" | grep -iE 'error|fail' | head -3 | tr '\n' ' ')"
  else skip "API 24 的系统上运行 API 24 的工程" "API 24 模拟器不可用"; fi
  emu_stop
  SW="$(/opt/scripts/switch-emulator.sh 26 2>&1 | tail -1)"
  EMU="$(emu_start 240)"; ET="${EMU%%|*}"; EM="${EMU#*|}"
  if [ "$ET" -gt 0 ] 2>/dev/null && [ "$(emu_api)" = "26" ] && [ "$(sed -n 's/^os\.osVersion=//p' "$INST/config.ini" | head -1)" = "$EXPECTED_OS" ]; then
    ok "切换回 API 26 并启动" "用时 $ET 秒;$SW"
  else bad "切换回 API 26 后启动失败" "$(echo "$SW" | cut -c1-120) $EM"; fi
  SAME="$(/opt/scripts/switch-emulator.sh 26 2>&1 | tail -1)"
  echo "$SAME" | grep -q "不用切换" && ok "已是目标版本时不会重复切换" "$SAME" || bad "重复切换的提示不对" "$SAME"
  # 恢复:版本不变,换回干净实例。模拟器此时还开着,脚本应当先把它停掉。实例用过之后数据盘会变大,所以和预置状态比
  # 文件数和文件大小(不比磁盘占用:复制稀疏文件后分配可能差几 KB)。
  clean_sig() { find "$1" -type f -printf '%s\n' 2>/dev/null | sort | awk '{n++; s+=$1} END{print n+0, s+0}'; }
  if /opt/scripts/switch-emulator.sh reset >/tmp/selfcheck-reset.log 2>&1 && [ "$(sed -n 's/^os\.osVersion=//p' "$INST/config.ini" | head -1)" = "$EXPECTED_OS" ] \
     && ! pgrep -f "Emulator -start" >/dev/null 2>&1 && [ "$(clean_sig "$INST")" = "$(clean_sig /opt/emulator-state/api26/deveco_phone)" ]; then
    ok "reset 能把当前版本恢复成干净实例" "$(tail -1 /tmp/selfcheck-reset.log | cut -c1-60) 文件数与大小和预置状态一致"
  else bad "reset 恢复失败" "$(tail -2 /tmp/selfcheck-reset.log | tr '\n' ' ') 文件: 当前 [$(clean_sig "$INST")] / 预置 [$(clean_sig /opt/emulator-state/api26/deveco_phone)]"
  fi
  EMU="$(emu_start 240)"; ET="${EMU%%|*}"; EM="${EMU#*|}"
  [ "$ET" -gt 0 ] 2>/dev/null && [ "$(emu_api)" = "26" ] && ok "恢复后能正常启动" "用时 $ET 秒" || bad "恢复后启动失败" "$EM"
else skip "切换系统版本" "容器没有 /dev/kvm"; fi

# ---------------------------------------------------------------- 6
sec "6. 遥测"
[ ! -e /root/.local/share/deveco-cli/TraceLogData ] && ok "全部命令跑完后仍未产生遥测文件" || bad "产生了遥测文件" "$(ls /root/.local/share/deveco-cli/TraceLogData 2>/dev/null | tr '\n' ' ')"

# ----------------------------------------------------------------
printf '\n===== 汇总:通过 %d / 失败 %d / 跳过 %d =====\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then printf '失败项:\n'; for f in "${FAILED[@]}"; do printf '  - %s\n' "$f"; done; exit 1; fi
exit 0
