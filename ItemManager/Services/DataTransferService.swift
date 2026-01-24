//
//  DataTransferService.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/25/26.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - DTOs for Backup/Restore

struct BackupData: Codable {
    let version: Int
    let timestamp: Date
    let brands: [BrandDTO]
    let tags: [TagDTO]
    let clothings: [ClothingDTO]
    let storedImages: [StoredImageDTO]
    let cutouts: [CutoutDTO]
    let outfits: [OutfitDTO]
    let outfitItems: [OutfitItemDTO]
}

struct BrandDTO: Codable {
    let id: UUID
    let name: String
    let colorHex: String
}

struct TagDTO: Codable {
    let id: UUID
    let name: String
    let colorHex: String
}

struct ClothingDTO: Codable {
    let id: UUID
    let name: String
    let brandId: UUID?
    let tagIds: [UUID]
    let types: String
    let colors: String
    let sizes: String
    let length: String
    let condition: String
    let accessories: String
    let imagePaths: [String]
    let isShared: Bool
    let price: Decimal
    let deposit: Decimal
    let balance: Decimal
    let accessoriesPrice: Decimal
    let purchaseDate: Date
    let depositDate: Date?
    let isDepositPlan: Bool
    let finalPaymentDate: Date?
    let finalPaymentEndDate: Date?
    let note: String
    let stock: Int
    let status: ClothingStatus
    let createdAt: Date
    let updatedAt: Date
}

struct StoredImageDTO: Codable {
    let id: UUID
    let imageHash: String
    let fileName: String
    let refCount: Int
    let createdAt: Date
    let updatedAt: Date
}

struct CutoutDTO: Codable {
    let id: UUID
    let originalImageHash: String
    let timestamp: Date
    let category: String
    let imagePath: String
    let width: Double
    let height: Double
    let linkedClothingId: UUID?
}

struct OutfitDTO: Codable {
    let id: UUID
    let createdAt: Date
    let note: String
    let snapshotPath: String?
    let itemIds: [UUID]
}

struct OutfitItemDTO: Codable {
    let id: UUID
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let zIndex: Int
    let cutoutId: UUID?
    let outfitId: UUID?
}

// MARK: - DataTransferService

@MainActor
class DataTransferService {
    static let shared = DataTransferService()
    
    private init() {}
    
    // MARK: - CSV Export
    
    func exportToCSV(context: ModelContext) throws -> URL {
        let descriptor = FetchDescriptor<Clothing>(sortBy: [SortDescriptor(\.purchaseDate, order: .reverse)])
        let clothings = try context.fetch(descriptor)
        
        var csvString = "名称,品牌,标签,类型,颜色,尺码,衣长,状态,小物,价格,定金,尾款,购买日期,定金日期,尾款开始,尾款截止,备注,库存\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for item in clothings {
            let brandName = item.brand?.name ?? ""
            let tagNames = item.tags?.map { $0.name }.joined(separator: ";") ?? ""
            let purchaseDateStr = dateFormatter.string(from: item.purchaseDate)
            
            let depositDateStr = item.depositDate.map { dateFormatter.string(from: $0) } ?? ""
            let finalPaymentStartStr = item.finalPaymentDate.map { dateFormatter.string(from: $0) } ?? ""
            let finalPaymentEndStr = item.finalPaymentEndDate.map { dateFormatter.string(from: $0) } ?? ""
            
            let row: [String] = [
                escapeCSV(item.name),
                escapeCSV(brandName),
                escapeCSV(tagNames),
                escapeCSV(item.types),
                escapeCSV(item.colors),
                escapeCSV(item.sizes),
                escapeCSV(item.length),
                escapeCSV(item.condition),
                escapeCSV(item.accessories),
                "\(item.price)",
                "\(item.deposit)",
                "\(item.balance)",
                purchaseDateStr,
                depositDateStr,
                finalPaymentStartStr,
                finalPaymentEndStr,
                escapeCSV(item.note),
                "\(item.stock)"
            ]
            
            csvString.append(row.joined(separator: ",") + "\n")
        }
        
        let fileName = "PinkHouse_Export_\(Int(Date().timeIntervalSince1970)).csv"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    private func escapeCSV(_ text: String) -> String {
        var newText = text.replacingOccurrences(of: "\"", with: "\"\"")
        if newText.contains(",") || newText.contains("\n") || newText.contains("\"") {
            newText = "\"\(newText)\""
        }
        return newText
    }
    
