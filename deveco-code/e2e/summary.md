# Live E2E Report

Started: 2026-11-23T13:31:16.976Z
Finished: 2026-11-23T13:39:44.592Z
Duration: 507.6s

Total: 34
Passed: 18
Failed: 5
Skipped: 11

| Status | ID | Title | Duration |
|---|---|---|---|
| PASS | MCP_ADD_SERVER | 添加 MCP 服务器 | 6.0s |
| PASS | MCP_LIST_SERVERS | 列出 MCP 服务器 | 4.5s |
| SKIP | START_APP_DEPLOY | devecocli run推包启动 | 0.0s |
| SKIP | HDC_LOG_LIST_DEVICES | devecocli设备列表 | 0.0s |
| PASS | HDC_GUARD_ALLOW_BASIC | HDC守卫基础查询与日志放行 | 24.8s |
| PASS | HDC_GUARD_DENY_OPERATIONS | HDC守卫拒绝操作不执行 | 18.2s |
| FAIL | HDC_GUARD_FILE_SEND_APPROVE | HDC守卫文件传输审批执行 | 5.4s |
| FAIL | HDC_GUARD_FILE_SEND_REJECT | HDC守卫审批拒绝不执行 | 5.6s |
| FAIL | HDC_GUARD_INSTALL_LAUNCH | HDC守卫安装与启动审批执行 | 12.3s |
| FAIL | HDC_GUARD_SUBPROCESS | HDC守卫一层子进程调用与直接调用同策略 | 4.5s |
| PASS | HDC_GUARD_OBJECT_BOUNDARY | HDC守卫对象边界负向拒绝 | 5.6s |
| PASS | HDC_GUARD_EXEC_RELIABILITY | HDC守卫长运行输出/取消/并发隔离 | 10.2s |
| PASS | HDC_GUARD_FAULT_INJECTION | HDC守卫故障注入失败关闭 | 15.6s |
| SKIP | SWITCH_CWD_BUILD | 指定目录不存在项目代码构建switch_cwd | 0.0s |
| SKIP | SWITCH_CWD_PROJECT_BUILD | 支持指定目录项目代码构建switch_cwd | 0.0s |
| SKIP | BUILD_PROJECT | 支持devecocli build构建鸿蒙项目 | 0.0s |
| SKIP | BUILD_FAILURE_CHECK | 编译构建结果检查 | 0.0s |
| SKIP | BUILD_MODE_BUILTIN_TOOLS | build模式内置工具列表 | 0.0s |
| SKIP | PLAN_MODE_BUILTIN_TOOLS | plan模式内置工具列表 | 0.0s |
| PASS | UPGRADE_COMMAND | upgrade命令验证 | 6.9s |
| SKIP | AUTH_LIST_PROVIDERS | 列出已认证的AI服务供应商 | 0.0s |
| PASS | AUTH_LOGOUT | 登出认证服务 | 4.6s |
| SKIP | MODELS_LIST | 列出可用模型 | 0.0s |
| PASS | AGENT_LIST | 列出所有agent | 5.7s |
| PASS | SESSION_LIST | 列出所有会话 | 3.6s |
| PASS | SESSION_IMPORT | 导入最简会话 | 8.3s |
| PASS | SESSION_EXPORT | 导出指定会话 | 8.8s |
| PASS | TOKEN_STATS | 查看 Token 使用统计 | 8.0s |
| PASS | ACP_STARTUP | ACP 服务启动与握手 | 3.4s |
| PASS | DEVECO_TUI_START | TUI 启动命令可用 | 2.9s |
| PASS | SERVE_STARTUP | Serve 服务启动与健康检查 | 5.2s |
| FAIL | ATTACH_RUNNING_SERVER | Attach 连接运行中服务器 | 38.5s |
| PASS | AUTH_LOGIN_WELLKNOWN | 通过 Well-known 登录认证服务（含风险确认） | 16.1s |
| SKIP | CONFIG_THIRD_PARTY_MODELS | 在deveco.jsonc中配置三方模型 | 0.0s |
