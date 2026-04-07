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
    @Published var managedNotices: [Notice] = []
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
            let descriptor = FetchDescriptor<Notice>(
                sortBy: [
                    SortDescriptor(\.updatedAt, order: .reverse),
                    SortDescriptor(\.createdAt, order: .reverse)
                ]
            )
            let fetched = try context.fetch(descriptor)
            refreshCollections(from: fetched)
        } catch {
            errorMessage = "获取公告失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 从 CloudKit 同步
    func syncFromCloudKit() async {
        guard let context = modelContext else { return }
        errorMessage = nil

        isSyncing = true

        await cloudKitService.syncNotices(with: context)
        if let syncError = cloudKitService.syncError {
            errorMessage = syncError
        }

        // 在结束同步标记前先刷新本地列表，避免弹窗判断拿到旧数据。
        await fetchNotices()
        isSyncing = false
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
        summary: String? = nil,
        content: String,
        mediaURL: String? = nil,
        builtinMediaName: String? = nil,
        mediaType: Notice.MediaType = .none,
        priority: Int = 0,
        status: Notice.Status = .draft,
        channel: Notice.Channel = .inbox,
        severity: Notice.Severity = .info,
        isPinned: Bool = false,
        requiresAck: Bool = false,
        isSilent: Bool = false,
        publishAt: Date? = nil,
        startAt: Date? = nil,
        endAt: Date? = nil,
        audience: String = "all",
        minAppVersion: String? = nil,
        maxAppVersion: String? = nil,
        actionType: Notice.ActionType = .none,
        actionTarget: String? = nil,
        actionLabel: String? = nil
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
        let existing = managedNotices.first { $0.title == title && $0.content == content }
        if existing != nil {
            print("⚠️ 相同内容的公告已存在")
            errorMessage = "相同内容的公告已存在"
            return nil
        }

        guard validateNoticeInput(
            status: status,
            channel: channel,
            severity: severity,
            actionType: actionType,
            actionTarget: actionTarget,
            publishAt: publishAt,
            startAt: startAt,
            endAt: endAt
        ) else {
            return nil
        }

        let notice = Notice(
            title: title,
            summary: summary,
            content: content,
            mediaURL: mediaURL,
            builtinMediaName: builtinMediaName,
            mediaType: mediaType,
            priority: priority,
            displayPriority: priority,
            status: status,
            channel: channel,
            severity: severity,
            isPinned: isPinned,
            requiresAck: requiresAck,
            isSilent: isSilent,
            publishAt: publishAt,
            startAt: startAt,
            endAt: endAt,
            audience: audience,
            minAppVersion: minAppVersion,
            maxAppVersion: maxAppVersion,
            actionType: actionType,
            actionTarget: actionTarget,
            actionLabel: actionLabel
        )
        notice.applyLifecycleDefaults()

        context.insert(notice)

        do {
            try context.save()
            print("✅ 公告本地保存成功")

            let published = await cloudKitService.publishNotice(notice)
            if published {
                print("✅ 公告已发布到云端")
                try context.save()
            } else {
                context.delete(notice)
                try context.save()
                print("⚠️ 公告创建已回滚，避免留下本地孤儿记录")
                errorMessage = cloudKitService.syncError ?? "云端发布失败"
                return nil
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
        guard validateNoticeInput(
            status: notice.status,
            channel: notice.channel,
            severity: notice.severity,
            actionType: notice.actionType,
            actionTarget: notice.actionTarget,
            publishAt: notice.publishAt,
            startAt: notice.startAt,
            endAt: notice.endAt
        ) else {
            return
        }
        notice.revision += 1
        notice.version = notice.revision
        notice.updatedAt = Date()
        notice.applyLifecycleDefaults(now: notice.updatedAt)

        do {
            try context.save()

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

        // 仅本地未同步的公告直接本地删除，避免残留在列表里。
        if notice.recordName == nil {
            context.delete(notice)
            do {
                try context.save()
                await fetchNotices()
            } catch {
                errorMessage = "删除公告失败: \(error.localizedDescription)"
            }
            return
        }

        notice.status = .archived
        notice.archivedAt = Date()
        notice.revision += 1
        notice.version = notice.revision
        notice.updatedAt = Date()
        notice.applyLifecycleDefaults(now: notice.updatedAt)

        do {
            try context.save()

            let deactivated = await cloudKitService.deactivateCloudNotice(notice)
            if deactivated {
                print("✅ 公告已从云端停用")
            } else if cloudKitService.lastDeleteFailedBecauseMissingRecord {
                context.delete(notice)
                try context.save()
                print("🧹 云端记录缺失，已清理本地缓存公告")
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

    func latestEligibleModalNotice() -> Notice? {
        notices.first { $0.isEligibleForModal() }
    }

    func wasFetchedFromCloudThisRun(_ notice: Notice) -> Bool {
        cloudKitService.lastFetchedNoticeIdentifiers.contains(notice.stableIdentifier)
    }

    private func validateNoticeInput(
        status: Notice.Status,
        channel: Notice.Channel,
        severity: Notice.Severity,
        actionType: Notice.ActionType,
        actionTarget: String?,
        publishAt: Date?,
        startAt: Date?,
        endAt: Date?
    ) -> Bool {
        if channel == .modal && severity != .critical {
            errorMessage = "只有 critical 公告可以配置为弹窗"
            return false
        }

        if actionType != .none && (actionTarget?.isEmpty ?? true) {
            errorMessage = "配置动作后必须填写动作目标"
            return false
        }

        if let startAt, let endAt, endAt < startAt {
            errorMessage = "结束时间不能早于开始时间"
            return false
        }

        if status == .scheduled && publishAt == nil && startAt == nil {
            errorMessage = "定时公告必须设置发布时间或开始时间"
            return false
        }

        return true
    }

    private func refreshCollections(from notices: [Notice]) {
        let normalized = notices.map { notice -> Notice in
            notice.normalizeLegacyFields()
            return notice
        }

        managedNotices = normalized.sorted(by: sortForAdmin)
        self.notices = managedNotices
            .filter { $0.isVisibleInInbox() }
            .sorted(by: sortForUser)
    }

    private func sortForUser(_ lhs: Notice, _ rhs: Notice) -> Bool {
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

        return lhs.updatedAt > rhs.updatedAt
    }

    private func sortForAdmin(_ lhs: Notice, _ rhs: Notice) -> Bool {
        let statusOrder: [Notice.Status: Int] = [
            .draft: 0,
            .scheduled: 1,
            .published: 2,
            .archived: 3
        ]

        let lhsOrder = statusOrder[lhs.status] ?? 99
        let rhsOrder = statusOrder[rhs.status] ?? 99
        if lhsOrder != rhsOrder {
            return lhsOrder < rhsOrder
        }

        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.createdAt > rhs.createdAt
    }
}
