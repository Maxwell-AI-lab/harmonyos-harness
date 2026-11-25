#!/bin/bash
# 不花模型额度的自检:用随镜像附带的“假模型”把 SkillsRSI 整条流水线跑一遍。
# 用法和 skillsrsi-run.sh 相同(镜像入口 + KVM),不需要任何模型凭据。
# 假模型按剧本回答,只用来确认环境是通的;它的“判断”不代表真实效果。
set -euo pipefail
export SKILLS_RSI_API_KEY=mock
export SKILLS_RSI_BASE_URL=http://127.0.0.1:18991/v1
export SKILLS_RSI_MODEL=mock-model
export SKILLS_RSI_TITLE="MOCK 自检 · OpenCalc 双端(假模型)"
export OUT_DIR=${OUT_DIR:-/work/skillsrsi-selftest-out}
python3 -I /opt/skills-rsi-selftest/mock_model.py 18991 /tmp/skillsrsi-selftest /opt/skills-rsi-selftest/NumberFormatter.ets >/tmp/skillsrsi-selftest.log 2>&1 &
MOCK=$!
trap 'kill "$MOCK" 2>/dev/null || true' EXIT
sleep 1
/opt/scripts/skillsrsi-run.sh
