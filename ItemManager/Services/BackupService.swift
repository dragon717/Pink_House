//
//  BackupService.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/25/26.
//

import Foundation
import SwiftData
import UIKit
import WidgetKit
import CryptoKit

// MARK: - Backup Service

@MainActor
class BackupService {
    static let shared = BackupService()
    
    enum BackupError: Error, LocalizedError {
        case dataFetchFailed
        case fileCreateFailed
        case imageNotFound(String)
        case archiveFailed
        case invalidArchive
        case compressionFailed
        case decompressionFailed(reason: String)
        case unknownFormat
        case corruptedArchive(reason: String)
        
        var errorDescription: String? {
            switch self {
            case .dataFetchFailed: return "获取数据失败"
            case .fileCreateFailed: return "创建文件失败"
            case .imageNotFound(let name): return "找不到图片: \(name)"
            case .archiveFailed: return "打包存档失败"
            case .invalidArchive: return "无效的备份文件 (找不到 manifest.json)"
            case .compressionFailed: return "压缩失败"
            case .decompressionFailed(let reason): return "解压失败: \(reason)"
            case .unknownFormat: return "无法识别的文件格式。请确保选择的是有效的 .save 或 .json 备份文件。"
            case .corruptedArchive(let reason): return "备份文件已损坏: \(reason)"
            }
        }
    }
    
    private init() {}
    
    // MARK: - Internal Helpers
    
    nonisolated func processByIDs<T: PersistentModel, ResultType>(
        context: ModelContext,
        descriptor: FetchDescriptor<T>,
        entityName: String,
        process: (T) -> ResultType?
    ) throws -> [ResultType] {
        print("### Export: Fetching IDs for \(entityName)...")
        
        context.processPendingChanges()
        
        var safeDescriptor = descriptor
        safeDescriptor.includePendingChanges = false
        
        let allItems = try context.fetch(safeDescriptor)
        let totalCount = allItems.count
        print("### Export: Found \(totalCount) \(entityName) items (Excl. Pending). Starting processing...")
        
        var results: [ResultType] = []
        var successCount = 0
        var failCount = 0
        
        for (index, item) in allItems.enumerated() {
            if index > 0 && index % 100 == 0 {
                print("### Export \(entityName): Processed \(index)/\(totalCount)...")
            }
            
            let id = item.persistentModelID
            
            do {
                guard let safeItem = try context.model(for: id) as? T else {
                    print("### Export \(entityName): 跳过无法加载的对象 (Index: \(index), ID: \(id))")
                    failCount += 1
                    continue
                }
                
                // Removed generic isDeleted check to avoid conflict with Clothing.isDeleted (soft delete)
                // Since we fetched with includePendingChanges = false, we should be safe from hard-deleted items.
                
                if let result = process(safeItem) {
                    results.append(result)
                    successCount += 1
                } else {
                    failCount += 1
                }
            } catch {
                print("### Export \(entityName): 捕获到失效对象 (ID: \(id)). 已跳过。错误: \(error)")
                failCount += 1
                continue
            }
        }
        
        print("### Export \(entityName): Finished. Success: \(successCount), Skipped/Failed: \(failCount)")
        return results
    }

    // MARK: - Export
    
    struct BackupData {
        let manifest: BackupManifest
        let imageFiles: [String: URL]
    }
    
