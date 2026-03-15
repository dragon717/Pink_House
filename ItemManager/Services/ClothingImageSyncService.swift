//
//  ClothingImageSyncService.swift
//  ItemManager
//
//  裙装主图 CloudKit 实时同步服务
//  使用 Private Database 确保用户数据安全
//

import Foundation
import CloudKit
import SwiftData
import UIKit
import CryptoKit
import Combine

// MARK: - 同步状态枚举
enum ImageSyncStatus: Equatable {
    case idle
    case uploading(imageName: String, progress: Double)
    case downloading(imageName: String, progress: Double)
    case syncing
    case completed
    case failed(Error)
    
    static func == (lhs: ImageSyncStatus, rhs: ImageSyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.syncing, .syncing), (.completed, .completed):
            return true
        case (.uploading(let n1, let p1), .uploading(let n2, let p2)):
            return n1 == n2 && p1 == p2
        case (.downloading(let n1, let p1), .downloading(let n2, let p2)):
            return n1 == n2 && p1 == p2
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

// MARK: - 同步记录模型
@Model
final class ClothingImageSyncRecord {
    var id: UUID = UUID()
    var clothingID: UUID = UUID()
    var imageFileName: String = ""
    var imageHash: String = ""
    var cloudRecordID: String? = nil
    var lastSyncDate: Date? = nil
    var syncStatus: String = "pending" // pending, synced, failed
    var retryCount: Int = 0
    var lastError: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    init(clothingID: UUID, imageFileName: String, imageHash: String) {
        self.id = UUID()
        self.clothingID = clothingID
        self.imageFileName = imageFileName
        self.imageHash = imageHash
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - CloudKit 记录类型常量
private enum CKRecordTypes {
    static let clothingImage = "ClothingImage_v1"
    static let syncIndex = "ClothingImageSyncIndex_v1"
}

// MARK: - 主同步服务
@MainActor
final class ClothingImageSyncService: ObservableObject {
    static let shared = ClothingImageSyncService()
    
    // CloudKit 容器
    private let container = CKContainer(identifier: "iCloud.bugod2.ItemManager")
    private var database: CKDatabase {
        return container.privateCloudDatabase
    }
    
    // 发布状态
    @Published var syncStatus: ImageSyncStatus = .idle
    @Published var pendingUploadCount: Int = 0
    @Published var lastSyncDate: Date?
    @Published var isCloudKitAvailable: Bool = false
    
    // 同步队列
    private let syncQueue = OperationQueue()
    private var cancellables = Set<AnyCancellable>()
    private var syncTimer: Timer?
    
    // 用户记录ID缓存
    private var userRecordID: CKRecord.ID?
    
    private init() {
        syncQueue.maxConcurrentOperationCount = 3
        syncQueue.qualityOfService = .utility
        
        // 初始化时检查 CloudKit 可用性
        Task {
            await checkCloudKitAvailability()
            await cleanupOldSyncRecords()
        }
        
        // 设置定时同步
        setupPeriodicSync()
    }
    
    // MARK: - CloudKit 可用性检查
    
    func checkCloudKitAvailability() async {
        do {
            let status = try await container.accountStatus()
            await MainActor.run {
                self.isCloudKitAvailable = (status == .available)
            }
        } catch {
            await MainActor.run {
                self.isCloudKitAvailable = false
            }
        }
    }
    
    // MARK: - 定时同步设置
    
    private func setupPeriodicSync() {
        // 每5分钟检查一次待同步的图片
        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task {
                await self?.syncPendingImages()
            }
        }
    }
    
    // MARK: - 用户记录ID
    
    private func fetchUserRecordID() async throws -> CKRecord.ID {
        if let existing = userRecordID {
            return existing
        }
        
        let id = try await container.userRecordID()
        userRecordID = id
        return id
    }
    
    // MARK: - 图片同步入口
    
    /// 同步裙装的所有图片到 CloudKit
    /// - Parameters:
    ///   - clothing: 裙装对象
    ///   - context: ModelContext
    func syncClothingImages(clothing: Clothing, context: ModelContext) async {
        guard await isCloudKitAvailable else {
            AppLogger.info("CloudKit 不可用，跳过图片同步")
            return
        }
        
        let imagePaths = clothing.imagePaths
        guard !imagePaths.isEmpty else { return }
        
        await MainActor.run {
            self.syncStatus = .syncing
        }
        
        for (index, imageName) in imagePaths.enumerated() {
            let progress = Double(index) / Double(imagePaths.count)
            await MainActor.run {
                self.syncStatus = .uploading(imageName: imageName, progress: progress)
            }
            
            await syncSingleImage(
                clothingID: clothing.id,
                imageFileName: imageName,
                context: context
            )
        }
        
        await MainActor.run {
            self.syncStatus = .completed
            self.lastSyncDate = Date()
        }
    }
    
    /// 同步单张图片
    private func syncSingleImage(clothingID: UUID, imageFileName: String, context: ModelContext) async {
        // 1. 检查本地文件是否存在
        let fileURL = ImageManager.shared.imagesDirectory.appendingPathComponent(imageFileName)
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            AppLogger.error("本地图片不存在: \(imageFileName)")
            return
        }
        
        // 2. 计算图片哈希
        guard let imageData = try? Data(contentsOf: fileURL),
              let hash = calculateHash(data: imageData) else {
            AppLogger.error("无法计算图片哈希: \(imageFileName)")
            return
        }
        
        // 3. 检查是否已同步
        let descriptor = FetchDescriptor<ClothingImageSyncRecord>(
            predicate: #Predicate { $0.imageFileName == imageFileName && $0.syncStatus == "synced" }
        )
        
        do {
            let existingRecords = try context.fetch(descriptor)
            if let existing = existingRecords.first,
               existing.imageHash == hash {
                // 图片未变化，跳过
                AppLogger.info("图片已同步且未变化: \(imageFileName)")
                return
            }
        } catch {
            AppLogger.error("查询同步记录失败: \(error)")
        }
        
        // 4. 创建或更新同步记录
        let syncRecord: ClothingImageSyncRecord
        let existingDescriptor = FetchDescriptor<ClothingImageSyncRecord>(
            predicate: #Predicate { $0.imageFileName == imageFileName }
        )
        
        if let existing = try? context.fetch(existingDescriptor).first {
            syncRecord = existing
            syncRecord.imageHash = hash
            syncRecord.syncStatus = "pending"
            syncRecord.updatedAt = Date()
        } else {
            syncRecord = ClothingImageSyncRecord(
                clothingID: clothingID,
                imageFileName: imageFileName,
                imageHash: hash
            )
            context.insert(syncRecord)
        }
        
        // 5. 上传到 CloudKit
        do {
            try await uploadImageToCloudKit(
                fileURL: fileURL,
                imageName: imageFileName,
                hash: hash,
                clothingID: clothingID,
                syncRecord: syncRecord
            )
            
            syncRecord.syncStatus = "synced"
            syncRecord.lastSyncDate = Date()
            syncRecord.retryCount = 0
            syncRecord.lastError = nil
            
            try context.save()
            AppLogger.info("图片同步成功: \(imageFileName)")
            
        } catch {
            syncRecord.syncStatus = "failed"
            syncRecord.retryCount += 1
            syncRecord.lastError = error.localizedDescription
            syncRecord.updatedAt = Date()
            
            try? context.save()
            AppLogger.error("图片同步失败: \(imageFileName), 错误: \(error)")
        }
    }
    
