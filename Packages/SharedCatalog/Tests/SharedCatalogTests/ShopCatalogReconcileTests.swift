//
//  ShopCatalogReconcileTests.swift
//  SharedCatalogTests
//
//  「以线上那一版为准对账本地」的回归锁（2026-09-29）。
//
//  ## 这份测试要防的是什么
//
//  对账是**会删东西**的动作：本地有、线上没有的条目会被移除。所以最怕的不是崩溃，
//  而是三件**不报错**的事：
//
//    1. 把「销售历史」也照着线上删掉 —— append-only 硬约束被破，历史不可恢复；
//    2. 对完了却**不等于**线上（悄悄少了几条 / 顺序漂了），而界面还说「已对齐」；
//    3. 报告漏项 —— 运营看不到「会移除什么」，只能事后发现东西没了。
//

import XCTest

@testable import SharedCatalog

final class ShopCatalogReconcileTests: XCTestCase {

    // MARK: - 夹具

    private func shop(_ id: String, name: String) -> CatalogShop {
        CatalogShop(id: id, name: name)
    }

    private func series(_ id: String, shop shopID: String, _ name: String) -> CatalogSeries {
        CatalogSeries(id: id, shopID: shopID, name: name, year: 2026)
    }

    private func product(
        _ id: String, shop shopID: String, series seriesID: String, _ name: String,
        category: String = "JSK"
    ) -> CatalogProduct {
        CatalogProduct(id: id, shopID: shopID, seriesID: seriesID, name: name, category: category)
    }

    private func event(_ id: String, product productID: String, price: Decimal = 100) -> CatalogSaleEvent {
        CatalogSaleEvent(id: id, productID: productID, type: .reservation, price: price)
    }

    private func catalog(
        shops: [CatalogShop] = [],
        series: [CatalogSeries] = [],
        products: [CatalogProduct] = [],
        saleEvents: [CatalogSaleEvent] = [],
        removedShopIDs: [String] = [],
        removedSeriesIDs: [String] = [],
        removedProductIDs: [String] = []
    ) -> ShopCatalog {
        ShopCatalog(
            shops: shops, series: series, products: products, saleEvents: saleEvents,
            removedShopIDs: removedShopIDs,
            removedSeriesIDs: removedSeriesIDs,
            removedProductIDs: removedProductIDs)
    }

    /// 本地：1 店家 / 1 系列 / 2 商品（其中 prd-old 线上没有）/ 2 条销售记录
    private func localFixture() -> ShopCatalog {
        catalog(
            shops: [shop("shop-a", name: "小魔女")],
            series: [series("ser-1", shop: "shop-a", "2026 春")],
            products: [
                product("prd-keep", shop: "shop-a", series: "ser-1", "月光 JSK"),
                product("prd-old", shop: "shop-a", series: "ser-1", "旧款 JSK"),
            ],
            saleEvents: [
                event("evt-1", product: "prd-keep"),
                event("evt-old", product: "prd-old"),
            ])
    }

    /// 线上：同店家、同系列；prd-keep 换了名字（内容变了）、少了 prd-old、多了一条 prd-new
    private func remoteFixture() -> ShopCatalog {
        catalog(
            shops: [shop("shop-a", name: "小魔女")],
            series: [series("ser-1", shop: "shop-a", "2026 春")],
            products: [
                product("prd-keep", shop: "shop-a", series: "ser-1", "月光 JSK（改）"),
                product("prd-new", shop: "shop-a", series: "ser-1", "新芽 JSK"),
            ],
            saleEvents: [event("evt-1", product: "prd-keep")])
    }

    // MARK: - 三种基本情形

    /// 线上有、本地没有 → 加进来（这就是「增量」那一半）。
    func testAddedEntitiesComeFromRemote() {
        let (result, outcome) = ShopCatalogReconcile.align(
            local: localFixture(), remote: remoteFixture())

        XCTAssertEqual(outcome.added.map(\.entityID), ["prd-new"])
        XCTAssertEqual(outcome.added.first?.name, "新芽 JSK")
        XCTAssertTrue(result.products.contains { $0.id == "prd-new" })
    }

    /// 同一个 id 两边都有但内容不同 → 用**线上那份**覆盖（不是保留本地）。
    func testSameIDDifferentContentIsOverwrittenByRemote() {
        let (result, outcome) = ShopCatalogReconcile.align(
            local: localFixture(), remote: remoteFixture())

        XCTAssertEqual(outcome.overwritten.map(\.entityID), ["prd-keep"])
        XCTAssertEqual(outcome.overwritten.first?.name, "月光 JSK（改）",
                       "覆盖项的名字要取线上那份，否则运营看到的是旧名字")
        XCTAssertEqual(result.products.first { $0.id == "prd-keep" }?.name, "月光 JSK（改）")
    }