    nonisolated func prepareBackupData(container: ModelContainer) async throws -> BackupData {
        print("### Export: prepareBackupData called.")
        
        let imagesDir = await ImageManager.shared.imagesDirectory
        let deviceName = await UIDevice.current.name
        
        // Capture Settings
        var settings: [String: String] = [:]
        let keysToBackup = [
            "theme_background_color",
            "theme_background_style",
            "theme_background_opacity",
            "theme_is_blur_enabled",
            "isDepositNotificationEnabled",
            "depositNotificationDaysBefore",
            "depositNotificationTime",
            "AppleLanguages"
        ]
        
        for key in keysToBackup {
            if let value = UserDefaults.standard.object(forKey: key) {
                if let stringVal = value as? String {
                    settings[key] = stringVal
                } else if let numberVal = value as? NSNumber {
                    settings[key] = numberVal.stringValue
                } else if let dateVal = value as? Date {
                    settings[key] = ISO8601DateFormatter().string(from: dateVal)
                } else if let arrayVal = value as? [String] {
                    settings[key] = arrayVal.joined(separator: ",")
                }
            }
        }
        
        return try await Task.detached(priority: .medium) {
            print("### Export: Background task started.")
            
            let context = ModelContext(container)
            context.autosaveEnabled = false
            
            var standardImagesToBackup: Set<String> = []
            
            // 1. Brands
            let brandDTOs: [BrandDTO] = try self.processByIDs(context: context, descriptor: FetchDescriptor<Brand>(), entityName: "Brands") { b in
                return BrandDTO(id: b.id, name: b.name, colorHex: b.colorHex)
            }
            
            // 2. Tags
            let tagDTOs: [TagDTO] = try self.processByIDs(context: context, descriptor: FetchDescriptor<Tag>(), entityName: "Tags") { t in
                return TagDTO(id: t.id, name: t.name, colorHex: t.colorHex)
            }
            
            // 3. Stored Images
            let storedImageDTOs: [StoredImageDTO] = try self.processByIDs(context: context, descriptor: FetchDescriptor<StoredImage>(), entityName: "StoredImages") { img in
                standardImagesToBackup.insert(img.fileName)
                return StoredImageDTO(id: img.id, imageHash: img.imageHash, fileName: img.fileName, refCount: img.refCount)
            }
            
            // 4. Clothings
            var cutoutIDToClothingID: [UUID: UUID] = [:]
            
            var clothingDescriptor = FetchDescriptor<Clothing>()
            clothingDescriptor.relationshipKeyPathsForPrefetching = [\Clothing.brand, \Clothing.tags, \Clothing.cutouts, \Clothing.accessoryItems]
            let clothingDTOs: [ClothingDTO] = try self.processByIDs(context: context, descriptor: clothingDescriptor, entityName: "Clothings") { c in
                // Skip deleted items during backup
                if c.isDeleted { return nil }
                
                for cutout in c.cutouts {
                    cutoutIDToClothingID[cutout.id] = c.id
                }
                
                let safeImagePaths = c.imagePaths.map { ($0 as NSString).lastPathComponent }
                
                for path in safeImagePaths {
                    standardImagesToBackup.insert(path)
                }
                
                var brandUUID: UUID? = nil
                var tagUUIDs: [UUID] = []
                
                do {
                    brandUUID = c.brand?.id
                    tagUUIDs = c.tags?.map { $0.id } ?? []
                } catch {
                    print("### Export Clothings [ID: \(c.id)]: 获取关联关系失败。")
                }
                
                let accItems = c.accessoryItems?.sorted(by: { $0.sortIndex < $1.sortIndex }).map { item in
                    AccessoryItemDTO(
                        id: item.id,
                        name: item.name,
                        price: item.price,
                        deposit: item.deposit,
                        balance: item.balance,
                        sortIndex: item.sortIndex
                    )
                }
                
                return ClothingDTO(
                    id: c.id,
                    name: c.name,
                    brandID: brandUUID,
                    tagIDs: tagUUIDs,
                    types: c.types,
                    colors: c.colors,
                    sizes: c.sizes,
                    length: c.length,
                    condition: c.condition,
                    accessories: c.accessories,
                    imagePaths: safeImagePaths,
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
                    isDeleted: c.isDeleted,
                    deletedAt: c.deletedAt,
                    createdAt: c.createdAt,
                    updatedAt: c.updatedAt,
                    accessoryItems: accItems
                )
            }
            
            // 5. Cutouts
            let cutoutDTOs: [CutoutItemDTO] = try self.processByIDs(context: context, descriptor: FetchDescriptor<CutoutItem>(), entityName: "Cutouts") { c in
                let fileName = (c.imagePath as NSString).lastPathComponent
                if !fileName.isEmpty {
                    standardImagesToBackup.insert(fileName)
                }
                
                let linkedClothingID = cutoutIDToClothingID[c.id]
                
                return CutoutItemDTO(
                    id: c.id,
                    originalImageHash: c.originalImageHash,
                    timestamp: c.timestamp,
                    category: c.category,
                    imagePath: fileName,
                    width: c.width,
                    height: c.height,
                    linkedClothingID: linkedClothingID
                )
            }
            
            // 6. Outfits
            var outfitDescriptor = FetchDescriptor<Outfit>()
            outfitDescriptor.relationshipKeyPathsForPrefetching = [\Outfit.items]
            let outfitDTOs: [OutfitDTO] = try self.processByIDs(context: context, descriptor: outfitDescriptor, entityName: "Outfits") { o in
                var safeSnapshotPath: String? = nil
                if let snapshot = o.snapshotPath {
                    let fileName = (snapshot as NSString).lastPathComponent
                    standardImagesToBackup.insert(fileName)
                    safeSnapshotPath = fileName
                }
                
                var items: [OutfitItemDTO] = []
                do {
                    for item in o.items {
                        if item.isDeleted { continue }
                        let cutoutID = item.cutout?.id
                        
                        var backupImagePath: String?
                        var backupWidth: Double?
                        var backupHeight: Double?
                        
                        if let cutout = item.cutout {
                            let fileName = (cutout.imagePath as NSString).lastPathComponent
                            backupImagePath = fileName
                            backupWidth = cutout.width
                            backupHeight = cutout.height
                            standardImagesToBackup.insert(fileName)
                        }
                        
                        let itemDTO = OutfitItemDTO(
                            id: item.id,
                            x: item.x,
                            y: item.y,
                            rotation: item.rotation,
                            scale: item.scale,
                            zIndex: item.zIndex,
                            cutoutID: cutoutID,
                            backupImagePath: backupImagePath,
                            backupImageWidth: backupWidth,
                            backupImageHeight: backupHeight
                        )
                        items.append(itemDTO)
                    }
                } catch {
                    print("### Export Outfits [ID: \(o.id)]: 访问 items 失败。")
                }
                
                return OutfitDTO(
                    id: o.id,
                    createdAt: o.createdAt,
                    note: o.note,
                    snapshotPath: safeSnapshotPath,
                    items: items
                )
            }
            
            let fileManager = FileManager.default
            guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw BackupError.fileCreateFailed
            }
            
            var themeFiles: [String] = []
            let possibleThemeFiles = ["theme_background_image.png", "theme_background_image_original.png"]
            for file in possibleThemeFiles {
                let url = documentsDir.appendingPathComponent(file)
                if fileManager.fileExists(atPath: url.path) {
                    themeFiles.append(file)
                }
            }
            
            var wealthFiles: [String] = []
            if let docFiles = try? fileManager.contentsOfDirectory(atPath: documentsDir.path) {
                for file in docFiles {
                    if file.hasPrefix("wealth_") && file.hasSuffix(".png") {
                        wealthFiles.append(file)
                    }
                }
            }
            
            var hasWidgetBackground = false
            var widgetBackgroundURL: URL? = nil
            if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.bugod2.ItemManager") {
                let widgetFile = containerURL.appendingPathComponent("widget_background.jpg")
                if fileManager.fileExists(atPath: widgetFile.path) {
                    hasWidgetBackground = true
                    widgetBackgroundURL = widgetFile
                }
            }
            
