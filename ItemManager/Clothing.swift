
//
//  Clothing.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import Foundation
import SwiftData
import SwiftUI



enum ClothingPriceCurrency: String, Codable, CaseIterable, Identifiable {
    case cny = "CNY"
    case jpy = "JPY"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cny: return "人民币"
        case .jpy: return "日元"
        }
    }

    var shortName: String {
        switch self {
        case .cny: return "人民币"
        case .jpy: return "日元"
        }
    }

    var symbol: String {
        switch self {
        case .cny: return "¥"
        case .jpy: return "JP¥"
        }
    }
}

enum ClothingStatus: String, Codable, CaseIterable, Identifiable {
    case onShelf = "上架"
    case offShelf = "下架"
    
    var id: Self { self }
}

enum ClothingReservationKind: String, Codable, CaseIterable, Identifiable {
    case owned = "owned"
    case fullPaymentReservation = "full_payment_reservation"
    case depositPlan = "deposit_plan"
    case sold = "sold"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .owned: return "已拥有"
        case .fullPaymentReservation: return "全款预约"
        case .depositPlan: return "定金尾款"
        case .sold: return "已售出"
        }
    }
}

enum ClothingDeletionSource: String, Codable {
    case mergeToAccessory = "merge_to_accessory"
}

enum WealthSavingEntryKind: String, Codable {
    case saving = "saving"
    case finalPayment = "final_payment"
}

struct FinalPaymentRecordResult {
    let paymentEntry: WealthSavingEntry
    let paidOff: Bool
    let paidAmount: Decimal
    let paidTotal: Decimal
    let remainingAmount: Decimal
}

@Model
final class Clothing {
    var id: UUID = UUID()
    // 基础信息
    var name: String = ""
    // var brand: String = "" // Deprecated
    var types: String = "" // 逗号分隔，如 JSK,OP
    var colors: String = "" // 逗号分隔
    var sizes: String = "" // 逗号分隔
    var length: String = "" // 长度
    var condition: String = "全新" // 状态：全新/非全新
    var accessories: String = "" // 逗号分隔，小物
    var imagePaths: [String] = [] // 图片路径列表
    var isShared: Bool = false // 同步到裙装广场
    var replacedCutoutID: UUID? = nil // 记录替换主图所使用的抠图 ID
    
    // 表图信息
    var sizeChartImagePath: String? = nil  // 尺码表图片路径
    var priceChartImagePath: String? = nil // 价格表图片路径
    
    // 价格信息
    var originalPrice: Decimal = 0.0 // 原价（人民币，统计 source of truth）
    var originalPriceJPY: Decimal = 0.0 // 原价（日元，保留历史显示习惯）
    var originalPriceCurrencyCode: String = ClothingPriceCurrency.cny.rawValue // 原价显示币种
    var originalPriceExchangeRateJPY: Decimal = 21.0 // 保存时 CNY -> JPY 汇率
    var originalPriceRateUpdatedAt: Date? = nil // 原价汇率更新时间
    var price: Decimal = 0.0 // 裙装总价
    var deposit: Decimal = 0.0 // 定金
    var balance: Decimal = 0.0 // 尾款
    var accessoriesPrice: Decimal = 0.0 // 小物总价
    var shippingFee: Decimal = 0.0 // 邮费（人民币，合计 source of truth）
    var shippingFeeJPY: Decimal = 0.0 // 邮费（日元）
    var shippingFeeCurrencyCode: String = ClothingPriceCurrency.cny.rawValue // 邮费显示币种
    var shippingExchangeRateJPY: Decimal = 21.0 // 保存时 CNY -> JPY 汇率
    var shippingRateUpdatedAt: Date? = nil // 邮费汇率更新时间
    var sortIndex: Int = 0 // 自定义排序索引
    
    // 购买信息
    var purchaseDate: Date = Date()
    var depositDate: Date? = nil // 定金日期
    var isDepositPlan: Bool = false // 是否加入心愿尾款
    var finalPaymentDate: Date? = nil // 预估尾款时间（开始）
    var finalPaymentEndDate: Date? = nil // 预估尾款时间（结束）
    var finalPaymentInstallmentCount: Int = 0 // v1.13+ 旧版尾款账单兼容字段，新记录保持 0
    var isFinalPaymentSavedToWealth: Bool = false // 旧版尾款标记，保留用于兼容旧数据
    var finalPaymentSavedAt: Date? = nil // 旧版尾款标记时间
    var note: String = ""
    
