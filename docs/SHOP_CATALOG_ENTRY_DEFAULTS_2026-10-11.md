# 时光馆入橱与运营录入默认规则（2026-10-11）

2026-10-16 补充：已配置团次或批次的商品在入橱确认页内选择购买批次；尾款结束选填支持“十天、十五天、一个月”等时长，从所选批次预计开始日推算。Mac 系列配置保存自动更新两环境，失败时在该配置页顶部重试并查看日志。当前规则与验证见 [尾款结束时长与同步入口](SHOP_CATALOG_BALANCE_DURATION_AND_SYNC_2026-10-16.md)。

2026-10-16 真机排查补充：用户购买、入橱和尾款校准通过 `seriesForPurchase` 读取已发布档期，防止本机旧运营副本遮住线上团次。编辑器仍保留原副本，详见 [手机已发布团次读取修复](SHOP_CATALOG_PUBLISHED_BATCH_CONSUMPTION_2026-10-16.md)。

## 入橱选择

- 当前规则（2026-10-18 起）：系列选购页同时提供「逐件加入」与「合并加入」。逐件加入在同一确认页选好全部商品后，一次保存为多条独立衣物，小物也独立成条；成功后移除本批勾选，失败整批回滚并保留选择。已选配色、尺码和价格口径传入确认页；合并加入保留下列主衣物与小物规则。
- 入橱确认页默认选中第一件主衣物；JSK / OP / SK / Blouse 沿用统一分类，每件主衣物生成一条衣橱记录。
- 小物初始不勾选。仅用户勾选的小物参与加入方式、金额预览、图片导入和小物明细落库；用户取消勾选后，页面再次出现不得自动选回。
- 只有小物时，默认第一件作为独立衣橱主条目；切换主条目必须同步到草稿。主条目不能再次作为自己的小物重复记账。
- 主衣物有多件时，勾选的小物归属于用户选定的主条目，其余主衣物仍独立入橱。
- 加入方式只在确认页内选择；点击「确认加入衣橱」直接按每件商品已选方式保存，不再弹出重复的预约价 / 定金尾款选择。这条规则取代 2026-09-27 的二次弹窗要求。
- 保存、成功气泡、实际到账鱼币继续按 `OPERATION_FEEDBACK_AND_FISH_COIN_GUIDE.md` 处理，小物不另发入橱奖励。

选择状态集中在 `ShopCatalogWardrobeMergeSelection`，确认页只负责交互；`makeSplitDrafts` 接收主条目 ID，使用同一选择结果落库。

## 运营默认币种

- iOS 单品新草稿、整款公共表单、Mac 追加销售记录统一默认 CNY（人民币）。
- iOS 新款录入和 Mac 系列向导已经默认人民币，沿用现有实现。
- iOS 追加销售记录沿用已明确的商品币种；缺失 / 待确认时新录入默认人民币。去重预检与提交携带同一币种。
- iOS 未提交表单快照未记录币种时，恢复到人民币默认值；已选择币种的快照原样恢复。
- 新草稿的预约价和现货价发布时都携带 CNY。运营可以明确选择其他币种。
- 历史销售记录与旧 JSON 缺币种的解码仍保留来源语义；不会直接把日元价格数字改标人民币，也不进行隐式换汇。

## 验证

iOS 使用 Xcode 27 / SDK 27，目标模拟器 iPhone 17 Pro（26.3.1）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=826F5E71-D2BC-4E76-A8C5-4251C526A5D4' \
  -derivedDataPath /private/tmp/pink-house-detail-layout-20261011 \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 \
  -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogEntryDefaultsTests \
  -only-testing:ItemManagerTests/ShopCatalogCurrencyTests \
  -resultBundlePath /private/tmp/pink-house-entry-defaults-final-20261011.xcresult test
