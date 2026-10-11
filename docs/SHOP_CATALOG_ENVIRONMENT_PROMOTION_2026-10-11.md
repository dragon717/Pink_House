# 运营端数据同步：三个入口（2026-10-11）

主窗口「数据同步」或设置（Cmd+,）进入。只保留三个按钮，每轮操作显示一个结果、生成一份完整日志。

| 入口 | 一次点击完成 | 数据边界 |
|---|---|---|
| 拉取开发环境 | 读取已发布目录 → 下载缺少的图片 → 合并保存 | 只读取 Development，不上传 |
| 拉取线上环境 | 读取已发布目录 → 下载缺少的图片 → 合并保存 | 只读取 Production，不上传 |
| 开发环境 → 线上环境 | 读取两端 → 增量合并 → 下载源图片 → 发布 → 回读确认 | 将 Development 已发布运营目录迁入 Production |

发布环境名称统一为「开发环境 Development」「线上环境 Production」，协议值仍为 `development` / `production`。两个拉取入口显式绑定来源，与日常编辑发布环境的设置相互独立。

## 简化后的行为

- 删除目录拉取、合并确认、图片下载的三个分步按钮，删除同步进度窗口、问题弹窗、重复结果入口与按阶段列出的日志按钮。
- 删除迁移预览表格、字段差异列表与来源选择器；迁移以开发环境内容更新同 ID 条目，自动执行完整过程。
- 每次拉取自动下载目录引用的远端图片并按 SHA-256 验证，合并保留本地独有条目，双方同字段差异采用所拉取环境的值；远端显式删除标记仍生效。合并前本地完整目录另存 local-before-merge.json，路径写入操作日志，可用「导入 JSON」恢复。共同基线保存为本次读取的远端版本，本地独立编辑仍保留为待发布差分。
- 目录合并成功但部分图片失败，显示「已合并，仍有 N 张图片未下载」，可重试同一拉取按钮，已校验图片跳过下载。
- 拉取不会调用发布器，也不会在结束时启动待发布编辑队列。系列发布和显式编辑保存仍使用既有发布功能。
- 迁移保留线上独有条目、线上下架记录及其他时光馆分片。开发环境删除标记不迁移；线上墓碑阻止已下架条目复活。重复执行无变化时不发新版本。
- 迁移冻结线上基线并复核开发版本；线上版本改变时拒绝发布。超时或未知结果保留冻结任务，第三个按钮改为「确认上次迁移结果」，先查询原任务，再允许迁移。
- 运行时只在原结果位置显示当前阶段；下载、上传图片显示真实计数和该阶段进度条，同时显示已用时间。45 秒没有阶段或数量推进时显示「等待响应，尚未完成」，不会把图片 100% 当成整轮完成。
- 运行中也可打开同一份日志，阶段和图片数量即时追加；完成后仍在该文件追加完整事件与最终结论。图片缓存校验、迁移打包及摘要计算在后台执行。
- 连接配置、整包导入与数据修复收进折叠项。删除悬空销售记录仍要求确认。

## 本次失败与修复

现场日志 `20261011-200452-baseline-A52E8204.log` 实际已读到开发环境发布号 21，但 baseline 模式没有发送终态 result 事件，Swift 按合同拒绝继续。桥接器已补发 confirmed 事件，空环境也明确成功返回 seq 0；凭证错误仍返回 refused。

现场日志 `20261011-200614-publish-CBA0F2D6.log` 显示线上发布号 11；6 个远端媒体引用中 2 个已在线上、4 个缺少，发布包也没有对应字节，导致 build_release.py 退出 5。下载已完成，失败发生在随后自动触发的上传阶段，线上未修改。

修复两层图片遗漏：

1. 发布前补图检查本地与目标目录引用的并集；目标明确返回 NOT_FOUND 的本地独有引用，才允许从开发环境按不可变摘要补齐。网络错误、损坏、目标已发布图片均不隐式切换来源。
2. 缺图检查识别任意缓存后缀，但旧预览/打包查找只列举 jpg/png/webp/heic/gif。改用 `OpsCachedMedia` 的同一份 SHA-256 校验清单，避免 jpeg、HEIC 大写后缀或损坏重复副本使已有图片从发布包漏掉。现场本机显示图片已齐而发布包缺图；具体 4 张缓存的后缀未逐文件取证，扩展名回归使用离线夹具验证。

`OpsOperationLog` 在业务开始时创建文件，运行输出即时追加，各桥接调用结束后补入完整事件，最后补入图片结果、合并明细、冲突和最终结论。期间不另写分步日志或 latest 副本。历史日志保留。最近业务结果及其专属日志链接持久化，重启后仍可查看。

用户实际发起的首轮迁移日志 `20261011-213236-sync-D5D37A0D.log`：21:32:36 开始，21:52:05 回读确认 Production seq 12，耗时 19 分 29 秒。旧界面始终只有固定转圈，未展示已存在的图片进度事件。已将事件接入统一阶段显示，补齐 Python 已发送但 Swift 未识别的 remoteMedia 阶段；重复进度与迟到的旧任务事件不会刷新等待状态。

实际复验日志 `20261011-220350-sync-E3A13316.log`：22:03:50 开始，22:04:26 回读确认 Production seq 13。运行中已在设置界面看到「下载开发环境目录」「检查线上环境已有图片」、已用时间与可用的单个日志入口。该轮还暴露重复迁移的统计误差：13 条下架商品的源销售事件被构建器剔除，5 条序列化后相等的内存差异被误算为更新。规划层现跳过不会下发的新增历史（仍保留已有线上历史），差分只计实际持久化字段变化，日期与小数精度均有离线回归。

