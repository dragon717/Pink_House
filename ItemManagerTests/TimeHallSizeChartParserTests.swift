import XCTest

@testable import ItemManager

/// 尺码表解析（第二步 · 商品功能的「尺码表」数据来源）。
///
/// 覆盖三件关键事：
///   1. 已抓取的描述文本能被解析成结构化尺码表（这是零成本的主来源）
///   2. 旧 JSON 没有新字段时能正常解码（不能因为加字段就炸掉历史数据）
///   3. 解析不出来的商品返回 nil，由界面走「待补充 + 人工录入」而不是显示错数据
final class TimeHallSizeChartParserTests: XCTestCase {

  // MARK: - 解析规则

  func testParsesJapaneseMeasurementsAndKeepsRange() {
    let text = """
      商品説明
      着丈：約98cm
      バスト：約88～140cm
      ウエスト：約68～138cm
      肩幅：約34cm
      袖丈：約62cm
      """

    let chart = TimeHallSizeChartParser.parse(
      japaneseText: text,
      chineseText: nil,
      sizes: ["FREE"],
      sourceURL: "https://example.com/p/1"
    )

    let unwrapped = try? XCTUnwrap(chart)
    XCTAssertNotNil(unwrapped, "5 项测量值应当解析成功")
    guard let chart = unwrapped else { return }

    XCTAssertEqual(chart.unit, "cm")
    XCTAssertEqual(chart.columns, ["尺码", "衣长", "胸围", "腰围", "肩宽", "袖长"])
    XCTAssertEqual(chart.rows.count, 1)
    XCTAssertEqual(chart.rows[0].label, "FREE", "单一尺码时行标签用该尺码")
    XCTAssertEqual(chart.rows[0].values, ["98", "88～140", "68～138", "34", "62"])
    XCTAssertEqual(chart.sourceURL, "https://example.com/p/1")
    XCTAssertEqual(chart.isManuallyEntered, false, "来自文本解析的不能标成人工录入")
    XCTAssertTrue(chart.isUsable)
  }

  func testChineseDescriptionFillsColumnsMissingFromJapanese() {
    let ja = """
      着丈：約96cm
      バスト：約88～103cm
      ウエスト：約69～84cm
      """
    let zh = """
      衣长：约96cm
      胸围：约88～103cm
      腰围：约69～84cm
      肩宽：约34cm
      袖长：约62cm
      """

    let chart = try? XCTUnwrap(
      TimeHallSizeChartParser.parse(japaneseText: ja, chineseText: zh, sizes: [])
    )
    guard let chart else { return XCTFail("应当解析成功") }

    // 肩宽 / 袖长 只在中文里有，应被补齐；顺序仍按规范列走。
    XCTAssertEqual(chart.columns, ["尺码", "衣长", "胸围", "腰围", "肩宽", "袖长"])
    XCTAssertEqual(chart.rows[0].values.count, 5, "values 必须与表头列数一致")
    XCTAssertEqual(chart.rows[0].values[3], "34")
    XCTAssertEqual(chart.rows[0].values[4], "62")
  }

  func testJapaneseWinsOverChineseForSameColumn() {
    let ja = "着丈：約98cm バスト：約90cm ウエスト：約70cm"
    let zh = "衣长：约99cm 胸围：约91cm 腰围：约71cm"

    let chart = TimeHallSizeChartParser.parse(japaneseText: ja, chineseText: zh, sizes: [])
    XCTAssertEqual(chart?.rows.first?.values.first, "98", "同列冲突时以日文原文为准")
  }

  func testFewerThanThreeColumnsReturnsNil() {
    // 只有 2 项：多半是描述正文里偶然出现的词，不是尺码表。
    let text = "着丈：約47cm ウエスト：約65cm"
    XCTAssertNil(
      TimeHallSizeChartParser.parse(japaneseText: text, chineseText: nil, sizes: []),
      "少于 3 项不应产出尺码表"
    )
  }

  func testProseMentioningWaistDoesNotProduceChart() {
    // Wunderwelt 的描述里到处是「ウエスト」，但没有数值 —— 不能误判成尺码表。
    let text = "背面の両サイドには編上げに見立てた装飾があり、ウエストラインをすっきり見せます。"
    XCTAssertNil(TimeHallSizeChartParser.parse(japaneseText: text, chineseText: nil, sizes: []))
  }

  func testMultipleSizesAreLabelledAsOneSizeWithCaveat() {
    let text = "着丈：約98cm バスト：約88cm ウエスト：約68cm"
    let chart = TimeHallSizeChartParser.parse(
      japaneseText: text,
      chineseText: nil,
      sizes: ["S", "M", "L"]
    )
    guard let chart else { return XCTFail("应当解析成功") }
    XCTAssertEqual(chart.rows[0].label, "均码", "单组测量值不区分尺码，不能假装按尺码分了")
    XCTAssertNotNil(chart.noteZH)
    XCTAssertTrue(
      chart.noteZH?.contains("不区分") == true,
      "必须显式说明这组尺寸不区分尺码，避免误导"
    )
  }

  func testDuplicateMentionsKeepFirstValue() {
    let text = """
      着丈：約98cm
      バスト：約88cm
      ウエスト：約68cm
      着丈：約999cm
      """
    let chart = TimeHallSizeChartParser.parse(japaneseText: text, chineseText: nil, sizes: [])
    XCTAssertEqual(chart?.rows.first?.values.first, "98", "重复出现时应保留首次出现的值")
  }

