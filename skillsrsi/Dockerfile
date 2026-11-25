# harness-dev:2.2 + SkillsRSI 0.4.1(薄层)。
# 不改动 2.2 本身;镜像里不含任何模型凭据。模型 Key 在运行时通过环境变量传入。
#
# 构建前需要把 SkillsRSI 的官方发布包 skills-rsi-0.4.1.tgz 放在本目录(内部项目,不在本仓库;
# 构建时会核对 SHA-256,见 build.sh)。然后:
#   docker build -t harness-dev:2.2-skillsrsi .
FROM harness-dev:2.2
ARG REVIEWER=skillsrsi-sandbox-image
LABEL org.opencontainers.image.description="harness-dev:2.2 plus SkillsRSI 0.4.1 (skill optimisation sandbox; needs KVM)"

COPY skills-rsi-0.4.1.tgz build.sh /tmp/skillsrsi-build/
COPY scripts/ /opt/scripts/
COPY selftest/ /opt/skills-rsi-selftest/

RUN bash /tmp/skillsrsi-build/build.sh "$REVIEWER" && rm -rf /tmp/skillsrsi-build