    // MARK: - CloudKit 上传
    
    private func uploadImageToCloudKit(
        fileURL: URL,
        imageName: String,
        hash: String,
        clothingID: UUID,
        syncRecord: ClothingImageSyncRecord
    ) async throws {
        
        // 创建 CloudKit 记录
        let recordID = CKRecord.ID(recordName: "ClothingImage_\(hash)")
        let record: CKRecord
        
        do {
            // 尝试获取现有记录
            record = try await database.record(for: recordID)
        } catch {
            // 记录不存在，创建新记录
            record = CKRecord(recordType: CKRecordTypes.clothingImage, recordID: recordID)
        }
        
        // 设置记录字段
        record["imageAsset"] = CKAsset(fileURL: fileURL)
        record["imageHash"] = hash
        record["imageName"] = imageName
        record["clothingID"] = clothingID.uuidString
        record["uploadDate"] = Date()
        record["fileSize"] = try Data(contentsOf: fileURL).count
        
        // 保存到 CloudKit
        let savedRecord = try await database.save(record)
        
        // 更新同步记录
        syncRecord.cloudRecordID = savedRecord.recordID.recordName
        
        AppLogger.info("图片已上传到 CloudKit: \(imageName)")
    }
    
    // MARK: - 从 CloudKit 下载图片
    
