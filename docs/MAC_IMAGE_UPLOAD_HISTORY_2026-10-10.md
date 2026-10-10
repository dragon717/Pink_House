# 运营图片上传历史持久化（2026-10-10）

## 原因与行为

批量配图窗口原先只在 `@State importedIDs/importedNames` 保存「本次上传」图片 ID 和原文件名。关闭窗口或退出 App 后这些临时值会消失，无法恢复原来的上传列表、按原文件名搜索。既有图片字节和已成功保存的目录资源仍在 staging / SwiftData，但缺少独立的上传历史。

现在左侧默认显示「上传历史」，保留图片、原文件名和上传顺序。单图上传（店家 Logo、系列封面、尺码表、价格表）和颜色批量上传均立即保存历史，不依赖配图窗口「确定」或系列提交。「取消」仅放弃颜色分配，保留成功上传的素材。上新成功归零仅清空表单，不清理上传历史。

`OpsCatalogDraftRecord` 新增可空 `uploadedImageHistoryJSON`，保存完整 `CatalogAsset` 快照、UTF-8 原文件名和上传时间；图片继续使用原 staging 副本，不引入另一份媒体目录。历史元数据与目录资源使用同一次 SwiftData 保存；落盘失败报告原因、恢复原历史，不能假装已持久化。历史记录保存完整资源快照，所以后续目录合并不再包含该资源时，也能恢复图片。

素材库汇总本机草稿记录中的上传历史，同图去重；新系列或新目录草稿可直接复用。只在选择一张历史图时，把它原样复制到当前 staging 并保存对应资源，不重新编码、不复制整库、也不自动发布。旧版本没有历史元数据的本机图片从已有目录资源与 staging 恢复显示；旧版本未记录的原上传文件名无法凭摘要推回，沿用现有文件名。

## 验证命令和结果

```sh
xcodebuild -project ItemManager.xcodeproj -scheme PinkHouseOps -destination 'platform=macOS' -derivedDataPath /tmp/pink-house-ops-save-logo-build build-for-testing
python3 tools/testing/run_ops_catalog_editor_regressions.py --derived-data /tmp/pink-house-ops-save-logo-build --snapshot-dir /tmp/pink-house-image-upload-history-after
git diff --check
```

Mac 构建通过，实际 App 模块的 35 项 XCTest 全部通过，差异检查通过。新增 6 项覆盖：

- 批量导入含失败文件、重复图片及中文文件名；不确认配图，删除原文件后重新读取仍可显示和搜索。
- 系列提交后表单归零，以及当前目录不再包含资源时，上传历史与副本仍可复用。
- 新建目录草稿后复用历史图，只复制所选资源，字节完全一致，并保存颜色分配。
- 旧记录历史字段为空时恢复可用本机图片。
- 历史保存失败时保留之前已保存的历史，不把失败上传说成成功保存。
- SQLite 容器关闭后重新打开，仍保留可显示图片与中文原文件名。

原生 SwiftUI 夹具使用新的 workspace 重新读取同一临时库并打开批量配图窗口；已检查截图 `/tmp/pink-house-image-upload-history-after/color-upload-history-after-reopen.png`，确认「上传历史」、原文件名、图片缩略图均可见，底部文案说明关闭窗口和退出 App 后可复用。

日志：`/tmp/pink-house-image-upload-history-build.log`、`/tmp/pink-house-image-upload-history-acceptance.log`。

验证边界：使用临时 SwiftData / SQLite 和图片夹具，没有修改正在运行的运营 App 的用户草稿，没有真实云端发布。新行为需运行本次构建版本。历史保存在本机数据中；本次不涉及跨设备素材库同步。