    // 系统信息
    var stock: Int = 1
    var status: ClothingStatus = ClothingStatus.onShelf
    var isDeleted: Bool = false // 软删除标记
    var deletedAt: Date? = nil // 删除时间
    var deletionSource: String? = nil // 删除来源，nil 表示普通删除并进入回收站
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastModified: Date = Date() // iCloud 同步时间戳

    // 3D模型信息
    var model3DPath: String? = nil // 3D模型文件路径
    var model3DType: String? = nil // 3D模型类型: "multi"(多图3D), "single"(单图3D)
    var model3DThumbnailPath: String? = nil // 3D模型缩略图路径
    
    @Relationship(deleteRule: .nullify)
    var tags: [Tag]? = []
    
    @Relationship(deleteRule: .nullify)
    var brand: Brand?
    
    @Relationship(deleteRule: .cascade)
    var accessoryItems: [AccessoryItem]? = []
    
    // Removed direct relationship to prevent SwiftData side effects on deletion
    // var cutouts: [CutoutItem] = []
    
    // MARK: - 3D模型相关计算属性
    
    /// 是否是3D模型
    var is3DModel: Bool {
        return model3DPath != nil
    }
    
    /// 3D模型类型描述
    var model3DTypeDescription: String? {
        guard is3DModel else { return nil }
        switch model3DType {
        case "multi": return "3D"
        case "single": return "单向"
        default: return "3D"
        }
    }
    
