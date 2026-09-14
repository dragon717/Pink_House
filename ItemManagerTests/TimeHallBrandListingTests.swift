import XCTest

@testable import ItemManager

/// 时光馆主页（图一品牌列表）数据层测试。
///
/// 重点守住两条**诚实性**约束：
///   1. `newItemCount > 0` 必须携带来源说明，禁止出现无出处的「新品数」
///   2. 没有可核验上新数据时，主指标必须退化为真实在售件数，而不是编一个数字
@MainActor
final class TimeHallBrandListingTests: XCTestCase {

  // MARK: - 辅助

  private func loadSeed() throws -> TimeHallBrandMetaCatalog {
    try XCTUnwrap(
      TimeHallBrandMetaSeed.load(),
      "时光馆品牌元数据种子应能从 Bundle 读到（timehall-brand-meta.json）"
    )
  }

  private func makeListing(
    id: String = "testBrand",
    region: String = "jp",
    inStock: Int = 10,
    newItems: Int = 0,
    addedAt: Date? = nil
  ) -> TimeHallBrandListing {
    TimeHallBrandListing(
      id: id,
      displayName: "Test Brand",
      subtitle: "测试用副标题",
      thumbnailImage: nil,
      region: region,
      channel: "official",
      hasDedicatedPage: false,
      addedAt: addedAt,
      inStockCount: inStock,
      newItemCount: newItems,
      newItemCountSource: newItems > 0 ? "测试来源" : ""
    )
  }

  private func makeIsolatedFollowStore() -> TimeHallBrandFollowStore {
    let suiteName = "TimeHallBrandListingTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    return TimeHallBrandFollowStore(defaults: defaults)
  }

  // MARK: - 种子完整性

  func testSeedDecodesAndCoversEveryMerchant() throws {
    let seed = try loadSeed()
    XCTAssertEqual(seed.version, 1)
    XCTAssertFalse(seed.note.isEmpty, "种子文件必须自带口径说明")

    let knownIDs = Set(TimeHallMerchant.allCases.map(\.rawValue))
    let metaIDs = Set(seed.brands.map(\.merchantID))
    XCTAssertEqual(
      metaIDs, knownIDs,
      "元数据覆盖的品牌应与 TimeHallMerchant 完全一致，不多不少"
    )
    XCTAssertEqual(
      seed.brands.count, metaIDs.count,
      "同一个品牌不应在元数据里出现两次"
    )
  }

  /// 硬护栏：不允许出现「没有出处的上新数」。
  func testNewItemCountMustCarryVerifiableSource() throws {
    let seed = try loadSeed()
    for brand in seed.brands where brand.newItemCount > 0 {
      XCTAssertFalse(
        brand.newItemCountSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        "\(brand.displayName) 声明了 \(brand.newItemCount) 件新品，但没有写来源说明——不允许"
      )
    }
  }

  /// 没有上新数据的品牌必须诚实标 0（而不是留空或填假数字）。
  func testBrandsWithoutListingDataDeclareZeroNewItems() throws {
    let seed = try loadSeed()
    for brand in seed.brands where brand.newItemCount == 0 {
      XCTAssertTrue(
        brand.newItemCountSource.isEmpty,
        "\(brand.displayName) 没有新品却写了来源说明，口径不一致"
      )
      XCTAssertNil(
        brand.latestListingDate,
        "\(brand.displayName) 没有新品数据，不应有最近上新日"
      )
    }
  }

  func testAddedAtIsParsableAndNotInTheFuture() throws {
    let seed = try loadSeed()
    let now = Date()
    for brand in seed.brands {
      let date = try XCTUnwrap(
        brand.addedDate,
        "\(brand.displayName) 的 addedAt「\(brand.addedAt)」不是 yyyy-MM-dd"
      )
      XCTAssertLessThanOrEqual(date, now, "\(brand.displayName) 的加入日期在未来")
    }
  }

  func testEveryBrandCarriesAThumbnailOrFallsBackGracefully() throws {
    let seed = try loadSeed()
    // 缩略图为 nil 时界面会渲染首字母占位，这里只断言字段本身合法（不出现空白字符串）
    for brand in seed.brands {
      if let thumbnail = brand.thumbnailImage {
        XCTAssertFalse(
          thumbnail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          "\(brand.displayName) 的缩略图名不能是空白字符串"
        )
      }
    }
  }

  // MARK: - 相对时间

