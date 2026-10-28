# Mac 已上线商品改名（2026-10-17）

用户要求：已上线商品仍可在 Mac「少女心愿运营」修改名称，不能因为业务规则只在 iOS 实现就拒绝操作。

## 根因与修复

原 `OpsWorkspace.renameGuard` 以「草稿曾发布且基线包含商品 ID」为条件，直接拒绝名称或品类变化。`updateProductDetail` 也拒绝修改已上线商品的款式名。两个表单的说明把这种实现缺口当成了运营限制。

将 iOS 已有的 `ShopCatalogProductRename`、`ShopCatalogSameDesignGrouper`、`ShopCatalogColorPresentation` 和 `ShopCatalogStyleProfileSharing` 迁入 `Packages/SharedCatalog/Sources/SharedCatalog/Models/`。原 iOS 文件保留迁移入口说明，不保留第二套实现。两个 App 使用同一款式键、颜色词、整款改名和档案改键规则；iOS 原调用方式不变。共享计划增加可选显式款式名，供独立款式名字段使用，默认仍按原名称派生。

Mac 修改商品名/品类时使用该共享计划：被选商品及同款其他颜色（含归档）一起更新，款式档案迁移到新键，原商品 ID、颜色/尺码规格、排序、图片、尺码表、销售历史保持原值。档案目标键已存在时沿用已有的无损合并规则。直接修改「款式名」同样支持已上线商品。不同款或不同系列不参与。

「店家与系列 → 商品 → 编辑…」和「商品管理 → 归属与命名 → 编辑…」两处既有商品表单均调用 `saveProductIdentity`，保存后沿用现有目录自动同步任务。界面显示简短改名结果和影响范围，移除“已上线不能修改”及内部实现说明。已加入衣橱/心愿的记录仍是加入时快照，名称不自动重写。

实际验收进入 431 件商品的「商品管理」时，采样确认主线程反复执行 `publicationTags → changeSet → baselineCatalog → JSONDecoder`，每行重复解码完整目录造成页面长时间无响应。列表现在每次构建只计算一份差分传给各行；详情标签与变更卡共用同一份差分，不引入易失效的全局缓存。取样记录：`/private/tmp/pink-house-product-rename-native-sample-20261017.txt`。

目录保存失败时回滚整款、档案、编辑版本与校验版本；表单不关闭，可用同一输入重试，不留下半套改名。同一次编辑若同时改变名称/品类和所属店家/系列，明确提示先保存改名再调整归属，避免把款式档案跨系列拆开。只读损坏草稿仍禁止写入。

## 验证与交付

所有测试使用隔离存储，不改用户实际商品名，不以真实发布作测试。用户尚未提供目标新名称，由用户在更新后的编辑表单填写。

Xcode 27.0（27A266a），命令均使用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`：

```sh
swift test --package-path Packages/SharedCatalog --filter SharedProductRenameTests
xcodebuild build-for-testing -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2
python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /private/tmp/pink-house-reservation-batches-ops
xcodebuild test -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogProductRenameTests \
  -only-testing:ItemManagerTests/ShopCatalogProductRenameStoreTests \
  -only-testing:ItemManagerTests/ShopCatalogStyleProfileSharingTests \
  -only-testing:ItemManagerTests/ShopCatalogProductCardLogicTests \
  -only-testing:ItemManagerTests/ShopCatalogTitlePresentationTests \
  -resultBundlePath /private/tmp/pink-house-product-rename-ios-20261017.xcresult
SPM_CACHE=/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  MAX_JOBS=2 tools/xcode/build_mac_release.sh
```

147 项测试通过、0 失败：Mac 工作区 83 项，共享显式款式名/档案冲突 2 项，iOS 改名纯逻辑 18 项、真实 Store 6 项、款式档案 12 项、卡片分组/价格 9 项、标题 17 项。Mac 测试覆盖已上线草稿、归档颜色、重开恢复、原图片/价格/规格/尺码表保留、失败回滚及同一输入重试，iOS 旧行为通过原套件验证。目录日期按既有 ISO8601 秒精度比较持久化结果。

最终 Mac Debug `build-for-testing` 与 Release 构建均通过；列表性能改动后工作区 83 项再次通过。新旧完整 entitlement 相同（sandbox / 用户选择文件读写 / 网络客户端），严格签名验证通过。最终版已替换并重新启动 `/Applications/少女心愿运营.app`，安装证据 `/private/tmp/pink-house-product-rename-install-20261017.json`，最终 CDHash `0fa12c91ad4756f57266a7ea79e7df68d316751f`；上一版本保存在 `/Applications/.codex-product-rename-final-20261017-042317/少女心愿运营.app`。

实际 UI 验收：431 件商品的「商品管理」在一次点击与 AX 回读中用时 1792ms，未再出现此前的长时间无响应。搜索“华丽款”，定位「仲夏物语 → 双子星」的 `product-09895a97`，打开其“编辑归属与命名”表单。名称字段可编辑、保存按钮可用，说明已改为“已上线商品也可以修改，保存后自动同步到 App”。窗口保留在该表单，原商品名选中供用户输入；本次未输入目标新名、未点真实保存或发布。真实草稿更新前后均为第 3565 版、4 店家、14 系列、431 商品、617 图片。实际改名持久化和同步入队由隔离工作区测试验证，不把可编辑字段本身当作线上发布成功。

`git diff --check` 通过。日志位于 `/private/tmp/pink-house-product-rename-*-20261017.log`。TestFlight 上传继续暂停。