    init(name: String,
         brand: Brand? = nil,
         types: String = "",
         colors: String = "",
         sizes: String = "",
         length: String = "",
         condition: String = "全新",
         accessories: String = "",
         imagePaths: [String] = [],
         isShared: Bool = false,
         originalPrice: Decimal = 0.0,
         originalPriceJPY: Decimal = 0.0,
         originalPriceCurrencyCode: String = ClothingPriceCurrency.cny.rawValue,
         originalPriceExchangeRateJPY: Decimal = 21.0,
         originalPriceRateUpdatedAt: Date? = nil,
         price: Decimal = 0.0,
         deposit: Decimal = 0.0,
         balance: Decimal = 0.0,
         accessoriesPrice: Decimal = 0.0,
         shippingFee: Decimal = 0.0,
         shippingFeeJPY: Decimal = 0.0,
         shippingFeeCurrencyCode: String = ClothingPriceCurrency.cny.rawValue,
         shippingExchangeRateJPY: Decimal = 21.0,
         shippingRateUpdatedAt: Date? = nil,
         purchaseDate: Date = Date(),
         depositDate: Date? = nil,
         isDepositPlan: Bool = false,
         finalPaymentDate: Date? = nil,
         finalPaymentEndDate: Date? = nil,
         note: String = "",
         stock: Int = 1,
         status: ClothingStatus = .onShelf) {
        self.id = UUID()
        self.name = name
        self.brand = brand
        self.types = types
        self.colors = colors
        self.sizes = sizes
        self.length = length
        self.condition = condition
        self.accessories = accessories
        self.imagePaths = imagePaths
        self.isShared = isShared
        self.originalPrice = FinancialDataSanitizer.money(originalPrice)
        self.originalPriceJPY = FinancialDataSanitizer.money(originalPriceJPY)
        self.originalPriceCurrencyCode = originalPriceCurrencyCode
        self.originalPriceExchangeRateJPY = FinancialDataSanitizer.money(originalPriceExchangeRateJPY)
        self.originalPriceRateUpdatedAt = originalPriceRateUpdatedAt
        self.price = FinancialDataSanitizer.money(price)
        self.deposit = FinancialDataSanitizer.money(deposit)
        self.balance = FinancialDataSanitizer.money(balance)
        self.accessoriesPrice = FinancialDataSanitizer.money(accessoriesPrice)
        self.shippingFee = FinancialDataSanitizer.money(shippingFee)
        self.shippingFeeJPY = FinancialDataSanitizer.money(shippingFeeJPY)
        self.shippingFeeCurrencyCode = shippingFeeCurrencyCode
        self.shippingExchangeRateJPY = FinancialDataSanitizer.money(shippingExchangeRateJPY)
        self.shippingRateUpdatedAt = shippingRateUpdatedAt
        self.purchaseDate = purchaseDate
        self.depositDate = depositDate
        self.isDepositPlan = isDepositPlan
        self.finalPaymentDate = finalPaymentDate
        self.finalPaymentEndDate = finalPaymentEndDate
        self.note = note
        self.stock = FinancialDataSanitizer.stock(stock)
        self.status = status
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // Computed Properties for Total Calculation
    // 自定义小物总价：若存在明细，则以明细实时汇总为准；否则回退到存储字段
    var resolvedAccessoriesPrice: Decimal {
        let items = accessoryItems ?? []
        guard !items.isEmpty else { return FinancialDataSanitizer.money(accessoriesPrice) }
        return items.reduce(Decimal(0)) { $0 + FinancialDataSanitizer.money($1.price) }
    }

    var originalPriceCurrency: ClothingPriceCurrency {
        get { ClothingPriceCurrency(rawValue: originalPriceCurrencyCode) ?? .cny }
        set { originalPriceCurrencyCode = newValue.rawValue }
    }

    var shippingFeeCurrency: ClothingPriceCurrency {
        get { ClothingPriceCurrency(rawValue: shippingFeeCurrencyCode) ?? .cny }
        set { shippingFeeCurrencyCode = newValue.rawValue }
    }

    var resolvedShippingFee: Decimal {
        FinancialDataSanitizer.money(shippingFee)
    }

    // 单套总价（含自定义小物，不含一次性邮费）
    var unitTotalPrice: Decimal {
        FinancialDataSanitizer.money(price) + resolvedAccessoriesPrice
    }

    // 全部持有总价：裙装价格按库存累加，自定义小物总价只计算一次，邮费不随库存倍增
    var inventoryTotalPrice: Decimal {
        (FinancialDataSanitizer.money(price) * Decimal(FinancialDataSanitizer.stock(stock)))
            + resolvedAccessoriesPrice
            + resolvedShippingFee
    }

    // 总定金 = (裙装定金 + 小物定金总和) * 库存数量
    var totalDeposit: Decimal {
        let accDeposit = accessoryItems?.reduce(Decimal(0)) { $0 + FinancialDataSanitizer.money($1.deposit) } ?? 0
        return (FinancialDataSanitizer.money(deposit) + accDeposit)
            * Decimal(FinancialDataSanitizer.stock(stock))
    }
    
    // 总尾款 = (裙装尾款 + 小物尾款总和) * 库存数量
    var totalBalance: Decimal {
        let accBalance = accessoryItems?.reduce(Decimal(0)) { $0 + FinancialDataSanitizer.money($1.balance) } ?? 0
        let storedBalance = (FinancialDataSanitizer.money(balance) + accBalance)
            * Decimal(FinancialDataSanitizer.stock(stock))
        if storedBalance > 0 {
            return storedBalance
        }

        let conditionText = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isDepositPlan,
              !isFullPaymentReservation,
              conditionText == "待付尾款" else {
            return 0
        }
        return inventoryTotalPrice
    }

    var reservationKind: ClothingReservationKind {
        guard status != .offShelf else { return .sold }
        guard isDepositPlan else { return .owned }
        return isFullPaymentReservation ? .fullPaymentReservation : .depositPlan
    }

    var isFullPaymentReservation: Bool {
        status != .offShelf
            && isDepositPlan
            && FinancialDataSanitizer.money(deposit) > 0
            && FinancialDataSanitizer.money(balance) == 0
    }

    var isFinalPaymentPlan: Bool {
        status != .offShelf && isDepositPlan && !isFullPaymentReservation
    }

    var reservationGroupingDate: Date? {
        switch reservationKind {
        case .owned:
            return nil
        case .fullPaymentReservation:
            return depositDate
        case .depositPlan:
            return finalPaymentDate
        case .sold:
            return nil
        }
    }

    var fullPaymentReservationUnitAmount: Decimal {
        isFullPaymentReservation ? FinancialDataSanitizer.money(deposit) : 0
    }

    var fullPaymentReservationTotalAmount: Decimal {
        guard isFullPaymentReservation else { return 0 }
        let accessoryBalance = accessoryItems?.reduce(Decimal(0)) {
            $0 + FinancialDataSanitizer.money($1.balance)
        } ?? 0
        return totalDeposit + accessoryBalance * Decimal(stock)
    }

    var pendingFinalPaymentAmount: Decimal {
        isFullPaymentReservation ? 0 : totalBalance
    }

    var reservationPaidAmount: Decimal {
        isFullPaymentReservation ? 0 : totalDeposit
    }

    /// 衣橱“总价值”统一口径：已拥有计完整价格，预约只计已付款，已售出不计。
    var wardrobeValueAmount: Decimal {
        switch reservationKind {
        case .owned:
            return inventoryTotalPrice
        case .fullPaymentReservation:
            return fullPaymentReservationTotalAmount
        case .depositPlan:
            return totalDeposit
        case .sold:
            return 0
        }
    }

    /// 衣橱“裙装价值”统一口径：只统计裙装本身，不含小物与邮费。
    /// 已拥有（含已付清尾款）计完整裙装价；定金/预约阶段只计已付的裙装定金；已售出不计。
    var dressValueAmount: Decimal {
        switch reservationKind {
        case .owned:
            return FinancialDataSanitizer.money(price)
                * Decimal(FinancialDataSanitizer.stock(stock))
        case .fullPaymentReservation, .depositPlan:
            return FinancialDataSanitizer.money(deposit)
                * Decimal(FinancialDataSanitizer.stock(stock))
        case .sold:
            return 0
        }
    }

    var reservationListAmount: Decimal {
        isFullPaymentReservation ? fullPaymentReservationTotalAmount : pendingFinalPaymentAmount
    }

    func copyCurrencyAndShippingMetadata(from source: Clothing) {
        originalPriceJPY = FinancialDataSanitizer.money(source.originalPriceJPY)
        originalPriceCurrencyCode = source.originalPriceCurrencyCode
        originalPriceExchangeRateJPY = FinancialDataSanitizer.money(source.originalPriceExchangeRateJPY)
        originalPriceRateUpdatedAt = source.originalPriceRateUpdatedAt
        shippingFee = FinancialDataSanitizer.money(source.shippingFee)
        shippingFeeJPY = FinancialDataSanitizer.money(source.shippingFeeJPY)
        shippingFeeCurrencyCode = source.shippingFeeCurrencyCode
        shippingExchangeRateJPY = FinancialDataSanitizer.money(source.shippingExchangeRateJPY)
        shippingRateUpdatedAt = source.shippingRateUpdatedAt
    }
}

extension Clothing {
    /// Wardrobe list/stats summary values must not fault the accessory relationship for every row.
    /// `accessoriesPrice` is maintained by edit/validation flows and is the list-scale source.
    var wardrobeListInventoryTotalPrice: Decimal {
        (FinancialDataSanitizer.money(price) * Decimal(FinancialDataSanitizer.stock(stock)))
            + FinancialDataSanitizer.money(accessoriesPrice)
            + FinancialDataSanitizer.money(shippingFee)
    }