    /// 本地有、线上没有 → 从本地移除（这就是「被替换掉」的那一半）。
    func testLocalOnlyEntityIsRemoved() {
        let (result, outcome) = ShopCatalogReconcile.align(
            local: localFixture(), remote: remoteFixture())

        XCTAssertEqual(outcome.removed.map(\.entityID), ["prd-old"])
        XCTAssertEqual(outcome.removed.first?.name, "旧款 JSK",
                       "移除项的名字要取本地那份，否则运营不知道删掉的是什么")
        XCTAssertFalse(result.products.contains { $0.id == "prd-old" })
    }

    // MARK: - 两条例外

    /// ⭐ 销售历史只增不删：本地独有的那条**必须留着**，且不能出现在「移除」里。
    func testLocalOnlySaleEventsSurviveAndAreReported() {
        let (result, outcome) = ShopCatalogReconcile.align(
            local: localFixture(), remote: remoteFixture())

        XCTAssertEqual(outcome.keptLocalSaleEvents.map(\.entityID), ["evt-old"])
        XCTAssertFalse(outcome.removed.contains { $0.kind == .saleEvent },
                       "销售事件永远不允许出现在「移除」里：\(outcome.removed)")
        XCTAssertTrue(result.saleEvents.contains { $0.id == "evt-old" })
        XCTAssertTrue(result.saleEvents.contains { $0.id == "evt-1" })
    }

    /// ⭐ 本地独有的下架墓碑保留（并集）：否则线上还带着的条目会在本机复活。
    func testLocalOnlyTombstonesAreKeptAndReported() {
        let local = catalog(shops: [shop("shop-a", name: "A")], removedProductIDs: ["prd-gone"])
        let remote = catalog(shops: [shop("shop-a", name: "A")], removedProductIDs: ["prd-other"])

        let (result, outcome) = ShopCatalogReconcile.align(local: local, remote: remote)

        XCTAssertEqual(result.removedProductIDs, ["prd-other", "prd-gone"])
        XCTAssertEqual(outcome.keptLocalTombstones.map(\.entityID), ["prd-gone"])
    }

    /// 线上声明的下架不能被本地覆盖掉（本地没有它时必须补上）。
    func testRemoteTombstonesAreAlwaysPresentAfterAligning() {
        let local = catalog(shops: [shop("shop-a", name: "A")])
        let remote = catalog(shops: [shop("shop-a", name: "A")], removedProductIDs: ["prd-x"])

        let (result, _) = ShopCatalogReconcile.align(local: local, remote: remote)
        XCTAssertEqual(result.removedProductIDs, ["prd-x"])
    }

    // MARK: - 结果自证

    /// ⭐ 对完账必须**真的等于线上那一版**（`isAligned` 自证，不靠人眼）。
    func testAlignedResultPassesItsOwnVerification() {
        let remote = remoteFixture()
        let (result, _) = ShopCatalogReconcile.align(local: localFixture(), remote: remote)

        XCTAssertTrue(ShopCatalogReconcile.isAligned(result, with: remote))
    }

    /// 未对账的本地目录必须**判不过**（否则自证等于没写）。
    func testUnreconciledCatalogFailsVerification() {
        XCTAssertFalse(ShopCatalogReconcile.isAligned(localFixture(), with: remoteFixture()))
    }

    /// 幂等：对完账再对一次，除「保留项」外不应再有任何改动，结果逐字节相同。
    func testAligningTwiceChangesNothingFurther() {
        let remote = remoteFixture()
        let (once, _) = ShopCatalogReconcile.align(local: localFixture(), remote: remote)
        let (twice, secondOutcome) = ShopCatalogReconcile.align(local: once, remote: remote)

        XCTAssertEqual(once, twice)
        XCTAssertTrue(secondOutcome.added.isEmpty)
        XCTAssertTrue(secondOutcome.overwritten.isEmpty)
        XCTAssertTrue(secondOutcome.removed.isEmpty)
        XCTAssertEqual(secondOutcome.keptLocalSaleEvents.map(\.entityID), ["evt-old"])
    }

    /// 空线上 = 本地实体层清空（但本地独有的销售历史仍保留）。
    func testEmptyRemoteClearsLocalEntitiesButKeepsSaleHistory() {
        let (result, outcome) = ShopCatalogReconcile.align(
            local: localFixture(), remote: ShopCatalog())

        XCTAssertTrue(result.shops.isEmpty)
        XCTAssertTrue(result.series.isEmpty)
        XCTAssertTrue(result.products.isEmpty)
        XCTAssertEqual(result.saleEvents.map(\.id), ["evt-1", "evt-old"])
        XCTAssertEqual(outcome.removed.count, 4)   // 1 店家 + 1 系列 + 2 商品
        XCTAssertEqual(outcome.keptLocalSaleEvents.count, 2)
    }

    /// 内容完全一致时报告必须说「不需要改动」，且不产生任何 removed。
    func testIdenticalCatalogsProduceEmptyOutcome() {
        let local = localFixture()
        let (result, outcome) = ShopCatalogReconcile.align(local: local, remote: local)

        XCTAssertEqual(result, local)
        XCTAssertFalse(outcome.touchesExistingContent)
        XCTAssertTrue(outcome.summaryLines.contains { $0.contains("不需要改动") },
                      "\(outcome.summaryLines)")
    }

