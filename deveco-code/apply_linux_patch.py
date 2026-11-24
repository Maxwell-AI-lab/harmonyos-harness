#!/usr/bin/env python3
"""给 deveco-code 上游源码打 Linux 构建补丁(3 处改动 / 2 个文件)。

用法: python3 -I apply_linux_patch.py <repo-root>
设计: 每个锚点必须恰好命中一次,否则报错退出(上游文件漂移时立刻发现);可重复执行(已打过则跳过)。
改动内容与 Kimi 分享对话中的 linux-build.patch 一致,但以断言方式重写,保证对当前提交精确生效。
"""
import sys
from pathlib import Path

LINUX_TARGETS = """  {
    os: "linux",
    arch: "x64",
  },
  {
    os: "linux",
    arch: "x64",
    abi: "musl",
  },
  {
    os: "linux",
    arch: "arm64",
  },
"""


def replace_once(text: str, anchor: str, replacement: str, label: str) -> str:
    count = text.count(anchor)
    if count != 1:
        raise SystemExit(f"PATCH FAIL [{label}]: 锚点命中 {count} 次(应为 1)——上游文件已变化,需人工复核")
    print(f"  ok  {label}")
    return text.replace(anchor, replacement)


def patch_build_ts(path: Path) -> None:
    src = path.read_text(encoding="utf-8")
    if 'os: "linux",' in src and '"linux-x64": { archive' in src:
        print("  skip build.ts(已打过补丁)")
        return
    # 改动 1: allTargets 增加 linux-x64(glibc) / linux-x64-musl / linux-arm64
    anchor = (
        '  abi?: "musl"\n'
        '  avx2?: false\n'
        '}[] = [\n'
        '  {\n'
        '    os: "darwin",\n'
    )
    src = replace_once(src, anchor, anchor.replace('  {\n    os: "darwin",\n', LINUX_TARGETS + '  {\n    os: "darwin",\n'), "build.ts allTargets += linux")
    # 改动 2: rgArchiveMap 登记 linux 键。archive 留空是有意的: build.ts 只从 postinstall 填好的
    # .build-cache 取 ripgrep(见 build.ts "Copy ripgrep from cache"),不走 GitHub 发布包。
    anchor = 'const rgArchiveMap: Record<string, { archive: string; binary: string }> = {\n'
    src = replace_once(
        src,
        anchor,
        anchor + '  "linux-x64": { archive: "", binary: "rg" },\n  "linux-arm64": { archive: "", binary: "rg" },\n',
        "build.ts rgArchiveMap += linux",
    )
    path.write_text(src, encoding="utf-8")


def patch_postinstall_ts(path: Path) -> None:
    src = path.read_text(encoding="utf-8")
    if '"linux-x64"' in src:
        print("  skip postinstall.ts(已打过补丁)")
        return
    # 改动 3a: 平台白名单
    anchor = 'const supportedPlatforms = new Set(["darwin-arm64", "darwin-x64", "win32-x64"])'
    src = replace_once(
        src,
        anchor,
        'const supportedPlatforms = new Set(["darwin-arm64", "darwin-x64", "win32-x64", "linux-x64", "linux-arm64"])',
        "postinstall.ts supportedPlatforms += linux",
    )
    # 改动 3b: npm 包映射(ripgrep 走 npm 源的 Linux 平台包)
    lines = src.split("\n")
    hits = [i for i, line in enumerate(lines) if '"win32-x64":' in line and "ripgrep-win32-x64" in line]
    if len(hits) != 1:
        raise SystemExit(f"PATCH FAIL [postinstall.ts rgNpmMap]: win32 行命中 {len(hits)} 次(应为 1)")
    indent = lines[hits[0]][: len(lines[hits[0]]) - len(lines[hits[0]].lstrip())]
    lines[hits[0] + 1 : hits[0] + 1] = [
        f'{indent}"linux-x64":   {{ pkg: "@vscode/ripgrep-linux-x64",   binary: "rg" }},',
        f'{indent}"linux-arm64": {{ pkg: "@vscode/ripgrep-linux-arm64", binary: "rg" }},',
    ]
    print("  ok  postinstall.ts rgNpmMap += linux")
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    root = Path(sys.argv[1]).resolve()
    script_dir = root / "packages" / "opencode" / "script"
    print(f"patching {root}")
    patch_build_ts(script_dir / "build.ts")
    patch_postinstall_ts(script_dir / "postinstall.ts")
    print("patch applied: 3 changes in 2 files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
