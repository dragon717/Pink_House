
## ⚠️ 测试数据隔离硬规则（2026-09-21「小狗仪仗队」事故）
- 单测宿主 = 主 App（bugod2.ItemManager），测试进程里的 FileManager.default 就是用户真实沙盒。tearDown 删 Application Support 文件 = 删用户数据。
- ShopCatalog 系存储已统一走 `ShopCatalogStorage`（ShopCatalogOps.swift）：测试必须 setUp 调 `ShopCatalogStorage.useTemporaryForTesting()`、tearDown 调 `restoreDefaultForTesting()`；禁止对生产路径 removeItem。防线测试：ShopCatalogStorageIsolationTests。
- 新增任何落盘测试前先问：这条路径会不会指向宿主 App 沙盒？一律用注入目录，不准碰真实文件。
- BSD grep 不支持 `\|` 交替（会静默误报无匹配），搜索一律 `grep -E` 或 `grep -F`；JSONEncoder 默认把中文转义成 \uXXXX，搜中文数据要同时搜明文与 \u 转义。
- Xcode 环境现状：/Applications/Xcode-beta.app 已不存在，只有 /Applications/Xcode.app（不要再带 DEVELOPER_DIR=Xcode-beta）。

## ⚠️ 列表展示顺序硬规则（2026-09-22「系列乱序」事故）
- Catalog 实体在 JSON / 内存数组里是**录入顺序**，不是字典序。任何按名称展示的列表都必须走
  `AZIndexGrouping.sortedByName` 或 `AZIndexGrouping.groups`（`Services/ShopCatalog/AZIndexGrouping.swift`，
  nonisolated 纯逻辑），或 Store 的 `shopsSortedByName()/seriesSortedByName()/productsSortedByName()`；
  禁止直接 `ForEach(store.catalog?.series ?? [])`。
- 索引字母口径：`#` 排最前 → A–Z（中文走 CFStringTransform 转拼音首字母），组内 `localizedStandardCompare`。
- 同一页面混放多类实体时，A-Z 索引会出现重复字母导致跳转歧义：`ShopCatalogOpsManageView` 用
  店家/系列/商品分栏（segmented Picker），每栏独立 A-Z 分组 + 独立索引滑块。
- destination 坑：`-destination 'name=iPhone 17 Pro'` 对该 scheme 匹配失败 exit 70，
  必须用 iOS 27 runtime 那台的 UDID（iPhone 18 Pro）。`test` 首次报
  "signal term before establishing connection" 属模拟器抖动，原命令重跑即可。

## ⚠️ 补录上新：「重复」不是阻断条件（2026-09-22）
- `ShopCatalogDraftStore.publish` 命中既有商品时，预约价与现货价**都必须**能继续录入，
  只做 SaleEvent 追加；禁止用「已收录 / 重复」抛错——补录的目的常常就是给已在 Catalog、
  甚至已入心愿/尾款/衣橱的商品补价格。
- `CatalogPriceArchive` 同类取最新的口径必须显式处理并列：`max(by:)` 在并列时保留**先出现**元素，
  会让后追加的补录价格被盖住；一律按「startAt 晚者优先 + 同时间取数组靠后者」做 tie-break。
- 商品页价格档案要求：预约价 / 现货价 / 定金 / 尾款全部占位展示，缺失走「暂无」兜底，
  不许留空白，也不许用 `deposit ?? 0` 伪造数据。
- 预约价与现货价**并存不互斥**（2026-09-22）：草稿口径一律走 `effectiveReservationPrice /
  effectiveStockPrice`（saleKind 仅旧数据兼容）；现货价可空置后补。
- 预约价格表是**系列级**素材（`CatalogSeries.priceChart`），上传入口在系列编辑 sheet，
  单品编辑页不上传；详情页自动读所属系列；OCR 解析走 `CatalogChartParser`（parseText 可单测）。
- 实体管理只有 店家/系列 两个 Tab（2026-09-22）：商品管理入口在系列详情页
  （`ShopCatalogSeriesProductsView`），不要再往顶层加商品列表。

## ⚠️ 价格双流程硬规则（2026-09-22）：价格修正 ≠ 追加销售记录
- 两者**不得共用任何编辑与提交逻辑**：
  · `价格修正` = 更正当前商品属性 → 写 `CatalogProduct.priceCorrection`（唯一一份最新状态，
    重复修正直接覆盖），**不产生历史记录、不碰 saleEvents**，接口 `correctCurrentPrice(...)`；
    撤销用 `clearPriceCorrection(...)`。
  · `追加销售记录` = 新增业务事件（往年款再贩/复刻/补货）→ 只 append 一条 `CatalogSaleEvent`，
    **永不 remove/replace**，接口 `appendSaleRecord(...)`，`startAt`（再贩/批次时间）**必填**，
    去重靠 `CatalogSaleEvent.appendFingerprint`（商品|类型|价格|定金尾款|批次日；批次名与
    recordedAt 不参与），命中抛 `ShopCatalogPriceEditError.duplicateRecord`。
- 旧的无日期 `appendSaleEvent(...)` 已删除，不要再加回来——那是「不带时间维度」的后门。
- `CatalogPriceArchive` 只读推导：`current*` 系列取修正值优先、否则回退历史记录；
  写入必须走上面两个接口之一。详情页展示「当前生效值」并在修正时标注「历史销售记录不变」。
- 深度编辑页（`ShopCatalogProductDeepEditView`）只负责商品资料，价格只提供只读总览 + 两个
  独立入口（橙色=修正 / 绿色=追加），保存按钮文案「保存资料」。