    var wardrobeListTotalDeposit: Decimal {
        FinancialDataSanitizer.money(deposit) * Decimal(FinancialDataSanitizer.stock(stock))
    }

    var wardrobeListTotalBalance: Decimal {
        let storedBalance = FinancialDataSanitizer.money(balance) * Decimal(FinancialDataSanitizer.stock(stock))
        if storedBalance > 0 {
            return storedBalance
        }

        let conditionText = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isDepositPlan,
              !isFullPaymentReservation,
              conditionText == "待付尾款" else {
            return 0
        }
        return wardrobeListInventoryTotalPrice
    }

    var wardrobeListFullPaymentReservationTotalAmount: Decimal {
        isFullPaymentReservation ? wardrobeListTotalDeposit : 0
    }

    var wardrobeListValueAmount: Decimal {
        switch reservationKind {
        case .owned:
            return wardrobeListInventoryTotalPrice
        case .fullPaymentReservation:
            return wardrobeListFullPaymentReservationTotalAmount
        case .depositPlan:
            return wardrobeListTotalDeposit
        case .sold:
            return 0
        }
    }
}

@Model
final class AccessoryItem {
    var id: UUID = UUID()
    var name: String = ""
    var price: Decimal = 0.0
    var deposit: Decimal = 0.0 // 定金
    var balance: Decimal = 0.0 // 尾款
    var sortIndex: Int = 0
    var imagePaths: [String]? = nil // 图片路径列表，合并时从原裙装复制
    
    @Relationship(deleteRule: .nullify)
    var clothing: Clothing?
    
