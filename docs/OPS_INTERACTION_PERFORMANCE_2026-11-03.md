# Mac 运营工具交互性能修复（2026-11-03）

用户反馈输入、切页、滚动、看图、保存和导入等操作均不流畅，并提出每次响应低于 2 ms 的目标。

## 根因与实现

1. `stagedFileURL` 每次解析 `thmedia:` 都扫描、排序整个素材目录并读取文件核验 SHA-256；多个图片组件和每次页面刷新都会重复执行。新增 `OpsCachedMediaLookup`，复用目录索引和按文件大小、修改时间、inode 失效的摘要结果。视图另走 `previewFileURL` / `previewImageURL`，首次扫描、验证也放入独立 actor，后台完成后按主队列批次通知界面。业务命令继续保留同步查找；发布的 `OpsCachedMedia.files` 全量核验不变。
2. 共用缩略图、表格原图及本地预览原先在 `body` 中执行 `NSImage(contentsOf:)`。新增 `OpsImageLoader`，在独立 actor 上用 ImageIO 解码及降采样，按路径、尺寸和文件版本复用结果，解码缓存上限 64 MiB。原图预览在窗口出现后后台加载，预览最长边 4096 像素；取消或换款式后旧结果不能覆盖新图。
3. S3 每个款式行调用全系列校验，一轮刷新产生近似平方级重复工作。改为工作区拥有按稳定款式 ID 和完整条目值失效的 `OpsSeriesEntryValidationCache`，列表及当前编辑器复用同一结果。真正提交仍执行完整校验，手动取消的可售尺码策略不变。
4. 目录差异的 getter 每次都解码整份发布基线并重新 diff；图片、状态反馈、输入导致的刷新也重复执行。现在发布基线按原始 JSON 缓存，差异按目录变更代数及基线 JSON 缓存。资源 ID 查询也按目录变更代数建立索引，保留历史重复 ID 取首项的行为。

## 测量方式及边界

正式可复用入口：`tools/testing/run_ops_catalog_editor_regressions.py --derived-data build/chart-units-debug --interaction-performance-json <输出 JSON>`。

该入口将真实 Mac XCTest 和性能夹具链接到 Debug App 的模块，不启动 App 宿主测试；runner 开启 `-O`。测试数据为临时目录的 656 个约 64 KiB 素材文件、32 个带 7 列 × 5 行尺码表的款式、431 个商品。旧调用方式与新缓存路径在同一进程比较，记录中位数、P95 和最大值；图片首次索引另记冷耗时。不会修改正式草稿或发布云端数据。

“2 ms”仅能作为明确范围内处理路径的目标，不能作为整个 App 所有操作的保证。磁盘持久化、图片首次解码、文件选择器、网络发布及屏幕呈现均不在这些热路径计时内。P95 也不是最大值或端到端点击耗时，不能用它声称所有响应均低于 2 ms。

最初基线：单次媒体查找中位数 21.751 ms、P95 23.803 ms；32 款式列表校验中位数 82.729 ms、P95 90.279 ms。最终复测原始分布保存在同目录 JSON 文件；冷索引通过异步预览入口退出主线程。

## 构建及验证命令

环境：Xcode 27.0（27A266a）、本机 macOS arm64；以下命令均设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

```sh
swift test --package-path Packages/PinkHouseOps
xcodebuild build-for-testing -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/chart-units-debug \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2
python3 tools/testing/run_ops_catalog_editor_regressions.py --derived-data build/chart-units-debug \
  --interaction-performance-json /private/tmp/pink-perf-results.json
SPM_CACHE=/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  tools/xcode/build_mac_release.sh
```

日志：`/private/tmp/pink-perf-core-tests.log`、`/private/tmp/pink-perf-build.log`、`/private/tmp/pink-perf-regressions.log` 及 `build/mac-release/build.log`。测试覆盖图片替换/删除/重复格式回退、缓存与完整校验一致、后台图片加载及降采样、目录/发布基线更新后的差异缓存失效，以及现有草稿持久化和发布状态回归。

## 最终结果与本机安装

核心包 148 项、工作区 101 项测试通过，合计 249 项、0 失败；`TEST BUILD SUCCEEDED`、Release `BUILD SUCCEEDED`、`git diff --check` 和严格签名校验均通过。

最终固定夹具复测（毫秒；完整数据见 `OPS_INTERACTION_PERFORMANCE_2026-11-03.json`）：

| 处理路径 | 旧方式 P95 | 新方式 P95 | 新方式最大值 |
|---|---:|---:|---:|
| 素材缓存查找 | 31.231 | 0.165 | 0.347 |
| 32 款式列表重复校验 | 109.179 | 0.017 | 0.097 |
| 单款编辑后的重新校验 | — | 0.227 | 0.550 |
| 431 商品目录差异读取 | 3.753 | 0.002 | 0.014 |

首次目录索引 26.711 ms，由视图的后台解析路径执行。这些数字是进程内处理耗时，不是 Release App 的端到端响应 SLA。此前与构建并发的压力复测也出现过素材缓存查询最大 4.336 ms，说明不能承诺操作系统调度下的所有样本都小于 2 ms。

已正常退出旧进程，更新并启动 `/Applications/少女心愿运营.app`；新旧 bundle ID、签名团队和全部 entitlement 一致。旧包保留于 `/Applications/.codex-performance-backup-20261103-030948/少女心愿运营.app`，安装记录 `/private/tmp/pink-house-performance-install-20261103.json`。

电脑控制验收：草稿第 3578 版正常恢复，4 店家、14 系列、431 商品、656 图片不变；商品管理切页、列表滚动、搜索「贝雷帽」得到 9 项、图片预览及关闭均正常，实际商品原图显示已目视确认。已清除验收搜索并返回 S3 原录入页面；原 16×5 价格表（含 BNT）与 3×5 尺码表仍识别成功。未改写正式业务字段、未执行云端发布；真实磁盘保存、批量导入及网络发布的端到端耗时尚未建立性能基线。
