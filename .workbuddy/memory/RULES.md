# Pink_House 规则全表（细节层）
> 注入版红线见同目录 **MEMORY.md**；事故经过与来龙去脉见 YYYY-MM-DD.md。
> 本文件不会被自动注入，需要具体 API/口径时主动打开。

## 环境/工具
- 构建测试走 skill `pink-house-xcodebuild-acceptance`；只 `/Applications/Xcode.app`。
- destination 写 UDID `FA7332BE-B29E-4879-A139-C68A24314DB1`（`name=` exit 70）。
- 搜索用 `grep -E`/`-F`（BSD 禁空交替，`(a|b|)` 静默不过滤）；搜中文兼搜明文与 \uXXXX。
- 同一响应里对同一文件多次 Edit 会互相覆盖 → 串行或合并。
- `-only-testing:…/X` 不带 `XEndToEndTests`。
- `publish` 返回摘要**不是 productID**；静态写接口只刷 `.shared`，新实例断言前 `reloadWithOverlay()`。
- **后台测试日志可能陈旧**：`test-without-building` 用的是上次构建产物，同一批测试的多个后台任务
  可能分别命中「修复前/修复后」两份 bundle，回执乱序到达时容易看到矛盾的通过/失败数。
  以**用例数**为准核对（改了测试却仍报旧数量 = 旧 bundle），必要时重跑确认。

## 启动/横屏/「打不开」（09-23）
- 方向只由 Info.plist + pbxproj `INFOPLIST_KEY_UISupportedInterfaceOrientations[_iPhone]` 决定；改完 `plutil -p` 验 `~iphone` 含 Portrait。
- `INFOPLIST_KEY_UILaunchScreen_Generation` 必须 `NO`（YES=空字典=深色纯黑，冷启动 9–26s 全黑被误判打不开）；Info.plist 显式 `UILaunchScreen{UIImageName=LaunchSplash}`。
- `LaunchSplash.imageset` 图必须放 **3x** 槽位；别动 `SplashScreen.imageset`（`BuiltinImagePicker` 按名引用）。
- 判崩溃看 `~/Library/Logs/DiagnosticReports/ItemManager-*.ips`：含 `XCTest`/`Core Data` 的是**测试进程**（宿主=主 App）。

## 测试隔离（09-21 事故）
单测宿主=主 App，`FileManager.default` = 真实沙盒。
- 存储走 `ShopCatalogStorage`：setUp `useTemporaryForTesting()`、tearDown `restoreDefaultForTesting()`，禁对生产路径 removeItem。
- `.shared` 跨套件累积、坏文件标志跨用例残留：只比前后快照/按 `batchID` 收窄，禁断全局总数；setUp 要 `loadDrafts()`。

## SPU/SKU 分层与录入期同步（09-23）
- 款式级录一次：尺码表、面料、款式描述；颜色级：配色图、尺码选择。
- 款式键 = `seriesID|category|designName`（`ShopCatalogStyleProfileSharing.styleKey`）；写必须显式落 designName。
- 面料/描述存 `CatalogStyleProfile`（`ShopCatalog.styleProfiles`，**必须加进 `rebuildMergedCatalog`**）；读 `store.fabric/styleDescription(forProduct:)`；写唯一入口 `updateStylePublicInfo`（一次落盘、留空=清除）。
- 录入端唯一入口 `ShopCatalogStyleEntrySheet`；发布走 `publish`，别自写覆盖层。
- 草稿一键同步：`ShopCatalogDraftStyleSync`（分组 + `Field{price,sizeChart,fabric,styleDescription}` + `syncPlan`）→ `ShopCatalogDraftStore.syncStyleInfo(sourceDraftID:targetDraftIDs:fields:)`（服务层再判同款且未发布/归档，整批一次落盘）。价格整组、尺码表逐条重编 id 并清 productID、面料/描述整块；**绝不碰** name/images/variants/归属/状态；同款判定 seriesID 仅双方都明确时比较。
- **补录表单 = 一个表单管一个款式 + N 个颜色行**（09-23 需求 K）：`ShopCatalogDraftStyleForm`（`ColorRow`/`StyleInput`/`rows`/`applyStyle`/`applyColor`/`makeNewDraft`）→ `ShopCatalogDraftStore.applyStyleForm(sourceDraftID:style:colors:)`。一次 `persist` 内完成 新增/更新/移除，结果 `ShopCatalogStyleFormResult{updated,created,removed,skippedSettled}` 如实计数，禁假装整款都存好。
  · **款式名一处决议**：`resolveStyleName(explicit:source:)` 显式优先、否则按源草稿派生，再给所有颜色共用；**禁逐条派生** —— 新加颜色没有历史商品名可派生 → 空款名 → 商品名只剩颜色词 → 加一色变两款。多色必须填款名，单色可空。
  · **商品名 = 颜色名 + 款式名**，对存量草稿幂等（派生款名再组合回原名）；`applyStyle` 不替用户伪造 `designName`（没填就留 nil，靠 `styleNameFallback` 组合）。
  · **同款家族口径唯一**：`ShopCatalogDraftStyleForm.identity/isSameStyle/sameStyleFamily` —— 表单展示范围与 `applyStyleForm` 落盘范围**必须同源**，两处不一致会把「界面看不到」的草稿当用户删色而**误删**。（原私有的 `syncStyleIdentity`/`isSameStyleForSync` 已删。）
  · **移除颜色 = 删除其未发布草稿**（批次是归组记录故不连带删；颜色行就是草稿本身故要删），已发布/归档保留且计入 `skippedSettledCount`。
  · **图片与颜色强绑定链**：`ColorRow.imageRefs → draft.images`（asset id `asset-<草稿id前8位>-<序号>`，确定性幂等）`→ 每个 variant.imageAssetID = 本色主图`；前端详情页轮播 = 本商品 images（当前色）+ 同款其他色主图，切色读的就是它。
  · 尺码表 id 逐条重编（共享 id 会在发布时按 id 互相覆盖，最后一个颜色赢家通吃）。
