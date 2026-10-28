# 现有 TestFlight 商品数组排序根因修复（2026-10-17）

## 用户截图与准确根因

用户再次提供仲夏物语 → 双子星的运营列表与手机点菜页截图：运营 JSK 前几项为正腰 JSK、正腰 JSK+胸针（一对）、正腰 JSK+项链、正腰 JSK+项链+胸针（一对）；手机却为正腰 JSK、纯色 JSK、纯色 JSK+项链、纯色 JSK+眼罩发带。

正常诊断导出保存的 Production 23 目录中，商品数组前四个 JSK **逐项就是手机截图的四项**，同时它们的 `displayOrder` 分别为 36、48、50、52。运营保存的真实顺序 36、37、38、39 没有落实到发布数组。旧版 `ShopCatalogStore.products(inSeries:)` 直接过滤数组，合并卡片也保留首次出现顺序，不认识新增排序字段，因此只能继续展示旧数组。此前确认 145 个排序编号正确、以及新客户端读编号的测试通过，都不能证明已分发旧客户端的实际显示正确。这是前一次排查与验收遗漏。

本次异常手机由用户确认使用 TestFlight，上传新二进制仍受其暂停指令约束。该问题可以通过修复发布数据的兼容顺序解决，不以恢复 TestFlight 上传为前置条件。

## 修复位置

- `CatalogProductOrdering.publicationOrder`：对明确保存过顺序的系列，将商品数组按相同运营规则重排。各店家/系列仍占据原数组中的位置，没有明确排序的系列保持旧顺序；不改任何商品字段、稳定 ID 或图片绑定。
- `OpsSeriesConfigUpdate.applying`：排序任务同时落实编号与实际数组顺序；补齐缺失商品可能追加数组，因此 `OpsWorkspace+SeriesConfigSync` 在关联补齐之后再次落实发布顺序。
- `verifyProductOrders`：逐 ID 核对存在、归属与编号之后，还核对回读列表的实际顺序。编号正确而数组仍旧时拒绝确认，不能显示同步完成。
- Python 正式 `build_shop_catalog_pack`：完成归档剔除后，对所有有明确排序的系列进行相同数组排序。覆盖普通发布、图片重写与完整目录构建，避免下一次发布又恢复旧数组。
- 已保存排序补核对迁移升到版本 2；版本 1 只检查缺商品与编号，不再被视为已完成数组兼容。升级后自动重新核对已保存排序，不需要重新拖动，不改变本机业务目录或编辑版本。

## 复现与测试

先把真实构包回归改为断言旧客户端看到的原始数组，旧实现 4 项中失败 3 项，包含截图同名款式前后插入的问题。日志 `/private/tmp/pink-house-legacy-array-before-20261017.log`。修复后的构包回归 5 项通过。

正常保存面板导出的 `/private/tmp/pink-house-legacy-array-before-20261017.json` 为草稿 3568，431 件商品。用其中真实 Production 23 目录运行正式构包器，双子星全部 145 件商品的**原始数组 ID**与运营顺序逐项一致；构包前后商品按 ID 对照逐字段相同。JSK 的前 12 项均为正腰及其组合款，纯色不再插在第二张卡。记录 `/private/tmp/pink-house-legacy-array-real-pack-proof-20261017.json`。这一步是离线构包复现，不等同于线上已切换版本或手机已刷新。

Xcode 27.0 / 27A266a，构建显式 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

```sh
swift test --package-path Packages/SharedCatalog --filter CatalogProductOrderingTests
swift test --package-path Packages/PinkHouseOps \
  --filter 'OpsSeriesConfigUpdateTests|OpsCatalogEditorUpdateTests|OpsCatalogEditSyncTests|OpsCatalogMergeBaselineTests|OpsDataSyncProgressTests'
python3 tools/time_hall/publication/selftest_product_order.py
python3 tools/time_hall/publication/selftest_shop_catalog.py
python3 tools/time_hall/publication/selftest_ops_sync.py
xcodebuild build-for-testing -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2
python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /private/tmp/pink-house-reservation-batches-ops
SPM_CACHE=/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  MAX_JOBS=2 tools/xcode/build_mac_release.sh
```

