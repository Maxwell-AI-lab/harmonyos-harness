#!/bin/bash
# 镜像构建步骤:在 harness-dev:2.2 之上安装 SkillsRSI 0.4.1 及其依赖。不含任何模型凭据。
# 唯一参数是评测包的“确认人”名字(0.4.1 要求评测包被确认后才能使用,而命令行没有确认命令)。
set -euo pipefail
REVIEWER=${1:-skillsrsi-sandbox-image}
# 官方发布包 skills-rsi-0.4.1.tgz 的 SHA-256(与发布方清单一致)。包本身不在本仓库,由构建者提供。
PKG_SHA256=9aedc5909c205c6e45cb7cdfd4f035704c15005d1829f98bf8c126eb721cd62c
cd /tmp/skillsrsi-build

# 1) 校验 SkillsRSI 发布包后解压
echo "$PKG_SHA256  skills-rsi-0.4.1.tgz" | sha256sum -c -
mkdir -p /opt/skills-rsi /opt/skills-rsi-home
tar -xzf skills-rsi-0.4.1.tgz -C /opt/skills-rsi --strip-components=1
chmod +x /opt/scripts/skillsrsi /opt/scripts/skillsrsi-run.sh /opt/scripts/skillsrsi-selftest.sh

# 2) SkillsRSI 的准备脚本按 DevEco Studio 的目录结构找 Java;镜像里 Java 在系统目录,补一个软链接
mkdir -p /opt/deveco-home/jbr/Contents
ln -sfn /usr/lib/jvm/java-21-openjdk-amd64 /opt/deveco-home/jbr/Contents/Home

# 3) 用 DevEco 自带的新版 Node(系统自带的 Node 版本不够)安装 HMBot、准备 OpenCalc 示例
export PATH=/opt/deveco-home/tools/node/bin:$PATH
export SKILLS_RSI_HOME=/opt/skills-rsi-home SKILLS_RSI_PYTHON=/usr/bin/python3
/opt/scripts/skillsrsi setup --deveco | tee setup.json
/opt/scripts/skillsrsi prepare-formal-opencalc --harmony-device 127.0.0.1:5555 > prepare.json
jq -e .ready prepare.json
EXAMPLE=$(jq -r .recipe prepare.json | xargs dirname)
ln -sfn "$EXAMPLE" /opt/skills-rsi-home/examples/opencalc

# 4) 确认内置评测包
CID=$(jq -r .plan.evalPackage.contentId prepare.json)
printf '{"action":"confirm","home":"/opt/skills-rsi-home","name":"OpenCalc","contentId":"%s","reviewer":"%s","scopeConfirmed":true,"referenceConfirmed":true}' \
  "$CID" "$REVIEWER" | python3 /opt/skills-rsi/lab/evaluation_packages.py > confirm.json
jq -e '.status == "available"' confirm.json

# 5) 预热编译缓存(否则第一次编译要联网装 pnpm,网络不通时会卡满 4 分钟后失败)
W=/tmp/warm/arm/workspace
mkdir -p "$W/harmony/entry/src/main/ets/calculator"
cp -R "$EXAMPLE/input/." "$W/"
cp /opt/skills-rsi-selftest/NumberFormatter.ets "$W/harmony/entry/src/main/ets/calculator/"
"$DEVECO_HOME/tools/node/bin/node" "$EXAMPLE/tools/check.mjs" "$W" > warm.json 2>/dev/null
jq -e '[.checks[] | select(.id == "hap-compile") | .pass][0]' warm.json
rm -rf /tmp/warm

# 6) 记下构建信息,便于核对镜像和仓库是否对应
{
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "skillsrsi_package_sha256=$PKG_SHA256"
  echo "skillsrsi_version=$(jq -r .version /opt/skills-rsi/package.json)"
  echo "hmbot_package_digest=$(jq -r .deveco.digest setup.json)"
  echo "deveco_version=$(deveco --version | head -1)"
  echo "node=$(node -v)"
  echo "eval_package_content_id=$CID"
  echo "eval_package_reviewer=$REVIEWER"
  echo "scripts_sha256:"
  (cd /opt/scripts && sha256sum skillsrsi skillsrsi-run.sh skillsrsi-selftest.sh)
  echo "selftest_sha256:"
  (cd /opt/skills-rsi-selftest && sha256sum mock_model.py NumberFormatter.ets)
} > /opt/skills-rsi/BUILD-INFO.txt
echo "镜像内容就绪: node $(node -v), deveco $(deveco --version | head -1), SkillsRSI $(jq -r .version /opt/skills-rsi/package.json)"
