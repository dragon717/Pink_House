import XCTest

@testable import ItemManager

/// 仲夏物语 · 价格数据完整性校验。
///
/// 这个文件是「价格缺失或错误」的**根因修复**，不是补数脚本：
/// 以前的做法是发现哪个系列价格不对就手改那一处的数字，于是同一个数字在
/// 系列层和单品层各写一份，改一处忘一处；`price` 字段还被同时用来装
/// 现货价、参考价和尾款，没人说得清一个 ¥320 到底是什么钱。
///
/// 现在的规则（本文件逐条守住）：
///   1. 区间是**派生**的，不存储 —— 所以结构与单品不可能不一致
///   2. 任何价格数字都必须自报**口径**（商品页价 / 参考价）与**采集日期**
///   3. 没有价格必须**如实说明**理由，不允许静默留空
///   4. 定金与「参考价 / 现货价」分列，不许混成一个区间
///   5. 归集商品（一个淘宝链接含多款）的价格必须来自 SKU 逐款价，且区间非空
///
/// 任何一条被破坏，都是数据要出问题的信号，构建阶段就该红。
final class MidsummerPriceIntegrityTests: XCTestCase {

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

  private var allItems: [(series: MidsummerSeriesDTO, item: MidsummerItemDTO)] {
    get throws {
      let catalog = try loadSeed()
      return catalog.series.flatMap { series in series.items.map { (series, $0) } }
    }
  }

  // MARK: - 规则 2：口径与采集日

  func testEveryPricedItemDeclaresKindAndCaptureDate() throws {
    for (series, item) in try allItems {
      let hasAnyAmount = item.price != nil || item.deposit != nil || item.balance != nil
      guard hasAnyAmount else { continue }

      XCTAssertNotNil(
        item.priceKind,
        "\(series.name) / \(item.name) 有价格却没写口径——"
          + "没有口径就只能猜这个数字是商品页价、参考价还是尾款"
      )
      XCTAssertNotNil(
        item.priceCapturedOn,
        "\(series.name) / \(item.name) 有价格却没写采集日期——价格会变，没有日期就无法判断是否过期"
      )
      XCTAssertFalse(
        item.sourceURL.isEmpty,
        "\(series.name) / \(item.name) 有价格却没有可溯源的出处"
      )
    }
  }

  func testPriceCapturedOnUsesISODateFormat() throws {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")

    for (series, item) in try allItems {
      guard let stamp = item.priceCapturedOn else { continue }
      XCTAssertNotNil(
        formatter.date(from: stamp),
        "\(series.name) / \(item.name) 的采集日 \(stamp) 不是 yyyy-MM-dd"
      )
    }
  }

  // MARK: - 规则 3：缺价必须说明

  func testItemsWithoutPriceExplainWhy() throws {
    for (series, item) in try allItems {
      guard !item.hasPrice else { continue }
      let explanation = [item.priceNote, item.note]
        .compactMap { $0 }
        .first { !$0.isEmpty }
      XCTAssertNotNil(
        explanation,
        "\(series.name) / \(item.name) 没有任何价格，也没有一句说明——"
          + "缺项必须如实标注，不能静默留空"
      )
    }
  }

  // MARK: - 规则 4：定金与全款分列

  func testDepositAndCashPricesAreSeparateDimensions() throws {
    for series in try loadSeed().series {
      if let range = series.priceRange, let deposit = series.depositRange {
        XCTAssertLessThanOrEqual(range.min, range.max, "\(series.name) 价格区间上下限颠倒")
        XCTAssertLessThanOrEqual(deposit.min, deposit.max, "\(series.name) 定金区间上下限颠倒")
      }
      // 显式写了定金区间就必须给出处，否则又是一个来源不明的数字
      if series.depositMin != nil || series.depositMax != nil {
        XCTAssertFalse(
          (series.priceSource ?? "").isEmpty,
          "\(series.name) 标了定金区间却没写价格口径与出处"
        )
      }
    }
  }

  /// 同一数字不许在 `price` 和 `balance` 里各写一份——那是两份真相。
  /// 来源说的是尾款就写 `balance`，说的是参考价就写 `price`，不要都写。
  func testItemDoesNotDuplicateTheSameAmountInPriceAndBalance() throws {
    for (series, item) in try allItems {
      guard let price = item.price, let balance = item.balance else { continue }
      XCTAssertNotEqual(
        price, balance,
        "\(series.name) / \(item.name) 的 price 与 balance 是同一个数字——"
          + "等价于把同一份数据存了两遍，改一处就会不一致"
      )
    }
  }

