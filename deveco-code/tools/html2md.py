#!/usr/bin/env python3
"""把测试报告 HTML 转成 GitHub Flavored Markdown(供 GitHub 页面直接阅读)。

用法: python3 -I html2md.py <输入.html> <输出.md> [--img-prefix 前缀] [--head 注释行 ...]

只处理报告用到的结构:标题 / 段落 / 表格 / 列表 / 提示框 / 统计条 / 截图。
纯文本按 Markdown 规则转义;内容取自 HTML 的解析结果(实体已还原),不执行、不加载任何外部内容。
"""
import os
import re
import sys
from html.parser import HTMLParser

VOID = {"meta", "img", "br", "hr", "link", "input", "source"}
BLOCKISH = {"p", "div", "ul", "ol", "table", "figure", "blockquote", "li", "pre", "h1", "h2", "h3", "h4", "h5"}
TAG_MARK = {"tok": "✅", "terr": "❌", "twarn": "⚠️", "tskip": "⚪"}
HEADING = {"h1": 1, "h2": 2, "h3": 3, "h4": 4, "h5": 5}


class Node:
    def __init__(self, tag, attrs=None):
        self.tag = tag
        self.attrs = dict(attrs or [])
        self.kids = []

    @property
    def classes(self):
        return self.attrs.get("class", "").split()

    def text(self):
        return "".join(k if isinstance(k, str) else k.text() for k in self.kids)

    def elements(self, tag=None):
        return [k for k in self.kids if isinstance(k, Node) and (tag is None or k.tag == tag)]


class Tree(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("root")
        self.stack = [self.root]

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs)
        self.stack[-1].kids.append(node)
        if tag not in VOID:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self.stack[-1].kids.append(Node(tag, attrs))

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        for i in range(len(self.stack) - 1, 0, -1):  # 未闭合的标签向上找到最近的同名祖先后一并收起
            if self.stack[i].tag == tag:
                del self.stack[i:]
                return

    def handle_data(self, data):
        self.stack[-1].kids.append(data)


def ws(s):
    return re.sub(r"\s+", " ", s)


def esc_text(s):
    s = ws(s).replace("\\", "\\\\")
    s = re.sub(r"(?<=[A-Za-z0-9])_(?=[A-Za-z0-9])", "\x00", s)  # 词内下划线(DEVECO_HOME)不构成强调,不用转义
    s = re.sub(r"([`*_\[\]~|<>])", r"\\\1", s)
    return s.replace("\x00", "_")


def codespan(s, in_table=False):
    s = re.sub(r"[\r\n]+", " ", s).strip()  # 保留代码里的连续空格(CLI 输出的列对齐)
    if in_table:
        s = s.replace("|", "\\|")
    fence = "`" * (max((len(r) for r in re.findall(r"`+", s)), default=0) + 1)
    pad = " " if s.startswith("`") or s.endswith("`") else ""  # 首尾是反引号时留空格,避免和围栏粘连
    return f"{fence}{pad}{s}{pad}{fence}"


def inline(kids, table=False):
    out = []
    for k in kids:
        if isinstance(k, str):
            out.append(esc_text(k))
        elif k.tag == "code":
            out.append(codespan(k.text(), table))
        elif k.tag in ("b", "strong"):
            inner = inline(k.kids, table).strip()
            if inner:
                out.append(f"**{inner}**")
        elif k.tag in ("i", "em"):
            inner = inline(k.kids, table).strip()
            if inner:
                out.append(f"*{inner}*")
        elif k.tag == "br":
            out.append("<br>")
        elif k.tag == "span" and "tag" in k.classes:  # 带颜色的状态标签:颜色语义改用符号保留
            mark = next((TAG_MARK[c] for c in k.classes if c in TAG_MARK), "")
            out.append(f"{mark} {esc_text(k.text().strip())}".strip())
        elif k.tag == "a":
            inner = inline(k.kids, table).strip() or k.attrs.get("href", "")
            out.append(f"[{inner}]({k.attrs.get('href', '')})")
        elif k.tag in BLOCKISH:
            out.append(esc_text(k.text()))  # 行内不该出现块级元素;出现就只取文字
        else:
            out.append(inline(k.kids, table))
    return "".join(out)


def lead_guard(text):
    # 行首会被 Markdown 当成列表 / 标题 / 引用 / 表格 / 分隔线的写法,转义掉
    out = []
    for line in text.split("\n"):
        if re.match(r"^(?:\d+[.)]|[#>+\-|])(?:\s|$)", line) or re.match(r"^(?:[-=*_]\s*){3,}$", line):
            line = "\\" + line
        out.append(line)
    return "\n".join(out)


def para(kids, italic=False):
    s = inline(kids).strip()
    if not s:
        return []
    s = lead_guard(s)
    return [f"*{s}*" if italic else s]


