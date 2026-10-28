# 已拥有与心愿尾款的状态隔离（2026-10-28）

用户确认：已拥有不包含心愿尾款，付清尾款后才能进入已拥有。

## 业务口径

- 已付定金、待付尾款、尚未付款的心愿记录，都不能通过「已拥有」筛选。
- 尾款付清并保存成功后，既有 `WealthSavingLedger.recordFinalPayment` 完成状态迁移：退出定金计划，进入已拥有。
- 存钱、部分付款、已作废的付款流水都不能作为付清事实。
- 历史 `deposit` / `balance` 保留；付清后的历史尾款仍可为正数，不能用 `balance > 0` 把已付清记录重新判成未付。
- 全款预约和已售出继续使用各自独立状态；「全部」仍可查看各状态。

## 实现与原因

模型及同步筛选原本已有「已拥有排除定金计划」的规则。主列表还存在 350ms 延迟的异步筛选缓存、独立的统计缓存、编辑排序缓存：切换条件或付款状态后，旧结果在新计算提交之前仍可能显示；编辑缓存非空时原来不会随新筛选结果同步。

本次做了以下修复，不改付款金额或批量重写用户记录：

1. `DepositStatusFilter.includes` 为同步筛选、后台快照、合并小物筛选与显示前校验共用状态入口。
2. 后台快照直接保存 `ClothingReservationKind`，不再用独立布尔值拼状态。也修复了旧快照对「已售出、但仍保留定金标记」记录的心愿尾款判定分歧。
3. 列表显示前，按当前筛选与当前衣物状态再收窄缓存，保证选择已拥有时不露出未付清记录；网格、普通列表和编辑列表一致。
4. 统计缓存绑定生成它的完整筛选签名。签名未匹配或显示记录已被收窄时，立即从当前可见记录重算件数、裙装价值与总价值。
5. 编辑缓存随筛选结果移除隐藏记录、补入新记录，并保留已有拖动顺序；列表移动的下标按可见记录映射回编辑缓存，避免隐藏记录导致错位。
6. 筛选签名直接纳入完整状态，状态变化可以触发重算，无需依赖付款金额是否清零。
7. 卡片缓存遇到付款、售出或转单状态变化时立即生成新快照，付清后的记录不会继续显示旧的「已付定」标签与定金尾款价格行。

这些改动保证程序遵守用户确认的规则；截图本身不能证明每条衣物的实际付款流水，因此没有根据截图推断并迁移用户的 37 条记录。

## 回归与构建

新增 `WardrobeOwnershipFilterTests` 8 项，覆盖：已拥有排除未付清及心愿记录；各筛选入口一致；件数与金额排除未付记录及其小物；旧显示缓存即时收窄；真实付清事务后进入已拥有；存钱、部分与作废付款不算付清；重新进入尾款状态后退出已拥有；编辑缓存随筛选变化且保留排序。

本机 Xcode 27.0（27A266a），iPhone 17 Pro / iOS 26.3.1。验证命令：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/WardrobeOwnershipFilterTests \
  -only-testing:ItemManagerTests/ClothingTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeEntryTests \
  -only-testing:ItemManagerTests/WardrobeStorageInventoryTests test
```

结果：54 项通过（8 项状态隔离、5 项衣物模型、34 项入橱与付款、7 项衣橱分类）。最初边构建边增补方法导致一次测试编译使用了过早的模块快照，随后按最终源码重新构建验证。

验证边界：业务规则、缓存投影、统计与真实内存持久化付款事务；未进行本次真机或界面截图验收。代码尚未上传或发布，新版本分发后生效。
