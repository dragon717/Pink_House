# 尺码表换图保存链路修复（2026-10-16）

## 现场与诊断边界

用户反馈「选择新图片后仍显示旧图」。先以隔离内存草稿检查系列上新 S3 和商品管理尺码表两个入口：普通 PNG 都能选中新图、改变绑定并打开新图预览，未复现每次换图都失败的情况。用户尚未提供失败图片的文件名 / 路径，不能将下述缺陷直接认定为该文件现场失败的唯一原因。

代码核对发现两个保存结果不一致的缺口：

1. `importSingleImage` 调用 `saveImportedImageHistory` 失败后仍返回新图片资源 ID。调用方会继续把这个未成功落盘的资源当作有效替换。新增测试在旧构建上复现此缺陷：66 项中 1 项失败，断言未保存的导入不得返回可用 ID。
2. 系列向导先保存素材，再由视图给 `@Binding entry` 赋值，依赖 400ms 防抖保存款式绑定；导入素材的成功不代表图片与款式绑定已经保存，且原图旁没有单独显示换图失败原因。

本次修复以上已确认缺口；对用户具体文件的同路径复现仍待补充输入。已向用户请求文件名或路径，不假称已查明文件格式、读取权限或缓存故障。

## 修复

- 共用单图导入在保存失败时返回 `nil`，保留错误，不继续把资源 ID 交给尺码表、封面等调用方。
- 新增 `replaceSeriesSizeChartImage` / `setSeriesSizeChartImage`：选择文件前固定草稿 ID 和款式 ID；导入成功后立即保存款式绑定，保存成功才更新界面。上传新图和从已有素材选择共用此入口，不再依赖防抖持久化完成换图。
- 绑定保存失败保留原图片、表格、价格和尺码选择；已经成功上传的素材仍保留在历史中，允许重试。草稿或款式变化、图片不可解码、资源已不存在时明确拒绝。
- 复用共享的可售尺码政策：仅补齐尚未选择有效尺码的颜色，手动取消的尺码保持原样，自动补齐与新图绑定一起保存。
- 原图附近直接显示换图失败原因；取消文件选择不作为失败。
- 尺码表缩略图使用现有统一引用解析器 `stagedImageURL`，兼容资源 ID、直接媒体引用及已下载缓存；当前原图不在素材枚举中时保留其 Picker 选项，避免无效 selection。
- 向导换图不自动发布尚未完成的商品；商品管理仍按原有显式保存流程工作。

实现：`PinkHouseOps/Services/OpsWorkspace+SeriesEntry.swift`、`PinkHouseOps/Views/OpsSeriesWizardTypeEditor.swift`。回归：`PinkHouseOpsTests/OpsCatalogEditorPersistenceTests.swift`。

## 构建与回归

Xcode 27.0（27A266a），本机工作区 `/Users/sangyu/develop/Pink_House`。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing \
  -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 \
  tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /private/tmp/pink-house-reservation-batches-ops
```

最终 `TEST BUILD SUCCEEDED`，69 项回归通过、0 失败。新增 4 项覆盖：

1. 单图历史保存失败不返回可用替换 ID。
2. 同文件名更换不同内容会产生新图片身份和预览路径，立即重开仍正确；同名同类型共用旧原图的另一款式不受影响。
3. 素材保存成功、绑定保存失败时旧绑定不变，上传历史可用，解除失败后可重试。
4. 过期草稿、删除款式、损坏图片、缺失资源拒绝修改；明确清除后重开保持清除。

正常运行构建将上述 `build-for-testing` 改为 `build -configuration Debug`，结果 `BUILD SUCCEEDED`。`git diff --check` 通过。

## 界面与日常工具

临时 `SizeChartQA.app` 承载实际向导组件，使用内存 SwiftData、两个共用蓝色旧图的临时款式，通过真实文件选择器选中粉色新图。修复版确认：

- 当前款式 Picker 更新为新图 hash；持久化 `seriesEntryJSON` 与界面内容相同，另一款式仍引用蓝图，手动只勾 S 的结果保留。
- 点击新缩略图，大图首帧实际显示粉色新图，与新图 hash 一致。
- 未替换真实运营商品的图片，未提交云端或 TestFlight。

正常构建已更新并启动于日常路径：

`/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/Build/Products/Debug/PinkHouseOps.app`

新旧签名均通过严格验证，四项 entitlements 不变；旧应用保留在同目录 `.codex-size-chart-replace-20261016-172604/PinkHouseOps.previous.app`。未迁移、清空或复制应用数据目录。重开恢复到 S3，真实草稿仍为第 1,419 版，5 店家、14 系列、273 商品、449 图片。真实数据只做页面与大图查看，没有执行配图保存。

证据根目录 `/private/tmp/pink-house-size-chart-replace-20261016/`：`baseline-regressions.log`（旧构建的确定性失败）、`build.log`、`regressions.log`、`normal-build.log`、`baseline-ui-success.json`、`fixed-ui-persisted.json`、临时验收代码、签名与安装记录。
