//
//  OpsWorkspace.swift
//  PinkHouseOps
//
//  Mac 运营工具的**编排层**：草稿装载、素材导入、发布前校验、导出待发布包。
//
//  ## 它在架构里的位置（计划 §3）
//
//      SharedCatalog（领域事实：模型 / 协议 / 图片规范化 / 发布门禁）
//            ↑                    ↑
//      ItemManager（iOS）    PinkHouseOps（Mac，本文件所在层）
//
//  本文件只做编排与落盘，**不重新定义任何口径**：
//    · 图片规范化与 mediaKey → `ShopCatalogMediaStaging`
//    · 发布前门禁       → `ShopCatalogPublicationGate`
//    · 任务状态机       → `MediaUploadJobMachine`
//    · JSON 编解码      → `ShopCatalogJSONCoding`
//    · 整包归档         → `ShopCatalogExportArchive`
//
//  ## 为什么素材必须立刻复制进 staging
//
//  `.fileImporter` 给的是 **security-scoped URL**：作用域只在当前会话内有效，
//  下次启动就取不到了；运营把图放在移动硬盘 / 另一台机器上再拔掉，文件也没了。
//  所以拿到 URL 的第一件事是把字节**复制进应用自己的目录**，
//  之后一切以 staging 副本为准（计划 §4.1 第 2 步）。
//  目录 JSON 同理 —— 导入之后草稿内容就是唯一事实来源，不再回读原路径。
//
//  ## 可靠性地基（方案 §2 的 R01–R03，本文件是主要落点）
//
//  · **R01 校验会过期**：编辑 ≠ 只改一句文案。任何变更都递增 `draftRevision`
//    并让上一次校验结果失效；导出入口**自己再跑一次门禁**再取产物，
//    杜绝「校验的是 A、导出去的是 B」。
//  · **R02 保存失败会被后续成功文案盖掉**：`saveDraft()` 返回 Bool，
//    失败**保留内存里的编辑内容**且绝不报告成功；导图的汇总文案不能覆盖保存错误。
//  · **R03 坏草稿只提示不隔离**：解码失败进入**只读隔离态**并备份原始字节，
//    保存 / 导图 / 导入 / 导出一律拒绝，只能「另存为新草稿」后继续。
//
//  一个贯穿三条的统一原则：**内存里的 `catalog` 是唯一工作副本，
//  界面上显示的成功/失败必须与「磁盘上真的发生了什么」一致。**
//

