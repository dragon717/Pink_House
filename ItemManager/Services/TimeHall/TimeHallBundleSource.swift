import Foundation

// MARK: - Bundle 种子来源
//
// 对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md §17.2。
//
// Bundle 是**某个已审核发布版本的离线快照**，不是「过期数据」。
// 对历史上缺少 releaseSeq / 分片版本 / 覆盖状态的数据：
//   - 不推测其覆盖今天或某个新品牌；
//   - 根据构建时生成的迁移映射赋予明确种子版本与范围；
//   - 使用它已有的真实日期与来源字段，不把 publishedOn / observedAt 统一改成 updatedAt；
//   - 对完整性未知的范围标记 `partial`，不要全盘声明完整。

/// 品牌种子注册项。资源名与品牌的映射在这里显式登记，不从文件名猜。
nonisolated struct TimeHallBundleBrandSeed: Sendable {
    let brandID: String
    let resourceName: String
    let displayName: String
    /// 来源业务时区（§4.3）。日牌官网资料统一使用 Asia/Tokyo；新增来源必须显式配置。
    let sourceTimeZone: String
    let sourceCoverage: TimeHallSourceCoverage
    let coverageDescription: String
    /// 迁移映射赋予的种子发布序号。历史安装包没有 releaseSeq，不能推测为「最新」。
    let seedReleaseSeq: Int
    /// 是否由主 catalog 承载界面头部信息
    let isPrimary: Bool

    var brand: TimeHallBrandDescriptor {
        TimeHallBrandDescriptor(
            brandID: brandID,
            displayName: displayName,
            sourceTimeZone: sourceTimeZone,
            sourceCoverage: sourceCoverage,
            coverageDescription: coverageDescription
        )
    }
}

/// 一个品牌在本机 Bundle 中的离线种子
nonisolated struct TimeHallBundleSeed: Sendable {
    let brand: TimeHallBrandDescriptor
    let seedReleaseSeq: Int
    let catalog: TimeHallCatalogDTO
    let template: TimeHallCatalogTemplate
    /// 分片描述（scope 固定为 `all`，覆盖状态为 `partial`）
    let partitions: [TimeHallPartitionDescriptor]
    /// 该种子声明的真实检查上界（各实体类型 observedAt 的最大值），可能为 nil
    let seedCheckedThrough: String?

    func contains(entityType: TimeHallEntityType) -> Bool {
        partitions.contains { $0.entityType == entityType }
    }

    func partition(for entityType: TimeHallEntityType) -> TimeHallPartitionDescriptor? {
        partitions.first { $0.entityType == entityType }
    }
}

/// catalog.json 中与分片无关的头部信息，用于把合并后的分片重新组装成界面需要的 DTO。
nonisolated struct TimeHallCatalogTemplate: Sendable {
    let version: Int
    let source: String
    let title: String
    let subtitle: String
    let heroImage: String?
    let heroCaption: String
    let heroBody: String
    let scope: TimeHallCatalogScopeDTO
    let importBatches: [TimeHallImportBatchDTO]

    init(catalog: TimeHallCatalogDTO) {
        version = catalog.version
        source = catalog.source
        title = catalog.title
        subtitle = catalog.subtitle
        heroImage = catalog.heroImage
        heroCaption = catalog.heroCaption
        heroBody = catalog.heroBody
        scope = catalog.scope
        importBatches = catalog.importBatches
    }

    /// 把合并后的分片内容组装回界面消费的 `TimeHallCatalogDTO`。
    /// `timelineYears` 等由 Bundle 提供的静态部分按模板回填。
    func makeCatalog(fragment: TimeHallCatalogFragmentDTO) -> TimeHallCatalogDTO {
        TimeHallCatalogDTO(
            version: version,
            source: source,
            title: title,
            subtitle: subtitle,
            heroImage: heroImage,
            heroCaption: heroCaption,
            heroBody: heroBody,
            scope: scope,
            timelineYears: fragment.timelineYears,
            archiveCatalogues: fragment.archiveCatalogues,
            catalogues: fragment.catalogues,
            items: fragment.items,
            commerceSnapshots: fragment.commerceSnapshots,
            commerceItems: fragment.commerceItems,
            coordinates: fragment.coordinates,
            stories: fragment.stories,
            events: fragment.events,
            historyEntries: fragment.historyEntries,
            importBatches: importBatches
        )
    }
}