            print("### Export: Collecting files...")
            
            var imageFiles: [String: URL] = [:]
            
            for fileName in standardImagesToBackup {
                let fileURL = imagesDir.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: fileURL.path) {
                    imageFiles[fileName] = fileURL
                }
            }
            
            for fileName in themeFiles {
                let fileURL = documentsDir.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: fileURL.path) {
                    imageFiles[fileName] = fileURL
                }
            }
            
            for fileName in wealthFiles {
                let fileURL = documentsDir.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: fileURL.path) {
                    imageFiles[fileName] = fileURL
                }
            }
            
            if let widgetURL = widgetBackgroundURL {
                imageFiles["widget_background.jpg"] = widgetURL
            }
            
            // Calculate External File Hashes
            var externalHashes: [String: String] = [:]
            
            func fileHash(_ url: URL) -> String? {
                guard let data = try? Data(contentsOf: url) else { return nil }
                let digest = SHA256.hash(data: data)
                return digest.compactMap { String(format: "%02x", $0) }.joined()
            }
            
            // Version 1.2+ Fix: Include ALL files not in StoredImages (e.g., Cutouts, Outfits, Theme, etc.)
            // This ensures CloudSyncManager knows about them.
            let storedImageNames = Set(storedImageDTOs.map { $0.fileName })
            
            for (fileName, url) in imageFiles {
                // If it's not a standard StoredImage, we must track its hash for Cloud Sync
                if !storedImageNames.contains(fileName) {
                    if let h = fileHash(url) {
                        externalHashes[fileName] = h
                    }
                }
            }
            
            let manifest = BackupManifest(
                version: "1.2",
                timestamp: Date(),
                deviceName: deviceName,
                brands: brandDTOs,
                tags: tagDTOs,
                clothings: clothingDTOs,
                storedImages: storedImageDTOs,
                cutouts: cutoutDTOs,
                outfits: outfitDTOs,
                appSettings: settings,
                themeFiles: themeFiles,
                wealthFiles: wealthFiles,
                hasWidgetBackground: hasWidgetBackground,
                externalFileHashes: externalHashes,
                clothingCount: clothingDTOs.count,
                imageCount: storedImageDTOs.count,
                outfitCount: outfitDTOs.count
            )
            
            print("### Export: Prepared data. Total files: \(imageFiles.count)")
            return BackupData(manifest: manifest, imageFiles: imageFiles)
        }.value
    }
    
    nonisolated func exportBackup(container: ModelContainer) async throws -> URL {
        let backupData = try await prepareBackupData(container: container)
        let manifest = backupData.manifest
        let imageFiles = backupData.imageFiles
        
        // 1. Generate Manifest JSON
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        let jsonData = try jsonEncoder.encode(manifest)
        
        // 2. Archive
        print("### Export: Archiving using NativePackageWrapper...")
        let compressedData = try NativePackageWrapper.createPackage(manifestData: jsonData, imageFiles: imageFiles)
        
        // 3. Generate Output File
        let dateString = Date().formatted(.dateTime.year().month().day().hour().minute().second())
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "_")
        let fileName = "Shaonvxinyuan\(dateString).save"
        
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupsDir = documentsURL.appendingPathComponent("Backups")
        
        if !fileManager.fileExists(atPath: backupsDir.path) {
            try? fileManager.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        } else {
            let oldFiles = try? fileManager.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)
            for fileURL in oldFiles ?? [] {
                try? fileManager.removeItem(at: fileURL)
            }
        }
        
        let finalURL = backupsDir.appendingPathComponent(fileName)
        try compressedData.write(to: finalURL, options: .atomic)
        
        print("### Export: Backup file ready at \(finalURL.path) (Size: \(compressedData.count) bytes)")
        
        return finalURL
    }
    
    // MARK: - Import
    
    /// Low-level restore function that takes a Manifest and a map of Image Filenames to Local URLs
    func restoreFromManifest(manifest: BackupManifest, imageFiles: [String: URL], context: ModelContext) throws {
        print("### Restore: Starting restore from manifest...")
        
        // --- 开始分阶段恢复 ---
        
        // 阶段 1: 恢复文件 (图片、主题、小组件背景等)
        print("--- Stage 1: Restoring Files ---")
        let fileManager = FileManager.default
        let imagesDir = ImageManager.shared.imagesDirectory
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
             throw BackupError.fileCreateFailed
        }
        
        let themeFilesSet = Set(manifest.themeFiles ?? [])
        let wealthFilesSet = Set(manifest.wealthFiles ?? [])
        
        for (fileName, sourceURL) in imageFiles {
            var destinationURL: URL
            
            if themeFilesSet.contains(fileName) || wealthFilesSet.contains(fileName) {
                // Restore to Documents
                destinationURL = documentsDir.appendingPathComponent(fileName)
            } else if fileName == "widget_background.jpg" && (manifest.hasWidgetBackground == true) {
                // Restore to App Group
                 if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.bugod2.ItemManager") {
                    destinationURL = containerURL.appendingPathComponent(fileName)
                 } else {
                    print("Skipping widget background: App Group not found")
                    continue
                 }
            } else {
                // Default: Restore to Images Directory
                destinationURL = imagesDir.appendingPathComponent(fileName)
            }
            
            // Write file
            // Standard images are content-addressed (hashed), so if they exist, they are same.
            // But Settings-related images might change with same filename, so we overwrite them.
            if !fileManager.fileExists(atPath: destinationURL.path) || themeFilesSet.contains(fileName) || wealthFilesSet.contains(fileName) || fileName == "widget_background.jpg" {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try? fileManager.removeItem(at: destinationURL)
                }
                try? fileManager.copyItem(at: sourceURL, to: destinationURL)
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
            // Logic:
            // 1. If backup item is deleted, SKIP it (User requirement: "Don't restore deleted items").
            // 2. If local item is already deleted, KEEP it deleted (Don't revive trash).
            
            // Check if backup item is deleted (using isDeleted flag or deletedAt presence)
            let isBackupDeleted = dto.isDeleted ?? (dto.deletedAt != nil)
            if isBackupDeleted {
                continue
            }
            
            let clothingBack: Clothing
            if let existing = clothingMap[dto.id] {
                // Capture local deletion state
                let localIsDeleted = existing.isDeleted
                
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
                
                // CRITICAL: If local item was deleted, FORCE it to remain deleted.
                // This prevents restoring a backup from "reviving" items the user has currently trashed.
                if localIsDeleted {
                    clothingBack.isDeleted = true
                    // Ensure deletedAt is set
                    if clothingBack.deletedAt == nil {
                        clothingBack.deletedAt = Date()
                    }
                } else {
                    // Otherwise, since we skipped backup deleted items above, this must be false/nil
                    clothingBack.isDeleted = false 
                    clothingBack.deletedAt = nil
                }
                
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
                
                // New items from backup (that passed the check above) are by definition not deleted
                // UNLESS we are in a weird state where we skipped the check? No.
                // But let's be safe.
                clothingBack.isDeleted = false
                clothingBack.deletedAt = nil
                
                clothingBack.createdAt = dto.createdAt
                clothingBack.updatedAt = dto.updatedAt
            }
            
            // Restore AccessoryItems
            if let accDTOs = dto.accessoryItems {
                // Delete existing (strategy: replace all)
                if let existingItems = clothingBack.accessoryItems {
                    for item in existingItems {
                        context.delete(item)
                    }
                }
                
                var newItems: [AccessoryItem] = []
                for accDTO in accDTOs {
                    let accItem = AccessoryItem(
                        name: accDTO.name,
                        price: accDTO.price,
                        deposit: accDTO.deposit ?? 0,
                        balance: accDTO.balance ?? 0,
                        sortIndex: accDTO.sortIndex
                    )
                    accItem.id = accDTO.id
                    newItems.append(accItem)
                }
                clothingBack.accessoryItems = newItems
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
                if let cid = itemDTO.cutoutID, let found = cutoutMap[cid] {
                    item.cutout = found
                } else if let backupPath = itemDTO.backupImagePath, !backupPath.isEmpty {
                    // Fallback: Use redundant backup info
                    print("Restore: OutfitItem \(itemDTO.id) missing linked cutout. Using backup info: \(backupPath)")
                    
                    // Check if we already created a fallback cutout for this path to avoid duplicates
                    let fallbackDescriptor = FetchDescriptor<CutoutItem>(predicate: #Predicate { $0.imagePath == backupPath })
                    if let existingFallback = try? context.fetch(fallbackDescriptor).first {
                        item.cutout = existingFallback
                    } else {
                        // Create new ad-hoc cutout
                        let newCutout = CutoutItem(
                            originalImageHash: "restored_fallback_\(UUID().uuidString)",
                            category: "未分类",
                            imagePath: backupPath,
                            width: itemDTO.backupImageWidth ?? 200,
                            height: itemDTO.backupImageHeight ?? 200
                        )
                        context.insert(newCutout)
                        item.cutout = newCutout
                    }
                }
            }
        }
        
        try context.save()
        
        // 阶段 4: 恢复设置
        print("--- Stage 4: Restoring Settings ---")
        if let settings = manifest.appSettings {
            for (key, value) in settings {
                switch key {
                case "theme_background_opacity":
                    if let doubleVal = Double(value) { UserDefaults.standard.set(doubleVal, forKey: key) }
                case "theme_is_blur_enabled", "isDepositNotificationEnabled":
                    if let boolVal = Bool(value) { UserDefaults.standard.set(boolVal, forKey: key) }
                    else if let intVal = Int(value) { UserDefaults.standard.set(intVal == 1, forKey: key) }
                case "depositNotificationDaysBefore":
                    if let intVal = Int(value) { UserDefaults.standard.set(intVal, forKey: key) }
                case "depositNotificationTime":
                    if let date = ISO8601DateFormatter().date(from: value) { UserDefaults.standard.set(date, forKey: key) }
                case "AppleLanguages":
                     let languages = value.components(separatedBy: ",")
                     UserDefaults.standard.set(languages, forKey: key)
                default:
                    UserDefaults.standard.set(value, forKey: key)
                }
            }
            UserDefaults.standard.synchronize()
            WidgetCenter.shared.reloadAllTimelines()
        }
        
        print("--- Import Successful! ---")
    }

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
        
        // 4. Prepare temporary files for restoration
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        var tempFileMap: [String: URL] = [:]
        
        for (fileName, data) in fileMap where fileName != "manifest.json" {
            let tempURL = tempDir.appendingPathComponent(fileName)
            try data.write(to: tempURL)
            tempFileMap[fileName] = tempURL
        }
        
        // 5. Call internal restore
        try restoreFromManifest(manifest: manifest, imageFiles: tempFileMap, context: context)
        
        // 6. Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
}
