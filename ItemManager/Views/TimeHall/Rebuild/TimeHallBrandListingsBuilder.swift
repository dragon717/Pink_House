import Foundation

// MARK: - 品牌列表构造
//
// 把「品牌枚举 + 元数据种子 + 在售统计」合成主页要用的 `TimeHallBrandListing`。
// 刻意做成 `@MainActor` 纯函数（输入全由参数注入），既能被 `TimeHallView` 直接调用，
// 也能在单测里用假数据验证合并规则。

@MainActor
enum TimeHallBrandListingsBuilder {
  static func makeListings(
    merchants: [TimeHallMerchant],
    metaCatalog: TimeHallBrandMetaCatalog?,
    inStockCount: (TimeHallMerchant) -> Int,
    followStore: TimeHallBrandFollowStore = .shared
  ) -> [TimeHallBrandListing] {
    var metaByID: [String: TimeHallBrandMeta] = [:]
    for meta in metaCatalog?.brands ?? [] {
      metaByID[meta.merchantID] = meta
    }

    return merchants.map { merchant in
      let meta = metaByID[merchant.rawValue]
      return TimeHallBrandListing(
        id: merchant.rawValue,
        displayName: meta?.displayName ?? merchant.name,
        subtitle: meta?.subtitle ?? merchant.subtitle,
        thumbnailImage: meta?.thumbnailImage ?? merchant.coverImage,
        region: meta?.region ?? "jp",
        channel: meta?.channel ?? "official",
        hasDedicatedPage: meta?.hasDedicatedPage ?? merchant.usesDedicatedBrandPage,
        addedAt: followStore.resolvedAddedAt(
          merchantID: merchant.rawValue,
          fallback: meta?.addedDate
        ),
        inStockCount: inStockCount(merchant),
        newItemCount: meta?.newItemCount ?? 0,
        newItemCountSource: meta?.newItemCountSource ?? ""
      )
    }
  }

  /// 品牌档案在 Bundle 里对应的 catalog 资源名。
  ///
  /// `TimeHallMerchant.catalogResourceName` 对 Pink House 返回 nil——它的主档
  /// 就是无后缀的 `catalog.json`（`TimeHallCatalogStore.catalog`），所以这里补上。
  static func catalogResourceName(for merchant: TimeHallMerchant) -> String? {
    if let name = merchant.catalogResourceName { return name }
    return merchant == .pinkHouse ? "catalog" : nil
  }
}

// MARK: - 在售件数缓存
//
// `TimeHallCatalogStore.bundledCatalog(named:)` 每次调用都会重新读盘并解码，
// 而 Wunderwelt 一个档就有 3116 条商品。主页每次 body 重算都解析一遍会明显卡顿，
// 因此按资源名缓存一次统计结果（进程内不变）。

@MainActor
final class TimeHallBrandStockCounter {
  static let shared = TimeHallBrandStockCounter()

  private var cache: [String: Int] = [:]

  func inStockCount(for merchant: TimeHallMerchant) -> Int {
    guard let resourceName = TimeHallBrandListingsBuilder.catalogResourceName(for: merchant) else {
      // 仲夏物语没有 Bundle catalog，走 MidsummerStore 的种子计数。
      return MidsummerStore.shared.itemCount(year: nil, seriesID: nil)
    }

    if let cached = cache[resourceName] { return cached }

    let count =
      TimeHallCatalogStore.shared.bundledCatalog(named: resourceName)?
      .commerceItems
      .filter { $0.listingStatus == "in_stock" }
      .count ?? 0
    cache[resourceName] = count
    return count
  }
}
