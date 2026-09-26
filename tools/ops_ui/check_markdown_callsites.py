#!/usr/bin/env python3
"""Mac 运营 UI 的 Markdown 渲染回归锁（静态检查，不联网、不写任何文件）。

## 为什么需要一道可执行的门禁

`Text("**重点**")` 会解析 Markdown，`Text(变量)` 与 `Text("a" + "b")` **不会** ——
后两者走的是 `String` 的逐字初始化器，星号原样显示成 `**重点**`。

本仓库（含共享包 `SharedCatalog` 的 `guidance` 等字段）大量用 `**…**` 标重点，
所以**凡是从变量来的文案都要过 `opsMarkdown(_:)`**
（`PinkHouseOps/Views/OpsFormSupport.swift`）。

这条规则只靠「改的时候记得」守不住：漏掉一处的表现是界面上多了一对星号 ——
不报错、不崩、单测不会红。2026-09-27 做应用内离屏快照时才发现这一类漏网
**已经存在很久了**（`opsMarkdown` 自己以前也是坏的）。所以把它变成可执行的门禁。

## 两条规则

R1 —— 确定违规（不需要任何约定，纯语法）：
    `Text(` / `Label(` 的参数里含 `**`，且这个参数**不是一个完整的字符串字面量**。
    被允许的形态只有两种：
      · 单个字符串字面量          —— `Text("…**…**…")`（走 LocalizedStringKey，会解析）
      · 字面量 + 纯参数标签        —— `Label("…**…", systemImage: "x")`
    其余形态（`"a" + "b"`、`cond ? "a" : "b"`、`String(format:)`…）都**不解析** → 报错。

R2 —— 跨文件的叙事字段（只能按字段名拦）：
    把「给运营看的说明性字段」直接喂给 `Text(` / `Label(`。
    这些字段的值住在别的文件里（共享包 / 服务层），星号在这里**看不见**。
    过了 `opsMarkdown` 的调用点不会被匹配（那种写法里根本没有 `Text(`）。

    字段名清单刻意保持很窄：只收「语义上一定是文案」的字段。
    `value` / `text` / `title` 这类**会承载数据**的名字**不能进清单** ——
    例如 `OpsTag(text:)` 会收到 `product.category`，那是数据；
    对数据做 Markdown 解析会把 `A_B` 变成斜体，属于改坏数据，比星号更糟。

## 能力边界（这条决定了 R2 为什么要收 `label` / `help`）

静态检查**看不到调用方传进来的字符串值**。
`OpsOptionalDateField(label:)` 自己写的是 `Text(label)`，星号在**生产端**
（`OpsSeriesConfigView` 的 `"预约结束时间（**驱动自动流转**）"`）—— 两边分开看都没毛病。
所以唯一能守住的形态是：**组件自己也要把 `label` / `help` 过 `opsMarkdown`**，
由 R2 拦「组件没这么做」。这也是把 `label` / `help` 放进清单的真正原因。

代价要说清楚：这是一条**按名字的约定**，不是语义分析。
新写一个 `Text(caption)`（`caption` 不在清单里）不会被告警 —— 但那种情况
参数里若真有星号，R1 会拦（只要它不是单个字面量）。

## 用法

    python3 tools/ops_ui/check_markdown_callsites.py            # 扫 PinkHouseOps/
    python3 tools/ops_ui/check_markdown_callsites.py --root X
    python3 tools/ops_ui/check_markdown_callsites.py --self-test  # 用内嵌样例自证

退出码：0 = 干净；1 = 有违规；2 = 用法错误。
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# R2 的字段名清单：只收「语义上一定是给运营看的文案」的字段。
NARRATIVE_FIELDS = (
    "guidance",
    "lastErrorMessage",
    "label",
    "help",
    "subtitle",
)

# 会被检查的调用（`Text(` / `Label(` 才是逐字渲染；`OpsFootnote` 等已经自己过了 opsMarkdown）
SCANNED_CALLEES = ("Text", "Label")


class Literal:
    """一个字符串字面量在源文件里的位置。"""

    __slots__ = ("start", "end", "has_interpolation")

    def __init__(self, start: int, end: int, has_interpolation: bool) -> None:
        self.start = start
        self.end = end
        self.has_interpolation = has_interpolation


def mask_source(src: str) -> tuple[str, list[Literal]]:
    """把注释与字符串字面量都替换成空格，**保持字符偏移不变**。

    为什么要保留偏移：后面要按括号配对从 `masked` 里切参数、又要回 `src` 里读原文，
    两边索引对得上才不用再写一遍位置映射。

    为什么去注释时要尊重字符串：仓库文案里就有 `//` 与 `/*`（路径、URL、说明）。
    反过来，字符串里的 `(` `)` 也必须被抹掉，否则括号配对会被文案里的括号带偏。

    返回 (masked, literals)；`literals` 用来判断「参数是不是一个完整的字面量」。
    """
    out: list[str] = []
    literals: list[Literal] = []
    i = 0
    n = len(src)

    while i < n:
        ch = src[i]

        # ── 行注释 ──
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
            continue

        # ── 块注释（Swift 支持嵌套，按深度配对）──
        if src.startswith("/*", i):
            depth = 1
            j = i + 2
            while j < n and depth > 0:
                if src.startswith("/*", j):
                    depth += 1
                    j += 2
                elif src.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            out.append(" " * (j - i))
            i = j
            continue

        # ── 字符串字面量 ──
        if ch == '"':
            start = i
            # 多行 """ 或 原始 #"…"#（含 ####"…"####）都归一处理
            hashes = 0
            k = i - 1
            while k >= 0 and src[k] == "#":
                hashes += 1
                k -= 1
            quote = '"' * (3 if src.startswith('"""', i) else 1)
            closes = quote + ("#" * hashes)
            j = i + len(quote)
            has_interp = False
            while j < n:
                if src.startswith("\\", j) and not src.startswith(closes, j):
                    # 转义：跳过下一个字符（含 \( 插值，插值本身也整体当字面量抹掉）
                    if src.startswith("\\(", j):
                        has_interp = True
                    j += 2
                    continue
                if src.startswith(closes, j):
                    j += len(closes)
                    break
                j += 1
            out.append(" " * (j - start))
            literals.append(Literal(start, j, has_interp))
            i = j
            continue

        out.append(ch)
        i += 1

    return "".join(out), literals


