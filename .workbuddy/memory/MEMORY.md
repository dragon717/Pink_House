# Pink_House 硬规则索引

> **这是索引，不是手册。** 每行 = 「最容易违反的那一句」+ 标识符；事故经过/签名/判定表见 **`RULES.md`**（104KB，`grep -n "^## " RULES.md`）。
> 构建验收 skill `pink-house-xcodebuild-acceptance`；抽包 skill `ios-local-spm-package-extraction`。
> **写新条目先问：这一行删掉会不会有人写出错代码？不会就别写。**

## 全局状态

- 发布通道 = **Mac 导出待发布包 → Python CLI 打 CloudKit**；App **不直连** CloudKit。
- ⚠️ `local:` 改写有两套状态机（iOS / Mac 交 CLI），字段清单已统一，实现未合并。
- R07：只读 `--mode pull-catalog`（线上空 → `EXIT_OK` 且不产文件）；写前比 `baseRootIndexHash`，不一致**退出码 5**。
- ⭐ 拉回 = `SharedCatalog.ShopCatalogReconcile`（线上有→加 / 同 id→线上覆盖 / 本地多有→移除；销售史与墓碑保留；幂等自证 `isAligned`）。Mac 走 `alignCatalogToPulledContent`；**iOS 只写覆盖层 `localOnlyRemainder`**（整份写＝给本机盖快照，界面看不出）。只改目录，不碰 staging。
- 离线演练已全删（09-29）：拒绝路径只能真连上验。保留 `--allow-unapproved-local-fixture` + 四份 `selftest_*`。桥接器只认 `development`/`production`，其它**报错不回落**（退出码 4）。
- CloudKit 记录 **not indexable，无法从云端反推内容** → 想知道线上有什么只能拉回或查发布头。

## Mac 端（target `PinkHouseOps`）

