import Foundation

// MARK: - 协议常量
//
// 对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md
//   §6.1 容器与数据库、§6.2 `THRelease`、§6.3 `THDataPack`、§6.4 `THMedia`
//   §4.4 版本不等于日期、§4.5 稳定 ID
//
// 本文件只定义**发布层协议**，不触碰任何个人资产模型（衣橱 / 照片 / 手账 / 收藏）。

/// 内容分发协议通道。
///
/// `catalog-v1` 是内容分发协议通道，**不是** Xcode 的 Debug/Release 构建配置。
nonisolated enum TimeHallChannel {
    /// 首版唯一通道
    static let catalogV1 = "catalog-v1"

    /// 发布头固定 Record ID（§6.2：唯一生效发布头）
    static let releaseRecordName = "th.release.catalog-v1"

    /// 时光馆在公共库使用的三种正式 Record Type（§6 首版只建三种）
    static let recordTypeRelease = "THRelease"
    static let recordTypeDataPack = "THDataPack"
    static let recordTypeMedia = "THMedia"

    /// 首版唯一允许的载荷编码（§6.3）
    static let encodingJSONGzip = "json+gzip"
    /// 未压缩 JSON，仅用于本地 fixture 与排障，不作为线上发布格式
    static let encodingJSONPlain = "json"
}

/// 读取协议版本（§4.4）。
nonisolated enum TimeHallProtocol {
    /// 根清单 / 数据包结构版本。现有 Bundle 的 `version == 3` 是**业务数据集**版本，两者不可混用。
    static let schemaVersion = 1
    /// 本客户端实现的读取协议版本，用于比对发布头的 `minimumReaderVersion`。
    static let readerVersion = 1
}

// MARK: - 覆盖状态

/// 分片覆盖状态（§5.2）。
///
/// **空数组不是缺数据的同义词。** `empty` 表示「已检查完、明确为零条」的有效结果，
/// 带有版本与检查时间；请求失败、超时、解析异常一律**不得**映射为 `empty`。
nonisolated enum TimeHallCoverageStatus: String, Codable, Sendable, CaseIterable, Hashable {
    /// 声明范围已检查完（可能有条目，也可能为零）
    case complete
    /// 已检查完，明确为零条
    case empty
    /// 仅有部分资料，或来源分页未完成
    case partial
    /// 尚未检查或信息不足
    case unknown
    /// 运营当前不提供该范围
    case notSupported
    /// 该范围已撤回
    case withdrawn

    var labelZH: String {
        switch self {
        case .complete: return "已收录"
        case .empty: return "确认为空"
        case .partial: return "资料不完整"
        case .unknown: return "尚未检查"
        case .notSupported: return "暂未收录"
        case .withdrawn: return "已撤回"
        }
    }

    /// 是否已得出确定结论。确定结论不再循环补拉（§11.2 步骤 10）。
    var isConclusive: Bool {
        switch self {
        case .complete, .empty, .notSupported, .withdrawn: return true
        case .partial, .unknown: return false
        }
    }

    /// 该范围是否允许展示内容。`withdrawn` 不得从旧缓存或 Bundle 恢复显示（§5.2 / §14.1）。
    var allowsDisplay: Bool {
        switch self {
        case .withdrawn, .notSupported: return false
        case .complete, .empty, .partial, .unknown: return true
        }
    }
}

/// 来源覆盖边界（§5.3）。没有可验证依据时**不得**标记 `historicalComplete`。
nonisolated enum TimeHallSourceCoverage: String, Codable, Sendable, CaseIterable, Hashable {
    /// 只能枚举官网当前仍可枚举到的内容
    case currentlyEnumerable
    /// 运营挑选的精选集合，不是全量
    case curatedSelection
    /// 有可验证依据的历史完整集合
    case historicalComplete

    var labelZH: String {
        switch self {
        case .currentlyEnumerable: return "官网当前可枚举"
        case .curatedSelection: return "运营精选"
        case .historicalComplete: return "历史完整"
        }
    }
}

// MARK: - 实体类型与稳定身份

