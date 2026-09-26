# Pink_House 硬规则索引

> 只留**最容易违反的那一句**；完整口径（签名/判定表/事故经过）见 **`RULES.md`**
> → `grep -n "^## " RULES.md`。构建验收见 skill `pink-house-xcodebuild-acceptance`，
> 抽包见 `ios-local-spm-package-extraction`。
<!-- 小节顺序即重要性：越靠前越不该被上下文截断丢掉。完整口径始终以 RULES.md 为准。 -->

## 待用户拍板

- ✅ 发布通道 = **Mac 导出待发布包 → Python CLI 打 CloudKit**；**不需要 Mac 直连 CloudKit**。
- ⏳ **「App 驱动 CLI」未闭环**：用户从未授权过仓库目录（探针实测）→ 子进程能否继承 security-scoped 扩展无法验。若不成立 → 改「把工具+包搬进 App 容器」。**授权后跑一次探针即定论。**
- ⚠️ **`local:` 改写仍两条路径**：iOS `ShopCatalogOpsPublisher` vs Mac 交 CLI。字段清单已统一，**状态机仍两套**。计划 §6 P4 二选一。
- ✅ **R07 已拍板 C=A+B 并落完**：**A** 只读 `--mode pull-catalog`（四道摘要自证；线上空→`EXIT_OK` 且**不产出**文件；**已下发口径**：不含归档条目、图片已是 `thmedia:`）；**B** 写前比 `baseRootIndexHash` → 不一致则**退出码 5 拒绝**（`dry-run` 同判定）。CLI 49 / 包 50 / `drill_offline.sh` 34 / `selftest_cloudkit_read` 18 全绿。
## Mac 端（target `PinkHouseOps`）

- **可靠性地基**：① `@Model` **新增字段一律 Optional**（推断失败=App `fatalError`）；② **编辑≠改文案**：变更必过 `markDirty()`，`isReviewStale` 时导出必须被拦；③ 导出服务**自己复校验当前快照**；④ 坏草稿**只提示不隔离=会被空目录覆盖** → 只读态+备份原始字节，四出口全拒，唯一出口「另存为新草稿」；⑤ 编辑命令返回 Bool，**成功才 `dismiss()`**；⑥ 父子归属链在命令层拒。
- ⭐ **Markdown 渲染**：`Text(字面量)` 解析、`Text(变量)` 与 `Text("a"+"b")` **不解析** → 变量文案一律过 `opsMarkdown(_:)`（`inlineOnlyPreservingWhitespace`，两个参数都不能去）。**门禁 `python3 tools/ops_ui/check_markdown_callsites.py`**（R1 参数含 `**` 非单字面量；R2 叙事字段 `guidance/lastErrorMessage/label/help/subtitle` 直喂 `Text`/`Label`；**数据字段 `value`/`text`/`title` 不进清单**）。**编译与单测全绿也发现不了这类缺陷。**
- ⭐ **基线快照是编码后产物**（`.iso8601` 秒精度）→ 直比会让带日期的实体都「已修改」→ **严格策略作用域被静默放大**；写基线前必须 `normalizeWorkingCopyToStoragePrecision()`。
- ⭐ **沙箱 GUI 拿不到 stdout** → 日志落 `harness.log`，**失败还要盖到图上**（`stampUntrusted`）；判快照可信=先看有没有 `SNAPSHOT 造数据失败`。抓图窗口**必须 `.borderless`**，**触发必须走文件 `snapshot.request`**（命令行参数没用）。
- ⭐ **超时/取消是抛出不是结果**：`OpsBridgeRunResult` 禁恒 false 的 `timedOut/cancelled`；中断唯一入口 `interrupt(_:)`，**先标记 collector 再发 SIGTERM**；按阶段保守判定走 `OpsPublishCenter.concludeInterruption`。
- **媒体门禁**：`thmedia:`/64hex=已远端化；`local:`+文件在=待上传；`local:`+**文件不在=阻断**；`bundle:`=内置；`http(s)://`=告警；**asset-id 字段里的裸名字=放行+告警，绝不阻断**。待发布包=`shop-catalog.json`+`images/<文件名>`，**不自创第二种格式**。
- ⭐ **读/写闸门**：`apply=False`=**「不许写」不是「不许联网」** → 读走 `_send` 照发、写走 `_post` 静默拦住，**不要合并**（合并会让 `--mode baseline` 谎报「线上尚无发布头」）。锁 `selftest_cloudkit_read.py`。
- ⭐ **子进程六关**：①读得到线上基线 ②有 `cryptography` ③能签名连 CloudKit ④授权先于落盘、判据只能「真读」 ⑤授权过仓库目录（`ops.publishBridgeSettings`）⑥凭证能进沙盒（**子进程读不到登录钥匙串** → 容器内凭证 JSON + `process.environment`，变量名与 `CREDENTIAL_ENV_VAR` 逐字一致）。
- ⭐ **`fileExists` 在沙盒里会骗人** → 唯一判据 `OpsBridgeSettings.isReadableFile(_:)`；**禁** `(try? read(upToCount:1)) != nil`（空文件被误判）。
- ⭐ **解释器候选顺序**：显式设置 → **仓库内 `.venv/bin/python3`** → homebrew → usr/local → `/usr/bin`（沙盒里报 `cannot be used within an App Sandbox`）。`cryptography` 只装 `tools/time_hall/publication/.venv`。
- ⚠️ **本机做不了沙盒实验** → 只能在真实 App 里探：文件触发 `bridge-probe.request`（`BridgeProbeHarness.swift`），产物 `probe.log`/`probe.json`。本 target 开 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` → 跨线程盒子必须显式 `nonisolated`。
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
- **图片引用字段清单只一处**：`ShopCatalogMediaReferences`，与 Python `collect_shop_catalog_media`、iOS `ShopCatalogOpsMediaStaging.rewrite` 同步；`isRewrittenByPublisher` 与 `allowsAssetID` **必须分开**（合并会丢商品图）。
## 包与跨模块

- `SharedCatalog`（领域/门禁，**只许** Foundation/CryptoKit/ImageIO/CoreGraphics）、`PinkHouseOps`（桥接，**产品名 `PinkHouseOpsCore`——不能与 App target 同名**）；编排与界面留在各自 App。
- 三坑：`public` 类型**不会**让成员 public；**合成逐成员 init 是 internal**（对 Optional `var` 隐式 `nil`）；`MemberImportVisibility` 下必须**在使用文件里**显式 import；**带协议一致性的 extension 不许加 `public`**。包内**没有** `@_exported` 桥接文件 → 每个文件自己 `import SharedCatalog`（`ObservableObject`/`@Published` 还要 `import Combine`）。