  func testRowValuesAlignToColumnCount() {
    let long = TimeHallSizeRow(label: "S", values: ["1", "2", "3"], alignTo: 5)
    XCTAssertEqual(long.values.count, 5)
    XCTAssertEqual(long.values.suffix(2), ["—", "—"])

    let short = TimeHallSizeRow(label: "S", values: ["1", "2", "3", "4", "5", "6"], alignTo: 3)
    XCTAssertEqual(short.values, ["1", "2", "3"], "超出列数的值应被裁掉")
  }

  // MARK: - 解码兼容（加字段不能炸历史数据）

  func testLegacyJSONWithoutSpecFieldsDecodesWithNilSpecs() throws {
    let items = try loadCommerceItems(resourceName: "catalog-angelic-pretty")
    XCTAssertFalse(items.isEmpty, "应当能解出商品")

    // 历史 JSON 没有 priceTiers / sizeChart 两个键 —— 必须按 nil 解码，
    // 而不是抛 keyNotFound。
    for item in items.prefix(20) {
      XCTAssertNil(item.priceTiers)
      XCTAssertNil(item.sizeChart)
    }
  }

  func testStoredChartTakesPrecedenceOverParsedOne() throws {
    // 同一条数据既有可解析的描述文本、又存了结构化尺码表（人工录入场景），
    // 结构化数据必须赢。顺带验证新增字段能被正确解码。
    let json = """
      {
        "commerceItems": [{
          "id": "test-1",
          "productCode": "p-1",
          "kind": "dress",
          "category": "current",
          "categoryZH": "连衣裙",
          "name": "テスト",
          "nameZH": "测试款",
          "brand": "test",
          "sourceKind": "current",
          "regularPriceJPY": 1000,
          "listingStatus": "in_stock",
          "description": "着丈：約98cm バスト：約88cm ウエスト：約68cm",
          "colors": ["红"],
          "sizes": ["S", "M"],
          "styles": [],
          "stylesZH": [],
          "coverImage": "",
          "imageSourceURLs": [],
          "productPageURL": "https://example.com/p",
          "observedAt": "2026-01-01",
          "priceTiers": [{
            "label": "M",
            "size": "M",
            "regularPriceJPY": 1200,
            "depositJPY": 200,
            "balanceJPY": 1000,
            "currency": "JPY"
          }],
          "sizeChart": {
            "unit": "cm",
            "columns": ["尺码", "胸围"],
            "rows": [{ "label": "M", "values": ["90"] }],
            "isManuallyEntered": true,
            "noteZH": "创作者录入"
          }
        }]
      }
      """.data(using: .utf8)!

    struct Envelope: Decodable { let commerceItems: [TimeHallCommerceItemDTO] }
    let item = try XCTUnwrap(
      JSONDecoder().decode(Envelope.self, from: json).commerceItems.first
    )

    XCTAssertEqual(item.priceTiers?.count, 1)
    XCTAssertEqual(item.priceTiers?.first?.depositJPY, 200)
    XCTAssertEqual(item.priceTiers?.first?.label, "M")

    let resolved = try XCTUnwrap(item.resolvedSizeChart)
    XCTAssertEqual(resolved.isManuallyEntered, true, "已存的结构化尺码表必须优先于文本解析")
    XCTAssertEqual(resolved.rows.first?.label, "M")
    XCTAssertEqual(resolved.columns, ["尺码", "胸围"])
  }

  // MARK: - 真实数据覆盖率（回归护栏）

  /// 记录在案的覆盖率：Baby 861 件里 283 件可解析，全部目錄合计 285 / 4773。
  /// 这里给出下限而非精确值，避免数据小幅增补就把测试打红。
  func testRealCatalogCoverageStaysAboveRecordedFloor() throws {
    let babyItems = try loadCommerceItems(resourceName: "catalog-baby-stars-shine-bright")
    let babyParsable = babyItems.filter { $0.resolvedSizeChart != nil }.count
    XCTAssertGreaterThanOrEqual(
      babyParsable, 200,
      "Baby 目录可解析尺码表数量跌破记录下限（记录值 283），解析规则可能被改坏"
    )

    var total = 0
    var parsable = 0
    for name in [
      "catalog", "catalog-angelic-pretty", "catalog-baby-stars-shine-bright",
      "catalog-juliette-et-justine", "catalog-wunderwelt-fleur",
    ] {
      let items = try loadCommerceItems(resourceName: name)
      total += items.count
      parsable += items.filter { $0.resolvedSizeChart != nil }.count
    }
    XCTAssertGreaterThan(total, 4000)
    XCTAssertGreaterThanOrEqual(
      parsable, 250,
      "全库可解析尺码表数量跌破记录下限（记录值 285）"
    )
  }

  // MARK: - 辅助

  /// 用与 `TimeHallBundleSource` 相同的候选路径从 Bundle 取 JSON。
  private func loadCommerceItems(resourceName: String) throws -> [TimeHallCommerceItemDTO] {
    let bundle = Bundle.main
    let candidates: [URL?] = [
      bundle.url(forResource: resourceName, withExtension: "json", subdirectory: "TimeHall"),
      bundle.url(forResource: resourceName, withExtension: "json", subdirectory: "Resources/TimeHall"),
      bundle.url(forResource: resourceName, withExtension: "json"),
    ]
    guard let url = candidates.compactMap({ $0 }).first else {
      throw XCTSkip("Bundle 里找不到 \(resourceName).json，跳过真实数据校验")
    }
    struct Envelope: Decodable { let commerceItems: [TimeHallCommerceItemDTO] }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(Envelope.self, from: data).commerceItems
  }
}
