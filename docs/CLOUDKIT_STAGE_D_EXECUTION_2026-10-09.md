# 阶段 D 执行记录（2026-10-09）

状态：**D1–D8 全部通过**。iOS Release / Production 真机验收已完成；78 项测试通过（76 项相关回归 + 2 项真实云端验收）。原归档导出的 App 已重新安装并正常启动。

证据根：`output/阶段D/2026-10-09_正式区验收/`；汇总断言 `final-stage-d-check.json`。本轮只使用专用样本，没有自动发布用户整份业务目录，也没有上传 App Store。

## 八项验收

| 项目 | 实际结果 | 证据 |
|---|---|---|
| D1 | Release 归档、导出退出 0；归档、导出 App 与测试宿主签名均为 Production | release-archive.log；archive-signing-check.json；export-signing-check.json；test-host-signing-check.json |
| D2 | 安装真机成功，手机实际读到与 Mac 相同的 production seq 3 / 根摘要后才写入 | release-install-utf8.json；native-create-report.json；production-before/ |
| D3 | 手机普通消费路径收到 Mac 店家和系列及两张引用图；新建样本三级文字回读通过，五张图下载、解码与实际 SwiftUI 图片组件展示通过 | native-create-report.json；create-attachments/；native-delete-report.json；five-production-redownloaded-images.png |
| D4 | 手机追加 stage-d-20261009 专用店家、系列、商品，上传五张 PNG：成功 5、跳过 0、失败 0，真实发布 seq 3→4 并回读 | NativeCreateAndReleaseRegressionEmbedded.xcresult；native-create-report.json |
| D5 | Mac 独立取回 seq 4；只修改专用店家说明后发布 seq 5，手机确认收到「阶段D电脑发回，手机应能看到」 | mac-create-cross-read-check.json；mac-echo-publish-receipt.json；mac-echo-check.json；native-delete-report.json |
| D6 | 手机仅删除专用商品并发布 seq 5→6，删除标记存在；seq 5 历史包与五张原图仍可取回 | NativeReceiveMacDeleteAndEmptyCacheVerified.xcresult；native-delete-report.json |
| D7 | Mac 发→手机读、手机发→Mac 读、Mac 修改→手机收到、手机删除→Mac 收到，四个方向均真实运行 | mac-final-cross-read-check.json；两份 native 报告 |
| D8 | Mac seq 6 看不到删除商品且保留删除标记；隔离缓存清空后五图重新下载摘要相同，冷启动不复活删除商品；development seq 8 未变；三份手机运营文件摘要前后完全相同 | production-final/；development-final/；mac-final-cross-read-check.json；phone-original-data-check.json |

## 初始状态与保护范围

- Mac 初始 production seq 3，rootIndexHash `e4560464f1c9e1583a2d6fc35f75d039db048a96503cc4d890c3a8dc4c91d534`。
- development 前后 seq 8，rootIndexHash `a2fd60abaf8ae0510b192cf92321d6901ef23b79fb92aff3a9972f2be31a9eee`，目录 JSON 前后相同。
- 真机 iPhone 16 Pro / iOS 26.5；沿用既有运营白名单及角色，不增加成员。
- 安装前后复制并逐字节核对 `shop-catalog-override.json`（455988 字节）、`shop-catalog-drafts.json`（743 字节）、`shop-catalog-batches.json`（2 字节），全部 SHA-256 相同。私有副本目录 700、文件 600；这是三份运营文件核对，不是整机备份或整机数据未变的证明。
- 测试用独立目录、独立下载缓存及内存上传任务表，测试结束恢复存储入口。仅追加专用样本、仅删除专用商品；不替换个人运营覆盖层、不清空用户真实缓存。
- 旧正式目录业务字段保留；Swift 编解码将缺失的店家 aliases 规范为 `[]`。跨端比较仅归一化这一项，不宣称旧目录 JSON 逐字节相同。

## 实际发布链

1. Mac 阶段 B 原正式目录 seq 3 → 手机读取；取回两张旧引用图。
2. 手机发布专用店家、系列、商品和五图 → seq 4，rootIndexHash `46adfe0c19ea987d79990c16598ef70e49d499cb3f9f2e0f654dd95665e52b06`。
3. Mac 独立取回并只修改专用店家说明 → seq 5，rootIndexHash `fc2d300699cdea6de1476e3648be1033b39454ab8b79f1c958970d55c53c2b00`。比较证实其它目录字段完全保留。
4. 手机确认收到说明后删除专用商品 → seq 6，rootIndexHash `310d5e95e73c47bf5f95a4e99671c5f7ee1d9c937cc83d5220b52ff4aa4796f9`。
5. Mac 独立取回 seq 6，原 B 商品删除标记和 D 商品删除标记均保留；专用店家与系列仍在，商品不再展示。五张历史图片与历史包没有物理删除。

## 环境修正与测试边界

原 Release 与 Debug 共用未指定 CloudKit 环境的权利文件，不能仅用编译配置名称证明生产路由。新增 `ItemManagerProduction.entitlements`，保留原有内容，仅增加 `com.apple.developer.icloud-container-environment=Production`；主 App Release 使用该文件，Debug 配置不变。导出指定 `iCloudContainerEnvironment=Production`，并核查实际签名。依据：[Apple 环境权利说明](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.icloud-container-environment)、[Apple 测试与导出说明](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitQuickStart/TestingYourApp/TestingYourApp.html)。

