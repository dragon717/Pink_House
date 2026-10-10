# 店家与系列保存、店家 Logo 与自动同步修复

用户反馈：系列配置修改保存后不生效；上新向导与店家编辑需要上传/替换店家 Logo；目录页保存后应自动同步到少女心愿 App。

## 根因

1. `SeriesConfigSheet.saveSalePhase` 用 `declaresPhase` 同时控制阶段声明与所有日期。截图中的“不声明阶段 + 已填尾款区间”会被转成全部 nil，保存时把日期清掉。声明是否存在与用于推导阶段的档期是两个独立事实。
2. 系列配置、店家/系列表单等“保存”按钮只调用内存编辑命令，没有调用 `saveDraft()`，也没有调用受控发布流程。关闭表单后无法把“内存变化”当成“持久化且已同步”。
3. `saveDraft()` 在 `context.save()` 前更新 `savedRevision`，失败后没有恢复；界面可能把未成功写盘的内容标为“已保存”。发布回执的保存也需要同样的失败回滚。
4. 店家模型已有 `logo`，但 Mac 两处表单都没有图片上传入口。iOS 店家图片直接解析文件/远端引用，因此 Mac 保存 Logo 时必须把选择的 asset ID 转成其原图文件引用，才能由发布器改写为 `thmedia:`。
5. 向导恢复时把尚未创建的店家、尚未创建的系列也当作已删除实体，重开时丢失未提交的新店家资料。

## 实现

- `OpsSeriesSalePhaseInput` 仅用阶段声明开关控制 `salePhase`；预约与尾款日期独立映射，未填的可选尾款保持 nil，非法区间继续由领域命令拒绝。
- 目录页明确保存走 `saveCatalogEditorChanges()`：目录与同步意图一起先落盘，再执行 `OpsCloudSyncModel.publishNow` 的下载、三方合并、校验、受控发布、回读确认流程。
- `OpsCatalogEditSyncQueue` 合并短时间内连续保存；正在发布时的新保存继续排队。任务绑定草稿 ID、版本与目标环境，不借用其他环境的回执。
- 同步意图使用 SwiftData 新增可空列，兼容存量草稿。网络请求前落盘尝试标记；退出、超时或失败后保留意图与错误，不自动重复发送结果不确定的发布。用户再次明确保存或使用云端更新可继续处理。
- 只在发布回读确认且对应冻结版本覆盖该次保存时清除意图。手动云端更新同样可以确认此前待同步保存；发布中新增的后续保存不会被旧回执清除。
- 本地保存失败恢复 JSON、已保存版本和时间；回执保存失败恢复发布基线、回执元数据与同步意图，并向调用方返回失败。
- `OpsShopLogoPicker` 在 S1 和店家编辑中提供点击图片上传/替换、预览、清除。上传字节进入现有 staging，替换原文件或移除原文件不影响已导入图片。店家列表展示本机 Logo；云端沿用已有 `shops.logo` 和 THMedia 协议。
- S1 Logo 选择单独持久化，切换店家时清除该店家的待选覆盖，未管理时保留已有 Logo；新建资料恢复后仍保留。向导逐字编辑或暂存图片不触发整包发布，向导发布仍走原提交入口。
- 目标环境选择写入 UserDefaults，重开不会把已选生产环境静默重置为开发环境。状态显示目标环境；同步继续依赖该环境已配置的仓库授权与凭证。
- iOS 自动刷新沿用 [自动刷新修复记录](SHOP_CATALOG_AUTOMATIC_REFRESH_2026-10-10.md)：发布通知到达后检查，前台每 30 秒检查，回到前台立即检查。正式用户需要新版 iOS App 与 Production 公共库发布，后台推送由系统调度。

## 验证（2026-10-10，本机）

命令均从 `/Users/sangyu/develop/Pink_House` 执行，使用 `/Applications/Xcode.app`。

```sh
swift test --package-path Packages/PinkHouseOps

xcodebuild -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/pink-house-ops-save-logo-build build-for-testing

python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /tmp/pink-house-ops-save-logo-build \
  --snapshot-dir /tmp/pink-house-save-logo-snapshots

python3 tools/time_hall/publication/selftest_shop_catalog.py
git diff --check
```

- OpsCore：99 个测试通过，包含新增日期映射与同步队列 9 个回归场景。
- Mac `build-for-testing` 通过，包括 App 和测试目标编译。仅有未使用 AppIntents 的元数据提取提示。
- 实际 App 模块的 SwiftData 回归：9 个测试通过。覆盖日期重开、写盘失败后重试、Logo 替换/清除、旧向导 JSON、新店家向导恢复与提交、原图片移除后仍可导出、冻结版本/环境回执隔离、SQLite 文件重开、回执写盘失败回滚。
- 测试脚本链接该 Debug App 模块后独立运行 XCTest，避免本机已有的 App 宿主测试启动挂起问题。测试使用临时库，替换同步队列以禁用真实网络发布，不读取或修改运营的正式草稿库。
- Python 目录发布自测 49 项检查通过，包含 Logo 本地文件改写为云端媒体引用及图片上传去重。
- 三张真实 SwiftUI 布局快照已检查：`shop-logo-editor.png`、`series-entry-shop-logo.png`、`series-config-dates.png`，位于 `/tmp/pink-house-save-logo-snapshots/`。使用临时数据、真实图片暂存、白色窗口底板，未修改用户附图。
- `git diff --check` 通过。

日志：`/tmp/pink-house-save-sync-core.log`、`/tmp/pink-house-ops-save-logo-build.log`、`/tmp/pink-house-save-logo-persistence.log`、`/tmp/pink-house-logo-publication.log`。

验证边界：未对正式运营草稿执行真实云端写入，未替换当前正在运行的旧 App 进程，未验证真实 Mac → CloudKit → iPhone APNs 端到端时延。以上是代码、构建、真实本地持久化和发布协议自测的结果；新版 Mac/iOS 启用后仍需正式环境端到端验收。网络失败、缺图或合并冲突会保留本地保存并明确报告，不能显示为已同步。
