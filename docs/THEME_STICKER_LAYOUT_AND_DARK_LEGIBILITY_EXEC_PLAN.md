# 主题贴纸排布规范 & 暗黑模式文字可读性 · 可执行计划（harness）

> 状态：**2026-05-01 可执行版**。本文档只定义后续实施步骤与验收标准；本次文档修订只改本文档，不改 Swift、不新增脚本、不触碰 Xcode 工程。后续真正执行 T0a 时才新增 `scripts/theme_skin_harness/` 脚本。
> 范围：`ItemManager/Views/ThemeSkin/**` 的贴纸 / 装饰层 / 容器外壳 / 文字可读性，以及 P0/P1 页面中与 ThemeSkin 交界的卡片容器。
> 红线：不改 `ThemeSkinSlot.rawValue` 与 18 个 slot 数量；不改 `ThemeSkinManager` 持久化 key；不改 `temp/_harness/MANIFEST.yaml`；不新增暗黑专用 PNG；不让默认主题被主题装饰波及。

---

## 0. 启动协议（必读）

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
cd "$PROJ"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PYTHONUTF8=1
```

### 0.1 执行边界

- iOS 阶段 **允许 Codex 按任务需要运行 `xcodebuild`** 构建、测试或模拟器验收；静态检查、脚本、diff/parse 级验证仍需保留，并在最终报告中写明实际命令、PASS/FAIL 和未覆盖边界。若用户明确说本次不跑构建，则遵守该次约束。
- 模拟器截图只作为 T0/T1 初筛；**T2 暗黑文字最终验收必须有真机截图 + OCR/WCAG 数据**，不能只用 simulator 结论交差。
- 可提交脚本统一放在 `scripts/theme_skin_harness/`。
- 运行产物统一放在 `temp/_themeharness/runs/<phase>_<ts>/`；该目录位于 ignored `temp/*` 下，默认不提交。
- 每个阶段独立 commit：`[T0a]` / `[T0b]` / `[T1a]` / `[T1b]` / `[T1c]` / `[T2]`，方便回滚与 bisect。
- Swift 阶段的功能开关必须显式分层：背景排布用 `THEMESKIN_LAYOUT_ENGINE_V2`，容器/P0 接入用 `THEMESKIN_CONTAINER_CHROME_V2`，暗黑可读性用 `THEMESKIN_DARK_LEGIBILITY_V2`。

### 0.2 不允许的假修复

- 不把 `Color(hex: "6A647D")` 一刀切替换成 `Color.primary`；主题色必须保留氛围。
- 不用 `colorScheme == .dark ? .white : .black` 作为散落 fallback。
- 不靠单层 `.shadow(color: .black, radius: 8)` 宣称解决文字可读性。
- 不整体拉高/拉低贴纸 opacity；必须按 `heroLayer / midLayer / edgeLayer` 分层。
- 不把主题贴纸替换成 SF Symbol 作为常态；SF Symbol 只能是缺图 fallback。
- 不在滚动 cell 内加入 `.ultraThinMaterial` 或三层 blur backdrop。
- 不用 `Bool.random()` / `CGFloat.random(in:)` 生成贴纸位置；排布必须 deterministic。
- 不把 `patternPlacements` 盲目扩到 50+ 点；先测密度与最小间距。
- 不在 token/服务层依赖 `UITraitCollection.current` 决定 ThemeSkin 暗黑色；由 View 层读取 `@Environment(\.colorScheme)` 后显式 resolve。

---

## 1. 当前事实与问题定位

### 1.1 必读代码

1. `ItemManager/Services/ThemeSkin/ThemeSkinModels.swift`：`ThemeSkinSlot` 18 个 case 是兼容边界，不可增删或改 rawValue。
2. `ItemManager/Views/ThemeSkin/ThemeSkinStickerWallpaperBackground.swift`：背景层仍是 24 个手摆 `patternPlacements`，当前 `base = min(max(size.width, 320), 460)` 对 iPad 横屏不稳定。
3. `ItemManager/Views/ThemeSkin/SkyConcertThemeSkinComponents.swift`：Sky Concert / Swan Dream 各自维护 toolbar、wardrobe backdrop、stats card、wardrobe card、tab bar placement 数组，尚无共享坐标系。
4. `ItemManager/Views/ThemeSkin/ThemeSkinSharedComponents.swift`：`ThemeSkinOrnateFrameStyle` 只有 compact / standard / hero / scrollOptimized 四档，装饰主要是 topTrailing + bottomLeading 两点。
5. `ItemManager/Views/ThemeSkin/ThemeSkinDetailPreviewPanel.swift`：同一面板已混用 `themeManager.primaryTextColor` 与静态 `SkyConcertThemeSkin.labelColor(for:)`。
6. `ItemManager/Views/ThemeSkin/ThemeSkinAssetRendering.swift`：主题图片缺失会走 placeholder，后续 missing asset 记录应接这里。

### 1.2 已确认风险

| ID | 风险 | 触发面 | 代码入口 |
|---|---|---|---|
| H1 | 背景贴纸 24 格手摆，换设备后密度不稳定 | 背景 / iPad 横屏 | `ThemeSkinStickerWallpaperBackground` |
| H2 | 每主题各维护 5 套 placement，新主题成本高 | SC / SD / 新主题 | `SkyConcertThemeSkinComponents` |
| H3 | 18 slot 中 `searchBar / segmentedControl / filterChip / discountBadge / filterSheet` 覆盖薄 | 搜索 / 筛选 / 折扣 | ThemeSkin 调用方 |
| H4 | 大量 `RoundedRectangle / cornerRadius` 容器未接主题 | 编辑 / 设置 / 财富 / 补款 | P0/P1 清单 |
| H5 | `#6A647D` / `#735E78` 暗黑对比度不足 | 暗黑 + 主题文字 | `labelColor(for:)` |
| H6 | light-only shadow / fill / accent 暗黑下浮起感塌陷 | 卡片 / shell | `shadowColor` / fill token |
| H7 | 贴纸 opacity 不随暗黑调整 | 装饰层 | placement / frame style |
| H8 | 文字与贴纸重叠时无 backdrop 或描边 | 衣橱卡 / 预览 | card / preview text |
| H9 | 详情预览面板动态色与静态色混用 | 主题详情页 | `ThemeSkinDetailPreviewPanel` |
| H10 | shared container 只有两角装饰，无四角策略 | section/card | `ThemeSkinSharedComponents` |

### 1.3 P0/P1/P2 覆盖边界

- **P0 必须在 T1c 完成主题容器接入**：`ClothingEditView`、`ClothingPickerView`、`BrandSelectionView`、`MultiDimensionalFilterSheet`、`GlobalSearchView`、`BatchImportView`、`RecycleBinView`、`WardrobeStatisticsDetailView`、`DepositPlan/*` 主面板、`Wealth/BanknoteView`。
- **P1 在 T2 做暗黑可读性 audit，并只修必要文字/容器问题**：设置、补款子页面、ThemePreview、MagicTheme、Network、ModelManagement 等次频视图。
- **P2 不要求接入 ThemeSkin 装饰**：`PerlerBeadsView`、`FrenchRetroSmallWorldView`、`VIP/*`。但暗黑文字可读性仍须满足 T2 标准。

---

## 2. 阶段总览

| 阶段 | 目标 | 是否改 Swift | 可提交产物 | 运行产物 |
|---|---|---:|---|---|
| T0a | 测量脚本 + 报告模板 + baseline 采集 | 否 | `scripts/theme_skin_harness/*.rb`、报告模板 | `temp/_themeharness/runs/T0a_<ts>/` |
| T0b | 最小止血，修明显逻辑漏洞 | 是 | Swift 小改 + tests | `temp/_themeharness/runs/T0b_<ts>/` |
| T1a | 背景贴纸 deterministic Jittered Grid 引擎 | 是 | layout engine + 背景层接入 | `temp/_themeharness/runs/T1a_<ts>/` |
| T1b | shared container 四角策略 | 是 | shared surface 扩展 | `temp/_themeharness/runs/T1b_<ts>/` |
| T1c | P0 页面主题容器接入 | 是 | P0 视图接入 | `temp/_themeharness/runs/T1c_<ts>/` |
| T2 | 暗黑 token + 文字可读性 + P1 audit | 是 | token/backdrop/audit 修复 | `temp/_themeharness/runs/T2_<ts>/` |

---

## 3. T0a：测量脚本与 baseline（不改 Swift）

> T0a 的唯一目标是把问题量化。**不修改 Swift、不改资源、不改 Xcode 工程。**

### 3.1 新增可提交脚本

新增目录：`scripts/theme_skin_harness/`。

1. `audit_unthemed_containers.rb`
   - 输入：`ItemManager/Views/**/*.swift`。
   - 输出：`temp/_themeharness/runs/T0a_<ts>/unthemed.csv`。
   - 规则：含 `RoundedRectangle` / `cornerRadius` 但不含 `ThemeSkin` / `themeSkin` / `WardrobeThemeClothingCardContainer` / `WardrobeListCellBackground` 的视图，输出 `file,line,snippet,suggested_slot,p_tier`。
2. `audit_label_colors.rb`
   - 输入：`ItemManager/Views/ThemeSkin/**/*.swift`。
   - 输出：`temp/_themeharness/runs/T0a_<ts>/label_colors.csv`。
   - 规则：扫描 `Color(hex: "RRGGBB")` 与 `SkyConcertThemeSkin.labelColor(for:)` 调用，生成 light/dark 背景下 WCAG 对比度表。
3. `sticker_density_score.rb`
   - 输入：当前 `ThemeSkinStickerWallpaperBackground.patternPlacements`。
   - 输出：`temp/_themeharness/runs/T0a_<ts>/density.json`。
   - 指标：最小成对距离、4×6 网格 std/mean、iPad 横屏 vs 竖屏密度波动。
4. `theme_skin_audit_report.rb`
   - 输入：上面三份产物。
   - 输出：`temp/_themeharness/runs/T0a_<ts>/REPORT.md`。

### 3.2 初筛截图口径

- 可选使用 simulator 截图初筛：`xcrun simctl io booted screenshot ...`。
- simulator 截图只用于定位明显问题，不作为 T2 最终暗黑可读性结论。
- 可按任务需要由 Codex 运行 `xcodebuild` 完成 build/install 后再做模拟器截图；截图归档需记录构建命令、destination 和截图路径。

### 3.3 T0a 验收

- `scripts/theme_skin_harness/` 下四个脚本可被 git 跟踪，不在 `.gitignore` 命中范围。
- `unthemed.csv`、`label_colors.csv`、`density.json`、`REPORT.md` 产出齐全。
- REPORT 至少列出 H1/H3/H5/H8/H9 各 1 个证据样本。
- 只允许文档/脚本变更，不允许 Swift diff。

---

## 4. T0b：最小止血代码修复（独立 commit）

> T0b 可以改 Swift，但只修明确漏洞，不引入新架构。

### 4.1 必做修复

1. **iPad 横屏背景 base 修正**
   - `ThemeSkinStickerWallpaperBackground` 中把 base 改为基于 `min(size.width, size.height)`：
     `let base = min(max(min(size.width, size.height), 320), 460)`。
2. **背景 placement 最小间距测试**
   - 新增 `ItemManagerTests/ThemeSkinWallpaperPlacementTests.swift`。
   - 断言当前 24 点 normalized pair distance ≥ `0.10`；失败时只挪动冲突点，不重写算法。
3. **装饰层无障碍兜底**
   - grep ThemeSkin 装饰层，补 `.allowsHitTesting(false)` 与 `.accessibilityHidden(true)` 缺口。
4. **ThemeSkinDetailPreviewPanel 文字色归口**
   - 正文 / 标题 / caption 用 `themeManager.primaryTextColor` / `secondaryTextColor`。
   - 主题状态、价格、强调文案才使用主题 accent。
   - 不引入 T2 token，不散落 dark if-else。
5. **asset missing DEBUG 记录**
   - 在 `ThemeSkinAssetAvailability.hasImage` / resolver 失败路径添加 DEBUG log 或 signpost。
   - 不改变 placeholder 行为。

### 4.2 不做事项

- 不接入 P0 页面。
- 不改 `SkyConcertThemeSkin` 静态 hex token。
- 不重写 `patternPlacements` 为算法。
- 不引入 feature flag。

### 4.3 T0b 验收

```bash
cd "$PROJ"
git diff --check
ruby scripts/theme_skin_harness/audit_label_colors.rb
ruby scripts/theme_skin_harness/sticker_density_score.rb
```

- 静态检查通过。
- T0a REPORT 中的最明显横屏/预览文字问题有对应 before/after 记录。
- 最终报告必须明确写明 `xcodebuild` 状态：未运行 / PASS / FAIL；未运行时写清原因和剩余验证边界。

---

## 5. T1a：背景贴纸排布引擎（feature flag 默认 OFF）

> T1a 只处理背景层，不碰 P0 页面接入，不碰暗黑 token。

### 5.1 新增接口

新增 `ThemeSkinStickerLayoutEngine` 与唯一实现 `ThemeSkinJitteredGridEngine`：

```swift
protocol ThemeSkinStickerLayoutEngine {
    func placements(
        containerSize: CGSize,
        descriptor: ThemeSkinDescriptor?,
        slot: ThemeSkinSlot,
        density: ThemeSkinStickerDensity,
        seed: UInt64
    ) -> [ThemeSkinStickerPlacement]
}
```

- `ThemeSkinStickerPlacement.center` 使用 `UnitPoint`。
- `width` 是相对 `min(width, height)` 的比例。
- `seed = hash(namespace, slot, density)`，不得使用无 seed random。
- `ThemeSkinJitteredGridEngine` 是首轮唯一实现；Phyllotaxis / Poisson Disk 仅写入注释为后续备选，不建 stub、不进首轮交付。

### 5.2 Feature flag

新增 `ItemManager/Services/ThemeSkin/ThemeSkinFeatureFlags.swift`：

```swift
enum ThemeSkinFeatureFlags {
    static let layoutEngineV2Key = "THEMESKIN_LAYOUT_ENGINE_V2"
    static let containerChromeV2Key = "THEMESKIN_CONTAINER_CHROME_V2"
    static let darkLegibilityV2Key = "THEMESKIN_DARK_LEGIBILITY_V2"
}
```

- T1a 只读取 `layoutEngineV2Key`。
- T1b/T1c 只读取 `containerChromeV2Key`，不得复用背景排布开关。
- T2 只读取 `darkLegibilityV2Key`。
- Release 默认 OFF；DEBUG 可通过 UserDefaults / launch argument 打开。
- 对应 flag OFF 时完全走旧路径：背景回旧 `patternPlacements`，容器回旧两角/无 P0 装饰，暗黑回旧色彩。

### 5.3 接入范围

- 只在 `ThemeSkinStickerWallpaperBackground` 接入 V2 引擎。
- 旧 `patternPlacements` 保留作为 fallback，至少保留 1 个版本。
- 不迁移 toolbar / wardrobe card / stats card / tab bar placement。

### 5.4 T1a 验收

- flag OFF：截图与 T0b baseline 基本一致。
- flag ON：`density.json` 满足 std/mean ≤ 0.4、最小 pair distance ≥ 0.10、iPad 横竖屏波动 ≤ 10%。
- `git grep -n 'random(in:\|Bool.random' ItemManager/Views/ThemeSkin ItemManager/Services/ThemeSkin` 不命中新增排布代码。

---

## 6. T1b：shared container 四角策略（`THEMESKIN_CONTAINER_CHROME_V2` 默认 OFF）

> T1b 只规范 shared surface，不强制替换历史 5 套 placement 数组。

### 6.1 角色扩展

在 `ThemeSkinEdgeStickerRole` 增加四角语义角色：

- `cardCornerTopLeading`
- `cardCornerTopTrailing`
- `cardCornerBottomLeading`
- `cardCornerBottomTrailing`
- `cardCenterEmblem`

兼容规则：

- 旧 `cardPrimary` 等价于 `cardCornerTopTrailing`。
- 旧 `cardSecondary` 等价于 `cardCornerBottomLeading`。
- 旧 API 不删除，避免大范围调用方改动。

### 6.2 容器策略

新增 `ThemeSkinCornerStrategy`：

| strategy | 行为 | 用途 |
|---|---|---|
| `.compact` | topTrailing 1 个 micro sticker | filterChip / discountBadge |
| `.standard` | topTrailing + bottomLeading | section card 默认 |
| `.hero` | 四角 + center emblem | hero / empty state |
| `.scrollOptimized` | topTrailing 1 个，≤24pt，无 shadow | 列表 cell |
| `.auto` | 按 cornerRadius 与 style 推断 | 现有调用方默认 |

`ThemeSkinSectionCardContainer` 新增可选参数 `cornerStrategy: ThemeSkinCornerStrategy = .auto`。

### 6.3 T1b 验收

- `THEMESKIN_CONTAINER_CHROME_V2=OFF`：旧两角外观不变。
- `THEMESKIN_CONTAINER_CHROME_V2=ON`：shared container 可展示四角策略。
- `scrollOptimized` 每 cell 最多 1 个 sticker，且无 shadow / material。
- 不迁移 P0 页面；只保证 shared API 可用。

---

## 7. T1c：P0 页面主题容器接入（`THEMESKIN_CONTAINER_CHROME_V2` 默认 OFF）

> T1c 才开始改业务视图。目标是 P0 = 100%，不追求 P1/P2 全覆盖。

### 7.1 P0 接入规则

- `searchBar`：`GlobalSearchView` / `MultiDimensionalFilterSheet` 顶部搜索条包 `ThemeSkinSectionCardContainer(slot: .searchBar, cornerRadius: 18, cornerStrategy: .compact)`。
- `segmentedControl`：统计/编辑顶部 segmented 用 `.themeSkinSectionCard(slot: .segmentedControl, cornerRadius: 14, showsDecoration: false)`。
- `filterChip`：筛选胶囊用新 `ThemeSkinFilterChipStyle`，复用 shared container token。
- `discountBadge`：衣橱卡折扣标使用 `.compact` 策略，不加多层 backdrop。
- `filterSheet`：筛选 sheet 外壳用 `slot: .filterSheet, cornerRadius: 28, cornerStrategy: .hero`。
- 编辑、搜索、补款、财富页面只装饰容器 chrome；**不染色用户图片、图表、品牌图、衣物照片**。

### 7.2 覆盖率检查

新增或扩展 `scripts/theme_skin_harness/coverage_check.rb`：

- 输入：T0a 的 `unthemed.csv` + 当前源码。
- 输出：`temp/_themeharness/runs/T1c_<ts>/coverage.json`。
- T1c 出口：P0 coverage = 100%。

### 7.3 T1c 验收

```bash
cd "$PROJ"
git diff --check
ruby scripts/theme_skin_harness/audit_unthemed_containers.rb
ruby scripts/theme_skin_harness/coverage_check.rb
```

- `THEMESKIN_CONTAINER_CHROME_V2=ON` 时 P0 coverage = 100%。
- `THEMESKIN_CONTAINER_CHROME_V2=OFF` 时 P0 页面不得出现新主题贴纸或新容器 chrome。
- 默认主题截图无主题贴纸泄漏。
- 列表滚动路径未新增 material / blur / 多贴纸。
- 报告明确标注 `xcodebuild` 验证状态；若未运行，说明仅完成静态验证与剩余运行风险。

---

## 8. T2：暗黑 token 与文字可读性（`THEMESKIN_DARK_LEGIBILITY_V2` 默认 OFF）

> T2 是治本阶段。只在 T1c 通过后启动。

### 8.1 色彩解析原则

新增 `ThemeSkinColorToken`：

```swift
struct ThemeSkinColorToken {
    let light: Color
    let dark: Color
    func resolved(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? dark : light
    }
}
```

规则：

- View 层使用 `@Environment(\.colorScheme)`，把 `colorScheme` 显式传给 token resolve。
- token、engine、服务层不读 `UITraitCollection.current`。
- 主题正文色保留紫/蓝/金氛围，不退化为 `Color.primary`。
- 浅色 token 保持现有视觉；暗黑 token 先由 `audit_label_colors.rb` 算 4.5:1 / 7:1 后再写入。

### 8.2 首批 token

- Sky Concert：`text #6A647D -> dark #D6CFE0`，`softGold #E5C57C -> dark #F4D798`，shell fill 改为深蓝紫系。
- Swan Dream：`text #735E78 -> dark #E2D2E5`，moon/gold/ribbon 对应提亮。
- shadow：暗黑下不靠高 opacity shadow；用 surface tint + 低 opacity shadow。

