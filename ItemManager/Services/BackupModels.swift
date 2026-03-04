//
//  BackupModels.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/26/26.
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
    
    // Version 1.7: Perler Bead Patterns (拼豆/像素画)
    let perlerBeadPatterns: [PerlerBeadPatternDTO]?
    
    // Version 1.8: Magic Tasks (魔法任务解锁状态)
    let featureStatuses: [FeatureStatusDTO]? // v1.8+ 魔法任务解锁状态
    let unlockConditions: [UnlockConditionDTO]? // v1.8+ 魔法任务解锁条件配置
    
    // Version 1.8: CheckIn Records (签到打卡记录)
    let checkInRecords: [CheckInRecordDTO]? // v1.8+ 签到打卡记录
    let checkInStats: CheckInStatsDTO? // v1.8+ 签到统计数据
    
    // Version 1.9: Theme Color Config (魔法配色/客制化配色配置)
    let themeColorConfig: ThemeColorConfig? // v1.9+ 主题配色配置
    
    // Summary
    let clothingCount: Int
    let imageCount: Int
    let outfitCount: Int
    let bookGroupCount: Int?
    let spaceBookGroupCount: Int?
    let spaceOutfitCount: Int?
    let model3DCount: Int?
    let perlerBeadPatternCount: Int?
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
    let isShared: Bool? // v1.2+ 共享到广场标记，老版本备份可能不存在
    let price: Decimal
    let deposit: Decimal
    let balance: Decimal
    let accessoriesPrice: Decimal? // v1.3+ 小物总价，老版本备份可能不存在
    let purchaseDate: Date
    let depositDate: Date?
    let isDepositPlan: Bool
    let finalPaymentDate: Date?
    let finalPaymentEndDate: Date?
    let note: String
    let stock: Int
    let status: String? // v1.2+ 上架状态，老版本备份可能不存在
    let isDeleted: Bool? // v1.4+ 软删除标记，老版本备份可能不存在
    let deletedAt: Date? // v1.4+ 删除时间，老版本备份可能不存在
    let createdAt: Date
    let updatedAt: Date
    let sortIndex: Int? // v1.2+ 排序索引，老版本备份可能不存在
    let lastModified: Date? // v1.4+ 最后修改时间，老版本备份可能不存在

    // New Fields (v1.4)
    let replacedCutoutID: UUID? // v1.4+ 替换主图所用的抠图ID，老版本备份可能不存在

    // Custom Accessories (Added in v1.3)
    let accessoryItems: [AccessoryItemDTO]? // v1.3+ 自定义小物列表，老版本备份可能不存在
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
    let isDeleted: Bool? // v1.5+ 软删除标记，老版本备份可能不存在
    let deletedAt: Date? // v1.5+ 删除时间，老版本备份可能不存在
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
    let isDeleted: Bool? // v1.5+ 软删除标记，老版本备份可能不存在
    let deletedAt: Date? // v1.5+ 删除时间，老版本备份可能不存在
    let createdAt: Date
    let updatedAt: Date
    let sortIndex: Int
    let cameraPositionX: Float? // v1.5+ 相机位置，老版本备份可能不存在
    let cameraPositionY: Float? // v1.5+ 相机位置，老版本备份可能不存在
    let cameraPositionZ: Float? // v1.5+ 相机位置，老版本备份可能不存在
    let cameraRotationX: Float? // v1.5+ 相机旋转，老版本备份可能不存在
    let cameraRotationY: Float? // v1.5+ 相机旋转，老版本备份可能不存在
    let cameraRotationZ: Float? // v1.5+ 相机旋转，老版本备份可能不存在
    let lastModified: Date?
}

// MARK: - Book Group DTOs (v1.5)

struct BookGroupDTO: Codable {
    let id: UUID
    let title: String
    let coverImage: String?
    let createdAt: Date
    let isDeleted: Bool? // v1.5+ 软删除标记，老版本备份可能不存在
    let deletedAt: Date? // v1.5+ 删除时间，老版本备份可能不存在
    let sortIndex: Int
    let lastModified: Date?
}

struct SpaceBookGroupDTO: Codable {
    let id: UUID
    let title: String
    let coverImage: String?
    let createdAt: Date
    let isDeleted: Bool? // v1.5+ 软删除标记，老版本备份可能不存在
    let deletedAt: Date? // v1.5+ 删除时间，老版本备份可能不存在
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
    let isDeleted: Bool? // v1.5+ 软删除标记，老版本备份可能不存在
    let deletedAt: Date? // v1.5+ 删除时间，老版本备份可能不存在
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

// MARK: - Perler Bead Pattern DTO (v1.7)

struct PerlerBeadPatternDTO: Codable {
    let id: UUID
    let name: String
    let patternType: String
    let resolution: Int
    let paletteSize: Int
    let canvasStyle: String
    let pixelData: [Int]
    let paletteSortOrder: String
    let thumbnailPath: String?
    let isDeleted: Bool? // v1.7+ 软删除标记，老版本备份可能不存在
    let deletedAt: Date? // v1.7+ 删除时间，老版本备份可能不存在
    let createdAt: Date
    let updatedAt: Date
    let lastModified: Date?
    let sortIndex: Int
}

// MARK: - Magic Tasks DTO (v1.8)
// 魔法任务解锁状态和条件配置的备份DTO

struct FeatureStatusDTO: Codable {
    let featureID: String // FeatureItem.rawValue
    let isUnlocked: Bool
    let isVisible: Bool
    let unlockedAt: Date?
    let unlockedBy: String?
}

struct UnlockConditionDTO: Codable {
    let featureID: String // FeatureItem.rawValue
    let type: String // UnlockConditionType.rawValue
    let requiredValue: Int
    let description: String
}

// MARK: - CheckIn DTO (v1.8)
// 签到打卡记录的备份DTO

struct CheckInRecordDTO: Codable {
    let id: String
    let date: Date
    let colors: [String]
    let accessories: String
    let weather: String?
    let location: String?
    let isAIGenerated: Bool
}

struct CheckInStatsDTO: Codable {
    let consecutiveDays: Int
    let totalDays: Int
    let lastCheckInDate: Date?
}