- ⭐ 出网唯一入口 `open_https()`；**禁在适配层直接写 `urlopen`**。**网络失败 ≠ 内部错误**：退出码 **7**，`pendingConfirmation` 不可重试。
- ⭐ **禁 `import mimetypes`**（沙盒子进程读 `/etc` 被拒 → 发布必挂，CLI 直跑复现不出）。MIME 走 `protocol.media_mime_type()` 查表。**子进程路径上的代码不许依赖系统文件库。**
- ⭐ `previousReleaseSeq` 必须传（线上 `head.releaseSeq`），语义＝「本版取代哪一版」。
- ⭐ `rootIndexHash` 每次重建都变（含 `publishedAt`）→ 别写「同输入同摘要」断言，别当内容寻址键。
- ⭐ 日志**在模型层落盘**（`OpsCloudSyncModel.perform` → `persistLog`，`bridge/logs/<runID>.log` + `latest.log`）；排查用**本次专属** `lastRunLogURL`，别用会被覆盖的 `latest.log`。
- ⭐⭐ **R5（未修）**：`build_release.py:383` 的 `rewrite()` 对非 `local:` 原样返回 → 拉回的 `thmedia:` 引用不产 `media_records`，而 `known_media_hashes` 只来自本次 → 全判 `media.reference.missing`。后果：**「拉回→编辑→发布」走不通**；首次全 `local:` 发布才正常。
- ⭐ **「点了没反应」与「失败了」必须分开**：操作型卡片必须有失败分支。
- ⭐ 切环境必须清空 `onlineHead`/`pulled`/`outcome`/`lastReceiptSeq`/`baselineAcknowledged`/`lastError`/`pullFailure`（双锁：`didSet` + `publish()` 校验 `head.environment`）。
- ⭐ dev 线上：**seq 4**（10-07 核对）。别拿 seq 1/2 口径互套（seq1 = 2 店家/9 系列/263 商品）。
- ⭐⭐ **10-07 整包恢复事故的两个数字别混**：①「缺 174 张图」**是真的**——但成因是 **iOS 端修好之前导出的老 tar**（只带商品图：276 张 vs 引用 452 名字），不是 Mac 导入 bug；②「线上 seq 4 缺 174」**是假的**（当年审计脚本 set 比对 bug，实测 0 缺）。**下次看到「276 图/450 引用」先想老包，别查 Mac 端。**
- ⭐ 沙盒取证 harness（文件触发 + 跑完自杀）：`snapshot.request`、`bridge-probe.request`（只读探针 S1–S10）、`publish-probe.request`（演练，固定 `dryRun=true`）。⚠️ 三者**各用自己的触发文件**。演练整包放**容器内**（沙盒读不到 `/tmp`）。`osascript` 无辅助功能授权 → **不能靠点击驱动 UI**。
- ⭐ `stageTrail` 只收 `state == .started` → Python 的 `freeze`/`verifyArtifact` 本就不该在轨迹里（拿它当断言＝假失败）。`reachedHeadSwitch` **无任何消费方**。
- ⭐ 凭证按环境分文件 `cloudkit.<env>.json`，缺则抛 `credentialMissing` 不回落 Keychain，私钥永不进 `OpsCredentialSummary`。导入按**当前环境**命名 → 唯一拦截 `declaredEnvironmentMatches`。
- ⭐ iOS→Mac 整包（tar = `shop-catalog.json` + `images/<原文件名>`）；**哈希命名会让 `local:` 引用悬空**。导入防呆：目录形态找不到 JSON 且唯一子目录里有 → 自动下钻一层；「仅 JSON」入口也认 `images/` 子目录。
- ⭐⭐ **「云端同步」面板已整块删除**：工具栏 = **「云端更新」一键**（`publishNow`：取发布头→自动采用基线→恒真实发布）；结果 = 顶部**悬浮框**（成功 15s 消失，失败常驻 + 打开日志 + 按条件出现的「缺图清单（N）」/「数据修复」）。环境 / 仓库授权 / 凭证 / 日志 / 从 iOS 恢复 / 数据修复全在**设置**（Cmd+,）。
- ⭐⭐ **新 SwiftUI 只认 `SettingsLink`** 打开设置；`NSApp.sendAction(showSettingsWindow:)` 不被响应（只刷 "Please use SettingsLink"），别再写。SettingsLink 无「导航到分区」API → 跨场景指令用单例 `OpsSettingsFocus`。
- 可靠性地基：① `@Model` 新字段一律 Optional；② 变更必 `markDirty()`，`isReviewStale` 拦导出；③ 导出服务自复校验；④ 坏草稿只读 + 备份原始字节，唯一出口「另存为新草稿」；⑤ 编辑命令返回 Bool，成功才 `dismiss()`；⑥ 父子归属链在命令层拒。
- ⭐ **Markdown**：`Text(字面量)` 才解析；变量/拼接文案一律过 `opsMarkdown(_:)`。门禁 `tools/ops_ui/check_markdown_callsites.py`（**只覆盖 Mac**）。
- ⭐ 媒体门禁：`thmedia:`/64hex 已远端化；`local:`+文件在＝待上传；`local:`+**文件不在＝阻断**（按**引用条数**计，不是文件数）；`bundle:` 内置；`http(s)://` 告警。
- ⭐⭐ **缺图三道防线（10-07 定案）**：①**防**在出口——导出端缺图必须拒绝打包（现在只是 toast 提一句仍照打包，是根因）；②**知**在入口——导入/换机立即对账，「缺 N 张」做成常驻状态别等发布才炸；③**补**靠账本——发布产出的 `media.json`（fileName/contentHash/recordName）要持久化成**媒体账本**，本地文件丢了可回填成 `thmedia:`。**门禁不放宽，绝不加「忽略缺图继续发」开关。**
- ⭐ 读/写闸门：`apply=False` = 「不许写」**不是**「不许联网」；读 `_send`、写 `_post` 不要合并。
- ⭐ 子进程六件：读得到基线 / 有 `cryptography` / 能签名 / **授权先于落盘且判据只能是真读** / 授权仓库目录 / 凭证经 `process.environment` 进沙盒。
- ⭐ `fileExists` 在沙盒会骗人 → 唯一判据 `OpsBridgeSettings.isReadableFile(_:)`。
- ⭐ 解释器顺序：显式 → 仓库 `.venv/bin/python3` → homebrew → usr/local → `/usr/bin`；`cryptography` 只装 `tools/time_hall/publication/.venv`。
- ⭐ 沙箱 GUI 拿不到 stdout → 日志落 `harness.log` + `stampUntrusted` 盖图；抓图窗口 `.borderless`。target 默认 MainActor → 跨线程盒子显式 `nonisolated`。
- ⭐ 超时/取消是**抛出**不是结果；中断唯一入口 `interrupt(_:)`（先标记 collector 再 SIGTERM）。
- ⭐ 基线快照是编码后产物（`.iso8601` 秒精度）→ 写基线前 `normalizeWorkingCopyToStoragePrecision()`。
- ⭐ 主题跟随：`OpsFlowPalette` 全动态 NSColor；视图层禁用 `Color.white`/固定 hex 当**表面色**。
- ⭐⭐ 系列发布 = **一键无感**：`OpsWorkspace.publishSeries(cloud:)` → 草稿箱 `OpsSeriesPublishJob`（SwiftData）→ 标记发布中 → `publishNow` → **全成功才删草稿记录**，失败/部分成功保留 + 条目级状态 + 重试。侧栏入口「发布草稿箱」。⚠️ 不拉回整份目录，代价 = 本地整包**取代**线上那一版（日志留痕）。
- ⭐⭐ **S5 提交 = 保存，不顺手发布**：反馈只有两态「保存成功 / 保存失败：<原因>」（单一 `@State` 替换式）。根因：R07 比的是草稿 `baseReleaseSeq`/`baseRootIndexHash`，App 从不回填 → 自动发布必被拒（退出码 5）。解法：发布前 `adoptBaseline(head)` 自动回填。
- ⭐ 系列上新向导：`OpsSeriesEntryDraft`/`OpsSeriesEntryValidator`，提交走 `commitSeriesEntry()` 一票拦截；**首次 = 追加 SaleEvent，再次改价 = `applyPriceCorrection`**。价格表上传入口在 **S2**，S1 只选择。ViewBuilder 分支禁 `var`；`@Published` 计算属性无 `$` → 用 `bind(_ keyPath:)`。
- ⭐⭐ 可售尺码勾选：唯一口径 `CatalogSizeSelectionPolicy.autoFilled`（幂等），判据是「**一个有效尺码都没勾**」——不是「缺哪些补哪些」；触发**只有 5 个且全是人的动作**，禁在 body/onAppear 里对账。
- ⭐ 规格卡默认只显示颜色（口径 `CatalogVariantColorGrouping`）；**代表图 = 该色第一条有图的规格**；展开态换商品必清空。**S3 快照必须 1900 高**。
- ⭐⭐ **向导「系列级」字段切系列必须重载或清空**（`seriesEntryJSON` 长期持久化 → A 系列内容原样写进 B，**全程无报错**）。`reloadPriceChartFromSelectedSeries()` **只在显式切系列时**跑。导入整包后也要重载（否则 Picker 刷 "selection invalid" 且提交挂到悬空 id）。⚠️ `coverAssetID` 同类隐患未修。
- ⭐ S2 价格表开关 `declaresPriceChart`：空串既可能是「没填」也可能是「要清空」→ 没开关会静默清掉线上价格表。「只有原图没表格」是合法状态。
- ⭐ 新建店家：S1 哨兵 `__new_shop__` ↔ `createsNewShop`；`commitSeriesEntry` 先建店家再建系列。

