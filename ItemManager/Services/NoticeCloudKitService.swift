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
    static let shared = NoticeCloudKitService()

    private let container = CKContainer(identifier: "iCloud.bugod2.ItemManager")
    private var database: CKDatabase {
        return container.publicCloudDatabase
    }

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    // 管理员 iCloud IDs - 只有这些用户可以发布公告
    private let adminIDs: [String] = [
        "_819804d902cb79c2d6e4bf736ed6c50b",  // 主管理员
    ]

    private init() {}

    // MARK: - 检查是否为管理员
    func isAdmin() async -> Bool {
        do {
            let recordID = try await container.userRecordID()
            // TODO: 配置时取消注释下面这行来获取你的 iCloud ID
            // print("🔑 当前用户 iCloud ID: \(recordID.recordName)")
            return adminIDs.contains(recordID.recordName)
        } catch {
            print("检查管理员权限失败: \(error)")
            return false
        }
    }

    // MARK: - 获取当前用户 iCloud ID（用于配置管理员）
    func getCurrentUserID() async -> String? {
        do {
            let recordID = try await container.userRecordID()
            print("🔑 当前用户 iCloud ID: \(recordID.recordName)")
            print("📋 请复制上面的 ID 添加到 adminIDs 数组中")
            return recordID.recordName
        } catch {
            print("❌ 获取用户 ID 失败: \(error)")
            return nil
        }
    }

    // MARK: - 拉取云端公告
    func fetchCloudNotices() async -> [Notice] {
        isSyncing = true
        defer { isSyncing = false }

        do {
            // 检查 iCloud 账户状态
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                print("iCloud 账户不可用")
                return []
            }

            // 只获取最近30天的活跃公告
            let cutoffDate = Date().addingTimeInterval(-NoticeConfig.maxNoticeAge)
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "isActive == true"),
                NSPredicate(format: "createdAt > %@", cutoffDate as NSDate)
            ])
            let query = CKQuery(recordType: Notice.recordType, predicate: predicate)
            query.sortDescriptors = [
                NSSortDescriptor(key: "priority", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false)
            ]

            let (results, _) = try await database.records(matching: query, inZoneWith: nil)

            var notices: [Notice] = []
            for (_, result) in results {
                switch result {
                case .success(let record):
                    if let notice = Notice(from: record) {
                        notices.append(notice)
                    }
                case .failure(let error):
                    print("获取公告记录失败: \(error)")
                }
            }

            lastSyncDate = Date()
            print("✅ 成功拉取 \(notices.count) 条云端公告")
            return notices

        } catch {
            syncError = "同步失败: \(error.localizedDescription)"
            print("❌ 拉取云端公告失败: \(error)")
            return []
        }
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
        defer { isSyncing = false }

        do {
            let record = notice.toCloudKitRecord()
            let savedRecord = try await database.save(record)

            // 更新本地公告的 recordName
            notice.recordName = savedRecord.recordID.recordName
            notice.creatorID = savedRecord.creatorUserRecordID?.recordName

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
        defer { isSyncing = false }

        do {
            let recordID = CKRecord.ID(recordName: recordName)
            let record = try await database.record(for: recordID)

            // 更新字段
            record["title"] = notice.title
            record["content"] = notice.content
            record["priority"] = notice.priority
            record["isActive"] = notice.isActive
            record["updatedAt"] = Date()

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
        defer { isSyncing = false }

        do {
            let recordID = CKRecord.ID(recordName: recordName)
            let record = try await database.record(for: recordID)

            // 软删除：标记为不活跃
            record["isActive"] = false
            record["updatedAt"] = Date()

            try await database.save(record)
            print("✅ 公告已停用: \(notice.title)")
            return true

        } catch {
            syncError = "删除失败: \(error.localizedDescription)"
            print("❌ 停用公告失败: \(error)")
            return false
        }
    }

    // MARK: - 同步本地和云端公告
    func syncNotices(with context: ModelContext) async {
        print("🔄 开始同步公告...")

        // 1. 拉取云端公告
        let cloudNotices = await fetchCloudNotices()

        // 2. 获取本地公告
        let localDescriptor = FetchDescriptor<Notice>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let localNotices = try? context.fetch(localDescriptor) else {
            print("❌ 获取本地公告失败")
            return
        }

        // 3. 合并公告
        await mergeNotices(
            cloudNotices: cloudNotices,
            localNotices: localNotices,
            context: context
        )

        print("✅ 公告同步完成")
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
                // 更新本地公告
                updateLocalNotice(localNotice, from: cloudNotice)
            } else {
                // 插入新公告
                context.insert(cloudNotice)
            }
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
        local.content = cloud.content
        local.priority = cloud.priority
        local.isActive = cloud.isActive
        local.updatedAt = cloud.updatedAt
        local.creatorID = cloud.creatorID
        // 注意：不更新 mediaURL，因为使用本地资源
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
