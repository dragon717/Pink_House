# 修复提交后的死代码检查（2026-10-28）

按用户要求先提交业务修复，基线为 `61ae36b0`，然后进行独立的死代码清理。

## 检查方法与范围

使用 `rg --files` 枚举 App、运营端、共享包和测试的 719 个 Swift 源文件，统计声明与引用，再逐项查看调用点和实现。单次文本命中只用于发现候选；SwiftUI / UIKit / SpriteKit 协议回调、SwiftData 存储字段、编码键以及条件编译入口需要额外判断。例如 `ScrollDropDelegate.dropExited` 由框架调用，继续保留。

本轮人工核对并删除的是安财、衣橱、系列汇总及入橱图片链路的确定无引用代码。扫描范围不等于已证明整个仓库没有死代码。工作区已有的运营排序、改名等其他修改保持原状，未混入这两次提交。

## 删除内容

| 范围 | 删除的代码与原因 |
| --- | --- |
| 安财场景 | 黄金、白银、虚拟币三处 `updateBackgroundColor` 及未使用的 `none` 碰撞分类。透明背景由 `WealthPhysicsHost` 统一设置。 |
| 财富音效 | 无调用的 `playPewSound`、专用播放器及预加载、`generatePewSound`；同时删除仅被写入的 `isRolling` 和无读取的 `fireworksSoundID`。避免初始化时生成和加载永远不会播放的音效。 |
| 旧视图 | `FortuneStickView`、`WardrobeListCellContainer`、`BookDetailViewFromWardrobe`、`FilterStringSection` 均未被实例化；保留当前页面正在使用的视图和背景组件。 |
| 草稿 | 无调用的 `flushNow`、`loadDraftID`、`hasDraft` 及因此失去唯一调用的同步 `loadDraft()`、`loadLegacyDraftID`。现用异步读盘、草稿存在性缓存、保存和旧草稿恢复仍保留。 |
| 衣橱及目录辅助接口 | 无引用的 `shortName`、旧迁移来源常量、`moneyString`、`formattedRecordDate`、`defaultReservationDeposit`、`productsSortedByName`、`installedRemoteCatalog`、`resetSessionFailuresForTesting`。 |
| 系列及 AI | 旧 `String.isNumber` 扩展，以及无调用的 `buildPromptWithRelevantWardrobeContext`、`generateItemDetail`。仍有引用的标准库 `Character.isNumber` 和现用 AI 上下文入口保留。 |

同步删除旧编译故障猜测注释，并将入橱默认值文档开头改为当前“一次确认、分别入橱”规则；2026-10-17 的队列逐件确认注明历史、已被取代。

本轮业务代码及旧说明共删除 423 行、替换 3 行；未删除持久化字段、用户数据或图片素材。

## 验证

删除符号的跨目录复查已无运行时 / 测试引用，`git diff --cached --check` 通过。删除检查覆盖具体类型及调用链，不把函数声明与注释当成使用证据。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/WealthPhysicsSurfaceTests \
  -only-testing:ItemManagerTests/ClothingAccessoryTests \
  -only-testing:ItemManagerTests/ClothingConditionTests \
  -only-testing:ItemManagerTests/WardrobeOwnershipFilterTests \
  -only-testing:ItemManagerTests/SeriesAnalyzerTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeImageImportTests test
```

结果：`TEST SUCCEEDED`，构建通过，71 项定向回归全部通过、0 失败。覆盖安财场景 8 项、小物金额 23 项、成色 8 项、已拥有筛选 8 项、系列分组 8 项、图片入橱 16 项。环境为 Xcode 27.0（27A266a）、iOS 26.3.1 模拟器。日志：`/private/tmp/pink-house-dead-code-cleanup-tests.log`。

安财删除前的新构建已完成模拟器页面验收，见 [安财验证记录](WEALTH_STORAGE_RENDERING_FIX_2026-10-28.md)。本轮无真机传感器、触感或线上交易验收，不重复声称此前已记录失败的入橱 UIHosting 截图测试通过。
