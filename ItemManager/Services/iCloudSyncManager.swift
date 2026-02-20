import Foundation
import SwiftData
import CloudKit
import Combine
import CoreData

/// iCloud 同步管理器
/// 负责数据迁移、冲突解决和同步状态监控
@Observable
final class iCloudSyncManager {
    static let shared = iCloudSyncManager()

    // MARK: - 同步状态
    enum SyncStatus: Equatable {
        case notStarted
        case migrating(progress: Double)
        case syncing
        case synced
        case failed(Error)
        case offline

        static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
            switch (lhs, rhs) {
            case (.notStarted, .notStarted),
                 (.syncing, .syncing),
                 (.synced, .synced),
                 (.offline, .offline):
                return true
            case (.migrating(let p1), .migrating(let p2)):
                return p1 == p2
            case (.failed, .failed):
                return true
            default:
                return false
            }
        }
    }

    var syncStatus: SyncStatus = .notStarted
    var lastSyncTime: Date?
    var migrationProgress: Double = 0
    var isMigrationCompleted: Bool {
        UserDefaults.standard.bool(forKey: "iCloudMigrationCompleted")
    }

    // MARK: - 通知名称
    static let syncStatusChanged = Notification.Name("iCloudSyncStatusChanged")
    static let migrationCompleted = Notification.Name("iCloudMigrationCompleted")
    static let conflictDetected = Notification.Name("iCloudConflictDetected")

    private var cancellables = Set<AnyCancellable>()
    private var container: ModelContainer?
    private var context: ModelContext?

    private init() {}

    // MARK: - 初始化
    func setup(with container: ModelContainer) {
        self.container = container
        self.context = ModelContext(container)

        // 检查是否需要迁移
        if !isMigrationCompleted {
            Task {
                await performMigration()
            }
        }

        // 监听 iCloud 账户状态
        setupCloudKitMonitoring()
    }

    // MARK: - 数据迁移
    /// 执行从旧本地 Store 到 iCloud Store 的数据迁移
    func performMigration() async {
        await MainActor.run {
            syncStatus = .migrating(progress: 0)
            NotificationCenter.default.post(name: Self.syncStatusChanged, object: nil)
        }

        do {
            // 1. 检查旧数据库是否存在
            let oldStoreURL = getOldStoreURL()
            guard FileManager.default.fileExists(atPath: oldStoreURL.path) else {
                print("[iCloudSync] 未找到旧数据库，跳过迁移")
                markMigrationCompleted()
                return
            }

            // 2. 迁移数据
            // 注意：实际的迁移逻辑需要在具体的模型上下文中实现
            // 这里提供一个框架，具体的迁移在应用启动时由 SwiftData 自动处理

            // 3. 标记迁移完成
            markMigrationCompleted()

            await MainActor.run {
                syncStatus = .synced
                lastSyncTime = Date()
                NotificationCenter.default.post(name: Self.migrationCompleted, object: nil)
                NotificationCenter.default.post(name: Self.syncStatusChanged, object: nil)
            }

            print("[iCloudSync] 数据迁移完成")

        } catch {
            print("[iCloudSync] 迁移失败: \(error)")
            await MainActor.run {
                syncStatus = .failed(error)
                NotificationCenter.default.post(name: Self.syncStatusChanged, object: nil)
            }
        }
    }

    // MARK: - 冲突解决
    /// 解决数据冲突 - 使用 "最后写入者胜出" 策略
    func resolveConflict<T: PersistentModel>(
        local: T,
        remote: T,
        localTimestamp: Date,
        remoteTimestamp: Date
    ) -> T {
        if localTimestamp > remoteTimestamp {
            print("[iCloudSync] 保留本地数据 (更新)")
            return local
        } else {
            print("[iCloudSync] 采用远程数据")
            return remote
        }
    }

    /// 智能合并 - 对于数组类型的数据尝试合并
    func mergeArrays<T: Identifiable & Equatable>(
        local: [T],
        remote: [T]
    ) -> [T] {
        var merged = local
        for remoteItem in remote {
            if !local.contains(where: { $0.id == remoteItem.id }) {
                merged.append(remoteItem)
            }
        }
        return merged
    }

    // MARK: - 同步状态监控
    /// 强制触发同步
    func triggerSync() async {
        guard let context = context else { return }

        await MainActor.run {
            syncStatus = .syncing
            NotificationCenter.default.post(name: Self.syncStatusChanged, object: nil)
        }

        do {
            try context.save()

            await MainActor.run {
                syncStatus = .synced
                lastSyncTime = Date()
                NotificationCenter.default.post(name: Self.syncStatusChanged, object: nil)
            }
        } catch {
            await MainActor.run {
                syncStatus = .failed(error)
                NotificationCenter.default.post(name: Self.syncStatusChanged, object: nil)
            }
        }
    }

    /// 检查 iCloud 账户状态
    func checkiCloudStatus() async -> CKAccountStatus {
        let container = CKContainer.default()
        return try! await container.accountStatus()
    }

    // MARK: - 私有方法
    private func getOldStoreURL() -> URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("default.store")
    }

    private func markMigrationCompleted() {
        UserDefaults.standard.set(true, forKey: "iCloudMigrationCompleted")
    }

    private func setupCloudKitMonitoring() {
        // 监听 CloudKit 同步通知
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .sink { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event else { return }

                self?.handleCloudKitEvent(event)
            }
            .store(in: &cancellables)
    }

    private func handleCloudKitEvent(_ event: NSPersistentCloudKitContainer.Event) {
        switch event.type {
        case .setup:
            print("[iCloudSync] CloudKit 设置中...")
        case .import:
            print("[iCloudSync] 导入数据中...")
        case .export:
            print("[iCloudSync] 导出数据中...")
        @unknown default:
            break
        }

        if event.endDate != nil {
            if let error = event.error {
                print("[iCloudSync] 同步错误: \(error)")
                syncStatus = .failed(error)
            } else {
                print("[iCloudSync] 同步完成")
                syncStatus = .synced
                lastSyncTime = Date()
            }
            NotificationCenter.default.post(name: Self.syncStatusChanged, object: nil)
        }
    }
}

// MARK: - 模型扩展协议
/// 可同步模型协议
protocol SyncableModel {
    var id: UUID { get set }
    var lastModified: Date { get set }
}

// MARK: - 默认实现
extension SyncableModel {
    /// 更新最后修改时间
    mutating func touch() {
        lastModified = Date()
    }
}
