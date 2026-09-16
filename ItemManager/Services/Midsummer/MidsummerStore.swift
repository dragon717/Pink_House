import Combine
import Foundation
// MARK: - Bundle 种子
//
// `ItemManager/Resources/Midsummer/midsummer-series.json`
// 与 TimeHall 的多品牌 catalog 一样随包分发，保证未登录 iCloud、断网、
// 或公共库还没配置时页面依然有内容（不白屏）。

nonisolated enum MidsummerSeedCatalog {
  static let resourceName = "midsummer-series"
  static let subdirectory = "Midsummer"

  static func load(bundle: Bundle = .main) -> MidsummerCatalogDTO? {
    guard let url = url(in: bundle) else {
      print("⚠️ [Midsummer] 未找到 \(resourceName).json")
      return nil
    }
    do {
      let data = try Data(contentsOf: url)
      return try JSONDecoder().decode(MidsummerCatalogDTO.self, from: data)
    } catch {
      print("⚠️ [Midsummer] 种子解码失败：\(error.localizedDescription)")
      return nil
    }
  }

  private static func url(in bundle: Bundle) -> URL? {
    bundle.url(forResource: resourceName, withExtension: "json", subdirectory: subdirectory)
      ?? bundle.url(forResource: resourceName, withExtension: "json", subdirectory: "Resources/\(subdirectory)")
      ?? bundle.url(forResource: resourceName, withExtension: "json")
  }
}

// MARK: - 状态层
//
// 数据来源优先级（§T4 云端优先、本地兜底）：
//   CloudKit 创作者上传  >  Bundle 种子
//
// 合并按 `series.id` 进行：云端同 id 覆盖种子（视为创作者校正），
// 种子独有的系列保留——云端是**补充**，不是替换，否则首次上传会把整个历史抹掉。

@MainActor
final class MidsummerStore: ObservableObject {
  static let shared = MidsummerStore()

  /// 界面唯一数据源（种子与云端合并后的结果）
  @Published private(set) var catalog: MidsummerCatalogDTO?
  @Published private(set) var syncStatusText: String?
  @Published private(set) var isRefreshingCloud = false
  /// CloudKit 管理员白名单的判定结果。模拟器 / 未登录 iCloud / 非白名单账号下为 false。
  @Published private(set) var isAdminUser = false
  /// 三态白名单判定结果（含「取不到身份」这一态）。上传入口的显示门控看它。
  @Published private(set) var creatorGate: NoticeCloudKitService.CreatorGate = .unresolved(
    reason: "尚未判定"
  )
  /// 上传入口的显示门控。
  ///
  /// 三态语义（使用者的明确要求：「不在白名单里就不该显示」）：
  ///   · `allowed`    → 显示
  ///   · `denied`     → **不显示**，本机「创作者模式」开关也不能撬开
  ///   · `unresolved` → 身份取不到（模拟器 / 未登录 iCloud / 断网）。
  ///                    此时不能等同于「不是运营」，否则内容维护者在模拟器上永远没有入口，
  ///                    所以允许「创作者模式」开关解界面闸门。
  ///
  /// ⚠️ 只是**界面闸门**，不是安全边界——真正的写入权限在 CloudKit Console 的
  /// Security Roles（见 docs/MIDSUMMER_TALE_CLOUDKIT_SETUP.md §2）。
  var canContribute: Bool {
    switch creatorGate {
    case .allowed:
      return true
    case .denied:
      return false
    case .unresolved:
      return CreatorMode.isEnabledInDefaults()
    }
  }
  /// 本次会话内成功上传、但云端还没回读到的条目（乐观更新用）
  @Published private(set) var pendingUploads: [MidsummerSeriesDTO] = []

  private let seed: MidsummerCatalogDTO?
  private var cloudSeries: [MidsummerSeriesDTO] = []
  private var didStartCloudRefresh = false
  /// 上新工作台（`MidsummerListingStore`）的变更订阅：上架 / 下架 / 编辑后
  /// 立即重算 catalog，让系列 feed 跟着变，不需要手动刷新。
  private var listingSubscription: AnyCancellable?

