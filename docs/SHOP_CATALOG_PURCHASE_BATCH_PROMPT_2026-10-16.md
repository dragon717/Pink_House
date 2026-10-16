# 入橱前选择团次／批次（2026-10-16，历史步骤）

> 后续用户截图明确要求选择批次与最终确认合并为同一页，日期移入紧凑详情。当前规则见[入橱同页选择与紧凑档期详情](SHOP_CATALOG_INLINE_BATCH_PICKER_2026-10-16.md)。下文保留上午独立步骤的实现与验证经过，不作为当前交互要求。

## 当时要求与行为

已配置分团或分 P 次的商品，用户点击加入衣橱后，入橱弹窗首先显示「选择购买批次」。原先只在确认页内提供下拉项的方式被此步骤取代。

- 选择页原样列出运营配置的批次名称，可为「先行团」「一团」「二团」「1P」「2P」，也可为「一团 · 1P」等完整名称；不根据商品描述猜测或新增批次。
- 每项同时展示该批次的具体尾款日期、大致原文及预计日期，或「待公布」。节日前估算沿用已确认的提前六天规则。
- 没有选齐时，「继续加入衣橱」不可用；只有一个已配置批次也要求用户明确选择。没有分批配置的商品直接进入既有确认页。
- 用户选定并继续后，再展示配色、尺码、金额及加入方式等原有确认内容；选择批次本身不写衣物、不生成支付任务或发奖励。
- 确认页保留批次摘要，可点击「更改团次 / P次」重新选择；备注、配色及尺码等输入保留，付款方式仍只在原确认页内选择一次。
- 单件加购、无价格档案的单件兜底、多件合并入橱均使用同一个步骤。多件同系列使用同一批次，不同系列分别选择；未勾选的小物不增加批次要求。
- 批次被撤下或本次加入新增了其他系列时，必须补齐有效选择；无效 ID 不改投剩余批次。稳定 ID 下更名或日期更新仍属于原购买批次。

选择状态由 `ShopCatalogPurchaseBatchSelection` 管理；它明确区分「已点选」与「已确认」，不使用共用尾款解析器的单团自动兜底。目录线上的字段与已有衣物的 `catalogReservationBatchID` 保持兼容。

## 尾款联动

最终确认时，已选批次 ID 继续传入 `ShopCatalogWardrobeDraftBuilder.Selection` 和既有 `ShopCatalogWardrobeAddition.add/addSet`。定金入橱按该批次生成待付尾款日期；全款仍不生成尾款任务。未公布日期的批次保留待公布，后续只按同一批次更新，不套用其他团或 P 次的日期。

本次另修正多件确认页在切换批次后仍可能保留失效付款候选的问题：所选方式不在该批次阶段的候选内时，回到既有阶段策略提供的有效默认项；显示金额与最终保存使用同一口径。

## 验证命令与结果

本机 Xcode 27.0（27A266a），目标模拟器 `Codex DIY Outfit QA`，iOS 26.3，UDID `F64FFA05-1AA0-4C8F-9920-F18A772486CB`，scheme `ItemManager`。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 \
  -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogPurchaseBatchSelectionTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeEntryTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeBalanceSyncTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeImageImportTests \
  -resultBundlePath /private/tmp/pink-house-purchase-batch-choice-20261016/PurchaseBatchFinal.xcresult
```

**71 项通过，0 失败，TEST SUCCEEDED**：批次选择 9、尾款同步与入橱联动 16、既有记账 34、图片导入 12。覆盖未选拦截、单批次不默认、多系列独立选择、更改和撤下批次、2P 实际落库及其尾款更新；第一 P 改期不会影响第二 P，金额保持不变。

真实 SwiftUI 选择页和摘要使用隔离夹具渲染，已目视检查未选中、选中 2P、确认后三个状态，文字及按钮完整。截图由结果包导出至日志目录的 `screenshots/`，具体名称与状态见 `manifest.json`。

正常构建使用上述 `xcodebuild` 参数，将 `test` 改为 `build` 并移除测试筛选、并行测试及结果包选项。日志目录为 `/private/tmp/pink-house-purchase-batch-choice-20261016/`：`ios-tests-final.log`、`ios-build.log`，模拟器安装与启动另记于 `simulator-install.json`。

正常构建 **BUILD SUCCEEDED**；向同一目标执行 `simctl install` 通过。终止旧进程返回 3（没有旧进程），重新 `launch bugod2.ItemManager` 通过，新 PID 20498。正常产物中已确认包含「选择购买批次」文案。此运行检查不记为整条业务链的手动点击验收。

## 生效边界

本次不更改云端目录内容，不要求再次发布目录。iOS 功能随新版客户端安装生效，未上传 TestFlight / App Store。

自动测试与 SwiftUI 渲染验证使用测试目录和内存夹具；未执行真机完整点击入橱，也未验收系统提醒实际送达。模拟器无 iCloud 账号的既有 CloudKit 日志不影响本次 71 项测试通过。
