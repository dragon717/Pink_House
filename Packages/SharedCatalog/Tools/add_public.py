#!/usr/bin/env python3
"""给迁进 SharedCatalog 的源码批量补 `public`（确定性实现，可重复跑）。

## 为什么需要它

共享包之外的 App 要能访问这些类型，类型**和它的成员**都必须 `public`
（Swift 默认 internal，且 `public` 类型不会让成员自动变 `public`）。
迁入的 4 个文件原本是 App 内部代码，合计约 230 处声明要加。

## 难点：区分「类型成员」与「函数体里的局部声明」

局部声明加 `public` 是编译错误（`attribute 'public' can only be used in a
non-local scope`）。**前两版实现都在这里翻过车**，值得记下来：

### 版本一（单靠缩进启发式）—— 错
判据是「栈顶是类型 且 缩进 = 栈顶缩进 + 4」。但 `var/let` 分支**从不弹栈**，
于是「indent 4 的方法」压进来的 `(FUNC, 4)` 会一直留在栈顶，
紧跟其后的同层属性全被当成局部变量漏加。
实测代价：`CatalogMoney.displayText`、`CatalogPriceArchive` 的十几个计算属性、
`ShopCatalogRootIndex` 的整组字段。

### 版本二（让 var 也弹栈）—— 更错
修完漏加，又把**真正的局部变量**误判成成员：
`init(from:)` 里的 `let c = try decoder.container(...)`、`tarData` 里的
`let padding`、`appendFingerprint` 里的 `var calendar` 全被加上 `public`。
根因是**已经写了 `public` 的行不匹配旧的声明正则**（正则不认识限定符），
所以已限定的方法从不入栈，作用域栈整体错位。

### 版本三（本文件）—— 花括号配对
不再猜缩进，直接按 `{` / `}` 维护作用域栈：

  · 声明是否算成员 ⟺ 栈空（顶层）**或**栈顶作用域是「类型」；
  · 类型声明（struct/enum/class/actor/extension/protocol）在第一个 `{` 处压入 TYPE；
  · 函数声明（func/init/subscript/deinit）压入 FUNC；
  · `var/let` 带闭包初始化（`= {`）也压入 FUNC —— 否则属性初始化闭包里的
    局部变量会被当成成员（本项目实测有 `static let iso8601Fractional = { let f = … }`）；
  · 右花括号把 `open_depth` 越界的作用域弹掉。

字符串与注释先「涂白」再数括号，避免 `"\\(a) / \\(b)"` 这类插值干扰配对。
"""
import pathlib
import re
import sys

TYPE = "type"
FUNC = "func"

DECL = re.compile(
    r"^(?P<indent>[ \t]*)"
    r"(?:(?:private|fileprivate|internal|public|open|package)\s+)?"
    r"(?:(?:nonisolated|static|mutating|indirect|final|required|convenience|override)\s+)*"
    r"(?P<kind>var|let|func|init|subscript|deinit|struct|enum|class|actor|extension|protocol|typealias)\b"
)

TYPE_KINDS = {"struct", "enum", "class", "actor", "extension", "protocol"}
FUNC_KINDS = {"func", "init", "subscript", "deinit"}
QUALIFIERS = ("private", "fileprivate", "internal", "public", "open", "package")


def blank_out(line: str, in_block_comment: bool) -> tuple[str, bool]:
    """把注释与字符串字面量涂成空格，只留结构性字符（用于数花括号）。"""
    out: list[str] = []
    index = 0
    length = len(line)
    while index < length:
        char = line[index]
        if in_block_comment:
            if line.startswith("*/", index):
                in_block_comment = False
                out.append("  ")
                index += 2
            else:
                out.append(" ")
                index += 1
            continue
        if line.startswith("//", index):
            break
        if line.startswith("/*", index):
            in_block_comment = True
            out.append("  ")
            index += 2
            continue
        if char == '"':
            out.append(" ")
            index += 1
            while index < length:
                if line[index] == "\\":
                    out.append(" ")
                    index += 2
                    continue
                if line[index] == '"':
                    out.append(" ")
                    index += 1
                    break
                out.append(" ")
                index += 1
            continue
        out.append(char)
        index += 1
    return "".join(out), in_block_comment


