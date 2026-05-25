# iOS 26 衣橱原生菜单性能 · 执行计划与验收标准（harness）

> 状态：**2026-04-29 调研稿，未动代码**。仅文档，按本 harness 三阶段（M0/M1/M2）逐项落地。
> 范围：iOS 26（Liquid Glass 平台样式）下，从衣橱顶栏点击「⋯ 更多 / 排序 / 筛选 / 显示 / 添加」以及 cell 长按 `contextMenu` 出现的所有 SwiftUI `Menu` —— 即 `HomeView.swift` 顶栏 8 处 `Menu`、`WardrobeView.swift:686` 批量编辑 `Menu`、`WardrobeView.swift:1694` cell `contextMenu`、`WardrobeView.swift:2535` 多维筛选 Sheet 内的 Menu。
> 不动：SwiftData schema、`Clothing/Tag/Brand` 字段、CloudKit 同步链路、引导锚点 API、主题皮肤 slot 资产。
> 与已有计划的关系：本 harness 与 `docs/WARDROBE_LIST_SCROLL_PERFORMANCE_EXEC_PLAN.md` **互不重叠**——前者聚焦"列表滚动"，本文档聚焦"菜单首帧"。两者共用 `temp/_perf/wardrobe_*` 数据集、设备矩阵和压测 seed。

---

## 0. 启动协议（必读）

执行任何步骤前先把以下变量写入会话上下文：

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
TARGET_FILES=(
  "ItemManager/Views/HomeView.swift"                 # 顶栏 Menu 主战场
  "ItemManager/Views/WardrobeView.swift"             # 批量编辑 Menu / cell contextMenu / 多维筛选
  "ItemManager/Views/Settings/Refactored/WardrobeNavigationStyleSelectionView.swift"  # 风格切换 Picker
  "ItemManager/Views/Wardrobe/MultiDimensionalFilterSheet.swift"  # 若存在
  "ItemManager/Services/ClothingFilterService.swift"
  "ItemManager/Services/Guide/GuideManager.swift"    # 自定义引导菜单走的旁路
)
LOW_END_DEVICES=("iPhone SE (3rd gen)" "iPhone XR" "iPhone 11")  # 跑 iOS 26 的最低规格
MID_DEVICES=("iPhone 13" "iPhone 14")
HIGH_DEVICES=("iPhone 16 Pro")                                    # iOS 26 Liquid Glass 全开
DATA_TIERS=(50 200 800 2000)   # Clothing 件数；Tag/Brand 同时按 5/20/80 三档
OS_TIERS=("iOS 17.5" "iOS 18.4" "iOS 26.0")  # 26 是必跑，其余作为对照基线
```

### 0.1 不允许的"假优化"

- 把 SwiftUI `Menu` 强行换成自绘弹层（已有 `presentGuideMenu` 仅用于"引导态"，不允许把常态菜单也走旁路）。
- 用 `if #available(iOS 26)` 在 26 上隐藏菜单项以求"看起来不卡"——视觉/功能必须等价。
- 在 `Menu { ... }` 的 content 闭包里用 `Task { ... }` 异步填项 —— iOS 26 的 platter 在 closure 返回前不会渲染，会出现"白屏 → 跳出"的更严重观感。
- 对 `getAllValues / tags / brands` 做 `@MainActor` 同步缓存而不订阅 SwiftData 变更 —— 会导致新增标签/品牌后菜单不更新。
- 关闭 Liquid Glass 材质（`UIView.appearance` 全局降级）来"提帧" —— 整 App 主题视觉断裂。
- 用 `AnyView` 把 ForEach 包一层假装"减少 diff" —— `AnyView` 本身就是 SwiftUI Performance 反模式。

---

## 1. 必读上下文（顺序固定）

