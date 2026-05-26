//
//  ImportManager.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/18/26.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

// MARK: - Backup Data Models
// 用于解析备份文件的临时模型
private struct BackupRoot: Codable {
    let brands: [BackupBrand]?
    let categories: [BackupCategory]?
    let items: [BackupItem]?
    let images: [String: String]? // UID: Base64String
    // 其他字段如 sizes, colors 等暂时忽略，直接使用 item 中的字符串值
}

private struct BackupBrand: Codable {
    let id: String
    let name: String
    let logoImageUID: String?
}

private struct BackupCategory: Codable {
    let id: String
    let name: String
}

private struct BackupItem: Codable {
    let id: String
    let name: String
    let brandId: String
    let categoryId: String // 对应 Tag 或 Type
    let num: Int
    let color: String
    let size: String
    let length: String
    let preservationStatus: String // 对应 condition
    let purchaseDate: String?
    let notes: String
    let preservationNotes: String?
    let paymentInfo: [String: BackupPaymentInfo]?
    let isDepositMode: Bool
    let originalPrice: Double
    let isFavorite: Bool
    let imageUIDs: [String]
    let noteImageUIDs: [String]
    let displayImageUids: [String]
    let createDate: String
    
    // 辅助计算属性
    var allImageUIDs: [String] {
        var uids = imageUIDs
        uids.append(contentsOf: displayImageUids)
        // 去重
        return Array(Set(uids))
    }
}

private struct BackupPaymentInfo: Codable {
    let amount: Double
    let isPaid: Bool
    let paymentDate: String?
}

// MARK: - Import Manager
@MainActor
class ImportManager {
    static let shared = ImportManager()
    
    private init() {}
    
    struct ImportResult {
        var successCount: Int = 0
        var failCount: Int = 0
        var errors: [String] = []
    }
    
    func importBackup(from url: URL, context: ModelContext) async throws -> ImportResult {
        var result = ImportResult()
        
        // 1. 读取并解析 JSON
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let backup = try decoder.decode(BackupRoot.self, from: data)
        
        // 2. 准备数据映射缓存
        var brandMap: [String: Brand] = [:] // BackupID : Brand Entity
        var tagMap: [String: Tag] = [:] // BackupCategoryID : Tag Entity (或 Name : Tag)
        
        // 3. 导入品牌
        if let backupBrands = backup.brands {
            let existingBrands = try context.fetch(FetchDescriptor<Brand>())
            
            for bBrand in backupBrands {
                // 查找是否已存在同名或同ID品牌
                if let existing = existingBrands.first(where: { $0.name == bBrand.name }) {
                    brandMap[bBrand.id] = existing
                } else {
                    let newBrand = Brand(name: bBrand.name)
                    // 尝试保持 ID 一致性（如果 Brand ID 是可变的，这里 Brand 使用 UUID 自动生成，所以我们无法强制设置 ID，只能新建）
                    // 如果 Brand 模型允许设置 ID，可以 newBrand.id = UUID(uuidString: bBrand.id)
                    context.insert(newBrand)
                    brandMap[bBrand.id] = newBrand
                }
            }
        }
        
        // 4. 导入分类 (作为 Tag)
        if let backupCategories = backup.categories {
            let existingTags = try context.fetch(FetchDescriptor<Tag>())
            
            for bCat in backupCategories {
                if let existing = existingTags.first(where: { $0.name == bCat.name }) {
                    tagMap[bCat.id] = existing
                } else {
                    let newTag = Tag(name: bCat.name)
                    context.insert(newTag)
                    tagMap[bCat.id] = newTag
                }
            }
        }
        
        // 5. 导入物品
        if let backupItems = backup.items {
            let dateFormatter = ISO8601DateFormatter()
            // 兼容可能的不带毫秒的格式
            let dateFormatter2 = DateFormatter()
            dateFormatter2.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            
            func parseDate(_ string: String?) -> Date? {
                guard let string = string, !string.isEmpty else { return nil }
                return dateFormatter.date(from: string) ?? dateFormatter2.date(from: string)
            }
            
            for bItem in backupItems {
                do {
                    let clothing = Clothing(name: bItem.name)
                    
                    // 基础信息
                    // clothing.name = bItem.name // Set via init
                    clothing.stock = FinancialDataSanitizer.stock(bItem.num)
                    
                    // 关联品牌
                    if let brand = brandMap[bItem.brandId] {
                        clothing.brand = brand
                    }
                    
                    // 关联标签/分类
                    // 原有分类作为 Tag
                    if let tag = tagMap[bItem.categoryId] {
                        clothing.tags = [tag]
                    }
                    // 同时将分类名称写入 types，以兼容 SuggestionManager
                    if let catName = backup.categories?.first(where: { $0.id == bItem.categoryId })?.name {
                        clothing.types = catName
                    }
                    
                    // 属性
                    clothing.colors = bItem.color
                    clothing.sizes = bItem.size
                    clothing.length = bItem.length
                    clothing.condition = bItem.preservationStatus.isEmpty ? "全新" : bItem.preservationStatus
                    clothing.note = bItem.notes
                    
                    // 日期
                    if let date = parseDate(bItem.purchaseDate) {
                        clothing.purchaseDate = date
                    }
                    if let date = parseDate(bItem.createDate) {
                        clothing.createdAt = date
                    }
                    
                    // 价格与支付信息
                    clothing.price = FinancialDataSanitizer.money(bItem.originalPrice)
                    clothing.isDepositPlan = bItem.isDepositMode
                    
                    if let paymentInfo = bItem.paymentInfo {
                        // 映射支付信息
                        // 假设 key "定金" -> deposit, "尾款" -> balance
                        // 注意：这里 key 可能是中文 "定金", "尾款"
                        
                        if let depositInfo = paymentInfo["定金"] {
                            clothing.deposit = FinancialDataSanitizer.money(depositInfo.amount)
                            if let date = parseDate(depositInfo.paymentDate) {
                                clothing.depositDate = date
                            }
                        }
                        
                        if let balanceInfo = paymentInfo["尾款"] {
                            clothing.balance = FinancialDataSanitizer.money(balanceInfo.amount)
                            // finalPaymentDate 逻辑比较复杂，这里简单映射
                        }
                    }
                    
                    // 图片处理
                    if let imageDict = backup.images {
                        var importedImagePaths: [String] = []
                        
                        // 优先处理 displayImageUids (展示图)
                        for uid in bItem.displayImageUids {
                            if let base64 = imageDict[uid],
                               let data = Data(base64Encoded: base64),
                               let image = UIImage(data: data) {
                                
                                if let fileName = ImageManager.shared.saveImage(image, context: context) {
                                    importedImagePaths.append(fileName)
                                }
                            }
                        }
                        
                        // 处理其他 imageUIDs
                        for uid in bItem.imageUIDs {
                            // 避免重复导入展示图
                            if !bItem.displayImageUids.contains(uid) {
                                if let base64 = imageDict[uid],
                                   let data = Data(base64Encoded: base64),
                                   let image = UIImage(data: data) {
                                    
                                    if let fileName = ImageManager.shared.saveImage(image, context: context) {
                                        importedImagePaths.append(fileName)
                                    }
                                }
                            }
                        }
                        
                        clothing.imagePaths = importedImagePaths
                    }
                    
                    context.insert(clothing)
                    result.successCount += 1
                    
                } catch {
                    result.failCount += 1
                    result.errors.append("Item \(bItem.name) failed: \(error.localizedDescription)")
                }
            }
        }
        
        // 保存上下文
        try context.save()
        
        // Sync widget data
        Task { await SharedPersistence.shared.syncWidgetData() }
        
        return result
    }
}
