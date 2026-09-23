import Foundation
import SwiftData

// MARK: - 旧馆收藏 → 心愿尾款 运行时迁移
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
//
// **R08 收口（2026-09-22 第三版）**：旧实现无论本轮有多少 unmatched / 单条异常，
// 结束后都会写一个全局标记，后续自动入口见标记即整轮跳过 ——
// 于是「本轮执行过」被误当成「全部迁移完成」，失败项被永久封死，
// 资源补齐后（例如候选包合入后旧收藏终于可解析）也不会再重试。
//
// 本版改为**逐条检查点**：
//   · 检查点记录每条收藏的状态（已迁 / 待重试 / 失败 / 用户已删除）与失败原因；
//   · 已成功的重放跳过，不会再建第二条；
//   · 未完成项在每次运行时**只重试这些**，不整轮重来；
//   · 用户迁移后主动删除的记录记 `removedByUser`，重放**不复活**；
//   · 全局标记区分「本轮执行过」与「全部完成」：未完成时下轮继续跑未完成项；
//   · Catalog 尚未就绪时不写完成标记，等待具备条件再执行。
//
// 本类型只读 treasured 集合、只新增 Clothing 记录，不触碰衣橱既有数据、
// 照片、手账或其他个人资产；`timeHall.treasured.v1` 永不由本次迁移删除。

@MainActor
enum TimeHallTreasuredWishMigrator {

    // MARK: 报告

    /// 迁移报告（同时作为审计载荷；**不再**兼作「全部完成」标记）。
    struct Report: Equatable, Codable {
        /// treasuredID（旧画册展品 id）→ CatalogProduct.id（"th-" 前缀）
        var matched: [String: String] = [:]
        /// 两种情况：旧馆种子中找不到该 id；或找到了但新库中无对应迁移商品
        var unmatched: [String] = []
        /// 已有同 catalogProductID 记录而跳过的条数（幂等护栏）
        var skippedExisting = 0
        /// 本次新建的心愿尾款记录条数
        var createdCount = 0
        /// 落库抛错的条数（检查点记为 failed，可单条重试）
        var failedCount = 0
        /// 本轮重试的历史未完成项条数
        var retriedCount = 0
        /// 检查点显示曾迁移成功、但记录现已不存在 → 判为迁移后主动删除
        var removedByUserCount = 0
        /// 本轮是否已把全部收藏处理完（决定全局标记写「完成」还是「待续」）
        var isComplete = false
        var migratedAt = Date()
    }

    /// 本轮执行标记。存在 ≠ 全部完成：`completed` 为 false 时下轮继续补迁。
    struct RunMarker: Codable {
        var lastRunAt: Date
        var completed: Bool
        var total: Int
        var migrated: Int
        var pending: Int
    }

    // MARK: 检查点

    enum ItemState: String, Codable {
        /// 已成功迁入心愿尾款
        case migrated
        /// 尚未匹配到目标商品（资源补齐后可重试）
        case pending
        /// 落库阶段失败（可单条重试）
        case failed
        /// 迁移后用户主动删除 / 软删除 → 重放不得复活
        case removedByUser
    }

    struct ItemCheckpoint: Codable {
        var state: ItemState
        var productID: String?
        var detail: String?
        var updatedAt: Date
    }

    /// 迁移完成标记（UserDefaults）。见 `RunMarker.completed` 的语义说明。
    static let markerKey = "timeHall.treasured.wishMigration.v1"
    /// 逐条检查点（R08）：不放在标记里，避免「标记一写就封死失败项」。
    static let checkpointKey = "timeHall.treasured.wishMigration.checkpoints.v1"

    // MARK: 检查点读写

    static func loadCheckpoints(_ defaults: UserDefaults) -> [String: ItemCheckpoint] {
        guard let data = defaults.data(forKey: checkpointKey),
              let decoded = try? JSONDecoder().decode([String: ItemCheckpoint].self, from: data)
        else { return [:] }
        return decoded
    }

    static func saveCheckpoints(_ checkpoints: [String: ItemCheckpoint], _ defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(checkpoints) else { return }
        defaults.set(data, forKey: checkpointKey)
    }

    static func loadMarker(_ defaults: UserDefaults) -> RunMarker? {
        guard let data = defaults.data(forKey: markerKey) else { return nil }
        return try? JSONDecoder().decode(RunMarker.self, from: data)
    }

    // MARK: 入口

    /// 自动迁移入口：Catalog 未就绪 → 什么都不做（也不写标记，等条件具备）；
    /// 已全部完成 → 返回 nil；否则跑一轮，且**只处理未完成项**。
    @discardableResult
    static func runIfNotYetMigrated(
        store: ShopCatalogStore = .shared,
        timeHall: TimeHallCatalogStore = .shared,
        userState: TimeHallUserStateStore = .shared,
        defaults: UserDefaults = .standard,
        modelContext: ModelContext
    ) -> Report? {
        // 资源未就绪：不执行、不写标记（R08「Catalog / 旧来源尚未就绪」一条）
        guard store.catalog != nil else { return nil }
        if let marker = loadMarker(defaults), marker.completed { return nil }
        return run(store: store, timeHall: timeHall, userState: userState,
                   defaults: defaults, modelContext: modelContext)
    }

