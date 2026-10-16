//
//  ShopCatalogWardrobeInserter.swift
//  ItemManager
//
//  「店家上新」→ 现有衣橱 / 心愿尾款 的联动层（Phase 4 + Phase 5）。
//
//  需求来源：docs/少女心愿_店家上新_第一版落地计划.md
//    - §12 系列页多选加入衣橱（P0）：主衣物 + 小物合并为一条记录
//    - §16 加入心愿：直接进入现有心愿系统，Catalog 只提供资料
//    - §17 我已经预约 → 心愿尾款：记录总价/定金/待付尾款/尾款时间
//    - §18 尾款状态严格沿用现有逻辑（不做发货/收货）
//    - §19-24 WardrobeEntry：primaryItem 决定主类型，小物写入现有「小物」栏
//
//  设计约束（计划 §34 约束 5）：不重新实现心愿、尾款、衣橱——
//  全部走既有 `ClothingEditDraft` + `TimeHallWardrobeQuickInserter` 管线
//  （与 MidsummerWardrobeInsertion 同构），只在落库后补写 Catalog 引用字段。
//

import Foundation
import SwiftData
import UIKit

// MARK: - 主衣物 / 小物分类判定（计划 §19-20）

nonisolated enum ShopCatalogWardrobeCategory {
    /// 可作主衣物（primaryItem）的分类：决定衣橱记录的主类型
    static let primaryCategories: Set<String> = ["JSK", "OP", "SK", "Blouse"]
    /// 其余分类（KC / 小物 / 鞋 / 包 / 其他）一律写入「小物」栏

    static func isPrimary(_ category: String) -> Bool {
        primaryCategories.contains(category)
    }
}

// MARK: - 草稿构建

@MainActor
enum ShopCatalogWardrobeDraftBuilder {

    enum PriceMode: Equatable {
        /// 现货价（或无记录时的兜底价）→ 已拥有
        case stock
        /// 预约价（定金 + 尾款）→ 心愿尾款
        case reservation(depositPaid: Decimal)
        /// 全款（预约价）→ 已全款：金额 = 后台预约价（定金 + 尾款总和），
        /// **绝不生成**任何心愿尾款任务（2026-09-23 需求 N §II 场景一 / 场景二分支 B）
        case fullReservation
        /// 全款（现货价）→ 同样「已全款」（2026-09-24 需求：现货阶段两个价格口径）：
        /// 金额 = 后台现货价，`balance = 0`、`isDepositPlan = true`
        /// （复用同一套「已付清」存储口径 → 卡片标签「全款」、`pendingFinalPaymentAmount == 0`），
        /// 与 `.fullReservation` **只差入橱金额取自哪份价格档案**，都**不生成**尾款任务。
        case fullStock
        /// 仅心愿：未付任何款项，全部记为待付尾款
        case wishlist
    }

    struct Selection {
        let productID: String
        var color: String? = nil
        var size: String? = nil
        var priceMode: PriceMode = .stock
        var reservationBatchID: String? = nil
        var hasCustomFinalPaymentDate = false
    }

