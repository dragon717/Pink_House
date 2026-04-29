# 衣橱列表滚动性能 · 执行计划与验收标准

> 状态：**2026-04-29 已执行 P0 + P0.5 首轮落地**。后续每一阶段（P0/P1/P2）仍需对照本文档的"硬约束"和"验收门槛"逐条勾选。
> 已落地点：DEBUG 压测入口、cell 热路径清理、过滤/统计缓存、轻量 `WardrobeCellSnapshot`、list 模式 `ScrollView + LazyVStack`、衣橱主题 cell 滚动优化容器。
> 2026-04-29 追加：300 条真实数据仍卡时，继续移除滚动 cell 内 `ClothingDetailView` 导航图、常态 grid drop/preference 监听、非自定义排序选择态 drag/drop，并降低 cell 阴影/主题标题/主题角标成本；缩略图 NSCache aggressive 档上调。
> 范围：`ItemManager/Views/WardrobeView.swift`、`ItemManager/Views/ClothingCard.swift`、`ItemManager/ImageManager.swift`、以及衣橱主题 cell 容器 `ItemManager/Views/ThemeSkin/WardrobeThemeSkinComponents.swift`。
> 不动：SwiftData schema、`Clothing` / `StoredImage` / `BookGroup` 模型字段、iCloud 同步链路、主题皮肤资产清单、引导锚点 API（`captureGuideTarget`）。

---

## 0. 启动协议（必读）

执行任何步骤前，先把以下变量写入会话上下文：

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
TARGET_FILES=(
  "ItemManager/Views/WardrobeView.swift"
  "ItemManager/Views/ClothingCard.swift"
  "ItemManager/ImageManager.swift"
  "ItemManager/Views/ThemeSkin/WardrobeThemeSkinComponents.swift"
)
# 性能基线设备矩阵
LOW_END_DEVICES=("iPhone SE (2nd gen)" "iPhone 8" "iPhone XR")   # ≤ 2GB / ≤ 3GB
MID_DEVICES=("iPhone 12" "iPhone 13")                              # 4GB
HIGH_DEVICES=("iPhone 16 Pro")                                     # 8GB
# 数据集规模档（用脚本预填）
DATA_TIERS=(50 200 800 2000)
```

### 0.1 不允许的"假优化"

- 用 `if #available` 把 cell 视觉降级到难看的占位（用户感知必须保持"丝滑优雅"）。
- 在 cell 内 `Task.sleep` 拉长解码时间换"看起来不卡"。
- 把 `LazyVGrid` 退回 `VStack(ForEach)` —— 会让所有 cell 一次性 inflate，瞬间 OOM。
- 把 `@Query` 改成手写 fetch + `@StateObject` 数组 —— 会断 SwiftData → CloudKit 自动刷新。
- 用 `DispatchQueue.main.asyncAfter` 分帧 inflate —— 会让滚动出现"挤牙膏"感。
- 关掉 SwiftData iCloud 容器以"提速"。

---

## 1. 必读上下文（顺序固定）

1. `ItemManager/Views/WardrobeView.swift:1-668` — 主视图、`@Query`、`filteredClothings` 计算属性、`gridWardrobeView`、`listView`。
2. `ItemManager/Views/WardrobeView.swift:1205-1370` — `statsSection` 与 `WardrobeStatsView`（`reduce` 聚合在主线程）。
3. `ItemManager/Views/ClothingCard.swift:24-256` — `ClothingCard`（grid2/grid3 主 cell）。
4. `ItemManager/Views/ClothingCard.swift:259-306` — `ClothingThumbnail`（grid6 紧凑 cell）。
5. `ItemManager/Views/ClothingCard.swift:386-630` — `ClothingRow` / `ClothingRowBrief`（list 模式）。
6. `ItemManager/ImageManager.swift:23-95` — NSCache 配置、aggressive memory mode 阈值。
7. `ItemManager/ImageManager.swift:611-770` — `loadImageAsync` / `cachedImage` / `downsample` / `forceDecode`。
8. `ItemManager/Services/ClothingFilterService.swift` — 过滤管线（每次 body 重建 config）。
9. `docs/SWIFTUI_THEME_ADAPTATION_BEST_PRACTICES.md`、`docs/HAPTICS_BEST_PRACTICES.md` — 不在本任务范围内但需保持兼容。