1. `ItemManager/Views/HomeView.swift:84-87` — `@Query allClothings / tags / brands`，三者共同驱动顶栏 Menu。
2. `ItemManager/Views/HomeView.swift:672-696` — `moreMenuButton` + 自定义引导菜单旁路条件。
3. `ItemManager/Views/HomeView.swift:698-712` — `sortButton`（Picker）。
4. `ItemManager/Views/HomeView.swift:715-874` — `filterButton` + `classicFilterMenu`（**最核心的卡顿源**：8 层 ForEach 子 Menu）。
5. `ItemManager/Views/HomeView.swift:876-1173` — `buildFilterSection(for:)` 6 个动态字段子 Menu。
6. `ItemManager/Views/HomeView.swift:1175-1181` — `getAllValues(for:)`（**body 路径上的 O(N) 全量扫描**）。
7. `ItemManager/Views/HomeView.swift:1183-1207` — `displayButton`（布局 Picker）。
8. `ItemManager/Views/HomeView.swift:1232-1264` — `wardrobeMoreMenuContent`。
9. `ItemManager/Views/HomeView.swift:1352-1386` — `wardrobeAddMenuContent`（含 `draftManager.hasDraft()` 调用）。
10. `ItemManager/Views/HomeView.swift:1448-1475` — `addButton` + 引导旁路。
11. `ItemManager/Views/WardrobeView.swift:686-740` — 批量编辑工具栏 `Menu`（多 `showing*Selection` State）。
12. `ItemManager/Views/WardrobeView.swift:1694-1730` — cell `.contextMenu` + `contextMenuItems(for:)`。
13. `ItemManager/Views/WardrobeView.swift:2532-2570` — 多维筛选 Sheet 内的"心愿尾款"Menu。
14. **官方文档**（必须在 PR 描述中引用条款编号）：
    - WWDC23 *Demystify SwiftUI performance*（`body` cost / dependency narrowing / `Equatable` view）。
    - WWDC25 *What's new in SwiftUI*（Menu / `menuActionDismissBehavior` / `menuOrder` / `Section` 在 Menu 内的稳定性）。
    - WWDC25 *Build for the Liquid Glass design system*（platter 渲染成本、`menuStyle` 与材质交互）。
    - Apple Human Interface Guidelines · iOS 26 · *Menus and Pop-ups*（建议菜单项 ≤ 5–7 项、子菜单嵌套 ≤ 2 层、超出请改用 Sheet/Picker）。
    - Apple Developer · *Improving the responsiveness of your app's main thread*（Menu open 主线程预算 ≤ 50ms）。

---

## 2. 性能基线测量（动手前必跑）

### 2.1 数据集前置

复用 `WARDROBE_LIST_SCROLL_PERFORMANCE_EXEC_PLAN.md` §2.1 的 `seed_wardrobe_perf.swift`；**新增** seed 出 80 个 Tag、80 个 Brand，并保证至少 60 件衣物的 `types/colors/sizes/length/condition/accessories` 各自包含 30+ 个**不重复** value 的 CSV，以触发 `getAllValues` 的 worst case。

> 硬约束：seed 数据必须真实写入 SwiftData，不允许用 mock 注入到 `@State`，否则跑出来的 Menu 不会经历 SwiftData → SwiftUI 订阅链路。

### 2.2 指标定义（核心是"按下到首帧"）

| 指标 | 测量方法 | M0 门槛（≤ 3GB iOS 26 + 800 件 + 80/80 Tag/Brand） | M2 目标（同上） |
|---|---|---|---|
| Menu 按下 → platter 首帧 | Instruments → Animation Hitches + 自埋 `signpost("menu_open")` | ≤ 250ms | ≤ 80ms |
| Menu 内容闭包总耗时 | 自埋 `signpost("menu_content_eval")` | ≤ 80ms | ≤ 20ms |
| `getAllValues` 单次耗时（worst case 字段） | 自埋 `signpost("getAllValues:<field>")` | ≤ 12ms | ≤ 2ms（命中缓存） |
| 顶栏区域帧率（点 Menu 前后 1s） | Animation Hitches | ≥ 55fps | ≥ 59fps |
| Menu 关闭 → 屏幕回到 60fps 用时 | signpost | ≤ 200ms | ≤ 80ms |
| 第 5 次反复点开同一 Menu 的耗时 | signpost | 与首次差 ≤ 30% | 与首次差 ≤ 10% |
| cell `contextMenu` 长按到 platter 首帧 | signpost | ≤ 350ms | ≤ 200ms |
| 进入衣橱后立刻点筛选 Menu 的耗时（冷态） | signpost | ≤ 400ms | ≤ 150ms |
| 触发 `os_signpost(.event, "main_thread_hang")` | Instruments → Hangs | 0 | 0 |

### 2.3 基线快照存档

```bash
mkdir -p "$PROJ/temp/_perf/wardrobe_menu/$(date +%Y%m%d-%H%M)/baseline"
# 每个 (设备, 数据档, OS) 跑一次：
#   - .trace（Instruments：Animation Hitches + Hangs + os_signpost）
#   - menu_open.signpost.csv（每次点 Menu 的耗时序列）
#   - hang.png（如果有 hang，截图 main thread stack）
#   - notes.md（手感：哪一类 Menu 最先卡，是否能感知"白屏"）
```

**M0 不允许跳过基线**。没有 `signpost` 数据就没有"是否变好"的判定依据；尤其是 iOS 17 / 18 / 26 三档对照，能直接证明这是 iOS 26 平台行为还是工程问题。

