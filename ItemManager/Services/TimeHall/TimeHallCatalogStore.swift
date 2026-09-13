import Combine
import Foundation
import UIKit

// MARK: - 时光馆展示状态适配层
//
// 对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md §1.2 B / §10.1 / §17.5。
//
// 本类型**只负责展示状态**：
//   - 先验证，通过后才切换为可展示数据（不再「先 `catalog = decoded` 再断言」）；
//   - 内容的合成、撤回过滤、覆盖状态判定统一委托给 `TimeHallRepository`；
//   - 收藏语义委托 `TimeHallUserStateStore`，清理缓存不删除收藏；
//   - 不再承担上传、鉴权或运维逻辑。
//
// 公共读取能力**只读**：这里没有 `savePublicEntry()` / `uploadLocalCatalog()`
// 或 `moderateSubmission()`（§10.1）。

@MainActor
final class TimeHallCatalogStore: ObservableObject {
    static let shared = TimeHallCatalogStore()

    /// 当前展示的目录快照
    @Published private(set) var catalog: TimeHallCatalogDTO?
    /// 收藏标识（`timeHall.treasured.v1`，清理缓存不得删除）
    @Published private(set) var treasuredIDs: Set<String> = []
    /// 品牌数据集校验报告（现有 PINK HOUSE 整馆规则）
    @Published private(set) var validationReport: TimeHallValidationReport
    /// 云端同步状态文案，供界面展示「资料更新于……」/「暂时无法检查」（§4.2 / §11.3）
    @Published private(set) var syncStatusText: String?
    /// 最近一次成功校验时间
    @Published private(set) var lastValidatedAt: Date?
    /// 是否存在被撤回但仍被收藏的条目
    @Published private(set) var unavailableTreasuredIDs: Set<String> = []

    private let repository: TimeHallRepository
    private let userState: TimeHallUserStateStore
    private var didStartCloudRefresh = false
    private var refreshTask: Task<Void, Never>?

    private let imageSubdir = "TimeHall/images"
    private let imageCache = NSCache<NSString, UIImage>()

    init(
        repository: TimeHallRepository = .shared,
        userState: TimeHallUserStateStore = .shared
    ) {
        self.repository = repository
        self.userState = userState
        self.validationReport = Self.emptyReport
        // 先出页面：同步读 Bundle 种子，不等待 CloudKit（§15.3）
        loadSeedCatalog()
        treasuredIDs = userState.treasuredIDs
        refreshUnavailableTreasuredIDs()
    }

    // MARK: 启动加载

    /// Bundle 与多品牌资源目录读取。
    ///
    /// 保留原 API：部分界面按 `catalogResourceName` 加载其它品牌 catalog。
    func bundledCatalog(named resourceName: String) -> TimeHallCatalogDTO? {
        guard
            let url = Self.bundleCatalogURL(resourceName: resourceName, subdirectory: "TimeHall")
                ?? Self.bundleCatalogURL(resourceName: resourceName, subdirectory: "Resources/TimeHall")
                ?? Self.bundleCatalogURL(resourceName: resourceName, subdirectory: nil)
        else { return nil }
        do {
            return try JSONDecoder().decode(TimeHallCatalogDTO.self, from: Data(contentsOf: url))
        } catch {
            return nil
        }
    }

    /// 主品牌 Bundle 种子加载。
    ///
    /// **先验证，通过后才切换为可展示数据**（§1.2 B）。
    private func loadSeedCatalog() {
        guard
            let url = Self.bundleCatalogURL(resourceName: "catalog", subdirectory: "TimeHall")
                ?? Self.bundleCatalogURL(
                    resourceName: "catalog", subdirectory: "Resources/TimeHall")
                ?? Self.bundleCatalogURL(resourceName: "catalog", subdirectory: nil)
        else {
            return
        }
        let decoded: TimeHallCatalogDTO
        do {
            decoded = try JSONDecoder().decode(TimeHallCatalogDTO.self, from: Data(contentsOf: url))
        } catch {
            return
        }

        let report = Self.validate(decoded)
        guard report.isCatalogValid else {
            // 校验不通过：**不**把这份数据交给 UI，保留上一份有效快照
            validationReport = report
            assert(false, "TimeHall catalog must pass integrity and dedup validation")
            return
        }
        catalog = decoded
        validationReport = report
    }

    private static func bundleCatalogURL(resourceName: String, subdirectory: String?) -> URL? {
        Bundle.main.url(forResource: resourceName, withExtension: "json", subdirectory: subdirectory)
    }

    // MARK: 云端只读刷新

