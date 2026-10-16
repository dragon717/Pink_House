# 发布前六项假冲突：分环境共同基线修复（2026-10-16）

## 现场证据与根因

真实草稿 `5EF72441-3EB7-41C5-8594-EF58C7526EB7` 第 3368 版，发布目标为 Production。
报错日志：`20261016-222346-sync-DB1908A0.log`，上传前拦下 6 项，未发送发布请求。

经运营工具内「设置 → 导入与数据修复 → 导出发布诊断」导出本机证据，不直接读取受保护数据库：

- 旧草稿唯一基线为 Development seq 21，根摘要 `00924ce7e8a8…`，观察于 2026-10-11。
- 2026-10-16 22:24 下载的 Production seq 16，根摘要 `975d4e3d401c…`。
- `series-ops-4A5144C0` 是「双子星」。旧基线与 Production 的该系列对象逐字段完全一致，均只有 ID、店家 ID、名称。
- 本地新增 `salePhase`、`balanceDueKind`、`balanceDueAt`、`balanceDueEndAt`、`cover`、`priceChart`。
- 旧 `mergedCatalog` 在环境不同后把基线直接变成 nil；共享合并器于是正确地拒绝未知来源差异，却被界面误称为「双方都修改了」。

另一处同链路缺陷：系列配置自动同步两环境后，只保存发布号回执，没有确认对应字段的比较祖先。即使不切换环境，之后继续编辑该字段也可能把自己上次的更新算作并发编辑。

图片资源 ID 在构建前后保持一致，本地 URL 与 thmedia 摘要的现有比较也已覆盖；图片引用转换不是这次六项误报的来源。

## 修复规则

1. `OpsCatalogDraftRecord.environmentBaselinesJSON` 为可空新列。Development / Production 各自保存共同祖先，旧字段继续兼容已有展示与协议。
2. 整包发布回读确认、明确拉取合并分别更新所属环境，保留另一环境祖先。基线、回执与同步意图同次落盘；失败回滚。
3. 系列局部发布只确认冻结任务实际保存的 schedule / cover / priceChart 与相应资源。其他未发布本地内容和未合并远端变更不被记成已同步。
4. 对尚无完整祖先的环境，共享合并器支持按实体/字段标记已知范围；未确认字段继续阻断，不把「不知道」当成空值。已知可空字段的明确清空仍可正确合并。
5. 旧任务恢复只接受同草稿、同请求、同环境、同发布号/根摘要、applied + readBackConfirmed 的回执，冻结 tar 必须通过载荷 SHA-256。目录直接从匹配摘要的 USTAR 读取，不能相信可能已替换的解包输入。
6. 跨环境迁移只确认旧共同快照与历史已确认任务内容相同的实体，以及该任务实际发布的系列字段；不同环境的其他内容继续按未知处理。失败同步新下载的快照不能直接变成祖先。
7. 结果未知仍查询原冻结请求；已确认环境的比较祖先与环境回执一起保存，再允许检查点完成。旧任务不能清除网络等待期间产生的新请求。
8. 合并保存失败保留内存内容，恢复旧基线。真正并发编辑同字段仍拦截；未知基线与真正并发编辑分别说明原因。完整日志记录所用环境、发布号与祖先范围。

恢复只改比较元数据，不修改目录内容、编辑版本、待发布条目或用户输入，不触发网络发布。

## 验证

旧二进制回归：新增「Production 发布后再发布 Development，再修改本地名称」用例，旧版报 `shops.*.name` 假冲突；70 项中该项失败，其他 69 项通过。

Xcode 27.0（27A266a），显式 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`：

```sh
xcodebuild -scheme PinkHouseOps -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ops \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 build-for-testing
python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /private/tmp/pink-house-reservation-batches-ops
swift test --package-path Packages/PinkHouseOps \
  --filter 'OpsCatalogMergeBaselineTests|OpsSeriesConfigUpdateTests|OpsSyncWorkflowTests|OpsCatalogEditSyncTests'
swift test --package-path Packages/SharedCatalog \
  --filter 'ShopCatalogThreeWayMergeTests|ShopCatalogPublishProtocolTests'
```

结果：构建通过；126 项通过，0 失败（Mac 工作区 73、运营核心 29、共享合并/协议 24）。包含截图六项复现、分环境与重启恢复、局部确认不吞掉其他编辑、真实冲突、回执/载荷不匹配拒绝恢复、磁盘失败回滚。`git diff --check` 通过。

测试宿主的临时权限不用于安装版本。安装使用普通 `build`，校验新旧 entitlement 完全一致和严格签名；旧 App 保留备份。

日志：`/private/tmp/pink-house-publish-baseline-{before-tests,app-final-tests,final-build,install-build}.log`、`/private/tmp/pink-house-baseline-{core-final-tests,shared-tests}.log`。

本次不修改 iOS 功能，不重新上传 TestFlight；不通过真实再次发布来代替只读验证。

## 真实草稿复验

23:11 普通签名修复版已替换并重新启动；SwiftData 新增可空列实际迁移成功。安装记录：`/private/tmp/pink-house-publish-baseline-fix-20261016/installation.json`。

修复前后均经 App 保存面板导出诊断。第 3368 版目录逐项完全相同，仍为 5 店家、14 系列、418 商品、579 图片；没有通过重写内容来消除报错。

恢复出 Development seq 23 的比较祖先，以及 Production seq 16 的已确认范围（1527 个实体）。「双子星」在旧共同快照与已确认 Production 任务中完全相同，整条系列祖先可核验。

对失败当次下载的 Production seq 16 重新运行同一 `mergePreview`，冲突 **6 → 0**。这是本机已下载版本的只读字段检查，没有再次上传；未来发布仍先下载最新内容并执行真实冲突检查。

摘要证据：`/private/tmp/pink-house-publish-baseline-fix-20261016/verification.json`。完整诊断：`/private/tmp/ops-publication-diagnostics.json`（修复前）、`/private/tmp/ops-publication-diagnostics-after.json`（修复后）。草稿箱里的失败记录保留上次发布结果，用户可从原任务重试。
