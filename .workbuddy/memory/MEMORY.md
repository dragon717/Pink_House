# Pink_House 硬规则索引

> **这是索引，不是手册。** 每行只说「最容易违反的那一句」+ 必须记住的标识符；
> 事故经过 / 签名 / 判定表一律见 **`RULES.md`** → `grep -n "^## " RULES.md`。
> 构建验收见 skill `pink-house-xcodebuild-acceptance`，抽包见 `ios-local-spm-package-extraction`。
> **写新条目时先问：这一行删掉会不会有人写出错代码？不会就别写。**

## 状态

- ⚠️ **`local:` 改写两套状态机**：iOS `ShopCatalogOpsPublisher` vs Mac 交 CLI（字段清单已统一）。计划 §6 P4 二选一。
- 发布通道 = **Mac 导出待发布包 → Python CLI 打 CloudKit**；App **不直连** CloudKit。
- R07：只读 `--mode pull-catalog`（线上空 → `EXIT_OK` 且**不产出**文件；不含归档条目）；写前比 `baseRootIndexHash`，不一致**退出码 5**。
- **本机演练 + 离线演练已全删（2026-09-29）**：`localFixture`/`isRealRemote`/`selectableEnvironments`/环境派生 `adapter`/`requiresCredentialFile` 全删；两个 `drill_*` 脚本删除。**流水线从此没有离线自证，拒绝路径只能在真连上验。** 保留 `--allow-unapproved-local-fixture` 标记 + **四份 `selftest_*`（35/18/16/6）**。桥接器只认 `development`/`production`，其它值**报错不回落**（退出码 4）。

## Mac 端（target `PinkHouseOps`）