---

## 2. 性能基线测量（动手前必跑）

### 2.1 数据集生成

衣橱当前没有压测数据生成工具。**P0 任务之一**：在 `ItemManager/Scripts/` 增加 `seed_wardrobe_perf.swift`（仅 DEBUG 编译），从命令行参数 `--count <N>` 写入 N 件 `Clothing`，每件挂 1 张 200×200 JPEG（来自 `temp/商品图/`）。
> 硬约束：seed 出来的图片必须复用 `ImageManager.saveImage`，走真实哈希去重链路，否则 NSCache 命中数据失真。

### 2.2 指标定义

| 指标 | 测量方法 | P0 门槛（≤ 2GB 设备 + 800 件） | P2 目标（同上） |
|---|---|---|---|
| 冷启动到衣橱首帧 | Instruments → Time Profiler，从 launch 到 `WardrobeView.body` 第一次返回 | ≤ 1.6s | ≤ 1.0s |
| 衣橱滚动平均帧率 | Instruments → Animation Hitches，匀速滑动 5s | ≥ 55 fps | ≥ 59 fps |
| 严重掉帧（hitch > 250ms） | 同上 | 0 次 | 0 次 |
| 滑动峰值内存 | Xcode Memory Gauge，连续翻 10 屏后 | ≤ 220 MB | ≤ 160 MB |
| 进入衣橱后 30s 稳态内存 | 同上 | ≤ 180 MB | ≤ 130 MB |
| 切换 grid2 ↔ grid6 二次回滚耗时 | 在 `viewLayout` `onChange` 打 `signpost` | ≤ 200 ms | ≤ 80 ms |
| 触发 `didReceiveMemoryWarning` 次数（10 分钟使用） | Console 日志 `Memory warning` | 0 | 0 |

### 2.3 基线快照存档

```bash
mkdir -p "$PROJ/temp/_perf/wardrobe_list/$(date +%Y%m%d-%H%M)/baseline"
# 每个 (设备, 数据档) 跑一次，存：
#   - .trace（Instruments）
#   - memory_gauge.png（Xcode 截图）
#   - console.log（含 signpost）
#   - notes.md（手感描述：哪一档开始觉得卡）
```

**P0 不允许跳过基线**。没有基线就没有"是否变好"的判定依据。

---

## 3. 现状问题清单（按管线分层）

### 3.1 数据 / 计算层

| 编号 | 位置 | 问题 | 影响 |
|---|---|---|---|
| D-1 | `WardrobeView.swift:173-217` | `filteredClothings` 是计算属性，每次 body 重算执行 search → filter → sort 三步全量 | 一次刷新可触发 5+ 次完整管线（被 `gridWardrobeView`、`statsSection`、`isAllSelectedInView`、`toggleSelectAll`、`disabled` 等多处读取） |
| D-2 | `WardrobeView.swift:103` | `_clothings = Query(filter: ..., sort: sortOption.sortDescriptors)` 全量加载所有未删除 `Clothing` 到主线程数组 | 2000 件以上初始化即可见卡顿 |
| D-3 | `WardrobeView.swift:1389-1403` | `WardrobeStatsView` 在 body 内 `reduce` 聚合 `count / totalCount / dressValue / totalValue` | 每次 stats 显示都遍历全量数组 |
| D-4 | `WardrobeView.swift:175` | `let searchService = ClothingSearchService(clothings: clothings)` 每次都新建实例 | 没有索引/缓存，纯线性扫描 |
| D-5 | `WardrobeView.swift:219-230` | `conditionBatchOptions` 在 body 路径上 flatMap+Set+sorted 全量数据 | 进入选择模式时主线程同步阻塞 |

### 3.2 视图层级

