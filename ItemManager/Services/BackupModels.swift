//
//  BackupModels.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/26/26.
//

import Foundation

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
    // Deprecated: outfits are now handled as snapshots
    let outfits: [OutfitDTO]?
    // New: OOTD Snapshots
    let snapshots: [OOTDSnapshotDTO]?
    
    // New Features Backup (Optional for backward compatibility)
    let appSettings: [String: String]?
    let themeFiles: [String]?
    let wealthFiles: [String]?
    let hasWidgetBackground: Bool?
    
    // Version 1.2: External File Hashes for Incremental Sync
    let externalFileHashes: [String: String]? // [FileName: Hash]
    
    // Summary
    let clothingCount: Int
    let imageCount: Int
    let outfitCount: Int
}

struct BrandDTO: Codable {
    let id: UUID
    let name: String
    let colorHex: String
    let imagePath: String?
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
    let isDeleted: Bool?
    let deletedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let sortIndex: Int?
    
    // Custom Accessories (Added in v1.3)
    let accessoryItems: [AccessoryItemDTO]?
}

struct AccessoryItemDTO: Codable {
    let id: UUID
    let name: String
    let price: Decimal
    let deposit: Decimal?
    let balance: Decimal?
    let sortIndex: Int
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
    var canvasType: String? = "mannequin"
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
    
    // Redundant Backup Data for Robust Restore
    var backupImagePath: String?
    var backupImageWidth: Double?
    var backupImageHeight: Double?
}

struct OOTDSnapshotDTO: Codable {
    let id: UUID
    let createdAt: Date
    let note: String
    let snapshotPath: String?
    var canvasType: String? = "mannequin"
    let items: [OOTDSnapshotItemDTO]
}

struct OOTDSnapshotItemDTO: Codable {
    let id: UUID
    let imageReference: String // Path to the cutout image
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let zIndex: Int
    let rotation: Double
}
