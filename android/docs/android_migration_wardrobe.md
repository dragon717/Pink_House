# 少女衣橱 · Android 迁移说明（衣橱页）

> 本文记录 `feature/wardrobe/**` 从 iOS SwiftUI 版本（`Pink_House/Pink_House/Views/Wardrobe/WardrobeView.swift` 等）迁移到 Android Jetpack Compose 的进度与差异。业务以 SwiftUI 为准；规范参考 Android 官方文档 / Material 3 / Compose Guidelines。与鸿蒙侧 `harmony_next/docs/harmony_migration_wardrobe.md` 对标，差异集中在无 GMS / Scoped Storage / Room schema 几类。

> **当前状态**：M2 衣橱闭环已落。`WardrobeRoute.kt` 已替换为 `衣橱 / 心愿尾款` 双页 Compose 复刻；`WardrobeHomeViewModel` 负责 Room + DataStore + 单向 UI 状态；Room `wardrobe_item` 已升级到 v2 并保留 v1→v2 Migration；手动创建、图片导入、搜索、筛选、排序、布局切换、编辑选择态、批量软删除均已接入。当前优先级已切到衣橱核心查询与统计：搜索/筛选结果会驱动统计卡联动显示当前命中数据。

## 一、TopBar 顶栏

### 目标

| 功能 | iOS 原型 | Android 实现要点 |
| --- | --- | --- |
| 5 常驻圆按：排序 / 筛选 / 视图 / 更多 / 添加 | `WardrobeView.toolbar { .. }` 五按钮 | 已迁移：圆角操作组 + Material Icons |
| 排序 Sheet | `SortOptionsSheet` | 已迁移为 `DropdownMenu`，覆盖 iOS 排序项 |
| 筛选 Sheet | `FilterView` 多选 Chip | 已迁移为 `ModalBottomSheet`，支持品牌/类型/颜色/尺码/状态/小物/心愿尾款 |
| 视图切换 Sheet | 视图 ActionSheet | 已迁移为 `DropdownMenu`，支持双列/三列/六列/简略列表/详细列表 |
| 更多菜单：搜索 / 编辑 / 调整顺序 | 原 iOS 散落在工具栏+编辑模式切换 | 已迁移搜索和编辑；调整顺序入口暂不做拖拽 |
| 添加菜单：手动创建 / 批量导入 | `AddSheet` ActionSheet | 已迁移；批量导入当前复用手动创建入口占位 |
| 编辑模式顶栏 | `isSelectionMode` 时切换 `完成 / 已选 n / 全选` | 已迁移：完成、已选 n/N、全选/取消全选 |

### 差异预期

- iOS `toolbar` 与系统导航返回绑定，Android 用 `BackHandler` 手动处理编辑模式退出。
- iOS 分段 ActionSheet 在 Material 3 没有对应控件，统一改为 `DropdownMenu` + `ModalBottomSheet` 两种组合。

## 二、ItemCard 网格卡片

### 目标

- 卡片主视觉：已实现本地私有目录图片异步缩略图解码；缺图时回退粉色渐变占位，避免在 Compose 主线程解码大图。
- 编辑模式（`isSelectionMode`）右上角勾选圈：未选中=白色空圈，选中=粉色填充+白色 `Icons.Default.Check`，配合卡片 `border` 加粗变粉。
- 点击路由：编辑模式下点击切换勾选；非编辑模式进 `WardrobeItemDetailRoute`。
- 非编辑模式保留右上角"心愿尾款"小角标。
- 自定义排序下长按拖拽：优先用官方 `Modifier.draggable` + `rememberReorderableLazyListState`（或 `burnoutcrown/reorderable` 第三方），落地 `sort_index` 到 Room。

### 差异预期

- iOS `onDrag/onDrop` 的 `ItemProvider` 是系统级跨页面的；Android 拖拽目前只在 `LazyVerticalGrid` 内部生效，跨页拖动需要自实现浮层。
- iOS 里"编辑"与"调整顺序"同一模式（`EditMode`）；Android 拆两个入口，`编辑` 保持当前排序，`调整顺序` 强制切 `Custom`。
- 列表布局（`LazyColumn`）和 Grid 拖拽排序本轮均暂不实现；保留 `sortIndex` 和自定义排序枚举，为下一轮接入拖拽留接口。

## 三、手动创建 Sheet

### 目标