### 2.4 signpost 埋点清单（必须在 M0 之前补齐）

```swift
// ItemManager/Telemetry/MenuPerfSignpost.swift  (新建)
import OSLog
enum MenuPerfSignpost {
    static let log = Logger(subsystem: "app.pinkhouse.perf", category: "menu")
    static let signposter = OSSignposter(subsystem: "app.pinkhouse.perf", category: "menu")
    // open(name:) -> intervalState；close 时调用 signposter.endInterval
}
```

埋点点位（**必须在不改业务逻辑的前提下**插入）：
- `Menu` 的 `label` `.simultaneousGesture(TapGesture().onEnded { signpost("menu_open:filter") })`
- `Menu(content:)` closure 第一行 `let _ = signpostBegin("menu_content_eval:filter")`，return 前 `defer { signpostEnd(...) }`（用 `@ViewBuilder` 包不下，改成 `let _ = { ... }()` 计时）
- `getAllValues` 函数体内 `signposter.measureInterval(...)`
- `cell.contextMenu` 用 `.onAppear` 不准（contextMenu 不发送 onAppear），改用 `UIContextMenuInteraction` swizzle 或 hook `LongPressGesture(minimumDuration: 0.4)` 上的 `onChanged`。

---

## 3. 现状问题清单（对照官方反模式归类）

### 3.1 Menu 内容闭包过重（**主要矛盾**）

| 编号 | 位置 | 问题 | 对应官方反模式 |
|---|---|---|---|
| M-1 | `HomeView.swift:1175-1181` `getAllValues(for:)` | body / Menu content 路径上 `map → joined → split → Set → sorted` 全量遍历；6 个字段 × 每次 Menu 打开 = 6N 次扫描 | WWDC23 "Make body cheap" 反例 |
| M-2 | `HomeView.swift:758-873` `classicFilterMenu` | 8 层嵌套 `Menu`：标签 / 品牌 / 类型 / 颜色 / 尺码 / 衣长 / 状态 / 小物，每层 `ForEach` 输出 N 个 Button | HIG iOS 26 "≤ 2 级子菜单" 违反 |
| M-3 | `HomeView.swift:765, 814, 882, 930, 979, 1028, 1077, 1126` 等 | 每个子 Menu 内 `Button(role: .destructive)` + 多个 `if selected.contains(...)` 条件求值 | platter 预解析全部子项 → Buttons 数量级膨胀 |
| M-4 | `HomeView.swift:803-808, 855-860, 922-924, 971-973, 1020-1022, 1069-1071, 1118-1120, 1167-1169` | `label` 内做 `.first.flatMap { ... }` 临时计算 + `tags.first(where:)` / `brands.first(where:)` 线性查找 | WWDC23 "narrow dependencies" 反例（label 也会随 selected* 变化重算） |
| M-5 | `HomeView.swift:865-869` `ForEach(visibilityManager.fieldOrder)` | `visibilityManager` 若是 `@Observable`，**整个 fieldOrder** 变化都会重建 8 层 Menu 子树 | iOS 26 platter 不支持增量 diff content closure |
| M-6 | `HomeView.swift:1233-1264` `wardrobeMoreMenuContent` | 含 `if guideManager.shouldUseCustomGuideMenu(for:)` 双路径，常态走 Menu，引导态走 overlay；overlay 与 Menu 之间未充分解耦，开关瞬间 SwiftUI 重建上层 | 自有引导旁路加重首次评估 |
| M-7 | `HomeView.swift:1354` `if draftManager.hasDraft()` | 每次打开添加 Menu 都查询草稿单例，若草稿读盘未做 `@Observable` 缓存，会同步触发 `Codable` 解码 | Apple "main thread responsiveness" 警告 |

### 3.2 数据订阅过粗

| 编号 | 位置 | 问题 |
|---|---|---|
| D-1 | `HomeView.swift:84` `@Query private var allClothings: [Clothing]` | `getAllValues` 直接消费 `allClothings`；新增/编辑任意一件衣物都重算 6 次。**Menu 闭包内对 `allClothings` 的依赖应该是 `Tag/Brand/distinctValueCache`，而不是整张衣物表** |
| D-2 | `HomeView.swift:85-86` `@Query(sort: \Tag.name) tags / brands` | `tags / brands` 排序在 SwiftData 侧已做，但 `ForEach(tags)` 直接用 `Tag` 对象 + 取 `tag.id / tag.name`，未经过 `Equatable` 视图包装；标签批量重命名时 8 层 Menu 全部刷新 |
| D-3 | `WardrobeView.swift:686` 批量编辑 Menu | 该 Menu 的 content 引用了 `tempSelectedTags / tempSelectedBrand / tempSelectedColors / ...` 共 6+ 个 `@State`；任一变化都会让 Menu 闭包重建（即便菜单未打开） |

