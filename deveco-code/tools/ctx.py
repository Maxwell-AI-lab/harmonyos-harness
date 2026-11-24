#!/usr/bin/env python3
"""在目录内的文本文件里按正则找关键词,打印前后文窗口(只读分析用,不执行任何被扫描的代码)。

用法: python3 -I ctx.py <root> <regex> [before=200] [after=400] [max_matches=6] [min_bytes=2000]
"""
import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    root = Path(sys.argv[1]).resolve()
    pattern = re.compile(sys.argv[2])
    before = int(sys.argv[3]) if len(sys.argv) > 3 else 200
    after = int(sys.argv[4]) if len(sys.argv) > 4 else 400
    limit = int(sys.argv[5]) if len(sys.argv) > 5 else 6
    min_bytes = int(sys.argv[6]) if len(sys.argv) > 6 else 2000

    shown = 0
    seen: set[str] = set()
    for path in sorted(root.rglob("*")):
        if shown >= limit:
            break
        if not path.is_file() or path.suffix in {".json", ".map", ".md", ".ts", ".d.ts", ".txt"}:
            continue
        try:
            if path.stat().st_size < min_bytes or path.stat().st_size > 60_000_000:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for match in pattern.finditer(text):
            snippet = text[max(0, match.start() - before) : match.end() + after].replace("\n", " ")
            key = snippet[before - 60 : before + 80]
            if key in seen:
                continue
            seen.add(key)
            print(f"--- {path.relative_to(root)} @ {match.start()} ---")
            print(snippet)
            print()
            shown += 1
            if shown >= limit:
                break
    print(f"[matches shown: {shown}]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
