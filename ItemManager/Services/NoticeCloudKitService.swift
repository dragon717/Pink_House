import Foundation
import CloudKit
import SwiftData
import UIKit
import Combine

// MARK: - Notice CloudKit 同步服务
// 使用 Public Database 实现公告的跨用户同步
// 媒体资源使用应用内置资源，不通过 CloudKit 传输

@MainActor
class NoticeCloudKitService: ObservableObject {
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

    static let shared = NoticeCloudKitService()

    private let container = CKContainer(identifier: "iCloud.bugod2.ItemManager")
    private var database: CKDatabase {
        return container.publicCloudDatabase
    }
    private let noticeDesiredKeys = [
        "id",
        "title",
        "summary",
        "content",
        "locale",
        "mediaType",
        "status",
        "channel",
        "severity",
        "displayPriority",
        "priority",
        "isPinned",
        "requiresAck",
        "isSilent",
        "isActive",
        "publishAt",
        "startAt",
        "endAt",
        "archivedAt",
        "audience",
        "minAppVersion",
        "maxAppVersion",
        "actionType",
        "actionTarget",
        "actionLabel",
        "environment",
        "revision",
        "createdAt",
        "updatedAt",
        "version",
        "rollbackFrom",
        "createdBy",
        "updatedBy",
        "publishedBy",
        Notice.builtinMediaNameField,
        "mediaAsset"
    ]

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published private(set) var lastFetchedNoticeIdentifiers: Set<String> = []
    @Published private(set) var lastFetchSucceeded = false
    @Published private(set) var lastDeleteFailedBecauseMissingRecord = false

    // 管理员 iCloud IDs - 只有这些用户可以发布公告
    private let adminIDs: [String] = [
        "_819804d902cb79c2d6e4bf736ed6c50b",  // 主管理员
        "_8a195c73786fc49283cc3d180dbf50bb",  // 本机（sangyu）运营账号，2026-09-15 加入
    ]

    private init() {}

    // MARK: - 创作者 / 运营白名单判定
    //
    // 三态而不是布尔，是因为「取不到 iCloud 身份」和「取到了但不在名单里」
    // 必须区别对待：
    //   · denied      —— 明确的「你不是运营」。上传入口**一律不显示**，
    //                    本机的「创作者模式」开关也不能把它撬开（这是使用者的明确要求）。
    //   · unresolved  —— 模拟器 / 未登录 iCloud / 网络失败，身份根本取不到。
    //                    这种情况不能等同于「不是运营」，否则内容维护者在模拟器上
    //                    永远没有入口；此时允许「创作者模式」开关解界面闸门。
    //   · allowed     —— 在白名单里，正常显示。
    //
    // ⚠️ 这一层只是**界面闸门**，不是安全边界：真正的写入权限在 CloudKit Console
    // 的 Security Roles。非白名单账号即使绕过界面，也照样写不进去。

    /// Xcode 控制台里搜这个关键词就能看到白名单判定全过程。
    nonisolated static let creatorGateLogTag = "CreatorGate"

    nonisolated enum CreatorGate: Equatable, Sendable {
        case allowed
        case denied
        case unresolved(reason: String)

        var isDefinitelyNotOperator: Bool { self == .denied }
    }

    /// 判定当前 iCloud 账户是否在创作者 / 运营白名单里，并把过程打进日志。
    ///
    /// 日志格式固定为 `🔑 [CreatorGate] …`，在 Xcode 控制台过滤 `CreatorGate` 即可：
    /// ```
    /// 🔑 [CreatorGate] 本机 iCloud 用户标识 = _819804d902cb79c2d6e4bf736ed6c50b
    /// 🔑 [CreatorGate] 白名单           = ["_819804d9…"]
    /// 🔑 [CreatorGate] 命中白名单        = true
    /// 🔑 [CreatorGate] 判定结果          = allowed
    /// ```
    func creatorGate() async -> CreatorGate {
        do {
            let recordID = try await container.userRecordID()
            let key = recordID.recordName
            let matched = adminIDs.contains(key)

            print("🔑 [\(Self.creatorGateLogTag)] 本机 iCloud 用户标识 = \(key)")
            print("🔑 [\(Self.creatorGateLogTag)] 白名单            = \(adminIDs)")
            print("🔑 [\(Self.creatorGateLogTag)] 命中白名单        = \(matched)")
            print("🔑 [\(Self.creatorGateLogTag)] 判定结果          = \(matched ? "allowed" : "denied")")

            return matched ? .allowed : .denied
        } catch {
            let reason = (error as NSError).localizedDescription
            print("⚠️ [\(Self.creatorGateLogTag)] 取不到 iCloud 用户标识：\(reason)")
            print("⚠️ [\(Self.creatorGateLogTag)] 判定结果 = unresolved（模拟器 / 未登录 iCloud / 网络不通都会走到这里）")
            print("⚠️ [\(Self.creatorGateLogTag)] 此时只有本机「创作者模式」开关能解界面闸门；真实写入仍需 CloudKit 角色授权")
            return .unresolved(reason: reason)
        }
    }