    init(name: String, price: Decimal, deposit: Decimal = 0.0, balance: Decimal = 0.0, sortIndex: Int = 0, imagePaths: [String]? = nil) {
        self.name = name
        self.price = FinancialDataSanitizer.money(price)
        self.deposit = FinancialDataSanitizer.money(deposit)
        self.balance = FinancialDataSanitizer.money(balance)
        self.sortIndex = sortIndex
        self.imagePaths = imagePaths
    }
}

@Model
final class WealthSavingEntry {
    var id: UUID = UUID()
    var amount: Decimal = 0.0
    var clothingID: UUID? = nil
    var note: String = ""
    var migrationSource: String? = nil
    var entryKind: String = WealthSavingEntryKind.saving.rawValue // v1.13+ saving / final_payment
    var finalPaymentMode: String? = nil // v1.13+ 旧版尾款账单兼容字段
    var installmentIndex: Int = 0 // v1.13+ 旧版尾款账单兼容字段
    var installmentCount: Int = 0 // v1.13+ 旧版尾款账单兼容字段
    var paidAt: Date? = nil // v1.13+ 尾款实付时间
    var vaultDeductionAmount: Decimal = 0.0 // v1.13+ 旧版金额兼容字段
    var externalPaymentAmount: Decimal = 0.0 // v1.13+ 本笔外部实付金额
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var usedAt: Date? = nil
    var voidedAt: Date? = nil
    var lastModified: Date = Date()

    init(
        amount: Decimal,
        clothingID: UUID? = nil,
        note: String = "",
        migrationSource: String? = nil,
        entryKind: WealthSavingEntryKind = .saving,
        paidAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.amount = FinancialDataSanitizer.money(amount)
        self.clothingID = clothingID
        self.note = note
        self.migrationSource = migrationSource
        self.entryKind = entryKind.rawValue
        self.paidAt = paidAt
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.lastModified = createdAt
    }

    var kind: WealthSavingEntryKind {
        get { WealthSavingEntryKind(rawValue: entryKind) ?? .saving }
        set { entryKind = newValue.rawValue }
    }

}

enum WealthSavingLedger {
    static let legacyFinalPaymentMigrationSource = "legacy.finalPaymentSavedToWealth"
    @MainActor private static var lastViewReconciliationAt: Date?

    private static var viewReconciliationMinimumInterval: TimeInterval {
        ProcessInfo.processInfo.physicalMemory <= 3_500_000_000 ? 45 : 20
    }

    static func isActive(_ entry: WealthSavingEntry) -> Bool {
        entry.kind == .saving
            && FinancialDataSanitizer.money(entry.amount) > 0
            && entry.usedAt == nil
            && entry.voidedAt == nil
    }

    static func isFinalPaymentRecord(_ entry: WealthSavingEntry) -> Bool {
        entry.kind == .finalPayment
            && FinancialDataSanitizer.money(entry.amount) > 0
            && entry.voidedAt == nil
    }

    static func activeTotal(in entries: [WealthSavingEntry]) -> Decimal {
        entries.reduce(Decimal(0)) { partial, entry in
            isActive(entry) ? partial + FinancialDataSanitizer.money(entry.amount) : partial
        }
    }

    static func activeTotal(for clothingID: UUID, in entries: [WealthSavingEntry]) -> Decimal {
        entries.reduce(Decimal(0)) { partial, entry in
            isActive(entry) && entry.clothingID == clothingID
                ? partial + FinancialDataSanitizer.money(entry.amount)
                : partial
        }
    }

    static func finalPaymentDueAmount(for clothing: Clothing) -> Decimal {
        if clothing.isFullPaymentReservation {
            return 0
        }

        if clothing.reservationKind == .depositPlan {
            let due = clothing.totalBalance
            if due > 0 { return due }
        }
        return 0
    }

    static func unpaidFinalPaymentAmount(for clothing: Clothing) -> Decimal {
        finalPaymentDueAmount(for: clothing)
    }

    static func shouldShowFinalPaymentPayoffAction(for clothing: Clothing) -> Bool {
        clothing.reservationKind == .depositPlan && unpaidFinalPaymentAmount(for: clothing) > 0
    }