### 3.3 iOS 26 平台层（Liquid Glass）

| 编号 | 现象 | 官方依据 |
|---|---|---|
| L-1 | iOS 26 SwiftUI `Menu` 改走 `_UIPlatterContainerView`，content closure 必须**同步**返回；首帧前会做一次 GPU snapshot | WWDC25 *What's new in SwiftUI* / *Build for Liquid Glass* |
| L-2 | platter 背景 Liquid Glass 材质需要 `displayP3` 颜色与背景模糊 backing；Buttons 数量越多，第一次首帧延迟越大 | HIG iOS 26 "Materials and depth" |
| L-3 | iOS 26 `Menu` 不再支持 `> 2` 层子菜单的"无延迟展开"；第 3 层开始首次展开会有 ~150ms 平台动画延迟 | HIG iOS 26 "Menus and Pop-ups" |
| L-4 | `Picker(selection:)` 嵌在 `Menu` 内会被自动改写成 `inlinePickerStyle`，但每个 case 仍是独立 Button；`SortOption.allCases` / `ViewLayout.allCases` 较少时不影响，但与父 Menu 嵌套时仍走 platter 评估 | WWDC25 |
| L-5 | iOS 26 `contextMenu { ... }` 在长按 0.4s 触发 hold-and-snapshot；如果被长按 cell 内有 `.ultraThinMaterial`，snapshot 阶段会做两次模糊（cell + platter） | 关联 `WARDROBE_LIST_SCROLL_PERFORMANCE_EXEC_PLAN.md` C-4 |

### 3.4 引导旁路与状态污染

| 编号 | 位置 | 问题 |
|---|---|---|
| G-1 | `HomeView.swift:674, 1450` `shouldUseCustomGuideMenu` 两路分支 | 引导关闭瞬间 `Group` 重建上层按钮，可能触发 `captureGuideToolbarIconTarget` 锚点重新上报 → 引导系统再触发 MainActor 任务 → Menu 首帧延迟 |
| G-2 | `HomeView.swift:689-693` `simultaneousGesture(TapGesture().onEnded { notifyWardrobeMoreMenuOpened() })` | `TapGesture` 与 Menu 内置手势冲突；iOS 26 上**两次**触发：一次 simultaneous，一次 menu open delegate。NotificationCenter 也会发两遍 |

---

## 4. 优化方案（按落地成本三阶段）

### 4.1 M0 · 不动架构、必清的"显式黑洞"（1–2 天，必须全做）

目标：把 §2.2 全部指标拉到 **M0 门槛**；不引入新组件、不改 SwiftData schema、不改菜单功能。

| 任务 ID | 改动点 | 硬约束 |
|---|---|---|
| M0-1 | 把 `getAllValues(for:)` 提取到 `WardrobeMenuFacetCache`（轻量 `@Observable`），由 `clothings` 变化驱动后台重算；body 路径只读 `cache.types / colors / sizes / length / condition / accessories` | 重算函数 `nonisolated` + `Task.detached(priority: .utility)`；用 `Equatable` snapshot 对比，结果未变不写回 |
| M0-2 | `classicFilterMenu` 中标签 / 品牌的 `label` 不再做 `tags.first(where:)`，改用 `cache.tagNameByID[id]` `Dictionary` 查表 | `Dictionary` 由 `@Observable` 缓存维护，O(1) 查找 |
| M0-3 | 移除 `simultaneousGesture(TapGesture)` 触发 `notifyWardrobeMoreMenuOpened` 的重复调用；改成 `Menu` 的 `.onChange(of: ...isPresented)`（iOS 17+） 或 `MenuStyle` 中的状态回调 | 通知中心只发一次；引导系统监听端不变 |
| M0-4 | `wardrobeMoreMenuContent` / `wardrobeAddMenuContent` 拆成 `@ViewBuilder` 顶层私有方法（已是），但**禁止**直接读 `draftManager.hasDraft()` —— 改读 `@Observable draftPresence: Bool` | `ClothingEditDraftManager` 暴露 `@Published / @Observable` 状态；菜单闭包不触发 IO |
| M0-5 | `buildFilterSection(for:)` 6 路 `case` 共用一个泛型私有 View `FilterSubmenu(field:cache:selected:noMarker:)`，替换 6 段重复 ~50 行代码 | 该 View `Equatable` 实现按 `(field, selected, options.identifiers)` 三元组比较 |
| M0-6 | `Menu(content:)` 闭包内禁出现 `print / os_log / NSLog`；现有 `notify*MenuOpened` 必须用 `@MainActor` 调度，**不在** content closure 体内 | 静态自检：`grep "print(\|NSLog\|notifyWardrobe" -A1 HomeView.swift \| grep "Menu {"` 应空 |
| M0-7 | `WardrobeView.swift:686` 批量编辑 Menu 的 `tempSelected*` 6 个 `@State` 改为单一 `BatchEditDraft` struct + `@State` —— 减少 SwiftUI dependency 数量 | `BatchEditDraft` `Equatable`，按引用对比；菜单 content 只读不写 |
| M0-8 | `cell.contextMenu` 中 `contextMenuItems(for:)` 不引用 cell 周边的 `themeManager / themeSkinManager` —— 当前已传 `clothing`，确认 `Group` 不带主题依赖 | 静态检查：在 `contextMenuItems` 上方写 `// MARK: keep this closure dependency-free`，CR 时强制 |
| M0-9 | `displayButton` / `sortButton` 内的 `Picker` 保留，但移除外层 `HomeThemeSkinToolbarIconShell` 的 magicPalette 订阅 —— 改成传入 `let foreground: Color` | 主题切换时只刷新顶栏一次，而非 Menu 打开瞬间 |
| M0-10 | `MenuPerfSignpost`（§2.4）落地，所有顶栏 Menu 与 cell contextMenu 全部覆盖 | DEBUG 编译启用，RELEASE 用 `#if DEBUG` 包；不允许走生产埋点 |

