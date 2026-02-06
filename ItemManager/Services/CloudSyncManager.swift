//
//  CloudSyncManager.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/28/26.
//

import Foundation
import CloudKit
import SwiftData
import UIKit
import Combine
import CryptoKit

@MainActor
class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()
    
    private let container = CKContainer(identifier: "iCloud.bugod2.ItemManager")
    
    // 使用 Public Database 模拟私有存储 (规避 Private DB 权限问题)
    private var database: CKDatabase {
        return container.publicCloudDatabase
    }
    
    @Published var isSyncing = false
    @Published var lastCloudBackupDate: Date?
    @Published var syncError: String?
    
    @Published var hasSuccessfulBackup: Bool {
        didSet {
            UserDefaults.standard.set(hasSuccessfulBackup, forKey: "hasSuccessfulBackup")
        }
    }
    
    // Version 4: Incremental Backup Support
    private let indexRecordType = "BackupIndex_v4"
    private let imageRecordType = "BackupImage"
    
    private var userRecordID: CKRecord.ID?
    
    private init() {
        self.hasSuccessfulBackup = UserDefaults.standard.bool(forKey: "hasSuccessfulBackup")
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
    
    func uploadBackup(modelContainer: ModelContainer) async {
        // Force save main context to ensure pending changes are persisted to store
        // so that the new background context created in prepareBackupData can see them.
        try? modelContainer.mainContext.save()
        
        isSyncing = true
        syncError = nil
        
        do {
            // 0. Check iCloud
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                throw NSError(domain: "CloudSync", code: 401, userInfo: [NSLocalizedDescriptionKey: "iCloud 账户不可用。"])
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
            
        } catch {
            self.syncError = "备份失败: \(error.localizedDescription)"
            print("Cloud Backup Failed: \(error)")
        }
        
        isSyncing = false
    }
    
    // MARK: - Incremental Restore
    
    func restoreFromCloud(context: ModelContext) async -> Bool {
        return await restoreFromCloudInternal(context: context, silent: false)
    }
    
    private func restoreFromCloudInternal(context: ModelContext, silent: Bool) async -> Bool {
        if !silent { isSyncing = true }
        syncError = nil
        
        do {
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
                self.syncError = error.localizedDescription
                isSyncing = false
            }
            print("Cloud Restore Failed: \(error)")
            return false
        }
    }
    
    // MARK: - Auto Sync & Silent Restore
    
    func checkAndSilentRestore(container: ModelContainer) async {
        // Condition: Empty Database (No Clothings)
        let context = ModelContext(container)
        let count = try? context.fetchCount(FetchDescriptor<Clothing>())
        
        if count == 0 {
            print("SilentRestore: Empty database detected. Checking for cloud backup...")
            let success = await restoreFromCloudInternal(context: context, silent: true)
            if success {
                print("SilentRestore: Data restored successfully.")
            }
        }
    }
}
