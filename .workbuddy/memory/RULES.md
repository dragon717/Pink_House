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
- **Bundle 种子已清空（09-24）**：`shop-catalog.json` 是空壳，全新安装零店家。测试要种子语义 → `ShopCatalogSeedFixture.makeStore()`（@MainActor；AG/UNNIQ 完整子图注入 `ShopCatalogStore(baseCatalog:)`），禁再假设 `.shared` 里有种子数据。

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
- **分区/分组顺序禁止用 `Set`/`Dictionary` 遍历序派生**（09-25 事故：点菜页分区乱跳）：`Array(Set(...))` 的顺序取决于**进程级随机哈希种子**，每次冷启动都换排法，表现为「商品列表不断重新排序」。唯一确定性来源是 catalog 数组的**录入顺序**（持久化、跨启动稳定）。`ShopCatalogStore.categories(inSeries:)` 已收口为：固定品类（`canonicalCategoryOrder` 除「其他」）在前 → 自定义分类按商品**首次出现序** → 「其他」垫底；新增任何分组列表都必须走这类「显式顺序源」，回归测试在 `ShopCatalogStoreTests.testSeriesCategoriesCustomOrderIsEntryOrderNotSetOrder`。

## 商品改名 = 款式级（09-24 需求：改名后什么都没变）

**根因（两处叠加）**：① 标题只读 `designName`；② 发布路径无条件把 `designName` 写成
**非空显式值**（`resolveDesignName` 永不返回 nil，`baseName` 兜底回退整名）
→ **`name` 被永久遮蔽**，`baseName(for: name)` 那条派生分支永远不执行。
「只改 `name`」= 界面上一个像素都不动（用户三张截图：商品管理改名「黄色蜜糖邦尼背心裙」
→ 点菜页标题仍是「背心裙」）。

- **唯一口径**：`ShopCatalogProductRename.plan(edited:basedOn:among:profiles:)`（`nonisolated` 可单测）。
  弹窗预览与落盘**共用同一份 plan**；写入口 `renameProduct(productID:newName:newCategory:)`。
- 名称 → 款式名 = `baseName(for:)` 剥颜色词（与录入端 `draft.name = 颜色 + 款式名` 同口径）；
  「名称」字段继续是**完整 SKU 名**（可含颜色词）。
- **必须扇出整款**（同系列+同品类+同款式名，**含已归档**）。只改一色 = 拆组 + 款式档案孤儿 + 尺码表范围塌成 1 行。
- 兄弟名字走**定向替换**（旧款名→新款名），颜色词与其位置保留。
  ⚠️ `colorWord(in:)` **≠** `ShopCatalogColorPresentation.derivedLabel`：后者守卫「剥离后须≠原名」，
  名字**恰好就是**一个颜色词（「粉色」）时返回 nil —— 「能不能当颜色标签」用它对，
  「改名别把颜色弄丢」必须用 `colorWord(in:)`。
- **品类也是款式级**（`designKey` = 品类|款式名）→ 随款式一起改。
- **名称没被改动时禁止重新派生款式名**（存量存在「款式名≠名称剥颜色词」的人工命名）。
  ⚠️ 所以 `plan` 必须有独立的 `basedOn:` 基准入参：深度编辑传进来的 `edited` 里 `name` 已是新值，
  拿它自己跟自己比，「改了名」会被判成「没改名」（**本轮实测踩到，两个端到端用例红**）。
- **款式档案 `CatalogStyleProfile.id` 就是款式键** → 改名必须**改键**（删旧 id + 写新 id），
  否则面料/款式描述变孤儿（界面表现＝「改个名字面料就空白了」）。目标键已有档案时**无损合并**
  （目标值优先、补空缺字段），不留两条同键行（读取侧是「取最后一条」＝随机胜负）。
- **尺码表无需数据迁移**（行按 `productID` 存），但 `updatePublishedProduct` 有**两条顺序死约束**：
  ① `applyRenamePlan` 必须在 `applySizeChart` **之前**（范围由 `writeTargetCatalog` 按覆盖层现算）；
  ② `applySizeChart` 必须传 `renamePlan.products.first`（**改名后**那一份）—— 局部 `updated`
  的 `designName` 还是旧值，拿去比款式键会一个新键都匹配不上。
