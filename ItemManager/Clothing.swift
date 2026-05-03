
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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .owned: return "已拥有"
        case .fullPaymentReservation: return "全款预约"
        case .depositPlan: return "定金尾款"
        }
    }
}

enum WealthSavingEntryKind: String, Codable {
    case saving = "saving"
    case finalPayment = "final_payment"
}

enum FinalPaymentMode: String, Codable, CaseIterable, Identifiable {
    case oneTime = "one_time"
    case installment = "installment"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oneTime: return "一次性付清"
        case .installment: return "分期支付"
        }
    }
}

struct FinalPaymentRecordResult {
    let paymentEntry: WealthSavingEntry
    let paidOff: Bool
    let paidAmount: Decimal
    let deductedFromVault: Decimal
    let externalPaymentAmount: Decimal
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
    var finalPaymentInstallmentCount: Int = 0 // v1.13+ 尾款分期期数，0 表示尚未选择
    var isFinalPaymentSavedToWealth: Bool = false // 是否已将尾款存入马上来财招财猫
    var finalPaymentSavedAt: Date? = nil // 尾款存入招财猫时间
    var note: String = ""
    
    // 系统信息
    var stock: Int = 1
    var status: ClothingStatus = ClothingStatus.onShelf
    var isDeleted: Bool = false // 软删除标记
    var deletedAt: Date? = nil // 删除时间
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
        self.originalPrice = originalPrice
        self.originalPriceJPY = originalPriceJPY
        self.originalPriceCurrencyCode = originalPriceCurrencyCode
        self.originalPriceExchangeRateJPY = originalPriceExchangeRateJPY
        self.originalPriceRateUpdatedAt = originalPriceRateUpdatedAt
        self.price = price
        self.deposit = deposit
        self.balance = balance
        self.accessoriesPrice = accessoriesPrice
        self.shippingFee = shippingFee
        self.shippingFeeJPY = shippingFeeJPY
        self.shippingFeeCurrencyCode = shippingFeeCurrencyCode
        self.shippingExchangeRateJPY = shippingExchangeRateJPY
        self.shippingRateUpdatedAt = shippingRateUpdatedAt
        self.purchaseDate = purchaseDate
        self.depositDate = depositDate
        self.isDepositPlan = isDepositPlan
        self.finalPaymentDate = finalPaymentDate
        self.finalPaymentEndDate = finalPaymentEndDate
        self.note = note
        self.stock = stock
        self.status = status
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // Computed Properties for Total Calculation
    // 自定义小物总价：若存在明细，则以明细实时汇总为准；否则回退到存储字段
    var resolvedAccessoriesPrice: Decimal {
        let items = accessoryItems ?? []
        guard !items.isEmpty else { return accessoriesPrice }
        return items.reduce(Decimal(0)) { $0 + $1.price }
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
        shippingFee
    }

    // 单套总价（含自定义小物，不含一次性邮费）
    var unitTotalPrice: Decimal {
        price + resolvedAccessoriesPrice
    }

    // 全部持有总价：裙装价格按库存累加，自定义小物总价只计算一次，邮费不随库存倍增
    var inventoryTotalPrice: Decimal {
        (price * Decimal(stock)) + resolvedAccessoriesPrice + resolvedShippingFee
    }

    // 总定金 = (裙装定金 + 小物定金总和) * 库存数量
    var totalDeposit: Decimal {
        let accDeposit = accessoryItems?.reduce(Decimal(0)) { $0 + $1.deposit } ?? 0
        return (deposit + accDeposit) * Decimal(stock)
    }
    
    // 总尾款 = (裙装尾款 + 小物尾款总和) * 库存数量
    var totalBalance: Decimal {
        let accBalance = accessoryItems?.reduce(Decimal(0)) { $0 + $1.balance } ?? 0
        return (balance + accBalance) * Decimal(stock)
    }

    var reservationKind: ClothingReservationKind {
        guard isDepositPlan else { return .owned }
        return isFullPaymentReservation ? .fullPaymentReservation : .depositPlan
    }

    var isFullPaymentReservation: Bool {
        isDepositPlan && deposit > 0 && balance == 0
    }

