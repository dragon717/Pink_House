//
//  ShopCatalogOps.swift
//  ItemManager
//
//  店家商品库运营端（Phase 6，计划 §26-31）：
//    · CatalogProductDraft  运营草稿（§27 自动生成草稿 → 人工补录）
//    · ShopCatalogTaobaoParser  淘宝分享文本 / URL 导入的轻量解析（§28）
//    · ShopCatalogDraftStore    草稿持久化 + 发布 → 覆盖层 JSON（§31 草稿/发布）
//    · 发布校验：必填项、价格、定金尾款对账、Shop/Series/Product 去重（§29）
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
    /// 本次销售记录类型：reservation / stock
    var saleKind: CatalogSaleEventType = .reservation
    var price: Double = 0
    var deposit: Double?
    var balance: Double?
    var startAt: Date? = nil
    var endAt: Date? = nil
    var sourceURL: String? = nil

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

    /// 预约草稿的定金尾款对账（允许缺省，缺省时发布前自动补齐）
    nonisolated var depositBalanceIssue: String? {
        guard saleKind == .reservation, let d = deposit, let b = balance else { return nil }
        return (Decimal(d) + Decimal(b)) == Decimal(price)
            ? nil : "定金 \(Int(d)) + 尾款 \(Int(b)) ≠ 总价 \(Int(price))"
    }
}

// MARK: - 淘宝解析（§28：部分自动解析，人工补录兜底）

nonisolated enum ShopCatalogTaobaoParser {

    nonisolated struct ParsedListing: Sendable, Equatable {
        var url: String?
        var title: String?
        var price: Double?
        var deposit: Double?
        var balance: Double?
        /// 解析出的字段说明（人工补录提示用）
        var notes: [String]
    }

    /// 从淘宝 App 分享文本 / 链接中抽取可自动化的最小字段集。
    /// 抽不到的字段留空，由人工补录（计划 §28「部分自动解析」定位）。
    static func parse(_ text: String) -> ParsedListing {
        var result = ParsedListing(notes: [])
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. URL（短链 / 商品页）
        if let range = trimmed.range(of: #"https?://[^\s，,。）)]+"#, options: .regularExpression) {
            result.url = String(trimmed[range])
            result.notes.append("已识别链接")
        }

        // 2. 标题：第一个非链接、非「复制这条信息」口令行的行
        for line in trimmed.components(separatedBy: .newlines) {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !l.isEmpty,
                  !l.lowercased().contains("http"),
                  !l.contains("复制"),
                  !l.contains("打开淘宝"),
                  !l.contains("----------------") else { continue }
            result.title = String(l.prefix(60))
            break
        }

        // 3. 价格：¥428 / 428元 / 价格:428
        let pricePatterns = [#"(?:¥|￥)\s*(\d+(?:\.\d+)?)"#, #"(\d+(?:\.\d+)?)\s*元"#, #"价格[:：]?\s*(\d+(?:\.\d+)?)"#]
        for p in pricePatterns {
            if let range = trimmed.range(of: p, options: .regularExpression),
               let num = trimmed[range].range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression),
               let value = Double(trimmed[num]) {
                result.price = value
                break
            }
        }

        // 4. 定金 / 尾款
        if let range = trimmed.range(of: #"定金[:：\s]*?(\d+(?:\.\d+)?)"#, options: .regularExpression) {
            result.deposit = Double(trimmed[range].range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression).map { String(trimmed[$0]) } ?? "")
        }
        if let range = trimmed.range(of: #"尾款[:：\s]*?(\d+(?:\.\d+)?)"#, options: .regularExpression) {
            result.balance = Double(trimmed[range].range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression).map { String(trimmed[$0]) } ?? "")
        }

        // 5. 有定金即预约记录，否则现货
        if result.deposit != nil || result.balance != nil {
            result.notes.append("识别为预约（含定金/尾款）")
        } else {
            result.notes.append("默认按现货记录")
        }
        return result
    }

    /// 解析结果 → 草稿（§28 自动生成草稿）
    static func makeDraft(from parsed: ParsedListing, category: String = "其他") -> CatalogProductDraft {
        var draft = CatalogProductDraft()
        draft.name = parsed.title ?? ""
        draft.category = category
        if let d = parsed.deposit {
            draft.saleKind = .reservation
            draft.deposit = d
            draft.balance = parsed.balance ?? ((parsed.price ?? 0) - d >= 0 ? (parsed.price ?? 0) - d : nil)
            draft.price = parsed.price ?? ((d + (parsed.balance ?? 0)))
        } else {
            draft.saleKind = .stock
            draft.price = parsed.price ?? 0
        }
        draft.sourceURL = parsed.url
        return draft
    }

    // MARK: 批量导入（V1.1 §4.1：多条链接/分享文本 → 多条独立草稿，逐条容错）

    /// 批量导入结果：每条输入独立产出草稿或错误，失败不阻塞其余条目
    nonisolated struct BatchParseOutcome: Sendable, Equatable {
        var drafts: [CatalogProductDraft]
        /// 解析失败条目（原文片段 + 原因），运营在批次页逐条补录
        var failures: [BatchParseFailure]

        nonisolated struct BatchParseFailure: Sendable, Equatable {
            var excerpt: String
            var reason: String
        }
    }

    /// 多条淘宝内容批量解析：按 URL 切分输入文本，每段一个候选单品。
    /// 规则：每条 URL 及其前导文本 = 一个条目；无 URL 的整段文本 = 单条目兜底。
    /// 解析结果**永远是草稿**，绝不直接发布（硬约束 §6）。
    static func parseBatch(_ text: String) -> BatchParseOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return BatchParseOutcome(drafts: [], failures: [])
        }

        // 切分：以 http(s) URL 为界，URL 带上其前导文案作为一段
        var segments: [String] = []
        if let regex = try? NSRegularExpression(pattern: #"https?://[^\s，,。）)]+"#) {
            let ns = trimmed as NSString
            let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
            var cursor = 0
            for m in matches {
                if m.range.location > cursor {
                    let head = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                    segments.append(head + ns.substring(with: m.range))
                } else {
                    segments.append(ns.substring(with: m.range))
                }
                cursor = m.range.location + m.range.length
            }
            if cursor < ns.length {
                segments.append(ns.substring(from: cursor))
            }
        }
        if segments.isEmpty { segments = [trimmed] }

        var drafts: [CatalogProductDraft] = []
        var failures: [BatchParseOutcome.BatchParseFailure] = []
        for segment in segments {
            let content = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            let parsed = parse(content)
            // 完全解析不出任何有效字段（无链接、无标题、无价格）→ 记失败不阻塞
            if parsed.url == nil, (parsed.title ?? "").isEmpty, parsed.price == nil {
                failures.append(.init(excerpt: String(content.prefix(40)),
                                      reason: "未识别到链接、标题或价格，请手动补录"))
                continue
            }
            let draft = makeDraft(from: parsed)
            // 同批次草稿默认归入同一批次会话（batchID 由调用方回填）
            drafts.append(draft)
        }
        return BatchParseOutcome(drafts: drafts, failures: failures)
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

    /// 原始淘宝文本仅运营侧留存（draftID → 原文），绝不透出用户端（V1.1 §5）
    var sourceTexts: [String: String] = [:]
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
        guard draft.price > 0 else { throw ValidationError.invalidPrice }
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