- 已按 iOS Simulator 表单顺序迁移：图片、名称、品牌、类型、颜色、尺码、衣长、状态、小物、价格、库存、购买信息、心愿尾款、备注。
- 主图：`ActivityResultContracts.PickVisualMedia` 单选，复制到 App 私有目录 `files/wardrobe_images`，表单内预览。
- 保存：写 Room `wardrobe_item` 表，`sortIndex` 默认 `System.currentTimeMillis()`，列表自动刷新。
- 取消：dismiss Sheet，不写入数据。

### 差异 / 降级

| iOS 字段 | Android 状态 | 原因 |
| --- | --- | --- |
| 品牌 brand / 品牌系列 | 品牌已暴露，系列暂不暴露 | 系列表后补 |
| 标签 tag | **先不暴露** | 关系表后补 |
| 定金/尾款/付款日 | 已暴露基础字段 | 系列/通知明细后补 |
| 多图拍摄 + 预览 | **不支持** | 批量导入承担多图诉求 |

## 四、批量导入 Sheet

### 目标

- 系列名输入（可选，不填默认"导入"）
- `PickMultipleVisualMedia` 最多 20 张
- 3 列 `LazyVerticalGrid` 预览，单图右上角 `×` 删除
- 确认导入：`viewModelScope` 串行写入 Room，每条文案 `${seriesName} ${i+1}`；失败单条 `Timber.e`，成功计数返回

### 差异 / 降级

- 不走 AI 识图（PRD W-03/W-04/W-05），统一分类为"连衣裙"，用户详情页调整。
- 系列元数据暂不写 `brand_series` 表（该表二期再建），只在 `name` 前缀拼接。

## 五、编辑模式

### 目标

- 入口：`更多 → 编辑`、`更多 → 调整顺序`（后者强制 `Custom` 排序）
- 顶栏：`完成 / 已选 n/N / 全选 ⇄ 取消全选`
- 卡片：勾选圈 + 选中描边
- 底部批量操作栏：已实现 `批量删除`，`AlertDialog` 二次确认，命中 `BatchSoftDeleteWardrobeItems`
- 自定义排序下 Grid 拖拽暂不实现，只保留数据字段和排序项。

### 差异 / 降级

- iOS 还支持批量加入心愿单 / 批量导出到穿搭；Android 底栏先只做"批量删除"，二期按反馈迭代。
- 不实现"从社区导入"（PRD 未列）。

## 六、数据链路

### 目标

- `WardrobeItemEntity` + Room schema v2 `wardrobe_item`：已补齐衣橱闭环字段。
- `sortIndex`（Long）：已补到 schema，升级走 `Migration(1, 2)`。
- DAO 新增：`softDeleteItems(ids: List<Long>)`；查询覆盖名称/品牌/类型/颜色/尺码/状态/小物。
- Repository：`RoomWardrobeRepository` 已代理批量软删除。
- UseCase：已新增 `BatchSoftDeleteWardrobeItems`；拖拽排序 UseCase 暂缓。
- Preferences：`UserPreferencesDataStore` 已保存上次子页、排序、布局、心愿尾款显示模式。

### 差异 / 降级

- 鸿蒙 MVP 用 DROP 重建丢数据；**Android 不准这么做**——必须写 `Migration`，老用户必须平滑升级。
- 标签关系表 DAO 可提前建，UI 先不暴露。

## 七、WARDROBE-DATA 推进记录（查询 / 统计优先）

### BATCH-WARDROBE-DATA-01 查询/筛选结果联动统计

**改动范围**

- `WardrobeHomeViewModel.kt`
  - `WardrobeHomeUiState` 新增 `visibleStatistics`，由当前搜索/筛选后的 `visibleItems` 计算。
  - 新增 `hasActiveQuery`，统一判断搜索词或筛选项是否处于激活状态。
- `WardrobeRoute.kt`
  - 统计卡从固定全量数据改为根据 `hasActiveQuery` 自动切换：无查询时显示「衣橱总览」，有查询/筛选时显示「当前结果统计」。
  - 增加命中说明：`命中 x/y 款 · 筛选 n 项`。
  - 搜索词不为空时在统计卡右侧显示当前关键词 Chip，帮助用户确认统计口径。
  - 搜索框占位补充 `备注或 100-300`，显性提示价格区间查询能力。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：新增 diff 无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中。
- Android Emulator 装机验证：进入衣橱搜索 `100-200`，UI 出现 `当前结果统计`、`命中`、`100-200`、`2/2`、`¥297.00`。
- 截图记录：`/tmp/pinkhouse_wardrobe_data_01_query_stats.png`。

**后续待办**