`ShopCatalogStageDLiveTests` 默认关闭，须显式设置 `PINK_HOUSE_STAGE_D_LIVE=1`，只允许 Release。每次写入都绑定刚独立取回的序号、根摘要，旧基线会在写入前停止；第二次还必须收到 Mac 的专用说明。

测试使用应用原生消费者、发布器和真实云端，截图使用实际 `ShopCatalogAssetImage`。它证明收发、摘要、删除和图片组件显示，不代替人工逐页点按完整录入流程。五图截图已人工查看，D1–D5 全部显示，无占位图。

本地导出采用 debugging 方法并保留 `get-task-allow=true`，用于已连接真机验收；没有声称这是 App Store 分发包。`ENABLE_TESTABILITY=YES` 保持 Release 优化方式。临时测试宿主嵌入 XCTest 插件后沿用已有签名资料重新签名，仍核实 Production；最后重新安装不带测试插件的原归档导出 App，并启动成功，见 `final-release-install.json` / `normal-release-launch.json`。

## 命令、结果与边界

归档（退出 0）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme ItemManager -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/DerivedDataStageD -clonedSourcePackagesDirPath build/SourcePackages -archivePath 'output/阶段D/2026-10-09_正式区验收/ItemManager-Production.xcarchive' -jobs 5 -allowProvisioningUpdates DEVELOPMENT_TEAM=833FJ74GS2 ENABLE_TESTABILITY=YES -quiet archive
```

导出（退出 0）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -exportArchive -archivePath 'output/阶段D/2026-10-09_正式区验收/ItemManager-Production.xcarchive' -exportPath 'output/阶段D/2026-10-09_正式区验收/exported-production' -exportOptionsPlist 'output/阶段D/2026-10-09_正式区验收/export-options.plist' -allowProvisioningUpdates -quiet
```

真机测试构建使用归档 SYMROOT / OBJROOT / DSTROOT，并显式 `DEPLOYMENT_LOCATION=YES`；完整配置和日志在 `release-build-for-testing-deployment.log` / `release-build-final-live-guards.log`，均退出 0。已将插件嵌入测试宿主，并在 `StageD-Live.xctestrun` 设置 `TestBundlePath=__TESTHOST__/PlugIns/ItemManagerTests.xctest`。

测试通用命令（完整各次命令保留在对应日志开头）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test-without-building -xctestrun build/DerivedDataStageD/Build/Intermediates.noindex/ArchiveIntermediates/ItemManager/BuildProductsPath/StageD-Live.xctestrun -destination 'platform=iOS,id=00008140-000C289E1862201C' -parallel-testing-enabled NO -only-testing:ItemManagerTests/ShopCatalogStageDLiveTests/testReceiveMacUpdateDeleteAndReadFromEmptyCacheOnProduction -resultBundlePath 'output/阶段D/2026-10-09_正式区验收/NativeReceiveMacDeleteAndEmptyCacheVerified.xcresult'
```

- `NativeCreateAndReleaseRegressionEmbedded.xcresult`：退出 0，77/77 通过，包括 76 项相关回归与真实创建发布。
- `NativeReceiveMacDeleteAndEmptyCacheVerified.xcresult`：退出 0，1/1 通过，真实接收 Mac 修改、删除、空缓存重下载与冷启动检查。
- Mac 发布 dry-run、真实发布、最终两个环境独立取回均退出 0；发布回执 `applied=true`、`readBackConfirmed=true`。
- `final-stage-d-check.json` 汇总证据断言通过；测试摘要只保留结果及数量，不复制账号或设备个人昵称。
- `git diff --check` 退出 0。

## 未通过的尝试及处理

这些记录保留，不计为通过：

- 初次 Python 展开 IPA 错误处理中文路径，安装退出 1；改用 `ditto -x -k` 保留 UTF-8 / 符号链接，所有可执行文件及深层签名核验后安装退出 0。原归档未受影响。
- 初次测试构建沿用归档路径但缺少 `DEPLOYMENT_LOCATION=YES`，退出 65；修正构建目录设置后通过，不是源码编译失败。
- 初次运行 `NativeCreateAndReleaseRegression.xcresult` 退出 65，没有执行测试；外置插件路径不在宿主内。嵌入测试插件并重签宿主后 77 项全部通过。
- Mac 严格 JSON 比较曾因缺失 aliases 与空数组不同停止；核实仅这一编解码规范差异后修正比较口径，所有其它字段继续严格比较。
- Mac 初次 dry-run 缺少输入 TAR 的 `payloadHash`，退出 2，未写入；补上 TAR SHA-256 后预演与发布均通过。
- Mac seq 5 独立取回首次遭遇 HTTP 503，退出 7；同一只读请求重试退出 0。
- `NativeReceiveMacDeleteAndEmptyCache.xcresult` 退出 65：绑定的旧基线 seq 3 与实际 seq 5 不一致，保护检查拒绝且未删除。独立确认 seq 5、更新绑定基线后，`...Verified.xcresult` 通过并发布 seq 6。
- Xcode 某些日志出现「failed with exit code 0」诊断噪声；按进程真实退出码、测试结果与实际产物判断，不将失败尝试误计成功。

用户操作见 [阶段 D 用户清单](阶段D_用户操作与检查清单.txt)。