**M0 验收门槛**：§2.2 表格 "M0 门槛" 列全部满足；并且：
- `grep -n "getAllValues" ItemManager/Views/HomeView.swift` 命中位置仅在 cache 内部；body / Menu 内 0 次
- `grep -n "AnyView" ItemManager/Views/HomeView.swift` ≤ 5
- `grep -n "tags.first(where" ItemManager/Views/HomeView.swift` = 0；`brands.first(where` 同
- iOS 26 Hangs Instrument trace：顶栏任意 Menu 打开期间无 `> 250ms` 红条
- 上述 signpost CSV 五次连续打开同一 Menu 的方差 ≤ 25%

### 4.2 M1 · 数据管线与 Menu 结构重设计（3–5 天）

目标：把指标拉到 M0 ↔ M2 中间档；引入"菜单 facet 缓存 + 多维筛选 Sheet 优先"。

- **`WardrobeMenuFacetCache`**：升级为正式 `@Observable` 单例（生命周期与 `HomeView` 相同），暴露：
  - `distinctValues(for: ClothingField) -> [String]`（带 `Set` 缓存）
  - `tagNameByID: [UUID: String]`、`brandNameByID: [UUID: String]`
  - `recentTagIDs / recentBrandIDs`（按用户使用频次缓存最近 10 项）
  - 重算 debounce 200ms；底层 `clothings.objectWillChange` 仅在 `field` 实际变更时触发（用属性级 hash）。
- **筛选入口"经典 Menu"上线 5 项硬上限**：超过 5 个标签 / 品牌 / 类型时，子 Menu 顶部强制插入 `Button("查看全部") → MultiDimensionalFilterSheet`；满足 HIG iOS 26 "≤ 5–7 项" 条款。
- **保留经典菜单为"快捷模式"**：UI 不变，但内部走 facet cache + recent N=5；用户切到 `multiDimensional` 仍可见全量。
- **`MultiDimensionalFilterSheet`** 内部不允许再嵌 `Menu`（§3.3 L-5 反模式）；用 `LazyVGrid` + `Toggle` 列表替代。
- **cell contextMenu 简化**：iOS 26 上 `contextMenuItems(for:)` 只保留 4 项核心动作（选择 / 详情 / 复制 / 删除）；二级动作（分享 / 收藏 / 移到深柜）改用详情页 toolbar。
- **Menu open 通知去重**：`notifyWardrobeMoreMenuOpened` 等 4 个 notification 改成单一 `WardrobeMenuOpenEvent { kind, openedAt }`，引导系统按 kind 分发；移除 `simultaneousGesture` 路径。
- **`@Query` 范围收窄**：`HomeView` 的 `@Query allClothings` **不**变（保持 cell 数据源）；但**新增** `@Query(predicate: #Predicate { ... }, sortBy: ...)` 仅返回 `id / types / colors / ...` 投影到 `ClothingFacetRow`，供 facet cache 消费。SwiftData 投影 fetch 比全量节省 ~60% 内存与排序时间。