- 衣橱/心愿记录名是**加入时的快照，不跟着改**（`Clothing` 按 `catalogProductID` 引用，改名不断链），
  但 toast 必须**如实报条数**（`ShopCatalogReferenceGuard.referencedRecordCount`）。
- 改名弹窗已上移到 `ShopCatalogSeriesProductsView` **页面级**（行视图会被列表重建，
  挂行上的弹窗 `@State` 会归零 → 名称输入到一半就丢）。
  **`ProductManageRow` 上原本的 6 个模态已整组上移**（改名 alert + 深度编辑/价格修正/追加销售记录 3 sheet
  + 归档/删除 2 dialog）：行现在**只渲染 + 发意图**（`onEditBasics` / `onSheet` / `onConfirm`），
  模态目标用两个 `Identifiable` 枚举 `ProductRowSheet` / `ProductRowConfirm` 带上**商品本身** ——
  禁再退回「一个 Bool + 另存一个商品」的双状态写法（两者不同步就会弹出**别的商品**的表单）。
- 回归锁：`ItemManagerTests/ShopCatalogProductRenameTests.swift`（纯逻辑 18 例 + 端到端 6 例）。
  端到端断言必须**按 id 收窄**、不按名字（`publish` 的返回值是给人看的摘要，不是 id）。

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
- `previewProductDeletion` 与 `deleteProducts` 共用 `planProductDeletion`；**整批只写一次覆盖层**，禁循环调单品删除。守卫（09-25 需求一后）：**只剩种子不可删**；**用户引用不再拦截删除**——用户衣橱/心愿记录是加入时快照，删除发布内容不影响它们（数据独立），涉及条数走 `preservedRecordCount`（单品 `deleteProduct` 返回 Int）如实汇报；级联清 variants/sizeCharts，销售事件保留；部分成功绝不静默。`referencedOnlyArchive` 错误与 `.referencedByUserData` 拦截原因已删。
- **`ShopCatalogReferenceGuard.referencedRecordCount` 谓词必须用存储属性 `deletedAt == nil`，禁用 `isDeleted`**——后者谓词下推会抛「No eligible connection available」（09-25 实测崩溃）。
- 批次删除只动 `shop-catalog-batches.json`，**绝不连带删草稿**；视图读 `draftStore.batches`（@Published）。
- 草稿箱删除单条/多选共用 `deleteDrafts(ids:)`。
- **店家强制删除（09-24，09-25 放宽引用拦截）**：`previewShopForceDeletion`/`forceDeleteShop` 共用 `planShopForceDeletion`；级联 店家→系列→商品→规格/尺码表；**种子实体靠墓碑**（`ShopCatalog.removedShopIDs/SeriesIDs/ProductIDs`，合并层 `applyTombstones` 排除，规格尺码表按商品连坐）；被引用商品**照删**，汇报字段 `referencedProductNames` + `preservedRecordCount`（商品已删、用户记录按快照保留，两件事都说清）；销售事件保留；同 id 重录走 `upsertEntity` 清墓碑（复活语义）。
- `ShopCatalogStore.rebuildMergedCatalog`：基底 nil 且覆盖层 nil 时 **catalog 必须保持 nil**——置非 nil 空对象会把 `.shared` 的 `loadFromBundleIfNeeded`（`guard catalog == nil`）永久短路，种子消失（09-24 踩到）。
- 禁顺手删旧能力：`MainTabView` tab4 仍 `TimeHallView()`；`TimeHallWardrobeQuickInserter` 被复用。

## 尾款阶段同步与大致时间估算（09-25 需求二/三）
- 窗口解法**唯一口径** `CatalogBalanceDueApproximation.declaredWindow(of:anchor:)`：exact 直接用 `balanceDueAt/EndAt`；approximate（上旬/中旬/中下旬/下旬，同义 月初/月末/月底）→ 估算成**固定具体日期**（上旬→10日、中旬→20日、中下旬→25日、下旬→月末最后一天；显式月份是硬约束、已过顺延一年；无显式月份 = 锚点+1个月）。估算**不掺 `Date()`** → 幂等固定；无旬关键词/缺锚点 → nil 不猜。两消费方：`ShopCatalogWardrobeDraftBuilder.makeDraft`（加购，锚点 `series.reservationEndAt ?? event.endAt`，禁加购当天占位）与 `ShopCatalogWardrobeBalanceSync`（同步，锚点仅 `series.reservationEndAt`）。
- 同步只动「尾款中」（`effectivePhase == .balancePending`）系列下 `isFinalPaymentPlan` 的 Clothing 的 `finalPaymentDate/EndDate` + 备注留痕；**金额一个不碰**；商品已删 → 跳过（数据独立）；全款/已付清不进扫描。触发点：`ShopCatalogBrowseView.task`（云同步后）+ 批次详情页 `saveSeriesConfig` 保存成功后。
- `ShopCatalogWardrobeBalanceSync` **不持有默认 ModelContext**，context 必须调用方显式传（防单测碰生产容器）。

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
- 测试：`ItemManagerTests/ShopCatalogWardrobeEntryTests.swift`（34 项）。

