#!/usr/bin/env python3
"""让新建工程的 Lint 默认生效:给 devecocli 的工程模板 code-linter.json5 加一条规则。

背景
----
DevEco Code 命令行工具自带的 CodeLinter,在命令行模式下遇到“与内置默认完全相同”的配置时会跳过执行规则的
ESLint 引擎(日志:Using default configuration, skipping ESLint engine)。而 devecocli create 生成
code-linter.json5 用的模板,内容恰好就是那份默认配置。结果是:任何新建工程直接跑 `devecocli check lint`,
得到的都是“Files checked: 0 / No defects found”——什么都没检查,却像全部通过。

做法
----
在模板的 rules 里加一条 `@typescript-eslint/no-unused-vars`。这条规则本来就在模板的推荐规则集里,显式写出来
只是让配置内容不再等于内置默认,ESLint 引擎就会正常执行(推荐规则集 + 模板里的安全规则)。

参数设成 args: none 的原因
--------------------------
模板生成的 EntryAbility.ets 本身就有两个未被使用的生命周期回调参数(want、launchParam),按默认参数检查
会被报成两个 error——每个新工程一建出来就带两个“错误”。未使用的函数参数对迁移质量基本没有价值,
有价值的是未使用的局部变量和导入,所以只关掉对参数的检查。实测:干净的模板工程 0 问题;未使用的导入和
局部变量能被报出。

模板有两份:命令行里直接用的 devecocli(node 全局目录下),和 DevEco Code 内置的那一份。两份都改。
脚本可重复执行(已改过的会跳过);找不到任何模板或模板格式与预期不符时以非零退出。

用法: python3 -I enable-lint.py
"""
import glob
import sys

PATTERNS = [
    # 直接在命令行里用的 devecocli(基础镜像自带)
    "/opt/node-v*/lib/node_modules/@deveco/deveco-cli/node_modules/@deveco/deveco-cli-common/templates/*/code-linter.json5",
    # DevEco Code 内置的 devecocli(agent 实际使用的那一份)
    "/opt/deveco/node_modules/@deveco-test/deveco-harness/vendor/deveco-cli/node_modules/@deveco-test/deveco-cli-common/templates/*/code-linter.json5",
]
ANCHOR = '  "rules": {\n'
RULE = '    "@typescript-eslint/no-unused-vars": ["error", { "args": "none" }],\n'
MARK = "no-unused-vars"


def main() -> int:
    seen = patched = skipped = 0
    for pattern in PATTERNS:
        for path in sorted(glob.glob(pattern)):
            seen += 1
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            if MARK in text:
                skipped += 1
                print(f"已有规则,跳过: {path}")
                continue
            if text.count(ANCHOR) != 1:
                print(f"模板格式与预期不符(应恰有一处 rules 段): {path}", file=sys.stderr)
                return 1
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text.replace(ANCHOR, ANCHOR + RULE))
            patched += 1
            print(f"已修改: {path}")
    if seen == 0:
        print("没有找到任何 code-linter.json5 模板", file=sys.stderr)
        return 1
    print(f"共 {seen} 份模板:修改 {patched} 份,跳过 {skipped} 份")
    return 0


if __name__ == "__main__":
    sys.exit(main())
