# 尾款结束时长与系列同步入口（2026-10-16）

后续真机排查已确认：该手机已下载Development23，但本机旧系列副本遮住团次。修复购买读取、实际入口验证和真机交付见 [手机已发布团次读取修复](SHOP_CATALOG_PUBLISHED_BATCH_CONSUMPTION_2026-10-16.md)；下文“现场客户端原因尚未确定”是本轮排查前的历史边界。

## 录入和日期口径

用户确认：尾款结束为选填，运营常填“十天、十五天、一个月”，应从尾款开始日推算截止日。Mac 与 iOS 共用 `CatalogBalanceDueEstimate.declaredWindow`，不从预约结束日、录入日或入橱当天加时长。

| 运营开始描述 | 结束 / 时长 | 预计开始 | 预计结束 |
| --- | --- | --- | --- |
| 2026年圣诞节前 | 十天 / 10天 | 2026-12-19 | 2026-12-29 |
| 2026年圣诞节前 | 十五天 / 15天 | 2026-12-19 | 2027-01-03 |
| 2026年圣诞节前 | 一个月 / 1个月 | 2026-12-19 | 2027-01-19 |
| 2027年1月底 | 一个月 | 2027-01-31 | 2027-02-28 |
| 2028年1月底 | 一个月 | 2028-01-31 | 2028-02-29 |

- 天数按日历日相加；“一个月”按日历月相加，不固定为30天；跨年、月底及闰年由日历计算。
- 同时接受中文整数一至九十九、阿拉伯数字、天 / 日 / 月 / 个月 / 周、“半个月”（15天）；可含空格。只识别完整时长，不从“大货到后一个月”等缺少事实基准的描述里截取数字。
- 原有“10月中旬”等结束日期描述仍按既有月份和旬规则解析。空白、未知描述、非正数或超限时长保持没有额外截止日；开始时间无法估算时，不凭结束时长制造开始日。
- 保留运营原文及 `approximate` 类型。预计日期用于入橱、待付尾款与提醒，不写成运营公布的具体时间，不改变销售阶段自动流转规则。
- Mac 编辑 / 检查页、iOS 团次编辑、购买批次选择和确认摘要均显示预计结束日期及“结束按开始后…推算”的依据。
- 用户所选稳定团次 ID 随衣物保存，后续时长变更只校准该团未支付记录。金额、备注、其它团和已付清记录沿用既有保护。

## 运营操作入口

进入 **店家与系列 → 选择系列 → 配置团次、发售阶段与价格表…**。

1. 填写团次 / P 次及尾款开始、结束时长，点击该区的“保存发售阶段”。保存自动更新 Development 与 Production，不要求再手动发布。
2. 配置页顶部显示正在更新的环境，以及两端回读确认的发布号。若只保存到本机或某端失败，明确显示原因，不显示两端成功。
3. 失败后在同页顶部点击 **“重试更新开发环境和用户环境”**；有日志时可直接点 **“打开更新日志”**。凭证、仓库授权和连接问题可在主工具栏齿轮“设置 → 发布环境 / 连接配置”中处理。
4. 重试保留同一保存请求、字段快照、冻结发布文件及已确认环境回执。已发送请求先查询；只有查询成功证明未生效且当前发布号、根摘要仍与原基线完全一致，才沿原请求重试上传。查询失败、摘要未知或线上已有不同版本时不覆盖；后者提示核对后重新保存。
5. 手机端 **时光馆 → 店铺时光册首页下拉刷新** 会强制检查公共目录，跳过自动检查节流。新团次选择及本次时长解析需要安装含这些功能的新版客户端；公共目录更新不会替换已安装的 App 二进制。

## 当前两环境独立回读

2026-10-16 03:39（Asia/Shanghai）经受控桥接器 `pull-catalog`，只读重新下载两环境公开目录；两端 `series-ops-19AAE8DD`（小狗仪仗队）团次字段完全一致：

| 环境 | 发布号 | 根清单摘要 |
| --- | --- | --- |
| Development | 23 | `1d960aac0877f78f056d33ae346052e9fdd274d8d3cf351645a945a0b7c55b7f` |
| Production | 16 | `975d4e3d401ce6246f55a18dbafe3c069105a6136cecab6d65f989825d619d57` |

- 先行团：`E15F15DF-2E6D-4D4F-9223-CC209F5222CD`；“圣诞节前”，结束“一个月”，预约结束为 2026-09-27 23:59:13（UTC+8）。
- 非圣诞先行团：`25AB0683-3DD2-4074-B288-79D1073CFD14`；“2027年2月中上旬”，结束“一个月”。
- 两条都保留原录入基准。云端已经有这些描述，升级解析不要求再次发布目录。本轮未修改线上数据。
- 两环境均有35件商品引用此系列，团次不是保存到与商品无关的空系列中。

