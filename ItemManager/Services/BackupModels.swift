//
//  BackupModels.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/26/26.
//

import Foundation

// MARK: - 备份版本控制
/// 强制版本控制 - 使用单一版本号管理所有备份格式变更
enum BackupFormatVersion: Int, Codable {
    case v1_0 = 1  // 初始版本
    case v1_9 = 2  // v1.9+ 新增主题配色配置、魔法任务、签到打卡等
    
    /// 当前最新版本
    static let current: BackupFormatVersion = .v1_9
    
    /// 版本号字符串（用于 manifest）
    var versionString: String {
        switch self {
        case .v1_0: return "1.0"
        case .v1_9: return "1.9"
        }
    }
}

// MARK: - Data Transfer Objects

struct BackupManifest: Codable {
    // MARK: - 强制版本控制（单一版本字段）
    /// 备份格式版本号 - 用于控制所有字段的兼容性
    /// 所有新增字段都通过版本号判断是否存在，不再使用多个可选字段注释
    let formatVersion: Int
    
    /// 便捷访问：获取版本枚举
    var backupVersion: BackupFormatVersion {
        BackupFormatVersion(rawValue: formatVersion) ?? .v1_0
    }
    
    // MARK: - 基础字段（所有版本都有）
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
    
    // MARK: - 编码/解码处理
    
    enum CodingKeys: String, CodingKey {
        case formatVersion
        // 兼容旧版本：旧备份使用 "version" 字段
        case legacyVersion = "version"
        case timestamp
        case deviceName
        case brands
        case tags
        case clothings
        case storedImages
        case cutouts
        case outfits
        case snapshots
        case appSettings
        case themeFiles
        case wealthFiles
        case hasWidgetBackground
        case hasSmallWidgetBackground
        case hasMediumWidgetBackground
        case hasLargeWidgetBackground
        case externalFileHashes
        case petStatusData
        case chatHistoryData
        case appVersion
        case bookGroups
        case spaceBookGroups
        case spaceOutfits
        case model3Ds
        case userProfile
        case userAvatarFile
        case perlerBeadPatterns
        case featureStatuses
        case unlockConditions
        case checkInRecords
        case checkInStats
        case themeColorConfig
        case clothingCount
        case imageCount
        case outfitCount
        case bookGroupCount
        case spaceBookGroupCount
        case spaceOutfitCount
        case model3DCount
        case perlerBeadPatternCount
    }
    
