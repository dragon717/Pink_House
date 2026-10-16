# 商品上传团次与独立尾款期（2026-10-14）

## 需求与录入方式

同款商品可能有先行团、一团、二团、三团等，购买者所属团次不同，尾款期也不同。团次名称由运营按实际填写，不自动推断团数或日期；同款商品无需按团次重复建档。

- Mac 上新向导：S2「系列资料」增加「团次与尾款时间」卡片；S4「检查」逐团列出预约结束与尾款起止，随 S5 既有保存和发布流程进入目录快照。
- iOS「录入款式」：公共资料和颜色之间增加同一入口；整批配置和系列配置继续使用已有团次表单。
- 每团可填写预约结束时间，分别声明具体尾款起止、大致尾款起止，或保留待公布。未公布结束时间允许留空。
- 团次资料沿现有系列配置存储，供同系列商品、颜色和尺码共用。团次与运营补录任务批次、销售记录再贩批次分别存储。

## 保存与防串团

`OpsSeriesEntryDraft.reservationBatches` 随向导 JSON 持久化：`nil` 表示本次不编辑、沿用系列声明；非空列表更新团次；空列表是明确撤下分团。旧 JSON 缺键可解码，不清除系列已有团次。关闭编辑开关恢复沿用已保存声明；若要撤下，保持编辑开启并删除列表中的团次。

运营切换店家或系列时重新载入团次和对应阶段、时间；不在视图出现或恢复草稿时覆盖未提交输入。团次 ID 稳定，改名或调整顺序不改变用户归属。

校验在写入前执行：空名称、重名、重复 ID、尾款起止倒置等均拦截并保留输入。声明预约中时，可填写统一预约结束，也可让每团分别填写结束时间。阶段写入失败会阻止继续提交，不报告成功。

iOS 款式录入通过 `updateReservationBatches(seriesID:batches:store:)`，基于最新覆盖层仅更新团次；不覆盖另一窗口刚保存的简介、封面、价格表或共用日期。`saveSeriesConfig` 同样在服务层校验团次。

## 用户入橱与尾款

沿用工作区已接入的 `CatalogSeries.reservationBatches` 和 `Clothing.catalogReservationBatchID`：单件和整套入橱都显示所属团次及尾款期，只有一团时自动确定，多团需明确选择。提醒与后续同步只读取所选团，不把其他团或旧系列共用日期当作该团尾款。

未选团的多团旧记录、已移除团次、没有可解析尾款声明的团次，不自动猜测日期。用户备注保持原文。

## 验证命令与边界

本机 Xcode 27.0（27A266a），显式设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。构建使用既有 SPM 缓存和临时 DerivedData。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --package-path Packages/SharedCatalog \
  --scratch-path /tmp/pink-house-reservation-batches-shared

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing \
  -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 \
  tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /tmp/pink-house-reservation-batches-ops \
  --reservation-batch-snapshot-dir /tmp/pink-house-upload-batches-visual-20261014

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=FA7332BE-B29E-4879-A139-C68A24314DB1' \
  -derivedDataPath /tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeEntryTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeBalanceSyncTests \
  -only-testing:ItemManagerTests/ShopCatalogBatchSeriesConfigSyncTests \
  -only-testing:ItemManagerTests/ShopCatalogSeriesConfigFormTests \
  -only-testing:ItemManagerTests/CatalogSeriesSalePhaseResolverTests \
  -only-testing:ItemManagerTests/CatalogSeriesBalanceDueTests \
  -resultBundlePath /tmp/pink-house-upload-batches-ios-20261014.xcresult -quiet