  // MARK: - 规则 5：归集商品

  func testConsolidatedProductPricesComeFromSKUsAndFormARange() throws {
    let catalog = try loadSeed()
    let sakura = try XCTUnwrap(catalog.series(withID: "midsummer-2026-sakura-lamb"))

    // 两个淘宝链接（服装 item 1032370386538 + 小物 item 1031690555405）
    // 合并为一个归集商品——不再单列小物条目。
    XCTAssertEqual(sakura.items.count, 1, "两条淘宝链接合并为一个归集商品")
    let product = try XCTUnwrap(
      sakura.items.first { $0.id == "midsummer-2026-sakura-lamb" },
      "主链接归集商品缺失")

    XCTAssertEqual(product.variantCount, 24, "合并条目含 24 个颜色分类选项（服装 16 + 小物 8）")
    XCTAssertNotNil(
      product.itemURL,
      "归集商品必须留下那个唯一的商品链接，否则「统一到一个链接」无从体现")
    XCTAssertTrue(
      product.specGroups?.contains { $0.resolvedRole == .variant } ?? false,
      "归集商品必须用「款式」组把多款区分开")

    // 逐款商品页价必须落在 SKU 表里，且区间由它派生（淘宝采集 2026-09-16）。
    // 合并后区间取两个页面的并集：服装 ¥119–999，小物 ¥59–149。
    let prices = Set((product.skus ?? []).compactMap(\.price))
    XCTAssertTrue(
      prices.isSuperset(of: [59, 119, 149, 229, 279, 359, 369, 399, 449, 599, 699, 999]),
      "逐款商品页价缺失或写错：实际 \(prices.sorted())"
    )
    XCTAssertEqual(product.priceRange?.min, 59)
    XCTAssertEqual(product.priceRange?.max, 999)
    XCTAssertEqual(product.priceText, "¥59–999")

    // 小物款式（草帽等）必须真的并入款式组，而不是只搬了 SKU
    let styleNames = Set(
      (product.specGroups ?? [])
        .first { $0.resolvedRole == .variant }?
        .options.map(\.name) ?? [])
    XCTAssertTrue(styleNames.contains("现 草帽 生成色"), "小物的颜色分类选项应并入款式组")

    // 系列区间与合并条目区间一致（两条链接共同派生）
    XCTAssertEqual(sakura.priceRangeText, "¥59–999", "系列区间应派生自全部商品")
    XCTAssertNil(sakura.depositRangeText, "淘宝链接未给定金口径，不得虚构定金区间")
  }

  func testConsolidatedProductVariantOptionsMatchSKUTable() throws {
    let catalog = try loadSeed()
    let product = try XCTUnwrap(
      catalog.series(withID: "midsummer-2026-sakura-lamb")?.items.first)

    let styleGroup = try XCTUnwrap(
      product.specGroups?.first { $0.resolvedRole == .variant })
    let styleIDs = Set(styleGroup.options.map(\.id))
    let skuStyleIDs = Set((product.skus ?? []).compactMap { $0.options["style"] })

    XCTAssertEqual(
      styleIDs, skuStyleIDs,
      "款式组里的每一项都必须能在 SKU 表里找到对应组合，否则它永远选不出价格"
    )

    // 每一款都必须至少有一条带价的 SKU（小物除外：来源确实没给参考价）
    for option in styleGroup.options {
      let variants = (product.skus ?? []).filter { $0.options["style"] == option.id }
      XCTAssertFalse(variants.isEmpty, "款式「\(option.name)」在 SKU 表里没有组合")
      if option.id != "accessory" {
        XCTAssertTrue(
          variants.contains { $0.price != nil },
          "款式「\(option.name)」没有任何带参考价的组合"
        )
      }
    }
  }

  // MARK: - 规则 6：系列归集

  /// 同一系列下的多款必须归集到同一个商品。
  ///
  /// 唯一的例外是「每个商品都有自己明确的淘宝链接」——那时它们本来就是不同链接，
  /// 拆开是对的。除此之外同系列还留着多条商品，就说明归集漏了。
  func testSeriesWithMultipleProductsMustHaveDistinctLinks() throws {
    for series in try loadSeed().series {
      guard series.items.count > 1 else { continue }
      let links = Set(series.items.compactMap(\.itemURL))
      XCTAssertEqual(
        links.count, series.items.count,
        "\(series.name) 有 \(series.items.count) 个商品却只有 \(links.count) 个链接——"
          + "同一链接下的多款必须归集为一个商品"
      )
    }
  }