- 防线：`updatePublishedProduct` 入参 priceCorrection 为 nil 但已存有修正时，保留已存修正
  （防止用旧快照的资料保存把修正清掉）。
- 价格修正口径（2026-09-22 调整）：**留空 = 清除该价格**，不是「跳过不修改」。修正弹窗按
  当前生效值完整预填、整快照提交；`correctCurrentPrice` 的 nil = 清除（无 noChange 错误）；
  `CatalogPriceArchive` 在 correction 存在时逐字段对号入座、nil 不回退历史；
  预约价清空时定金/尾款必须一并清空（否则对账拦截）。禁止给修正加「空 = 保留」的旧语义。

## ⚠️ 批次列表治理（2026-09-22）
- 批次会话 `CatalogBatchEntrySession` 的删除只动 `shop-catalog-batches.json` 里的归组记录，
  **绝不连带删除任何 `CatalogProductDraft`**；草稿的 batchID 引用失效但数据完整保留。
- 可删口径：批次下无草稿，或草稿全为 published/archived（已处理）。
  仍有 draft/submitted/reviewed → 拦截并返回明确原因（含各状态条数与处理路径）。
- 视图必须读 `draftStore.batches`（`@Published`）而不是 `ShopCatalogDraftStore.loadBatches()`：
  后者是静态读盘，删完列表不刷新。
- 删除/多选/确认/反馈沿用现有组件：行尾「更多」下拉菜单（ellipsis.circle，同实体管理商品行）、`.confirmationDialog`
  （同 ProductManageRow 删除）、toast 胶囊、`.alert("操作失败")`；拦截走独立的
  「部分批次无法删除」alert，条目与选择都保留以便重试。
- 测试坑：同一进程内 `ShopCatalogDraftStore.shared.drafts` 跨套件累积，断言只能比对**前后快照**或按
  `batchID` 收窄，禁止断言全局总数 / `allSatisfy` 全属于某批次。

## ⚠️ 点菜页商品卡片合并与双价（2026-09-22）
- 点菜式选购（ShopCatalogSeriesMenuView）：同款不同色按「品类|剥离颜色词后的款名」
  合并为一张卡（`ShopCatalogSameDesignGrouper`，nonisolated 可单测）；卡片内颜色
  chips 切换激活单品（activeProductByCard），多色卡标题=款名+「· N 色」。
- 价格双阶段（`ShopCatalogCardPricePhase`）：预约窗口进行中 → 默认按预约价加入、
  不可自选；预约结束且双价并存 → 卡片上「现货/预约」chips 自选（默认现货）。
- 加购口径透传：菜单页把 effectiveChoice + 颜色传给 `ShopCatalogWardrobeMergeView`
  （新增可选参数 priceChoices/colorByProduct，默认值保旧调用点）；确认页按口径生成
  Selection，预约口径用 `reservation.deposit ?? 0`（**CatalogSaleEvent.deposit 是
  Optional**）；选预约但无 reservation 记录时回退 .stock（现货缺价回退历史预约价）。

## ⚠️ 尺码表/价格表解析口径（2026-09-22 V1.4）
- OCR 表格解析必须走包围盒行重建（`CatalogChartParser.reconstructLineTexts`）：
  Vision 会把大列距表格拆成逐单元格 observation，「一行=一个 observation」的旧口径
  会报「表头下没有数据行」。
- 手动表格文本一律走 `CatalogManualChartText`（parseColumns/parseRows/normalized）：
  · 列头首列是行标签列名（尺码/项目/款式…）时剔除，否则详情页出现重复「尺码」列 + 错位；
  · 词元尾冒号/逗号清洗（「86-92:」→「86-92」）；
  · 详情页 structuredTable 渲染前也做 normalized（已落库坏数据兜底对齐）。
- 详情页「预约价格表」卡有**预约价区间**兜底（系列在售商品 currentReservationPrice
  的 min–max），价格表解析失败时用户仍能看到价格区间。
- 点菜页选择区维度 = 颜色 + 尺码（尺码表行标签优先）+ 价格口径（双价并存即可自选，
  预约期间默认预约价）；尺码经 MergeView.sizeByProduct → Selection(size:) 入库。

## ⚠️ 款式归组（同款不同色）硬规则（2026-09-22 V1.5）
- `CatalogProduct.designName`（可选）：显式款式名优先，缺省按名称剥离颜色词派生
  （`ShopCatalogSameDesignGrouper.designName(of:)` / `designKey(of:) = 品类|款式`）。
  同款不同色是**独立 product 实体**，列表/详情只做展示层归组，不合并实体。
- 发布/建档必须落款式名（publish + QuickAddSheet + DraftDetailEditor 款式字段）；
  既有商品缺款式名时补价草稿也会回填（判定以 overlay 为准，传入 store 视图可能过期）。
- 系列商品管理页列表按款式组展示（展开看颜色子项）；详情页轮播 = 本商品图 +
  同款其他颜色主图（滑动切换、颜色标注胶囊）。

## ⚠️ 图表图片引用与显示（2026-09-22 V1.6）
- 尺码表 sourceImage=asset id（→assets.originalURL→Bundle）；价格表 sourceImage=local: 直接引用。
  判断「图片能否显示」一律用 `ShopCatalogImageResolver.isUnavailable(_:)`（nonisolated 可单测），
  禁止渲染 `UIImage(contentsOfFile:) ?? UIImage()` 空白图——ShopCatalogAssetImage 读图失败必须走占位图。
- 模拟器 acceptance 重装/抹容器会连带删掉 Application Support/ShopCatalog（JSON+images），
  local: 引用全部失效；UI 需给「原图文件丢失，请重新上传」提示而非空白。
