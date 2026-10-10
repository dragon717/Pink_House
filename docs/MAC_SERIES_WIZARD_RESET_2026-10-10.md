# 系列上新完成后恢复默认状态（2026-10-10）

## 原因与行为

原先显式提交和发布成功都保留 `seriesEntry`，自动持久化又保留了旧的 `seriesEntryJSON`，窗口重新打开仍会恢复上一份输入；已有未调用的重置函数还保留店家选择，没有恢复完整默认状态。

现在 S5「提交整个系列（写入草稿）」在完整落盘成功后，及「发布整个系列」取得确认成功后，会先保存空白向导，再清空内存并通知界面回到 S1。店家、系列、日期、价格、图片和类型全部恢复默认值；已入库的店家、系列、商品及图片保持可查可编辑。发布内部的提交不会提前清空，以便网络失败时修正、重试。

失败、部分成功、结果未确认均保留输入。保存空白表单本身失败时回退原 JSON 并保留表单、显示原因。发布开始前记录当前草稿 ID 和提交后的完整表单；发布期间用户继续编辑或切换草稿时，完成回调不能清掉新内容。草稿箱重试确认成功时同样只清理对应的未继续编辑的表单。

## 验证

以下命令均通过：

```sh
xcodebuild -project ItemManager.xcodeproj -scheme PinkHouseOps -destination 'platform=macOS' -derivedDataPath /tmp/pink-house-ops-save-logo-build build-for-testing
python3 tools/testing/run_ops_catalog_editor_regressions.py --derived-data /tmp/pink-house-ops-save-logo-build
python3 tools/testing/run_ops_catalog_editor_regressions.py --derived-data /tmp/pink-house-ops-save-logo-build --snapshot-dir /tmp/pink-house-series-reset-after
git diff --check
```

实际 App 模块与 SwiftData 的 19 项回归通过，0 失败。新增 7 项覆盖：保存后空白表单恢复及目录保留、校验失败保留、空白表单落盘失败回退、发布确认后归零、未确认保留、新输入保护、切换草稿保护。

原生 SwiftUI 夹具从 S5 展示后执行同一保存入口，确认画面回到 S1、店家与系列均未选择、所有文本为空；截图 `/tmp/pink-house-series-reset-after/series-save-reset-to-first-step.png` 已查看。构建日志 `/tmp/pink-house-series-reset-build.log`，回归日志 `/tmp/pink-house-series-reset-regressions.log`，界面夹具日志 `/tmp/pink-house-series-reset-acceptance.log`。

边界：使用临时数据，未触碰正在运行的运营 App 的草稿；发布调用注入确认或未确认回执，未向真实 CloudKit 发布。实际运行中的旧进程尚未替换，新行为需运行本次构建的 PinkHouseOps。

## 发布草稿箱入口补全

后续已将显式写入草稿接入发布草稿箱，待发布记录与空白向导一同落盘，详见 [系列写入发布草稿箱](MAC_SERIES_DRAFT_PUBLISH_QUEUE_2026-10-10.md)。最新回归为 29 项全部通过。
