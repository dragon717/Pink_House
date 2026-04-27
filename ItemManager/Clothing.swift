
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

    init(note: String = "", snapshotPath: String? = nil, canvasType: String = "mannequin", backgroundImagePath: String? = nil, book: BookGroup? = nil) {
        self.note = note
        self.snapshotPath = snapshotPath
        self.canvasType = canvasType
        self.backgroundImagePath = backgroundImagePath
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