  /// 每个款式都必须在 SKU 表里至少有一条组合，否则它永远选不出价格。
  func testEveryVariantOptionHasASKU() throws {
    for (series, item) in try allItems {
      guard let styleGroup = item.specGroups?.first(where: { $0.resolvedRole == .variant })
      else { continue }
      let skus = item.skus ?? []
      for option in styleGroup.options {
        XCTAssertTrue(
          skus.contains { $0.options["style"] == option.id },
          "\(series.name) 的款式「\(option.name)」在 SKU 表里没有任何组合"
        )
      }
    }
  }

  /// SKU 逐款价同样要自报口径——归集商品的价格全在 SKU 表里，
  /// 单品层的 `priceKind` 覆盖不到，不守住这条规则就又是一个「¥320 是什么钱」。
  func testPricedSKUsDeclareTheirKind() throws {
    for (series, item) in try allItems {
      for sku in item.skus ?? [] where sku.price != nil {
        XCTAssertNotNil(
          sku.priceKind,
          "\(series.name) / \(item.name) 的 SKU \(sku.id) 有逐款价却没写口径"
        )
      }
    }
  }

  /// 归集商品的价格全在 SKU 表里，采集日只能写在单品层。
  func testConsolidatedProductDeclaresCaptureDate() throws {
    for (series, item) in try allItems {
      let priced = (item.skus ?? []).contains { $0.price != nil }
      guard priced else { continue }
      XCTAssertNotNil(
        item.priceCapturedOn,
        "\(series.name) / \(item.name) 的逐款价没有采集日期——SKU 表没有日期字段，"
          + "采集日只能由单品层统一声明"
      )
    }
  }

  // MARK: - 区间派生：改一处，上面全跟着变

  func testChangingOneItemPriceMovesTheWholeChain() {
    let item = MidsummerItemDTO(
      id: "i", seriesID: "s", name: "款", kind: .op,
      price: 500, deposit: nil, balance: nil,
      priceKind: .reference, priceCapturedOn: "2026-09-15", priceNote: nil,
      sizes: ["S"], colors: [], coverImage: nil, itemURL: nil,
      sourceURL: "https://example.com", note: nil, specGroups: nil, skus: nil
    )
    let series = MidsummerSeriesDTO(
      id: "s", name: "系列", year: 2026, launchedOn: "2026-01-01", stage: .inStock,
      coverImage: nil, depositMin: nil, depositMax: nil, priceSource: nil,
      sizes: ["S"], colors: [], summary: nil, sourceURL: "https://example.com",
      sourceKind: "public", verified: true, items: [item]
    )

    XCTAssertEqual(series.priceRangeText, "¥500")

    // 把单品价改一次，系列区间立刻跟着走——不存在需要手动同步的第二处
    let repriced = MidsummerItemDTO(
      id: "i", seriesID: "s", name: "款", kind: .op,
      price: 640, deposit: nil, balance: nil,
      priceKind: .reference, priceCapturedOn: "2026-09-15", priceNote: nil,
      sizes: ["S"], colors: [], coverImage: nil, itemURL: nil,
      sourceURL: "https://example.com", note: nil, specGroups: nil, skus: nil
    )
    let updated = MidsummerSeriesDTO(
      id: "s", name: "系列", year: 2026, launchedOn: "2026-01-01", stage: .inStock,
      coverImage: nil, depositMin: nil, depositMax: nil, priceSource: nil,
      sizes: ["S"], colors: [], summary: nil, sourceURL: "https://example.com",
      sourceKind: "public", verified: true, items: [repriced]
    )
    XCTAssertEqual(updated.priceRangeText, "¥640")
  }

  func testPendingFieldCountUsesDerivedPriceNotRawFields() {
    // 价格全在 SKU 表里（归集商品的情形）不该被算成「缺价格」
    let item = MidsummerItemDTO(
      id: "i", seriesID: "s", name: "款", kind: .set,
      price: nil, deposit: nil, balance: nil,
      priceKind: nil, priceCapturedOn: nil, priceNote: "逐款价见 SKU 表",
      sizes: ["S"], colors: [], coverImage: nil, itemURL: nil,
      sourceURL: "https://example.com", note: nil, specGroups: nil,
      skus: [MidsummerSKU(id: "k", options: [:], image: nil, price: 329)]
    )
    XCTAssertTrue(item.hasPrice, "有 SKU 逐款价就不算缺价格")
    XCTAssertEqual(item.priceText, "¥329")
  }
}
