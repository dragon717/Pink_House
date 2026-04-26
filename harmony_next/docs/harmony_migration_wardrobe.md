# 少女衣橱 · 鸿蒙迁移说明（衣橱页）

本文记录 `feature/wardrobe/WardrobePage.ets` 从 iOS SwiftUI 版本（`Pink_House/Pink_House/Views/Wardrobe/WardrobeView.swift` 等）迁移到 HarmonyOS ArkUI 的进度与差异。业务以 SwiftUI 为准；规范参考鸿蒙官方文档 / DevEco Studio。

## 一、TopBar 顶栏

### 已迁移

| 功能 | iOS 原型 | 鸿蒙实现要点 |
| --- | --- | --- |
| 5 常驻圆按：排序 / 筛选 / 视图 / 更多 / 添加 | `WardrobeView.toolbar { .. }` 五按钮 | `RoundButton` + `RoundButtonWithMenu` @Builder，40×40，`AppSymbolName.{Sort,Filter,Grid,More,Add}` |
| 排序 Sheet | `SortOptionsSheet` | `SortSheet`，FIT_CONTENT |
| 筛选 Sheet | `FilterView` 多选 Chip | `FilterSheet`，MEDIUM |
| 视图切换 Sheet | 视图 ActionSheet | `ViewLayoutSheet`，FIT_CONTENT |
| 更多菜单：搜索 / 编辑 / 调整顺序 | 原 iOS 散落在工具栏+编辑模式切换 | `bindMenu(MenuElement[])` 下拉 |
| 添加菜单：手动创建 / 批量导入 | `AddSheet` ActionSheet | `bindMenu` 下拉分别进入 `CreateSheet` / `BatchImportSheet` |
| 编辑模式顶栏 | `isSelectionMode` 时切换 `完成 / 已选 n / 全选` | `SelectionTopBarContent` @Builder |

### 差异 / 降级说明

- iOS `toolbar` 有系统返回侧滑衔接，鸿蒙 `Navigation` 的 `hideTitleBar(true)` 后，顶栏完全自绘，空间与 iPhone 17 不完全一致，已尽量对齐。
- "更多 / 添加" 使用 ArkUI `bindMenu` 原生下拉，iOS 的分段 ActionSheet 在鸿蒙不存在对应控件，改为原生菜单。

## 二、ItemCard 网格卡片

### 已迁移

- 卡片主视觉：`item.imageUri` 优先显示真实图片（`Image().objectFit(ImageFit.Cover)`），缺图时回退到原型的「分类首字 + 粉色渐变」占位。
- 编辑模式（`isSelectionMode`）右上角勾选圈：未选中=白色空圈，选中=粉色填充+白色 ✓，配合卡片边框加粗&变粉。
- 点击路由：编辑模式下点击切换勾选（`toggleItemSelection`）；非编辑模式点击进入 `wardrobeItemDetail` 详情页。
- 非编辑模式保留右上角「心愿尾款」小角标。
- 自定义排序下可长按拖拽换位（`Grid.editMode + onItemDragStart/onItemDrop`），释放后即时 `persistCustomOrder` 刷写 RDB `sort_index`。

### 差异 / 降级说明

- iOS `onDrag/onDrop` 的 `ItemProvider` 是系统级，鸿蒙 `Grid` 的 `editMode` 只在 Grid 内部生效，拖到 Grid 外无视觉反馈，这是当前鸿蒙栅格拖拽能力的上限。
- iOS 里 "编辑" 与 "调整顺序" 是同一模式（SwiftUI `EditMode`），鸿蒙里我们把两个入口分开：`编辑` 保持当前排序、`调整顺序` 强制切到 `Custom` 并触发一次 `loadItems`，避免用户在「价格排序」下拖拽后状态错乱。
- 列表模式（Row 布局）下的拖拽 **暂未实现**，当前仅 Grid 布局可拖。

## 三、手动创建 Sheet

### 已迁移

- 名称（必填）/ 分类 Chip（上衣/下装/连衣裙/鞋履/配饰）/ 价格（可选）/ 主图选择
- 主图：`photoAccessHelper.PhotoViewPicker` 单选，选中后 72×72 预览 + 「换图」按钮
- 保存：写 `wardrobe_items` 表，`sort_index` 默认 `Date.now()`，刷新列表
- 取消：清空草稿 + 关 Sheet

### 差异 / 降级说明

