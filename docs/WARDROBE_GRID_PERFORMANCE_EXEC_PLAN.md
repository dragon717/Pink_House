# 衣橱列表 · 网格视图（Grid）性能 · 执行计划与验收标准

> 状态：**2026-04-30 仅文档，未改代码**。本计划与
> [`docs/WARDROBE_LIST_SCROLL_PERFORMANCE_EXEC_PLAN.md`](./WARDROBE_LIST_SCROLL_PERFORMANCE_EXEC_PLAN.md)（以下简称「列表 P 计划」）
> 并列：**列表 P 计划聚焦"通用滚动 / 数据 / 图片管线"，本文档仅聚焦 grid2 / grid3 / grid6
> 三档网格布局所特有的卡顿点**（视图层级、主题包装、`LazyVGrid` 容器、网格 cell 长按预览）。
> 列表（`listBrief / listDetailed`）与详情页性能不在本计划范围。
>
> 列表 P 计划已在 P0 + P0.5 落地的项（重复内容不再展开，本计划在其基础上叠加）：
> - `filteredClothings` 改 `@State`，`.task(id: filterSignature)` 后台重算（`WardrobeView.swift:655-657, 1758-1797`）。
> - `WardrobeClothingSnapshot` / `WardrobeFilterEngine` 全部 `Sendable + nonisolated`（`WardrobeView.swift:69-187`）。
> - stats 改 `filteredStatsSummary @State`（`WardrobeView.swift:357, 1582-1588`）。
> - `WardrobeCellSnapshot` 解耦 cell 与 `Clothing`（`ClothingCard.swift:15-58`）。
> - `ImageDecodeSemaphore` 限并发解码（`ImageManager.swift:32-62`）。
> - NSCache bucket 化 + 切换布局清旧桶（`ImageManager.swift:71, 698-709, 808-812`）。
> - `inFlightImageLoads` 去重（`ImageManager.swift:72, 730-734, 756-758`）。
> - 按布局分档目标尺寸：grid2=160 / grid3=112 / grid6=64（`WardrobeView.swift:1799-1816`）。
> - 切布局即时预取首屏（`WardrobeView.swift:1818-1849`）。
> - cell `.task` 内 `Task.sleep(50ms)` 已全部移除（`ClothingCard.swift:336-351, 449-464`）。
>
> 范围（grid 专属，必须改）：
> - `ItemManager/Views/WardrobeView.swift` — `gridWardrobeView / gridScrollBody / wardrobeGridCell / selectionGridCell / clothingItemView / gridColumns`。
> - `ItemManager/Views/ClothingCard.swift` — `ClothingCard`（grid2 / grid3）/ `ClothingThumbnail`（grid6）/ `WardrobeListCellBackground`。
> - `ItemManager/Views/ThemeSkin/WardrobeThemeSkinComponents.swift` — `WardrobeThemeClothingCardContainer` 的 `scrollOptimized` 分支。
>
> 不动：SwiftData schema、`Clothing` / `StoredImage` 字段、iCloud 同步链路、引导锚点
> `captureGuideTarget(.wardrobeSelectionCard)`、主题资产（`SkyConcert / SwanDream`）清单。

---

## 0. 启动协议（必读）