    var reservationGroupingDate: Date? {
        switch reservationKind {
        case .owned:
            return nil
        case .fullPaymentReservation:
            return depositDate
        case .depositPlan:
            return finalPaymentDate
        }
    }

    var fullPaymentReservationUnitAmount: Decimal {
        isFullPaymentReservation ? deposit : 0
    }

    var fullPaymentReservationTotalAmount: Decimal {
        isFullPaymentReservation ? totalDeposit : 0
    }

    var pendingFinalPaymentAmount: Decimal {
        isFullPaymentReservation ? 0 : totalBalance
    }

    var reservationPaidAmount: Decimal {
        isFullPaymentReservation ? 0 : totalDeposit
    }

    var reservationListAmount: Decimal {
        isFullPaymentReservation ? fullPaymentReservationTotalAmount : pendingFinalPaymentAmount
    }

    func copyCurrencyAndShippingMetadata(from source: Clothing) {
        originalPriceJPY = source.originalPriceJPY
        originalPriceCurrencyCode = source.originalPriceCurrencyCode
        originalPriceExchangeRateJPY = source.originalPriceExchangeRateJPY
        originalPriceRateUpdatedAt = source.originalPriceRateUpdatedAt
        shippingFee = source.shippingFee
        shippingFeeJPY = source.shippingFeeJPY
        shippingFeeCurrencyCode = source.shippingFeeCurrencyCode
        shippingExchangeRateJPY = source.shippingExchangeRateJPY
        shippingRateUpdatedAt = source.shippingRateUpdatedAt
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
        self.price = price
        self.deposit = deposit
        self.balance = balance
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
    var finalPaymentMode: String? = nil // v1.13+ one_time / installment
    var installmentIndex: Int = 0 // v1.13+ 第几期，0 表示非尾款账单
    var installmentCount: Int = 0 // v1.13+ 共几期，0 表示非尾款账单
    var paidAt: Date? = nil // v1.13+ 尾款实付时间
    var vaultDeductionAmount: Decimal = 0.0 // v1.13+ 本笔从小金库自动抵扣金额
    var externalPaymentAmount: Decimal = 0.0 // v1.13+ 本笔小金库不足时的外部实付金额
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
        finalPaymentMode: FinalPaymentMode? = nil,
        installmentIndex: Int = 0,
        installmentCount: Int = 0,
        paidAt: Date? = nil,
        vaultDeductionAmount: Decimal = 0.0,
        externalPaymentAmount: Decimal = 0.0,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.amount = amount
        self.clothingID = clothingID
        self.note = note
        self.migrationSource = migrationSource
        self.entryKind = entryKind.rawValue
        self.finalPaymentMode = finalPaymentMode?.rawValue
        self.installmentIndex = installmentIndex
        self.installmentCount = installmentCount
        self.paidAt = paidAt
        self.vaultDeductionAmount = vaultDeductionAmount
        self.externalPaymentAmount = externalPaymentAmount
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.lastModified = createdAt
    }

    var kind: WealthSavingEntryKind {
        get { WealthSavingEntryKind(rawValue: entryKind) ?? .saving }
        set { entryKind = newValue.rawValue }
    }

    var paymentMode: FinalPaymentMode? {
        get {
            guard let finalPaymentMode else { return nil }
            return FinalPaymentMode(rawValue: finalPaymentMode)
        }
        set { finalPaymentMode = newValue?.rawValue }
    }
}

enum WealthSavingLedger {
    static let legacyFinalPaymentMigrationSource = "legacy.finalPaymentSavedToWealth"

    static func isActive(_ entry: WealthSavingEntry) -> Bool {
        entry.kind == .saving && entry.amount > 0 && entry.usedAt == nil && entry.voidedAt == nil
    }

    static func isFinalPaymentRecord(_ entry: WealthSavingEntry) -> Bool {
        entry.kind == .finalPayment && entry.amount > 0 && entry.voidedAt == nil
    }

    static func activeTotal(in entries: [WealthSavingEntry]) -> Decimal {
        entries.reduce(Decimal(0)) { partial, entry in
            isActive(entry) ? partial + entry.amount : partial
        }
    }