- `CatalogProductDraft.fabric/styleDescription` 必须进 `publishOperationKey` 指纹，否则被「已恢复发布」吞掉。
- `colorWords` 必须含复合色（`生成色`/`粉紫色`），否则同款拆三款（长词优先）。

## 尺码表=款式级共享
- 读只走 `ShopCatalogStore.sizeChart/sizeRun(forProduct:)`；写只走 `ShopCatalogOps.applySizeChart`（每色一行，nil=清空整款）。禁 `sizeCharts.first{productID==}`、禁按色单存。
- `canonicalChart` 结构化优先，整款都没有才回退「仅原图」。
- 同款=`seriesID`+`designKey`；读含归档、写不含。
- 尺码轴必须判方向：用 `sizeLabels(of:)`，禁 `rows.map(\.label)`。

## 列表/归组/标题
- 数组是录入顺序：走 `AZIndexGrouping.sortedByName/groups`；`#`→A–Z（拼音）+ `localizedStandardCompare`；一页多类实体分栏索引。
- 同款不同色是独立 product，只展示层归组（`designName` 优先，缺省 `ShopCatalogSameDesignGrouper`）；实体管理只有 店家/系列 两 Tab。
- **同款商品集合唯一来源** = `ShopCatalogDesignPalette.sameDesignProducts(of:among:)`（同系列+同品类+同款式名+未归档）。标题「· N 色」/ 详情页「配色」行 / 轮播兄弟色都从它取，**禁在视图里再写一遍过滤**。
- **详情页「配色」行 = 同款颜色集合**（`store.designColors(forProduct:)`），**不是**本商品规格色。旧口径只读本商品规格色 → SPU/SKU 下只有自己那一色、纯名称命名时整行消失，而标题仍写「· N 色」（09-23 事故）。不变量：**配色行条数 == 标题的 N**。单商品贡献颜色要覆盖两形态：多规格色全列出；规格色为空则退回商品名颜色词（**不用整名兜底**）。
- **加购弹窗的「配色」区块**是「挑本商品买哪个色号」的**规格选择器**，仍读 `colors(forProduct:)` —— 与上一条语义不同，**禁合并**（会把别的商品色号塞进购买记录）。
- 标题=款式名+(多色)「· N 色」，共用 `ShopCatalogTitleResolver`；颜色走 `ShopCatalogColorPresentation.label`（规格色→名称颜色词→nil）。例外：心愿/尾款/衣橱**记录名必须带颜色**。
- 点菜页同款合并一张卡（颜色 chips）；价格双阶段 `ShopCatalogCardPricePhase`（预约窗口内默认预约价不可选；结束后双价并存才自选，默认现货）；口径经 `priceChoices/colorByProduct` 透传 `ShopCatalogWardrobeMergeView`。

