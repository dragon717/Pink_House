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
