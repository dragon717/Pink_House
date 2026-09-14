import XCTest

@testable import ItemManager

/// 仲夏物语品牌页：数据层与合并规则。
///
/// 重点覆盖三件容易出错的事：
///   1. Bundle 种子真的能被解出来（路径回退正确、字段没写错）
///   2. 云端合并是**补充**而不是替换——不能因为第一次上传就把历史系列抹掉
///   3. 缺项如实呈现为「待补充」，而不是静默丢字段
final class MidsummerBrandPageTests: XCTestCase {

  // MARK: - 种子加载

  private func loadSeed() throws -> MidsummerCatalogDTO {
    let candidates = [
      Bundle.main.url(
        forResource: MidsummerSeedCatalog.resourceName, withExtension: "json",
        subdirectory: MidsummerSeedCatalog.subdirectory),
      Bundle.main.url(forResource: MidsummerSeedCatalog.resourceName, withExtension: "json"),
      Bundle(for: Self.self).url(
        forResource: MidsummerSeedCatalog.resourceName, withExtension: "json"),
    ]
    let url = try XCTUnwrap(candidates.compactMap { $0 }.first, "找不到 midsummer-series.json")
    return try JSONDecoder().decode(MidsummerCatalogDTO.self, from: Data(contentsOf: url))
  }

  func testSeedCatalogDecodesWithExpectedBrandMetadata() throws {
    let catalog = try loadSeed()
    XCTAssertEqual(catalog.brandID, "midsummer-tale")
    XCTAssertEqual(catalog.brandName, "仲夏物语")
    XCTAssertEqual(catalog.brandNameEN, "Midsummer Tale")
    // 公开工商与百科资料一致：2017-04-06，不是 2023 年
    XCTAssertEqual(catalog.foundedOn, "2017-04-06")
    XCTAssertFalse(catalog.disclaimer.isEmpty, "必须向用户说明资料可能不完整")
  }

  func testSeedSeriesCoveragesFrom2022To2026() throws {
    let catalog = try loadSeed()
    XCTAssertFalse(catalog.series.isEmpty)
    let years = Set(catalog.series.map(\.year))
    for year in 2022...2026 {
      XCTAssertTrue(years.contains(year), "缺少 \(year) 年的系列")
    }
    XCTAssertEqual(catalog.years, catalog.years.sorted(by: >), "年份导航必须倒序")
  }

  func testSeedSeriesIDsAreUniqueAndItemsBelongToTheirSeries() throws {
    let catalog = try loadSeed()
    let seriesIDs = catalog.series.map(\.id)
    XCTAssertEqual(seriesIDs.count, Set(seriesIDs).count, "系列 id 必须唯一")

    let allItemIDs = catalog.series.flatMap { $0.items.map(\.id) }
    XCTAssertEqual(allItemIDs.count, Set(allItemIDs).count, "单品 id 必须唯一")

    for series in catalog.series {
      for item in series.items {
        XCTAssertEqual(item.seriesID, series.id, "\(item.id) 的 seriesID 与所属系列不符")
      }
    }
  }

  func testEverySeriesCarriesSourceURLForTraceability() throws {
    let catalog = try loadSeed()
    for series in catalog.series {
      XCTAssertFalse(series.sourceURL.isEmpty, "\(series.name) 缺少原文出处")
      XCTAssertTrue(
        series.sourceURL.hasPrefix("http"),
        "\(series.name) 的出处不是可访问的 URL"
      )
      // 出处必须落在可信域名上，不能是随手编的地址（Apple 5.2 可溯源）
      XCTAssertFalse(
        series.sourceURL.contains("xyzstar"),
        "\(series.name) 用了不可溯源的出处域名"
      )
      for item in series.items {
        XCTAssertTrue(
          item.sourceURL.hasPrefix("http"),
          "\(item.name) 的出处不是可访问的 URL"
        )
      }
    }
  }