## 加购分支按阶段区分 + 现货阶段两个全款口径（09-24）

- **分支候选唯一口径 `ShopCatalogWardrobeEntryPolicy.options(phase:hasReservationPrice:hasStockPrice:)`**：
  预约中 / 预约已结束 / 尾款中 = `[depositPaid, fullPaid]`（**两者都以预约价档案取数**，
  没有预约价就一条都不给）；**现货 / 中性 = `fullPaymentOptions`，只给全款、两个价格口径**
  （`fullPaid` 按预约价 / `fullStockPaid` 按现货价），**缺哪个价格档案就不出哪个口径**。
  ⚠️ 视图曾自己写死 `[.depositPaid, .fullPaid]`、策略改了界面不动；现在选择段候选**必须**取自这里。
- **`defaultChoiceOption(phase:hasReservationPrice:hasStockPrice:)` 的返回值同时是「要不要弹选择弹窗」的判据**
  （nil = 不弹，走原路径）：预约中 / 尾款中 → `depositPaid`；预约已结束 → `fullPaid`；
  **现货 → `fullStockPaid`**（没有现货价才退回 `fullPaid`）；预约未开始 → nil（加入心愿 = 开售提醒）。
  **这四个阶段都不得静默默认一种付款方式直接落库**，也不能隐藏 / 置灰任何候选。
- **全款两个口径的落库完全同构**：`PriceMode.fullReservation`（预约价）与 `PriceMode.fullStock`（现货价）
  都是 `deposit = 金额 / balance = 0 / isDepositPlan = true` → 衣橱标签都是「全款」、
  `pendingFinalPaymentAmount == 0`、**都不生成心愿尾款任务**；**唯一差别是金额取自哪份价格档案**。
  备注必须写「按预约价 / 按现货价」（否则事后无法分辨这笔全款按哪个价记的）。
  `.fullStock` 缺现货价档案时**返回 nil**（不静默记 0 元）。
- **`insert` 回写 `catalogSaleEventID`**：预约口径（`.reservation` / `.fullReservation`）→ 预约记录；
  `.fullStock` → **现货**记录；`.stock` / `.wishlist` 不写。
- **文案按阶段取**：`choiceTitle(for:phase:)` —— 现货阶段没有「预约」这个动作了，
  两个选项是**价格口径**，标题必须是「按预约价全款加入 / 按现货价全款加入」，
  **不得**沿用「预约价全款预约」；段落标题同理由「加入方式」改为「全款计价方式」。
- **弹窗 `effectiveOption` 必须做候选自洽防御**：选中的项不在当前候选里（阶段 / 价格档案变了）
  就退回候选第一项，否则确认按钮会按一个界面上看不到的口径落库。
- **需求「定金+尾款 → 心愿尾款 → 付完尾款自动进衣橱」= 同一条 `Clothing` 的状态变化**：
  `isDepositPlan + balance > 0` → `isFinalPaymentPlan`（**= 心愿尾款列表的筛选口径**）
  → `WealthSavingLedger.recordFinalPayment` → `markFinalPaymentCompleted`（`isDepositPlan = false`）
  → `reservationKind == .owned`（= 衣橱已拥有）。**收尾不清 `balance`（那是历史值）**，
  所以判「付没付清」只能用 `isFinalPaymentPlan` / `shouldShowFinalPaymentPayoffAction`，
  **禁止**用 `pendingFinalPaymentAmount`（对已收尾记录仍返回历史尾款）。
- 文档：`docs/加购分支与现货阶段全款口径_需求实现说明.md`。

## 系列配置一站式 + 尾款中/尾款时间（09-24 需求）