// MARK: - 草稿存储 + 发布（§31）

@MainActor
final class ShopCatalogDraftStore: ObservableObject {
    static let shared = ShopCatalogDraftStore()

    @Published private(set) var drafts: [CatalogProductDraft] = []

    private let fileManager = FileManager.default
    private var draftsURL: URL {
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShopCatalog", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("shop-catalog-drafts.json")
    }

    private var batchesURL: URL {
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShopCatalog", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("shop-catalog-batches.json")
    }

    /// 发布后的覆盖层：与 Bundle 种子合并后对用户可见
    nonisolated static var overlayURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShopCatalog", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("shop-catalog-override.json")
    }

    private init() {
        loadDrafts()
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
    }

    nonisolated private static var batchesURLStatic: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShopCatalog", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("shop-catalog-batches.json")
    }

    /// 创建批次并把批量解析出的草稿写入草稿箱（含失败清单回传提示文案）
    @discardableResult
    func createBatch(
        _ session: CatalogBatchEntrySession,
        drafts: [CatalogProductDraft],
        failures: [ShopCatalogTaobaoParser.BatchParseOutcome.BatchParseFailure] = []
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
        if failures.isEmpty {
            return "已生成 \(drafts.count) 条单品草稿"
        }
        return "已整理部分资料：\(drafts.count) 条草稿，\(failures.count) 条异常请手动补全"
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
                || draft.price <= 0
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

        // 商品：同名 → 现货记录追加；否则新建
        var productID: String
        var summary: String
        if let existing = ShopCatalogDraftValidator.findExistingProduct(for: draft, seriesID: series.id, catalog: catalog ?? overlay) {
            guard draft.saleKind == .stock else {
                throw ShopCatalogDraftValidator.ValidationError.depositBalanceMismatch(
                    "「\(existing.name)」已收录，预约记录请直接编辑既有商品，或改用现货追加")
            }
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
            summary = "已向既有商品「\(existing.name)」追加现货记录"
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
            overlay.products.append(CatalogProduct(id: productID, shopID: shop.id, seriesID: series.id,
                                                   name: draft.name.trimmingCharacters(in: .whitespaces),
                                                   category: draft.category,
                                                   images: assetIDs))
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

        // 销售记录（追加式，预约价不被覆盖——计划 §7 约束）
        let eventPrice = Decimal(draft.price)
        let eventDeposit = draft.deposit.map { Decimal($0) }
        let eventBalance = draft.balance.map { Decimal($0) }
        var event = CatalogSaleEvent(
            id: "ev-ops-\(UUID().uuidString.prefix(8))",
            productID: productID,
            type: draft.saleKind,
            price: eventPrice,
            deposit: eventDeposit,
            balance: eventBalance,
            startAt: draft.startAt,
            endAt: draft.endAt
        )
        if draft.saleKind == .reservation, event.balance == nil {
            event.balance = eventPrice - (eventDeposit ?? 0)
        }
        overlay.saleEvents.append(event)

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
