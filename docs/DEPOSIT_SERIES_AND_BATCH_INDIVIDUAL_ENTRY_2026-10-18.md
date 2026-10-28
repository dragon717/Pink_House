# 心愿尾款系列金额、去重与一键分别入橱

日期：2026-10-18。

## 用户要求与结论

用户确认梨园梦瓷的正确尾款 **¥7,934 已包含附属小物**。金额错误的直接根因是 `Clothing.totalBalance` 将小物尾款与衣物单件尾款相加后，一起乘了衣物数量，重复计算了小物。定金存在同样问题。

另外两处独立问题也已修复：系列候选前缀互相重叠，以及部分页面状态变化没有刷新系列汇总。逐件入橱改为同页选择、一次确认分别保存，保留合并加入。

## ¥418 差额的逐项证据

已通过 `devicectl device copy from` 只读取得既有配对 iPhone 的数据库和 WAL 副本，SQLite `PRAGMA quick_check` 返回 `ok`。只对本机副本查询，没有改写真机记录。个人数据库保留在权限为 0700 的本机诊断目录，不进入仓库。

原公式：

```text
(衣物单件尾款 + 小物尾款明细之和) × 衣物数量
```

正确公式：

```text
衣物单件尾款 × 衣物数量 + 小物尾款明细之和
```

每条 `AccessoryItem` 本来就是一条已录入的小物明细，不能再次随主衣物数量复制。根据图一展示金额与副本中对应的小物明细，六条记录如下：

| 记录 | 衣物数量 | 衣物单件尾款 | 小物尾款合计（一次） | 原显示 | 修正后 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 高腰 op | 1 | 518 | 79 + 44 = 123 | 641 | 641 |
| 高腰 op | 2 | 518 | 79 + 44 = 123 | 1,282 | 1,159 |
| op | 2 | 518 | 79 | 1,194 | 1,115 |
| dress | 2 | 939 | 108 | 2,094 | 1,986 |
| dress | 2 | 939 | 108 | 2,094 | 1,986 |
| dress | 1 | 939 | 108 | 1,047 | 1,047 |
| **总计** | **10** | | **649** | **8,352** | **7,934** |

四条数量为 2 的记录分别多算小物尾款 123、79、108、108，合计 **418**。主衣物尾款合计 7,285，加一次小物 649，得到 **7,934**。定金同理由 2,210 修正为 2,050。

只读手机副本对应图二的较旧金额版本：前三条主衣物单件尾款为 568，较图一每件高 50，共 5 件，相差 250。该副本原公式得到 8,602，修正公式得到 8,184；两种金额版本都恰好多算 **418**。不应为了得到 7,934 而擅自把不同版本的单件金额改写为 518。

## 共用金额模型修复

- `FinancialDataSanitizer.orderTotal` 统一实现「主衣物单件金额 × 数量 + 小物明细一次」，保留金额和数量的合法性处理。
- `Clothing.totalDeposit`、`totalBalance`、全款预约的小物累计使用这一口径。`pendingFinalPaymentAmount`、`reservationPaidAmount`、支付待付额、通知及系列汇总随模型自动取得正确结果。
- 衣橱卡片和小组件原有 `wardrobeListTotalDeposit/Balance` 仅计算主衣物、漏掉小物，现直接复用模型总额。衣橱、心愿尾款和小组件查询批量预取小物关系，避免逐行查询。
- 编辑页定金/尾款合计共用此公式；统计页附属小物总价不再乘衣物数量；萌宠统计和衣橱上下文读取同一模型口径。
- 没有新增存档字段、数据迁移或金额回写。原单件金额、数量和小物明细保持其业务含义，已有记录加载后按正确公式计算。单独作为主条目的小物，其自身数量仍正常参与主条目计算。

## 系列归类与刷新

原来的 `SeriesAnalyzer` 从 `reservationListAmount` 汇总。对真正的定金尾款记录，这个属性本来就等于 `pendingFinalPaymentAmount`，字段名本身不是金额错误的根因。现直接读取后者，使业务含义明确。

原算法为一件衣物生成前 2、3、4 字的多个候选，只有成员完全相同时才删除短候选。因此「美乐蒂」包含全部成员，「美乐蒂联」「美乐蒂蜜」又重复包含其子集。

