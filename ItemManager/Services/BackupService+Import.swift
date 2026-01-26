//
//  BackupService+Import.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/26/26.
//

import Foundation
import SwiftData

extension BackupService {
    
    // MARK: - Import
    
    func importBackup(from url: URL, context: ModelContext) throws {
        print("### Import: Starting native-wrapper based import from \(url.path)")
        
        // 1. 读取备份文件数据
        let compressedData = try Data(contentsOf: url)
        if compressedData.isEmpty { 
            throw BackupError.invalidArchive 
        }
        
        // 2. 使用原生方案解压缩和还原打包目录 (内部映射 libcompression)
        print("### Import: Unwrapping package...")
        let fileMap = try NativePackageWrapper.unwrapPackage(data: compressedData)
        print("### Import: Unwrapped \(fileMap.count) files.")
        
        // 3. 提取 Manifest
        guard let manifestData = fileMap["manifest.json"] else {
            print("### Import: CRITICAL ERROR - manifest.json missing in fileMap.")
            throw BackupError.invalidArchive
        }
        
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        let manifest = try jsonDecoder.decode(BackupManifest.self, from: manifestData)
        
        // --- 开始分阶段恢复 ---
        
        // 阶段 1: 恢复图片文件
        print("--- Stage 1: Restoring Image Files ---")
        let imagesDir = ImageManager.shared.imagesDirectory
        for (fileName, data) in fileMap where fileName != "manifest.json" {
            let fileURL = imagesDir.appendingPathComponent(fileName)
            // 如果文件不存在，则写入。如果已存在，我们假设哈希一致，保持不变
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try? data.write(to: fileURL)
            }
        }
        
        // 阶段 2: 恢复基础模型 (Brand, Tag, StoredImage)
        print("--- Stage 2: Restoring Basis Models (Brands, Tags, StoredImages) ---")
        
        // 2a. Brands
        let existingBrands = try context.fetch(FetchDescriptor<Brand>())
        var brandMap: [UUID: Brand] = Dictionary(uniqueKeysWithValues: existingBrands.map { ($0.id, $0) })
        for dto in manifest.brands {
            if let existing = brandMap[dto.id] {
                existing.name = dto.name
                existing.colorHex = dto.colorHex
            } else {
                let newBrand = Brand(name: dto.name, colorHex: dto.colorHex)
                newBrand.id = dto.id
                context.insert(newBrand)
                brandMap[dto.id] = newBrand
            }
        }
        
        // 2b. Tags
        let existingTags = try context.fetch(FetchDescriptor<Tag>())
        var tagMap: [UUID: Tag] = Dictionary(uniqueKeysWithValues: existingTags.map { ($0.id, $0) })
        for dto in manifest.tags {
            if let existing = tagMap[dto.id] {
                existing.name = dto.name
                existing.colorHex = dto.colorHex
            } else {
                let newTag = Tag(name: dto.name, colorHex: dto.colorHex)
                newTag.id = dto.id
                context.insert(newTag)
                tagMap[dto.id] = newTag
            }
        }
        
        // 2c. StoredImages (Metadata)
        let existingImgMeta = try context.fetch(FetchDescriptor<StoredImage>())
        var imageMetaMap: [UUID: StoredImage] = Dictionary(uniqueKeysWithValues: existingImgMeta.map { ($0.id, $0) })
        for dto in manifest.storedImages {
            if let existing = imageMetaMap[dto.id] {
                existing.refCount = dto.refCount
                existing.fileName = dto.fileName
                existing.imageHash = dto.imageHash
            } else {
                let newImg = StoredImage(imageHash: dto.imageHash, fileName: dto.fileName)
                newImg.id = dto.id
                newImg.refCount = dto.refCount
                context.insert(newImg)
                imageMetaMap[dto.id] = newImg
            }
        }
        
        // 提交阶段 2
        try context.save()
        print("--- Stage 2 Complete ---")
        
        // 阶段 3: 恢复复杂模型与关系 (Clothing, CutoutItem, Outfit)
        print("--- Stage 3: Rebuilding Relationships ---")
        
        let existingClothings = try context.fetch(FetchDescriptor<Clothing>())
        var clothingMap: [UUID: Clothing] = Dictionary(uniqueKeysWithValues: existingClothings.map { ($0.id, $0) })
        