**M1 验收门槛**：
- 顶栏任意 Menu 首帧 ≤ 150ms（iOS 26 + 800 件 + 80/80 Tag/Brand）
- `getAllValues` signpost 已不再出现（被 facet cache 替代）
- iOS 17 / 18 / 26 三档之间，Menu 首帧差异 ≤ 50ms（证明工程问题已修，剩余差异是平台行为）
- HIG 自检：所有进入路径下，单层 Menu 项数 ≤ 7、子菜单嵌套 ≤ 2 层（**例外**：`classicFilterMenu` 第一层为 8 个分类 → 改为 `Section` 分组，仍计 1 层，符合 WWDC25 *Section in Menu*）

### 4.3 M2 · 视觉 / 平台对齐与极限优化（按需，2–3 天）

目标：达成 §2.2 的 M2 目标值。仅在 M1 之后再考虑。

- **iOS 26 `MenuStyle` 自定义**：实现 `WardrobeMenuStyle: MenuStyle`，统一注入 `menuOrder(.fixed)` + `menuActionDismissBehavior(.automatic)` + 主题色 tint；可在低端档把 `menuOrder(.priority)` 关闭以省一次排序。
- **Liquid Glass 降级桥**：`PerformanceTier`（与列表滚动 harness 共用）`.low` 档下，对 ≤ iPhone XR 的 iOS 26 设备，把 `Menu` 的 background 用 `.regularMaterial` 替代 Liquid Glass platter 背景（**仅** Menu 内层，外层 platter 保留系统材质，避免视觉断裂）。
- **预热 facet cache**：进入衣橱 200ms 后（avoid 与首屏抢 CPU）启动 `Task.detached(priority: .background)` 预热 `WardrobeMenuFacetCache`；Menu 首次按下命中预热结果。
- **`presentGuideMenu` 与原生 Menu 等价化**：把自定义引导菜单的样式按 iOS 26 platter 视觉对齐，去除 G-1 中 Group 切换造成的重建。
- **Sheet 优先策略写入设置项**：用户偏好 `WardrobeFilterMode = .multiDimensional` 时，所有 Menu 入口（含分类 / 排序 / 显示）一律走 Sheet；让重度用户跳过 Menu 平台开销。
- **iOS 26 `searchable(in: .menu)`**：M2 探索 —— 当某子 Menu 项数 > 12 时，启用 iOS 26 新增的 menu search field（需确认 API 已 GM）。

---

## 5. 标准与硬约束（贯穿所有阶段）

### 5.1 SwiftUI / Menu

- `Menu(content:)` closure 内严禁：`print / debugPrint / os_log / NSLog`、`reduce / sorted / filter / Set` 全量聚合、`Tag.fetchAll / Brand.fetchAll` 等 IO、`UserDefaults` 读取、`UIImage(named:)` / SF Symbol 解码以外的图像加载。
- Menu content 闭包必须 O(1) 引用现成数据；任何 `O(N)` 聚合都属于"显式黑洞"。
- 子菜单嵌套深度 ≤ 2（HIG iOS 26）。第三层必须改用 Sheet。
- 单层 Menu 中 Button 数量 ≤ 12（含 Section 后仍受限）；超出走 Sheet。
- Menu 的 `label` 必须用 `Equatable` `struct` 包装（哪怕只是 `let icon: Image`），不允许直接放 `HStack { Image; Text }` 这种会随父 State 变化重建的 inline 组合。
- `Picker(selection:)` 在 Menu 内必须使用 `tag(_:)` 显式 tag，避免运行时反射推断。
- 所有 `Menu` / `contextMenu` 必须在 `// MARK:` 上写 `// menu-perf: <场景>`，便于 grep。

### 5.2 SwiftData

- `@Query` 不允许在 Menu / contextMenu 闭包内被读取；必须经由 `@Observable cache` 中转。
- facet cache 必须与 SwiftData 通过 `ModelContext.willSave / didSave` 通知保持一致，不允许手动 invalidate。
- 标签 / 品牌的"显示名"读取走 `cache.tagNameByID[id] ?? "未命名"` 兜底；Menu 闭包不查 SwiftData 上下文。

### 5.3 iOS 26 平台

- 不允许 `if #available(iOS 26)` 中藏 "在 26 上隐藏菜单项" 类型的功能阉割；只允许"视觉降级"（如 M2 的 `regularMaterial` 替代）。
- `Menu` 外层不允许嵌套 `.background(...)` 自绘材质 —— Liquid Glass platter 已带背景，叠加会造成 GPU 双倍负载。
- `contextMenu` 所在 cell 不允许同时使用 `.ultraThinMaterial`（与列表滚动 harness §5 对齐）。

### 5.4 引导系统