    /// 单件草稿。失败（查不到商品）返回 nil。
    static func makeDraft(
        selection: Selection,
        store: ShopCatalogStore
    ) -> ClothingEditDraft? {
        guard let product = store.product(id: selection.productID) else { return nil }
        let series = store.seriesForPurchase(id: product.seriesID)
        let schedule = series?.paymentSchedule(batchID: selection.reservationBatchID)
        if !(series?.reservationBatches ?? []).isEmpty, schedule == nil {
            switch selection.priceMode {
            case .wishlist: break
            default: return nil
            }
        }
        let shop = store.shop(id: product.shopID)

        // 价格口径（计划 §13/§16/§17）：预约 → 定金尾款；心愿 → 全记待付尾款；现货 → 总价。
        var depositAmount: Decimal = 0
        var balanceAmount: Decimal = 0
        var totalAmount: Decimal = 0
        var isDepositPlan = false
        var finalPaymentStart: Date = Date()
        var finalPaymentEnd: Date = Date()

        // 币种（R02）：整条记录统一用商品的生效币种，日元不按人民币入库。
        let archive = store.priceArchive(forProduct: product.id)
        let currency: CatalogCurrency = archive.currentCurrency ?? .unknown

        switch selection.priceMode {
        case .stock:
            totalAmount = archive.currentStockPrice
                ?? archive.historicalReservationPrice ?? 0
        case .reservation(let depositPaid):
            guard let event = archive.reservation else { return nil }
            depositAmount = max(0, min(depositPaid, event.price))
            // 待补尾款（2026-09-23 需求 N §II 修正）：**读后台录入的「尾款」**，
            // 后台没录才退回「预约价 − 已付定金」。口径唯一来源 `ShopCatalogWardrobeAmount`，
            // 与加购弹窗的只读预览共用（弹窗显示多少，心愿尾款就写多少）。
            balanceAmount = ShopCatalogWardrobeAmount.pendingBalance(
                backendBalance: archive.currentBalance,
                reservationPrice: event.price,
                depositPaid: depositAmount
            )
            totalAmount = event.price
            isDepositPlan = true
            // 尾款窗口（§17）：预约结束 = 尾款开始；结束未公布 → 待公布（用开始时间占位）
            finalPaymentStart = event.endAt ?? Date()
            finalPaymentEnd = finalPaymentStart
        case .fullReservation:
            // 全款（预约价）：金额一律取后台预约价（= 定金 + 尾款总和），用户不输入。
            // 记为「已付定 + 尾款 0」→ `isFullPaymentReservation` → 卡片标签「全款」，
            // 且 `pendingFinalPaymentAmount == 0` → 心愿尾款里不会留下待补任务。
            guard let event = archive.reservation else { return nil }
            depositAmount = event.price
            balanceAmount = 0
            totalAmount = event.price
            isDepositPlan = true
            finalPaymentStart = event.endAt ?? Date()
            finalPaymentEnd = finalPaymentStart
        case .fullStock:
            // 全款（现货价，2026-09-24 需求：现货阶段两个价格口径）：
            // 金额一律取后台**现货价**，用户不输入；存储口径与 `.fullReservation` 一致
            // （deposit = 总额、balance = 0、isDepositPlan = true）→ 同样记为「已全款」、
            // 同样**绝不生成**心愿尾款任务 —— 两者只差金额来源。
            guard let price = archive.currentStockPrice else { return nil }
            depositAmount = price
            balanceAmount = 0
            totalAmount = price
            isDepositPlan = true
            // 现货全款不挂预约窗口：没有「尾款时间」可言，保持默认（不生成任务）
            finalPaymentStart = Date()
            finalPaymentEnd = finalPaymentStart
        case .wishlist:
            totalAmount = archive.currentStockPrice
                ?? archive.historicalReservationPrice ?? 0
            balanceAmount = totalAmount
            isDepositPlan = true
        }

        // 尾款窗口来源（2026-09-25 需求二/三）：运营已声明尾款期 → 用户记录以声明为准；
        // 大致描述（上旬/中旬/中下旬/下旬）→ 以「约一个月」为基准估算成**固定具体日期**
        //（锚点是运营侧事实：系列预约结束时间 → 预约销售记录结束时间，绝不用加购当天）。
        // 窗口解法唯一口径 `CatalogBalanceDueApproximation.declaredWindow`（与同步共用）。
        // 全款（balance == 0）不生成尾款任务，窗口无意义，不在此改。
        // 备注留给用户，来源说明在确认页展示。完全无声明 → 维持旧行为（预约结束 = 尾款开始；结束未公布用开始时间占位）。
        if isDepositPlan, balanceAmount > 0, let schedule {
            let anchor = schedule.reservationEndAt ?? archive.reservation?.endAt
            if let window = CatalogBalanceDueApproximation.declaredWindow(of: schedule, anchor: anchor),
               window.start != finalPaymentStart || window.end != finalPaymentEnd {
                finalPaymentStart = window.start
                finalPaymentEnd = window.end
            }
        }

        // 记录名（需求 N §III.1）：`[系列名] + [款式名] + [颜色]`，缺失项按 §III.2 降级。
        // 颜色优先用户选定色、其次后台规格色 —— 保证「同名不同色」在衣橱里能一眼区分；
        // 纯配饰（无规格色也无颜色词）→ 自动降级为 `[系列名] + [款式名]`。
        let resolvedColor = ShopCatalogWardrobeTitle.resolvedColor(
            explicit: selection.color,
            specColors: store.colors(forProduct: product.id),
            productName: product.name
        )
        let recordName = ShopCatalogWardrobeTitle.recordName(
            product: product,
            seriesName: series?.name,
            color: resolvedColor
        )
        let colors = resolvedColor ?? ""
        let sizes = [selection.size].compactMap { $0 }.joined(separator: "、")

        let draft = ClothingEditDraft(
            name: recordName,
            brandName: shop?.name ?? "",
            types: product.category,
            colors: colors,
            sizes: sizes,
            length: "",
            condition: "全新",
            accessories: "",
            // 草稿只组装资料；确认入库时异步下载并保存商品图片。
            imagePaths: [],
            isShared: false,
            // R02：金额写进**币种对应**的字段。日元进 originalPriceJPY 并标 JPY，
            // 不写进「人民币原价」——否则 24800 日元会变成 24800 元人民币。
            originalPrice: currency == .jpy ? 0 : NSDecimalNumber(decimal: totalAmount).doubleValue,
            originalPriceJPY: currency == .jpy ? NSDecimalNumber(decimal: totalAmount).doubleValue : 0,
            originalPriceCurrencyCode: currency.clothingCurrencyCode,
            priceTotal: NSDecimalNumber(decimal: totalAmount).doubleValue,
            deposit: NSDecimalNumber(decimal: depositAmount).doubleValue,
            balance: NSDecimalNumber(decimal: balanceAmount).doubleValue,
            accessoriesPrice: 0,
            stock: 1,
            purchaseDate: Date(),
            depositDate: Date(),
            isDepositPlan: isDepositPlan,
            reservationKindRawValue: ClothingReservationKind.owned.rawValue,
            finalPaymentDate: finalPaymentStart,
            finalPaymentEndDate: finalPaymentEnd,
            note: "",
            accessoryList: [],
            sizeChartImagePath: nil
        )
        return draft
    }

