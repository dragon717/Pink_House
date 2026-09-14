import Combine
import Foundation

// MARK: - 品牌列表页元数据
//
// 时光馆主页（参考图一：关注店铺列表）需要三类信息：
//   1. 展示信息——名称、副标题、缩略图
//   2. 上新信息——「N 件新品」（图一绿字位）
//   3. 时间信息——「N 天前关注」（图一灰字位）
//
// 其中 (2) 是**必须诚实**的一项：现有 catalog 只有 `listingStatus`
// （`in_stock` / `sold_out`）与单一批次的 `observedAt`，推不出「新品」。
// 因此硬规则是：
//
//   `newItemCount > 0` 必须同时给出来源说明 `newItemCountSource`，
//   否则界面退化为显示真实的在售件数，绝不显示一个编造的新品数。
//
// 该不变量由 `TimeHallBrandListingTests` 守住。
//
// 隔离策略：纯逻辑（数据、匹配、筛选、相对时间计算）一律 `nonisolated`
// 以便单测；含本地化文案的展示属性放在文件末尾的 `@MainActor` 扩展里，
// 因为 `String.appLocalized` 依赖 `LanguageManager.shared`。

// MARK: - Bundle 种子

/// 单个品牌的静态元数据，对应 `Resources/TimeHall/timehall-brand-meta.json`。
///
/// `addedAt` 一律取自该品牌 catalog 的 `observedAt`（抓取观测日），
/// 是可核验的真实日期，而不是为了凑出好看的「N 天前」而臆造的时间。
nonisolated struct TimeHallBrandMeta: Codable, Hashable, Sendable {
  let merchantID: String
  let displayName: String
  let subtitle: String
  /// `jp` / `cn`
  let region: String
  /// `official`（品牌官网）/ `aggregator`（授权集合店）/ `independent`（独立国牌）
  let channel: String
  let hasDedicatedPage: Bool
  let thumbnailImage: String?
  /// `yyyy-MM-dd`
  let addedAt: String
  let latestListingAt: String?
  let newItemCount: Int
  let newItemCountSource: String

  /// 解析后的加入日期（UTC 日历，避免时区把日期推前/推后一天）。
  var addedDate: Date? { TimeHallBrandDayParser.date(from: addedAt) }

  var latestListingDate: Date? {
    guard let latestListingAt else { return nil }
    return TimeHallBrandDayParser.date(from: latestListingAt)
  }
}

nonisolated struct TimeHallBrandMetaCatalog: Codable, Sendable {
  let version: Int
  let generatedAt: String
  let note: String
  let brands: [TimeHallBrandMeta]
}

nonisolated enum TimeHallBrandDayParser {
  static func date(from text: String) -> Date? {
    let parts = text.split(separator: "-")
    guard parts.count == 3,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2])
    else { return nil }

    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar.date(from: components)
  }
}

nonisolated enum TimeHallBrandMetaSeed {
  static let resourceName = "timehall-brand-meta"
  static let subdirectory = "TimeHall"

  static func load(bundle: Bundle = .main) -> TimeHallBrandMetaCatalog? {
    guard let url = url(in: bundle) else {
      print("⚠️ [TimeHall] 未找到 \(resourceName).json")
      return nil
    }
    do {
      let data = try Data(contentsOf: url)
      return try JSONDecoder().decode(TimeHallBrandMetaCatalog.self, from: data)
    } catch {
      print("⚠️ [TimeHall] 品牌元数据解码失败：\(error.localizedDescription)")
      return nil
    }
  }

  private static func url(in bundle: Bundle) -> URL? {
    bundle.url(forResource: resourceName, withExtension: "json", subdirectory: subdirectory)
      ?? bundle.url(
        forResource: resourceName,
        withExtension: "json",
        subdirectory: "Resources/\(subdirectory)"
      )
      ?? bundle.url(forResource: resourceName, withExtension: "json")
  }
}

// MARK: - 展示模型

/// 图一列表里的一行。除文案外都可在非主线程计算，便于单测。
nonisolated struct TimeHallBrandListing: Identifiable, Hashable, Sendable {
  let id: String
  let displayName: String
  let subtitle: String
  let thumbnailImage: String?
  let region: String
  let channel: String
  let hasDedicatedPage: Bool
  let addedAt: Date?
  /// 该品牌档案里的在售件数（真实统计，来自 catalog）
  let inStockCount: Int
  let newItemCount: Int
  let newItemCountSource: String

  /// 是否有可核验的上新 —— 决定图一左下角绿色「新」角标是否出现。
  var hasVerifiedNewItems: Bool { newItemCount > 0 }

  func matches(keyword: String) -> Bool {
    let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return true }
    return displayName.lowercased().contains(trimmed)
      || subtitle.lowercased().contains(trimmed)
      || channel.lowercased().contains(trimmed)
  }
}

// MARK: - 相对时间（纯计算）

