# Pink_House 硬规则索引

> 只留**最容易违反的那一句**；完整口径（签名/判定表/事故经过）见 **`RULES.md`**
> → `grep -n "^## " RULES.md`。构建验收见 skill `pink-house-xcodebuild-acceptance`，
> 抽包见 `ios-local-spm-package-extraction`。
<!-- 小节顺序即重要性：越靠前越不该被上下文截断丢掉。完整口径始终以 RULES.md 为准。 -->

## 待用户拍板

- ✅ 发布通道 = **Mac 导出待发布包 → Python CLI 打 CloudKit**；**不需要 Mac 直连 CloudKit**。
- ✅ **「App 驱动 CLI」已闭环（2026-09-28 实测，不再是待办）**：用户授权仓库目录后，探针 **11 关全绿** —— **子进程真的继承 security-scoped 授权**（S2 未授权侧仍红、S6 授权后退出码 0，两侧不同才证明授权是决定性的）。所以**不必**改「把工具+包搬进 App 容器」那条备选。授权入口现在在**「云端同步」面板的「选择仓库目录…」**（发布中心已移除，那句话不再意味着「只能沿用存量」）。
- ⚠️ **`local:` 改写仍两条路径**：iOS `ShopCatalogOpsPublisher` vs Mac 交 CLI。字段清单已统一，**状态机仍两套**。计划 §6 P4 二选一。
- ✅ **R07 已拍板 C=A+B 并落完**：**A** 只读 `--mode pull-catalog`（四道摘要自证；线上空→`EXIT_OK` 且**不产出**文件；**已下发口径**：不含归档条目、图片已是 `thmedia:`）；**B** 写前比 `baseRootIndexHash` → 不一致则**退出码 5 拒绝**（`dry-run` 同判定）。CLI 49 / 包 50 / `drill_offline.sh` 34 / `selftest_cloudkit_read` 18 全绿。
## Mac 端（target `PinkHouseOps`）

- ⭐ **2026-09-28 云端同步面板 `OpsCloudSyncView.swift`**（单例 `OpsCloudSyncModel`）：工具栏 + 向导 S5 两个入口开同一面板；自检三关（仓库目录 / 解释器 / 凭证）→ 读线上基线 → 拉回目录（blockers 与 caveats 后才许替换草稿）→ 上传（**先导出整包再写冻结请求**，只有 `dryRun==false && receipt.readBackConfirmed==true` 才记已发布）。**仓库目录仍需用户点一次授权**（bookmark 造不出来）。补 `@Published` 别忘了 `import Combine`（缺了报「ObservableObject 不合规」，看不出真因）。
  - **面板只暴露真实远端环境**：`selectableEnvironments = allCases.filter { $0.isRealRemote }` —— 「本机演练 / `localFixture`」不给运营选（不联网、到不了任何设备）。**枚举与 CLI 保留**：离线演练 `drill_bridge_offline.py`（53 项）靠它自证协议与失败路径，删枚举 = 拆回归锁。由此 UI 上不再有「不需要凭证」那一支（两个可选环境都必须要凭证）。
  - **下载侧已实测可用**：探针 S10（`--mode pull-catalog`）在真沙盒里拉到 releaseSeq 1 全量目录并落盘可读（2 店家 / 9 系列 / 263 商品 / 252 尺码表 / 276 图片资源）。
  - **上传侧只差图**：`makePublicationArchive` 引用集合是 560 处 / **450 个不同文件名**，本机只有 **276 张**（Downloads 那个 iOS 旧整包，缺 **174**：尺码表原图 / 系列封面 / 价格表 / 店家 logo）。缺图在**导出那一步**硬失败 ⇒ 连 dry-run 都跑不起来。**174 张只在 iPhone 上**（iOS `plan(for:)` 缺图必抛 `fileMissing`，而那次发布了 398 条媒体任务 ⇒ 设备上文件是全的）。补齐路径：**iOS 重编 → 导出整包（450 张齐全）→ Mac 导入 → 发 seq 2**。
  - dev 云端的 THMedia **已经有这些图**（抽样 12/12 命中 `th.media.<sha256>`），所以 Mac 一旦拿到完整整包，发布成功即 iOS 立刻能看到图。**CloudKit 三个记录类型都「not marked indexable」→ 不能枚举记录、拿不到「文件名→摘要」映射**，所以 174 张无法从云端反推。