```

- iOS 最终构建：**BUILD SUCCEEDED**（与上方相同参数，移除测试筛选与结果包参数，改用 `-jobs 2 build`）。追加记录界面的最后补充也已编译通过。日志 `/private/tmp/pink-house-entry-defaults-build-20261011.log`。
- iOS 测试结果：**23 通过，0 失败，0 跳过**（新增默认值回归 7 项 + 原有币种回归 16 项）。结果包 `/private/tmp/pink-house-entry-defaults-final-20261011.xcresult`。

Mac 编译与测试目标构建（本机宿主式 Mac XCTest 已记录连接挂起问题，因此使用 build-for-testing）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme PinkHouseOps -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/pink-house-ops-defaults-20261011 \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```

- Mac 结果：**TEST BUILD SUCCEEDED**，运营 App 和测试目标编译通过；未执行宿主式 Mac XCTest。日志 `/private/tmp/pink-house-ops-defaults-20261011.log`。
- 新增回归覆盖默认主衣物、手动勾选/取消小物、页面再次出现、单独小物入橱、主条目切换、CNY 草稿与预约/现货发布、显式 JPY 与旧缺币种解码。
- 原有币种测试改用 async XCTest，为 SDK 27 的 MainActor fixture 析构提供 Swift Task 上下文，沿用已验证的测试兼容口径。
- 边界：没有修改线上商品数据，没有实际运营上传或真机视觉验收。

## 后续拆分计划

确认页已抽出选择状态，并删除二次弹窗的状态与分支，文件回到 500 行以内；`ShopCatalogOps.swift` 后续拆出草稿模型与发布服务；`ShopCatalogOpsView` / `OpsProductsView` 后续拆出独立价格表单，本次只修默认值。

## 加入方式交互简化验收

2026-10-11 按用户截图保留页内加入方式单选，删除 confirmationDialog、弹窗状态、统一候选计算与弹窗覆盖单品选择的代码。按钮直接调用已有 confirmInsert；保存失败仍显示错误，成功仍走统一反馈。构建与回归结果：**TEST SUCCEEDED，14 项通过，0 失败，0 跳过**；Xcode 27 / SDK 27 构建，运行于 iPhone 17 Pro / iOS 26.3.1。没有执行该确认页的模拟器视觉点击验收。


本次验证命令（日志 `/private/tmp/pink-house-merge-inline-choice-20261011.log`）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=826F5E71-D2BC-4E76-A8C5-4251C526A5D4' \
  -derivedDataPath /private/tmp/pink-house-detail-layout-20261011 \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 \
  -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogMergeEntryChoiceTests \
  -only-testing:ItemManagerTests/ShopCatalogEntryDefaultsTests \
  -resultBundlePath /private/tmp/pink-house-merge-inline-choice-20261011.xcresult test
