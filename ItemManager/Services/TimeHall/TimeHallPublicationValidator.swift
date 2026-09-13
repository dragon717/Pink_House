import Foundation

// MARK: - 校验层次
//
// 对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md §1.2 B/C。
//
// 现有实现把「单品牌整馆验收规则」直接当成通用契约（`version == 3`、`1972...2026`、
// `brand == "PINK HOUSE"`）。这些规则对当前 PINK HOUSE 历史数据集仍然有效，
// 但**不能**作为多品牌、每日空结果、云端增量包的通用校验。
//
// 因此拆成三层：
//   1. structural   通用结构：与品牌无关，任何实体集合都必须满足
//   2. partition    分片契约：分片 ID、hash、字节数、实体类型、覆盖状态自洽
//   3. brandDataset 品牌数据集：现有 PINK HOUSE 整馆规则，保留不动

/// 校验层次
nonisolated enum TimeHallValidationLayer: String, Sendable, Hashable, CaseIterable {
    case structural
    case partition
    case brandDataset

    var labelZH: String {
        switch self {
        case .structural: return "通用结构"
        case .partition: return "分片契约"
        case .brandDataset: return "品牌数据集"
        }
    }
}

/// 单条校验问题
nonisolated struct TimeHallValidationIssue: Sendable, Hashable {
    let layer: TimeHallValidationLayer
    /// 机器可读的错误码
    let code: String
    /// 相关实体 ID（可能为空）
    let entityID: String?
    let message: String

    init(layer: TimeHallValidationLayer, code: String, entityID: String? = nil, message: String) {
        self.layer = layer
        self.code = code
        self.entityID = entityID
        self.message = message
    }
}

/// 校验结果
nonisolated struct TimeHallValidationOutcome: Sendable {
    let issues: [TimeHallValidationIssue]

    static let valid = TimeHallValidationOutcome(issues: [])

    var isValid: Bool { issues.isEmpty }

    func issues(in layer: TimeHallValidationLayer) -> [TimeHallValidationIssue] {
        issues.filter { $0.layer == layer }
    }

    var summary: String {
        guard !isValid else { return "校验通过" }
        return issues.map { "[\($0.layer.rawValue)] \($0.code)" }.joined(separator: ", ")
    }

    static func merging(_ outcomes: [TimeHallValidationOutcome]) -> TimeHallValidationOutcome {
        TimeHallValidationOutcome(issues: outcomes.flatMap(\.issues))
    }
}

// MARK: - 底层谓词（与品牌无关，供三层共用）

/// 数据规则谓词集合。原属 `TimeHallCatalogStore` 的私有工具方法，抽为共享层，
/// 让 Release / DataPack / Bundle 三条路径使用同一套判定。
nonisolated enum TimeHallDatasetRules {
    static func duplicateValues(_ values: [String]) -> [String] {
        Dictionary(grouping: values, by: { $0 })
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
    }

    static let officialHost = "pinkhouse-webshop.jp"
    static let melroseHost = "www.melrose.co.jp"

    static func isOfficialURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme == "https" && url.host == officialHost
    }

    static func isOfficialSourceURL(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host else {
            return false
        }
        return host == officialHost || host == melroseHost
    }

    static func isOfficialImageURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme == "https"
            && url.host == officialHost
            && url.path.hasPrefix("/photo/catalog/")
            && url.pathExtension.lowercased() == "jpg"
    }

    static func isOfficialCommerceImageURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme == "https"
            && url.host == officialHost
            && url.path.hasPrefix("/photo/")
            && url.pathExtension.lowercased() == "jpg"
    }

    static func isOfficialCoordinateImageURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme == "https"
            && url.host == officialHost
            && url.path.hasPrefix("/photo/coordinate/")
            && url.pathExtension.lowercased() == "jpg"
    }

    static func isOfficialStoryImageURL(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host else {
            return false
        }
        if host == officialHost {
            return url.path.hasPrefix("/photo/")
        }
        return host == melroseHost
            && url.path.hasPrefix("/wp-content/themes/melrose/assets/images/50th/")
    }

    static func isOfficialNewsImageURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme == "https"
            && url.host == officialHost
            && url.path.hasPrefix("/photo/news/")
            && ["jpg", "jpeg", "png", "webp"].contains(url.pathExtension.lowercased())
    }

    static func isOfficialHistoryImageURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme == "https"
            && url.host == melroseHost
            && url.path.hasPrefix("/wp-content/themes/melrose/assets/images/about/history/")
    }

    /// 严格的 `yyyy-MM-dd`（不宽松、固定 POSIX locale）
    static func isISODate(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value) != nil
    }

    /// SHA-256 十六进制摘要
    static func isSHA256Hex(_ value: String) -> Bool {
        guard value.count == 64 else { return false }
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        return value.unicodeScalars.allSatisfy { hex.contains($0) }
    }
}

// MARK: - 发布校验器