- ⭐ **出网唯一入口 `open_https()`；`create_connection` 的地址回退不覆盖 TLS**（2026-09-29 根因修复）。`connect_first_ready` 把「就绪」定义成 **TLS 之后**；**禁止在适配层直接写 `urlopen`**（`selftest_network_failover.py` 16 项会红）。⚠️ **网络失败 ≠ 内部错误**：退出码 **7**；只读 `retryable=True`，**发布 `pendingConfirmation` 且不可重试**（先 `--mode query`，R09）。
- ⭐ **日志必须落盘 + 能一次拿走**（2026-09-29）：`bridge/logs/<runID>.log` + `latest.log`；面板「复制日志」必须带头部（环境/模式/线上发布号/失败原因）。**`perform` 之外的早退路径（门禁 / 导出整包 / 写请求文件）也必须落盘**（`failBeforeBridge(_:mode:)`）—— 实测卡住用户的正是导出失败那条，原先一个文件都不留。
- ⭐ **「点了没反应」和「失败了」必须分开**：任何「操作型」卡片都必须有失败分支（下载卡片原先只有 `if let pulled`，失败时一个字都不显示）。
- ⭐ **切环境必须清空** `onlineHead`/`pulled`/`outcome`/`lastReceiptSeq`/`baselineAcknowledged`/`lastError`/`pullFailure` —— 不清 = 拿 Development 的 `seq+1` 写 Production 且**全程无报错**。双锁：`targetEnvironment.didSet` + `publish()` 里校验 `head.environment`。
- ⭐ **下载侧通、上传侧只差图**：拉回 releaseSeq 1 = 2 店家 / 9 系列 / 263 商品。上传卡在**导出**：引用 560 处 / **450 个文件名**，本机只有 **276 张**，缺 **174** ⇒ 导出硬失败、`publish-seq2/` 为空、**线上没被改动、重试安全**。补齐路径 **iOS 重编 → 导出整包 → Mac 导入 → 发 seq 2**；**CloudKit 三个记录类型 not marked indexable，无法从云端反推**。
- ⭐ **dev 线上 releaseSeq 1 不是受控发布器产物**：560 个引用**全是 `local:`、thmedia: 0**，而 `build_release.py` 必然改写成 `thmedia:`。所以别写死「图片引用是 thmedia:」，**实测再报**（`_media_reference_census` → `pull-manifest.json` 的 `mediaReferences`）。
- ⭐ **凭证按环境分文件** `cloudkit.<env>.json`；legacy `cloudkit.json` **只对 development 兜底**。缺则**先抛 `credentialMissing`**，不回落 Keychain。**私钥永不进 `OpsCredentialSummary`**。⚠️ **导入按「当前选中的环境」命名落盘** → Development 下选错文件会把 production 那份装成 `cloudkit.development.json`；唯一拦截 `credentialSummary.declaredEnvironmentMatches`（探针里 **S8 绿、S9/S10 红** → 查「读不通」先看 S8 的 `environment=`）。
- ⭐ **iOS→Mac 走整包交接**（tar = `shop-catalog.json` + `images/<文件名>`），接收端 `OpsWorkspace+Handoff.swift`。**图片必须按原文件名进 staging**，哈希命名会让所有 `local:` 引用悬空。
- ⭐ **侧栏只剩 4 分区**（09-27 移除工作台/素材库/发布中心）：系列上新 / 店家与系列 / 商品管理 / 本地预览。**保留为服务层（无 UI）**：`validate`/`exportReleasePackage`/`recordConfirmedPublish`/基线差分。发布文案只说「受控发布链路 / 发布器」。
- ⭐ **云端同步面板** `OpsCloudSyncView.swift`（单例 `OpsCloudSyncModel`，工具栏 + 向导 S5 同入口）：自检三关 → 读基线 → 拉回 → 上传（**先导出整包再写冻结请求**；只有 `dryRun==false && receipt.readBackConfirmed==true` 才记已发布）。**仓库目录需用户点一次授权**（bookmark 造不出来）。补 `@Published` 别忘了 `import Combine`（否则报「ObservableObject 不合规」）。
- **可靠性地基**：① `@Model` **新增字段一律 Optional**；② 变更必过 `markDirty()`，`isReviewStale` 时导出必须被拦；③ 导出服务**自己复校验当前快照**；④ 坏草稿**只提示不隔离 = 会被空目录覆盖** → 只读态 + 备份原始字节，唯一出口「另存为新草稿」；⑤ 编辑命令返回 Bool，**成功才 `dismiss()`**；⑥ 父子归属链在命令层拒。
- ⭐ **Markdown**：`Text(字面量)` 解析，`Text(变量)` 与 `Text("a"+"b")` **不解析** → 变量文案一律过 `opsMarkdown(_:)`（`inlineOnlyPreservingWhitespace`，两个参数都不能去）。**门禁 `python3 tools/ops_ui/check_markdown_callsites.py`**（数据字段 `value`/`text`/`title` **不进**清单）。**编译与单测全绿发现不了这类缺陷。**
- ⭐ **媒体门禁**：`thmedia:`/64hex = 已远端化；`local:`+文件在 = 待上传；`local:`+**文件不在 = 阻断**；`bundle:` = 内置；`http(s)://` = 告警；**asset-id 里的裸名字 = 放行 + 告警**。待发布包 = `shop-catalog.json` + `images/<文件名>`，**不自创第二种格式**。
- ⭐ **读/写闸门**：`apply=False` = **「不许写」不是「不许联网」** → 读走 `_send`、写走 `_post` 静默拦住，**不要合并**（合并会让 `--mode baseline` 谎报「线上尚无发布头」）。锁 `selftest_cloudkit_read.py`。
- ⭐ **子进程六件必需品**：读得到基线 / 有 `cryptography` / 能签名连 CloudKit / **授权先于落盘且判据只能是「真读」** / 授权过仓库目录（`ops.publishBridgeSettings`）/ 凭证能进沙盒（**子进程读不到登录钥匙串** → 容器内 JSON + `process.environment`，变量名与 `CREDENTIAL_ENV_VAR` 逐字一致）。
- ⭐ **`fileExists` 在沙盒里会骗人** → 唯一判据 `OpsBridgeSettings.isReadableFile(_:)`；**禁** `(try? read(upToCount:1)) != nil`。
- ⭐ **解释器候选顺序**：显式设置 → **仓库内 `.venv/bin/python3`** → homebrew → usr/local → `/usr/bin`。`cryptography` 只装 `tools/time_hall/publication/.venv`。
- ⭐ **沙箱 GUI 拿不到 stdout** → 日志落 `harness.log`，**失败还要盖到图上**（`stampUntrusted`）。抓图窗口**必须 `.borderless`**，**触发必须走文件 `snapshot.request`**。⚠️ **本机做不了沙盒实验** → 只能在真实 App 里探（文件触发 `bridge-probe.request`，产物 `probe.log`）。本 target `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` → 跨线程盒子必须显式 `nonisolated`。
- ⭐ **超时/取消是抛出不是结果**：`OpsBridgeRunResult` 禁恒 false 的 `timedOut/cancelled`；中断唯一入口 `interrupt(_:)`，**先标记 collector 再发 SIGTERM**。
- ⭐ **基线快照是编码后产物**（`.iso8601` 秒精度）→ 直比会让带日期的实体都「已修改」；写基线前必须 `normalizeWorkingCopyToStoragePrecision()`。
- ⭐ **主题跟随**：`OpsFlowPalette` 全 token 是动态 NSColor。铁律：视图层不许用 `Color.white`/固定 hex 当**表面色**；新颜色一律进色板加双值（彩色填充上的白字可保留）。快照目录名 `-dark` 后缀 = 深色验收。
- ⭐ **系列上新向导**：录入单位 = 系列级多类型条目（`OpsSeriesEntryDraft`/`OpsSeriesEntryValidator`）；提交 = `commitSeriesEntry()` 全量校验一票拦截；**首次 = 追加 SaleEvent，再次改价 = `applyPriceCorrection`（修正≠追加）**。ViewBuilder 分支禁 `var`/赋值语句；`@Published` 计算属性无 `$` 投影 → 用 `bind(_ keyPath:)`。
- ⭐ **新建店家**：S1 Picker 哨兵 `__new_shop__` ↔ `draft.createsNewShop`；`commitSeriesEntry` **先建店家再建系列**，落库后回写 `shopID` + `createsNewShop=false`；唯一写入口 `addShopReturningID(name:aliases:)`。