def table(node):
    rows = []
    for tr in node.elements("tr"):
        rows.append([inline(c.kids, True).strip() for c in tr.elements() if c.tag in ("td", "th")])
    width = max(len(r) for r in rows)
    rows = [r + [""] * (width - len(r)) for r in rows]
    out = ["| " + " | ".join(rows[0]) + " |", "| " + " | ".join(["---"] * width) + " |"]
    out += ["| " + " | ".join(r) + " |" for r in rows[1:]]
    return "\n".join(out)


def stat_row(node):
    nums, labels = [], []
    for stat in node.elements("div"):
        by_class = {c: d for d in stat.elements("div") for c in d.classes}
        nums.append(ws(by_class["n"].text()).strip())
        labels.append(ws(by_class["l"].text()).strip())
    return "\n".join([
        "| " + " | ".join(nums) + " |",
        "| " + " | ".join(["---"] * len(nums)) + " |",
        "| " + " | ".join(esc_text(x) for x in labels) + " |",
    ])


def figure(node, img_prefix):
    imgs = node.elements("img")
    if not imgs:
        return []
    img = imgs[0]
    alt = esc_text(img.attrs.get("alt", "")).strip()
    out = [f"![{alt}]({img_prefix}{os.path.basename(img.attrs.get('src', ''))})"]
    caps = node.elements("figcaption")
    if caps:
        out.append(f"*{inline(caps[0].kids).strip()}*")
    return ["\n\n".join(out)]


def quote(blocks):
    lines = []
    for i, block in enumerate(blocks):
        if i:
            lines.append(">")
        lines.extend(("> " + line).rstrip() for line in block.split("\n"))
    return "\n".join(lines)


def render_block(node, img_prefix):
    tag, cls = node.tag, node.classes
    if tag in HEADING:
        return [f"{'#' * HEADING[tag]} {inline(node.kids).strip()}"]
    if tag == "p":
        return para(node.kids)
    if tag == "table":
        return [table(node)]
    if tag in ("ul", "ol"):
        items = []
        for i, li in enumerate(node.elements("li"), 1):
            marker = "-" if tag == "ul" else f"{i}."
            items.append(f"{marker} {lead_guard(inline(li.kids).strip())}")  # 守卫只作用于内容,不碰列表标记
        return ["\n".join(items)]
    if tag == "figure":
        return figure(node, img_prefix)
    if tag == "div":
        if "wrap" in cls:
            return render_blocks(node, img_prefix)
        if "sub" in cls:
            return para(node.kids, italic=True)
        if "callout" in cls:
            return [quote(render_blocks(node, img_prefix))]
        if "stat-row" in cls:
            return [stat_row(node)]
        if "shots" in cls:
            out = []
            for fig in node.elements("figure"):
                out.extend(figure(fig, img_prefix))
            return out
        if "foot" in cls:
            return para(node.kids, italic=True)
        # 没有语义 class 的 div:有块级子元素就当容器,否则当段落
        if any(isinstance(k, Node) and k.tag in BLOCKISH for k in node.kids):
            return render_blocks(node, img_prefix)
        return para(node.kids)
    return render_blocks(node, img_prefix)  # 其余标签一律当容器


def render_blocks(node, img_prefix):
    blocks, buf = [], []

    def flush():
        if buf:
            s = "".join(buf).strip()
            buf.clear()
            if s:
                blocks.append(lead_guard(s))

    for k in node.kids:
        if isinstance(k, str) or k.tag not in BLOCKISH:
            buf.append(inline([k]))
        else:
            flush()
            blocks.extend(render_block(k, img_prefix))
    flush()
    return blocks


def find(node, tag):
    for kid in node.elements():
        if kid.tag == tag:
            return kid
        hit = find(kid, tag)
        if hit is not None:
            return hit
    return None


def main(argv):
    if len(argv) < 3:
        raise SystemExit(__doc__)
    src, dst, rest = argv[1], argv[2], argv[3:]
    img_prefix, head = "", []
    while rest:
        a = rest.pop(0)
        if a == "--img-prefix" and rest:
            img_prefix = rest.pop(0)
        elif a == "--head" and rest:
            head.append(rest.pop(0))
        else:
            raise SystemExit(__doc__)
    with open(src, encoding="utf-8") as handle:
        tree = Tree()
        tree.feed(handle.read())
        tree.close()
    body = find(tree.root, "body")
    if body is None:
        raise SystemExit("HTML 里找不到 <body>")
    blocks = [quote([h]) for h in head] + render_blocks(body, img_prefix)
    text = "\n\n".join(blocks) + "\n"
    with open(dst, "w", encoding="utf-8") as handle:
        handle.write(text)
    all_nodes = []

    def walk(n):
        for k in n.kids:
            if isinstance(k, Node):
                all_nodes.append(k)
                walk(k)

    walk(body)
    print(f"已写出 {dst}: {len(text)} 字符,{len(blocks)} 个块;"
          f"HTML 中 标题 {sum(k.tag in HEADING for k in all_nodes)} / 表格 {sum(k.tag == 'table' for k in all_nodes)} / 图片 {sum(k.tag == 'img' for k in all_nodes)}",
          file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv)
