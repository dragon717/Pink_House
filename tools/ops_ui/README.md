# `tools/ops_ui/` —— Mac 运营 UI 的静态门禁

本目录放**不跑 App、不联网、无第三方依赖**的静态检查，用来守那些「编译通过与单测全绿
都发现不了」的界面缺陷。

## `check_markdown_callsites.py`

守 **Markdown 渲染**这一条：`Text(字面量)` 会解析 Markdown，`Text(变量)` 与
`Text("a" + "b")` **不会** → 变量文案必须过 `PinkHouseOps/Views/OpsFormSupport.swift`
的 `opsMarkdown(_:)`。漏掉一处的表现只是界面上多一对星号 —— 不崩、不报错、测试不红，
所以只能靠静态检查 + 快照。

```bash
python3 tools/ops_ui/check_markdown_callsites.py             # 扫 PinkHouseOps/；退出码 1 = 有违规
python3 tools/ops_ui/check_markdown_callsites.py --root X    # 换目录（如扫 SharedCatalog）
python3 tools/ops_ui/check_markdown_callsites.py --self-test # 内嵌 18 例自证
```

两条规则：

- **R1**（纯语法，无约定）：`Text(` / `Label(` 的参数里含 `**`，但参数**不是一个完整字面量**。
  只有两种形态会解析 Markdown ——「单个字符串字面量」与「字面量 + 纯参数标签」；
  `"a" + "b"`、`cond ? "a" : "b"`、`String(format:)` 都不解析。
- **R2**（按字段名的约定）：把叙事字段 `guidance` / `lastErrorMessage` / `label` / `help` /
  `subtitle` 直接喂给 `Text` / `Label`。这些字段的值住在别的文件里（共享包 / 服务层），
  星号在调用点**看不见**，只能按名字拦。

  ⚠️ 清单**刻意很窄**：`value` / `text` / `title` 这类会**承载数据**的名字不能进 ——
  例如 `OpsTag(text:)` 会收到 `product.category`。对数据做 Markdown 解析会把 `A_B`
  变成斜体，那是**改坏数据**，比多一对星号更糟。

⚠️ **能力边界**：静态检查看不到调用方传进来的字符串。`Text(label)` 里的星号可能在
**生产端**（`OpsOptionalDateField` 的 `label:` 来自 `OpsSeriesConfigView`）—— 所以
**组件自己也要把 `label` / `help` 过 `opsMarkdown`**，由 R2 拦「组件没这么做」。

⚠️ **改检查器后必须重跑 `--self-test`**：18 例里既有「该报的」也有「不该报的」
（单字面量、注释里的星号、文案里的括号、`OpsFootnote(text:)`、插值字面量…），
专门防误报把正确写法逼回去。

配套的快照验收见 skill `pink-house-xcodebuild-acceptance` §1d。