    static func finalPaymentRecords(for clothingID: UUID, in entries: [WealthSavingEntry]) -> [WealthSavingEntry] {
        entries
            .filter { isFinalPaymentRecord($0) && $0.clothingID == clothingID }
            .sorted {
                let leftDate = $0.paidAt ?? $0.createdAt
                let rightDate = $1.paidAt ?? $1.createdAt
                if leftDate != rightDate { return leftDate < rightDate }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    static func paidFinalPaymentTotal(for clothingID: UUID, in entries: [WealthSavingEntry]) -> Decimal {
        finalPaymentRecords(for: clothingID, in: entries)
            .reduce(Decimal(0)) { $0 + FinancialDataSanitizer.money($1.amount) }
    }

    static func remainingFinalPaymentAmount(for clothing: Clothing, entries: [WealthSavingEntry]) -> Decimal {
        let due = finalPaymentDueAmount(for: clothing)
        guard due > 0 else { return 0 }
        let remaining = due - paidFinalPaymentTotal(for: clothing.id, in: entries)
        return remaining > 0 ? remaining : 0
    }

    static func isFinalPaymentPaidOff(for clothing: Clothing, entries: [WealthSavingEntry]) -> Bool {
        guard !clothing.isFullPaymentReservation else { return false }
        let due = clothing.totalBalance
        guard due > 0 else { return false }
        return paidFinalPaymentTotal(for: clothing.id, in: entries) >= due
    }

    static func hasPaidFinalPaymentFact(for clothing: Clothing, entries: [WealthSavingEntry]) -> Bool {
        isFinalPaymentPaidOff(for: clothing, entries: entries)
            || hasCompletedFinalPaymentState(for: clothing)
    }

    static func hasCompletedFinalPaymentState(for clothing: Clothing) -> Bool {
        !clothing.isDeleted
            && clothing.deletedAt == nil
            && !clothing.isDepositPlan
            && clothing.totalBalance > 0
    }

    @discardableResult
    static func reconcilePaidFinalPayments(
        clothings: [Clothing],
        entries: [WealthSavingEntry],
        context: ModelContext,
        at date: Date = Date()
    ) -> Int {
        var changedCount = 0

        for clothing in clothings {
            guard !clothing.isDeleted,
                  clothing.deletedAt == nil,
                  clothing.isFinalPaymentPlan,
                  isFinalPaymentPaidOff(for: clothing, entries: entries) else {
                continue
            }

            markFinalPaymentCompleted(clothing, at: date)
            changedCount += 1
        }

        if changedCount > 0 {
            do {
                try context.save()
            } catch {
                print("WealthSavingLedger: Failed to reconcile paid final payments: \(error)")
            }
        }

        return changedCount
    }

    @discardableResult
    static func reconcilePaidFinalPayments(context: ModelContext, at date: Date = Date()) -> Int {
        let finalPaymentKind = WealthSavingEntryKind.finalPayment.rawValue
        let clothingDescriptor = FetchDescriptor<Clothing>(
            predicate: #Predicate { clothing in
                clothing.deletedAt == nil && clothing.isDepositPlan == true
            }
        )
        let entryDescriptor = FetchDescriptor<WealthSavingEntry>(
            predicate: #Predicate { entry in
                entry.entryKind == finalPaymentKind && entry.voidedAt == nil
            }
        )

        do {
            let clothings = try context.fetch(clothingDescriptor)
            let entries = try context.fetch(entryDescriptor)
            return reconcilePaidFinalPayments(
                clothings: clothings,
                entries: entries,
                context: context,
                at: date
            )
        } catch {
            print("WealthSavingLedger: Failed to fetch final payment reconciliation data: \(error)")
            return 0
        }
    }

    @discardableResult
    @MainActor
    static func reconcilePaidFinalPaymentsIfNeededForView(
        context: ModelContext,
        reason: String,
        at date: Date = Date()
    ) -> Int {
        if let lastViewReconciliationAt,
           date.timeIntervalSince(lastViewReconciliationAt) < viewReconciliationMinimumInterval {
            return 0
        }

        lastViewReconciliationAt = date
        let reconciledCount = reconcilePaidFinalPayments(context: context, at: date)
        if reconciledCount > 0 {
            print("\(reason): Reconciled \(reconciledCount) paid final payment clothing record(s) before filtering.")
        }
        return reconciledCount
    }

    @discardableResult
    @MainActor
    static func recordFinalPayment(
        amount requestedAmount: Decimal,
        for clothing: Clothing,
        context: ModelContext
    ) throws -> FinalPaymentRecordResult? {
        let existingEntries = try fetchFinalPaymentEntries(for: clothing.id, context: context)
        if isFinalPaymentPaidOff(for: clothing, entries: existingEntries) {
            if clothing.isFinalPaymentPlan {
                markFinalPaymentCompleted(clothing, at: Date())
                try context.save()
            }
            return nil
        }

        let remainingBefore = unpaidFinalPaymentAmount(for: clothing)
        guard remainingBefore > 0, requestedAmount > 0 else { return nil }

        let now = Date()
        let actualAmount = remainingBefore
        guard actualAmount > 0 else { return nil }

        try resetLegacyFinalPaymentProgress(for: clothing.id, context: context, at: now)

        let entry = WealthSavingEntry(
            amount: actualAmount,
            clothingID: clothing.id,
            note: "尾款付清",
            entryKind: .finalPayment,
            paidAt: now,
            createdAt: now
        )
        context.insert(entry)

        markFinalPaymentCompleted(clothing, at: now)

        try context.save()
        return FinalPaymentRecordResult(
            paymentEntry: entry,
            paidOff: true,
            paidAmount: actualAmount,
            paidTotal: actualAmount,
            remainingAmount: 0
        )
    }