nonisolated enum TimeHallRelativeDayText {
  /// 返回「7天」「14天」「6个月」这类不含介词的时间段文案。
  /// 对齐图一的口语化粒度：30 天内按天，之后按月，一年以上按年。
  static func amount(from date: Date, to now: Date = Date()) -> TimeHallRelativeAmount {
    let seconds = now.timeIntervalSince(date)
    let days = Int(seconds / 86_400)

    if days < 1 { return .today }
    if days < 2 { return .yesterday }
    if days < 30 { return .days(days) }
    if days < 365 { return .months(max(days / 30, 1)) }
    return .years(max(days / 365, 1))
  }
}

/// 时间段的结构化表示，让「计算」与「本地化」彻底分开。
nonisolated enum TimeHallRelativeAmount: Equatable, Sendable {
  case today
  case yesterday
  case days(Int)
  case months(Int)
  case years(Int)
}

// MARK: - 筛选与搜索（纯函数，可单测）

nonisolated enum TimeHallBrandListFilter: String, CaseIterable, Identifiable, Sendable {
  case all
  case hasNew
  case domestic
  case overseas

  var id: String { rawValue }

  func accepts(_ listing: TimeHallBrandListing) -> Bool {
    switch self {
    case .all: return true
    case .hasNew: return listing.hasVerifiedNewItems
    case .domestic: return listing.region == "cn"
    case .overseas: return listing.region == "jp"
    }
  }
}

nonisolated enum TimeHallBrandListQuery {
  /// 搜索 + 筛选。两个条件同时生效（与图一「搜索框 + 筛选条」的并列关系一致）。
  static func apply(
    _ listings: [TimeHallBrandListing],
    keyword: String,
    filter: TimeHallBrandListFilter
  ) -> [TimeHallBrandListing] {
    listings.filter { filter.accepts($0) && $0.matches(keyword: keyword) }
  }
}

// MARK: - 关注时间（本地覆盖层）
//
// 元数据里的 `addedAt` 是「档案入库日」，对所有用户一致；
// 用户真正进入过某个品牌后，这里记下真实时间并优先使用，
// 于是「N 天前加入」会随使用自然变化，而不是永远停在种子日期。

@MainActor
final class TimeHallBrandFollowStore: ObservableObject {
  static let shared = TimeHallBrandFollowStore()

  private let defaults: UserDefaults
  private let storageKey = "timehall.brand.followedAt"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func followedAt(for merchantID: String) -> Date? {
    let table = defaults.dictionary(forKey: storageKey) as? [String: Double]
    guard let stamp = table?[merchantID] else { return nil }
    return Date(timeIntervalSince1970: stamp)
  }

  /// 已经记过就不覆盖 —— 保留最早那次，语义才是「加入时间」。
  func markFollowed(_ merchantID: String, at date: Date = Date()) {
    guard followedAt(for: merchantID) == nil else { return }
    var table = (defaults.dictionary(forKey: storageKey) as? [String: Double]) ?? [:]
    table[merchantID] = date.timeIntervalSince1970
    defaults.set(table, forKey: storageKey)
  }

  /// 本地记录优先，否则退回元数据里的档案入库日。
  func resolvedAddedAt(merchantID: String, fallback: Date?) -> Date? {
    followedAt(for: merchantID) ?? fallback
  }
}

// MARK: - 本地化文案（主线程）

@MainActor
extension TimeHallBrandListing {
  /// 图一副行左侧的绿字。有可核验上新才显示「N件新品」。
  var newItemText: String? {
    hasVerifiedNewItems ? "\(newItemCount)" + "件新品".appLocalized : nil
  }

  /// 没有上新数据时的诚实退化文案。
  var inStockText: String {
    "\(inStockCount)" + "件在售".appLocalized
  }

  /// 主指标（绿字位）：优先真实上新，否则真实在售。
  var headlineMetricText: String { newItemText ?? inStockText }

  /// 图一副行右侧的灰字，例如「14天前加入」。
  ///
  /// 注意「今天／昨天」**不能**拼「前」，否则会出现「今天前加入」这种病句。
  func followedText(now: Date = Date()) -> String {
    guard let addedAt else { return "刚加入".appLocalized }
    let amount = TimeHallRelativeDayText.amount(from: addedAt, to: now)
    switch amount {
    case .today: return "今天加入".appLocalized
    case .yesterday: return "昨天加入".appLocalized
    case .days(let count): return "\(count)" + "天前加入".appLocalized
    case .months(let count): return "\(count)" + "个月前加入".appLocalized
    case .years(let count): return "\(count)" + "年前加入".appLocalized
    }
  }
}

@MainActor
extension TimeHallBrandListFilter {
  var title: String {
    switch self {
    case .all: return "全部".appLocalized
    case .hasNew: return "有上新".appLocalized
    case .domestic: return "国牌".appLocalized
    case .overseas: return "日牌".appLocalized
    }
  }
}
