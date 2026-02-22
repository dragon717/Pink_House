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
    
    // Version 1.5: Book Groups and Space Outfits
    let bookGroups: [BookGroupDTO]?
    let spaceBookGroups: [SpaceBookGroupDTO]?
    let spaceOutfits: [SpaceOutfitDTO]?
    
    // Version 1.5: Model3D
    let model3Ds: [Model3DDTO]?
    
    // Version 1.6: User Profile (头像和昵称)
    let userProfile: UserProfileDTO?
    let userAvatarFile: String?
    
    // Summary
    let clothingCount: Int
    let imageCount: Int
    let outfitCount: Int
    let bookGroupCount: Int?
    let spaceBookGroupCount: Int?
    let spaceOutfitCount: Int?
    let model3DCount: Int?
}

// MARK: - User Profile DTO (v1.6)
struct UserProfileDTO: Codable {
    let userIdentifier: String
    let nickname: String
    let updatedAt: Date
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
    let lastModified: Date?
    
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
    let lastModified: Date?
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
    let lastModified: Date?
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
    let bookID: UUID? // Reference to parent BookGroup (v1.5)
    let items: [OOTDSnapshotItemDTO]
    let lastModified: Date?
    let isDeleted: Bool
    let deletedAt: Date?
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

// MARK: - Model3D DTO (v1.5)

struct Model3DDTO: Codable {
    let id: UUID
    let name: String
    let types: String
    let modelPath: String?
    let modelType: String?
    let thumbnailPath: String?
    let sourceImagePaths: [String]
    let isDeleted: Bool
    let deletedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let sortIndex: Int
    let cameraPositionX: Float
    let cameraPositionY: Float
    let cameraPositionZ: Float
    let cameraRotationX: Float
    let cameraRotationY: Float
    let cameraRotationZ: Float
    let lastModified: Date?
}

// MARK: - Book Group DTOs (v1.5)

struct BookGroupDTO: Codable {
    let id: UUID
    let title: String
    let coverImage: String?
    let createdAt: Date
    let isDeleted: Bool
    let deletedAt: Date?
    let sortIndex: Int
    let lastModified: Date?
}

struct SpaceBookGroupDTO: Codable {
    let id: UUID
    let title: String
    let coverImage: String?
    let createdAt: Date
    let isDeleted: Bool
    let deletedAt: Date?
    let sortIndex: Int
    let lastModified: Date?
}

// MARK: - Space Outfit DTOs (v1.5)

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
    let isDeleted: Bool
    let deletedAt: Date?
    let bookID: UUID? // Reference to parent SpaceBookGroup
    let sceneObjects: [SceneObjectDataDTO]
    let lastModified: Date?
}

struct SceneObjectDataDTO: Codable {
    let id: UUID
    let objectType: String
    let positionX: Double
    let positionY: Double
    let positionZ: Double
    let rotationX: Double
    let rotationY: Double
    let rotationZ: Double
    let scaleX: Double
    let scaleY: Double
    let scaleZ: Double
    let usdzModelPath: String?
    let colorR: Double
    let colorG: Double
    let colorB: Double
    let colorA: Double
    let sortIndex: Int
    let model3DID: UUID? // Reference to Model3D if applicable
}