    @MainActor
    private static func fetchFinalPaymentEntries(
        for clothingID: UUID,
        context: ModelContext
    ) throws -> [WealthSavingEntry] {
        let finalPaymentKind = WealthSavingEntryKind.finalPayment.rawValue
        let descriptor = FetchDescriptor<WealthSavingEntry>(
            predicate: #Predicate { entry in
                entry.clothingID == clothingID && entry.entryKind == finalPaymentKind
            }
        )
        return try context.fetch(descriptor)
    }

    @MainActor
    static func resetFinalPaymentProgress(
        for clothing: Clothing,
        context: ModelContext,
        at date: Date = Date()
    ) throws {
        try resetLegacyFinalPaymentProgress(for: clothing.id, context: context, at: date)
        clothing.isFinalPaymentSavedToWealth = false
        clothing.finalPaymentSavedAt = nil
        clothing.finalPaymentInstallmentCount = 0
        clothing.updatedAt = date
        clothing.lastModified = date
    }

    @MainActor
    private static func resetLegacyFinalPaymentProgress(
        for clothingID: UUID,
        context: ModelContext,
        at date: Date
    ) throws {
        let existingEntries = try fetchFinalPaymentEntries(for: clothingID, context: context)
        for entry in existingEntries {
            entry.finalPaymentMode = nil
            entry.installmentIndex = 0
            entry.installmentCount = 0
            entry.vaultDeductionAmount = 0
            entry.externalPaymentAmount = 0
            if entry.voidedAt == nil {
                entry.voidedAt = date
            }
            entry.updatedAt = date
            entry.lastModified = date
        }
    }

    @MainActor
    static func migrateLegacySavedFinalPayments(
        clothings: [Clothing],
        entries _: [WealthSavingEntry],
        context: ModelContext
    ) {
        var didUpdate = false
        for clothing in clothings {
            guard clothing.isDepositPlan,
                  !clothing.isDeleted,
                  clothing.deletedAt == nil,
                  clothing.isFinalPaymentSavedToWealth,
                  clothing.totalBalance > 0 else {
                continue
            }

            let now = Date()
            clothing.isFinalPaymentSavedToWealth = false
            clothing.finalPaymentSavedAt = nil
            clothing.updatedAt = now
            clothing.lastModified = now
            didUpdate = true
        }

        if didUpdate {
            try? context.save()
        }
    }

    static func markFinalPaymentCompleted(_ clothing: Clothing, at date: Date) {
        clothing.isDepositPlan = false
        clothing.isFinalPaymentSavedToWealth = false
        clothing.finalPaymentSavedAt = nil
        clothing.depositDate = nil
        clothing.finalPaymentDate = nil
        clothing.finalPaymentEndDate = nil
        clothing.finalPaymentInstallmentCount = 0
        clothing.updatedAt = date
        clothing.lastModified = date
    }
}

// MARK: - OOTD Models
// Moved here to ensure availability in all targets (e.g., Widget Extension)

@Model
final class CutoutItem {
    var id: UUID = UUID()
    var originalImageHash: String = ""
    var timestamp: Date = Date()
    var category: String = "未分类" // e.g., 裙装, 上衣, etc.
    var imagePath: String = "" // Path to the cutout image (PNG with transparency)
    var width: Double = 0.0
    var height: Double = 0.0

    // 缓存裙装名字，方便在画布中显示（即使原 Clothing 被删除）
    var clothingName: String?

    // Use ID instead of Relationship to decouple deletion lifecycle
    var linkedClothingID: UUID?

    @Relationship(deleteRule: .nullify)
    var outfitItems: [OutfitItem]? = []

    // iCloud 同步时间戳
    var lastModified: Date = Date()

    init(originalImageHash: String,
         category: String = "未分类",
         imagePath: String,
         width: Double,
         height: Double,
         linkedClothingID: UUID? = nil,
         clothingName: String? = nil) {
        self.originalImageHash = originalImageHash
        self.category = category
        self.imagePath = imagePath
        self.width = width
        self.height = height
        self.linkedClothingID = linkedClothingID
        self.clothingName = clothingName
    }
}