def already_qualified(line: str) -> bool:
    stripped = line.strip()
    return any(stripped == q or stripped.startswith(q + " ") for q in QUALIFIERS)


def process(path: pathlib.Path) -> int:
    lines = path.read_text(encoding="utf-8").split("\n")
    # 作用域栈：元素 (kind, open_depth)；open_depth = 其左花括号之后的花括号深度
    scope_stack: list[tuple[str, int]] = []
    depth = 0
    in_block_comment = False
    changed = 0
    # 多行签名：`{` 常常不在声明那一行上，例如
    #     static func stage(
    #         _ data: Data, …
    #     ) throws -> StagedMedia {
    # 声明行没有 `{` 就压不了栈，函数体里的局部变量会全被当成类型成员。
    # 所以把「本行声明的应该是哪种作用域」挂起来，等真正遇到 `{` 再压。
    pending_scope: str | None = None

    for index, line in enumerate(lines):
        code, in_block_comment = blank_out(line, in_block_comment)
        body = code.lstrip()

        # ---- 1) 行首连续的 `}` 先结算：它们可能关掉当前作用域
        consumed = 0
        for position, char in enumerate(body):
            if char == "}":
                consumed = position + 1
            else:
                break
        for _ in range(consumed):
            depth -= 1
            while scope_stack and scope_stack[-1][1] > depth:
                scope_stack.pop()
        rest = body[consumed:]

        match = DECL.match(line)

        # ---- 2) 判定本行声明的成员身份（外层作用域 = 当前栈顶）
        opens_scope = False
        scope_kind = None
        if match:
            kind = match.group("kind")
            if kind in TYPE_KINDS:
                scope_kind = TYPE
            elif kind in FUNC_KINDS:
                scope_kind = FUNC
            elif kind in ("var", "let") and "{" in rest:
                # 带花括号的 var/let 有**两种**，体里都是函数体、局部变量都不是成员：
                #   · 计算属性      `var x: T { … }`
                #   · 闭包初始化    `let f = { … }`
                # 只判 `= {` 会漏掉计算属性 —— 实测 `CatalogSaleEvent.appendFingerprint`
                # 里的 `var calendar` / `let day` 就是因此被误加了 public。
                scope_kind = FUNC

            if scope_kind is not None:
                if "{" in rest:
                    opens_scope = True
                else:
                    # 多行签名：`{` 在后面的行上，挂起等它
                    pending_scope = scope_kind

            is_member = (not scope_stack) or scope_stack[-1][0] == TYPE
            # `deinit` 不接受访问级别修饰符（它恒定等于所属类型），必须放过。
            if kind == "deinit":
                is_member = False
            if is_member and not already_qualified(line):
                raw_indent = match.group("indent")
                # ⚠️ 必须从**缩进之后**整行保留，不能从 `match.start('kind')` 截。
                # 旧写法只保留了 kind 之后的内容，而 `static` / `nonisolated`
                # 是被正则的限定符分支吃掉的 —— 结果 `static func f` 变成
                # `func f`（实例成员），编译期报「instance member 'x' cannot be
                # used on type 'Y'」。实测一次剥掉 42 个 static。
                lines[index] = f"{raw_indent}public {line[len(raw_indent):]}"
                changed += 1

        # ---- 3) 结算本行剩余的花括号
        pushed = False
        for char in rest:
            if char == "{":
                depth += 1
                if opens_scope and not pushed:
                    scope_stack.append((scope_kind, depth))
                    pushed = True
                elif pending_scope is not None:
                    # 挂起的作用域终于等到它的 `{`
                    scope_stack.append((pending_scope, depth))
                    pending_scope = None
                    pushed = True
            elif char == "}":
                depth -= 1
                while scope_stack and scope_stack[-1][1] > depth:
                    scope_stack.pop()

    path.write_text("\n".join(lines), encoding="utf-8")
    return changed


def main() -> int:
    root = pathlib.Path(sys.argv[1])
    total = 0
    for path in sorted(root.rglob("*.swift")):
        if path.name == "Package.swift":
            continue
        count = process(path)
        total += count
        print(f"{count:4d}  {path}")
    print(f"合计 {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