执行任何步骤前先把以下变量写入会话上下文，**必须与列表 P 计划共享同一份 seed / 设备矩阵**，便于横向对比：

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
TARGET_FILES=(
  "ItemManager/Views/WardrobeView.swift"
  "ItemManager/Views/ClothingCard.swift"
  "ItemManager/Views/ThemeSkin/WardrobeThemeSkinComponents.swift"
)
GRID_LAYOUTS=("grid2" "grid3" "grid6")            # 本计划只关心这三档
LOW_END_DEVICES=("iPhone SE (2nd gen)" "iPhone 8" "iPhone XR")
MID_DEVICES=("iPhone 12" "iPhone 13")
HIGH_DEVICES=("iPhone 16 Pro")
DATA_TIERS=(50 200 800 2000)
THEME_MATRIX=("default" "skyConcert" "swanDream") # 必跑：主题皮肤直接放大 grid 阴影/边框成本
```

### 0.1 不允许的"假优化"（grid 特化）

- 把 `LazyVGrid` 退回 `VStack(ForEach)` 或 `ScrollView { HStack }` —— 一次性 inflate 所有 cell，瞬间 OOM。
- 通过 `if performanceTier == .low { /* hide grid6 */ }` 直接砍布局档位。grid6 是产品强需求，不能砍。
- 在 grid cell 上加 `DispatchQueue.main.asyncAfter` 分帧 inflate 假装"流畅"。
- 为节省渲染把主题皮肤角标整体隐藏（详见列表 P 计划 §5.5）。
- 把 `.contextMenu` 整体删掉 —— 长按菜单是 grid 唯一进入"复制 / 删除 / 进入选择模式"的入口。

---

## 1. 必读上下文（顺序固定）

1. `ItemManager/Views/WardrobeView.swift:461-479` — `gridColumns`（grid 列数 / spacing 决策）。
2. `ItemManager/Views/WardrobeView.swift:481-526` — `clothingItemView` / `visibleItemFrameReporter` / `guideSelectionAnchor`。
3. `ItemManager/Views/WardrobeView.swift:1001-1063` — `gridWardrobeView / gridScrollContent / gridScrollBody`（含 `statsSection` 同栈）。
4. `ItemManager/Views/WardrobeView.swift:1065-1123` — `wardrobeGridCell / selectionGridCell`（normal / selection / editing 三态）。
5. `ItemManager/Views/WardrobeView.swift:1799-1849` — `wardrobeCellImageTargetSize / initialImagePrefetchLimit / prefetchInitialWardrobeImages`。
6. `ItemManager/Views/ClothingCard.swift:131-403` — `ClothingCard`（grid2/grid3 主 cell，含 4 路 `skirtFillMode` switch + `colorScheme` 分支 + 多角标 overlay）。
7. `ItemManager/Views/ClothingCard.swift:406-466` — `ClothingThumbnail`（grid6 cell）。
8. `ItemManager/Views/ClothingCard.swift:60-120` — `WardrobeListCellContainer / WardrobeListCellBackground`（非主题路径仍直读 `themeManager.cardStyle` 等 6 个字段）。
9. `ItemManager/Views/ThemeSkin/WardrobeThemeSkinComponents.swift:119-214` — `WardrobeThemeClothingCardContainer` 的 `scrollOptimized` 分支。
10. 列表 P 计划 §3 / §5（**不重读，作为基础**）。

---

## 2. 性能基线测量（动手前必跑）

### 2.1 数据集复用

- 复用列表 P 计划 §2.1 的 `seed_wardrobe_perf.swift` 数据；本计划**不**额外建 seed 工具。
- 主题维度：每组 `(设备, 数据档)` 还需在 `THEME_MATRIX` 三档下各跑一次（默认 / 天空音乐会 / 天鹅之梦），主题皮肤会显著放大网格阴影 / 边框 / 装饰图层成本。
- 总矩阵：`3 设备 × 4 数据档 × 3 布局 × 3 主题 = 108 组`。≤ 2GB 设备 + 800 件 + 默认主题为 P0 必测；其余可在 G1/G2 阶段轮跑。

### 2.2 指标定义（grid 专属）

| 指标 | 测量方法 | G0 门槛（≤ 2GB + 800 件 + 默认主题） | G2 目标（同条件） |
|---|---|---|---|
| grid2 滚动平均帧率 | Animation Hitches，匀速滑 5s | ≥ 56 fps | ≥ 59 fps |
| grid3 滚动平均帧率 | 同上 | ≥ 55 fps | ≥ 59 fps |
| grid6 滚动平均帧率 | 同上 | ≥ 53 fps | ≥ 58 fps |
| grid 单次切换二次回滚耗时（grid2↔grid3↔grid6） | `signpost` 包裹 `viewLayout onChange` | ≤ 220 ms | ≤ 90 ms |
| 主题切换（默认↔天空音乐会）后首帧 | 在 ThemeSkinManager 推送日志包夹 `signpost` | ≤ 350 ms | ≤ 120 ms |
| grid cell `contextMenu` 长按 → 预览首帧 | `signpost contextMenuOpen → previewVisible` | ≤ 350 ms | ≤ 180 ms |
| grid 选择模式切换（进入/退出）后首帧 | `isSelectionMode onChange` 前后 `signpost` | ≤ 250 ms | ≤ 100 ms |
| 严重掉帧（hitch > 250ms） | Animation Hitches | 0 | 0 |
| grid6 800 件冷进入到稳态首帧 | Time Profiler `WardrobeView.body` 第一次返回 | ≤ 1.8 s | ≤ 1.0 s |

> 不再单测峰值/稳态内存：列表 P 计划已覆盖；grid 不引入新解码尺寸（仍用 160/112/64 三档）。

### 2.3 基线快照存档

```bash
mkdir -p "$PROJ/temp/_perf/wardrobe_grid/$(date +%Y%m%d-%H%M)/baseline"
# 每个 (设备, 数据档, 布局, 主题) 跑一次，存：
#   - .trace（Instruments Time Profiler + Animation Hitches）
#   - hitches_<layout>_<theme>.png
#   - signposts.csv（layout switch / theme switch / context menu open / selection toggle）
#   - notes.md（主观手感，必填："丝滑/能用/明显卡"，逐布局逐主题描述）
```

**G0 不允许跳过基线**。基线缺失即不允许进入下一阶段。

---

## 3. 现状问题清单（grid 专属，按层级分类）

> 沿用列表 P 计划编号体系，新增前缀 `G-`（grid view-only）。已在列表 P 计划 P0/P0.5 落地的不再列入。

### 3.1 视图层级（Grid Container）

| 编号 | 位置 | 问题 | 影响 |
|---|---|---|---|
| G-V1 | `WardrobeView.swift:461-479` `gridColumns` 是计算属性 | 每次 body 都 `Array(repeating: GridItem(.flexible(), spacing:, alignment: .top), count:)` 重建 | grid6 = 6 列；body 每帧重建一遍，破坏 LazyVGrid 列布局 diff |
| G-V2 | `WardrobeView.swift:1047-1063` `gridScrollBody` 把 `statsSection` 与 `LazyVGrid` 同放一层 `ScrollView { VStack }` | `showStats.toggle()` / `filteredStatsSummary` 变更触发整 ScrollView 重新 layout，含 LazyVGrid | 进入衣橱后改一次过滤、按一次"显示/隐藏统计" → 整网格重 layout（hitch） |
| G-V3 | `WardrobeView.swift:1066-1093` `wardrobeGridCell` 用 `if isSelectionMode {} else if isEditing {} else { Button + contextMenu }` 三态 switch | 进入/退出选择模式时整网格 cell 类型变化 → SwiftUI 全量重建（不能 diff） | 800 件 grid6 进选择模式可见 ~400ms 卡顿 |
| G-V4 | `WardrobeView.swift:482-504` `clothingItemView` 内 `.background(visibleItemFrameReporter(for:))` 始终附着 | `visibleItemFrameReporter` 仅在 `isReorderTrackingEnabled` 内部 gate；常态滚动也走该 modifier 链 | 每个 cell 多一层 background 节点；800 cells × 修饰符 = 不必要的 view tree 体积 |
| G-V5 | `WardrobeView.swift:1001-1029` `gridWardrobeView` 用 `ScrollViewReader { proxy in let filtered = ...; let displayed = ...; let firstFilteredID = ... ZStack { ... } }` | `let filtered = filteredClothings` 等三个 `let` 在 body 内，配合 `ZStack` + 编辑时 drag 区两层 `Color.clear` | 非编辑模式仍计算 `displayed = isReorderTrackingEnabled ? editableClothings : filtered`；可恢复成"显式分支" |
| G-V6 | `WardrobeView.swift:609` 外层 `.containerAdaptiveColors(background: .ultraThinMaterial)` 应用在 `baseWardrobeView` | grid 屏背景全屏毛玻璃；与 cell 分离已 OK，但全屏 material + 主题皮肤背景叠加在 ≤ 2GB 设备上仍造成离屏 | 不算 cell 内部黑洞，但属于 grid 顶层成本 |
| G-V7 | `WardrobeView.swift:348-359` 顶层 `@ObservedObject private var themeSkinManager = ThemeSkinManager.shared` + body 路径上 `wardrobeThemeDescriptor` = `themeSkinManager.descriptor(for: .wardrobeItemCard)` 每帧解析 | `ThemeSkinManager` 任何 publish（含装饰资产预加载完成）都让整页 + 所有 grid cell 重 diff | 主题装饰图加载期间滚动 fps 抖动 |

### 3.2 Cell 主题/订阅成本（Grid Cell）

| 编号 | 位置 | 问题 | 影响 |
|---|---|---|---|
| G-C1 | `ClothingCard.swift:146-148` 仍直 `@Environment(ThemeManager.self)` + `\.colorScheme` + `\.containerPalette` | 违反列表 P 计划 §5.1 硬约束 | `ThemeManager` / 系统颜色模式变化 → **所有可见 grid cell 同步刷新**；与 `WardrobeCellSnapshot` 解耦的努力被这三道环境订阅再次"打通" |
| G-C2 | `ClothingCard.swift:84` `WardrobeListCellBackground` 也 `@Environment(ThemeManager.self)` 并直读 6 个字段（`cardStyle / cardBackgroundColor / cardTintColor / transparentOpacity / tintOpacity / strokeOpacity`） | 非主题皮肤路径仍把"全屏 cell 同步刷新"问题原样保留 | 主题色微调（用户拖滑动条）→ 全网格重渲染 |
| G-C3 | `ClothingCard.swift:259-281, 480-501` `Group { switch themeManager.skirtFillMode { ... 4 路 ... } }` 在 `ClothingCard.body` 与 `ThemedPlaceholderView.body` 中重复 4 分支 | 每个 grid cell 在图片背景上做 4 路条件分支 + colorScheme 分支 | grid6 = 800 cells × 同样判断 = view tree 体积膨胀 |
| G-C4 | `ClothingCard.swift:299-331` 三个角标（3D 立绘 / 心愿尾款 / 库存>1）各自 `wardrobeCellBadge(...)` + `isThemeSkinThemed ? : ` 分支 | 单 cell ≤ 3 个角标，加在一起每 cell 多 6 路条件求值 + 多个 capsule clip | 网格视图下角标命中率高（库存 + 心愿尾款常见），叠加成本不可忽略 |
| G-C5 | `WardrobeThemeSkinComponents.swift:144-154` `scrollOptimized=true` 路径仍带 `.background(ThemeSkinOrnateFrameSurface)` + `.shadow(...)` | 主题皮肤启用时，每 grid6 cell 一层 frame surface + shadow → GPU 离屏渲染 6 列 × 屏内可见行 | 启用主题（天空音乐会）后 grid6 fps 显著下降 |
| G-C6 | `ClothingCard.swift:131-138` `ClothingCard.==` 已覆盖 5 字段（snapshot/showPrice/showOriginalPrice/wardrobeThemeDescriptor/imageTargetSize），但**不覆盖** colorScheme / themeManager.skirtFillMode / cardStyle | 受 `Equatable` 短路保护 → SwiftUI 认为 cell 未变；但内部 `body` 又依赖 colorScheme/themeManager 真实值 → **行为不确定**（视觉延迟 / 偶发不刷新） | 主题切换瞬间会出现"半屏老主题、半屏新主题"≥ 1 帧 |

### 3.3 LazyVGrid 长按 / 上下文菜单（iOS 26 Liquid Glass）

| 编号 | 位置 | 问题 | 影响 |
|---|---|---|---|
| G-M1 | `WardrobeView.swift:1088-1092` 每个 grid cell 挂 `.contextMenu { let _ = MenuPerfSignpost.contextMenuOpen("wardrobe.grid_cell"); contextMenuItems(for: clothing) }` | iOS 26 长按生成 GPU snapshot；cell 含主题外框 + shadow + 4 角标 → snapshot 成本高 | grid6 长按预览首帧 ≥ 400ms（实测） |
| G-M2 | `WardrobeView.swift:1706-1737` `contextMenuItems(for clothing: Clothing)` 直接接收 `Clothing` SwiftData model | 长按时 closure 捕获 `Clothing` 实例（含 `tags / brand` to-many 关系），SwiftUI 拍照过程中可能触发 lazy load | 可能造成长按瞬间主线程突发 fault |
| G-M3 | 与列表 P 计划 menu doc 已记 M-3 重复 | iOS 26 cell `contextMenu` 上方未禁 `.ultraThinMaterial`；**grid 已不在 cell 用 material**（OK），但外层 `WardrobeThemeClothingCardContainer` 阴影未在长按预览前压平 | snapshot 仍带模糊 + 阴影 |

### 3.4 切换 / 预取竞态

| 编号 | 位置 | 问题 | 影响 |
|---|---|---|---|
| G-P1 | `WardrobeView.swift:658-661` `.onChange(of: viewLayout) { evict + prefetch }` 立即触发 | 用户连续点 grid2 → grid3 → grid6 时，每次都 evict 老桶 + 启动 N=8/12/30 张预取；解码 semaphore 排队拥塞 | "切布局时图片闪一下" + 切完 1-2 秒内新布局首屏空白 |
| G-P2 | `WardrobeView.swift:1818-1829` `initialImagePrefetchLimit` 写死（grid2=8 / grid3=12 / grid6=30） | 未按设备 tier 区分；≤ 2GB 设备 grid6=30 直接打满 NSCache `countLimit=60` 一半 | grid6 滚动到第 2 屏即触底 evict |
| G-P3 | `WardrobeView.swift:1831-1849` `prefetchInitialWardrobeImages` 取 `prefix(limit * 2)` 后再 `compactMap firstImagePath`，未做 visibility-based 预取 | 用户已滚到 200 行外，仍预取 0..(limit*2) 的旧首屏 | 浪费解码 semaphore 资源 |

---

## 4. 优化方案（按落地成本三阶段）

### 4.1 G0 · 不动架构、清显式黑洞（1–2 天，必须全做）

目标：把 §2.2 拉到 **G0 门槛**；不引入新组件；不改 `WardrobeView` / `ClothingCard` 拆分结构。

| 任务 ID | 改动点 | 硬约束 |
|---|---|---|
| G0-1 | `gridColumns` 改 `@State [GridItem]` 或私有缓存（`viewLayout` 变化时 `onChange` 重算） | 不允许在 body 路径上 `Array(repeating:GridItem(...))`。`spacing` / `alignment` 必须沿用现值 |
| G0-2 | `clothingItemView` 中 `.background(visibleItemFrameReporter(for:))` 改为 `if isReorderTrackingEnabled { ... .background(...) } else { ... }` 在外层 gate；不要 gate 在 modifier 内部 | 编辑模式下行为必须保持；`WardrobeVisibleItemFramePreferenceKey` 仍只在编辑/选择拖拽时收集 |
| G0-3 | `ClothingCard` / `WardrobeListCellBackground` 的 `@Environment(ThemeManager.self)` + `\.colorScheme` 改为 `let` 输入 —— 由 `WardrobeView` 读一次顶层 `themeManager.skirtFillMode` / `cardStyle` / `colorScheme` 等，打成 `WardrobeCellThemeInputs` `Hashable struct` 通过 init 传入 | `ClothingCard.==` 必须把这个 inputs 加入比较；`@Environment(\.containerPalette)` 暂保留（已是结构传导） |
| G0-4 | `ClothingCard.body` 中 image 背景的 `Group { switch themeManager.skirtFillMode { ... } }` 改为 `WardrobeCellThemeInputs.imageBackgroundColor: Color` 一次性算好；`ThemedPlaceholderView` 同 | 4 路分支必须搬到 `WardrobeCellThemeInputs` 的纯函数派生（在 G0-3 同 patch 内做） |
| G0-5 | 主题描述符缓存：`WardrobeView` 引入 `@State wardrobeThemeDescriptor: ThemeSkinDescriptor?`，`ThemeSkinManager` 切换时 `onReceive` 更新一次；body 路径上不再调用 `themeSkinManager.descriptor(for:)` | `@ObservedObject themeSkinManager` 仍保留（保证 `onReceive` 通道），但禁止 body 内取值 |
| G0-6 | `wardrobeGridCell` 三态 switch 改为：单 `Button { }` 包装 + `ZStack(alignment: .topTrailing) { clothingItemView; selectionOverlay }`，selection 半透明圆圈用 `if isSelectionMode { overlay }`；编辑/拖拽用 `.draggable / .dropDestination`（iOS 16+）替代 `.onDrag/.onDrop` —— 至少不再把整个 cell view 类型按模式切换 | 重构必须保持 **引导锚点 `captureGuideTarget(.wardrobeSelectionCard)` 不丢失**（在 `clothingItemView` 内部，OK）；`MenuPerfSignpost.contextMenuOpen` 原样保留 |
| G0-7 | `gridScrollBody` 的 `statsSection` 改用 `safeAreaInset(edge: .top)` 或单独 `Section`，不与 `LazyVGrid` 同 ScrollView | 不允许把 statsSection 整体替换成自定义 SectionHeader（保留"显示/隐藏"按钮和过渡） |
| G0-8 | `prefetchInitialWardrobeImages` 在 `viewLayout onChange` 内 debounce 200ms（同步把 `prefetchTask?.cancel()` 加上）；首次进入页面仍立即触发 | 用户单次切换 grid2→grid3→grid6 时只预取最终目标布局，避免中间档浪费 |
| G0-9 | `initialImagePrefetchLimit` 按 `PerformanceTier`（与列表 P 计划 §4.3 共享）分档：≤ 2GB grid6 = 18（不再 30）/ grid3 = 8 / grid2 = 6；4GB+ 维持现值 | 不允许直接把 grid6 限制砍到 0 |
| G0-10 | `contextMenuItems(for clothing: Clothing)` 改为接收 `WardrobeCellSnapshot`（无关 SwiftData lazy load）；具体动作仍按 id 反查 `clothings` | `selectionMode` / `delete` / `copy` 行为不能变 |
| G0-11 | `ClothingCard.==` 必须把 G0-3 引入的 `WardrobeCellThemeInputs` 加入比较 | `==` 不允许永远返回 true / false；不允许只比 id |

**G0 验收门槛**：§2.2 G0 门槛全部满足；并且：
- `grep -n "@Environment(\\\\.colorScheme)\\|@Environment(ThemeManager" ItemManager/Views/ClothingCard.swift` 计数 = 0（含 `WardrobeListCellBackground`）
- `grep -n "Array(repeating: GridItem" ItemManager/Views/WardrobeView.swift` 计数 = 0
- `grep -n "themeSkinManager.descriptor" ItemManager/Views/WardrobeView.swift` 在 body 路径计数 = 0（仅允许 `onReceive` 内）
- 主题切换瞬间无"新老主题混排 ≥ 1 帧"现象（§6.4 视觉回归）

### 4.2 G1 · 容器与主题包装重设计（3–5 天）

目标：把指标拉到 G0 ↔ G2 中间档；引入"主题快照 + 容器解耦 + ContextMenu Preview 显式压平"。

- **`WardrobeCellThemeInputs` 升级为 `@Observable WardrobeCellThemeFacet`（iOS 17+）**，由 `WardrobeView` 持有；变化时按 hash 比较，仅在真实差异时重新派发到 cell。
- **`WardrobeThemeClothingCardContainer.scrollOptimized` 网格档**：拆出 `WardrobeGridCellChrome`（专用于 grid，layout-aware）。
  - grid6：纯 `RoundedRectangle.fill`，**禁** shadow / OrnateFrameSurface（即使主题启用）；主题色彩 token 改为顶部 1px hairline + 主题色 `tint`。
  - grid3：保留淡 shadow（radius ≤ 1），ornate frame surface 简化为 `LinearGradient` 单层。
  - grid2：保留 `scrollOptimized` 路径现状，但 shadow `radius` 由 2 → 1。
  - 必须在 `WardrobeThemeSkinComponents.swift` 内新增分档；**禁止**在 `ClothingCard.body` 里写 `if viewLayout == .grid6 { ... }`（仍由父层注入 chrome）。
- **`gridWardrobeView` 拆分**：`statsSection` 用 `safeAreaInset(edge: .top)` 真正与 `LazyVGrid` 解耦（G0-7 的最终形态）；进入/退出 stats 不再触发网格 layout。
- **ContextMenu Preview 显式提供**：grid cell 改为 `.contextMenu { ... } preview: { GridCellSnapshotPreview(snapshot:) }`，预览视图为**纯 `RoundedRectangle + Image`** 无主题外框无 shadow，长按瞬间不再用复杂 cell 做 GPU snapshot。
- **`prefetchInitialWardrobeImages` 升级为 visibility-based**：在 `LazyVGrid` 内用 `onAppear/onDisappear` 收集"刚滚到底部 N 行"的 fileName；停止滚动 200ms 后才发起预取（与列表 P 计划 P1 保持一致）。
- **进入选择模式优化**：`isSelectionMode` 切换走 `withTransaction { transaction.disablesAnimations = true }`，避免每个 cell 在 selection overlay 出现/消失时跑动画。

**G1 验收门槛**：
- `(800 件 + 默认主题) grid6 fps ≥ 56`、`(800 件 + 天空音乐会主题) grid6 fps ≥ 53`。
- 进入选择模式 → 全选 800 件 → 退出选择，主线程不阻塞 ≥ 200ms。
- 长按 grid cell 预览首帧 ≤ 220ms（默认主题）/ ≤ 280ms（主题皮肤启用）。
- `grep -n "scrollOptimized: true" ItemManager/Views/ClothingCard.swift` 替换为 `chrome: .gridX(...)` 注入；ClothingCard 体内不再依赖 viewLayout。

### 4.3 G2 · 视觉降级与高级优化（按需，2–3 天）

目标：达成 §2.2 G2 目标值。仅在 G1 之后再考虑。

- **`PerformanceTier` 复用**（与列表 P 计划 §4.3 共享同一注入路径）：
  - `.low`：grid6 cell 完全 `Color.clear` 背景 + 1px hairline；3D / 尾款 / 库存角标改单色 capsule（**不能丢文字**）；grid3/grid2 shadow `radius = 1`。
  - `.mid`：grid6 保留 1px hairline；其余 shadow `radius = 2`。
  - `.high`：保持 G1 形态。
- **`WardrobeGridCellChrome` 在 `.low` 档进入"全无离屏"模式**：`scrollOptimized` 路径完全压平为 `Color.clear`。主题色 token 由顶部 hairline 与图片角标传递。
- **图片解码统一管线**（与列表 P 计划 §4.3 共用 actor）：grid 可视区 cell 优先 `.userInitiated`；预取 `.background`；主题切换瞬间打 `.utility`。
- **网格滚动到顶/底 haptic** 沿用 `HapticsManager.softTick()` + 200ms 节流（不在本计划新增）。
- **iOS 26 Liquid Glass 探索（可选）**：在 `.high` 档接入 `.contextMenu(menuItems: ..., preview: { LiquidGlassPreview(...) })` 官方 preview，长按预览自动 GPU 加速；`.low` / `.mid` 档保持 G1 自定义 preview。

---

## 5. 标准与硬约束（grid 专属，叠加在列表 P 计划 §5 之上）

### 5.1 SwiftUI（grid）

- `gridColumns`、`spacing`、`alignment` 不允许在 body 路径上即时构造 `[GridItem]` 数组。
- `wardrobeGridCell` 不允许通过"按 mode 切 view 类型"的方式实现选择/编辑态切换；必须用 overlay/disable + 单一 view 主体。
- grid cell 不允许直读 `@Environment(ThemeManager.self) / \\.colorScheme`；必须由父层注入 `WardrobeCellThemeInputs / WardrobeCellThemeFacet`。
- `LazyVGrid` 与 `statsSection` 不允许嵌套在同一 `ScrollView { VStack { ... } }`（G0-7 之后绝不允许回退）。
- `WardrobeListCellBackground` 不允许直订阅 `@Environment(ThemeManager.self)`；必须接收派生值（G1 起强制）。

### 5.2 LazyVGrid 容器

- 不允许在 grid cell `body` 内写 `if viewLayout == .gridX { ... }`（要由父层注入 chrome / spacing）。
- 主题皮肤的 `WardrobeThemeClothingCardContainer.scrollOptimized` 在 grid6 档**禁** shadow + OrnateFrameSurface；G1 后通过 `WardrobeGridCellChrome.gridX` 强制。
- `.contextMenu` 必须显式提供 `preview:`，不允许让 SwiftUI 默认 snapshot 含主题阴影 / 边框的 cell。
- `.contextMenu` 内 closure 不允许捕获 `Clothing` SwiftData model（必须是 `WardrobeCellSnapshot` + `id`）。

### 5.3 切换 / 预取

- `viewLayout onChange` 必须 debounce ≥ 200ms 再 prefetch；中间档不预取。
- `initialImagePrefetchLimit` 必须按 `PerformanceTier` 分档（G0 起）。
- 主题切换瞬间必须同步压平所有 grid cell 视觉（G0-5 的 `wardrobeThemeDescriptor` 缓存 + `==` 校验保证）。

### 5.4 视觉一致性（grid）

- grid6 即使在 `.low` 档也必须保留：图片、`stock>1` 数字、心愿尾款标识（可降级为单色，但不能消失）。
- grid 主题角标在 `.low / .mid` 档只允许"**色彩降级**"（去阴影 / 单色 capsule），不允许"**语义降级**"。
- 引导锚点 `captureGuideTarget(.wardrobeSelectionCard)` 必须挂在第一张过滤后 cell 上，G0-6 重构后必须验证。

---

## 6. 验收清单（每阶段结束都跑）

### 6.1 静态自检

```bash
# 在 PROJ 目录
grep -n "@Environment(ThemeManager\|@Environment(\\\\.colorScheme)" \
       ItemManager/Views/ClothingCard.swift                                # G0 后应为 0
