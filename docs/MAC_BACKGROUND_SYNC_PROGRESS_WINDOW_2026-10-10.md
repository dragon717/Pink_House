# Mac 同步进度后台运行

> 2026-10-11：本文保留为历史记录。分步进度窗口、问题弹窗及分散日志入口已删除；当前操作以 [三个同步入口](SHOP_CATALOG_ENVIRONMENT_PROMOTION_2026-10-11.md) 为准，每轮操作显示一个结果、生成一份日志。

用户需求：同步时可移开进度窗口，继续编辑；同步上传在后台继续。

根因：`OpsMainView` 把进度卡片叠在主页面上；卡片没有独立窗口的移动能力，运行中又不显示关闭入口。

实现：`OpsSyncProgressWindowController` 用非模态 `NSPanel` 展示同一份 `OpsCloudSyncModel` 状态。标题栏可拖动、调整大小，位置由原生窗口保存。点击「后台运行」或系统关闭按钮只隐藏窗口，不取消同步任务。收起后，后续自动保存同步不反复弹出窗口；右上角「同步中」可以重新查看，结束后「查看同步结果」可以查看步骤、问题和日志。自动弹出不抢主窗口输入焦点。

主页面移除同步进度遮罩，编辑和保存仍可继续。保存沿用既有串行同步队列，正在发布时的新保存保留待同步意图；浮窗不持有同步任务。主页面切换分区、隐藏浮窗不调用取消。

## 验证

2026-10-10，在 `/Users/sangyu/develop/Pink_House` 使用 `/Applications/Xcode.app` 执行：

```sh
xcodebuild -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/pink-house-ops-save-logo-build build-for-testing

python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /tmp/pink-house-ops-save-logo-build \
  --snapshot-dir /tmp/pink-house-background-sync-snapshots

git diff --check
```

- Mac App 和测试目标构建通过。增量构建仅有无 AppIntents 依赖的元数据提取提示。
- 实际 App 模块的 9 个 SwiftData 编辑保存回归测试通过，0 失败。
- 临时数据原生窗口验收通过：可移动、非 sheet、无应用模态窗口；后台运行和系统关闭均保留运行状态；后台更新进度；重新打开复用窗口和位置；后续同步不再次弹出；同步中修改店家并保存产生待同步意图；主页面没有同步遮罩。
- 已检查真实 SwiftUI 布局截图 `sync-progress-background.png`、`catalog-while-syncing.png`，位于 `/tmp/pink-house-background-sync-snapshots/`。主页面截图为无标题栏的布局 fixture，不包含 App 场景的原生工具栏。
- 验收记录 `/tmp/pink-house-background-sync-snapshots/background-sync-acceptance.txt`。日志 `/tmp/pink-house-background-sync-build.log`、`/tmp/pink-house-background-sync-acceptance.log`。

验证边界：使用临时 SwiftData 数据与模拟同步进度，未执行真实云端发布，未修改用户正式草稿，也未替换正在运行的运营 App。隐藏窗口期间没有实际网络任务的端到端验收；同步任务所属模型与发布队列保持原有实现，窗口关闭不调用任务取消。运行新版 Mac App 后该界面生效。