| 编号 | 位置 | 问题 | 影响 |
|---|---|---|---|
| V-1 | `WardrobeView.swift:232-238` | `body` 用 5 层 `AnyView` 嵌套包裹 modifier | 破坏 SwiftUI 类型化 diff，每次刷新整个子树 |
| V-2 | `WardrobeView.swift:622-668` | `gridWardrobeView` 内 `ScrollView { VStack { statsSection; LazyVGrid } }`，stats 跟 grid 同一可滚动容器 | `showStats` 切换或 stats 内部 state 变更触发整个 ScrollView 重新 layout |
| V-3 | `WardrobeView.swift:643-646` | `.onDrop` 直接挂在外层 `ScrollView` 上（非编辑模式也存在） | 持续监听 drop 事件 |
| V-4 | `WardrobeView.swift:687-696, 708-717, 758-767` | 编辑/选择模式下，每个 cell `onAppear`/`onDisappear` 修改 `Set<UUID> visibleItemIDs` | 800+ 列表滚动时高频 State 写入 |
| V-5 | `WardrobeView.swift:724-729, 1307-1310` | 每个 cell 都嵌一个 `NavigationLink(destination:)` | iOS 16+ 应迁 `navigationDestination(for:)` 减少 nav graph 节点 |

### 3.3 Cell 设计

| 编号 | 位置 | 问题 | 影响 |
|---|---|---|---|
| C-1 | `ClothingCard.swift:42-45` | `debugPalette` 计算属性内 `print()` —— 虽然当前未被 body 引用，但保留即风险 | 任何后续误调用 = 每帧打印 |
| C-2 | `ClothingCard.swift:24-32` | `Equatable` 只比较了 7 个属性，**未比较** themeSkin / palette / `showPrice` / `showOriginalPrice` / `isHovering` | 这些状态变化时 SwiftUI 仍会重建，但 == 又永远返回相同值 → 行为不确定 |
| C-3 | `ClothingCard.swift:36-39` | 每个 cell 同时订阅 `themeSkinManager` + `themeManager` + `colorScheme` + `containerPalette` + 2× `@AppStorage` | 主题/隐私设置变更 → 屏幕上**所有**可见 cell 同时刷新 |
| C-4 | `ClothingCard.swift:243, 517, 627` | `.containerAdaptiveColors(background: .ultraThinMaterial)` 在每个 cell 都用毛玻璃 | Material 离屏渲染 + 高斯模糊，是 ≤ 2GB 设备 GPU 黑洞 |
| C-5 | `ClothingCard.swift:245-252` | `.shadow + .scaleEffect + .animation(.spring) + .onHover` 全员挂载 | 触屏 iPhone 上 `onHover` 永不触发，但 spring animation modifier 拖累 diff |
| C-6 | `ClothingCard.swift:65-88, 319-342` | `Group { switch themeManager.skirtFillMode { ... } }` 在 cell 和占位图中重复 4 分支 | 每个 cell 都做 4 路条件展开 |
| C-7 | `ClothingCard.swift:106-170` | 3D / 心愿尾款 / 库存 角标各自 `if isThemeSkinThemed { ... } else { ... }` | 每个角标都重新求值主题判断 |

### 3.4 图片管线

| 编号 | 位置 | 问题 | 影响 |
|---|---|---|---|
| I-1 | `ClothingCard.swift:185-187, 297, 422, 573` | 每个 cell 在 `.task` 里 `await Task.sleep(nanoseconds: 50_000_000)` | LazyVGrid 已经按需 inflate，这 50ms 是纯净延迟 |
| I-2 | `ImageManager.swift:642-645` | `cachedImage(fileName, targetSize)` 用 `fileName_WxH` 做 NSCache key | grid6/grid3/grid2/list/listBrief 五种尺寸 = 同一图最多 5 份缓存 |
| I-3 | `ImageManager.swift:752-765` | ≤ 2GB 设备**禁用** `forceDecode`，懒解码留给 UIKit | 第一次显示时主线程突发解码 = 滚动掉帧 |
| I-4 | `ImageManager.swift:651-697` | `loadImageAsync` 把所有解码丢 `Task.detached(priority: .userInitiated)` | 大量 cell 同时滚入时全部抢同一队列，无优先级区分 |
| I-5 | `ImageManager.swift:60-89` | aggressive 模式下 ≤ 2GB 设备 `countLimit = 20`、`limitInMB = 20` | 滚动到第 5 屏时缓存命中率 0%，反复触底解码 |
| I-6 | `ClothingCard.swift:559-575` | `safeGetProperty` 包了一堆 `do/catch`，每个 cell 加载图片都过 4-6 次 try/catch | iCloud 同步期防御性代码，但常态路径也吃成本 |

