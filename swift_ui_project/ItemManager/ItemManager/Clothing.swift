
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
    
    // 价格信息
    var price: Decimal = 0.0 // 裙子总价
    var deposit: Decimal = 0.0 // 定金
    var balance: Decimal = 0.0 // 尾款
    var accessoriesPrice: Decimal = 0.0 // 小物总价
    
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
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    @Relationship(deleteRule: .nullify)
    var tags: [Tag]? = []
    
    @Relationship(deleteRule: .nullify)
    var brand: Brand?
    
    init(name: String = "",
         brand: Brand? = nil,
         types: String = "",
         colors: String = "",
         sizes: String = "",
         length: String = "",
         condition: String = "全新",
         accessories: String = "",
         imagePaths: [String] = [],
         isShared: Bool = false,
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
    
    @Relationship(deleteRule: .nullify)
    var linkedClothing: Clothing?
    
    init(originalImageHash: String, 
         category: String = "未分类",
         imagePath: String,
         width: Double,
         height: Double,
         linkedClothing: Clothing? = nil) {
        self.originalImageHash = originalImageHash
        self.category = category
        self.imagePath = imagePath
        self.width = width
        self.height = height
        self.linkedClothing = linkedClothing
    }
}

@Model
final class Outfit {
    @Attribute(.unique) var id: UUID = UUID()
    var createdAt: Date = Date()
    var note: String = ""
    var snapshotPath: String? // Path to the saved OOTD image
    
    @Relationship(deleteRule: .cascade)
    var items: [OutfitItem] = []
    
    init(note: String = "", snapshotPath: String? = nil) {
        self.note = note
        self.snapshotPath = snapshotPath
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
    
    @Relationship
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
