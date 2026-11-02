# 运营端提交前死代码清理（2026-11-03）

本次提交同时包含 BNT 配饰识别、表格默认单位、图片和校验性能、小窗口布局修复及对应测试、验收工具。用户原有的 iOS 工程版本号修改与个人记忆文件保留在工作区，不纳入提交。

通过运营 App、全部 Mac 测试及工具代码引用检索，移除 17 个无调用成员及其专属说明：

- `OpsWorkspace`：`remoteMediaHashesMissingLocally`、`renameDraft`、`adoptBaseline`、`stagedImageURLs`、`exportCorruptedBackup`、`recordBaseRelease`。
- `OpsWorkspace+Editing`：`isPublishedEntity`、`references(toAsset:)`、`removeAsset`，并移除由此变空的 extension。
- `OpsCloudSyncModel`：`readOnlineBaseline`、`clearLog`、`revealLogsFolder`、`revealLogFile`、`credentialText`、`credentialGuidance`、`credentialFileURL`、`credentialSummary`。

SwiftUI/文件文稿/拖放协议回调、存档字段、实际图片缓存与布局验收探针均保留。损坏草稿导出仍走现有 `RawDataDocument` 文件导出入口；本次只删无调用的旧服务方法，不删除用户数据、素材或历史资料。

验证使用 Xcode 27.0（27A266a），设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`：

```sh
swift test --package-path Packages/SharedCatalog
swift test --package-path Packages/PinkHouseOps
xcodebuild build-for-testing -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/chart-units-debug \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2
python3 tools/testing/run_ops_catalog_editor_regressions.py --derived-data build/chart-units-debug
git diff --check
```

验证边界：仅清理无调用代码并运行离线验证，不重启或替换当前已恢复正常的运营 App，不执行云端发布。当前安装版的界面和恢复证据见 `OPS_WINDOW_RESIZING_FIX_2026-11-03.md`。

结果：共享包 259 项、运营核心 148 项、工作区 111 项，共 518 项测试全部通过；`TEST BUILD SUCCEEDED`、Python 语法检查和 `git diff --check` 通过。日志分别为 `/private/tmp/pink-cleanup-shared-tests.log`、`pink-cleanup-core-tests.log`、`pink-cleanup-build.log`、`pink-cleanup-mac-tests.log`。