```

## 运营存量币种的明确补充

用户确认运营已上传、未明确币种的商品全部属于人民币；已经对实际公共库补填并发布。通用旧 JSON 解码不猜币种的规则不影响这次已确认的数据修复。范围与证据见 [运营存量币种修复](SHOP_CATALOG_OPERATOR_CURRENCY_REPAIR_2026-10-11.md)。

## 2026-10-13 入橱备注与预约团次

- 入橱备注默认空白，供用户选填。系列、年月、币种、价格口径、小物说明、尾款估算依据和同步说明均不再自动写入备注；旧记录和用户已填写的备注保留原文。
- 同一系列可按实际团数配置先行团、一团、二团等，使用 `CatalogSeries.reservationBatches`，每团独立声明具体或大致尾款期，可选填该团预约结束时间作为估算锚点。这与运营录入批次、销售记录再贩批次分开存储。
- iOS 系列编辑 / 整批配置与 Mac 系列配置均可添加、删除、编辑团次。团次 ID 稳定，名称不得重复，具体结束时间不得早于开始时间。表单快照和旧 Catalog JSON 缺少新字段时仍可解码。
- 单件与多选入橱均显示所属团次和尾款时间；只有一团时自动确定，多团必须明确选择。用户记录保存 `catalogReservationBatchID`，后续尾款同步只读取该团声明；团次改名不影响归属，团次被移除或多团旧记录未选团时跳过同步。
- 该团未公布日期或大致描述无法估算时保留待公布，不套用系列共用日期、其他团日期或加购当天。单件确认页仍允许用户自行设置日期；运营已有可解析的声明优先，不能被原先预约结束日的预选值覆盖。
- 未分团系列沿用原有尾款规则。本次不自动猜测存量商品团数或各团日期；实际声明由运营填写并沿既有保存 / 发布流程进入公共目录。

验证入口：`CatalogReservationBatchTests`、`ShopCatalogWardrobeBalanceSyncTests`、`ShopCatalogWardrobeEntryTests`、`OpsCatalogEditorPersistenceTests.testReservationBatchesSaveReloadAndValidateWithoutNetworking`。

本机验证使用 Xcode 27.0（27A266a），显式设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。SPM 沿用已核验无重复 Swift 源文件的本机缓存：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --package-path Packages/SharedCatalog --scratch-path /tmp/pink-house-reservation-batches-shared

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=FA7332BE-B29E-4879-A139-C68A24314DB1' \
  -derivedDataPath /tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeEntryTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeBalanceSyncTests \
  -only-testing:ItemManagerTests/ShopCatalogPhase456Tests \
  -only-testing:ItemManagerTests/ShopCatalogSeriesConfigFormTests \
  -only-testing:ItemManagerTests/ShopCatalogEntryDefaultsTests \
  -only-testing:ItemManagerTests/CatalogSeriesSalePhaseResolverTests \
  -only-testing:ItemManagerTests/CatalogSeriesBalanceDueTests \
  -resultBundlePath /tmp/pink-house-reservation-batches-verified.xcresult -quiet

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing \
  -project ItemManager.xcodeproj -scheme PinkHouseOps -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 -quiet

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 \
  tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /tmp/pink-house-reservation-batches-ops
```

共享包 **207 项通过、0 失败**；Mac `build-for-testing` **PASS**，无联网写入的实际 Workspace 回归 **49 项通过、0 失败**。日志分别位于 `/tmp/pink-house-reservation-batches-shared.log`、`/tmp/pink-house-reservation-batches-ops-final.log`、`/tmp/pink-house-reservation-batches-ops-tests-final.log`。

iOS 构建与测试 **PASS：105 项通过、0 失败、0 跳过**，运行于 iPhone 18 Pro / iOS 27.0。结果包 `/tmp/pink-house-reservation-batches-verified.xcresult`，日志 `/tmp/pink-house-reservation-batches-ios-verified.log`；用 `xcrun xcresulttool get test-results summary --path /tmp/pink-house-reservation-batches-verified.xcresult` 核验最终结果。覆盖按团次入橱与改名后的稳定归属、各团独立估算锚点、未公布时间保留空值、用户备注不被同步改写，以及未分团旧行为。

验证边界：不操作生产公共库，不自动补填未知团次和日期；未进行真机、线上 CloudKit 发布或模拟器页面视觉点击验收。保留已存在的 Sendable / actor 隔离警告与 iOS 扩展版本号警告，不在本次变更中调整。

2026-10-14 已把团次录入直接接入 Mac 上新向导 S2 与 iOS「录入款式」，并接入向导持久化、S4 摘要、发布快照及切换系列时的独立回填。规则、测试和验证边界见 [商品上传团次与独立尾款期](SHOP_CATALOG_RESERVATION_BATCH_UPLOAD_2026-10-14.md)。


## 2026-10-16 入橱图片与保存后自动同步

系列配置保存后自动更新 Development 与 Production，两端回读确认后才报告完成。入橱优先保留所选配色图及通用商品图，未绑定规格不再导致空图；明确属于其它颜色的图片仍排除。多团购买需先选团，尾款记录按该团生成和更新。正式规则、两端发布号与验证边界见 [本次修复记录](SHOP_CATALOG_SERIES_SAVE_AND_WARDROBE_FIX_2026-10-16.md)。

## 2026-10-16 节日前预计尾款

