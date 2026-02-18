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
    
    // Book Groups (平面手帐) - v1.6
    let bookGroups: [BookGroupDTO]?
    // Outfits Full (平面书页 - 包含手帐关联) - v1.6
    let outfitsFull: [OutfitFullDTO]?
    // Space Book Groups (空间手帐) - v1.6
    let spaceBookGroups: [SpaceBookGroupDTO]?
    // Space Outfits (空间书页) - v1.6
    let spaceOutfits: [SpaceOutfitDTO]?
    
    // New Features Backup (Optional for backward compatibility)
    let appSettings: [String: String]?
    let themeFiles: [String]?
    let wealthFiles: [String]?
    let hasWidgetBackground: Bool?
    let hasSmallWidgetBackground: Bool?
    let hasMediumWidgetBackground: Bool?
    let hasLargeWidgetBackground: Bool?
    
    // Version 1.2: External File Hashes for Incremental Sync
    let externalFileHashes: [String: String]? // [FileName: Hash]
    
    // Pet Module
    let petStatusData: Data?
    // v1.4.1: Chat History (JSON only, no images)
    let chatHistoryData: Data?
    
    // App Version Persistence
    let appVersion: String?
    
    // 大世界图钉数据 (v1.5)
    let bigWorldPinsData: Data?
    
    // 用户资料数据 (v1.5)
    let userProfileData: UserProfileDTO?
    
    // Summary
    let clothingCount: Int
    let imageCount: Int
    let outfitCount: Int
}

// MARK: - 用户资料 DTO
struct UserProfileDTO: Codable {
    let userName: String
    let userAvatar: Data?
    let isAuthenticated: Bool
    let appleUserIdentifier: String?
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
    
    // New Fields (v1.4)
    let replacedCutoutID: UUID?
    
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
    var backgroundImagePath: String?
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

// MARK: - Book Group DTOs (平面手帐)

struct BookGroupDTO: Codable {
    let id: UUID
    let title: String
    let coverImage: String?
    let createdAt: Date
    let isDeleted: Bool?
    let deletedAt: Date?
    let sortIndex: Int
}

// MARK: - Outfit DTO (平面书页 - 完整版)

struct OutfitFullDTO: Codable {
    let id: UUID
    let createdAt: Date
    let note: String
    let snapshotPath: String?
    let canvasType: String?
    let backgroundImagePath: String?
    let sortIndex: Int
    let isDeleted: Bool?
    let deletedAt: Date?
    let bookID: UUID? // 关联的手帐ID
    let items: [OutfitItemFullDTO]
}

struct OutfitItemFullDTO: Codable {
    let id: UUID
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let zIndex: Int
    let cutoutID: UUID?
}

// MARK: - Space Book Group DTOs (空间手帐)

struct SpaceBookGroupDTO: Codable {
    let id: UUID
    let title: String
    let coverImage: String?
    let createdAt: Date
    let isDeleted: Bool?
    let deletedAt: Date?
    let sortIndex: Int
}

// MARK: - Space Outfit DTO (空间书页)

struct SpaceOutfitDTO: Codable {
    let id: UUID
    let createdAt: Date
    let note: String
    let snapshotPath: String?
    let sortIndex: Int
    let modelPath: String?
    let camPosX: Double
    let camPosY: Double
    let camPosZ: Double
    let lightingIntensity: Double
    let isDeleted: Bool?
    let deletedAt: Date?
    let bookID: UUID? // 关联的空间手帐ID
}