    init(
        formatVersion: Int = BackupFormatVersion.current.rawValue,
        timestamp: Date,
        deviceName: String,
        brands: [BrandDTO],
        tags: [TagDTO],
        clothings: [ClothingDTO],
        storedImages: [StoredImageDTO],
        cutouts: [CutoutItemDTO],
        outfits: [OutfitDTO]?,
        snapshots: [OOTDSnapshotDTO]?,
        appSettings: [String: String]?,
        themeFiles: [String]?,
        wealthFiles: [String]?,
        hasWidgetBackground: Bool?,
        hasSmallWidgetBackground: Bool?,
        hasMediumWidgetBackground: Bool?,
        hasLargeWidgetBackground: Bool?,
        externalFileHashes: [String: String]?,
        petStatusData: Data?,
        chatHistoryData: Data?,
        appVersion: String?,
        bookGroups: [BookGroupDTO]?,
        spaceBookGroups: [SpaceBookGroupDTO]?,
        spaceOutfits: [SpaceOutfitDTO]?,
        model3Ds: [Model3DDTO]?,
        userProfile: UserProfileDTO?,
        userAvatarFile: String?,
        perlerBeadPatterns: [PerlerBeadPatternDTO]?,
        featureStatuses: [FeatureStatusDTO]?,
        unlockConditions: [UnlockConditionDTO]?,
        checkInRecords: [CheckInRecordDTO]?,
        checkInStats: CheckInStatsDTO?,
        themeColorConfig: ThemeColorConfig?,
        clothingCount: Int,
        imageCount: Int,
        outfitCount: Int,
        bookGroupCount: Int?,
        spaceBookGroupCount: Int?,
        spaceOutfitCount: Int?,
        model3DCount: Int?,
        perlerBeadPatternCount: Int?
    ) {
        self.formatVersion = formatVersion
        self.timestamp = timestamp
        self.deviceName = deviceName
        self.brands = brands
        self.tags = tags
        self.clothings = clothings
        self.storedImages = storedImages
        self.cutouts = cutouts
        self.outfits = outfits
        self.snapshots = snapshots
        self.appSettings = appSettings
        self.themeFiles = themeFiles
        self.wealthFiles = wealthFiles
        self.hasWidgetBackground = hasWidgetBackground
        self.hasSmallWidgetBackground = hasSmallWidgetBackground
        self.hasMediumWidgetBackground = hasMediumWidgetBackground
        self.hasLargeWidgetBackground = hasLargeWidgetBackground
        self.externalFileHashes = externalFileHashes
        self.petStatusData = petStatusData
        self.chatHistoryData = chatHistoryData
        self.appVersion = appVersion
        self.bookGroups = bookGroups
        self.spaceBookGroups = spaceBookGroups
        self.spaceOutfits = spaceOutfits
        self.model3Ds = model3Ds
        self.userProfile = userProfile
        self.userAvatarFile = userAvatarFile
        self.perlerBeadPatterns = perlerBeadPatterns
        self.featureStatuses = featureStatuses
        self.unlockConditions = unlockConditions
        self.checkInRecords = checkInRecords
        self.checkInStats = checkInStats
        self.themeColorConfig = themeColorConfig
        self.clothingCount = clothingCount
        self.imageCount = imageCount
        self.outfitCount = outfitCount
        self.bookGroupCount = bookGroupCount
        self.spaceBookGroupCount = spaceBookGroupCount
        self.spaceOutfitCount = spaceOutfitCount
        self.model3DCount = model3DCount
        self.perlerBeadPatternCount = perlerBeadPatternCount
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 优先读取新的 formatVersion，如果不存在则读取旧的 version 字段
        if let version = try? container.decode(Int.self, forKey: .formatVersion) {
            self.formatVersion = version
        } else if let legacyVersion = try? container.decode(String.self, forKey: .legacyVersion) {
            // 兼容旧版本：从字符串版本号转换
            self.formatVersion = BackupManifest.convertLegacyVersion(legacyVersion)
        } else {
            self.formatVersion = BackupFormatVersion.v1_0.rawValue
        }
        
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.deviceName = try container.decode(String.self, forKey: .deviceName)
        self.brands = try container.decode([BrandDTO].self, forKey: .brands)
        self.tags = try container.decode([TagDTO].self, forKey: .tags)
        self.clothings = try container.decode([ClothingDTO].self, forKey: .clothings)
        self.storedImages = try container.decode([StoredImageDTO].self, forKey: .storedImages)
        self.cutouts = try container.decode([CutoutItemDTO].self, forKey: .cutouts)
        self.outfits = try container.decodeIfPresent([OutfitDTO].self, forKey: .outfits)
        self.snapshots = try container.decodeIfPresent([OOTDSnapshotDTO].self, forKey: .snapshots)
        self.appSettings = try container.decodeIfPresent([String: String].self, forKey: .appSettings)
        self.themeFiles = try container.decodeIfPresent([String].self, forKey: .themeFiles)
        self.wealthFiles = try container.decodeIfPresent([String].self, forKey: .wealthFiles)
        self.hasWidgetBackground = try container.decodeIfPresent(Bool.self, forKey: .hasWidgetBackground)
        self.hasSmallWidgetBackground = try container.decodeIfPresent(Bool.self, forKey: .hasSmallWidgetBackground)
        self.hasMediumWidgetBackground = try container.decodeIfPresent(Bool.self, forKey: .hasMediumWidgetBackground)
        self.hasLargeWidgetBackground = try container.decodeIfPresent(Bool.self, forKey: .hasLargeWidgetBackground)
        self.externalFileHashes = try container.decodeIfPresent([String: String].self, forKey: .externalFileHashes)
        self.petStatusData = try container.decodeIfPresent(Data.self, forKey: .petStatusData)
        self.chatHistoryData = try container.decodeIfPresent(Data.self, forKey: .chatHistoryData)
        self.appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        self.bookGroups = try container.decodeIfPresent([BookGroupDTO].self, forKey: .bookGroups)
        self.spaceBookGroups = try container.decodeIfPresent([SpaceBookGroupDTO].self, forKey: .spaceBookGroups)
        self.spaceOutfits = try container.decodeIfPresent([SpaceOutfitDTO].self, forKey: .spaceOutfits)
        self.model3Ds = try container.decodeIfPresent([Model3DDTO].self, forKey: .model3Ds)
        self.userProfile = try container.decodeIfPresent(UserProfileDTO.self, forKey: .userProfile)
        self.userAvatarFile = try container.decodeIfPresent(String.self, forKey: .userAvatarFile)
        self.perlerBeadPatterns = try container.decodeIfPresent([PerlerBeadPatternDTO].self, forKey: .perlerBeadPatterns)
        self.featureStatuses = try container.decodeIfPresent([FeatureStatusDTO].self, forKey: .featureStatuses)
        self.unlockConditions = try container.decodeIfPresent([UnlockConditionDTO].self, forKey: .unlockConditions)
        self.checkInRecords = try container.decodeIfPresent([CheckInRecordDTO].self, forKey: .checkInRecords)
        self.checkInStats = try container.decodeIfPresent(CheckInStatsDTO.self, forKey: .checkInStats)
        self.themeColorConfig = try container.decodeIfPresent(ThemeColorConfig.self, forKey: .themeColorConfig)
        self.clothingCount = try container.decode(Int.self, forKey: .clothingCount)
        self.imageCount = try container.decode(Int.self, forKey: .imageCount)
        self.outfitCount = try container.decode(Int.self, forKey: .outfitCount)
        self.bookGroupCount = try container.decodeIfPresent(Int.self, forKey: .bookGroupCount)
        self.spaceBookGroupCount = try container.decodeIfPresent(Int.self, forKey: .spaceBookGroupCount)
        self.spaceOutfitCount = try container.decodeIfPresent(Int.self, forKey: .spaceOutfitCount)
        self.model3DCount = try container.decodeIfPresent(Int.self, forKey: .model3DCount)
        self.perlerBeadPatternCount = try container.decodeIfPresent(Int.self, forKey: .perlerBeadPatternCount)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encode(brands, forKey: .brands)
        try container.encode(tags, forKey: .tags)
        try container.encode(clothings, forKey: .clothings)
        try container.encode(storedImages, forKey: .storedImages)
        try container.encode(cutouts, forKey: .cutouts)
        try container.encodeIfPresent(outfits, forKey: .outfits)
        try container.encodeIfPresent(snapshots, forKey: .snapshots)
        try container.encodeIfPresent(appSettings, forKey: .appSettings)
        try container.encodeIfPresent(themeFiles, forKey: .themeFiles)
        try container.encodeIfPresent(wealthFiles, forKey: .wealthFiles)
        try container.encodeIfPresent(hasWidgetBackground, forKey: .hasWidgetBackground)
        try container.encodeIfPresent(hasSmallWidgetBackground, forKey: .hasSmallWidgetBackground)
        try container.encodeIfPresent(hasMediumWidgetBackground, forKey: .hasMediumWidgetBackground)
        try container.encodeIfPresent(hasLargeWidgetBackground, forKey: .hasLargeWidgetBackground)
        try container.encodeIfPresent(externalFileHashes, forKey: .externalFileHashes)
        try container.encodeIfPresent(petStatusData, forKey: .petStatusData)
        try container.encodeIfPresent(chatHistoryData, forKey: .chatHistoryData)
        try container.encodeIfPresent(appVersion, forKey: .appVersion)
        try container.encodeIfPresent(bookGroups, forKey: .bookGroups)
        try container.encodeIfPresent(spaceBookGroups, forKey: .spaceBookGroups)
        try container.encodeIfPresent(spaceOutfits, forKey: .spaceOutfits)
        try container.encodeIfPresent(model3Ds, forKey: .model3Ds)
        try container.encodeIfPresent(userProfile, forKey: .userProfile)
        try container.encodeIfPresent(userAvatarFile, forKey: .userAvatarFile)
        try container.encodeIfPresent(perlerBeadPatterns, forKey: .perlerBeadPatterns)
        try container.encodeIfPresent(featureStatuses, forKey: .featureStatuses)
        try container.encodeIfPresent(unlockConditions, forKey: .unlockConditions)
        try container.encodeIfPresent(checkInRecords, forKey: .checkInRecords)
        try container.encodeIfPresent(checkInStats, forKey: .checkInStats)
        try container.encodeIfPresent(themeColorConfig, forKey: .themeColorConfig)
        try container.encode(clothingCount, forKey: .clothingCount)
        try container.encode(imageCount, forKey: .imageCount)
        try container.encode(outfitCount, forKey: .outfitCount)
        try container.encodeIfPresent(bookGroupCount, forKey: .bookGroupCount)
        try container.encodeIfPresent(spaceBookGroupCount, forKey: .spaceBookGroupCount)
        try container.encodeIfPresent(spaceOutfitCount, forKey: .spaceOutfitCount)
        try container.encodeIfPresent(model3DCount, forKey: .model3DCount)
        try container.encodeIfPresent(perlerBeadPatternCount, forKey: .perlerBeadPatternCount)
    }
    