    /// 触发一次云端确认与按需补全。首屏不等待它（§15.3）。
    func startCloudRefreshIfNeeded(force: Bool = false) {
        guard force || !didStartCloudRefresh else { return }
        didStartCloudRefresh = true
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performCloudRefresh()
        }
    }

    func refreshFromCloud() async {
        await performCloudRefresh()
    }

    private func performCloudRefresh() async {
        guard TimeHallRuntimeConfiguration.isCloudSyncEnabled else {
            syncStatusText = nil
            return
        }
        let brandID = await repository.primaryBrandID()
        let result = await repository.read(
            TimeHallRequest(brandID: brandID, entityTypes: Set(TimeHallEntityType.allCases))
        )
        guard !Task.isCancelled else { return }

        syncStatusText = statusText(for: result)
        lastValidatedAt = result.lastValidatedAt
        unavailableTreasuredIDs = userState.withdrawnTreasuredIDs(
            withdrawn: result.withdrawnEntityIDs)

        // 撤回内容不得回退到旧 Bundle；确认无内容时也不覆盖现有快照
        if case .failed = result.status { return }
        if result.fragment.isEmpty {
            guard case .emptyConfirmed = result.status else { return }
        }

        // 合并快照只做与覆盖范围无关的通用结构校验
        let outcome = TimeHallPublicationValidator.validateMergedFragment(
            result.fragment, brandID: brandID)
        guard outcome.isValid else { return }
        guard
            let updated = await repository.displayCatalog(
                brandID: brandID,
                entityTypes: Set(TimeHallEntityType.allCases)
            )
        else { return }
        guard !Task.isCancelled else { return }

        // 通过校验后才切换（此时才允许进入 UI）
        catalog = updated
    }

    private func statusText(for result: TimeHallReadResult) -> String {
        switch result.status {
        case .ok:
            return sourceNote(result)
        case .emptyConfirmed:
            return result.source.labelZH + " · 暂无内容"
        case .stale(let reason), .partial(let reason):
            return result.source.labelZH + " · " + reason.labelZH
        case .failed(let error):
            return error.labelZH
        }
    }

    private func sourceNote(_ result: TimeHallReadResult) -> String {
        guard let lastValidatedAt = result.lastValidatedAt else {
            return result.source.labelZH
        }
        return result.source.labelZH + " · 资料校验于 " + Self.timeFormatter.string(from: lastValidatedAt)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    // MARK: 只读投影（沿用原有 API，界面无需改动）

    var items: [TimeHallItemDTO] { catalog?.items ?? [] }

    var dresses: [TimeHallItemDTO] { items.filter { $0.kind == .dress } }

    var accessories: [TimeHallItemDTO] { items.filter { $0.kind == .accessory } }

    var clothing: [TimeHallItemDTO] { items.filter { $0.kind == .clothing } }

    var catalogues: [TimeHallCatalogueDTO] { catalog?.catalogues ?? [] }

    var archiveCatalogues: [TimeHallArchiveCatalogueDTO] { catalog?.archiveCatalogues ?? [] }

    var importBatches: [TimeHallImportBatchDTO] {
        (catalog?.importBatches ?? []).sorted { $0.order < $1.order }
    }

    var commerceSnapshots: [TimeHallCommerceSnapshotDTO] {
        (catalog?.commerceSnapshots ?? []).sorted { $0.observedAt > $1.observedAt }
    }

    var commerceItems: [TimeHallCommerceItemDTO] { catalog?.commerceItems ?? [] }

    var coordinates: [TimeHallCoordinateDTO] { catalog?.coordinates ?? [] }

    var stories: [TimeHallStoryDTO] {
        (catalog?.stories ?? []).sorted { ($0.publishedOn ?? "") > ($1.publishedOn ?? "") }
    }

    var events: [TimeHallEventDTO] {
        (catalog?.events ?? []).sorted { $0.publishedOn > $1.publishedOn }
    }

    func events(for year: Int) -> [TimeHallEventDTO] {
        events.filter { $0.publishedOn.hasPrefix("\(year)-") }
    }

    func historyEntries(for year: Int) -> [TimeHallHistoryEntryDTO] {
        (catalog?.historyEntries ?? []).filter { $0.year == year }
    }

    func commerceItems(in snapshot: TimeHallCommerceSnapshotDTO) -> [TimeHallCommerceItemDTO] {
        let itemByID = Dictionary(commerceItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return snapshot.itemIDs.compactMap { itemByID[$0] }
    }

    var timelineYears: [TimeHallYearRecordDTO] {
        (catalog?.timelineYears ?? []).sorted { $0.year > $1.year }
    }

    var years: [Int] { timelineYears.map(\.year) }

    func yearRecord(for year: Int) -> TimeHallYearRecordDTO? {
        timelineYears.first { $0.year == year }
    }

    func archiveCatalogues(for year: Int) -> [TimeHallArchiveCatalogueDTO] {
        archiveCatalogues.filter { $0.year == year }
    }

    func items(in catalogue: TimeHallCatalogueDTO) -> [TimeHallItemDTO] {
        let map = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return catalogue.itemIds.compactMap { map[$0] }
    }

    func catalogues(for year: Int) -> [TimeHallCatalogueDTO] {
        catalogues.filter { $0.year == year }
    }

    func styleBubbles() -> [TimeHallStyleBubble] {
        var counts: [String: Int] = [:]
        for item in items {
            for tag in item.stylesZH where !tag.isEmpty {
                counts[tag, default: 0] += 1
            }
        }
        return
            counts
            .map { TimeHallStyleBubble(id: $0.key, label: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.label < rhs.label
            }
    }

    func items(withStyle label: String) -> [TimeHallItemDTO] {
        items.filter { $0.stylesZH.contains(label) || $0.styles.contains(label) }
    }

    // MARK: 收藏（不是缓存）

    func isTreasured(_ id: String) -> Bool {
        treasuredIDs.contains(id)
    }

    func toggleTreasure(_ id: String) {
        userState.toggle(id)
        treasuredIDs = userState.treasuredIDs
        refreshUnavailableTreasuredIDs()
    }

    /// 已被撤回、但收藏关系保留的条目：界面显示「原图鉴资料已不可用」（§14.3）。
    func isUnavailable(_ id: String) -> Bool {
        unavailableTreasuredIDs.contains(id)
    }

    private func refreshUnavailableTreasuredIDs() {
        guard !unavailableTreasuredIDs.isEmpty else { return }
        unavailableTreasuredIDs = unavailableTreasuredIDs.intersection(treasuredIDs)
    }

    // MARK: 图片

    /// 同步取图：内存缓存 → Bundle 离线种子。
    ///
    /// 下载媒体的异步路径见 `loadImage(named:)`。
    func image(named fileName: String?) -> UIImage? {
        guard let fileName, !fileName.isEmpty else { return nil }
        if let cached = imageCache.object(forKey: fileName as NSString) {
            return cached
        }
        guard let url = imageURL(named: fileName), let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        imageCache.setObject(image, forKey: fileName as NSString)
        return image
    }

    /// 异步取图：媒体缓存（经授权可重分发的下载图）优先，其次 Bundle 离线种子。
    ///
    /// 媒体键与 Bundle 文件名共用同一套稳定文件名，因此新下载的媒体会自然取代旧种子图。
    /// 两处都没有时返回 `nil`，由界面显示占位——**不切换回第三方网址**（§12.1）。
    func loadImage(named fileName: String?) async -> UIImage? {
        guard let fileName, !fileName.isEmpty else { return nil }
        let cacheKey = fileName as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        if let downloaded = await repository.mediaImage(
            mediaKey: fileName, targetPixelDimension: 1200)
        {
            guard !Task.isCancelled else { return nil }
            let cost = downloaded.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            imageCache.setObject(downloaded, forKey: cacheKey, cost: cost)
            return downloaded
        }

        guard let url = imageURL(named: fileName) else { return nil }
        let image = await Task.detached(priority: .userInitiated) {
            TimeHallImageDownsampler.load(url: url, maxPixelDimension: 1200)
        }.value
        guard let image, !Task.isCancelled else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        imageCache.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }

    private func imageURL(named fileName: String) -> URL? {
        TimeHallBundleSource.bundleImageURL(named: fileName)
    }

    // MARK: 校验（品牌数据集规则）

    /// 现有 PINK HOUSE 整馆验收规则。测试与 Bundle 种子加载都依赖这个签名。
    ///
    /// 规则本体已迁入 `TimeHallPublicationValidator.validateBrandDataset`，
    /// 这里只做转发，避免两处维护同一套判定。
    nonisolated static func validate(_ catalog: TimeHallCatalogDTO) -> TimeHallValidationReport {
        TimeHallPublicationValidator.validateBrandDataset(catalog)
    }

    nonisolated private static var emptyReport: TimeHallValidationReport {
        TimeHallValidationReport(
            dressCount: 0,
            clothingCount: 0,
            accessoryCount: 0,
            catalogueCount: 0,
            timelineYearCount: 0,
            archiveCatalogueCount: 0,
            commerceSnapshotCount: 0,
            commerceItemCount: 0,
            coordinateCount: 0,
            storyCount: 0,
            eventCount: 0,
            historyEntryCount: 0,
            importBatchCount: 0,
            catalogErrors: [],
            duplicateItemIDs: [],
            duplicateCatalogueIDs: [],
            duplicateArchiveCatalogueIDs: [],
            duplicateImportBatchIDs: [],
            duplicateCommerceSnapshotIDs: [],
            duplicateCommerceItemIDs: [],
            duplicateCommerceProductCodes: [],
            duplicateCoordinateIDs: [],
            duplicateStoryIDs: [],
            duplicateEventIDs: [],
            duplicateHistoryEntryIDs: [],
            duplicateTimelineYears: [],
            duplicateCanonicalKeys: [],
            duplicateCatalogueItemIDs: [],
            missingCatalogueItemIDs: [],
            orphanItemIDs: [],
            invalidCatalogueIDs: [],
            invalidArchiveCatalogueIDs: [],
            invalidImportBatchIDs: [],
            invalidCommerceSnapshotIDs: [],
            invalidCommerceItemIDs: [],
            invalidCoordinateIDs: [],
            invalidStoryIDs: [],
            invalidEventIDs: [],
            invalidHistoryEntryIDs: [],
            invalidTimelineYears: [],
            invalidItemIDs: []
        )
    }
}