- `BATCH-WARDROBE-DATA-02`：把已支持但较隐藏的高级查询能力做成帮助说明与快捷 Chip。
- `BATCH-WARDROBE-DATA-03`：新增统计明细页 / Sheet，按品牌、类型、颜色、状态、心愿尾款等维度拆解。
- `BATCH-WARDROBE-DATA-04`：沉淀最近搜索与常用筛选组合。

### BATCH-WARDROBE-DATA-02 高级查询语法提示 + 快捷筛选 Chip

**改动范围**

- `WardrobeBusinessLogic.kt`
  - 搜索能力从纯全文/价格区间扩展为 `字段:关键词`：
    - `名称:name` / `品牌:brand` / `类型:type` / `颜色:color` / `尺码:size` / `衣长:length` / `状态:condition` / `小物:accessory` / `标签:tag` / `备注:note`。
    - 同时兼容英文别名与中文全角冒号。
  - 支持无值快捷查询：`无品牌`、`无标签`、`无小物` 等，也支持 `品牌:无品牌` 这种显式字段写法。
  - 支持 `尾款` / `心愿尾款` / `定金` 查询，直达心愿尾款衣物。
  - 新增 `queryShortcuts(items)`，按当前衣橱数据生成价格、无值、尾款与品牌/类型/颜色/状态 Top 维度快捷入口。
- `WardrobeRoute.kt`
  - 搜索框升级为查询小抄卡片，展示语法说明：字段查询、无值查询、尾款、价格区间。
  - 搜索区展示横向快捷 Chip；点击后直接写入查询词，复用 `BATCH-WARDROBE-DATA-01` 的统计联动。
  - 有筛选项叠加时提示「搜索 + 筛选共同更新」，避免用户误判统计口径。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：新增 diff 无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中。
- Android Emulator 装机验证：
  - 打开 `更多 → 搜索` 后可见 `查询小抄`、`价格 100-300`、`无品牌`、`无标签`、`无小物`。
  - 点击 `价格 100-300` 后查询词变为 `100-300`，统计卡切到 `当前结果统计`，显示 `命中 3/4 款`。
  - 点击 `无品牌` 后查询词变为 `品牌:无品牌`，统计卡继续联动，显示 `命中 2/4 款`。
- 截图记录：`/tmp/pinkhouse_wardrobe_data_02_shortcuts.png`。

**后续待办**

- `BATCH-WARDROBE-DATA-03`：把「详细统计」从占位按钮升级为统计明细 Sheet，优先支持当前搜索/筛选结果口径。
- `BATCH-WARDROBE-DATA-04`：沉淀最近搜索与常用筛选组合。

### BATCH-WARDROBE-DATA-03 衣橱详细统计 Sheet

**改动范围**

- `WardrobeHomeViewModel.kt`
  - 新增 `WardrobeStatisticBucket` 与 `WardrobeStatisticsBreakdown`。
  - UI 状态新增 `statisticsBreakdown`，按当前统计口径生成分组统计。
  - 分组维度：品牌、类型、颜色、状态、尾款状态。
  - 每个分组项包含件数、款数、总价值、尾款金额，默认按总价值排序。
  - 若有搜索/筛选，统计明细使用当前结果；否则使用全量衣橱。
- `WardrobeRoute.kt`
  - 统计卡内「详细统计」从纯展示 Pill 改为可点击入口。
  - 新增 `WardrobeDetailedStatisticsSheet`，展示统计口径、总件数/款、总价值、尾款，以及各维度明细。
  - Sheet 复用 `PinkFullHeightSheet` / `PinkSheetHeader`，保持与现有衣橱 Sheet 交互一致。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：新增 diff 无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中。
- Android Emulator 装机验证：
  - 点击统计卡 `详细统计` 后打开 Sheet。
  - 首屏可见 `详细统计`、`统计口径：全量衣橱`、`按品牌`、`按类型`、`按颜色`。
  - 向下滚动后可见 `按状态` 与 `按尾款状态`。
- 截图记录：`/tmp/pinkhouse_wardrobe_data_03_stats_sheet.png`。

**后续待办**

- `BATCH-WARDROBE-DATA-04`：最近搜索 / 常用筛选。
- 统计增强：后续可追加均价、占比条、购买年份/月度维度，以及从统计项反向生成筛选。

### BATCH-WARDROBE-DATA-04A 最近搜索 UI + 搜索区软圆还原

**背景**

