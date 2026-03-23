import Foundation
import SwiftData
import CloudKit
import UIKit
import Combine

// MARK: - 公告服务
// 处理公告的CRUD操作和CloudKit同步
// 注意：Public Database 的权限需要在 CloudKit Dashboard 中配置

@MainActor
class NoticeService: ObservableObject {
    static let shared = NoticeService()

    @Published var notices: [Notice] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSyncing = false

    private var modelContext: ModelContext?
    private let cloudKitService = NoticeCloudKitService.shared

    private init() {}

    // MARK: - 设置 ModelContext
    func setup(with context: ModelContext) {
        self.modelContext = context
        Task {
            await fetchNotices()
            await syncIfNeeded()
        }
    }

    // MARK: - 获取公告列表
    func fetchNotices() async {
        guard let context = modelContext else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            // 从本地 SwiftData 获取
            let descriptor = FetchDescriptor<Notice>(
                predicate: #Predicate { $0.isActive == true },
                sortBy: [SortDescriptor(\.priority, order: .reverse),
                         SortDescriptor(\.updatedAt, order: .reverse),
                         SortDescriptor(\.createdAt, order: .reverse)]
            )
            notices = try context.fetch(descriptor)

        } catch {
            errorMessage = "获取公告失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 从 CloudKit 同步
    func syncFromCloudKit() async {
        guard let context = modelContext else { return }
        errorMessage = nil

        isSyncing = true
        defer {
            isSyncing = false
            // 同步完成后刷新本地列表
            Task {
                await fetchNotices()
            }
        }

        await cloudKitService.syncNotices(with: context)
        if let syncError = cloudKitService.syncError {
            errorMessage = syncError
        }
    }

    func syncIfNeeded(force: Bool = false) async {
        if isSyncing { return }

        if force {
            await syncFromCloudKit()
            return
        }

        if let lastSyncDate = cloudKitService.lastSyncDate,
           Date().timeIntervalSince(lastSyncDate) < NoticeConfig.syncInterval {
            return
        }

        await syncFromCloudKit()
    }

    // MARK: - 创建公告
    func createNotice(
        title: String,
        content: String,
        mediaURL: String? = nil,
        builtinMediaName: String? = nil,
        mediaType: Notice.MediaType = .none,
        priority: Int = 0
    ) async -> Notice? {
        guard let context = modelContext else {
            print("❌ 创建公告失败: modelContext 为 nil")
            errorMessage = "系统错误，请重试"
            return nil
        }

        // 检查管理员权限
        let isAdmin = await cloudKitService.isAdmin()
        guard isAdmin else {
            errorMessage = "只有管理员可以发布公告"
            return nil
        }

        print("📝 开始创建公告: title=\(title)")

        // 检查重复
        let existing = notices.first { $0.title == title && $0.content == content }
        if existing != nil {
            print("⚠️ 相同内容的公告已存在")
            errorMessage = "相同内容的公告已存在"
            return nil
        }

        let notice = Notice(
            title: title,
            content: content,
            mediaURL: mediaURL,
            builtinMediaName: builtinMediaName,
            mediaType: mediaType,
            priority: priority
        )

        // 先保存到本地
        context.insert(notice)

        do {
            try context.save()
            print("✅ 公告本地保存成功")

            // 发布到 CloudKit
            let published = await cloudKitService.publishNotice(notice)
            if published {
                print("✅ 公告已发布到云端")
                // 保存云端返回的 recordName
                try context.save()
            } else {
                print("⚠️ 公告本地保存但云端发布失败")
                errorMessage = cloudKitService.syncError ?? "云端发布失败"
            }

            await fetchNotices()
            return notice

        } catch {
            print("❌ 保存公告失败: \(error)")
            errorMessage = "保存公告失败: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - 更新公告
    func updateNotice(_ notice: Notice) async {
        guard let context = modelContext else { return }

        // 检查管理员权限
        let isAdmin = await cloudKitService.isAdmin()
        guard isAdmin else {
            errorMessage = "只有管理员可以更新公告"
            return
        }

        errorMessage = nil
        notice.version += 1
        notice.updatedAt = Date()

        do {
            try context.save()

            // 同步更新到 CloudKit
            let updated = await cloudKitService.updateCloudNotice(notice)
            if updated {
                print("✅ 公告已更新到云端")
            } else {
                print("⚠️ 公告本地更新但云端同步失败")
            }

            await fetchNotices()
        } catch {
            errorMessage = "更新公告失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 删除公告 (软删除)
    func deleteNotice(_ notice: Notice) async {
        guard let context = modelContext else { return }

        // 检查管理员权限
        let isAdmin = await cloudKitService.isAdmin()
        guard isAdmin else {
            errorMessage = "只有管理员可以删除公告"
            return
        }

        errorMessage = nil
        // 软删除：标记为不活跃
        notice.isActive = false
        notice.version += 1
        notice.updatedAt = Date()

        do {
            try context.save()

            // 同步删除到 CloudKit
            let deactivated = await cloudKitService.deactivateCloudNotice(notice)
            if deactivated {
                print("✅ 公告已从云端停用")
            } else {
                print("⚠️ 公告本地停用但云端同步失败")
            }

            await fetchNotices()
        } catch {
            errorMessage = "删除公告失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 硬删除 (仅管理员使用)
    func hardDeleteNotice(_ notice: Notice) async {
        guard let context = modelContext else { return }

        // 检查管理员权限
        let isAdmin = await cloudKitService.isAdmin()
        guard isAdmin else {
            errorMessage = "只有管理员可以删除公告"
            return
        }

        context.delete(notice)

        do {
            try context.save()
            await fetchNotices()
        } catch {
            errorMessage = "删除公告失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 检查用户是否为管理员
    func isAdmin() async -> Bool {
        return await cloudKitService.isAdmin()
    }

    // MARK: - 频率限制检查
    func checkRateLimit() -> Bool {
        // 简单的客户端频率限制
        let lastPostKey = "lastNoticePostTime"
        let minInterval: TimeInterval = 60 // 1分钟

        if let lastPost = UserDefaults.standard.object(forKey: lastPostKey) as? Date {
            if Date().timeIntervalSince(lastPost) < minInterval {
                return false
            }
        }

        UserDefaults.standard.set(Date(), forKey: lastPostKey)
        return true
    }

    // MARK: - 手动触发同步
    func manualSync() async {
        await syncFromCloudKit()
    }
}
