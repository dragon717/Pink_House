//
//  ShopCatalogOps.swift
//  ItemManager
//
//  店家商品库运营端（Phase 6，计划 §26-31）：
//    · CatalogProductDraft  运营草稿（§27 手动录入草稿 → 人工补录）
//    · ShopCatalogDraftStore    草稿持久化 + 发布 → 覆盖层 JSON（§31 草稿/发布）
//    · 发布校验：必填项、价格、定金尾款对账、Shop/Series/Product 去重（§29）
//    · 淘宝导入（§28 ShopCatalogTaobaoParser）与批量导入已下线，代码已删除
//
//  简化说明（第一版）：审核态由白名单创作者一步完成——发布 = 校验通过后
//  写入覆盖层并对用户可见；CatalogPublicationStatus 枚举保留完整状态机。
//

import Foundation
import Combine
import SwiftData

// MARK: - 草稿流转错误（§31）

nonisolated enum ShopCatalogDraftStoreError: LocalizedError {
    case illegalTransition(from: CatalogPublicationStatus, to: CatalogPublicationStatus)
    case notReadyForPublish(CatalogPublicationStatus)

    var errorDescription: String? {
        switch self {
        case .illegalTransition(let from, let to):
            return "状态不能从「\(from.displayName)」变更为「\(to.displayName)」"
        case .notReadyForPublish(let status):
            return "草稿当前为「\(status.displayName)」，需先提交并审核通过后才能发布"
        }
    }
}

// MARK: - 价格双流程错误（2026-09-22）

/// 价格修正 / 追加销售记录两条流程各自的校验错误。
/// 分开定义而非复用 `ShopCatalogDraftValidator.ValidationError`：草稿发布校验
/// 与这两条运营流程语义不同（是否要求时间维度、是否需要去重都不一样）。
nonisolated enum ShopCatalogPriceEditError: LocalizedError {
    /// 价格非正数
    case invalidPrice
    /// 定金 + 尾款 ≠ 价格（或清了预约价却留着定金 / 尾款）
    case depositBalanceMismatch(String)
    /// 追加记录重复提交（业务指纹命中既有记录）
    case duplicateRecord
    /// 商品不存在（可能已被删除）
    case productNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidPrice:
            return "价格必须大于 0"
        case .depositBalanceMismatch(let detail):
            return "定金尾款对账失败：\(detail)"
        case .duplicateRecord:
            return "该销售记录已存在（同商品 / 同类型 / 同价格 / 同批次日），请勿重复提交"
        case .productNotFound(let id):
            return "未找到商品 \(id)，可能已被删除"
        }
    }
}

// MARK: - 运营草稿

nonisolated struct CatalogProductDraft: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    /// 所属批次（V1.1 §4.1 批量录入：一次补录任务的多条单品互不耦合）；nil = 单条录入
    var batchID: String? = nil
    /// 关联既有店家；为 nil 时用 newShopName 新建
    var shopID: String?
    var newShopName: String = ""
    var newShopAliases: String = "" // 逗号分隔
    /// 关联既有系列；为 nil 时用 newSeriesName 新建
    var seriesID: String?
    var newSeriesName: String = ""
    var newSeriesYear: Int?
    var newSeriesSeason: String = ""

    var name: String = ""
    var category: String = "其他"
    /// 款式名（2026-09-22 V1.4「同款不同色」归类）：可空 = 按商品名剥离颜色词自动派生；
    /// 同款式不同颜色的补录填同一款式名，发布后列表自动归入同一款式展示。
    /// Optional + 默认 nil，合成解码对旧 JSON 自动兜底。
    var designName: String? = nil
    /// 本次销售记录类型：reservation / stock
    /// ⚠️ 2026-09-22 起仅作旧数据兼容：预约价与现货价**并存且不互斥**，
    /// 新录入一律用 price（预约价）+ stockPrice（现货价），不再用本字段切换互斥表单。
    var saleKind: CatalogSaleEventType = .reservation
    /// 预约价（可空 = 0；现货价可与之并存，也可两者都空置后补录）
    var price: Double = 0
    /// 现货价（可空，后续补录修改；与预约价并存，互不清空/覆盖）
    var stockPrice: Double? = nil
    var deposit: Double?
    var balance: Double?
    var startAt: Date? = nil
    var endAt: Date? = nil

    /// 完整商品资料（V1.1 G5：手动录入必须能完成全部业务）
    /// 图片以 CatalogAsset 表达（originalURL 必填）；发布时一并写入覆盖层
    var images: [CatalogAsset] = []
    /// 配色尺码规格；发布时一并写入覆盖层
    var variants: [CatalogProductVariant] = []
    /// 结构化尺码表（含 sourceImage）；发布时一并写入覆盖层
    var sizeChart: CatalogSizeChart? = nil

    var status: CatalogPublicationStatus = .draft
    /// 审核驳回原因（V1.1 §4.1：驳回退回草稿并保留原因）；重新提交时清空。
    /// Optional + 默认 nil，合成解码对旧 JSON 自动兜底。
    var rejectReason: String? = nil
    var createdAt: Date = Date()

    // MARK: 预约 / 现货并存口径（2026-09-22）

    /// 预约价口径：新口径下 price 即预约价；
    /// 唯一例外是**未经新编辑器迁移的旧现货草稿**（saleKind == .stock 且未单独填
    /// stockPrice）——它的 price 历史上就是现货价，不得重复解释为预约价。
    nonisolated var effectiveReservationPrice: Double? {
        if saleKind == .stock && stockPrice == nil { return nil }
        return price > 0 ? price : nil
    }

    /// 现货价口径：新口径取 stockPrice；
    /// 旧现货草稿（同上）回退解释 price，保证存量草稿发布行为不变。
    nonisolated var effectiveStockPrice: Double? {
        if saleKind == .stock && stockPrice == nil { return price > 0 ? price : nil }
        return stockPrice.flatMap { $0 > 0 ? $0 : nil }
    }

    /// 价格摘要：预约 / 现货并存展示（谁填了显示谁，都不填给引导文案）
    nonisolated var priceSummary: String {
        var parts: [String] = []
        if let r = effectiveReservationPrice { parts.append("预约 ¥\(Int(r))") }
        if let s = effectiveStockPrice { parts.append("现货 ¥\(Int(s))") }
        return parts.isEmpty ? "待填价格" : parts.joined(separator: " · ")
    }

    /// 预约草稿的定金尾款对账（允许缺省，缺省时发布前自动补齐）
    nonisolated var depositBalanceIssue: String? {
        guard effectiveReservationPrice != nil, let d = deposit, let b = balance else { return nil }
        return (Decimal(d) + Decimal(b)) == Decimal(price)
            ? nil : "定金 \(Int(d)) + 尾款 \(Int(b)) ≠ 总价 \(Int(price))"
    }
}

