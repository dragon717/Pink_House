# Pink_House 硬规则（红线 + 索引）

> **本文件只放「最容易违反的那一句」**；完整规则表、函数口径、事故经过见同目录 **`RULES.md`**（按主题分节）与 **`YYYY-MM-DD.md`**。
> 动某个模块前，先按下面括号里的节名去 RULES.md 读那一节。
> 构建 / 测试 / 验收命令见 skill **`pink-house-xcodebuild-acceptance`**；跨平台抽包与公共包边界见 skill **`ios-local-spm-package-extraction`**。

## 红线（一条一句）

- **测试隔离**（§测试隔离）：单测宿主 = 主 App，`FileManager.default` 就是**用户真实沙盒** → 落盘测试必须 `ShopCatalogStorage.useTemporaryForTesting()`，禁碰生产路径；`.shared` 跨套件累积，setUp 要 `loadDrafts()`、断言只比前后快照或按 `batchID` 收窄。
- **启动与方向**（§启动/横屏/「打不开」）：`INFOPLIST_KEY_UILaunchScreen_Generation` 必须 `NO`（YES = 空字典 = 深色纯黑，被误判「打不开」）；方向只由 Info.plist / pbxproj 的 `UISupportedInterfaceOrientations[_iPhone]` 决定。
- **构建验收**（§环境/工具）：destination 写 UDID `FA7332BE-B29E-4879-A139-C68A24314DB1`（写 `name=` 会 exit 70）。
- **搜索**（§环境/工具）：一律 `grep -E` / `-F`（BSD 禁空交替，`(a|b|)` **静默不过滤**）；搜中文兼搜 `\uXXXX`。
- **列表与分区顺序**（§列表/归组/标题）：一律走 `AZIndexGrouping` / `*SortedByName()`；数组是**录入顺序**不是字典序；**分区顺序禁止用 `Set`/`Dictionary` 遍历序派生**（`Array(Set(...))` 随进程哈希种子每次冷启动换排法），必须来自**显式顺序源**。
- **价格**（§价格：留空=清除，修正≠追加）：**修正 ≠ 追加**且不共用逻辑；修正**留空 = 清除**；`CatalogSaleEvent` 只 append、**永不 remove/replace**；缺失一律「暂无」，禁 `deposit ?? 0`。
- **图表**（§图表、§图表识别与录入）：两卡只消费同一个 `ShopCatalogChartPresentation.plan(...)`；`sourceImage` 非空绝不静默 `.none`；**识别结果必须过 `CatalogChartQuality` 门禁**，未过门禁一个字都不写进输入框；粘贴与多模态共用 `parsePastedText`，**预览即落库**。（09-23 后图片识别入口已移除，但系列编辑页的 `priceChartImageText` state **必须留着**，它承载既有原图。）
- **「同款商品集合」只能有一处定义**（§列表/归组/标题）：`ShopCatalogDesignPalette.sameDesignProducts`；详情页「配色」行 = **同款颜色集合**（`store.designColors`），**不能**读本商品规格色；加购弹窗的色号选择器仍读 `colors(forProduct:)`，**禁合并**。
- **删除**（§删除守卫）：预检与执行**共用** `plan*Deletion`；批量删除**整批只写一次覆盖层**；销售事件保留；部分成功绝不静默。
- **发布幂等**（§币种与发布幂等）：ID 必须按**该类型自己的**价格指纹；草稿坏 JSON 留原件 + 备份 + 阻止写回。
- **录入端 = 一个表单一个款式**（§SPU/SKU 分层与录入期同步）：`applyStyleForm` 一次 persist；**款式名一处决议**（逐条派生会让新色拿空款名 → 加一色变两款）；**同款家族必须同源**（`sameStyleFamily`，否则**误删**草稿）；图片绑定 `ColorRow.imageRefs → draft.images → variant.imageAssetID`。
- **加购记账**（§加购记账与衣橱标题、§加购分支按阶段区分）：**金额零手输**（全取 `CatalogPriceArchive`；**尾款读 `currentBalance`，禁现算**）；分支唯一口径 `ShopCatalogWardrobeEntryPolicy` —— **现货阶段 = 仅全款、两个价格口径**（`fullPaid` 按预约价 / `fullStockPaid` 按现货价）；**四个阶段都不得静默默认，必须弹选择弹窗**；选择段候选**必须取自 `options(...)`**；全款一律 `deposit=金额/balance=0/isDepositPlan=true`（**绝不生成尾款任务**）；**判付清只能用 `isFinalPaymentPlan`**（`markFinalPaymentCompleted` **不清 `balance`**）；`ClothingEditDraft` 新增字段**必须 Optional**。
- **系列发售阶段**（§系列「发售阶段」）：`salePhase` / `reservationEndAt` **必须 Optional**；**自动流转 = 读取时判定**（`CatalogSeriesSalePhaseResolver.effectivePhase`），**不做定时任务回写**；详情页**系列声明优先 → 未声明落回档期推导**；保存只写这两个字段、**不碰任何价格**；⚠️ 预约已结束**只改引导不剥夺能力**（全款为主按钮，【加入心愿尾款】收进折叠区，**禁止隐藏/置灰**）。
- **系列配置一站式**（§系列配置一站式）：发售阶段/图文/价格表**只有一处存储**（`CatalogSeries`），批次与单品只持 `seriesID` **引用无副本**；两个入口**必须共用** `ShopCatalogSeriesConfigSections` + `saveSeriesConfig`；`form.apply(to:)` **只写自己负责的字段**；尾款时间三字段全 Optional、切粒度清空另一种、**大致时间不驱动流转**。
- **系列年月与区间**（§系列年月通道 + 预约期/尾款期区间）：`CatalogSeries.month` 写入通道在**批次/草稿链路**（`newSeriesMonth` → `CatalogBatchEntrySession` → `applyBatchAttribution`）；复用既有系列时**「只填空不覆盖」**；`publishOperationKey` **只有年份时输出必须与旧实现逐字相同**（`"2026"`）否则存量草稿被判成新内容重发；年月录入唯一口径 `CatalogYearMonthText`，解析失败**不动已存值**。**⚠️ 预约期/尾款期都是区间**：**「开始」必填、「结束」选填**；**只有「预约结束时间」与「尾款开始时间」驱动流转**；`balanceDueAt` 的 key **不得改名**。
- **表单状态**（§表单「编辑中快照」与 sheet 呈现位置）：**`.sheet` 一律不许挂在 `ForEach`/`List` 的行视图上**（行重建 → 行上 sheet 的 `@State` 全归零）；同页多个 sheet 合并成一个 `enum XxxSheet: Identifiable` 挂**页面级**；**靠 `@State` 守卫防重置无效**（`loaded` 自己就是 `@State`）；要恢复的必须落盘（`ShopCatalogFormSnapshotStore` + `...Keeper`，0.5s 防抖 = **相册场景唯一兜底**）；恢复**必须可见 + 可放弃**；载荷日期用**整秒**；**`.onChange(of:)` 做派生回填会对程序化赋值也触发** → 改挂控件自己的 `Binding` setter。
- **界面遮挡**（§界面遮挡与底部 Dock 避让）：底部 Dock 叠在 tab 内容**之上**、**不参与安全区** → 每个可滚动页面自己避让；唯一口径 `avoidingBottomDock()`，高度只有一处 `LegacyCustomTabBarLayout.floatingSurfaceBottomInset`（= **72**），页面**不写数字、不判断系统版本**；**只给 tab 根 + tab 内 push 的页面加**，sheet/cover 不加，自带贴底操作条的**不要重复加**；`Group` 上会作用到每个 child（会双倍）。另一类是**浮层与卡片顶边重叠**（商品详情轮播 `.offset(y:-36)` 上提是**有意设计**）。
- **商品改名 = 款式级**（§商品改名 = 款式级）：**标题只读 `designName`**，而发布路径无条件写非空显式值 → `name` 被永久遮蔽；唯一口径 `ShopCatalogProductRename.plan(edited:basedOn:among:profiles:)`，写入口 `renameProduct(productID:newName:newCategory:)`；**必须扇出整款**（含已归档），否则拆组 + 款式档案孤儿 + 尺码表范围塌成 1 行；**品类也是款式级**；**名称没被改动时禁止重新派生款式名**；款式档案 `id` 就是款式键 → 必须**改键**；`applyRenamePlan` **必须先于** `applySizeChart` 且后者传**改名后**那份；衣橱/心愿记录名是**快照不跟着改**。
- **图片引用字段清单只有一处**（09-26 合并后新增，暂无 RULES.md 节）：`ShopCatalogMediaReferences`（共享包）是唯一 Swift 定义，必须与 Python `build_release.collect_shop_catalog_media`、iOS `ShopCatalogOpsMediaStaging.rewrite` 同步。两个标记**必须分开**：`isRewrittenByPublisher`（文件引用，`local:` 要换 `thmedia:`）vs `allowsAssetID`（可能是 asset id —— 一起改写会把 id 换成内容摘要、**商品图直接丢**）。回归锁 `ShopCatalogMediaReferenceTests` 把字段路径逐字写死。