    /// 顺序也照线上（远端是权威）——顺序会影响展示派生，不能各留一份。
    func testEntityOrderFollowsRemote() {
        let local = catalog(products: [
            product("prd-b", shop: "s", series: "se", "B"),
            product("prd-a", shop: "s", series: "se", "A"),
        ])
        let remote = catalog(products: [
            product("prd-a", shop: "s", series: "se", "A"),
            product("prd-b", shop: "s", series: "se", "B"),
        ])
        let (result, _) = ShopCatalogReconcile.align(local: local, remote: remote)
        XCTAssertEqual(result.products.map(\.id), ["prd-a", "prd-b"])
    }

    // MARK: - 报告文案

    /// 要先说「会不会删」，再报数量 —— 顺序反了运营只会看到「新增 3」。
    func testSummaryLinesLeadWithRemoval() {
        let (_, outcome) = ShopCatalogReconcile.align(
            local: localFixture(), remote: remoteFixture())
        XCTAssertTrue(outcome.summaryLines.first?.contains("移除") ?? false,
                      "\(outcome.summaryLines)")
        XCTAssertTrue(outcome.summaryLines.contains { $0.contains("销售记录") },
                      "保留项必须显式说出来：\(outcome.summaryLines)")
    }

    func testSummaryTextCountsEachCategory() {
        let (_, outcome) = ShopCatalogReconcile.align(
            local: localFixture(), remote: remoteFixture())
        XCTAssertTrue(outcome.summaryText.contains("新增 1"), outcome.summaryText)
        XCTAssertTrue(outcome.summaryText.contains("覆盖 1"), outcome.summaryText)
        XCTAssertTrue(outcome.summaryText.contains("移除 1"), outcome.summaryText)
        XCTAssertTrue(outcome.summaryText.contains("保留"), outcome.summaryText)
    }

    /// 明细超限时给「还有 N 条」，且**绝不静默截断**。
    func testDetailLinesTruncateVisibly() {
        var products: [CatalogProduct] = []
        for index in 0..<8 {
            products.append(product("prd-\(index)", shop: "s", series: "se", "P\(index)"))
        }
        let local = catalog(products: products)
        let remote = catalog(products: [])

        let (_, outcome) = ShopCatalogReconcile.align(local: local, remote: remote)
        let lines = outcome.detailLines(limit: 3)
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines.last?.contains("还有 5 条") ?? false, "\(lines)")
    }

    // MARK: - 分层结构（iOS）的覆盖层收敛

    /// 覆盖层只留「本地必须保留的部分」：实体一个都不留（交给远端层提供）。
    func testLocalOnlyRemainderKeepsOnlyExceptions() {
        let remainder = ShopCatalogReconcile.localOnlyRemainder(
            local: localFixture(), remote: remoteFixture())

        XCTAssertTrue(remainder.shops.isEmpty)
        XCTAssertTrue(remainder.series.isEmpty)
        XCTAssertTrue(remainder.products.isEmpty)
        XCTAssertTrue(remainder.assets.isEmpty)
        XCTAssertEqual(remainder.saleEvents.map(\.id), ["evt-old"],
                       "与线上重叠的销售事件不该留在覆盖层（远端层已经提供）")
    }

    /// 本地独有的墓碑留在覆盖层；与线上重叠的交给远端层（留两份只会让「谁说了算」含糊）。
    func testLocalOnlyRemainderKeepsOnlyLocalTombstones() {
        let local = catalog(shops: [shop("s", name: "S")],
                            removedProductIDs: ["prd-a", "prd-b"])
        let remote = catalog(shops: [shop("s", name: "S")], removedProductIDs: ["prd-a"])
        let remainder = ShopCatalogReconcile.localOnlyRemainder(local: local, remote: remote)
        XCTAssertEqual(remainder.removedProductIDs, ["prd-b"])
    }

    /// ⭐ 收敛之后「远端层 + 覆盖层」合并出来的生效目录**仍然等于线上那一版**。
    /// 这一条是 iOS 侧「与线上对齐」的落点判据：不成立就等于没对齐。
    func testMergedRemotePlusRemainderStillEqualsRemote() {
        let remote = remoteFixture()
        let local = localFixture()
        let remainder = ShopCatalogReconcile.localOnlyRemainder(local: local, remote: remote)

        // 三层合并（base 为空）等价于：远端层为基底 + 覆盖层补销售事件与墓碑
        var effective = remote
        effective.saleEvents.append(contentsOf: remainder.saleEvents)
        effective.removedShopIDs.append(contentsOf: remainder.removedShopIDs)
        effective.removedSeriesIDs.append(contentsOf: remainder.removedSeriesIDs)
        effective.removedProductIDs.append(contentsOf: remainder.removedProductIDs)

        XCTAssertTrue(ShopCatalogReconcile.isAligned(effective, with: remote))
    }
}