    static func activeTotal(for clothingID: UUID, in entries: [WealthSavingEntry]) -> Decimal {
        entries.reduce(Decimal(0)) { partial, entry in
            isActive(entry) && entry.clothingID == clothingID ? partial + entry.amount : partial
        }
    }

    static func activeUnassignedTotal(in entries: [WealthSavingEntry]) -> Decimal {
        entries.reduce(Decimal(0)) { partial, entry in
            isActive(entry) && entry.clothingID == nil ? partial + entry.amount : partial
        }
    }

    static func finalPaymentDueAmount(for clothing: Clothing) -> Decimal {
        if clothing.isFullPaymentReservation {
            return 0
        }

        if clothing.isDepositPlan || clothing.finalPaymentInstallmentCount > 0 || clothing.totalBalance > 0 {
            let target = clothing.totalDeposit + clothing.totalBalance + clothing.resolvedShippingFee
            let due = target - clothing.totalDeposit
            if due > 0 { return due }
        }
        return assignableSavingCap(for: clothing)
    }

    static func finalPaymentRecords(for clothingID: UUID, in entries: [WealthSavingEntry]) -> [WealthSavingEntry] {
        entries
            .filter { isFinalPaymentRecord($0) && $0.clothingID == clothingID }
            .sorted {
                let leftDate = $0.paidAt ?? $0.createdAt
                let rightDate = $1.paidAt ?? $1.createdAt
                if leftDate != rightDate { return leftDate < rightDate }
                return $0.installmentIndex < $1.installmentIndex
            }
    }

    static func paidFinalPaymentTotal(for clothingID: UUID, in entries: [WealthSavingEntry]) -> Decimal {
        finalPaymentRecords(for: clothingID, in: entries).reduce(Decimal(0)) { $0 + $1.amount }
    }

    static func remainingFinalPaymentAmount(for clothing: Clothing, entries: [WealthSavingEntry]) -> Decimal {
        let remaining = finalPaymentDueAmount(for: clothing) - paidFinalPaymentTotal(for: clothing.id, in: entries)
        return max(remaining, Decimal(0))
    }

    static func nextInstallmentIndex(for clothing: Clothing, entries: [WealthSavingEntry]) -> Int {
        finalPaymentRecords(for: clothing.id, in: entries).count + 1
    }

    static func defaultInstallmentAmount(
        for clothing: Clothing,
        entries: [WealthSavingEntry],
        installmentCount: Int
    ) -> Decimal {
        let remaining = remainingFinalPaymentAmount(for: clothing, entries: entries)
        guard remaining > 0 else { return 0 }
        let nextIndex = nextInstallmentIndex(for: clothing, entries: entries)
        let remainingInstallments = max(installmentCount - nextIndex + 1, 1)
        guard remainingInstallments > 1 else { return remaining }
        return roundedCurrencyAmount(remaining / Decimal(remainingInstallments))
    }

    static func roundedCurrencyAmount(_ amount: Decimal) -> Decimal {
        var value = amount
        var result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }

    static func assignableSavingCap(for clothing: Clothing) -> Decimal {
        if clothing.isFullPaymentReservation {
            return 0
        }

        let target = purchaseTarget(for: clothing)
        let cap: Decimal
        if clothing.isDepositPlan {
            cap = target - clothing.totalDeposit
        } else {
            cap = target
        }
        return max(cap, Decimal(0))
    }

    static func remainingAssignableAmount(for clothing: Clothing, entries: [WealthSavingEntry]) -> Decimal {
        let remaining = assignableSavingCap(for: clothing)
            - activeTotal(for: clothing.id, in: entries)
            - paidFinalPaymentTotal(for: clothing.id, in: entries)
        return max(remaining, Decimal(0))
    }

    static func overflowAmount(for clothing: Clothing, entries: [WealthSavingEntry]) -> Decimal {
        let overflow = activeTotal(for: clothing.id, in: entries)
            + paidFinalPaymentTotal(for: clothing.id, in: entries)
            - assignableSavingCap(for: clothing)
        return max(overflow, Decimal(0))
    }

