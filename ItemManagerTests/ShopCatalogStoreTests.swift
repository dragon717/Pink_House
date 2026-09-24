//
//  ShopCatalogStoreTests.swift
//  ItemManagerTests
//
//  Phase 2（只读浏览）数据层验收：
//    · Bundle 整包加载与日期解码（ISO8601）
//    · 店家搜索（正式名 + 别名，计划 §8/§9）
//    · 店家卡片指标（最近上新时间 / 系列数，§9）
//    · 当前上新 vs 历年系列（§10）
//    · 分类筛选与固定顺序（§11）
//    · 价格档案（历史预约价 + 当前现货价 + 差价，§13/§6）
//    · 上新窗口状态（预约中 / 未开始 / 已结束）
//

import XCTest
@testable import ItemManager

/// Store 为 @MainActor，测试也标注主线程隔离
@MainActor
final class ShopCatalogStoreTests: XCTestCase {

    /// 演示数据锚点：预约期 2026-09-10 ~ 09-28，现货 2026-11-01 起
    private var now: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 20; c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal.date(from: c)!
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @discardableResult
    private func loadedStore() -> ShopCatalogStore {
        // 种子已连根清理（2026-09-24）：演示数据锚点改由合成种子夹具提供（同 id 同字段）
        let s = ShopCatalogSeedFixture.makeStore()
        XCTAssertNotNil(s.catalog, "合成种子应能直接构建")
        return s
    }

    // MARK: 加载

    func testBundleCatalogLoadsEmptyAfterSeedCleanup() throws {
        // 空种子契约：Bundle 仍要能正常加载（不白屏），且不再内置任何店家数据
        let s = ShopCatalogStore()
        XCTAssertNotNil(s.loadFromBundleIfNeeded(), "Bundle 内应存在 shop-catalog.json")
        let catalog = try XCTUnwrap(s.catalog)
        XCTAssertTrue(catalog.shops.isEmpty, "种子店家应已连根清理")
        XCTAssertTrue(catalog.series.isEmpty)
        XCTAssertTrue(catalog.products.isEmpty)
        XCTAssertTrue(catalog.saleEvents.isEmpty)
        XCTAssertEqual(s.status, .loaded)
    }

    // MARK: 店家搜索（§8/§9）

    func testShopSearchByAlias() {
        let s = loadedStore()
        XCTAssertEqual(s.searchShops(keyword: "许愿池").first?.id, "shop-unniq")
        XCTAssertEqual(s.searchShops(keyword: "unniq").first?.id, "shop-unniq")
        XCTAssertEqual(s.searchShops(keyword: "AG").first?.id, "shop-alice-girl")
        XCTAssertEqual(s.searchShops(keyword: "爱丽丝").count, 1)
        XCTAssertEqual(s.searchShops(keyword: "").count, s.catalog?.shops.count ?? 0)
    }

    // MARK: 店家卡片指标（§9）

    func testShopCardMetrics() {
        let s = loadedStore()
        // 「已上新」= startAt ≤ now：2026.09 预约已开始，2026.11 现货排期不算
        let activity = s.latestActivityDate(shopID: "shop-alice-girl", now: now)
        XCTAssertEqual(ShopCatalogFormat.month(activity), "2026.09")
        XCTAssertEqual(s.series(inShop: "shop-alice-girl").count, 2)
        // 列表按最近上新倒序：Alice Girl（2026.09）在 UNNIQ（2026.07）之前
        XCTAssertEqual(s.shopsSortedByActivity().first?.id, "shop-alice-girl")
    }

    // MARK: 当前上新 vs 历年系列（§10）

    func testCurrentAndArchiveSeries() {
        let s = loadedStore()
        // 雪国来信有预约中（open）与未开始（upcoming）记录 → 当前上新
        XCTAssertEqual(s.currentSeries(inShop: "shop-alice-girl", now: now).map(\.id),
                       ["series-ag-xueguo-2026"])
        // 星屑圆舞曲现货已结束 → 历年
        XCTAssertTrue(s.archiveSeries(inShop: "shop-alice-girl", now: now).map(\.id)
            .contains("series-ag-xingwu-2025"))
        // UNNIQ 全部记录已结束 → 当前上新为空
        XCTAssertTrue(s.currentSeries(inShop: "shop-unniq", now: now).isEmpty)
        XCTAssertEqual(s.years(inShop: "shop-alice-girl"), [2026, 2025])
    }

    // MARK: 分类筛选（§11）

    func testCategoryFilterAndOrder() {
        let s = loadedStore()
        XCTAssertEqual(s.categories(inSeries: "series-ag-xueguo-2026"), ["JSK", "KC", "小物", "包"])
        XCTAssertEqual(s.products(inSeries: "series-ag-xueguo-2026", category: "JSK").map(\.name),
                       ["雪国来信 JSK"])
        XCTAssertEqual(s.products(inSeries: "series-ag-xueguo-2026").count, 4)
        XCTAssertEqual(s.productCount(inSeries: "series-ag-xueguo-2026"), 4)
    }

    // MARK: 价格档案（§13/§6）