---

## 4. 优化方案（按落地成本三阶段）

### 4.1 P0 · 不动架构、必清的"显式黑洞"（1–2 天，必须全做）

目标：把基线指标拉到 §2.2 的 **P0 门槛**，且不引入新组件、不改 SwiftData schema。

| 任务 ID | 改动点 | 硬约束 |
|---|---|---|
| P0-1 | 删除 `ClothingCard.swift:42-45` `debugPalette` + `print` | 整文件 grep `print(` 后只允许在 catch 分支保留 |
| P0-2 | 移除每个 cell `.task` 里的 `Task.sleep(50ms)`（C/T/Row/RowBrief 共 4 处） | 用 `LazyVGrid` 默认按需 inflate；不允许换 `DispatchQueue.main.asyncAfter` |
| P0-3 | `ClothingCard` / `ClothingRow` / `ClothingRowBrief` 去 `.containerAdaptiveColors(background: .ultraThinMaterial)`，cell 背景改用主题色实色或 `Color.clear` | 详情页、stats 卡可继续用 material；列表 cell 必须实色 |
| P0-4 | `ClothingCard.swift:245-252` 移除 `.scaleEffect + .animation(.spring) + .onHover`；shadow 改成静态值 | iPad 悬停高亮如有需求，按 `horizontalSizeClass == .regular` 走另一分支 |
| P0-5 | `WardrobeView.swift:232-238` 拆掉 5 层 `AnyView`，改成线性 modifier 链或 `@ViewBuilder` 私有方法 | 类型推断爆炸时按"功能拆 ≤ 200 行子 View"，不能为了短再加 AnyView |
| P0-6 | `filteredClothings` 改为 `@State private var filteredClothings: [Clothing]` + 在 `onChange` (clothings/searchText/9 个 filter/sortOption) 内重算 | 重算函数必须 `nonisolated` 并跳到 `Task.detached(priority: .userInitiated)`，结果用 `await MainActor.run` 写回 |
| P0-7 | `ImageManager.swift:752-765` 在 ≤ 2GB 设备允许 `forceDecode`，但只对 `targetSize.width * height ≤ 200×200` 的小图开启 | 大图（chart / 详情）保持懒解码 |
| P0-8 | `WardrobeStatsView` 的 `styleCount/totalCount/dressValue/totalValue` 改为对 `clothings` 数组做一次 `reduce` 后缓存到 `@State`，依赖 `clothings.identifiers` 变化触发 | 不允许加全局 cache 单例 |
| P0-9 | 编辑/选择模式 `visibleItemIDs` 收集改用 `PreferenceKey`，去掉每个 cell 的 `onAppear/onDisappear` `Set` 写入 | 仅在编辑模式 ≥ 2s 后才更新，避免滑动中段抖动 |
| P0-10 | `ClothingFilterMenu` / `ClothingSearchService` 实例化下沉到 `@StateObject` 或顶层 ViewModel；`ClothingFilterService.FilterConfig` 用 `Hashable struct` 做 key 避免重建 | service 不持有强引用衣物数组 |

**P0 验收门槛**：§2.2 表格内"P0 门槛"列全部满足；并且：
- 所有改动后 `grep -n "AnyView" WardrobeView.swift` 计数 ≤ baseline 的 30%
- `grep -n "Task.sleep" ClothingCard.swift ItemManager/Views/Wardrobe*` = 0
- Animation Hitches 截图无 > 100ms 红点

### 4.2 P1 · 数据管线与缓存重设计（3–5 天）

