# harness-dev:2.1 镜像验证报告
日期:2026-11-20 · 服务器:hmbot1119(88核/376G/裸金属KVM) · 全部在镜像容器内实测

## 验证结果总览(6/6 通过)

| # | 验证项 | 结果 | 关键数据 |
|---|---|---|---|
| 1 | 安卓模拟器启动 | ✅ PASS | 无头模式 boot 完成后解锁截图 547KB(非黑屏);Android 14 / API 34 / Pixel 仿真 |
| 2 | 鸿蒙模拟器启动 | ✅ PASS | 冷启动约 64 秒就绪;hdc shell 通;解锁后截图 111KB |
| 3 | 鸿蒙工程构建 | ✅ PASS | devecocli create 脚手架 + hvigorw assembleHap,BUILD SUCCESSFUL 8.6秒,HAP 21KB |
| 4 | 安卓构建链 | ✅ PASS | aapt2 compile+link 出 APK → zipalign → apksigner 签名并验证通过 |
| 5 | 端到端闭环 | ✅ PASS | 镜像内构建 HAP → 装入鸿蒙模拟器 → 启动应用 → 运行截图 71KB |
| 6 | 工具链完整性 | ✅ PASS | Git/Python/Node24/pnpm/rg/jq/GCC/CMake/JDK21+17/adb/hdc/ohpm/hvigor/devecocli/claude-code 全部就位 |

## 验证中发现并已解决的问题(镜像已内置修复)

1. 【已修】鸿蒙模拟器协议未接受:新环境首次运行需 `Emulator -license accept`,已写入镜像构建层
2. 【已修】截图路径限制:guest 截图必须保存在 `/data/local/tmp/` 下,其他路径报 invalid
3. 【已修】装包时机:bmc 安装服务在开机后约 60 秒才完全就绪,建议稳定等待后装包
4. 【注意】HAP 目标版本须 ≤ 模拟器系统版本(镜像系统为 6.1.1 / API 24,CLT26 脚手架默认 API 26,需将工程 targetSdkVersion 调整为 "6.1.1(24)")

## 运行环境要求

- 宿主机:Linux x86_64,`/dev/kvm` 可用(跑模拟器必需;纯构建可不带)
- Docker 运行参数:`--device /dev/kvm`
- 镜像大小:20.9GB(含双端工具链 + 双模拟器 + 鸿蒙系统镜像)