/// 时光馆的公共内容实体类型（§4.5）。
nonisolated enum TimeHallEntityType: String, Codable, Sendable, CaseIterable, Hashable {
    case brand
    case event
    case commerceProduct = "commerce-product"
    case commerceSnapshot = "commerce-snapshot"
    case catalogue
    case archiveCatalogue = "archive-catalogue"
    case item
    case coordinate
    case story
    case historyEntry = "history-entry"

    var labelZH: String {
        switch self {
        case .brand: return "品牌"
        case .event: return "资讯与活动"
        case .commerceProduct: return "在售商品"
        case .commerceSnapshot: return "商品快照"
        case .catalogue: return "目录"
        case .archiveCatalogue: return "官方目录"
        case .item: return "目录展品"
        case .coordinate: return "搭配"
        case .story: return "专题"
        case .historyEntry: return "品牌史"
        }
    }
}

/// 统一身份映射（§4.5）。
///
/// 规范：`canonicalEntityID = brandID / entityType / stableSourceID`
///
/// **本实现的工程决策**：`stableSourceID` 直接沿用现有 DTO 的 `id`
/// （`news-<officialID>`、`coordinate-<officialID>`、`official-catalog-<officialID>` 等）。
/// 理由是这些 `id` 由官方 ID 派生、本身就是稳定来源 ID，
/// 因此**旧收藏 `timeHall.treasured.v1` 里的 ID 无需迁移**，不会因新协议失效。
/// 设计文档 §4.5 的 `product-code-abc` 只是格式示例，不代表必须改成另一套字符串。
nonisolated enum TimeHallCanonicalID {
    static let separator: Character = "/"

    static func make(
        brandID: String,
        entityType: TimeHallEntityType,
        stableSourceID: String
    ) -> String {
        "\(brandID)\(separator)\(entityType.rawValue)\(separator)\(stableSourceID)"
    }

    /// canonical ID 必须恰好是三段，且每一段非空、不含分隔符。
    static func isValid(_ value: String) -> Bool {
        let parts = value.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        guard parts.allSatisfy({ !$0.isEmpty }) else { return false }
        guard TimeHallEntityType(rawValue: String(parts[1])) != nil else { return false }
        return true
    }

    static func brandID(from value: String) -> String? {
        guard isValid(value) else { return nil }
        return String(value.split(separator: separator)[0])
    }

    static func entityType(from value: String) -> TimeHallEntityType? {
        guard isValid(value) else { return nil }
        return TimeHallEntityType(rawValue: String(value.split(separator: separator)[1]))
    }
}

// MARK: - 品牌描述

/// 品牌级描述（§5.1 品牌基本信息按品牌分片；§4.3 来源业务时区）。
nonisolated struct TimeHallBrandDescriptor: Codable, Sendable, Hashable, Identifiable {
    let brandID: String
    let displayName: String
    /// IANA 时区标识，用于把来源业务日期映射为分片 ID（§4.3）。不得用设备当前时区替代。
    let sourceTimeZone: String
    let sourceCoverage: TimeHallSourceCoverage
    /// 对用户可理解的范围说明；不允许留空，空说明无法如实告知用户边界（§5.3）。
    let coverageDescription: String

    var id: String { brandID }

    init(
        brandID: String,
        displayName: String,
        sourceTimeZone: String,
        sourceCoverage: TimeHallSourceCoverage,
        coverageDescription: String
    ) {
        self.brandID = brandID
        self.displayName = displayName
        self.sourceTimeZone = sourceTimeZone
        self.sourceCoverage = sourceCoverage
        self.coverageDescription = coverageDescription
    }

    private enum CodingKeys: String, CodingKey {
        case brandID, displayName, sourceTimeZone, sourceCoverage, coverageDescription
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brandID = try c.decodeIfPresent(String.self, forKey: .brandID) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        sourceTimeZone = try c.decodeIfPresent(String.self, forKey: .sourceTimeZone) ?? ""
        sourceCoverage =
            try c.decodeIfPresent(TimeHallSourceCoverage.self, forKey: .sourceCoverage)
            ?? .curatedSelection
        coverageDescription =
            try c.decodeIfPresent(String.self, forKey: .coverageDescription) ?? ""
    }

    var businessTimeZone: TimeZone {
        TimeZone(identifier: sourceTimeZone) ?? TimeZone(identifier: "Asia/Tokyo")
            ?? TimeZone(secondsFromGMT: 9 * 3600)!
    }
}

// MARK: - 分片描述

