# Harness 一体化镜像 v2.0:开发构建 + 安卓/鸿蒙模拟器运行
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive TZ=Asia/Shanghai

# ===== 一、通用开发层 =====
RUN apt-get update && apt-get install -y --no-install-recommends \
      git python3 python3-pip python3-venv curl wget jq zip unzip tar xz-utils \
      ripgrep build-essential cmake ca-certificates openssh-client \
      openjdk-21-jdk-headless openjdk-17-jdk-headless \
    && rm -rf /var/lib/apt/lists/*
RUN cd /opt && VER=$(curl -s https://registry.npmmirror.com/-/binary/node/latest-v24.x/ | grep -oE 'node-v24\.[0-9]+\.[0-9]+-linux-x64\.tar\.xz' | head -1) \
    && curl -sL -o node.tar.xz "https://registry.npmmirror.com/-/binary/node/latest-v24.x/$VER" \
    && tar -xf node.tar.xz && rm node.tar.xz \
    && ln -sf /opt/node-v24*-linux-x64/bin/* /usr/local/bin/ && node -v
RUN npm config set registry https://registry.npmmirror.com \
    && npm i -g pnpm@10 @deveco/deveco-cli@1.3.12 \
    && (npm i -g @anthropic-ai/claude-code || true) \
    && ln -sf /opt/node-v24*-linux-x64/bin/* /usr/local/bin/

# ===== 二、安卓构建+模拟器层 =====
ENV ANDROID_HOME=/opt/android-sdk ANDROID_AVD_HOME=/root/.android/avd
COPY cmdtools.zip /tmp/
RUN mkdir -p $ANDROID_HOME/cmdline-tools \
    && unzip -q /tmp/cmdtools.zip -d $ANDROID_HOME/cmdline-tools \
    && mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest \
    && rm /tmp/cmdtools.zip \
    && yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null 2>&1 || true \
    && yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager \
         "platform-tools" "platforms;android-35" "platforms;android-36" \
         "build-tools;35.0.0" "build-tools;36.0.0" \
         "emulator" "system-images;android-34;google_apis;x86_64" >/dev/null 2>&1 || true

# ===== 三、鸿蒙构建+模拟器层 =====
COPY clt/ /opt/command-line-tools/
COPY clt-emu/ /opt/command-line-tools/emulator/
COPY emu-images/ /opt/emu-images/
ENV DEVECO_CLI_CLT_PATH=/opt/command-line-tools
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:/opt/command-line-tools/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/command-line-tools/sdk/default/openharmony/toolchains

# ===== 四、图形与模拟器运行依赖层 =====
RUN apt-get update && apt-get install -y --no-install-recommends \
      xvfb openbox x11vnc xdotool socat mesa-utils libatomic1 \
      libegl1 libgbm1 libgl1 libpulse0 \
      libxcb-cursor0 libxkbcommon-x11-0 libxcb-icccm4 libxcb-keysyms1 libxcb-shape0 \
      libxcb-render-util0 libxcb-glx0 libxcb-xinerama0 libxcb-xkb1 \
      libxcb-randr0 libxcb-xfixes0 libxcb-sync1 libxcb-dri3-0 libxcb-present0 \
      libxcb-dpms0 libxcb-composite0 iproute2 net-tools \
    && rm -rf /var/lib/apt/lists/*

# ===== 五、配置层 =====
RUN chmod +x /opt/command-line-tools/bin/* /opt/command-line-tools/emulator/Emulator 2>/dev/null; \
    ln -sf /opt/command-line-tools/sdk/default/openharmony/toolchains/hdc /usr/local/bin/hdc; \
    mkdir -p /root/.config/deveco-cli && \
    printf '<application>\n    <component name="CountryRegionSetting">\n        <countryregion name="CN"/>\n    </component>\n</application>\n' \
      > /root/.config/deveco-cli/country.region.xml; \
    mkdir -p /opt/scripts
COPY start-android.sh start-harmony.sh /opt/scripts/
RUN chmod +x /opt/scripts/*.ssh 2>/dev/null; chmod +x /opt/scripts/*.sh; export DISPLAY=dummy LD_LIBRARY_PATH=/opt/command-line-tools/sdk/default/openharmony/toolchains; /opt/command-line-tools/emulator/Emulator -license accept >/dev/null 2>&1 || true; echo ok
WORKDIR /work
CMD ["/bin/bash"]