## Mac 原生运营工具（09-26，P0+P1，**已合并进 main**）

三口径已与用户确认：**发布通道 = 封装现有 Python CLI**（不写 CloudKit、私钥不进 App）、**范围 P0+P1**、**共享代码 = 本地 SPM 包**。
worktree `Pink_House_macops`（`feature/mac-ops-tool`）已 ff 进 `main`。提交链：`ee837d78`（Mac 工具 + 共享包）→ `f445bf6e`（merge main 的「iOS 运营上传发布」）→ `cad63284`（字段清单收口）→ `7453892e`（Mac UI 快照 harness）。

- `Packages/SharedCatalog` **边界**：只许 Foundation / CryptoKit / ImageIO / CoreGraphics；**UIKit / PhotosUI / SwiftUI / SwiftData / CloudKit 一律禁止**（UIKit 一进来 Mac 编不过）。迁入 4 文件 + `ShopCatalogMediaStaging` / `ShopCatalogMediaJob` / `ShopCatalogPublicationGate` / `ShopCatalogMediaReferences`。
- **`@_exported import SharedCatalog` 实测按模块生效**（一个文件写一行全模块可见），但**它不带 Combine**。
- **跨模块三坑**：① `public` 类型**不会**让成员 public；② **合成逐成员 init 是 internal**，跨模块必须显式 `public init`；③ 工程开 `MemberImportVisibility` → `ObservableObject/@Published` 要 `import Combine`。
- 迁移脚本（`Packages/SharedCatalog/Tools/`）：`apply_migration_edits.py` → `add_public.py` → `add_public_inits.py`；**从 HEAD 原始文件重跑三个脚本**是唯一可靠的还原方式。
- **门禁判定**：`thmedia:` / 64hex → 已远端化；`local:` + 文件在 → 待上传；`local:` + 文件不在 → **阻断**；`bundle:` → 内置；`http(s)://` → 告警；悬空 asset id → 告警；**asset-id 字段里的裸名字 → 放行 + 告警，绝不阻断**（无法与内置资源文件名区分，阻断会误伤存量数据）。
- `ShopCatalogExportArchive.imageEntries` **去掉了 iOS 默认参数**，改必填 `imageDirectory:`；待发布包布局 = `shop-catalog.json` + `images/<文件名>`，与 iOS 整包导出逐字一致，交给 `tools/time_hall/publication` 发布，**不自创第二种格式**。
- ⚠️ **`local:` 改写仍有两条路径（属 P4 待决策，别擅自合并）**：iOS 侧 `ShopCatalogOpsPublisher`（直连 CloudKit，等于把 P2 在 iOS 实现了）vs Mac 侧「导出待发布包交给 Python CLI」。**字段清单已统一**，但**状态机仍是两套**（共享包 `MediaUploadJobState` 的 5 态 vs iOS `ShopCatalogUploadStatus` 多了 `mediaVerified/published/blocked`）。计划 §6 P4：要么两端共用同一 Publisher，要么 iOS 入口降级为只读/导出。**这是需要用户拍板的事。**