/// 分片描述（§5.1 分片策略、§5.2 覆盖状态、§6.7 根清单示例）。
nonisolated struct TimeHallPartitionDescriptor: Codable, Sendable, Hashable, Identifiable {
    let partitionID: String
    let brandID: String
    let entityType: TimeHallEntityType
    /// 该分片的修订号（§4.4）。当天可以发布多次。
    let partitionRevision: Int
    let coverageStatus: TimeHallCoverageStatus
    /// 已检查来源至何时（§4.2）。不得当作「数据必然覆盖所有历史」的证明。
    let checkedThrough: String?
    /// 逻辑覆盖按天（§5.1）。某日 `empty` 是有效结论，不代表永久结论。
    let dayCoverage: [String: TimeHallCoverageStatus]
    let packRecordName: String
    let payloadHash: String
    let recordCount: Int
    /// 关联完整性（§6.7）：引用了其它包时必须显式声明，缺依赖不得让整页崩溃。
    let dependencyPackRecordNames: [String]

    var id: String { partitionID }

    init(
        partitionID: String,
        brandID: String,
        entityType: TimeHallEntityType,
        partitionRevision: Int,
        coverageStatus: TimeHallCoverageStatus,
        checkedThrough: String?,
        dayCoverage: [String: TimeHallCoverageStatus],
        packRecordName: String,
        payloadHash: String,
        recordCount: Int,
        dependencyPackRecordNames: [String]
    ) {
        self.partitionID = partitionID
        self.brandID = brandID
        self.entityType = entityType
        self.partitionRevision = partitionRevision
        self.coverageStatus = coverageStatus
        self.checkedThrough = checkedThrough
        self.dayCoverage = dayCoverage
        self.packRecordName = packRecordName
        self.payloadHash = payloadHash
        self.recordCount = recordCount
        self.dependencyPackRecordNames = dependencyPackRecordNames
    }

    private enum CodingKeys: String, CodingKey {
        case partitionID, brandID, entityType, partitionRevision, coverageStatus
        case checkedThrough, dayCoverage, packRecordName, payloadHash, recordCount
        case dependencyPackRecordNames
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        partitionID = try c.decodeIfPresent(String.self, forKey: .partitionID) ?? ""
        brandID = try c.decodeIfPresent(String.self, forKey: .brandID) ?? ""
        entityType =
            try c.decodeIfPresent(TimeHallEntityType.self, forKey: .entityType) ?? .event
        partitionRevision = try c.decodeIfPresent(Int.self, forKey: .partitionRevision) ?? 0
        coverageStatus =
            try c.decodeIfPresent(TimeHallCoverageStatus.self, forKey: .coverageStatus) ?? .unknown
        checkedThrough = try c.decodeIfPresent(String.self, forKey: .checkedThrough)
        dayCoverage =
            try c.decodeIfPresent([String: TimeHallCoverageStatus].self, forKey: .dayCoverage)
            ?? [:]
        packRecordName = try c.decodeIfPresent(String.self, forKey: .packRecordName) ?? ""
        payloadHash = try c.decodeIfPresent(String.self, forKey: .payloadHash) ?? ""
        recordCount = try c.decodeIfPresent(Int.self, forKey: .recordCount) ?? 0
        dependencyPackRecordNames =
            try c.decodeIfPresent([String].self, forKey: .dependencyPackRecordNames) ?? []
    }

    /// 按业务时区排序的日覆盖键（`yyyy-MM-dd`）
    var sortedDayKeys: [String] { dayCoverage.keys.sorted() }

    func coverageStatus(forDay dayKey: String) -> TimeHallCoverageStatus? {
        dayCoverage[dayKey]
    }
}

// MARK: - 撤回

/// 撤回条目（§14.1）。撤回优先于所有展示来源，可作用于云端缓存与 Bundle 的展示投影。
///
/// 记录中**不得**包含内部审核说明、投诉者资料或其他非公开信息（§14.1）。
nonisolated struct TimeHallWithdrawal: Codable, Sendable, Hashable {
    let canonicalEntityID: String
    let withdrawnAt: String
    /// 按媒体内容摘要撤回（§14.1 允许用稳定实体 ID 或媒体 hash）
    let mediaHashes: [String]

    init(canonicalEntityID: String, withdrawnAt: String, mediaHashes: [String] = []) {
        self.canonicalEntityID = canonicalEntityID
        self.withdrawnAt = withdrawnAt
        self.mediaHashes = mediaHashes
    }

    private enum CodingKeys: String, CodingKey {
        case canonicalEntityID, withdrawnAt, mediaHashes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canonicalEntityID = try c.decodeIfPresent(String.self, forKey: .canonicalEntityID) ?? ""
        withdrawnAt = try c.decodeIfPresent(String.self, forKey: .withdrawnAt) ?? ""
        mediaHashes = try c.decodeIfPresent([String].self, forKey: .mediaHashes) ?? []
    }
}

