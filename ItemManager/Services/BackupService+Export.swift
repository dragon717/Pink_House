//
//  BackupService+Export.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/26/26.
//

import Foundation
import SwiftData
import UIKit

extension BackupService {
    
    // MARK: - Export
    
    nonisolated func exportBackup(container: ModelContainer) async throws -> URL {
        // Immediate Log to verify execution start
        print("### Export: exportBackup called on background service.")
        
        let imagesDir = await ImageManager.shared.imagesDirectory
        // 0. Capture MainActor properties
        let deviceName = await UIDevice.current.name
        
        print("### Export: Captured device info. Starting background task...")
        
        // Run everything in a detached task with a NEW ModelContext
        return try await Task.detached(priority: .medium) {
            print("### Export: Background task started.")
            
            // Create a local context for background work
            let context = ModelContext(container)
            context.autosaveEnabled = false
            
            // Shared file collection
            var filesToBackup: Set<String> = []
            
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
                filesToBackup.insert(img.fileName)
                return StoredImageDTO(id: img.id, imageHash: img.imageHash, fileName: img.fileName, refCount: img.refCount)
            }
            
            // 4. Clothings
            var cutoutIDToClothingID: [UUID: UUID] = [:]
            
            var clothingDescriptor = FetchDescriptor<Clothing>()
            clothingDescriptor.relationshipKeyPathsForPrefetching = [\Clothing.brand, \Clothing.tags, \Clothing.cutouts]
            let clothingDTOs: [ClothingDTO] = try self.processByIDs(context: context, descriptor: clothingDescriptor, entityName: "Clothings") { c in
                // 填充映射表
                for cutout in c.cutouts {
                    cutoutIDToClothingID[cutout.id] = c.id
                }
                
                for path in c.imagePaths {
                    filesToBackup.insert(path)
                }
                
                var brandUUID: UUID? = nil
                var tagUUIDs: [UUID] = []
                
                do {
                    brandUUID = c.brand?.id
                    tagUUIDs = c.tags?.map { $0.id } ?? []
                } catch {
                    print("### Export Clothings [ID: \(c.id)]: 获取关联关系失败。")
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
            
            // 5. Cutouts
            let cutoutDTOs: [CutoutItemDTO] = try self.processByIDs(context: context, descriptor: FetchDescriptor<CutoutItem>(), entityName: "Cutouts") { c in
                if !c.imagePath.isEmpty {
                    filesToBackup.insert((c.imagePath as NSString).lastPathComponent)
                }
                
                let linkedClothingID = cutoutIDToClothingID[c.id]
                
                return CutoutItemDTO(
                    id: c.id,
                    originalImageHash: c.originalImageHash,
                    timestamp: c.timestamp,
                    category: c.category,
                    imagePath: c.imagePath,
                    width: c.width,
                    height: c.height,
                    linkedClothingID: linkedClothingID
                )
            }
            
            // 6. Outfits
            var outfitDescriptor = FetchDescriptor<Outfit>()
            outfitDescriptor.relationshipKeyPathsForPrefetching = [\Outfit.items]
            let outfitDTOs: [OutfitDTO] = try self.processByIDs(context: context, descriptor: outfitDescriptor, entityName: "Outfits") { o in
                if let snapshot = o.snapshotPath {
                    filesToBackup.insert((snapshot as NSString).lastPathComponent)
                }
                
                var items: [OutfitItemDTO] = []
                do {
                    for item in o.items {
                        if item.isDeleted { continue }
                        let cutoutID = item.cutout?.id
                        let itemDTO = OutfitItemDTO(
                            id: item.id,
                            x: item.x,
                            y: item.y,
                            rotation: item.rotation,
                            scale: item.scale,
                            zIndex: item.zIndex,
                            cutoutID: cutoutID
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
                    snapshotPath: o.snapshotPath,
                    items: items
                )
            }
            
            let manifest = BackupManifest(
                version: "1.0",
                timestamp: Date(),
                deviceName: deviceName,
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
            
            print("### Export: Collecting files (\(filesToBackup.count) files)...")
            
            let fileList = Array(filesToBackup)
            
            // 4. Create Backups Directory in Documents
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
            
            let dateString = Date().formatted(.dateTime.year().month().day().hour().minute().second())
                .replacingOccurrences(of: "/", with: "")
                .replacingOccurrences(of: ":", with: "")
                .replacingOccurrences(of: " ", with: "_")
            let fileName = "Shaonvxinyuan\(dateString).save"
            let tempURL = backupsDir.appendingPathComponent(fileName)
            
            // 5. Init Streaming Writer
            let compressionWriter = try StreamingCompressionWriter(url: tempURL)
            let tarWriter = TarStreamWriter(writer: compressionWriter)
            
            defer {
                try? compressionWriter.close()
            }
            
            // 6. Write Manifest
            let jsonEncoder = JSONEncoder()
            jsonEncoder.dateEncodingStrategy = .iso8601
            let jsonData = try jsonEncoder.encode(manifest)
            try tarWriter.appendEntry(fileName: "manifest.json", data: jsonData)
            
            // 7. Write Images (Streamed)
            let totalFiles = fileList.count
            for (i, fileName) in fileList.enumerated() {
                if i > 0 && i % 50 == 0 {
                    print("### Export: Archiving file \(i)/\(totalFiles)...")
                }
                
                let fileURL = imagesDir.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try tarWriter.appendEntry(fileName: fileName, fileURL: fileURL)
                }
            }
            
            // 8. Finalize
            try tarWriter.finalize()
            try compressionWriter.close()
            print("### Export: Backup file ready at \(tempURL)")
            
            return tempURL
        }.value
    }
}
