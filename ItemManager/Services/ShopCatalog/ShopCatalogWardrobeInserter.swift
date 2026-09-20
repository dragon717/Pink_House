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

    enum PriceMode {
        /// 现货价（或无记录时的兜底价）→ 已拥有
        case stock
        /// 预约价（定金 + 尾款）→ 心愿尾款
        case reservation(depositPaid: Decimal)
        /// 仅心愿：未付任何款项，全部记为待付尾款
        case wishlist
    }

    struct Selection {
        let productID: String
        var color: String? = nil
        var size: String? = nil
        var priceMode: PriceMode = .stock
    }

    /// 单件草稿。失败（查不到商品）返回 nil。
    static func makeDraft(
        selection: Selection,
        store: ShopCatalogStore,
        modelContext: ModelContext
    ) -> ClothingEditDraft? {
        guard let product = store.product(id: selection.productID) else { return nil }
        let series = store.series(id: product.seriesID)
        let shop = store.shop(id: product.shopID)

        var noteLines: [String] = []
        if let series { noteLines.append("系列：\(series.name)") }
        if let year = series?.year { noteLines.append("年份：\(String(year))") }

        // 价格口径（计划 §13/§16/§17）：预约 → 定金尾款；心愿 → 全记待付尾款；现货 → 总价。
        var depositAmount: Decimal = 0
        var balanceAmount: Decimal = 0
        var totalAmount: Decimal = 0
        var isDepositPlan = false
        var finalPaymentStart: Date = Date()
        var finalPaymentEnd: Date = Date()
        var saleEventID: String? = nil

        switch selection.priceMode {
        case .stock:
            let archive = store.priceArchive(forProduct: product.id)
            totalAmount = archive.currentStockPrice
                ?? archive.historicalReservationPrice ?? 0
        case .reservation(let depositPaid):
            let archive = store.priceArchive(forProduct: product.id)
            guard let event = archive.reservation else { return nil }
            depositAmount = max(0, min(depositPaid, event.price))
            balanceAmount = event.price - depositAmount
            totalAmount = event.price
            isDepositPlan = true
            saleEventID = event.id
            // 尾款窗口（§17）：预约结束 = 尾款开始；结束未公布 → 待公布（用开始时间占位）
            finalPaymentStart = event.endAt ?? Date()
            finalPaymentEnd = finalPaymentStart
        case .wishlist:
            let archive = store.priceArchive(forProduct: product.id)
            totalAmount = archive.currentStockPrice
                ?? archive.historicalReservationPrice ?? 0
            balanceAmount = totalAmount
            isDepositPlan = true
        }

        if isDepositPlan {
            noteLines.append("价格口径：定金 ¥\(depositAmount) + 尾款 ¥\(balanceAmount) = ¥\(totalAmount)")
        }

        let colors = [selection.color].compactMap { $0 }.joined(separator: "、")
        let sizes = [selection.size].compactMap { $0 }.joined(separator: "、")

        let draft = ClothingEditDraft(
            name: product.name,
            brandName: shop?.name ?? "",
            types: product.category,
            colors: colors,
            sizes: sizes,
            length: "",
            condition: "全新",
            accessories: "",
            imagePaths: [],
            isShared: false,
            originalPrice: NSDecimalNumber(decimal: totalAmount).doubleValue,
            originalPriceJPY: 0,
            originalPriceCurrencyCode: ClothingPriceCurrency.cny.rawValue,
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
            note: noteLines.joined(separator: "\n"),
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
        modelContext: ModelContext
    ) throws -> [(draft: ClothingEditDraft, selection: Selection)] {
        guard !selections.isEmpty else {
            throw ShopCatalogWardrobeError.emptySelection
        }

        var built: [(selection: Selection, draft: ClothingEditDraft, product: CatalogProduct)] = []
        for selection in selections {
            guard let product = store.product(id: selection.productID),
                  let draft = makeDraft(selection: selection, store: store, modelContext: modelContext)
            else { throw ShopCatalogWardrobeError.productNotFound(selection.productID) }
            built.append((selection, draft, product))
        }

        let accessorySet = accessoryProductIDs
        // 主衣物 = 分类可作主、且未被用户勾为小物的勾选项（§23：主衣物决定主类型）
        let primaryEntries = built.filter {
            ShopCatalogWardrobeCategory.isPrimary($0.product.category) && !accessorySet.contains($0.product.id)
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

        // 至少要有一个主条目；全被勾成小物时回退第一条为主
        let entryHeads: [(selection: Selection, draft: ClothingEditDraft, product: CatalogProduct)] =
            primaryEntries.isEmpty ? [built[0]] : primaryEntries

        func accessoryPriceLine(_ product: CatalogProduct) -> String {
            let archive = store.priceArchive(forProduct: product.id)
            let price = archive.currentStockPrice ?? archive.historicalReservationPrice
            return price.map { "¥\(NSDecimalNumber(decimal: $0).stringValue)" } ?? "价格未填"
        }

        return entryHeads.enumerated().map { index, head in
            guard index == 0 else { return (draft: head.draft, selection: head.selection) }

            // 小物只挂第一条主衣物记录（§23 示例：JSK + KC / OP 各一条）
            let names = accessoryEntries.map { $0.product.name }
            let accessoryPriceTotal = accessoryEntries.reduce(Decimal(0)) { sum, item in
                let archive = store.priceArchive(forProduct: item.product.id)
                return sum + (archive.currentStockPrice ?? archive.historicalReservationPrice ?? 0)
            }
            var noteLines = head.draft.note.components(separatedBy: "\n")
            for item in accessoryEntries {
                noteLines.append("小物：\(item.product.name)（\(accessoryPriceLine(item.product))）")
            }

            let accessoryTotalDouble = NSDecimalNumber(decimal: accessoryPriceTotal).doubleValue
            // 预约套装：小物价计入尾款（§24 尾款多件写入）
            let mergedBalance = head.draft.isDepositPlan
                ? head.draft.balance + accessoryTotalDouble
                : head.draft.balance
            let mergedName = names.isEmpty
                ? head.draft.name
                : "\(head.product.name)＋\(names.joined(separator: "＋"))（套装）"

            // ClothingEditDraft 全 let + 显式 init：用复制重建生成合并后的草稿
            let merged = head.draft.with(
                name: mergedName,
                accessories: names.joined(separator: "、"), // §21 写入现有「小物」栏
                accessoriesPrice: accessoryTotalDouble,
                priceTotal: head.draft.priceTotal + accessoryTotalDouble,
                balance: mergedBalance,
                note: noteLines.joined(separator: "\n")
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
        accessories: String? = nil,
        accessoriesPrice: Double? = nil,
        priceTotal: Double? = nil,
        balance: Double? = nil,
        note: String? = nil,
        finalPaymentDate: Date? = nil,
        finalPaymentEndDate: Date? = nil
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
            imagePaths: imagePaths,
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
            selectedTags: selectedTags
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
        let clothing = try TimeHallWardrobeQuickInserter.insert(draft: draft, modelContext: modelContext)
        if let selection, let product = store.product(id: selection.productID) {
            clothing.catalogProductID = product.id
            if let color = selection.color, let size = selection.size {
                clothing.catalogVariantID = store.variants(forProduct: product.id).first {
                    $0.color == color && $0.size == size
                }?.id
            }
            if case .reservation = selection.priceMode {
                clothing.catalogSaleEventID = store.priceArchive(forProduct: product.id).reservation?.id
            }
        }
        try? modelContext.save()
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
        modelContext: ModelContext
    ) throws -> [Clothing] {
        var inserted: [Clothing] = []
        for (index, entry) in drafts.enumerated() {
            let clothing = try insert(draft: entry.draft, selection: entry.selection, store: store, modelContext: modelContext)
            if index == 0, !accessoryProductIDs.isEmpty {
                persistAccessoryItems(
                    accessoryProductIDs: accessoryProductIDs,
                    onto: clothing,
                    store: store
                )
            }
            inserted.append(clothing)
        }
        try? modelContext.save()
        return inserted
    }

    /// 把勾选的小物按 Catalog 价格档案写成 `AccessoryItem`（§21：单价可空时记 0，
    /// 名称缺失时用商品名；定金/尾款仅在预约记录上拆分展示）。
    private static func persistAccessoryItems(
        accessoryProductIDs: Set<String>,
        onto clothing: Clothing,
        store: ShopCatalogStore
    ) {
        var sortIndex = 0
        for productID in accessoryProductIDs.sorted() {
            guard let product = store.product(id: productID) else { continue }
            let archive = store.priceArchive(forProduct: productID)
            let price = archive.currentStockPrice ?? archive.historicalReservationPrice ?? 0
            let isReservation = clothing.isDepositPlan
            let item = AccessoryItem(
                name: product.name,
                price: price,
                deposit: isReservation ? (archive.reservation?.deposit ?? 0) : 0,
                balance: isReservation ? max(0, price - (archive.reservation?.deposit ?? 0)) : 0,
                sortIndex: sortIndex
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
    case multiplePrimaries([String])
    /// §23：主衣物（JSK/OP/SK/Blouse）不能被勾为小物
    case primaryMarkedAsAccessory([String])

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "尚未选择任何商品"
        case .productNotFound(let id):
            return "商品不存在或已被下架（\(id)）"
        case .multiplePrimaries(let names):
            // 计划 §23：多主衣物需用户先取消多余主衣物
            return "一次只能加入一件主衣物，当前选中了多件：\(names.joined(separator: "、"))。请取消多余的 JSK/OP/SK/Blouse 后重试。"
        case .primaryMarkedAsAccessory(let names):
            return "主衣物不能勾选为小物：\(names.joined(separator: "、"))。主衣物会各自生成一条衣橱记录。"
        }
    }
}