// MARK: - 批次录入会话（V1.1 §4.1：一次补录任务录入多个单品、多品类混合）

/// 批次会话：归属店家/系列（可新建）+ 若干独立单品草稿。
/// 状态互不耦合：批次内可部分发布、部分停留草稿、部分驳回（§4.3）。
nonisolated struct CatalogBatchEntrySession: Codable, Identifiable, Hashable, Sendable {
    var id: String = "batch-\(UUID().uuidString.prefix(8))"
    /// 归属店家；nil = 用 newShopName 新建（整批同店）
    var shopID: String?
    var newShopName: String = ""
    var newShopAliases: String = ""
    /// 归属系列；nil = 用 newSeriesName 新建（整批同系列）
    var seriesID: String?
    var newSeriesName: String = ""
    var newSeriesYear: Int?
    var newSeriesSeason: String = ""
    var createdAt: Date = Date()
}

// MARK: - 发布校验（§29 去重 + 基础校验）

nonisolated enum ShopCatalogDraftValidator {

    nonisolated enum ValidationError: LocalizedError {
        case missingName
        case invalidPrice
        case depositBalanceMismatch(String)
        case missingShop
        case missingSeries

        var errorDescription: String? {
            switch self {
            case .missingName: return "商品名称不能为空"
            case .invalidPrice: return "价格必须大于 0"
            case .depositBalanceMismatch(let detail): return "定金尾款对账失败：\(detail)"
            case .missingShop: return "未选择或填写店家"
            case .missingSeries: return "未选择或填写系列"
            }
        }
    }

    static func validate(_ draft: CatalogProductDraft, catalog: ShopCatalog?) throws {
        guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw ValidationError.missingName }
        // 预约价与现货价并存且不互斥：至少填一项即可；现货价可空置后补录（2026-09-22）
        guard draft.effectiveReservationPrice != nil || draft.effectiveStockPrice != nil else {
            throw ValidationError.invalidPrice
        }
        if let issue = draft.depositBalanceIssue { throw ValidationError.depositBalanceMismatch(issue) }
        guard draft.shopID != nil || !draft.newShopName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError.missingShop
        }
        guard draft.seriesID != nil || !draft.newSeriesName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError.missingSeries
        }
    }

    /// 店家去重（§29）：按名称或别名匹配既有店家；命中则应复用，不再新建
    static func findExistingShop(for draft: CatalogProductDraft, catalog: ShopCatalog?) -> CatalogShop? {
        guard let catalog else { return nil }
        let name = draft.newShopName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return catalog.shops.first { $0.matches(nameOrAlias: name) }
    }

    /// 系列去重：同店家下同名（不区分大小写）系列视为同一系列
    static func findExistingSeries(for draft: CatalogProductDraft, shopID: String, catalog: ShopCatalog?) -> CatalogSeries? {
        guard let catalog else { return nil }
        let name = draft.newSeriesName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return nil }
        return catalog.series.first { $0.shopID == shopID && $0.name.lowercased() == name }
    }

    /// 商品去重 + 现货追加判定（§29/§30）：同系列同名商品已存在，
    /// 且草稿是现货记录 → 追加 SaleEvent 而不是新建商品。
    static func findExistingProduct(for draft: CatalogProductDraft, seriesID: String, catalog: ShopCatalog?) -> CatalogProduct? {
        guard let catalog else { return nil }
        let name = draft.name.trimmingCharacters(in: .whitespaces).lowercased()
        return catalog.products.first { $0.seriesID == seriesID && $0.name.lowercased() == name }
    }
}

// MARK: - 统一存储目录（测试隔离，2026-09-21 事故根源修复）

/// ShopCatalog 全部运营数据的统一根目录（草稿 / 批次 / 覆盖层 / 运营上传图片）。
///
/// 事故回顾：单元测试以主 App 为宿主运行，`FileManager.default` 指向用户真实沙盒。
/// 多个测试套件在 tearDown 里删除真实覆盖层/草稿文件，导致用户发布的系列在
/// 每轮回归测试后被清掉（表现为「发布的系列刷新后消失」）。
/// 根源修复：所有测试必须先 `useTemporaryForTesting()` 把读写重定向到独立临时
/// 目录，结束时 `restoreDefaultForTesting()` 还原并清理——测试从此无法触碰生产数据。
nonisolated enum ShopCatalogStorage {

    /// 测试注入的临时目录；nil = 生产路径（宿主 App 沙盒 Application Support/ShopCatalog）
    private nonisolated(unsafe) static var testOverride: URL?

    /// 当前生效的存储根目录（测试注入优先）
    static var directory: URL {
        if let testOverride { return testOverride }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShopCatalog", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 生产路径（永不受测试注入影响）：供回归测试断言「测试未污染生产数据」
    static var productionDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShopCatalog", isDirectory: true)
    }

    static var isTestOverridden: Bool { testOverride != nil }

    /// 测试专用：重定向到全新临时目录（每套测试独立，互不串扰）
    @discardableResult
    static func useTemporaryForTesting() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShopCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        testOverride = url
        return url
    }

    /// 测试专用：恢复生产路径并清掉临时目录
    static func restoreDefaultForTesting() {
        if let url = testOverride {
            try? FileManager.default.removeItem(at: url)
        }
        testOverride = nil
    }
}

// MARK: - 批次单品分组（2026-09-22：未指定系列默认继承整批归属）

/// 批次详情「本批单品（按系列分组）」的分组键纯逻辑（nonisolated 可单测）：
///   · 草稿**自报**了系列（关联系列 Picker 选中，或填了新系列名）→ 永远用自己的，
///     整批归属怎么变都不覆盖（用户手动修改不被覆盖）；
///   · 草稿未自报 → **继承**整批归属当前选定的系列（上方店家/系列选择联动，
///     上方一变，分组即时跟着变）；
///   · 整批也没选定系列 → 维持原有默认行为「未指定系列」。
/// 注意：这里只是**展示分组**口径；把继承值真正写进草稿数据仍走「应用到整批」按钮
/// （applyBatchAttribution），避免上方随便点一下就静默改数据。
nonisolated enum CatalogBatchGrouping {
    static let unspecified = "未指定系列"

    /// - Parameters:
    ///   - draftOwnSeriesName: 草稿自报系列的展示名（seriesID 解析成功 = 系列名，
    ///     解析失败 = 原始 id 兜底；填了新系列名 = 该名称）；nil = 草稿未自报系列
    ///   - batchSeriesName: 整批归属当前选定系列的展示名；nil = 上方未选定系列
    static func groupKey(draftOwnSeriesName: String?, batchSeriesName: String?) -> String {
        if let own = draftOwnSeriesName { return own }
        if let batch = batchSeriesName { return batch }
        return unspecified
    }
}

// MARK: - 批次删除（2026-09-22 批次列表治理）