    /// 系列页多选 → 按计划 §19-24 生成草稿组：
    ///   · 每件主衣物（JSK/OP/SK/Blouse）各自成为一条衣橱记录（§23：拆成多条，
    ///     不能把 OP 当小物）；无主衣物时以第一件为主。
    ///   · 小物（§12 参考图6：用户在确认页勾选）全部挂到第一条主衣物记录，
    ///     名称写入现有「小物」栏，并生成 AccessoryItem 记录（§21 小物明细：
    ///     每小物名称+价格，可选定金/尾款，单价可空）。
    static func makeSplitDrafts(
        selections: [Selection],
        accessoryProductIDs: Set<String>,
        store: ShopCatalogStore,
        primaryProductID: String? = nil
    ) throws -> [(draft: ClothingEditDraft, selection: Selection)] {
        guard !selections.isEmpty else {
            throw ShopCatalogWardrobeError.emptySelection
        }

        var built: [(selection: Selection, draft: ClothingEditDraft, product: CatalogProduct)] = []
        for selection in selections {
            guard let product = store.product(id: selection.productID),
                  let draft = makeDraft(selection: selection, store: store)
            else { throw ShopCatalogWardrobeError.productNotFound(selection.productID) }
            built.append((selection, draft, product))
        }

        let accessorySet = accessoryProductIDs
        // 主衣物 = 分类可作主、且未被用户勾为小物的勾选项（§23：主衣物决定主类型）
        var primaryEntries = built.filter {
            ShopCatalogWardrobeCategory.isPrimary($0.product.category) && !accessorySet.contains($0.product.id)
        }
        if let index = primaryEntries.firstIndex(where: { $0.product.id == primaryProductID }) {
            primaryEntries.insert(primaryEntries.remove(at: index), at: 0)
        }
        // §23「不能把 OP 当小物」：主衣物分类被勾为小物属于非法勾选，
        // 必须显式报错而不是静默丢弃（否则该商品会凭空消失）。
        let illegalAccessories = built.filter {
            ShopCatalogWardrobeCategory.isPrimary($0.product.category) && accessorySet.contains($0.product.id)
        }
        if !illegalAccessories.isEmpty {
            throw ShopCatalogWardrobeError.primaryMarkedAsAccessory(
                illegalAccessories.map(\.product.name))
        }
        let accessoryEntries = built.filter {
            !ShopCatalogWardrobeCategory.isPrimary($0.product.category) && accessorySet.contains($0.product.id)
        }

        // 单独入橱小物时，以确认页选定的商品作为主条目。
        let entryHeads: [(selection: Selection, draft: ClothingEditDraft, product: CatalogProduct)] =
            primaryEntries.isEmpty
                ? [built.first { $0.product.id == primaryProductID } ?? built[0]] : primaryEntries

        /// 主衣物的币种：小物只与同币种的主衣物合并计价（§7.5：跨币种不直接合计）
        let headCurrency = entryHeads.first.map {
            store.priceArchive(forProduct: $0.product.id).currentCurrency
        } ?? nil

        /// 与主衣物同币种的小物才可计入合计；跨币种小物单独列出，不参与加总
        func isSameCurrencyAsHead(_ product: CatalogProduct) -> Bool {
            guard let headCurrency, !headCurrency.isUnknown else { return true }
            let c = store.priceArchive(forProduct: product.id).currentCurrency
            return c == nil || c == headCurrency
        }

        return entryHeads.enumerated().map { index, head in
            guard index == 0 else { return (draft: head.draft, selection: head.selection) }

            // 小物只挂第一条主衣物记录（§23 示例：JSK + KC / OP 各一条）
            let names = accessoryEntries.map { $0.product.name }
            let accessoryPriceTotal = accessoryEntries.reduce(Decimal(0)) { sum, item in
                guard isSameCurrencyAsHead(item.product) else { return sum }
                let archive = store.priceArchive(forProduct: item.product.id)
                return sum + (archive.currentStockPrice ?? archive.historicalReservationPrice ?? 0)
            }
            let accessoryTotalDouble = NSDecimalNumber(decimal: accessoryPriceTotal).doubleValue
            // 预约套装：小物价计入尾款（§24 尾款多件写入）
            let mergedBalance = head.draft.isDepositPlan
                ? head.draft.balance + accessoryTotalDouble
                : head.draft.balance
            let mergedName = names.isEmpty
                ? head.draft.name
                : "\(head.draft.name)＋\(names.joined(separator: "＋"))（套装）"

            // ClothingEditDraft 全 let + 显式 init：用复制重建生成合并后的草稿
            let merged = head.draft.with(
                name: mergedName,
                accessories: names.joined(separator: "、"), // §21 写入现有「小物」栏
                accessoriesPrice: accessoryTotalDouble,
                priceTotal: head.draft.priceTotal + accessoryTotalDouble,
                balance: mergedBalance
            )
            return (draft: merged, selection: head.selection)
        }
    }
}