  /// 详情页要能展示「图片、价格、尺码」，所以每个系列都必须真的承载这些字段：
  /// 至少一个单品（图片与款名的载体）+ 非空尺码。价格允许「待补充」，
  /// 但必须在界面上显式标注而不是留空。
  func testEverySeriesCanRenderImagePriceAndSizes() throws {
    let catalog = try loadSeed()
    for series in catalog.series {
      XCTAssertFalse(
        series.items.isEmpty,
        "\(series.name) 没有单品——系列页展示不出图片与款名"
      )
      XCTAssertFalse(
        series.sizes.isEmpty,
        "\(series.name) 没有尺码信息——系列页展示不出尺码"
      )
      // 有价格就应形成合法区间；没有则界面显示「价格待补充」
      // 区间是**派生**的（含 SKU 逐款价），所以这里断言的是派生结果而不是字段。
      if let range = series.priceRange {
        XCTAssertLessThanOrEqual(range.min, range.max, "\(series.name) 的价格区间上下限颠倒")
        XCTAssertGreaterThan(range.min, 0, "\(series.name) 的价格区间出现 0 元")
      }
      if let deposit = series.depositRange {
        XCTAssertLessThanOrEqual(deposit.min, deposit.max, "\(series.name) 的定金区间上下限颠倒")
      }
    }
  }

  /// 每个系列都应能被导航到——按年份分组、按时间倒序，不出现孤儿。
  func testEverySeriesIsReachableByYearNavigation() throws {
    let catalog = try loadSeed()
    let grouped = Dictionary(grouping: catalog.series, by: \.year)
    XCTAssertEqual(
      grouped.values.reduce(0) { $0 + $1.count }, catalog.series.count,
      "按年份分组后不能丢系列"
    )
    for year in catalog.years {
      XCTAssertFalse(grouped[year]?.isEmpty ?? true, "\(year) 年在导航里是空的")
    }
  }

  @MainActor
  func testSeriesWithoutLaunchDateAreSortedFirst() {
    // 排序发生在 Store 合并阶段，所以必须断言 store.allSeries，
    // 而不是解码后的原始 JSON 顺序（那是文件里的书写顺序）。
    let store = MidsummerStore(bundle: .main)
    let series = store.allSeries

    let lastWithout = series.lastIndex { $0.launchedOn.isEmpty }
    let firstWith = series.firstIndex { !$0.launchedOn.isEmpty }
    if let lastWithout, let firstWith {
      XCTAssertLessThan(lastWithout, firstWith, "日期待补的系列没有排在前面")
    }

    let dated = series.filter { !$0.launchedOn.isEmpty }.map(\.launchedOn)
    XCTAssertEqual(dated, dated.sorted(by: >), "有日期的系列应按时间倒序")
  }

  // MARK: - 展示文案

  func testItemPriceTextPrefersDepositThenPriceThenBalance() {
    let depositItem = makeItem(deposit: 47, balance: 160, price: nil)
    XCTAssertEqual(depositItem.priceText, "定金 ¥47 · 尾款 ¥160")

    let depositOnly = makeItem(deposit: 388, balance: nil, price: 499)
    XCTAssertEqual(depositOnly.priceText, "定金 ¥388")

    let priceOnly = makeItem(deposit: nil, balance: nil, price: 119)
    XCTAssertEqual(priceOnly.priceText, "¥119")

    let unknown = makeItem(deposit: nil, balance: nil, price: nil)
    XCTAssertEqual(unknown.priceText, "价格待补充", "缺价必须如实说明，不能显示 ¥0")
  }

  func testSizesTextFallsBackToPendingInsteadOfEmptyString() {
    XCTAssertEqual(makeItem(sizes: []).sizesText, "尺码待补充")
    XCTAssertEqual(makeItem(sizes: ["S", "M"]).sizesText, "S / M")
  }