### Mac UI 视觉验收 = 应用内离屏快照（`PinkHouseOps/SnapshotHarness.swift`）

**完整用法见 skill `pink-house-xcodebuild-acceptance` §1d**。三条不可忘的：

- 系统截屏被 TCC 挡住（`screencapture` → `could not create image from display`）→ 用**应用内** `NSHostingView` + `cacheDisplay` 抓位图，绕开权限。
- ⭐ **触发方式必须走文件 `snapshot.request`，命令行参数没用**（实测 `open -n --args --snapshot-dir X` 时 App 收不到 X）；**沙盒应用只能写自己容器**，输出目录放容器里。
- ⭐ **抓图窗口必须 `.borderless`**：带标题栏会让快照**顶部被裁一条**（侧栏第一行、三栏表头正好落在那条里），看起来像布局 bug，其实是抓图的锅。

验收结论：5 张分区快照（2560×1680 @2x）内容全部正确 —— 概览统计（店家 1 / 系列 1 / 商品 1 / 图片资源 2 / 图片任务 2 待处理）、三栏主从编辑、任务台账 + 孤儿文件双向核对、门禁页「校验通过前导出按钮为灰」、**预览页两张样例图真的加载渲染出来**（证明取图链路通）。

## 主题索引 → RULES.md

环境/工具 · 启动与「强制横屏/打不开」 · 测试数据隔离 · SPU/SKU 分层与录入期同步 · 尺码表=款式级共享 · 列表/归组/标题与同款颜色 · **分区顺序禁用 Set 遍历序（09-25）** · **商品改名=款式级（整款扇出 + 款式档案改键）** · 价格（修正 vs 追加） · 图表展示同源 · 图表识别与录入（门禁/多模态/粘贴） · 系列发售阶段与自动流转 · 加购记账与衣橱标题 · **加购分支按阶段区分与现货两个全款口径** · 删除守卫 · **尾款阶段同步与大致时间估算** · **店家上新云同步消费端（远端层冷启动恢复 / 节流不越空态 / 失败必须可见）** · **店家上新图片随包走（THMedia）** · 币种与发布幂等 · **系列配置一站式与尾款中/尾款时间** · **系列年月通道与预约/尾款区间** · **表单编辑中快照与 sheet 呈现位置** · **界面遮挡与底部 Dock 避让**

