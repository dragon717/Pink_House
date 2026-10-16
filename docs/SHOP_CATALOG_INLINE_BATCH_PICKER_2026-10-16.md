# 入橱同页选择批次与紧凑档期详情（2026-10-16）

## 当前行为

用户确认以同页操作取代单独的「选择购买批次 → 继续加入衣橱」步骤：

- 已选商品、加入方式、购买批次、主衣物、备注和最终确认位于同一入橱页。
- 购买批次只显示名称菜单，不显示尾款时间、预计日期或估算依据。选择后可以直接确认入橱；单批次仍需主动选择，未选择或原批次已撤下时确认不可用。
- 同系列多件商品共用一次选择，不同系列分别选择；未勾选小物不增加要求。批次ID仍传入原草稿及最终落库路径，按所选批次生成和校准尾款。
- 「P次」是误写，界面统一为「批次」。运营真实命名如1P、2P、P4不自动改写。
- 系列选购页及每件商品详情共用「团次与尾款」折叠行，默认收起、占一行。展开查看各团原文、预计开始 / 结束日期和估算依据；待公布时间如实显示。
- 入橱批次卡使用完整可用宽度，避免随短内容缩窄、居中。

`ShopCatalogPurchaseBatchSelection`仅保存有效选择，不再维护第二份“已继续确认”的状态。公开档期仍使用`seriesForPurchase`，并把同一Store从系列传入商品详情和单件入橱入口，保留既有旧本机副本覆盖修复。

## 验证

Xcode27.0（27A266a）；目标Codex DIY Outfit QA，iOS26.3，UDID F64FFA05-1AA0-4C8F-9920-F18A772486CB。日志根：`/private/tmp/pink-house-inline-batches-20261016/`。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogCloudSyncTests \
  -only-testing:ItemManagerTests/ShopCatalogPurchaseBatchSelectionTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeBalanceSyncTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeEntryTests \
  -resultBundlePath /private/tmp/pink-house-inline-batches-20261016/InlineBatches.xcresult
```

**104项通过，0失败，TEST SUCCEEDED**：公开同步42、批次选择10、尾款联动18、记账34。随后移除商品状态文案里重复的批次尾款全文，重新执行同一命令的`ShopCatalogPurchaseBatchSelectionTests`筛选，结果包`FinalLayout.xcresult`，**10项再次通过**（不是新增10项不同测试）。

最终截图导出至`final-screenshots/`，已目视核对真实合并页、系列页、商品详情、选中批次，以及待公布 / 大致日期 / 结束时长详情。入橱没有独立继续步骤或日期说明，主题卡片完整宽度；系列及商品各自保留单行折叠入口。图片空缺来自隔离夹具未配置图片，不代表线上商品图被移除。日期仍使用原解析与落库规则。

正常模拟器构建使用以上参数，将`test`改为`build`并去掉测试筛选、并行测试及结果包，结果**BUILD SUCCEEDED**，日志`simulator-build.log`。`simctl install`成功；terminate退出3（无旧进程），新进程PID80268启动成功，见`simulator-run.json`。此次正常启动不等同于完整人工点击链路；页面验证来自真实SwiftUI渲染截图。

真机Debug构建使用相同project、scheme和依赖缓存，改为`build -configuration Debug -destination 'platform=iOS,id=00008140-000C289E1862201C' -derivedDataPath /private/tmp/pink-house-phone-batch-entry-device -jobs 3`，结果**BUILD SUCCEEDED**。深层严格签名通过、团队保持833FJ74GS2，无XCTest插件，`get-task-allow=true`，保持原Debug配置。通过官方`devicectl device install app`安装成功，再执行`device process launch --terminate-existing`成功，新进程PID2751，安装标识3456FE93-D4DE-4A50-8F8E-B7641285FBFB。回执为`phone-install.json`、`phone-launch.json`；二进制SHA-256为`f83da31254766593c787e1f6070ef3f073bf94ae166dfee80a2b240a566cfff6`。iOS26.5真机画面仍无法通过当前Mac读取，未声称本次已由用户逐页确认。

测试使用隔离目录和内存数据库，不写用户衣物或奖励。`git diff --check`通过。

## TestFlight续接

前一个4.2（2）归档包含独立选择步骤，不能作为本次界面调整的交付包。其上传未成功：代理故障排除后，Apple另明确返回Account credentials have expired，需Xcode账号重新登录。临时关闭代理的两次流程均已恢复并逐项核对；新需求到达时取消了待登录的上传流程，未继续上传旧归档。

包含新界面的本地Release归档已完成，路径`/Users/sangyu/Library/Developer/Xcode/Archives/2026-10-16/ItemManager 4.2-2 Inline Batches.xcarchive`；App版本4.2（2），严格签名及Production环境核验通过。构建命令与前一轮归档相同，仅替换`-archivePath`；日志为本次证据目录内`archive.log`。新归档未导出或上传。

**用户随后明确要求“暂停上传TestFlight的指令”。已结束待登录流程，HTTP、HTTPS、SOCKS三项代理与保存的原设置逐项一致；没有活动的`xcodebuild -exportArchive`上传命令。暂停持续有效，未在归档完成后自动上传，也不继续请求账号登录。需要用户明确恢复TestFlight分发后才可继续；仅继续界面工作不视为恢复上传。**