目标：把指标拉到 P0 ↔ P2 中间档；引入"缓存键归一化 + ViewModel + 分页"。

- **WardrobeListVM**：新增 `@Observable` 类（iOS 17+），托管 `clothings`、`filteredClothings`、`stats`、`filterConfig`、`sortOption`。`WardrobeView` 只读。
  - 输入：`@Query` 拿到的 `[Clothing]`（保留 SwiftData → CloudKit 链路）。
  - 输出：`PublishedSnapshot { items: [Clothing.ID]; stats: WardrobeStats }`。
  - 重算策略：debounce 80ms、跳到后台队列；中途用户再改 filter，旧任务取消。
- **NSCache key 归一化**：`ImageManager.cacheKey(fileName:bucket:)`，`bucket` 只允许枚举 `.thumbnail80 / .card200 / .row60 / .full`。grid2 与 grid3 共用 `.card200`。同一图最多 4 份缓存（含 full）。
- **预取**：在 `LazyVGrid` 当前可见 index 之外预取 N=8 张（用 `Task` group + `priority: .background`）。预取命中后写入 NSCache，不产生 UIImage 引用。
- **NSCache 容量重新分档**：
  - ≤ 2GB：`countLimit = 60`（可视屏 ≈ 30 cell × 2 屏），`totalCostLimit = 40 MB`。
  - 4GB：`80 / 80 MB`。
  - ≥ 6GB：`160 / 200 MB`。
  - 进入后台仍按 `useAggressiveMemoryOptimization` 决定是否清空，但**新增**：进入「列表非可见状态超过 30s」时主动 `evict 50%`。
- **`@Query` 分页**：当 `clothings.count > 1000` 时切到 `FetchDescriptor` + `fetchLimit = 300` + 滚动到底再追加；保留 SwiftData 监听，仅控制初始一帧只展开一窗口。
- **`safeGetProperty`** (`ClothingCard.swift:559-575`) 仅在 `iCloudSyncManager.isSyncing == true` 时启用 try/catch；常态路径直接读属性。

**P1 验收门槛**：
- 同一图在 grid 切换后 NSCache 命中率 ≥ 85%（在 ImageManager 增加 `signpost` 输出 hit / miss 比）。
- 进入衣橱后 30s 内存 ≤ 150 MB（≤ 2GB 设备 + 800 件）。
- 滑动 5s 平均 fps ≥ 58。

### 4.3 P2 · 视觉降级与高级优化（按需，2–3 天）

目标：达成 §2.2 的 P2 目标值。仅在 P1 之后再考虑。

- **低端设备视觉自适应**：`PerformanceTier`（`.low / .mid / .high`，按 `physicalMemory` + `processorCount` 计算）注入到 `Environment`。
  - `.low`：`ClothingCard` 阴影完全去除；圆角 8 → 6（少一层离屏）；3D / 尾款角标改为单色 capsule。
  - `.mid`：保留阴影但 radius 降到 2；spring 动画统一改 `.linear(duration: 0.2)`。
  - `.high`：保持现状视觉。
  - **硬约束**：`.low` 与 `.mid` 不允许丢失语义信息（角标文字、价格、库存数字）。
- **图片解码统一管线**：`ImageDecodeQueue`（actor）按 `priority` 排队，可视区 cell `.userInitiated`、预取 `.background`、详情 `.high`。
- **`statsSection` 与 `LazyVGrid` 解耦**：stats 改用 `safeAreaInset(edge: .top)` 或单独 `Section`，`showStats` toggle 不重新 layout grid。
- **NavigationLink 收口**：迁移到 `.navigationDestination(for: Clothing.ID)`，cell 仅 `Button` + `path.append`。
- **滚动到顶/底 haptic**：保持现有 `HapticsManager` 不变，按 `SWIFTUI_GESTURE_ANIMATION_BEST_PRACTICES.md` 节流。

---

## 5. 标准与硬约束（贯穿所有阶段）

### 5.1 SwiftUI

