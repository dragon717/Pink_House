# 发布草稿箱多选发布（2026-10-10）

需求：草稿箱里的多个系列可勾选后一起发布。

## 实现

- 每张系列卡片增加「选择此系列」，顶部增加「全选可发布系列」「清除选择」「发布所选系列（数量）」。原单系列发布和重试入口保留。
- 可批量选择当前目录草稿、当前目标环境下已完整提交的待发布或发布失败记录。其它草稿、其它环境、正在发布、已经发布、有失败条目及目录中不存在的系列显示原因；不能组成半组上传。
- `OpsWorkspace+SeriesBatchPublish.swift` 在上传前一次保存所有所选任务的发布中状态、尝试次数和最新目录快照，然后仅调用一次现有受控同步发布器。
- 受控发布器沿用完整目录发布协议；多选决定本次一起确认和清理哪些草稿箱任务。没有生成「只含所选系列」的目录来覆盖线上其它内容，未选任务仍保留原记录。
- 云端回读确认后先持久化发布号及已发布状态，再清理选中记录。清理失败时撤销唯一的未保存删除操作，保留已确认记录，不显示成待发布。回执保存失败会显示原因，内存仍保留已发布状态；重启后旧发布中记录也不会自动重传。
- 网络未确认时记录整组失败原因供重试；每个任务冻结提交标识，新提交不会被旧成功或失败回执改写。
- 草稿箱发布不清空正在填写的下一份系列；沿用可收起的非模态后台同步窗口。

## 验证

构建：

```sh
xcodebuild -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/pink-house-ops-save-logo-build build-for-testing
```

结果：`TEST BUILD SUCCEEDED`。日志：`/tmp/pink-house-series-batch-publish-build.log`。

离线实际 App XCTest 和原生 SwiftUI 临时数据截图：

```sh
python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /tmp/pink-house-ops-save-logo-build \
  --snapshot-dir /tmp/pink-house-series-batch-publish-after
```

结果：42 项测试通过，0 失败。日志：`/tmp/pink-house-series-batch-publish-acceptance.log`。

进一步验证清理失败撤销删除不影响上传期间已保存的新输入：

```sh
python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /tmp/pink-house-ops-save-logo-build
```

结果：42 项测试通过，0 失败。日志：`/tmp/pink-house-series-batch-publish-regressions.log`。

新增覆盖包括：多选去重且只发一次请求；未选任务和下一份输入保留；失败后重开和整组重试；异草稿/异环境/未完成/运行中记录整组拒绝；空选择及云端忙；发布前落盘失败不上传；旧批次回执不删新提交；回执或清理保存失败保留证据，撤销清理不回滚已保存输入。

已检查 `/tmp/pink-house-series-batch-publish-after/series-queue-multiple-selected.png`：两张卡片都有勾选框，顶部显示已选 2 个系列和「发布所选系列（2）」。

验证边界：测试使用临时 SwiftData 库和替换发布回调，没有发送真实云端发布、没有操作用户当前草稿，也没有替换或重启用户正在运行的运营 App。新界面位于本次编译的 `PinkHouseOps.app`，运行旧二进制不会自动获得代码变更。