- 用户反馈 Android 衣橱 UI 还原度不足，原生组件偏方正；后续衣橱复刻需优先用自定义软圆容器/组件贴近 iOS。
- iOS Simulator 对照：搜索激活时顶部为白色胶囊输入框 + 右侧圆形关闭按钮，背景保持粉色柔和渐变，统计卡与功能入口均为大圆角浅色块。

**改动范围**

- `WardrobeHomeViewModel.kt`
  - `WardrobeHomeUiState` / `WardrobeRuntimeState` 新增会话内 `recentSearches`。
  - 新增 `submitSearchQuery(query)`：提交快捷查询或键盘搜索时写入当前搜索词，并维护最近 8 条，大小写去重。
- `WardrobeRoute.kt`
  - 搜索输入由 Material `OutlinedTextField` 改为自定义 `BasicTextField` 胶囊，右侧使用圆形关闭按钮。
  - 搜索面板改为自定义 `SoftGlassPanel`，使用高圆角、半透明白底和浅描边模拟 iOS 玻璃感，不使用 `Modifier.blur`。
  - 快捷查询从 Material `AssistChip` 改为自定义 `SoftSearchPill`，减少方正感。
  - 点击快捷查询后显示「最近搜索」横向软圆 Pill；本批只做会话内 UI，不做 DataStore 持久化。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：新增 diff 无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中。
- Android Emulator 装机验证：
  - 打开 `更多 → 搜索` 后可见软圆搜索胶囊、圆形关闭按钮、`快捷查询` 与软圆查询 Pill。
  - 点击 `价格 100-300` 后出现 `最近搜索`、`100-300`、`当前结果统计`、`命中 3/4 款`。
- 截图记录：
  - `/tmp/pinkhouse_wardrobe_data_04a_search_soft.png`
  - `/tmp/pinkhouse_wardrobe_data_04a_recent_soft.png`

**后续待办**

- `BATCH-WARDROBE-DATA-04B`：将最近搜索持久化到 DataStore。
- `BATCH-WARDROBE-UI-02`：继续把统计卡、统计 Sheet 行项改成统一软圆玻璃容器，减少 Material 卡片感。

### BATCH-WARDROBE-DATA-04B 最近搜索持久化

**改动范围**

- `UserPreferencesDataStore.kt`
  - 新增 `wardrobe_recent_searches` preference key。
  - 新增 `wardrobeRecentSearches: Flow<List<String>>`。
  - 新增 `setWardrobeRecentSearches(searches)`，最多保存 8 条，大小写去重。
  - 查询词使用 UTF-8 percent-encoding 存入单个字符串，避免中文、空格或换行破坏序列化。
- `WardrobeHomeViewModel.kt`
  - 将 04A 的会话内最近搜索切换为 DataStore 来源。
  - `submitSearchQuery(query)` 在设置当前查询词后，把新查询合并进持久化最近搜索。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：新增 diff 无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中。
- Android Emulator 装机验证：
  - 点击 `价格 100-300` 后出现 `最近搜索` 与 `100-300`。
  - `am force-stop` 后重启 App，再打开 `更多 → 搜索`，仍可见 `最近搜索` 与 `100-300`。
- 截图记录：`/tmp/pinkhouse_wardrobe_data_04b_persist_recent.png`。

**后续待办**

- `BATCH-WARDROBE-UI-02`：按用户反馈继续提高 UI 还原度，优先统计卡与统计 Sheet 的自定义软圆容器。

### BATCH-WARDROBE-UI-02 衣橱统计卡 / 详细统计 Sheet 软圆还原

**背景**

- 用户反馈 Android UI 还原度仍不足，原生组件偏方正；后续若原生组件气质不贴 iOS，应优先用自定义容器/组件承接语义。
- iOS 对照：衣橱统计区是大圆角浅色容器，内部三项统计与功能入口都是柔和、低对比、轻透的分块；详细统计页面也应避免硬边 Card 堆叠。

**改动范围**

- `WardrobeRoute.kt`
  - 统计卡外层从 `ElevatedCard` 改为复用自定义 `SoftGlassPanel`。
  - 查询词展示从 Material `AssistChip` 改为自定义 `SoftSearchPill`。
  - 三项统计改为 `SoftStatTile`：半透明白底、18dp 圆角、轻描边，裙装价值/尾款使用粉色强调。
  - 功能入口 `FeaturePill` 从默认卡片色块改为自定义软圆、轻描边、半透明白底。
  - 详细统计 Sheet 内容区加入轻粉底，汇总卡复用 `SoftGlassPanel`，分组卡与分组行改为软圆半透明容器。
  - 不使用 `Modifier.blur`，避免 API 兼容红线。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：新增 diff 无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中。
