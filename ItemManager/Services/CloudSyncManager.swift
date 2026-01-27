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

@MainActor
class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()
    
    private let container = CKContainer(identifier: "iCloud.bugod2.ItemManager")
    private var database: CKDatabase {
        return container.privateCloudDatabase
    }
    
    @Published var isSyncing = false
    @Published var lastCloudBackupDate: Date?
    @Published var syncError: String?
    
    private let recordType = "BackupArchive"
    
    private init() {}
    
    // MARK: - Metadata Fetching
    
    func fetchLatestBackupMetadata() {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 1
        operation.qualityOfService = .userInitiated
        
        operation.recordMatchedBlock = { [weak self] _, result in
            DispatchQueue.main.async {
                switch result {
                case .success(let record):
                    self?.lastCloudBackupDate = record.creationDate
                case .failure(let error):
                    // Ignore "Unknown Item" errors which mean no records found yet
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        return
                    }
                    print("Error fetching backup metadata: \(error)")
                }
            }
        }
        
        operation.queryResultBlock = { [weak self] result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                     print("Query failed: \(error)")
                     // 如果是权限错误，提示用户
                     if let ckError = error as? CKError, ckError.code == .permissionFailure {
                         self?.syncError = "请在系统设置中允许使用 iCloud"
                     }
                }
            }
        }
        
        database.add(operation)
    }
    
    // MARK: - Upload (Backup)
    
    func uploadBackup(modelContainer: ModelContainer) async {
        isSyncing = true
        syncError = nil
        
        do {
            // 0. Check iCloud Availability
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                throw NSError(domain: "CloudSync", code: 401, userInfo: [NSLocalizedDescriptionKey: "iCloud 账户不可用。请在设置中登录并开启 iCloud Drive。"])
            }
            
            // 1. Generate Local Backup
            print("Starting Cloud Backup: Generating local archive...")
            let backupURL = try await BackupService.shared.exportBackup(container: modelContainer)
            
            // Verify file exists and has size
            let attr = try FileManager.default.attributesOfItem(atPath: backupURL.path)
            let fileSize = attr[.size] as? Int64 ?? 0
            print("Backup file generated at: \(backupURL.path), size: \(fileSize) bytes")
            
            guard fileSize > 0 else {
                throw NSError(domain: "CloudSync", code: 500, userInfo: [NSLocalizedDescriptionKey: "生成的备份文件为空"])
            }

            // 2. Prepare CKRecord
            let record = CKRecord(recordType: recordType)
            let asset = CKAsset(fileURL: backupURL)
            record["archiveAsset"] = asset
            record["deviceName"] = UIDevice.current.name
            record["version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            
            // 3. Upload
            print("Starting Cloud Backup: Uploading to CloudKit...")
            
            // Use modifyRecordsOperation for better error handling and atomic saves
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let modifyOp = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
                modifyOp.savePolicy = .allKeys // Overwrite if exists (though we use new ID)
                modifyOp.qualityOfService = .userInitiated
                
                modifyOp.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        // Extract detailed error info
                        if let ckError = error as? CKError {
                            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                                for (_, partialError) in partialErrors {
                                    print("Partial Error: \(partialError)")
                                }
                            }
                            // Handle specific error codes
                            if ckError.code == .serverRejectedRequest {
                                print("Server Rejected Request: \(ckError.userInfo)")
                            }
                        }
                        continuation.resume(throwing: error)
                    }
                }
                
                self.database.add(modifyOp)
            }
            
            // 4. Cleanup & Update UI
            try? FileManager.default.removeItem(at: backupURL)
            
            self.lastCloudBackupDate = Date()
            print("Cloud Backup Success!")
            
        } catch {
            self.syncError = "备份失败: \(error.localizedDescription)"
            if let ckError = error as? CKError {
                 if ckError.code == .serverRejectedRequest {
                     self.syncError = "服务器拒绝了请求。请检查 iCloud 设置或网络。(Code 15)"
                 } else if ckError.code == .quotaExceeded {
                     self.syncError = "iCloud 存储空间不足"
                 }
            }
            print("Cloud Backup Failed: \(error)")
        }
        
        isSyncing = false
    }
    
    // MARK: - Download (Restore)
    
    func restoreFromCloud(context: ModelContext) async {
        isSyncing = true
        syncError = nil
        
        do {
            // 1. Find latest backup
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let (matchResults, _) = try await database.records(matching: query, inZoneWith: nil, desiredKeys: ["archiveAsset"], resultsLimit: 1)
            
            guard let match = matchResults.first,
                  case .success(let record) = match.1,
                  let asset = record["archiveAsset"] as? CKAsset,
                  let fileURL = asset.fileURL else {
                throw NSError(domain: "CloudSync", code: 404, userInfo: [NSLocalizedDescriptionKey: "No cloud backup found."])
            }
            
            print("Restoring from Cloud: Found backup, downloading...")
            
            // 2. Import Backup
            // CKAsset fileURL is usually accessible, but sometimes we might need to copy it if it's temporary
            // BackupService.importBackup expects a valid file URL.
            
            try BackupService.shared.importBackup(from: fileURL, context: context)
            
            print("Cloud Restore Success!")
            
        } catch {
            self.syncError = error.localizedDescription
            print("Cloud Restore Failed: \(error)")
        }
        
        isSyncing = false
    }
}