    static func clampedSavingAmount(
        _ amount: Decimal,
        for clothing: Clothing,
        entries: [WealthSavingEntry]
    ) -> Decimal {
        guard amount > 0 else { return 0 }
        return min(amount, remainingAssignableAmount(for: clothing, entries: entries))
    }

    static func purchaseTarget(for clothing: Clothing) -> Decimal {
        let target: Decimal
        if clothing.isFullPaymentReservation {
            target = clothing.fullPaymentReservationTotalAmount
        } else if clothing.isDepositPlan {
            target = clothing.totalDeposit + clothing.totalBalance + clothing.resolvedShippingFee
        } else {
            target = clothing.inventoryTotalPrice
        }

        if target > 0 {
            return target
        }

        let fallback = clothing.price + clothing.resolvedAccessoriesPrice + clothing.resolvedShippingFee
        return max(fallback, clothing.totalBalance)
    }

    static func progressNumerator(for clothing: Clothing, entries: [WealthSavingEntry]) -> Decimal {
        let saved = activeTotal(for: clothing.id, in: entries)
        let paid = paidFinalPaymentTotal(for: clothing.id, in: entries)
        if clothing.isDepositPlan || paid > 0 || clothing.finalPaymentInstallmentCount > 0 {
            return clothing.totalDeposit + saved + paid
        } else {
            return saved
        }
    }

    static func progressRatio(for clothing: Clothing, entries: [WealthSavingEntry]) -> Double {
        let target = purchaseTarget(for: clothing)
        guard target > 0 else { return 0 }
        let numerator = progressNumerator(for: clothing, entries: entries)
        return NSDecimalNumber(decimal: numerator / target).doubleValue
    }

