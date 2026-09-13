import Foundation
import UIKit

// MARK: - 统一读取仓储
//
// 对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md §10.1 / §11。
//
// **读取顺序**：先读本地让页面快速出现，需要时再访问云端。
// **内容生效规则**：撤回控制优先；同一覆盖范围采用有效且较新的发布版本；
// 不能因为某内容来自 Bundle 就永久压过云端修订。
//
//   本地撤回 / 禁用控制
//     > 当前有效且较新的分片快照
//     > 该范围的较旧可用缓存或 Bundle
//
// 本 actor 只做读取与本地缓存决策，**不提供任何公共库写能力**（§10.1）。

/// 本地合成的中间结果
private struct TimeHallLocalComposition {
    var fragment = TimeHallCatalogFragmentDTO()
    var partitionCoverage: [String: TimeHallCoverageStatus] = [:]
    var dayCoverage: [String: TimeHallCoverageStatus] = [:]
    var source: TimeHallDataSource = .none
    var isFullyInstalled = false
    var lastValidatedAt: Date?
    var usedBundle = false
    var usedCache = false
}

actor TimeHallRepository {
    // MARK: 依赖

    private let layout: TimeHallCacheLayout
    private let limits: TimeHallCacheLimits
    private let freshness: TimeHallFreshnessPolicy
    private let packCache: TimeHallPackCache
    private let mediaCache: TimeHallMediaCache
    /// 公共库只读通道。为 nil 表示本构建未接入云端，只消费 Bundle 与本地缓存。
    private let cloudReader: (any TimeHallPublicReading)?
    private let bundle: Bundle
    private let fileManager: FileManager
    private let clock: @Sendable () -> Date

    // MARK: 状态

    private var isLoaded = false
    private var seeds: [String: TimeHallBundleSeed] = [:]
    private var seedOrder: [String] = []
    private var cachedRelease: TimeHallReleaseMetadata?
    private var cachedRootIndex: TimeHallRootIndex?
    private var controlState: TimeHallControlState = .empty
    private var lastReleaseCheckAt: Date?
    private var inFlight: [String: Task<TimeHallReadResult, Never>] = [:]

    init(
        layout: TimeHallCacheLayout = .live(),
        limits: TimeHallCacheLimits = .default,
        freshness: TimeHallFreshnessPolicy = .default,
        packCache: TimeHallPackCache? = nil,
        mediaCache: TimeHallMediaCache? = nil,
        cloudReader: (any TimeHallPublicReading)? = nil,
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.layout = layout
        self.limits = limits
        self.freshness = freshness
        self.packCache =
            packCache ?? TimeHallPackCache(layout: layout, limits: limits, fileManager: fileManager)
        self.mediaCache =
            mediaCache ?? TimeHallMediaCache(layout: layout, limits: limits, fileManager: fileManager)
        self.cloudReader = cloudReader
        self.bundle = bundle
        self.fileManager = fileManager
        self.clock = clock
    }

    // MARK: 初始化

    /// 载入 Bundle 种子与最小控制状态。
    ///
    /// 种子只读一次并常驻：`catalog.json` 是 MB 级文件，重复解码是纯浪费。
    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        for seed in TimeHallBundleSource.loadSeeds(in: bundle) {
            seeds[seed.brand.brandID] = seed
            seedOrder.append(seed.brand.brandID)
        }
        loadControlState()
    }

    private func loadControlState() {
        guard let data = try? Data(contentsOf: layout.controlFileURL) else { return }
        guard let decoded = try? JSONDecoder().decode(TimeHallControlState.self, from: data) else {
            return
        }
        controlState = decoded
    }

    private func persistControlState() {
        do {
            try fileManager.createDirectory(
                at: layout.supportRoot, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(controlState).write(to: layout.controlFileURL, options: .atomic)
        } catch {
            // 控制状态写失败：下次启动回退到上一份有效状态，
            // 不会因为写失败而丢掉已安装的数据包。
        }
    }

    // MARK: 品牌

    func brandDescriptors() -> [TimeHallBrandDescriptor] {
        loadIfNeeded()
        var result: [TimeHallBrandDescriptor] = seedOrder.compactMap { seeds[$0]?.brand }
        if let cachedRootIndex {
            for brand in cachedRootIndex.brands
            where !result.contains(where: { $0.brandID == brand.brandID }) {
                result.append(brand)
            }
        }
        return result
    }

    func primaryBrandID() -> String {
        TimeHallBundleSource.primaryBrandID
    }

    func lastCheckedAt() -> Date? {
        lastReleaseCheckAt ?? controlState.lastCheckedAt
    }

    func controlStateSnapshot() -> TimeHallControlState {
        loadIfNeeded()
        return controlState
    }

    // MARK: 对外读取

    func read(_ request: TimeHallRequest) async -> TimeHallReadResult {
        await performRead(request)
    }

    /// 手动刷新：可跳过本地新鲜度间隔，但不能跳过服务端重试等待要求（§11.6）。
    func refresh(_ request: TimeHallRequest) async -> TimeHallReadResult {
        let forced = TimeHallRequest(
            brandID: request.brandID,
            entityTypes: request.entityTypes,
            recentDayCount: request.recentDayCount,
            referenceDate: request.referenceDate,
            allowsNetwork: request.allowsNetwork,
            forcesRefresh: true
        )
        return await performRead(forced)
    }

    /// 供展示层使用的完整目录快照。
    ///
    /// 界面仍然消费 `TimeHallCatalogDTO`，但内容的合成与撤回过滤统一在本仓储内完成，
    /// 展示层不再自己做合并决策（§10.1 保留 View 使用方式、内部拆分职责）。
    func displayCatalog(
        brandID: String,
        entityTypes: Set<TimeHallEntityType> = Set(TimeHallEntityType.allCases),
        recentDayCount: Int? = nil,
        referenceDate: Date = Date()
    ) async -> TimeHallCatalogDTO? {
        loadIfNeeded()
        let timeZone = businessTimeZone(brandID: brandID)
        let dayKeys: [String] =
            recentDayCount.map {
                TimeHallBusinessCalendar.recentDayKeys(
                    referenceDate: referenceDate, count: $0, timeZone: timeZone)
            } ?? []
        var composition = await composeLocalFragment(
            brandID: brandID, entityTypes: entityTypes, dayKeys: dayKeys)
        composition.fragment = composition.fragment.filteringWithdrawn(
            canonicalIDs: controlState.withdrawnSet, brandID: brandID)

        let templateSeed = seeds[brandID] ?? seeds[TimeHallBundleSource.primaryBrandID]
        guard let templateSeed else { return nil }
        return templateSeed.template.makeCatalog(fragment: composition.fragment)
    }

    // MARK: 读取主流程（§11.2）

    private func performRead(_ request: TimeHallRequest) async -> TimeHallReadResult {
        let key = request.deduplicationKey
        if let existing = inFlight[key] {
            // 同一分片的并发请求合并为一项任务（§11.6）
            return await existing.value
        }
        let task = Task { [weak self] () -> TimeHallReadResult in
            guard let self else {
                return TimeHallReadResult.empty(brandID: request.brandID, error: .unknown)
            }
            return await self.readWithoutDeduplication(request)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func readWithoutDeduplication(_ request: TimeHallRequest) async -> TimeHallReadResult {
        loadIfNeeded()

        var diagnostics: [String] = []
        let brandID = request.brandID
        guard !brandID.isEmpty else {
            return TimeHallReadResult.empty(brandID: brandID, error: .invalidIdentifier)
        }

        // 1. 规范化业务时区与日期范围（用来源时区，不用设备时区）
        let timeZone = businessTimeZone(brandID: brandID)
        let dayKeys: [String] =
            request.recentDayCount.map {
                TimeHallBusinessCalendar.recentDayKeys(
                    referenceDate: request.referenceDate, count: $0, timeZone: timeZone)
            } ?? []
        if !dayKeys.isEmpty { diagnostics.append("days=\(dayKeys.count)") }

        // 2 + 3. 撤回过滤 + 本地合成，立即得到可展示快照
        var composition = await composeLocalFragment(
            brandID: brandID, entityTypes: request.entityTypes, dayKeys: dayKeys)
        composition.fragment = composition.fragment.filteringWithdrawn(
            canonicalIDs: controlState.withdrawnSet, brandID: brandID)

        // 品牌完全未知：既无种子，根清单里也没有它
        if seeds[brandID] == nil, let cachedRootIndex, cachedRootIndex.brand(brandID) == nil {
            return makeResult(
                composition: composition,
                status: .failed(error: .brandNotSupported),
                brandID: brandID,
                diagnostics: diagnostics + ["brand.notSupported"],
                error: .brandNotSupported
            )
        }

        // 4 + 5. 是否需要检查发布头
        let needsCheck = shouldCheckRelease(request: request)
        guard needsCheck, request.allowsNetwork, let reader = cloudReader else {
            let status = offlineStatus(
                composition: composition,
                shouldRetry: cloudReader != nil && needsCheck
            )
            return makeResult(
                composition: composition,
                status: status,
                brandID: brandID,
                diagnostics: diagnostics + ["skip.cloudCheck"],
                error: nil
            )
        }

        // 6–14. 云端确认与按需补全
        do {
            diagnostics += try await synchronize(request: request, reader: reader)
        } catch let error as TimeHallReadError {
            // 16. 失败时保留已有合法数据，返回明确的失败 / 陈旧状态
            let status: TimeHallReadStatus =
                composition.fragment.isEmpty
                ? .failed(error: error)
                : .stale(reason: staleReason(for: error))
            return makeResult(
                composition: composition, status: status, brandID: brandID,
                diagnostics: diagnostics + ["sync.failed=\(error.rawValue)"], error: error)
        } catch {
            let status: TimeHallReadStatus =
                composition.fragment.isEmpty
                ? .failed(error: .unknown) : .stale(reason: .cloudUnavailable)
            return makeResult(
                composition: composition, status: status, brandID: brandID,
                diagnostics: diagnostics + ["sync.failed=unknown"], error: .unknown)
        }

        // 15. 同步成功后重新合成，拿到刚安装的分片
        composition = await composeLocalFragment(
            brandID: brandID, entityTypes: request.entityTypes, dayKeys: dayKeys)
        composition.fragment = composition.fragment.filteringWithdrawn(
            canonicalIDs: controlState.withdrawnSet, brandID: brandID)

        return makeResult(
            composition: composition,
            status: resolvedStatus(composition: composition, request: request),
            brandID: brandID,
            diagnostics: diagnostics,
            error: nil
        )
    }

    // MARK: 本地合成（§11.5）

    private func composeLocalFragment(
        brandID: String,
        entityTypes: Set<TimeHallEntityType>,
        dayKeys: [String]
    ) async -> TimeHallLocalComposition {
        var composition = TimeHallLocalComposition()

        // 更新版本优先：先按分片修订号、再按安装时间排序，保证「较新的发布版本」胜出
        let installed = await packCache.installedPacks(brandID: brandID)
            .sorted { lhs, rhs in
                if lhs.partitionRevision != rhs.partitionRevision {
                    return lhs.partitionRevision > rhs.partitionRevision
                }
                return lhs.installedAt > rhs.installedAt
            }

        var installedFragment = TimeHallCatalogFragmentDTO()
        var installedAny = false
        // 已被「完整 / 明确为空」快照覆盖的实体类型，Bundle 旧条目**不得**再拼回来（§11.5）
        var supersededEntityTypes: Set<TimeHallEntityType> = []

        for record in installed where entityTypes.contains(record.entityType) {
            composition.partitionCoverage[record.partitionID] = record.coverageStatus
            for (day, status) in record.dayCoverage {
                composition.dayCoverage[day] = status
            }
            if record.coverageStatus == .complete || record.coverageStatus == .empty {
                supersededEntityTypes.insert(record.entityType)
            }
            // 已撤回 / 不提供的分片不参与展示
            guard record.coverageStatus.allowsDisplay else { continue }
            guard let fragment = try? await packCache.fragment(partitionID: record.partitionID) else {
                continue
            }
            installedFragment.merge(fragment)
            installedAny = true
            let candidate = record.installedAt
            composition.lastValidatedAt = composition.lastValidatedAt.map {
                max($0, candidate)
            } ?? candidate
        }
        if installedAny { composition.usedCache = true }

        // Bundle 种子补齐缺口
        var bundleFragment = TimeHallCatalogFragmentDTO()
        if let seed = seeds[brandID], !isBrandDisabled(brandID) {
            for partition in seed.partitions where entityTypes.contains(partition.entityType) {
                if composition.partitionCoverage[partition.partitionID] == nil {
                    composition.partitionCoverage[partition.partitionID] = partition.coverageStatus
                }
            }
            let allowedTypes = entityTypes.subtracting(supersededEntityTypes)
            bundleFragment = TimeHallBundleSource.fragment(
                from: seed.catalog, entityTypes: allowedTypes)
            composition.usedBundle = !bundleFragment.isEmpty
        }

        // 先放云端/缓存内容，再让 Bundle 只填缺口（merge 保留先出现者）
        var merged = installedFragment
        merged.merge(bundleFragment)
        if !dayKeys.isEmpty {
            merged.events = filteredEvents(merged.events, dayKeys: dayKeys)
        }
        composition.fragment = merged

        switch (composition.usedCache, composition.usedBundle) {
        case (true, true): composition.source = .mixed
        case (true, false): composition.source = .downloadedCache
        case (false, true): composition.source = .bundle
        case (false, false): composition.source = .none
        }

        composition.isFullyInstalled = isFullyInstalled(brandID: brandID, entityTypes: entityTypes)
        return composition
    }

    /// 近三天的判定不能只看条目日期是否存在，还要看覆盖状态与检查时间（§11.4）。
    private func filteredEvents(
        _ events: [TimeHallEventDTO],
        dayKeys: [String]
    ) -> [TimeHallEventDTO] {
        let window = Set(dayKeys)
        return events.filter { window.contains($0.publishedOn) }
            .sorted { $0.publishedOn > $1.publishedOn }
    }

    private func businessTimeZone(brandID: String) -> TimeZone {
        seeds[brandID]?.brand.businessTimeZone
            ?? TimeZone(identifier: "Asia/Tokyo")
            ?? TimeZone(secondsFromGMT: 9 * 3600)!
    }

    private func isBrandDisabled(_ brandID: String) -> Bool {
        controlState.disabledBrandIDs.contains(brandID)
    }

    private func isFullyInstalled(
        brandID: String,
        entityTypes: Set<TimeHallEntityType>
    ) -> Bool {
        guard cloudReader != nil else {
            // 未接入云端：Bundle 就是权威来源
            return seeds[brandID] != nil
        }
        guard let cachedRootIndex else { return false }
        let required = cachedRootIndex.partitions(brandID: brandID, entityTypes: entityTypes)
        guard !required.isEmpty else { return true }
        return required.allSatisfy { $0.coverageStatus.isConclusive }
    }

    // MARK: 云端同步（§11.2 步骤 6–14）

    private func shouldCheckRelease(request: TimeHallRequest) -> Bool {
        if request.forcesRefresh { return true }
        guard let lastCheck = lastReleaseCheckAt ?? controlState.lastCheckedAt else { return true }
        return clock().timeIntervalSince(lastCheck) >= freshness.releaseCheckInterval
    }

    private func synchronize(
        request: TimeHallRequest,
        reader: any TimeHallPublicReading
    ) async throws -> [String] {
        var diagnostics: [String] = []
        // 记录本次同步开始时的 generation，安装时用它拒绝被清理过的旧任务（§13.3）
        let generationBefore = await packCache.currentGeneration()

        // 6. 获取发布头元数据
        let release = try await mapError { try await reader.fetchReleaseMetadata() }
        diagnostics.append("release=\(release.releaseSeq)")
        guard release.isReadableByCurrentClient else {
            throw TimeHallReadError.releaseUnreadable
        }

        // 7. 未改变时只刷新「已检查」时间，不重复下载根清单与大包
        let unchanged =
            cachedRelease?.releaseSeq == release.releaseSeq
            && cachedRelease?.rootIndexHash == release.rootIndexHash
            && cachedRelease?.revocationEpoch == release.revocationEpoch
        if unchanged, cachedRootIndex != nil {
            lastReleaseCheckAt = clock()
            controlState.lastCheckedAt = lastReleaseCheckAt
            persistControlState()
            diagnostics.append("rootIndex.unchanged")
            return diagnostics
        }

        // 8. 有变化时下载并校验根清单
        let downloaded = try await mapError { try await reader.fetchRootIndex(for: release) }
        guard downloaded.isHashMatching else {
            throw TimeHallReadError.rootIndexHashMismatch
        }
        let rootOutcome = TimeHallPublicationValidator.validateRootIndex(downloaded.rootIndex)
        guard rootOutcome.isValid else {
            diagnostics.append("rootIndex.invalid=\(rootOutcome.summary)")
            throw TimeHallReadError.unsupportedSchema
        }

        // 先应用撤回控制，再做任何安装
        apply(rootIndex: downloaded.rootIndex, release: release)
        cachedRootIndex = downloaded.rootIndex
        cachedRelease = release
        diagnostics.append("rootIndex.applied")

        // 9. 确定本次请求所需的分片
        let needed = downloaded.rootIndex.partitions(
            brandID: request.brandID, entityTypes: request.entityTypes)
        guard !needed.isEmpty else {
            diagnostics.append("partitions.none")
            return diagnostics
        }

        // 10 + 11. 终态确定性处理；仅下载本地缺少或 hash 已变化的数据包
        var toDownload: [TimeHallPartitionDescriptor] = []
        for partition in needed {
            if partition.coverageStatus == .withdrawn || partition.coverageStatus == .notSupported {
                continue
            }
            if let installed = await packCache.installedPack(partitionID: partition.partitionID),
                installed.payloadHash == partition.payloadHash,
                installed.partitionRevision == partition.partitionRevision
            {
                continue
            }
            toDownload.append(partition)
        }

        // 关联完整性：先把依赖包补齐（§6.7）
        let dependencies = Set(toDownload.flatMap(\.dependencyPackRecordNames))
        if !dependencies.isEmpty {
            let missing = await missingDependencies(dependencies)
            if !missing.isEmpty {
                diagnostics.append("dependencies.missing=\(missing.count)")
                throw TimeHallReadError.missingDependency
            }
        }

        guard !toDownload.isEmpty else {
            diagnostics.append("packs.upToDate")
            return diagnostics
        }

        // 12–14. 下载、校验、原子安装
        let downloadOutcome = await download(
            partitions: toDownload,
            reader: reader,
            limit: freshness.maxParallelPackDownloads
        )
        diagnostics += downloadOutcome.diagnostics

        for partition in toDownload {
            guard let payload = downloadOutcome.packs[partition.partitionID] else { continue }
            do {
                try await install(
                    partition: partition, payload: payload, generation: generationBefore)
            } catch let error as TimeHallCacheError {
                // 单个分片失败不阻塞其它分片；已安装的旧包保持有效（§16.1）
                diagnostics.append("install.failed=\(partition.partitionID):\(error.readError.rawValue)")
            }
        }
        return diagnostics
    }

    /// 有界并行下载。子任务只做网络 IO，返回后由本 actor 串行校验与安装，
    /// 避免在并发子任务里改动 actor 状态。
    ///
    /// reader 支持批量 fetch 时优先走显式批量抓取，减少往返（§6.6）。
    private func download(
        partitions: [TimeHallPartitionDescriptor],
        reader: any TimeHallPublicReading,
        limit: Int
    ) async -> (packs: [String: TimeHallDownloadedPack], diagnostics: [String]) {
        guard !partitions.isEmpty else { return ([:], []) }
        var packs: [String: TimeHallDownloadedPack] = [:]
        var diagnostics: [String] = []
        let window = max(1, limit)
        let batchReader = reader as? any TimeHallPublicBatchReading

        var cursor = 0
        while cursor < partitions.count {
            let batch = Array(partitions[cursor..<min(cursor + window, partitions.count)])
            cursor += window

            let outcome: [(String, Result<TimeHallDownloadedPack, TimeHallReadError>)]
            if let batchReader {
                let byRecordName = await batchReader.fetchPacks(
                    recordNames: batch.map(\.packRecordName))
                outcome = batch.map { partition in
                    (
                        partition.partitionID,
                        byRecordName[partition.packRecordName] ?? .failure(.missingDependency)
                    )
                }
            } else {
                outcome = await withTaskGroup(
                    of: (String, Result<TimeHallDownloadedPack, TimeHallReadError>).self
                ) { group -> [(String, Result<TimeHallDownloadedPack, TimeHallReadError>)] in
                    for partition in batch {
                        group.addTask {
                            do {
                                let pack = try await reader.fetchPack(
                                    recordName: partition.packRecordName)
                                return (partition.partitionID, .success(pack))
                            } catch let error as TimeHallReadError {
                                return (partition.partitionID, .failure(error))
                            } catch {
                                return (partition.partitionID, .failure(.cloudUnavailable))
                            }
                        }
                    }
                    var collected: [(String, Result<TimeHallDownloadedPack, TimeHallReadError>)] = []
                    for await item in group { collected.append(item) }
                    return collected
                }
            }

            for (partitionID, result) in outcome {
                switch result {
                case .success(let pack): packs[partitionID] = pack
                case .failure(let error):
                    diagnostics.append("download.failed=\(partitionID):\(error.rawValue)")
                }
            }
        }
        return (packs, diagnostics)
    }

    /// 校验并原子安装一个数据包（§11.2 步骤 12–14）。
    ///
    /// **根清单下载成功不代表数据包已安装**，因此逐包独立校验、独立安装，
    /// 任何一步失败都不推进本地安装状态。
    private func install(
        partition: TimeHallPartitionDescriptor,
        payload: TimeHallDownloadedPack,
        generation: UInt64
    ) async throws {
        // 12. 校验声明摘要与大小
        guard payload.payloadHash == partition.payloadHash else {
            throw TimeHallCacheError.checksumMismatch
        }
        guard payload.compressedBytes <= limits.maxPackCompressedBytes,
            payload.jsonData.count <= limits.maxPackUncompressedBytes
        else {
            throw TimeHallCacheError.sizeLimitExceeded
        }

        let decoded: TimeHallPackPayload
        do {
            decoded = try JSONDecoder().decode(TimeHallPackPayload.self, from: payload.jsonData)
        } catch {
            throw TimeHallCacheError.malformedArchive
        }

        // 结构 + 分片契约校验；通过后才允许安装（§1.2 B：先验证后切换）
        let outcome = TimeHallValidationOutcome.merging([
            TimeHallPublicationValidator.validateStructural(
                decoded.records,
                declaredEntityType: partition.entityType,
                brandID: partition.brandID,
                coverageStatus: partition.coverageStatus
            ),
            TimeHallPublicationValidator.validatePartition(
                descriptor: partition,
                payload: decoded,
                compressedBytes: payload.compressedBytes,
                uncompressedBytes: payload.jsonData.count,
                limits: limits
            ),
        ])
        guard outcome.isValid else {
            throw TimeHallCacheError.malformedArchive
        }

        // 13 + 14. 缓存自身再校验 generation 未变，然后原子安装并落索引
        try await packCache.install(
            descriptor: partition, payload: decoded, generation: generation)
    }

    private func missingDependencies(_ recordNames: Set<String>) async -> [String] {
        guard let cachedRootIndex else { return Array(recordNames).sorted() }
        var missing: [String] = []
        for recordName in recordNames.sorted() {
            guard
                let partition = cachedRootIndex.partitions.first(where: {
                    $0.packRecordName == recordName
                })
            else {
                missing.append(recordName)
                continue
            }
            if await packCache.installedPack(partitionID: partition.partitionID) == nil {
                missing.append(recordName)
            }
        }
        return missing
    }

    /// 应用更高 `revocationEpoch` 的撤回控制（§14.1）。
    /// 撤回只增不减，回滚也不能让撤回内容复活（§9.4）。
    private func apply(rootIndex: TimeHallRootIndex, release: TimeHallReleaseMetadata) {
        var next = controlState
        next.revocationEpoch = max(controlState.revocationEpoch, rootIndex.revocationEpoch)
        next.revocationEpoch = max(next.revocationEpoch, release.revocationEpoch)
        next.withdrawnEntityIDs = Array(
            controlState.withdrawnSet.union(rootIndex.withdrawnEntityIDs())
        ).sorted()
        next.withdrawnMediaHashes = Array(
            controlState.withdrawnMediaHashSet.union(rootIndex.withdrawnMediaHashes())
        ).sorted()
        next.lastCheckedAt = clock()
        next.knownReleaseSeq = release.releaseSeq
        next.knownRootIndexHash = release.rootIndexHash
        controlState = next
        lastReleaseCheckAt = next.lastCheckedAt
        persistControlState()
    }

    private func mapError<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as TimeHallReadError {
            throw error
        } catch {
            throw TimeHallReadError.cloudUnavailable
        }
    }

    // MARK: 状态判定（§16.1 错误不是空结果）

    private func offlineStatus(
        composition: TimeHallLocalComposition,
        shouldRetry: Bool
    ) -> TimeHallReadStatus {
        if composition.fragment.isEmpty {
            return shouldRetry ? .failed(error: .cloudUnavailable) : .emptyConfirmed
        }
        guard let cachedRootIndex else {
            return .stale(reason: .bundleOnly)
        }
        let incomplete = cachedRootIndex.partitions.contains {
            !$0.coverageStatus.isConclusive && $0.coverageStatus.allowsDisplay
        }
        return incomplete ? .partial(reason: .coverageIncomplete) : .ok
    }

    private func resolvedStatus(
        composition: TimeHallLocalComposition,
        request: TimeHallRequest
    ) -> TimeHallReadStatus {
        if composition.fragment.isEmpty {
            // 空白只有在覆盖状态明确为 empty 时才算「确认零条」（§5.2）
            let conclusiveEmpty =
                composition.partitionCoverage.values.contains(.empty)
                || (request.recentDayCount != nil && !composition.partitionCoverage.isEmpty
                    && composition.partitionCoverage.values.allSatisfy { $0.isConclusive })
            return conclusiveEmpty ? .emptyConfirmed : .partial(reason: .coverageIncomplete)
        }
        if !composition.isFullyInstalled {
            return .partial(reason: .coverageIncomplete)
        }
        if composition.source == .bundle {
            return .stale(reason: .bundleOnly)
        }
        return .ok
    }

    private func staleReason(for error: TimeHallReadError) -> TimeHallStaleReason {
        switch error {
        case .offline: return .networkUnavailable
        case .permissionDenied: return .permissionDenied
        case .throttled: return .throttled
        case .releaseUnreadable: return .releaseUnreadable
        case .releaseMissing, .brandNotSupported: return .neverChecked
        default: return .cloudUnavailable
        }
    }

    private func makeResult(
        composition: TimeHallLocalComposition,
        status: TimeHallReadStatus,
        brandID: String,
        diagnostics: [String],
        error: TimeHallReadError?
    ) -> TimeHallReadResult {
        let shouldRetry: Bool
        if let error, error.isRetryable {
            shouldRetry = true
        } else {
            shouldRetry = composition.partitionCoverage.values.contains { !$0.isConclusive }
        }
        return TimeHallReadResult(
            fragment: composition.fragment,
            source: composition.source,
            status: status,
            partitionCoverage: composition.partitionCoverage,
            dayCoverage: composition.dayCoverage,
            lastValidatedAt: composition.lastValidatedAt,
            shouldRetry: shouldRetry,
            withdrawnEntityIDs: controlState.withdrawnSet,
            installedReleaseSeq: cachedRelease?.releaseSeq ?? 0,
            isFullyInstalled: composition.isFullyInstalled,
            diagnostics: diagnostics + ["brand=\(brandID)"]
        )
    }

    // MARK: 缓存维护（§13）

    func usage() async -> TimeHallCacheUsage {
        var usage = await packCache.usage()
        let mediaUsage = await mediaCache.usage()
        usage.mediaBytes = mediaUsage.mediaBytes
        usage.mediaCount = mediaUsage.mediaCount
        usage.stagingBytes = max(usage.stagingBytes, mediaUsage.stagingBytes)
        usage.lastCheckedAt = lastCheckedAt()
        return usage
    }

    /// 清理可重新下载的公共资料副本。
    ///
    /// 严格按 §13.3 的顺序：
    ///   1. 递增 generation → 2. 使旧下载任务失效 → 3. 展示快照转向 Bundle
    ///   → 4. 清 packs / media / staging / index → 5. 清空内存图片
    ///   → 6. 重置安装状态 → 7. 保留收藏、私人资产、撤回控制版本 → 8. 后续按需重新拉取
    ///
    /// 清理后**不**立即无条件全量重下，让用户感知清理真实有效（§13.2）。
    func clearDownloadedContent() async throws {
        loadIfNeeded()
        await packCache.bumpGeneration()
        await mediaCache.bumpGeneration()
        try await packCache.clearDownloadedContent()
        try await mediaCache.clearDownloadedContent()
        // 根清单缓存也清掉，下次访问会重新确认当前发布
        cachedRootIndex = nil
        cachedRelease = nil
        // 检查时间重置，否则清缓存后会被新鲜度窗口挡住、迟迟不重新确认
        lastReleaseCheckAt = nil
        controlState.lastCheckedAt = nil
        // 撤回控制版本与撤回清单属于「最小控制状态」，**不随缓存清理删除**
        persistControlState()
    }

    func mediaImage(mediaKey: String, targetPixelDimension: CGFloat = 1200) async -> UIImage? {
        await mediaCache.image(mediaKey: mediaKey, targetPixelDimension: targetPixelDimension)
    }

    func mediaCacheStore() -> TimeHallMediaCache { mediaCache }

    func packCacheStore() -> TimeHallPackCache { packCache }

    /// 来源预览链接。打开链接**不同时触发抓取入库**（§12.1）。
    /// 缺图时显示占位，不悄悄切回任意第三方网址重新获取。
    func sourcePreviewURL(for urlString: String) -> URL? {
        guard let url = URL(string: urlString), url.scheme == "https" else { return nil }
        return url
    }
}

// MARK: - 共享实例

extension TimeHallRepository {
    /// 应用内共享实例。
    ///
    /// 只读通道指向 `iCloud.bugod2.ItemManager` 的公共库；
    /// 若容器标识未配置则退回「只消费本地与 Bundle」模式，界面不白屏（§0.3 第六条约束）。
    static let shared = TimeHallRepository(
        cloudReader: TimeHallPublicCloudReader.makeIfAvailable()
    )
}

// MARK: - 运行时配置

nonisolated enum TimeHallRuntimeConfiguration {
    private static let cloudSyncKey = "timeHall.cloudSync.enabled"

    /// 是否检查线上更新。
    ///
    /// 默认 **关闭**：生产库里还没有第一个 `THRelease` 之前，每次启动都发一次注定
    /// 返回 `unknownItem` 的请求既浪费配额也污染诊断日志。
    /// 运营在 CloudKit Console 建好三种 Record Type 并发布首个版本后，
    /// 在「时光馆下载缓存」页打开此开关（§16.1 / §20.1）。
    ///
    /// 关闭时仍完整读取 Bundle 与本地下载缓存，主功能不受影响（§0.3）。
    static var isCloudSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: cloudSyncKey) }
        set { UserDefaults.standard.set(newValue, forKey: cloudSyncKey) }
    }

    static var cloudSyncDefaultsKey: String { cloudSyncKey }
}