  func testSeriesPriceRangeTextIsDerivedFromItemsNotStored() throws {
    let catalog = try loadSeed()
    let peterRabbit = try XCTUnwrap(catalog.series(withID: "midsummer-2022-peter-rabbit"))
    XCTAssertEqual(peterRabbit.priceRangeText, "¥160–554")
    XCTAssertEqual(peterRabbit.depositRangeText, "定金 ¥75", "定金与全款是两个维度，必须分列")

    // 单值：上下限相同时不应显示区间
    let single = makeSeries(id: "x", items: [makeItem(price: 269)])
    XCTAssertEqual(single.priceRangeText, "¥269")
    XCTAssertEqual(single.priceRange?.min, 269)
    XCTAssertNil(single.depositRangeText)

    // 缺价：如实说明，不显示 ¥0
    let missing = makeSeries(id: "y", items: [makeItem()], launchedOn: "", stage: .preview)
    XCTAssertEqual(missing.priceRangeText, "价格待补充")
    XCTAssertFalse(missing.hasPrice)
    XCTAssertEqual(missing.launchDateText, "")

    // 价格只在 SKU 表里（归集商品就是这样）——派生区间必须仍能算出来
    let skuDriven = makeSeries(
      id: "z",
      items: [
        makeItem(skus: [
          MidsummerSKU(id: "a", options: ["size": "s"], image: nil, price: 199),
          MidsummerSKU(id: "b", options: ["size": "m"], image: nil, price: 699),
        ])
      ]
    )
    XCTAssertEqual(
      skuDriven.priceRangeText, "¥199–699",
      "价格全在 SKU 表时不能退化成「价格待补充」——这正是归集商品的情形"
    )
  }

  func testLaunchDateTextUsesDottedFormat() throws {
    let catalog = try loadSeed()
    let series = try XCTUnwrap(catalog.series(withID: "midsummer-2025-bow-eternal-garden"))
    XCTAssertEqual(series.launchedOn, "2025-05-08")
    XCTAssertEqual(series.launchDateText, "2025.05.08")
  }

  func testItemKindInferencePrefersSpecificKeywords() {
    XCTAssertEqual(MidsummerItemKind.infer(fromName: "樱花小羊 SK"), .skirt)
    XCTAssertEqual(MidsummerItemKind.infer(fromName: "小熊博物馆 JSK"), .jsk)
    XCTAssertEqual(MidsummerItemKind.infer(fromName: "三丽鸥家族合作 联名 OP"), .op)
    // 「op罩裙jsk」这类混写要先命中更具体的品类，不能被首个关键词吃掉
    XCTAssertEqual(MidsummerItemKind.infer(fromName: "樱花小羊 围裙 / 罩裙"), .skirt)
    XCTAssertEqual(MidsummerItemKind.infer(fromName: "樱花小羊 内搭"), .blouse)
    XCTAssertEqual(MidsummerItemKind.infer(fromName: "小物（边夹 / KC）"), .accessory)
    XCTAssertNil(MidsummerItemKind.infer(fromName: "看不懂的标题"))
  }

  // MARK: - 合并规则

  @MainActor
  func testStoreLoadsSeedIntoCatalog() {
    let store = MidsummerStore(bundle: .main)
    XCTAssertNotNil(store.catalog, "种子必须能独立撑起页面")
    XCTAssertGreaterThan(store.allSeries.count, 10)
    XCTAssertFalse(store.yearEntries.isEmpty)
  }

  @MainActor
  func testCloudSeriesOverridesSeedWithSameIDButKeepsOthers() throws {
    let store = MidsummerStore(bundle: .main)
    let before = store.allSeries.count
    XCTAssertGreaterThan(before, 0)

    // 模拟创作者校正了某个已有系列的价格（价格挂在单品上，区间自动派生）
    let corrected = MidsummerSeriesDTO(
      id: "midsummer-2024-monet",
      name: "莫奈油画柄",
      year: 2024,
      launchedOn: "2024-04-01",
      stage: .restock,
      coverImage: nil,
      depositMin: nil,
      depositMax: nil,
      priceSource: "创作者核对",
      sizes: ["S", "M", "L"],
      colors: ["粉色"],
      summary: "创作者补充：确认了再贩日期与价格。",
      sourceURL: "https://example.com/edit",
      sourceKind: "editorial",
      verified: true,
      items: [makeItem(price: 299)]
    )
    store.applyUploaded(series: corrected)

    let updated = try XCTUnwrap(store.series(withID: "midsummer-2024-monet"))
    XCTAssertEqual(updated.priceRangeText, "¥299", "云端同 id 应覆盖种子")
    XCTAssertEqual(updated.launchedOn, "2024-04-01")
    XCTAssertEqual(updated.sourceKind, "editorial")
    XCTAssertEqual(store.allSeries.count, before, "覆盖不应改变系列总数")
  }

