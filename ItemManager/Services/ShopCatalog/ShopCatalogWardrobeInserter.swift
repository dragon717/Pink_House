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

    enum PriceMode {
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
        if let yearMonth = series?.yearMonthText { noteLines.append("年月：\(yearMonth)") }

        // 价格口径（计划 §13/§16/§17）：预约 → 定金尾款；心愿 → 全记待付尾款；现货 → 总价。
        var depositAmount: Decimal = 0
        var balanceAmount: Decimal = 0
        var totalAmount: Decimal = 0
        var isDepositPlan = false
        var finalPaymentStart: Date = Date()
        var finalPaymentEnd: Date = Date()
        var saleEventID: String? = nil
        /// 全款口径的价格来源（预约价 / 现货价）：只用来在备注里写清「这个全款是按哪个价记的」
        var fullPriceBasisText: String? = nil

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
            saleEventID = event.id
            // 后台三价不自洽时不静默：如实留痕，说明尾款取了哪个数
            if ShopCatalogWardrobeAmount.isBackendPriceInconsistent(
                deposit: event.deposit,
                balance: archive.currentBalance,
                reservationPrice: event.price
            ) {
                let symbol = currency.symbol
                noteLines.append(
                    "后台三价不自洽：定金 \(symbol)\(NSDecimalNumber(decimal: event.deposit ?? 0).stringValue)"
                    + " + 尾款 \(symbol)\(NSDecimalNumber(decimal: archive.currentBalance ?? 0).stringValue)"
                    + " ≠ 预约价 \(symbol)\(NSDecimalNumber(decimal: event.price).stringValue)"
                    + "；待补尾款按「录入的尾款」记账"
                )
            }
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
            saleEventID = event.id
            fullPriceBasisText = "按预约价"
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
            saleEventID = archive.stock?.id
            fullPriceBasisText = "按现货价"
            // 现货全款不挂预约窗口：没有「尾款时间」可言，保持默认（不生成任务）
            finalPaymentStart = Date()
            finalPaymentEnd = finalPaymentStart
        case .wishlist:
            totalAmount = archive.currentStockPrice
                ?? archive.historicalReservationPrice ?? 0
            balanceAmount = totalAmount
            isDepositPlan = true
        }

        // 金额与币种一起留痕：个人记录事后要能回答「这笔钱是什么币」
        if currency.isUnknown {
            noteLines.append("币种待确认（来源未标注币种；金额按原值记录，未做换算）")
        } else if currency != .cny {
            noteLines.append("原始币种：\(currency.displayName)（\(currency.symbol)\(NSDecimalNumber(decimal: totalAmount).stringValue)，未做换算）")
        }

        if isDepositPlan {
            let symbol = currency.symbol
            func money(_ value: Decimal) -> String {
                "\(symbol)\(NSDecimalNumber(decimal: value).stringValue)"
            }
            if balanceAmount == 0 {
                // 全款：已付清，心愿尾款里不会留下待补任务（需求 N §II）。
                // 现货阶段的「全款」有两个价格口径，必须写清按哪个价记的，
                // 否则事后无法从备注分辨这一笔到底按预约价还是现货价入的橱。
                let basisText = fullPriceBasisText.map { "\($0)，" } ?? ""
                noteLines.append("价格口径：全款 \(money(totalAmount))（\(basisText)已付清，不生成尾款任务）")
            } else if depositAmount + balanceAmount == totalAmount {
                noteLines.append("价格口径：定金 \(money(depositAmount)) + 尾款 \(money(balanceAmount)) = \(money(totalAmount))")
            } else {
                // 后台三价不自洽：不能写「A + B = C」这种算不平的等式，
                // 但也不许偷偷改数——照实写，并点明以哪个为准。
                noteLines.append("价格口径：定金 \(money(depositAmount)) + 尾款 \(money(balanceAmount))（预约价 \(money(totalAmount))，以后台录入为准）")
            }
        }

        // 尾款窗口来源（2026-09-25 需求二/三）：运营已声明尾款期 → 用户记录以声明为准；
        // 大致描述（上旬/中旬/中下旬/下旬）→ 以「约一个月」为基准估算成**固定具体日期**
        //（锚点是运营侧事实：系列预约结束时间 → 预约销售记录结束时间，绝不用加购当天）。
        // 窗口解法唯一口径 `CatalogBalanceDueApproximation.declaredWindow`（与同步共用）。
        // 全款（balance == 0）不生成尾款任务，窗口无意义，不在此改。
        // 完全无声明 → 维持旧行为（预约结束 = 尾款开始；结束未公布用开始时间占位）。
        if isDepositPlan, balanceAmount > 0, let series {
            let anchor = series.reservationEndAt ?? archive.reservation?.endAt
            if let window = CatalogBalanceDueApproximation.declaredWindow(of: series, anchor: anchor),
               window.start != finalPaymentStart || window.end != finalPaymentEnd {
                finalPaymentStart = window.start
                finalPaymentEnd = window.end
                noteLines.append("尾款时间：\(window.basis)，按 \(CatalogSeriesBalanceDue.shortDateText(window.start)) 记录")
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
            // 2026-09-24 根因修复：把商品图物化成 ImageManager 文件，衣橱卡片才有图可显示
            imagePaths: materializeImagePaths(for: product, store: store, modelContext: modelContext),
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
            note: noteLines.joined(separator: "\n"),
            accessoryList: [],
            sizeChartImagePath: nil
        )
        return draft
    }

    /// 商品图引用 → 衣橱图片文件名（2026-09-24 根因修复）。
    ///
    /// 根因：`makeDraft` 曾硬编码 `imagePaths: []`，加购落库的 `Clothing` 没有任何图片，
    /// 而衣橱卡片走 `ImageManager` 文件名体系 —— 引用再完整也无处取图，表现为「衣橱不显示图片」。
    ///
    /// 引用推导与详情页同一口径：`store.asset(id:)?.originalURL ?? 原值`，随后分类解析：
    ///   · `local:` 运营上传图 → Application Support/ShopCatalog/images/
    ///   · 其余视为 Bundle 画册图（含 "bundle:" 前缀）
    ///   · http(s) 远程图 → 不在主线程同步拉网络，跳过（详情页轮播仍可看原图）
    /// 单张失败不阻塞其余图片；全部失败返回空数组（卡片展示占位，与旧行为一致）。
    /// 物化是「复制」不是「搬移」：Catalog 侧引用原样保留。
    @MainActor
    static func materializeImagePaths(
        for product: CatalogProduct,
        store: ShopCatalogStore,
        modelContext: ModelContext,
        maxCount: Int = 6
    ) -> [String] {
        var fileNames: [String] = []
        for assetID in product.images {
            guard fileNames.count < maxCount else { break }
            let reference = store.asset(id: assetID)?.originalURL ?? assetID
            let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.lowercased().hasPrefix("http") { continue }
            guard let url = ShopCatalogImageResolver.url(for: trimmed),
                  let image = UIImage(contentsOfFile: url.path),
                  let fileName = ImageManager.shared.saveImage(image, context: modelContext)
            else { continue }
            fileNames.append(fileName)
        }
        return fileNames
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
            let symbol = (archive.currentCurrency ?? .unknown).symbol
            return price.map { "\(symbol)\(NSDecimalNumber(decimal: $0).stringValue)" } ?? "价格未填"
        }

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
            var noteLines = head.draft.note.components(separatedBy: "\n")
            for item in accessoryEntries {
                let line = "小物：\(item.product.name)（\(accessoryPriceLine(item.product))）"
                noteLines.append(isSameCurrencyAsHead(item.product)
                                 ? line : line + "（币种不同，未计入合计）")
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
        let clothing = try TimeHallWardrobeQuickInserter.insert(draft: draft, modelContext: modelContext)
        if let selection, let product = store.product(id: selection.productID) {
            clothing.catalogProductID = product.id
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
