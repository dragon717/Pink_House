// 线上拉取产物的解析、空态与数量展示回归。

import XCTest
@testable import PinkHouseOpsCore
import SharedCatalog

final class OpsPulledCatalogTests: XCTestCase {

    // MARK: - 夹具

    private func makeCatalog(
        releaseSeq: Int = 6,
        rootIndexHash: String? = String(repeating: "a", count: 64),
        payloadHash: String? = String(repeating: "b", count: 64),
        counts: [String: Int] = ["shops": 2, "series": 9, "products": 263],
        environment: String = "development",
        path: String = "/tmp/pull/shop-catalog.json"
    ) -> OpsPulledCatalog {
        OpsPulledCatalog(
            path: path,
            environment: environment,
            releaseSeq: releaseSeq,
            rootIndexHash: rootIndexHash,
            payloadHash: payloadHash,
            itemCounts: counts,
            pulledAt: Date(timeIntervalSince1970: 1_772_000_000))
    }

    private func makeResult(
        catalogPath: String? = "/tmp/pull/shop-catalog.json",
        itemCounts: [String: Int]? = ["products": 3],
        payloadHash: String? = "deadbeef",
        head: ShopCatalogOnlineHead? = ShopCatalogOnlineHead(
            environment: "development", releaseSeq: 6,
            rootIndexHash: String(repeating: "a", count: 64))
    ) -> OpsBridgeRunResult {
        var result = OpsBridgeRunResult(
            exitCode: 0,
            events: [],
            nonJSONLines: [],
            executablePath: "/usr/bin/true",
            scriptPath: "/tmp/ops_publish_bridge.py")
        result.onlineHead = head
        result.pulledCatalogPath = catalogPath
        result.pulledCatalogItemCounts = itemCounts
        result.pulledCatalogPayloadHash = payloadHash
        return result
    }

    // MARK: - 模式本身

    /// rawValue 是**带连字符**的：写错的话桥接器的 `--mode` 会被 argparse 直接拒，
    /// 但错误只表现为一句 usage，看不出是我们这边拼错。
    func testPullCatalogRawValueMatchesBridgeCLI() {
        XCTAssertEqual(OpsBridgeMode.pullCatalog.rawValue, "pull-catalog")
    }

    /// ⭐ 只有 `publish` 会写远端。这条锁住的是「界面文案读哪个属性」——
    /// 一旦有人把 `writesRemote` 改成恒真，只读操作会被自己吓成会覆盖线上。
    func testOnlyPublishWritesRemote() {
        XCTAssertTrue(OpsBridgeMode.publish.writesRemote)
        XCTAssertFalse(OpsBridgeMode.baseline.writesRemote)
        XCTAssertFalse(OpsBridgeMode.query.writesRemote)
        XCTAssertFalse(OpsBridgeMode.pullCatalog.writesRemote)
    }