- 列表 cell 必须 `struct` + `Equatable`，且 `==` 必须覆盖**所有**会触发视觉差异的属性（如 P0-3 之后还引入新主题状态，必须补齐）。
- 列表 cell 严禁 `@StateObject`、`@ObservedObject`、`@Environment(\.colorScheme)` 直接订阅；颜色/主题通过父 view 传 `let` 进来。
- 列表 cell 严禁用 `.ultraThinMaterial`、`.regularMaterial`、`.thinMaterial`。
- `body` 内严禁 `print` / `debugPrint` / `os_log`（DEBUG 也不行；要打日志放 `task` / `onAppear` 内的事件回调里）。
- `body` 内严禁出现 5 层以上 `AnyView`（线性 modifier 链可，多分支 view 用 `@ViewBuilder`）。
- 计算属性返回数组且依赖外部数据源时，**必须**有缓存层（`@State`、ViewModel 或 `Equatable` 输入快照），不允许在 body 路径上做 O(N) 以上聚合。

### 5.2 SwiftData

- `@Query` 不允许在 body 路径上 `.filter / .sorted / .reduce` 全量数组（用 SwiftData 的 `predicate` / `sortDescriptors` 或下沉到 ViewModel + 后台队列）。
- 不允许在 cell 内访问 `@Query` 结果。
- 软删除 (`deletedAt != nil`) 必须走 SwiftData predicate 而不是数组 filter。

### 5.3 图片管线

- 任何 cell `.task` 不允许 `Task.sleep`。
- NSCache key 必须使用归一化 bucket（见 §4.2），不允许出现 `fileName + 任意尺寸` 的 key 自由组合。
- 解码必须在 `Task.detached(priority:)` 后台执行，priority 由调用方根据"可视/预取/详情"决定。
- `forceDecode` 决策必须依据"目标尺寸"而非"设备内存"。
- `loadImageAsync` 必须支持取消（`Task.isCancelled` 检查放在解码前后各一次）。

### 5.4 内存

- ≤ 2GB 设备峰值不超过 240 MB；超过即触发 `clearCache()` 而不是等系统警告。
- 进入衣橱后 30s 稳态内存上限按 §2.2 表执行。
- NSCache `totalCostLimit` 必须显式设置；`countLimit` 不允许为默认 0。

### 5.5 视觉一致性

- P2 视觉降级必须在 `ThemeSkinManager` 当前 slot 启用时**保留主题色彩 token**（哪怕去阴影、去毛玻璃）。
- 主题皮肤角标（3D / 尾款 / 库存）在 `.low` 档允许降级为单色，但**不能**移除文字。
- 引导锚点 `captureGuideTarget(.wardrobeSelectionCard)` 必须保留，不能因重构丢失。

---

## 6. 验收清单（每阶段结束都跑）

### 6.1 静态自检

```bash
# 在 PROJ 目录
grep -n "AnyView" ItemManager/Views/WardrobeView.swift | wc -l            # P0 后应 ≤ 5
grep -rn "Task.sleep" ItemManager/Views/ClothingCard.swift                 # 应为 0
grep -rn "ultraThinMaterial\|thinMaterial\|regularMaterial" \
       ItemManager/Views/ClothingCard.swift                                # 应为 0
grep -n "print(" ItemManager/Views/ClothingCard.swift                      # 应为 0（catch 分支例外）
grep -n "@ObservedObject\|@StateObject" ItemManager/Views/ClothingCard.swift  # 应为 0
```

### 6.2 设备矩阵 × 数据档

每个阶段结束时跑全矩阵 12 组（3 设备 × 4 数据档），存档到 `temp/_perf/wardrobe_list/<ts>/<phase>/<device>_<count>/`：

```
trace.trace                   # Instruments Time Profiler + Allocations
hitches.png                   # Animation Hitches 截图
memory_30s.png                # 进入衣橱 30s 内存截图
memory_peak.png               # 滚 10 屏后峰值截图
fps_log.csv                   # signpost 输出（cell appear / decode start/end）
notes.md                      # 主观手感（必填："丝滑/能用/明显卡"，必须有具体段落描述）
```

### 6.3 PASS / PARTIAL / FAIL 判定

