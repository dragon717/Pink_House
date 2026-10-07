# Pink_House 硬规则索引

> **这是索引，不是手册。** 每行 = 「最容易违反的那一句」+ 标识符；事故经过/签名/判定表见 **`RULES.md`**（96KB，`grep -n "^## " RULES.md`）。
> 构建验收 skill `pink-house-xcodebuild-acceptance`；抽包 skill `ios-local-spm-package-extraction`。
> **写新条目先问：这一行删掉会不会有人写出错代码？不会就别写。**

## 全局状态

- 发布通道 = **Mac 导出待发布包 → Python CLI 打 CloudKit**；App **不直连** CloudKit。
- ⚠️ `local:` 改写有两套状态机（iOS `ShopCatalogOpsPublisher` / Mac 交 CLI），字段清单已统一，实现未合并。
- R07：只读 `--mode pull-catalog`（线上空 → `EXIT_OK` 且**不产文件**）；写前比 `baseRootIndexHash`，不一致**退出码 5**。
- ⭐ **拉回 = `SharedCatalog.ShopCatalogReconcile`**（线上有→加 / 同 id→线上覆盖 / 本地多有→**移除**；销售史与本地墓碑保留；幂等自证 `isAligned`）。Mac 走 `OpsWorkspace.alignCatalogToPulledContent`（先 `reconcilePreview`）；**iOS 只往覆盖层写 `localOnlyRemainder`**（整份写＝给本机盖快照，线上新版被同 id 旧副本挡住，界面看不出）。只改目录，不碰 staging。
- **离线/本机演练已全删**（09-29）：拒绝路径只能在真连上验。保留 `--allow-unapproved-local-fixture` + 四份 `selftest_*`（35/18/16/6）。桥接器只认 `development`/`production`，其它**报错不回落**（退出码 4）。

## Mac 端（target `PinkHouseOps`）