- Android Emulator 装机验证：
  - 衣橱首页可见 `衣橱总览`、`总件数/款`、`裙装价值`、`详细统计`。
  - 点击 `详细统计` 后可见 `统计口径：全量衣橱`、`按品牌`、`按类型`，内容区呈轻粉底 + 软圆分组块。
- 截图记录：
  - `/tmp/pinkhouse_wardrobe_ui_02_stats_card.png`
  - `/tmp/pinkhouse_wardrobe_ui_02_stats_sheet.png`

**后续待办**

- `BATCH-WARDROBE-UI-03`：继续处理衣物网格/列表卡片，包括空图占位、价格区、尾款角标与卡片边缘。


### BATCH-WARDROBE-UI-03 衣橱列表/网格卡片软圆还原

**背景**

- 延续用户关于「原生组件太方正时使用自定义容器/组件」的反馈，本批集中处理最高频可见的衣物卡片区域。
- 目标不是增加新功能，而是让网格卡、列表行、尾款角标、价格文本与空图占位更接近 iOS Pink_House 的柔和、低对比、粉白玻璃感。

**改动范围**

- `WardrobeRoute.kt`
  - `WardrobeGridCard` 从 Material `Card` 改为自定义 `Surface`：28dp 大圆角、半透明白底、轻白描边，选中态使用粉色描边而不是硬边框。
  - 网格主图容器加入 22dp 圆角白色描边，卡片内容区增加轻微内边距，名称颜色统一为柔和灰；价格从裸文本改为 `SoftPricePill` 胶囊。
  - `WardrobeListRow` 同步改为 26dp 软圆 `Surface`，列表缩略图使用 20dp 圆角白描边，右侧价格复用 `SoftPricePill`。
  - 心愿尾款角标从硬色矩形改为 `SoftDepositBadge`：粉色半透明圆角面、白描边、白字。
  - 空图占位渐变从新增硬编码色值改为现有 `Color.White` / `PinkBackground` 半透明组合，避免新增 token 红线。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：新增 diff 无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中。
- Android Emulator 装机验证：衣橱首页可见软圆衣物网格卡、白色圆角主图框、价格胶囊；UI XML 确认 `奶油白半身裙`、`¥129.00`、`粉色针织开衫`、`心愿尾款` 均存在。
- 截图记录：`/tmp/pinkhouse_wardrobe_ui_03_cards.png`。

**后续待办**

- `BATCH-WARDROBE-UI-04`：继续处理顶部 `少女衣橱 / 心愿尾款` 分段、排序/筛选/网格/更多/新增按钮组与触控热区，让顶部操作区也脱离 Material IconButton 气质。


### BATCH-WARDROBE-UI-04 衣橱顶部操作栏 / 分段控件软圆还原

**背景**

- Computer Use 对照 iOS Simulator：iOS 衣橱顶部为 `少女衣橱 / 心愿尾款` 图标+文字分段，右侧是白色胶囊内的排序、筛选、网格、更多、添加按钮。
- Android 上一版虽然已有胶囊外框，但页签仍偏大号纯文本，工具按钮仍使用 Material `IconButton` 视觉；本批继续按用户反馈改成自定义软圆组件。

**改动范围**

- `WardrobeRoute.kt`
  - 顶部分段容器加入白色轻描边、零 elevation，页签改为图标 + 小字的紧凑纵向布局。
  - iOS `cabinet.fill` 语义在 Android 侧映射为 Material `Checkroom`；心愿尾款使用 `CalendarMonth`，不引入 SF Symbols 资产。
  - 操作按钮组保留白色胶囊，但内部按钮从 Material `IconButton` 改为自定义圆形 `Surface` + `clickable` 热区，降低原生按钮气质。
  - 排序图标改为 `SwapVert`，更多图标改为横向 `MoreHoriz`，更贴近 iOS 顶栏的视觉语义。
  - 筛选 badge 使用现有 `PinkBackground` / `PinkAccent` / `SoftGrayText`，不新增硬编码 `0xFF...` 色值。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：新增 diff 无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中。
- Android Emulator 装机验证：衣橱首页顶部左右胶囊之间留出间隔，分段显示图标 + `少女衣橱` / `心愿尾款`，工具栏可见 `排序`、`筛选`、`布局`、`更多`、`添加` 的可访问描述。
- 截图记录：`/tmp/pinkhouse_wardrobe_ui_04_top_controls.png`。