```

### 本次结果

| 检查 | 结果 |
| --- | --- |
| SharedCatalog `swift test` | **PASS：207 项通过，0 失败** |
| Mac `xcodebuild build-for-testing` | **TEST BUILD SUCCEEDED**，应用及测试目标均通过 |
| Mac 无宿主 Workspace 回归 | **PASS：54 项通过，0 失败**，含本次新增 5 项团次上传回归 |
| Mac 真实 SwiftUI 截图 | **PASS**，已目视检查 S2 团次表单及 S4 各团尾款摘要 |
| iOS 首次 `xcodebuild test` | 应用及测试二进制生成；停在模拟器安装阶段，手动终止（143），**运行测试未通过验收** |
| iOS 替代运行及单独测试构建 | 下列两次尝试均停在 Xcode 准备 / 包解析阶段，手动终止；不计作测试或构建通过 |

后续尝试命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test-without-building \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=826F5E71-D2BC-4E76-A8C5-4251C526A5D4' \
  -derivedDataPath /tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeEntryTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeBalanceSyncTests \
  -only-testing:ItemManagerTests/ShopCatalogBatchSeriesConfigSyncTests \
  -only-testing:ItemManagerTests/ShopCatalogSeriesConfigFormTests \
  -only-testing:ItemManagerTests/CatalogSeriesSalePhaseResolverTests \
  -only-testing:ItemManagerTests/CatalogSeriesBalanceDueTests \
  -resultBundlePath /tmp/pink-house-upload-batches-ios26-20261014.xcresult

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2
```

日志：`/tmp/pink-house-upload-batches-shared-20261014.log`、`/tmp/pink-house-upload-batches-ops-final-20261014.log`、`/tmp/pink-house-upload-batches-ops-tests-final-20261014.log`、`/tmp/pink-house-upload-batches-ios-20261014.log`、`/tmp/pink-house-upload-batches-ios26-20261014.log`、`/tmp/pink-house-upload-batches-ios-build-for-testing-20261014.log`。首轮 Xcode 采样明确停在 `SimDevice installApplication`；`/tmp/pink-house-upload-batches-ios-xcode-sample-20261014.txt` 保留诊断。

Mac 回归使用无联网写入的临时 Workspace 和无 App 宿主 XCTest runner；截图来自当前构建的实际 SwiftUI 表单，位于 `/tmp/pink-house-upload-batches-visual-20261014/`。iOS 测试二进制 `/tmp/pink-house-reservation-batches-ios/Build/Products/Debug-iphonesimulator/ItemManager.app/PlugIns/ItemManagerTests.xctest/ItemManagerTests` 于本轮 20:08 生成，不能以此替代执行结果。未进行真机验收、iOS 上传页视觉点击或线上 CloudKit 发布。未修改生产商品，未补填未知团次及日期。

## Mac 实际使用入口与构建交付补充

用户后续截图位于「店家与系列」，现场进程仍是 10 月 12 日启动的旧进程，原路径的二进制构建时间为 10 月 11 日。前轮临时目录的构建和截图并未替换这份正在使用的 App，不能视为真实应用已经更新。

- 上新：左侧「系列上新」选择店家 / 系列后进入 S2；「团次与尾款时间」卡片移到系列封面后、价格表前，避免入口埋在页面底部。S4 继续逐团列出时间摘要。
- 已有系列：左侧「店家与系列」选中系列，底部及右键菜单入口明确命名为「配置团次、发售阶段与价格表…」，进入后可编辑「预约团次与尾款时间」。
- 本机实际启动路径：`/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/Build/Products/Debug/PinkHouseOps.app`。
- 交付时按普通 App 配置构建实际使用路径，退出旧进程后从该明确路径启动；核对新进程启动时间、二进制时间和入口文案。测试构建的附加沙盒权限不作为日常运行配置交付，临时截图也不能替代真实运行版本核对。

普通构建命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ItemManager.xcodeproj -scheme PinkHouseOps -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 build
```

本轮构建日志：`/tmp/pink-house-ops-running-app-update-20261014.log`。更新前应用副本：`/tmp/pink-house-ops-before-visible-update-20261014/PinkHouseOps.app`。

原路径首次 SDK 缓存重建耗时较长，该次构建已中止（143）；后续复用已通过回归的缓存，以普通 `build` 重新生成 App，再更新原启动路径：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ItemManager.xcodeproj -scheme PinkHouseOps -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 build
```

该次日志：`/tmp/pink-house-ops-visible-entry-normal-build-20261014.log`。交付流程检查 `codesign --verify --deep --strict`、日常 Debug 的原有四项权限及新入口文案；复制到同文件系统的暂存目录并复验签名后替换原路径，旧应用保留在暂存目录中，再通过 `open -a` 启动明确路径。

电脑控制工具两次未返回窗口状态；系统辅助功能读取为未启用。因此本轮不会把源码或二进制核对写成真实窗口的自动点击验收。

### 2026-10-15 实际应用交付结果