/// 批量删除结果：成功删除的批次 + 被拦截的批次（条目保留，附原因，可处理后重试）
nonisolated struct CatalogBatchDeleteBlock: Identifiable, Hashable, Sendable {
    let batchID: String
    let reason: String
    var id: String { batchID }
}

nonisolated struct CatalogBatchDeleteResult: Sendable {
    let deletedIDs: Set<String>
    let blocked: [CatalogBatchDeleteBlock]
}

nonisolated enum ShopCatalogBatchStoreError: LocalizedError {
    /// 批次记录持久化失败：内存与磁盘都未变化，条目完整保留，可直接重试
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .persistenceFailed(let detail):
            return "批次记录写入失败：\(detail)。列表未发生任何变化，请重试。"
        }
    }
}

// MARK: - 草稿存储 + 发布（§31）

@MainActor
final class ShopCatalogDraftStore: ObservableObject {
    static let shared = ShopCatalogDraftStore()

    @Published private(set) var drafts: [CatalogProductDraft] = []
    /// 批次会话（发布式：createBatch / saveBatches / deleteBatches 统一维护，
    /// 视图请读 `batches` 而不是直接调 `loadBatches()`，否则删除后不会刷新）
    @Published private(set) var batches: [CatalogBatchEntrySession] = []

    private let fileManager = FileManager.default
    private var draftsURL: URL {
        ShopCatalogStorage.directory.appendingPathComponent("shop-catalog-drafts.json")
    }

    private var batchesURL: URL {
        ShopCatalogStorage.directory.appendingPathComponent("shop-catalog-batches.json")
    }

    /// 发布后的覆盖层：与 Bundle 种子合并后对用户可见
    nonisolated static var overlayURL: URL {
        ShopCatalogStorage.directory.appendingPathComponent("shop-catalog-override.json")
    }

    private init() {
        loadDrafts()
        batches = Self.loadBatches()
    }

    func loadDrafts() {
        guard let data = try? Data(contentsOf: draftsURL) else { drafts = []; return }
        drafts = (try? JSONDecoder().decode([CatalogProductDraft].self, from: data)) ?? []
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(drafts) {
            try? data.write(to: draftsURL, options: .atomic)
        }
    }