**后续待办**

- `BATCH-WARDROBE-UI-05`：处理衣物详情 Sheet、信息行、编辑/删除入口的软圆还原，继续覆盖核心查看链路。


### BATCH-WARDROBE-UI-05 衣物详情 Sheet / 信息行软圆还原

**背景**

- Computer Use 对照 iOS Simulator：iOS 衣橱详情页是粉色背景上的大图、名称品牌卡、分组信息卡与底部操作入口；信息行是低对比白色圆角块。
- Android 详情仍是线性 `DetailLine` + 裸图 + `OutlinedButton`，和前两批软圆卡片气质不一致；本批只改查看链路 UI，不新增数据能力。

**改动范围**

- `WardrobeRoute.kt`
  - `WardrobeItemDetailSheet` 内容区加入轻粉背景，并用 `SoftGlassPanel` 承载主图、摘要卡与分组信息卡。
  - 主图区域增加白色圆角描边；心愿尾款物品在主图右上复用 `SoftDepositBadge`。
  - 新增摘要卡：展示衣物名、品牌/暂无品牌信息、价格胶囊与库存，贴近 iOS 名称品牌卡结构。
  - 新增 `SoftDetailSection`，将原本散落的详情行分组为 `裙装信息`、`价格信息`、`备注`。
  - `DetailLine` 从裸 `Row` 改为半透明白色圆角信息行，统一文字层级与轻描边。
  - 删除入口从 Material `OutlinedButton` 改为 `SoftDeleteAction`，使用粉色轻底 + 圆角描边，避免硬边表单按钮感。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：新增 diff 无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中。
- Android Emulator 装机验证：点击 `奶油白半身裙` 打开 `衣物详情`，首屏可见软圆主图框、摘要卡与 `裙装信息`；向下滚动后可见 `价格信息`、`备注` 与 `移入回收站`。
- 截图记录：
  - `/tmp/pinkhouse_wardrobe_ui_05_detail_sheet.png`
  - `/tmp/pinkhouse_wardrobe_ui_05_detail_sheet_bottom.png`

**后续待办**

- `BATCH-WARDROBE-UI-06`：继续处理新增/编辑衣物 Sheet 的表单分组、输入框、日期选择入口与心愿尾款开关。


### BATCH-WARDROBE-UI-06 创建/编辑表单软圆还原

**背景**

- 新增/编辑衣物是衣橱核心录入链路；上一版表单仍大量使用 Material `OutlinedTextField`、`OutlinedButton` 与 `AssistChip`，视觉上偏硬、偏默认 Android。
- 延续用户偏好：当原生组件太方正时，优先用自定义软圆容器/组件保持 Pink_House 的粉白玻璃感。

**改动范围**

- `WardrobeRoute.kt`
  - `WardrobeItemEditorSheet` 内容区加入轻粉背景，和详情 Sheet / 统计 Sheet 的软圆体系统一。
  - `FormSection` 从 Material `Card` 改为复用 `SoftGlassPanel`，表单分组统一大圆角、半透明白底、轻描边。
  - 图片缩略图增加白色圆角描边；相册 / 测试图片入口改为 `SoftFormActionButton` 粉色软圆按钮。
  - 测试素材列表从 Material `AssistChip` 改为 `SoftSearchPill`，减少硬边 Chip 感。
  - `DraftTextField` 从 `OutlinedTextField` 改为自定义 `BasicTextField`：标签、占位与输入内容都放在半透明白色软圆块中，备注支持多行。
  - `DatePickerField` 从只读 `OutlinedTextField` 改为自定义日期行，右侧圆形日历按钮保留选择语义。
  - `加入心愿尾款` 开关外包入柔和白底容器，说明文字与 Switch 保持原有行为。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：新增 diff 无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中。
- Android Emulator 装机验证：点击顶部 `添加 → 手动创建`，可见软圆表单分组、`相册`、`测试图片`、`裙装名称 *`、`品牌名称`；继续滚动可见 `价格信息`、`购买信息`、`购买日期`、`加入心愿尾款` 与 `备注`。
- 截图记录：
  - `/tmp/pinkhouse_wardrobe_ui_06_editor_sheet.png`
  - `/tmp/pinkhouse_wardrobe_ui_06_editor_sheet_purchase.png`

**后续待办**

- `BATCH-WARDROBE-UI-07`：继续处理筛选 Sheet / 查询条件面板软圆还原，优先服务数据查询体验。


