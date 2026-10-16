# 系列保存自动同步与入橱修复（2026-10-16）

## 保存即同步

用户确认：系列配置保存后应自动更新开发环境和用户环境，不要求再次点击发布。

系列配置的阶段 / 团次、封面、价格表保存动作分别冻结自己负责的字段。后台任务读取 Development、Production 各自最新目录，应用这些字段，再经原有受控发布器条件切换发布头及回读确认。两端其它商品、价格、图片及下架记录保留各自原值，不把整份本机草稿覆盖到 Production。

待同步字段和分环境回执随本地 SwiftData 草稿保存；连续保存合并，发布期间新保存继续排队。两端均确认才清除同步意图。一端失败保留另一端回执，保存页显示具体原因。中断后的冻结发布先查询结果，不换号盲发。旧版本明确显示“尚未发送发布请求”的已保存团次任务，升级后自动接续；未知发布结果不走这条迁移。其它编辑沿用原同步规则。

## 入橱

- 修复选定颜色但没有规格图绑定时过滤掉所有商品图的问题。优先使用所选配色图，并保留未明确绑定到其它颜色的通用商品图；旧商品没有规格绑定时仍带商品相册。
- 图片保存到 ImageManager 的持久化与引用计数体系。商品有图片却没有可用的所选配色图，或读取 / 保存失败时，明确失败并回滚，不生成空图衣物或发奖励。商品本身没有图片时仍允许无图入橱。
- 单件、整套确认页先显示购买团次，再显示加入方式。多团商品未选有效团次，草稿和落库服务均拒绝保存；单团仍可自动确定。仅心愿收藏不代表已购买，沿用原规则。
- 保存稳定团次 ID，定金入橱按该团生成待付尾款及可解析的日期。后续该团日期变化时及时更新待付记录，不等待整个系列进入尾款阶段。公共目录自动更新后也同步日期并重新协调提醒。全款、已付清及其它团不受影响。

## 实际交付与云端验证：PASS

Mac 正常 Debug 应用已更新至实际使用路径：

`/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/Build/Products/Debug/PinkHouseOps.app`

普通构建和复制前后的 `codesign --verify --deep --strict` 均通过，日常四项权限与原应用一致。旧应用保留于同目录 `.codex-series-config-sync-5b4344d2/PinkHouseOps.previous.app`。旧调试进程退出后启动正常应用，新 PID 9936，启动时间 2026-10-16 01:50:02（Asia/Shanghai）。

新应用自动接续原来已保存的“小狗仪仗队”团次，没有再次点击保存或发布：

| 环境 | 更新前 | 更新后 | 回读根摘要 |
| --- | --- | --- | --- |
| Development | 21 | **22** | `e84ca0220d412bf046a8781e17b1c558bf75f2d34884c7f3de9b5c49b1c2169f` |
| Production | 14 | **15** | `606cf99fa0d3a3603ebdc3e38cab116299f231420876720e7d40e13edc42fe9e` |

Computer Use 在实际系列配置页读到：“已自动同步到开发环境和用户环境，均已回读确认（Development 22，Production 15）。”

独立 CLI 经普通读取路径重新下载两端目录，逐集合、逐系列对比断言：唯一变更为 `series-ops-19AAE8DD.reservationBatches`。两端团次字段完全一致：

- 先行团：`E15F15DF-2E6D-4D4F-9223-CC209F5222CD`；“圣诞节前”，结束描述“一个月”，预约结束 2026-09-26 22:59:13。
- 非圣诞先行团：`25AB0683-3DD2-4074-B288-79D1073CFD14`；“2027年2月中上旬”，结束描述“一个月”。

两端其它集合及系列原有字段保持原值。证据：`/private/tmp/pink-house-catalog-batch-fix-20261016/verification-report.json`；更新前目录位于各环境的 `pulled/`，更新后位于 `verified/`。

## 构建、测试与命令

Xcode 27.0（27A266a）；所有命令显式设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。iOS SDK 27 构建，运行于 Codex DIY Outfit QA / iPhone 17 Pro / iOS 26.3.1，UDID `F64FFA05-1AA0-4C8F-9920-F18A772486CB`。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --package-path Packages/PinkHouseOps \
  --scratch-path /private/tmp/pink-house-catalog-batch-fix-20261016/ops-core \
  --filter 'OpsSeriesConfigUpdateTests|OpsSyncWorkflowTests|OpsCatalogEditSyncTests'

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeImageImportTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeBalanceSyncTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeEntryTests \
  -resultBundlePath /private/tmp/pink-house-catalog-batch-fix-20261016/WardrobeEntry.xcresult

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing \
  -project ItemManager.xcodeproj -scheme PinkHouseOps -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 \
  tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /private/tmp/pink-house-reservation-batches-ops
```

- 服务层：**21 通过、0 失败**。覆盖两端字段保留、保存合并与恢复、移除团次、下架保护及图片归档缺失。
- iOS：**60 通过、0 失败**。覆盖未绑定规格的商品图、配色排除、失败回滚、图片与所选团次 / 尾款日期同时落库，以及预约期间日期更新。
- Mac Workspace：**58 通过、0 失败**。覆盖一次保存自动排队、恢复字段、部分失败不报告完成、旧预检拦截任务自动接续。
- Mac 正常构建：上述 Mac 命令将 `build-for-testing` 改为 `build -configuration Debug`，**BUILD SUCCEEDED**，日志 `mac-normal-build.log`。
- iOS 提醒协调补充后的正常构建：上述 iOS 命令移除测试筛选、结果包与并行测试选项，改为 `build`，**BUILD SUCCEEDED**，日志 `ios-final-build.log`。
- 模拟器 install / launch 通过，PID 9888；terminate 返回 3 表示没有旧进程。Device Hub 读取到新进程衣橱主页；进入时光馆的电脑控制点击返回 `noWindowsAvailable`，不记为完整手动入橱验收。

全部日志及测试结果位于 `/private/tmp/pink-house-catalog-batch-fix-20261016/`。既有 actor 隔离 warning 未阻断构建；本次未增加权限或修改签名身份。

## 边界

云端数据已实际更新；iOS 图片与团次选择修复需随新版客户端安装，已有 TestFlight / App Store 二进制不会因数据发布而更新。本次未上传新的 TestFlight，未执行真机入橱或系统通知实际送达验收。

“圣诞节前”“一个月”等文字保留运营原文。用户随后明确允许节日前提前 5～7 天估算，现统一提前 6 天，规则与验证见 [节日前尾款估算](SHOP_CATALOG_HOLIDAY_BALANCE_DUE_ESTIMATES_2026-10-16.md)；本系列先行团预计为 2026-12-19。用户进一步确认时长描述需要推算截止日，已新增“十天、十五天、一个月”等解析，另补充同步失败时的原任务重试入口，并重新核对 Development 23 / Production 16，见 [尾款结束时长与同步入口](SHOP_CATALOG_BALANCE_DURATION_AND_SYNC_2026-10-16.md)。已有空图衣物未批量回填；图片修复作用于后续入橱。
