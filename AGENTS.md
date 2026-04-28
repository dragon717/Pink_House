# AGENTS.md — Codex / 编码代理指引

> 本文件由 Codex CLI 自动注入。其他 LLM agent 也按这里的硬约束执行。

## 仓库 source of truth

- **Swift / Xcode 工程在 iCloud 写**：`/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House`
  - 含中文 + 空格，shell 路径必须 quote
  - 用变量：`PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"`
- **不写**：`/Users/muniao/Downloads/Pink_House`（鸿蒙 DevEco 用，独立 .git，靠 iCloud 文件级同步）
- **鸿蒙 / ArkTS / harmony_next** 才在 Downloads 写

## 主题皮肤复刻 — 通用 harness

工程已有 `ThemeSkin` 框架（`ItemManager/Services/ThemeSkin/*` + `ItemManager/Views/ThemeSkin/*`），架构与 slot 已落地。本系列任务 = **接入素材，不改架构**。

通用 harness 在 `temp/_harness/`，**一份模板覆盖所有主题**：

```
temp/_harness/
├── README.md          # 入口与流程图
├── MANIFEST.yaml      # 两主题元数据 + 通用 imageset 清单 + 验收基准
├── EXEC_PLAN.md       # 通用执行（按 ${THEME_*} 变量替换）
├── ACCEPT_PLAN.md     # 通用验收（A–O 15 验收点）
└── ASSETS_SPEC.md     # PSD 导图层 pipeline
```

每主题自己的产物：

```
temp/<theme-dir>/_artifacts/
├── generated/   # 中间产物（抠图 / PSD 导出 / image2 草稿，含 .meta.json）
├── runs/<ts>/   # Codex 跑模拟器的截图
└── accept/<ts>/ # Claude 验收截图 + RESULT.md
```

### 待复刻主题

| THEME_ID | 目录 | 设计稿 | source_type | 状态 |
|---|---|---|---|---|
| `theme_skin.sky_concert` | `temp/主题1/` | 天空音乐会.psd（2480×3319） | psd | manifest ✅ / 代码 ✅ / 素材 dry-run ✅ / 验收待跑 |
| `theme_skin.swan_dream` | `temp/主题2/` | 天鹅入梦.psd（4000×4000） | psd | manifest ✅ / 代码 ✅ / 素材 dry-run ✅ / 验收待跑 |

### 复刻顺序

1. 主题1 天空音乐会
2. 主题2 天鹅入梦

### 跑 harness 的方式

每个会话起手必须指定 THEME_ID：

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
THEME_ID="theme_skin.sky_concert"   # 或 theme_skin.swan_dream
```

Codex prompt 顶端写 `THEME_ID = <value>`，整份 `EXEC_PLAN.md` 喂下去；Codex 自己用 `yq` / `pyyaml` 从 `MANIFEST.yaml` 解析 `${...}` 变量。验收同理喂 `ACCEPT_PLAN.md`。

### 新增主题的最小步骤

1. 在 `temp/` 下建 `<theme-dir>/`，丢设计稿
2. 在 `MANIFEST.yaml` 的 `themes[]` 追加一条
3. 起 Codex 会话 → 喂 `EXEC_PLAN.md` + `THEME_ID`
4. 完成后起 Claude 验收 → 喂 `ACCEPT_PLAN.md`

不再需要每主题一份 harness 副本。

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

- **禁止**碰 git 主题分支
- **禁止** force push
- **禁止** `--no-verify` 跳 hook
- 主分支：`main`
- commit 文案中文 OK

## 模拟器与构建

```bash
cd "$PROJ"
xcodebuild -scheme ItemManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet build
xcrun simctl boot "iPhone 16 Pro" 2>/dev/null || true
xcrun simctl install booted "$PROJ/build/Debug-iphonesimulator/ItemManager.app"
BUNDLE_ID=$(grep -m1 PRODUCT_BUNDLE_IDENTIFIER "$PROJ/ItemManager.xcodeproj/project.pbxproj" | awk -F'= ' '{print $2}' | tr -d ';" ')
xcrun simctl launch booted "$BUNDLE_ID"
```

## 验收图基准（所有主题共用）

- `temp/design/IMG_7936.png` — 衣橱主页
- `temp/design/IMG_7937.png` — 衣橱统计页
- `temp/design/IMG_8204.PNG` — 大世界 House 页
- `temp/design/IMG_8208.PNG` — 财富页
- `temp/design/IMG_8211.PNG` — 穿搭手帐页

不同主题视觉不同但**版式一致**，验收图作为版式基准，颜色 / 装饰随主题。

## 协作角色（双 computer use）

- **Codex computer use** = 执行端：切图 / PSD 导出 / 改 Swift / build / 跑模拟器 → `_artifacts/runs/<ts>/`
- **Claude computer use** = 验收端：按 `ACCEPT_PLAN.md` 逐项打分 → `_artifacts/accept/<ts>/RESULT.md`

## 卡住怎么办

- 看不懂 ThemeSkin 架构 → 读 `docs/少女衣橱主题皮肤重构方案.md`
- 不知道 manifest 字段 → `temp/_harness/MANIFEST.yaml` 顶部注释列了全部
- imageset 加完 Xcode 找不到 → 检查 target membership + namespace 文件夹的 `provides-namespace: false`
- PSD 图层导出全空 → `psd-tools` 默认只导可见层，先 `layer.visible = True`
- iCloud 同步锁文件 → `find "$PROJ" -name "*.icloud"` 或 `brctl download "$PROJ"`
- 模拟器键盘不响应 → 模拟器是 click 层，输入用 `xcrun simctl io booted setText`
