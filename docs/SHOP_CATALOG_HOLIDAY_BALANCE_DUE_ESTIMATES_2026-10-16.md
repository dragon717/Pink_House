# 节日前尾款日期估算（2026-10-16）

## 用户确认与规则

用户明确允许根据节假日描述，提前 5～7 天设置预计尾款日期。实现固定取中间值 **6 天**，保证运营预览、入橱和后续同步结果一致：

| 运营描述 | 预计日期 |
| --- | --- |
| 2026年圣诞节前 | 2026-12-19（12月25日前6天） |
| 2026年平安夜前 | 2026-12-18（12月24日前6天） |
| 2027年春节前 | 2027-01-31（2月6日前6天） |
| 2027年元旦前 | 2026-12-26（1月1日前6天） |

目录继续保存运营原文及 `approximate` 类型；计算结果供预计尾款与提醒使用，不写成运营已公布的具体日期，也不驱动具体尾款销售阶段。界面展示实际估算依据，例如“在圣诞节前6天估算”。

## 可识别范围与年份

- 公历节日：圣诞节、平安夜、元旦、国庆节、劳动节／五一、儿童节／六一、妇女节、情人节。
- 农历节日：春节／农历新年、除夕、元宵、端午、七夕、中秋、重阳。按中国农历对应年份换算，不固定成某个公历月日；七夕情人节按七夕解释。
- 支持“前”“之前”“以前”“前夕”及常见繁体别名。“节后”“前后”、未指明节日、多个节日二选一和“节前一个月／前5天”等明确偏移，不套用六天规则。
- 明确年份保持原值；今年、明年、后年、去年、前年相对运营录入基准解释。未写年份时，按基准选择尚未过去的节日；节日未到但预计日期已过时，仍保留本次节日。
- 团次使用持久化的 `balanceDueReferenceAt` 固定年份，跨年入橱、恢复目录或后续同步不按入橱当天重新滚动。元旦固定节日年份，避免提前六天跨年后再错减一年。
- 缺少明确年份且没有有效基准，或节日尚未支持时，仍返回无法估算；用户可自行指定日期。
- 农历换算使用东八区农历，得到公历月日后转为用户时区的当地日期，避免旅行造成节日日期变化。

农历测试样例核对香港天文台的 [2026年公历与农历对照表](https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2026e.pdf) 与 [2027年对照表](https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2027e.pdf)：春节分别为 2月17日、2月6日，中秋分别为 9月25日、9月15日；2026年端午为 6月19日、七夕为 8月19日。

## 接入与已有记录

- `SharedCatalog/CatalogHolidayEstimate.swift` 负责节日识别及换算，`CatalogBalanceDueEstimate` 为 Mac 与 iOS 的共用入口。
- Mac 系列配置、iOS 团次编辑及商品详情展示预计日期和估算依据；原文仍可编辑。
- 入橱确认选择购买团次后，按该团生成预计尾款日期。已选团次且尚未支付的记录，也可在目录同步时补齐或更新日期。
- 目录返回 `upToDate` 时同样执行尾款校准：客户端升级了估算规则但目录序号未变，也能更新已有记录并协调提醒。
- 原结束描述保留原文；用户随后确认“十天、十五天、一个月”应从开始日推算结束日，已补充共用解析，见 [尾款结束时长与同步入口](SHOP_CATALOG_BALANCE_DURATION_AND_SYNC_2026-10-16.md)。无法解析的结束描述不产生额外截止日期。

已发布的“先行团”保留“圣诞节前”及 2026-10-15 录入基准；新客户端据此估算为 2026-12-19。无需为这条规则再次保存或发布目录。

## 验证

Xcode `/Applications/Xcode.app`，27.0（27A266a）。以下命令均通过：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --package-path Packages/SharedCatalog \
  --scratch-path /private/tmp/pink-house-holiday-estimates-20261016/shared-tests

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 \
  -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/CatalogBalanceDueApproximationTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeBalanceSyncTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeEntryTests \
  -resultBundlePath /private/tmp/pink-house-holiday-estimates-20261016/HolidayWardrobe.xcresult

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project ItemManager.xcodeproj -scheme PinkHouseOps -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2
```

- 共用模块：**240 通过，0 失败**；包含节日、农历、相对年份、跨年、恢复与时区测试。
- iOS：**67 通过，0 失败**；包含真实入橱落库、既有空日期补齐，以及原文、团次、金额与用户备注保留。
- Mac：**BUILD SUCCEEDED**。共计 **307 项测试通过**。
- 日志与结果包：`/private/tmp/pink-house-holiday-estimates-20261016/`。

## 安装与验收边界

新版 Mac 应用已更新到日常启动路径：`/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/Build/Products/Debug/PinkHouseOps.app`。原应用、暂存副本和更新后应用的 `codesign --verify --deep --strict` 通过，权限与原版一致。

用户当前停在商品录入向导，保留运行进程与当前窗口；重开工具后新预览生效。旧应用保存在同目录 `.codex-holiday-estimate-1703f4af/PinkHouseOps.previous.app`，安装记录为日志目录内的 `mac-install.txt`。

本次未重新发布云端目录、未上传 TestFlight。iOS 规则随新版客户端生效；本次验证包含模拟器测试与构建，未记为真机操作、Mac 新预览手动操作或系统提醒实际送达验收。
