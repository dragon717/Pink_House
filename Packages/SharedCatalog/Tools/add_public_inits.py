#!/usr/bin/env python3
"""给 SharedCatalog 里「缺显式 init」的 public struct 补上 `public init`。

## 为什么必须有这一步

Swift 的规则：**`public` 结构体的合成逐成员初始化器是 `internal`**
（"the default memberwise initializer ... has an access level of internal"）。
换句话说 `public struct` 并不能让外部模块写 `Foo(a: 1, b: 2)` ——
`public` 只作用于**类型本身**，不作用于编译器合成的那个 init。

迁包前这些结构体都住在 `ItemManager` **同一个模块**里，internal 的逐成员
init 够用；搬进 `Packages/SharedCatalog` 之后，`ItemManager`（iOS）与
`PinkHouseOps`（Mac）都成了**别的模块**，所有直接构造都会报
`'Foo' initializer is inaccessible due to 'internal' protection level`。

## 判定与生成口径

  · 只处理 `public struct`，且该 struct **成员层没有任何 `init` 声明** ——
    已有显式 init 的（CatalogShop / CatalogProduct / ShopCatalog /
    CatalogPriceArchive）一律不碰，避免造出第二个重载把调用方搞歧义。
  · 只收**存储属性**：一行写完的 `public var 名: 类型 [= 默认值]`。
    计算属性（`public var x: T { … }`）、多行声明、静态属性都不收。
  · 参数顺序 = 属性声明顺序；带默认值的属性 → 参数带**同一个**默认值
    （逐字复制，含 `nil` / `[]` / `1`）。
  · 行尾注释会被剥掉，否则默认值里会混进 `[]   // 说明` 这种垃圾。

脚本可重复跑：已经有 `init` 的 struct 会被跳过。
"""
import pathlib
import re
import sys

STORED = re.compile(
    r"^(?P<indent>[ \t]*)public (?P<kind>var|let) (?P<name>\w+)\s*:\s*(?P<type>[^={]+?)"
    r"(?:\s*=\s*(?P<default>.*))?$"
)
STRUCT_HEAD = re.compile(
    r"^(?P<indent>[ \t]*)public (?:(?:nonisolated|final|indirect|@\w+)\s+)*struct (?P<name>\w+)\b")
ANY_INIT = re.compile(r"^[ \t]*(?:public |package |internal |fileprivate |private )?init[?!]?\(")

DOC = "// 跨模块构造入口：`public` 结构体的合成逐成员 init 是 internal，外部模块必须显式声明。"


def strip_line_comment(text: str) -> str:
    """剥掉行尾 `//` 注释（字符串字面量里的 `//` 不算）。"""
    out: list[str] = []
    index = 0
    in_string = False
    while index < len(text):
        char = text[index]
        if in_string:
            out.append(char)
            if char == "\\" and index + 1 < len(text):
                out.append(text[index + 1])
                index += 2
                continue
            if char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            out.append(char)
            index += 1
            continue
        if text.startswith("//", index):
            break
        out.append(char)
        index += 1
    return "".join(out).rstrip()


def build_init(params: list[tuple[str, str, str | None]], indent: str) -> str:
    """按 `indent` 生成 init 文本。

    `indent` **必须**来自外层 struct 的实际成员缩进，不能写死 4 个空格：
    嵌套类型（如 `MediaUploadJobMachine.Progress`）的成员缩进是 8 个空格，
    写死会让生成的 init 与所属类型缩进不一致 —— 轻则格式错乱，
    重则把后面的计算属性挤出作用域。
    """
    inner = indent + "    "
    pieces = [
        f"{name}: {type_text}" if default is None else f"{name}: {type_text} = {default}"
        for name, type_text, default in params]
    one_line = f"{indent}public init(" + ", ".join(pieces) + ") {"
    if len(one_line) <= 96:
        head = [one_line]
    else:
        head = [f"{indent}public init("]
        for index, (name, type_text, default) in enumerate(params):
            tail = "," if index < len(params) - 1 else ""
            if default is None:
                head.append(f"{inner}{name}: {type_text}{tail}")
            else:
                head.append(f"{inner}{name}: {type_text} = {default}{tail}")
        head.append(f"{indent}) {{")
    body = [f"{inner}self.{name} = {name}" for name, _, _ in params]
    return "\n".join(["", f"{indent}{DOC}", *head, *body, f"{indent}}}"])


class Frame:
    __slots__ = ("name", "inner", "indent", "props", "last_line", "has_init")

    def __init__(self, name: str, inner: int, indent: str) -> None:
        self.name = name
        self.inner = inner
        self.indent = indent
        self.props: list[tuple[str, str, str | None]] = []
        self.last_line = -1
        self.has_init = False


def process(path: pathlib.Path) -> int:
    lines = path.read_text(encoding="utf-8").split("\n")
    frames: list[Frame] = []
    insertions: list[tuple[int, str]] = []
    depth = 0

    def close(frame: Frame) -> None:
        if frame.props and not frame.has_init:
            insertions.append((frame.last_line, build_init(frame.props, frame.indent)))

    for index, raw in enumerate(lines):
        code = strip_line_comment(raw)
        body = code.lstrip()

        # 1) 行首连续的 `}` 先结算作用域
        consumed = 0
        for char in body:
            if char != "}":
                break
            consumed += 1
        for _ in range(consumed):
            depth -= 1
            while frames and frames[-1].inner > depth:
                close(frames.pop())
        rest = body[consumed:]

        # 2) 成员层：判定本行是不是存储属性 / init
        if frames and depth == frames[-1].inner:
            frame = frames[-1]
            if ANY_INIT.match(code):
                frame.has_init = True
            matched = STORED.match(code)
            if matched and "{" not in matched.group("type"):
                default = matched.group("default")
                # `let` 带默认值 = 已初始化常量，**不参与**逐成员 init
                # （Swift 规则：这类参数会被合成 init 直接省略），收了会造出
                # 一个无法赋值的参数。`public let name: String`（无默认值）则必须收。
                if matched.group("kind") == "let" and default is not None:
                    continue
                frame.props.append((
                    matched.group("name"),
                    matched.group("type").strip(),
                    None if default is None else re.sub(r"\s+", " ", default.strip())))
                frame.last_line = index

        # 3) 本行是否开了新的 struct 作用域
        head = STRUCT_HEAD.match(code)
        if head is not None and "{" in rest:
            frames.append(Frame(
                head.group("name"), depth + 1, head.group("indent") + "    "))

        # 4) 结算本行剩余花括号
        for char in rest:
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                while frames and frames[-1].inner > depth:
                    close(frames.pop())

    while frames:
        close(frames.pop())

    if not insertions:
        return 0
    for line_index, block in sorted(insertions, key=lambda item: -item[0]):
        lines.insert(line_index + 1, block)
    path.write_text("\n".join(lines), encoding="utf-8")
    return len(insertions)


def main() -> int:
    root = pathlib.Path(sys.argv[1])
    total = 0
    for path in sorted(root.rglob("*.swift")):
        if path.name == "Package.swift":
            continue
        count = process(path)
        total += count
        if count:
            print(f"{count:4d}  {path}")
    print(f"合计补了 {total} 个 public init")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
