//
//  BackupService.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/25/26.
//

import Foundation
import SwiftData
import UIKit

// MARK: - Data Transfer Objects

struct BackupManifest: Codable {
    let version: String
    let timestamp: Date
    let deviceName: String
    
    let brands: [BrandDTO]
    let tags: [TagDTO]
    let clothings: [ClothingDTO]
    let storedImages: [StoredImageDTO]
    let cutouts: [CutoutItemDTO]
    let outfits: [OutfitDTO]
    
    // Summary
    let clothingCount: Int
    let imageCount: Int
    let outfitCount: Int
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
    let brandID: UUID?
    let tagIDs: [UUID]
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
    let status: String
    let createdAt: Date
    let updatedAt: Date
}

struct StoredImageDTO: Codable {
    let id: UUID
    let imageHash: String
    let fileName: String
    let refCount: Int
}

struct CutoutItemDTO: Codable {
    let id: UUID
    let originalImageHash: String
    let timestamp: Date
    let category: String
    let imagePath: String
    let width: Double
    let height: Double
    let linkedClothingID: UUID?
}

struct OutfitDTO: Codable {
    let id: UUID
    let createdAt: Date
    let note: String
    let snapshotPath: String?
    let items: [OutfitItemDTO]
}

struct OutfitItemDTO: Codable {
    let id: UUID
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let zIndex: Int
    let cutoutID: UUID?
}

// MARK: - Tar Utilities

class TarWriter {
    private var data = Data()
    
    func append(fileName: String, data fileData: Data) {
        // 1. Header
        var header = Data(count: 512)
        
        // Name (0)
        let nameData = fileName.data(using: .utf8)!
        let nameLength = min(nameData.count, 100)
        header.replaceSubrange(0..<nameLength, with: nameData.prefix(nameLength))
        
        // Mode (100) - 0000644
        let mode = "0000644\0"
        header.replaceSubrange(100..<108, with: mode.data(using: .utf8)!)
        
        // UID (108)
        let uid = "0000000\0"
        header.replaceSubrange(108..<116, with: uid.data(using: .utf8)!)
        
        // GID (116)
        let gid = "0000000\0"
        header.replaceSubrange(116..<124, with: gid.data(using: .utf8)!)
        
        // Size (124) - Octal string
        let sizeString = String(format: "%011o\0", fileData.count)
        header.replaceSubrange(124..<136, with: sizeString.data(using: .utf8)!)
        
        // MTime (136)
        let mtime = String(format: "%011o\0", Int(Date().timeIntervalSince1970))
        header.replaceSubrange(136..<148, with: mtime.data(using: .utf8)!)
        
        // Typeflag (156) - '0' for normal file
        header[156] = 48 // '0'
        
        // Magic (257) - ustar
        let magic = "ustar\0"
        header.replaceSubrange(257..<263, with: magic.data(using: .utf8)!)
        
        // Version (263) - 00
        let version = "00"
        header.replaceSubrange(263..<265, with: version.data(using: .utf8)!)
        
        // Checksum (148) - Calculate last
        // First fill with spaces
        let spaces = "        " // 8 spaces
        header.replaceSubrange(148..<156, with: spaces.data(using: .utf8)!)
        
        var checksum: Int = 0
        for byte in header {
            checksum += Int(byte)
        }
        let checksumString = String(format: "%06o\0 ", checksum)
        header.replaceSubrange(148..<156, with: checksumString.data(using: .utf8)!)
        
        // Append Header
        data.append(header)
        
        // Append Data
        data.append(fileData)
        
        // Padding to 512 bytes
        let paddingSize = (512 - (fileData.count % 512)) % 512
        if paddingSize > 0 {
            data.append(Data(count: paddingSize))
        }
    }
    
    func finalize() -> Data {
        // Two empty blocks
        data.append(Data(count: 1024))
        return data
    }
}

class TarReader {
    struct TarEntry {
        let name: String
        let data: Data
    }
    