    /// 从 CloudKit 下载图片到本地
    /// - Parameters:
    ///   - imageName: 图片文件名
    ///   - clothingID: 裙装ID
    ///   - context: ModelContext
    /// - Returns: 下载是否成功
    func downloadImageFromCloudKit(
        imageName: String,
        clothingID: UUID,
        context: ModelContext
    ) async -> Bool {
        guard await isCloudKitAvailable else {
            return false
        }
        
        await MainActor.run {
            self.syncStatus = .downloading(imageName: imageName, progress: 0)
        }
        
        do {
            // 1. 查询 CloudKit 记录
            let predicate = NSPredicate(format: "imageName == %@ AND clothingID == %@", 
                                       imageName, clothingID.uuidString)
            let query = CKQuery(recordType: CKRecordTypes.clothingImage, predicate: predicate)
            
            let (results, _) = try await database.records(matching: query)
            
            // 处理 Result 类型
            guard let (_, result) = results.first else {
                AppLogger.error("CloudKit 中未找到图片记录: \(imageName)")
                return false
            }
            
            let record: CKRecord
            switch result {
            case .success(let rec):
                record = rec
            case .failure(let error):
                AppLogger.error("获取 CloudKit 记录失败: \(error)")
                return false
            }
            
            // 2. 获取图片资源
            guard let asset = record["imageAsset"] as? CKAsset,
                  let assetURL = asset.fileURL else {
                AppLogger.error("CloudKit 记录中没有图片资源: \(imageName)")
                return false
            }
            
            // 3. 复制到本地目录
            let destinationURL = ImageManager.shared.imagesDirectory.appendingPathComponent(imageName)
            let fileManager = FileManager.default
            
            // 如果文件已存在，先删除
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }
            
            try fileManager.copyItem(at: assetURL, to: destinationURL)
            
            // 4. 创建 StoredImage 记录
            if let imageData = try? Data(contentsOf: destinationURL),
               let hash = calculateHash(data: imageData) {
                
                let storedImage = StoredImage(imageHash: hash, fileName: imageName)
                context.insert(storedImage)
                try? context.save()
            }
            
            // 5. 更新同步记录
            let syncDescriptor = FetchDescriptor<ClothingImageSyncRecord>(
                predicate: #Predicate { $0.imageFileName == imageName }
            )
            
            if let syncRecord = try? context.fetch(syncDescriptor).first {
                syncRecord.syncStatus = "synced"
                syncRecord.lastSyncDate = Date()
                syncRecord.cloudRecordID = record.recordID.recordName
                try? context.save()
            }
            
            AppLogger.info("图片已从 CloudKit 下载: \(imageName)")
            return true
            
        } catch {
            AppLogger.error("下载图片失败: \(imageName), 错误: \(error)")
            return false
        }
    }
    
    // MARK: - 批量同步
    
    /// 同步所有待同步的图片
    func syncPendingImages() async {
        guard await isCloudKitAvailable else {
            return
        }
        
        let context = ModelContext(SharedContainer.sharedModelContainer)
        
        let descriptor = FetchDescriptor<ClothingImageSyncRecord>(
            predicate: #Predicate { $0.syncStatus == "pending" || $0.syncStatus == "failed" }
        )
        
        do {
            let pendingRecords = try context.fetch(descriptor)
            
            await MainActor.run {
                self.pendingUploadCount = pendingRecords.count
            }
            
            guard !pendingRecords.isEmpty else { return }
            
            AppLogger.info("开始同步 \(pendingRecords.count) 张待同步图片")
            
            for (index, record) in pendingRecords.enumerated() {
                // 跳过重试次数过多的记录
                if record.retryCount >= 5 {
                    AppLogger.info("跳过重试次数过多的图片: \(record.imageFileName)")
                    continue
                }
                
                let progress = Double(index) / Double(pendingRecords.count)
                await MainActor.run {
                    self.syncStatus = .uploading(imageName: record.imageFileName, progress: progress)
                }
                
                await syncSingleImage(
                    clothingID: record.clothingID,
                    imageFileName: record.imageFileName,
                    context: context
                )
            }
            
            await MainActor.run {
                self.syncStatus = .completed
                self.lastSyncDate = Date()
            }
            
        } catch {
            AppLogger.error("获取待同步记录失败: \(error)")
        }
    }
    