def _match_paren(masked: str, open_index: int) -> int | None:
    """`masked[open_index]` 是 `(`；返回配对的 `)` 的下标。"""
    depth = 0
    for j in range(open_index, len(masked)):
        c = masked[j]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return j
    return None


def _is_literal_only(masked_arg: str) -> bool:
    """参数是不是「字面量 + 纯参数标签 + 逗号」这一种会解析 Markdown 的形态。

    `masked_arg` 里所有字面量都已经变成空格，所以只要看剩下什么：
      · 什么都不剩                                   → 单个字面量            ✅
      · 只剩 `, systemImage:` 这类「标识符 :」        → 字面量 + 标签         ✅
      · 还剩别的（`+`、`?`、标识符、调用…）           → 运行时才拼出来         ❌
    """
    residual = re.sub(r"[A-Za-z_][A-Za-z0-9_]*\s*:", "", masked_arg)  # 去掉参数标签
    residual = residual.replace(",", "")
    return residual.strip() == ""


def _narrative_field_in(masked_arg: str) -> str | None:
    """参数是不是「某个叙事字段」本身（R2）。

    只看**第一个**参数：`Label(kind.guidance, systemImage: "…")` 里
    `systemImage:` 那一截不是我们要判的东西，按顶层逗号切掉。
    """
    first_arg = masked_arg.split(",", 1)[0]
    stripped = first_arg.strip()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*", stripped):
        return None
    tail = stripped.rsplit(".", 1)[-1]
    return tail if tail in NARRATIVE_FIELDS else None