- **三项系列配置只有一处存储**：`CatalogSeries` 的 `salePhase/reservationEndAt`、`cover/description`、
  `priceChart`。批次/单品只持 `seriesID` **引用、没有副本** —— 所以「写一次 = 全批次 + 全单品同步生效」。
  保存唯一入口 `ShopCatalogDraftStore.saveSeriesConfig(_:batchID:)`（单点写系列 + 未自报系列草稿的链接归一，
  返回实际同步条数；自报系列的草稿**永不被覆盖**）。
- **两个入口必须共用一份实现**：`Views/ShopCatalog/ShopCatalogSeriesConfigSections.swift`
  （`ShopCatalogSeriesConfigSections` + `ShopCatalogSeriesConfigForm`），批次详情页与系列编辑页都用它。
  **禁止**各写一套 Section：各写一套必然出现「一边填、另一边一保存就丢」。
  边界：`form.apply(to:)` **只写自己负责的字段**（名称/年月/季节归系列编辑页），否则批次页保存会覆盖基础信息。
- **发售阶段四态**：未设置 / 预约中 / 预约已结束 / **尾款中（`balance_pending`）** / 现货。
  rawValue 只追加不改（旧覆盖层要继续可解码）；`allCases` 顺序 = Picker 顺序。
- **尾款中流转（读取时判定，不做定时回写）**：预约中 →（过 `reservationEndAt`）预约已结束 →
  （**具体**尾款时间到）尾款中。**尾款中的出口只能由运营声明**（改「现货」）——
  别造「尾款是否收齐」的判据（会把「有笔尾款还没记」误判成收齐）。
  显式声明的「尾款中/现货」不被时间改写（运营声明最优先）。
- **尾款时间三字段全 Optional**：`balanceDueKind`(approximate/exact) + `balanceDueText`（大致原文，
  **故意不解析成日期**）+ `balanceDueAt`（具体时刻，**唯一**能驱动自动流转的字段）。
  规范化时**切换粒度清空另一种**；「未填写」是显式清空路径。校验：大致非空且 ≤30 字；
  具体**严格晚于**预约结束时间（无基准不比对）、已过不拦。**非必填**。
  唯一口径 `CatalogSeriesBalanceDue`（纯逻辑 nonisolated + 文案 @MainActor 扩展）。
- **加购引导**：尾款中 **默认「加入心愿尾款（定金+尾款）」**（补尾款的动作），
  `ShopCatalogPurchasePhase.balancePending` 必须是独立枚举值，**不得塌缩成 `reservationEnded`**
  （否则默认选中会变成「预约价全款预约」）。两个选项仍同屏可选，**能力不剥夺**（09-23 裁定继续成立）。
- **`ensureAttributionEntities` 与 `publish` 同源**：既有 id → 同名去重 → 新建，且**幂等**
  （重复点击不建重复系列）。批次详情页要配置系列必须先有系列实体 —— 走这里，别自己造 id / 自己建系列。
- 测试：`CatalogSeriesBalanceDueTests` / `ShopCatalogSeriesConfigFormTests` /
  `CatalogSeriesBalanceDuePersistenceTests` / `ShopCatalogBatchSeriesConfigSyncTests`；
  阶段流转在 `CatalogSeriesSalePhaseResolverTests`（已含 `allCases.count == 4` 与尾款中流转用例）。

## 系列年月通道 + 预约期/尾款期区间（09-24 需求五）

- **「只有它不带月份」的根因**：`CatalogSeries.month` 的写入通道原先只在系列编辑页，批次/草稿链路
  只承载 `newSeriesYear`，而 `publish` / `ensureAttributionEntities` 建系列时也只写 `year:`。
  修法三层，**缺一层都不算修好**：
  ① 通道 `CatalogProductDraft.newSeriesMonth` → `CatalogBatchEntrySession.newSeriesMonth` →
  `applyBatchAttribution(newSeriesMonth:)` → `ShopCatalogDraftStyleForm.StyleInput`；
  ② 写入：建系列时必须写 `month`；③ 存量补全（下条）。
- **存量补全只填空、绝不覆盖**：唯一判定 `ShopCatalogDraftStore.seriesCompletingYearMonth(_:year:month:)`
  —— 系列无年 → 年+月一起补（**年月同源**）；同年缺月 → 只补月；**已有月份不动**、
  **年份不一致不补月**（同名不同年 = 另一条系列）。三个触发点同一份实现：
  `ensureAttributionEntities` / `publish`（含 `recoverPendingPublish`）/ 批次详情页显式入口
  `completeSeriesYearMonth`（返回「是否真的写了盘」，false = 无需补全，不假装成功）。