### 8.3 文字可读性容器

新增 `ThemeSkinLegibleText`：

- 默认只启用文字本体 + 小半径描边/发光。
- 只有非 cell、非滚动热路径上的装饰重叠文字，才允许启用 Layer 1/2 backdrop blur。
- cell 内禁止三层 blur；最多使用描边/小阴影 + 降低贴纸 opacity。

### 8.4 Surface tint

新增 `ThemeSkinSurfaceTint(for:elevation:colorScheme:)`：

- light：保留现有 shadow 语义。
- dark：使用主题 accent 的 4% / 6% / 8% overlay 表示 elevation，shadow opacity 降低到 ≤0.18。

### 8.5 P1 暗黑 audit

- P1 不强求 ThemeSkin 装饰全接入。
- 必须修正硬编码 `Color.black` / light-only hex 造成的暗黑文字不可读。
- 输出 `temp/_themeharness/runs/T2_<ts>/p1_dark_audit.csv`。

### 8.6 T2 最终验收

- 真机截图 + OCR/WCAG 数据齐全，不能只用 simulator。
- 标题/正文/caption 对比度 ≥ 4.5:1。
- 贴纸覆盖区域文字对比度 ≥ 7:1。
- `git grep -n 'Color(hex: "' ItemManager/Views/ThemeSkin` 只允许命中 token 定义或明确标注的 fallback。
- `git grep -n 'UITraitCollection.current' ItemManager/Views/ThemeSkin ItemManager/Services/ThemeSkin` 不命中新 ThemeSkin token 代码。
- light 模式与默认主题无明显视觉回归。