import Combine
import Foundation
import Observation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class OpsWorkspace: ObservableObject {

    // MARK: 状态

    /// 当前草稿的元数据（nil = 还没建过草稿）
    @Published private(set) var draft: OpsCatalogDraftRecord?
    /// 内存里的工作副本。所有编辑改这一份，保存时整包编码落盘。
    ///
    /// ## 为什么 setter 是 `internal(set)` 而不是 `private(set)`
    ///
    /// Swift 的 `private(set)` 是**按文件**生效的：它只允许**本文件**里的扩展写入。
    /// 但这组编辑命令按职责拆在 `OpsWorkspace+Editing.swift`（录入语义）、
    /// `OpsWorkspace+Publishing.swift` 里，那是类型自己的代码、不在本文件 ——
    /// 于是 `private(set)` 会把它们全部挡在门外（实测 184 处编译错）。
    ///
    /// 语言没有「setter 只对同类型的其它文件可见」这一档，所以只能放开成默认的
    /// `internal`（写成 `internal(set)` 也一样，编译器还会警告冗余）。**这不代表
    /// 契约松了**，写入口径依旧是：
    ///   · 内容变更一律走本类型的编辑方法（`canMutate()` 门禁 → 改 `catalog`
    ///     → `markDirty()`），**视图层只读、一行都不许写**；
    ///   · 反馈只写 `statusMessage` / `lastError`（全局 banner 是唯一通道）。
    /// 视图层（`PinkHouseOps/Views/`）当前对这四个字段**全部是读**（已核对）。
    @Published var catalog = ShopCatalog()
    /// 最近一次导入 / 导出 / 校验的可见反馈（界面上必须有地方显示，
    /// 否则「点了没反应」会被当成功能坏了 —— 计划 §7 的「失败必须可见」）
    @Published var statusMessage: String?
    @Published var lastError: String?
    /// 导入的图片任务（按 mediaKey 唯一）
    @Published private(set) var mediaJobs: [MediaUploadJob] = []
    /// 最近一次发布前校验结果（nil = 还没校验过，或校验后被编辑作废）
    @Published private(set) var review: ShopCatalogPublicationReview?

    private let context: ModelContext
    private let fileManager = FileManager.default

    /// 发布中心需要同一个 `ModelContext` 来写发布任务台账。
    /// 暴露只读访问而不是让它自己再建容器的第二个 context：两个 context
    /// 写同一个库会让「刚保存的草稿」在另一侧看不见。
    var modelContextForPublishing: ModelContext { context }

    /// 发布中心。**懒建**：它需要 workspace 自己，构造期不能互相引用
    /// （`OpsWorkspace.init` 里 `self` 还不完整）。
    lazy var publishCenter = OpsPublishCenter(workspace: self)

    init(context: ModelContext) {
        self.context = context
        loadOrCreateDraft()
    }

    // MARK: 版本 / 状态派生（视图只读这些，不自己算）

    /// 当前编辑版本号（每次内容变更 +1）
    var currentRevision: Int { draft?.currentRevision ?? 0 }
    /// 已落盘的版本号
    var savedRevision: Int { draft?.lastSavedRevision ?? 0 }
    /// 有未保存的修改
    var hasUnsavedChanges: Bool { currentRevision != savedRevision }
    /// 上一次校验对应的版本（nil = 从未校验）
    var reviewedRevision: Int? { draft?.reviewedRevision }
    /// 校验结果是否已过期 —— 为 true 时导出必须被拦（R01）
    var isReviewStale: Bool {
        guard review != nil else { return false }
        return (draft?.isReviewCurrent ?? false) == false
    }
    /// 草稿处于「内容解不开」的只读隔离态（R03）
    var isCorrupted: Bool { draft?.isCorrupted ?? false }
    /// 草稿是否可编辑（损坏时一律不可编辑）
    var canEdit: Bool { draft != nil && !isCorrupted }

    // MARK: 目录位置

    /// 应用容器内的数据根目录。沙箱下就是
    /// `~/Library/Containers/bugod2.ItemManager.Ops/Data/Library/Application Support/PinkHouseOps/`
    var rootDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("PinkHouseOps", isDirectory: true)
    }

    /// 当前草稿的 staging 目录：图片副本与待发布包都放这里
    var stagingDirectory: URL {
        let name = draft?.stagingFolderName ?? "default"
        return rootDirectory
            .appendingPathComponent("staging", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    /// staging 里现有的文件名集合（门禁据此判断「引用到的图在不在本机」）
    var stagedFileNames: Set<String> {
        let names = (try? fileManager.contentsOfDirectory(atPath: stagingDirectory.path)) ?? []
        return Set(names)
    }

    // MARK: 草稿装载 / 保存

    private func loadOrCreateDraft() {
        let descriptor = FetchDescriptor<OpsCatalogDraftRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let existing = (try? context.fetch(descriptor)) ?? []
        // 跳过处于只读隔离态的历史草稿：它们留在库里做证据，但不该被自动打开
        // （打开只会得到一个空目录，运营会以为「内容丢了」）。
        if let first = existing.first(where: { ($0.corruptionDetected ?? false) == false }) {
            adopt(first)
            statusMessage = "已恢复上次草稿「\(first.title)」（第 \(first.currentRevision) 版）"
        } else if let corrupted = existing.first {
            adopt(corrupted)
            statusMessage = "库里只剩一份「内容解不开」的草稿，已按只读方式打开。"
        } else {
            createDraft(title: defaultDraftTitle())
        }
        loadMediaJobs()
    }

    private func defaultDraftTitle() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: Date())) 上新"
    }

    private func adopt(_ record: OpsCatalogDraftRecord) {
        draft = record
        do {
            catalog = try ShopCatalogJSONCoding.decoder()
                .decode(ShopCatalog.self, from: record.catalogJSON)
            if record.corruptionDetected == true {
                // 内容又解得开了（例如有人手工修好了字节）：解除隔离，但备份留着
                record.corruptionDetected = false
                try? context.save()
            }
            lastError = nil
        } catch {
            // R03：坏 JSON **不静默兜成空目录** —— 一旦允许在空目录上保存，
            // 原始内容就被永久覆盖了（这正是旧实现只写一句提示、实际仍可覆盖的问题）。
            // 现在：进入只读隔离 + 备份原始字节；所有写入入口都会被 `canEdit` 拦下。
            catalog = ShopCatalog()
            record.corruptionDetected = true
            if record.corruptedBackupJSON == nil {
                record.corruptedBackupJSON = record.catalogJSON
            }
            try? context.save()
            lastError = "草稿内容无法解析，已进入**只读隔离**（原始字节保留，任何保存都不会覆盖它）。"
                + "请用下方的「另存为新草稿」继续工作。原因："
                + error.localizedDescription
        }
        try? fileManager.createDirectory(
            at: stagingDirectory, withIntermediateDirectories: true)
    }

    /// 显式换到另一份草稿（多草稿管理在 M4，这里先给恢复流程用）
    @discardableResult
    func adoptDraft(id: String) -> Bool {
        let descriptor = FetchDescriptor<OpsCatalogDraftRecord>(
            predicate: #Predicate { $0.id == id })
        guard let record = (try? context.fetch(descriptor))?.first else {
            lastError = "找不到草稿 \(id)。"
            return false
        }
        review = nil
        adopt(record)
        loadMediaJobs()
        return true
    }

    @discardableResult
    func createDraft(title: String) -> OpsCatalogDraftRecord {
        let empty = ShopCatalog()
        let data = (try? ShopCatalogJSONCoding.encoder(prettyPrinted: true).encode(empty))
            ?? Data("{}".utf8)
        let record = OpsCatalogDraftRecord(title: title, catalogJSON: data)
        context.insert(record)
        try? context.save()
        review = nil
        adopt(record)
        statusMessage = "已新建草稿「\(title)」"
        lastError = nil
        return record
    }

    /// 落盘。**显式调用**，不在每次编辑时自动写盘 —— 自动写盘会让「误改了字段」
    /// 变得不可撤销，而且目录整包编码不便宜。
    ///
    /// - Returns: 是否真的写盘成功。**调用方必须看返回值**（R02）：
    ///   失败时内存里的编辑内容仍然保留，绝不能被后续成功文案盖掉。
    @discardableResult
    func saveDraft() -> Bool {
        guard let draft else { return false }
        guard !draft.isCorrupted else {
            lastError = "草稿处于只读隔离状态（内容解不开），**已拒绝保存**以免覆盖原始字节。"
                + "请先「另存为新草稿」。"
            return false
        }
        do {
            draft.catalogJSON = try ShopCatalogJSONCoding.encoder(prettyPrinted: true)
                .encode(catalog)
            draft.updatedAt = Date()
            draft.savedRevision = draft.currentRevision
            try context.save()
            statusMessage = "已保存草稿（第 \(draft.currentRevision) 版：\(catalog.shops.count) 店家 / "
                + "\(catalog.series.count) 系列 / \(catalog.products.count) 商品）"
            lastError = nil
            return true
        } catch {
            lastError = "保存失败（编辑内容仍保留在界面上，没有写盘）：\(error.localizedDescription)"
            return false
        }
    }

    /// 运营改草稿标题（走统一入口，才能带上版本与失败反馈）
    @discardableResult
    func renameDraft(title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let draft, !trimmed.isEmpty else {
            lastError = "草稿标题不能为空。"
            return false
        }
        guard !draft.isCorrupted else {
            lastError = "草稿处于只读隔离状态，不能改名。请先「另存为新草稿」。"
            return false
        }
        guard trimmed != draft.title else { return true }
        draft.title = trimmed
        markDirty()
        return saveDraft()
    }

    // MARK: 与基线的差分 / 严格策略的作用域（方案 R07 / R08）

    /// 上次确认发布出去的那一版目录快照。nil = 从未确认发布过。
    var baselineCatalog: ShopCatalog? { draft?.baselineCatalog }

    /// 线上基线（只由受控发布器回填 / 运营显式采用）
    var baseline: ShopCatalogBaseline { draft?.baseline ?? ShopCatalogBaseline() }

    /// 相对基线快照的差分。
    ///
    /// `hasBaseline == false` 时界面**必须**显示「无法比较」——
    /// 把它显示成「没有改动」会让运营以为发一份空改动是安全的。
    var changeSet: ShopCatalogChangeSet {
        ShopCatalogChangeSetCalculator.diff(baseline: baselineCatalog, current: catalog)
    }

    /// 严格发布策略（R08）的作用域：**本次新增 / 修改过的实体 id**。
    ///
    /// 没有基线快照（从未发布过）时 = 整份目录。理由：那些内容本来就要作为
    /// 首次发布发出去，它们**全是新的**，用严格口径没问题；
    /// 反过来，如果这时作用域算成空集，严格策略就变成了一个永远不生效的开关。
    var strictScopeIDs: Set<String> {
        guard let baseline = baselineCatalog else {
            var ids: Set<String> = []
            ids.formUnion(catalog.shops.map(\.id))
            ids.formUnion(catalog.series.map(\.id))
            ids.formUnion(catalog.products.map(\.id))
            ids.formUnion(catalog.variants.map(\.id))
            ids.formUnion(catalog.sizeCharts.map(\.id))
            ids.formUnion(catalog.saleEvents.map(\.id))
            ids.formUnion(catalog.assets.map(\.id))
            ids.formUnion(catalog.styleProfiles.map(\.id))
            return ids
        }
        return ShopCatalogChangeSetCalculator.diff(baseline: baseline, current: catalog)
            .strictScopeIDs
    }

    /// 显式把「线上当前版本」采用为这份草稿的基线。
    ///
    /// 这是**运营的选择**，不是自动行为：自动回填等于替运营声明
    /// 「我的草稿一定基于最新线上」，而那正是 R07 要防的假话。
    /// 采用之后，基线里的旧内容快照会被清掉（我们手上没有线上那份内容），
    /// 所以严格策略的作用域会暂时按「整份目录」算 —— 这一点在界面上要说出来。
    func adoptBaseline(_ head: ShopCatalogOnlineHead) {
        guard let draft else { return }
        draft.baseline = ShopCatalogBaseline(
            releaseSeq: head.releaseSeq,
            rootIndexHash: head.rootIndexHash,
            environment: head.environment,
            observedAt: head.observedAt)
        try? context.save()
        statusMessage = "已把线上 releaseSeq \(head.releaseSeq) 采用为这份草稿的基线（未改动任何内容）。"
    }

    /// 记一次**已回读确认**的发布（由发布中心在拿到回执后调用）。
    @discardableResult
    func recordConfirmedPublish(
        releaseSeq: Int,
        rootIndexHash: String?,
        environment: String,
        revision: Int
    ) -> Bool {
        guard let draft, !draft.isCorrupted else { return false }
        draft.recordConfirmedPublish(
            releaseSeq: releaseSeq,
            rootIndexHash: rootIndexHash,
            revision: revision,
            catalog: catalog,
            environment: environment)
        // ⚠️ 顺序要紧：先把内存里的工作副本收敛到「存储精度」，再落盘。
        // 不收敛的话，刚发布完的那段时间里 `changeSet` 会把**每一个带日期的
        // 实体**都报成「已修改」（原因见下面那个方法的注释）。
        normalizeWorkingCopyToStoragePrecision()
        do {
            try context.save()
            return true
        } catch {
            lastError = "记录发布结果失败（发布本身已完成，但本机没记下来）：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: 用「从线上拉回」的内容替换草稿（方案 §5 的「当前线上完整基线」）

    /// 用「从线上拉回」的一份目录**替换当前草稿的全部内容**，
    /// 并**把这一版直接记为基线快照**。
    ///
    /// ## 与 `importCatalog(from:)` 的唯一差别 —— 但很关键
    ///
    /// 内容替换那段**复用**导入路径（`canMutate` 门禁 / 解码 / `markDirty` / 落盘
    /// 都已经在那里做对了，不另写一份）。这里多做的只有一件事：**写基线快照**。
    ///
    /// 拉回来的内容就是线上那一份，所以它天然是「与线上比对过了的参照物」。
    /// 不写快照的话，下一次发布的差分会把**整份目录**都算成「本次新增 / 修改」，
    /// 于是严格策略的作用域被放大到全部存量内容 —— 那正是 R08 要避免的
    /// （「顺手改一句文案，却被隔壁一个用了裸文件名的老商品卡住」）。
    ///
    /// ## 语义是**替换**，不是合并
    ///
    /// 未发布的本地改动会丢掉。所以调用方必须先把
    /// `OpsPulledCatalogAdoption.caveats(...)` 的每一条给运营看过并拿到明确确认 ——
    /// 「替换」这个动作不该由一次点击悄悄完成。
    @discardableResult
    func adoptPulledCatalogContent(from url: URL, baseline: ShopCatalogBaseline) -> Bool {
        // 内容替换（含 canMutate 守卫 → 损坏草稿会被拒）
        guard importCatalog(from: url) else { return false }
        guard let draft else { return true }

        // 基线快照 = 刚拉回的这份内容；基线本身按环境记录（跨环境比对必然误判）
        draft.baselineCatalog = catalog
        draft.baseline = baseline
        // ⚠️ 顺序要紧：先把内存工作副本收敛到存储精度，再落盘。
        // 不收敛的话，紧接其后的差分会把每个带日期的实体都报成「已修改」，
        // 而严格策略的作用域是从差分推出来的 —— 作用域被静默放大。
        normalizeWorkingCopyToStoragePrecision()
        do {
            try context.save()
            let seq = baseline.releaseSeq.map(String.init) ?? "未知"
            statusMessage = "已用线上拉回的内容替换当前草稿，基线记为 releaseSeq \(seq)"
                + (baseline.environment.map { "（\($0)）" } ?? "")
                + "。这次的改动集已归零，之后的编辑才算「本次新增 / 修改」。"
            lastError = nil
            return true
        } catch {
            lastError = "内容已替换，但基线没写进库：\(error.localizedDescription)"
                + "请重新拉一次，否则这次的修改会被当成整份目录的改动。"
            return false
        }
    }

    /// 把内存里的工作副本过一次编解码，让它与**基线快照同精度**。
    ///
    /// ## 为什么必须做（2026-09-27 用快照实测到）
    ///
    /// 基线快照是**编码后**的产物（`baselineCatalogJSON`，日期走 `.iso8601`，
    /// 精度到**秒**）；而内存里的 `catalog` 拿的是原始 `Date`（`Date()` 带小数秒，
    /// 例如 `…:30.437`）。两者直接按 `Equatable` 比，会让**每一个带日期的实体**
    /// 都不相等：
    ///
    ///   · 归档时写过 `archivedAt` 的商品；
    ///   · 记过销售记录的商品（`recordedAt` / `startAt`）；
    ///   · 声明过预约档期的系列（`reservationStartAt` / `reservationEndAt`）；
    ///   · 修过价格的商品（`correctedAt`）。
    ///
    /// 后果不是「多几个标签」那么轻：**严格策略的作用域是从这个差分推出来的**
    /// （R08），于是它会把这些根本没动过的实体也收进去 —— 表现为
    /// 「顺手改一句文案，却被隔壁一个用了裸文件名的老商品卡住」，
    /// 而界面上看起来一切正常（只多几个「已修改」标签，谁也不会去数）。
    ///
    /// 过一次编解码 = 与「重启后重新读盘」完全一致的状态（磁盘上那份本来就是
    /// 截断过的），所以没有语义丢失，只是把内存追平到实际存储精度。
    private func normalizeWorkingCopyToStoragePrecision() {
        guard let data = try? ShopCatalogJSONCoding.encoder().encode(catalog),
              let normalized = try? ShopCatalogJSONCoding.decoder()
                  .decode(ShopCatalog.self, from: data) else { return }
        catalog = normalized
    }

    // MARK: 编辑入口（全部只改内存副本，保存由运营显式触发）
    //
    // 所有编辑命令的契约（方案 R05）：
    //   · 返回 Bool —— **成功才算成功**，界面据此决定要不要关掉编辑器；
    //   · 失败只写 `lastError`，不关编辑器、不报告成功；
    //   · 只读隔离态一律拒绝。

    /// 写入门禁：只读隔离态一律拒绝。
    ///
    /// 非 private：商品级编辑命令在 `OpsWorkspace+Editing.swift` 里，
    /// 它们必须走**同一条**门禁（否则新加的编辑入口会绕过 R03 的隔离）。
    func canMutate() -> Bool {
        guard let draft else {
            lastError = "还没有草稿。"
            return false
        }
        guard !draft.isCorrupted else {
            lastError = "草稿处于只读隔离状态（内容解不开），不能编辑。请先「另存为新草稿」。"
            return false
        }
        return true
    }

    @discardableResult
    func addShop(name: String) -> Bool {
        guard canMutate() else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "店家名不能为空。"
            return false
        }
        catalog.shops.append(CatalogShop(id: "shop-\(shortID())", name: trimmed))
        markDirty()
        return true
    }

    @discardableResult
    func addSeries(shopID: String, name: String, year: Int?, month: Int?, season: String?) -> Bool {
        guard canMutate() else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "系列名不能为空。"
            return false
        }
        guard let shop = catalog.shops.first(where: { $0.id == shopID }) else {
            lastError = "请先选择一个店家。"
            return false
        }
        let trimmedSeason = season?.trimmingCharacters(in: .whitespacesAndNewlines)
        var series = CatalogSeries(
            id: "series-\(shortID())", shopID: shop.id, name: trimmed)
        series.year = year
        series.month = month
        series.season = (trimmedSeason?.isEmpty ?? true) ? nil : trimmedSeason
        catalog.series.append(series)
        markDirty()
        return true
    }

    @discardableResult
    func addProduct(shopID: String, seriesID: String, name: String, category: String) -> Bool {
        guard canMutate() else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "商品名不能为空。"
            return false
        }
        // 归属必须是一条链：商品 → 系列 → 店家。悬空结构发布端会拦，
        // 但那时运营已经填完一整页了，所以在命令层就拒。
        guard let series = catalog.series.first(where: { $0.id == seriesID }),
              series.shopID == shopID else {
            lastError = "所选系列不属于所选店家，请重新选择（商品必须挂在「店家 → 系列」下）。"
            return false
        }
        catalog.products.append(CatalogProduct(
            id: "product-\(shortID())",
            shopID: shopID,
            seriesID: seriesID,
            name: trimmed,
            category: category.trimmingCharacters(in: .whitespacesAndNewlines)))
        markDirty()
        return true
    }

    /// 商品图绑定：**传入的顺序就是商品自己的图片顺序**（R04）。
    /// 只接受已经在 staging 里的图片资源 id。
    @discardableResult
    func bindImages(_ assetIDs: [String], toProduct productID: String) -> Bool {
        guard canMutate() else { return false }
        guard let index = catalog.products.firstIndex(where: { $0.id == productID }) else {
            lastError = "找不到商品 \(productID)。"
            return false
        }
        var seen: Set<String> = []
        catalog.products[index].images = assetIDs.filter { seen.insert($0).inserted }
        markDirty()
        return true
    }

    @discardableResult
    func removeProduct(id: String) -> Bool {
        guard canMutate() else { return false }
        guard catalog.products.contains(where: { $0.id == id }) else { return false }
        catalog.products.removeAll { $0.id == id }
        catalog.variants.removeAll { $0.productID == id }
        catalog.sizeCharts.removeAll { $0.productID == id }
        catalog.saleEvents.removeAll { $0.productID == id }
        // 与 iOS 端口径一致：删除靠「墓碑」表达，发布端才知道这是「下架」而不是「漏传」
        if !catalog.removedProductIDs.contains(id) { catalog.removedProductIDs.append(id) }
        markDirty()
        statusMessage = "已删除商品（已记入删除墓碑，发布端会把它当作下架；未保存）"
        return true
    }

    // MARK: 编辑（改名 / 改归属）

    @discardableResult
    func updateShop(id: String, name: String, aliases: [String]) -> Bool {
        guard canMutate() else { return false }
        guard let index = catalog.shops.firstIndex(where: { $0.id == id }) else {
            lastError = "找不到店家 \(id)。"
            return false
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "店家名不能为空。"
            return false
        }
        catalog.shops[index].name = trimmed
        catalog.shops[index].aliases = aliases
        markDirty()
        return true
    }

    @discardableResult
    func updateSeries(
        id: String, shopID: String, name: String, year: Int?, month: Int?, season: String?
    ) -> Bool {
        guard canMutate() else { return false }
        guard let index = catalog.series.firstIndex(where: { $0.id == id }) else {
            lastError = "找不到系列 \(id)。"
            return false
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "系列名不能为空。"
            return false
        }
        guard catalog.shops.contains(where: { $0.id == shopID }) else {
            lastError = "找不到目标店家。"
            return false
        }
        // 改店家 = 把整个系列连同它的商品一起搬家。商品没有「店家」字段可改，
        // 只有 seriesID，所以系列一换店家，子商品就会指向「别的店家的系列」。
        // 不做静默级联：要么先迁走/删掉子商品，要么明确拒绝。
        let childCount = catalog.products.filter { $0.seriesID == id }.count
        if catalog.series[index].shopID != shopID, childCount > 0 {
            lastError = "这个系列下面还有 \(childCount) 个商品，直接改店家会让它们归属悬空；"
                + "请先迁移或删除这些商品，再改系列归属。"
            return false
        }
        let trimmedSeason = season?.trimmingCharacters(in: .whitespacesAndNewlines)
        catalog.series[index].shopID = shopID
        catalog.series[index].name = trimmed
        catalog.series[index].year = year
        catalog.series[index].month = month
        catalog.series[index].season = (trimmedSeason?.isEmpty ?? true) ? nil : trimmedSeason
        markDirty()
        return true
    }

    @discardableResult
    func updateProduct(
        id: String, shopID: String, seriesID: String, name: String, category: String
    ) -> Bool {
        guard canMutate() else { return false }
        guard let index = catalog.products.firstIndex(where: { $0.id == id }) else {
            lastError = "找不到商品 \(id)。"
            return false
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "商品名不能为空。"
            return false
        }
        guard let series = catalog.series.first(where: { $0.id == seriesID }),
              series.shopID == shopID else {
            lastError = "所选系列不属于所选店家，请重新选择。"
            return false
        }
        if let reason = renameGuard(productID: id, newName: trimmed, newCategory: category) {
            lastError = reason
            return false
        }
        catalog.products[index].shopID = shopID
        catalog.products[index].seriesID = seriesID
        catalog.products[index].name = trimmed
        catalog.products[index].category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        markDirty()
        return true
    }

    /// 改名守卫（仓库红线「商品改名 = 款式级」）。
    ///
    /// 改名不是「改一个字段」：它要把整款（含已归档）一起改、要改款式档案的**键**、
    /// 要让尺码表的尺码范围跟着走、还要保证颜色词不丢。这套口径在 iOS 端只有
    /// 一处实现（`ShopCatalogProductRename`）。
    ///
    /// Mac 端**不复制**它 —— 复制出来就是第二套口径，两边迟早分叉，而分叉的
    /// 表现是「改名之后同款被拆成两款」。所以这里只允许改**从未发布过**的商品名
    /// （那些内容还没有线上副本，改了不会造成两边不一致），已发布过的拒绝并说明去哪里改。
    private func renameGuard(productID: String, newName: String, newCategory: String) -> String? {
        guard let product = catalog.products.first(where: { $0.id == productID }) else { return nil }
        let category = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameChanged = newName != product.name
        let categoryChanged = category != product.category
        guard nameChanged || categoryChanged else { return nil }
        // 从未确认发布过：整份草稿都还没有线上副本，改名不会与线上分叉
        guard draft?.hasEverPublished == true else { return nil }
        // 已在基线快照里存在 = 线上有它 → 改名要走款式级口径
        guard let baseline = baselineCatalog,
              baseline.products.contains(where: { $0.id == productID }) else { return nil }
        return "「\(product.name)」已经上线过，改名/改品类会牵动整款（同款颜色子项、款式档案、尺码表范围）。"
            + "这套规则在 iOS 端只有一处实现，Mac 端本版不复制它（避免出现第二套口径）。"
            + "本版 Mac 端支持的是：新录入内容的编辑、规格、尺码表、价格与归档。"
    }

    // MARK: 删除店家 / 系列（有下级引用时**拒绝**，不做静默级联）

    /// 删除店家。有系列或商品还挂在它下面时**拒绝**并说明原因。
    ///
    /// 为什么不做级联删除：级联会一次改掉一大片实体，运营点一下「删店家」
    /// 却丢掉 20 个商品，是「部分成功/静默扩大影响」的典型。这里要求运营
    /// 自己先把下级挪走或删掉，每一步都看得见。
    @discardableResult
    func removeShop(id: String) -> Bool {
        guard canMutate() else { return false }
        let seriesCount = catalog.series.filter { $0.shopID == id }.count
        let productCount = catalog.products.filter { $0.shopID == id }.count
        guard seriesCount == 0, productCount == 0 else {
            lastError = "这个店家下面还有 \(seriesCount) 个系列、\(productCount) 个商品，"
                + "先挪走或删除它们再删店家（不做级联删除）。"
            return false
        }
        catalog.shops.removeAll { $0.id == id }
        if !catalog.removedShopIDs.contains(id) { catalog.removedShopIDs.append(id) }
        markDirty()
        statusMessage = "已删除店家（已记入删除墓碑；未保存）"
        return true
    }

    @discardableResult
    func removeSeries(id: String) -> Bool {
        guard canMutate() else { return false }
        let productCount = catalog.products.filter { $0.seriesID == id }.count
        guard productCount == 0 else {
            lastError = "这个系列下面还有 \(productCount) 个商品，先挪走或删除它们再删系列。"
            return false
        }
        catalog.series.removeAll { $0.id == id }
        if !catalog.removedSeriesIDs.contains(id) { catalog.removedSeriesIDs.append(id) }
        markDirty()
        statusMessage = "已删除系列（已记入删除墓碑；未保存）"
        return true
    }

    // MARK: 查询辅助（视图层不做口径判断）

    func shopName(for id: String) -> String {
        catalog.shops.first { $0.id == id }?.name ?? "（店家已删除）"
    }

    func seriesName(for id: String) -> String {
        catalog.series.first { $0.id == id }?.name ?? "（系列已删除）"
    }

    func asset(for id: String) -> CatalogAsset? {
        catalog.assets.first { $0.id == id }
    }

    /// 把 `local:<文件名>` 解析成 staging 目录里的真实文件 URL。
    ///
    /// 只认 `local:` 前缀：`thmedia:` / `http(s)://` / `bundle:` 都不是本机文件，
    /// 一律返回 nil（界面据此显示「非本机图」而不是空白）。
    func stagedFileURL(forReference reference: String?) -> URL? {
        guard let reference, reference.hasPrefix("local:") else { return nil }
        let name = String(reference.dropFirst("local:".count))
        guard !name.isEmpty else { return nil }
        let url = stagingDirectory.appendingPathComponent(name)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// 商品的图片引用 → 本机可显示的 URL（顺序与 `product.images` 一致，解不出的跳过）
    func stagedImageURLs(forProduct productID: String) -> [URL] {
        guard let product = catalog.products.first(where: { $0.id == productID }) else { return [] }
        return product.images.compactMap { assetID in
            guard let asset = asset(for: assetID) else { return nil }
            return stagedFileURL(forReference: asset.originalURL)
                ?? stagedFileURL(forReference: asset.previewURL)
                ?? stagedFileURL(forReference: asset.thumbnailURL)
        }
    }

    /// 任何一次内容变更的唯一入口（R01）：
    /// 递增版本、**让上一次校验失效**、把「未保存」这件事说出来。
    ///
    /// 非 private：`OpsWorkspace+Editing.swift` 里的商品级命令也必须走这一条，
    /// 漏走一处就会出现「改了但校验结果没作废」—— 也就是拿着旧 review 去导出。
    func markDirty() {
        guard let draft else { return }
        draft.draftRevision = draft.currentRevision + 1
        // 关键：不是只改一句文案。旧实现里校验结果会一直留在界面上，
        // 于是「改完再点导出」用的还是改之前那份 review。
        review = nil
        draft.reviewedRevision = nil
        statusMessage = "已修改（第 \(draft.currentRevision) 版，未保存）。"
            + "上一次校验结果已作废，导出前必须重新校验。"
    }

    func shortID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    // MARK: 导入目录 JSON

    /// 导入一份 `shop-catalog.json`（覆盖当前草稿内容）。
    /// 返回 false 表示失败，原因在 `lastError` 里。
    @discardableResult
    func importCatalog(from url: URL) -> Bool {
        // 只读隔离态下导入 = 覆盖损坏记录 → 拒绝（R03 的「默认保存/导图/导出均不可覆盖」）
        guard canMutate() else { return false }

        // security-scoped：作用域用完必须还回去，否则系统会一直替我们持有权限
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: data)
            catalog = decoded
            // 导入是一次内容变更，同样要过版本与校验失效
            markDirty()
            let saved = saveDraft()
            var parts = ["已导入 \(url.lastPathComponent)："
                + "\(decoded.shops.count) 店家 / \(decoded.series.count) 系列 / "
                + "\(decoded.products.count) 商品 / \(decoded.assets.count) 图片资源"]
            if !saved { parts.append("但草稿落盘失败") }
            statusMessage = parts.joined(separator: "，")
            if saved { lastError = nil }
            return saved
        } catch {
            lastError = "导入失败（目录 JSON 解不开，已保留当前草稿）：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: 导入图片

    /// 导入图片：**规范化 → 内容寻址 → 立即复制进 staging**。
    ///
    /// 规范化在这里发生（而不是等发布端），因为：
    ///   · `mediaKey` 要进草稿 JSON，越早定下来越好；
    ///   · 长边 1600 的重编码很吃内存，一次导入一张比发布时批量处理更可控。
    ///
    /// 每张图同时创建一个 `CatalogAsset` 与一条上传任务；两者都用 `mediaKey` 做键，
    /// 重复导入同一张图（哪怕文件名不同）只会得到一条记录。
    func importImages(from urls: [URL]) {
        guard canMutate() else { return }

        var imported = 0
        var skipped: [String] = []
        var failures: [String] = []

        try? fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let displayName = url.lastPathComponent
            do {
                let raw = try Data(contentsOf: url)
                // 规范化在这里做（不是发布时批量做）：mediaKey 要进草稿 JSON，
                // 越早定下来越好；长边 1600 的重编码很吃内存，逐张处理更可控。
                //
                // 「同一张图重复导入」不需要额外判重：规范化是确定性的
                // （同字节 → 同字节），因此 fileName 相同 → 下面 fileExists 直接复用。
                let staged = try ShopCatalogMediaStaging.stage(raw)

                let target = stagingDirectory.appendingPathComponent(staged.fileName)
                if fileManager.fileExists(atPath: target.path) {
                    skipped.append(displayName)
                } else {
                    try staged.data.write(to: target, options: .atomic)
                    imported += 1
                }

                upsertAssetAndJob(for: staged, sourceName: displayName)
            } catch let error as ShopCatalogMediaStagingError {
                failures.append("\(displayName)：\(error.errorDescription ?? "无法处理")")
            } catch {
                failures.append("\(displayName)：\(error.localizedDescription)")
            }
        }

        // R02：先把草稿落盘结果拿到手，再拼文案。
        // 旧实的顺序是「saveDraft() → 用图片失败信息重写 lastError」，
        // 于是「导图成功、保存失败」时保存错误会被清掉。
        let catalogSaved = saveDraft()

        var parts = ["新增 \(imported) 张"]
        if !skipped.isEmpty { parts.append("\(skipped.count) 张内容重复已复用") }
        if !catalogSaved { parts.append("草稿落盘失败") }
        statusMessage = parts.joined(separator: "，")

        if catalogSaved {
            lastError = failures.isEmpty ? nil : failures.joined(separator: "\n")
        } else {
            // 保存失败优先，绝不静默；图片处理失败也一并保留
            let saveError = lastError ?? "草稿保存失败。"
            lastError = ([saveError] + failures).joined(separator: "\n")
        }
    }

    private func upsertAssetAndJob(
        for staged: ShopCatalogMediaStaging.StagedMedia, sourceName: String
    ) {
        // 1) 图片资源：mediaKey 存在 → 同一个媒体，只补 URL 字段
        let assetID = "asset-\(String(staged.mediaKey.prefix(12)))"
        if let index = catalog.assets.firstIndex(where: { $0.id == assetID }) {
            catalog.assets[index].thumbnailURL = "local:\(staged.fileName)"
            catalog.assets[index].previewURL = "local:\(staged.fileName)"
            catalog.assets[index].originalURL = "local:\(staged.fileName)"
            catalog.assets[index].width = staged.pixelWidth
            catalog.assets[index].height = staged.pixelHeight
            catalog.assets[index].mediaKey = staged.mediaKey
        } else {
            catalog.assets.append(CatalogAsset(
                id: assetID,
                type: .productImage,
                thumbnailURL: "local:\(staged.fileName)",
                previewURL: "local:\(staged.fileName)",
                originalURL: "local:\(staged.fileName)",
                width: staged.pixelWidth,
                height: staged.pixelHeight,
                mediaKey: staged.mediaKey))
        }

        // 2) 上传任务：同 mediaKey 只留一条
        var job = mediaJobs.first { $0.mediaKey == staged.mediaKey }
            ?? MediaUploadJob(
                mediaKey: staged.mediaKey,
                stagedFileName: staged.fileName,
                byteCount: staged.byteCount,
                mimeType: staged.mimeType)
        job.stagedFileName = staged.fileName
        job.byteCount = staged.byteCount
        job.mimeType = staged.mimeType
        persist(job)

        _ = sourceName    // 原始文件名只用于报错文案，不参与身份判定（身份 = 内容摘要）
    }

    // MARK: 上传任务落盘

    private func loadMediaJobs() {
        guard let draftID = draft?.id else { mediaJobs = []; return }
        let target = draftID
        let descriptor = FetchDescriptor<OpsMediaJobRecord>(
            predicate: #Predicate { $0.draftID == target },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        let records = (try? context.fetch(descriptor)) ?? []
        // 启动恢复：上次进程被杀留下的 `uploading` 一律回退成 `retryable`。
        // 保持 uploading 的话，新进程里它既不会前进也不会后退，界面永远卡在「上传中」。
        mediaJobs = records.map { record in
            let restored = MediaUploadJobMachine.recovered(record.job)
            if restored.state != record.job.state { record.apply(restored) }
            return restored
        }
        try? context.save()
    }

    /// 写回一条任务（存在则更新，不存在则插入）
    func persist(_ job: MediaUploadJob) {
        if let index = mediaJobs.firstIndex(where: { $0.mediaKey == job.mediaKey }) {
            mediaJobs[index] = job
        } else {
            mediaJobs.append(job)
        }
        guard let draftID = draft?.id else { return }
        let key = job.mediaKey
        let descriptor = FetchDescriptor<OpsMediaJobRecord>(
            predicate: #Predicate { $0.mediaKey == key && $0.draftID == draftID })
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.apply(job)
        } else {
            context.insert(OpsMediaJobRecord(
                mediaKey: job.mediaKey,
                draftID: draftID,
                stagedFileName: job.stagedFileName,
                byteCount: job.byteCount,
                mimeType: job.mimeType,
                stateRawValue: job.state.rawValue,
                attemptCount: job.attemptCount,
                failureKindRawValue: job.failureKind?.rawValue,
                lastErrorMessage: job.lastErrorMessage,
                createdAt: job.createdAt,
                updatedAt: job.updatedAt,
                verifiedAt: job.verifiedAt))
        }
        try? context.save()
    }

    var mediaProgress: MediaUploadJobMachine.Progress {
        MediaUploadJobMachine.progress(of: mediaJobs)
    }

    /// 台账里记着、但 staging 目录里已经没有文件的图片。
    ///
    /// 这三者（目录文件 / 台账 / 目录 JSON 引用）是三个独立事实，**必须能分别看见**：
    ///   · 台账有、文件没有 → 别人手删过 staging，或者换过机器；
    ///   · 文件有、台账没有 → 直接往 staging 目录里丢了图（没走导入流程）；
    ///   · 目录 JSON 引用了不存在的文件 → 发布门禁会拦（`missingLocal`）。
    /// 本方法只负责第 1 种；第 2 种由 `rescanStagingDirectory()` 补台账；
    /// 第 3 种交给 `ShopCatalogPublicationGate`。
    var mediaKeysMissingStagedFile: [String] {
        let names = stagedFileNames
        return mediaJobs
            .filter { !names.contains($0.stagedFileName) }
            .map(\.mediaKey)
            .sorted()
    }

    /// 台账里没有、但 staging 目录里存在的文件名（孤儿素材）。
    var orphanStagedFileNames: [String] {
        let known = Set(mediaJobs.map(\.stagedFileName))
        return stagedFileNames.filter { !known.contains($0) }.sorted()
    }

    /// 重新扫 staging 目录，给「目录里有文件但台账没记」的图片补一条任务。
    ///
    /// 为什么要有：`.fileImporter` 不是唯一的素材来源 —— 运营会把图直接拷进
    /// staging 目录（尤其是「重新拿一份上次的素材」）。没有这一步，那些图
    /// 在界面上就是隐形的，而发布端**照样会上传它们**（它按文件名找文件，
    /// 不看台账）——「界面上没有、线上有图」是最难解释的一类不一致。
    ///
    /// 媒体键取自**文件名主干**：staging 的文件名由
    /// `ShopCatalogMediaStaging.StagedMedia.fileName` 固定生成为 `<mediaKey>.<ext>`，
    /// 所以主干就是媒体键。这里额外用 `isPayloadHash` 校验形态，
    /// 形态不对的（例如运营手放了一个 `备注.txt`）直接跳过，不伪造台账。
    @discardableResult
    func rescanStagingDirectory() -> Int {
        try? fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        var added: [String] = []
        for name in stagedFileNames.sorted() {
            let stem = (name as NSString).deletingPathExtension
            guard ShopCatalogSyncProtocol.isPayloadHash(stem) else { continue }
            if mediaJobs.contains(where: { $0.stagedFileName == name }) { continue }
            let url = stagingDirectory.appendingPathComponent(name)
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let byteCount = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            persist(MediaUploadJob(
                mediaKey: stem,
                stagedFileName: name,
                byteCount: byteCount,
                mimeType: mimeType(forFileName: name)))
            added.append(name)
        }
        if added.isEmpty {
            statusMessage = "素材清单已是最新（台账 \(mediaJobs.count) 条）"
        } else {
            statusMessage = "已补记 \(added.count) 张原本只在目录里的图片"
        }
        return added.count
    }

    /// 删掉一条台账记录。**不动文件**，也不动目录 JSON 里的引用 ——
    /// 引用与文件该不该在，由发布门禁判定；删台账只是「不再跟踪这条」。
    func removeMediaJob(mediaKey: String) {
        mediaJobs.removeAll { $0.mediaKey == mediaKey }
        let key = mediaKey
        guard let draftID = draft?.id else { return }
        let descriptor = FetchDescriptor<OpsMediaJobRecord>(
            predicate: #Predicate { $0.mediaKey == key && $0.draftID == draftID })
        for record in (try? context.fetch(descriptor)) ?? [] {
            context.delete(record)
        }
        try? context.save()
        statusMessage = "已移除 1 条上传任务记录（文件与目录引用都没动）"
    }

    private func mimeType(forFileName name: String) -> String {
        let ext = (name as NSString).pathExtension
        if let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime.lowercased()
        }
        return "application/octet-stream"
    }

    // MARK: 发布前校验（离线）

    /// 跑一遍发布门禁。这是 P1 的核心交付：**离线就能知道这份目录发出去会不会缺图**。
    ///
    /// 校验结果会与**当时的编辑版本**绑定（R01）：任何后续编辑都会作废它。
    ///
    /// - Parameters:
    ///   - strict: 引用校验策略（R08）。默认 `.compatibility`，与改动前逐字一致。
    ///   - strictScope: 严格策略的作用域（本次新增 / 修改过的实体 id）。
    ///     调用方通常直接传 `strictScopeIDs`；不传 = 严格策略没有作用对象。
    ///   - verifiedRemoteMediaKeys: 已在目标环境回读确认过的媒体键。
    ///     本机离线**判不出来**，所以默认空集，严格策略只会把它们列成告警。
    ///   - targetEnvironmentName: 严格策略文案里的目标环境名。
    @discardableResult
    func validate(
        strict: ShopCatalogStrictPolicy = .compatibility,
        strictScope: Set<String> = [],
        verifiedRemoteMediaKeys: Set<String> = [],
        targetEnvironmentName: String = ""
    ) -> ShopCatalogPublicationReview {
        let result = review(
            strict: strict,
            strictScope: strictScope,
            verifiedRemoteMediaKeys: verifiedRemoteMediaKeys,
            targetEnvironmentName: targetEnvironmentName)
        review = result
        // 绑定版本：以后拿 review 之前先看 `isReviewStale`
        draft?.reviewedRevision = draft?.currentRevision
        try? context.save()
        if result.isBlocked {
            lastError = result.blockingIssues.joined(separator: "\n")
        } else {
            lastError = nil
        }
        statusMessage = result.summary + "（对应第 \(currentRevision) 版）"
        return result
    }

    /// 按当前参数跑一遍门禁，**不写状态、不污染 review**。
    /// 导出入口与发布中心都用它做「服务侧复校验」。
    func review(
        strict: ShopCatalogStrictPolicy = .compatibility,
        strictScope: Set<String> = [],
        verifiedRemoteMediaKeys: Set<String> = [],
        targetEnvironmentName: String = ""
    ) -> ShopCatalogPublicationReview {
        ShopCatalogPublicationGate.review(
            catalog,
            stagedFileNames: stagedFileNames,
            coverageStatus: draft?.coverageStatus ?? "complete",
            strict: strict,
            strictScope: strictScope,
            verifiedRemoteMediaKeys: verifiedRemoteMediaKeys,
            targetEnvironmentName: targetEnvironmentName)
    }

    /// 校验当前快照，返回是否阻断 —— 供「服务入口复校验」用。
    func isCurrentSnapshotBlocked(
        strict: ShopCatalogStrictPolicy = .compatibility,
        strictScope: Set<String> = [],
        verifiedRemoteMediaKeys: Set<String> = [],
        targetEnvironmentName: String = ""
    ) -> (blocked: Bool, issues: [String]) {
        let result = review(
            strict: strict,
            strictScope: strictScope,
            verifiedRemoteMediaKeys: verifiedRemoteMediaKeys,
            targetEnvironmentName: targetEnvironmentName)
        return (result.isBlocked, result.catalogIssues + result.blockingIssues)
    }

    // MARK: 导出待发布包

    /// 生成待发布 tar：`shop-catalog.json` + `images/<文件名>`。
    ///
    /// 布局与 iOS 端「整包导出」完全一致，所以发布端**同一条命令**就能吃：
    ///     python3 tools/time_hall/publication/build_release.py \
    ///         --shop-catalog-archive <这个 tar> ...
    /// 不要自创第二种布局 —— 计划 §6 P4 明确警告不要出现第二套发布格式。
    ///
    /// ⚠️ **本方法自己复校验**（R01）：即使界面上的校验按钮被绕过、
    /// 或者校验之后又改了内容，产物也不会带着未通过的快照出去。
    /// 严格策略的作用域也在这里重新算（而不是复用界面上那份），
    /// 否则「界面勾了严格 → 导出时被绕过」就成了新的洞。
    func makePublicationArchive(
        strict: ShopCatalogStrictPolicy = .compatibility,
        strictScope: Set<String>? = nil,
        verifiedRemoteMediaKeys: Set<String> = [],
        targetEnvironmentName: String = ""
    ) throws -> Data {
        guard !isCorrupted else {
            throw OpsWorkspaceError.corruptedDraft
        }
        // 服务入口复校验：不依赖界面那次 review 是否还新鲜，也不依赖按钮是否被禁用
        let fresh = isCurrentSnapshotBlocked(
            strict: strict,
            strictScope: strictScope ?? strictScopeIDs,
            verifiedRemoteMediaKeys: verifiedRemoteMediaKeys,
            targetEnvironmentName: targetEnvironmentName)
        guard !fresh.blocked else {
            throw OpsWorkspaceError.blockedByGate(fresh.issues)
        }

        let references = Set(catalog.assets.flatMap { asset in
            [asset.originalURL, asset.thumbnailURL, asset.previewURL].compactMap { $0 }
        })
        let (imageEntries, missing) = ShopCatalogExportArchive.imageEntries(
            forLocalReferences: references,
            imageDirectory: stagingDirectory)

        // 缺图一律硬报错：静默跳过会让「图没传」以「用户看到空白」的形式暴露，
        // 比构建失败难查得多（与 build_release.py 同一口径）。
        guard missing.isEmpty else {
            throw OpsWorkspaceError.missingStagedFiles(missing)
        }

        var entries = [ShopCatalogExportArchive.Entry]()
        let json = try ShopCatalogJSONCoding.encoder(prettyPrinted: true).encode(catalog)
        entries.append(.init(name: "shop-catalog.json", data: json))
        entries.append(contentsOf: imageEntries)
        return ShopCatalogExportArchive.tarData(entries: entries)
    }

    // MARK: 损坏草稿恢复（R03）

    /// 把损坏草稿**另存为一份新草稿**，原记录的原始字节原样留在库里。
    ///
    /// 为什么不是「就地修好」：解不开的内容没法在界面上编辑；就地覆盖等于毁掉
    /// 证据。运营真正需要的是「能继续干活」，同时原始字节还在。
    @discardableResult
    func recoverCorruptedDraftToNewDraft() -> OpsCatalogDraftRecord? {
        guard let corrupt = draft, corrupt.isCorrupted else {
            lastError = "当前草稿不是「内容解不开」状态，无需恢复。"
            return nil
        }
        let backup = corrupt.corruptedBackupJSON ?? corrupt.catalogJSON
        let empty = ShopCatalog()
        let data = (try? ShopCatalogJSONCoding.encoder(prettyPrinted: true).encode(empty))
            ?? Data("{}".utf8)
        let record = OpsCatalogDraftRecord(title: corrupt.title + "（新副本）", catalogJSON: data)
        // 备份跟着新草稿走：运营在新草稿里也能拿到那份原始字节
        record.corruptedBackupJSON = backup
        context.insert(record)
        // 原草稿的 updatedAt 不动 → 下次启动不会又被它抢走
        try? context.save()
        review = nil
        adopt(record)
        loadMediaJobs()
        statusMessage = "已从损坏草稿另存出一份可编辑的新草稿；原草稿的原始字节与备份仍保留在库里。"
        return record
    }

    /// 把损坏草稿的原始字节写到用户选定的位置（保留证据用）
    func exportCorruptedBackup(to url: URL) -> Bool {
        guard let corrupt = draft else { return false }
        let data = corrupt.corruptedBackupJSON ?? corrupt.catalogJSON
        do {
            try data.write(to: url, options: .atomic)
            statusMessage = "已导出损坏草稿的原始字节：\(url.lastPathComponent)"
            lastError = nil
            return true
        } catch {
            lastError = "导出原始字节失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: 发布基线（R07 的留痕位；读取要等 M3 接入受控发布器）

    /// 记录这份草稿基于哪个线上版本。**只能由受控发布器回填** ——
    /// Mac 端读不到线上基线，在 M3 接入之前不要据此声称「基线已核对」。
    func recordBaseRelease(seq: Int?, rootIndexHash: String?) {
        guard let draft else { return }
        draft.baseReleaseSeq = seq
        draft.baseRootIndexHash = rootIndexHash
        try? context.save()
    }

    var baseReleaseSeq: Int? { draft?.baseReleaseSeq }
    var baseRootIndexHash: String? { draft?.baseRootIndexHash }

    func clearError() {
        lastError = nil
    }

    /// 成功类反馈入口（与 `reportFailure` 对称）。界面不许自己弹提示，
    /// 否则「有的成功看得见、有的看不见」。
    func reportSuccess(_ message: String) {
        lastError = nil
        statusMessage = message
    }

    /// 界面层的失败上报入口（唯一通道，见 `OpsRootView` 顶部说明）。
    /// 界面不许自己弹 alert 兜失败：文案一旦分散，就会出现「有的失败看得见、有的看不见」。
    func reportFailure(_ message: String) {
        lastError = message
    }

    var statusText: String? { statusMessage }
}

// MARK: - 错误

enum OpsWorkspaceError: LocalizedError {
    /// 目录引用的图片在 staging 里找不到
    case missingStagedFiles([String])
    /// 发布门禁未通过（结构问题或引用问题）
    case blockedByGate([String])
    /// 草稿内容解不开，处于只读隔离态
    case corruptedDraft

    var errorDescription: String? {
        switch self {
        case .missingStagedFiles(let names):
            return "有 \(names.count) 张被引用的图片在本机找不到，已中止生成待发布包："
                + names.prefix(5).joined(separator: "、")
                + (names.count > 5 ? " 等" : "")
        case .blockedByGate(let issues):
            return "发布前校验未通过（\(issues.count) 条）：" + issues.prefix(3).joined(separator: "；")
        case .corruptedDraft:
            return "当前草稿内容无法解析，处于只读隔离状态，不能导出。请先「另存为新草稿」。"
        }
    }
}
