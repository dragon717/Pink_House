//
//  ShopCatalogModelsTests.swift
//  ItemManagerTests
//
//  Phase 1 领域模型单测：覆盖 docs/少女心愿_店家上新_第一版落地计划.md
//  中与模型直接相关的硬约束——
//    §6  预约价与现货价并存、不覆盖、差价展示口径
//    §5  CatalogAsset 必须保留 originalURL
//    §9  店家别名搜索
//    §4  Catalog JSON 往返（公共 Catalog 与用户数据分层的传输结构）
//

import XCTest
@testable import ItemManager

final class ShopCatalogModelsTests: XCTestCase {

    // MARK: 夹具：Alice Girl / 雪国来信（计划 §35 测试数据）

    private func makeSaleEvents() -> [CatalogSaleEvent] {
        let df = ISO8601DateFormatter()
        return [
            CatalogSaleEvent(
                id: "se-1", productID: "p-jsk", type: .reservation,
                price: 428, deposit: 100, balance: 328,
                startAt: df.date(from: "2026-09-01T00:00:00Z"),
                endAt: df.date(from: "2026-09-30T00:00:00Z")),
            CatalogSaleEvent(
                id: "se-2", productID: "p-jsk", type: .stock,
                price: 568, deposit: nil, balance: nil,
                startAt: df.date(from: "2026-11-01T00:00:00Z")),
        ]
    }

    // MARK: 价格档案（计划 §6）

    /// 预约价不被现货价覆盖：档案同时给出 ¥428 / ¥568，差价 ¥140
    func testPriceArchiveKeepsBothReservationAndStock() {
        let archive = CatalogPriceArchive(events: makeSaleEvents())
        XCTAssertEqual(archive.historicalReservationPrice, 428)
        XCTAssertEqual(archive.currentStockPrice, 568)
        XCTAssertEqual(archive.stockOverReservationDelta, 140)
    }

    /// 多条同类记录取时间最近的一条（再贩 / 二次预约场景）
    func testPriceArchiveTakesLatestPerType() {
        let df = ISO8601DateFormatter()
        var events = makeSaleEvents()
        events.append(CatalogSaleEvent(
            id: "se-3", productID: "p-jsk", type: .reservation,
            price: 478, deposit: 120, balance: 358,
            startAt: df.date(from: "2026-10-15T00:00:00Z")))
        let archive = CatalogPriceArchive(events: events)
        XCTAssertEqual(archive.reservation?.id, "se-3")
        XCTAssertEqual(archive.historicalReservationPrice, 478)
        // 现货侧不受影响
        XCTAssertEqual(archive.currentStockPrice, 568)
    }

    /// 只有现货（无预约）时差价为 nil，不崩溃
    func testPriceArchiveWithStockOnly() {
        let stock = CatalogSaleEvent(id: "se-2", productID: "p-jsk", type: .stock, price: 568)
        let archive = CatalogPriceArchive(events: [stock])
        XCTAssertNil(archive.historicalReservationPrice)
        XCTAssertEqual(archive.currentStockPrice, 568)
        XCTAssertNil(archive.stockOverReservationDelta)
    }

    /// 定金 + 尾款 = 总价 校验
    func testSaleEventDepositBalanceConsistency() {
        XCTAssertTrue(makeSaleEvents()[0].isDepositBalanceConsistent)
        var broken = makeSaleEvents()[0]
        broken.balance = 999
        XCTAssertFalse(broken.isDepositBalanceConsistent)
    }

    // MARK: CatalogAsset（计划 §5）

    /// 原图 URL 必须保留，不得只存缩略图
    func testCatalogAssetKeepsOriginalURL() throws {
        let asset = CatalogAsset(
            id: "a-1", type: .sizeChartImage,
            thumbnailURL: "thumb://a-1", previewURL: "preview://a-1",
            originalURL: "original://a-1", width: 1000, height: 800)
        let data = try JSONEncoder().encode(asset)
        let decoded = try JSONDecoder().decode(CatalogAsset.self, from: data)
        XCTAssertEqual(decoded.originalURL, "original://a-1")
        XCTAssertEqual(decoded.type, .sizeChartImage)
    }

    // MARK: 店家别名（计划 §9）

    /// UNNIQ 许愿池原创：正式名与别名均可命中
    func testShopAliasMatching() {
        let shop = CatalogShop(
            id: "s-1", name: "UNNIQ 许愿池原创",
            aliases: ["UNNIQ", "许愿池"])
        XCTAssertTrue(shop.matches(nameOrAlias: "UNNIQ"))
        XCTAssertTrue(shop.matches(nameOrAlias: "许愿池"))
        XCTAssertTrue(shop.matches(nameOrAlias: "unniq 许愿池原创"))
        XCTAssertFalse(shop.matches(nameOrAlias: "Alice Girl"))
        XCTAssertFalse(shop.matches(nameOrAlias: "  "))
    }

    // MARK: JSON 往返（计划 §4）

    /// 整包 Catalog JSON 解码 → 再编码往返不丢数据
    func testShopCatalogJSONRoundTrip() throws {
        let df = ISO8601DateFormatter()
        let catalog = ShopCatalog(
            shops: [CatalogShop(id: "s-alice", name: "Alice Girl", aliases: ["AliceGirl"])],
            series: [CatalogSeries(id: "sr-1", shopID: "s-alice", name: "雪国来信",
                                   year: 2026, season: "冬")],
            products: [CatalogProduct(id: "p-jsk", shopID: "s-alice", seriesID: "sr-1",
                                      name: "雪国来信 JSK", category: "JSK")],
            variants: [CatalogProductVariant(id: "v-1", productID: "p-jsk",
                                             color: "蓝色", size: "M")],
            sizeCharts: [CatalogSizeChart(
                id: "sc-1", productID: "p-jsk", unit: "cm",
                columns: ["S", "M", "L"],
                rows: [CatalogSizeRow(label: "胸围", values: ["80-84", "84-88", "88-92"])],
                sourceImage: "a-sizechart")],
            saleEvents: makeSaleEvents(),
            assets: [CatalogAsset(id: "a-sizechart", type: .sizeChartImage,
                                  originalURL: "original://sc")])

        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(ShopCatalog.self, from: data)

        XCTAssertEqual(decoded, catalog)
        XCTAssertEqual(decoded.series.first?.name, "雪国来信")
        XCTAssertEqual(decoded.saleEvents.first?.startAt,
                       df.date(from: "2026-09-01T00:00:00Z"))
        XCTAssertEqual(decoded.sizeCharts.first?.hasStructuredContent, true)
    }

    /// 缺省字段（nil）解码兜底：旧格式 JSON 缺新字段时不应失败
    func testShopCatalogDecodeWithMissingOptionalFields() throws {
        let json = """
        {
          "version": 1,
          "shops": [{"id": "s-1", "name": "Alice Girl"}],
          "series": [{"id": "sr-1", "shopID": "s-1", "name": "雪国来信"}],
          "products": [{"id": "p-1", "shopID": "s-1", "seriesID": "sr-1",
                        "name": "雪国来信 JSK", "category": "JSK"}],
          "variants": [],
          "sizeCharts": [],
          "saleEvents": [{"id": "se-1", "productID": "p-1",
                          "type": "reservation", "price": 428}],
          "assets": []
        }
        """
        let catalog = try JSONDecoder().decode(ShopCatalog.self, from: Data(json.utf8))
        XCTAssertEqual(catalog.products.count, 1)
        XCTAssertEqual(catalog.saleEvents.first?.type, .reservation)
        XCTAssertEqual(catalog.shops.first?.aliases, []) // 缺失键兜底为空数组
    }
}