    /// 转换旧版本字符串版本号为整数版本
    private static func convertLegacyVersion(_ version: String) -> Int {
        switch version {
        case "1.9": return BackupFormatVersion.v1_9.rawValue
        case "1.8", "1.7", "1.6", "1.5", "1.4", "1.3", "1.2", "1.1":
            // 这些版本都映射到 v1_0，因为它们没有 formatVersion 字段
            return BackupFormatVersion.v1_0.rawValue
        default:
            return BackupFormatVersion.v1_0.rawValue
        }
    }
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

    // v1.9+ 新增字段 - 今日穿搭色增强
    let temperature: Double?  // 温度
    let season: String?       // 季节
    let petName: String?      // 萌宠推荐者名字

    // v1.10+ 新增字段 - AI 生成的颜色 hex 值
    let colorHexes: [String?]? // 颜色 hex 值数组（AI生成时会有）

    // 自定义解码以兼容旧备份（没有 colorHexes 字段）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        colors = try container.decode([String].self, forKey: .colors)
        accessories = try container.decode(String.self, forKey: .accessories)
        weather = try container.decodeIfPresent(String.self, forKey: .weather)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        isAIGenerated = try container.decode(Bool.self, forKey: .isAIGenerated)
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        season = try container.decodeIfPresent(String.self, forKey: .season)
        petName = try container.decodeIfPresent(String.self, forKey: .petName)
        colorHexes = try container.decodeIfPresent([String?].self, forKey: .colorHexes)
    }

    // 自定义编码
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(colors, forKey: .colors)
        try container.encode(accessories, forKey: .accessories)
        try container.encode(weather, forKey: .weather)
        try container.encode(location, forKey: .location)
        try container.encode(isAIGenerated, forKey: .isAIGenerated)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(season, forKey: .season)
        try container.encode(petName, forKey: .petName)
        try container.encode(colorHexes, forKey: .colorHexes)
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, colors, accessories, weather, location, isAIGenerated
        case temperature, season, petName, colorHexes
    }

    // 初始化方法 - 用于创建新记录
    init(id: String, date: Date, colors: [String], colorHexes: [String?]? = nil,
         accessories: String, weather: String?, location: String?,
         isAIGenerated: Bool, temperature: Double? = nil,
         season: String? = nil, petName: String? = nil) {
        self.id = id
        self.date = date
        self.colors = colors
        self.colorHexes = colorHexes
        self.accessories = accessories
        self.weather = weather
        self.location = location
        self.isAIGenerated = isAIGenerated
        self.temperature = temperature
        self.season = season
        self.petName = petName
    }
}

struct CheckInStatsDTO: Codable {
    let consecutiveDays: Int
    let totalDays: Int
    let lastCheckInDate: Date?
}
