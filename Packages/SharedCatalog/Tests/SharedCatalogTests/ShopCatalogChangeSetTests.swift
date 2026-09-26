//
//  ShopCatalogChangeSetTests.swift
//  SharedCatalogTests
//
//  变更集与本地变更追踪（方案 §4.3 / R07 / R08 的作用域 / T14）。
//
//  ## 这份测试要防的是什么
//
//  1. **「没有基线」被显示成「没有改动」**。两者含义完全相反：前者是无法比较，
//     后者是「这份包等于线上」。混为一谈会让运营放心地覆盖别人。
//  2. **顺序不稳定**。仓库红线：数组是**录入顺序**，绝不是字典遍历序
//     （`Array(Set(...))` 会随进程哈希种子每次冷启动换排法）。差分结果会被
//     直接写进界面与日志，必须稳定。
//  3. **墓碑被当成「漏传」**。`removedProductIDs` 表达的是「下架」，
//     丢一次就等于线上永远不下架。
//

import XCTest

@testable import SharedCatalog

final class ShopCatalogChangeSetTests: XCTestCase {

    // MARK: 没有基线

    func testMissingBaselineIsNotReportedAsNoChange() {
        let current = makeCatalog(productNames: ["A", "B"])
        let changes = ShopCatalogChangeSetCalculator.diff(baseline: nil, current: current)

        XCTAssertFalse(changes.hasBaseline)
        XCTAssertEqual(changes.totalChanged, 0)
        XCTAssertTrue(
            changes.summaryLines.contains { $0.contains("无法说明") },
            "没有基线时必须明说「无法比较」，实际：\(changes.summaryLines)")
    }

    // MARK: 新增 / 修改 / 删除

    func testDetectsAddedModifiedAndRemovedProducts() {
        let baseline = makeCatalog(products: [
            ("p-1", "星月夜 JSK 蓝", "JSK"),
            ("p-2", "星月夜 JSK 粉", "JSK"),
            ("p-3", "旧款 OP", "OP"),
        ])
        let current = makeCatalog(products: [
            ("p-1", "星月夜 JSK 蓝", "JSK"),          // 未改
            ("p-2", "星月夜 JSK 粉色", "JSK"),        // 改了名字
            ("p-4", "新增 KC", "KC"),                 // 新增
        ])

        let delta = ShopCatalogChangeSetCalculator.delta(.product, baseline: baseline, current: current)
        XCTAssertEqual(delta.addedIDs, ["p-4"])
        XCTAssertEqual(delta.modifiedIDs, ["p-2"])
        XCTAssertEqual(delta.removedIDs, ["p-3"], "基线里有、当前没有 = 真删除")
        XCTAssertEqual(delta.changedCount, 3)
    }

    func testDeletedDeltaIsDistinctFromTombstone() {
        let baseline = makeCatalog(products: [("p-1", "A", "JSK"), ("p-2", "B", "JSK")])
        var current = makeCatalog(products: [("p-1", "A", "JSK")])
        // 运营点了「删除商品」：实体移除 + 墓碑
        current.removedProductIDs = ["p-2"]

        let delta = ShopCatalogChangeSetCalculator.delta(.product, baseline: baseline, current: current)
        XCTAssertEqual(delta.removedIDs, ["p-2"])
        XCTAssertEqual(delta.tombstoneIDs, ["p-2"], "墓碑必须单独列出，它表达「下架」而不是「漏传」")
        XCTAssertTrue(delta.summaryLine.contains("下架"), "摘要要说「下架」：\(delta.summaryLine)")
    }

    func testUnchangedCatalogProducesEmptyDelta() {
        let catalog = makeCatalog(products: [("p-1", "A", "JSK")])
        let changes = ShopCatalogChangeSetCalculator.diff(baseline: catalog, current: catalog)
        XCTAssertTrue(changes.hasBaseline)
        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(changes.totalChanged, 0)
        XCTAssertTrue(changes.summaryLines.contains { $0.contains("没有差异") })
    }

    // MARK: 顺序稳定（仓库红线）