现先按清理括号、忽略大小写后的前两字建立互斥分组，再以组内最长共同前缀（最多四字）命名。每个衣物 ID 仅进入一个组；不足两字的名称也保留。`SeriesInfo` 保存明确的成员 ID，卡片汇总与明细筛选共用这些身份，稳定名称作为系列标识。

`DepositPlanView` 此前在搜索/筛选、按月模式修改后切换系列、页面重新出现等情况下，可能复用非空的旧系列数组。现随明细基准变化重算，每次进入系列模式也重算；旧任务取消后的结果不能覆盖新结果。

## 一次确认、分别保存

旧实现逐件推进确认队列，现将全部勾选商品交给同一确认页：

- 每件商品独立选择付款方式，保留颜色和尺码，同页选择购买团次。
- 底部固定合计与「一键逐件加入衣橱」。一次构建全部独立草稿，包括 KC、包等小物；小物也单独成条。
- 统一调用一次 `ShopCatalogWardrobeAddition.addSet`，沿用图片持久化、失败回滚、业务收尾，以及一次成功和实际到账鱼币反馈。
- 保存中禁用重复提交、取消和滑动关闭；只有整批成功才移除本次勾选，失败保留勾选。
- 「合并加入」保留主衣物与小物选择规则。

这取代 `SHOP_CATALOG_ENTRY_DEFAULTS_2026-10-11.md` 中 2026-10-17 的逐件队列确认方式。

## 验证

前一阶段的系列归类和批量入橱构建与测试为 57 项通过，0 失败，结果包 `/private/tmp/pink-house-series-and-one-click-verified-20261018.xcresult`。

本轮新增的金额验证使用真实小物明细重建两种金额版本，覆盖：图一 8,352→7,934、只读副本 8,602→8,184、定金与全款金额、数量变化、小物持久化后修改，以及列表/详情/统计/萌宠/支付的口径一致性。

首次金额回归尝试因磁盘空间不足发生 CodeSign 错误；后续启动停滞的构建已中止。仅清理了本轮生成的中间结果、可重建索引和 Xcode 模块缓存，并重启专用 QA 模拟器，没有删除仓库文件或个人数据。

最终构建与测试 **PASS：79 项通过，0 失败，0 跳过**。`xcodebuild test` 退出码 0，已用 `xcresulttool get test-results summary` 复核。覆盖真实金额差额、定金/全款、小物持久化与修改、统计和萌宠口径，以及尾款账本、奖励防重、系列归类、合并选择、批量分别入库和图片保存/回滚。

结果包：`/private/tmp/pink-house-accessory-once-fixed-20261018.xcresult`；日志：`/private/tmp/pink-house-accessory-once-fixed-20261018.log`。`git diff --check` 通过。保留项目既有 MainActor / Sendable、扩展版本号与资源脚本警告；Xcode 的 `exit code 0 but produced no further output` 诊断噪声以真实退出码及 xcresult 为准。

验证环境：Xcode 27.0 / 27A266a，scheme `ItemManager`，iPhone 17 Pro 模拟器 `Codex DIY Outfit QA` / iOS 26.3.1。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 \
  -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/SeriesAnalyzerTests \
  -only-testing:ItemManagerTests/ClothingTests \
  -only-testing:ItemManagerTests/ClothingAccessoryTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeIndividualAdditionTests \
  -only-testing:ItemManagerTests/ShopCatalogEntryDefaultsTests \
  -only-testing:ItemManagerTests/ShopCatalogMergeEntryChoiceTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeImageImportTests \
  -only-testing:ItemManagerTests/OperationFeedbackTests \
  -only-testing:ItemManagerTests/RewardManagerTests \
  -resultBundlePath /private/tmp/pink-house-accessory-once-fixed-20261018.xcresult -quiet
```

实际 SwiftUI 入橱页已用隔离夹具渲染并目视核对，同页显示 3 件商品与各自付款选项，底部合计和一键确认可见。未执行完整 UI 点击保存链路，批量持久化由自动化测试验证。本次未向真机安装，也未发布 TestFlight / App Store 或写入生产 CloudKit。