| iOS 字段 | 状态 | 原因 |
| --- | --- | --- |
| 品牌 brand / 品牌系列 | **未迁移** | 预留字段，当前 MVP 暂不暴露；可通过 `addItem` 扩参补齐 |
| 标签 tag | **未迁移** | `WardrobeItemTag` 关系表迁移完成，但手动创建 Sheet 还没出标签选择 UI，计划二期 |
| 定金/尾款/付款日 | **未迁移** | 原型里这是「心愿尾款」分支的字段，手动创建 Sheet 默认按衣橱项录入 |
| 多图拍摄 + 预览 | **未迁移** | 暂只支持单张主图；批量导入承担多图诉求 |

## 四、批量导入 Sheet

### 已迁移

- 系列名输入（可选，不填默认「导入」）
- `PhotoViewPicker` 多选（maxSelectNumber=20），已选与待选累加
- 3 列预览网格，单图右上角 `×` 删除
- 确认导入：串行写入 RDB，每条文案 `${seriesName} ${i+1}`；失败单条记录 hilog，成功计数返回

### 差异 / 降级说明

- 没有原型里的 AI 识图分类（鸿蒙侧暂无 Vision Kit 封装），全部按「连衣裙」分类写入，用户可在详情页再调整。
- 系列元数据（品牌、系列、定金）暂未写入 `brand_series` 表，批量导入后仅在 `name` 字段拼前缀。

## 五、编辑模式

### 已迁移

- 入口：`更多 → 编辑`、`更多 → 调整顺序`（后者强制 `Custom` 排序）
- 顶栏：`完成 / 已选 n/N / 全选 ⇄ 取消全选`
- 卡片：勾选圈 + 选中描边
- 底部批量操作栏：`批量删除 (n)`，带 `AlertDialog` 二次确认，命中 `BatchSoftDeleteWardrobeItemsUseCase` 软删
- 自定义排序下支持 Grid 拖拽换位

### 差异 / 降级说明

- iOS 编辑模式还支持 **批量加入心愿单 / 批量导出到穿搭** 等操作，鸿蒙当前底栏只有「批量删除」一个按钮，后续按用户反馈迭代。
- 社区导入（"从社区导入"）**按需求不实现**，UI 入口也已隐藏。

## 六、数据链路

### 已迁移

- `DatabaseSchema.ets` v4：新增 `sort_index INTEGER DEFAULT 0`
- `WardrobeItemDao`：`reorderItems(ids)` / `softDeleteItems(ids)` / `queryItems.orderBy` 的 `Custom` 分支 `ORDER BY sort_index ASC, created_at DESC`
- `RdbWardrobeRepository`：代理 DAO 新增两个方法
- `ReorderWardrobeItemsUseCase` / `BatchSoftDeleteWardrobeItemsUseCase`：新增两个 UseCase
- `loadPreferences`：读 `wardrobePreferences`，恢复上次排序/布局

### 差异 / 降级说明

- `sort_index` 是 schema 新增字段；版本从 3 升 4，旧数据库会触发 `ensureSchema` 的 DROP 重建逻辑；**真机升级的老用户会丢失本地衣橱数据**。MVP 期先接受，发版前需要补一次 `ALTER TABLE ... ADD COLUMN` 的软迁移。
- `WardrobeItemTag` 关系表迁移完了 DAO，但 Chip 选择 UI 还没在手动创建 Sheet 里暴露。

## 七、已知待办（非本迭代）

- 列表布局下的拖拽排序
- 品牌 / 系列 / 标签 在手动创建 Sheet 中的录入 UI
- `brand_series` 表的批量导入写入
- 详情页编辑 / 删除 / 加入心愿单的全链路
- 心愿尾款分支 `DepositPanel` 的编辑模式（当前不支持在心愿尾款分支进入编辑）
- Sheet 切换时的 `setTimeout` 规避能否用 `@Watch` 更优

## 八、日志与可调试性

已为关键路径加 `AppLogger` 埋点，过滤 `WardrobePage` 标签可见：

- `[TopBar]` 顶栏按钮点击
- `[MoreMenu]` / `[AddMenu]` 下拉菜单项点击
- `[Sheet]` `openSheet` / `bindSheet` 生命周期
- `[Create]` / `[BatchImport]` / `[Picker]` 草稿与图片选择
- `[Reorder]` 拖拽起止
- `[Selection]` / `[ItemCard]` 批量勾选

便于后续 hilog 侧定位「手动创建/批量导入没反应」类回归。