/// Bundle 种子适配器。
///
/// 用 enum 命名空间 + static 方法，避免把 `Bundle` 实例带进 actor 边界。
nonisolated enum TimeHallBundleSource {
    /// 品牌与资源文件登记表。新增品牌必须在这里显式登记，
    /// 否则不参与种子分片，也不会因为文件名而「自动」出现（§8.3 默认禁止）。
    static let brandSeeds: [TimeHallBundleBrandSeed] = [
        TimeHallBundleBrandSeed(
            brandID: "pink-house",
            resourceName: "catalog",
            displayName: "PINK HOUSE",
            sourceTimeZone: "Asia/Tokyo",
            sourceCoverage: .currentlyEnumerable,
            coverageDescription: "官网当前仍可枚举的目录、商品与资讯",
            seedReleaseSeq: 1,
            isPrimary: true
        ),
        TimeHallBundleBrandSeed(
            brandID: "angelic-pretty",
            resourceName: "catalog-angelic-pretty",
            displayName: "Angelic Pretty",
            sourceTimeZone: "Asia/Tokyo",
            sourceCoverage: .curatedSelection,
            coverageDescription: "运营整理的精选收录，非官网全量",
            seedReleaseSeq: 1,
            isPrimary: false
        ),
        TimeHallBundleBrandSeed(
            brandID: "baby-the-stars-shine-bright",
            resourceName: "catalog-baby-stars-shine-bright",
            displayName: "BABY, THE STARS SHINE BRIGHT",
            sourceTimeZone: "Asia/Tokyo",
            sourceCoverage: .curatedSelection,
            coverageDescription: "运营整理的精选收录，非官网全量",
            seedReleaseSeq: 1,
            isPrimary: false
        ),
        TimeHallBundleBrandSeed(
            brandID: "juliette-et-justine",
            resourceName: "catalog-juliette-et-justine",
            displayName: "Juliette et Justine",
            sourceTimeZone: "Asia/Tokyo",
            sourceCoverage: .curatedSelection,
            coverageDescription: "运营整理的精选收录，非官网全量",
            seedReleaseSeq: 1,
            isPrimary: false
        ),
        TimeHallBundleBrandSeed(
            brandID: "moi-meme-moitie",
            resourceName: "catalog-wunderwelt-fleur",
            displayName: "Moi-même-Moitié",
            sourceTimeZone: "Asia/Tokyo",
            sourceCoverage: .curatedSelection,
            coverageDescription: "运营整理的精选收录，非官网全量",
            seedReleaseSeq: 1,
            isPrimary: false
        ),
    ]

    /// 主品牌（承载界面头部与默认入口）
    static var primaryBrandID: String {
        brandSeeds.first(where: \.isPrimary)?.brandID ?? brandSeeds.first?.brandID ?? "pink-house"
    }

    /// 资源候选路径。含中文与空格的工程路径在真机上不参与，只管 Bundle 内部子目录（§1.2 A）。
    private static func resourceURL(resourceName: String, in bundle: Bundle) -> URL? {
        let candidates: [URL?] = [
            bundle.url(forResource: resourceName, withExtension: "json", subdirectory: "TimeHall"),
            bundle.url(
                forResource: resourceName, withExtension: "json",
                subdirectory: "Resources/TimeHall"),
            bundle.url(forResource: resourceName, withExtension: "json"),
        ]
        return candidates.compactMap { $0 }.first
    }

    /// 读取并解码一个品牌 catalog。解码是纯计算，可在后台线程执行。
    static func catalog(resourceName: String, in bundle: Bundle = .main) -> TimeHallCatalogDTO? {
        guard let url = resourceURL(resourceName: resourceName, in: bundle) else { return nil }
        do {
            return try JSONDecoder().decode(TimeHallCatalogDTO.self, from: Data(contentsOf: url))
        } catch {
            return nil
        }
    }

    /// 载入全部已登记品牌的种子分片。
    ///
    /// - 不做整馆断言：单个品牌解码失败不影响其他品牌（§16.1 单点失败不阻塞全局）。
    /// - `includeUnregistered: false` 时不扫描未登记文件，避免「文件存在即自动上线」。
    static func loadSeeds(in bundle: Bundle = .main) -> [TimeHallBundleSeed] {
        var result: [TimeHallBundleSeed] = []
        for entry in brandSeeds {
            guard let catalog = catalog(resourceName: entry.resourceName, in: bundle) else {
                continue
            }
            result.append(makeSeed(entry: entry, catalog: catalog))
        }
        return result
    }

    /// 由登记项与已解码 catalog 生成种子分片。
    static func makeSeed(
        entry: TimeHallBundleBrandSeed,
        catalog: TimeHallCatalogDTO
    ) -> TimeHallBundleSeed {
        let partitions = makePartitions(brandID: entry.brandID, catalog: catalog)
        return TimeHallBundleSeed(
            brand: entry.brand,
            seedReleaseSeq: entry.seedReleaseSeq,
            catalog: catalog,
            template: TimeHallCatalogTemplate(catalog: catalog),
            partitions: partitions,
            seedCheckedThrough: partitions.compactMap(\.checkedThrough).max()
        )
    }

    /// 把整馆 catalog 映射为按实体类型的种子分片。
    ///
    /// 覆盖状态一律为 `partial`：Bundle 是过去某个时点的快照，
    /// **不得**声明 `complete` 或覆盖今天。`dayCoverage` 留空，
    /// 因为本机没有对任何业务日做过「已检查完」的确认。
    static func makePartitions(
        brandID: String,
        catalog: TimeHallCatalogDTO
    ) -> [TimeHallPartitionDescriptor] {
        var result: [TimeHallPartitionDescriptor] = []

        func append(
            _ entityType: TimeHallEntityType,
            count: Int,
            checkedThrough: String?
        ) {
            guard count > 0 else { return }
            let partitionID = TimeHallPartitionID.make(
                brandID: brandID,
                entityType: entityType,
                scopeKey: TimeHallPartitionID.legacyScope
            )
            result.append(
                TimeHallPartitionDescriptor(
                    partitionID: partitionID,
                    brandID: brandID,
                    entityType: entityType,
                    // 种子修订号固定为 1：来源没有修订概念，不编造。
                    partitionRevision: 1,
                    coverageStatus: .partial,
                    checkedThrough: checkedThrough,
                    dayCoverage: [:],
                    packRecordName: "bundle.\(partitionID)",
                    payloadHash: bundleSeedPlaceholderHash(partitionID),
                    recordCount: count,
                    dependencyPackRecordNames: []
                )
            )
        }

        append(.event, count: catalog.events.count, checkedThrough: catalog.events.map(\.observedAt).max())
        append(
            .commerceProduct, count: catalog.commerceItems.count,
            checkedThrough: catalog.commerceItems.map(\.observedAt).max())
        append(
            .commerceSnapshot, count: catalog.commerceSnapshots.count,
            checkedThrough: catalog.commerceSnapshots.map(\.observedAt).max())
        append(
            .catalogue, count: catalog.catalogues.count,
            // 目录 DTO 没有 observedAt 字段，不编造检查时间
            checkedThrough: nil)
        append(.archiveCatalogue, count: catalog.archiveCatalogues.count, checkedThrough: nil)
        append(.item, count: catalog.items.count, checkedThrough: catalog.items.map(\.observedAt).max())
        append(
            .coordinate, count: catalog.coordinates.count,
            checkedThrough: catalog.coordinates.map(\.observedAt).max())
        append(.story, count: catalog.stories.count, checkedThrough: catalog.stories.map(\.observedAt).max())
        append(
            .historyEntry, count: catalog.historyEntries.count,
            checkedThrough: catalog.historyEntries.map(\.observedAt).max())

        return result
    }

    /// 种子分片的占位摘要。
    ///
    /// 种子不是从云端下载的包，没有真实字节摘要，因此用固定前缀 + 分片 ID 的确定性哈希，
    /// **不伪造**一个看起来像 SHA-256 的值（避免被误当成可校验的云端包摘要）。
    static func bundleSeedPlaceholderHash(_ partitionID: String) -> String {
        "bundle-seed:" + stableDigest(partitionID)
    }

    /// FNV-1a 64 位，确定性、不依赖 Foundation 的哈希随机化。
    static func stableDigest(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }

    /// 从整馆 catalog 中抽出指定实体类型的分片内容。
    static func fragment(
        from catalog: TimeHallCatalogDTO,
        entityTypes: Set<TimeHallEntityType>
    ) -> TimeHallCatalogFragmentDTO {
        var fragment = TimeHallCatalogFragmentDTO()
        if entityTypes.contains(.catalogue) { fragment.catalogues = catalog.catalogues }
        if entityTypes.contains(.archiveCatalogue) {
            fragment.archiveCatalogues = catalog.archiveCatalogues
        }
        if entityTypes.contains(.item) { fragment.items = catalog.items }
        if entityTypes.contains(.commerceSnapshot) {
            fragment.commerceSnapshots = catalog.commerceSnapshots
        }
        if entityTypes.contains(.commerceProduct) { fragment.commerceItems = catalog.commerceItems }
        if entityTypes.contains(.coordinate) { fragment.coordinates = catalog.coordinates }
        if entityTypes.contains(.story) { fragment.stories = catalog.stories }
        if entityTypes.contains(.event) { fragment.events = catalog.events }
        if entityTypes.contains(.historyEntry) { fragment.historyEntries = catalog.historyEntries }
        // 年度卡片始终跟随目录类内容，否则年鉴界面会缺年份
        if entityTypes.contains(.archiveCatalogue) || entityTypes.contains(.historyEntry)
            || entityTypes.contains(.brand)
        {
            fragment.timelineYears = catalog.timelineYears
        }
        return fragment
    }

    /// 整馆 catalog 的完整分片视图
    static func fullFragment(from catalog: TimeHallCatalogDTO) -> TimeHallCatalogFragmentDTO {
        fragment(from: catalog, entityTypes: Set(TimeHallEntityType.allCases))
    }

    // MARK: Bundle 图片（离线种子媒体）

    private static let imageSubdir = "TimeHall/images"

    /// 在 Bundle 中定位离线种子图片。
    ///
    /// 这是**种子媒体**路径，不是云端媒体路径；云端媒体由 `TimeHallMediaCache` 负责。
    static func bundleImageURL(named fileName: String, in bundle: Bundle = .main) -> URL? {
        let ns = fileName as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension.isEmpty ? nil : ns.pathExtension
        let candidates: [URL?] = [
            bundle.url(forResource: fileName, withExtension: nil, subdirectory: imageSubdir),
            bundle.url(forResource: base, withExtension: ext, subdirectory: imageSubdir),
            bundle.url(
                forResource: fileName, withExtension: nil,
                subdirectory: "Resources/\(imageSubdir)"),
            bundle.url(forResource: base, withExtension: ext),
            bundle.url(forResource: fileName, withExtension: nil),
        ]
        return candidates.compactMap { $0 }.first
            ?? bundle.urls(forResourcesWithExtension: ext, subdirectory: nil)?.first {
                $0.lastPathComponent.caseInsensitiveCompare(fileName) == .orderedSame
            }
    }
}