// MARK: - 根清单

/// 根清单（§6.7）。由 `THRelease.rootIndexAsset` 指向，列出分片与数据包引用。
nonisolated struct TimeHallRootIndex: Codable, Sendable, Hashable {
    let schemaVersion: Int
    let releaseSeq: Int
    let publishedAt: String
    let revocationEpoch: Int
    let brands: [TimeHallBrandDescriptor]
    let partitions: [TimeHallPartitionDescriptor]
    let withdrawals: [TimeHallWithdrawal]

    init(
        schemaVersion: Int = TimeHallProtocol.schemaVersion,
        releaseSeq: Int,
        publishedAt: String,
        revocationEpoch: Int,
        brands: [TimeHallBrandDescriptor],
        partitions: [TimeHallPartitionDescriptor],
        withdrawals: [TimeHallWithdrawal]
    ) {
        self.schemaVersion = schemaVersion
        self.releaseSeq = releaseSeq
        self.publishedAt = publishedAt
        self.revocationEpoch = revocationEpoch
        self.brands = brands
        self.partitions = partitions
        self.withdrawals = withdrawals
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, releaseSeq, publishedAt, revocationEpoch, brands, partitions, withdrawals
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        releaseSeq = try c.decodeIfPresent(Int.self, forKey: .releaseSeq) ?? 0
        publishedAt = try c.decodeIfPresent(String.self, forKey: .publishedAt) ?? ""
        revocationEpoch = try c.decodeIfPresent(Int.self, forKey: .revocationEpoch) ?? 0
        brands = try c.decodeIfPresent([TimeHallBrandDescriptor].self, forKey: .brands) ?? []
        partitions =
            try c.decodeIfPresent([TimeHallPartitionDescriptor].self, forKey: .partitions) ?? []
        withdrawals =
            try c.decodeIfPresent([TimeHallWithdrawal].self, forKey: .withdrawals) ?? []
    }

    func brand(_ brandID: String) -> TimeHallBrandDescriptor? {
        brands.first { $0.brandID == brandID }
    }

    func partition(partitionID: String) -> TimeHallPartitionDescriptor? {
        partitions.first { $0.partitionID == partitionID }
    }

    /// 该品牌的全部已撤回实体 ID
    func withdrawnEntityIDs(brandID: String? = nil) -> Set<String> {
        var result: Set<String> = []
        for withdrawal in withdrawals {
            if let brandID, TimeHallCanonicalID.brandID(from: withdrawal.canonicalEntityID) != brandID {
                continue
            }
            result.insert(withdrawal.canonicalEntityID)
        }
        return result
    }

    /// 已撤回的媒体内容摘要
    func withdrawnMediaHashes() -> Set<String> {
        Set(withdrawals.flatMap(\.mediaHashes))
    }

    /// 选中某品牌、某批实体类型的分片
    func partitions(
        brandID: String,
        entityTypes: Set<TimeHallEntityType>
    ) -> [TimeHallPartitionDescriptor] {
        partitions.filter { $0.brandID == brandID && entityTypes.contains($0.entityType) }
    }
}

// MARK: - 发布头元数据