---

## 9. 验收命令清单

### 9.1 每阶段通用静态检查

```bash
cd "$PROJ"
git diff --check
ruby scripts/theme_skin_harness/audit_label_colors.rb
ruby scripts/theme_skin_harness/sticker_density_score.rb
```

### 9.2 T0a/T1c 覆盖检查

```bash
cd "$PROJ"
ruby scripts/theme_skin_harness/audit_unthemed_containers.rb
ruby scripts/theme_skin_harness/coverage_check.rb
```

### 9.3 ThemeSkin 红线检查

```bash
cd "$PROJ"
git grep -n 'ThemeSkinSlot' ItemManager/Services/ThemeSkin/ThemeSkinModels.swift
git grep -n 'UITraitCollection.current' ItemManager/Views/ThemeSkin ItemManager/Services/ThemeSkin || true
git grep -n 'random(in:\|Bool.random' ItemManager/Views/ThemeSkin ItemManager/Services/ThemeSkin || true
git grep -n 'scripts/theme_skin_harness' docs scripts | head
```

### 9.4 构建与产物说明

- 可按任务需要运行 `xcodebuild`；运行后必须记录命令、scheme、destination、PASS/FAIL 和未覆盖边界。
- 不把 `temp/_themeharness/runs/**` 产物提交到 git。
- 不以 simulator 截图替代 T2 真机验收。