    static func extract(data: Data) -> [TarEntry] {
        var entries: [TarEntry] = []
        var offset = 0
        
        while offset + 512 <= data.count {
            let header = data.subdata(in: offset..<offset+512)
            
            // Check for empty block (end of archive)
            if header.allSatisfy({ $0 == 0 }) {
                break
            }
            
            // Parse Name
            // Name is at 0, length 100. Find first null byte.
            let nameBytes = header.subdata(in: 0..<100)
            guard let nameString = String(data: nameBytes.prefix(while: { $0 != 0 }), encoding: .utf8) else {
                offset += 512
                continue
            }
            
            // Parse Size (124, 12 bytes)
            let sizeBytes = header.subdata(in: 124..<136)
            guard let sizeString = String(data: sizeBytes.prefix(while: { $0 != 0 }), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let size = Int(sizeString, radix: 8) else {
                offset += 512
                continue
            }
            
            offset += 512
            
            // Read Data
            if offset + size <= data.count {
                let fileData = data.subdata(in: offset..<offset+size)
                entries.append(TarEntry(name: nameString, data: fileData))
                
                // Skip padding
                let padding = (512 - (size % 512)) % 512
                offset += size + padding
            } else {
                break
            }
        }
        
        return entries
    }
}

// MARK: - Backup Service

@MainActor
class BackupService {
    static let shared = BackupService()
    
    enum BackupError: Error {
        case dataFetchFailed
        case fileCreateFailed
        case imageNotFound(String)
        case archiveFailed
        case invalidArchive
    }
    
    private init() {}
    
    // MARK: - Export
    