    func upsert(_ draft: CatalogProductDraft) {
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
        } else {
            drafts.append(draft)
        }
        persist()
    }

    func delete(_ draft: CatalogProductDraft) {
        drafts.removeAll { $0.id == draft.id }
        persist()
    }

    // MARK: 批次会话（V1.1 §4.1）

    /// 全部批次（草稿状态互不耦合，批次只是归组视图）
    nonisolated static func loadBatches() -> [CatalogBatchEntrySession] {
        guard let data = try? Data(contentsOf: batchesURLStatic) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CatalogBatchEntrySession].self, from: data)) ?? []
    }

    func saveBatches(_ batches: [CatalogBatchEntrySession]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(batches) {
            try? data.write(to: batchesURL, options: .atomic)
        }
        self.batches = batches
    }

    nonisolated private static var batchesURLStatic: URL {
        ShopCatalogStorage.directory.appendingPathComponent("shop-catalog-batches.json")
    }

    // MARK: 批次删除（2026-09-22 批次列表治理）

    /// 批次删除拦截判定：批次下仍有**未处理**单品草稿（draft / submitted / reviewed）
    /// 时禁止删除，返回面向运营的可读原因；nil = 可删。
    /// 「已处理」口径：已发布（published）或已归档（archived）的草稿不算未处理——
    /// 批次只是归组记录，发布产物在覆盖层，删除批次不影响它们。
    nonisolated static func batchDeleteBlockReason(
        batchID: String, drafts: [CatalogProductDraft]
    ) -> String? {
        let unprocessed = drafts.filter {
            $0.batchID == batchID
                && ($0.status == .draft || $0.status == .submitted || $0.status == .reviewed)
        }
        guard !unprocessed.isEmpty else { return nil }
        var parts: [String] = []
        let draftCount = unprocessed.filter { $0.status == .draft }.count
        let submittedCount = unprocessed.filter { $0.status == .submitted }.count
        let reviewedCount = unprocessed.filter { $0.status == .reviewed }.count
        if draftCount > 0 { parts.append("草稿 \(draftCount) 条") }
        if submittedCount > 0 { parts.append("待审核 \(submittedCount) 条") }
        if reviewedCount > 0 { parts.append("待发布 \(reviewedCount) 条") }
        return "批次下仍有未处理数据（\(parts.joined(separator: "、"))），请先提交 / 发布，或在草稿箱中删除这些草稿后再删除批次。"
    }

    /// 批量删除批次会话。**只删归组记录，不动任何单品草稿**：
    ///   · 草稿箱中的草稿原样保留（batchID 引用随之失效，仅失去批次归组）；
    ///   · 已发布到覆盖层的数据完全不受影响；
    ///   · 未处理草稿命中拦截的批次**整体保留**（连同原因返回），可处理后重试；
    ///   · 持久化失败时抛错，磁盘与内存均不变化，调用方提示重试即可。
    @discardableResult
    func deleteBatches(ids: Set<String>) throws -> CatalogBatchDeleteResult {
        try CreatorAccess.requireCreator(.listingEdit)
        guard !ids.isEmpty else {
            return CatalogBatchDeleteResult(deletedIDs: [], blocked: [])
        }

        var blocked: [CatalogBatchDeleteBlock] = []
        var deletable = Set<String>()
        for id in ids {
            if let reason = Self.batchDeleteBlockReason(batchID: id, drafts: drafts) {
                blocked.append(CatalogBatchDeleteBlock(batchID: id, reason: reason))
            } else {
                deletable.insert(id)
            }
        }
        guard !deletable.isEmpty else {
            return CatalogBatchDeleteResult(deletedIDs: [], blocked: blocked)
        }

        var remaining = Self.loadBatches()
        remaining.removeAll { deletable.contains($0.id) }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(remaining)
            try data.write(to: batchesURL, options: .atomic)
        } catch {
            throw ShopCatalogBatchStoreError.persistenceFailed(error.localizedDescription)
        }
        batches = remaining
        return CatalogBatchDeleteResult(deletedIDs: deletable, blocked: blocked)
    }

    /// 创建批次并把草稿写入草稿箱
    @discardableResult
    func createBatch(
        _ session: CatalogBatchEntrySession,
        drafts: [CatalogProductDraft]
    ) -> String {
        var batches = Self.loadBatches()
        batches.append(session)
        saveBatches(batches)

        for var draft in drafts {
            draft.batchID = session.id
            // 批次级归属：整批同店同系列（草稿可再单独改）
            draft.shopID = session.shopID
            draft.newShopName = session.newShopName
            draft.newShopAliases = session.newShopAliases
            draft.seriesID = session.seriesID
            draft.newSeriesName = session.newSeriesName
            draft.newSeriesYear = session.newSeriesYear
            draft.newSeriesSeason = session.newSeriesSeason
            upsert(draft)
        }
        return "已生成 \(drafts.count) 条单品草稿"
    }

    /// 批量提交（§4.1）：本批次全部草稿态条目 → 提交；单品状态互不耦合
    func submitBatch(_ batchID: String) throws -> Int {
        try CreatorAccess.requireCreator(.listingStatus)
        var count = 0
        for draft in drafts where draft.batchID == batchID && draft.status == .draft {
            try advance(draft, to: .submitted)
            count += 1
        }
        return count
    }

    /// 整批归属整合（V1.1 §4.1）：一次指定「店家 + 系列」，写入批次会话并同步到
    /// 该批全部未发布草稿——同一系列的多单品归入同一条系列链路，用户端从系列页
    /// 查看并选择全部单品，避免单品与链接一一对应的分散结构。
    /// 已发布（.published）条目不回写（发布产物已写入覆盖层，改动请走实体编辑）。
    /// 返回更新的草稿数。
    @discardableResult
    func applyBatchAttribution(
        batchID: String,
        shopID: String?, newShopName: String, newShopAliases: String,
        seriesID: String?, newSeriesName: String, newSeriesYear: Int?, newSeriesSeason: String
    ) -> Int {
        var batches = Self.loadBatches()
        guard let idx = batches.firstIndex(where: { $0.id == batchID }) else { return 0 }
        batches[idx].shopID = shopID
        batches[idx].newShopName = newShopName
        batches[idx].newShopAliases = newShopAliases
        batches[idx].seriesID = seriesID
        batches[idx].newSeriesName = newSeriesName
        batches[idx].newSeriesYear = newSeriesYear
        batches[idx].newSeriesSeason = newSeriesSeason
        saveBatches(batches)

        var count = 0
        for var draft in drafts
        where draft.batchID == batchID && draft.status != .published && draft.status != .archived {
            draft.shopID = shopID
            draft.newShopName = newShopName
            draft.newShopAliases = newShopAliases
            draft.seriesID = seriesID
            draft.newSeriesName = newSeriesName
            draft.newSeriesYear = newSeriesYear
            draft.newSeriesSeason = newSeriesSeason
            upsert(draft)
            count += 1
        }
        return count
    }

    /// 单品粒度审核（§4.1）：通过 → reviewed；驳回 → 退回草稿并保留原因
    func review(_ draft: CatalogProductDraft, approve: Bool, reason: String? = nil) throws {
        try CreatorAccess.requireCreator(.listingStatus)
        guard draft.status == .submitted else {
            throw ShopCatalogDraftStoreError.illegalTransition(from: draft.status, to: approve ? .reviewed : .draft)
        }
        if approve {
            try advance(draft, to: .reviewed)
            return
        }
        // 驳回：原因写入草稿（空白原因归一为 nil），状态退回 draft
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = draft
        updated.status = .draft
        updated.rejectReason = (trimmed?.isEmpty == false) ? trimmed : nil
        upsert(updated)
    }

    // MARK: 发布状态机（计划 §31：draft → submitted → reviewed → published，任一态可 archived）

    /// 推进草稿状态。非法流转抛错。
    /// `submitted → draft` 为审核驳回（V1.1 §4.1：部分通过发布、部分驳回退回草稿）。
    func advance(_ draft: CatalogProductDraft, to newStatus: CatalogPublicationStatus) throws {
        let allowed: [CatalogPublicationStatus: Set<CatalogPublicationStatus>] = [
            .draft: [.submitted, .archived],
            .submitted: [.reviewed, .archived, .draft],
            .reviewed: [.published, .archived],
            .published: [.archived],
            .archived: [.draft],
        ]
        guard allowed[draft.status]?.contains(newStatus) == true else {
            throw ShopCatalogDraftStoreError.illegalTransition(from: draft.status, to: newStatus)
        }
        var updated = draft
        updated.status = newStatus
        // 重新提交即视为已回应驳回意见：清空驳回原因
        if newStatus == .submitted { updated.rejectReason = nil }
        upsert(updated)
    }

    // MARK: 运营中心看板（计划 §26：今日更新 / 草稿 / 待审核 / 待补充）

    /// 今日更新：今天创建或推进过的草稿数
    var todayUpdatedCount: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return drafts.filter { $0.createdAt >= start }.count
    }

    var draftCount: Int { drafts.filter { $0.status == .draft }.count }

    /// 待审核：已提交、等待审核的草稿
    var pendingReviewCount: Int { drafts.filter { $0.status == .submitted }.count }

    /// 待补充：关键字段不全（缺名称 / 价格为 0 / 缺店家或系列）的草稿
    var needsSupplementCount: Int {
        drafts.filter { draft in
            draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                || (draft.effectiveReservationPrice == nil && draft.effectiveStockPrice == nil)
                || (draft.shopID == nil && draft.newShopName.trimmingCharacters(in: .whitespaces).isEmpty)
                || (draft.seriesID == nil && draft.newSeriesName.trimmingCharacters(in: .whitespaces).isEmpty)
        }.count
    }

    /// 发布：白名单校验（§26 服务层入口）→ 状态校验（§31：仅 reviewed 可发布）→
    /// 校验 → 去重合并（复用既有店家/系列；同名商品现货记录追加）→ 写覆盖层。
    func publish(_ draft: CatalogProductDraft, store: ShopCatalogStore) throws -> String {
        try CreatorAccess.requireCreator(.listingPublish)
        guard draft.status == .reviewed else {
            throw ShopCatalogDraftStoreError.notReadyForPublish(draft.status)
        }
        let catalog = store.catalog
        try ShopCatalogDraftValidator.validate(draft, catalog: catalog)

        var overlay = Self.loadOverlay() ?? ShopCatalog()

        // 店家：复用或新建（再按别名兜底去重一次）
        let shop: CatalogShop
        if let shopID = draft.shopID, let existing = catalog?.shops.first(where: { $0.id == shopID }) ?? overlay.shops.first(where: { $0.id == shopID }) {
            shop = existing
        } else if let hit = ShopCatalogDraftValidator.findExistingShop(for: draft, catalog: catalog ?? overlay) {
            shop = hit
        } else {
            let aliases = draft.newShopAliases
                .components(separatedBy: CharacterSet(charactersIn: "，,、"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            shop = CatalogShop(id: "shop-ops-\(UUID().uuidString.prefix(8))",
                               name: draft.newShopName.trimmingCharacters(in: .whitespaces),
                               aliases: aliases)
            overlay.shops.append(shop)
        }

        // 系列：复用或新建
        let series: CatalogSeries
        if let seriesID = draft.seriesID,
           let existing = catalog?.series.first(where: { $0.id == seriesID }) ?? overlay.series.first(where: { $0.id == seriesID }) {
            series = existing
        } else if let hit = ShopCatalogDraftValidator.findExistingSeries(for: draft, shopID: shop.id, catalog: catalog ?? overlay) {
            series = hit
        } else {
            series = CatalogSeries(id: "series-ops-\(UUID().uuidString.prefix(8))",
                                   shopID: shop.id,
                                   name: draft.newSeriesName.trimmingCharacters(in: .whitespaces),
                                   year: draft.newSeriesYear,
                                   season: draft.newSeriesSeason.isEmpty ? nil : draft.newSeriesSeason)
            overlay.series.append(series)
        }

        // 商品：已存在 → 只追加本次销售记录；否则新建
        //
        // ⚠️ 重复不再是阻断条件（2026-09-22）：补录上新场景里，商品常常已经存在于
        // Catalog，甚至已被用户收进心愿 / 尾款 / 衣橱。此时补录的目的正是给既有
        // 商品补充价格，预约价与现货价都必须能继续录入并提交；一旦拦截，价格就
        // 永远补不上去。
        // 处理口径：商品本体（名称/分类/图片/规格/尺码表）保持不变仅在草稿
        // 携带新资料时补全；本次价格作为一条新的 SaleEvent 追加，永不以"重复"
        // 为由抛错。
        var productID: String
        var summary: String
        if let existing = ShopCatalogDraftValidator.findExistingProduct(for: draft, seriesID: series.id, catalog: catalog ?? overlay) {
            productID = existing.id
            // 追加现货时若草稿带了规格/尺码表/图片，一并补全到既有商品（V1.1 §4.2 编辑）
            if !draft.variants.isEmpty || draft.sizeChart != nil || !draft.images.isEmpty {
                var updated = existing
                if !draft.variants.isEmpty {
                    overlay.variants.append(contentsOf: draft.variants.map { v in
                        var v = v
                        v.productID = existing.id
                        if !overlay.variants.contains(where: { $0.id == v.id }) { return v }
                        var copy = v
                        copy.id = "var-ops-\(UUID().uuidString.prefix(8))"
                        return copy
                    })
                }
                if let chart = draft.sizeChart {
                    var chart = chart
                    chart.productID = existing.id
                    overlay.sizeCharts.removeAll { $0.productID == existing.id }
                    overlay.sizeCharts.append(chart)
                }
                if !draft.images.isEmpty {
                    var assetIDs: [String] = []
                    for var asset in draft.images {
                        if overlay.assets.contains(where: { $0.id == asset.id }) {
                            asset.id = "asset-ops-\(UUID().uuidString.prefix(8))"
                        }
                        overlay.assets.append(asset)
                        assetIDs.append(asset.id)
                    }
                    if updated.images.isEmpty { updated.images = assetIDs }
                    else { updated.images.append(contentsOf: assetIDs) }
                }
                let index = overlay.products.firstIndex { $0.id == existing.id }
                if let index {
                    overlay.products[index] = updated
                } else {
                    // 既有商品在 Bundle 种子里：同 id 替换规则会以覆盖层版本胜出（§5.3）
                    overlay.products.append(updated)
                }
            }
            // V1.4「同款不同色」：既有商品缺款式名时按草稿回填（显式优先、名称派生兜底）。
            // 放在资料补全块之外：纯补价草稿也能让既有商品归入款式组。
            // 判定以**覆盖层**为准（写入目标）：调用方传入的 store 视图可能尚未刷新。
            let overlayProduct = overlay.products.first { $0.id == existing.id } ?? existing
            if overlayProduct.designName == nil {
                let backfilled = ShopCatalogSameDesignGrouper.resolveDesignName(
                    explicit: draft.designName, name: overlayProduct.name)
                if let backfilled {
                    var updated = overlayProduct
                    updated.designName = backfilled
                    if let index = overlay.products.firstIndex(where: { $0.id == existing.id }) {
                        overlay.products[index] = updated
                    } else {
                        overlay.products.append(updated)
                    }
                }
            }
            // 本次提交的价格由下方统一的 SaleEvent 追加逻辑落库
            var appendedKinds: [String] = []
            if draft.effectiveReservationPrice != nil { appendedKinds.append("预约价") }
            if draft.effectiveStockPrice != nil { appendedKinds.append("现货价") }
            summary = "已向既有商品「\(existing.name)」追加\(appendedKinds.joined(separator: " + "))记录"
        } else {
            productID = "prod-ops-\(UUID().uuidString.prefix(8))"
            let assetIDs = draft.images.map { asset -> String in
                var a = asset
                if overlay.assets.contains(where: { $0.id == a.id }) {
                    a.id = "asset-ops-\(UUID().uuidString.prefix(8))"
                }
                overlay.assets.append(a)
                return a.id
            }
            // V1.4「同款不同色」：显式款式名优先，未填按名称剥离颜色词派生，
            // 发布后列表按款式归组展示（同款不同色合并为一条）
            overlay.products.append(CatalogProduct(id: productID, shopID: shop.id, seriesID: series.id,
                                                   name: draft.name.trimmingCharacters(in: .whitespaces),
                                                   category: draft.category,
                                                   images: assetIDs,
                                                   designName: ShopCatalogSameDesignGrouper.resolveDesignName(
                                                       explicit: draft.designName,
                                                       name: draft.name.trimmingCharacters(in: .whitespaces))))
            // 规格 / 尺码表随商品一并落库（G5：手动录入可完成全部业务）
            overlay.variants.append(contentsOf: draft.variants.map { v in
                var v = v
                v.productID = productID
                return v
            })
            if var chart = draft.sizeChart {
                chart.productID = productID
                overlay.sizeCharts.append(chart)
            }
            summary = "已发布商品「\(draft.name)」"
        }

        // 销售记录（追加式，历史记录永不覆盖）：预约价与现货价**并存且不互斥**
        //（2026-09-22）—— 都填时各生成一条 SaleEvent；只填其一也放行（现货价可空置后补录）。
        if let reservationPrice = draft.effectiveReservationPrice {
            let eventDeposit = draft.deposit.map { Decimal($0) }
            var event = CatalogSaleEvent(
                id: "ev-ops-\(UUID().uuidString.prefix(8))",
                productID: productID,
                type: .reservation,
                price: Decimal(reservationPrice),
                deposit: eventDeposit,
                balance: draft.balance.map { Decimal($0) },
                startAt: draft.startAt,
                endAt: draft.endAt
            )
            // 只填定金时尾款自动补齐（沿用既有口径：预约价不被覆盖）
            if event.balance == nil {
                event.balance = event.price - (eventDeposit ?? 0)
            }
            overlay.saleEvents.append(event)
        }
        if let stockPrice = draft.effectiveStockPrice {
            overlay.saleEvents.append(CatalogSaleEvent(
                id: "ev-ops-\(UUID().uuidString.prefix(8))",
                productID: productID,
                type: .stock,
                price: Decimal(stockPrice),
                deposit: nil,
                balance: nil,
                startAt: draft.startAt,
                endAt: draft.endAt
            ))
        }

        try Self.saveOverlay(overlay)
        store.reloadWithOverlay()
        var draft = draft
        draft.status = .published
        upsert(draft)
        return summary + "（\(shop.name) · \(series.name)）"
    }

    // MARK: 实体编辑 / 归档 / 删除（V1.1 §4.2 + 重构方案 §5.5 引用保护）

    /// 把修改后的实体写入覆盖层（同 id 整体替换，合并规则见 ShopCatalogStore §5.3）。
    /// id 永不改变；所有关联的系列、商品自动跟随展示信息。
    static func upsertEntity<T: Identifiable>(
        _ entity: T, keyPath: WritableKeyPath<ShopCatalog, [T]>
    ) throws {
        try CreatorAccess.requireCreator(.listingEdit)
        var overlay = loadOverlay() ?? ShopCatalog()
        let array = overlay[keyPath: keyPath]
        if let index = array.firstIndex(where: { $0.id == entity.id }) {
            overlay[keyPath: keyPath][index] = entity
        } else {
            overlay[keyPath: keyPath].append(entity)
        }
        try saveOverlay(overlay)
        ShopCatalogStore.shared.reloadWithOverlay()
    }

    /// 已发布商品深度编辑（V1.1 §4.2 Product 修改：名称/分类/图片/配色尺码/尺码表）。
    /// id 永不改变，用户侧引用不受影响；一次落盘 product + assets + variants + sizeChart。
    /// 图片行 originalURL 未变的复用原 asset id（避免规格图文绑定与用户缓存断链）。
    static func updatePublishedProduct(
        _ product: CatalogProduct,
        assets: [CatalogAsset],
        variants: [CatalogProductVariant],
        sizeChart: CatalogSizeChart?
    ) throws {
        try CreatorAccess.requireCreator(.listingEdit)
        var overlay = loadOverlay() ?? ShopCatalog()

        // 旧商品图（来自覆盖层或 Bundle 种子）：清理覆盖层内旧图 asset，
        // Bundle 种子 asset 只读不可删，但新图用全新 id 写入覆盖层后同 id 合并规则以新图为准
        let oldImages = overlay.products.first { $0.id == product.id }?.images
            ?? ShopCatalogStore.shared.catalog?.products.first { $0.id == product.id }?.images
            ?? []
        if !oldImages.isEmpty {
            overlay.assets.removeAll { oldImages.contains($0.id) }
        }

        // 新 assets 写入（id 冲突时换新 id）
        var assetIDs: [String] = []
        for var asset in assets {
            if overlay.assets.contains(where: { $0.id == asset.id }) {
                asset.id = "asset-edit-\(UUID().uuidString.prefix(8))"
            }
            overlay.assets.append(asset)
            assetIDs.append(asset.id)
        }

        var updated = product
        updated.images = assetIDs
        // 防线：价格修正属于独立流程，资料保存若拿到修正前的旧快照，
        // 不得把修正值清掉（修正只能由 correctCurrentPrice / clearPriceCorrection 改动）
        if updated.priceCorrection == nil,
           let stored = overlay.products.first(where: { $0.id == product.id })?.priceCorrection {
            updated.priceCorrection = stored
        }

        // 规格 / 尺码表整组重建（productID 归位）
        overlay.variants.removeAll { $0.productID == product.id }
        overlay.variants.append(contentsOf: variants.map { v in
            var v = v
            v.productID = product.id
            return v
        })
        overlay.sizeCharts.removeAll { $0.productID == product.id }
        if var chart = sizeChart {
            chart.productID = product.id
            overlay.sizeCharts.append(chart)
        }

        if let index = overlay.products.firstIndex(where: { $0.id == product.id }) {
            overlay.products[index] = updated
        } else {
            // 既有商品在 Bundle 种子里：同 id 替换规则会以覆盖层版本胜出（§5.3）
            overlay.products.append(updated)
        }
        try saveOverlay(overlay)
        ShopCatalogStore.shared.reloadWithOverlay()
    }

    // MARK: 价格双流程（2026-09-22：价格修正 / 追加销售记录彻底分离）
    //
    // 两条流程的边界（硬约束，任何改动都不得打破）：
    //
    //   ┌──────────────┬──────────────────────────┬──────────────────────────┐
    //   │              │ 价格修正                  │ 追加销售记录              │
    //   │              │ correctCurrentPrice       │ appendSaleRecord          │
    //   ├──────────────┼──────────────────────────┼──────────────────────────┤
    //   │ 语义         │ 更正当前商品属性           │ 新增业务事件（再贩/补货） │
    //   │ 存储         │ product.priceCorrection   │ saleEvents（数组追加）    │
    //   │ 写入方式     │ 覆盖，只留最新状态         │ append-only，永不改写     │
    //   │ 历史记录     │ 不产生                    │ 每条一条，按时间排序      │
    //   │ 时间维度     │ correctedAt（审计）        │ startAt 必填（批次时间）  │
    //   │ 重复提交     │ 幂等（同值覆盖无副作用）   │ 指纹相同 → 抛错拦截      │
    //   └──────────────┴──────────────────────────┴──────────────────────────┘
    //
    // 两者**不共用任何校验或写入代码**：修正只碰 product，追加只碰 saleEvents。

    /// 价格修正：**覆盖**商品的当前价格状态（现货价 / 预约价 / 定金 / 尾款）。
    /// 只保留最新状态，不产生任何历史记录 —— `saleEvents` 全程只读不写。
    ///
    /// 口径（2026-09-22 调整）：传 nil = **清除该价格**（当前生效值变为「暂无」），
    /// 不是「跳过不修改」——修正弹窗预填当前生效值、按完整快照提交，
    /// 所以想保留的字段必须带着原值一起提交。全部留空 = 清除全部价格，合法。
    @discardableResult
    static func correctCurrentPrice(
        productID: String,
        reservationPrice: Decimal?,
        stockPrice: Decimal?,
        deposit: Decimal?,
        balance: Decimal?
    ) throws -> CatalogPriceCorrection {
        try CreatorAccess.requireCreator(.listingEdit)

        // 校验规则（只服务于「修正」语义：合法性 + 对账，不涉及批次时间）
        if let r = reservationPrice { guard r > 0 else { throw ShopCatalogPriceEditError.invalidPrice } }
        if let s = stockPrice { guard s > 0 else { throw ShopCatalogPriceEditError.invalidPrice } }
        if let d = deposit { guard d >= 0 else { throw ShopCatalogPriceEditError.invalidPrice } }
        if let b = balance { guard b >= 0 else { throw ShopCatalogPriceEditError.invalidPrice } }
        if let d = deposit, let b = balance, let base = reservationPrice, d + b != base {
            throw ShopCatalogPriceEditError.depositBalanceMismatch(
                "定金 \(NSDecimalNumber(decimal: d).stringValue) + 尾款 \(NSDecimalNumber(decimal: b).stringValue) ≠ 预约价 \(NSDecimalNumber(decimal: base).stringValue)")
        }
        // 预约价被清除时，定金 / 尾款失去对账基准，必须一并清空
        if reservationPrice == nil, deposit != nil || balance != nil {
            throw ShopCatalogPriceEditError.depositBalanceMismatch(
                "预约价已留空（清除），定金与尾款也需一并留空；或填回预约价后再修正定金尾款")
        }

        let correction = CatalogPriceCorrection(reservationPrice: reservationPrice,
                                                stockPrice: stockPrice,
                                                deposit: deposit,
                                                balance: balance,
                                                correctedAt: Date())

        var overlay = loadOverlay() ?? ShopCatalog()
        var product = overlay.products.first { $0.id == productID }
            ?? ShopCatalogStore.shared.catalog?.products.first { $0.id == productID }
        guard let product else { throw ShopCatalogPriceEditError.productNotFound(productID) }

        var updated = product
        updated.priceCorrection = correction
        if let index = overlay.products.firstIndex(where: { $0.id == productID }) {
            overlay.products[index] = updated
        } else {
            // 既有商品在 Bundle 种子里：同 id 替换规则以覆盖层版本胜出（§5.3）
            overlay.products.append(updated)
        }
        // ⚠️ 这里**绝不触碰 overlay.saleEvents**：修正不产生历史记录
        try saveOverlay(overlay)
        ShopCatalogStore.shared.reloadWithOverlay()
        return correction
    }

    /// 撤销价格修正：回到「由 append-only 历史推导」的口径。
    /// 只清 `priceCorrection`，销售历史一条不动。
    static func clearPriceCorrection(productID: String) throws {
        try CreatorAccess.requireCreator(.listingEdit)
        var overlay = loadOverlay() ?? ShopCatalog()
        guard var product = overlay.products.first(where: { $0.id == productID })
            ?? ShopCatalogStore.shared.catalog?.products.first(where: { $0.id == productID })
        else { throw ShopCatalogPriceEditError.productNotFound(productID) }
        product.priceCorrection = nil
        if let index = overlay.products.firstIndex(where: { $0.id == productID }) {
            overlay.products[index] = product
        } else {
            overlay.products.append(product)
        }
        try saveOverlay(overlay)
        ShopCatalogStore.shared.reloadWithOverlay()
    }

    /// 追加销售记录（往年款再贩 / 复刻 / 补货）：**append-only** 写入。
    ///
    /// 不可变性保证：本函数对 `overlay.saleEvents` 只做 `append`，
    /// 不做任何 remove / replace —— 已有记录永不被修改或覆盖。
    ///
    /// - startAt 必填：再贩日期 / 批次时间，是每条记录的时间维度；
    /// - 重复提交防护：业务指纹（商品 / 类型 / 价格 / 定金尾款 / 批次日）
    ///   命中既有记录时抛 `duplicateRecord`，不会写出第二条。
    @discardableResult
    static func appendSaleRecord(
        productID: String,
        type: CatalogSaleEventType,
        price: Decimal,
        deposit: Decimal? = nil,
        balance: Decimal? = nil,
        startAt: Date,
        endAt: Date? = nil,
        batchLabel: String? = nil
    ) throws -> CatalogSaleEvent {
        try CreatorAccess.requireCreator(.listingEdit)

        // 校验规则（只服务于「追加」语义：价格合法 + 时间维度必填 + 对账 + 去重）
        guard price > 0 else { throw ShopCatalogPriceEditError.invalidPrice }
        if let d = deposit, let b = balance, d + b != price {
            throw ShopCatalogPriceEditError.depositBalanceMismatch(
                "定金 \(NSDecimalNumber(decimal: d).stringValue) + 尾款 \(NSDecimalNumber(decimal: b).stringValue) ≠ 价格 \(NSDecimalNumber(decimal: price).stringValue)")
        }

        var event = CatalogSaleEvent(
            id: "ev-append-\(UUID().uuidString.prefix(8))",
            productID: productID,
            type: type,
            price: price,
            deposit: deposit,
            balance: balance,
            startAt: startAt,
            endAt: endAt,
            batchLabel: trimmedBatchLabel(batchLabel),
            recordedAt: Date()
        )
        // 预约类记录只填定金时自动补齐尾款（先补齐再算指纹，保证去重口径一致）
        if type == .reservation, event.balance == nil {
            event.balance = event.price - (event.deposit ?? 0)
        }

        var overlay = loadOverlay() ?? ShopCatalog()
        // 重复提交防护：覆盖层 + 已合并进内存的种子记录都要比对
        var known = overlay.saleEvents
        for existing in ShopCatalogStore.shared.catalog?.saleEvents ?? []
        where !known.contains(where: { $0.id == existing.id }) {
            known.append(existing)
        }
        let fingerprint = event.appendFingerprint
        guard !known.contains(where: { $0.appendFingerprint == fingerprint }) else {
            throw ShopCatalogPriceEditError.duplicateRecord
        }

        overlay.saleEvents.append(event)   // 只追加：既有记录不可变
        try saveOverlay(overlay)
        ShopCatalogStore.shared.reloadWithOverlay()
        return event
    }

    private static func trimmedBatchLabel(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    /// 归档：写 archivedAt（同 id 替换）。用户端隐藏，用户已收藏记录保留（§4.2）。
    static func archiveShop(_ shop: CatalogShop) throws {
        try CreatorAccess.requireCreator(.listingStatus)
        var updated = shop
        updated.archivedAt = Date()
        try upsertEntity(updated, keyPath: \.shops)
    }

    static func archiveSeries(_ series: CatalogSeries) throws {
        try CreatorAccess.requireCreator(.listingStatus)
        var updated = series
        updated.archivedAt = Date()
        try upsertEntity(updated, keyPath: \.series)
    }

    static func archiveProduct(_ product: CatalogProduct) throws {
        try CreatorAccess.requireCreator(.listingStatus)
        var updated = product
        updated.archivedAt = Date()
        try upsertEntity(updated, keyPath: \.products)
    }

    /// 物理删除：仅当实体来自运营覆盖层（Bundle 种子不可变）、无下级、且无用户引用时允许；
    /// 否则抛错，提示仅可归档（§4.2 引用保护）。
    static func deleteProduct(
        _ product: CatalogProduct, store: ShopCatalogStore, modelContext: ModelContext
    ) throws {
        try CreatorAccess.requireCreator(.listingDelete)
        let catalog = store.catalog
        // 引用保护：被用户心愿/尾款/衣橱引用（含软删除记录）→ 禁止物理删除
        let referenced = try ShopCatalogReferenceGuard.referencedProductIDs(
            [product.id], modelContext: modelContext)
        guard referenced.isEmpty else {
            throw ShopCatalogEntityError.referencedOnlyArchive(
                kind: "商品", name: product.name)
        }
        guard let overlay = loadOverlay(),
              overlay.products.contains(where: { $0.id == product.id }) else {
            throw ShopCatalogEntityError.seedImmutableOnlyArchive(kind: "商品", name: product.name)
        }
        var updated = overlay
        updated.products.removeAll { $0.id == product.id }
        // 无引用时连带清理其规格/尺码表（销售事件按硬约束保留历史）
        updated.variants.removeAll { $0.productID == product.id }
        updated.sizeCharts.removeAll { $0.productID == product.id }
        // 种子里也有同 id → 物理删除做不到（Bundle 只读），退化为归档
        if store.isSeedProduct(id: product.id) {
            throw ShopCatalogEntityError.seedImmutableOnlyArchive(kind: "商品", name: product.name)
        }
        try saveOverlay(updated)
        ShopCatalogStore.shared.reloadWithOverlay()
    }

    static func deleteSeries(
        _ series: CatalogSeries, store: ShopCatalogStore, modelContext: ModelContext
    ) throws {
        try CreatorAccess.requireCreator(.listingDelete)
        let catalog = store.catalog
        let childProducts = (catalog?.products ?? []).filter { $0.seriesID == series.id }
        guard childProducts.isEmpty else {
            throw ShopCatalogEntityError.hasChildrenOnlyArchive(
                kind: "系列", name: series.name, childCount: childProducts.count)
        }
        guard let overlay = loadOverlay(),
              overlay.series.contains(where: { $0.id == series.id }) else {
            throw ShopCatalogEntityError.seedImmutableOnlyArchive(kind: "系列", name: series.name)
        }
        var updated = overlay
        updated.series.removeAll { $0.id == series.id }
        if store.isSeedSeries(id: series.id) {
            throw ShopCatalogEntityError.seedImmutableOnlyArchive(kind: "系列", name: series.name)
        }
        try saveOverlay(updated)
        ShopCatalogStore.shared.reloadWithOverlay()
    }

    static func deleteShop(
        _ shop: CatalogShop, store: ShopCatalogStore, modelContext: ModelContext
    ) throws {
        try CreatorAccess.requireCreator(.listingDelete)
        let catalog = store.catalog
        let childSeries = (catalog?.series ?? []).filter { $0.shopID == shop.id }
        let childProducts = (catalog?.products ?? []).filter { $0.shopID == shop.id }
        guard childSeries.isEmpty && childProducts.isEmpty else {
            throw ShopCatalogEntityError.hasChildrenOnlyArchive(
                kind: "店家", name: shop.name, childCount: childSeries.count + childProducts.count)
        }
        guard let overlay = loadOverlay(),
              overlay.shops.contains(where: { $0.id == shop.id }) else {
            throw ShopCatalogEntityError.seedImmutableOnlyArchive(kind: "店家", name: shop.name)
        }
        var updated = overlay
        updated.shops.removeAll { $0.id == shop.id }
        if store.isSeedShop(id: shop.id) {
            throw ShopCatalogEntityError.seedImmutableOnlyArchive(kind: "店家", name: shop.name)
        }
        try saveOverlay(updated)
        ShopCatalogStore.shared.reloadWithOverlay()
    }

    // MARK: 覆盖层读写

    nonisolated static func loadOverlay() -> ShopCatalog? {
        guard let data = try? Data(contentsOf: overlayURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ShopCatalog.self, from: data)
    }

    private nonisolated static func saveOverlay(_ overlay: ShopCatalog) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(overlay)
        try data.write(to: overlayURL, options: .atomic)
    }

    /// 导出整包（含 Bundle 种子 + 覆盖层），用于交接 / 备份
    func exportJSON(store: ShopCatalogStore) -> String? {
        guard let catalog = store.catalog else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(catalog) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - 引用保护（V1.1 §4.2 + 重构方案 §5.5）

/// 判定 Catalog 实体是否被用户私有状态引用（心愿 / 尾款 / 少女衣橱）。
/// 口径：`Clothing.catalog*` 引用字段命中即算被引用——**含软删除记录**
/// （deletedAt 不豁免），保证「被引用过 → 只能归档」保守成立。
enum ShopCatalogReferenceGuard {

    /// 返回入参中被引用的商品 id 集合
    static func referencedProductIDs(
        _ productIDs: Set<String>, modelContext: ModelContext
    ) throws -> Set<String> {
        guard !productIDs.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Clothing>(
            predicate: #Predicate { clothing in
                clothing.catalogProductID != nil
            }
        )
        let clothings = try modelContext.fetch(descriptor)
        var hit = Set<String>()
        for clothing in clothings {
            if let pid = clothing.catalogProductID, productIDs.contains(pid) {
                hit.insert(pid)
            }
        }
        return hit
    }

    /// 系列被引用判定：系列下存在任意商品（含已归档）或商品被用户引用
    static func seriesHasReferencedContent(
        _ series: CatalogSeries, store: ShopCatalogStore, modelContext: ModelContext
    ) throws -> Bool {
        let products = (store.catalog?.products ?? []).filter { $0.seriesID == series.id }
        guard !products.isEmpty else { return false }
        let referenced = try referencedProductIDs(Set(products.map(\.id)), modelContext: modelContext)
        return !referenced.isEmpty || !products.isEmpty // 有商品即算有内容引用
    }
}

// MARK: - 实体操作错误（V1.1 §4.2）

nonisolated enum ShopCatalogEntityError: LocalizedError {
    /// 被用户心愿/尾款/衣橱引用 → 禁止物理删除，仅可归档
    case referencedOnlyArchive(kind: String, name: String)
    /// 存在下级实体（系列/商品）→ 禁止物理删除
    case hasChildrenOnlyArchive(kind: String, name: String, childCount: Int)
    /// 实体来自 Bundle 种子（只读）→ 无法物理删除，仅可归档
    case seedImmutableOnlyArchive(kind: String, name: String)

    var errorDescription: String? {
        switch self {
        case .referencedOnlyArchive(let kind, let name):
            return "「\(name)」已被用户心愿/尾款/衣橱引用，禁止删除，仅可归档。"
        case .hasChildrenOnlyArchive(let kind, let name, let count):
            return "「\(name)」名下仍有 \(count) 个下级条目，请先处理下级，或仅归档。"
        case .seedImmutableOnlyArchive(let kind, let name):
            return "「\(name)」来自随版本内置的种子档案，无法物理删除，仅可归档。"
        }
    }
}