## 还容易踩的（其余见 RULES.md 与上面两个 skill）

- **改名计划的基准必须是「改名前后两个不同的商品快照」**：写起来像「传入已改好 name 的那一份」更省事，但那样「名称是否被改动」自己跟自己比永远相等 → **真改名被判成没改名**（09-24 实测两条端到端用例红）。`plan(edited:basedOn:)` 两个入参缺一不可。
- 颜色词有**两个**口径别混用：`ShopCatalogColorPresentation.derivedLabel`（守卫「剥离后须≠原名」，用于「能不能当颜色标签」）vs `ShopCatalogProductRename.colorWord(in:)`（用于「改名别把颜色弄丢」）。
- `CatalogProductDraft` 新增款式字段必须进 `publishOperationKey` 指纹，否则「改了再发布」被幂等入口吞掉；`colorWords` 必须含**复合色**（`生成色`/`粉紫色`，长词优先），否则同款三色被拆成三款。
- `ShopCatalogImageStore.url(for:)` **只拼路径、不查盘**，对不存在的文件也返回非 nil → 判「文件不存在」必须自己补 `FileManager.fileExists`，否则会掉进 `unreadable` 而 `fileMissing` 永远不可达（两者对运营含义不同：缺图→重新选图 / 读失败→重试）。
- 持有 SwiftData 容器的 `@MainActor` store 进单测，**测试类本身要标 `@MainActor`**（光标在另一个类上不够）。
- **不要在脚本运行中途编辑脚本**：bash 按字节偏移增量读取，改文件头会让它从错位处继续读（`line N: syntax error`），收尾结论行静默丢失。
- `xcodebuild` 参数误写相对路径会生成 `ItemManager.xcodeproj/-Xcc/`（26M clang 缓存），已 `gitignore`。
- **`XCTestCase` 子类里不能有名叫 `hash` 的属性**（NSObject 的 `hash` 是只读 `Int`）→ 改用 `mediaHash` 之类。
- **同名不同返回类型的重载会被判歧义**（Swift 重载解析不看返回类型）→ 必须改名。
- ⭐ **`NSData.compressed(using: .zlib)` 是裸 deflate（RFC 1951），不是 zlib 封装**（名字骗人）：0B→2B `03 00`、1B→3B `73 04 00`、512B→20B 首字节 `0x7B`，首字节**从不是** `0x78`。写 `compress` 前先读同文件 `decompress` 的注释；若要判「是否 zlib 封装」，阈值**必须 ≥ 8**。
- ⭐ **PATH 上的 `grep` 是 WorkBuddy 的 toybox shim**（不是 BSD/GNU）：`grep 'a\|b'`（BRE 交替）**静默 0 命中、exit 1**，看起来像「这些符号根本不存在」，极易据此写错代码。**一律用 `-E`，或直接调 `/usr/bin/grep`，或用 Grep 工具**；`sed`/`find` 同样被 shim。