grep -n "Array(repeating: GridItem" ItemManager/Views/WardrobeView.swift   # 应为 0
grep -n "themeSkinManager.descriptor" ItemManager/Views/WardrobeView.swift | grep -v "onReceive\|// menu-perf" | wc -l   # 应为 0
grep -n "if viewLayout == .grid" ItemManager/Views/ClothingCard.swift      # G1 后应为 0
grep -n "scrollOptimized: true" ItemManager/Views/ClothingCard.swift       # G1 后应被 chrome 注入替代
grep -n "\\.contextMenu {" ItemManager/Views/WardrobeView.swift            # G1 后必须看到对应 preview:
```

### 6.2 设备 × 数据 × 布局 × 主题矩阵

每阶段跑全矩阵 108 组（3 设备 × 4 数据档 × 3 布局 × 3 主题），允许在 G0 阶段先跑 `(≤ 2GB 设备, 800 件, 全 3 布局, 默认 + 天空音乐会)` 共 6 组作为门控；G1/G2 全跑。

存档到 `temp/_perf/wardrobe_grid/<ts>/<phase>/<device>_<count>_<layout>_<theme>/`：

```
trace.trace
hitches.png
signposts.csv          # layout switch / theme switch / contextMenu open / selection toggle
notes.md               # 主观手感（必填："丝滑/能用/明显卡"，按 layout × theme 分段描述）
```

### 6.3 PASS / PARTIAL / FAIL 判定

| 判定 | 含义 |
|---|---|
| **PASS** | §2.2 全部门槛达成 + §6.1 全部通过 + §6.4 视觉回归无瑕 |
| **PARTIAL** | 指标全达标但 ≤ 5% 边界，或主观"能用但偶有顿挫"，或 §6.4 出现 1–2 帧主题混排 → 必须列出待办 |
| **FAIL** | 任一指标超门槛 ≥ 10%，或 §6.1 静态自检失败，或主题切换 ≥ 2 帧混排，或视觉降级丢字 → **不允许合入 main**，回到上一阶段 |

### 6.4 跨场景回归（grid）

- 切换 grid2 ↔ grid3 ↔ grid6 各 5 次：无白屏、无错位、无主题混排 ≥ 1 帧。
- 默认 ↔ 天空音乐会 ↔ 天鹅之梦 各 3 轮：每次切换后立即滚动 grid6 不允许出现"主题色 cell 与默认 cell 混排" `> 1` 帧（G-C6 修复后强制）。
- 进入选择模式全选 800 件 grid6 → 删除：主线程不阻塞 ≥ 1s（spinner 可见即可）；退出后 grid 不重新滚回顶部。
- 长按 grid2 / grid3 / grid6 cell：预览首帧 ≤ §2.2 表；菜单内"选择 / 详情 / 复制 / 删除"四项行为不能变。
- 引导首次出现：`captureGuideTarget(.wardrobeSelectionCard)` 锚点必须仍在第一张过滤后 cell（G0-6 重构后必测）。

---

## 7. 风险与回滚

| 风险 | 触发条件 | 回滚动作 |
|---|---|---|
| `WardrobeCellThemeInputs` 注入后 cell 主题色与全局不一致 | `ThemeManager` publish 但 `WardrobeView` 未及时收到 | 回滚 G0-3 / G0-4 / G0-5；改为 `@Environment(ThemeManager.self)` 但通过 `.equatable()` 包装；先合入其余 G0 |
| `safeAreaInset(edge: .top)` 与现有顶栏 / 搜索框冲突 | iOS 17/18/26 行为差异 | 回滚 G0-7，改用 `LazyVGrid Section { content } header: { statsSection }`；保持解耦但不上 `safeAreaInset` |
| `WardrobeGridCellChrome.gridX` 在主题皮肤启用时视觉太"塑料感" | 设计/产品反馈 | grid3 / grid2 档恢复 ornate frame surface 单层背景；grid6 保持简化 |
| `.contextMenu(preview:)` 自定义预览在 iOS 17 行为异常 | 仅 iOS 17 / 部分 iOS 18 build | `if #available(iOS 18, *)` 分档；iOS 17 仍走默认 snapshot（接受性能损失） |
| `prefetch debounce 200ms` 后用户感觉"切布局后图片来得慢" | 主观反馈 | debounce 降到 120ms；同时把 G0-9 的 grid6 limit 临时上调到 24 |

