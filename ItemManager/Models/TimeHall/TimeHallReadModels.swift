import Foundation

// MARK: - 业务日历
//
// 对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md §4.3。
//
// 「最近三天」= 今天、昨天、前天三个**自然日**，不是滚动 72 小时。
// 必须按来源品牌配置的 `sourceTimeZone` 计算业务日期，
// 不得用设备当前时区、也不得用固定减去若干秒来替代业务日历。
nonisolated enum TimeHallBusinessCalendar {
    /// 业务日期键，格式 `yyyy-MM-dd`
    static func dayKey(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day
        else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// 自然日递减。跨月、跨年与夏令时边界都由 Calendar 处理（§18.1 D08）。
    static func dayKey(byAddingDays days: Int, to dayKey: String, timeZone: TimeZone) -> String? {
        guard let date = date(fromDayKey: dayKey, timeZone: timeZone) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let shifted = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return self.dayKey(for: shifted, timeZone: timeZone)
    }

    /// 业务日期键 → 该业务日 00:00 的时刻
    static func date(fromDayKey dayKey: String, timeZone: TimeZone) -> Date? {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    /// 近 `count` 个自然日（含参考日），由新到旧。
    static func recentDayKeys(
        referenceDate: Date,
        count: Int,
        timeZone: TimeZone
    ) -> [String] {
        guard count > 0 else { return [] }
        let today = dayKey(for: referenceDate, timeZone: timeZone)
        var result: [String] = []
        for offset in 0..<count {
            if let key = dayKey(byAddingDays: -offset, to: today, timeZone: timeZone) {
                result.append(key)
            }
        }
        return result
    }

    /// 分片 ID 的月度范围键，格式 `yyyy-MM`
    static func monthKey(for dayKey: String) -> String {
        guard dayKey.count >= 7 else { return dayKey }
        return String(dayKey.prefix(7))
    }
}

// MARK: - 分片 ID 规范

/// 分片 ID 规范（§5.1）。
///
/// 逻辑覆盖可以按天，**物理数据包不必按天**：资讯按月打包，另附每日覆盖状态。
/// 分片 ID 只由 `brandID / entityType / scopeKey` 决定，
/// 因此同一分片在不同时区客户端上映射到同一 ID（§18.1 D07）。
nonisolated enum TimeHallPartitionID {
    /// 旧安装包 / 整馆 Bundle 种子使用的范围键
    static let legacyScope = "all"

    static func make(
        brandID: String,
        entityType: TimeHallEntityType,
        scopeKey: String
    ) -> String {
        "\(brandID)/\(entityType.rawValue)/\(scopeKey)"
    }

    /// 资讯等按月的分片
    static func monthly(
        brandID: String,
        entityType: TimeHallEntityType,
        dayKey: String
    ) -> String {
        make(brandID: brandID, entityType: entityType, scopeKey: TimeHallBusinessCalendar.monthKey(for: dayKey))
    }

    static func brandID(from partitionID: String) -> String? {
        let parts = partitionID.split(separator: "/")
        guard parts.count >= 3 else { return nil }
        return String(parts[0])
    }

    static func entityType(from partitionID: String) -> TimeHallEntityType? {
        let parts = partitionID.split(separator: "/")
        guard parts.count >= 3 else { return nil }
        return TimeHallEntityType(rawValue: String(parts[1]))
    }

    static func scopeKey(from partitionID: String) -> String? {
        let parts = partitionID.split(separator: "/")
        guard parts.count >= 3 else { return nil }
        return parts.dropFirst(2).joined(separator: "/")
    }

    /// 分片 ID 会落到文件名上，必须拒绝路径穿越与非法字符（§12.3）。
    static func isSafe(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 200 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-._/")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
            && !value.contains("..")
            && !value.hasPrefix("/")
            && !value.hasSuffix("/")
    }

    /// 落到磁盘文件名时把分隔符折叠，避免创建子目录层级
    static func fileNameComponent(for partitionID: String) -> String {
        partitionID.replacingOccurrences(of: "/", with: "_")
    }
}

// MARK: - 读取请求

/// 一次读取请求（§11.2 步骤 1：规范化品牌、实体类型、日期范围与业务时区）。
nonisolated struct TimeHallRequest: Sendable, Hashable {
    let brandID: String
    let entityTypes: Set<TimeHallEntityType>
    /// 近 N 个自然日；`nil` 表示不按日过滤
    let recentDayCount: Int?
    /// 计算业务日期的参考时刻
    let referenceDate: Date
    /// 是否允许访问云端。`false` 时只读 Bundle 与本地缓存（§16.1 离线回退）。
    let allowsNetwork: Bool
    /// 用户手动刷新：可跳过本地新鲜度间隔，但不能跳过服务端重试等待要求（§11.6）
    let forcesRefresh: Bool

    init(
        brandID: String,
        entityTypes: Set<TimeHallEntityType>,
        recentDayCount: Int? = nil,
        referenceDate: Date = Date(),
        allowsNetwork: Bool = true,
        forcesRefresh: Bool = false
    ) {
        self.brandID = brandID
        self.entityTypes = entityTypes
        self.recentDayCount = recentDayCount
        self.referenceDate = referenceDate
        self.allowsNetwork = allowsNetwork
        self.forcesRefresh = forcesRefresh
    }

    /// 品牌总览：目录、展品、官方目录、品牌史、搭配、专题
    static func brandOverview(brandID: String) -> TimeHallRequest {
        TimeHallRequest(
            brandID: brandID,
            entityTypes: [
                .brand, .catalogue, .archiveCatalogue, .item,
                .historyEntry, .coordinate, .story, .commerceProduct, .commerceSnapshot,
            ]
        )
    }

    /// 近期资讯：资讯 + 在售商品
    static func recent(brandID: String, days: Int, referenceDate: Date = Date()) -> TimeHallRequest {
        TimeHallRequest(
            brandID: brandID,
            entityTypes: [.event, .commerceProduct, .commerceSnapshot],
            recentDayCount: days,
            referenceDate: referenceDate
        )
    }

    /// 全部实体类型
    static func entire(brandID: String) -> TimeHallRequest {
        TimeHallRequest(brandID: brandID, entityTypes: Set(TimeHallEntityType.allCases))
    }

    /// 折叠为请求身份，用于同分片并发合并（§11.6）
    var deduplicationKey: String {
        let types = entityTypes.map(\.rawValue).sorted().joined(separator: ",")
        let days = recentDayCount.map(String.init) ?? "-"
        return "\(brandID)|\(types)|\(days)"
    }
}

// MARK: - 读取结果

/// 数据来源（§11.1 读取顺序与内容优先级是两回事）
nonisolated enum TimeHallDataSource: String, Sendable, Hashable {
    /// 仅随安装包分发的离线种子
    case bundle
    /// 仅本地下载缓存
    case downloadedCache
    /// 缓存与 Bundle 合成
    case mixed
    /// 无任何可用数据
    case none

    var labelZH: String {
        switch self {
        case .bundle: return "随包离线资料"
        case .downloadedCache: return "已下载资料"
        case .mixed: return "已下载资料 + 随包资料"
        case .none: return "无可用资料"
        }
    }
}

/// 陈旧原因。**错误不是空结果**（§16.1）。
nonisolated enum TimeHallStaleReason: String, Sendable, Hashable {
    case networkUnavailable
    case cloudUnavailable
    case permissionDenied
    case throttled
    case releaseUnreadable
    case bundleOnly
    case coverageIncomplete
    case neverChecked

    var labelZH: String {
        switch self {
        case .networkUnavailable: return "当前无网络"
        case .cloudUnavailable: return "云端暂时不可用"
        case .permissionDenied: return "读取被拒绝"
        case .throttled: return "云端请求过于频繁"
        case .releaseUnreadable: return "资料需要更新版本的 App 才能读取"
        case .bundleOnly: return "仅随包离线资料"
        case .coverageIncomplete: return "资料尚不完整"
        case .neverChecked: return "尚未检查过更新"
        }
    }
}

/// 读取错误分类（§16.1）。失败与「确认零条」必须能被上层区分。
nonisolated enum TimeHallReadError: String, Error, Sendable, Hashable {
    case offline
    case cloudUnavailable
    case permissionDenied
    case throttled
    case releaseUnreadable
    case releaseMissing
    case rootIndexHashMismatch
    case packHashMismatch
    case packDecodeFailed
    case packTooLarge
    case unsupportedEncoding
    case unsupportedSchema
    case missingDependency
    case invalidIdentifier
    case brandNotSupported
    case diskSpaceInsufficient
    case cancelled
    case unknown

    var labelZH: String {
        switch self {
        case .offline: return "当前无网络"
        case .cloudUnavailable: return "云端暂时不可用"
        case .permissionDenied: return "读取被拒绝"
        case .throttled: return "云端请求过于频繁，稍后重试"
        case .releaseUnreadable: return "资料需要更新版本的 App"
        case .releaseMissing: return "尚未发布任何资料"
        case .rootIndexHashMismatch: return "发布清单校验失败"
        case .packHashMismatch: return "数据包校验失败"
        case .packDecodeFailed: return "数据包解码失败"
        case .packTooLarge: return "数据包超出大小上限"
        case .unsupportedEncoding: return "不支持的压缩格式"
        case .unsupportedSchema: return "不支持的资料结构版本"
        case .missingDependency: return "缺少关联数据包"
        case .invalidIdentifier: return "资料标识非法"
        case .brandNotSupported: return "该品牌资料尚未收录"
        case .diskSpaceInsufficient: return "磁盘空间不足"
        case .cancelled: return "已取消"
        case .unknown: return "未知错误"
        }
    }

    /// 是否值得按退避策略重试
    var isRetryable: Bool {
        switch self {
        case .offline, .cloudUnavailable, .throttled, .packHashMismatch, .packDecodeFailed,
            .missingDependency, .diskSpaceInsufficient, .unknown:
            return true
        case .permissionDenied, .releaseUnreadable, .releaseMissing, .rootIndexHashMismatch,
            .packTooLarge, .unsupportedEncoding, .unsupportedSchema, .invalidIdentifier,
            .brandNotSupported, .cancelled:
            return false
        }
    }
}

/// 读取状态
nonisolated enum TimeHallReadStatus: Sendable, Equatable {
    /// 拿到了在新鲜度窗口内、覆盖范围确定的数据
    case ok
    /// 范围内明确为零条（有效结论，不是失败）
    case emptyConfirmed
    /// 有可展示数据，但已陈旧
    case stale(reason: TimeHallStaleReason)
    /// 有可展示数据，但覆盖不完整
    case partial(reason: TimeHallStaleReason)
    /// 完全失败，无可展示数据
    case failed(error: TimeHallReadError)

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    var labelZH: String {
        switch self {
        case .ok: return "已是最新"
        case .emptyConfirmed: return "暂无内容"
        case .stale(let reason): return reason.labelZH
        case .partial(let reason): return reason.labelZH
        case .failed(let error): return error.labelZH
        }
    }
}

/// 读取结果（§10.3）。
///
/// **不能只返回 `[Item]` 后让 UI 猜测「空数组代表哪种状态」。**
/// 必须携带数据来源、覆盖状态、最后成功校验时间、是否陈旧、是否需重试、是否有被撤回内容。
nonisolated struct TimeHallReadResult: Sendable {
    /// 可展示数据
    let fragment: TimeHallCatalogFragmentDTO
    let source: TimeHallDataSource
    let status: TimeHallReadStatus
    /// 分片 ID → 覆盖状态
    let partitionCoverage: [String: TimeHallCoverageStatus]
    /// 业务日 → 覆盖状态
    let dayCoverage: [String: TimeHallCoverageStatus]
    /// 最后一次成功校验（通过校验并安装 / 读种子）的时刻
    let lastValidatedAt: Date?
    /// 是否需要重试
    let shouldRetry: Bool
    /// 被撤回的实体集合；调用方不得再展示这些内容
    let withdrawnEntityIDs: Set<String>
    /// 已生效的发布序号
    let installedReleaseSeq: Int
    /// 本地是否已安装该请求所需的全部分片
    let isFullyInstalled: Bool
    /// 诊断信息（本地日志用，不得包含个人信息，§16.3）
    let diagnostics: [String]

    static func empty(brandID: String, error: TimeHallReadError) -> TimeHallReadResult {
        TimeHallReadResult(
            fragment: TimeHallCatalogFragmentDTO(),
            source: .none,
            status: .failed(error: error),
            partitionCoverage: [:],
            dayCoverage: [:],
            lastValidatedAt: nil,
            shouldRetry: error.isRetryable,
            withdrawnEntityIDs: [],
            installedReleaseSeq: 0,
            isFullyInstalled: false,
            diagnostics: ["brand=\(brandID)", "error=\(error.rawValue)"]
        )
    }
}

// MARK: - 缓存用量与配额

/// 缓存用量（§13.2 设置页展示）
nonisolated struct TimeHallCacheUsage: Sendable, Equatable {
    /// 图鉴数据（结构化数据包）
    var packBytes: Int64 = 0
    /// 图片缓存
    var mediaBytes: Int64 = 0
    /// 未完成或待验证下载
    var stagingBytes: Int64 = 0
    var packCount: Int = 0
    var mediaCount: Int = 0
    /// 最近检查时间
    var lastCheckedAt: Date?

    var downloadedBytes: Int64 { packBytes + mediaBytes }

    var totalBytes: Int64 { downloadedBytes + stagingBytes }

    static let empty = TimeHallCacheUsage()

    var packDescription: String { Self.format(packBytes) }
    var mediaDescription: String { Self.format(mediaBytes) }

    static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
    }
}

/// 缓存与下载上限（§12.3 下载安全、§13.4 空间回收）。
///
/// 这些是**初始预算**，需按目标机型与真实数据量调整，不是 Apple 配额。
nonisolated struct TimeHallCacheLimits: Sendable, Equatable {
    /// 结构化数据包磁盘预算
    var packBudgetBytes: Int64 = 100 * 1024 * 1024
    /// 磁盘媒体预算
    var mediaBudgetBytes: Int64 = 300 * 1024 * 1024
    /// 单个数据包压缩后上限
    var maxPackCompressedBytes: Int = 16 * 1024 * 1024
    /// 单个数据包解压后上限（客户端另设硬上限，不信任声明值）
    var maxPackUncompressedBytes: Int = 64 * 1024 * 1024
    /// 单个媒体文件上限
    var maxMediaBytes: Int = 8 * 1024 * 1024
    /// 解压膨胀比上限，防御压缩炸弹。
    ///
    /// 真正的主防线是 `maxPackUncompressedBytes`；本项只拦截量级明显异常的包，
    /// 因此留出较大余量，避免误伤高度重复的合法 JSON。
    var maxDecompressionRatio: Int = 512
    /// 单张图片最大像素数
    var maxMediaPixels: Int = 24_000_000

    static let `default` = TimeHallCacheLimits()
}

/// 新鲜度策略（§11.6）。
///
/// 均为**待测量调整的产品参数**，不是 Apple 配额或保证。
nonisolated struct TimeHallFreshnessPolicy: Sendable, Equatable {
    /// App 前台的发布头最短自动检查间隔
    var releaseCheckInterval: TimeInterval = 30 * 60
    /// 已知空结果重新检查节奏（与发布头一致）
    var knownEmptyRecheckInterval: TimeInterval = 30 * 60
    /// 同一数据包并行下载数
    var maxParallelPackDownloads: Int = 2
    /// 图片并行下载数
    var maxParallelMediaDownloads: Int = 4

    static let `default` = TimeHallFreshnessPolicy()
}

// MARK: - 读取接口（§10.3）

/// 已下载的数据包
nonisolated struct TimeHallDownloadedPack: Sendable {
    let recordName: String
    let payloadHash: String
    let encoding: String
    /// 已解码、待校验的原始 JSON 字节
    let jsonData: Data
    let compressedBytes: Int
    let uncompressedBytes: Int
}

/// 已下载的媒体
nonisolated struct TimeHallDownloadedMedia: Sendable {
    let recordName: String
    let contentHash: String
    let mimeType: String
    let bytes: Data
}

/// 已下载的根清单。
///
/// 必须同时带回**原始字节**，否则无法校验发布头声明的 `rootIndexHash`（§6.2 / §12.3）。
nonisolated struct TimeHallDownloadedRootIndex: Sendable {
    let rootIndex: TimeHallRootIndex
    let rawBytes: Data
    let declaredHash: String

    /// 摘要是否与发布头一致
    var isHashMatching: Bool {
        TimeHallPackCodec.sha256Hex(rawBytes) == declaredHash
    }
}

/// 公共只读接口。
///
/// **类型层面只有读取能力**：这里不提供 `savePublicEntry()` / `uploadLocalCatalog()` /
/// `moderateSubmission()`，普通用户客户端不具备对公共库任何写能力（§10.1 / §7.3）。
protocol TimeHallPublicReading: Sendable {
    /// 取发布头元数据（不含 Asset，§6.2）
    func fetchReleaseMetadata() async throws -> TimeHallReleaseMetadata
    /// 取根清单并带回原始字节用于摘要校验
    func fetchRootIndex(for release: TimeHallReleaseMetadata) async throws
        -> TimeHallDownloadedRootIndex
    /// 取一个不可变数据包
    func fetchPack(recordName: String) async throws -> TimeHallDownloadedPack
    /// 取一个已获许可的媒体资源
    func fetchMedia(recordName: String) async throws -> TimeHallDownloadedMedia
}

/// 统一读取接口
protocol TimeHallReading: Sendable {
    func read(_ request: TimeHallRequest) async -> TimeHallReadResult
    func refresh(_ request: TimeHallRequest) async -> TimeHallReadResult
}

/// 缓存维护接口（§13）
protocol TimeHallCacheMaintaining: Sendable {
    func usage() async -> TimeHallCacheUsage
    func clearDownloadedContent() async throws
}