- ⭐ 出网唯一入口 `open_https()`；**禁在适配层直接写 `urlopen`**（`selftest_network_failover.py` 16 项）。**网络失败 ≠ 内部错误**：退出码 **7**，发布 `pendingConfirmation` 不可重试。
- ⭐ **禁 `import mimetypes`**（沙盒子进程读 `/etc` 被拒 → 发布必挂，CLI 直跑复现不出；取证 `sandbox_profile_run.py`）。MIME 走 `protocol.media_mime_type()` 纯查表。**子进程路径上的代码不许依赖系统文件库。**
- ⭐ `previousReleaseSeq` 必须传（取线上 `head.releaseSeq`），语义＝「本版取代哪一版」。
- ⭐ `rootIndexHash` 每次重建都变（含 `publishedAt`）→ **别写「同输入同摘要」断言**，别当内容寻址键。
- ⭐ 日志必须落盘（`bridge/logs/<runID>.log` + `latest.log`，可一次复制）；**`perform` 之外的早退路径也要落盘**（`failBeforeBridge`）。✅ **落盘在模型层**（`OpsCloudSyncModel.perform` → `persistLog`），任何调用方（面板 / S5 / 探针）都落盘 —— 旧口径写的「只在视图层、绕过视图没有日志」**是错的**（10-07 实测容器里既有面板日志也有 S5 触发的 `20261007-162258-publish.log`）。排查要拿**本次专属**文件用 `lastRunLogURL`，不是会被覆盖的 `latest.log`。
- ⭐⭐ **发布门禁分不清「已在公共库」与「缺失」**（10-07）：`build_release.py:383` 的 `rewrite()` 对非 `local:` 值**原样返回** → 拉回的 `thmedia:` 引用不产生 `media_records`，而 `:907` 的 `known_media_hashes` **只**来自本次 `media_records` → 全判 `media.reference.missing`（4 资产×4 字段＝**16 条假错误**）。后果：**「拉回→编辑→发布」走不通**（＝ R4 要求的每次发布第一步挂着）；首次全 `local:` 发布才正常。**未修。**
- ⭐ **「点了没反应」与「失败了」必须分开**：操作型卡片必须有失败分支。
- ⭐ **切环境必须清空** `onlineHead`/`pulled`/`outcome`/`lastReceiptSeq`/`baselineAcknowledged`/`lastError`/`pullFailure`（双锁：`didSet` + `publish()` 校验 `head.environment`）。
- ⭐ 上传现状（**10-07 已更新**）：dev 线上 **seq 4**（seq 3 = 首次受控发布；seq 4 = 删一个商品）。**「缺 174 张图」是假前提**（那是我审计脚本的 set 比对 bug）——实测 0 缺、4 引用、1 孤儿。09-29 App 内发布真失败过，死因是沙盒 `import mimetypes`（已修，且 10-07 已在沙盒内复验通过）。⚠️ 别拿 seq 1/seq 2 的口径互相套：seq 1 = 2 店家/9 系列/263 商品；seq 2 只有 1 店家。**CloudKit 记录 not indexable，无法从云端反推。**
- ⭐ App 沙盒取证有两个 harness（文件触发 + 跑完自杀）：`snapshot.request`（视觉）、`bridge-probe.request`（只读探针 S1–S10）、**`publish-probe.request`（10-07 新增：发布演练 S11，固定 `dryRun=true`）**。⚠️ 三者**必须各用自己的触发文件** —— 只读探针的承诺是「从不构造 `--mode publish`」，合并就等于作废。演练整包要放**容器内** `publish-probe-stage/release.tar`（沙盒读不到 `/tmp`）。`osascript` 无辅助功能授权（-10004）→ **不能靠点击驱动 UI**。
- ⭐ `stageTrail` **只收 `state == .started`** 的阶段事件 → Python 的 `freeze`/`verifyArtifact` **只发 succeeded、本来就不该在轨迹里**（拿它们当断言＝假失败）。⚠️ 于是**演练也会播报到 `switchHead`/`confirmHead`**（`run_child` 按子进程步骤标记翻译，与 `dryRun` 无关）：今天无害（`reachedHeadSwitch` **无任何消费方**，记已发布受 `dryRun==false && readBackConfirmed==true` 门禁），但谁照它那句「R09 判定关键输入」把它接进「结果待确认」判定，演练就会被误判成「可能已切头」。
- ⭐ dev 线上 seq 1 **不是受控发布器产物**（引用全 `local:`）→ 别写死「引用是 thmedia:」，**实测再报**（`_media_reference_census`）。
- ⭐ 凭证按环境分文件 `cloudkit.<env>.json`（legacy 只对 development 兜底），缺则抛 `credentialMissing` 不回落 Keychain，私钥永不进 `OpsCredentialSummary`。⚠️ 导入按**当前选中环境**命名 → 唯一拦截 `credentialSummary.declaredEnvironmentMatches`。
- ⭐ iOS→Mac 整包交接（tar = `shop-catalog.json` + `images/<原文件名>`）；**哈希命名会让 `local:` 引用悬空**。
- ⭐ 侧栏只剩 4 分区（系列上新/店家与系列/商品管理/本地预览）；`validate`/`exportReleasePackage`/`recordConfirmedPublish`/基线差分保留为无 UI 服务层。
- ⭐⭐ **「云端同步」面板已整块删除**（10-07 定案）：工具栏 = **「云端更新」一键**
  （`OpsCloudSyncModel.publishNow`，内部取发布头 → 自动采用基线 → 恒真实发布，
  `dryRun`/`baselineAcknowledged`/拉回目录/iOS 交接的分步 UI 与模型方法全删）；
  结果 = 顶部**悬浮框**（成功 15s 自动消失，失败常驻 + 「打开日志」）。
  环境选择 / 仓库授权 / 凭证 / 日志入口全在 **设置（Cmd+,，`OpsSettingsView`）**。
  服务层能力（`alignCatalogToPulledContent` 等）保留但无 UI 入口；探针 harness 自建请求不受影响。
  加 `@Published` 记得 `import Combine`。
