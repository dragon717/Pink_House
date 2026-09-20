import Foundation
import SwiftData

// MARK: - 旧馆收藏 → 心愿尾款 运行时一次性迁移
//
// 重构方案《时光馆_店家上新模式重构实现方案》§5.6 收藏行 + §7 Phase 4 推迟决策
// 的前置条件：`timeHall.treasured.v1`（旧馆画册展品收藏，UserDefaults 字符串数组）
// 在新首屏（店家商品库）没有对应形态，需要一次运行时迁移把收藏落到心愿体系。
//
// **口径（2026-09-21 用户确认）**：
// 1. 匹配到的收藏按 `ShopCatalogWardrobeDraftBuilder.PriceMode.wishlist` 落
//    「心愿尾款」记录（isDepositPlan=true、定金 0、全款记待付尾款），复用现有
//    落库管线（DraftBuilder → Inserter），落库后自动携带 catalogProductID。
// 2. 匹配不到的收藏**保留在旧馆归档**：`treasured.v1` 原键永不删除、不改写，
//    旧馆「珍选」入口继续可见（§4.5 不静默删除）。
// 3. 幂等：迁移标记键（markerKey）存在则整轮不再执行；逐条层面，已存在同
//    catalogProductID 的未删除记录时跳过——即便标记丢失，重复执行也不会
//    产生重复记录。
//
// 本类型只读 treasured 集合、只新增 Clothing 记录，不触碰衣橱既有数据、
// 照片、手账或其他个人资产。

@MainActor
enum TimeHallTreasuredWishMigrator {

    // MARK: 报告

    /// 迁移报告（同时作为 UserDefaults 标记载荷，供审计与排查）。
    struct Report: Equatable, Codable {
        /// treasuredID（旧画册展品 id）→ CatalogProduct.id（"th-" 前缀）
        var matched: [String: String] = [:]
        /// 两种情况：旧馆种子中找不到该 id；或找到了但新库中无对应迁移商品
        var unmatched: [String] = []
        /// 已有同 catalogProductID 记录而跳过的条数（幂等护栏）
        var skippedExisting = 0
        /// 本次新建的心愿尾款记录条数
        var createdCount = 0
        var migratedAt = Date()
    }

    /// 迁移完成标记（UserDefaults，存在即视为已完成，不再执行）。
    static let markerKey = "timeHall.treasured.wishMigration.v1"

    // MARK: 入口

    /// 自动一次性迁移：标记不存在时执行一轮，完成后写标记。
    /// 已迁移过返回 nil（调用方可静默忽略）。
    @discardableResult
    static func runIfNotYetMigrated(
        store: ShopCatalogStore = .shared,
        timeHall: TimeHallCatalogStore = .shared,
        userState: TimeHallUserStateStore = .shared,
        defaults: UserDefaults = .standard,
        modelContext: ModelContext
    ) -> Report? {
        guard defaults.data(forKey: markerKey) == nil else { return nil }
        let report = run(store: store, timeHall: timeHall, userState: userState, modelContext: modelContext)
        if let data = try? JSONEncoder().encode(report) {
            defaults.set(data, forKey: markerKey)
        }
        return report
    }

    /// 执行一轮迁移（不做标记检查，幂等性由逐条跳过保证；测试与手动重放用）。
    @discardableResult
    static func run(
        store: ShopCatalogStore = .shared,
        timeHall: TimeHallCatalogStore = .shared,
        userState: TimeHallUserStateStore = .shared,
        modelContext: ModelContext
    ) -> Report {
        var report = Report()
        let treasuredIDs = userState.treasuredIDs.sorted()

        // 旧馆 item id → productCode 二级解析表（迁移 id 策略："th-" + productCode
        // 优先于 item id，因此直查失败时需回查旧馆种子）。
        let productCodeByID = Dictionary(
            uniqueKeysWithValues: timeHall.items.map { ($0.id, $0.productCode) }
        )

        for treasuredID in treasuredIDs {
            guard let product = resolveProduct(
                treasuredID: treasuredID,
                productCodeByID: productCodeByID,
                store: store
            ) else {
                report.unmatched.append(treasuredID)
                continue
            }
            report.matched[treasuredID] = product.id

            if hasExistingRecord(productID: product.id, modelContext: modelContext) {
                report.skippedExisting += 1
                continue
            }

            do {
                guard let draft = ShopCatalogWardrobeDraftBuilder.makeDraft(
                    selection: .init(productID: product.id, priceMode: .wishlist),
                    store: store,
                    modelContext: modelContext
                ) else {
                    report.unmatched.append(treasuredID)
                    report.matched[treasuredID] = nil
                    continue
                }
                _ = try ShopCatalogWardrobeInserter.insert(
                    draft: draft,
                    selection: .init(productID: product.id, priceMode: .wishlist),
                    store: store,
                    modelContext: modelContext
                )
                report.createdCount += 1
            } catch {
                // 单条失败不中断整轮；该收藏留在旧馆归档（treasured.v1 不动）
                report.matched[treasuredID] = nil
                report.unmatched.append(treasuredID)
            }
        }
        return report
    }

    // MARK: 匹配

    /// 收藏 id → 迁移商品。两级解析：
    /// 1) 直查 "th-\(treasuredID)"（覆盖无 productCode 的展品，以及
    ///    productCode == item id 的展品）；
    /// 2) 回查旧馆种子的 productCode，再查 "th-\(productCode)"。
    static func resolveProduct(
        treasuredID: String,
        productCodeByID: [String: String?],
        store: ShopCatalogStore
    ) -> CatalogProduct? {
        if let direct = store.product(id: "th-\(treasuredID)") { return direct }
        guard let productCode = productCodeByID[treasuredID] ?? nil,
              !productCode.isEmpty,
              productCode != treasuredID else { return nil }
        return store.product(id: "th-\(productCode)")
    }

    /// 幂等护栏：该商品是否已有未删除的心愿/衣橱记录（与商品详情页判定口径一致）。
    static func hasExistingRecord(productID: String, modelContext: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<Clothing>(
            predicate: #Predicate { $0.catalogProductID == productID && $0.isDeleted == false }
        )
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetch(descriptor))?.isEmpty == false)
    }
}
