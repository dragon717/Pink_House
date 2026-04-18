//
//  CloudSyncManager.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/28/26.
//

import Foundation
import CloudKit
import SwiftData
import UIKit
import Combine
import CryptoKit
import CoreTelephony

@MainActor
class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()
    
    private let container = CKContainer(identifier: "iCloud.bugod2.ItemManager")
    private let cellularData = CTCellularData()
    
    // MARK: - Network Permission
    
    func checkNetworkPermission() {
        let currentState = cellularData.restrictedState
        print("Network permission state: \(currentState.rawValue)")
        
        // iCloud 元数据同步本身不应被蜂窝权限状态阻塞，尤其是在 Wi-Fi 或状态未知的启动阶段。
        fetchLatestBackupMetadata()
        
        // 监听权限变化（例如用户刚刚点击了允许）
        // Monitor permission changes (e.g. user just tapped Allow)
        cellularData.cellularDataRestrictionDidUpdateNotifier = { [weak self] state in
            guard let self = self else { return }
            
            // 回到主线程处理
            DispatchQueue.main.async {
                if state == .notRestricted {
                    print("Network permission granted via notifier. Fetching backup metadata...")
                    self.fetchLatestBackupMetadata()
                } else {
                    print("Network permission updated to: \(state.rawValue)")
                }
            }
        }
    }
    
    // 使用 Private Database 存储用户数据（符合苹果规范）
    private var database: CKDatabase {
        return container.privateCloudDatabase
    }
    
    @Published var isSyncing = false
    @Published var lastCloudBackupDate: Date?
    @Published var syncError: String?
    
    @Published var hasSuccessfulBackup: Bool {
        didSet {
            UserDefaults.standard.set(hasSuccessfulBackup, forKey: "hasSuccessfulBackup")
        }
    }
    
    // MARK: - iCloud 同步开关
    @Published var isCloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isCloudSyncEnabled, forKey: "isCloudSyncEnabled")
            if isCloudSyncEnabled {
                // 开启同步时立即检查一次
                Task {
                    await checkiCloudAccountStatus()
                }
            }
        }
    }
    
    @Published var iCloudAccountStatus: CKAccountStatus = .couldNotDetermine
    @Published var iCloudAccountError: Error?
    
    // Version 4: Incremental Backup Support
    private let indexRecordType = "BackupIndex_v4"
    private let imageRecordType = "BackupImage"
    
    private var userRecordID: CKRecord.ID?
    
    private init() {
        self.hasSuccessfulBackup = UserDefaults.standard.bool(forKey: "hasSuccessfulBackup")
        self.isCloudSyncEnabled = UserDefaults.standard.bool(forKey: "isCloudSyncEnabled")
        
        // 初始化时检查 iCloud 账户状态
        Task {
            await checkiCloudAccountStatus()
        }
    }
    
    // MARK: - iCloud 账户状态检查
    
    /// 检查 iCloud 账户状态
    func checkiCloudAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            await MainActor.run {
                self.iCloudAccountStatus = status
            }
        } catch {
            await MainActor.run {
                self.iCloudAccountStatus = .couldNotDetermine
                self.iCloudAccountError = error
            }
        }
    }
    
    /// 检查是否可以使用 iCloud 同步
    /// - Returns: (是否可用, 错误信息)
    func canUseCloudSync() async -> (Bool, String?) {
        await checkiCloudAccountStatus()
        
        switch iCloudAccountStatus {
        case .available:
            return (true, nil)
        case .noAccount:
            return (false, "请先登录 Apple ID 并开启 iCloud")
        case .restricted:
            return (false, "iCloud 功能受限，请检查设置")
        case .couldNotDetermine:
            return (false, "无法确定 iCloud 状态，请稍后重试")
        case .temporarilyUnavailable:
            return (false, "iCloud 暂时不可用，请稍后重试")
        @unknown default:
            return (false, "iCloud 状态异常")
        }
    }
    
    /// 尝试开启 iCloud 同步，如果 Apple ID 未登录则返回 false
    func tryEnableCloudSync() async -> Bool {
        let (canSync, _) = await canUseCloudSync()
        if canSync {
            await MainActor.run {
                self.isCloudSyncEnabled = true
            }
            return true
        }
        return false
    }
    
    // MARK: - User Identity
    
    private func fetchUserRecordID() async throws -> CKRecord.ID {
        if let existing = userRecordID {
            return existing
        }
        let id = try await container.userRecordID()
        userRecordID = id
        return id
    }
    
    private func getBackupIndexRecordID() async throws -> CKRecord.ID {
        let userId = try await fetchUserRecordID()
        return CKRecord.ID(recordName: "UserBackupIndex_\(userId.recordName)")
    }
    
    private func getImageRecordID(hash: String) -> CKRecord.ID {
        return CKRecord.ID(recordName: "Image_\(hash)")
    }
    
    // MARK: - Hashing Helper
    
    nonisolated private func calculateFileHash(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Metadata Fetching
    
    func fetchLatestBackupMetadata() {
        Task {
            // 先检查 iCloud 账户状态
            let (canSync, errorMsg) = await canUseCloudSync()
            guard canSync else {
                print("fetchLatestBackupMetadata: iCloud 不可用 - \(errorMsg ?? "未知错误")")
                return
            }
            
            do {
                let recordID = try await getBackupIndexRecordID()
                let operation = CKFetchRecordsOperation(recordIDs: [recordID])
                operation.qualityOfService = .userInitiated
                operation.desiredKeys = ["backupDate", "creationDate"]
                
                operation.perRecordResultBlock = { [weak self] _, result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let record):
                            if let backupDate = record["backupDate"] as? Date {
                                self?.lastCloudBackupDate = backupDate
                            } else {
                                self?.lastCloudBackupDate = record.creationDate
                            }
                        case .failure(let error):
                            if let ckError = error as? CKError, ckError.code == .unknownItem {
                                // Normal for new users
                            } else {
                                print("Metadata fetch failed: \(error)")
                            }
                        }
                    }
                }
                database.add(operation)
            } catch {
                print("Failed to get User Record ID: \(error)")
            }
        }
    }
    
    // MARK: - Incremental Upload
    
    func uploadBackup(modelContainer: ModelContainer) async -> Bool {
        // Force save main context to ensure pending changes are persisted to store
        // so that the new background context created in prepareBackupData can see them.
        try? modelContainer.mainContext.save()
        
        isSyncing = true
        syncError = nil
        
        do {
            // 0. Check Disk Space (Local) - User Requirement: > 500MB
            try checkDiskSpace(minMB: 500)
            
            // 0.1 Check iCloud Account
            let (canSync, errorMsg) = await canUseCloudSync()
            guard canSync else {
                throw NSError(domain: "CloudSync", code: 401, userInfo: [NSLocalizedDescriptionKey: errorMsg ?? "iCloud 账户不可用"])
            }
            
            // 1. Prepare Data
            print("CloudSync: Preparing backup data...")
            let backupData = try await BackupService.shared.prepareBackupData(container: modelContainer)
            
            // 2. Identify Images to Upload
            // Map: [Hash: FileURL]
            var imagesToUpload: [String: URL] = [:]
            var allImageHashes: [String] = []
            
            // Process Stored Images (Already hashed)
            for imgDTO in backupData.manifest.storedImages {
                if let url = backupData.imageFiles[imgDTO.fileName] {
                    imagesToUpload[imgDTO.imageHash] = url
                    allImageHashes.append(imgDTO.imageHash)
                }
            }
            
            // Process Other Files (Need hashing)
            // Theme files, Widget bg, etc.
            let specialFiles = backupData.imageFiles.keys.filter { key in
                !backupData.manifest.storedImages.contains { $0.fileName == key }
            }
            
            for fileName in specialFiles {
                if let url = backupData.imageFiles[fileName],
                   let hash = calculateFileHash(url: url) {
                    imagesToUpload[hash] = url
                    allImageHashes.append(hash)
                }
            }
            
            print("CloudSync: Total images referenced: \(allImageHashes.count)")
            
            // 3. Check which images already exist in Cloud
            // We use CKFetchRecordsOperation with keys: [] to check existence efficiently
            let allRecordIDs = Set(allImageHashes).map { getImageRecordID(hash: $0) }
            
            // Only check if we have images
            var missingRecordIDs: [CKRecord.ID] = []
            
            if !allRecordIDs.isEmpty {
                print("CloudSync: Checking existence of \(allRecordIDs.count) images...")
                // Split into batches of 400 (CloudKit limit)
                let batches = stride(from: 0, to: allRecordIDs.count, by: 400).map {
                    Array(allRecordIDs[$0..<min($0 + 400, allRecordIDs.count)])
                }
                
                for batch in batches {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        let operation = CKFetchRecordsOperation(recordIDs: batch)
                        operation.desiredKeys = [] // We only need existence
                        operation.qualityOfService = .userInitiated
                        
                        operation.fetchRecordsResultBlock = { result in
                            switch result {
                            case .success:
                                continuation.resume()
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        }
                        
                        operation.perRecordResultBlock = { recordID, result in
                            switch result {
                            case .success:
                                break // Exists
                            case .failure(let error):
                                if let ckError = error as? CKError, ckError.code == .unknownItem {
                                    missingRecordIDs.append(recordID)
                                }
                            }
                        }
                        
                        self.database.add(operation)
                    }
                }
            }
            
            print("CloudSync: Found \(missingRecordIDs.count) missing images to upload.")
            
            // 4. Upload Missing Images
            if !missingRecordIDs.isEmpty {
                var recordsToSave: [CKRecord] = []
                for recordID in missingRecordIDs {
                    // Extract Hash from RecordName "Image_{HASH}"
                    let hash = String(recordID.recordName.dropFirst(6))
                    if let url = imagesToUpload[hash] {
                        let record = CKRecord(recordType: imageRecordType, recordID: recordID)
                        record["imageAsset"] = CKAsset(fileURL: url)
                        record["hash"] = hash
                        recordsToSave.append(record)
                    }
                }
                
                // Batch Upload
                // Split into batches
                let saveBatches = stride(from: 0, to: recordsToSave.count, by: 200).map {
                    Array(recordsToSave[$0..<min($0 + 200, recordsToSave.count)])
                }
                
                for batch in saveBatches {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        let op = CKModifyRecordsOperation(recordsToSave: batch, recordIDsToDelete: nil)
                        op.savePolicy = .changedKeys
                        op.isAtomic = false // Allow partial success if some exist
                        op.qualityOfService = .userInitiated
                        
                        op.modifyRecordsResultBlock = { result in
                            switch result {
                            case .success:
                                continuation.resume()
                            case .failure(let error):
                                // If partial failure, we might still proceed.
                                // For now, treat as error.
                                continuation.resume(throwing: error)
                            }
                        }
                        self.database.add(op)
                    }
                }
            }
            
            // 5. Upload Manifest (Index Record)
            let indexRecordID = try await getBackupIndexRecordID()
            
            let indexRecord: CKRecord
            do {
                indexRecord = try await database.record(for: indexRecordID)
            } catch {
                indexRecord = CKRecord(recordType: indexRecordType, recordID: indexRecordID)
            }
            
            // Serialize Manifest to File
            let jsonEncoder = JSONEncoder()
            jsonEncoder.dateEncodingStrategy = .iso8601
            let manifestData = try jsonEncoder.encode(backupData.manifest)
            
            let tempDir = FileManager.default.temporaryDirectory
            let manifestURL = tempDir.appendingPathComponent("manifest.json")
            try manifestData.write(to: manifestURL)
            
            indexRecord["manifest"] = CKAsset(fileURL: manifestURL)
            indexRecord["deviceName"] = UIDevice.current.name
            indexRecord["version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            indexRecord["backupDate"] = Date()
            
            // Save Index
            try await database.save(indexRecord)
            
            try? FileManager.default.removeItem(at: manifestURL)
            
            self.lastCloudBackupDate = Date()
            self.hasSuccessfulBackup = true
            print("Cloud Backup Success!")
            isSyncing = false
            return true
            
        } catch {
            self.syncError = "备份失败: \(error.localizedDescription)"
            print("Cloud Backup Failed: \(error)")
            isSyncing = false
            return false
        }
    }
    
    // MARK: - Incremental Restore
    
    func restoreFromCloud(context: ModelContext) async -> Bool {
        return await restoreFromCloudInternal(context: context, silent: false)
    }
    
    private func restoreFromCloudInternal(context: ModelContext, silent: Bool) async -> Bool {
        if !silent { isSyncing = true }
        syncError = nil
        
        do {
            // Check iCloud Account
            let (canSync, errorMsg) = await canUseCloudSync()
            guard canSync else {
                throw NSError(domain: "CloudSync", code: 401, userInfo: [NSLocalizedDescriptionKey: errorMsg ?? "iCloud 账户不可用，请检查 Apple ID 登录状态"])
            }
            
            // Check Disk Space
            if !silent {
                try checkDiskSpace(minMB: 500)
            }
            
            print("CloudSync: Fetching Backup Index...")
            let indexRecordID = try await getBackupIndexRecordID()
            let indexRecord = try await database.record(for: indexRecordID)
            
            guard let manifestAsset = indexRecord["manifest"] as? CKAsset,
                  let manifestURL = manifestAsset.fileURL else {
                throw NSError(domain: "CloudSync", code: 404, userInfo: [NSLocalizedDescriptionKey: "Manifest missing"])
            }
            
            let manifestData = try Data(contentsOf: manifestURL)
            let jsonDecoder = JSONDecoder()
            jsonDecoder.dateDecodingStrategy = .iso8601
            let manifest = try jsonDecoder.decode(BackupManifest.self, from: manifestData)
            
            // Collect needed images
            var neededHashes: Set<String> = []
            // Stored Images
            for img in manifest.storedImages {
                neededHashes.insert(img.imageHash)
            }
            // External Files
            if let extHashes = manifest.externalFileHashes {
                for (_, hash) in extHashes {
                    neededHashes.insert(hash)
                }
            }
            
            // 2. Identify Missing Local Images
            let imagesDir = await ImageManager.shared.imagesDirectory
            let fileManager = FileManager.default
            let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            
            // Map [FileName: LocalURL]
            // For existing files, we point to them. For missing, we download to temp.
            var imageFileMap: [String: URL] = [:]
            var hashesToDownload: Set<String> = []
            
            // A. Stored Images
            for img in manifest.storedImages {
                let localURL = imagesDir.appendingPathComponent(img.fileName)
                if fileManager.fileExists(atPath: localURL.path) {
                    imageFileMap[img.fileName] = localURL
                } else {
                    hashesToDownload.insert(img.imageHash)
                }
            }
            
            // B. External Files (Theme, Wealth, Widget)
            if let extHashes = manifest.externalFileHashes {
                for (fileName, hash) in extHashes {
                    // Determine where this file lives locally to check existence
                    var localURL: URL
                    if fileName == "widget_background.jpg" {
                        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: WidgetDataManager.appGroupIdentifier) {
                            localURL = containerURL.appendingPathComponent(fileName)
                        } else {
                            continue // Skip if no app group
                        }
                    } else {
                        // Theme/Wealth files are in Documents
                        localURL = documentsDir.appendingPathComponent(fileName)
                    }
                    
                    if fileManager.fileExists(atPath: localURL.path) {
                         imageFileMap[fileName] = localURL
                    } else {
                         hashesToDownload.insert(hash)
                    }
                }
            }
            
            if !hashesToDownload.isEmpty {
                print("CloudSync: Downloading \(hashesToDownload.count) missing images...")
                
                // Batch Download
                let hashesArray = Array(hashesToDownload)
                let batches = stride(from: 0, to: hashesArray.count, by: 200).map {
                    Array(hashesArray[$0..<min($0 + 200, hashesArray.count)])
                }
                
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("restore_\(UUID().uuidString)")
                try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                for batch in batches {
                    let recordIDs = batch.map { getImageRecordID(hash: $0) }
                    
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        let op = CKFetchRecordsOperation(recordIDs: recordIDs)
                        op.qualityOfService = .userInitiated
                        
                        op.perRecordResultBlock = { recordID, result in
                            switch result {
                            case .success(let record):
                                if let asset = record["imageAsset"] as? CKAsset,
                                   let fileURL = asset.fileURL {
                                    let hash = String(recordID.recordName.dropFirst(6))
                                    
                                    // 1. Check StoredImages
                                    let matchingStored = manifest.storedImages.filter { $0.imageHash == hash }
                                    for match in matchingStored {
                                        let destURL = tempDir.appendingPathComponent(match.fileName)
                                        try? fileManager.copyItem(at: fileURL, to: destURL)
                                        imageFileMap[match.fileName] = destURL
                                    }
                                    
                                    // 2. Check External Files
                                    if let extHashes = manifest.externalFileHashes {
                                        let matchingExt = extHashes.filter { $0.value == hash }
                                        for (fileName, _) in matchingExt {
                                            let destURL = tempDir.appendingPathComponent(fileName)
                                            try? fileManager.copyItem(at: fileURL, to: destURL)
                                            imageFileMap[fileName] = destURL
                                        }
                                    }
                                }
                            case .failure(let error):
                                print("Failed to download image \(recordID): \(error)")
                            }
                        }
                        
                        op.fetchRecordsResultBlock = { result in
                            switch result {
                            case .success:
                                continuation.resume()
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        }
                        
                        self.database.add(op)
                    }
                }
            }
            
            // 3. Restore
            print("CloudSync: Applying restore...")
            // Ensure we are on Main Actor for context operations
            try await MainActor.run {
                try BackupService.shared.restoreFromManifest(manifest: manifest, imageFiles: imageFileMap, context: context)
            }
            
            self.hasSuccessfulBackup = true
            if !silent { isSyncing = false }
            return true
            
        } catch {
            if !silent {
                // 处理特定错误，显示友好提示
                let friendlyError = self.friendlyErrorMessage(for: error)
                self.syncError = friendlyError
                isSyncing = false
            }
            print("Cloud Restore Failed: \(error)")
            return false
        }
    }
    
    /// 将技术错误转换为用户友好的提示
    private func friendlyErrorMessage(for error: Error) -> String {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .unknownItem:
                return "云端没有备份记录。请先备份数据到云端。"
            case .networkFailure, .notAuthenticated:
                return "网络连接失败，请检查网络后重试。"
            case .quotaExceeded:
                return "iCloud 空间不足，请清理空间后重试。"
            case .userDeletedZone:
                return "备份数据已被删除，无法恢复。"
            default:
                break
            }
        }
        
        // 检查错误描述中的关键词
        let errorDesc = error.localizedDescription.lowercased()
        if errorDesc.contains("record not found") || errorDesc.contains("unknown item") {
            return "云端没有备份记录。请先备份数据到云端。"
        }
        
        return "恢复失败: \(error.localizedDescription)"
    }

    // MARK: - Manual Restore Only
    
    /// 检查云端是否有备份（供 UI 使用，显示恢复提示）
    /// 返回：是否有可恢复的云端备份
    func checkCloudBackupAvailable() async -> Bool {
        return await checkCloudBackupExists(timeout: 5.0)
    }
    
    /// 快速检查云端是否有备份（带超时）
    private func checkCloudBackupExists(timeout: TimeInterval) async -> Bool {
        // 先检查 iCloud 账户状态
        let (canSync, _) = await canUseCloudSync()
        guard canSync else {
            return false
        }
        
        return await withTimeout(seconds: timeout) {
            do {
                let indexRecordID = try await self.getBackupIndexRecordID()
                _ = try await self.database.record(for: indexRecordID)
                return true
            } catch {
                return false
            }
        } ?? false
    }
    
    /// 超时包装器
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async -> T? {
        try? await withThrowingTaskGroup(of: T.self) { group in
            // 添加主任务
            group.addTask {
                try await operation()
            }
            
            // 添加超时任务
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            // 返回先完成的任务结果
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    struct TimeoutError: Error {}
    
    /// 用户手动触发恢复（不再自动调用）
    func restoreFromCloudManual(context: ModelContext) async -> Bool {
        print("ManualRestore: User initiated cloud restore...")
        return await restoreFromCloudInternal(context: context, silent: false)
    }
    
    // MARK: - Helper
    
    private func checkDiskSpace(minMB: Int) throws {
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                let minBytes = Int64(minMB) * 1024 * 1024
                if capacity < minBytes {
                    throw NSError(domain: "CloudSync", code: 507, userInfo: [NSLocalizedDescriptionKey: "设备剩余空间不足。请至少预留 \(minMB)MB 空间以进行备份/恢复。"])
                }
            }
        } catch {
            if (error as NSError).domain == "CloudSync" {
                throw error
            }
            // Ignore other errors (e.g. unable to query)
            print("CloudSync: Warning - Failed to check disk space: \(error)")
        }
    }
}