- ⭐ **凭证按环境分文件（2026-09-28）**：`cloudkit.<env>.json`；legacy `cloudkit.json` **只对 development 兜底**，绝不给 production 蒙混。s2s key 按环境注册，一份凭证打两个环境 = Production 必然 401。缺对应环境凭证 → `run()` **先抛 `credentialMissing`**，不回落 Keychain（子进程继承沙盒读不到）。摘要只含 containerID/keyID，**私钥永不进 `OpsCredentialSummary`**。⚠️ **导入是按「当前选中的环境」命名落盘的** → 用户在 Development 下选错文件，就会把 production 那份装成 `cloudkit.development.json`（09-28 实际发生）；唯一拦截是 `credentialSummary.declaredEnvironmentMatches`，探针里表现为 **S8 绿（只报 environment=production）、S9/S10 红** —— 查这类「读不通」先看 S8 那行的 `environment=`。
- ⭐ **dev 线上 releaseSeq 1 不是受控发布器产物**：拉回的 560 个引用**全是 `local:`、thmedia: 为 0**，而 `build_release.py` 必然把 `local:` 改写成 `thmedia:`（缺图硬报错）⇒ 那一版是**早期种子发布**。所以：① 谁读到 seq1 都看不到图（占位图）、也看不到新增；② 拉回说明里「图片引用是 thmedia:」原先是**写死的结论**，已改成**实测再报**（`_media_reference_census`，写进 `pull-manifest.json` 的 `mediaReferences` + 日志/结论）。
- ⭐ **切环境必须清空跨环境状态**：`onlineHead`/`pulled`/`outcome`/`lastReceiptSeq`/`baselineAcknowledged` 只对读到它们的那个环境成立；不清 = 拿 Development 的 `seq+1` 写 Production 且**全程无报错**。已由 `targetEnvironment.didSet` + `publish()` 里 `head.environment` 校验双重锁住。
- ⭐ **iOS→Mac 走「整包交接」，不走云端**：iOS「导出整包（含图片）」产出 tar（`shop-catalog.json` + `images/<原文件名>`），接收端 `OpsWorkspace+Handoff.swift`。硬口径：**图片按原文件名进 staging**，走 `<mediaKey>.<ext>` 哈希命名会让所有 `local:` 引用悬空。线上 dev 发布头自 09-25 起停在 seq 1 未变（iOS 的发布没切换它），所以「拉回」拿不到 iOS 新内容。
- ⭐ **2026-09-27 已移除三模块：工作台/素材库/发布中心**（用户拍板）。侧栏只剩 **4 分区**：系列上新/店家与系列/商品管理/本地预览（默认 `.seriesEntry`）。**删了** 7 个文件 + 上传任务台账整层（`mediaJobs`/`importImages` 等）+ `OpsMediaJobRecord`/`OpsPublishJobRecord`（Schema 只剩 `OpsCatalogDraftRecord`，删实体迁移安全已实测）。**保留为服务层（无 UI 入口）**：`validate`/`exportReleasePackage`/`recordConfirmedPublish`/基线差分。`OpsCard` 在 `OpsFormSupport.swift`。发布相关文案一律说「受控发布链路/发布器」，**不要再写「发布中心」「素材库」**。

