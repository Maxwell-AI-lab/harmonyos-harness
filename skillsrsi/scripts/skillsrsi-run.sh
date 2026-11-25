#!/bin/bash
# 在容器里跑一轮 SkillsRSI:开鸿蒙模拟器 → 生成配方 → 运行 → 把结果拷到输出目录。
# 必须用镜像自带的入口脚本启动(不要加 --entrypoint),并给容器 KVM。见同目录的 README。
#
# 必填(都通过环境变量传入,不会落盘):
#   SKILLS_RSI_API_KEY     模型凭据
#   SKILLS_RSI_BASE_URL    OpenAI 兼容接口的根地址,例如 https://某个服务/v1
#   SKILLS_RSI_MODEL       模型名(需要支持工具调用和 JSON 输出)
# 选填:
#   SKILLS_RSI_OPTIMIZER   arkts-routed-bc(默认)或 skillopt
#   SKILLS_RSI_THINKING    disabled(默认)/ enabled / provider-default
#   SKILLS_RSI_TITLE       实验名称
#   SKILLS_RSI_REVIEWER    填了就用这个名字重新确认评测包
#   SKILLS_RSI_DEVICE      鸿蒙设备号,默认 127.0.0.1:5555
#   OUT_DIR                结果输出目录,默认 /work/skillsrsi-out
#   TEMPLATE               配方模板,默认镜像里预置的 OpenCalc 配方
set -euo pipefail
export PATH=/opt/deveco-home/tools/node/bin:$PATH
export SKILLS_RSI_HOME=/opt/skills-rsi-home SKILLS_RSI_PYTHON=/usr/bin/python3
: "${SKILLS_RSI_API_KEY:?需要通过环境变量 SKILLS_RSI_API_KEY 提供模型凭据}"
: "${SKILLS_RSI_BASE_URL:?需要通过环境变量 SKILLS_RSI_BASE_URL 提供模型接口根地址}"
: "${SKILLS_RSI_MODEL:?需要通过环境变量 SKILLS_RSI_MODEL 提供模型名}"
OUT=${OUT_DIR:-/work/skillsrsi-out}
TEMPLATE=${TEMPLATE:-/opt/skills-rsi-home/examples/opencalc/recipe.json}
HDC=/opt/deveco-home/sdk/default/openharmony/toolchains/hdc
DEV=${SKILLS_RSI_DEVICE:-127.0.0.1:5555}
mkdir -p "$OUT"

# 模型地址:SkillsRSI 只接受 https 或本机回环地址。如果给的是容器网络里的 http 地址,就在本机转一层。
BASE=$SKILLS_RSI_BASE_URL
case "$BASE" in
  https://*|http://127.0.0.1:*|http://localhost:*) ;;
  http://*)
    REST=${BASE#http://}; HOSTPORT=${REST%%/*}; HOST=${HOSTPORT%%:*}; PORT=${HOSTPORT##*:}; PORT=${PORT:-80}
    socat TCP-LISTEN:18080,bind=127.0.0.1,fork,reuseaddr TCP:"$HOST":"$PORT" >/tmp/skillsrsi-socat.log 2>&1 &
    BASE="http://127.0.0.1:18080${REST#${HOSTPORT}}" ;;
esac

# 鸿蒙模拟器:沿用 2.2 使用指南里的方式启动,再把屏幕设成常亮并回到桌面(评测脚本不会自己唤醒屏幕)。
[ -S /tmp/.X11-unix/X0 ] || { Xvfb :0 -screen 0 1600x900x24 >/tmp/skillsrsi-xvfb.log 2>&1 & sleep 2; }
devecocli emulator start deveco_phone >/tmp/skillsrsi-emulator.log 2>&1 || { tail -5 /tmp/skillsrsi-emulator.log >&2; exit 1; }
hdc tconn "$DEV" >/dev/null 2>&1 || true
hdc -t "$DEV" shell power-shell wakeup >/dev/null 2>&1 || true
hdc -t "$DEV" shell power-shell timeout -o 2147483647 >/dev/null 2>&1 || true
hdc -t "$DEV" shell power-shell setmode 602 >/dev/null 2>&1 || true
hdc -t "$DEV" shell uitest uiInput keyEvent Home >/dev/null 2>&1 || true
hdc list targets

if [ -n "${SKILLS_RSI_REVIEWER:-}" ]; then
  CID=$(jq -r .evalPackage.contentId "$TEMPLATE")
  printf '{"action":"confirm","home":"%s","name":"OpenCalc","contentId":"%s","reviewer":"%s","scopeConfirmed":true,"referenceConfirmed":true}' \
    "$SKILLS_RSI_HOME" "$CID" "$SKILLS_RSI_REVIEWER" | python3 /opt/skills-rsi/lab/evaluation_packages.py >/dev/null
fi

jq --arg model "$SKILLS_RSI_MODEL" --arg base "$BASE" --arg optimizer "${SKILLS_RSI_OPTIMIZER:-arkts-routed-bc}" \
   --arg thinking "${SKILLS_RSI_THINKING:-disabled}" --arg title "${SKILLS_RSI_TITLE:-SkillsRSI · OpenCalc 双端}" \
   '.model = $model | .baseUrl = $base | .optimizer = $optimizer | .thinking = $thinking | .title = $title' \
   "$TEMPLATE" > "$OUT/recipe.json"

START=$(date +%s)
/opt/scripts/skillsrsi run "$OUT/recipe.json" > "$OUT/cli.log" 2>&1 && RC=0 || RC=$?

# 带出证据和生成的代码;不带每轮的工作副本、编译中间产物和 DevEco 的运行状态(一轮约 200M,证据本身约 5M)。
LATEST=$(ls -td "$SKILLS_RSI_HOME"/runs/*/ 2>/dev/null | head -1 || true)
if [ -n "$LATEST" ]; then
  mkdir -p "$OUT/run"
  tar -C "$LATEST" --exclude='*/native-workspace' --exclude='*/build-project' --exclude='*/host-state' -cf - . | tar -C "$OUT/run" -xf -
fi
hdc -t "$DEV" uninstall com.hmbot.skillsrsi.opencalcformatter >/dev/null 2>&1 || true
echo "SkillsRSI 结束: 退出码 $RC,用时 $(( $(date +%s) - START )) 秒,结果在 $OUT/run"
exit "$RC"