- 可靠性地基：① `@Model` 新字段一律 Optional；② 变更必 `markDirty()`，`isReviewStale` 拦导出；③ 导出服务自复校验；④ 坏草稿只读 + 备份原始字节，唯一出口「另存为新草稿」；⑤ 编辑命令返回 Bool，成功才 `dismiss()`；⑥ 父子归属链在命令层拒。
- ⭐ **Markdown**：`Text(字面量)` 才解析；变量文案一律过 `opsMarkdown(_:)`（`Label` 用闭包形态）。门禁 `tools/ops_ui/check_markdown_callsites.py`。⚠️ 门禁**只覆盖 Mac** —— iOS 共享文案要自己过 `AttributedString(markdown:options:.inlineOnlyPreservingWhitespace)`，否则 `**` 显示成星号。
- ⭐ 媒体门禁：`thmedia:`/64hex 已远端化；`local:`+文件在＝待上传；`local:`+**文件不在＝阻断**；`bundle:` 内置；`http(s)://` 告警。待发布包格式不自创。
- ⭐ 读/写闸门：`apply=False` = 「不许写」**不是**「不许联网」；读 `_send`、写 `_post` **不要合并**。
- ⭐ 子进程六件：读得到基线 / 有 `cryptography` / 能签名 / **授权先于落盘且判据只能是真读** / 授权仓库目录 / 凭证经 `process.environment` 进沙盒（子进程读不到登录钥匙串）。
- ⭐ `fileExists` 在沙盒会骗人 → 唯一判据 `OpsBridgeSettings.isReadableFile(_:)`。
- ⭐ 解释器顺序：显式 → 仓库 `.venv/bin/python3` → homebrew → usr/local → `/usr/bin`；`cryptography` 只装 `tools/time_hall/publication/.venv`。
- ⭐ 沙箱 GUI 拿不到 stdout → 日志落 `harness.log` 并 `stampUntrusted` 盖图；抓图窗口 `.borderless`，触发走文件 `snapshot.request`。target 默认 MainActor → 跨线程盒子显式 `nonisolated`。
- ⭐ 超时/取消是**抛出**不是结果；中断唯一入口 `interrupt(_:)`（先标记 collector 再 SIGTERM）。
- ⭐ 基线快照是编码后产物（`.iso8601` 秒精度）→ 写基线前 `normalizeWorkingCopyToStoragePrecision()`。
- ⭐ 主题跟随：`OpsFlowPalette` 全动态 NSColor；视图层禁用 `Color.white`/固定 hex 当**表面色**。快照 `-dark` 后缀 = 深色验收。
- ⭐⭐ **系列发布 = 一键无感**（10-07 定案）：入口 `OpsWorkspace.publishSeries(cloud:)`
  → 草稿箱记录 `OpsSeriesPublishJob`（SwiftData，新模型已加进两处 schema）→ 标记「发布中」
  → `OpsCloudSyncModel.publishSeriesAuto`（内部 readOnlineBaseline + `adoptBaseline` 自动回填基线
  + `publish(forceLiveRun:true)`）→ **全成功才删草稿记录**，失败/部分成功保留 + 条目级状态
  + 日志路径 + 重试。前端入口：侧栏「发布草稿箱」= `OpsSeriesPublishQueueView`。
  ⚠️ 不拉回整份目录（运营要求），代价 = 本地整包**取代**线上那一版，已在日志留痕。