    func testPriceArchive() throws {
        let s = loadedStore()
        let archive = s.priceArchive(forProduct: "prod-ag-xueguo-jsk")
        XCTAssertEqual(archive.historicalReservationPrice, 428)
        XCTAssertEqual(archive.currentStockPrice, 568)
        XCTAssertEqual(archive.stockOverReservationDelta, 140)
        XCTAssertEqual(archive.reservation?.deposit, 128)
        XCTAssertEqual(archive.reservation?.balance, 300)
        XCTAssertTrue(archive.reservation?.isDepositBalanceConsistent ?? false)

        // 只有历史现货的历年商品：无预约价、无差价
        let archive2025 = s.priceArchive(forProduct: "prod-ag-xingwu-jsk")
        XCTAssertNil(archive2025.historicalReservationPrice)
        XCTAssertEqual(archive2025.currentStockPrice, 398)
        XCTAssertNil(archive2025.stockOverReservationDelta)
    }

    // MARK: 上新窗口状态

    func testWindowStatus() throws {
        let s = loadedStore()
        let resv = try XCTUnwrap(s.saleEvent(id: "ev-ag-jsk-resv-2026"))
        let stock = try XCTUnwrap(s.saleEvent(id: "ev-ag-jsk-stock-2026"))
        let past = try XCTUnwrap(s.saleEvent(id: "ev-ag-xw-stock-2025"))

        XCTAssertEqual(s.windowStatus(of: resv, now: now), .open)
        XCTAssertEqual(s.windowStatus(of: resv, now: date(2026, 9, 5)), .upcoming)
        XCTAssertEqual(s.windowStatus(of: resv, now: date(2026, 10, 1)), .ended)
        XCTAssertEqual(s.windowStatus(of: stock, now: now), .upcoming)
        XCTAssertEqual(s.windowStatus(of: past, now: now), .ended)
        // 无时间窗口 → 长期有效
        let noWindow = CatalogSaleEvent(id: "ev-x", productID: "p", type: .stock, price: 100)
        XCTAssertEqual(s.windowStatus(of: noWindow, now: now), .ongoing)
    }

    // MARK: 规格汇总（§13）

    func testVariantAggregation() {
        let s = loadedStore()
        XCTAssertEqual(s.colors(forProduct: "prod-ag-xueguo-jsk"), ["夜空蓝", "初雪白"])
        XCTAssertEqual(s.sizes(forProduct: "prod-ag-xueguo-jsk"), ["S", "M", "L"])
        // KC 只有配色没有尺码
        XCTAssertEqual(s.colors(forProduct: "prod-ag-xueguo-kc"), ["夜空蓝", "初雪白"])
        XCTAssertTrue(s.sizes(forProduct: "prod-ag-xueguo-kc").isEmpty)
    }

    // MARK: 尺码表与资产（§15/§5）

    func testSizeChartAndAssets() throws {
        let s = loadedStore()
        let chart = try XCTUnwrap(s.sizeChart(forProduct: "prod-ag-xueguo-jsk"))
        XCTAssertTrue(chart.hasStructuredContent)
        XCTAssertEqual(chart.columns, ["S", "M", "L"])
        XCTAssertEqual(chart.rows.first?.label, "胸围")

        let asset = try XCTUnwrap(s.asset(id: "asset-ag-jsk-size"))
        XCTAssertEqual(asset.type, .sizeChartImage)
        XCTAssertFalse(asset.originalURL.isEmpty, "CatalogAsset 必须保留 originalURL（计划 §5）")

        // 演示数据引用的 Bundle 图（复用时光馆画册图）应能解析到
        XCTAssertNotNil(ShopCatalogImageResolver.url(for: asset.originalURL))
    }

    // MARK: 年份筛选口径（2026-09-24 店主页「年份死区」回归）

    /// 店主页年份 chip 的筛选数据源必须是**全量系列**（`series(inShop:)`），
    /// 不能用 `archiveSeries`（= 全量 − 当前上新）：正在上新的系列会被排除，
    /// 在它自己标注的年份下永远查不到（用户实测：系列填年月 2026-4、现货在售，
    /// 点「2026」chip 却显示「该年份暂无收录系列」）。
    /// 「当前上新」是活动维度，年份是档案维度，两者正交。
    func testYearFilterCoversOngoingSeries() {
        let s = loadedStore()
        let now = self.now
        // fixture 锚点：雪国来信 year=2026，预约 2026-09-10 ~ 09-28 在 now 时 ongoing
        let seriesID = "series-ag-xueguo-2026"
        XCTAssertTrue(
            s.currentSeries(inShop: "shop-alice-girl", now: now).contains { $0.id == seriesID },
            "前置：该系列正在上新（锚点失效请检查 fixture 销售事件）")
        XCTAssertFalse(
            s.archiveSeries(inShop: "shop-alice-girl", now: now).contains { $0.id == seriesID },
            "前置：archiveSeries 会把在售系列排除——这正是当年份死区的来源")
        // 修复后的年份筛选口径（店主页 visibleSeries 的 .year 分支同语义）
        let yearFiltered = s.series(inShop: "shop-alice-girl").filter { $0.year == 2026 }
        XCTAssertTrue(
            yearFiltered.contains { $0.id == seriesID },
            "年份筛选必须能看到正在上新的系列（不能用 archiveSeries 过滤）")
        XCTAssertTrue(s.years(inShop: "shop-alice-girl").contains(2026))
    }
}