/// 发布头元数据（§6.2）。
///
/// 普通读取先只取**不含 Asset** 的元数据，确认版本改变后才取根清单（§6.2）。
nonisolated struct TimeHallReleaseMetadata: Codable, Sendable, Hashable {
    let recordName: String
    let releaseSeq: Int
    let schemaVersion: Int
    let publishedAt: String
    /// 根清单文件 SHA-256
    let rootIndexHash: String
    /// 撤回控制版本，单调递增（§4.4 / §14.1）
    let revocationEpoch: Int
    /// 最小读取协议版本。**不用于下载执行代码**（§6.2）。
    let minimumReaderVersion: Int
    let previousReleaseSeq: Int
    /// CloudKit 自身的 `recordChangeTag`，用于并发控制；不手工伪造（§6.2 / §9.3）。
    let changeTag: String?

    init(
        recordName: String = TimeHallChannel.releaseRecordName,
        releaseSeq: Int,
        schemaVersion: Int,
        publishedAt: String,
        rootIndexHash: String,
        revocationEpoch: Int,
        minimumReaderVersion: Int,
        previousReleaseSeq: Int,
        changeTag: String?
    ) {
        self.recordName = recordName
        self.releaseSeq = releaseSeq
        self.schemaVersion = schemaVersion
        self.publishedAt = publishedAt
        self.rootIndexHash = rootIndexHash
        self.revocationEpoch = revocationEpoch
        self.minimumReaderVersion = minimumReaderVersion
        self.previousReleaseSeq = previousReleaseSeq
        self.changeTag = changeTag
    }

    /// 客户端是否具备读取该发布的能力。不支持时提示「资料更新需要新版读取能力」，
    /// 而不是直接失败（§16.1）。
    var isReadableByCurrentClient: Bool {
        minimumReaderVersion <= TimeHallProtocol.readerVersion
    }

    /// 同一条发布链上的新旧判断。不能只用日期判断新旧（§4.4）。
    func supersedes(_ other: TimeHallReleaseMetadata?) -> Bool {
        guard let other else { return true }
        if releaseSeq != other.releaseSeq { return releaseSeq > other.releaseSeq }
        return revocationEpoch > other.revocationEpoch
    }
}

// MARK: - 数据包内容