- 普通 Mac 构建 **BUILD SUCCEEDED**（日志第 224 行），未重复运行未受此次入口文案 / 排列影响的业务回归。
- 构建产物和复制后的原路径应用均通过 `codesign --verify --deep --strict`；主应用只带原有四项 Debug 权限，TeamIdentifier 仍为 `833FJ74GS2`。
- 二进制包含「配置团次、发售阶段与价格表…」「团次与尾款时间」「添加团次」三个入口文案。
- 原启动路径已替换并通过 `open -a` 打开。现场进程 PID `3189`，启动时间 **2026-10-15 01:17:08**；二进制及签名时间 **01:16**，已排除旧进程仍在运行的情况。
- 替换采用同文件系统暂存与目录重命名，旧应用另外保留在 `Build/Products/Debug/.codex-ops-update-db6e_83x/PinkHouseOps.previous.app`；更新前的临时目录副本仍保留。
- 验收边界仍为普通构建、签名、二进制入口与实际启动进程核对；没有把系统未授权的自动页面点击记为已完成。

构建后排查发现，本轮 iOS 27 测试设备 `FA7332BE-B29E-4879-A139-C68A24314DB1` 在关闭后仍有脱离模拟器的服务，造成系统持续高负载。清理仅针对同用户、父进程为 1、iOS 27 runtime 路径且进程环境中的 `SIMULATOR_UDID` 与该测试设备精确相符的服务；先发送 TERM，对未退出的服务再定向终止。复核匹配服务数为 0。未执行全局模拟器关闭，也未终止用户原有 iOS 26.3 设备的服务。负载均值需要时间回落，未将其即时归零作为本轮验收结论。


## 2026-10-15 大致尾款时间优先录入

用户确认：尾款一般只公布「1月上旬、2月中旬、3月下旬」等大致时间，系统应据此推算，具体日期输入继续保留。

- Mac 系列配置、上新向导与 iOS 团次表单：新增团次默认「大致时间」，三种粒度直接并排显示；预约结束时间移至尾款录入之后，标为选填，不再称为估算前置基准。
- 填入月份与旬后显示完整的预计尾款日期。按用户后续确认，各旬固定取中间日：上旬 / 月初为 5 日，中旬为 15 日，下旬为 25 日；中下旬为 20 日，明确写月末 / 月底仍取当月最后一天。结束描述仍选填；具体日期的开始 / 结束输入保留。
- 新团次以 `balanceDueReferenceAt` 固定大致时间录入的时间基准，仅用来推算省略的年份。已过月份（或同月已过的旬）顺延至次年；可填写「2027年1月上旬」明确年份。该基准是 Optional，旧 JSON 缺键兼容；不伪装成预约结束或具体尾款时间。
- 原文及基准随草稿、目录和发布快照保存。所选团次的 `paymentSchedule` 使用固定年份的描述；不以用户入橱当天重算年份，不跨团套用日期。明确年月可在没有预约结束日期时估算。
- 共用纯逻辑放在 `SharedCatalog.CatalogBalanceDueEstimate`；Mac 预览、iOS 入橱与尾款同步走同一算法。大致日期用于用户记录和提醒，仍不冒充运营已公布的具体收款日期驱动销售阶段流转。
- 旧的「只有旬、没有月份」仍需预约结束等有效基准；原先「春节前」不参与估算的行为已由 2026-10-16 用户确认的 [节日前提前六天规则](SHOP_CATALOG_HOLIDAY_BALANCE_DUE_ESTIMATES_2026-10-16.md) 取代，原文仍保留。预约中阶段的预约结束校验保持既有规则，可统一填写或逐团填写，与大致尾款估算无关。

### 本轮验证与交付

Xcode 27.0（27A266a），命令统一设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

```sh
swift test --package-path Packages/SharedCatalog --scratch-path /tmp/pink-house-reservation-batches-shared

xcodebuild build-for-testing -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3

python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /tmp/pink-house-reservation-batches-ops \
  --reservation-batch-snapshot-dir /tmp/pink-house-approximate-tail-20261015/screenshots

xcodebuild build -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2

xcodebuild build -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2
```