- **`publishOperationKey` 用 `CatalogProductDraft.yearMonthKey(year:month:)`**：只有年份时输出
  `"2026"`、都没有 `"-"` —— 与旧实现**逐字相同**，所以存量已发布草稿不会被判成「内容变了」重发；
  带上月份才是新指纹。`saleEventKey` **不含年月** ⇒ 事件 ID 不变 ⇒ 「补月再发布」走
  `recoverPendingPublish` 的收尾路径、**不重复生成销售记录**（该路径也必须补年月，否则月份永远落不了库）。
- **年月录入唯一口径 `CatalogYearMonthText`**（`2026` / `2026-10` / `2026年10月`）：批次详情页与
  草稿编辑器共用；**解析失败不改动已存值**（打字途中「2026-」是半成品，擦掉已填月份会让输入框与
  存储来回打架），只给红字；清空文本 = 显式清除；换系列时输入框要跟着回填该系列的年月。
- **预约期 = 开始 + 结束，尾款期 = 开始 + 结束**（需求五）：新增 `reservationStartAt` /
  `balanceDueEndAt` / `balanceDueEndText`（**全 Optional**，旧 JSON 零迁移）。
  **「开始」必填、「结束」选填**：开始是自动流转唯一依据；结束必填会让存量系列一打开表单就报错
  （「什么都没改也保存不了」），给默认值则是替运营编事实。表单用显式 `Toggle`
  （「已设置预约开始时间」/「已设置尾款结束时间」）声明，与加购弹窗「已公布尾款时间」同一写法。
- **`balanceDueAt` 的 Codable key 不得改名**（改 = 存量覆盖层字段全丢），它的语义本来就精确等于
  「开始收尾款」，直接当区间起点。校验：预约 `start > end` 拦（相等放行，只在预约中校验）；
  尾款大致起止各 ≤30 字、具体起点严格晚于预约结束、结束不得早于起点（同日允许）。
- **结束时间不驱动任何流转**：流转仍只由「预约结束时间」＋「尾款**开始**时间」决定；
  过了尾款结束时间只给橙色提示（「若已收齐可改为现货，系统不会自动改」）——出口只能是运营声明。
  **不新增「预约未开始」阶段**（开始时间在未来时仍是预约中），避免动 `allCases` 与所有 `switch`。
- 展示：`CatalogSeriesBalanceDue.displayText(of:)` 前缀随内容变（只有开始 → 「尾款时间：…」，
  声明了结束 → 「尾款期：起 — 止」）；预约期走 `CatalogSeriesReservationWindow.displayText(of:)`。
- 测试：`ShopCatalogSeriesWindowTests.swift`（3 类：预约期 10 / 尾款期 14 / 配置表单区间 6）、
  `ShopCatalogSeriesYearMonthChannelTests.swift`（2 类：补全判定+指纹 9 / 存储链路 7）。
  **⚠️ 断言「是否已开始 / 是否已过期」必须用相对当前时间的日期**，写死的时间戳会随真实日期漂移成过去。

## 表单「编辑中快照」与 sheet 呈现位置（09-24 需求十四）

事故：切后台 / 跳系统相册 / 切到其他应用再回来，表单**全部内容消失、页面重置为初始状态**。

- **`.sheet` 一律不许挂在 `ForEach` / `List` 的行视图上**。`Form`/`List` 的行是惰性 + 可复用的，
  切后台、跳系统相册、切到其他应用返回**都会让列表重新布局** → 行视图重建 →
  挂在行上的 sheet 内容视图连同它全部 `@State` 一起归零。
  正确写法：**提到页面级稳定容器上只挂一次**；多个 sheet 用 `enum XxxSheet: Identifiable` 合并
  （同页多个 `.sheet` 绑同一状态是未定义行为，5 行就有 5 个 presenter）。
  页面现有实现：`ShopCatalogOpsView.OpsSheet`、`ShopCatalogOpsManageView.editingSeries`。
- **靠 `@State` 守卫防「状态被重置」是无效的**：`guard !loaded` 里的 `loaded` 自己就是 `@State`，
  视图一重建就归零 → 守卫直接失效。**守卫和被守卫的东西在同一个生命周期里，挡不住「生命周期结束」。**
