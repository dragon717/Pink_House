//
//  ShopCatalogPriceCoexistTests.swift
//  ItemManagerTests
//
//  补录上新 · 预约价 / 现货价并存 + 系列级预约价格表（2026-09-22）：
//    1. 预约价与现货价并存且不互斥：可同时填写、各自生成 SaleEvent；
//       现货价可空置（后续补录），校验不得因填其一而禁用另一项
//    2. 旧口径兼容：saleKind == .stock 的存量草稿 price 仍按现货解释
//    3. 系列级预约价格表：归属系列（非单品），随系列持久化，旧 JSON 缺键兼容
//    4. 价格表 / 尺码表图片文本解析（OCR 下游）：表头 + 行列映射 + 占位符兜底
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogPriceCoexistTests: XCTestCase {

    private var store = ShopCatalogStore()

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        store = ShopCatalogStore()
        XCTAssertNotNil(store.loadFromBundleIfNeeded())
        CreatorAccess.setTestOverride(.creator)
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    private func publishNew(_ draft: CatalogProductDraft) throws -> String {
        let draftStore = ShopCatalogDraftStore.shared
        try draftStore.advance(draft, to: .submitted)
        var d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.advance(d, to: .reviewed)
        d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        return try draftStore.publish(d, store: store)
    }

    private func makeDraft(name: String, shop: String, series: String) -> CatalogProductDraft {
        var draft = CatalogProductDraft()
        draft.name = name
        draft.newShopName = shop
        draft.newSeriesName = series
        return draft
    }

    // MARK: 1. 预约 / 现货并存

    func testBothPricesProduceTwoSaleEvents() throws {
        var draft = makeDraft(name: "并存价格款", shop: "并存店家", series: "并存系列")
        draft.price = 428          // 预约价
        draft.deposit = 128
        draft.balance = 300
        draft.stockPrice = 568     // 现货价（并存）
        _ = try publishNew(draft)

        let product = try XCTUnwrap(store.product(named: "并存价格款"))
        let events = store.saleEvents(forProduct: product.id)
        XCTAssertEqual(events.count, 2, "预约 + 现货应各生成一条销售记录")
        XCTAssertEqual(events.filter { $0.type == .reservation }.first?.price, 428)
        XCTAssertEqual(events.filter { $0.type == .reservation }.first?.deposit, 128)
        XCTAssertEqual(events.filter { $0.type == .reservation }.first?.balance, 300)
        XCTAssertEqual(events.filter { $0.type == .stock }.first?.price, 568)

        // 价格档案并列可读（商品页展示所需全部字段）
        let archive = store.priceArchive(forProduct: product.id)
        XCTAssertEqual(archive.historicalReservationPrice, 428)
        XCTAssertEqual(archive.reservation?.deposit, 128)
        XCTAssertEqual(archive.reservation?.balance, 300)
        XCTAssertEqual(archive.currentStockPrice, 568)
        XCTAssertEqual(archive.stockOverReservationDelta, 140)
    }

    func testStockPriceAloneIsAllowedForLaterSupplement() throws {
        var draft = makeDraft(name: "仅现货款", shop: "并存店家", series: "并存系列")
        draft.price = 0            // 预约价空置
        draft.stockPrice = 399
        _ = try publishNew(draft)

        let product = try XCTUnwrap(store.product(named: "仅现货款"))
        let events = store.saleEvents(forProduct: product.id)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .stock)
        XCTAssertEqual(events.first?.price, 399)
    }

    func testLegacyStockDraftStillPublishesStockEvent() throws {
        // 存量草稿口径：saleKind == .stock 且未填 stockPrice → price 是现货价
        var draft = makeDraft(name: "旧现货款", shop: "并存店家", series: "并存系列")
        draft.saleKind = .stock
        draft.price = 128
        _ = try publishNew(draft)

        let product = try XCTUnwrap(store.product(named: "旧现货款"))
        let events = store.saleEvents(forProduct: product.id)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .stock, "旧现货草稿不得被解释成预约记录")
        XCTAssertEqual(events.first?.price, 128)
    }

    func testValidatorRejectsDraftWithoutAnyPrice() {
        var draft = makeDraft(name: "无价格款", shop: "并存店家", series: "并存系列")
        draft.price = 0
        draft.stockPrice = nil
        XCTAssertThrowsError(try ShopCatalogDraftValidator.validate(draft, catalog: store.catalog)) { error in
            guard case ShopCatalogDraftValidator.ValidationError.invalidPrice = error else {
                return XCTFail("应抛 invalidPrice，实际：\(error)")
            }
        }
    }

    // MARK: 2. 系列级预约价格表

    func testSeriesPriceChartPersistsAndFeedsProducts() throws {
        // 先发布一个商品拿到系列
        var draft = makeDraft(name: "价格表系列款", shop: "价格表店家", series: "价格表系列")
        draft.price = 100
        draft.stockPrice = 120
        _ = try publishNew(draft)
        let product = try XCTUnwrap(store.product(named: "价格表系列款"))
        let series = try XCTUnwrap(store.series(id: product.seriesID))
        XCTAssertNil(series.priceChart, "初始无价格表")

        // 在系列维度配置价格表（模拟系列编辑 sheet 的保存路径）
        var updated = series
        var chart = CatalogPriceChart(id: "pricechart-test-1", seriesID: series.id)
        chart.columns = ["S", "M", "L"]
        chart.rows = [
            CatalogSizeRow(label: "定金", values: ["100", "100", "100"]),
            CatalogSizeRow(label: "尾款", values: ["328", "328", "328"]),
        ]
        chart.sourceImage = "local:pricechart-test.jpg"
        updated.priceChart = chart
        try ShopCatalogDraftStore.upsertEntity(updated, keyPath: \.series)
        store.reloadWithOverlay()

        // 单品详情页口径：经所属系列自动读取
        let reloaded = try XCTUnwrap(store.series(id: product.seriesID))
        let savedChart = try XCTUnwrap(reloaded.priceChart)
        XCTAssertTrue(savedChart.hasStructuredContent)
        XCTAssertEqual(savedChart.columns, ["S", "M", "L"])
        XCTAssertEqual(savedChart.rows.count, 2)
        XCTAssertEqual(savedChart.rows[0].values[0], "100")
    }

    func testSeriesDecodeWithoutPriceChartIsBackwardCompatible() throws {
        let json = """
        {"id":"s-old","shopID":"shop-1","name":"旧系列"}
        """
        let series = try JSONDecoder().decode(CatalogSeries.self, from: Data(json.utf8))
        XCTAssertNil(series.priceChart, "旧 JSON 无 priceChart 键应自动置 nil")
    }

    // MARK: 3. 价格表 / 尺码表文本解析（OCR 下游）

    func testParseSizeChartText() throws {
        let table = try CatalogChartParser.parseText([
            "商品信息忽略行",
            "尺码 S M L",
            "胸围 80-84 84-88 88-92",
            "裙长 92 94 96",
        ])
        XCTAssertEqual(table.columns, ["S", "M", "L"])
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows[0].label, "胸围")
        XCTAssertEqual(table.rows[0].values, ["80-84", "84-88", "88-92"])
        XCTAssertEqual(table.rows[1].values[2], "96")
    }

    func testParsePriceChartTextWithMissingCells() throws {
        let table = try CatalogChartParser.parseText([
            "尺码 S M L",
            "定金 100 100 -",
            "尾款 328 300 /",
        ])
        XCTAssertEqual(table.columns, ["S", "M", "L"])
        XCTAssertEqual(table.rows[0].values, ["100", "100", nil], "占位符「-」应解析为空")
        XCTAssertEqual(table.rows[1].values, ["328", "300", nil], "占位符「/」应解析为空")
    }

    func testParseFailsWithClearErrorWhenNoHeader() {
        XCTAssertThrowsError(try CatalogChartParser.parseText(["只有一个词元", "还是没有两列"])) { error in
            guard case CatalogChartParserError.tableUnparsable = error else {
                return XCTFail("应抛 tableUnparsable，实际：\(error)")
            }
            XCTAssertTrue(error.localizedDescription.contains("解析失败"), "提示必须可读：\(error.localizedDescription)")
        }
    }

    func testParseFailsWhenHeaderOnly() {
        XCTAssertThrowsError(try CatalogChartParser.parseText(["尺码 S M L"])) { error in
            guard case CatalogChartParserError.tableUnparsable = error else {
                return XCTFail("应抛 tableUnparsable，实际：\(error)")
            }
        }
    }
}
