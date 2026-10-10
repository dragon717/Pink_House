# 整系列提交白屏与目录表格补录

## 白屏根因与复现

「提交整个系列（写入草稿）」和「发布整个系列」均先调用 `commitSeriesEntry()`。当多个颜色的图片引用已失效时，写入失败原因逐规格汇总到 `OpsWorkspace.lastError`。根页面的 `OpsStatusBanner` 用没有行数限制的 `.fixedSize(horizontal: false, vertical: true)` 展示整段原因；长文本把布局撑出窗口，主界面无法正常显示。

用临时 SwiftData 库、真实提交方法和 80 个失效图片引用复现。修改前真实 SwiftUI 快照 `/tmp/pink-house-series-white-before/series-submit-long-error.png` 显示整个主界面只剩空白背景。修改后同一组数据的 `/tmp/pink-house-series-tables-after/series-submit-long-error.png` 正常显示侧栏、步骤条、提交与发布卡片及有界错误摘要。

修复：顶部错误摘要最多 3 行，完整原文保留在工作区；「查看详情」打开有界、可滚动、可复制的详情窗。不会把错误当作提交成功，也不清空向导输入。根页面的提示条不再随着条目数量无限增高。

## 价格表、尺码表与补录

- 「店家与系列」选中商品后，底部和右键菜单提供「查看价格表与尺码表」。底部显示未录入、缺原图、已录入状态。
- 查看窗展示当前商品预约价、定金、尾款、现货价；系列共用的价格表结构与全部原图；该商品自己的尺码表结构与原图。图片点击可打开原图，远端原图未下载时明确提示。
- 补录系列价格表支持多选上传图片、结构化表格和仅原图。加载并保留多图列表，不把已有多张图截成一张。使用现有 `CatalogSeries.priceChart`，没有第二份价格表副本。
- 尺码表复用商品管理的录入表单，新增点击缩略图上传/替换原图；支持仅原图和结构化数据。已发布的 `thmedia:` 原图在补录结构化表格时继续可用，不要求它必须是本机 asset ID；选择器提供对应当前原图 tag。
- 商品价格编辑预填当前价格，避免未设置修正时以空表单覆盖其他已填金额。用户编辑预约价或定金后自动计算尾款；初始化预填不重算历史字段。
- 这些入口保存后调用既有 `saveCatalogEditorChanges()`，先本地保存再进入串行同步队列。保存失败不关闭表单，保留输入和具体原因。尺码表只改选中的商品，不改变同系列其他商品；系列价格表仍为共用表。

## 验证命令与结果

在 `/Users/sangyu/develop/Pink_House`、`/Applications/Xcode.app` 执行：

```sh
xcodebuild -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/pink-house-ops-save-logo-build build-for-testing

python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /tmp/pink-house-ops-save-logo-build \
  --snapshot-dir /tmp/pink-house-series-tables-after

git diff --check
```

最终 Mac App / 测试目标构建通过；增量构建仅有无 AppIntents 依赖的元数据提取提示。实际 App 模块的 XCTest 回归 12 项通过，0 失败。新增覆盖：大量提交错误提示的高度小于 140 pt、保留完整原因与输入；系列发布在条目提交失败时保留草稿箱和输入且不进行网络发布；价格表多图、尺码表结构与远端原图、商品价格重开恢复及商品隔离、待同步意图持久化。`git diff --check` 通过。

真实 SwiftUI 布局快照已检查：长错误提交、未录入表格查看、已录入表格查看、尺码表补录、系列价格表补录。快照在 `/tmp/pink-house-series-tables-after/`；现有后台进度窗验收同样通过。主页面离屏截图中的系统 List 选中行存在黑色渲染差异，不影响新增表单或白屏复现对比。

日志：`/tmp/pink-house-series-white-before.log`、`/tmp/pink-house-series-tables-build.log`、`/tmp/pink-house-series-tables-regressions.log`。

验证边界：临时库与模拟错误，不改用户正式草稿、未执行真实云端发布、未替换当前正在运行的运营 App。修复的是已复现的长错误布局白屏；若用户遇到的是进程退出或无错误时白屏，仍需对应现场日志进一步定位。运行本次构建的新版运营 App 后生效。
