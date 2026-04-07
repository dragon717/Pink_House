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

    private final class RecordPageCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [CKRecord] = []

        func append(_ record: CKRecord) {
            lock.lock()
            storage.append(record)
            lock.unlock()
        }

        var records: [CKRecord] {
            lock.lock()
            let snapshot = storage
            lock.unlock()
            return snapshot
        }
    }

    enum UserState: String, Codable {
        case unseen
        case read
        case acknowledged
        case dismissed
    }

    struct StateSnapshot: Codable {
        var state: UserState = .unseen
        var readAt: Date? = nil
        var acknowledgedAt: Date? = nil
        var dismissedAt: Date? = nil
        var presentationCount: Int = 0
        var lastPresentedAt: Date? = nil
    }
    
    private let container = CKContainer(identifier: "iCloud.bugod2.ItemManager")
    private var database: CKDatabase {
        return container.privateCloudDatabase
    }
    
    // 本地缓存（内存）
    private var localReadStatus: Set<String> = []
    private var localStates: [String: StateSnapshot] = [:]
    private var localResetTime: Date?
    
    // 同步状态
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    
    // UserDefaults 作为本地备用存储
    private let shownNoticeIDsKey = "shownNoticeIDs"
    private let noticeStatesKey = "noticeUserStates"
    private let lastResetTimeKey = "noticeLastResetTime"
    private let lastSyncTimeKey = "noticeReadStatusLastSync"
    private let readStatusDesiredKeys = [
        "readKey",
        "noticeID",
        "state",
        "readAt",
        "acknowledgedAt",
        "dismissedAt",
        "presentationCount",
        "lastPresentedAt",
        "title"
    ]
    
    private init() {
        // 从 UserDefaults 加载本地数据
        loadFromUserDefaults()
    }
    
    // MARK: - 从 UserDefaults 加载（备用）
    private func loadFromUserDefaults() {
        if let ids = UserDefaults.standard.stringArray(forKey: shownNoticeIDsKey) {
            localReadStatus = Set(ids)
        }
        if let data = UserDefaults.standard.data(forKey: noticeStatesKey),
           let states = try? JSONDecoder().decode([String: StateSnapshot].self, from: data) {
            localStates = states
        }
        localResetTime = UserDefaults.standard.object(forKey: lastResetTimeKey) as? Date
    }
    
    private func saveToUserDefaults() {
        UserDefaults.standard.set(Array(localReadStatus), forKey: shownNoticeIDsKey)
        if let data = try? JSONEncoder().encode(localStates) {
            UserDefaults.standard.set(data, forKey: noticeStatesKey)
        }
        UserDefaults.standard.set(localResetTime, forKey: lastResetTimeKey)
    }

    private func stateKey(for notice: Notice) -> String {
        notice.recordName ?? notice.id.uuidString
    }

    func state(for notice: Notice) -> UserState {
        if let resetTime = localResetTime, max(notice.createdAt, notice.updatedAt) > resetTime {
            return .unseen
        }

        let key = stateKey(for: notice)
        if let snapshot = localStates[key] {
            return snapshot.state
        }

        return hasReadNotice(notice) ? .read : .unseen
    }
    
    // MARK: - 检查公告是否已读
    func hasReadNotice(_ notice: Notice) -> Bool {
        let key = stateKey(for: notice)
        if let snapshot = localStates[key] {
            return snapshot.state == .read || snapshot.state == .acknowledged
        }

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

    func hasAcknowledgedNotice(_ notice: Notice) -> Bool {
        localStates[stateKey(for: notice)]?.state == .acknowledged
    }

    func presentationCount(for notice: Notice) -> Int {
        localStates[stateKey(for: notice)]?.presentationCount ?? 0
    }

    func shouldShowModal(for notice: Notice) -> Bool {
        guard notice.isEligibleForModal() else { return false }

        let currentState = state(for: notice)
        if currentState == .read || currentState == .acknowledged || currentState == .dismissed {
            return false
        }

        let snapshot = localStates[stateKey(for: notice)]
        if (snapshot?.presentationCount ?? 0) >= 1 {
            return false
        }

        let todayPresentations = localStates.values.filter { snapshot in
            guard let lastPresentedAt = snapshot.lastPresentedAt else { return false }
            return Calendar.current.isDateInToday(lastPresentedAt)
        }.count

        return todayPresentations < 1
    }

    // MARK: - 标记公告为已读
    func markAsRead(_ notice: Notice) {
        updateState(for: notice) { snapshot in
            if snapshot.state != .acknowledged {
                snapshot.state = .read
            }
            snapshot.readAt = snapshot.readAt ?? Date()
        }
    }

    func markAsAcknowledged(_ notice: Notice) {
        updateState(for: notice) { snapshot in
            snapshot.state = .acknowledged
            snapshot.acknowledgedAt = Date()
            snapshot.readAt = snapshot.readAt ?? Date()
        }
    }

    func markAsDismissed(_ notice: Notice) {
        updateState(for: notice) { snapshot in
            if snapshot.state == .unseen {
                snapshot.state = .dismissed
            }
            snapshot.dismissedAt = Date()
        }
    }

    func markAsPresented(_ notice: Notice) {
        updateState(for: notice) { snapshot in
            snapshot.presentationCount += 1
            snapshot.lastPresentedAt = Date()
        }
    }
    
    // MARK: - 重置已读历史
    func resetReadHistory() {
        localReadStatus.removeAll()
        localStates.removeAll()
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
    private func syncReadStatusToCloud(notice: Notice, snapshot: StateSnapshot) async {
        guard await checkAccountStatus() else { return }
        
        do {
            let recordID = CKRecord.ID(recordName: "NoticeReadStatus_\(stateKey(for: notice))")
            let record = CKRecord(recordType: "NoticeReadStatus", recordID: recordID)
            record["readKey"] = notice.readTrackingKey
            record["noticeID"] = notice.id.uuidString
            record["recordName"] = notice.recordName
            record["version"] = notice.version
            record["updatedAt"] = notice.updatedAt
            record["state"] = snapshot.state.rawValue
            record["readAt"] = snapshot.readAt
            record["acknowledgedAt"] = snapshot.acknowledgedAt
            record["dismissedAt"] = snapshot.dismissedAt
            record["presentationCount"] = snapshot.presentationCount
            record["lastPresentedAt"] = snapshot.lastPresentedAt
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
            let query = CKQuery(recordType: "NoticeReadStatus", predicate: NSPredicate(value: true))
            let records = try await fetchAllRecords(query: query, desiredKeys: [])

            for record in records {
                try await database.deleteRecord(withID: record.recordID)
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
            let cloudResetTime = try await fetchLatestResetTimeIfAvailable()
            
            // 2. 获取云端已读状态
            let query = CKQuery(recordType: "NoticeReadStatus", predicate: NSPredicate(value: true))
            let records = try await fetchAllRecords(query: query, desiredKeys: readStatusDesiredKeys)
            
            var cloudReadStatus: Set<String> = []
            var cloudStates: [String: StateSnapshot] = [:]
            for record in records {
                if let readKey = record["readKey"] as? String {
                    cloudReadStatus.insert(readKey)
                }
                if let noticeID = record["noticeID"] as? String {
                    cloudReadStatus.insert(noticeID)
                }

                let key = stateKey(from: record)
                let stateRaw = record["state"] as? String
                let snapshot = StateSnapshot(
                    state: UserState(rawValue: stateRaw ?? "") ?? .read,
                    readAt: record["readAt"] as? Date,
                    acknowledgedAt: record["acknowledgedAt"] as? Date,
                    dismissedAt: record["dismissedAt"] as? Date,
                    presentationCount: record["presentationCount"] as? Int ?? 0,
                    lastPresentedAt: record["lastPresentedAt"] as? Date
                )
                cloudStates[key] = snapshot
            }
            
            // 3. 合并本地和云端数据
            // 以最新的重置时间为准
            let localReset = localResetTime?.timeIntervalSince1970 ?? 0
            let cloudReset = cloudResetTime?.timeIntervalSince1970 ?? 0
            
            if cloudReset > localReset {
                // 云端重置时间更新，使用云端数据
                localResetTime = cloudResetTime
                localReadStatus = cloudReadStatus
                localStates = cloudStates
                print("📢 使用云端重置时间和已读状态")
            } else if cloudReset == localReset && cloudReset > 0 {
                // 重置时间相同，合并数据
                localReadStatus.formUnion(cloudReadStatus)
                mergeCloudStates(cloudStates)
                print("📢 合并本地和云端已读状态")
            } else if localReset == 0 && cloudReset == 0 {
                // 都没有重置过，合并数据
                localReadStatus.formUnion(cloudReadStatus)
                mergeCloudStates(cloudStates)
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

    private func updateState(
        for notice: Notice,
        mutation: (inout StateSnapshot) -> Void
    ) {
        let key = stateKey(for: notice)
        var snapshot = localStates[key] ?? StateSnapshot()
        mutation(&snapshot)
        localStates[key] = snapshot

        let keys = [notice.readTrackingKey] + notice.legacyReadTrackingKeys + [key]
        for rawKey in keys where snapshot.state != .unseen {
            localReadStatus.insert(rawKey)
        }

        saveToUserDefaults()

        Task {
            await syncReadStatusToCloud(notice: notice, snapshot: snapshot)
        }
    }

    private func mergeCloudStates(_ cloudStates: [String: StateSnapshot]) {
        for (key, cloudSnapshot) in cloudStates {
            guard let localSnapshot = localStates[key] else {
                localStates[key] = cloudSnapshot
                continue
            }

            if (cloudSnapshot.lastPresentedAt ?? .distantPast) > (localSnapshot.lastPresentedAt ?? .distantPast) {
                localStates[key] = cloudSnapshot
            }
        }
    }

    private func fetchLatestResetTimeIfAvailable() async throws -> Date? {
        do {
            let resetQuery = CKQuery(recordType: "NoticeReadStatusReset", predicate: NSPredicate(value: true))
            let resetRecords = try await fetchAllRecords(query: resetQuery, desiredKeys: ["resetAt"])
                .sorted { lhs, rhs in
                    let lhsDate = lhs["resetAt"] as? Date ?? .distantPast
                    let rhsDate = rhs["resetAt"] as? Date ?? .distantPast
                    return lhsDate > rhsDate
                }
            for record in resetRecords {
                if let resetAt = record["resetAt"] as? Date {
                    return resetAt
                }
            }
            return nil
        } catch let error as CKError where error.code == .unknownItem {
            print("📢 未配置 NoticeReadStatusReset 记录类型，按无重置记录继续")
            return nil
        }
    }

    private func stateKey(from record: CKRecord) -> String {
        let prefix = "NoticeReadStatus_"
        if record.recordID.recordName.hasPrefix(prefix) {
            return String(record.recordID.recordName.dropFirst(prefix.count))
        }

        if let noticeID = record["noticeID"] as? String, !noticeID.isEmpty {
            return noticeID
        }

        return record.recordID.recordName
    }

    private func fetchAllRecords(query: CKQuery, desiredKeys: [String]? = nil) async throws -> [CKRecord] {
        var collected: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let page = try await fetchRecordPage(
                query: cursor == nil ? query : nil,
                cursor: cursor,
                desiredKeys: desiredKeys
            )
            collected.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil

        return collected
    }

    private func fetchRecordPage(
        query: CKQuery?,
        cursor: CKQueryOperation.Cursor?,
        desiredKeys: [String]? = nil
    ) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { continuation in
            let collector = RecordPageCollector()
            let operation: CKQueryOperation
            if let cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else if let query {
                operation = CKQueryOperation(query: query)
            } else {
                continuation.resume(throwing: NSError(
                    domain: "NoticeReadStatusService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "已读状态查询参数无效"]
                ))
                return
            }

            operation.desiredKeys = desiredKeys
            operation.resultsLimit = CKQueryOperation.maximumResults
            operation.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record):
                    collector.append(record)
                case .failure(let error):
                    print("⚠️ 获取已读状态记录失败: \(error)")
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success(let nextCursor):
                    continuation.resume(returning: (collector.records, nextCursor))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }
}