用户允许按节日提前 5～7 天估算，固定取 6 天；“圣诞节前”为 12月19日，农历节日按对应年份换算。运营原文及大致时间属性保留，团次按录入基准固定年份，入橱与已有待支付记录共用规则。目录已是最新版时也可校准日期，无需再次发布。详见 [规则与307项测试记录](SHOP_CATALOG_HOLIDAY_BALANCE_DUE_ESTIMATES_2026-10-16.md)。

## 2026-10-16 运营款式顺序与删除

系列向导的款式条目支持拖动排序并保存；删除仅作用于指定条目的独立身份。同名、同类型和共用素材不构成联删条件；旧重复行标识在恢复时修复，类型取消勾选不再默认指向第一条。规则、64项回归及实际界面验证见 [款式排序与逐条删除](SHOP_CATALOG_STYLE_ORDER_AND_DELETE_2026-10-16.md)。

## 2026-10-16 入橱确认页内选择购买批次

对已配置团次或批次的商品，在原入橱确认页内用简洁菜单选择，不另开选择步骤。此处只显示批次名称；尾款原文、预计日期及依据统一放在系列和每件商品详情的折叠行内。单批次也不静默默认，未分批商品沿用原流程。详见 [同页选择与紧凑详情](SHOP_CATALOG_INLINE_BATCH_PICKER_2026-10-16.md)；上午的独立弹窗记录仅作历史验证。

## 2026-10-17 多选商品逐件加入（历史，已被下一节取代）

系列选购页底部保留「合并加入」，新增「逐件加入」。逐件确认页显示当前进度（如 1/3），保存成功后自动进入下一件，全部成功后关闭。每件确认页使用独立状态，避免备注、购买批次和付款方式串到下一件。保存入口仍为 `ShopCatalogWardrobeAddition.addSet`，沿用长期图片引用、系统收尾、成功反馈和实际到账鱼币。

验证环境：Xcode 27.0（27A266a），scheme `ItemManager`，iPhone 17 Pro 模拟器 `Codex DIY Outfit QA`，iOS 26.3.1。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 \
  -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeIndividualAdditionTests \
  -only-testing:ItemManagerTests/ShopCatalogEntryDefaultsTests \
  -only-testing:ItemManagerTests/ShopCatalogMergeEntryChoiceTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeImageImportTests \
  -resultBundlePath /private/tmp/pink-house-individual-addition-20261017.xcresult
```

结果：构建与测试 **PASS，31 项通过，0 失败，0 跳过**。覆盖逐件顺序、重复/过期回调不推进、取消后的剩余勾选、空选择，以及原合并默认值、记账口径和图片保存/失败回滚。实际 SwiftUI 页面渲染了两个入口、首件 1/2 与小物末件 2/2，已目视核对按钮、进度与独立主条目。截图是隔离夹具渲染，第二件通过队列状态构造；未执行完整连续点击保存验收。

日志：`/private/tmp/pink-house-individual-addition-20261017.log`；截图及索引：`/private/tmp/pink-house-individual-addition-20261017-screenshots/`。保留项目已有 Swift 并发警告。本次未进行真机或云端能力验收，未发布 TestFlight / App Store，需新版客户端安装后生效。

## 2026-10-18 一键分别入橱

用户要求取代上一节逐件确认队列：现在在同一确认页选好全部商品后，一次确认并分别生成独立衣物，小物也单独成条；保留「合并加入」。沿用统一批量入库、图片保存、失败回滚及一次成功/实际到账鱼币反馈。根因、规则与验证边界见 [系列汇总与一键分别入橱](DEPOSIT_SERIES_AND_BATCH_INDIVIDUAL_ENTRY_2026-10-18.md)。

2026-10-18 用户确认：梨园梦瓷 ¥7,934 已包含附属小物。共用计算统一为「衣物单件金额 × 数量 + 小物明细一次」，定金、尾款和相关展示共用模型口径。¥418 差额的逐项核对、79 项回归及两张截图的单价版本说明见上述修复记录。