---

## 8. 不在本计划范围（明确排除）

- 列表（`listBrief / listDetailed`）滚动性能 — 由列表 P 计划主导。
- 详情页 (`ClothingDetailView`) / 编辑器 (`ClothingEditView`) 性能。
- 拼豆 / 空间手帐 / 小世界 / 衣橱主题资产替换。
- iCloud 同步策略、`safeGetProperty` 防御性代码 — 列表 P 计划 §4.2 主导。
- 顶栏 Menu / 批量编辑 Menu 卡顿 — 由 [`docs/iOS26_WARDROBE_MENU_PERFORMANCE_EXEC_PLAN.md`](./iOS26_WARDROBE_MENU_PERFORMANCE_EXEC_PLAN.md) 主导。
- `NavigationStack` 全局迁移 — 仅在 G2 内做 grid 局部探索。
- `seed_wardrobe_perf.swift` 基线工具 — 列表 P 计划 §2.1 主导，本计划只复用。

---

## 9. 文档维护

- 每完成一个 G 阶段，把 `temp/_perf/wardrobe_grid/<ts>/<phase>/` 目录路径回填到 §10。
- 任何"硬约束"被破坏时，必须在 PR 描述中显式申报豁免理由，并在本文档 §5 对应条目下加 `<!-- exception: ... -->` 注释。
- 与列表 P 计划 / Menu 计划共用 seed / 设备矩阵；改动 §0、§2、§3 时必须双向更新另两份文档对应章节。
- 当 `WardrobeView.swift` 文件长度逼近 500 行时（参照 `.trae/rules/my.md`），优先把 G1 引入的 `WardrobeGridCellChrome` 拆到 `Views/Wardrobe/`（当前为空目录），不允许塞回主文件。
- 当 `ClothingCard.swift` 接入 `WardrobeCellThemeInputs` 后逼近 500 行时，把 grid2/grid3 与 grid6 的 cell（`ClothingCard` / `ClothingThumbnail`）拆到独立文件。

---

## 10. 执行档案（落地后回填）

| 阶段 | 完成日期 | 基线档案 | 验收档案 | RESULT |
|---|---|---|---|---|
| G0 | _待填_ | `temp/_perf/wardrobe_grid/<ts>/baseline/` | `temp/_perf/wardrobe_grid/<ts>/g0/` | _待填_ |
| G1 | _待填_ | _待填_ | _待填_ | _待填_ |
| G2 | _待填_ | _待填_ | _待填_ | _待填_ |
