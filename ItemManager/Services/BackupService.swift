//
//  BackupService.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/25/26.
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
    
    // MARK: - 可重入性保护
    private var isRestoring = false
    private let restoreLock = NSLock()
    
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
        case restoreInProgress
        
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
            case .restoreInProgress: return "恢复操作正在进行中，请稍后再试"
            }
        }
    }
    
    private init() {}
    
    // MARK: - Constants
    
    static let keysToBackup = [
        "theme_background_color",
        "theme_background_style",
        "theme_background_opacity",
        "theme_is_blur_enabled",
        "theme_card_style",
        "theme_skirt_fill_mode",
        "theme_transparent_opacity",
        "theme_tint_opacity",
        "theme_card_tint_color",
        "theme_image_fill_tint_color",      // v1.9+: 图片填充色调颜色
        "theme_image_fill_tint_opacity",    // v1.9+: 图片填充色调透明度
        "isDepositNotificationEnabled",
        "depositNotificationDaysBefore",
        "depositNotificationDaysList",
        "depositNotificationTime",
        "AppleLanguages",
        "UserPreference_SortOption",
        "UserPreference_ViewLayout",
        "UserPreference_DepositDisplayMode",
        "shouldShowWealthContainerBackground",
        "visualModelPriority",
        "textModelPriority",
        "voiceModelId",
        "voiceToneId",
        "UserCustomFontFileName",
        "HasRedeemedVIP_Prince",
        "userProfiles"  // v1.6: 用户资料（包含所有用户的昵称和头像路径）
    ]
    
    // MARK: - Internal Helpers
    
    nonisolated func processByIDs<T: PersistentModel, ResultType>(
        context: ModelContext,
        descriptor: FetchDescriptor<T>,
        entityName: String,
        process: (T) -> ResultType?
    ) throws -> [ResultType] {
        print("### Export: Fetching \(entityName)...")
        
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
            
            // Direct item access logic to avoid context detachment issues
            if item.isDeleted {
                continue
            }
            
            if let result = process(item) {
                results.append(result)
                successCount += 1
            } else {
                failCount += 1
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
        let keysToBackup = BackupService.keysToBackup
        
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
                } else if let intArrayVal = value as? [Int] {
                    settings[key] = intArrayVal.map { String($0) }.joined(separator: ",")
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
                if let path = b.imagePath {
                    standardImagesToBackup.insert(path)
                }
                return BrandDTO(id: b.id, name: b.name, colorHex: b.colorHex, imagePath: b.imagePath)
            }
            
            // 2. Tags
            let tagDTOs: [TagDTO] = try self.processByIDs(context: context, descriptor: FetchDescriptor<Tag>(), entityName: "Tags") { t in
                return TagDTO(id: t.id, name: t.name, colorHex: t.colorHex)
            }
            
            // 3. Stored Images
            let storedImageDTOs: [StoredImageDTO] = try self.processByIDs(context: context, descriptor: FetchDescriptor<StoredImage>(), entityName: "StoredImages") { img in
                standardImagesToBackup.insert(img.fileName)
                return StoredImageDTO(id: img.id, imageHash: img.imageHash, fileName: img.fileName, refCount: img.refCount, lastModified: img.lastModified)
            }
            
            // 4. Clothings
            // var cutoutIDToClothingID: [UUID: UUID] = [:] // Deprecated
            
            var clothingDescriptor = FetchDescriptor<Clothing>()
            clothingDescriptor.relationshipKeyPathsForPrefetching = [\Clothing.brand, \Clothing.tags, \Clothing.accessoryItems]
            let clothingDTOs: [ClothingDTO] = try self.processByIDs(context: context, descriptor: clothingDescriptor, entityName: "Clothings") { c in
                // 备份所有数据，包括已删除的，以支持回收站同步和跨设备恢复
                // No need to track cutoutIDToClothingID here anymore since we use direct ID on CutoutItem
                // for cutout in c.cutouts {
                //    cutoutIDToClothingID[cutout.id] = c.id
                // }
                
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
                    sortIndex: c.sortIndex,
                    lastModified: c.lastModified,
                    replacedCutoutID: c.replacedCutoutID,
                    accessoryItems: accItems
                )
            }
            
            // 5. Cutouts
            let cutoutDTOs: [CutoutItemDTO] = try self.processByIDs(context: context, descriptor: FetchDescriptor<CutoutItem>(), entityName: "Cutouts") { c in
                let fileName = (c.imagePath as NSString).lastPathComponent
                if !fileName.isEmpty {
                    standardImagesToBackup.insert(fileName)
                }
                
                let linkedClothingID = c.linkedClothingID
                
                return CutoutItemDTO(
                    id: c.id,
                    originalImageHash: c.originalImageHash,
                    timestamp: c.timestamp,
                    category: c.category,
                    imagePath: fileName,
                    width: c.width,
                    height: c.height,
                    linkedClothingID: linkedClothingID,
                    lastModified: c.lastModified
                )
            }
            
            // 6. OOTD Snapshots (Replacing Outfits)
            var outfitDescriptor = FetchDescriptor<Outfit>()
            outfitDescriptor.relationshipKeyPathsForPrefetching = [\Outfit.items, \Outfit.book]
            let snapshotDTOs: [OOTDSnapshotDTO] = try self.processByIDs(context: context, descriptor: outfitDescriptor, entityName: "Outfits (Snapshots)") { o in
                var safeSnapshotPath: String? = nil
                if let snapshot = o.snapshotPath {
                    let fileName = (snapshot as NSString).lastPathComponent
                    standardImagesToBackup.insert(fileName)
                    safeSnapshotPath = fileName
                }
                
                var safeBackgroundImagePath: String? = nil
                if let bgPath = o.backgroundImagePath {
                    let fileName = (bgPath as NSString).lastPathComponent
                    standardImagesToBackup.insert(fileName)
                    safeBackgroundImagePath = fileName
                }
                
                var items: [OOTDSnapshotItemDTO] = []
                for item in o.items ?? [] {
                    if item.isDeleted { continue }
                    guard let cutout = item.cutout else { continue }
                    
                    let fileName = (cutout.imagePath as NSString).lastPathComponent
                    standardImagesToBackup.insert(fileName)
                    
                    let displayWidth = cutout.width * item.scale
                    let displayHeight = cutout.height * item.scale
                    
                    let itemDTO = OOTDSnapshotItemDTO(
                        id: item.id,
                        imageReference: fileName,
                        x: item.x,
                        y: item.y,
                        width: displayWidth,
                        height: displayHeight,
                        zIndex: item.zIndex,
                        rotation: item.rotation
                    )
                    items.append(itemDTO)
                }
                
                return OOTDSnapshotDTO(
                    id: o.id,
                    createdAt: o.createdAt,
                    note: o.note,
                    snapshotPath: safeSnapshotPath,
                    canvasType: o.canvasType,
                    backgroundImagePath: safeBackgroundImagePath,
                    bookID: o.book?.id,
                    items: items,
                    lastModified: o.lastModified,
                    isDeleted: o.isDeleted,
                    deletedAt: o.deletedAt
                )
            }
            
            let fileManager = FileManager.default
            guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw BackupError.fileCreateFailed
            }
            
            // 7. Model3D (3D模型)
            let model3DDTOs: [Model3DDTO] = try self.processByIDs(context: context, descriptor: FetchDescriptor<Model3D>(), entityName: "Model3Ds") { m in
                // Model file
                if let modelPath = m.modelPath {
                    let fileName = (modelPath as NSString).lastPathComponent
                    if !fileName.isEmpty {
                        standardImagesToBackup.insert(fileName)
                    }
                }
                
                // Thumbnail
                if let thumbnailPath = m.thumbnailPath {
                    let fileName = (thumbnailPath as NSString).lastPathComponent
                    if !fileName.isEmpty {
                        standardImagesToBackup.insert(fileName)
                    }
                }
                
                // Source images
                for sourcePath in m.sourceImagePaths {
                    let fileName = (sourcePath as NSString).lastPathComponent
                    if !fileName.isEmpty {
                        standardImagesToBackup.insert(fileName)
                    }
                }
                
                return Model3DDTO(
                    id: m.id,
                    name: m.name,
                    types: m.types,
                    modelPath: m.modelPath,
                    modelType: m.modelType,
                    thumbnailPath: m.thumbnailPath,
                    sourceImagePaths: m.sourceImagePaths,
                    isDeleted: m.isDeleted,
                    deletedAt: m.deletedAt,
                    createdAt: m.createdAt,
                    updatedAt: m.updatedAt,
                    sortIndex: m.sortIndex,
                    cameraPositionX: m.cameraPositionX,
                    cameraPositionY: m.cameraPositionY,
                    cameraPositionZ: m.cameraPositionZ,
                    cameraRotationX: m.cameraRotationX,
                    cameraRotationY: m.cameraRotationY,
                    cameraRotationZ: m.cameraRotationZ,
                    lastModified: m.lastModified
                )
            }
            
            // 8. Book Groups (平面手帐)
            let bookGroupDTOs: [BookGroupDTO] = try self.processByIDs(context: context, descriptor: FetchDescriptor<BookGroup>(), entityName: "BookGroups") { bg in
                // Cover image
                if let coverImage = bg.coverImage {
                    standardImagesToBackup.insert(coverImage)
                }
                
                return BookGroupDTO(
                    id: bg.id,
                    title: bg.title,
                    coverImage: bg.coverImage,
                    createdAt: bg.createdAt,
                    isDeleted: bg.isDeleted,
                    deletedAt: bg.deletedAt,
                    sortIndex: bg.sortIndex,
                    lastModified: bg.lastModified
                )
            }
            
            // 8. Space Book Groups (空间手帐)
            let spaceBookGroupDTOs: [SpaceBookGroupDTO] = try self.processByIDs(context: context, descriptor: FetchDescriptor<SpaceBookGroup>(), entityName: "SpaceBookGroups") { sbg in
                // Cover image
                if let coverImage = sbg.coverImage {
                    standardImagesToBackup.insert(coverImage)
                }
                
                return SpaceBookGroupDTO(
                    id: sbg.id,
                    title: sbg.title,
                    coverImage: sbg.coverImage,
                    createdAt: sbg.createdAt,
                    isDeleted: sbg.isDeleted,
                    deletedAt: sbg.deletedAt,
                    sortIndex: sbg.sortIndex,
                    lastModified: sbg.lastModified
                )
            }
            
            // 9. Space Outfits (空间书页) with Scene Objects
            var spaceOutfitDescriptor = FetchDescriptor<SpaceOutfit>()
            spaceOutfitDescriptor.relationshipKeyPathsForPrefetching = [\SpaceOutfit.book]
            let spaceOutfitDTOs: [SpaceOutfitDTO] = try self.processByIDs(context: context, descriptor: spaceOutfitDescriptor, entityName: "SpaceOutfits") { so in
                // Snapshot image
                if let snapshotPath = so.snapshotPath {
                    let fileName = (snapshotPath as NSString).lastPathComponent
                    standardImagesToBackup.insert(fileName)
                }
                
                // 3D Model file
                if let modelPath = so.modelPath {
                    // Model files are stored in documents directory
                    let fileName = (modelPath as NSString).lastPathComponent
                    if !fileName.isEmpty {
                        let modelURL = documentsDir.appendingPathComponent(fileName)
                        if fileManager.fileExists(atPath: modelURL.path) {
                            standardImagesToBackup.insert(fileName)
                        }
                    }
                }
                
                // Fetch scene objects for this space outfit
                // Note: Using spaceOutfitID instead of relationship
                let outfitId = so.id
                let descriptor = FetchDescriptor<SceneObjectData>(
                    predicate: #Predicate { data in
                        data.spaceOutfitID == outfitId
                    }
                )
                let sceneObjects = try? context.fetch(descriptor)
                
                let sceneObjectDTOs = sceneObjects?.map { obj in
                    SceneObjectDataDTO(
                        id: obj.id,
                        objectType: obj.objectType,
                        positionX: obj.positionX,
                        positionY: obj.positionY,
                        positionZ: obj.positionZ,
                        rotationX: obj.rotationX,
                        rotationY: obj.rotationY,
                        rotationZ: obj.rotationZ,
                        scaleX: obj.scaleX,
                        scaleY: obj.scaleY,
                        scaleZ: obj.scaleZ,
                        usdzModelPath: obj.usdzModelPath,
                        colorR: obj.colorR,
                        colorG: obj.colorG,
                        colorB: obj.colorB,
                        colorA: obj.colorA,
                        sortIndex: obj.sortIndex,
                        model3DID: obj.model3D?.id
                    )
                } ?? []
                
                return SpaceOutfitDTO(
                    id: so.id,
                    createdAt: so.createdAt,
                    note: so.note,
                    snapshotPath: so.snapshotPath,
                    sortIndex: so.sortIndex,
                    modelPath: so.modelPath,
                    camPosX: so.camPosX,
                    camPosY: so.camPosY,
                    camPosZ: so.camPosZ,
                    lightingIntensity: so.lightingIntensity,
                    isDeleted: so.isDeleted,
                    deletedAt: so.deletedAt,
                    bookID: so.book?.id,
                    sceneObjects: sceneObjectDTOs,
                    lastModified: so.lastModified
                )
            }
            
            // 10. Perler Bead Patterns (拼豆/像素画)
            let perlerBeadPatternDTOs: [PerlerBeadPatternDTO] = try self.processByIDs(context: context, descriptor: FetchDescriptor<PerlerBeadPattern>(), entityName: "PerlerBeadPatterns") { pattern in
                // Thumbnail image
                if let thumbnailPath = pattern.thumbnailPath {
                    let fileName = (thumbnailPath as NSString).lastPathComponent
                    if !fileName.isEmpty {
                        standardImagesToBackup.insert(fileName)
                    }
                }
                
                return PerlerBeadPatternDTO(
                    id: pattern.id,
                    name: pattern.name,
                    patternType: pattern.patternType,
                    resolution: pattern.resolution,
                    paletteSize: pattern.paletteSize,
                    canvasStyle: pattern.canvasStyle,
                    pixelData: pattern.pixelData,
                    paletteSortOrder: pattern.paletteSortOrder,
                    thumbnailPath: pattern.thumbnailPath,
                    isDeleted: pattern.isDeleted,
                    deletedAt: pattern.deletedAt,
                    createdAt: pattern.createdAt,
                    updatedAt: pattern.updatedAt,
                    lastModified: pattern.lastModified,
                    sortIndex: pattern.sortIndex
                )
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
            
            var hasSmallWidgetBackground = false
            var smallWidgetBackgroundURL: URL? = nil
            
            var hasMediumWidgetBackground = false
            var mediumWidgetBackgroundURL: URL? = nil
            
            var hasLargeWidgetBackground = false
            var largeWidgetBackgroundURL: URL? = nil
            
            if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: WidgetDataManager.appGroupIdentifier) {
                let widgetFile = containerURL.appendingPathComponent("widget_background.jpg")
                if fileManager.fileExists(atPath: widgetFile.path) {
                    hasWidgetBackground = true
                    widgetBackgroundURL = widgetFile
                }
                
                let smallFile = containerURL.appendingPathComponent("widget_background_small.jpg")
                if fileManager.fileExists(atPath: smallFile.path) {
                    hasSmallWidgetBackground = true
                    smallWidgetBackgroundURL = smallFile
                }
                
                let mediumFile = containerURL.appendingPathComponent("widget_background_medium.jpg")
                if fileManager.fileExists(atPath: mediumFile.path) {
                    hasMediumWidgetBackground = true
                    mediumWidgetBackgroundURL = mediumFile
                }
                
                let largeFile = containerURL.appendingPathComponent("widget_background_large.jpg")
                if fileManager.fileExists(atPath: largeFile.path) {
                    hasLargeWidgetBackground = true
                    largeWidgetBackgroundURL = largeFile
                }
            }
            
            print("### Export: Collecting files...")
            
            var imageFiles: [String: URL] = [:]
            
            for fileName in standardImagesToBackup {
                // First try images directory (most images are here)
                let imageFileURL = imagesDir.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: imageFileURL.path) {
                    imageFiles[fileName] = imageFileURL
                    continue
                }
                
                // Then try documents directory (for 3D models and other files)
                let docFileURL = documentsDir.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: docFileURL.path) {
                    imageFiles[fileName] = docFileURL
                    continue
                }
                
                print("### Export: Warning - File not found: \(fileName)")
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
            if let smallURL = smallWidgetBackgroundURL {
                imageFiles["widget_background_small.jpg"] = smallURL
            }
            if let mediumURL = mediumWidgetBackgroundURL {
                imageFiles["widget_background_medium.jpg"] = mediumURL
            }
            if let largeURL = largeWidgetBackgroundURL {
                imageFiles["widget_background_large.jpg"] = largeURL
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
            
            // Pet Status
            let petStatusData = UserDefaults.standard.data(forKey: "PetStatus_Data")
            
            // Chat History (JSON only)
            var chatHistoryData: Data? = nil
            let chatHistoryURL = documentsDir.appendingPathComponent("chat_history.json")
            if fileManager.fileExists(atPath: chatHistoryURL.path) {
                chatHistoryData = try? Data(contentsOf: chatHistoryURL)
            }
            
            // App Version
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            
            // v1.6: User Profile (当前登录用户的头像和昵称)
            var userProfileDTO: UserProfileDTO? = nil
            var userAvatarFileName: String? = nil
            
            // 从主线程获取用户资料信息
            let userProfileInfo = await MainActor.run { () -> (isAuthenticated: Bool, userId: String, nickname: String, hasAvatar: Bool, avatarFileURL: URL)? in
                let auth = AuthenticationManager.shared
                guard auth.isAuthenticated else { return nil }
                return (
                    isAuthenticated: auth.isAuthenticated,
                    userId: auth.userIdentifier,
                    nickname: auth.customNickname,
                    hasAvatar: auth.hasCustomAvatar,
                    avatarFileURL: auth.avatarFileURL
                )
            }
            
            if let info = userProfileInfo {
                userProfileDTO = UserProfileDTO(
                    userIdentifier: info.userId,
                    nickname: info.nickname,
                    updatedAt: Date()
                )
                // 如果有自定义头像，添加到备份文件列表
                if info.hasAvatar {
                    let fileURL = info.avatarFileURL
                    let fileName = fileURL.lastPathComponent
                    if fileManager.fileExists(atPath: fileURL.path) {
                        imageFiles[fileName] = fileURL
                        userAvatarFileName = fileName
                        // 添加到 externalHashes 用于增量同步
                        if let h = fileHash(fileURL) {
                            externalHashes[fileName] = h
                        }
                        print("### Export: Added user avatar: \(fileName)")
                    }
                }
            }
            
            // v1.8: Magic Tasks (魔法任务解锁状态)
            let featureStatusDTOs: [FeatureStatusDTO] = await MainActor.run {
                let manager = FeatureUnlockManager.shared
                return FeatureItem.allCases.map { feature in
                    let status = manager.getStatus(for: feature)
                    return FeatureStatusDTO(
                        featureID: feature.rawValue,
                        isUnlocked: status.isUnlocked,
                        isVisible: status.isVisible,
                        unlockedAt: status.unlockedAt,
                        unlockedBy: status.unlockedBy
                    )
                }
            }
            
            let unlockConditionDTOs: [UnlockConditionDTO] = await MainActor.run {
                let manager = FeatureUnlockManager.shared
                return FeatureItem.allCases.map { feature in
                    let condition = manager.getCondition(for: feature)
                    return UnlockConditionDTO(
                        featureID: feature.rawValue,
                        type: condition.type,
                        requiredValue: condition.requiredValue,
                        description: condition.description
                    )
                }
            }
            print("### Export: Added \(featureStatusDTOs.count) magic task statuses")
            
            // v1.8: CheckIn Records (签到打卡记录)
            let checkInRecordsDTOs: [CheckInRecordDTO] = await MainActor.run {
                let manager = DailyCheckInManager.shared
                // 获取所有打卡记录
                if let data = UserDefaults.standard.data(forKey: "dailyCheckIn.records"),
                   let records = try? JSONDecoder().decode([CheckInRecord].self, from: data) {
                    return records.map { record in
                        CheckInRecordDTO(
                            id: record.id,
                            date: record.date,
                            colors: record.colors,
                            colorHexes: record.colorHexes,
                            accessories: record.accessories,
                            weather: record.weather,
                            location: record.location,
                            isAIGenerated: record.isAIGenerated,
                            temperature: record.temperature,
                            season: record.season,
                            petName: record.petName
                        )
                    }
                }
                return []
            }
            
            let checkInStatsDTO: CheckInStatsDTO = await MainActor.run {
                let consecutiveDays = UserDefaults.standard.integer(forKey: "dailyCheckIn.consecutiveDays")
                let totalDays = UserDefaults.standard.integer(forKey: "dailyCheckIn.totalDays")
                let lastDate = UserDefaults.standard.object(forKey: "dailyCheckIn.lastDate") as? Date
                return CheckInStatsDTO(
                    consecutiveDays: consecutiveDays,
                    totalDays: totalDays,
                    lastCheckInDate: lastDate
                )
            }
            print("### Export: Added \(checkInRecordsDTOs.count) check-in records")
            
            // 获取主题配色配置
            let themeColorConfig = ThemeManager.shared.themeColorConfig
            
            let manifest = BackupManifest(
                formatVersion: BackupFormatVersion.current.rawValue,
                timestamp: Date(),
                deviceName: deviceName,
                brands: brandDTOs,
                tags: tagDTOs,
                clothings: clothingDTOs,
                storedImages: storedImageDTOs,
                cutouts: cutoutDTOs,
                outfits: nil,
                snapshots: snapshotDTOs,
                appSettings: settings,
                themeFiles: themeFiles,
                wealthFiles: wealthFiles,
                hasWidgetBackground: hasWidgetBackground,
                hasSmallWidgetBackground: hasSmallWidgetBackground,
                hasMediumWidgetBackground: hasMediumWidgetBackground,
                hasLargeWidgetBackground: hasLargeWidgetBackground,
                externalFileHashes: externalHashes,
                petStatusData: petStatusData,
                chatHistoryData: chatHistoryData,
                appVersion: appVersion,
                bookGroups: bookGroupDTOs,
                spaceBookGroups: spaceBookGroupDTOs,
                spaceOutfits: spaceOutfitDTOs,
                model3Ds: model3DDTOs,
                userProfile: userProfileDTO,
                userAvatarFile: userAvatarFileName,
                perlerBeadPatterns: perlerBeadPatternDTOs,
                featureStatuses: featureStatusDTOs,
                unlockConditions: unlockConditionDTOs,
                checkInRecords: checkInRecordsDTOs,
                checkInStats: checkInStatsDTO,
                themeColorConfig: themeColorConfig,
                clothingCount: clothingDTOs.count,
                imageCount: storedImageDTOs.count,
                outfitCount: snapshotDTOs.count,
                bookGroupCount: bookGroupDTOs.count,
                spaceBookGroupCount: spaceBookGroupDTOs.count,
                spaceOutfitCount: spaceOutfitDTOs.count,
                model3DCount: model3DDTOs.count,
                perlerBeadPatternCount: perlerBeadPatternDTOs.count
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
        let fileName = "少女心愿_\(dateString).save"
        
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

    /// 恢复上下文，用于在恢复过程中共享状态
    private struct RestoreContext {
        let manifest: BackupManifest
        let imageFiles: [String: URL]
        let context: ModelContext
        let fileManager: FileManager
        let imagesDir: URL
        let documentsDir: URL

        // 阶段2产生的映射表，供后续阶段使用
        var brandMap: [UUID: Brand] = [:]
        var tagMap: [UUID: Tag] = [:]
        var imageMetaMap: [UUID: StoredImage] = [:]

        // 阶段3产生的映射表，供后续阶段使用
        var clothingMap: [UUID: Clothing] = [:]
        var cutoutMap: [UUID: CutoutItem] = [:]
        var outfitMap: [UUID: Outfit] = [:]
        var model3DMap: [UUID: Model3D] = [:]
        var bookGroupMap: [UUID: BookGroup] = [:]
        var spaceBookGroupMap: [UUID: SpaceBookGroup] = [:]
        var perlerBeadPatternMap: [UUID: PerlerBeadPattern] = [:]

        init(manifest: BackupManifest, imageFiles: [String: URL], context: ModelContext) throws {
            self.manifest = manifest
            self.imageFiles = imageFiles
            self.context = context
            self.fileManager = FileManager.default
            self.imagesDir = ImageManager.shared.imagesDirectory
            guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw BackupError.fileCreateFailed
            }
            self.documentsDir = documentsDir
        }
    }

    /// 恢复结果，包含各模块的成功/失败状态
    struct RestoreResult {
        var filesSuccess: Bool = true
        var filesError: String?
        var brandsSuccess: Bool = true
        var brandsError: String?
        var tagsSuccess: Bool = true
        var tagsError: String?
        var storedImagesSuccess: Bool = true
        var storedImagesError: String?
        var clothingSuccess: Bool = true
        var clothingError: String?
        var cutoutItemsSuccess: Bool = true
        var cutoutItemsError: String?
        var outfitsSuccess: Bool = true
        var outfitsError: String?
        var model3DsSuccess: Bool = true
        var model3DsError: String?
        var bookGroupsSuccess: Bool = true
        var bookGroupsError: String?
        var perlerBeadsSuccess: Bool = true
        var perlerBeadsError: String?
        var settingsSuccess: Bool = true
        var settingsError: String?

        /// 是否有任何模块失败
        var hasFailures: Bool {
            !filesSuccess || !brandsSuccess || !tagsSuccess || !storedImagesSuccess ||
            !clothingSuccess || !cutoutItemsSuccess || !outfitsSuccess ||
            !model3DsSuccess || !bookGroupsSuccess || !perlerBeadsSuccess || !settingsSuccess
        }

        /// 生成错误报告
        var errorReport: String {
            var errors: [String] = []
            if let e = filesError { errors.append("文件: \(e)") }
            if let e = brandsError { errors.append("品牌: \(e)") }
            if let e = tagsError { errors.append("标签: \(e)") }
            if let e = storedImagesError { errors.append("图片: \(e)") }
            if let e = clothingError { errors.append("衣橱: \(e)") }
            if let e = cutoutItemsError { errors.append("贴纸: \(e)") }
            if let e = outfitsError { errors.append("搭配: \(e)") }
            if let e = model3DsError { errors.append("3D模型: \(e)") }
            if let e = bookGroupsError { errors.append("手帐: \(e)") }
            if let e = perlerBeadsError { errors.append("拼豆: \(e)") }
            if let e = settingsError { errors.append("设置: \(e)") }

            if errors.isEmpty {
                return "所有模块恢复成功"
            } else {
                return "以下模块恢复失败:\n" + errors.joined(separator: "\n")
            }
        }
    }

    /// Low-level restore function that takes a Manifest and a map of Image Filenames to Local URLs
    /// 采用模块化恢复策略：各模块独立执行，即使某个模块失败也不会影响其他模块
    func restoreFromManifest(manifest: BackupManifest, imageFiles: [String: URL], context: ModelContext) throws {
        // 可重入性保护
        restoreLock.lock()
        defer { restoreLock.unlock() }

        if isRestoring {
            print("### Restore: Warning - Restore already in progress, skipping...")
            throw BackupError.restoreInProgress
        }

        isRestoring = true
        defer { isRestoring = false }

        print("### Restore: Starting modular restore from manifest...")

        // 创建恢复上下文
        var ctx = try RestoreContext(manifest: manifest, imageFiles: imageFiles, context: context)
        var result = RestoreResult()

        // --- 阶段 1: 恢复文件 (图片、主题、小组件背景等) ---
        do {
            try restoreFiles(context: &ctx)
            print("✅ Stage 1 (Files): Success")
        } catch {
            result.filesSuccess = false
            result.filesError = error.localizedDescription
            print("❌ Stage 1 (Files): Failed - \(error)")
        }

        // --- 阶段 2: 恢复基础模型 ---
        // 2a. Brands
        do {
            try restoreBrands(context: &ctx)
            print("✅ Stage 2a (Brands): Success")
        } catch {
            result.brandsSuccess = false
            result.brandsError = error.localizedDescription
            print("❌ Stage 2a (Brands): Failed - \(error)")
        }

        // 2b. Tags
        do {
            try restoreTags(context: &ctx)
            print("✅ Stage 2b (Tags): Success")
        } catch {
            result.tagsSuccess = false
            result.tagsError = error.localizedDescription
            print("❌ Stage 2b (Tags): Failed - \(error)")
        }

        // 2c. StoredImages
        do {
            try restoreStoredImages(context: &ctx)
            print("✅ Stage 2c (StoredImages): Success")
        } catch {
            result.storedImagesSuccess = false
            result.storedImagesError = error.localizedDescription
            print("❌ Stage 2c (StoredImages): Failed - \(error)")
        }

        // 提交基础模型阶段
        do {
            try context.save()
            print("✅ Stage 2 Commit: Success")
        } catch {
            print("❌ Stage 2 Commit: Failed - \(error)")
            // 基础模型提交失败是严重问题，需要抛出
            throw BackupError.dataFetchFailed
        }

        // --- 阶段 3: 恢复复杂模型与关系 ---
        // 3a. Clothing 和 CutoutItem
        do {
            try restoreClothingAndOutfits(context: &ctx)
            print("✅ Stage 3a (Clothing & Cutouts): Success")
        } catch {
            result.clothingSuccess = false
            result.cutoutItemsSuccess = false
            result.clothingError = error.localizedDescription
            print("❌ Stage 3a (Clothing & Cutouts): Failed - \(error)")
        }

        // 3b. Model3D
        do {
            try restoreModel3Ds(context: &ctx)
            print("✅ Stage 3b (Model3Ds): Success")
        } catch {
            result.model3DsSuccess = false
            result.model3DsError = error.localizedDescription
            print("❌ Stage 3b (Model3Ds): Failed - \(error)")
        }

        // 3c. BookGroups
        do {
            try restoreBookGroups(context: &ctx)
            print("✅ Stage 3c (BookGroups): Success")
        } catch {
            result.bookGroupsSuccess = false
            result.bookGroupsError = error.localizedDescription
            print("❌ Stage 3c (BookGroups): Failed - \(error)")
        }

        // 3d. PerlerBeadPatterns
        do {
            try restorePerlerBeadPatterns(context: &ctx)
            print("✅ Stage 3d (PerlerBeads): Success")
        } catch {
            result.perlerBeadsSuccess = false
            result.perlerBeadsError = error.localizedDescription
            print("❌ Stage 3d (PerlerBeads): Failed - \(error)")
        }

        // --- 阶段 4: 恢复设置 ---
        do {
            try restoreSettings(context: ctx)
            print("✅ Stage 4 (Settings): Success")
        } catch {
            result.settingsSuccess = false
            result.settingsError = error.localizedDescription
            print("❌ Stage 4 (Settings): Failed - \(error)")
        }

        // --- 最终报告 ---
        print("\n========== 恢复报告 ==========")
        print(result.errorReport)
        print("==============================\n")

        // 如果有任何模块失败，抛出包含详细信息的错误
        if result.hasFailures {
            // 创建一个新的错误类型来承载详细报告
            throw RestorePartialFailureError(result: result)
        }

        print("--- Import Successful! ---")
    }

    /// 部分恢复失败错误
    struct RestorePartialFailureError: Error, LocalizedError {
        let result: RestoreResult

        var errorDescription: String? {
            result.errorReport
        }
    }

    // MARK: - 阶段 1: 恢复文件

    private func restoreFiles(context: inout RestoreContext) throws {
        print("--- Stage 1: Restoring Files ---")
        let manifest = context.manifest
        let imageFiles = context.imageFiles
        let fileManager = context.fileManager
        let imagesDir = context.imagesDir
        let documentsDir = context.documentsDir
        
        let themeFilesSet = Set(manifest.themeFiles ?? [])
        let wealthFilesSet = Set(manifest.wealthFiles ?? [])
        
        for (fileName, sourceURL) in imageFiles {
            var destinationURL: URL
            
            // 增强判定：直接检查文件名，防止 manifest 列表缺失导致路径错误
            let isThemeFileByName = fileName == "theme_background_image.png" || fileName == "theme_background_image_original.png"
            
            if themeFilesSet.contains(fileName) || wealthFilesSet.contains(fileName) || isThemeFileByName {
                // Restore to Documents
                destinationURL = documentsDir.appendingPathComponent(fileName)
            } else if (fileName == "widget_background.jpg" && manifest.hasWidgetBackground == true) ||
                      (fileName == "widget_background_small.jpg" && manifest.hasSmallWidgetBackground == true) ||
                      (fileName == "widget_background_medium.jpg" && manifest.hasMediumWidgetBackground == true) ||
                      (fileName == "widget_background_large.jpg" && manifest.hasLargeWidgetBackground == true) {
                // Restore to App Group
                 if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: WidgetDataManager.appGroupIdentifier) {
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
            let isWidgetFile = fileName.hasPrefix("widget_background")
            let isThemeFile = themeFilesSet.contains(fileName) || isThemeFileByName
            let isWealthFile = wealthFilesSet.contains(fileName)
            
            // Fix: If source and destination are the same (e.g. CloudSync using local file), skip copy to avoid self-deletion
            if sourceURL.standardizedFileURL == destinationURL.standardizedFileURL {
                print("Restore: Source and destination are the same file. Skipping copy for \(fileName).")
                continue
            }
            
            // 修复：对于 CutoutItem 图片（PNG格式），总是恢复以确保完整性
            // 因为 CutoutItem 图片是贴纸库的核心，必须确保文件正确
            let isCutoutImage = fileName.hasSuffix(".png") && !isThemeFile && !isWealthFile && !isWidgetFile
            
            // 改进：使用哈希值验证文件是否需要恢复
            var shouldRestore = false
            if !fileManager.fileExists(atPath: destinationURL.path) {
                shouldRestore = true
            } else if isThemeFile || isWealthFile || isWidgetFile || isCutoutImage {
                shouldRestore = true
            } else if let externalHashes = manifest.externalFileHashes,
                      let backupHash = externalHashes[fileName] {
                // 如果备份中有哈希值，比较本地文件和备份文件的哈希
                if let localData = try? Data(contentsOf: destinationURL) {
                    let localHash = SHA256.hash(data: localData).compactMap { String(format: "%02x", $0) }.joined()
                    if localHash != backupHash {
                        print("Restore: File \(fileName) hash mismatch (local: \(localHash.prefix(8))..., backup: \(backupHash.prefix(8))...), will restore")
                        shouldRestore = true
                    } else {
                        print("Restore: File \(fileName) hash matches, skipping")
                    }
                } else {
                    shouldRestore = true
                }
            } else {
                // 没有哈希值信息，默认恢复以确保数据完整性
                print("Restore: No hash info for \(fileName), will restore to ensure integrity")
                shouldRestore = true
            }
            
            if shouldRestore {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try? fileManager.removeItem(at: destinationURL)
                }
                
                do {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                    if isThemeFile {
                        print("Restore: Successfully restored theme file: \(fileName) to \(destinationURL.path)")
                    } else if isCutoutImage {
                        print("Restore: Successfully restored CutoutItem image: \(fileName)")
                    } else {
                        print("Restore: Successfully restored file: \(fileName)")
                    }
                } catch {
                    print("Restore: Failed to copy file \(fileName): \(error)")
                }
            }
        }
    }
    
    // MARK: - 阶段 2: 恢复基础模型
    
    private func restoreBasicModels(context: inout RestoreContext) throws {
        print("--- Stage 2: Restoring Basis Models (Brands, Tags, StoredImages) ---")
        let modelContext = context.context
        
        // 2a. Brands
        try restoreBrands(context: &context)
        
        // 2b. Tags
        try restoreTags(context: &context)
        
        // 2c. StoredImages (Metadata)
        try restoreStoredImages(context: &context)
        
        // 提交阶段 2
        try modelContext.save()
        print("--- Stage 2 Complete ---")
    }
    
    private func restoreBrands(context: inout RestoreContext) throws {
        let modelContext = context.context
        let manifest = context.manifest
        
        let existingBrands = try modelContext.fetch(FetchDescriptor<Brand>())
        var brandMap: [UUID: Brand] = [:]
        var duplicateBrands: [Brand] = []
        for brand in existingBrands {
            if brandMap[brand.id] != nil {
                print("### Restore: Warning - Duplicate Brand ID detected: \(brand.id), will merge and delete duplicate")
                duplicateBrands.append(brand)
            } else {
                brandMap[brand.id] = brand
            }
        }
        for dto in manifest.brands {
            if let existing = brandMap[dto.id] {
                // Smart merge: backup data overwrites existing
                existing.name = dto.name
                existing.colorHex = dto.colorHex
                // Image: only update if backup has value and existing doesn't, or backup is different
                if let newImagePath = dto.imagePath {
                    existing.imagePath = newImagePath
                }
            } else {
                let newBrand = Brand(name: dto.name, colorHex: dto.colorHex, imagePath: dto.imagePath)
                newBrand.id = dto.id
                modelContext.insert(newBrand)
                brandMap[dto.id] = newBrand
            }
        }
        // Delete duplicate brands after merging
        for duplicate in duplicateBrands {
            if let keeper = brandMap[duplicate.id] {
                // Merge data from duplicate to keeper before deleting
                if keeper.name.isEmpty && !duplicate.name.isEmpty {
                    keeper.name = duplicate.name
                }
                if keeper.imagePath == nil && duplicate.imagePath != nil {
                    keeper.imagePath = duplicate.imagePath
                }
            }
            modelContext.delete(duplicate)
            print("### Restore: Deleted duplicate Brand with ID: \(duplicate.id)")
        }
        
        // 保存映射表到上下文
        context.brandMap = brandMap
    }
    
    private func restoreTags(context: inout RestoreContext) throws {
        let modelContext = context.context
        let manifest = context.manifest
        
        let existingTags = try modelContext.fetch(FetchDescriptor<Tag>())
        var tagMap: [UUID: Tag] = [:]
        var duplicateTags: [Tag] = []
        for tag in existingTags {
            if tagMap[tag.id] != nil {
                print("### Restore: Warning - Duplicate Tag ID detected: \(tag.id), will merge and delete duplicate")
                duplicateTags.append(tag)
            } else {
                tagMap[tag.id] = tag
            }
        }
        for dto in manifest.tags {
            if let existing = tagMap[dto.id] {
                // Smart merge: backup data overwrites existing
                existing.name = dto.name
                existing.colorHex = dto.colorHex
            } else {
                let newTag = Tag(name: dto.name, colorHex: dto.colorHex)
                newTag.id = dto.id
                modelContext.insert(newTag)
                tagMap[dto.id] = newTag
            }
        }
        // Delete duplicate tags after merging
        for duplicate in duplicateTags {
            if let keeper = tagMap[duplicate.id] {
                // Merge data from duplicate to keeper before deleting
                if keeper.name.isEmpty && !duplicate.name.isEmpty {
                    keeper.name = duplicate.name
                }
            }
            modelContext.delete(duplicate)
            print("### Restore: Deleted duplicate Tag with ID: \(duplicate.id)")
        }
        
        // 保存映射表到上下文
        context.tagMap = tagMap
    }
    
    private func restoreStoredImages(context: inout RestoreContext) throws {
        let modelContext = context.context
        let manifest = context.manifest
        
        let existingImgMeta = try modelContext.fetch(FetchDescriptor<StoredImage>())
        var imageMetaMap: [UUID: StoredImage] = [:]
        var duplicateImages: [StoredImage] = []
        for img in existingImgMeta {
            if imageMetaMap[img.id] != nil {
                print("### Restore: Warning - Duplicate StoredImage ID detected: \(img.id), will merge and delete duplicate")
                duplicateImages.append(img)
            } else {
                imageMetaMap[img.id] = img
            }
        }
        for dto in manifest.storedImages {
            if let existing = imageMetaMap[dto.id] {
                // Smart merge: use backup refCount if it's higher (more references)
                existing.refCount = max(existing.refCount, dto.refCount)
                existing.fileName = dto.fileName
                existing.imageHash = dto.imageHash
                if let lastModified = dto.lastModified {
                    existing.lastModified = lastModified
                }
            } else {
                let newImg = StoredImage(imageHash: dto.imageHash, fileName: dto.fileName)
                newImg.id = dto.id
                newImg.refCount = dto.refCount
                newImg.lastModified = dto.lastModified ?? Date()
                modelContext.insert(newImg)
                imageMetaMap[dto.id] = newImg
            }
        }
        // Delete duplicate stored images after merging
        for duplicate in duplicateImages {
            if let keeper = imageMetaMap[duplicate.id] {
                // Merge: use higher refCount
                keeper.refCount = max(keeper.refCount, duplicate.refCount)
            }
            modelContext.delete(duplicate)
            print("### Restore: Deleted duplicate StoredImage with ID: \(duplicate.id)")
        }
        
        // 保存映射表到上下文
        context.imageMetaMap = imageMetaMap
    }
    
    // MARK: - 阶段 3: 恢复复杂模型与关系
    
    private func restoreComplexModels(context: inout RestoreContext) throws {
        print("--- Stage 3: Rebuilding Relationships ---")
        
        // 3a. 恢复 Clothing、CutoutItem、Outfit
        try restoreClothingAndOutfits(context: &context)
        
        // 3b. 恢复 Model3D
        try restoreModel3Ds(context: &context)
        
        // 3c. 恢复书册数据 (BookGroup, SpaceBookGroup, SpaceOutfit)
        try restoreBookGroups(context: &context)
        
        // 3d. 恢复拼豆图案 (PerlerBeadPattern)
        try restorePerlerBeadPatterns(context: &context)
    }
    
    private func restoreClothingAndOutfits(context: inout RestoreContext) throws {
        let modelContext = context.context
        let manifest = context.manifest
        let brandMap = context.brandMap
        let tagMap = context.tagMap
        let imagesDir = context.imagesDir
        
        // 尝试直接获取所有对象，不做任何过滤
        var descriptor = FetchDescriptor<Clothing>()
        descriptor.includePendingChanges = true
        let existingClothings = try modelContext.fetch(descriptor)

        // Debug Log: Check for soft-deleted items specifically using deletedAt to avoid property shadowing issues
        let softDeletedItems = existingClothings.filter { $0.isDeleted || $0.deletedAt != nil }
        print("### Restore: Found \(existingClothings.count) existing clothings in local DB (Soft Deleted: \(softDeletedItems.count))")

        if softDeletedItems.count > 0 {
            print("### Restore: Soft deleted items sample: \(softDeletedItems.prefix(3).map { "\($0.name) (isDeleted:\($0.isDeleted), deletedAt:\($0.deletedAt != nil))" })")
        }

        var clothingMap: [UUID: Clothing] = [:]
        var duplicateClothings: [Clothing] = []
        for clothing in existingClothings {
            if clothingMap[clothing.id] != nil {
                print("### Restore: Warning - Duplicate Clothing ID detected: \(clothing.id), will merge and delete duplicate")
                duplicateClothings.append(clothing)
            } else {
                clothingMap[clothing.id] = clothing
            }
        }
        
        // Merge duplicate clothings into the keeper before processing backup
        for duplicate in duplicateClothings {
            if let keeper = clothingMap[duplicate.id] {
                // Merge strategy: if keeper has empty/default values, use duplicate's values
                if keeper.name.isEmpty && !duplicate.name.isEmpty {
                    keeper.name = duplicate.name
                }
                // Merge image paths without duplicates
                let existingPaths = Set(keeper.imagePaths)
                for path in duplicate.imagePaths where !existingPaths.contains(path) {
                    keeper.imagePaths.append(path)
                }
                // Use higher stock value
                keeper.stock = max(keeper.stock, duplicate.stock)
                // Use higher prices if duplicate has them
                if keeper.price == 0 && duplicate.price > 0 {
                    keeper.price = duplicate.price
                }
                if keeper.deposit == 0 && duplicate.deposit > 0 {
                    keeper.deposit = duplicate.deposit
                }
                if keeper.balance == 0 && duplicate.balance > 0 {
                    keeper.balance = duplicate.balance
                }
                // Use earlier purchase date if available
                if let dupDate = duplicate.purchaseDate as Date?, dupDate < keeper.purchaseDate {
                    keeper.purchaseDate = dupDate
                }
            }
            modelContext.delete(duplicate)
            print("### Restore: Deleted duplicate Clothing with ID: \(duplicate.id)")
        }
        
        for dto in manifest.clothings {
            // Logic:
            // 1. If backup item is deleted, SKIP it (User requirement: "Don't restore deleted items").
            // 2. If local item is already deleted, KEEP it deleted (Don't revive trash).
            
            // Check if backup item is deleted (using isDeleted flag or deletedAt presence)
            let isBackupDeleted = dto.isDeleted ?? (dto.deletedAt != nil)
            if isBackupDeleted {
                // print("### Restore: Skipping deleted backup item \(dto.name) (\(dto.id))")
                continue
            }
            
            var clothingBack: Clothing!
            var isLocalDeleted = false
            
            if let existing = clothingMap[dto.id] {
                clothingBack = existing
                // Enhanced check: Use deletedAt as fallback for isDeleted
                isLocalDeleted = existing.isDeleted || existing.deletedAt != nil
                if isLocalDeleted {
                    print("### Restore: Item '\(dto.name)' (\(dto.id)) exists locally but is DELETED (isDeleted:\(existing.isDeleted), deletedAt:\(String(describing: existing.deletedAt))). Ensuring it stays deleted.")
                }
            } else {
                // Double check: Try to fetch by ID directly to be absolutely sure
                let targetID = dto.id
                let specificDescriptor = FetchDescriptor<Clothing>(predicate: #Predicate { $0.id == targetID })
                // specificDescriptor.includePendingChanges = true // FetchDescriptor struct is value type
                var specificDesc = specificDescriptor
                specificDesc.includePendingChanges = true
                
                if let found = try? modelContext.fetch(specificDesc).first {
                    // Enhanced check here too
                    let foundIsDeleted = found.isDeleted || found.deletedAt != nil
                    print("### Restore: CRITICAL - Found item '\(dto.name)' (\(dto.id)) via specific fetch which was missed in batch fetch! isDeleted=\(found.isDeleted), deletedAt=\(String(describing: found.deletedAt))")
                    clothingBack = found
                    clothingMap[dto.id] = found
                    isLocalDeleted = foundIsDeleted
                } else {
                    print("### Restore: Item '\(dto.name)' (\(dto.id)) NOT found locally. Creating new (isDeleted=false).")
                    clothingBack = Clothing(name: dto.name)
                    clothingBack.id = dto.id
                    modelContext.insert(clothingBack)
                    clothingMap[dto.id] = clothingBack
                    isLocalDeleted = false
                }
            }
            
            // Update properties - Smart merge strategy
            // Basic info: backup overwrites
            clothingBack.name = dto.name
            clothingBack.types = dto.types
            clothingBack.colors = dto.colors
            clothingBack.sizes = dto.sizes
            clothingBack.length = dto.length
            clothingBack.condition = dto.condition
            clothingBack.accessories = dto.accessories
            
            // Image paths: merge without duplicates (backup paths take priority)
            var mergedImagePaths = dto.imagePaths
            let existingPaths = Set(dto.imagePaths)
            for path in clothingBack.imagePaths where !existingPaths.contains(path) {
                mergedImagePaths.append(path)
            }
            clothingBack.imagePaths = mergedImagePaths
            
            clothingBack.isShared = dto.isShared ?? false

            // Prices: backup data overwrites (user may have updated prices)
            clothingBack.price = dto.price
            clothingBack.deposit = dto.deposit
            clothingBack.balance = dto.balance
            clothingBack.accessoriesPrice = dto.accessoriesPrice ?? 0
            
            // Dates: backup data overwrites
            clothingBack.purchaseDate = dto.purchaseDate
            clothingBack.depositDate = dto.depositDate
            clothingBack.isDepositPlan = dto.isDepositPlan
            clothingBack.finalPaymentDate = dto.finalPaymentDate
            clothingBack.finalPaymentEndDate = dto.finalPaymentEndDate
            
            clothingBack.note = dto.note
            
            // Stock: use backup value (backup is source of truth for inventory)
            clothingBack.stock = dto.stock
            
            clothingBack.status = ClothingStatus(rawValue: dto.status ?? "") ?? .onShelf
            
            // 恢复删除状态：优先使用备份的删除状态
            clothingBack.isDeleted = dto.isDeleted ?? false
            clothingBack.deletedAt = dto.deletedAt

            // 如果本地被删除但备份未删除，保持本地删除状态（避免已删除数据复活）
            if isLocalDeleted && !(dto.isDeleted ?? false) {
                clothingBack.isDeleted = true
                if clothingBack.deletedAt == nil {
                    clothingBack.deletedAt = Date()
                }
                print("### Restore: FORCE DELETED applied to '\(clothingBack.name)' (local deleted but backup not deleted)")
            }
            
            clothingBack.createdAt = dto.createdAt
            clothingBack.updatedAt = dto.updatedAt
            clothingBack.sortIndex = dto.sortIndex ?? 0
            clothingBack.replacedCutoutID = dto.replacedCutoutID
            if let lastModified = dto.lastModified {
                clothingBack.lastModified = lastModified
            }
            
            // Restore AccessoryItems
            if let accDTOs = dto.accessoryItems {
                // Delete existing (strategy: replace all)
                if let existingItems = clothingBack.accessoryItems {
                    for item in existingItems {
                        modelContext.delete(item)
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
        let existingCutouts = try modelContext.fetch(FetchDescriptor<CutoutItem>())
        var cutoutMap: [UUID: CutoutItem] = [:]
        var duplicateCutouts: [CutoutItem] = []
        for cutout in existingCutouts {
            if cutoutMap[cutout.id] != nil {
                print("### Restore: Warning - Duplicate CutoutItem ID detected: \(cutout.id), will merge and delete duplicate")
                duplicateCutouts.append(cutout)
            } else {
                cutoutMap[cutout.id] = cutout
            }
        }
        // Merge duplicate cutouts before processing backup
        for duplicate in duplicateCutouts {
            if let keeper = cutoutMap[duplicate.id] {
                // Merge: if keeper has empty category, use duplicate's
                if keeper.category.isEmpty || keeper.category == "未分类" {
                    keeper.category = duplicate.category
                }
                // Keep the linkedClothingID if keeper doesn't have one
                if keeper.linkedClothingID == nil && duplicate.linkedClothingID != nil {
                    keeper.linkedClothingID = duplicate.linkedClothingID
                }
            }
            modelContext.delete(duplicate)
            print("### Restore: Deleted duplicate CutoutItem with ID: \(duplicate.id)")
        }
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
                modelContext.insert(cutout)
                cutoutMap[dto.id] = cutout
                cutout.timestamp = dto.timestamp
            }
            if let lid = dto.linkedClothingID {
                cutout.linkedClothingID = lid
            } else {
                cutout.linkedClothingID = nil
            }
            
            // 恢复 lastModified
            if let lastModified = dto.lastModified {
                cutout.lastModified = lastModified
            }

            // 修复：确保 CutoutItem 的图片有对应的 StoredImage 记录
            // 这很重要，因为 CutoutItem 图片是通过 ImageManager.saveImage 创建的
            // 恢复时需要确保 StoredImage 记录存在，否则图片可能被误删
            if !dto.imagePath.isEmpty {
                let fileName = dto.imagePath
                let storedImageDescriptor = FetchDescriptor<StoredImage>(predicate: #Predicate { $0.fileName == fileName })
                if let existingStoredImage = try? modelContext.fetch(storedImageDescriptor).first {
                    // 确保 refCount 至少为 1
                    if existingStoredImage.refCount < 1 {
                        existingStoredImage.refCount = 1
                        print("### Restore: Fixed refCount for CutoutItem image: \(fileName)")
                    }
                } else {
                    // 如果 StoredImage 记录不存在，创建一个
                    // 计算图片哈希（如果文件存在）
                    let imageFileURL = imagesDir.appendingPathComponent(fileName)
                    var imageHash = "restored_cutout_\(fileName)"
                    if let fileData = try? Data(contentsOf: imageFileURL) {
                        let hash = SHA256.hash(data: fileData)
                        imageHash = hash.compactMap { String(format: "%02x", $0) }.joined()
                    }
                    let newStoredImage = StoredImage(imageHash: imageHash, fileName: fileName)
                    newStoredImage.refCount = 1
                    newStoredImage.lastModified = Date()
                    modelContext.insert(newStoredImage)
                    print("### Restore: Created missing StoredImage for CutoutItem: \(fileName)")
                }
            }
        }
        
        // Outfits
        let existingOutfits = try modelContext.fetch(FetchDescriptor<Outfit>())
        var outfitMap: [UUID: Outfit] = [:]
        var duplicateOutfits: [Outfit] = []
        for outfit in existingOutfits {
            if outfitMap[outfit.id] != nil {
                print("### Restore: Warning - Duplicate Outfit ID detected: \(outfit.id), will merge and delete duplicate")
                duplicateOutfits.append(outfit)
            } else {
                outfitMap[outfit.id] = outfit
            }
        }
        // Merge duplicate outfits
        for duplicate in duplicateOutfits {
            if let keeper = outfitMap[duplicate.id] {
                // Merge: use non-empty note
                if keeper.note.isEmpty && !duplicate.note.isEmpty {
                    keeper.note = duplicate.note
                }
                // Merge items without duplicates
                let existingItemIDs = Set(keeper.items?.map { $0.id } ?? [])
                for item in duplicate.items ?? [] where !existingItemIDs.contains(item.id) {
                    keeper.items?.append(item)
                }
            }
            modelContext.delete(duplicate)
            print("### Restore: Deleted duplicate Outfit with ID: \(duplicate.id)")
        }

        // Fetch ALL OutfitItems globally to avoid ID collision
        let allOutfitItems = try modelContext.fetch(FetchDescriptor<OutfitItem>())
        var globalItemMap: [UUID: OutfitItem] = [:]
        var duplicateOutfitItems: [OutfitItem] = []
        for item in allOutfitItems {
            if globalItemMap[item.id] != nil {
                print("### Restore: Warning - Duplicate OutfitItem ID detected: \(item.id), will merge and delete duplicate")
                duplicateOutfitItems.append(item)
            } else {
                globalItemMap[item.id] = item
            }
        }
        // Delete duplicate outfit items
        for duplicate in duplicateOutfitItems {
            modelContext.delete(duplicate)
            print("### Restore: Deleted duplicate OutfitItem with ID: \(duplicate.id)")
        }
        print("### Restore: Found \(globalItemMap.count) global OutfitItems.")
        
        // 建立 Cutout 反向查找表 (FileName -> CutoutItem) 以支持 Snapshot 恢复
        var cutoutFileMap: [String: CutoutItem] = [:]
        for cutout in cutoutMap.values {
            let fileName = (cutout.imagePath as NSString).lastPathComponent
            cutoutFileMap[fileName] = cutout
        }
        print("### Restore: Built cutoutFileMap with \(cutoutFileMap.count) entries from \(cutoutMap.count) cutouts.")
        
        // Pre-fetch BookGroups for Outfit relationship restoration
        let existingBookGroups = try modelContext.fetch(FetchDescriptor<BookGroup>())
        var bookGroupMap: [UUID: BookGroup] = [:]
        var duplicateBookGroups: [BookGroup] = []
        for bookGroup in existingBookGroups {
            if bookGroupMap[bookGroup.id] != nil {
                print("### Restore: Warning - Duplicate BookGroup ID detected: \(bookGroup.id), will merge and delete duplicate")
                duplicateBookGroups.append(bookGroup)
            } else {
                bookGroupMap[bookGroup.id] = bookGroup
            }
        }
        // Merge duplicate book groups
        for duplicate in duplicateBookGroups {
            if let keeper = bookGroupMap[duplicate.id] {
                // Merge: use non-empty title
                if keeper.title.isEmpty && !duplicate.title.isEmpty {
                    keeper.title = duplicate.title
                }
                // Merge pages without duplicates
                let existingPageIDs = Set(keeper.pages?.map { $0.id } ?? [])
                for page in duplicate.pages ?? [] where !existingPageIDs.contains(page.id) {
                    keeper.pages?.append(page)
                }
            }
            modelContext.delete(duplicate)
            print("### Restore: Deleted duplicate BookGroup with ID: \(duplicate.id)")
        }
        
        // 1. 优先尝试恢复 Snapshots (新版备份格式)
        if let snapshots = manifest.snapshots {
            print("### Restore: Found \(snapshots.count) snapshots. Restoring as Outfits...")
            
            for dto in snapshots {
                let outfit: Outfit
                if let existing = outfitMap[dto.id] {
                    outfit = existing
                    outfit.note = dto.note
                    outfit.snapshotPath = dto.snapshotPath
                    outfit.canvasType = dto.canvasType ?? "mannequin"
                    outfit.backgroundImagePath = dto.backgroundImagePath
                } else {
                    outfit = Outfit(note: dto.note, snapshotPath: dto.snapshotPath, canvasType: dto.canvasType ?? "mannequin", backgroundImagePath: dto.backgroundImagePath)
                    outfit.id = dto.id
                    outfit.createdAt = dto.createdAt
                    modelContext.insert(outfit)
                    outfitMap[dto.id] = outfit
                }
                
                // Restore book relationship (v1.5+)
                if let bookID = dto.bookID {
                    outfit.book = bookGroupMap[bookID]
                }
                
                // 恢复 lastModified
                if let lastModified = dto.lastModified {
                    outfit.lastModified = lastModified
                }
                
                // 恢复删除状态（兼容老版本备份）
                outfit.isDeleted = dto.isDeleted ?? false
                outfit.deletedAt = dto.deletedAt
                
                print("### Restore: Processing Outfit \(dto.note) (\(dto.id)) with \(dto.items.count) items...")
                
                // 处理 Items
                // We don't use local itemMap anymore, we use globalItemMap to prevent collision
                
                for itemDTO in dto.items {
                    // 查找对应的 Cutout
                    guard let cutout = cutoutFileMap[itemDTO.imageReference] else {
                        print("### Restore: WARNING - Cutout not found for snapshot item [\(itemDTO.imageReference)]. Skipping.")
                        if cutoutFileMap.count < 10 {
                            print("Available keys: \(cutoutFileMap.keys.joined(separator: ", "))")
                        }
                        continue
                    }
                    
                    // 计算 Scale
                    let scale = cutout.width > 0 ? (itemDTO.width / cutout.width) : 1.0
                    
                    let item: OutfitItem
                    if let ex = globalItemMap[itemDTO.id] {
                        item = ex
                        item.x = itemDTO.x
                        item.y = itemDTO.y
                        item.rotation = itemDTO.rotation
                        item.scale = scale
                        item.zIndex = itemDTO.zIndex
                        
                        // Remove dangerous check for item.outfit?.id which causes crash if old outfit is invalid
                        // We will rely on outfit.items.append(item) to establish relationship
                    } else {
                        item = OutfitItem(cutout: cutout, x: itemDTO.x, y: itemDTO.y, rotation: itemDTO.rotation, scale: scale, zIndex: itemDTO.zIndex)
                        item.id = itemDTO.id
                        modelContext.insert(item)
                        globalItemMap[item.id] = item // Update global map
                    }
                    
                    item.cutout = cutout
                    
                    // Ensure item is in outfit's list
                    // Use ID check to avoid object comparison which might trigger faults
                    if outfit.items == nil {
                        outfit.items = []
                    }
                    if !(outfit.items?.contains(where: { $0.id == item.id }) ?? false) {
                        outfit.items?.append(item)
                    }
                }
                
                print("### Restore: Outfit \(outfit.note) now has \(outfit.items?.count ?? 0) items in memory before save.")
            }
        }
        
        // 2. 尝试恢复 Outfits (旧版备份格式，兼容性保留)
        // 只有当 manifest.outfits 存在且不为空时才执行
        if let oldOutfits = manifest.outfits, !oldOutfits.isEmpty {
            print("### Restore: Found \(oldOutfits.count) legacy outfits. Restoring...")
            for dto in oldOutfits {
                // 如果 ID 已经在 Snapshot 中恢复过了，跳过
                // 或者是合并？通常备份只会有一种格式。
                
                let outfit: Outfit
                if let existing = outfitMap[dto.id] {
                    outfit = existing
                    // 仅更新基本信息，避免覆盖 Snapshot 的详细数据（如果两者共存）
                    if manifest.snapshots == nil {
                        outfit.note = dto.note
                        outfit.snapshotPath = dto.snapshotPath
                        outfit.canvasType = dto.canvasType ?? "mannequin"
                    }
                } else {
                    outfit = Outfit(note: dto.note, snapshotPath: dto.snapshotPath, canvasType: dto.canvasType ?? "mannequin")
                    outfit.id = dto.id
                    outfit.createdAt = dto.createdAt
                    modelContext.insert(outfit)
                    outfitMap[dto.id] = outfit
                }
                
                // 仅当没有 Snapshot 数据时，才使用旧格式恢复 Items
                if manifest.snapshots == nil {
                    let existingItems = outfit.items ?? []
                    var itemMap: [UUID: OutfitItem] = [:]
                    for item in existingItems {
                        if itemMap[item.id] != nil {
                            print("### Restore: Warning - Duplicate OutfitItem ID detected: \(item.id), skipping duplicate")
                        } else {
                            itemMap[item.id] = item
                        }
                    }
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
                            modelContext.insert(item)
                            item.outfit = outfit
                        }
                        if let cid = itemDTO.cutoutID, let found = cutoutMap[cid] {
                            item.cutout = found
                        } else if let backupPath = itemDTO.backupImagePath, !backupPath.isEmpty {
                            // Fallback logic...
                            let fallbackDescriptor = FetchDescriptor<CutoutItem>(predicate: #Predicate<CutoutItem> { $0.imagePath == backupPath })
                            if let existingFallback = try modelContext.fetch(fallbackDescriptor).first {
                                item.cutout = existingFallback
                            } else {
                                let newCutout = CutoutItem(
                                    originalImageHash: "restored_fallback_\(UUID().uuidString)",
                                    category: "未分类",
                                    imagePath: backupPath,
                                    width: itemDTO.backupImageWidth ?? 200,
                                    height: itemDTO.backupImageHeight ?? 200
                                )
                                modelContext.insert(newCutout)
                                item.cutout = newCutout
                            }
                        }
                    }
                }
            }
        }
        
        // 保存映射表到上下文
        context.clothingMap = clothingMap
        context.cutoutMap = cutoutMap
        context.outfitMap = outfitMap
    }
    
    private func restoreModel3Ds(context: inout RestoreContext) throws {
        let modelContext = context.context
        let manifest = context.manifest
        
        // MARK: - 阶段 3b: 恢复 Model3D (v1.5)
        print("--- Stage 3b: Restoring Model3Ds ---")
        
        var model3DMap: [UUID: Model3D] = [:]
        if let model3DDTOs = manifest.model3Ds {
            print("### Restore: Found \(model3DDTOs.count) Model3Ds.")
            
            let existingModel3Ds = try modelContext.fetch(FetchDescriptor<Model3D>())
            model3DMap = [:]
            var duplicateModel3Ds: [Model3D] = []
            for model in existingModel3Ds {
                if model3DMap[model.id] != nil {
                    print("### Restore: Warning - Duplicate Model3D ID detected: \(model.id), will merge and delete duplicate")
                    duplicateModel3Ds.append(model)
                } else {
                    model3DMap[model.id] = model
                }
            }
            // Merge duplicate Model3Ds
            for duplicate in duplicateModel3Ds {
                if let keeper = model3DMap[duplicate.id] {
                    // Merge: use non-empty name
                    if keeper.name.isEmpty && !duplicate.name.isEmpty {
                        keeper.name = duplicate.name
                    }
                    // Merge source image paths without duplicates
                    let existingPaths = Set(keeper.sourceImagePaths)
                    for path in duplicate.sourceImagePaths where !existingPaths.contains(path) {
                        keeper.sourceImagePaths.append(path)
                    }
                }
                modelContext.delete(duplicate)
                print("### Restore: Deleted duplicate Model3D with ID: \(duplicate.id)")
            }
            
            for dto in model3DDTOs {
                // Skip deleted models in backup
                if dto.isDeleted ?? false { continue }
                
                let model3D: Model3D
                if let existing = model3DMap[dto.id] {
                    model3D = existing
                    model3D.name = dto.name
                    model3D.types = dto.types
                    model3D.modelPath = dto.modelPath
                    model3D.modelType = dto.modelType
                    model3D.thumbnailPath = dto.thumbnailPath
                    model3D.sourceImagePaths = dto.sourceImagePaths
                    model3D.sortIndex = dto.sortIndex
                    model3D.cameraPositionX = dto.cameraPositionX ?? 0
                    model3D.cameraPositionY = dto.cameraPositionY ?? 0
                    model3D.cameraPositionZ = dto.cameraPositionZ ?? 0
                    model3D.cameraRotationX = dto.cameraRotationX ?? 0
                    model3D.cameraRotationY = dto.cameraRotationY ?? 0
                    model3D.cameraRotationZ = dto.cameraRotationZ ?? 0
                } else {
                    model3D = Model3D(
                        name: dto.name,
                        types: dto.types,
                        modelPath: dto.modelPath,
                        modelType: dto.modelType,
                        thumbnailPath: dto.thumbnailPath,
                        sourceImagePaths: dto.sourceImagePaths,
                        sortIndex: dto.sortIndex
                    )
                    model3D.id = dto.id
                    model3D.createdAt = dto.createdAt
                    model3D.updatedAt = dto.updatedAt
                    model3D.cameraPositionX = dto.cameraPositionX ?? 0
                    model3D.cameraPositionY = dto.cameraPositionY ?? 0
                    model3D.cameraPositionZ = dto.cameraPositionZ ?? 0
                    model3D.cameraRotationX = dto.cameraRotationX ?? 0
                    model3D.cameraRotationY = dto.cameraRotationY ?? 0
                    model3D.cameraRotationZ = dto.cameraRotationZ ?? 0
                    modelContext.insert(model3D)
                    model3DMap[dto.id] = model3D
                }
                
                // 恢复删除状态（兼容老版本备份）
                model3D.isDeleted = dto.isDeleted ?? false
                model3D.deletedAt = dto.deletedAt
                
                // 恢复 lastModified
                if let lastModified = dto.lastModified {
                    model3D.lastModified = lastModified
                }
            }
        }
        
        // 保存映射表到上下文
        context.model3DMap = model3DMap
    }
    
    private func restoreBookGroups(context: inout RestoreContext) throws {
        let modelContext = context.context
        let manifest = context.manifest
        let clothingMap = context.clothingMap
        let cutoutMap = context.cutoutMap
        let outfitMap = context.outfitMap
        let model3DMap = context.model3DMap
        
        // 初始化映射表
        var localBookGroupMap: [UUID: BookGroup] = [:]
        var spaceBookGroupMap: [UUID: SpaceBookGroup] = [:]
        
        // MARK: - 阶段 3c: 恢复书册数据 (v1.5)
        print("--- Stage 3c: Restoring Book Groups ---")
        
        // 1. 恢复平面手帐 (BookGroup)
        if let bookGroupDTOs = manifest.bookGroups {
            print("### Restore: Found \(bookGroupDTOs.count) book groups.")
            
            let existingBookGroups = try modelContext.fetch(FetchDescriptor<BookGroup>())
            localBookGroupMap = [:]
            var duplicateLocalBookGroups: [BookGroup] = []
            for bookGroup in existingBookGroups {
                if localBookGroupMap[bookGroup.id] != nil {
                    print("### Restore: Warning - Duplicate BookGroup ID detected: \(bookGroup.id), will merge and delete duplicate")
                    duplicateLocalBookGroups.append(bookGroup)
                } else {
                    localBookGroupMap[bookGroup.id] = bookGroup
                }
            }
            // Merge duplicate book groups
            for duplicate in duplicateLocalBookGroups {
                if let keeper = localBookGroupMap[duplicate.id] {
                    if keeper.title.isEmpty && !duplicate.title.isEmpty {
                        keeper.title = duplicate.title
                    }
                    if keeper.coverImage == nil && duplicate.coverImage != nil {
                        keeper.coverImage = duplicate.coverImage
                    }
                }
                modelContext.delete(duplicate)
                print("### Restore: Deleted duplicate BookGroup with ID: \(duplicate.id)")
            }
            
            for dto in bookGroupDTOs {
                // Skip deleted book groups in backup
                if dto.isDeleted ?? false { continue }

                let bookGroup: BookGroup
                if let existing = localBookGroupMap[dto.id] {
                    bookGroup = existing
                    bookGroup.title = dto.title
                    bookGroup.coverImage = dto.coverImage
                    bookGroup.sortIndex = dto.sortIndex
                } else {
                    bookGroup = BookGroup(title: dto.title, coverImage: dto.coverImage, sortIndex: dto.sortIndex)
                    bookGroup.id = dto.id
                    bookGroup.createdAt = dto.createdAt
                    modelContext.insert(bookGroup)
                    localBookGroupMap[dto.id] = bookGroup
                }
                
                // 恢复删除状态（兼容老版本备份）
                bookGroup.isDeleted = dto.isDeleted ?? false
                bookGroup.deletedAt = dto.deletedAt
                
                // 恢复 lastModified
                if let lastModified = dto.lastModified {
                    bookGroup.lastModified = lastModified
                }
            }
            
            // 2. 恢复平面书页与手帐的关联
            // Re-fetch outfits to establish book relationships
            let allOutfits = try modelContext.fetch(FetchDescriptor<Outfit>())
            for outfit in allOutfits {
                // Find if this outfit should belong to a book
                // Note: In current data model, Outfit doesn't have a direct book reference
                // This relationship is established via BookGroup.pages
                // We need to check if the backup had this relationship
            }
        }
        
        // 3. 恢复空间手帐 (SpaceBookGroup)
        if let spaceBookGroupDTOs = manifest.spaceBookGroups {
            print("### Restore: Found \(spaceBookGroupDTOs.count) space book groups.")
            
            let existingSpaceBookGroups = try modelContext.fetch(FetchDescriptor<SpaceBookGroup>())
            spaceBookGroupMap = [:]
            var duplicateSpaceBookGroups: [SpaceBookGroup] = []
            for spaceBookGroup in existingSpaceBookGroups {
                if spaceBookGroupMap[spaceBookGroup.id] != nil {
                    print("### Restore: Warning - Duplicate SpaceBookGroup ID detected: \(spaceBookGroup.id), will merge and delete duplicate")
                    duplicateSpaceBookGroups.append(spaceBookGroup)
                } else {
                    spaceBookGroupMap[spaceBookGroup.id] = spaceBookGroup
                }
            }
            // Merge duplicate space book groups
            for duplicate in duplicateSpaceBookGroups {
                if let keeper = spaceBookGroupMap[duplicate.id] {
                    if keeper.title.isEmpty && !duplicate.title.isEmpty {
                        keeper.title = duplicate.title
                    }
                    if keeper.coverImage == nil && duplicate.coverImage != nil {
                        keeper.coverImage = duplicate.coverImage
                    }
                }
                modelContext.delete(duplicate)
                print("### Restore: Deleted duplicate SpaceBookGroup with ID: \(duplicate.id)")
            }
            
            for dto in spaceBookGroupDTOs {
                // Skip deleted space book groups in backup
                if dto.isDeleted ?? false { continue }
                
                let spaceBookGroup: SpaceBookGroup
                if let existing = spaceBookGroupMap[dto.id] {
                    spaceBookGroup = existing
                    spaceBookGroup.title = dto.title
                    spaceBookGroup.coverImage = dto.coverImage
                    spaceBookGroup.sortIndex = dto.sortIndex
                } else {
                    spaceBookGroup = SpaceBookGroup(title: dto.title, coverImage: dto.coverImage, sortIndex: dto.sortIndex)
                    spaceBookGroup.id = dto.id
                    spaceBookGroup.createdAt = dto.createdAt
                    modelContext.insert(spaceBookGroup)
                    spaceBookGroupMap[dto.id] = spaceBookGroup
                }
                
                // 恢复删除状态（兼容老版本备份）
                spaceBookGroup.isDeleted = dto.isDeleted ?? false
                spaceBookGroup.deletedAt = dto.deletedAt
                
                // 恢复 lastModified
                if let lastModified = dto.lastModified {
                    spaceBookGroup.lastModified = lastModified
                }
            }
            
            // 4. 恢复空间书页 (SpaceOutfit) 与场景对象
            if let spaceOutfitDTOs = manifest.spaceOutfits {
                print("### Restore: Found \(spaceOutfitDTOs.count) space outfits.")
                
                let existingSpaceOutfits = try modelContext.fetch(FetchDescriptor<SpaceOutfit>())
                var spaceOutfitMap: [UUID: SpaceOutfit] = [:]
                var duplicateSpaceOutfits: [SpaceOutfit] = []
                for spaceOutfit in existingSpaceOutfits {
                    if spaceOutfitMap[spaceOutfit.id] != nil {
                        print("### Restore: Warning - Duplicate SpaceOutfit ID detected: \(spaceOutfit.id), will merge and delete duplicate")
                        duplicateSpaceOutfits.append(spaceOutfit)
                    } else {
                        spaceOutfitMap[spaceOutfit.id] = spaceOutfit
                    }
                }
                // Merge duplicate space outfits
                for duplicate in duplicateSpaceOutfits {
                    if let keeper = spaceOutfitMap[duplicate.id] {
                        if keeper.note.isEmpty && !duplicate.note.isEmpty {
                            keeper.note = duplicate.note
                        }
                        // Scene objects are linked via spaceOutfitID, they will be handled below
                    }
                    modelContext.delete(duplicate)
                    print("### Restore: Deleted duplicate SpaceOutfit with ID: \(duplicate.id)")
                }

                // Fetch all existing scene objects to avoid collision
                let existingSceneObjects = try modelContext.fetch(FetchDescriptor<SceneObjectData>())
                var sceneObjectMap: [UUID: SceneObjectData] = [:]
                var duplicateSceneObjects: [SceneObjectData] = []
                for sceneObject in existingSceneObjects {
                    if sceneObjectMap[sceneObject.id] != nil {
                        print("### Restore: Warning - Duplicate SceneObjectData ID detected: \(sceneObject.id), will merge and delete duplicate")
                        duplicateSceneObjects.append(sceneObject)
                    } else {
                        sceneObjectMap[sceneObject.id] = sceneObject
                    }
                }
                // Delete duplicate scene objects
                for duplicate in duplicateSceneObjects {
                    modelContext.delete(duplicate)
                    print("### Restore: Deleted duplicate SceneObjectData with ID: \(duplicate.id)")
                }
                
                for dto in spaceOutfitDTOs {
                    // Skip deleted space outfits in backup
                    if dto.isDeleted ?? false { continue }
                    
                    let spaceOutfit: SpaceOutfit
                    if let existing = spaceOutfitMap[dto.id] {
                        spaceOutfit = existing
                        spaceOutfit.note = dto.note
                        spaceOutfit.snapshotPath = dto.snapshotPath
                        spaceOutfit.sortIndex = dto.sortIndex
                        spaceOutfit.modelPath = dto.modelPath
                        spaceOutfit.camPosX = dto.camPosX
                        spaceOutfit.camPosY = dto.camPosY
                        spaceOutfit.camPosZ = dto.camPosZ
                        spaceOutfit.lightingIntensity = dto.lightingIntensity
                    } else {
                        spaceOutfit = SpaceOutfit(
                            note: dto.note,
                            snapshotPath: dto.snapshotPath,
                            book: nil, // Will set later
                            sortIndex: dto.sortIndex
                        )
                        spaceOutfit.id = dto.id
                        spaceOutfit.createdAt = dto.createdAt
                        spaceOutfit.modelPath = dto.modelPath
                        spaceOutfit.camPosX = dto.camPosX
                        spaceOutfit.camPosY = dto.camPosY
                        spaceOutfit.camPosZ = dto.camPosZ
                        spaceOutfit.lightingIntensity = dto.lightingIntensity
                        modelContext.insert(spaceOutfit)
                        spaceOutfitMap[dto.id] = spaceOutfit
                    }
                    
                    // 恢复删除状态（兼容老版本备份）
                    spaceOutfit.isDeleted = dto.isDeleted ?? false
                    spaceOutfit.deletedAt = dto.deletedAt
                    
                    // 恢复 lastModified
                    if let lastModified = dto.lastModified {
                        spaceOutfit.lastModified = lastModified
                    }
                    
                    // Re-link to book
                    if let bookID = dto.bookID {
                        spaceOutfit.book = spaceBookGroupMap[bookID]
                    }
                    
                    // Restore scene objects
                    for sceneDTO in dto.sceneObjects {
                        let sceneObject: SceneObjectData
                        if let existing = sceneObjectMap[sceneDTO.id] {
                            sceneObject = existing
                            sceneObject.objectType = sceneDTO.objectType
                            sceneObject.positionX = sceneDTO.positionX
                            sceneObject.positionY = sceneDTO.positionY
                            sceneObject.positionZ = sceneDTO.positionZ
                            sceneObject.rotationX = sceneDTO.rotationX
                            sceneObject.rotationY = sceneDTO.rotationY
                            sceneObject.rotationZ = sceneDTO.rotationZ
                            sceneObject.scaleX = sceneDTO.scaleX
                            sceneObject.scaleY = sceneDTO.scaleY
                            sceneObject.scaleZ = sceneDTO.scaleZ
                            sceneObject.usdzModelPath = sceneDTO.usdzModelPath
                            sceneObject.colorR = sceneDTO.colorR
                            sceneObject.colorG = sceneDTO.colorG
                            sceneObject.colorB = sceneDTO.colorB
                            sceneObject.colorA = sceneDTO.colorA
                            sceneObject.sortIndex = sceneDTO.sortIndex
                            // Re-link Model3D if applicable
                            if let model3DID = sceneDTO.model3DID {
                                sceneObject.model3D = model3DMap[model3DID]
                            }
                        } else {
                            sceneObject = SceneObjectData(
                                id: sceneDTO.id,
                                objectType: sceneDTO.objectType,
                                position: SIMD3<Float>(Float(sceneDTO.positionX), Float(sceneDTO.positionY), Float(sceneDTO.positionZ)),
                                rotation: SIMD3<Float>(Float(sceneDTO.rotationX), Float(sceneDTO.rotationY), Float(sceneDTO.rotationZ)),
                                scale: SIMD3<Float>(Float(sceneDTO.scaleX), Float(sceneDTO.scaleY), Float(sceneDTO.scaleZ)),
                                usdzModelPath: sceneDTO.usdzModelPath,
                                color: SIMD4<Float>(Float(sceneDTO.colorR), Float(sceneDTO.colorG), Float(sceneDTO.colorB), Float(sceneDTO.colorA)),
                                sortIndex: sceneDTO.sortIndex,
                                spaceOutfitID: spaceOutfit.id,
                                model3D: sceneDTO.model3DID.flatMap { model3DMap[$0] }
                            )
                            modelContext.insert(sceneObject)
                            sceneObjectMap[sceneDTO.id] = sceneObject
                        }
                    }
                }
            }
        }
        
        // 保存映射表到上下文
        context.bookGroupMap = localBookGroupMap
        context.spaceBookGroupMap = spaceBookGroupMap
    }
    
    // MARK: - 阶段 3d: 恢复拼豆图案
    
    private func restorePerlerBeadPatterns(context: inout RestoreContext) throws {
        let modelContext = context.context
        let manifest = context.manifest
        
        print("--- Stage 3d: Restoring Perler Bead Patterns ---")
        
        if let patternDTOs = manifest.perlerBeadPatterns {
            print("### Restore: Found \(patternDTOs.count) perler bead patterns.")
            
            let existingPatterns = try modelContext.fetch(FetchDescriptor<PerlerBeadPattern>())
            var patternMap: [UUID: PerlerBeadPattern] = [:]
            var duplicatePatterns: [PerlerBeadPattern] = []
            for pattern in existingPatterns {
                if patternMap[pattern.id] != nil {
                    print("### Restore: Warning - Duplicate PerlerBeadPattern ID detected: \(pattern.id), will merge and delete duplicate")
                    duplicatePatterns.append(pattern)
                } else {
                    patternMap[pattern.id] = pattern
                }
            }
            // Merge duplicate patterns
            for duplicate in duplicatePatterns {
                if let keeper = patternMap[duplicate.id] {
                    // Merge: use non-empty name
                    if keeper.name.isEmpty && !duplicate.name.isEmpty {
                        keeper.name = duplicate.name
                    }
                    // Merge thumbnail paths
                    if keeper.thumbnailPath == nil && duplicate.thumbnailPath != nil {
                        keeper.thumbnailPath = duplicate.thumbnailPath
                    }
                }
                modelContext.delete(duplicate)
                print("### Restore: Deleted duplicate PerlerBeadPattern with ID: \(duplicate.id)")
            }
            
            for dto in patternDTOs {
                // Skip deleted patterns in backup
                if dto.isDeleted ?? false { continue }
                
                let pattern: PerlerBeadPattern
                if let existing = patternMap[dto.id] {
                    pattern = existing
                    pattern.name = dto.name
                    pattern.patternType = dto.patternType
                    pattern.resolution = dto.resolution
                    pattern.paletteSize = dto.paletteSize
                    pattern.canvasStyle = dto.canvasStyle
                    pattern.pixelData = dto.pixelData
                    pattern.paletteSortOrder = dto.paletteSortOrder
                    pattern.thumbnailPath = dto.thumbnailPath
                    pattern.sortIndex = dto.sortIndex
                } else {
                    pattern = PerlerBeadPattern(
                        name: dto.name,
                        patternType: PerlerPatternType(rawValue: dto.patternType) ?? .perlerBeads,
                        resolution: PerlerBeadsConfig.Resolution(rawValue: dto.resolution) ?? .x64,
                        paletteSize: PerlerBeadsConfig.PaletteSize(rawValue: dto.paletteSize) ?? .c48,
                        canvasStyle: dto.canvasStyle == "pixelArt" ? .pixelArt : .perlerBeads,
                        pixelData: dto.pixelData,
                        paletteSortOrder: dto.paletteSortOrder == "byHue" ? .byHue : .byId,
                        thumbnailPath: dto.thumbnailPath
                    )
                    pattern.id = dto.id
                    pattern.createdAt = dto.createdAt
                    pattern.updatedAt = dto.updatedAt
                    pattern.sortIndex = dto.sortIndex
                    modelContext.insert(pattern)
                    patternMap[dto.id] = pattern
                }
                
                // 恢复删除状态（兼容老版本备份）
                pattern.isDeleted = dto.isDeleted ?? false
                pattern.deletedAt = dto.deletedAt
                
                // 恢复 lastModified
                if let lastModified = dto.lastModified {
                    pattern.lastModified = lastModified
                }
            }
            
            // 保存映射表到上下文
            context.perlerBeadPatternMap = patternMap
        }
    }
    
    // MARK: - 阶段 4: 恢复设置
    
    private func restoreSettings(context: RestoreContext) throws {
        print("--- Stage 4: Restoring Settings ---")
        let manifest = context.manifest
        let imageFiles = context.imageFiles
        let documentsDir = context.documentsDir
        let fileManager = context.fileManager
        
        // 1. 恢复 UserDefaults 设置
        restoreUserDefaultsSettings(manifest: manifest)
        
        // 2. 恢复 Pet Status
        restorePetStatus(manifest: manifest)
        
        // 3. 恢复 Chat History
        restoreChatHistory(manifest: manifest, documentsDir: documentsDir, fileManager: fileManager)
        
        // 4. 恢复 User Profile (头像和昵称)
        restoreUserProfile(manifest: manifest, imageFiles: imageFiles, documentsDir: documentsDir, fileManager: fileManager)
        
        // 5. 恢复魔法任务 (v1.8+)
        restoreMagicTasks(manifest: manifest)
        
        // 6. 恢复签到打卡 (v1.8+)
        restoreCheckInRecords(manifest: manifest)
        
        // 7. 恢复主题配色配置 (v1.9+)
        restoreThemeColorConfig(manifest: manifest)
        
        // 8. 刷新主题和小组件
        refreshThemeAndWidget(documentsDir: documentsDir, fileManager: fileManager)
        
        // 8. 版本检查与缓存清理
        performVersionCheckAndCacheClear(manifest: manifest)
    }
    
    private func restoreUserDefaultsSettings(manifest: BackupManifest) {
        // 1. Reset all known keys to default (remove from UserDefaults)
        // This ensures that if a key is missing in the backup (e.g. user was using default),
        // we don't keep dirty state from current session.
        for key in BackupService.keysToBackup {
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        if let settings = manifest.appSettings {
            for (key, value) in settings {
                print("Restore Setting: \(key) = \(value)")
                switch key {
                case "theme_background_opacity", "theme_transparent_opacity", "theme_tint_opacity":
                    // Fix: Handle both String (legacy backup) and Number types
                    if let doubleVal = Double(value) {
                        UserDefaults.standard.set(doubleVal, forKey: key)
                    } else if let doubleVal = value as? Double {
                         UserDefaults.standard.set(doubleVal, forKey: key)
                    }
                case "theme_is_blur_enabled", "isDepositNotificationEnabled", "shouldShowWealthContainerBackground", "HasRedeemedVIP_Prince":
                    if let boolVal = Bool(value) { UserDefaults.standard.set(boolVal, forKey: key) }
                    else if let intVal = Int(value) { UserDefaults.standard.set(intVal == 1, forKey: key) }
                case "depositNotificationDaysBefore":
                    if let intVal = Int(value) { UserDefaults.standard.set(intVal, forKey: key) }
                case "depositNotificationDaysList":
                    let stringValues = value.components(separatedBy: ",")
                    let intValues = stringValues.compactMap { Int($0) }
                    UserDefaults.standard.set(intValues, forKey: key)
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
        }
        
    }
    
    private func restorePetStatus(manifest: BackupManifest) {
        if let petData = manifest.petStatusData {
            print("Restore: Restoring Pet Status...")
            UserDefaults.standard.set(petData, forKey: "PetStatus_Data")
            
            // Force reload data manager
            DispatchQueue.main.async {
                PetDataManager.shared.reloadFromDisk()
            }
        }
    }
    
    private func restoreChatHistory(manifest: BackupManifest, documentsDir: URL, fileManager: FileManager) {
        if let chatData = manifest.chatHistoryData {
            print("Restore: Restoring Chat History (JSON)...")
            let chatHistoryURL = documentsDir.appendingPathComponent("chat_history.json")
            if fileManager.fileExists(atPath: chatHistoryURL.path) {
                try? fileManager.removeItem(at: chatHistoryURL)
            }
            try? chatData.write(to: chatHistoryURL)
            
            // Reload Pet AI Service
            DispatchQueue.main.async {
                PetAIService.shared.reloadHistory()
            }
        }
    }
    
    private func restoreUserProfile(manifest: BackupManifest, imageFiles: [String: URL], documentsDir: URL, fileManager: FileManager) {
        // v1.6: Restore User Profile (头像和昵称)
        if let userProfile = manifest.userProfile {
            print("Restore: Restoring User Profile...")
            
            // 恢复用户资料到 UserDefaults
            if let userProfilesData = UserDefaults.standard.string(forKey: "userProfiles"),
               let data = userProfilesData.data(using: .utf8),
               var profiles = try? JSONDecoder().decode([String: AuthenticationManager.UserProfile].self, from: data) {
                
                // 更新或添加当前用户的资料
                let profile = AuthenticationManager.UserProfile(
                    nickname: userProfile.nickname,
                    avatarPath: "", // 将在下面设置
                    updatedAt: userProfile.updatedAt
                )
                profiles[userProfile.userIdentifier] = profile
                
                if let updatedData = try? JSONEncoder().encode(profiles),
                   let updatedJson = String(data: updatedData, encoding: .utf8) {
                    UserDefaults.standard.set(updatedJson, forKey: "userProfiles")
                }
            }
            
            // 恢复头像文件
            if let avatarFileName = manifest.userAvatarFile,
               let avatarSourceURL = imageFiles[avatarFileName] {
                let avatarDir = documentsDir.appendingPathComponent("UserAvatars", isDirectory: true)
                try? fileManager.createDirectory(at: avatarDir, withIntermediateDirectories: true)
                
                let avatarDestURL = avatarDir.appendingPathComponent(avatarFileName)
                
                // 如果源和目标不同，则复制
                if avatarSourceURL.standardizedFileURL != avatarDestURL.standardizedFileURL {
                    if fileManager.fileExists(atPath: avatarDestURL.path) {
                        try? fileManager.removeItem(at: avatarDestURL)
                    }
                    try? fileManager.copyItem(at: avatarSourceURL, to: avatarDestURL)
                }
                
                // 更新用户资料中的头像路径（只存储文件名）
                if let userProfilesData = UserDefaults.standard.string(forKey: "userProfiles"),
                   let data = userProfilesData.data(using: .utf8),
                   var profiles = try? JSONDecoder().decode([String: AuthenticationManager.UserProfile].self, from: data) {
                    
                    if var profile = profiles[userProfile.userIdentifier] {
                        profile.avatarPath = avatarFileName  // 只存储文件名
                        profiles[userProfile.userIdentifier] = profile
                        
                        if let updatedData = try? JSONEncoder().encode(profiles),
                           let updatedJson = String(data: updatedData, encoding: .utf8) {
                            UserDefaults.standard.set(updatedJson, forKey: "userProfiles")
                        }
                    }
                }
                
                print("Restore: User avatar restored to \(avatarDestURL.path)")
            }
            
            // 如果当前登录用户与备份用户相同，刷新 AuthenticationManager
            DispatchQueue.main.async {
                let authManager = AuthenticationManager.shared
                if authManager.isAuthenticated && authManager.userIdentifier == userProfile.userIdentifier {
                    authManager.loadCurrentUserProfile()
                    print("Restore: Current user profile refreshed")
                }
            }
        }
    }
    
    private func refreshThemeAndWidget(documentsDir: URL, fileManager: FileManager) {
        // Refresh Theme & Widget
        print("Restore: Reloading Theme Background...")
        ThemeManager.shared.reloadBackgroundImage()
        
        if ThemeManager.shared.backgroundImage != nil {
             print("Restore: Theme Background loaded successfully.")
        } else {
             print("Restore: WARNING - Theme Background is nil after reload.")
             let themeURL = documentsDir.appendingPathComponent("theme_background_image.png")
             print("Restore: File at \(themeURL.path) exists? \(fileManager.fileExists(atPath: themeURL.path))")
        }
        
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func performVersionCheckAndCacheClear(manifest: BackupManifest) {
        // Version Check & Cache Clearing
        // 若 app版本不一致，则清理缓存（尤其是House空间照片缓存）
        if let backupAppVersion = manifest.appVersion {
            let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            if backupAppVersion != currentAppVersion {
                print("Restore: App Version Mismatch (Backup: \(backupAppVersion), Current: \(currentAppVersion ?? "Unknown")). Clearing Spatial Cache...")
                SpatialAssetManager.shared.clearAllCache()
            }
        }
    }
    
    // MARK: - 恢复魔法任务 (v1.8+)
    
    private func restoreMagicTasks(manifest: BackupManifest) {
        // 恢复魔法任务解锁状态
        if let featureStatusDTOs = manifest.featureStatuses {
            print("Restore: Restoring \(featureStatusDTOs.count) magic task statuses...")
            
            var restoredStatuses: [String: FeatureStatus] = [:]
            for dto in featureStatusDTOs {
                let status = FeatureStatus(
                    isUnlocked: dto.isUnlocked,
                    isVisible: dto.isVisible,
                    unlockedAt: dto.unlockedAt,
                    unlockedBy: dto.unlockedBy
                )
                restoredStatuses[dto.featureID] = status
            }
            
            // 保存到 UserDefaults
            if let encoded = try? JSONEncoder().encode(restoredStatuses) {
                UserDefaults.standard.set(encoded, forKey: "featureUnlock.statuses")
                print("Restore: Magic task statuses saved to UserDefaults")
            }
        }
        
        // 恢复魔法任务解锁条件配置
        if let unlockConditionDTOs = manifest.unlockConditions {
            print("Restore: Restoring \(unlockConditionDTOs.count) unlock conditions...")
            
            var restoredConditions: [String: UnlockCondition] = [:]
            for dto in unlockConditionDTOs {
                let condition = UnlockCondition(
                    type: dto.type,
                    requiredValue: dto.requiredValue,
                    description: dto.description
                )
                restoredConditions[dto.featureID] = condition
            }
            
            // 保存到 UserDefaults
            if let encoded = try? JSONEncoder().encode(restoredConditions) {
                UserDefaults.standard.set(encoded, forKey: "featureUnlock.conditions")
                print("Restore: Unlock conditions saved to UserDefaults")
            }
        }
        
        // 刷新 FeatureUnlockManager
        DispatchQueue.main.async {
            FeatureUnlockManager.shared.reloadFromDisk()
            print("Restore: FeatureUnlockManager reloaded")
        }
    }
    
    // MARK: - 恢复签到打卡 (v1.8+)
    
    private func restoreCheckInRecords(manifest: BackupManifest) {
        // 恢复打卡记录
        if let checkInRecordDTOs = manifest.checkInRecords {
            print("Restore: Restoring \(checkInRecordDTOs.count) check-in records...")
            
            let records = checkInRecordDTOs.map { dto in
                CheckInRecord(
                    id: dto.id,
                    date: dto.date,
                    colors: dto.colors,
                    colorHexes: dto.colorHexes ?? Array(repeating: nil, count: dto.colors.count),
                    accessories: dto.accessories,
                    weather: dto.weather,
                    location: dto.location,
                    temperature: dto.temperature,
                    season: dto.season,
                    isAIGenerated: dto.isAIGenerated,
                    petName: dto.petName
                )
            }
            
            // 保存到 UserDefaults
            if let encoded = try? JSONEncoder().encode(records) {
                UserDefaults.standard.set(encoded, forKey: "dailyCheckIn.records")
                print("Restore: Check-in records saved to UserDefaults")
            }
        }
        
        // 恢复签到统计数据
        if let stats = manifest.checkInStats {
            print("Restore: Restoring check-in stats...")
            UserDefaults.standard.set(stats.consecutiveDays, forKey: "dailyCheckIn.consecutiveDays")
            UserDefaults.standard.set(stats.totalDays, forKey: "dailyCheckIn.totalDays")
            if let lastDate = stats.lastCheckInDate {
                UserDefaults.standard.set(lastDate, forKey: "dailyCheckIn.lastDate")
            }
            // 同时恢复魔法任务需要的登录天数进度
            UserDefaults.standard.set(stats.totalDays, forKey: "loginDays")
            print("Restore: Check-in stats saved to UserDefaults (totalDays: \(stats.totalDays))")
        }

        // 刷新 DailyCheckInManager
        DispatchQueue.main.async {
            // 通过重新初始化来加载新数据
            DailyCheckInManager.shared.reloadFromDisk()
            // 同时刷新 FeatureUnlockManager 的登录天数缓存
            FeatureUnlockManager.shared.updateLoginDays(manifest.checkInStats?.totalDays ?? 0)
            print("Restore: DailyCheckInManager reloaded")
        }
    }

    // MARK: - 恢复主题配色配置 (v1.9+)

    private func restoreThemeColorConfig(manifest: BackupManifest) {
        if let config = manifest.themeColorConfig {
            print("Restore: Restoring theme color config...")
            ThemeManager.shared.themeColorConfig = config
            print("Restore: Theme color config restored successfully")
        } else {
            print("Restore: No theme color config found in backup (backward compatibility)")
        }
    }

    /// 从文件导入备份
    /// 注意：此方法需要在主线程调用，因为 ModelContext 只能在主线程使用
    func importBackup(from url: URL, context: ModelContext) async throws {
        print("### Import: Starting native-wrapper based import from \(url.path)")

        // 确保在主线程执行
        await MainActor.run {
            print("### Import: Running on MainActor")
        }

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

        print("### Import: Decoding manifest.json (\(manifestData.count) bytes)...")
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601

        // 尝试解码，如果失败则记录详细的解码错误
        let manifest: BackupManifest
        do {
            manifest = try jsonDecoder.decode(BackupManifest.self, from: manifestData)
            print("### Import: Manifest decoded successfully. Format Version: \(manifest.backupVersion.versionString) (raw: \(manifest.formatVersion)), Backup Date: \(manifest.timestamp)")
        } catch let decodingError as DecodingError {
            print("### Import: FAILED to decode manifest - \(decodingError)")
            // 详细的解码错误信息
            switch decodingError {
            case .keyNotFound(let key, let context):
                print("### Import: Missing key '\(key.stringValue)' in \(context.codingPath)")
            case .typeMismatch(let type, let context):
                print("### Import: Type mismatch for \(type) in \(context.codingPath): \(context.debugDescription)")
            case .valueNotFound(let type, let context):
                print("### Import: Value not found for \(type) in \(context.codingPath)")
            case .dataCorrupted(let context):
                print("### Import: Data corrupted: \(context.debugDescription)")
            @unknown default:
                print("### Import: Unknown decoding error: \(decodingError)")
            }
            throw BackupError.invalidArchive
        } catch {
            print("### Import: Unexpected error decoding manifest: \(error)")
            throw BackupError.invalidArchive
        }

        // 4. Prepare temporary files for restoration
        print("### Import: Preparing temporary files...")
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        print("### Import: Created temp directory: \(tempDir.path)")

        var tempFileMap: [String: URL] = [:]
        let fileCount = fileMap.count - 1 // excluding manifest.json
        var processedCount = 0

        print("### Import: Writing \(fileCount) files to temp directory...")
        for (fileName, data) in fileMap where fileName != "manifest.json" {
            let tempURL = tempDir.appendingPathComponent(fileName)
            do {
                try data.write(to: tempURL)
                tempFileMap[fileName] = tempURL
                processedCount += 1
                if processedCount % 100 == 0 {
                    print("### Import: Written \(processedCount)/\(fileCount) files...")
                }
            } catch {
                print("### Import: Failed to write file \(fileName): \(error)")
                throw error
            }
        }
        print("### Import: All \(processedCount) files written to temp directory")

        // 5. Call internal restore (已经在主线程，直接调用)
        print("### Import: Calling restoreFromManifest...")
        do {
            try restoreFromManifest(manifest: manifest, imageFiles: tempFileMap, context: context)
            print("### Import: restoreFromManifest completed successfully")
        } catch {
            print("### Import: restoreFromManifest failed with error: \(error)")
            // 恢复失败时清理临时目录并抛出错误
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }

        // 6. Cleanup
        print("### Import: Cleaning up temp directory...")
        try? FileManager.default.removeItem(at: tempDir)
        print("### Import: Cleanup completed")
    }
}