### BATCH-WARDROBE-UI-07 筛选 Sheet / 查询条件面板软圆还原

**背景**

- 筛选是衣橱数据查询链路的核心入口；上一版功能可用，但 Sheet 内部仍是线性表单、Material `AssistChip` / `FilterChip` 与默认按钮组合，和近期软圆体系不一致。
- 本批保持筛选逻辑不变，只把多维筛选面板、快捷条件和底部操作条统一到粉白玻璃风格。

**改动范围**

- `WardrobeRoute.kt`
  - `FilterSheet` 内容区加入轻粉背景，顶部显示当前草稿筛选项数量。
  - 筛选字段归入 `筛选条件` 软玻璃分组，继续复用 UI-06 的自定义 `DraftTextField`。
  - `无品牌`、`无标签`、`无小物` 快捷条件从 Material `AssistChip` 改为 `SoftSearchPill`。
  - `只看心愿尾款` 从 `FilterChip` 改为同体系 `SoftSearchPill`，选中状态更贴近 iOS 低对比粉色胶囊。
  - 底部 `清空 / 取消 / 应用筛选` 改为固定软圆操作条，新增 `SoftSheetActionButton`，应用按钮使用粉色主操作样式。
  - 保留原筛选字段、清空、应用与统计联动行为，不改数据层。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：新增 diff 无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中。
- Android Emulator 装机验证：点击顶部筛选按钮打开 Sheet，首屏可见 `筛选`、`筛选条件`、品牌/类型等软圆输入行与固定 `应用筛选`；向下滚动可见 `快捷条件`、`无品牌`、`无标签`、`无小物`、`只看心愿尾款`。
- 截图记录：
  - `/tmp/pinkhouse_wardrobe_ui_07_filter_sheet.png`
  - `/tmp/pinkhouse_wardrobe_ui_07_filter_sheet_shortcuts.png`

**后续待办**

- `BATCH-WARDROBE-DATA-05`：把详细统计 Sheet 的品牌/类型/颜色/状态/尾款分组项做成一键反向筛选，形成“统计发现 → 查询定位”的闭环。


### BATCH-WARDROBE-DATA-05 统计明细项一键反向筛选

**背景**

- 衣橱详细统计已经能按品牌、类型、颜色、状态、尾款状态拆解数据，但用户发现某一类后还需要手动回到筛选面板输入条件。
- 本批补齐“统计发现 → 查询定位”的闭环：点统计明细行，直接生成筛选条件并回到首页当前结果统计。

**改动范围**

- `WardrobeHomeViewModel.kt`
  - 新增 `WardrobeStatisticsFilterKind`，描述统计分组来源：品牌、类型、颜色、状态、尾款状态。
  - 新增 `applyStatisticsBucketFilter(kind, label)`：把统计分组 label 映射为 `WardrobeFilterState`。
  - 空值统计项自动映射到现有无值筛选语义：`未填写品牌 → 无品牌`、`未填写类型 → 无类型`、`未填写颜色 → 无颜色`、`未填写状态 → 无成色`。
  - 尾款状态支持 `心愿尾款` 与 `现货/已拥有` 两种反向筛选；`WardrobeFilterState` 增加 `ownedOnly`，并在 ViewModel 组合链路中执行现货筛选，不改 repository / Room。
- `WardrobeRoute.kt`
  - `WardrobeDetailedStatisticsSheet` 新增分组行点击回调，点击后关闭 Sheet。
  - 汇总区加入提示文案：点按下方分组行可直接生成筛选条件。
  - 分组行增加 `点按筛选` 提示，保留软圆半透明样式。
  - 筛选 Sheet 快捷条件补充 `只看现货/已拥有`，与尾款状态反向筛选保持一致。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：新增 diff 无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中。
- Android Emulator 装机验证：点击 `详细统计` 打开 Sheet，可见 `点按下方分组行`、`按品牌`、`点按筛选`；点击 `未填写品牌` 后 Sheet 关闭，首页统计卡切换为 `当前结果统计`，显示 `筛选 1 项` 与 `命中 2/4 款`。
- 截图记录：`/tmp/pinkhouse_wardrobe_data_05_reverse_filter.png`。

**后续待办**

- `BATCH-WARDROBE-DATA-06`：在统计明细分组中补充均价与价值占比条，继续增强数据统计可读性。

## 八、M3 推进记录（Computer Use 对照）

### 已落地

