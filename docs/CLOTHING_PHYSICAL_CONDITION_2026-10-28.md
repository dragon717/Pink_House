# 衣物状况与购买状态分离（2026-10-28）

用户确认：状况指全新 / 非全新；付清尾款后不能继续在状况栏显示「待付尾款」。

## 根因

1. `ClothingEditView` 在已拥有切换为预约时，会自动填入并在保存时强制覆盖 `condition`：全款预约写「未到货」，定金尾款写「待付尾款」。这也会覆盖原本的非全新成色。
2. 尾款付清服务只迁移 `isDepositPlan` 等购买字段，详情页直接读取原始 `condition`，因此已付清仍显示旧购买文案。
3. 自动补全预设还提供这两项购买文案，筛选和批量修改继续从历史记录收集这些值。
4. 总尾款的旧数据兜底依赖 `condition == "待付尾款"`，直接清理成色可能让只有总价的旧心愿金额归零。

## 修复口径

- `ClothingCondition` 统一提供「全新 / 非全新」。沿用 SwiftData / CloudKit 的 `condition` 字段，新增计算属性 `physicalCondition`，不改存储 schema。
- 详情、筛选、搜索、AI 成色描述与 CSV 导出使用同一成色投影。编辑页固定单选两项，批量修改和建议列表只提供两项，状况管理不再把固定分类当作可重命名或删除的自由标签。
- 移除预约切换自动填写成色、保存强制覆盖成色及相关确认文案。付清尾款或签收不会把非全新改成全新。
- 对旧版误写的「待付尾款 / 未到货」按创建默认值修复为全新。旧代码覆盖前的成色已经无法由当前数据还原；不据截图推断实际成色，用户仍可选择非全新。
- 旧「仅试穿、99新、有瑕疵」等成色展示归入非全新，保留原始存储描述用于备份和同步。只保存其他编辑字段、付款或迁移时不覆盖这些描述。
- 启动与云端同步后重复执行修复，覆盖已付清存量以及迟到的旧云端记录；详情打开和付清服务也兜底修复。重复执行不再修改时间戳，已删除记录不参与批量修复。
- 总尾款缺失时按预约标记和金额计算兜底，不依赖成色；更改成色不影响数量、小物及一次性邮费的应付口径。付清记录仍保留历史尾款金额，是否已拥有继续由独立购买状态决定。

## 验证

新增 `ClothingConditionTests` 8 项：固定成色选项；保留旧物理成色描述；截图金额 589 / 113 / 476 的真实付款持久化；非全新在付款及购买状态切换后保持；已付清/未付清存量与迟到云端记录的幂等修复；成色不影响旧心愿金额；同步和异步筛选一致；付款流水核对后的成色修复。

本机 Xcode 27.0（27A266a），iPhone 17 Pro / iOS 26.3.1，命令：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ClothingConditionTests \
  -only-testing:ItemManagerTests/WardrobeOwnershipFilterTests \
  -only-testing:ItemManagerTests/ClothingTests \
  -only-testing:ItemManagerTests/ClothingAccessoryTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeEntryTests \
  -only-testing:ItemManagerTests/WardrobeStorageInventoryTests test
```

结果：最终版本 `TEST SUCCEEDED`，85 项通过、0 失败（成色 8、所有权筛选 8、衣物模型 5、小物与金额 23、入橱与付款 34、衣橱分类 7）。首次 85 项通过后，补齐首页成色菜单并用相同命令重新构建、测试，最终仍为 85 项通过。`git diff --check` 通过。

最终日志：`/private/tmp/pink-house-clothing-condition-final-tests.log`；结果包：`/private/tmp/pink-house-reservation-batches-ios/Logs/Test/Test-ItemManager-2026.10.28_12-05-21-+0800.xcresult`。

验证边界：构建、成色与购买状态逻辑、付款和修复的内存数据库持久化、筛选与金额回归；未进行本次真机或界面截图验收，未读写用户真机数据库。代码尚未上传或发布，随新版本安装后执行历史修复。