    // MARK: - 检查是否为管理员
    func isAdmin() async -> Bool {
        // 只有「明确在白名单里」才算管理员。
        // 以前这里把「取不到身份」也当成 false，于是模拟器上永远没有入口；
        // 现在入口显示改由 `creatorGate()` 三态决定，这个布尔语义保持严格。
        await creatorGate() == .allowed
    }

    // MARK: - 获取当前用户 iCloud ID（用于配置管理员）
    func getCurrentUserID() async -> String? {
        do {
            let recordID = try await container.userRecordID()
            print("🔑 [\(Self.creatorGateLogTag)] 本机 iCloud 用户标识 = \(recordID.recordName)")
            print("📋 [\(Self.creatorGateLogTag)] 想把它加进白名单，复制上面的值，"
                + "追加到 NoticeCloudKitService.adminIDs（同时记得在 CloudKit Console 授权该角色）")
            return recordID.recordName
        } catch {
            print("❌ [\(Self.creatorGateLogTag)] 获取用户 ID 失败: \(error)")
            return nil
        }
    }

    // MARK: - 拉取云端公告
    func fetchCloudNotices() async -> [Notice] {
        isSyncing = true
        syncError = nil
        lastFetchSucceeded = false
        defer { isSyncing = false }

        do {
            // 检查 iCloud 账户状态
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                print("📢 iCloud 账户不可用，状态: \(accountStatus)")
                lastFetchedNoticeIdentifiers = []
                return []
            }
            
            // 检测当前环境
            #if DEBUG
            print("📢 当前运行环境: Development (调试版)")
            #else
            print("📢 当前运行环境: Production (发布版)")
            #endif

            let records = try await fetchNoticeRecordsWithFallback()

            var notices: [Notice] = []
            for record in records {
                if let notice = Notice(from: record) {
                    notices.append(notice)
                } else {
                    print("⚠️ 公告记录缺少必要字段，已跳过: \(record.recordID.recordName)")
                }
            }
            notices.sort(by: sortCloudNotices)

            lastSyncDate = Date()
            lastFetchSucceeded = true
            lastFetchedNoticeIdentifiers = Set(notices.map(\.stableIdentifier))
            print("✅ 成功拉取 \(notices.count) 条云端公告")
            for notice in notices {
                print("   📋 公告标题: \(notice.title)")
            }
            return notices

        } catch let error as CKError {
            // 处理 CloudKit 特定错误
            lastFetchedNoticeIdentifiers = []
            handleCloudKitError(error, operation: "拉取公告")
            return []
        } catch {
            lastFetchedNoticeIdentifiers = []
            syncError = "同步失败: \(error.localizedDescription)"
            print("❌ 拉取云端公告失败: \(error)")
            return []
        }
    }

    private func fetchNoticeRecordsWithFallback() async throws -> [CKRecord] {
        do {
            return try await performNoticeQuery(
                includeSortDescriptors: false,
                predicate: NSPredicate(format: "createdAt > %@", Date(timeIntervalSince1970: 0) as NSDate)
            )
        } catch let error as CKError where error.code == .invalidArguments {
            print("⚠️ 公告 createdAt 查询失败，尝试切换到 title 查询: \(error.localizedDescription)")
            do {
                return try await performNoticeQuery(
                    includeSortDescriptors: false,
                    predicate: NSPredicate(format: "title != %@", "")
                )
            } catch {
                throw error
            }
        }
    }

    private func performNoticeQuery(includeSortDescriptors: Bool, predicate: NSPredicate) async throws -> [CKRecord] {
        let query = CKQuery(recordType: Notice.recordType, predicate: predicate)
        if includeSortDescriptors {
            query.sortDescriptors = [
                NSSortDescriptor(key: "isPinned", ascending: false),
                NSSortDescriptor(key: "severity", ascending: false),
                NSSortDescriptor(key: "displayPriority", ascending: false),
                NSSortDescriptor(key: "publishAt", ascending: false),
                NSSortDescriptor(key: "updatedAt", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false)
            ]
        }

        return try await fetchAllRecords(query: query)
    }

    private func fetchAllRecords(query: CKQuery) async throws -> [CKRecord] {
        var collected: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let page = try await fetchRecordPage(query: cursor == nil ? query : nil, cursor: cursor)
            collected.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil

        return collected
    }

    private func fetchRecordPage(
        query: CKQuery?,
        cursor: CKQueryOperation.Cursor?
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
                    domain: "NoticeCloudKitService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "公告查询参数无效"]
                ))
                return
            }

            operation.desiredKeys = noticeDesiredKeys
            operation.resultsLimit = CKQueryOperation.maximumResults
            operation.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record):
                    collector.append(record)
                case .failure(let error):
                    print("⚠️ 获取公告记录失败: \(error)")
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

    private func sortCloudNotices(_ lhs: Notice, _ rhs: Notice) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }

        let severityOrder: [Notice.Severity: Int] = [
            .critical: 3,
            .important: 2,
            .info: 1
        ]
        let lhsSeverity = severityOrder[lhs.severity] ?? 0
        let rhsSeverity = severityOrder[rhs.severity] ?? 0
        if lhsSeverity != rhsSeverity {
            return lhsSeverity > rhsSeverity
        }

        if lhs.displayPriority != rhs.displayPriority {
            return lhs.displayPriority > rhs.displayPriority
        }

        if lhs.effectivePublishAt != rhs.effectivePublishAt {
            return lhs.effectivePublishAt > rhs.effectivePublishAt
        }

        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.createdAt > rhs.createdAt
    }
    
    // MARK: - 处理 CloudKit 错误
    private func handleCloudKitError(_ error: CKError, operation: String) {
        switch error.code {
        case .assetNotAvailable:
            print("❌ \(operation) 失败: 资源不可用")
        case .badContainer:
            print("❌ \(operation) 失败: CloudKit 容器配置错误")
        case .badDatabase:
            print("❌ \(operation) 失败: 数据库访问错误")
        case .invalidArguments:
            print("❌ \(operation) 失败: 参数无效")
        case .networkFailure:
            print("❌ \(operation) 失败: 网络错误")
        case .networkUnavailable:
            print("❌ \(operation) 失败: 网络不可用")
        case .notAuthenticated:
            print("❌ \(operation) 失败: 用户未登录 iCloud")
        case .permissionFailure:
            print("❌ \(operation) 失败: 权限不足，请在 CloudKit Dashboard 中配置 Public Database 权限")
        case .quotaExceeded:
            print("❌ \(operation) 失败: 超出存储配额")
        case .requestRateLimited:
            print("❌ \(operation) 失败: 请求频率过高")
        case .serverRecordChanged:
            print("❌ \(operation) 失败: 服务器记录已更改")
        case .serviceUnavailable:
            print("❌ \(operation) 失败: CloudKit 服务不可用")
        case .zoneBusy:
            print("❌ \(operation) 失败: 区域繁忙")
        case .zoneNotFound:
            print("❌ \(operation) 失败: 区域未找到")
        case .unknownItem:
            print("❌ \(operation) 失败: 记录类型不存在，请在 CloudKit Dashboard 中创建 Notice Record Type")
        default:
            print("❌ \(operation) 失败: \(error.localizedDescription) (code: \(error.code.rawValue))")
        }
        
        // 记录详细错误信息
        if let retryAfter = error.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            print("⏱️ 建议重试时间: \(retryAfter) 秒后")
        }
        
        syncError = "\(operation)失败: \(error.localizedDescription)"
    }

    // MARK: - 发布公告到云端
    func publishNotice(_ notice: Notice) async -> Bool {
        // 检查管理员权限
        guard await isAdmin() else {
            syncError = "只有管理员可以发布公告"
            print("❌ 非管理员尝试发布公告")
            return false
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let record = notice.toCloudKitRecord()
            let savedRecord = try await database.save(record)

            // 更新本地公告的 recordName
            notice.recordName = savedRecord.recordID.recordName
            notice.creatorID = savedRecord.creatorUserRecordID?.recordName
            notice.createdBy = notice.createdBy ?? savedRecord.creatorUserRecordID?.recordName
            if notice.status == .published {
                notice.publishedBy = notice.publishedBy ?? savedRecord.creatorUserRecordID?.recordName
            }

            print("✅ 公告发布成功: \(notice.title)")
            return true

        } catch {
            syncError = "发布失败: \(error.localizedDescription)"
            print("❌ 发布公告失败: \(error)")
            return false
        }
    }

    // MARK: - 更新云端公告
    func updateCloudNotice(_ notice: Notice) async -> Bool {
        guard await isAdmin() else {
            syncError = "只有管理员可以更新公告"
            return false
        }

        guard let recordName = notice.recordName else {
            syncError = "公告没有云端记录"
            return false
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            if let currentRecordID = try? await container.userRecordID() {
                let currentUserID = currentRecordID.recordName
                notice.updatedBy = currentUserID
                if notice.status == .published {
                    notice.publishedBy = notice.publishedBy ?? currentUserID
                }
            }
            let recordID = CKRecord.ID(recordName: recordName)
            let record = try await database.record(for: recordID)
            applyNotice(notice, to: record)

            try await database.save(record)
            print("✅ 公告更新成功: \(notice.title)")
            return true

        } catch {
            syncError = "更新失败: \(error.localizedDescription)"
            print("❌ 更新公告失败: \(error)")
            return false
        }
    }

    // MARK: - 删除云端公告（软删除）
    func deactivateCloudNotice(_ notice: Notice) async -> Bool {
        guard await isAdmin() else {
            syncError = "只有管理员可以删除公告"
            return false
        }

        guard let recordName = notice.recordName else {
            // 本地公告没有云端记录，直接返回成功
            return true
        }

        isSyncing = true
        syncError = nil
        lastDeleteFailedBecauseMissingRecord = false
        defer { isSyncing = false }

        do {
            if let currentRecordID = try? await container.userRecordID() {
                notice.updatedBy = currentRecordID.recordName
            }
            let recordID = CKRecord.ID(recordName: recordName)
            let record = try await database.record(for: recordID)

            applyNotice(notice, to: record)

            try await database.save(record)
            print("✅ 公告已停用: \(notice.title)")
            return true

        } catch let error as CKError where error.code == .unknownItem {
            lastDeleteFailedBecauseMissingRecord = true
            syncError = "删除失败: 云端记录不存在"
            print("⚠️ 云端公告记录不存在，视为陈旧本地缓存: \(notice.title)")
            return false
        } catch {
            syncError = "删除失败: \(error.localizedDescription)"
            print("❌ 停用公告失败: \(error)")
            return false
        }
    }

    // MARK: - 同步本地和云端公告
    func syncNotices(with _: ModelContext) async {
        print("🔄 开始同步公告...")

        _ = await fetchCloudNotices()
        guard lastFetchSucceeded else {
            print("⚠️ 本次云端公告拉取失败，保留现有内存公告")
            return
        }

        // Notice local SwiftData rows from older TestFlight schemas can abort
        // during CoreData materialization, so runtime sync intentionally avoids
        // merging into the legacy local cache.
        print("✅ 公告云端拉取完成，本地 SwiftData 缓存已跳过")
    }

    // MARK: - 合并本地和云端公告
    private func mergeNotices(
        cloudNotices: [Notice],
        localNotices: [Notice],
        context: ModelContext
    ) async {
        // 创建本地公告字典（以 recordName 为 key）
        var localDict: [String: Notice] = [:]
        for notice in localNotices {
            if let recordName = notice.recordName {
                localDict[recordName] = notice
            }
        }

        // 处理云端公告
        for cloudNotice in cloudNotices {
            if let recordName = cloudNotice.recordName,
               let localNotice = localDict[recordName] {
                if shouldPreserveLocalArchivedNotice(localNotice, over: cloudNotice) {
                    print("🛡️ 保留本地删除状态，暂不使用云端旧版本覆盖: \(localNotice.title)")
                } else {
                    // 更新本地公告
                    updateLocalNotice(localNotice, from: cloudNotice)
                }
            } else {
                // 插入新公告
                context.insert(cloudNotice)
            }
        }

        let cloudRecordNames = Set(cloudNotices.compactMap(\.recordName))
        let staleCloudCaches = localNotices.filter { notice in
            guard let recordName = notice.recordName else { return false }
            return !cloudRecordNames.contains(recordName)
        }
        for staleNotice in staleCloudCaches {
            print("🧹 清理已不在云端的本地缓存公告: \(staleNotice.title)")
            context.delete(staleNotice)
        }

        // 保存上下文
        do {
            try context.save()
        } catch {
            print("❌ 保存合并后的公告失败: \(error)")
        }
    }

    // MARK: - 更新本地公告
    private func updateLocalNotice(_ local: Notice, from cloud: Notice) {
        local.title = cloud.title
        local.summary = cloud.summary
        local.content = cloud.content
        local.locale = cloud.locale
        local.mediaURL = cloud.mediaURL
        local.cloudKitMediaURL = cloud.cloudKitMediaURL
        local.builtinMediaName = cloud.builtinMediaName
        local.mediaType = cloud.mediaType
        local.status = cloud.status
        local.channel = cloud.channel
        local.severity = cloud.severity
        local.displayPriority = cloud.displayPriority
        local.priority = cloud.priority
        local.isPinned = cloud.isPinned
        local.requiresAck = cloud.requiresAck
        local.isSilent = cloud.isSilent
        local.publishAt = cloud.publishAt
        local.startAt = cloud.startAt
        local.endAt = cloud.endAt
        local.archivedAt = cloud.archivedAt
        local.audience = cloud.audience
        local.minAppVersion = cloud.minAppVersion
        local.maxAppVersion = cloud.maxAppVersion
        local.actionType = cloud.actionType
        local.actionTarget = cloud.actionTarget
        local.actionLabel = cloud.actionLabel
        local.environment = cloud.environment
        local.revision = cloud.revision
        local.rollbackFrom = cloud.rollbackFrom
        local.isActive = cloud.isActive
        local.createdAt = cloud.createdAt
        local.updatedAt = cloud.updatedAt
        local.version = cloud.version
        local.recordName = cloud.recordName
        local.creatorID = cloud.creatorID
        local.createdBy = cloud.createdBy
        local.updatedBy = cloud.updatedBy
        local.publishedBy = cloud.publishedBy
        local.normalizeLegacyFields()
    }

    private func shouldPreserveLocalArchivedNotice(_ local: Notice, over cloud: Notice) -> Bool {
        guard local.status == .archived else { return false }
        guard cloud.status != .archived else { return false }
        return local.updatedAt >= cloud.updatedAt
    }

    private func applyNotice(_ notice: Notice, to record: CKRecord) {
        notice.applyLifecycleDefaults()
        record["id"] = notice.id.uuidString
        record["title"] = notice.title
        record["summary"] = notice.summary
        record["content"] = notice.content
        record["locale"] = notice.locale
        record["mediaType"] = notice.mediaType.rawValue
        record["status"] = notice.status.rawValue
        record["channel"] = notice.channel.rawValue
        record["severity"] = notice.severity.rawValue
        record["displayPriority"] = notice.displayPriority
        record["priority"] = notice.priority
        record["isPinned"] = notice.isPinned
        record["requiresAck"] = notice.requiresAck
        record["isSilent"] = notice.isSilent
        record["isActive"] = notice.isActive
        record["publishAt"] = notice.publishAt
        record["startAt"] = notice.startAt
        record["endAt"] = notice.endAt
        record["archivedAt"] = notice.archivedAt
        record["audience"] = notice.audience
        record["minAppVersion"] = notice.minAppVersion
        record["maxAppVersion"] = notice.maxAppVersion
        record["actionType"] = notice.actionType.rawValue
        record["actionTarget"] = notice.actionTarget
        record["actionLabel"] = notice.actionLabel
        record["environment"] = notice.environment.rawValue
        record["revision"] = notice.revision
        record["createdAt"] = notice.createdAt
        record["updatedAt"] = notice.updatedAt
        record["version"] = notice.version
        record["rollbackFrom"] = notice.rollbackFrom
        record["createdBy"] = notice.createdBy
        record["updatedBy"] = notice.updatedBy
        record["publishedBy"] = notice.publishedBy
        record[Notice.builtinMediaNameField] = notice.builtinMediaName

        if let mediaURL = notice.mediaURL,
           !mediaURL.hasPrefix("builtin://"),
           let url = URL(string: mediaURL),
           FileManager.default.fileExists(atPath: url.path) {
            record["mediaAsset"] = CKAsset(fileURL: url)
        } else {
            record["mediaAsset"] = nil
        }
    }
}

// MARK: - CKContainer 扩展
extension CKContainer {
    func userRecordID() async throws -> CKRecord.ID {
        return try await withCheckedThrowingContinuation { continuation in
            fetchUserRecordIDWithCheck { recordID, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let recordID = recordID {
                    continuation.resume(returning: recordID)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "NoticeCloudKitService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "无法获取用户ID"]
                    ))
                }
            }
        }
    }

    private func fetchUserRecordIDWithCheck(completion: @escaping (CKRecord.ID?, Error?) -> Void) {
        accountStatus { status, error in
            if let error = error {
                completion(nil, error)
                return
            }

            guard status == .available else {
                completion(nil, NSError(
                    domain: "NoticeCloudKitService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "iCloud 账户不可用"]
                ))
                return
            }

            self.fetchUserRecordID { recordID, error in
                completion(recordID, error)
            }
        }
    }
}