- 引导菜单旁路 (`shouldUseCustomGuideMenu`) 切换瞬间必须使用 `.transaction { $0.disablesAnimations = true }` 包裹，避免上层 `Group` 触发动画引发 SwiftUI 重建。
- `captureGuideToolbarIconTarget` 在 Menu open 期间不允许重新上报锚点（用 `.allowsHitTesting(false)` 或锚点 cache）。

### 5.5 通知中心

- `wardrobeMoreMenuOpened / wardrobeAddMenuOpened / wardrobeBatchImportOpened / wardrobeManualCreateOpened` 在单次用户交互内只允许发出一次；M0-3 改造后必须 grep 验证。

---

## 6. 验收清单（每阶段结束都跑）

### 6.1 静态自检

```bash
# 在 PROJ 目录
grep -n "getAllValues" ItemManager/Views/HomeView.swift                       # M0 后只在 cache 文件内出现
grep -nE "tags\.first\(where|brands\.first\(where" ItemManager/Views/HomeView.swift  # M0 后 = 0
grep -nE "print\(|debugPrint\(|NSLog\(" ItemManager/Views/HomeView.swift      # = 0
grep -n "simultaneousGesture(TapGesture" ItemManager/Views/HomeView.swift     # M0 后 = 0
grep -nE "Menu\s*\{" ItemManager/Views/HomeView.swift | wc -l                  # 与 baseline 对比，M1 后 ≤ baseline（不允许新增）
grep -n "ultraThinMaterial\|thinMaterial\|regularMaterial" ItemManager/Views/WardrobeView.swift \
  | grep -i "context"                                                          # contextMenu 上下文 = 0
grep -n "// menu-perf:" ItemManager/Views/HomeView.swift ItemManager/Views/WardrobeView.swift  # M0 后必须每个 Menu 都有
```

### 6.2 设备 × 数据 × OS 矩阵

每阶段结束跑 **3 OS × 3 设备 × 4 数据档 = 36 组**；存档 `temp/_perf/wardrobe_menu/<ts>/<phase>/<os>_<device>_<count>/`：

```
trace.trace                  # Hitches + Hangs + os_signpost
menu_open.csv                # 每次点 Menu 的 [t_press, t_first_frame, t_close]
hang_main_thread.png         # 若有 hang，截 main thread stack
notes.md                     # 主观手感（必填："丝滑/能用/明显卡"，并描述哪一类 Menu 最先卡）
```

### 6.3 PASS / PARTIAL / FAIL 判定

| 判定 | 含义 |
|---|---|
| **PASS** | §2.2 全部门槛达成 + §6.1 全部通过 + 主观"打开即出"；iOS 26 / 18 / 17 三档差异 ≤ 50ms |
| **PARTIAL** | 指标全达标但有一项 ≤ 5% 边界，或主观"绝大多数 Menu 流畅但筛选 Menu 偶有顿挫" → 必须在 RESULT.md 列出待办 |
| **FAIL** | 任一指标超门槛 ≥ 10%、或 §6.1 静态自检失败、或出现 main thread hang ≥ 250ms、或视觉/功能等价性破坏（菜单项消失 / 文字变化）→ **不允许合入 main**，必须回到上一阶段 |

### 6.4 跨场景回归

- iOS 26 + iPhone XR + 800 件：连续点开 6 处顶栏 Menu 各 5 次 + cell contextMenu × 5 次，无 hang、无白屏、内存增量 ≤ 12 MB。
- 主题皮肤切换（`天空音乐会` ↔ `天鹅之梦` ↔ 默认）后立即点 Menu，首帧不超出门槛 + 20%。
- 引导态 `shouldUseCustomGuideMenu == true` 时所有功能通路与常态等价（菜单项数、回调、引导锚点定位）。
- 多维筛选 Sheet 模式下，Menu 入口数应**减少**而不是增加；用户偏好切回 `classic` 必须无 SwiftData 重新订阅。
- iCloud 同步进行中（手动 `xcrun simctl push` 触发新衣物），打开筛选 Menu 不允许首帧 > 600ms。
- Tag/Brand 80 项 → 5 项 → 80 项 反复横跳，facet cache 不允许出现"陈旧值在 Menu 中显示" 超过 1s。

---

## 7. 风险与回滚