    func exportBackup(context: ModelContext) throws -> URL {
        // 1. Fetch All Data
        let descriptor = FetchDescriptor<Clothing>()
        let clothings = try context.fetch(descriptor)
        
        let brands = try context.fetch(FetchDescriptor<Brand>())
        let tags = try context.fetch(FetchDescriptor<Tag>())
        let storedImages = try context.fetch(FetchDescriptor<StoredImage>())
        let cutouts = try context.fetch(FetchDescriptor<CutoutItem>())
        let outfits = try context.fetch(FetchDescriptor<Outfit>())
        
        // 2. Convert to DTOs
        let brandDTOs = brands.map { BrandDTO(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        let tagDTOs = tags.map { TagDTO(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        
        let clothingDTOs = clothings.map { c in
            ClothingDTO(
                id: c.id,
                name: c.name,
                brandID: c.brand?.id,
                tagIDs: c.tags?.map { $0.id } ?? [],
                types: c.types,
                colors: c.colors,
                sizes: c.sizes,
                length: c.length,
                condition: c.condition,
                accessories: c.accessories,
                imagePaths: c.imagePaths,
                isShared: c.isShared,
                price: c.price,
                deposit: c.deposit,
                balance: c.balance,
                accessoriesPrice: c.accessoriesPrice,
                purchaseDate: c.purchaseDate,
                depositDate: c.depositDate,
                isDepositPlan: c.isDepositPlan,
                finalPaymentDate: c.finalPaymentDate,
                finalPaymentEndDate: c.finalPaymentEndDate,
                note: c.note,
                stock: c.stock,
                status: c.status.rawValue,
                createdAt: c.createdAt,
                updatedAt: c.updatedAt
            )
        }
        
        let storedImageDTOs = storedImages.map { StoredImageDTO(id: $0.id, imageHash: $0.imageHash, fileName: $0.fileName, refCount: $0.refCount) }
        
        let cutoutDTOs = cutouts.map { c in
            CutoutItemDTO(
                id: c.id,
                originalImageHash: c.originalImageHash,
                timestamp: c.timestamp,
                category: c.category,
                imagePath: c.imagePath,
                width: c.width,
                height: c.height,
                linkedClothingID: c.linkedClothing?.id
            )
        }
        
        let outfitDTOs = outfits.map { o in
            OutfitDTO(
                id: o.id,
                createdAt: o.createdAt,
                note: o.note,
                snapshotPath: o.snapshotPath,
                items: o.items.map { item in
                    OutfitItemDTO(
                        id: item.id,
                        x: item.x,
                        y: item.y,
                        rotation: item.rotation,
                        scale: item.scale,
                        zIndex: item.zIndex,
                        cutoutID: item.cutout?.id
                    )
                }
            )
        }
        
        let manifest = BackupManifest(
            version: "1.0",
            timestamp: Date(),
            deviceName: UIDevice.current.name,
            brands: brandDTOs,
            tags: tagDTOs,
            clothings: clothingDTOs,
            storedImages: storedImageDTOs,
            cutouts: cutoutDTOs,
            outfits: outfitDTOs,
            clothingCount: clothingDTOs.count,
            imageCount: storedImageDTOs.count,
            outfitCount: outfitDTOs.count
        )
        
        // 3. Serialize Manifest
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        let jsonData = try jsonEncoder.encode(manifest)
        
        // 4. Create TAR Archive
        let tarWriter = TarWriter()
        tarWriter.append(fileName: "manifest.json", data: jsonData)
        
        // 5. Collect and Append Images
        let imagesDir = ImageManager.shared.imagesDirectory
        
        // Helper to add file if exists
        func addFileToTar(fileName: String) {
            let fileURL = imagesDir.appendingPathComponent(fileName)
            if let data = try? Data(contentsOf: fileURL) {
                tarWriter.append(fileName: fileName, data: data)
            } else {
                print("Warning: Image file not found: \(fileName)")
            }
        }
        
        // Add Stored Images
        for img in storedImages {
            addFileToTar(fileName: img.fileName)
        }
        
        // Add Cutout Images (they might not be in StoredImage if handled separately, but let's check path)
        // CutoutItem imagePath seems to be just filename or relative path?
        // Let's assume they are in the same Images folder or we need to resolve them.
        // Looking at CutoutService (if exists) or just assuming they are in Documents.
        // CutoutItem.imagePath usage needs verification. Assuming filename in Documents.
        
        for cutout in cutouts {
            // Cutout images might be separate. Check if they are full paths or filenames.
            // If they are full paths, we need to extract filename and ensure we can find them.
            // Usually we store filenames.
            let path = cutout.imagePath
            if !path.isEmpty {
                let fileName = (path as NSString).lastPathComponent
                addFileToTar(fileName: fileName)
            }
        }
        
        for outfit in outfits {
            if let snapshot = outfit.snapshotPath {
                let fileName = (snapshot as NSString).lastPathComponent
                addFileToTar(fileName: fileName)
            }
        }
        
        let tarData = tarWriter.finalize()
        
        // 6. Compress (GZIP)
        // Since we don't have easy GZIP without importing zlib or using NSData compression,
        // we'll use `Data.compressed` if available (iOS 13+).
        // `compressed(using: .lzfse)` is efficient and Apple specific.
        // User asked for "high compression". LZFSE is good.
        let compressedData = try (tarData as NSData).compressed(using: .lzfse)
        
        // 7. Save to Temp File
        let fileName = "少女心愿\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "")).save"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try compressedData.write(to: tempURL)
        
        return tempURL
    }
    
    // MARK: - Import
    
    func importBackup(from url: URL, context: ModelContext) throws {
        // 1. Read Data
        let compressedData = try Data(contentsOf: url)
        
        // 2. Decompress
        let tarData = try (compressedData as NSData).decompressed(using: .lzfse) as Data
        
        // 3. Extract TAR
        let entries = TarReader.extract(data: tarData)
        
        // 4. Find Manifest
        guard let manifestEntry = entries.first(where: { $0.name == "manifest.json" }) else {
            throw BackupError.invalidArchive
        }
        
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        let manifest = try jsonDecoder.decode(BackupManifest.self, from: manifestEntry.data)
        
        // 5. Restore Images
        let imagesDir = ImageManager.shared.imagesDirectory
        for entry in entries where entry.name != "manifest.json" {
            let fileURL = imagesDir.appendingPathComponent(entry.name)
            // Skip if exists? Or overwrite? Restore usually implies overwrite or ensuring existence.
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try entry.data.write(to: fileURL)
            }
        }
        
        // 6. Restore Data
        // Helper map for UUIDs if we were remapping, but here we keep UUIDs.
        
        // Restore Brands
        let existingBrands = try context.fetch(FetchDescriptor<Brand>())
        var brandMap: [UUID: Brand] = Dictionary(uniqueKeysWithValues: existingBrands.map { ($0.id, $0) })
        
        for dto in manifest.brands {
            if let existing = brandMap[dto.id] {
                // Update
                existing.name = dto.name
                existing.colorHex = dto.colorHex
            } else {
                // Create
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
                // Update properties
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
                
                // Set props
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
            
            // Link Brand
            if let brandID = dto.brandID, let brand = brandMap[brandID] {
                clothing.brand = brand
            }
            
            // Link Tags
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
                // Clear existing items to rebuild? Or merge?
                // Safest to clear and rebuild items as they are owned by Outfit
                if !outfit.items.isEmpty {
                    // This is tricky with SwiftData cascade.
                    // Let's delete old items manually?
                    // For now, assume we just add missing ones or if ID matches update.
                }
            } else {
                outfit = Outfit(note: dto.note, snapshotPath: dto.snapshotPath)
                outfit.id = dto.id
                context.insert(outfit)
                outfitMap[dto.id] = outfit
            }
            
            // Restore Outfit Items
            // First map existing items
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
                    item.outfit = outfit // Relationship
                    // context.insert(item) // Relationship assignment should handle insert
                }
                
                if let cutoutID = itemDTO.cutoutID, let cutout = cutoutMap[cutoutID] {
                    item.cutout = cutout
                }
            }
        }
        
        try context.save()
    }
}