---

## 10. 回滚策略

- T0a：脚本/报告模板可整 commit 回滚。
- T0b：每条止血修复保持小 diff，可单独 revert。
- T1a：关闭 `THEMESKIN_LAYOUT_ENGINE_V2` 回到旧背景 placement。
- T1b/T1c：关闭 `THEMESKIN_CONTAINER_CHROME_V2` 后 shared container / P0 接入回旧外观；如 P0 接入有页面问题，按视图单独 revert。
- T2：关闭 `THEMESKIN_DARK_LEGIBILITY_V2` 回到 T1c 色彩路径；若暗黑回滚，必须保留不会破坏 light/default 的安全修复。

---

## 11. 出口准则

- **T0a 出口**：四个脚本 + baseline 报告完成；无 Swift diff。
- **T0b 出口**：横屏 base、placement test、无障碍、预览文字归口、missing asset DEBUG 记录完成；静态检查通过。
- **T1a 出口**：背景 Jittered Grid 在 flag ON 下通过 density 指标，flag OFF 保持旧视觉。
- **T1b 出口**：shared container 支持四角策略，旧 API 兼容，scrollOptimized 不超性能红线。
- **T1c 出口**：`THEMESKIN_CONTAINER_CHROME_V2=ON` 时 P0 页面 coverage = 100%，默认主题与 flag OFF 路径无装饰泄漏。
- **T2 出口**：ThemeSkin 双值 token + 可读文字路径完成；P1 暗黑 audit 通过；真机 OCR/WCAG 数据达标。