证据目录 `/private/tmp/pink-house-duration-sync-20261016/`：`cloud-verification.json`、两环境的 `pulled/shop-catalog.json`、`pull-manifest.json` 和 `pull.log`。初次系统 Python 缺少 cryptography，随后使用仓库受控 `.venv/bin/python` 回读成功；这不是运营工具实际同步失败。

已排除当前两环境公开目录缺少上述团次；未读取用户手机的实际安装版本和刷新结果，现场未显示团次的具体客户端原因尚未确定。本机开发模拟器更新不代表 TestFlight / App Store 已更新。

## 验证命令与结果

Xcode 27.0（27A266a），显式使用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。日志根目录为上述证据目录。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --package-path Packages/SharedCatalog \
  --scratch-path /private/tmp/pink-house-duration-sync-20261016/shared-tests

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --package-path Packages/PinkHouseOps \
  --scratch-path /private/tmp/pink-house-duration-sync-20261016/ops-core \
  --filter 'OpsSeriesConfigUpdateTests|OpsCatalogEditSyncTests'

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/CatalogBalanceDueApproximationTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeBalanceSyncTests \
  -only-testing:ItemManagerTests/ShopCatalogPurchaseBatchSelectionTests \
  -resultBundlePath /private/tmp/pink-house-duration-sync-20261016/DurationWardrobe.xcresult

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing \
  -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 \
  tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /private/tmp/pink-house-reservation-batches-ops \
  --reservation-batch-snapshot-dir /private/tmp/pink-house-duration-sync-20261016/mac-screenshots
```

- SharedCatalog：244 通过，0失败，含中文 / 阿拉伯时长、空白及未知结束、年月描述兼容、跨年、月末、闰年和恢复后固定日期。
- 运营服务：16 通过，0失败，含原请求显式重试、不自动循环、未知结果 / 摘要缺失 / 环境不符 / 基线变化拒绝续传。
- Mac Workspace：65 通过，0失败，含失败请求与单环境回执持久化、重启可重试、同一请求恢复后两端才报告成功。最终代码复验日志为 `mac-workspace-final-tests-retry.log`。
- iOS：44 通过，0失败（日期18、批次选择9、尾款同步17）；实际入橱和修改时长后只更新所选团，金额和备注不变。合计369项。
- Mac 与 iOS 正常构建采用上方对应 xcodebuild 参数，改为 `build -configuration Debug` 并移除测试筛选 / 结果包 / 测试并行参数。两端均 **BUILD SUCCEEDED**，最终日志为 `mac-final-with-log-build.log`、`ios-normal-build.log`。
- 隔离 SwiftUI 截图已目视检查 Mac 时长预览和失败重试入口，以及 iOS 选择页的开始 / 结束日期。最终截图位于 `mac-screenshots-final/`、`ios-screenshots/`；不是用户当前业务窗口或真机操作截图。

普通构建后的独立 Mac 测试 runner 首次因缺少 PackageFrameworks 运行时搜索路径而未启动（不是用例失败）；已在正式测试脚本补齐该 rpath，随后对最终普通构建重新执行65项全部通过，并重新生成截图。原失败日志保留为 `mac-workspace-final-tests.log`。

本轮未上传 TestFlight / App Store，未执行真机入橱或系统提醒实际送达验收。模拟器无 iCloud 账号的既有日志不影响本轮测试结果。

## 安装与生效边界

- Mac 已更新至日常使用路径 `/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/Build/Products/Debug/PinkHouseOps.app`。原应用、新构建与更新后应用的严格签名核验通过，4项权限完全一致。旧版保留在同目录 `.codex-balance-duration-92217569/PinkHouseOps.previous.app`。
- 保留用户当前运营进程 PID17663 和编辑窗口，新时长预览、重试与日志按钮在重开运营工具后生效。没有为安装强制退出用户正在使用的进程。安装证据 `mac-install.json`。
- iOS 正常构建已安装到同一目标 `Codex DIY Outfit QA / iPhone 17 Pro / iOS26.3`，UDID见命令，bundle `bugod2.ItemManager`；install通过，terminate返回3表示无旧进程，launch通过，新PID26272。证据 `simulator-install.json`。
- 手机尚未安装新版时，下拉刷新只能更新目录数据，不能获得新代码。此次交付覆盖本机开发构建及模拟器，未把模拟器验证写成用户真机已更新。