/// 一个数据包内的结构化内容。
///
/// 沿用现有 V3 DTO（§17.2 / §6.5），**不**把所有实体压成一个通用投稿模型（§1.1）。
/// 所有数组都可缺省：`partial` 数据包允许只带一部分实体类型。
nonisolated struct TimeHallCatalogFragmentDTO: Codable, Sendable {
    var timelineYears: [TimeHallYearRecordDTO]
    var archiveCatalogues: [TimeHallArchiveCatalogueDTO]
    var catalogues: [TimeHallCatalogueDTO]
    var items: [TimeHallItemDTO]
    var commerceSnapshots: [TimeHallCommerceSnapshotDTO]
    var commerceItems: [TimeHallCommerceItemDTO]
    var coordinates: [TimeHallCoordinateDTO]
    var stories: [TimeHallStoryDTO]
    var events: [TimeHallEventDTO]
    var historyEntries: [TimeHallHistoryEntryDTO]

    init(
        timelineYears: [TimeHallYearRecordDTO] = [],
        archiveCatalogues: [TimeHallArchiveCatalogueDTO] = [],
        catalogues: [TimeHallCatalogueDTO] = [],
        items: [TimeHallItemDTO] = [],
        commerceSnapshots: [TimeHallCommerceSnapshotDTO] = [],
        commerceItems: [TimeHallCommerceItemDTO] = [],
        coordinates: [TimeHallCoordinateDTO] = [],
        stories: [TimeHallStoryDTO] = [],
        events: [TimeHallEventDTO] = [],
        historyEntries: [TimeHallHistoryEntryDTO] = []
    ) {
        self.timelineYears = timelineYears
        self.archiveCatalogues = archiveCatalogues
        self.catalogues = catalogues
        self.items = items
        self.commerceSnapshots = commerceSnapshots
        self.commerceItems = commerceItems
        self.coordinates = coordinates
        self.stories = stories
        self.events = events
        self.historyEntries = historyEntries
    }

    private enum CodingKeys: String, CodingKey {
        case timelineYears, archiveCatalogues, catalogues, items
        case commerceSnapshots, commerceItems, coordinates, stories, events, historyEntries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timelineYears =
            try c.decodeIfPresent([TimeHallYearRecordDTO].self, forKey: .timelineYears) ?? []
        archiveCatalogues =
            try c.decodeIfPresent([TimeHallArchiveCatalogueDTO].self, forKey: .archiveCatalogues)
            ?? []
        catalogues =
            try c.decodeIfPresent([TimeHallCatalogueDTO].self, forKey: .catalogues) ?? []
        items = try c.decodeIfPresent([TimeHallItemDTO].self, forKey: .items) ?? []
        commerceSnapshots =
            try c.decodeIfPresent([TimeHallCommerceSnapshotDTO].self, forKey: .commerceSnapshots)
            ?? []
        commerceItems =
            try c.decodeIfPresent([TimeHallCommerceItemDTO].self, forKey: .commerceItems) ?? []
        coordinates =
            try c.decodeIfPresent([TimeHallCoordinateDTO].self, forKey: .coordinates) ?? []
        stories = try c.decodeIfPresent([TimeHallStoryDTO].self, forKey: .stories) ?? []
        events = try c.decodeIfPresent([TimeHallEventDTO].self, forKey: .events) ?? []
        historyEntries =
            try c.decodeIfPresent([TimeHallHistoryEntryDTO].self, forKey: .historyEntries) ?? []
    }

    var totalEntityCount: Int {
        timelineYears.count + archiveCatalogues.count + catalogues.count + items.count
            + commerceSnapshots.count + commerceItems.count + coordinates.count + stories.count
            + events.count + historyEntries.count
    }

    var isEmpty: Bool { totalEntityCount == 0 }

    /// 合并另一个分片内容。用于把多个数据包拼成一个可展示快照。
    mutating func merge(_ other: TimeHallCatalogFragmentDTO) {
        timelineYears = Self.deduplicated(timelineYears + other.timelineYears, by: \.year)
        archiveCatalogues = Self.deduplicated(
            archiveCatalogues + other.archiveCatalogues, by: \.id)
        catalogues = Self.deduplicated(catalogues + other.catalogues, by: \.id)
        items = Self.deduplicated(items + other.items, by: \.id)
        commerceSnapshots = Self.deduplicated(
            commerceSnapshots + other.commerceSnapshots, by: \.id)
        commerceItems = Self.deduplicated(commerceItems + other.commerceItems, by: \.id)
        coordinates = Self.deduplicated(coordinates + other.coordinates, by: \.id)
        stories = Self.deduplicated(stories + other.stories, by: \.id)
        events = Self.deduplicated(events + other.events, by: \.id)
        historyEntries = Self.deduplicated(historyEntries + other.historyEntries, by: \.id)
    }

    /// `later` 覆盖 `earlier`，保留 `earlier` 中不在 `later` 覆盖范围内的条目（§11.5）。
    func replacing(_ earlier: TimeHallCatalogFragmentDTO) -> TimeHallCatalogFragmentDTO {
        var result = self
        result.merge(earlier)
        return result
    }

    private static func deduplicated<T, K: Hashable>(_ values: [T], by key: KeyPath<T, K>) -> [T] {
        var seen: Set<K> = []
        var result: [T] = []
        for value in values {
            let k = value[keyPath: key]
            if seen.insert(k).inserted { result.append(value) }
        }
        return result
    }

    /// 移除被撤回的实体（§14.1）。撤回优先于所有展示来源，
    /// 且清缓存 / 手动刷新 / 离线回退都**不得**让被撤回内容复活。
    ///
    /// `timelineYears` 以年份为身份，没有稳定来源 ID，因此不参与实体级撤回；
    /// 需要撤回年度卡片时由发布侧发更高 `revocationEpoch` 的清洁替代包处理。
    func filteringWithdrawn(
        canonicalIDs: Set<String>,
        brandID: String
    ) -> TimeHallCatalogFragmentDTO {
        guard !canonicalIDs.isEmpty else { return self }
        var result = self
        result.events.removeAll { canonicalIDs.contains(canonicalID(brandID, .event, $0.id)) }
        result.commerceItems.removeAll {
            canonicalIDs.contains(canonicalID(brandID, .commerceProduct, $0.id))
        }
        result.commerceSnapshots.removeAll {
            canonicalIDs.contains(canonicalID(brandID, .commerceSnapshot, $0.id))
        }
        result.catalogues.removeAll { canonicalIDs.contains(canonicalID(brandID, .catalogue, $0.id)) }
        result.archiveCatalogues.removeAll {
            canonicalIDs.contains(canonicalID(brandID, .archiveCatalogue, $0.id))
        }
        result.items.removeAll { canonicalIDs.contains(canonicalID(brandID, .item, $0.id)) }
        result.coordinates.removeAll {
            canonicalIDs.contains(canonicalID(brandID, .coordinate, $0.id))
        }
        result.stories.removeAll { canonicalIDs.contains(canonicalID(brandID, .story, $0.id)) }
        result.historyEntries.removeAll {
            canonicalIDs.contains(canonicalID(brandID, .historyEntry, $0.id))
        }
        // 被撤回的目录 / 展品可能仍被目录的 itemIds 引用，
        // 保留引用但由 UI 层按「关联条目未下载」占位处理，不因缺依赖整页崩溃。
        return result
    }

    private func canonicalID(
        _ brandID: String,
        _ entityType: TimeHallEntityType,
        _ stableSourceID: String
    ) -> String {
        TimeHallCanonicalID.make(
            brandID: brandID, entityType: entityType, stableSourceID: stableSourceID)
    }

    /// 该分片内所有实体的 canonical ID（撤回过筛与唯一性校验用）。
    func canonicalEntityIDs(brandID: String) -> [String] {
        var result: [String] = []
        result += events.map {
            TimeHallCanonicalID.make(brandID: brandID, entityType: .event, stableSourceID: $0.id)
        }
        result += commerceItems.map {
            TimeHallCanonicalID.make(
                brandID: brandID, entityType: .commerceProduct, stableSourceID: $0.id)
        }
        result += commerceSnapshots.map {
            TimeHallCanonicalID.make(
                brandID: brandID, entityType: .commerceSnapshot, stableSourceID: $0.id)
        }
        result += catalogues.map {
            TimeHallCanonicalID.make(brandID: brandID, entityType: .catalogue, stableSourceID: $0.id)
        }
        result += archiveCatalogues.map {
            TimeHallCanonicalID.make(
                brandID: brandID, entityType: .archiveCatalogue, stableSourceID: $0.id)
        }
        result += items.map {
            TimeHallCanonicalID.make(brandID: brandID, entityType: .item, stableSourceID: $0.id)
        }
        result += coordinates.map {
            TimeHallCanonicalID.make(
                brandID: brandID, entityType: .coordinate, stableSourceID: $0.id)
        }
        result += stories.map {
            TimeHallCanonicalID.make(brandID: brandID, entityType: .story, stableSourceID: $0.id)
        }
        result += historyEntries.map {
            TimeHallCanonicalID.make(
                brandID: brandID, entityType: .historyEntry, stableSourceID: $0.id)
        }
        return result
    }
}