- **可靠性地基**：① `@Model` **新增字段一律 Optional**（推断失败=App `fatalError`）；② **编辑≠改文案**：变更必过 `markDirty()`，`isReviewStale` 时导出必须被拦；③ 导出服务**自己复校验当前快照**；④ 坏草稿**只提示不隔离=会被空目录覆盖** → 只读态+备份原始字节，四出口全拒，唯一出口「另存为新草稿」；⑤ 编辑命令返回 Bool，**成功才 `dismiss()`**；⑥ 父子归属链在命令层拒。
- ⭐ **Markdown 渲染**：`Text(字面量)` 解析、`Text(变量)` 与 `Text("a"+"b")` **不解析** → 变量文案一律过 `opsMarkdown(_:)`（`inlineOnlyPreservingWhitespace`，两个参数都不能去）。**门禁 `python3 tools/ops_ui/check_markdown_callsites.py`**（R1 参数含 `**` 非单字面量；R2 叙事字段 `guidance/lastErrorMessage/label/help/subtitle` 直喂 `Text`/`Label`；**数据字段 `value`/`text`/`title` 不进清单**）。**编译与单测全绿也发现不了这类缺陷。**
- ⭐ **基线快照是编码后产物**（`.iso8601` 秒精度）→ 直比会让带日期的实体都「已修改」→ **严格策略作用域被静默放大**；写基线前必须 `normalizeWorkingCopyToStoragePrecision()`。
- ⭐ **沙箱 GUI 拿不到 stdout** → 日志落 `harness.log`，**失败还要盖到图上**（`stampUntrusted`）；判快照可信=先看有没有 `SNAPSHOT 造数据失败`。抓图窗口**必须 `.borderless`**，**触发必须走文件 `snapshot.request`**（命令行参数没用）。
- ⭐ **超时/取消是抛出不是结果**：`OpsBridgeRunResult` 禁恒 false 的 `timedOut/cancelled`；中断唯一入口 `interrupt(_:)`，**先标记 collector 再发 SIGTERM**；按阶段保守判定收敛（原 `OpsPublishCenter.concludeInterruption` 所在类已随分区移除，判定逻辑参考包内 `OpsPublisherBridge` 文档注释）。
- **媒体门禁**：`thmedia:`/64hex=已远端化；`local:`+文件在=待上传；`local:`+**文件不在=阻断**；`bundle:`=内置；`http(s)://`=告警；**asset-id 字段里的裸名字=放行+告警，绝不阻断**。待发布包=`shop-catalog.json`+`images/<文件名>`，**不自创第二种格式**。
- ⭐ **读/写闸门**：`apply=False`=**「不许写」不是「不许联网」** → 读走 `_send` 照发、写走 `_post` 静默拦住，**不要合并**（合并会让 `--mode baseline` 谎报「线上尚无发布头」）。锁 `selftest_cloudkit_read.py`。
- ⭐ **子进程六关**：①读得到线上基线 ②有 `cryptography` ③能签名连 CloudKit ④授权先于落盘、判据只能「真读」 ⑤授权过仓库目录（`ops.publishBridgeSettings`）⑥凭证能进沙盒（**子进程读不到登录钥匙串** → 容器内凭证 JSON + `process.environment`，变量名与 `CREDENTIAL_ENV_VAR` 逐字一致）。
- ⭐ **`fileExists` 在沙盒里会骗人** → 唯一判据 `OpsBridgeSettings.isReadableFile(_:)`；**禁** `(try? read(upToCount:1)) != nil`（空文件被误判）。
- ⭐ **解释器候选顺序**：显式设置 → **仓库内 `.venv/bin/python3`** → homebrew → usr/local → `/usr/bin`（沙盒里报 `cannot be used within an App Sandbox`）。`cryptography` 只装 `tools/time_hall/publication/.venv`。
- ⚠️ **本机做不了沙盒实验** → 只能在真实 App 里探：文件触发 `bridge-probe.request`（`BridgeProbeHarness.swift`），产物 `probe.log`/`probe.json`。本 target 开 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` → 跨线程盒子必须显式 `nonisolated`。
- ⭐ **主题跟随（2026-09-27 起）**：`OpsFlowPalette` 全 token 是**动态 NSColor**（`dynamic(light:dark:)`）→ 系统深/浅色切换自动重解析，**视图层零改动**。铁律：视图层不许用 `Color.white`/固定 hex 当**表面色**（背景/文字底），新颜色一律进色板加双值；彩色填充上的白字可保留。快照 harness：目录名 `-dark` 后缀（中划线）= 深色验收，默认钉 aqua。
- ⭐ **系列上新向导（2026-09-27 重构后）**：录入单位=**系列级多类型条目**（`OpsSeriesEntryDraft`/`OpsSeriesEntryValidator`，无任务名称/批次/款式描述字段）；提交=`commitSeriesEntry()` 全量校验一票拦截 → 逐类型写现有链路；**首次=追加 SaleEvent，再次改价=走 applyPriceCorrection（修正≠追加）**；向导状态随 `seriesEntryJSON`（Optional 列，迁移已验）。ViewBuilder 分支禁 `var`/赋值语句（`type '()' cannot conform to 'View'`）；`@Published` 计算属性无 `$` 投影 → 用 `bind(_ keyPath:)`。
- ⭐ **新建店家（2026-09-27 补齐，对齐新建系列）**：向导 S1 店家 Picker 有「＋ 新建店家…」（哨兵 `__new_shop__` ↔ `draft.createsNewShop`，内联店名/别名随草稿持久化）；`commitSeriesEntry` **先建店家再建系列**（外键顺序），落库后回写 `shopID`+`createsNewShop=false` 防重复提交重复建；唯一写入口 `addShopReturningID(name:aliases:)`（别名创建时就落库，`addShop` 只是包装）；目录页 `ShopFormSheet` 保存成功经 `onSaved` 回调**自动选中**新店家。校验：新建态只查 `newShopName` 非空。
## iOS / 领域层

- **测试隔离**：宿主=主 App，`FileManager.default` 就是**用户真实沙盒** → 落盘测试必须 `ShopCatalogStorage.useTemporaryForTesting()`；断言只比前后快照或按 `batchID` 收窄。
- **环境与启动**：`INFOPLIST_KEY_UILaunchScreen_Generation` 必须 `NO`（YES=黑屏，被误判「打不开」），方向只由 Info.plist/pbxproj 决定；iOS destination 写 UDID `FA7332BE-B29E-4879-A139-C68A24314DB1`（`name=` exit 70），macOS 必须写 `arch=arm64`；`grep` 一律 `-E`（BSD 禁空交替，`(a|b|)` **静默不过滤**），搜中文兼搜 `\uXXXX`。
- **顺序与价格**：一律 `AZIndexGrouping`/`*SortedByName()`，**分区顺序禁用 `Set`/`Dictionary` 遍历序派生**（冷启动换排法）；**修正 ≠ 追加**、修正**留空 = 清除**、`CatalogSaleEvent` 只 append、缺失=「暂无」禁 `deposit ?? 0`；发布幂等 ID 按**该类型自己的**价格指纹。
- **图表与同款**：唯一 `ShopCatalogChartPresentation.plan`，识别**必过 `CatalogChartQuality` 门禁**（未过一字不写），`parsePastedText` 共用、**预览即落库**；唯一 `ShopCatalogDesignPalette.sameDesignProducts`，详情页「配色」=`store.designColors`（**不读本商品规格色**），加购弹窗读 `colors(forProduct:)`、**禁合并**。
- **删除与录入**：预检与执行**共用** `plan*Deletion`，批量**只写一次覆盖层**，销售事件保留；`applyStyleForm` 一次 persist，**款式名一处决议**，**同款家族必须同源** `sameStyleFamily`（否则**误删**草稿）。
- **加购记账**：**金额零手输**（**尾款读 `currentBalance`**）；唯一口径 `ShopCatalogWardrobeEntryPolicy`（**现货阶段=仅全款**）；**四阶段都必须弹选择弹窗**；候选取 `options(...)`；**判付清只能用 `isFinalPaymentPlan`**；`ClothingEditDraft` 新字段**必须 Optional**。
- **系列**：`salePhase`/`reservationEndAt` Optional；**自动流转=读取时判定**（`CatalogSeriesSalePhaseResolver.effectivePhase`），**不做定时回写**；**只有「预约结束」「尾款开始」驱动流转**；阶段/图文/价格表**只有一处存储**（`CatalogSeries`），两入口共用 `ShopCatalogSeriesConfigSections`+`saveSeriesConfig`；复用系列**只填空不覆盖**；`publishOperationKey` **只有年份必须逐字 `"2026"`**；`balanceDueAt` key **不得改名**；预约结束**只改引导不剥夺能力**。
- **表单状态**：**`.sheet` 禁挂 `ForEach`/`List` 行视图**（行重建→`@State` 归零）→ 合成 `enum XxxSheet` 挂**页面级**；要恢复的必须落盘（`ShopCatalogFormSnapshotStore`）；**`.onChange(of:)` 对程序化赋值也触发** → 改挂 `Binding` setter。底部 Dock **不参与安全区** → 唯一口径 `avoidingBottomDock()`，高度只有一处 `LegacyCustomTabBarLayout.floatingSurfaceBottomInset`=**72**，只给 **tab 根 + tab 内 push**。
- **商品改名=款式级**：**标题只读 `designName`**；唯一口径 `ShopCatalogProductRename.plan(...)`，入口 `renameProduct(...)`；**必须扇出整款**（含已归档）；**名称没改禁止重新派生款式名**；款式档案 `id`=款式键 → **必须改键**；`applyRenamePlan` **先于** `applySizeChart`。
- ⭐ **上传任务表（本地 SwiftData）三页签 + 启动修复（2026-09-28）**：`ShopCatalogOpsUploadStore` 有 `currentJobs`（今天的非失败）/ `failedJobs`（终态失败+retryable，**不分日期**）/ `historyJobs`（其余）；`repairStaleTasks()` 在 `init` 里把 `.uploading`（上次会话中断）与 `.conflict`（启动时没有运行在跑，媒体任务挂「发布头冲突」就是脏数据）复位 `.staged`、清错误、**不清 attemptCount**。⚠️ 只许在启动路径调用，运行中途调用会把正在跑的任务打回待办。`@State` 页签挂在 Section 级视图上，不挂 List 行视图（行重建归零）。
- ⭐ **图片引用字段清单只一处**：`ShopCatalogMediaReferences`，与 Python `collect_shop_catalog_media`、iOS `ShopCatalogOpsMediaStaging.rewrite` 同步；`isRewrittenByPublisher` 与 `allowsAssetID` **必须分开**（合并会丢商品图）。⭐ **打包/导出整包的引用集合必须走 `publisherRewritten(in:)`，禁止手拼**「assets 三个 URL」—— 2026-09-28 实测 iOS 导出与 Mac `makePublicationArchive` 各手拼一份，双双漏掉 sizeCharts(147)+价格表(16)+系列封面(9)+店家(2)=**174 张**，整包一进发布端就硬报错、根本发不出去。共享层 `fieldPaths`/`publisherRewritten` 有测试锁，出问题的永远是**调用点绕过它**。
- ⭐ **iOS 图片重复上传拦截（2026-09-28 加）**：旧逻辑对**每张图**都「单点查存在性 → 不存在才传 → 无条件把整张图下载回来算 hash」，末尾 `verifyEndToEnd` 又把 assets 的图再下载一遍 → 450 张 = 上千次 CloudKit 操作 → 撞 `requestRateLimited` → 任务落 `retryable` → `unresolved` 非空 → **发布头永远切不动**（线上停在 seq 1 就是这个）。三条拦截：① 存在性**批量**查（`fetchMediaMetadata(mediaKeys:)`，分块 200，450→3 次；带默认实现以免打断测试替身）；② 线上已有且摘要+字节数一致 ⇒ **不传字节也不回读字节**（`THMedia` 内容寻址且不可变），只有本次真上传的才拉字节校验；③ `verifiedThisRun` 让末尾验证不再二次下载。拦截必须可见 → `ShopCatalogOpsMediaStats`（新传/跳过/未通过）。⭐ **CloudKit `save` 不是 upsert**：记录名已存在 + 新建 CKRecord（无 change tag）→ `serverRecordChanged`，对内容寻址不可变记录（THMedia/THDataPack）要**按「已存在」放行**交给回读校验，否则媒体任务会被误标「发布头冲突」。
## 包与跨模块

- `SharedCatalog`（领域/门禁，**只许** Foundation/CryptoKit/ImageIO/CoreGraphics）、`PinkHouseOps`（桥接，**产品名 `PinkHouseOpsCore`——不能与 App target 同名**）；编排与界面留在各自 App。
- 三坑：`public` 类型**不会**让成员 public；**合成逐成员 init 是 internal**（对 Optional `var` 隐式 `nil`）；`MemberImportVisibility` 下必须**在使用文件里**显式 import；**带协议一致性的 extension 不许加 `public`**。包内**没有** `@_exported` 桥接文件 → 每个文件自己 `import SharedCatalog`（`ObservableObject`/`@Published` 还要 `import Combine`）。