  init(bundle: Bundle = .main) {
    seed = MidsummerSeedCatalog.load(bundle: bundle)
    recomputeCatalog()
    // 上新工作台存档变更 → 重算 feed。receive(on:) 跳出 willSet 时机，
    // 保证重算读到的是**已落好**的新 listings，而不是变更前的旧值。
    listingSubscription = MidsummerListingStore.shared.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in self?.recomputeCatalog() }
      }
    // 随包种子图 → 用户 Images 目录（幂等，后台执行不阻塞首屏）。
    // 导入完成后 nudge 一次：若视图在拷贝完成前已经渲染过封面/缩略图，
    // 让它们重新取图，避免首启停在占位图上。
    Task { [weak self] in
      await MidsummerSeedImageImporter.importIfNeeded()
      self?.objectWillChange.send()
    }
  }

  // MARK: - 投影

  /// 图一左栏的年份导航：倒序，并标注该年是否处于「新品预约」阶段。
  var yearEntries: [MidsummerYearEntry] {
    guard let catalog else { return [] }
    return catalog.years.map { year in
      let series = catalog.series(inYear: year)
      return MidsummerYearEntry(
        year: year,
        hasPreorder: series.contains { $0.stage == .deposit || $0.stage == .preview },
        seriesCount: series.count
      )
    }
  }

  var allSeries: [MidsummerSeriesDTO] { catalog?.series ?? [] }

  var isEmpty: Bool { allSeries.isEmpty }

  func series(withID id: String) -> MidsummerSeriesDTO? {
    allSeries.first { $0.id == id }
  }

  /// 品牌页主列表：按年份 + 系列筛选后的「系列 × 单品」扁平流（对应图一的商品卡片）。
  func itemFeed(year: Int?, seriesID: String?) -> [(series: MidsummerSeriesDTO, item: MidsummerItemDTO)] {
    var series = allSeries
    if let year { series = series.filter { $0.year == year } }
    if let seriesID { series = series.filter { $0.id == seriesID } }
    return series.flatMap { series in series.items.map { (series, $0) } }
  }

  /// 商品卡片总数——为 0 时界面应给出「该筛选下暂无收录」而不是空屏。
  func itemCount(year: Int?, seriesID: String?) -> Int {
    itemFeed(year: year, seriesID: seriesID).count
  }

  /// 待补充项统计，用于在界面上如实展示「资料不完整」。
  var pendingFieldCount: Int {
    allSeries.reduce(0) { partial, series in
      var count = partial
      if series.launchedOn.isEmpty { count += 1 }
      if !series.hasPrice { count += 1 }
      if series.sizes.isEmpty { count += 1 }
      count += series.items.filter { !$0.hasPrice }.count
      return count
    }
  }

  // MARK: - 云端刷新

  func startCloudRefreshIfNeeded(force: Bool = false) {
    guard force || !didStartCloudRefresh else { return }
    didStartCloudRefresh = true
    Task { await refreshFromCloud() }
  }

  func refreshFromCloud() async {
    isRefreshingCloud = true
    defer { isRefreshingCloud = false }

    creatorGate = await MidsummerCloudService.shared.creatorGate()
    isAdminUser = (creatorGate == .allowed)

    guard let remote = await MidsummerCloudService.shared.fetchSeries() else {
      // 读取失败/无数据都不是错误状态：种子已经铺满页面，这里只更新一句状态文案
      syncStatusText = seed == nil
        ? "暂时无法读取线上内容"
        : "当前显示随包资料（线上内容读取不到）"
      return
    }

    cloudSeries = remote
    recomputeCatalog()
    syncStatusText = "线上资料已更新 · \(remote.count) 个创作者补充系列"
  }

  // MARK: - 上传后的乐观更新

  /// 创作者刚上传成功时立刻插到列表里，无需等下一次云端刷新。
  func applyUploaded(series: MidsummerSeriesDTO) {
    cloudSeries.removeAll { $0.id == series.id }
    cloudSeries.append(series)
    pendingUploads.removeAll { $0.id == series.id }
    pendingUploads.append(series)
    recomputeCatalog()
  }

  private func recomputeCatalog() {
    guard let seed else {
      catalog = nil
      return
    }

    var byID: [String: MidsummerSeriesDTO] = [:]
    for series in seed.series { byID[series.id] = series }
    // 云端覆盖同 id（创作者校正），并补充新系列
    for series in cloudSeries { byID[series.id] = series }

    // 上新工作台（用户 2026-09-16）：已上架的本地新品并入对应系列——
    // 草稿 / 已下架不进 feed；下架重新上架自动回归。转换需要系列原单品
    // 做规格继承（款式组 / 尺码组 / 尺码表），所以先合完系列再挂新单品。
    let pendingListings = MidsummerListingStore.shared.listedListings
    if !pendingListings.isEmpty {
      var mergedByID: [String: MidsummerSeriesDTO] = [:]
      for (id, series) in byID {
        let listings = pendingListings.filter { $0.seriesID == id }
        if listings.isEmpty {
          mergedByID[id] = series
        } else {
          let sourceItem = series.items.first
          let newItems = listings.map { $0.makeItemDTO(sourceItem: sourceItem, seriesSourceURL: series.sourceURL) }
          mergedByID[id] = MidsummerSeriesDTO(
            id: series.id,
            name: series.name,
            year: series.year,
            launchedOn: series.launchedOn,
            stage: series.stage,
            coverImage: series.coverImage,
            depositMin: series.depositMin,
            depositMax: series.depositMax,
            priceSource: series.priceSource,
            sizes: series.sizes,
            colors: series.colors,
            summary: series.summary,
            sourceURL: series.sourceURL,
            sourceKind: series.sourceKind,
            verified: series.verified,
            items: series.items + newItems
          )
        }
      }
      byID = mergedByID
    }

    let merged = byID.values.sorted { lhs, rhs in
      // 尚未确认上新日期的系列排在最前——它们正是最需要创作者补充的一批
      if lhs.launchedOn.isEmpty != rhs.launchedOn.isEmpty {
        return lhs.launchedOn.isEmpty
      }
      if lhs.launchedOn != rhs.launchedOn {
        return lhs.launchedOn > rhs.launchedOn
      }
      return lhs.name < rhs.name
    }

    catalog = MidsummerCatalogDTO(
      brandID: seed.brandID,
      brandName: seed.brandName,
      brandNameEN: seed.brandNameEN,
      foundedOn: seed.foundedOn,
      company: seed.company,
      positioning: seed.positioning,
      officialShopURL: seed.officialShopURL,
      weiboURL: seed.weiboURL,
      disclaimer: seed.disclaimer,
      series: merged
    )
  }
}
