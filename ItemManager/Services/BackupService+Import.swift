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
        print("### Import: Starting import from \(url.path)")
        
        // 1. Read Data
        let compressedData: Data
        do {
            compressedData = try Data(contentsOf: url, options: [])
        } catch {
            print("### Import: Failed to read file: \(error)")
            throw error
        }
        
        let fileSize = compressedData.count
        print("### Import: File size is \(fileSize) bytes")
        
        if fileSize < 5 {
            throw BackupError.invalidArchive
        }
        
        // Check magic bytes for diagnostic
        let checkSize = min(compressedData.count, 64)
        let headerData = compressedData.prefix(checkSize)
        let hexString = headerData.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("### Import: Header Hex (64 bytes): \(hexString)")
        
        // Check for all-zero block
        if headerData.count >= 32 && headerData.prefix(32).allSatisfy({ $0 == 0 }) {
            print("### Import: DETECTED CORRUPTED ALL-ZERO HEADER!")
            throw BackupError.corruptedArchive(reason: "文件头全为零，备份可能已损坏或未正确生成。")
        }
        
        // 2. 强制解压逻辑：不再校验任何魔数，直接尝试 LZFSE 解压
        print("### Import: Attempting mandatory LZFSE decompression...")
        
        var tarData: Data
        do {
            tarData = try (compressedData as NSData).decompressed(using: .lzfse) as Data
            print("### Import: LZFSE decompression success, size: \(tarData.count) bytes")
        } catch {
            print("### Import: LZFSE decompression failed: \(error). Using raw data as fallback...")
            // 如果 LZFSE 失败，可能文件本身就是未压缩的或者是由于更名导致的
            tarData = compressedData
        }
        
        // 验证数据是否为空
        if tarData.isEmpty {
            throw BackupError.decompressionFailed(reason: "解压后数据为空")
        }
        
        // 3. Extract TAR
        let entries = TarReader.extract(data: tarData)
        print("### Import: Extracted \(entries.count) entries from TAR")
        
        // 4. Find Manifest with Fallback
        var manifestData: Data? = entries.first(where: { $0.name == "manifest.json" })?.data
        
        if manifestData == nil {
            print("### Import: manifest.json not found in TAR. Starting force extraction...")
            manifestData = forceExtractManifestFallback(from: tarData)
        }
        
        guard let finalManifestData = manifestData else {
            print("### Import: All manifest extraction attempts failed.")
            throw BackupError.invalidArchive
        }
        
        // 5. Restore Images (Even if TAR is partially broken, some files might still be there)
        let imagesDir = ImageManager.shared.imagesDirectory
        for entry in entries where entry.name != "manifest.json" {
            let fileURL = imagesDir.appendingPathComponent(entry.name)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try? entry.data.write(to: fileURL)
            }
        }
        
        // 6. Restore Data
        try importFromManifestData(finalManifestData, context: context)
    }

    /// 强制提取：在二进制数据中暴力搜索符合 manifest 签名的 JSON 块
    func forceExtractManifestFallback(from data: Data) -> Data? {
        // 寻找包含特定 Key 的 JSON 结构，例如 "brands": 或 "clothings":
        guard let brandsMarker = "\"brands\":".data(using: .utf8) else { return nil }
        
        var searchOffset = 0
        while let range = data.range(of: brandsMarker, options: [], in: searchOffset..<data.count) {
            // 寻找包含 marker 的最小有效 JSON 对象
            // 经验法则：Manifest 通常以 {"version" 开头
            if let startRange = data.range(of: "{\"version\":\"".data(using: .utf8)!, options: .backwards, in: 0..<range.lowerBound) {
                let possibleStart = startRange.lowerBound
                for length in 512..<min(5000000, data.count - possibleStart) { // 限制在 5MB 以内
                    let candidate = data.subdata(in: possibleStart..<possibleStart+length)
                    if let lastBrace = candidate.lastIndex(where: { $0 == 125 }) { // '}'
                        let trimmedCandidate = candidate.prefix(through: lastBrace)
                        if (try? JSONSerialization.jsonObject(with: trimmedCandidate)) != nil {
                            print("### Import: Forced search success at offset \(possibleStart), length \(trimmedCandidate.count)")
                            return trimmedCandidate
                        }
                    }
                }
            }
            searchOffset = range.upperBound
        }
        return nil
    }

    func importFromManifestData(_ data: Data, context: ModelContext) throws {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        let manifest = try jsonDecoder.decode(BackupManifest.self, from: data)
        
        print("### Import: Restoring manifest (Version: \(manifest.version), Clothings: \(manifest.clothingCount))")
        
        // Restore Brands
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
        
        // Restore Tags
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
        
        // Restore StoredImages (Metadata)
        let existingImages = try context.fetch(FetchDescriptor<StoredImage>())
        var imageMap: [UUID: StoredImage] = Dictionary(uniqueKeysWithValues: existingImages.map { ($0.id, $0) })
        
        for dto in manifest.storedImages {
            if let existing = imageMap[dto.id] {
                existing.refCount = dto.refCount
                existing.fileName = dto.fileName
                existing.imageHash = dto.imageHash
            } else {
                let newImage = StoredImage(imageHash: dto.imageHash, fileName: dto.fileName)
                newImage.id = dto.id
                newImage.refCount = dto.refCount
                context.insert(newImage)
                imageMap[dto.id] = newImage
            }
        }
        
        // Restore Clothing
        let existingClothings = try context.fetch(FetchDescriptor<Clothing>())
        var clothingMap: [UUID: Clothing] = Dictionary(uniqueKeysWithValues: existingClothings.map { ($0.id, $0) })
        
        for dto in manifest.clothings {
            let clothing: Clothing
            if let existing = clothingMap[dto.id] {
                clothing = existing
                clothing.name = dto.name
                clothing.types = dto.types
                clothing.colors = dto.colors
                clothing.sizes = dto.sizes
                clothing.length = dto.length
                clothing.condition = dto.condition
                clothing.accessories = dto.accessories
                clothing.imagePaths = dto.imagePaths
                clothing.isShared = dto.isShared
                clothing.price = dto.price
                clothing.deposit = dto.deposit
                clothing.balance = dto.balance
                clothing.accessoriesPrice = dto.accessoriesPrice
                clothing.purchaseDate = dto.purchaseDate
                clothing.depositDate = dto.depositDate
                clothing.isDepositPlan = dto.isDepositPlan
                clothing.finalPaymentDate = dto.finalPaymentDate
                clothing.finalPaymentEndDate = dto.finalPaymentEndDate
                clothing.note = dto.note
                clothing.stock = dto.stock
                clothing.status = ClothingStatus(rawValue: dto.status) ?? .onShelf
                clothing.createdAt = dto.createdAt
                clothing.updatedAt = dto.updatedAt
            } else {
                clothing = Clothing(name: dto.name)
                clothing.id = dto.id
                context.insert(clothing)
                clothingMap[dto.id] = clothing
                
                clothing.types = dto.types
                clothing.colors = dto.colors
                clothing.sizes = dto.sizes
                clothing.length = dto.length
                clothing.condition = dto.condition
                clothing.accessories = dto.accessories
                clothing.imagePaths = dto.imagePaths
                clothing.isShared = dto.isShared
                clothing.price = dto.price
                clothing.deposit = dto.deposit
                clothing.balance = dto.balance
                clothing.accessoriesPrice = dto.accessoriesPrice
                clothing.purchaseDate = dto.purchaseDate
                clothing.depositDate = dto.depositDate
                clothing.isDepositPlan = dto.isDepositPlan
                clothing.finalPaymentDate = dto.finalPaymentDate
                clothing.finalPaymentEndDate = dto.finalPaymentEndDate
                clothing.note = dto.note
                clothing.stock = dto.stock
                clothing.status = ClothingStatus(rawValue: dto.status) ?? .onShelf
                clothing.createdAt = dto.createdAt
                clothing.updatedAt = dto.updatedAt
            }
            
            if let brandID = dto.brandID, let brand = brandMap[brandID] {
                clothing.brand = brand
            }
            clothing.tags = dto.tagIDs.compactMap { tagMap[$0] }
        }
        
        // Restore Cutouts
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
            } else {
                cutout = CutoutItem(
                    originalImageHash: dto.originalImageHash,
                    category: dto.category,
                    imagePath: dto.imagePath,
                    width: dto.width,
                    height: dto.height
                )
                cutout.id = dto.id
                context.insert(cutout)
                cutoutMap[dto.id] = cutout
            }
            
            if let linkedID = dto.linkedClothingID, let clothing = clothingMap[linkedID] {
                cutout.linkedClothing = clothing
            }
        }
        
        // Restore Outfits
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
                context.insert(outfit)
                outfitMap[dto.id] = outfit
            }
            
            let existingItems = outfit.items
            var itemMap: [UUID: OutfitItem] = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
            
            for itemDTO in dto.items {
                let item: OutfitItem
                if let existingItem = itemMap[itemDTO.id] {
                    item = existingItem
                    item.x = itemDTO.x
                    item.y = itemDTO.y
                    item.rotation = itemDTO.rotation
                    item.scale = itemDTO.scale
                    item.zIndex = itemDTO.zIndex
                } else {
                    item = OutfitItem(cutout: nil, x: itemDTO.x, y: itemDTO.y, rotation: itemDTO.rotation, scale: itemDTO.scale, zIndex: itemDTO.zIndex)
                    item.id = itemDTO.id
                    item.outfit = outfit
                }
                
                if let cutoutID = itemDTO.cutoutID, let cutout = cutoutMap[cutoutID] {
                    item.cutout = cutout
                }
            }
        }
        
        try context.save()
    }
}