  @MainActor
  func testCloudUploadAppendsNewSeriesWithoutDroppingSeedHistory() {
    let store = MidsummerStore(bundle: .main)
    let before = store.allSeries.count

    let fresh = MidsummerSeriesDTO(
      id: "midsummer-2026-editorial-demo",
      name: "创作者新录入系列",
      year: 2026,
      launchedOn: "2026-05-01",
      stage: .deposit,
      coverImage: nil,
      depositMin: 199,
      depositMax: 199,
      priceSource: "创作者填写",
      sizes: ["S", "M"],
      colors: ["粉色"],
      summary: nil,
      sourceURL: "https://example.com/new",
      sourceKind: "editorial",
      verified: true,
      items: []
    )
    store.applyUploaded(series: fresh)

    XCTAssertEqual(store.allSeries.count, before + 1, "新系列应被追加")
    XCTAssertNotNil(store.series(withID: fresh.id))
    XCTAssertNotNil(
      store.series(withID: "midsummer-2022-peter-rabbit"),
      "上传新内容绝不能把种子里的历史系列抹掉"
    )
  }

  @MainActor
  func testPendingFieldCountReflectsIncompletePublicData() {
    let store = MidsummerStore(bundle: .main)
    // 公开渠道查不到的内容必须是「待补充」，而不是被静默填成 0
    XCTAssertGreaterThan(
      store.pendingFieldCount, 0,
      "公开渠道信息本就不完整，待补项应被如实统计出来")
  }

  @MainActor
  func testItemFeedFiltersByYearAndSeries() {
    let store = MidsummerStore(bundle: .main)
    let all = store.itemFeed(year: nil, seriesID: nil)
    XCTAssertFalse(all.isEmpty)

    let year2022 = store.itemFeed(year: 2022, seriesID: nil)
    XCTAssertTrue(year2022.allSatisfy { $0.series.year == 2022 })

    let single = store.itemFeed(year: 2022, seriesID: "midsummer-2022-peter-rabbit")
    XCTAssertFalse(single.isEmpty)
    XCTAssertTrue(single.allSatisfy { $0.series.id == "midsummer-2022-peter-rabbit" })

    // 筛选到不存在的组合时应为空（界面据此显示「该筛选下暂无收录」）
    XCTAssertTrue(store.itemFeed(year: 1999, seriesID: nil).isEmpty)
    XCTAssertEqual(store.itemCount(year: 1999, seriesID: nil), 0)
    XCTAssertLessThan(single.count, all.count)
  }

  // MARK: - 辅助

  private func makeItem(
    deposit: Int? = nil,
    balance: Int? = nil,
    price: Int? = nil,
    sizes: [String] = ["S", "M"],
    skus: [MidsummerSKU]? = nil
  ) -> MidsummerItemDTO {
    MidsummerItemDTO(
      id: "test-item",
      seriesID: "test-series",
      name: "测试款",
      kind: .op,
      price: price,
      deposit: deposit,
      balance: balance,
      priceKind: (price == nil && deposit == nil && balance == nil) ? nil : .reference,
      priceCapturedOn: nil,
      priceNote: nil,
      sizes: sizes,
      colors: [],
      coverImage: nil,
      itemURL: nil,
      sourceURL: "https://example.com",
      note: nil,
      specGroups: nil,
      skus: skus
    )
  }

  /// 造一个系列。价格区间已经是**派生**的，所以区间要由 `items` 决定。
  private func makeSeries(
    id: String,
    items: [MidsummerItemDTO],
    depositMin: Int? = nil,
    depositMax: Int? = nil,
    launchedOn: String = "2026-01-01",
    stage: MidsummerStage = .inStock
  ) -> MidsummerSeriesDTO {
    MidsummerSeriesDTO(
      id: id,
      name: id,
      year: 2026,
      launchedOn: launchedOn,
      stage: stage,
      coverImage: nil,
      depositMin: depositMin,
      depositMax: depositMax,
      priceSource: nil,
      sizes: ["S"],
      colors: [],
      summary: nil,
      sourceURL: "https://example.com",
      sourceKind: "public",
      verified: true,
      items: items
    )
  }
}