    @discardableResult
    @MainActor
    static func addSaving(
        amount: Decimal,
        clothingID: UUID?,
        note: String = "",
        context: ModelContext
    ) throws -> WealthSavingEntry? {
        guard amount > 0 else { return nil }
        let now = Date()
        let entry = WealthSavingEntry(
            amount: amount,
            clothingID: clothingID,
            note: note,
            createdAt: now
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    @discardableResult
    @MainActor
    static func addSaving(
        amount: Decimal,
        for clothing: Clothing,
        entries: [WealthSavingEntry],
        note: String = "",
        context: ModelContext
    ) throws -> WealthSavingEntry? {
        let actualAmount = clampedSavingAmount(amount, for: clothing, entries: entries)
        guard actualAmount > 0 else { return nil }
        return try addSaving(
            amount: actualAmount,
            clothingID: clothing.id,
            note: note,
            context: context
        )
    }

    @discardableResult
    @MainActor
    static func recordFinalPayment(
        amount requestedAmount: Decimal,
        for clothing: Clothing,
        entries: [WealthSavingEntry],
        mode: FinalPaymentMode,
        installmentCount requestedInstallmentCount: Int? = nil,
        context: ModelContext
    ) throws -> FinalPaymentRecordResult? {
        let remainingBefore = remainingFinalPaymentAmount(for: clothing, entries: entries)
        guard remainingBefore > 0, requestedAmount > 0 else { return nil }

        let now = Date()
        let paidRecordsBefore = finalPaymentRecords(for: clothing.id, in: entries)
        let planCount: Int
        let installmentIndex: Int
        switch mode {
        case .oneTime:
            planCount = clothing.finalPaymentInstallmentCount > 0 ? clothing.finalPaymentInstallmentCount : 1
            installmentIndex = max(paidRecordsBefore.count + 1, 1)
            if clothing.finalPaymentInstallmentCount <= 0 {
                clothing.finalPaymentInstallmentCount = 1
            }
        case .installment:
            let selectedCount = max(requestedInstallmentCount ?? clothing.finalPaymentInstallmentCount, 1)
            planCount = selectedCount
            clothing.finalPaymentInstallmentCount = selectedCount
            installmentIndex = min(paidRecordsBefore.count + 1, selectedCount)
        }

        let shouldSettleRemaining = mode == .oneTime || installmentIndex >= planCount
        let requestedForRecord = shouldSettleRemaining ? remainingBefore : requestedAmount
        let actualAmount = min(roundedCurrencyAmount(requestedForRecord), remainingBefore)
        guard actualAmount > 0 else { return nil }

        let targetSavingEntries = entries
            .filter { isActive($0) && $0.clothingID == clothing.id }
            .sorted { $0.createdAt < $1.createdAt }
        let deductedFromVault = consumeActiveSavingsForPayment(actualAmount, from: targetSavingEntries, at: now)
        let externalAmount = max(actualAmount - deductedFromVault, Decimal(0))

        let entry = WealthSavingEntry(
            amount: actualAmount,
            clothingID: clothing.id,
            note: mode == .oneTime ? "一次性付清尾款" : "第\(installmentIndex)/\(planCount)期尾款支付",
            entryKind: .finalPayment,
            finalPaymentMode: mode,
            installmentIndex: installmentIndex,
            installmentCount: planCount,
            paidAt: now,
            vaultDeductionAmount: deductedFromVault,
            externalPaymentAmount: externalAmount,
            createdAt: now
        )
        context.insert(entry)

        let paidTotal = paidFinalPaymentTotal(for: clothing.id, in: entries) + actualAmount
        let remainingAfter = max(finalPaymentDueAmount(for: clothing) - paidTotal, Decimal(0))
        let paidOff = remainingAfter <= 0

        if paidOff {
            moveAllActiveSavingsToUnassigned(
                for: clothing.id,
                clothingName: clothing.name,
                entries: entries,
                context: context,
                at: now
            )
            markClothingFinalPaymentCompleted(clothing, at: now)
        } else {
            clothing.updatedAt = now
            clothing.lastModified = now
        }

        try context.save()
        return FinalPaymentRecordResult(
            paymentEntry: entry,
            paidOff: paidOff,
            paidAmount: actualAmount,
            deductedFromVault: deductedFromVault,
            externalPaymentAmount: externalAmount,
            paidTotal: paidTotal,
            remainingAmount: remainingAfter
        )
    }

    @discardableResult
    @MainActor
    static func transferUnassignedSavings(
        to clothing: Clothing,
        entries: [WealthSavingEntry],
        context: ModelContext,
        note: String? = nil
    ) throws -> Decimal {
        let transferAmount = min(
            activeUnassignedTotal(in: entries),
            remainingAssignableAmount(for: clothing, entries: entries)
        )
        guard transferAmount > 0 else { return 0 }

        let now = Date()
        let unassignedEntries = entries
            .filter { isActive($0) && $0.clothingID == nil }
            .sorted { $0.createdAt < $1.createdAt }
        let movedAmount = consumeActiveAmount(transferAmount, from: unassignedEntries, at: now)
        guard movedAmount > 0 else { return 0 }

        let entry = WealthSavingEntry(
            amount: movedAmount,
            clothingID: clothing.id,
            note: note ?? "从未指定小金库填充「\(clothing.name)」",
            createdAt: now
        )
        context.insert(entry)
        try context.save()
        return movedAmount
    }

    @discardableResult
    @MainActor
    static func moveOverflowToUnassigned(
        for clothing: Clothing,
        entries: [WealthSavingEntry],
        context: ModelContext,
        note: String? = nil
    ) throws -> Decimal {
        let overflow = overflowAmount(for: clothing, entries: entries)
        guard overflow > 0 else { return 0 }

        let now = Date()
        let targetEntries = entries
            .filter { isActive($0) && $0.clothingID == clothing.id }
            .sorted { $0.createdAt > $1.createdAt }
        let movedAmount = consumeActiveAmount(overflow, from: targetEntries, at: now)
        guard movedAmount > 0 else { return 0 }

        let entry = WealthSavingEntry(
            amount: movedAmount,
            clothingID: nil,
            note: note ?? "从「\(clothing.name)」超额转回未指定",
            createdAt: now
        )
        context.insert(entry)
        try context.save()
        return movedAmount
    }

    @MainActor
    static func markActiveSavingsUsed(for clothingID: UUID, context: ModelContext, usedAt: Date = Date()) throws {
        let entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        markActiveSavingsUsed(for: clothingID, entries: entries, usedAt: usedAt)
        try context.save()
    }

    @MainActor
    static func markActiveSavingsUsed(
        for clothingID: UUID,
        entries: [WealthSavingEntry],
        usedAt: Date = Date()
    ) {
        for entry in entries where isActive(entry) && entry.clothingID == clothingID {
            entry.usedAt = usedAt
            entry.updatedAt = usedAt
            entry.lastModified = usedAt
        }
    }

    @MainActor
    static func migrateLegacySavedFinalPayments(
        clothings: [Clothing],
        entries: [WealthSavingEntry],
        context: ModelContext
    ) {
        var didInsert = false
        for clothing in clothings {
            guard clothing.isDepositPlan,
                  !clothing.isDeleted,
                  clothing.deletedAt == nil,
                  clothing.isFinalPaymentSavedToWealth,
                  clothing.totalBalance > 0 else {
                continue
            }

            let alreadyMigrated = entries.contains { entry in
                entry.clothingID == clothing.id &&
                entry.migrationSource == legacyFinalPaymentMigrationSource
            }
            guard !alreadyMigrated else { continue }

            let date = clothing.finalPaymentSavedAt ?? Date()
            let entry = WealthSavingEntry(
                amount: clothing.totalBalance,
                clothingID: clothing.id,
                note: "旧版整笔尾款小金库迁移",
                migrationSource: legacyFinalPaymentMigrationSource,
                createdAt: date
            )
            context.insert(entry)
            didInsert = true
        }

        if didInsert {
            try? context.save()
        }
    }

    @MainActor
    private static func markClothingFinalPaymentCompleted(_ clothing: Clothing, at date: Date) {
        clothing.isDepositPlan = false
        clothing.isFinalPaymentSavedToWealth = false
        clothing.finalPaymentSavedAt = nil
        clothing.depositDate = nil
        clothing.finalPaymentDate = nil
        clothing.finalPaymentEndDate = nil
        clothing.updatedAt = date
        clothing.lastModified = date
    }

    @MainActor
    private static func moveAllActiveSavingsToUnassigned(
        for clothingID: UUID,
        clothingName: String,
        entries: [WealthSavingEntry],
        context: ModelContext,
        at date: Date
    ) {
        let targetEntries = entries
            .filter { isActive($0) && $0.clothingID == clothingID }
            .sorted { $0.createdAt < $1.createdAt }
        let amount = activeTotal(for: clothingID, in: targetEntries)
        guard amount > 0 else { return }

        for entry in targetEntries {
            entry.voidedAt = date
            entry.updatedAt = date
            entry.lastModified = date
        }

        let unassigned = WealthSavingEntry(
            amount: amount,
            clothingID: nil,
            note: "「\(clothingName)」已付清后转回未指定",
            createdAt: date
        )
        context.insert(unassigned)
    }

    @MainActor
    private static func consumeActiveSavingsForPayment(
        _ amount: Decimal,
        from entries: [WealthSavingEntry],
        at date: Date
    ) -> Decimal {
        var remaining = amount
        var consumed = Decimal(0)

        for entry in entries where remaining > 0 && isActive(entry) {
            let entryAmount = entry.amount
            if entryAmount <= remaining {
                entry.usedAt = date
                entry.updatedAt = date
                entry.lastModified = date
                remaining -= entryAmount
                consumed += entryAmount
            } else {
                entry.amount = entryAmount - remaining
                entry.updatedAt = date
                entry.lastModified = date
                consumed += remaining
                remaining = 0
            }
        }

        return consumed
    }

    @MainActor
    private static func consumeActiveAmount(
        _ amount: Decimal,
        from entries: [WealthSavingEntry],
        at date: Date
    ) -> Decimal {
        var remaining = amount
        var consumed = Decimal(0)

        for entry in entries where remaining > 0 && isActive(entry) {
            let entryAmount = entry.amount
            if entryAmount <= remaining {
                entry.voidedAt = date
                entry.updatedAt = date
                entry.lastModified = date
                remaining -= entryAmount
                consumed += entryAmount
            } else {
                entry.amount = entryAmount - remaining
                entry.updatedAt = date
                entry.lastModified = date
                consumed += remaining
                remaining = 0
            }
        }

        return consumed
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
