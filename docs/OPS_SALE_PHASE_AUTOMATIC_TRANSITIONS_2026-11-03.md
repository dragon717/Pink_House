# 运营 App 发售阶段按时间自动流转（2026-11-03）

## 根因与规则

Mac 目录、系列配置和本地预览原先直接显示 `CatalogSeries.salePhase` 的保存值，未使用手机端已有的时间推导。现在将纯推导收口到 SharedCatalog 的 `CatalogSeriesSalePhasePolicy`；手机端原 resolver 委托同一规则，保留原签名。

- 声明预约中且已超过预约结束时间：显示「预约已结束」。无尾款日期时保持此状态，等待运营公布。
- 预约已结束，且具体尾款开始时间已到：显示「尾款中」。未到开始时间仍显示「预约已结束」。
- 「圣诞节前」等大致描述只作预计展示，不据此自动收尾款。
- 团次分别按自己的档期推导；系列总览优先展示已有团次进入的尾款阶段，其次为仍在预约的团次。入橱继续使用所选团次投影。
- 运营明确选择尾款中或现货时保留该选择。尾款结束不自动等于现货。
- 未声明阶段、缺少预约结束时间的兼容行为保持原口径。预约结束沿用严格超过边界，具体尾款开始包含边界时刻。

自动变化是展示的当前生效阶段，不覆盖保存的声明、价格、团次或日期，不产生云端写入。系列配置的选择器显示生效阶段，修改后仍沿既有保存和两环境更新流程提交。

## 页面保持打开时

`OpsSeriesPhaseTimeline` 在出现时读取当前时间，只为实际阶段边界安排可取消的异步等待；页面消失后取消，修改日期后重新安排。回到前台或系统时钟改变时重新求值。没有每秒扫描目录或定时发布。

目录徽标、选中系列摘要、本地预览和系列配置统一使用传入的当前时间，确保跨边界时子视图实际更新。

## 验证

Xcode 27.0（27A266a），`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

```sh
swift test --package-path Packages/SharedCatalog

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing \
  -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/chart-units-debug \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data build/chart-units-debug \
  --sale-phase-snapshot-dir /private/tmp/pink-phase-snapshots

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  SPM_CACHE=/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  tools/xcode/build_mac_release.sh
```

- SharedCatalog：266 项通过，含 7 项新阶段规则测试。
- Mac：测试目标构建通过，111 项实际 XCTest 通过。独立 runner 不启动真实 App 宿主，使用内存数据，不进行云端写入。
- 原 iOS resolver 的 22 项纯逻辑测试：将真实 resolver 源码与原测试类编译为 Mac 独立 runner，全部通过；这不代表完整 iOS 构建或模拟器验收。
- 真实 SwiftUI 系列配置截图：预约结束等待尾款、已进入具体尾款时间，两种选择器显示均正确。
- 同一个 SwiftUI 窗口持续跨过预约结束和尾款开始：依次观察到预约中 → 预约已结束 → 尾款中，无刷新、保存或网络请求。
- 日志：`/private/tmp/pink-phase-shared-tests.log`、`/private/tmp/pink-phase-mac-build.log`、`/private/tmp/pink-phase-mac-tests.log`、`/private/tmp/pink-phase-ios-compat.log`。
- Release 构建与严格签名校验通过，已安装到 `/Applications/少女心愿运营.app` 并正常重启；bundle ID、签名团队和全部 entitlements 与旧版一致。安装记录：`/private/tmp/pink-house-sale-phase-install-20261103.json`，旧 App 保留在 `/Applications/.codex-sale-phase-backup-20261103-043043/少女心愿运营.app`。
- 已安装版本实际点击「店家与系列」成功切页；「小狗仪仗队」列表、摘要和配置页均显示「预约已结束」。核对原预约结束为 2026/10/20、尾款仍为大致时间；只读验收后关闭配置页，没有保存业务变更。草稿仍为第 3747 版，4 店家、15 系列、447 商品、665 图片。

本次未改线上业务资料，未发布手机安装包。