    func testDeltaKeepsEntryOrderNotDictionaryOrder() {
        let baseline = makeCatalog(products: [])
        let current = makeCatalog(products: [
            ("p-z", "Z 款", "JSK"),
            ("p-a", "A 款", "JSK"),
            ("p-m", "M 款", "JSK"),
        ])

        let delta = ShopCatalogChangeSetCalculator.delta(.product, baseline: baseline, current: current)
        XCTAssertEqual(delta.addedIDs, ["p-z", "p-a", "p-m"], "必须是录入顺序，不能是字典/集合遍历序")
    }

    func testDuplicateIDsDoNotCrashAndAreDeduplicated() {
        // 坏数据里可能出现重复 id；差分不能因此崩，也不能重复列两遍
        let baseline = makeCatalog(products: [])
        var current = makeCatalog(products: [("p-1", "A", "JSK")])
        current.products.append(current.products[0])

        let delta = ShopCatalogChangeSetCalculator.delta(.product, baseline: baseline, current: current)
        XCTAssertEqual(delta.addedIDs, ["p-1"])
    }

    // MARK: 本地变更追踪

    func testTouchedIDsMergeAndDeduplicate() {
        var touched = ShopCatalogTouchedIDs()
        touched.insert("p-1", into: .product)
        touched.insert("p-1", into: .product)
        touched.insert(["p-2", "p-3"], into: .product)
        touched.insert("img-1", into: .asset)

        XCTAssertEqual(touched.productIDs, ["p-1", "p-2", "p-3"])
        XCTAssertEqual(touched.assetIDs, ["img-1"])
        XCTAssertFalse(touched.isEmpty)

        var other = ShopCatalogTouchedIDs()
        other.insert("p-3", into: .product)
        other.insert("s-9", into: .series)
        let union = touched.union(other)
        XCTAssertEqual(union.productIDs, ["p-1", "p-2", "p-3"], "并集不得产生重复")
        XCTAssertEqual(union.seriesIDs, ["s-9"])
    }

    func testTouchedIDsRoundTripThroughJSON() {
        var touched = ShopCatalogTouchedIDs()
        touched.insert("p-1", into: .product)
        touched.insert("img-9", into: .asset)
        touched.insert("v-2", into: .variant)

        let data = touched.encoded()
        XCTAssertNotNil(data, "编码失败必须能看出来（返回 nil），不能悄悄变成空集")
        XCTAssertEqual(ShopCatalogTouchedIDs.decoded(from: data), touched)
    }

    func testDecodingGarbageYieldsEmptyNotCrash() {
        let decoded = ShopCatalogTouchedIDs.decoded(from: Data("{ 这不是 JSON".utf8))
        XCTAssertTrue(decoded.isEmpty)
    }

    // MARK: 严格策略的作用域

    func testStrictScopeUnionsBaselineDiffAndLocalTouch() {
        let baseline = makeCatalog(products: [("p-1", "A", "JSK"), ("p-2", "B", "JSK")])
        let current = makeCatalog(products: [("p-1", "A 改了", "JSK"), ("p-2", "B", "JSK")])
        var touched = ShopCatalogTouchedIDs()
        touched.insert("img-7", into: .asset)
        touched.insert("p-2", into: .product)

        let changes = ShopCatalogChangeSetCalculator.diff(
            baseline: baseline, current: current, touched: touched)

        let scope = changes.strictScopeIDs
        XCTAssertTrue(scope.contains("p-1"), "与基线比出来的修改项要进作用域")
        XCTAssertTrue(scope.contains("p-2"), "本地动过的项也要进作用域")
        XCTAssertTrue(scope.contains("img-7"))
        XCTAssertTrue(changes.changedProductIDs.contains("p-2"))
    }

    // MARK: 夹具

    private func makeCatalog(products: [(String, String, String)]) -> ShopCatalog {
        var catalog = ShopCatalog()
        catalog.shops = [CatalogShop(id: "shop-1", name: "樱花小羊")]
        catalog.series = [CatalogSeries(id: "series-1", shopID: "shop-1", name: "星月夜")]
        catalog.products = products.map {
            CatalogProduct(
                id: $0.0, shopID: "shop-1", seriesID: "series-1", name: $0.1, category: $0.2)
        }
        return catalog
    }

    private func makeCatalog(productNames: [String]) -> ShopCatalog {
        makeCatalog(products: productNames.enumerated().map { ("p-\($0.offset)", $0.element, "JSK") })
    }
}