  func testRelativeDayGranularity() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    XCTAssertEqual(TimeHallRelativeDayText.amount(from: now.addingTimeInterval(-3_600), to: now), .today)
    XCTAssertEqual(TimeHallRelativeDayText.amount(from: now.addingTimeInterval(-day), to: now), .yesterday)
    XCTAssertEqual(TimeHallRelativeDayText.amount(from: now.addingTimeInterval(-day * 7), to: now), .days(7))
    XCTAssertEqual(
      TimeHallRelativeDayText.amount(from: now.addingTimeInterval(-day * 29), to: now),
      .days(29),
      "30 天以内按天显示"
    )
    XCTAssertEqual(
      TimeHallRelativeDayText.amount(from: now.addingTimeInterval(-day * 90), to: now),
      .months(3),
      "超过 30 天按月显示"
    )
    XCTAssertEqual(
      TimeHallRelativeDayText.amount(from: now.addingTimeInterval(-day * 400), to: now),
      .years(1),
      "超过一年按年显示"
    )
  }

  func testFollowedTextIsReadableInChinese() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let listing = makeListing(addedAt: now.addingTimeInterval(-86_400 * 14))
    XCTAssertEqual(listing.followedText(now: now), "14天前加入")
  }

  /// 回归：快照曾暴露「今天前加入」这种病句——「今天／昨天」不能接「前」。
  func testFollowedTextDoesNotGlueQianOntoTodayOrYesterday() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    let today = makeListing(addedAt: now.addingTimeInterval(-3_600)).followedText(now: now)
    XCTAssertEqual(today, "今天加入")
    XCTAssertFalse(today.contains("今天前"))

    let yesterday = makeListing(addedAt: now.addingTimeInterval(-86_400)).followedText(now: now)
    XCTAssertEqual(yesterday, "昨天加入")
    XCTAssertFalse(yesterday.contains("昨天前"))
  }

  func testFollowedTextFallsBackWhenDateMissing() {
    let listing = makeListing(addedAt: nil)
    XCTAssertEqual(listing.followedText(), "刚加入")
  }

  // MARK: - 主指标（诚实退化）

  func testHeadlineMetricPrefersVerifiedNewItems() {
    let listing = makeListing(inStock: 2020, newItems: 8)
    XCTAssertTrue(listing.hasVerifiedNewItems)
    XCTAssertEqual(listing.newItemText, "8件新品")
    XCTAssertEqual(listing.headlineMetricText, "8件新品")
  }

  func testHeadlineMetricFallsBackToRealStockWhenNoListingData() {
    let listing = makeListing(inStock: 2020, newItems: 0)
    XCTAssertFalse(listing.hasVerifiedNewItems)
    XCTAssertNil(listing.newItemText, "没有可核验上新时不应出现绿字「N件新品」")
    XCTAssertEqual(listing.headlineMetricText, "2020件在售")
  }

  // MARK: - 搜索

  func testEmptyKeywordKeepsEverything() {
    let listings = [makeListing(id: "a"), makeListing(id: "b")]
    let result = TimeHallBrandListQuery.apply(listings, keyword: "   ", filter: .all)
    XCTAssertEqual(result.count, 2, "空白关键词等同于不过滤")
  }

  func testSearchMatchesNameSubtitleAndChannelCaseInsensitively() {
    let listings = [
      makeListing(id: "a"), makeListing(id: "b", region: "cn")
    ]
    XCTAssertEqual(
      TimeHallBrandListQuery.apply(listings, keyword: "test brand", filter: .all).count, 2,
      "应按品牌名匹配且忽略大小写"
    )
    XCTAssertEqual(
      TimeHallBrandListQuery.apply(listings, keyword: "测试用副标题", filter: .all).count, 2,
      "应能按副标题匹配"
    )
    XCTAssertEqual(
      TimeHallBrandListQuery.apply(listings, keyword: "official", filter: .all).count, 2,
      "应能按渠道匹配"
    )
    XCTAssertTrue(
      TimeHallBrandListQuery.apply(listings, keyword: "不存在的词", filter: .all).isEmpty
    )
  }

  // MARK: - 筛选

  func testFilterHasNewKeepsOnlyBrandsWithVerifiedNewItems() {
    let listings = [
      makeListing(id: "withNew", newItems: 8),
      makeListing(id: "withoutNew", newItems: 0),
    ]
    let result = TimeHallBrandListQuery.apply(listings, keyword: "", filter: .hasNew)
    XCTAssertEqual(result.map(\.id), ["withNew"])
  }

  func testFilterDomesticAndOverseasSplitByRegion() {
    let listings = [
      makeListing(id: "cn1", region: "cn"),
      makeListing(id: "cn2", region: "cn"),
      makeListing(id: "jp1", region: "jp"),
    ]
    XCTAssertEqual(
      TimeHallBrandListQuery.apply(listings, keyword: "", filter: .domestic).map(\.id),
      ["cn1", "cn2"]
    )
    XCTAssertEqual(
      TimeHallBrandListQuery.apply(listings, keyword: "", filter: .overseas).map(\.id),
      ["jp1"]
    )
    XCTAssertEqual(
      TimeHallBrandListQuery.apply(listings, keyword: "", filter: .all).count, 3
    )
  }

  func testSearchAndFilterComposeAsIntersection() {
    let listings = [
      makeListing(id: "cnWithNew", region: "cn", newItems: 3),
      makeListing(id: "cnWithoutNew", region: "cn", newItems: 0),
      makeListing(id: "jpWithNew", region: "jp", newItems: 5),
    ]
    let result = TimeHallBrandListQuery.apply(listings, keyword: "test", filter: .hasNew)
    XCTAssertEqual(
      result.map(\.id), ["cnWithNew", "jpWithNew"],
      "搜索与筛选应同时生效"
    )
  }

  // MARK: - 构造（合并规则）

  func testBuilderFallsBackToMerchantDefaultsWhenMetaIsMissing() {
    let followStore = makeIsolatedFollowStore()
    let listings = TimeHallBrandListingsBuilder.makeListings(
      merchants: TimeHallMerchant.allCases,
      metaCatalog: nil,
      inStockCount: { _ in 0 },
      followStore: followStore
    )

    XCTAssertEqual(listings.count, TimeHallMerchant.allCases.count)
    XCTAssertEqual(listings.map(\.id), TimeHallMerchant.allCases.map(\.rawValue))
    for (listing, merchant) in zip(listings, TimeHallMerchant.allCases) {
      XCTAssertEqual(listing.displayName, merchant.name)
      XCTAssertEqual(listing.thumbnailImage, merchant.coverImage)
      XCTAssertEqual(listing.newItemCount, 0)
      XCTAssertNil(listing.addedAt, "既无本地记录也无元数据时，不应编造加入时间")
    }
  }

  func testBuilderPrefersLocalFollowStampOverSeedDate() {
    let followStore = makeIsolatedFollowStore()
    let stamped = Date(timeIntervalSince1970: 1_700_000_000)
    followStore.markFollowed("pinkHouse", at: stamped)

    let seed = TimeHallBrandMetaCatalog(
      version: 1,
      generatedAt: "2026-09-14",
      note: "test",
      brands: [
        TimeHallBrandMeta(
          merchantID: "pinkHouse",
          displayName: "Pink House",
          subtitle: "副标题",
          region: "jp",
          channel: "official",
          hasDedicatedPage: false,
          thumbnailImage: nil,
          addedAt: "2026-08-01",
          latestListingAt: nil,
          newItemCount: 0,
          newItemCountSource: ""
        )
      ]
    )

    let listings = TimeHallBrandListingsBuilder.makeListings(
      merchants: [.pinkHouse],
      metaCatalog: seed,
      inStockCount: { _ in 42 },
      followStore: followStore
    )

    XCTAssertEqual(listings.count, 1)
    XCTAssertEqual(
      listings[0].addedAt, stamped,
      "用户真实进入过的时间应覆盖种子里的档案入库日"
    )
    XCTAssertEqual(listings[0].inStockCount, 42, "在售件数应来自注入的统计闭包")
  }

  func testFollowStoreKeepsEarliestStamp() {
    let followStore = makeIsolatedFollowStore()
    let first = Date(timeIntervalSince1970: 1_600_000_000)
    let later = Date(timeIntervalSince1970: 1_700_000_000)

    followStore.markFollowed("angelicPretty", at: first)
    followStore.markFollowed("angelicPretty", at: later)

    XCTAssertEqual(
      followStore.followedAt(for: "angelicPretty"), first,
      "重复进入不应刷新加入时间"
    )
  }

  func testCatalogResourceNameMapsPinkHouseToUnsuffixedCatalog() {
    XCTAssertEqual(
      TimeHallBrandListingsBuilder.catalogResourceName(for: .pinkHouse), "catalog",
      "Pink House 的主档是无后缀的 catalog.json"
    )
    XCTAssertEqual(
      TimeHallBrandListingsBuilder.catalogResourceName(for: .angelicPretty),
      "catalog-angelic-pretty"
    )
    XCTAssertNil(
      TimeHallBrandListingsBuilder.catalogResourceName(for: .midsummerTale),
      "仲夏物语没有 Bundle catalog，走 MidsummerStore"
    )
  }
}
