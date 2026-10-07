# Mac 云端同步根因修复（2026-10-07）

本次开发工作区：`/Users/sangyu/develop/Pink_House`。承接工作区已有、未提交的媒体下载与并集合并代码。

后续实现与附件日志诊断见 [2026-10-08 三步同步与部分成功](MAC_CLOUD_SYNC_PARTIAL_SUCCESS_2026-10-08.md)。该次已把一键同步改为先下载、上传前安全合并、最后落盘确认；本页保留 10 月 7 日当时的验证记录。

## 已修复的根因

| 问题 | 修复行为 |
| --- | --- |
| 发布前自动采用最新发布号，却未合并对应内容 | 发布前核对环境、发布号、根摘要和基线内容；过期或未知基线要求先合并，服务端条件更新仍保留 |
| 同 ID 全量远端覆盖，丢掉本地单独编辑的字段 | `ShopCatalogThreeWayMerge` 按上一版快照逐字段推导；嵌套对象递归，数组作为完整值；双方都改同字段时在确认框选择本地或远端 |
| 合并结果本身被记成基线，新增内容不再算待上传 | 基线快照记录远端原始目录，本地新增、编辑和删除仍计入差分 |
| 图片由 `local:` 改写为 `thmedia:` 制造假冲突 | 用 staging 字节摘要比较图片身份；本地清除图片也能正确合并 |
| 墓碑与远端实体一起补回，产生复活与结构冲突 | 删除标记优先，并按现有删除命令口径移除关联规格、尺码表、销售事件和款式档案；公共包省略归档实体不被当成删除 |
| 下载中断时已完成文件无法被 App 接收 | 返回下载清单与 `media` 事件，区分 `pending`、`missing`、`corrupt`；App 先吸收已完成部分，下次按本机缺失集合补缺 |
| 坏图或格式错误仍报告成功 | 返回校验失败，并保留可接收的成功部分 |
| CloudKit 限流、权限错误、坏响应被解释成不存在 | 只有 `NOT_FOUND` 代表缺失；限流与服务暂不可用可重试，权限与结构错误明确拒绝；缺资产下载地址、缺发布号也不会伪装成空库 |
| 本机有缓存，目标云端没有该图片，却无法再上传 | 经摘要验证的缓存随 tar 交接，构建端把它加入待上传 THMedia；无缓存时仍要求真实远端存在性证明 |
| 环境没有商店分片，拉回没有产物，无法建立基线 | 明确交回空目录及对应发布号/根摘要，合并后本地独有内容保留 |
| 异步任务期间切环境、换草稿或继续编辑污染结果 | 环境切换清空拉回结果，使用环境代数拦住切走再切回的旧结果；预览绑定草稿 ID、版本和产物路径；下载绑定草稿与环境 |
| 发布完成后把期间新编辑也算已发布 | 成功回执只记录发布前冻结的目录和版本 |
| 作业目录、日志文件复用 | 作业和日志附加 UUID，避免同秒或同发布号运行覆盖 |
| 合并保存失败，内存基线仍前进 | 恢复旧基线、旧持久化内容与保存版本；保留内存编辑，明确报告未保存 |

## 操作语义

设置中拉回目录后先看预览。无冲突字段按三方推导自动合并；有冲突时可以确认「保留本地冲突字段」或「采用远端冲突字段」，一次选择作用于本次全部冲突字段。显式删除标记始终优先。合并完成后可下载缺失的远端图片，再运行主窗口「云端更新」。

图片字段为空可以是合法状态。本次没有新增「没有图片就禁止导出」规则。显式本地引用所指文件不存在、远端引用在目标环境不存在且本机无可验证字节时，仍需补齐数据；代码不能重建不存在的原图。

## 验证

环境：`/Applications/Xcode.app`，Xcode 27.0（27A266a），macOS 27 SDK；本机没有 `/Applications/Xcode-beta.app`。

以下两条包测试均使用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`：

```sh
swift test --package-path Packages/SharedCatalog --scratch-path /tmp/pink-sync-shared --disable-sandbox
swift test --package-path Packages/PinkHouseOps --scratch-path /tmp/pink-sync-ops --disable-sandbox
```

- SharedCatalog：205 项，0 失败；含 10 项三方合并测试。
- PinkHouseOpsCore：72 项，0 失败；覆盖中断下载清单、发布桥接与既有中断处理。
- `python3 tools/time_hall/publication/selftest_ops_sync.py`：12 项，0 失败；离线注入网络、权限、坏图、空基线和缓存上传场景。
- `python3 tools/time_hall/publication/selftest_cloudkit_read.py`：18 项，0 失败。
- `python3 tools/time_hall/publication/selftest_shop_catalog.py`：通过。
- `python3 tools/ops_ui/check_markdown_callsites.py`：29 文件，0 违规。
- `git diff --check`：通过。

Mac 构建命令（通过，最大 5 个任务）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ItemManager.xcodeproj -target PinkHouseOps -configuration Debug \
  -sdk macosx -jobs 5 \
  SYMROOT=/Users/sangyu/develop/Pink_House/build/sync-rootfix-products \
  OBJROOT=/Users/sangyu/develop/Pink_House/build/sync-rootfix-objects build
```

构建产物：`build/sync-rootfix-products/Debug/PinkHouseOps.app`。编译日志：`/tmp/pink-sync-mac-build.log`；包测试日志：`/tmp/pink-sync-shared.log`、`/tmp/pink-sync-ops.log`。

构建警告：`ONLY_ACTIVE_ARCH` 无活动架构时构建全部适用架构；AppIntents 元数据因没有相应框架依赖而跳过。没有 Swift 编译错误。

验证边界：未运行新 App 的 GUI 或真实 CloudKit 写入、未修改现有用户草稿。应用容器内历史日志读取在沙盒及升级权限后都被 macOS 以 `Operation not permitted` 拒绝，因而未取得当前现场日志。线上实测尚未完成，不能把离线回归通过当成真实云端同步成功。
