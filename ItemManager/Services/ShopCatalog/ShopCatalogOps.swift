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

    var status: CatalogPublicationStatus = .draft
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

    // MARK: 发布状态机（计划 §31：draft → submitted → reviewed → published，任一态可 archived）

    /// 推进草稿状态。非法流转抛错。
    func advance(_ draft: CatalogProductDraft, to newStatus: CatalogPublicationStatus) throws {
        let allowed: [CatalogPublicationStatus: Set<CatalogPublicationStatus>] = [
            .draft: [.submitted, .archived],
            .submitted: [.reviewed, .archived],
            .reviewed: [.published, .archived],
            .published: [.archived],
            .archived: [.draft],
        ]
        guard allowed[draft.status]?.contains(newStatus) == true else {
            throw ShopCatalogDraftStoreError.illegalTransition(from: draft.status, to: newStatus)
        }
        var updated = draft
        updated.status = newStatus
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
            summary = "已向既有商品「\(existing.name)」追加现货记录"
        } else {
            productID = "prod-ops-\(UUID().uuidString.prefix(8))"
            overlay.products.append(CatalogProduct(id: productID, shopID: shop.id, seriesID: series.id,
                                                   name: draft.name.trimmingCharacters(in: .whitespaces),
                                                   category: draft.category))
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