- **要恢复的东西必须落盘**：`ShopCatalogFormSnapshotStore`（目录 `form-snapshots/`）+ 页面侧
  `ShopCatalogFormSnapshotKeeper<Snapshot>`（`@MainActor` 值类型，放 `@State`）。四条口径：
  ① 变更 **0.5s 防抖落盘**（**相册场景的唯一兜底** —— 相册返回不走 `onDisappear`）；
  ② `scenePhase != .active` / `didEnterBackgroundNotification` / `onDisappear` → 立即 `flush`；
  ③ `onAppear` → `restoreOrDiscard`（与「按存储值填出的默认态」**逐字段相同就丢弃**，不弹无意义提示）；
  ④ 保存成功 → `commit`（清快照；此后关页的 `flush` **只清不写**，否则下次会恢复出刚保存的旧值）。
- **恢复必须可见 + 可放弃**（`已恢复上次未保存的编辑` + `知道了` / `放弃修改`），不许静默塞回旧值。
- **快照 `scope` 必须带实体 id**（批次 id / 草稿 id / 系列 id），换实体一律丢弃，否则串页；
  `scope` 为空串时所有读写跳过。
- 快照的读 / 写 / 坏文件**一律不抛错**（它是兜底，坏了不能挡住正常录入）；
  文件名 = 白名单化 + FNV-1a 哈希后缀（避免不同 id 被擦成同名字符而串页）。
- 快照 `Codable` 载荷里的日期**用整秒**：`ShopCatalogJSONCoding` 走 ISO8601 会截掉小数秒，
  用 `Date()` 造测试数据会让相等断言在往返后必然失败（不是缺陷，是口径）。
- **`.onChange(of: 某个 state)` 回填不要用来做「派生」**：它对**程序化赋值**同样触发 ——
  快照恢复出来的年月会被「按系列重新推导」立刻抹掉（表现为「恢复了但字段没了」）。
  要么挂在控件自己的 `Binding` setter（`ShopCatalogBatchDetailView.seriesSelection`），
  要么在程序化赋值处显式回填一次。
- 页面载荷：`ShopCatalogBatchConfigSnapshot` / `ShopCatalogDraftFormSnapshot` / `ShopCatalogSeriesEditSnapshot`；
  为了能整份落盘，`ShopCatalogSeriesConfigForm` 与 `ShopCatalogDraftStyleForm.ColorRow` 加了 `Codable`
  **遵循**（只加遵循，未增删字段、未改 key）。
- **尚未收口**：`ShopCatalogShopEditSheet`（店家）与商品编辑页的 sheet 仍挂在行上，同类反模式待处理。
- **验收断言口径**：这类「状态有没有丢」的交互验收一律写**「场景前快照 → 场景后逐字段比对」**，
  **不要写死字段清单** —— 页面上的字段会合法出现 / 消失（系列配置段出现后 `seriesID` 不再为空，
  `年月（选填…）` 输入框就**合法隐藏**），写死会把它误判成「状态丢失」。
  验收命令与三个驱动侧坑见 `docs/表单状态丢失_根源修复说明.md` §6.4 / §6.6。

## 界面遮挡与底部 Dock 避让（09-24 全量排查）

**根因**：`MainTabView` 的底部导航 Dock（`customTabBar`）放在 body 的 `ZStack` 里叠在
`contentView` **之上**，**不是系统 TabBar、不参与安全区计算**。所以「给 Dock 留底部空间」
是每个可滚动页面自己的责任 —— 漏一个就有一个页面最后一行被吞。
`BookHouseSmallWorldView` / `SmallWorldView` 是固定舞台，无滚动容器，天然不触底。

**唯一口径**：`Views/Components/BottomDockAvoidance.swift` 的 `avoidingBottomDock()`。
- 高度只有一处：`LegacyCustomTabBarLayout.floatingSurfaceBottomInset`
  = 56(Dock 高) + **max(2, 4)**(贴底；**取的是 max，不是 WithSafeArea 的 2**) + 12(间隙) = **72**，
  由 `MainTabView` 经 `\.customBottomNavigationAvoidanceInset` 下发。页面**不写数字**。
  （曾把 72 误记成 70 —— 那种「差 2pt」的笔误会让净空算错，改这块务必回读 `MainTabView` 常量。）