    /// 四种模式的显示名必须互不相同（界面上按钮文案重复 = 点错入口）。
    func testModeDisplayNamesAreDistinct() {
        let names = [OpsBridgeMode.baseline, .publish, .query, .pullCatalog].map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count, "显示名重复：\(names)")
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
    }

    // MARK: - 从运行结果取产物

    func testFromResultCarriesHeadCountsAndPayload() {
        let pulled = OpsPulledCatalog.from(
            result: makeResult(), environment: "development")
        XCTAssertNotNil(pulled)
        XCTAssertEqual(pulled?.path, "/tmp/pull/shop-catalog.json")
        XCTAssertEqual(pulled?.environment, "development")
        XCTAssertEqual(pulled?.releaseSeq, 6)
        XCTAssertEqual(pulled?.rootIndexHash, String(repeating: "a", count: 64))
        XCTAssertEqual(pulled?.payloadHash, "deadbeef")
        XCTAssertEqual(pulled?.itemCounts["products"], 3)
    }

    /// ⭐ 没有 `catalog` 事件时必须返回 nil —— **绝不去猜输出目录下的文件名**。
    /// 猜的话，「线上是空的」会被当成「拉回了一份空目录」，运营据此会把
    /// 自己的本地内容当成线上基线（正好是反的）。
    func testFromResultWithoutCatalogEventIsNil() {
        XCTAssertNil(OpsPulledCatalog.from(
            result: makeResult(catalogPath: nil), environment: "development"))
    }

    func testFromResultIgnoresEmptyPath() {
        XCTAssertNil(OpsPulledCatalog.from(
            result: makeResult(catalogPath: ""), environment: "development"))
    }

    /// 线上没有发布头时 `head_payload` 只给 `releaseSeq: 0`：
    /// 产物要如实反映「发布号 0、摘要没读到」，而不是编一个号。
    func testFromResultWithOnlySequenceStillWorks() {
        let head = ShopCatalogOnlineHead(environment: "development", releaseSeq: 0)
        let pulled = OpsPulledCatalog.from(
            result: makeResult(head: head), environment: "development")
        XCTAssertEqual(pulled?.releaseSeq, 0)
        XCTAssertNil(pulled?.rootIndexHash)
    }

    // MARK: - 条数

    /// 撤回清单（`removedXxxIDs`）是「删掉了什么」，**不是「有什么」** ——
    /// 混进总数会让运营以为拉回来的东西更多。
    func testEntityCountExcludesTombstones() {
        let pulled = makeCatalog(counts: [
            "shops": 2, "products": 263,
            "removedProductIDs": 7, "removedShopIDs": 1,
        ])
        XCTAssertEqual(pulled.entityCount, 265)
    }

    /// 顺序固定（写死的展示顺序），空条目不出现。
    func testSortedItemCountsIsOrderedAndSkipsZero() {
        let pulled = makeCatalog(counts: [
            "products": 3, "shops": 1,
            "series": 0, "variants": 4,
            "removedShopIDs": 2,
        ])
        let rows = pulled.sortedItemCounts
        XCTAssertEqual(rows.map(\.field), ["shops", "products", "variants", "removedShopIDs"])
        XCTAssertEqual(rows.map(\.label), ["店家", "商品", "规格", "撤回店家"])
        XCTAssertEqual(rows.map(\.count), [1, 3, 4, 2])
    }

    /// `id` 必须是字段名 —— 它同时是视图 `ForEach` 的键。
    func testItemCountIdentityIsFieldName() {
        let rows = makeCatalog().sortedItemCounts
        XCTAssertEqual(rows.map(\.id), rows.map(\.field))
    }

    func testCountsTextSkipsTombstonesAndIsEmptyForEmptyCatalog() {
        XCTAssertEqual(
            makeCatalog(counts: ["shops": 2, "series": 9, "products": 263,
                                 "removedProductIDs": 7]).countsText,
            "店家 2 / 系列 9 / 商品 263")
        XCTAssertEqual(makeCatalog(counts: [:]).countsText, "（空目录）")
    }

    func testHashTextNeverClaimsHashWhenMissing() {
        XCTAssertEqual(makeCatalog(rootIndexHash: nil).hashText, "摘要未读到")
        XCTAssertEqual(makeCatalog(rootIndexHash: "").hashText, "摘要未读到")
        XCTAssertEqual(makeCatalog(rootIndexHash: String(repeating: "a", count: 64)).hashText,
                       "aaaaaaaaaaaa…")
    }

    func testLabelFallsBackToFieldNameForUnknownField() {
        XCTAssertEqual(OpsPulledCatalog.label(for: "products"), "商品")
        XCTAssertEqual(OpsPulledCatalog.label(for: "somethingNew"), "somethingNew")
    }

    /// 展示表必须覆盖载荷的全部字段口径（漏一个 = 界面上那一类数字永远不显示）。
    func testOrderedFieldsCoverEveryPayloadField() {
        let covered = Set(OpsPulledCatalog.orderedFields.map(\.field))
        XCTAssertEqual(covered, Set(OpsPulledCatalog.entityFields + OpsPulledCatalog.tombstoneFields))
        XCTAssertEqual(OpsPulledCatalog.orderedFields.count,
                       OpsPulledCatalog.entityFields.count + OpsPulledCatalog.tombstoneFields.count)
    }
}
