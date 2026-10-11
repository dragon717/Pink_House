# 阶段 C 执行记录（2026-10-09）

阶段 C 的 C1–C10 已通过。真实上传、Mac 交叉回读、删除、空缓存下载与五图显示均通过，最终相关回归 76 项全过。未执行阶段 D。

证据根：`output/阶段C/2026-10-09_试用区验收/`。设备：iPhone 16 Pro / iOS 26.5；使用既有运营白名单，未新增成员或要求切换个人账号。

## C1–C10

| 步骤 | 结果 | 证据与验证边界 |
| --- | --- | --- |
| C1 | 通过 | THMedia 下载已接入；隔离缓存清空后真实下载五图，实际 ShopCatalogAssetImage 截图五张均可见，非占位图。 |
| C2 | 通过 | 手机先读取验证真实全目录、头、根清单及包；与 Mac 实读 seq 6 / rootIndexHash 一致才追加专用店家系列商品，冻结来源版本。未点击用户真实草稿的对齐按钮。 |
| C3 | 通过 | 真机五张有效 PNG 进入实际 local 暂存、改写和发布，无缺图；类型、大小、摘要、去重由相关回归覆盖。 |
| C4 | 通过 | 真机上传 5、跳过 0、失败 0；五图经普通只读路径下载、摘要核对及 UIImage 解码。重复跳过另有回归测试，不声称本次新图发生真实跳过。 |
| C5 | 通过 | Native 发布数据包、条件更新头 seq 6→7；删除 seq 7→8。发布前后两次核对来源，仍以 changeTag 条件更新。 |
| C6 | 通过 | 手机公共只读路径验证头、根清单、包和图片。创建额外逐张回读五图；删除发布用修正后的代码验证全部目录图片字段。 |
| C7 | 通过 | Mac 独立拉回 seq 7，新店家系列商品存在，原目录保留。mac-readback-create/、mac-cross-readback-create-check.json。 |
| C8 | 通过 | 只删除专用商品及它的三条资源引用，removedProductIDs 随 seq 8 发布；Mac 商品不存在、标记仍在，原有八类实体逐条相等。历史 seq 7 包与五张媒体仍可读取。 |
| C9 | 通过 | 清空隔离包/媒体缓存后重新同步，店家系列文字正确、删除商品不在；五图实际重新下载并通过 SwiftUI 图片组件显示。新建消费服务再次加载也不复活。未声称手工点击整页或重启整台手机。 |
| C10 | 通过 | 五个新下载文件 SHA-256 与引用逐一一致，均可解码，真实组件截图人工复核通过。native-delete-report.json、five-redownloaded-images.png。 |

## 修复

- 发布基线持久化：同步合并或真实发布回读成功才推进；普通消费刷新不推进。未知、过期、跨环境草稿在任何写入前阻断，切换头前再次核对。
- 只有真实读取确认公共库为空才允许首次无旧基线发布，读取错误不得当成空库。
- 新图改用普通消费读取路径回读，无法读取则阻断发布；末尾仅跳过已由该路径验证的新图，避免重复下载。
- 末尾验证共用全部图片字段清单，覆盖店家图标、系列封面、尺码表、资源各图片字段及 canonical mediaKey。
- 已切换头但根清单回读失败仍显示「已发布但未验证」。回归覆盖切换前图片读失败、切换后根清单失败、已有店家图标读失败。
- 实际界面是右上角刷新按钮，修正原有「下拉刷新」指引。

## 隔离与现状

Native XCTest 使用 ShopCatalogStorage / ShopCatalogSyncStorage 双临时目录，任务表为内存容器；不替换用户覆盖层，不清空真实用户缓存。从真实 development 全目录追加 stage-c-20261009-* 专用资料；测试商品已软删除，专用店家系列与历史资源保留。

Mac 独立回读确认原 shops / series / products / assets / sizeCharts / variants / saleEvents / styleProfiles 逐条保留。production 仍为 seq 3，rootIndexHash 与阶段 B 完成时完全一致，没有生产写入。

App 沙盒复制两次超时，未据此声称已备份。更新安装已有 App，测试不替换实际运营草稿。真实动作由手机应用内验收测试调用发布器、消费服务完成，未声称手工点完运营表单。空缓存仅指测试下载目录，冷启动指新建服务/Store 从持久缓存恢复。

[用户操作与检查清单](阶段C_用户操作与检查清单.txt)：2026-10-11 起改为录入后点击「同步更新并上传」，自动拉取并安全合并；旧删除式对齐已移除。无需卸载应用或清空个人资料。

## 命令与结果

使用 /Applications/Xcode.app，未修改全局 xcode-select。编译：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme ItemManager -configuration Debug -destination 'platform=iOS,id=00008140-000C289E1862201C' -derivedDataPath build/DerivedDataImageRepair -clonedSourcePackagesDirPath build/SourcePackages -jobs 5 -allowProvisioningUpdates DEVELOPMENT_TEAM=833FJ74GS2 -quiet build-for-testing
```

初次、修正读取后的增量、最终提示文字调整后的编译均退出 0，通过。对应 device-build-for-testing.log、device-build-public-reader-fix.log、device-build-final-ui-copy.log 等记录。

真机测试前缀：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test-without-building -xctestrun build/DerivedDataImageRepair/Build/Products/StageC-Live.xctestrun -destination 'platform=iOS,id=00008140-000C289E1862201C' -parallel-testing-enabled NO
```

Live xctestrun 显式设置 PINK_HOUSE_STAGE_C_LIVE=1，创建绑定 Mac 实读 seq 6 / rootIndexHash，删除绑定 seq 7 / rootIndexHash；两个用例之间完成 Mac 独立回读。普通测试默认不执行真实写入。

- 创建选择 ShopCatalogStageCLiveTests/testCreateAndPublishOnDevelopment，加 Publisher / CloudSync / MediaRetry / CreatorAccess 四类回归。NativeCreateAndRegression.xcresult：创建真实用例通过，195.544 秒；整批 45 项中 1 项旧回读失败用例失败，退出 65。保留失败并据此修复，未将整批记为成功。
- 删除选择 ShopCatalogStageCLiveTests/testDeleteAndReadFromEmptyCacheOnDevelopment，加相同四类回归。NativeDeleteAndCorrectedRegression.xcresult：退出 0，47 项全过，真实删除/重新下载通过，215.338 秒。
- 最终完整相关回归使用原始 ItemManager_ItemManager_iphoneos27.0-arm64.xctestrun，不开启 live；选择 AssetMediaKey / Gzip / OpsMediaStaging / UploadJob / OpsPublishScope / OpsPublisher / CloudSync / MediaRetry / CreatorAccess 九类。FinalRegression.xcresult：退出 0，76 项全部通过。

每项选择完整前缀为 -only-testing:ItemManagerTests/，结果包参数为 -resultBundlePath；完整命令见各次 .log 首行。

Mac 独立回读使用：

```sh
tools/time_hall/publication/.venv/bin/python tools/time_hall/publication/ops_publish_bridge.py --mode pull-catalog --request <本轮只读请求文件>
```

mac-readback-request.json、mac-readback-delete-request.json、production-after-ios-request.json 均退出 0，实际分别 development seq 7 / 8、production seq 3。原目录保留及 production 不变断言通过。

模拟器首次全量编译主动中断退出 75，未进入 UI 验收，不计通过/失败，不计为真机证据。本轮范围为目录发布与消费链路，不代表其他业务全部验收。

最终汇总：`final-stage-c-check.json`。门控 3 通过，阶段 D 待单独执行。