最终签名版本复验日志 `20261011-221343-sync-21B61490.log`：22:13:43 读取 Development seq 21 与 Production seq 14，22:14:00 返回「线上环境已是最新，无需迁移」，新增 0、更新 0；没有调用 publish，也未发 seq 15。期间的修复验收曾完成 seq 14 回读，最终重复迁移不再误发版本。

## 实现

`OpsDataSyncModel` 统一三个入口；`OpsDataSyncSection` 和主窗口复用同一结果。拉取通过显式环境请求执行既有 pull-catalog / fetch-media，使用原工作区三方合并与持久化。

`OpsEnvironmentPromotionModel` 使用独立快照执行既有 pull-catalog / baseline / fetch-media / publish / query，不修改本地草稿。`OpsEnvironmentPromotion` 按稳定 ID 合并，使用原 tar 格式。新请求 `preserveTargetPartitions: true` 在构建后保留目标其他内容分片、撤回与客户端门槛，重新核对摘要、依赖及根清单；原 publish_cloudkit.py 负责资源去重、条件切头与回读。新字段缺省兼容旧请求。

迁移范围是已发布公共 ShopCatalog（店家、系列、商品、规格、价格、尺码表、图片、款式）。开发其他时光馆分片、私有衣橱、钱包、账户不迁入；线上已有其他分片保留。

## 验证

Xcode 27.0（27A266a），macOS SDK 27。签名构建：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme PinkHouseOps -destination 'platform=macOS' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 build
```

结果 BUILD SUCCEEDED；日志 `/private/tmp/pink-house-ops-simple-sync-build-20261011.log`。已保存原草稿、重启该签名 App，确认三入口与单结果界面。构建仍有存量 SnapshotHarness actor 隔离和 AppIntents 元数据提示。本次未修改 iOS 业务，无 iOS/真机验收。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PinkHouseOps \
  --filter 'OpsCachedMediaTests|OpsOperationLogTests|OpsBaselineBridgeContractTests|OpsSyncMediaRecoveryTests|OpsEnvironmentPromotionTests|OpsFetchedMediaTests|OpsSyncWorkflowTests'
tools/time_hall/publication/.venv/bin/python3 tools/time_hall/publication/selftest_ops_sync.py
tools/time_hall/publication/.venv/bin/python3 tools/time_hall/publication/selftest_environment_promotion.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SharedCatalog --filter ShopCatalogThreeWayMergeTests
git diff --check
```

结果：76 项通过、0 失败（运营 Swift 36、共享合并 Swift 10、同步 Python 21、迁移 Python 9）。覆盖真实 Python→Swift baseline 合同、图片恢复来源约束、缓存后缀/损坏副本、单份长日志、增量并集/墓碑/重复执行、缺图拦截、旧基线阻断及保留其他分片。Swift 日志 `/private/tmp/pink-house-ops-simple-sync-tests-20261011.log`；Python 日志为同目录 `pink-house-ops-simple-sync-python-20261011.log` 和 `pink-house-ops-simple-sync-promotion-20261011.log`。

真实线上只读验收：一键拉取并自动合并成功，seq 11、根摘要 f3bea0f47a96…，0 新增、0 更新、保留本地独有 1316 条，图片已齐。整轮日志 `20261011-204205-sync-01CC4EA0.log` 已通过系统控制台打开并核对，含桥接输出、图片检查、合并统计及最终结果。

真实开发只读验收：seq 21、根摘要 00924ce7e8a8…，首次补进 13 条；最终规则下更新 41 条（38 条币种、3 份价格修正），保留本地独有 159 条，图片已齐。最终日志 `20261011-205317-sync-74973286.log` 已打开核对；包含合并前快照路径 `PinkHouseOps/pulls/3302703E-D1BD-4B60-A9FD-45545F6244CE/local-before-merge.json`，合并保存成功。

最终签名版本重复拉取开发环境成功，日志 `20261011-210725-sync-C6AABEDD.log`：退出码 0、补进 0 条、更新 0 条、保留本地独有 159 条，完整事件明细与结果在同一文件。

早期迁移验证使用离线真实构建链路回归，发布子进程截断。后续用户实际发起迁移已成功发布 seq 12；实时进度修复的实际复验已回读确认 seq 13。未做 TestFlight / iOS 真机刷新验收。

实时进度修复验证沿用上面的签名构建命令，结果 BUILD SUCCEEDED，日志 `/private/tmp/pink-house-ops-live-progress-build-20261011.log`。进度、单日志、增量规划和真实子进程中断回归：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PinkHouseOps \
  --filter 'OpsDataSyncProgressTests|OpsOperationLogTests|OpsEnvironmentPromotionTests|OpsPublisherBridgeInterruptionTests'
```

结果 34 项通过、0 失败；日志 `/private/tmp/pink-house-ops-live-progress-tests-20261011.log`。覆盖阶段切换、真实图片计数、重复/倒退事件的等待判定、图片完成后仍需确认、未知媒体检查阶段合同、运行中可读的 UTF-8 日志及重复迁移的下架历史和序列化精度。另执行 `swift test --package-path Packages/SharedCatalog --filter ShopCatalogPublishProtocolTests`，14 项通过、0 失败，日志 `/private/tmp/pink-house-ops-live-progress-protocol-20261011.log`。本轮相关回归共 48 项，`git diff --check` 通过。

## 文件规模

设置页已从 569 行缩减至 178 行，主框架与相关状态页从 573 行缩减至 387 行，并删除两份分步进度窗口文件及其焦点协调文件。新增服务、界面、工具均小于 500 行。存量 OpsCloudSyncView / OpsWorkspace / SnapshotHarness 超限；后续按桥接日志、工作区职责及快照场景拆分，保持状态唯一归属。