- SharedCatalog：**229 项通过，0 失败**，包括既有估算契约、新增无预约结束的月份 / 旬估算、闰月、跨年、明确历史年月、旧 JSON、固定基准落盘与团次排期投影。
- Mac 测试构建及日常普通构建：**通过**。Workspace 保存回归 **55 项通过，0 失败**，新增大致时间无预约结束的草稿恢复和发布快照检查。
- 前轮旧规则截图（已由下节中间日规则替代）：`/tmp/pink-house-approximate-tail-20261015/screenshots/approximate-tail-editor.png` 展示 1月上旬 → 2027-01-10、2月中旬 → 2027-02-20、3月下旬 → 2027-03-31，及保留的具体日期输入。另保留上新页和检查页截图。
- 普通构建产物已更新到上述本机实际使用路径并启动，更新前后均通过 `codesign --verify --deep --strict`；日常四项权限保持。旧应用保存在 `Build/Products/Debug/.codex-ops-approximate-tail-20261015/PinkHouseOps.previous.app`。
- 完整命令日志位于 `/tmp/pink-house-approximate-tail-20261015/`。没有发布线上商品；截图来自临时内存 Workspace，没有将截图夹具当作实际用户目录数据。

- iOS 通用模拟器构建：**BUILD SUCCEEDED**（arm64 / x86_64）。本轮未启动模拟器运行 XCTest、未做 iOS 界面点击验收或真机验收；日期逻辑已由共享包测试覆盖，不能将编译通过视为 UI 验收通过。
- 本机 Mac 新进程 PID `3808`，启动时间 **2026-10-15 04:26:46**，二进制时间 **04:26:23**，确认启动的是本轮普通构建。


## 2026-10-15 旬时间改为固定中间日

用户进一步确认「上中下旬都取中间值去固定推算」。正式口径改为 **上旬 5 日、中旬 15 日、下旬 25 日**，普通 2 月、闰年 2 月、30 天和 31 天的月份均使用相同固定日；中下旬取 20 日。明确写「月末 / 月底」的描述保留月末含义。此规则取代前轮按旬末 10 / 20 / 月末估算的口径。

Mac 录入预览、iOS 入橱与同步继续共用 `CatalogBalanceDueEstimate`。两端说明文案、纯逻辑测试、衣橱同步断言和 Mac 草稿 / 发布快照断言同步更新。具体时间、年份推算与固定基准逻辑不变。

本轮使用与上节相同的 Xcode 27.0 与构建参数，iOS 命令增加构建设置 `ARCHS=arm64` 以验证本机模拟器架构。日志及新截图目录为 `/tmp/pink-house-tail-midpoint-20261015/`；本轮验证结果在下方记录。


- SharedCatalog：**230 项通过，0 失败**，新增 28 / 29 / 30 / 31 天月份都固定取 5 / 15 / 25 日的回归。
- Mac 测试构建和普通构建：**通过**；Workspace 回归 **55 项通过，0 失败**。
- 新版实际 SwiftUI 表单截图已目视确认：`/tmp/pink-house-tail-midpoint-20261015/screenshots/approximate-tail-editor.png` 显示 **2027-01-05、2027-02-15、2027-03-25**，说明文案同步使用中间日。
- iOS 首次带 `-arch arm64` 的命令被 Xcode 拒绝（退出 70，destination 与 `-arch` 重复声明架构）；改用下列构建设置后 **BUILD SUCCEEDED**。本轮未运行 iOS 模拟器 XCTest 或界面验收。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'generic/platform=iOS Simulator' ARCHS=arm64 \
  -derivedDataPath /tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3
```

- 日常 Mac 应用已更新至原路径，通过签名复验后启动新进程 PID `29643`（**2026-10-15 11:26:31**）。电脑控制确认更新前后均为已保存第 1413 版、同一店家与系列，没有更改或发布目录内容。旧 App 保存在 `Build/Products/Debug/.codex-ops-tail-midpoint-20261015/PinkHouseOps.previous.app`。


## 2026-10-16 系列配置保存即更新两环境

已有系列配置的保存会自动把本次保存的字段应用到两端最新目录并回读，无需再次发布；整份本机草稿的其它冲突不再阻断该字段更新。原先明确尚未发送发布请求的已保存团次可自动接续。本次已验证 Development 22、Production 15，详见 [保存自动同步与入橱修复](SHOP_CATALOG_SERIES_SAVE_AND_WARDROBE_FIX_2026-10-16.md)。
