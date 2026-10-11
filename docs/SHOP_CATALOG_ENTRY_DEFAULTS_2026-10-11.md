# 时光馆入橱与运营录入默认规则（2026-10-11）

## 入橱选择

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