## iOS / 领域层

- 测试隔离：宿主 = 主 App → 落盘测试 `ShopCatalogStorage.useTemporaryForTesting()`；断言只比前后快照或按 `batchID` 收窄。
- 环境：`INFOPLIST_KEY_UILaunchScreen_Generation` 必须 `NO`；iOS destination 写 UDID `FA7332BE-…`（`name=` exit 70），macOS 必带 `arch=arm64`；**`grep` 一律 `-E`**（PATH 上是 toybox shim，交替 `a\|b` 静默 0 命中）。
- 顺序与价格：一律 `AZIndexGrouping`/`*SortedByName()`，**分区顺序禁用 Set/Dictionary 遍历序**；修正 ≠ 追加、留空 = 清除、`CatalogSaleEvent` 只 append、缺失 = 「暂无」禁 `deposit ?? 0`。
- 图表与同款：唯一 `ShopCatalogChartPresentation.plan`（必过 `CatalogChartQuality` 门禁、预览即落库）；唯一 `ShopCatalogDesignPalette.sameDesignProducts`；详情页读 `store.designColors`，加购弹窗读 `colors(forProduct:)`，**禁合并**。
- ⭐ 图表「识别成功/失败」判定与文案只在 `SharedCatalog.CatalogChartRecognition`；界面只许消费。App 内「上传图片识别」入口是**用户要求删掉的**。
- ⭐ **Mac 图表文本语法是等号**（`S = 80, 78-83`），**iOS 是冒号**（`S:80,78-83`）。抄错 = 用户照填必失败。
- ⭐ 图表表格行标签/列名禁 `lineLimit(1)` → 固定列宽 88pt + 换行。`ImageRenderer` **不画 ScrollView 内容** → 表格须为无滚动容器独立 View。
- ⭐⭐ 图表文本录入唯一口径 `SharedCatalog.CatalogChartTextSyntax`：(a) 列名**只写数据列**（「尺码/款式」是行标签列）；(b) 行值个数 = 剔除后的数据列数；(c) 全角「，」先归一。**把行标签列写进列名 = Mac 放行、iOS 剔除 ⇒ 整列错位仍显示「识别成功」**。
- ⭐⭐ **界面示例文案 = 隐式规范，必须与模板同源**（placeholder / 「每一行：…」/ 粘贴面板 `example` 各写一份必然矛盾）。锁：`CatalogChartTemplateTests`（171 例）+ `ShopCatalogChartPasteExampleTests`（含负向对照）。⚠️ 价格表单位是**金额**不是 `cm`；价格表是展示表、**不是定价来源**。
- 删除与录入：预检与执行**共用** `plan*Deletion`，批量只写一次覆盖层；同款家族必须同源 `sameStyleFamily`。
- 加购记账：**金额零手输**；唯一口径 `ShopCatalogWardrobeEntryPolicy`；四阶段都必须弹选择弹窗；判付清只用 `isFinalPaymentPlan`。
- 系列：`salePhase`/`reservationEndAt` Optional；**自动流转 = 读取时判定 `effectivePhase`**，不做定时回写；阶段/图文/价格表**只有一处存储**；`publishOperationKey` 年份逐字 `"2026"`。
- 表单：`.sheet` 禁挂 `ForEach`/`List` 行视图 → 合成 `enum XxxSheet` 挂页面级；`.onChange(of:)` 对程序化赋值也触发 → 挂 `Binding` setter。Dock 避让高度只有 `floatingSurfaceBottomInset` = **72**。
- 商品改名 = **款式级**：标题只读 `designName`；唯一口径 `ShopCatalogProductRename.plan(...)`；**必须扇出整款**；`applyRenamePlan` **先于** `applySizeChart`。
- ⭐ **iOS 上传/发布不打日志** → 判「上传成功」只能看 ①任务表阶段=发布头且状态=`published` ②线上 `releaseSeq` 是否 +1。
- ⭐ 查线上发布头（只读）：`env -u http_proxy … PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE=<容器>/credentials/cloudkit.development.json .venv/bin/python3 ops_publish_bridge.py --mode baseline --request <req.json>`；凭证在 Mac App **容器**里，仓库没有。⚠️ agent shell 自带 `http_proxy`，不摘掉会连到 127.0.0.1 并误判根因。
- ⭐ 上传任务三页签：`currentJobs`/`failedJobs`/`historyJobs`；`repairStaleTasks()` **只在启动路径**调用。
- ⭐ **图片引用字段清单只一处** `ShopCatalogMediaReferences`；`isRewrittenByPublisher` 与 `allowsAssetID` **必须分开**；导出/打包引用集合必走 `publisherRewritten(in:)`，**禁手拼**（09-28 两端手拼，双双漏 174 张）。
- ⭐ iOS 图片重复上传：存在性**批量**查（分块 200），摘要 + 字节数一致 ⇒ 不传也不回读；`verifiedThisRun` 防末尾二次下载。否则 450 张 → `requestRateLimited` → 发布头永远切不动。⭐ CloudKit `save` **不是 upsert** → 内容寻址记录撞 `serverRecordChanged` 按「已存在」放行。

## 包与跨模块

- `SharedCatalog`（领域/门禁，只 Foundation/CryptoKit/ImageIO/CoreGraphics）、`PinkHouseOps`（桥接，**产品名 `PinkHouseOpsCore`**，不能与 App target 同名）。
- 四坑：`public` 类型**不会**让成员 public；合成逐成员 init 是 internal；`MemberImportVisibility` 下必须**在使用文件里** import（`UTType` → `UniformTypeIdentifiers`、`@Published` → `Combine`）；带协议一致性的 extension 不许加 `public`。包内无 `@_exported` → 每个文件自己 `import SharedCatalog`。
