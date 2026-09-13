import Combine
import Foundation

// MARK: - 缓存维护
//
// 对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md §13.2 / §13.3。
//
// 设置页要如实显示清理范围，并且**只**清理可重新下载的公共资料副本：
//   - 不删除衣橱、手账、收藏或个人照片；
//   - 不删除 Bundle 离线种子；
//   - 不删除撤回控制版本（否则被撤回内容可能复活）。

/// 维护服务。纯逻辑、无 UI 状态，因此不需要 MainActor 隔离。
nonisolated struct TimeHallCacheMaintenanceService: TimeHallCacheMaintaining {
    let repository: TimeHallRepository

    func usage() async -> TimeHallCacheUsage {
        await repository.usage()
    }

    func clearDownloadedContent() async throws {
        try await repository.clearDownloadedContent()
    }
}

/// 设置页视图模型
@MainActor
final class TimeHallCacheSettingsModel: ObservableObject {
    @Published private(set) var usage: TimeHallCacheUsage = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var isClearing = false
    @Published var errorMessage: String?
    @Published var didClear = false

    private let service: TimeHallCacheMaintenanceService

    init(service: TimeHallCacheMaintenanceService) {
        self.service = service
    }

    convenience init() {
        self.init(service: TimeHallCacheMaintenanceService(repository: TimeHallRepository.shared))
    }

    func loadUsage() async {
        isLoading = true
        usage = await service.usage()
        isLoading = false
    }

    func clear() async {
        isClearing = true
        defer { isClearing = false }
        do {
            try await service.clearDownloadedContent()
            didClear = true
            // 清理后重新统计，让用户看到空间确实释放了
            usage = await service.usage()
        } catch {
            errorMessage = "清理失败，请稍后重试。"
        }
    }

    var lastCheckedDescription: String {
        guard let date = usage.lastCheckedAt else { return "尚未检查" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