    // MARK: - 冲突解决
    
    /// 解决图片同步冲突
    /// 策略：比较时间戳，保留最新的版本
    func resolveConflict(
        localRecord: ClothingImageSyncRecord,
        cloudRecord: CKRecord
    ) async throws -> Bool {
        guard let cloudDate = cloudRecord["uploadDate"] as? Date else {
            // Cloud 记录没有时间戳，保留本地
            return false
        }
        
        let localDate = localRecord.updatedAt
        
        if cloudDate > localDate {
            // Cloud 版本更新，需要下载
            AppLogger.info("Cloud 版本更新，需要下载: \(localRecord.imageFileName)")
            return true
        } else {
            // 本地版本更新，需要上传
            AppLogger.info("本地版本更新，需要上传: \(localRecord.imageFileName)")
            return false
        }
    }
    
    // MARK: - 清理旧记录
    
    /// 清理孤立的同步记录
    private func cleanupOldSyncRecords() async {
        let context = ModelContext(SharedContainer.sharedModelContainer)
        
        // 获取所有 Clothing
        let clothingDescriptor = FetchDescriptor<Clothing>()
        
        do {
            let allClothings = try context.fetch(clothingDescriptor)
            let validImageNames = Set(allClothings.flatMap { $0.imagePaths })
            
            // 获取所有同步记录
            let syncDescriptor = FetchDescriptor<ClothingImageSyncRecord>()
            let allSyncRecords = try context.fetch(syncDescriptor)
            
            var deletedCount = 0
            for record in allSyncRecords {
                if !validImageNames.contains(record.imageFileName) {
                    context.delete(record)
                    deletedCount += 1
                }
            }
            
            if deletedCount > 0 {
                try context.save()
                AppLogger.info("清理了 \(deletedCount) 条孤立的同步记录")
            }
            
        } catch {
            AppLogger.error("清理同步记录失败: \(error)")
        }
    }
    
    // MARK: - 辅助方法
    
    private func calculateHash(data: Data) -> String? {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// 获取图片的同步状态
    func getSyncStatus(imageFileName: String, context: ModelContext) -> String? {
        let descriptor = FetchDescriptor<ClothingImageSyncRecord>(
            predicate: #Predicate { $0.imageFileName == imageFileName }
        )
        
        do {
            if let record = try context.fetch(descriptor).first {
                return record.syncStatus
            }
        } catch {
            AppLogger.error("查询同步状态失败: \(error)")
        }
        
        return nil
    }
    
    /// 检查图片是否已同步
    func isImageSynced(imageFileName: String, context: ModelContext) -> Bool {
        return getSyncStatus(imageFileName: imageFileName, context: context) == "synced"
    }
    
    /// 删除 CloudKit 中的图片记录
    func deleteCloudImage(imageFileName: String, clothingID: UUID) async {
        guard await isCloudKitAvailable else { return }
        
        do {
            let predicate = NSPredicate(format: "imageName == %@ AND clothingID == %@",
                                       imageFileName, clothingID.uuidString)
            let query = CKQuery(recordType: CKRecordTypes.clothingImage, predicate: predicate)
            
            let (results, _) = try await database.records(matching: query)
            
            for (_, result) in results {
                if case .success(let record) = result {
                    try await database.deleteRecord(withID: record.recordID)
                    AppLogger.info("已删除 CloudKit 图片记录: \(imageFileName)")
                }
            }
        } catch {
            AppLogger.error("删除 CloudKit 图片记录失败: \(error)")
        }
    }
}