- ⭐⭐ **S5 提交 = 保存，不顺手发布**（10-07 重做定案）：反馈只有一条两态「保存成功 / 保存失败：<原因>」（`OpsSeriesWizardView.OpsSeriesSubmitFeedback`，单一 `@State` 替换式；失败不清空表单）。**根因**：R07 比的是草稿 `baseReleaseSeq`/`baseRootIndexHash`，而 App **从不回填**它们（`readOnlineBaseline()` 只写 `model.onlineHead`）→ 自动发布必被拒（实测退出码 5，草稿基线 2 / 线上 4）。**解法**：发布前自动 `adoptBaseline(head)` 回填（见上面「系列发布」那条），不再是阻塞。
- ⭐ 系列上新向导：`OpsSeriesEntryDraft`/`OpsSeriesEntryValidator`，提交走 `commitSeriesEntry()` 一票拦截；**首次 = 追加 SaleEvent，再次改价 = `applyPriceCorrection`**。价格表上传入口在 **S2**（`importPriceChartImages`/`appendPriceChartImages`），S1 只选择。ViewBuilder 分支禁 `var`；`@Published` 计算属性无 `$` → 用 `bind(_ keyPath:)`。
- ⭐⭐ **可售尺码勾选**：唯一口径 `CatalogSizeSelectionPolicy.autoFilled`（幂等），判据是「**一个有效尺码都没勾**」——**不是「缺哪些补哪些」**（后者会把用户手动取消的勾回来）；只勾一部分**一个字都不动**。触发**只有 5 个且全是人的动作**；**禁**在 body/onAppear 里对账。写回 `OpsWorkspace.autoSelectSellableSizes(entryID:)`。
- ⭐ 规格卡默认只显示颜色：口径 `CatalogVariantColorGrouping`；**代表图 = 该色第一条有图的规格**（不是 `items[0]`）；`nil`/空串/空白同一组；展开态 `Set<String?>` 换商品必清空；逐条行仍用 `variantLabel`。**S3 快照必须 1900 高**（1180 会被裁 ⇒ 什么也没证明）。
- ⭐⭐ **向导草稿里「系列级」字段，切系列必须重载或清空**（`seriesEntryJSON` 长期持久化 → A 系列的内容原样写进 B，**全程无报错**）。`reloadPriceChartFromSelectedSeries()` **只在用户显式切系列时**跑，不做 `onAppear` 自动装载。⚠️ `coverAssetID` 同类隐患未修。
- ⭐ S2 价格表开关 `declaresPriceChart`：没填与要清空在数据上一样（空串）→ 没开关会静默清掉线上价格表；关着 = 提交一个字都不写。「只有原图没表格」是**合法状态**（`CatalogPriceChart.hasStructuredContent == false`）。
- ⭐ 新建店家：S1 哨兵 `__new_shop__` ↔ `createsNewShop`；`commitSeriesEntry` **先建店家再建系列**，落库回写 `shopID`；唯一入口 `addShopReturningID(name:aliases:)`。

## iOS / 领域层

