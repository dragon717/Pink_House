# AGENTS.md — Codex / 编码代理指引

> 本文件由 Codex CLI 自动注入。其他 LLM agent 也按这里的硬约束执行。

## 本地开发偏好

- 在进行 iOS 开发时，可以按任务需要运行 `xcodebuild` 构建、测试或模拟器验收；运行后需在结果中记录命令、通过/失败状态和验证边界。若用户明确说本次不跑构建，则遵守该次约束。
- 进行鸿蒙 / 安卓开发时，用命令行编译。

## 编码规则

- 始终按 UTF-8 读写和解析文件、命令输出、日志、JSON 与路径，尤其是包含中文的路径。
- 如果遇到类似 `\xe6\xb8\xb8\xe6\x88\x8f` 的字节转义，优先把它当作 UTF-8 字节序列还原为中文，不要按 Latin-1/ASCII 解释。
- 生成 JSON、HTTP header、环境变量或跨进程序列化内容时，中文路径需要使用 UTF-8，并在 HTTP header 中使用 ASCII-safe 表示（例如 JSON 转义、percent-encoding 或 base64），避免把原始非 ASCII 字节直接塞进 header。

## 仓库 source of truth

- **Swift / Xcode 工程在 iCloud 写**：`/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House`
  - 含中文 + 空格，shell 路径必须 quote
  - 用变量：`PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"`
- **不写**：`/Users/muniao/Downloads/Pink_House`（鸿蒙 DevEco 用，独立 .git，靠 iCloud 文件级同步）
- **鸿蒙 / ArkTS / harmony_next** 才在 Downloads 写

## 主题皮肤复刻 — 历史 harness 与正式规则

工程已有 `ThemeSkin` 框架（`ItemManager/Services/ThemeSkin/*` + `ItemManager/Views/ThemeSkin/*`），架构与 slot 已落地。本系列任务 = **接入素材，不改架构**。

`temp/_harness/` 是历史 harness / 待迁移归档，不再作为永久 source of truth 或 runtime 依赖。删除 `temp` 前，必须先把仍有效的主题元数据、素材清单、执行脚本、验收规则和 PSD/image2 说明迁入 `docs/` 或 `tools/`；在迁移闭环前，它只能作为历史参考和清理核对输入。手动 image2 素材入库优先使用正式入口 `tools/theme_skin/materialize_manual_image2_assets.rb`，该脚本默认读取 `tools/theme_skin/theme_manifest.yaml`；只有复核历史清单时才用 `--manifest-path temp/_harness/MANIFEST.yaml`。

历史 harness 当前结构：

```text
temp/_harness/
├── README.md          # 入口与流程图
├── MANIFEST.yaml      # 两主题元数据 + 通用 imageset 清单 + 验收基准
├── EXEC_PLAN.md       # 通用执行（按 ${THEME_*} 变量替换）
├── ACCEPT_PLAN.md     # 通用验收（A–O 15 验收点）
└── ASSETS_SPEC.md     # PSD 导图层 pipeline
```

每主题自己的产物：

```text
temp/<theme-dir>/_artifacts/
├── generated/   # 中间产物（抠图 / PSD 导出 / image2 草稿，含 .meta.json）
├── runs/<ts>/   # Codex 跑模拟器的截图
└── accept/<ts>/ # Claude 验收截图 + RESULT.md
```

### 已落地主题与未闭环项

| THEME_ID | 目录 | 设计稿 | source_type | 状态 |
|---|---|---|---|---|
| `theme_skin.sky_concert` | `temp/主题1/` | 天空音乐会.psd（2480×3319） | psd | 代码 ✅ / Asset Catalog 素材 ✅ / dry-run ✅ / A-O 视觉验收待跑 / 历史占位 imageset 待清理 |
| `theme_skin.swan_dream` | `temp/主题2/` | 天鹅入梦.psd（4000×4000） | psd | 代码 ✅ / Asset Catalog 素材 ✅ / dry-run ✅ / A-O 视觉验收待跑 / 历史占位 imageset 待清理 |

### 复刻顺序

1. 主题1 天空音乐会
2. 主题2 天鹅入梦

### 使用历史 harness 的方式（迁移前临时参考）