// MARK: - 草稿复制重建

/// `ClothingEditDraft` 的属性全部为 `let`（显式 init，属现有衣橱底层，不改）。
/// 店家上新套装合并 / 预约改尾款时间需要「改若干字段」的语义，这里以复制重建实现。
extension ClothingEditDraft {
    func with(
        name: String? = nil,
        imagePaths: [String]? = nil,
        accessories: String? = nil,
        accessoriesPrice: Double? = nil,
        priceTotal: Double? = nil,
        balance: Double? = nil,
        note: String? = nil,
        finalPaymentDate: Date? = nil,
        finalPaymentEndDate: Date? = nil,
        isResaleTransfer: Bool? = nil
    ) -> ClothingEditDraft {
        ClothingEditDraft(
            id: id,
            name: name ?? self.name,
            brandName: brandName,
            types: types,
            colors: colors,
            sizes: sizes,
            length: length,
            condition: condition,
            accessories: accessories ?? self.accessories,
            imagePaths: imagePaths ?? self.imagePaths,
            isShared: isShared,
            originalPrice: originalPrice,
            originalPriceJPY: originalPriceJPY,
            originalPriceCurrencyCode: originalPriceCurrencyCode,
            originalPriceExchangeRateJPY: originalPriceExchangeRateJPY,
            originalPriceRateUpdatedAt: originalPriceRateUpdatedAt,
            priceTotal: priceTotal ?? self.priceTotal,
            deposit: deposit,
            balance: balance ?? self.balance,
            accessoriesPrice: accessoriesPrice ?? self.accessoriesPrice,
            shippingFee: shippingFee,
            shippingFeeJPY: shippingFeeJPY,
            shippingFeeCurrencyCode: shippingFeeCurrencyCode,
            shippingExchangeRateJPY: shippingExchangeRateJPY,
            shippingRateUpdatedAt: shippingRateUpdatedAt,
            stock: stock,
            purchaseDate: purchaseDate,
            depositDate: depositDate,
            isDepositPlan: isDepositPlan,
            reservationKindRawValue: reservationKindRawValue,
            finalPaymentDate: finalPaymentDate ?? self.finalPaymentDate,
            finalPaymentEndDate: finalPaymentEndDate ?? self.finalPaymentEndDate,
            note: note ?? self.note,
            accessoryList: accessoryList,
            sizeChartImagePath: sizeChartImagePath,
            priceChartImagePath: priceChartImagePath,
            selectedTags: selectedTags,
            isResaleTransfer: isResaleTransfer ?? self.isResaleTransfer
        )
    }
}