- **绝不再判断系统版本**。旧实现 `legacyCustomTabBarAvoidanceInset`（`AdaptiveSettingsView` 与
  `WealthView` **各有一份**）在 iOS 26+ 直接 `return 0` → 全部设置页 + 安财页在新系统上
  底部预留恒为 0。两份都已删除，回归锁 `ItemManagerTests/BottomDockAvoidanceTests` 扫源码树禁止复活。
- 在 tab 之外（sheet / fullScreenCover）环境值退化为 0，误加无副作用。
- **不要和自带贴底操作条叠加**（`ShopCatalogSeriesMenuView` 的 `safeAreaInset` 选择条）；
  尾部已有 `padding(.bottom,N≥72)` 的页面（`WardrobeView` 100 / `DepositPlanView` 100 /
  `ClothingDetailView` 80 / `ThemeSkinStoreView` 126）不要重复加。
- **只用 `List`/`Form`/`ScrollView` 根容器**；`Group` 上挂会作用到每个 child（回收站 4 个 List 共用一处，
  但书架 `bookGridContent` 的 Group **不能**挂 —— 正常态子视图 `BookGridView` 自带避让，会双倍）。

**模态页一律不改**（浮在 Dock 之上）：`ShopCatalogSeriesMenuView`(sheet)、`MoneyCountingView`(fullScreenCover)、
各种 `*Sheet` / `*Picker` / `Alert`。判断模板：**上溯它到底是被 push 还是被 modal 呈现**。

**Dock 几何（实测）**：iPhone 18 Pro 屏高 874、底部安全区 34 → Dock 胶囊占 `[782, 838]`；
避让 72 后内容底边落在 `768`，比 Dock 顶边高 **14pt**。截图判「有没有被吞」就量这两个数。
落点基数：源码里 `.avoidingBottomDock()` 共 **35 处 / 28 个文件**（剥离注释后统计）。

**同类但成因不同的第二类遮挡 —— 浮层与卡片顶边重叠**（商品详情轮播）：
卡片靠 `.offset(y:)` 上提覆盖图片下沿是**有意设计**，但轮播里**底对齐**的浮层（颜色胶囊、分页胶囊）
会落进同一条覆盖带。算法：`卡片顶边 = 轮播底边 − (上提量 − VStack 间距)`，
浮层底部留白必须 > 这个值 + 视觉间隙。几何常量收口在 `ShopCatalogProductView`
（`cardLiftOverCarousel` / `cardStackSpacing` / `carouselOverlayBottomInset`），
两个浮层**必须共用同一个底部留白**（原来一个 0、一个 12，本身就没对齐）。

**验收要点**：这类问题的主观感是「元素被吞」，单测覆盖不到 —— 必须模拟器真交互 + 截图量几何。
Bundle 种子已空壳，验收前把 `ShopCatalogSeedFixture.jsonString`（+ 补足数量让列表溢出屏幕）
**注入构建产物**的 `shop-catalog.json`（改产物、不改仓库资源），再 `build-for-testing` →
注入 → `test-without-building`（顺序不能反，重新构建会把种子覆盖回去）。

**⚠️ 本机内存是硬约束（09-24 实测卡了一整天）**：`sysctl vm.swapusage` 总 7G，常年已用 6G+。
- `xcodebuild test`（**不是** `test-without-building`）会跑 `PruneExplicitPrecompiledModules`，
  把显式模块缓存清掉 → 触发**整模块全量重编**（441 个 Swift 文件一次 `SwiftEmitModule`），
  单进程要几 G → swap 打满 → **静默卡死**（日志停在 `SwiftEmitModule`、产物目录也不再变动，
  但进程还在，看起来像「慢」）。判据：`wc -c <log>` 与 `find build/DerivedData -newermt`
  **双双静止 5 分钟以上**才算挂；只看时间长短会误杀。
- 省内存顺序：**先只跑 `build-for-testing`（且先 `xcrun simctl shutdown all`，模拟器自身吃 2–4G）
  → 编完再启模拟器 → 再 `test-without-building`**。模拟器与编译器同时在场是最容易崩的组合。
- 别在编译期间改源码（构建产物与源码就不一致了）；只改**注释**不影响行为，但仍要留意。
- 长任务必须交由工具的后台机制托管；`nohup … &` 在本环境会随命令结束被回收（日志 0 字节、
  进程消失，看起来像「构建秒退」）。
