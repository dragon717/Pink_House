# 系列写入发布草稿箱（2026-10-10）

## 问题和修复

S5「提交整个系列（写入草稿）」原先只调用目录提交并清空向导，没有生成 `OpsSeriesPublishJob`。因此目录中已有商品，但用户在发布草稿箱找不到该系列。

现在保存成功后生成或更新同一目录草稿、同一系列的待发布记录，包含店家、系列、条目结果、目录快照及目标环境。草稿箱记录和空白向导在同一个 SwiftData context.save 中落盘；完成后才通知界面回到 S1。校验或落盘失败保留表单；失败的新增记录撤销，失败的更新恢复原记录，不回滚其它目录编辑。

草稿箱中的「待发布」记录显示「发布整个系列」按钮，失败记录显示「重试发布」。发布调用使用所属目录的当前内容，不读取或提交运营正在填写的另一份上新表单，也不使用旧快照覆盖后来的目录编辑。确认成功移除对应记录，失败保留同一条记录和原因。

模型新增可空 `draftID` 与 `submissionID`，前者绑定目录草稿，后者防止旧发布结果删除或改写同一系列的新提交。不同目录的记录不能用当前目录误发，页面提供「打开所属草稿」，切换前先保存当前目录和向导内容。旧记录两个新增字段均为空时仍可在原目录发布；新增字段符合既有轻量迁移规则，没有改存档 key 或已有状态枚举值。

## 验证命令和结果

```sh
xcodebuild -project ItemManager.xcodeproj -scheme PinkHouseOps -destination 'platform=macOS' -derivedDataPath /tmp/pink-house-ops-save-logo-build build-for-testing
python3 tools/testing/run_ops_catalog_editor_regressions.py --derived-data /tmp/pink-house-ops-save-logo-build --snapshot-dir /tmp/pink-house-series-draft-queue-after
git diff --check
```

Mac 构建通过，实际 App 模块的 29 项 XCTest 回归通过（0 失败），差异检查通过。新增验证包括连续保存两个系列、重复保存同系列复用记录、清空表单后发布、保留下一份输入、失败重试、不同草稿拒绝及所属草稿打开、发布状态写盘失败不联网、旧发布回执不能处理新提交、SQLite 容器关闭后重新读取、已有记录保存失败回退及新增元数据为空的旧记录兼容。

原生 SwiftUI 夹具先展示 S5，再调用实际保存入口，随后截取 S1 和发布草稿箱；已查看截图确认表单为空、草稿箱出现「完成系列」「完成店家」「待发布」和「发布整个系列」按钮：

- `/tmp/pink-house-series-draft-queue-after/series-save-reset-to-first-step.png`
- `/tmp/pink-house-series-draft-queue-after/series-saved-in-publish-queue.png`

日志：`/tmp/pink-house-series-draft-queue-build.log`、`/tmp/pink-house-series-draft-queue-acceptance.log`。

验证边界：临时 SwiftData / SQLite 数据和原生界面夹具；发布调用注入确认或失败回执，没有真实 CloudKit 发布。未修改正在运行的运营 App 的个人草稿库或替换旧进程；新行为需要运行本次构建版本。先前已保存到目录、但从未创建过草稿箱记录的历史系列不会被盲目批量补入，仍可在店家与系列和商品管理查看。
