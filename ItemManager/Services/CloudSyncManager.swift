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
    
    // MARK: - Database Configuration
    // 切换策略：由于 Private Database 持续出现 Code 15 (Server Rejected Request) 错误，
    // 这通常意味着开发环境下的 Schema 自动创建失败，或者容器权限未正确传播。
    // 为了确保功能可用，我们尝试使用 Public Database。
    // 注意：Public Database 所有用户可读，但在 CloudKit Dashboard 配置 Security Roles 之前，
    // 默认只有创建者可以修改自己的记录。
    // 为了数据隐私，建议后续确保存储的数据是加密的，或者解决 Private DB 的问题。
    // 这里我们使用基于用户 ID 的记录 ID 来在 Public DB 中模拟“私有”存储。
    
    private var database: CKDatabase {
        return container.publicCloudDatabase
    }
    
    @Published var isSyncing = false
    @Published var lastCloudBackupDate: Date?
    @Published var syncError: String?
    
    private let recordType = "BackupArchive_v3" // 再次升级版本号以隔离数据
    
    // 在 Public DB 中，我们不能使用 Custom Zone（Public DB 只有一个 Default Zone），
    // 所以我们必须依靠 Record Name 来区分用户。
    // 我们将使用用户的 iCloud User Record ID 作为 Record Name 的一部分。
    private var userRecordID: CKRecord.ID?
    
    private init() {}
    
    // MARK: - User Identity
    
    private func fetchUserRecordID() async throws -> CKRecord.ID {
        if let existing = userRecordID {
            return existing
        }
        let id = try await container.userRecordID()
        userRecordID = id
        return id
    }
    
    // 生成基于用户的唯一记录 ID
    private func getBackupRecordID() async throws -> CKRecord.ID {
        let userId = try await fetchUserRecordID()
        // 记录 ID 格式: "UserBackup_{UserRecordName}"
        // 这样每个用户只能访问/修改包含自己 ID 的那个记录（配合 CloudKit 权限）
        return CKRecord.ID(recordName: "UserBackup_\(userId.recordName)")
    }
    
    // MARK: - Metadata Fetching
    
    func fetchLatestBackupMetadata() {
        Task {
            do {
                let recordID = try await getBackupRecordID()
                
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
                            print("Metadata fetch failed for record \(recordID.recordName): \(error)")
                            // 可能是记录不存在，属于正常情况
                        }
                    }
                }
                
                database.add(operation)
            } catch {
                print("Failed to get User Record ID for metadata fetch: \(error)")
            }
        }
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
            
            // 1. Get Record ID based on User
            let recordID = try await getBackupRecordID()
            print("CloudSync: Using Public DB Record ID: \(recordID.recordName)")
            
            // 2. Generate Local Backup
            print("Starting Cloud Backup: Generating local archive...")
            let backupURL = try await BackupService.shared.exportBackup(container: modelContainer)
            
            // Verify file exists and has size
            let attr = try FileManager.default.attributesOfItem(atPath: backupURL.path)
            let fileSize = attr[.size] as? Int64 ?? 0
            print("Backup file generated at: \(backupURL.path), size: \(fileSize) bytes")
            
            guard fileSize > 0 else {
                throw NSError(domain: "CloudSync", code: 500, userInfo: [NSLocalizedDescriptionKey: "生成的备份文件为空"])
            }

            // 3. Fetch or Create Record
            let recordToSave: CKRecord
            do {
                print("Fetching existing record for update...")
                let existingRecord = try await database.record(for: recordID)
                recordToSave = existingRecord
                print("Found existing record, updating.")
            } catch {
                print("No existing record found, creating new one.")
                recordToSave = CKRecord(recordType: recordType, recordID: recordID)
            }
            
            // 4. Update Record Fields
            let asset = CKAsset(fileURL: backupURL)
            recordToSave["archiveAsset"] = asset
            recordToSave["deviceName"] = UIDevice.current.name
            recordToSave["version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            recordToSave["backupDate"] = Date()
            
            // Set public permission: Only Creator can write, Everyone can read (default for Public DB)
            // Since the Record ID is tied to User ID, it's effectively private-ish,
            // but for real privacy, encryption is recommended.
            
            // 5. Upload
            print("Starting Cloud Backup: Uploading to CloudKit (Public DB)...")
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let modifyOp = CKModifyRecordsOperation(recordsToSave: [recordToSave], recordIDsToDelete: nil)
                modifyOp.savePolicy = .changedKeys
                modifyOp.qualityOfService = .userInitiated
                modifyOp.isAtomic = true
                
                modifyOp.perRecordProgressBlock = { record, progress in
                    // 仅在进度有显著变化时打印，避免刷屏 (例如每 10%)
                    let percentage = Int(progress * 100)
                    if percentage % 10 == 0 {
                        print("CloudSync: Uploading \(record.recordID.recordName)... \(percentage)%")
                    }
                }
                
                modifyOp.perRecordSaveBlock = { recordID, result in
                    switch result {
                    case .success:
                        print("CloudSync: Record \(recordID.recordName) saved successfully.")
                    case .failure(let error):
                        print("CloudSync: Record \(recordID.recordName) save failed: \(error)")
                    }
                }
                
                modifyOp.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                
                self.database.add(modifyOp)
            }
            
            // 6. Cleanup & Update UI
            try? FileManager.default.removeItem(at: backupURL)
            
            self.lastCloudBackupDate = Date()
            print("Cloud Backup Success!")
            
            // 7. Verify
            print("Verifying backup integrity...")
            do {
                let verifyRecord = try await database.record(for: recordID)
                if let verifyDate = verifyRecord["backupDate"] as? Date {
                     print("Verification Success: Record found with date \(verifyDate)")
                }
            } catch {
                print("Verification Failed: \(error)")
                throw error
            }
            
        } catch {
            self.syncError = "备份失败: \(error.localizedDescription)"
            if let ckError = error as? CKError {
                 if ckError.code == .serverRejectedRequest {
                     self.syncError = "服务器拒绝请求 (Code 15)。请检查 iCloud 容器权限配置。"
                 }
            }
            print("Cloud Backup Failed: \(error)")
        }
        
        isSyncing = false
    }
    
    // MARK: - Download (Restore)
    
    func restoreFromCloud(context: ModelContext) async -> Bool {
        isSyncing = true
        syncError = nil
        
        do {
            print("Restoring from Cloud: Fetching backup record...")
            let recordID = try await getBackupRecordID()
            
            // 1. Fetch Record
            let record = try await database.record(for: recordID)
            print("Found backup record: \(record.recordID.recordName)")
            
            // 2. Validate Asset
            guard let asset = record["archiveAsset"] as? CKAsset else {
                throw NSError(domain: "CloudSync", code: 404, userInfo: [NSLocalizedDescriptionKey: "备份记录损坏：缺失数据文件"])
            }
            
            guard let fileURL = asset.fileURL else {
                throw NSError(domain: "CloudSync", code: 404, userInfo: [NSLocalizedDescriptionKey: "备份文件下载失败 (URL为空)"])
            }
            
            print("Restoring from Cloud: Found backup, downloading from \(fileURL.path)...")
            
            // 3. Import
            try BackupService.shared.importBackup(from: fileURL, context: context)
            
            print("Cloud Restore Success!")
            isSyncing = false
            return true
            
        } catch {
            self.syncError = error.localizedDescription
            print("Cloud Restore Failed: \(error)")
            isSyncing = false
            return false
        }
    }
}
