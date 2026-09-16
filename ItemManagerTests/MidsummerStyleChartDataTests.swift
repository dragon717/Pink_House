import XCTest
@testable import ItemManager

// MARK: - 款式资料数据（原生页数据层）测试
//
// 校验两个随包资源 JSON 可解码、内容完整：
// - midsummer-style-chart.json：15 个分类、24 张色卡、16 张尺码表，全部图片在包内；
// - midsummer-link-report.json：2 个链接、16+8 个颜色分类、55+8 行 SKU。

final class MidsummerStyleChartDataTests: XCTestCase {

  private func load<T: Decodable>(
    _ filename: String, as type: T.Type, file: StaticString = #filePath, line: UInt = #line
  ) throws -> T {
    let candidates = [
      Bundle.main.url(forResource: filename, withExtension: "json"),
      Bundle(for: Self.self).url(forResource: filename, withExtension: "json"),
    ]
    let url = try XCTUnwrap(
      candidates.compactMap { $0 }.first,
      "找不到 \(filename).json", file: file, line: line)
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
  }

  func testStyleChartCatalogDecodesWithFullContent() throws {
    let catalog = try load("midsummer-style-chart", as: MidsummerStyleChartCatalog.self)

    XCTAssertEqual(catalog.categories.count, 15, "应有 15 个款式分类")
    XCTAssertEqual(catalog.sources.count, 2, "两个淘宝来源链接")

    let swatchCount = catalog.categories.reduce(0) { $0 + $1.swatches.count }
      + catalog.categories.reduce(0) { $0 + $1.charts.reduce(0) { $0 + ($1.swatches?.count ?? 0) } }
    XCTAssertEqual(swatchCount, 24, "共 24 张色卡")

    let chartCount = catalog.categories.reduce(0) { $0 + $1.charts.count }
    XCTAssertEqual(chartCount, 16, "共 16 张尺码表")

    // 全部色卡/尺码表图都引用 seed- 静态素材（随包分发）
    let referenced = catalog.categories.flatMap { category in
      category.swatches.map(\.imageName)
        + category.charts.flatMap { chart in
          [chart.imageName] + (chart.swatches?.map(\.imageName) ?? [])
        }
    }
    XCTAssertTrue(
      referenced.allSatisfy { $0.hasPrefix("seed-") },
      "所有图片必须引用 bundle 静态素材，实际: \(referenced.filter { !$0.hasPrefix("seed-") })")

    // SK 表应有 3 行数据（S/M/L）
    let sk = try XCTUnwrap(catalog.categories.first { $0.id == "sk" })
    XCTAssertEqual(sk.charts.first?.rows.count, 3)

    // 小物分类应含两张表（立体小脸包 + bb帽）
    let xw = try XCTUnwrap(catalog.categories.first { $0.id == "xw" })
    XCTAssertEqual(xw.charts.count, 2)
    XCTAssertEqual(xw.charts.map(\.title), ["立体小脸包", "bb帽"])
  }

  func testLinkReportDecodesWithFullContent() throws {
    let report = try load("midsummer-link-report", as: MidsummerLinkReport.self)

    XCTAssertEqual(report.links.count, 2)
    let ids = report.links.map(\.itemID)
    XCTAssertEqual(Set(ids), ["1032370386538", "1031690555405"])

    let main = try XCTUnwrap(report.links.first { $0.itemID == "1032370386538" })
    XCTAssertEqual(main.colorOptions.count, 16)
    XCTAssertEqual(main.skuRows.count, 55)
    XCTAssertEqual(main.priceRange, "¥119–999")
    XCTAssertEqual(main.shopName, "仲夏物语原创设计")

    let goods = try XCTUnwrap(report.links.first { $0.itemID == "1031690555405" })
    XCTAssertEqual(goods.colorOptions.count, 8)
    XCTAssertEqual(goods.skuRows.count, 8)
    XCTAssertEqual(goods.priceRange, "¥59–149")
    XCTAssertNotNil(goods.shortURL, "小物链接应保留原始短链")

    // 颜色分类名必须与种子 JSON 的选项名完全一致（同一命名规则）
    let seed = try loadSeedCatalog()
    let seedOptionNames = Set(
      seed.series.flatMap(\.items)
        .compactMap(\.specGroups)
        .flatMap { $0 }
        .filter { $0.id == "style" }
        .flatMap(\.options)
        .map(\.name))
    let reportNames = Set(report.links.flatMap(\.colorOptions).map(\.name))
    XCTAssertEqual(
      reportNames.subtracting(seedOptionNames), [],
      "链接报告里出现了种子选项没有的颜色分类名")
  }

  private func loadSeedCatalog() throws -> MidsummerCatalogDTO {
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
}