## 价格：留空=清除，修正≠追加
- 草稿走 `effectiveReservationPrice/effectiveStockPrice`；预约价与现货价并存不互斥。
- 修正→`priceCorrection`（`correctCurrentPrice/clearPriceCorrection`，**不动 saleEvents**）；追加→只 append `CatalogSaleEvent`（`appendSaleRecord`，`startAt` 必填，**永不 remove/replace**，去重 `appendFingerprint`）；两者不共用逻辑。
- 修正**留空=清除**：按生效值预填、整快照提交；预约价清空时定金/尾款一并清。防线：`updatePublishedProduct` 传 nil 但已存修正 → 保留。
- `CatalogPriceArchive` 只读：修正优先否则回退历史；并列取 startAt 晚者、同时间取靠后者。
- 缺失一律「暂无」，禁 `deposit ?? 0`；补录命中既有商品两价都能继续录，禁抛「已收录/重复」。

## 图表
- 两卡**只消费同一 Plan**：`ShopCatalogChartPresentation.plan(...)`，禁某卡单独写 if。
- `sourceImage` 非空必须进 `.ready/.unavailable`，绝不静默 `.none`；解析 `ShopCatalogChartReference.resolve`，可用性 `ShopCatalogImageResolver.isUnavailable`，禁 `UIImage(contentsOfFile:) ?? UIImage()`。
- 归属：商品编辑页只登记本商品尺码表原图；预约价格表归**系列**；原图默认收起。OCR 走 `reconstructLineTexts`；手填走 `CatalogManualChartText`。

## 图表识别与录入（09-23 需求 M）
- **图片识别必须过质量门禁**：`CatalogChartExtraction.extract` = 多模态 Qwen-VL 优先 → 端上 Vision OCR 兜底 → `CatalogChartQuality.issue` 门禁。命中任一即判失败：列数<2 / 无数据行 / 填写率<0.4 / 全表无数字 / 乱码词元 / 行标签=列名 / 混入说明文字。**禁**把未过门禁的结果写进任何输入框。
- **失败口径**：输入框恢复识别前快照（一个字符都不写）+ 常驻红字 + 弹窗「解析失败，请手动录入」，原图引用保留。禁「识别成功但结果是垃圾」这种弱成功定义。
- **粘贴与模型回复共用一套解析**：`CatalogManualChartText.parsePastedText`（列名行判定=不含冒号+≥2 段+无数字；兼容 标签:值 / 无冒号逗号行 / 制表符 / Markdown / 全角标点；表标题尾注丢弃）。预览必须与保存链路 `parseColumns→parseRows→normalized` 同源，**预览即落库**。
- 入口组件 `ShopCatalogChartPasteButton`（自带 sheet）挂在价格表 + 四处尺码表编辑器。
  **09-23 需求一后图片识别入口已整条移除**（用户：频繁报错 + 常驻霸屏）：价格表只走
  「粘贴文本录入」+ 列名/行文本/单位手填；`CatalogChartExtraction` 在 App 内已**无调用方**
  （文件与 24 个测试按「其他保留」未删）。上面的门禁口径是该模块自身的契约，**别再借它加回入口**。
  另：`priceChartImageText` state 必须留在系列编辑页——它承载既有 `priceChart.sourceImage`，
  删掉会让「打开→保存」把用户已上传的原图静默抹掉。

## 删除守卫
- `previewProductDeletion` 与 `deleteProducts` 共用 `planProductDeletion`；**整批只写一次覆盖层**，禁循环调单品删除。守卫：种子、被引用商品（含软删 Clothing）给原因；级联清 variants/sizeCharts，销售事件保留；部分成功绝不静默。
- 批次删除只动 `shop-catalog-batches.json`，**绝不连带删草稿**；视图读 `draftStore.batches`（@Published）。
- 草稿箱删除单条/多选共用 `deleteDrafts(ids:)`。
- 禁顺手删旧能力：`MainTabView` tab4 仍 `TimeHallView()`；`TimeHallWardrobeQuickInserter` 被复用。

## 币种与发布幂等
- `CatalogCurrency` cny/jpy/unknown 挂 SaleEvent/PriceCorrection.currency；旧 JSON 缺键=**unknown（不默认 CNY）**；两侧都 unknown 仍算差价；指纹含币种；跨币种抛 `crossCurrency`。
- 幂等 ID = FNV(草稿ID｜类型｜**该类型自己的**价格指纹)；半成功恢复要全部命中；恒「先写覆盖层、后写草稿回执」。坏文件留原件+备份+`isBlockedByCorruptFile` 阻止写回。