@Model
final class BookGroup {
    var id: UUID = UUID()
    var title: String = ""
    var coverImage: String? // Optional custom cover
    var createdAt: Date = Date()
    var isDeleted: Bool = false
    var deletedAt: Date? = nil
    var sortIndex: Int = 0 // 自定义排序索引

    // iCloud 同步时间戳
    var lastModified: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Outfit.book)
    var pages: [Outfit]? = []

    init(title: String, coverImage: String? = nil, sortIndex: Int = 0) {
        self.title = title
        self.coverImage = coverImage
        self.createdAt = Date()
        self.sortIndex = sortIndex
    }
}

@Model
final class Outfit {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var note: String = ""
    var snapshotPath: String? // Path to the saved OOTD image
    var canvasType: String = "mannequin" // "mannequin" or "blank"
    var backgroundImagePath: String? // Custom background image path
    var mannequinAssetID: String? // Static mannequin background identifier; nil falls back to default mannequin
    var sortIndex: Int = 0 // Custom order index

    // Trash Bin Logic
    var isDeleted: Bool = false
    var deletedAt: Date? = nil

    // iCloud 同步时间戳
    var lastModified: Date = Date()

    @Relationship
    var book: BookGroup?

    @Relationship(deleteRule: .cascade)
    var items: [OutfitItem]? = []

    init(note: String = "", snapshotPath: String? = nil, canvasType: String = "mannequin", backgroundImagePath: String? = nil, mannequinAssetID: String? = nil, book: BookGroup? = nil) {
        self.note = note
        self.snapshotPath = snapshotPath
        self.canvasType = canvasType
        self.backgroundImagePath = backgroundImagePath
        self.mannequinAssetID = mannequinAssetID
        self.book = book
    }
}

@Model
final class OutfitItem {
    var id: UUID = UUID()
    var x: Double = 0.0
    var y: Double = 0.0
    var rotation: Double = 0.0
    var scale: Double = 1.0
    var zIndex: Int = 0
    
    // 坐标版本：1 = 老版本（绝对坐标，像素值），2 = 新版本（相对坐标，0-1）
    // 默认值为 1 以兼容老数据，新创建的数据应设置为 2
    var coordinateVersion: Int = 1
    
    @Relationship(deleteRule: .nullify)
    var cutout: CutoutItem?
    
    @Relationship(deleteRule: .nullify)
    var outfit: Outfit?
    
    init(cutout: CutoutItem?, x: Double, y: Double, rotation: Double, scale: Double, zIndex: Int, coordinateVersion: Int = 2) {
        self.cutout = cutout
        self.x = x
        self.y = y
        self.rotation = rotation
        self.scale = scale
        self.zIndex = zIndex
        self.coordinateVersion = coordinateVersion
    }
}

// MARK: - 3D Space OOTD Models

@Model
final class SpaceBookGroup {
    var id: UUID = UUID()
    var title: String = ""
    var coverImage: String? // Optional custom cover
    var createdAt: Date = Date()
    var isDeleted: Bool = false
    var deletedAt: Date? = nil
    var sortIndex: Int = 0 // 自定义排序索引

    // iCloud 同步时间戳
    var lastModified: Date = Date()

    @Relationship(deleteRule: .cascade)
    var pages: [SpaceOutfit]? = []

    init(title: String, coverImage: String? = nil, sortIndex: Int = 0) {
        self.title = title
        self.coverImage = coverImage
        self.createdAt = Date()
        self.sortIndex = sortIndex
    }
}

@Model
final class SpaceOutfit {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var note: String = ""
    var snapshotPath: String? // Path to the saved 3D snapshot

    // Sorting
    var sortIndex: Int = 0

    // 3D Scene Configuration
    var modelPath: String? // Path to the 3D model file (e.g. .usdz, .ply)
    var camPosX: Double = 0.0
    var camPosY: Double = 1.5
    var camPosZ: Double = 5.0
    var lightingIntensity: Double = 1000.0

    // Trash Bin Logic
    var isDeleted: Bool = false
    var deletedAt: Date? = nil

    // iCloud 同步时间戳
    var lastModified: Date = Date()

    @Relationship(deleteRule: .nullify)
    var book: SpaceBookGroup?

    // pages 关系通过 SceneObjectData.spaceOutfitID 查询获取

    init(note: String = "", snapshotPath: String? = nil, book: SpaceBookGroup? = nil, sortIndex: Int = 0) {
        self.note = note
        self.snapshotPath = snapshotPath
        self.book = book
        self.createdAt = Date()
        self.sortIndex = sortIndex
    }
}
