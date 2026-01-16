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
         accessories: String = "",
         imagePaths: [String] = [],
         isShared: Bool = false,
         price: Decimal = 0.0,
         deposit: Decimal = 0.0,
         balance: Decimal = 0.0,
         accessoriesPrice: Decimal = 0.0,
         purchaseDate: Date = Date(),
         note: String = "",
         stock: Int = 1,
         status: ClothingStatus = .onShelf) {
        self.id = UUID()
        self.name = name
        self.brand = brand
        self.types = types
        self.colors = colors
        self.sizes = sizes
        self.accessories = accessories
        self.imagePaths = imagePaths
        self.isShared = isShared
        self.price = price
        self.deposit = deposit
        self.balance = balance
        self.accessoriesPrice = accessoriesPrice
        self.purchaseDate = purchaseDate
        self.note = note
        self.stock = stock
        self.status = status
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
