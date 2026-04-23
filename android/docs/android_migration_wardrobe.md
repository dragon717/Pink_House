# 少女衣橱 · Android 迁移说明（衣橱页）

> 本文记录 `feature/wardrobe/**` 从 iOS SwiftUI 版本（`Pink_House/Pink_House/Views/Wardrobe/WardrobeView.swift` 等）迁移到 Android Jetpack Compose 的进度与差异。业务以 SwiftUI 为准；规范参考 Android 官方文档 / Material 3 / Compose Guidelines。与鸿蒙侧 `harmony_next/docs/harmony_migration_wardrobe.md` 对标，差异集中在无 GMS / Scoped Storage / Room schema 几类。

> **当前状态**：M2 衣橱闭环已落。`WardrobeRoute.kt` 已替换为 `衣橱 / 心愿尾款` 双页 Compose 复刻；`WardrobeHomeViewModel` 负责 Room + DataStore + 单向 UI 状态；Room `wardrobe_item` 已升级到 v2 并保留 v1→v2 Migration；手动创建、图片导入、搜索、筛选、排序、布局切换、编辑选择态、批量软删除均已接入。

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

## 七、M3 推进记录（Computer Use 对照）

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

## 八、已知待办（非本迭代）

- 列表布局下的拖拽排序
- 品牌 / 系列 / 标签 独立管理页
- `brand_series` 表的批量导入写入与系列统计页
- 尺码表 / 价格表 图片编辑入口
- 心愿尾款分支的编辑模式
- Sheet 切换时的 key 变更能否用 `remember(key)` 更优

## 九、日志与可调试性

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

## 十、与鸿蒙侧差异对照

| 维度 | 鸿蒙 Next | Android | 差异根源 |
| --- | --- | --- | --- |
| Sheet | `bindSheet($$this.isOpen)` | `ModalBottomSheet(onDismissRequest)` | 响应式双向绑定 vs 单向数据流 |
| 图片 | `photoAccessHelper.PhotoViewPicker` | `ActivityResultContracts.PickVisualMedia` | 平台 API |
| RDB schema | v3→v4 DROP 重建 | Room v1→v2 Migration | Android 用户基数大，不能丢数据 |
| 拖拽排序 | `Grid.editMode` + `onItemDragStart/onItemDrop` | `LazyVerticalGrid` + 官方 `DragAndDrop` API / 第三方 `reorderable` | 平台能力差异 |
| 日志 | `hilog` + `AppLogger` 封装 | `Timber` | 平台日志栈 |
| 图标 | `SymbolGlyph($r('sys.symbol.xxx'))` | Material Icons vector | 资源体系 |