需要复核历史资料时，每个会话起手指定 THEME_ID：

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
THEME_ID="theme_skin.sky_concert"   # 或 theme_skin.swan_dream
```

Codex prompt 顶端写 `THEME_ID = <value>`，再按历史 `EXEC_PLAN.md` / `ACCEPT_PLAN.md` 复核。不要把这些 `temp/_harness` 文件继续扩写成长期流程；新增或仍有效规则应迁入正式 `docs/` 或 `tools/`。

### 新增主题的最小步骤

1. 在 `temp/` 下建 `<theme-dir>/`，丢设计稿
2. 在正式主题文档 / 工具清单中登记主题元数据和素材映射；如果仍临时借用历史 harness，再同步 `MANIFEST.yaml`
3. 起 Codex 会话 → 按正式 docs/tools 执行；历史 `EXEC_PLAN.md` 只作迁移前参考
4. 完成后按正式验收清单做 A-O 视觉验收；历史 `ACCEPT_PLAN.md` 只作迁移前参考

不再需要每主题一份 harness 副本，也不应把新流程继续沉淀在 `temp/_harness`。

## 主题包硬约束（所有主题通用）

- `ThemeSkinSlot.rawValue` 不改（`enabledSlots` 持久化兼容）
- `ThemeSkinManager` 存档 key 不改（`theme_skin.owned` / `theme_skin.active_selection`）
- 旧下线主题商品静态定义不改（历史归档兼容），但不要重新注册到商店列表
- 素材必须进 `Assets.xcassets/ThemeSkin/<namespace>/`，不走 Bundle 文件路径
- 三件套 Components（Home/TabBar/Wardrobe）的程序化绘制兜底**保留**，图缺失也得能跑
- 主题未启用时，禁止任何主题装饰泄漏到默认皮肤
- 不允许跨主题混搭组件（`ThemeSkinManager` 已强制；UI 层别绕过）
- slot 列表所有主题统一 18 个，禁止增减

## Git / 分支

- **禁止** force push
- **禁止** `--no-verify` 跳 hook
- 主分支：`main`
- commit 文案中文 OK

## 模拟器与构建

需要用 Computer Use / 电脑控制做模拟器 UI 验收时，先按 `docs/XCODE_SIMULATOR_COMPUTER_USE_ACCEPTANCE.md`：对当前目标模拟器重新编译、安装并重启新进程，再读取 Simulator 画面。

```bash
cd "$PROJ"
xcodebuild -scheme ItemManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet build
xcrun simctl boot "iPhone 16 Pro" 2>/dev/null || true
xcrun simctl install booted "$PROJ/build/Debug-iphonesimulator/ItemManager.app"
BUNDLE_ID=$(grep -m1 PRODUCT_BUNDLE_IDENTIFIER "$PROJ/ItemManager.xcodeproj/project.pbxproj" | awk -F'= ' '{print $2}' | tr -d ';" ')
xcrun simctl launch booted "$BUNDLE_ID"
```

## 验收图基准（所有主题共用）

验收基准图的语义与迁移状态见 `docs/THEME_SKIN_VISUAL_BASELINES.md`。历史引用路径为：

- `temp/design/IMG_7936.png` — 衣橱主页
- `temp/design/IMG_7937.png` — 衣橱统计页
- `temp/design/IMG_8204.PNG` — 大世界 House 页
- `temp/design/IMG_8208.PNG` — 财富页
- `temp/design/IMG_8211.PNG` — 穿搭手帐页

当前 iCloud 仓库未发现完整 `temp/design/` 目录；不同主题视觉不同但**版式一致**，删除 `temp` 前需先找回这些基准图、迁入正式基准目录，或记录正式替代来源。

## 协作角色（双 computer use）

- **Codex computer use** = 执行端：切图 / PSD 导出 / 改 Swift / build / 跑模拟器 → `_artifacts/runs/<ts>/`
- **Claude computer use** = 验收端：按 `ACCEPT_PLAN.md` 逐项打分 → `_artifacts/accept/<ts>/RESULT.md`

## 卡住怎么办

- 看不懂 ThemeSkin 架构 → 读 `docs/少女衣橱主题皮肤重构方案.md`
- 不知道 manifest 字段 → 先看 `docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md`；迁移完成前可对照历史 `temp/_harness/MANIFEST.yaml` 顶部注释
- imageset 加完 Xcode 找不到 → 检查 target membership + namespace 文件夹的 `provides-namespace: false`
- PSD 图层导出全空 → `psd-tools` 默认只导可见层，先 `layer.visible = True`
- iCloud 同步锁文件 → `find "$PROJ" -name "*.icloud"` 或 `brctl download "$PROJ"`
- 模拟器键盘不响应 → 模拟器是 click 层，输入用 `xcrun simctl io booted setText`