nonisolated enum TimeHallPublicationValidator {

    // MARK: 第一层：通用结构校验

    /// 通用结构校验。与品牌无关，任何分片内容都必须满足。
    ///
    /// 这一层通过之后才允许把数据交给 UI（§1.2 B：先验证，通过后才切换为可展示数据）。
    ///
    /// - Parameter declaredEntityType: 分片声明的实体类型；传 `nil` 表示校验的是**合并后的展示快照**，
    ///   此时跳过「条目数必须与覆盖状态匹配」这一条分片级规则。
    static func validateStructural(
        _ fragment: TimeHallCatalogFragmentDTO,
        declaredEntityType: TimeHallEntityType?,
        brandID: String,
        coverageStatus: TimeHallCoverageStatus
    ) -> TimeHallValidationOutcome {
        var issues: [TimeHallValidationIssue] = []

        func fail(_ code: String, _ id: String? = nil, _ message: String) {
            issues.append(
                TimeHallValidationIssue(
                    layer: .structural, code: code, entityID: id, message: message))
        }

        if brandID.isEmpty {
            fail("brandID.empty", nil, "brandID 不得为空")
        }

        if let declaredEntityType {
            let declaredCount = entityCount(of: declaredEntityType, in: fragment)
            switch coverageStatus {
            case .empty:
                if !fragment.isEmpty {
                    fail("empty.notEmpty", nil, "覆盖状态为 empty 的数据包不得携带任何条目")
                }
            case .complete, .partial:
                if declaredCount == 0 && fragment.isEmpty {
                    fail("records.empty", nil, "覆盖状态为 \(coverageStatus.rawValue) 的数据包不得为空")
                }
            case .unknown, .notSupported, .withdrawn:
                break
            }
        }

        // ID 非空与唯一性
        checkUniqueNonEmpty(fragment.events.map(\.id), label: "event", fail: fail)
        checkUniqueNonEmpty(fragment.commerceItems.map(\.id), label: "commerceItem", fail: fail)
        checkUniqueNonEmpty(
            fragment.commerceSnapshots.map(\.id), label: "commerceSnapshot", fail: fail)
        checkUniqueNonEmpty(fragment.catalogues.map(\.id), label: "catalogue", fail: fail)
        checkUniqueNonEmpty(
            fragment.archiveCatalogues.map(\.id), label: "archiveCatalogue", fail: fail)
        checkUniqueNonEmpty(fragment.items.map(\.id), label: "item", fail: fail)
        checkUniqueNonEmpty(fragment.coordinates.map(\.id), label: "coordinate", fail: fail)
        checkUniqueNonEmpty(fragment.stories.map(\.id), label: "story", fail: fail)
        checkUniqueNonEmpty(fragment.historyEntries.map(\.id), label: "historyEntry", fail: fail)

        // canonical ID 唯一（跨实体类型不允许冲突，§4.5）
        let canonicalIDs = fragment.canonicalEntityIDs(brandID: brandID)
        let duplicatedCanonical = TimeHallDatasetRules.duplicateValues(canonicalIDs)
        if !duplicatedCanonical.isEmpty {
            fail(
                "canonicalID.duplicate", duplicatedCanonical.first,
                "canonical ID 重复 \(duplicatedCanonical.count) 条")
        }
        for id in canonicalIDs where !TimeHallCanonicalID.isValid(id) {
            fail("canonicalID.invalid", id, "canonical ID 不符合 brandID/entityType/sourceID 规范")
            break
        }
        if let mismatched = canonicalIDs.first(where: {
            TimeHallCanonicalID.brandID(from: $0) != brandID
        }) {
            fail("canonicalID.brandMismatch", mismatched, "canonical ID 的品牌与数据包声明不一致")
        }

        // 日期字段格式
        for event in fragment.events {
            if event.publishedOn.isEmpty || !TimeHallDatasetRules.isISODate(event.publishedOn) {
                fail("event.publishedOn", event.id, "资讯发布日期必须是 yyyy-MM-dd")
            }
            if !TimeHallDatasetRules.isISODate(event.observedAt) {
                fail("event.observedAt", event.id, "observedAt 必须是 yyyy-MM-dd")
            }
        }
        for story in fragment.stories {
            if let publishedOn = story.publishedOn, !TimeHallDatasetRules.isISODate(publishedOn) {
                fail("story.publishedOn", story.id, "专题发布日期必须是 yyyy-MM-dd")
            }
        }
        for item in fragment.commerceItems where !TimeHallDatasetRules.isISODate(item.observedAt) {
            fail("commerceItem.observedAt", item.id, "observedAt 必须是 yyyy-MM-dd")
        }
        for snapshot in fragment.commerceSnapshots
        where !TimeHallDatasetRules.isISODate(snapshot.observedAt) {
            fail("commerceSnapshot.observedAt", snapshot.id, "observedAt 必须是 yyyy-MM-dd")
        }
        for coordinate in fragment.coordinates
        where !TimeHallDatasetRules.isISODate(coordinate.observedAt) {
            fail("coordinate.observedAt", coordinate.id, "observedAt 必须是 yyyy-MM-dd")
        }
        for entry in fragment.historyEntries
        where !TimeHallDatasetRules.isISODate(entry.observedAt) {
            fail("historyEntry.observedAt", entry.id, "observedAt 必须是 yyyy-MM-dd")
        }
        for item in fragment.items where !TimeHallDatasetRules.isISODate(item.observedAt) {
            fail("item.observedAt", item.id, "observedAt 必须是 yyyy-MM-dd")
        }
        for catalogue in fragment.catalogues where catalogue.pageCount <= 0 {
            fail("catalogue.pageCount", catalogue.id, "目录页数必须大于 0")
        }

        // 引用完整性：**包内可解析的引用**不得悬空（§18.1 D09）。
        //
        // 分片拆包后，被引用的实体可能在另一个包里（§6.7）。规则因此精确到：
        // 只有当被引用类型**也出现在本包中**时才要求引用闭合；目标类型不在本包时
        // 视为显式的外部依赖，由根清单的 `dependencyPackRecordNames` 声明，
        // 缺依赖时由读取层整体回退——不把合法的跨包引用误判为损坏数据。
        let commerceItemIDs = Set(fragment.commerceItems.map(\.id))
        if !fragment.commerceItems.isEmpty {
            collectDangling(
                fragment.events.flatMap { $0.linkedCommerceItemIDs.map { ($0, $0) } },
                known: commerceItemIDs, label: "event.linkedCommerceItem", fail: fail)
            collectDangling(
                fragment.stories.flatMap { $0.linkedCommerceItemIDs.map { ($0, $0) } },
                known: commerceItemIDs, label: "story.linkedCommerceItem", fail: fail)
            collectDangling(
                fragment.coordinates.flatMap { $0.linkedCommerceItemIDs.map { ($0, $0) } },
                known: commerceItemIDs, label: "coordinate.linkedCommerceItem", fail: fail)
        }

        if !fragment.catalogues.isEmpty {
            collectDangling(
                fragment.items.map { ($0.catalogueID, $0.id) },
                known: Set(fragment.catalogues.map(\.id)),
                label: "item.catalogueID", fail: fail)
        }

        if !fragment.archiveCatalogues.isEmpty {
            collectDangling(
                fragment.timelineYears.flatMap { record in
                    record.catalogueIDs.map { ($0, "\(record.year)") }
                },
                known: Set(fragment.archiveCatalogues.map(\.id)),
                label: "timelineYear.catalogueID", fail: fail)
        }

        // 商品快照内部一致性；快照与在售商品同包时引用必须闭合
        for snapshot in fragment.commerceSnapshots {
            let ids = Set(snapshot.itemIDs)
            let current = Set(snapshot.currentItemIDs)
            let outlet = Set(snapshot.outletItemIDs)
            if ids != current.union(outlet) || !current.isDisjoint(with: outlet) {
                fail(
                    "commerceSnapshot.split", snapshot.id,
                    "itemIDs 必须等于 currentItemIDs ∪ outletItemIDs 且两者不相交")
            }
            if !fragment.commerceItems.isEmpty, !ids.isSubset(of: commerceItemIDs) {
                fail("commerceSnapshot.dangling", snapshot.id, "快照引用了包内不存在的商品")
            }
        }

        return TimeHallValidationOutcome(issues: issues)
    }

    /// 合并后的展示快照校验。
    ///
    /// 多分片合并后不再对应单一分片边界，因此只做与覆盖范围无关的通用结构检查：
    /// ID 唯一、canonical ID 规范、日期格式、引用完整性。
    static func validateMergedFragment(
        _ fragment: TimeHallCatalogFragmentDTO,
        brandID: String
    ) -> TimeHallValidationOutcome {
        validateStructural(
            fragment,
            declaredEntityType: nil,
            brandID: brandID,
            coverageStatus: .partial
        )
    }

    // MARK: 第二层：分片契约校验

    /// 分片契约校验：分片描述、负载、字节数与覆盖状态必须自洽。
    static func validatePartition(
        descriptor: TimeHallPartitionDescriptor,
        payload: TimeHallPackPayload,
        compressedBytes: Int,
        uncompressedBytes: Int,
        limits: TimeHallCacheLimits = .default
    ) -> TimeHallValidationOutcome {
        var issues: [TimeHallValidationIssue] = []

        func fail(_ code: String, _ message: String) {
            issues.append(
                TimeHallValidationIssue(layer: .partition, code: code, entityID: descriptor.partitionID, message: message))
        }

        if !TimeHallPartitionID.isSafe(descriptor.partitionID) {
            fail("partitionID.unsafe", "分片 ID 含非法字符或路径穿越片段")
        }
        if TimeHallPartitionID.brandID(from: descriptor.partitionID) != descriptor.brandID {
            fail("partitionID.brandMismatch", "分片 ID 的品牌段与 brandID 不一致")
        }
        if TimeHallPartitionID.entityType(from: descriptor.partitionID) != descriptor.entityType {
            fail("partitionID.entityMismatch", "分片 ID 的实体类型段与 entityType 不一致")
        }
        if descriptor.brandID.isEmpty {
            fail("brandID.empty", "分片必须声明 brandID")
        }
        if descriptor.partitionRevision <= 0 {
            fail("partitionRevision.invalid", "分片修订号必须为正数")
        }
        if !TimeHallDatasetRules.isSHA256Hex(descriptor.payloadHash) {
            fail("payloadHash.invalid", "payloadHash 必须是 64 位小写十六进制 SHA-256")
        }
        if descriptor.packRecordName.isEmpty {
            fail("packRecordName.empty", "分片必须指向数据包 Record ID")
        }
        if descriptor.recordCount < 0 {
            fail("recordCount.invalid", "recordCount 不得为负")
        }

        // 覆盖状态与检查时间必须成对出现（§5.2：empty 是有版本和检查时间的有效结果）
        switch descriptor.coverageStatus {
        case .complete, .empty:
            if (descriptor.checkedThrough ?? "").isEmpty {
                fail(
                    "checkedThrough.missing",
                    "覆盖状态为 \(descriptor.coverageStatus.rawValue) 时必须声明 checkedThrough")
            }
        case .partial, .unknown, .notSupported, .withdrawn:
            break
        }
        if let checkedThrough = descriptor.checkedThrough, !checkedThrough.isEmpty,
            !TimeHallDatasetRules.isISODate(String(checkedThrough.prefix(10)))
        {
            fail("checkedThrough.format", "checkedThrough 必须是 ISO 8601 时间戳")
        }

        for dayKey in descriptor.dayCoverage.keys
        where dayKey.count != 10 || !TimeHallDatasetRules.isISODate(dayKey) {
            fail("dayCoverage.key", "日覆盖键必须是 yyyy-MM-dd：\(dayKey)")
            break
        }

        // 负载与分片描述必须一致
        if !payload.matches(descriptor) {
            fail("payload.mismatch", "数据包负载声明的分片与根清单描述不一致")
        }

        // 数量一致性：complete / empty 必须精确匹配，partial 允许少于声明（§11.5）
        let actualCount = entityCount(of: descriptor.entityType, in: payload.records)
        switch descriptor.coverageStatus {
        case .complete:
            if actualCount != descriptor.recordCount {
                fail(
                    "recordCount.mismatch",
                    "complete 分片声明 \(descriptor.recordCount) 条，实际 \(actualCount) 条")
            }
        case .empty:
            if actualCount != 0 {
                fail("recordCount.empty", "empty 分片不得携带条目")
            }
        case .partial, .unknown, .notSupported, .withdrawn:
            if actualCount > descriptor.recordCount {
                fail(
                    "recordCount.overflow",
                    "实际条目 \(actualCount) 多于声明的 \(descriptor.recordCount)")
            }
        }

        // 体积上限（§12.3）
        if compressedBytes <= 0 {
            fail("bytes.compressed", "压缩后字节数必须大于 0")
        }
        if uncompressedBytes <= 0 {
            fail("bytes.uncompressed", "解压后字节数必须大于 0")
        }
        if compressedBytes > limits.maxPackCompressedBytes {
            fail(
                "bytes.compressedTooLarge",
                "压缩后 \(compressedBytes) 字节超出上限 \(limits.maxPackCompressedBytes)")
        }
        if uncompressedBytes > limits.maxPackUncompressedBytes {
            fail(
                "bytes.uncompressedTooLarge",
                "解压后 \(uncompressedBytes) 字节超出上限 \(limits.maxPackUncompressedBytes)")
        }
        if compressedBytes > 0, uncompressedBytes / max(compressedBytes, 1)
            > limits.maxDecompressionRatio
        {
            fail("bytes.ratio", "解压膨胀比异常，疑似压缩炸弹")
        }

        return TimeHallValidationOutcome(issues: issues)
    }

    /// 根清单结构校验
    static func validateRootIndex(_ rootIndex: TimeHallRootIndex) -> TimeHallValidationOutcome {
        var issues: [TimeHallValidationIssue] = []

        func fail(_ code: String, _ entityID: String? = nil, _ message: String) {
            issues.append(
                TimeHallValidationIssue(layer: .partition, code: code, entityID: entityID, message: message))
        }

        if rootIndex.schemaVersion != TimeHallProtocol.schemaVersion {
            fail("schemaVersion", nil, "根清单 schemaVersion 不受支持")
        }
        if rootIndex.releaseSeq <= 0 {
            fail("releaseSeq", nil, "releaseSeq 必须为正数")
        }
        if !TimeHallDatasetRules.isISODate(String(rootIndex.publishedAt.prefix(10))) {
            fail("publishedAt", nil, "publishedAt 必须是 ISO 8601 时间戳")
        }

        let duplicatedBrands = TimeHallDatasetRules.duplicateValues(rootIndex.brands.map(\.brandID))
        if !duplicatedBrands.isEmpty {
            fail("brand.duplicate", duplicatedBrands.first, "根清单存在重复品牌")
        }
        let duplicatedPartitions = TimeHallDatasetRules.duplicateValues(
            rootIndex.partitions.map(\.partitionID))
        if !duplicatedPartitions.isEmpty {
            fail("partition.duplicate", duplicatedPartitions.first, "根清单存在重复分片")
        }

        let knownPartitions = Set(rootIndex.partitions.map(\.packRecordName))
        for partition in rootIndex.partitions {
            for dependency in partition.dependencyPackRecordNames
            where !knownPartitions.contains(dependency) {
                fail(
                    "dependency.missing", partition.partitionID,
                    "分片声明了根清单中不存在的依赖包 \(dependency)")
            }
            if !TimeHallPartitionID.isSafe(partition.partitionID) {
                fail("partitionID.unsafe", partition.partitionID, "分片 ID 含非法字符")
            }
        }

        for withdrawal in rootIndex.withdrawals {
            if !TimeHallCanonicalID.isValid(withdrawal.canonicalEntityID)
                && withdrawal.mediaHashes.isEmpty
            {
                fail(
                    "withdrawal.invalid", withdrawal.canonicalEntityID,
                    "撤回条目必须给出合法 canonical ID 或媒体 hash")
            }
        }

        return TimeHallValidationOutcome(issues: issues)
    }

    // MARK: 第三层：品牌数据集规则（现有 PINK HOUSE 整馆验收）

    /// 现有 `TimeHallCatalogStore.validate` 的规则本体。
    ///
    /// 这些条件（`version == 3`、`1972...2026`、`2015...2026`、`brand == "PINK HOUSE"`、
    /// 官方域名白名单、`sampleYears` 一致）是**当前 PINK HOUSE 历史数据集的验收规则**，
    /// 保留原样，不要用它去校验多品牌增量包。
    static func validateBrandDataset(_ catalog: TimeHallCatalogDTO) -> TimeHallValidationReport {
        let duplicateItemIDs = TimeHallDatasetRules.duplicateValues(catalog.items.map(\.id))
        let duplicateCatalogueIDs = TimeHallDatasetRules.duplicateValues(catalog.catalogues.map(\.id))
        let duplicateArchiveCatalogueIDs = TimeHallDatasetRules.duplicateValues(
            catalog.archiveCatalogues.map(\.id))
        let duplicateImportBatchIDs = TimeHallDatasetRules.duplicateValues(
            catalog.importBatches.map(\.id))
        let duplicateCommerceSnapshotIDs = TimeHallDatasetRules.duplicateValues(
            catalog.commerceSnapshots.map(\.id))
        let duplicateCommerceItemIDs = TimeHallDatasetRules.duplicateValues(
            catalog.commerceItems.map(\.id))
        let duplicateCommerceProductCodes = TimeHallDatasetRules.duplicateValues(
            catalog.commerceItems.map(\.productCode))
        let duplicateCoordinateIDs = TimeHallDatasetRules.duplicateValues(
            catalog.coordinates.map(\.id))
        let duplicateStoryIDs = TimeHallDatasetRules.duplicateValues(catalog.stories.map(\.id))
        let duplicateEventIDs = TimeHallDatasetRules.duplicateValues(catalog.events.map(\.id))
        let duplicateHistoryEntryIDs = TimeHallDatasetRules.duplicateValues(
            catalog.historyEntries.map(\.id))
        let duplicateTimelineYears = Dictionary(grouping: catalog.timelineYears.map(\.year), by: { $0 })
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
        let groupedKeys = Dictionary(grouping: catalog.items, by: \.canonicalKey)
        let duplicateKeys =
            groupedKeys
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()

        var catalogErrors: [String] = []
        if catalog.version != 3 { catalogErrors.append("version") }
        if !TimeHallDatasetRules.isOfficialURL(catalog.source) { catalogErrors.append("source") }
        if catalog.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            catalogErrors.append("title")
        }
        if catalog.scope.startYear != 1972 || catalog.scope.endYear != nil {
            catalogErrors.append("scope")
        }
        let actualSampleYears = Array(Set(catalog.catalogues.map(\.year))).sorted()
        if Array(Set(catalog.scope.sampleYears)).sorted() != actualSampleYears {
            catalogErrors.append("sampleYears")
        }
        if catalog.catalogues.isEmpty { catalogErrors.append("catalogues") }
        if catalog.items.isEmpty { catalogErrors.append("items") }
        if catalog.importBatches.isEmpty { catalogErrors.append("importBatches") }

        let expectedTimelineYears = Array(1972...2026)
        if catalog.timelineYears.map(\.year).sorted() != expectedTimelineYears {
            catalogErrors.append("timelineCoverage")
        }
        let expectedArchiveYears = Set(2015...2026)
        if Set(catalog.archiveCatalogues.map(\.year)) != expectedArchiveYears {
            catalogErrors.append("archiveCoverage")
        }

        let archiveCatalogueIDs = Set(catalog.archiveCatalogues.map(\.id))
        let invalidArchiveCatalogueIDs = Set(
            catalog.archiveCatalogues.compactMap { catalogue -> String? in
                let isValid =
                    !catalogue.id.isEmpty
                    && catalogue.id == "official-catalog-\(catalogue.officialID)"
                    && (2015...2026).contains(catalogue.year)
                    && !catalogue.title.isEmpty
                    && !catalogue.seasonLabelZH.isEmpty
                    && !catalogue.coverImage.isEmpty
                    && TimeHallDatasetRules.isOfficialURL(catalogue.sourceURL)
                    && TimeHallDatasetRules.isOfficialImageURL(catalogue.imageSourceURL)
                return isValid ? nil : catalogue.id
            }
        ).sorted()

        let deepCatalogueIDs = Set(catalog.catalogues.map(\.id))
        let deepCatalogueByID = Dictionary(
            catalog.catalogues.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let commerceSnapshotIDs = Set(catalog.commerceSnapshots.map(\.id))
        let coordinateIDs = Set(catalog.coordinates.map(\.id))
        let storyIDs = Set(catalog.stories.map(\.id))
        let eventIDs = Set(catalog.events.map(\.id))
        let historyEntryIDs = Set(catalog.historyEntries.map(\.id))
        let commerceSnapshotByID = Dictionary(
            catalog.commerceSnapshots.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let invalidImportBatchIDs = Set(
            catalog.importBatches.compactMap { batch -> String? in
                let catalogueItemIDs = batch.catalogueIDs.flatMap { deepCatalogueByID[$0]?.itemIds ?? [] }
                let commerceItemIDs = batch.commerceSnapshotIDs.flatMap {
                    commerceSnapshotByID[$0]?.itemIDs ?? []
                }
                let referencedCoordinateIDs = batch.coordinateIDs.filter { coordinateIDs.contains($0) }
                let referencedStoryIDs = batch.storyIDs.filter { storyIDs.contains($0) }
                let referencedEventIDs = batch.eventIDs.filter { eventIDs.contains($0) }
                let referencedHistoryEntryIDs = batch.historyEntryIDs.filter {
                    historyEntryIDs.contains($0)
                }
                let referencedItemCount = Set(
                    catalogueItemIDs + commerceItemIDs + referencedCoordinateIDs + referencedStoryIDs
                        + referencedEventIDs
                        + referencedHistoryEntryIDs
                ).count
                let ownsSupportedContent =
                    !batch.catalogueIDs.isEmpty || !batch.commerceSnapshotIDs.isEmpty
                    || !batch.coordinateIDs.isEmpty || !batch.storyIDs.isEmpty || !batch.eventIDs.isEmpty
                    || !batch.historyEntryIDs.isEmpty
                let isValid =
                    !batch.id.isEmpty
                    && batch.order > 0
                    && !batch.kind.isEmpty
                    && !batch.titleZH.isEmpty
                    && TimeHallDatasetRules.isISODate(batch.importedAt)
                    && !batch.sourceURLs.isEmpty
                    && batch.sourceURLs.allSatisfy(TimeHallDatasetRules.isOfficialSourceURL)
                    && ownsSupportedContent
                    && Set(batch.catalogueIDs).isSubset(of: deepCatalogueIDs)
                    && Set(batch.commerceSnapshotIDs).isSubset(of: commerceSnapshotIDs)
                    && Set(batch.coordinateIDs).isSubset(of: coordinateIDs)
                    && Set(batch.storyIDs).isSubset(of: storyIDs)
                    && Set(batch.eventIDs).isSubset(of: eventIDs)
                    && Set(batch.historyEntryIDs).isSubset(of: historyEntryIDs)
                    && batch.itemCount == referencedItemCount
                return isValid ? nil : batch.id
            }
        ).sorted()

        let commerceItemIDs = Set(catalog.commerceItems.map(\.id))
        let invalidCommerceSnapshotIDs = Set(
            catalog.commerceSnapshots.compactMap { snapshot -> String? in
                let ids = Set(snapshot.itemIDs)
                let currentIDs = Set(snapshot.currentItemIDs)
                let outletIDs = Set(snapshot.outletItemIDs)
                let isValid =
                    !snapshot.id.isEmpty
                    && !snapshot.titleZH.isEmpty
                    && TimeHallDatasetRules.isISODate(snapshot.observedAt)
                    && !snapshot.sourceURLs.isEmpty
                    && snapshot.sourceURLs.allSatisfy(TimeHallDatasetRules.isOfficialSourceURL)
                    && !ids.isEmpty
                    && ids == currentIDs.union(outletIDs)
                    && currentIDs.isDisjoint(with: outletIDs)
                    && ids.isSubset(of: commerceItemIDs)
                return isValid ? nil : snapshot.id
            }
        ).sorted()

        let invalidCommerceItemIDs = Set(
            catalog.commerceItems.compactMap { item -> String? in
                let priceIsValid =
                    item.regularPriceJPY > 0
                    && (item.salePriceJPY.map { $0 > 0 && $0 <= item.regularPriceJPY } ?? true)
                let isValid =
                    !item.id.isEmpty
                    && !item.productCode.isEmpty
                    && !item.category.isEmpty
                    && !item.categoryZH.isEmpty
                    && !item.name.isEmpty
                    && !item.nameZH.isEmpty
                    && item.brand == "PINK HOUSE"
                    && !item.listingStatus.isEmpty
                    && !item.styles.isEmpty
                    && !item.stylesZH.isEmpty
                    && !item.coverImage.isEmpty
                    && !item.imageSourceURLs.isEmpty
                    && item.imageSourceURLs.allSatisfy(
                        TimeHallDatasetRules.isOfficialCommerceImageURL)
                    && TimeHallDatasetRules.isOfficialURL(item.productPageURL)
                    && TimeHallDatasetRules.isISODate(item.observedAt)
                    && priceIsValid
                return isValid ? nil : item.id
            }
        ).sorted()

        let invalidCoordinateIDs = Set(
            catalog.coordinates.compactMap { coordinate -> String? in
                let publishedOnIsValid =
                    coordinate.publishedOn.map(TimeHallDatasetRules.isISODate) ?? true
                let isValid =
                    coordinate.id == "coordinate-\(coordinate.officialID)"
                    && coordinate.officialID > 0
                    && !coordinate.title.isEmpty
                    && !coordinate.coordinatePoint.isEmpty
                    && TimeHallDatasetRules.isOfficialURL(coordinate.sourceURL)
                    && TimeHallDatasetRules.isOfficialCoordinateImageURL(coordinate.imageSourceURL)
                    && !coordinate.coverImage.isEmpty
                    && Set(coordinate.linkedCommerceItemIDs).isSubset(of: commerceItemIDs)
                    && publishedOnIsValid
                    && TimeHallDatasetRules.isISODate(coordinate.observedAt)
                return isValid ? nil : coordinate.id
            }
        ).sorted()

        let invalidStoryIDs = Set(
            catalog.stories.compactMap { story -> String? in
                let publishedOnIsValid =
                    story.publishedOn.map(TimeHallDatasetRules.isISODate) ?? true
                let isValid =
                    !story.id.isEmpty
                    && !story.title.isEmpty
                    && !story.summary.isEmpty
                    && !story.content.isEmpty
                    && TimeHallDatasetRules.isOfficialSourceURL(story.sourceURL)
                    && !story.coverImage.isEmpty
                    && !story.imageSourceURLs.isEmpty
                    && story.imageSourceURLs.allSatisfy(
                        TimeHallDatasetRules.isOfficialStoryImageURL)
                    && Set(story.linkedCommerceItemIDs).isSubset(of: commerceItemIDs)
                    && publishedOnIsValid
                    && TimeHallDatasetRules.isISODate(story.observedAt)
                return isValid ? nil : story.id
            }
        ).sorted()

        let invalidEventIDs = Set(
            catalog.events.compactMap { event -> String? in
                let isValid =
                    event.id == "news-\(event.officialID)"
                    && event.officialID > 0
                    && !event.title.isEmpty
                    && TimeHallDatasetRules.isISODate(event.publishedOn)
                    && !event.summary.isEmpty
                    && !event.content.isEmpty
                    && TimeHallDatasetRules.isOfficialURL(event.sourceURL)
                    && !event.coverImage.isEmpty
                    && !event.imageSourceURLs.isEmpty
                    && event.imageSourceURLs.allSatisfy(TimeHallDatasetRules.isOfficialNewsImageURL)
                    && Set(event.linkedCommerceItemIDs).isSubset(of: commerceItemIDs)
                    && TimeHallDatasetRules.isISODate(event.observedAt)
                return isValid ? nil : event.id
            }
        ).sorted()

        let invalidHistoryEntryIDs = Set(
            catalog.historyEntries.compactMap { entry -> String? in
                let imagePairIsValid: Bool
                if let coverImage = entry.coverImage, let imageSourceURL = entry.imageSourceURL {
                    imagePairIsValid =
                        !coverImage.isEmpty
                        && TimeHallDatasetRules.isOfficialHistoryImageURL(imageSourceURL)
                } else {
                    imagePairIsValid = entry.coverImage == nil && entry.imageSourceURL == nil
                }
                let isValid =
                    !entry.id.isEmpty
                    && (1972...2026).contains(entry.year)
                    && !entry.title.isEmpty
                    && !entry.content.isEmpty
                    && TimeHallDatasetRules.isOfficialSourceURL(entry.sourceURL)
                    && imagePairIsValid
                    && TimeHallDatasetRules.isISODate(entry.observedAt)
                return isValid ? nil : entry.id
            }
        ).sorted()

        let invalidTimelineYears = Set(
            catalog.timelineYears.compactMap { record -> Int? in
                let hasCoreFields =
                    (1972...2026).contains(record.year)
                    && !record.titleZH.isEmpty
                    && !record.storyZH.isEmpty
                    && record.sourceURLs.allSatisfy(TimeHallDatasetRules.isOfficialSourceURL)
                    && Set(record.catalogueIDs).isSubset(of: archiveCatalogueIDs)
                let kindIsValid: Bool
                switch record.kind {
                case .archiveGap:
                    kindIsValid =
                        record.evidenceLevel == .archiveGap
                        && record.sourceURLs.isEmpty
                        && record.catalogueIDs.isEmpty
                case .officialArchive:
                    kindIsValid =
                        record.evidenceLevel == .officialCatalogue
                        && !record.catalogueIDs.isEmpty
                case .milestone:
                    kindIsValid =
                        record.evidenceLevel == .officialHistory
                        && !record.sourceURLs.isEmpty
                }
                return hasCoreFields && kindIsValid ? nil : record.year
            }
        ).sorted()

        let invalidCatalogueIDs = Set(
            catalog.catalogues.compactMap { catalogue -> String? in
                let hasCoreFields =
                    !catalogue.id.isEmpty
                    && !catalogue.title.isEmpty
                    && !catalogue.titleZH.isEmpty
                    && !catalogue.summaryZH.isEmpty
                    && !catalogue.season.isEmpty
                    && !catalogue.seasonLabel.isEmpty
                    && !catalogue.coverImage.isEmpty
                let isValid =
                    hasCoreFields
                    && catalogue.year >= catalog.scope.startYear
                    && catalogue.pageCount > 0
                    && !catalogue.itemIds.isEmpty
                    && TimeHallDatasetRules.isOfficialURL(catalogue.sourceURL)
                    && TimeHallDatasetRules.isOfficialImageURL(catalogue.imageSourceURL)
                return isValid ? nil : catalogue.id
            }
        ).sorted()

        let catalogueByID = Dictionary(
            catalog.catalogues.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let invalidItemIDs = Set(
            catalog.items.compactMap { item -> String? in
                guard let catalogue = catalogueByID[item.catalogueID] else { return item.id }
                let expectedCanonicalKey = "pink-house|\(item.year)-\(item.season)|\(item.name)"
                let hasCoreFields =
                    !item.id.isEmpty
                    && !item.canonicalKey.isEmpty
                    && !item.category.isEmpty
                    && !item.categoryZH.isEmpty
                    && !item.name.isEmpty
                    && !item.nameZH.isEmpty
                    && item.brand == "PINK HOUSE"
                    && !item.listingStatus.isEmpty
                    && !item.styles.isEmpty
                    && !item.stylesZH.isEmpty
                    && !item.noteZH.isEmpty
                    && !(item.coverImage ?? "").isEmpty
                let matchesCatalogue =
                    item.year == catalogue.year
                    && item.season == catalogue.season
                    && item.sourceURL == catalogue.sourceURL
                    && catalogue.itemIds.contains(item.id)
                    && (1...catalogue.pageCount).contains(item.cataloguePage)
                let cataloguePagesAreValid =
                    item.cataloguePages.map {
                        !$0.isEmpty
                            && $0.contains(item.cataloguePage)
                            && $0.allSatisfy { (1...catalogue.pageCount).contains($0) }
                    } ?? true
                let productPageIsValid =
                    item.productPageURL.map(TimeHallDatasetRules.isOfficialURL) ?? true
                let isValid =
                    hasCoreFields
                    && matchesCatalogue
                    && cataloguePagesAreValid
                    && productPageIsValid
                    && item.canonicalKey == expectedCanonicalKey
                    && item.priceJPY > 0
                    && item.datePrecision == "season"
                    && TimeHallDatasetRules.isOfficialURL(item.sourceURL)
                    && TimeHallDatasetRules.isOfficialImageURL(item.imageSourceURL)
                    && TimeHallDatasetRules.isISODate(item.observedAt)
                return isValid ? nil : item.id
            }
        ).sorted()

        let itemIDs = Set(catalog.items.map(\.id))
        let allReferencedIDs = catalog.catalogues.flatMap(\.itemIds)
        let referencedIDs = Set(allReferencedIDs)
        return TimeHallValidationReport(
            dressCount: catalog.items.filter { $0.kind == .dress }.count,
            clothingCount: catalog.items.filter { $0.kind == .clothing }.count,
            accessoryCount: catalog.items.filter { $0.kind == .accessory }.count,
            catalogueCount: catalog.catalogues.count,
            timelineYearCount: catalog.timelineYears.count,
            archiveCatalogueCount: catalog.archiveCatalogues.count,
            commerceSnapshotCount: catalog.commerceSnapshots.count,
            commerceItemCount: catalog.commerceItems.count,
            coordinateCount: catalog.coordinates.count,
            storyCount: catalog.stories.count,
            eventCount: catalog.events.count,
            historyEntryCount: catalog.historyEntries.count,
            importBatchCount: catalog.importBatches.count,
            catalogErrors: catalogErrors.sorted(),
            duplicateItemIDs: duplicateItemIDs,
            duplicateCatalogueIDs: duplicateCatalogueIDs,
            duplicateArchiveCatalogueIDs: duplicateArchiveCatalogueIDs,
            duplicateImportBatchIDs: duplicateImportBatchIDs,
            duplicateCommerceSnapshotIDs: duplicateCommerceSnapshotIDs,
            duplicateCommerceItemIDs: duplicateCommerceItemIDs,
            duplicateCommerceProductCodes: duplicateCommerceProductCodes,
            duplicateCoordinateIDs: duplicateCoordinateIDs,
            duplicateStoryIDs: duplicateStoryIDs,
            duplicateEventIDs: duplicateEventIDs,
            duplicateHistoryEntryIDs: duplicateHistoryEntryIDs,
            duplicateTimelineYears: duplicateTimelineYears,
            duplicateCanonicalKeys: duplicateKeys,
            duplicateCatalogueItemIDs: TimeHallDatasetRules.duplicateValues(allReferencedIDs),
            missingCatalogueItemIDs: Array(referencedIDs.subtracting(itemIDs)).sorted(),
            orphanItemIDs: Array(itemIDs.subtracting(referencedIDs)).sorted(),
            invalidCatalogueIDs: invalidCatalogueIDs,
            invalidArchiveCatalogueIDs: invalidArchiveCatalogueIDs,
            invalidImportBatchIDs: invalidImportBatchIDs,
            invalidCommerceSnapshotIDs: invalidCommerceSnapshotIDs,
            invalidCommerceItemIDs: invalidCommerceItemIDs,
            invalidCoordinateIDs: invalidCoordinateIDs,
            invalidStoryIDs: invalidStoryIDs,
            invalidEventIDs: invalidEventIDs,
            invalidHistoryEntryIDs: invalidHistoryEntryIDs,
            invalidTimelineYears: invalidTimelineYears,
            invalidItemIDs: invalidItemIDs
        )
    }

    // MARK: 工具

    /// 某实体类型在分片内容中的条目数
    static func entityCount(
        of entityType: TimeHallEntityType,
        in fragment: TimeHallCatalogFragmentDTO
    ) -> Int {
        switch entityType {
        case .brand: return 1
        case .event: return fragment.events.count
        case .commerceProduct: return fragment.commerceItems.count
        case .commerceSnapshot: return fragment.commerceSnapshots.count
        case .catalogue: return fragment.catalogues.count
        case .archiveCatalogue: return fragment.archiveCatalogues.count
        case .item: return fragment.items.count
        case .coordinate: return fragment.coordinates.count
        case .story: return fragment.stories.count
        case .historyEntry: return fragment.historyEntries.count
        }
    }

    private static func checkUniqueNonEmpty(
        _ values: [String],
        label: String,
        fail: (String, String?, String) -> Void
    ) {
        if let empty = values.first(where: { $0.isEmpty }) {
            fail("\(label).id.empty", empty, "\(label) 存在空 ID")
        }
        let duplicated = TimeHallDatasetRules.duplicateValues(values)
        if !duplicated.isEmpty {
            fail(
                "\(label).id.duplicate", duplicated.first,
                "\(label) 存在 \(duplicated.count) 个重复 ID")
        }
    }

    private static func collectDangling(
        _ pairs: [(String, String)],
        known: Set<String>,
        label: String,
        fail: (String, String?, String) -> Void
    ) {
        for (reference, owner) in pairs where !known.contains(reference) {
            fail("\(label).dangling", owner, "引用了包内不存在的标识 \(reference)")
        }
    }
}