| 风险 | 触发条件 | 回滚动作 |
|---|---|---|
| `WardrobeMenuFacetCache` 与 SwiftData 不同步 | 新增 Tag 后菜单未刷新 | 把 cache 改为按 `objectWillChange` 全量重算（性能略损但保证一致），仅保留 M0-1 的 `Dictionary` 查表 |
| `BatchEditDraft` 重构破坏现有 Sheet 回写 | 选完颜色后回写 SwiftData 失败 | 回滚 M0-7，仍保留 6 个 `@State`，但增加 `Equatable` 包装层降低 dependency 数量 |
| iOS 26 `MenuStyle` 自定义后视觉与系统 platter 不一致 | 设计反馈 "胶囊圆角与系统不符" | 回滚 M2 `WardrobeMenuStyle`，仅保留 facet cache 与 Sheet 优先策略 |
| 通知去重后引导系统漏触发 | 新手引导 step 卡住 | 引导端订阅 `WardrobeMenuOpenEvent`，并在 M0-3 回滚前**先**让引导系统迁移完毕 |
| 投影 `@Query(ClothingFacetRow)` 在 iOS 17 上不可用 | iOS 17 SwiftData 不支持指定 partial fetch | M1 该项仅在 iOS 18+ 启用；iOS 17 保留 `allClothings` + cache |
| 预热 facet cache 抢 CPU 拉慢首屏 | 冷启动到衣橱首帧 > 1.5s | 预热延迟从 200ms → 800ms，或仅在用户开 App 已 ≥ 30s 时启用 |

---

## 8. 不在本计划范围（明确排除）

- 衣橱列表滚动性能 —— `docs/WARDROBE_LIST_SCROLL_PERFORMANCE_EXEC_PLAN.md` 主导。
- 详情页 / 编辑器 / 拼豆 / 空间手帐 / 小世界视图的菜单。
- iOS 26 整体导航栏 / 异形底栏 —— `docs/iOS26_导航栏统一与异形底栏方案.md` 主导，本计划仅保证不破坏其约定。
- iCloud 同步策略与 SwiftData schema 改造。
- 主题皮肤资产 —— `temp/_harness/EXEC_PLAN.md` 仅作历史 ThemeSkin harness / 迁移前参考；正式口径遵循 `docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md` 和后续 `docs/` / `tools/`。
- `presentGuideMenu` 引导菜单整体改造（仅做 M2 视觉对齐），完整重写另立项。

---

## 9. 文档维护

- 每完成一个 M 阶段，把 `temp/_perf/wardrobe_menu/<ts>/<phase>/` 路径回填到 §10。
- 任何"硬约束"被破坏必须在 PR 描述显式申报豁免，并在本文档 §5 对应条目下加 `<!-- exception: ... -->` 注释。
- 当 `HomeView.swift` 文件长度逼近 500 行时（参照 `.trae/rules/my.md`），优先把 M0-1 引入的 facet cache、M0-5 引入的 `FilterSubmenu` 拆出去，不允许塞回主文件。
- 与列表滚动 harness 共用的指标（设备矩阵、seed 工具）改动必须双向更新两份文档。
- 引用的 WWDC / HIG 条款若 GA 后官方更名，须同步更新 §1 第 14 项的清单。

---

## 10. 执行档案（落地后回填）

| 阶段 | 完成日期 | 基线档案 | 验收档案 | RESULT |
|---|---|---|---|---|
| 基线 | _待填_ | `temp/_perf/wardrobe_menu/<ts>/baseline/` | — | _待填_ |
| M0 | _待填_ | 同上 | `temp/_perf/wardrobe_menu/<ts>/m0/` | _待填_ |
| M1 | _待填_ | — | `temp/_perf/wardrobe_menu/<ts>/m1/` | _待填_ |
| M2 | _待填_ | — | `temp/_perf/wardrobe_menu/<ts>/m2/` | _待填_ |

---

## 附录 A · 官方反模式 ↔ 本文档问题编号交叉表

| 官方文档（条款） | 反模式描述 | 本文档涉及的问题编号 |
|---|---|---|
| WWDC23 *Demystify SwiftUI performance* · "Make body cheap" | body 路径上 O(N) 聚合 | M-1, M-4, D-1 |
| WWDC23 同上 · "Narrow dependencies" | 视图依赖整个集合而非派生快照 | M-5, D-1, D-2, D-3 |
| WWDC25 *What's new in SwiftUI* · `Section in Menu` | 菜单分组取代深嵌套 | M-2 (M1 改造) |
| WWDC25 *Build for Liquid Glass* · platter 渲染成本 | content closure 必须同步且轻量 | L-1, L-2, M-1 |
| HIG iOS 26 · *Menus and Pop-ups* "≤ 5–7 项 / ≤ 2 层" | 菜单项 / 嵌套深度上限 | M-2, M-3, L-3 |
| HIG iOS 26 · *Materials and depth* | 不要在材质上叠加材质 | L-2, L-5 |
| Apple Developer · *Improving main thread responsiveness* | Menu open 主线程预算 ≤ 50ms | M-1, M-7, §2.2 |