| 判定 | 含义 |
|---|---|
| **PASS** | §2.2 全部门槛达成 + §6.1 全部通过 + 主观"丝滑" |
| **PARTIAL** | 指标全达标但有一项 ≤ 5% 边界，或主观"能用但偶有顿挫" → 必须在 RESULT.md 列出待办 |
| **FAIL** | 任一指标超门槛 ≥ 10%，或 §6.1 静态自检失败，或出现 `didReceiveMemoryWarning`，或视觉降级丢字 → **不允许合入 main**，必须回到上一阶段 |

### 6.4 跨场景回归

- 切换 grid2 ↔ grid3 ↔ grid6 ↔ listBrief ↔ listDetailed 各 5 次，无白屏、无错位、无内存阶梯式增长。
- 进入选择模式全选 1000 件 → 删除，主线程不阻塞超过 1s（spinner 可见即可）。
- 后台切前台 5 分钟内，再次进入衣橱首帧 ≤ 0.5s。
- iCloud 同步进行中（手动 `xcrun simctl push` 触发新衣物）滚动列表，不允许崩溃；P1 之后 `safeGetProperty` 路径只在同步窗口生效。
- 主题皮肤切换（`天空音乐会` ↔ `天鹅之梦` ↔ 默认）后立即滚列表，不允许出现"主题色 cell 与默认 cell 混排" `> 1` 帧。

---

## 7. 风险与回滚

| 风险 | 触发条件 | 回滚动作 |
|---|---|---|
| `@State filteredClothings` 与 `@Query clothings` 不同步 | SwiftData 推送新数据但 `onChange` 未触发 | 回滚 P0-6，临时改回计算属性，先合入其余 P0 |
| 去 material 后视觉与产品定位冲突 | 设计/产品同学反馈"塑料感" | 在 cell 容器（**非每 cell**）外层套一次 material；保持 cell 内实色 |
| 后台 Task 解码竞争导致首屏更慢 | P1 引入预取后冷启动反而 > 2s | 关闭预取、保留缓存归一化；预取改为"滚动停下后 200ms 触发" |
| 低端档去阴影后用户感觉"廉价" | 主观反馈 | 阴影改 1px hairline border 替代 |
| `PreferenceKey` 收集 visibleIDs 在编辑模式不准 | 拖动时 ID 错位 | 仅"长按进入编辑模式"那一刻快照一次，拖动期间不更新 |

---

## 8. 不在本计划范围（明确排除）

- 衣橱详情页 (`ClothingDetailView`) 性能 — 单独立项。
- 编辑器 (`ClothingEditView`) 性能。
- 拼豆 / 空间手帐 / 小世界视图。
- iCloud 同步策略改造 — 由 `iCloud_SYNC_GUIDE.md` 主导。
- 主题皮肤资产替换 — 由 `temp/_harness/EXEC_PLAN.md` 主导，本计划只保证不打破其约定。
- `NavigationStack` 全面迁移 — 仅在 P2 内做衣橱局部迁移。

---

## 9. 文档维护

- 每完成一个 P 阶段，把 `temp/_perf/wardrobe_list/<ts>/<phase>/` 目录路径回填到本文档 §10。
- 任何"硬约束"被破坏时，必须在 PR 描述中显式申报豁免理由，并在本文档 §5 对应条目下加 `<!-- exception: ... -->` 注释。
- 当 `WardrobeView.swift` 文件长度逼近 500 行时（参照 `.trae/rules/my.md`），优先把 P1 引入的 ViewModel / Section 拆出去，不允许塞回主文件。

---

## 10. 执行档案（落地后回填）

| 阶段 | 完成日期 | 基线档案 | 验收档案 | RESULT |
|---|---|---|---|---|
| P0 | _待填_ | `temp/_perf/wardrobe_list/<ts>/baseline/` | `temp/_perf/wardrobe_list/<ts>/p0/` | _待填_ |
| P1 | _待填_ | _待填_ | _待填_ | _待填_ |
| P2 | _待填_ | _待填_ | _待填_ | _待填_ |