## iOS / 领域层

- **测试隔离**：宿主 = 主 App → 落盘测试必须 `ShopCatalogStorage.useTemporaryForTesting()`；断言只比前后快照或按 `batchID` 收窄。
- **环境与启动**：`INFOPLIST_KEY_UILaunchScreen_Generation` 必须 `NO`；iOS destination 写 UDID `FA7332BE-B29E-4879-A139-C68A24314DB1`（`name=` exit 70），macOS 必须 `arch=arm64`；`grep` 一律 `-E`（BSD 禁空交替，`(a|b|)` **静默不过滤**），搜中文兼搜 `\uXXXX`。
- **顺序与价格**：一律 `AZIndexGrouping`/`*SortedByName()`，**分区顺序禁用 `Set`/`Dictionary` 遍历序派生**；**修正 ≠ 追加**、修正**留空 = 清除**、`CatalogSaleEvent` 只 append、缺失 = 「暂无」禁 `deposit ?? 0`；发布幂等 ID 按**该类型自己的**价格指纹。
- **图表与同款**：唯一 `ShopCatalogChartPresentation.plan`，**必过 `CatalogChartQuality` 门禁**（未过一字不写）、**预览即落库**；唯一 `ShopCatalogDesignPalette.sameDesignProducts`；详情页「配色」= `store.designColors`（**不读本商品规格色**），加购弹窗读 `colors(forProduct:)`、**禁合并**。
- **删除与录入**：预检与执行**共用** `plan*Deletion`，批量**只写一次覆盖层**；**款式名一处决议**；**同款家族必须同源 `sameStyleFamily`**（否则**误删**草稿）。
- **加购记账**：**金额零手输**（**尾款读 `currentBalance`**）；唯一口径 `ShopCatalogWardrobeEntryPolicy`（**现货阶段 = 仅全款**）；**四阶段都必须弹选择弹窗**；**判付清只能用 `isFinalPaymentPlan`**；`ClothingEditDraft` 新字段**必须 Optional**。
- **系列**：`salePhase`/`reservationEndAt` Optional；**自动流转 = 读取时判定**（`effectivePhase`），**不做定时回写**；**只有「预约结束」「尾款开始」驱动流转**；阶段/图文/价格表**只有一处存储**；复用系列**只填空不覆盖**；`publishOperationKey` 年份必须逐字 `"2026"`；`balanceDueAt` key **不得改名**。
- **表单状态**：**`.sheet` 禁挂 `ForEach`/`List` 行视图** → 合成 `enum XxxSheet` 挂**页面级**；要恢复的必须落盘；**`.onChange(of:)` 对程序化赋值也触发** → 改挂 `Binding` setter。底部 Dock 唯一口径 `avoidingBottomDock()`，高度只有 `LegacyCustomTabBarLayout.floatingSurfaceBottomInset` = **72**，只给 **tab 根 + tab 内 push**。
- **商品改名 = 款式级**：**标题只读 `designName`**；唯一口径 `ShopCatalogProductRename.plan(...)`；**必须扇出整款**（含已归档）；**名称没改禁止重新派生款式名**；款式档案 `id` = 款式键 → **必须改键**；`applyRenamePlan` **先于** `applySizeChart`。
- ⭐ **上传任务表三页签**：`currentJobs` / `failedJobs`（终态失败 + retryable，**不分日期**）/ `historyJobs`；`repairStaleTasks()` 只许在**启动路径**调用（运行中途调用会把正在跑的任务打回待办）。`@State` 页签挂 Section 级，不挂 List 行视图。
- ⭐ **图片引用字段清单只一处** `ShopCatalogMediaReferences`；`isRewrittenByPublisher` 与 `allowsAssetID` **必须分开**（合并会丢商品图）。**导出整包/打包的引用集合必须走 `publisherRewritten(in:)`，禁止手拼** —— 09-28 实测 iOS 与 Mac 各手拼一份，双双漏掉 **174 张**（sizeCharts 147 + 价格表 16 + 系列封面 9 + 店家 2）。
- ⭐ **iOS 图片重复上传拦截**：存在性**批量**查（分块 200）；线上已有且摘要 + 字节数一致 ⇒ **不传也不回读字节**；`verifiedThisRun` 让末尾验证不再二次下载。否则 450 张 → 上千次 CloudKit 操作 → `requestRateLimited` → `unresolved` 非空 → **发布头永远切不动**。拦截可见性 `ShopCatalogOpsMediaStats`。⭐ **CloudKit `save` 不是 upsert**：对内容寻址不可变记录（THMedia/THDataPack）撞 `serverRecordChanged` 要**按「已存在」放行**，否则被误标「发布头冲突」。

## 包与跨模块

- `SharedCatalog`（领域/门禁，**只许** Foundation/CryptoKit/ImageIO/CoreGraphics）、`PinkHouseOps`（桥接，**产品名 `PinkHouseOpsCore` —— 不能与 App target 同名**）。
- 四坑：`public` 类型**不会**让成员 public；**合成逐成员 init 是 internal**；`MemberImportVisibility` 下必须**在使用文件里**显式 import；**带协议一致性的 extension 不许加 `public`**。包内**没有** `@_exported` 桥接文件 → 每个文件自己 `import SharedCatalog`（`@Published` 还要 `import Combine`）。