## 系列「发售阶段」（09-23 需求二）
- `CatalogSeries.salePhase`（预约中/预约已结束/现货，**Optional**，nil=未声明=沿用档期推导）+ `reservationEndAt`。
  两个字段都必须 Optional，否则旧覆盖层 JSON 缺键解码抛错、整个系列列表打不开。
- **自动流转 = 读取时判定**，不写定时任务、不回写存储：`CatalogSeriesSalePhaseResolver.effectivePhase`
  （声明为预约中且 `now > reservationEndAt` → 预约已结束）。回写会覆盖运营声明、要动覆盖层写入口，不做。
- 详情页 `purchasePhase(for:)` 优先链：**系列声明 → 未声明才落回销售事件档期推导**（存量零变化、无需迁移）。
- 表单：只有「预约中」显示 `DatePicker`；选其它阶段**不清除**已录入时间（那是事实，不是临时输入）；
  时间已过只给红字提示，**不拦保存**（已过本身合法，拦下来与自动流转矛盾）。
- **数据保留（用户标注最重要）**：保存发售阶段只写这两个字段，**一个价格字段都不碰**；
  详情页价格档案卡片不按阶段渲染。回归锁 `testSavingSalePhaseKeepsPriceChartOnDisk` 真读 JSON 核对。
- ⚠️ **需求二与需求 N 冲突点（用户已裁定，别改回去）**：预约已结束**只改引导、不剥夺能力**——
  主按钮 =【加入衣橱】(全款)，【加入心愿尾款】(定金+尾款) 收进「其他记账方式」折叠区，
  **禁止**改成隐藏或置灰。`prefersFullPayment` 是引导口径，代码里不得出现能力门禁。

## 加购记账与衣橱标题（09-23 需求 N）
- **金额一律自动读取，用户零输入**（用户硬要求）：`ShopCatalogReservationSheet` 内**不存在**金额输入框；
  预约价 / 已付定金 / 待付尾款 / 入橱金额全取 `CatalogPriceArchive`（`currentReservationPrice` / `currentDeposit` / `currentBalance`）。
- **待补尾款取数唯一口径 `ShopCatalogWardrobeAmount.pendingBalance`**：**读后台录入的尾款 `currentBalance`**
  → 后台没录才回退「预约价 − 已付定金」；负数归零。**落库（`makeDraft`）与弹窗预览（`pendingBalance`）必须共用**，
  分开算迟早「弹窗显示 302、落库写 300」。后台三价不自洽（定金 + 尾款 ≠ 预约价）时**不静默**：
  备注写「以后台录入为准」，**禁**写算不平的 `A + B = C` 等式；入橱总额仍取后台预约价（分支 B 口径）。
  （09-23 复验修正：首版是 `event.price - depositAmount` 现算，把后台录入的尾款丢了。）
- 状态机唯一口径 `ShopCatalogWardrobeEntryPolicy`（nonisolated）：`wishlist / depositPaid / fullPaid`。
  按钮矩阵：预约中 = 加入心愿 / 付定金加购 / 全款加购；预约已结束 = 加入心愿尾款 / 加入衣橱。
- `PriceMode.fullReservation` = 全款预约价：`deposit = event.price, balance = 0, isDepositPlan = true`
  → `isFullPaymentReservation`（卡片「全款」）+ `pendingFinalPaymentAmount == 0`（**绝不生成尾款任务**）。
  已付定 = `isFinalPaymentPlan`。别再拿 `isDepositPlan` 当「在心愿尾款中」的判据。
- 衣橱**记录名**走 `ShopCatalogWardrobeTitle.recordName`（三段式 `[系列名] [款式名] [颜色]` + 四档降级），
  **不要**改回 `product.name`、也不要与商品标题 `ShopCatalogTitlePresentation` 合并（两者分工不同）。
  补充口径：款式名含系列名时不重复前置；没点颜色时取后台规格色第一个。
- 状态标签唯一口径 `ShopCatalogWardrobeStatusTag.chips`（`全款 / 已付定 / 转单 / 已售出`，转单与付款标签可并存）。
  `owned` 普通记录**不挂付款标签**（否则全部存量衣橱被刷上「全款」）。
- **草稿新增字段一律 Optional**：`ClothingEditDraft` 是 `Codable`，合成 `Decodable` 对非 Optional 走 `decode`，
  旧落盘草稿 JSON 缺键会**解码抛错、草稿丢失**（`isResaleTransfer: Bool?` 就是这么定的）。
- 测试：`ItemManagerTests/ShopCatalogWardrobeEntryTests.swift`（21 项）。
