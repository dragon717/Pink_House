import Foundation
import CloudKit
import SwiftData
import Combine

// MARK: - 公告已读状态服务
// 使用 CloudKit Private Database 同步已读状态到 iCloud
// 这样用户换设备或重装应用后，已读状态不会丢失

@MainActor
class NoticeReadStatusService: ObservableObject {
    static let shared = NoticeReadStatusService()
    
    private let container = CKContainer(identifier: "iCloud.bugod2.ItemManager")
    private var database: CKDatabase {
        return container.privateCloudDatabase
    }
    
    // 本地缓存（内存）
    private var localReadStatus: Set<String> = []
    private var localResetTime: Date?
    
    // 同步状态
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    
    // UserDefaults 作为本地备用存储
    private let shownNoticeIDsKey = "shownNoticeIDs"
    private let lastResetTimeKey = "noticeLastResetTime"
    private let lastSyncTimeKey = "noticeReadStatusLastSync"
    
    private init() {
        // 从 UserDefaults 加载本地数据
        loadFromUserDefaults()
    }
    
    // MARK: - 从 UserDefaults 加载（备用）
    private func loadFromUserDefaults() {
        if let ids = UserDefaults.standard.stringArray(forKey: shownNoticeIDsKey) {
            localReadStatus = Set(ids)
        }
        localResetTime = UserDefaults.standard.object(forKey: lastResetTimeKey) as? Date
    }
    
    private func saveToUserDefaults() {
        UserDefaults.standard.set(Array(localReadStatus), forKey: shownNoticeIDsKey)
        UserDefaults.standard.set(localResetTime, forKey: lastResetTimeKey)
    }
    
    // MARK: - 检查公告是否已读
    func hasReadNotice(_ notice: Notice) -> Bool {
        // 如果重置过，只检查重置时间之后的记录
        if let resetTime = localResetTime {
            if max(notice.createdAt, notice.updatedAt) > resetTime {
                return false
            }
        }

        if localReadStatus.contains(notice.readTrackingKey) {
            return true
        }

        if notice.shouldUseLegacyReadFallback,
           notice.legacyReadTrackingKeys.contains(where: { localReadStatus.contains($0) }) {
            return true
        }

        return false
    }
    
    // MARK: - 标记公告为已读
    func markAsRead(_ notice: Notice) {
        var changed = false

        let keys = [notice.readTrackingKey] + notice.legacyReadTrackingKeys
        for key in keys where !localReadStatus.contains(key) {
            localReadStatus.insert(key)
            changed = true
        }

        if changed {
            saveToUserDefaults()
            
            // 同步到 CloudKit
            Task {
                await syncReadStatusToCloud(notice: notice)
            }
        }
    }
    
    // MARK: - 重置已读历史
    func resetReadHistory() {
        localReadStatus.removeAll()
        localResetTime = Date()
        saveToUserDefaults()
        
        // 同步重置操作到云端
        Task {
            await syncResetToCloud()
        }
    }
    
    // MARK: - 获取上次重置时间
    var lastResetTime: Date? {
        return localResetTime
    }
    
    // MARK: - 同步已读状态到 CloudKit
    private func syncReadStatusToCloud(notice: Notice) async {
        guard await checkAccountStatus() else { return }
        
        do {
            let record = CKRecord(recordType: "NoticeReadStatus")
            record["readKey"] = notice.readTrackingKey
            record["noticeID"] = notice.id.uuidString
            record["recordName"] = notice.recordName
            record["version"] = notice.version
            record["updatedAt"] = notice.updatedAt
            record["readAt"] = Date()
            record["title"] = notice.title
            
            try await database.save(record)
            print("✅ 已读状态同步到云端: \(notice.title)")
        } catch {
            print("⚠️ 同步已读状态失败: \(error)")
        }
    }
    
    // MARK: - 同步重置操作到云端
    private func syncResetToCloud() async {
        guard await checkAccountStatus() else { return }
        
        do {
            // 删除所有已读状态记录
            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: "NoticeReadStatus", predicate: predicate)
            
            let (results, _) = try await database.records(matching: query, inZoneWith: nil)
            
            for (_, result) in results {
                if case .success(let record) = result {
                    try await database.deleteRecord(withID: record.recordID)
                }
            }
            
            // 创建重置标记记录
            let resetRecord = CKRecord(recordType: "NoticeReadStatusReset")
            resetRecord["resetAt"] = Date()
            try await database.save(resetRecord)
            
            print("✅ 重置操作同步到云端")
        } catch {
            print("⚠️ 同步重置操作失败: \(error)")
        }
    }
    
    // MARK: - 从 CloudKit 拉取已读状态
    func syncFromCloud() async {
        guard await checkAccountStatus() else { 
            print("📢 iCloud 账户不可用，使用本地数据")
            return 
        }
        
        isSyncing = true
        defer { 
            isSyncing = false
            lastSyncDate = Date()
            UserDefaults.standard.set(Date(), forKey: lastSyncTimeKey)
        }
        
        do {
            // 1. 检查是否有重置记录
            let resetPredicate = NSPredicate(value: true)
            let resetQuery = CKQuery(recordType: "NoticeReadStatusReset", predicate: resetPredicate)
            resetQuery.sortDescriptors = [NSSortDescriptor(key: "resetAt", ascending: false)]
            
            let (resetResults, _) = try await database.records(matching: resetQuery, inZoneWith: nil)
            var cloudResetTime: Date?
            
            for (_, result) in resetResults {
                if case .success(let record) = result,
                   let resetAt = record["resetAt"] as? Date {
                    cloudResetTime = resetAt
                    break // 只取最新的重置时间
                }
            }
            
            // 2. 获取云端已读状态
            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: "NoticeReadStatus", predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "readAt", ascending: false)]
            
            let (results, _) = try await database.records(matching: query, inZoneWith: nil)
            
            var cloudReadStatus: Set<String> = []
            for (_, result) in results {
                if case .success(let record) = result {
                    if let readKey = record["readKey"] as? String {
                        cloudReadStatus.insert(readKey)
                    }
                    if let noticeID = record["noticeID"] as? String {
                        cloudReadStatus.insert(noticeID)
                    }
                    if let recordName = record["recordName"] as? String {
                        cloudReadStatus.insert(recordName)
                    }
                }
            }
            
            // 3. 合并本地和云端数据
            // 以最新的重置时间为准
            let localReset = localResetTime?.timeIntervalSince1970 ?? 0
            let cloudReset = cloudResetTime?.timeIntervalSince1970 ?? 0
            
            if cloudReset > localReset {
                // 云端重置时间更新，使用云端数据
                localResetTime = cloudResetTime
                localReadStatus = cloudReadStatus
                print("📢 使用云端重置时间和已读状态")
            } else if cloudReset == localReset && cloudReset > 0 {
                // 重置时间相同，合并数据
                localReadStatus.formUnion(cloudReadStatus)
                print("📢 合并本地和云端已读状态")
            } else if localReset == 0 && cloudReset == 0 {
                // 都没有重置过，合并数据
                localReadStatus.formUnion(cloudReadStatus)
                print("📢 合并本地和云端已读状态（无重置记录）")
            }
            // 如果本地重置时间更新，保留本地数据
            
            saveToUserDefaults()
            print("✅ 已读状态同步完成，共 \(localReadStatus.count) 条")
            
        } catch {
            print("⚠️ 从云端同步已读状态失败: \(error)")
        }
    }
    
    // MARK: - 检查 iCloud 账户状态
    private func checkAccountStatus() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }
}
