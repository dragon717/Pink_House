# App 商品沿用运营排序（2026-10-17）

## 行为与根因

用户要求少女心愿 App 的系列商品类型分区及款式顺序与 Mac 运营排列一致，例如 OP → JSK。

原 App 的 `categories(inSeries:)` 使用独立的 JSK → OP 固定表；Mac 拖拽只保存向导条目顺序，提交商品时没有对应的发布字段。发布合并还会沿用远端数组排列，因此仅重排本地数组无法可靠传到用户端。

现在 `CatalogProduct.displayOrder: Int?` 随稳定商品 ID 发布，Mac 系列提交在条目全部建立商品 ID 后写入顺序。再次提交只更新原商品；未在本次向导出现的商品保持相对顺序接在后面，其他系列不受影响。目录保存、发布草稿箱快照和公共包保留这一字段。

`CatalogProductOrdering` 为共享展示规则：

- 有明确发布顺序时，类型分区按运营中首次出现的位置排列，同类型内按运营款式顺序排列。
- 旧目录缺字段时，使用运营固定类型顺序 OP、JSK、SK、开衫、衬衫、内搭、围裙/罩裙、斗篷、小物、包、其他；兼容旧 Blouse / KC / 鞋，自定义类型仍保留。
- 相同顺序号、缺值和非法负数保持稳定，不按名称或随机 Set 排列，不删除商品。
- App 查询使用最新公开排序，旧本机运营覆盖层不能遮住新顺序；商品其他字段及本地编辑记录不因排序被改写。
- 系列选购进入合并入橱时沿用列表顺序，取消 UUID 字符串排序。

Mac 固定类型选项直接引用共享规则，自定义输入仍保留。拖拽排序继续先保存录入草稿；系列提交/发布时写入并同步款式顺序。旧目录的 OP → JSK 类型顺序在 App 更新后即可兼容；已发布商品也可在「店家与系列 → 调整排序」直接保存并自动同步，不必重新提交系列，见 [已提交商品排序入口](OPS_EXISTING_PRODUCT_SORTING_2026-10-17.md)。

2026-10-17 后续现场确认：排序字段正确但目标环境缺少商品时，不能把“跳过缺失行”当作同步完成。运营端现冻结其他环境已确认发布的商品资料，补齐本次排序所需的缺失商品，再逐件核验顺序；本机未发布草稿不参与补齐。详见 [排序同步漏项根因修复](OPS_PRODUCT_ORDER_SYNC_ROOT_FIX_2026-10-17.md)。

## 验证

Xcode 27.0（27A266a），`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

```sh
swift test --package-path Packages/SharedCatalog \
  --filter 'CatalogProductOrderingTests|ShopCatalogThreeWayMergeTests'

xcodebuild test -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogProductOrderingTests \
  -only-testing:ItemManagerTests/ShopCatalogStoreTests \
  -only-testing:ItemManagerTests/ShopCatalogDesignGroupTests \
  -resultBundlePath /private/tmp/pink-house-product-order-20261017.xcresult

xcodebuild build-for-testing -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2
python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /private/tmp/pink-house-reservation-batches-ops

tools/time_hall/publication/.venv/bin/python3 tools/time_hall/publication/selftest_product_order.py
```

120 项通过，0 失败：共享排序/合并 15、iOS Store/款式分组/实际页面渲染 27、Mac 工作区 75、Python 真实打包 3。覆盖拖拽后再次提交与重开、冻结快照、旧目录、自定义类型、归档排除、重复/缺失序号、旧本地覆盖层、刷新后顺序、公共包压缩解压和媒体引用改写。

补齐「远端新版明确缺失排序字段时清除旧本机展示排序」后，再执行相同 iOS 参数，仅筛选 `ShopCatalogProductOrderingTests`，结果包 `pink-house-product-order-final-20261017.xcresult`，4 项再次通过（不重复计入总数）。

实际 `ShopCatalogSeriesMenuView` 渲染图已目视核对 OP 两件顺序和下方 JSK / 小物分区；夹具没有图片与价格，空图和待补价格不是线上内容变化。截图：`/private/tmp/pink-house-product-order-screenshots-20261017/334139C1-0617-4428-8E5A-DDDDCF66F879.png`。

日志：`/private/tmp/pink-house-product-order-{shared,ios-tests,ios-final-tests,mac-tests-build,mac-tests,publication-tests}-20261017.log`。`git diff --check` 通过。

## 安装与验证边界

- 通过 `tools/xcode/build_mac_release.sh` 正式入口构建 Release；签名严格校验，新旧 entitlement 完全一致，无调试附加权限。旧包保留备份，已更新并重新启动 `/Applications/少女心愿运营.app`。实际草稿仍第 3414 版、4 店家、13 系列、418 商品、585 图片，更新前后相同。安装记录：`/private/tmp/pink-house-product-order-mac-install-20261017.json`。
- 真机普通 Debug 构建使用相同 project/scheme/SPM 缓存，改为 `build -configuration Debug -destination 'platform=iOS,id=00008140-000C289E1862201C' -derivedDataPath /private/tmp/pink-house-phone-batch-entry-device -jobs 3`，`BUILD SUCCEEDED`。严格签名、原团队及正常 Debug 权限核验通过，无 XCTest 插件。
- 官方 `devicectl device install app` 已安装成功；随后 `device process launch --terminate-existing` 被真机锁屏拒绝（Locked），未声称真机页面已人工验收。解锁手机并打开 App 后运行新版。日志及回执为 `/private/tmp/pink-house-product-order-phone-{build,install,launch}-20261017.*`。
- 本次不重新上传真实商品，不更改用户衣物与价格；TestFlight 上传继续按用户此前要求暂停。测试版仍需以后分发包含本次改动的新客户端。