    /// 执行一轮迁移（不做标记检查；测试与手动重放用）。
    ///
    /// 幂等由**逐条检查点**保证：已成功的跳过，已删除的不复活，
    /// 只有 pending / failed 会重新尝试——即便标记丢失也不会产生重复记录。
    @discardableResult
    static func run(
        store: ShopCatalogStore = .shared,
        timeHall: TimeHallCatalogStore = .shared,
        userState: TimeHallUserStateStore = .shared,
        defaults: UserDefaults = .standard,
        modelContext: ModelContext
    ) -> Report {
        var report = Report()
        var checkpoints = loadCheckpoints(defaults)
        let treasuredIDs = userState.treasuredIDs.sorted()

        // 旧馆 item id → productCode 二级解析表（迁移 id 策略："th-" + productCode
        // 优先于 item id，因此直查失败时需回查旧馆种子）。
        let productCodeByID = Dictionary(
            uniqueKeysWithValues: timeHall.items.map { ($0.id, $0.productCode) }
        )

        for treasuredID in treasuredIDs {
            // ── 检查点 ①：已成功过 ────────────────────────────────────────
            if let cp = checkpoints[treasuredID], cp.state == .migrated {
                if hasExistingRecord(productID: cp.productID ?? "", modelContext: modelContext) {
                    report.skippedExisting += 1
                    continue
                }
                // 曾迁移成功但记录已不在（用户主动删除或软删）→ 标记不再复活，
                // 而不是凭「现在查不到记录」就再建一条（R08 防重放复活）
                checkpoints[treasuredID] = ItemCheckpoint(
                    state: .removedByUser, productID: cp.productID,
                    detail: "迁移后记录已不存在，判为用户主动删除，重放不复活",
                    updatedAt: Date())
                report.removedByUserCount += 1
                continue
            }
            // ── 检查点 ②：用户已删除，永不复活 ─────────────────────────────
            if let cp = checkpoints[treasuredID], cp.state == .removedByUser {
                continue
            }
            // ── 检查点 ③：历史未完成项 → 本轮重试 ─────────────────────────
            if checkpoints[treasuredID] != nil { report.retriedCount += 1 }

            guard let product = resolveProduct(
                treasuredID: treasuredID,
                productCodeByID: productCodeByID,
                store: store
            ) else {
                report.unmatched.append(treasuredID)
                checkpoints[treasuredID] = ItemCheckpoint(
                    state: .pending, productID: nil,
                    detail: "未匹配到迁移商品（候选包补齐后可重试）",
                    updatedAt: Date())
                continue
            }
            report.matched[treasuredID] = product.id

            if hasExistingRecord(productID: product.id, modelContext: modelContext) {
                report.skippedExisting += 1
                checkpoints[treasuredID] = ItemCheckpoint(
                    state: .migrated, productID: product.id,
                    detail: "已有同商品记录（幂等护栏命中）", updatedAt: Date())
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
                    checkpoints[treasuredID] = ItemCheckpoint(
                        state: .pending, productID: product.id,
                        detail: "商品可解析但草稿构建失败（价格/资料缺失）",
                        updatedAt: Date())
                    continue
                }
                _ = try ShopCatalogWardrobeInserter.insert(
                    draft: draft,
                    selection: .init(productID: product.id, priceMode: .wishlist),
                    store: store,
                    modelContext: modelContext
                )
                report.createdCount += 1
                checkpoints[treasuredID] = ItemCheckpoint(
                    state: .migrated, productID: product.id, detail: nil, updatedAt: Date())
            } catch {
                // 单条失败不中断整轮；该收藏留在旧馆归档（treasured.v1 不动）
                report.matched[treasuredID] = nil
                report.unmatched.append(treasuredID)
                report.failedCount += 1
                checkpoints[treasuredID] = ItemCheckpoint(
                    state: .failed, productID: product.id,
                    detail: error.localizedDescription, updatedAt: Date())
            }
        }

        saveCheckpoints(checkpoints, defaults)
        // 完成 ≠ 跑过一轮：还有 pending / failed 时下轮继续补迁
        report.isComplete = report.unmatched.isEmpty && report.failedCount == 0
        saveMarker(checkpoints: checkpoints, isComplete: report.isComplete, defaults: defaults)
        return report
    }

    /// 写本轮标记。**标记必须反映最近一次 `run` 的结果**，而不是只在自动入口写——
    /// 否则手动重放（运营/排障入口）跑完后标记仍是旧值，导致误判进度。
    private static func saveMarker(checkpoints: [String: ItemCheckpoint],
                                   isComplete: Bool,
                                   defaults: UserDefaults) {
        let pending = checkpoints.values.filter {
            $0.state == .pending || $0.state == .failed
        }.count
        let marker = RunMarker(
            lastRunAt: Date(),
            completed: isComplete,
            total: checkpoints.count,
            migrated: checkpoints.values.filter { $0.state == .migrated }.count,
            pending: pending)
        guard let data = try? JSONEncoder().encode(marker) else { return }
        defaults.set(data, forKey: markerKey)
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
        guard !productID.isEmpty else { return false }
        var descriptor = FetchDescriptor<Clothing>(
            predicate: #Predicate { $0.catalogProductID == productID && $0.isDeleted == false }
        )
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetch(descriptor))?.isEmpty == false)
    }
}