共享排序 6 项、核心 48 项、工作区 97 项、构包排序 5 项通过，目录归档裁剪与桥接自测通过，Debug 测试构建和 Release 构建通过。覆盖版本 1 补核对任务升级、正确编号却旧数组不能确认、关联补齐后重排、跨系列位置保留、未排序旧系列不变、归档过滤及图片绑定。

## 部署与验证状态

新版 `/Users/sangyu/develop/Pink_House/build/mac-release/少女心愿运营.app` 严格签名通过，完整 entitlement 与已安装版相同。用户确认 Mac 已解锁、运营工具在前台后，已从正常菜单退出旧版，确认进程结束后安装修复版。旧包保存在 `/Applications/.codex-legacy-product-order-20261017-160442/少女心愿运营.app`；新 CDHash `bee807be7b9c23083410cc19e68c1c82f89c646b`；安装记录 `/private/tmp/pink-house-legacy-array-install-20261017.json`。新进程恢复草稿 3568、4 店家 / 14 系列 / 431 商品 / 617 图片，自动开始旧排序版本 1 → 2 的补核对任务。已完成 Development 26、Production 24 的同步与回读，进度 100%；正常退出并重启后仍恢复相同草稿、两个环境版本与完成进度，未重新启动补核对任务。TestFlight 上传继续暂停。


同步期间发现磁盘仅余约 116 MB，画面读取失败，并出现“云端结果已收到，但本机同步记录保存失败；default.store 无法打开”。只清理本次任务生成且无构建进程使用的 `/private/tmp/pink-house-reservation-batches-ios/Build`，保留源码、最终 xcresult、4.2（3）归档与全部运营资料；释放后可用空间从约 108 MiB 恢复至 1.67 GiB。清理记录 `/private/tmp/pink-house-legacy-array-build-cache-cleanup-20261017.json`。通过正常按钮“继续同步并核对结果”恢复原冻结任务，先查询已发送结果，再继续回读，未新建重复发布。

最终通过正常保存面板导出 `/private/tmp/pink-house-legacy-array-after-20261017.json`。与更新前逐项比较：本机目录和编辑版本 3568 完全相同；Development 保持 436 件、Production 保持 431 件；两个环境全部商品按 ID 对照逐字段相同，其余目录字段与数组也完全相同，只有商品数组顺序变化。双子星 145 件、许愿池 13 件的原始数组 ID 均与运营顺序逐项一致。JSK 前六项为正腰 JSK、正腰 JSK+胸针（一对）、正腰 JSK+项链、正腰 JSK+项链+胸针（一对）、正腰 JSK+眼罩发带、正腰 JSK+胸针（一对）+眼罩发带。验证明细 `/private/tmp/pink-house-legacy-array-live-verification-20261017.json`。

Development 26 根摘要 `39fde747df1dab441b0be8871acc2421b85a3502d610bdd6952c5dc646044f96`；Production 24 根摘要 `eb5b46787e886cc92d7a5c8c4f2c4735b39345b9a94250a51de6440674d2c301`。当前 TestFlight 手机用户刷新后明确确认「已与运营顺序一致」，完成本次手机端验收。没有把编号核对或新开发版测试替代旧版手机验收。

为保障剩余同步落盘，后续仅清理了本次任务已无构建进程使用的真机 Build、iOS Index.noindex 与当前归档 ArchiveIntermediates 缓存；正式 xcarchive、最终 xcresult、日志与运营资料保留。附加记录 `/private/tmp/pink-house-legacy-array-device-cache-cleanup-20261017.json` 和 `/private/tmp/pink-house-legacy-array-archive-cache-cleanup-20261017.json`。本次未提交、未推送、未上传 TestFlight。