        for dto in manifest.clothings {
            let clothingBack: Clothing
            if let existing = clothingMap[dto.id] {
                clothingBack = existing
                // Update properties
                clothingBack.name = dto.name
                clothingBack.types = dto.types
                clothingBack.colors = dto.colors
                clothingBack.sizes = dto.sizes
                clothingBack.length = dto.length
                clothingBack.condition = dto.condition
                clothingBack.accessories = dto.accessories
                clothingBack.imagePaths = dto.imagePaths
                clothingBack.isShared = dto.isShared
                clothingBack.price = dto.price
                clothingBack.deposit = dto.deposit
                clothingBack.balance = dto.balance
                clothingBack.accessoriesPrice = dto.accessoriesPrice
                clothingBack.purchaseDate = dto.purchaseDate
                clothingBack.depositDate = dto.depositDate
                clothingBack.isDepositPlan = dto.isDepositPlan
                clothingBack.finalPaymentDate = dto.finalPaymentDate
                clothingBack.finalPaymentEndDate = dto.finalPaymentEndDate
                clothingBack.note = dto.note
                clothingBack.stock = dto.stock
                clothingBack.status = ClothingStatus(rawValue: dto.status) ?? .onShelf
                clothingBack.createdAt = dto.createdAt
                clothingBack.updatedAt = dto.updatedAt
            } else {
                clothingBack = Clothing(name: dto.name)
                clothingBack.id = dto.id
                context.insert(clothingBack)
                clothingMap[dto.id] = clothingBack
                
                clothingBack.name = dto.name
                clothingBack.types = dto.types
                clothingBack.colors = dto.colors
                clothingBack.sizes = dto.sizes
                clothingBack.length = dto.length
                clothingBack.condition = dto.condition
                clothingBack.accessories = dto.accessories
                clothingBack.imagePaths = dto.imagePaths
                clothingBack.isShared = dto.isShared
                clothingBack.price = dto.price
                clothingBack.deposit = dto.deposit
                clothingBack.balance = dto.balance
                clothingBack.accessoriesPrice = dto.accessoriesPrice
                clothingBack.purchaseDate = dto.purchaseDate
                clothingBack.depositDate = dto.depositDate
                clothingBack.isDepositPlan = dto.isDepositPlan
                clothingBack.finalPaymentDate = dto.finalPaymentDate
                clothingBack.finalPaymentEndDate = dto.finalPaymentEndDate
                clothingBack.note = dto.note
                clothingBack.stock = dto.stock
                clothingBack.status = ClothingStatus(rawValue: dto.status) ?? .onShelf
                clothingBack.createdAt = dto.createdAt
                clothingBack.updatedAt = dto.updatedAt
            }
            
            // Re-link Brand
            if let brandID = dto.brandID {
                clothingBack.brand = brandMap[brandID]
            } else {
                clothingBack.brand = nil
            }
            clothingBack.tags = dto.tagIDs.compactMap { tagMap[$0] }
        }
        
        // Cutouts
        let existingCutouts = try context.fetch(FetchDescriptor<CutoutItem>())
        var cutoutMap: [UUID: CutoutItem] = Dictionary(uniqueKeysWithValues: existingCutouts.map { ($0.id, $0) })
        for dto in manifest.cutouts {
            let cutout: CutoutItem
            if let existing = cutoutMap[dto.id] {
                cutout = existing
                cutout.category = dto.category
                cutout.imagePath = dto.imagePath
                cutout.width = dto.width
                cutout.height = dto.height
                cutout.timestamp = dto.timestamp
            } else {
                cutout = CutoutItem(originalImageHash: dto.originalImageHash, category: dto.category, imagePath: dto.imagePath, width: dto.width, height: dto.height)
                cutout.id = dto.id
                context.insert(cutout)
                cutoutMap[dto.id] = cutout
                cutout.timestamp = dto.timestamp
            }
            if let lid = dto.linkedClothingID {
                cutout.linkedClothing = clothingMap[lid]
            } else {
                cutout.linkedClothing = nil
            }
        }
        
        // Outfits
        let existingOutfits = try context.fetch(FetchDescriptor<Outfit>())
        var outfitMap: [UUID: Outfit] = Dictionary(uniqueKeysWithValues: existingOutfits.map { ($0.id, $0) })
        for dto in manifest.outfits {
            let outfit: Outfit
            if let existing = outfitMap[dto.id] {
                outfit = existing
                outfit.note = dto.note
                outfit.snapshotPath = dto.snapshotPath
            } else {
                outfit = Outfit(note: dto.note, snapshotPath: dto.snapshotPath)
                outfit.id = dto.id
                outfit.createdAt = dto.createdAt
                context.insert(outfit)
                outfitMap[dto.id] = outfit
            }
            
            let existingItems = outfit.items
            var itemMap: [UUID: OutfitItem] = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
            for itemDTO in dto.items {
                let item: OutfitItem
                if let ex = itemMap[itemDTO.id] {
                    item = ex
                    item.x = itemDTO.x
                    item.y = itemDTO.y
                    item.rotation = itemDTO.rotation
                    item.scale = itemDTO.scale
                    item.zIndex = itemDTO.zIndex
                } else {
                    item = OutfitItem(cutout: nil, x: itemDTO.x, y: itemDTO.y, rotation: itemDTO.rotation, scale: itemDTO.scale, zIndex: itemDTO.zIndex)
                    item.id = itemDTO.id
                    context.insert(item)
                    item.outfit = outfit
                }
                if let cid = itemDTO.cutoutID {
                    item.cutout = cutoutMap[cid]
                }
            }
        }
        
        try context.save()
        print("--- Import Successful! ---")
    }
}