- 测试隔离：宿主 = 主 App → 落盘测试 `ShopCatalogStorage.useTemporaryForTesting()`；断言只比前后快照或按 `batchID` 收窄。
- 环境：`INFOPLIST_KEY_UILaunchScreen_Generation` 必须 `NO`；iOS destination 写 UDID `FA7332BE-B29E-4879-A139-C68A24314DB1`（`name=` exit 70），macOS 必带 `arch=arm64`；`grep` 一律 `-E`。
- 顺序与价格：一律 `AZIndexGrouping`/`*SortedByName()`，**分区顺序禁用 Set/Dictionary 遍历序**；**修正 ≠ 追加**、修正留空 = 清除、`CatalogSaleEvent` 只 append、缺失 = 「暂无」禁 `deposit ?? 0`。
- 图表与同款：唯一 `ShopCatalogChartPresentation.plan`，必过 `CatalogChartQuality` 门禁、预览即落库；唯一 `ShopCatalogDesignPalette.sameDesignProducts`；详情页「配色」读 `store.designColors`，加购弹窗读 `colors(forProduct:)`，**禁合并**。
- ⭐ 图表「识别成功/失败」判定与文案只在 `SharedCatalog.CatalogChartRecognition`（`headline` 恒带图表名）；界面**只许消费**。⚠️ App 内「上传图片识别」入口是**用户要求删掉的**，`CatalogChartExtraction` 无界面调用方是有意为之。
- ⭐ **Mac 图表文本语法是等号**（`S = 80, 78-83` → `OpsChartTextParsing`），**iOS 是冒号**（`S:80,78-83` → `CatalogManualChartText`）。Mac 侧示例抄 iOS = 用户照填必失败。
- ⭐ 图表表格行标签/列名禁 `lineLimit(1)`（价格表行标签 = 款式名）→ 固定列宽 88pt + 换行；只有值单行。`ImageRenderer` **不画 ScrollView 内容** → 表格本体须为无滚动容器独立 View（`CatalogChartTablePreview`）。
- ⭐⭐ 图表文本录入唯一口径 `SharedCatalog.CatalogChartTextSyntax`：`normalizedSeparators`/`dataColumns`/`parseRowLine`。(a) 列名**只写数据列**（「尺码/款式」是行标签列）；(b) 行值个数 = 剔除后的数据列数；(c) 全角「，」先归一。**⚠️ 把行标签列写进列名 = Mac 放行、iOS 剔除 ⇒ 整列错位且仍显示「识别成功」**。模板 `CatalogChartTemplate.SizeChart`/`PriceChart`（UI placeholder 与测试读同一份）。
- ⭐⭐ **界面示例文案 = 隐式规范，必须与模板同源**（placeholder / 「每一行：…」/ 粘贴面板 `example` 各写一份必然互相矛盾）。锁：`CatalogChartTemplateTests`（171 例）+ `ShopCatalogChartPasteExampleTests`（含旧示例必须判不合格的负向对照）。⚠️ 价格表「单位」是**金额**（元/¥）不是 `cm`；价格表是**系列级展示表**、**不是定价来源**（真价格来自 SaleEvent，无自动校验）。
- 删除与录入：预检与执行**共用** `plan*Deletion`，批量**只写一次覆盖层**；款式名一处决议；同款家族必须同源 `sameStyleFamily`（否则误删草稿）。
- 加购记账：**金额零手输**（尾款读 `currentBalance`）；唯一口径 `ShopCatalogWardrobeEntryPolicy`（现货 = 仅全款）；**四阶段都必须弹选择弹窗**；判付清只用 `isFinalPaymentPlan`；`ClothingEditDraft` 新字段必 Optional。
- 系列：`salePhase`/`reservationEndAt` Optional；**自动流转 = 读取时判定 `effectivePhase`**，不做定时回写；阶段/图文/价格表**只有一处存储**；复用系列只填空不覆盖；`publishOperationKey` 年份逐字 `"2026"`；`balanceDueAt` key 不得改名。
- 表单：`.sheet` 禁挂 `ForEach`/`List` 行视图 → 合成 `enum XxxSheet` 挂页面级；要恢复的落盘；`.onChange(of:)` 对程序化赋值也触发 → 挂 `Binding` setter。Dock 避让 `avoidingBottomDock()`，高度只有 `floatingSurfaceBottomInset` = **72**，只给 tab 根 + tab 内 push。
- 商品改名 = **款式级**：标题只读 `designName`；唯一口径 `ShopCatalogProductRename.plan(...)`；**必须扇出整款**（含已归档）；名称没改禁重新派生款式名；档案 `id` = 款式键必须改键；`applyRenamePlan` **先于** `applySizeChart`。
- ⭐ **iOS 上传/发布不打日志** → 判「上传成功」只能看 ①任务表阶段=发布头且状态=`published` ②线上 `releaseSeq` 是否 +1。`[ShopCatalogSync] 发布头 seq=` 出自只读消费端，与上传无关。
- ⭐ 查线上发布头（只读）：`env -u http_proxy … PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE=<容器>/credentials/cloudkit.development.json .venv/bin/python3 ops_publish_bridge.py --mode baseline --request <req.json>`；凭证在 Mac App **容器**里，仓库没有。
- ⭐ 上传任务三页签：`currentJobs`/`failedJobs`（终态 + retryable，不分日期）/`historyJobs`；`repairStaleTasks()` **只在启动路径**调用。`@State` 页签挂 Section 级。
- ⭐ **图片引用字段清单只一处** `ShopCatalogMediaReferences`；`isRewrittenByPublisher` 与 `allowsAssetID` **必须分开**；导出/打包引用集合必走 `publisherRewritten(in:)`，**禁手拼**（09-28 两端各手拼一份，双双漏 174 张）。
- ⭐ iOS 图片重复上传：存在性**批量**查（分块 200），摘要 + 字节数一致 ⇒ 不传也不回读；`verifiedThisRun` 防末尾二次下载。否则 450 张 → `requestRateLimited` → 发布头永远切不动。⭐ CloudKit `save` **不是 upsert**：内容寻址记录撞 `serverRecordChanged` 要按「已存在」放行。

## 包与跨模块

- `SharedCatalog`（领域/门禁，只许 Foundation/CryptoKit/ImageIO/CoreGraphics）、`PinkHouseOps`（桥接，**产品名 `PinkHouseOpsCore`**，不能与 App target 同名）。
- 四坑：`public` 类型**不会**让成员 public；合成逐成员 init 是 internal；`MemberImportVisibility` 下必须**在使用文件里** import；带协议一致性的 extension 不许加 `public`。包内无 `@_exported` → 每个文件自己 `import SharedCatalog`（`@Published` 还要 `import Combine`）。
