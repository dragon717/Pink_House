# 保存修改后的双环境同步与可见进度（2026-10-17）

## 现场与根因

用户反馈：在「店家与系列」修改商品后，运营端显示同步完成，少女心愿 App 仍是旧名字。现场运营端显示 Production 发布号 22；用户已明确手机是 Xcode 直接安装的开发版。本机已安装的 Debug 构建签名未指定 Production，工程 Debug 使用 `ItemManager.entitlements`，按 CloudKit 调试环境读取 Development。

旧 `saveCatalogEditorChanges` 仅对团次/封面/价格表/商品排序使用双环境局部更新。普通商品名、店家、系列等编辑走 `cloud.publishNow`，只发布设置里选中的单个环境。UI 把该环境的回执显示为“已同步到 App”，导致 Production 成功被理解成开发版也已更新。混合保存路径还存在系列两个环境完成、随后普通编辑只发一个环境的分支。

实际补同步进一步确认：Development 缺少 `product-09895a97`，并非只有名称旧。旧版只发单环境还导致整件商品及关联资料漏发；开发环境保存的比较快照只有 278 件商品，Production 为 431 件。

另一个成功判定缺口：系列任务接受发布头/回执，未再次下载商品目录逐字段核验；并且完成回调过去可以在分环境回执缺失时报告“均已回读确认”。队列在单独拉取任务结束时缺少唤醒观察，也可能让保存请求一直等待。

## 实现

- 新 `OpsCatalogEditorUpdate` 冻结每次显式保存前后的字段差分。普通编辑与现有系列配置统一逐环境执行。每个环境先读最新目录，只应用本次保存的字段，保留该环境独有图片、价格、档期与其它商品。连续保存按字段合并，已知中间状态可幂等续传；真实并发修改同一字段明确阻断，不能强制用本机值覆盖。
- 名称改变时迁移各环境自己的款式档案键，保留各自面料和描述。公共包省略归档颜色不算漏传；未归档商品在目标环境缺失不能静默跳过。
- 不切换运营日常目标环境。Development / Production 分别拉取、冻结、上传、再次拉取。发布回执必须匹配请求、草稿、版本、环境、载荷摘要与 applied/readBackConfirmed，随后业务字段也必须与保存一致，才能写入该环境回执。
- 每个环境的已确认业务快照与回执同次持久化。部分失败保留原请求号、冻结文件及已确认环境，重试先查询，不盲目重复发布。旧任务不得清除网络等待期间的新保存。
- 两个环境均通过业务内容核验才能清除保存意图并显示 100%。只有单环境普通发布的旧回执不能清除新版双环境任务。
- `OpsCatalogEditSyncStatus` 显示于主界面顶部与设置：本机版本、整体进度条、两个环境各自阶段和确认版本、失败原因及“继续同步并核对结果”。图片上传结束不代表整轮完成，部分成功、错误、退出恢复均不显示 100%。下方手动拉取/环境迁移与“已保存修改”进度明确区分。
- 针对旧版已保存、只发一个环境的名称修改，一次性冻结补救任务：以最近确认发布的身份字段及另一环境已保留的祖先作参照，只补商品名/款式名/品类以及店家和系列名称；不复制价格、图片或档期，不触碰当前未保存输入，不绕过真实冲突。补救任务与标记原子保存，可退出恢复。
- 发布诊断导出按钮移出难以展开的折叠区，便于运营取证。

## 验证

补充恢复路径：目标环境的局部历史快照漏掉商品时，使用源环境此前已下载的旧身份作为允许匹配的旧值，仍不绕过远端同字段冲突。补救方向按最后确认发布摘要确定，不能因为手动拉取改变基线而反向覆盖新名称。目标实际缺少本次编辑的商品时，只补该商品及必要的店家、系列、规格、尺码表、销售记录、款式档案与图片资源；目标已存在的行保持原值，下架标记阻断自动恢复。关联补齐快照随冻结任务存盘，重启查询后继续核验。

构建命令与日志使用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`（Xcode 27.0 / 27A266a）。

```sh
swift test --package-path Packages/PinkHouseOps \
  --filter 'OpsCatalogEditorUpdateTests|OpsCatalogEditSyncTests|OpsSeriesConfigUpdateTests|OpsCatalogMergeBaselineTests|OpsDataSyncProgressTests'
xcodebuild build-for-testing -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2
python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /private/tmp/pink-house-reservation-batches-ops
SPM_CACHE=/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  MAX_JOBS=2 tools/xcode/build_mac_release.sh
```

隔离测试包括：普通改名实际走两个环境；发布回执返回成功但线上读回旧名字时必须保留失败任务；恢复后查询冻结请求、跳过已确认环境；相同字段并发修改保护；连续保存幂等；目标环境缺商品不能报完成；不同环境款式档案保留自身面料；归档颜色省略兼容；旧单环境名称补救的持久化；进度与保存结果落盘边界。所有测试均使用隔离草稿或替代桥接闭包。

最终离线验证：137 项通过、0 失败（Mac 工作区 93 项；运营核心 44 项）。Debug `build-for-testing`、Release 构建及 `git diff --check` 均通过；新旧完整 entitlement 与 bundle ID 一致，严格签名验证通过，最终包 CDHash `05327d655152064f43776d751bb5e7669254ff86`。安装检查记录 `/private/tmp/pink-house-saved-edit-install-20261017.json`。

已正常退出旧版并替换 `/Applications/少女心愿运营.app`，完整签名与权限验证通过，已启动新进程。草稿第 3568 版、4 店家 / 14 系列 / 431 商品 / 617 图片保留。实机主窗口已显示分环境进度条；第一次补核对在 12% 处正确阻断缺失商品，没有误报成功。关联补齐修复实际重试后，两个环境全部内容回读确认：Development 第 24 版、Production 第 23 版、整体 100%。最终工具重启后仍正确恢复 100% 及两个环境的确认发布号。面向运营的进度阶段使用“准备商品资料 / 上传商品图片 / 上传商品资料 / 保存云端更新 / 确认云端更新结果”等普通表述。

通过正常保存面板导出 `/private/tmp/pink-house-saved-edit-live-after-20261017.json`，两个已核验快照的 `product-09895a97` 名称及款式名均为 `华丽款JSK+bnt+项链+胸针（一对）`，均包含商品图 `asset-2258a1731eca`、5 条规格、1 份尺码表、1 条销售记录，图片资源引用完整。Development 为 279 商品（此次仅补本次修改涉及的 1 件漏发商品及关联资料），Production 保持 431 商品。本机目录与更新前导出快照逐字段完全一致，草稿版本仍 3568。Production 的业务内容与旧 22 版相同，唯一序列化差异为 `removedShopIDs` 排序，17 个下架标记集合保持一致。

Development 根摘要 `f95caed740fb550db879c3fa7b4788f70f4eac38305e5982a07837b018830963`；Production 根摘要 `fc0bbc41fb93ae7a2941891d64723795f648574f7e239e5255d87340a5e3d4d3`。用户随后明确回复“已显示新名称”，确认手机时光馆首页下拉刷新后已显示正确商品名称，完成运营保存、两个环境内容回读及手机实际显示的全链路核验。手机显示结果来自用户确认，未通过当前 Mac 工具截图读取。TestFlight 上传持续暂停。