// MARK: - 落库

@MainActor
enum ShopCatalogWardrobeInserter {

    /// 一键入库：复用现有 QuickInserter 管线，落库后补写 Catalog 引用字段
    /// （Clothing.catalogProductID / catalogVariantID / catalogSaleEventID，计划 §4）。
    @discardableResult
    static func insert(
        draft: ClothingEditDraft,
        selection: ShopCatalogWardrobeDraftBuilder.Selection? = nil,
        store: ShopCatalogStore,
        modelContext: ModelContext
    ) throws -> Clothing {
        if let selection, selection.priceMode != .wishlist,
           let product = store.product(id: selection.productID),
           let series = store.seriesForPurchase(id: product.seriesID),
           !(series.reservationBatches ?? []).isEmpty,
           series.reservationBatch(id: selection.reservationBatchID) == nil {
            throw ShopCatalogWardrobeError.reservationBatchRequired(series.name)
        }
        let clothing = try TimeHallWardrobeQuickInserter.insert(draft: draft, modelContext: modelContext)
        if let selection, let product = store.product(id: selection.productID) {
            clothing.catalogProductID = product.id
            clothing.catalogReservationBatchID = store.seriesForPurchase(id: product.seriesID)?
                .reservationBatch(id: selection.reservationBatchID)?.id
            // 已分团但该团尚未公布时间：不把预约结束日或加购当天冒充尾款日。
            if let series = store.seriesForPurchase(id: product.seriesID),
               !(series.reservationBatches ?? []).isEmpty,
               !selection.hasCustomFinalPaymentDate,
               let schedule = series.paymentSchedule(batchID: selection.reservationBatchID),
               CatalogBalanceDueApproximation.declaredWindow(
                   of: schedule, anchor: schedule.reservationEndAt
                       ?? store.priceArchive(forProduct: product.id).reservation?.endAt) == nil {
                clothing.finalPaymentDate = nil
                clothing.finalPaymentEndDate = nil
            }
            if let color = selection.color, let size = selection.size {
                clothing.catalogVariantID = store.variants(forProduct: product.id).first {
                    $0.color == color && $0.size == size
                }?.id
            }
            // 回写「这条记录依据哪份销售记录生成」（计划 §4）：预约口径两个分支都指向预约记录，
            // 现货价全款指向现货记录 —— 不写回就只能靠金额反推，事后对不上账。
            let archive = store.priceArchive(forProduct: product.id)
            switch selection.priceMode {
            case .reservation, .fullReservation:
                clothing.catalogSaleEventID = archive.reservation?.id
            case .fullStock:
                clothing.catalogSaleEventID = archive.stock?.id
            case .stock, .wishlist:
                break
            }
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(clothing)
            try? modelContext.save()
            throw error
        }
        return clothing
    }