def check_text(src: str, path: str) -> list[str]:
    """返回该文件里的违规（已经格式化好的字符串）。"""
    masked, _ = mask_source(src)
    findings: list[str] = []

    for callee in SCANNED_CALLEES:
        for m in re.finditer(rf"(?<![A-Za-z0-9_.]){callee}\s*\(", masked):
            open_index = masked.index("(", m.start())
            close = _match_paren(masked, open_index)
            if close is None:
                continue
            masked_arg = masked[open_index + 1 : close]
            raw_arg = src[open_index + 1 : close]
            line = src.count("\n", 0, m.start()) + 1

            # R1：参数里带星号，但拼出来才成为字符串
            if "**" in raw_arg and not _is_literal_only(masked_arg):
                first_line = raw_arg.strip().splitlines()[0].strip()
                findings.append(
                    f"{path}:{line}: [R1] {callee}(…) 的参数里有 ** 但不是一个完整字面量"
                    f" —— 不会解析 Markdown，星号会逐字显示。"
                    f"\n        改法：外包一层 opsMarkdown(…)。参数开头：{first_line[:70]}"
                )
                continue

            # R2：直接把叙事字段喂给 Text/Label
            field = _narrative_field_in(masked_arg)
            if field is not None:
                findings.append(
                    f"{path}:{line}: [R2] {callee}(…{field}) 直接把叙事字段交给逐字渲染。"
                    f"\n        改法：{callee} {{ opsMarkdown(…) }} —— 或改用 OpsFootnote。"
                )

    return findings


SELF_TEST_CASES: list[tuple[str, bool]] = [
    # (源码, 期望是否违规)
    ('Text("**重点**")', False),
    ('Text("演练（构建 + 校验 + 计划，但**不写线上**）")', False),
    ('Label("结果待确认：**不要重发**", systemImage: "exclamationmark.triangle.fill")', False),
    ('Text("这是**替换**不是合并。" + "下半句。")', True),
    ('Label("还没有基线快照："\n      + "严格策略的作用域因此是**整份目录**。",\n      systemImage: "info.circle")', True),
    ('Text(center.useDryRun ? "开着**不写线上**" : "关着")', True),
    ('Text("测试")', False),                       # 没星号：不管
    ('Text(value)', False),                        # 变量，且名字不在清单里（value 会装数据）
    ('Text(subtitle)', True),                      # R2：subtitle 在清单里
    ('Text(kind.guidance)', True),                 # R2
    ('Label(kind.guidance, systemImage: "info.circle")', True),
    ('opsMarkdown("**重点**")', False),            # 正确写法不该被误报
    ('OpsFootnote(text: some.guidance)', False),   # 已经自己过了 opsMarkdown
    ('// Text("注释里的 ** 不该被算")', False),
    ('/* Text("块注释里的 ** 也不该被算") */', False),
    ('Text("文案里有括号 ( 与 **星号**")', False),
    ('let url = "https://x.dev/a"  // Text("尾部注释 **")', False),
    (r'Text("\(name) 的**重点**")', False),         # 单字面量插值：LocalizedStringKey 路径，会解析
]


def self_test() -> int:
    failures = 0
    for source, should_flag in SELF_TEST_CASES:
        got = bool(check_text(source, "<self-test>"))
        if got != should_flag:
            failures += 1
            print(f"❌ 自证失败：期望{'违规' if should_flag else '放行'}，实际相反 → {source!r}")
    total = len(SELF_TEST_CASES)
    if failures == 0:
        print(f"✅ 检查器自证：{total} 例全部符合预期")
    else:
        print(f"❌ 检查器自证：{failures}/{total} 例不符合预期")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Mac 运营 UI 的 Markdown 渲染回归锁")
    parser.add_argument("--root", default="PinkHouseOps", help="要扫描的目录（默认 PinkHouseOps）")
    parser.add_argument("--self-test", action="store_true", help="只跑内嵌样例")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    root = Path(args.root)
    if not root.is_dir():
        print(f"❌ 目录不存在：{root}", file=sys.stderr)
        return 2

    files = sorted(root.rglob("*.swift"))
    if not files:
        print(f"❌ {root} 下没有 .swift 文件", file=sys.stderr)
        return 2

    findings: list[str] = []
    for path in files:
        findings.extend(check_text(path.read_text(encoding="utf-8"), str(path)))

    if findings:
        print(f"❌ Markdown 渲染门禁：{len(findings)} 处违规")
        print()
        for item in findings:
            print(f"  {item}")
        print()
        print("说明：`Text(字面量)` 会解析 Markdown，`Text(变量)` / `Text(\"a\" + \"b\")` 不会。")
        print("      变量文案一律走 PinkHouseOps/Views/OpsFormSupport.swift 的 opsMarkdown(_:)。")
        return 1

    print(f"✅ Markdown 渲染门禁：{len(files)} 个文件，0 处违规")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