    // MARK: - Backup
    
    func createBackup(context: ModelContext) throws -> URL {
        // Fetch all data
        let brands = try context.fetch(FetchDescriptor<Brand>())
        let tags = try context.fetch(FetchDescriptor<Tag>())
        let clothings = try context.fetch(FetchDescriptor<Clothing>())
        
        // Convert to DTOs
        let brandDTOs = brands.map { BrandDTO(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        let tagDTOs = tags.map { TagDTO(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        let clothingDTOs = clothings.map { clothing in
            ClothingDTO(
                id: clothing.id,
                name: clothing.name,
                brandId: clothing.brand?.id,
                tagIds: clothing.tags?.map { $0.id } ?? [],
                types: clothing.types,
                colors: clothing.colors,
                sizes: clothing.sizes,
                length: clothing.length,
                condition: clothing.condition,
                accessories: clothing.accessories,
                imagePaths: clothing.imagePaths,
                isShared: clothing.isShared,
                price: clothing.price,
                deposit: clothing.deposit,
                balance: clothing.balance,
                accessoriesPrice: clothing.accessoriesPrice,
                purchaseDate: clothing.purchaseDate,
                depositDate: clothing.depositDate,
                isDepositPlan: clothing.isDepositPlan,
                finalPaymentDate: clothing.finalPaymentDate,
                finalPaymentEndDate: clothing.finalPaymentEndDate,
                note: clothing.note,
                stock: clothing.stock,
                status: clothing.status,
                createdAt: clothing.createdAt,
                updatedAt: clothing.updatedAt
            )
        }
        
        let backupData = BackupData(
            version: 1,
            timestamp: Date(),
            brands: brandDTOs,
            tags: tagDTOs,
            clothings: clothingDTOs,
            storedImages: [], // 暂时为空
            cutouts: [], // 暂时为空
            outfits: [], // 暂时为空
            outfitItems: [] // 暂时为空
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(backupData)
        
        let fileName = "PinkHouse_Backup_\(Int(Date().timeIntervalSince1970)).json"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try data.write(to: fileURL)
        return fileURL
    }
    
    // MARK: - Restore
    
    func restoreBackup(from url: URL, context: ModelContext) async throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backupData = try decoder.decode(BackupData.self, from: data)
        
        // Clear existing data
        try context.delete(model: Clothing.self)
        try context.delete(model: Brand.self)
        try context.delete(model: Tag.self)
        // Note: Outfit/CutoutItem are not in this backup yet, might need to handle them later or clear them too
        
        // Save to apply deletions
        try context.save()
        
        // Restore Brands
        var brandMap: [UUID: Brand] = [:]
        for dto in backupData.brands {
            let brand = Brand(name: dto.name, colorHex: dto.colorHex)
            brand.id = dto.id
            context.insert(brand)
            brandMap[dto.id] = brand
        }
        
        // Restore Tags
        var tagMap: [UUID: Tag] = [:]
        for dto in backupData.tags {
            let tag = Tag(name: dto.name, colorHex: dto.colorHex)
            tag.id = dto.id
            context.insert(tag)
            tagMap[dto.id] = tag
        }
        
        // Restore Clothings
        for dto in backupData.clothings {
            let clothing = Clothing(
                name: dto.name,
                brand: nil, // Link later
                types: dto.types,
                colors: dto.colors,
                sizes: dto.sizes,
                length: dto.length,
                condition: dto.condition,
                accessories: dto.accessories,
                imagePaths: dto.imagePaths,
                isShared: dto.isShared,
                price: dto.price,
                deposit: dto.deposit,
                balance: dto.balance,
                accessoriesPrice: dto.accessoriesPrice,
                purchaseDate: dto.purchaseDate,
                depositDate: dto.depositDate,
                isDepositPlan: dto.isDepositPlan,
                finalPaymentDate: dto.finalPaymentDate,
                finalPaymentEndDate: dto.finalPaymentEndDate,
                note: dto.note,
                stock: dto.stock,
                status: dto.status
            )
            clothing.id = dto.id
            clothing.createdAt = dto.createdAt
            clothing.updatedAt = dto.updatedAt
            
            // Link relationships
            if let brandId = dto.brandId, let brand = brandMap[brandId] {
                clothing.brand = brand
            }
            
            clothing.tags = dto.tagIds.compactMap { tagMap[$0] }
            
            context.insert(clothing)
        }
        
        try context.save()
    }
}