- 使用 Computer Use 对照 iOS Simulator 与 Android Studio Pixel 模拟器：确认 iOS 衣橱首页/心愿尾款的顶部双分段、操作按钮组、统计卡、底部猫咪覆盖和空态结构。
- 原项目资产已迁入 Android：`pink_splash.jpg`、`pink_house_logo.png`、`naicha_peeking.png`、`maomao_peeking.png`、宠物头像、小世界背景、财富背景、VIP 卡、喵金币、食物图、字体与 `open_dress.mp4`。
- 开屏接入 Android SplashScreen API，Manifest 使用原项目 Logo，预 Android 12 窗口背景使用 `pink_splash_window.xml`。
- Room 升级到 v3：补齐 `uuid`、`tagNamesJson`、`accessoryItemsJson`、`sizeChartImagePathsJson`、`priceChartImagePathsJson`，并生成 schema v3。
- 数据层补齐详情与回收站能力：`observeItem`、`observeTrashedItems`、`restoreItems`、`permanentlyDeleteItems`、`purgeTrashedBefore`。
- 衣橱 UI 补齐详情 Sheet、编辑 Sheet、批量导入 Sheet、回收站 Sheet、心愿尾款提醒 Sheet；详情点击、编辑保存、软删除、恢复、彻底删除进入本地闭环。
- 搜索/筛选提取到 `WardrobeBusinessLogic`：支持深字段搜索、价格区间、无标签/无品牌/无小物等特殊筛选、月度/系列尾款聚合。
- 本地尾款通知接入 `AlarmManager` + `BroadcastReceiver` + `NotificationCompat`，通知权限由尾款提醒 Sheet 触发。
- 性能侧继续保持图片解码在 IO 线程；列表增加稳定 key，底部猫咪使用资源图；非衣橱 Tab 改为原资产骨架占位。

### 本轮验证

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:testDebugUnitTest` 通过。
- `adb shell am start -W` 普通冷启动成功，记录 `TotalTime: 3070ms`。
- Computer Use 验证 Android 模拟器：衣橱首页、底部猫咪覆盖、详情 Sheet 可见且未出现 System UI ANR。

## 九、已知待办（非本迭代）

- 列表布局下的拖拽排序
- 品牌 / 系列 / 标签 独立管理页
- `brand_series` 表的批量导入写入与系列统计页
- 尺码表 / 价格表 图片编辑入口
- 心愿尾款分支的编辑模式
- Sheet 切换时的 key 变更能否用 `remember(key)` 更优

## 十、日志与可调试性

统一走 **Timber**（Application.onCreate 注册），tag 约定：

- `WardrobeTopBar` 顶栏按钮点击
- `WardrobeMenu` DropdownMenu 项点击
- `WardrobeSheet` ModalBottomSheet 生命周期
- `WardrobeCreate` / `WardrobeBatchImport` / `WardrobePicker` 草稿与图片选择
- `WardrobeReorder` 拖拽起止
- `WardrobeSelection` / `WardrobeItemCard` 批量勾选

便于 `adb logcat -s Wardrobe*:V` 定位回归。

### Debug 启动备注

Pixel 10 Pro Emulator 在 Android Studio 使用 `am start -D --suspend` 调试启动时，曾出现一次 `System UI isn't responding` 弹窗。adb 普通启动未复现 app 侧 ANR，logcat 显示 SystemUI 资源查询错误且无 `com.pinkhouse` 崩溃记录。排查时优先用不带 `-D --suspend` 的普通启动确认 app 启动链路，再看 `/data/anr` 是否指向 app 进程。

## 十一、与鸿蒙侧差异对照

| 维度 | 鸿蒙 Next | Android | 差异根源 |
| --- | --- | --- | --- |
| Sheet | `bindSheet($$this.isOpen)` | `ModalBottomSheet(onDismissRequest)` | 响应式双向绑定 vs 单向数据流 |
| 图片 | `photoAccessHelper.PhotoViewPicker` | `ActivityResultContracts.PickVisualMedia` | 平台 API |
| RDB schema | v3→v4 DROP 重建 | Room v1→v2 Migration | Android 用户基数大，不能丢数据 |
| 拖拽排序 | `Grid.editMode` + `onItemDragStart/onItemDrop` | `LazyVerticalGrid` + 官方 `DragAndDrop` API / 第三方 `reorderable` | 平台能力差异 |
| 日志 | `hilog` + `AppLogger` 封装 | `Timber` | 平台日志栈 |
| 图标 | `SymbolGlyph($r('sys.symbol.xxx'))` | Material Icons vector | 资源体系 |