/// 数据包负载（§6.3）。传输包中是**纯数据**，不含脚本、动态代码或可任意执行的表达式。
nonisolated struct TimeHallPackPayload: Codable, Sendable {
    let schemaVersion: Int
    let partitionID: String
    let brandID: String
    let entityType: TimeHallEntityType
    let partitionRevision: Int
    let coverageStatus: TimeHallCoverageStatus
    let checkedThrough: String?
    let dayCoverage: [String: TimeHallCoverageStatus]
    let records: TimeHallCatalogFragmentDTO

    init(
        schemaVersion: Int = TimeHallProtocol.schemaVersion,
        partitionID: String,
        brandID: String,
        entityType: TimeHallEntityType,
        partitionRevision: Int,
        coverageStatus: TimeHallCoverageStatus,
        checkedThrough: String?,
        dayCoverage: [String: TimeHallCoverageStatus],
        records: TimeHallCatalogFragmentDTO
    ) {
        self.schemaVersion = schemaVersion
        self.partitionID = partitionID
        self.brandID = brandID
        self.entityType = entityType
        self.partitionRevision = partitionRevision
        self.coverageStatus = coverageStatus
        self.checkedThrough = checkedThrough
        self.dayCoverage = dayCoverage
        self.records = records
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, partitionID, brandID, entityType, partitionRevision
        case coverageStatus, checkedThrough, dayCoverage, records
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        partitionID = try c.decodeIfPresent(String.self, forKey: .partitionID) ?? ""
        brandID = try c.decodeIfPresent(String.self, forKey: .brandID) ?? ""
        entityType = try c.decodeIfPresent(TimeHallEntityType.self, forKey: .entityType) ?? .event
        partitionRevision = try c.decodeIfPresent(Int.self, forKey: .partitionRevision) ?? 0
        coverageStatus =
            try c.decodeIfPresent(TimeHallCoverageStatus.self, forKey: .coverageStatus) ?? .unknown
        checkedThrough = try c.decodeIfPresent(String.self, forKey: .checkedThrough)
        dayCoverage =
            try c.decodeIfPresent([String: TimeHallCoverageStatus].self, forKey: .dayCoverage) ?? [:]
        records = try c.decodeIfPresent(TimeHallCatalogFragmentDTO.self, forKey: .records) ?? TimeHallCatalogFragmentDTO()
    }

    /// 自洽性：包内身份必须与根清单描述的分片一致。
    func matches(_ descriptor: TimeHallPartitionDescriptor) -> Bool {
        partitionID == descriptor.partitionID
            && brandID == descriptor.brandID
            && entityType == descriptor.entityType
            && partitionRevision == descriptor.partitionRevision
    }
}

// MARK: - 本地安装状态