    /// 套装批量入库（§12 系列多选 / §23 拆分建议确认后调用）：
    /// 逐条落库并补引用字段；第一条主衣物记录额外生成 `AccessoryItem` 明细
    /// （§21：现有衣橱详情「小物明细」直接读取该记录展示名称+价格+定金/尾款）。
    @discardableResult
    static func insertSet(
        drafts: [(draft: ClothingEditDraft, selection: ShopCatalogWardrobeDraftBuilder.Selection?)],
        accessoryProductIDs: Set<String>,
        store: ShopCatalogStore,
        modelContext: ModelContext,
        accessoryImagePaths: [String: [String]] = [:]
    ) throws -> [Clothing] {
        var inserted: [Clothing] = []
        do {
            for (index, entry) in drafts.enumerated() {
                let clothing = try insert(draft: entry.draft, selection: entry.selection, store: store, modelContext: modelContext)
                inserted.append(clothing)
                if index == 0, !accessoryProductIDs.isEmpty {
                    persistAccessoryItems(
                        accessoryProductIDs: accessoryProductIDs,
                        onto: clothing,
                        store: store,
                        imagePaths: accessoryImagePaths
                    )
                }
            }
            try modelContext.save()
            return inserted
        } catch {
            // 图片层会释放本次取得的引用；不能留下仍引用这些图片的半套入橱记录。
            for clothing in inserted { modelContext.delete(clothing) }
            try? modelContext.save()
            throw error
        }
    }

    /// 把勾选的小物按 Catalog 价格档案写成 `AccessoryItem`（§21：单价可空时记 0，
    /// 名称缺失时用商品名；定金/尾款仅在预约记录上拆分展示）。
    private static func persistAccessoryItems(
        accessoryProductIDs: Set<String>,
        onto clothing: Clothing,
        store: ShopCatalogStore,
        imagePaths: [String: [String]]
    ) {
        let headCurrency = clothing.originalPriceCurrencyCode
        var sortIndex = 0
        for productID in accessoryProductIDs.sorted() {
            guard let product = store.product(id: productID) else { continue }
            let archive = store.priceArchive(forProduct: productID)
            let price = archive.currentStockPrice ?? archive.historicalReservationPrice ?? 0
            let currency = archive.currentCurrency ?? .unknown
            let isReservation = clothing.isDepositPlan
            // `AccessoryItem` 只有金额没有币种字段。小物与主衣物币种不同时，
            // 把金额写进名称并置 price = 0 —— 宁可少一个可合计的数字，
            // 也不能把 24800 日元当成 24800 元记进个人账（§7.5 不隐式换汇）。
            let sameCurrency = currency.clothingCurrencyCode == headCurrency
            let name = sameCurrency
                ? product.name
                : "\(product.name)（\(currency.symbol)\(NSDecimalNumber(decimal: price).stringValue)，\(currency.displayName)）"
            let item = AccessoryItem(
                name: name,
                price: sameCurrency ? price : 0,
                deposit: isReservation ? (archive.reservation?.deposit ?? 0) : 0,
                balance: isReservation ? max(0, price - (archive.reservation?.deposit ?? 0)) : 0,
                sortIndex: sortIndex,
                imagePaths: imagePaths[productID] ?? []
            )
            modelContextInsert(item, clothing: clothing)
            sortIndex += 1
        }
    }

    private static func modelContextInsert(_ item: AccessoryItem, clothing: Clothing) {
        item.clothing = clothing
        if clothing.accessoryItems == nil { clothing.accessoryItems = [] }
        clothing.accessoryItems?.append(item)
    }
}

// MARK: - 错误

nonisolated enum ShopCatalogWardrobeError: LocalizedError {
    case emptySelection
    case productNotFound(String)
    case reservationBatchRequired(String)
    case multiplePrimaries([String])
    /// §23：主衣物（JSK/OP/SK/Blouse）不能被勾为小物
    case primaryMarkedAsAccessory([String])

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "尚未选择任何商品"
        case .productNotFound(let id):
            return "商品不存在或已被下架（\(id)）"
        case .reservationBatchRequired(let series):
            return "请选择「\(series)」的购买团次"
        case .multiplePrimaries(let names):
            // 计划 §23：多主衣物需用户先取消多余主衣物
            return "一次只能加入一件主衣物，当前选中了多件：\(names.joined(separator: "、"))。请取消多余的 JSK/OP/SK/Blouse 后重试。"
        case .primaryMarkedAsAccessory(let names):
            return "主衣物不能勾选为小物：\(names.joined(separator: "、"))。主衣物会各自生成一条衣橱记录。"
        }
    }
}
