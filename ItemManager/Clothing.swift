
//
//  Clothing.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import Foundation
import SwiftData
import SwiftUI

enum ClothingStatus: String, Codable, CaseIterable, Identifiable {
    case onShelf = "上架"
    case offShelf = "下架"
    
    var id: Self { self }
}

@Model
final class Clothing {
    @Attribute(.unique) var id: UUID = UUID()
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
    var isShared: Bool = false // 同步到裙子广场
    var replacedCutoutID: UUID? = nil // 记录替换主图所使用的抠图 ID
    
    // 价格信息
    var originalPrice: Decimal = 0.0 // 原价
    var price: Decimal = 0.0 // 裙子总价
    var deposit: Decimal = 0.0 // 定金
    var balance: Decimal = 0.0 // 尾款
    var accessoriesPrice: Decimal = 0.0 // 小物总价
    var sortIndex: Int = 0 // 自定义排序索引
    
    // 购买信息
    var purchaseDate: Date = Date()
    var depositDate: Date? = nil // 定金日期
    var isDepositPlan: Bool = false // 是否加入尾款天使
    var finalPaymentDate: Date? = nil // 预估尾款时间（开始）
    var finalPaymentEndDate: Date? = nil // 预估尾款时间（结束）
    var note: String = ""
    
    // 系统信息
    var stock: Int = 1
    var status: ClothingStatus = ClothingStatus.onShelf
    var isDeleted: Bool = false // 软删除标记
    var deletedAt: Date? = nil // 删除时间
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    @Relationship(deleteRule: .nullify)
    var tags: [Tag]? = []
    
    @Relationship(deleteRule: .nullify)
    var brand: Brand?
    
    @Relationship(deleteRule: .cascade)
    var accessoryItems: [AccessoryItem]? = []
    
    // Removed direct relationship to prevent SwiftData side effects on deletion
    // var cutouts: [CutoutItem] = []
    
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
         price: Decimal = 0.0,
         deposit: Decimal = 0.0,
         balance: Decimal = 0.0,
         accessoriesPrice: Decimal = 0.0,
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
        self.price = price
        self.deposit = deposit
        self.balance = balance
        self.accessoriesPrice = accessoriesPrice
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
    var totalDeposit: Decimal {
        let accDeposit = accessoryItems?.reduce(Decimal(0)) { $0 + $1.deposit } ?? 0
        return deposit + accDeposit
    }
    
    var totalBalance: Decimal {
        let accBalance = accessoryItems?.reduce(Decimal(0)) { $0 + $1.balance } ?? 0
        return balance + accBalance
    }
}

@Model
final class AccessoryItem {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var price: Decimal = 0.0
    var deposit: Decimal = 0.0 // 定金
    var balance: Decimal = 0.0 // 尾款
    var sortIndex: Int = 0
    
    init(name: String, price: Decimal, deposit: Decimal = 0.0, balance: Decimal = 0.0, sortIndex: Int = 0) {
        self.name = name
        self.price = price
        self.deposit = deposit
        self.balance = balance
        self.sortIndex = sortIndex
    }
}

// MARK: - OOTD Models
// Moved here to ensure availability in all targets (e.g., Widget Extension)

@Model
final class CutoutItem {
    @Attribute(.unique) var id: UUID = UUID()
    var originalImageHash: String = ""
    var timestamp: Date = Date()
    var category: String = "未分类" // e.g., 裙装, 上衣, etc.
    var imagePath: String = "" // Path to the cutout image (PNG with transparency)
    var width: Double = 0.0
    var height: Double = 0.0
    
    // 缓存裙子名字，方便在画布中显示（即使原 Clothing 被删除）
    var clothingName: String?
    
    // Use ID instead of Relationship to decouple deletion lifecycle
    var linkedClothingID: UUID?
    
    @Relationship(deleteRule: .nullify, inverse: \OutfitItem.cutout)
    var outfitItems: [OutfitItem] = []
    
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
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var coverImage: String? // Optional custom cover
    var createdAt: Date = Date()
    var isDeleted: Bool = false
    var deletedAt: Date? = nil
    
    @Relationship(deleteRule: .cascade, inverse: \Outfit.book)
    var pages: [Outfit] = []
    
    init(title: String, coverImage: String? = nil) {
        self.title = title
        self.coverImage = coverImage
        self.createdAt = Date()
    }
}

@Model
final class Outfit {
    @Attribute(.unique) var id: UUID = UUID()
    var createdAt: Date = Date()
    var note: String = ""
    var snapshotPath: String? // Path to the saved OOTD image
    var canvasType: String = "mannequin" // "mannequin" or "blank"
    var backgroundImagePath: String? // Custom background image path
    var sortIndex: Int = 0 // Custom order index
    
    // Trash Bin Logic
    var isDeleted: Bool = false
    var deletedAt: Date? = nil
    
    @Relationship
    var book: BookGroup?
    
    @Relationship(deleteRule: .cascade)
    var items: [OutfitItem] = []
    
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
    @Attribute(.unique) var id: UUID = UUID()
    var x: Double = 0.0
    var y: Double = 0.0
    var rotation: Double = 0.0
    var scale: Double = 1.0
    var zIndex: Int = 0
    
    var cutout: CutoutItem?
    
    @Relationship
    var outfit: Outfit?
    
    init(cutout: CutoutItem?, x: Double, y: Double, rotation: Double, scale: Double, zIndex: Int) {
        self.cutout = cutout
        self.x = x
        self.y = y
        self.rotation = rotation
        self.scale = scale
        self.zIndex = zIndex
    }
}

// MARK: - 3D Space OOTD Models

@Model
final class SpaceBookGroup {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var coverImage: String? // Optional custom cover
    var createdAt: Date = Date()
    var isDeleted: Bool = false
    var deletedAt: Date? = nil
    
    @Relationship(deleteRule: .cascade, inverse: \SpaceOutfit.book)
    var pages: [SpaceOutfit] = []
    
    init(title: String, coverImage: String? = nil) {
        self.title = title
        self.coverImage = coverImage
        self.createdAt = Date()
    }
}

@Model
final class SpaceOutfit {
    @Attribute(.unique) var id: UUID = UUID()
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
    
    @Relationship
    var book: SpaceBookGroup?
    
    init(note: String = "", snapshotPath: String? = nil, book: SpaceBookGroup? = nil, sortIndex: Int = 0) {
        self.note = note
        self.snapshotPath = snapshotPath
        self.book = book
        self.createdAt = Date()
        self.sortIndex = sortIndex
    }
}