/// 已安装的数据包记录（§11.2 步骤 14 / §13.1）。
///
/// `knownRemoteRevision` 与 `installedRevision` 必须分开保存：
/// 根清单下载成功**不**表示对应数据包已安装。
nonisolated struct TimeHallInstalledPack: Codable, Sendable, Hashable {
    let partitionID: String
    let brandID: String
    let entityType: TimeHallEntityType
    let packRecordName: String
    let payloadHash: String
    let partitionRevision: Int
    let coverageStatus: TimeHallCoverageStatus
    let checkedThrough: String?
    let dayCoverage: [String: TimeHallCoverageStatus]
    let recordCount: Int
    let installedAt: Date
    /// 安装时的缓存 generation，用于清理竞态判定（§13.3）
    let generation: UInt64
}

/// 已应用的撤回控制状态（§13.1：最小控制状态，保存在 Application Support）。
nonisolated struct TimeHallControlState: Codable, Sendable, Hashable {
    var revocationEpoch: Int
    var withdrawnEntityIDs: [String]
    var withdrawnMediaHashes: [String]
    var disabledBrandIDs: [String]
    var lastCheckedAt: Date?
    var knownReleaseSeq: Int
    var knownRootIndexHash: String

    static let empty = TimeHallControlState(
        revocationEpoch: 0,
        withdrawnEntityIDs: [],
        withdrawnMediaHashes: [],
        disabledBrandIDs: [],
        lastCheckedAt: nil,
        knownReleaseSeq: 0,
        knownRootIndexHash: ""
    )

    private enum CodingKeys: String, CodingKey {
        case revocationEpoch, withdrawnEntityIDs, withdrawnMediaHashes
        case disabledBrandIDs, lastCheckedAt, knownReleaseSeq, knownRootIndexHash
    }

    init(
        revocationEpoch: Int,
        withdrawnEntityIDs: [String],
        withdrawnMediaHashes: [String],
        disabledBrandIDs: [String],
        lastCheckedAt: Date?,
        knownReleaseSeq: Int,
        knownRootIndexHash: String
    ) {
        self.revocationEpoch = revocationEpoch
        self.withdrawnEntityIDs = withdrawnEntityIDs
        self.withdrawnMediaHashes = withdrawnMediaHashes
        self.disabledBrandIDs = disabledBrandIDs
        self.lastCheckedAt = lastCheckedAt
        self.knownReleaseSeq = knownReleaseSeq
        self.knownRootIndexHash = knownRootIndexHash
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revocationEpoch = try c.decodeIfPresent(Int.self, forKey: .revocationEpoch) ?? 0
        withdrawnEntityIDs =
            try c.decodeIfPresent([String].self, forKey: .withdrawnEntityIDs) ?? []
        withdrawnMediaHashes =
            try c.decodeIfPresent([String].self, forKey: .withdrawnMediaHashes) ?? []
        disabledBrandIDs = try c.decodeIfPresent([String].self, forKey: .disabledBrandIDs) ?? []
        lastCheckedAt = try c.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        knownReleaseSeq = try c.decodeIfPresent(Int.self, forKey: .knownReleaseSeq) ?? 0
        knownRootIndexHash = try c.decodeIfPresent(String.self, forKey: .knownRootIndexHash) ?? ""
    }

    var withdrawnSet: Set<String> { Set(withdrawnEntityIDs) }
    var withdrawnMediaHashSet: Set<String> { Set(withdrawnMediaHashes) }

    /// 合并更高版本的撤回控制。撤回只增不减，回滚也不能让撤回内容复活（§9.4 / §14.1）。
    func merging(_ other: TimeHallControlState) -> TimeHallControlState {
        var result = self
        result.revocationEpoch = max(revocationEpoch, other.revocationEpoch)
        result.withdrawnEntityIDs = Array(Set(withdrawnEntityIDs).union(other.withdrawnEntityIDs))
            .sorted()
        result.withdrawnMediaHashes = Array(
            Set(withdrawnMediaHashes).union(other.withdrawnMediaHashes)
        ).sorted()
        result.disabledBrandIDs = Array(Set(disabledBrandIDs).union(other.disabledBrandIDs)).sorted()
        result.lastCheckedAt = other.lastCheckedAt ?? lastCheckedAt
        if other.knownReleaseSeq >= knownReleaseSeq {
            result.knownReleaseSeq = other.knownReleaseSeq
            result.knownRootIndexHash = other.knownRootIndexHash
        }
        return result
    }
}
