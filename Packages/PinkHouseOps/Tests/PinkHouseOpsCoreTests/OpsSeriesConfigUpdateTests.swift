import XCTest
import SharedCatalog
@testable import PinkHouseOpsCore

final class OpsSeriesConfigUpdateTests: XCTestCase {
    func testExistingProductOrderUpdatesOnlyRankWithoutPublishingLocalContent() throws {
        var remote = catalog(cover: "remote-cover")
        remote.products[0].priceCorrection = .init(stockPrice: 100)
        var localSeries = remote.series[0]
        localSeries.name = "本机未发布的系列名称"
        localSeries.cover = "unpublished-cover"
        let update = OpsSeriesConfigUpdate(series: localSeries, shop: shop, fields: [.productOrder],
            productOrders: ["product": 3, "unpublished-product": 0])
        for _ in ["development", "production"] {
            let result = try OpsSeriesConfigUpdate.applying([update], to: remote)
            XCTAssertEqual(result.products[0].displayOrder, 3)
            XCTAssertEqual(result.products[0].priceCorrection, remote.products[0].priceCorrection)
            XCTAssertEqual(result.products[0].images, remote.products[0].images)
            XCTAssertEqual(result.products.count, 1)
            XCTAssertEqual(result.series, remote.series)
        }
    }

    func testOrderDoesNotCreateOrRestoreSeriesAndRejectsForeignProduct() throws {
        let source = catalog(cover: "cover").series[0]
        let update = OpsSeriesConfigUpdate(series: source, shop: shop, fields: [.productOrder], productOrders: ["product": 0])
        let empty = ShopCatalog(shops: [shop])
        XCTAssertEqual(try OpsSeriesConfigUpdate.applying([update], to: empty), empty)
        let removed = ShopCatalog(shops: [shop], removedSeriesIDs: [source.id])
        XCTAssertEqual(try OpsSeriesConfigUpdate.applying([update], to: removed), removed)
        var foreign = catalog(cover: "cover")
        foreign.series.append(.init(id: "other", shopID: shop.id, name: "另一系列"))
        foreign.products[0].seriesID = "other"
        XCTAssertThrowsError(try OpsSeriesConfigUpdate.applying([update], to: foreign))
    }

    func testOrderVerificationCannotTreatMissingPublishedProductAsSuccess() throws {
        let source = catalog(cover: "cover")
        let update = OpsSeriesConfigUpdate(series: source.series[0], shop: shop, fields: [.productOrder],
            productOrders: ["product": 0], publishedOrderCatalog: source)
        var remote = source; remote.products = []
        XCTAssertThrowsError(try OpsSeriesConfigUpdate.verifyProductOrders([update], in: remote))
        XCTAssertThrowsError(try OpsSeriesConfigUpdate.verifyProductOrders([update], in: source), "旧顺序也不能确认")
        remote = try OpsSeriesConfigUpdate.applying([update], to: source)
        XCTAssertNoThrow(try OpsSeriesConfigUpdate.verifyProductOrders([update], in: remote))
        var legacy = update; legacy.publishedOrderCatalog = nil
        remote.products = []
        XCTAssertThrowsError(try OpsSeriesConfigUpdate.verifyProductOrders([legacy], in: remote), "旧任务也不能静默跳过缺商品")
    }

    func testOrderSeedOnlyRestoresAlreadyPublishedProductAndPreservesExistingTargetPrice() throws {
        var source = catalog(cover: "source-cover")
        source.products[0].priceCorrection = .init(stockPrice: 100)
        source.products.append(.init(id: "second", shopID: shop.id, seriesID: source.series[0].id,
            name: "另一件已发布商品", category: "OP"))
        source.variants = [.init(id: "v-second", productID: "second", color: "蓝色")]
        source.saleEvents = [.init(id: "sale-second", productID: "second", type: .stock, price: 200, currency: .cny)]
        let update = OpsSeriesConfigUpdate(series: source.series[0], shop: shop, fields: [.productOrder],
            productOrders: ["second": 0, "product": 1, "local-unpublished": 2], publishedOrderCatalog: source)
        var target = catalog(cover: "target-cover")
        target.products[0].priceCorrection = .init(stockPrice: 300)
        let ranked = try OpsSeriesConfigUpdate.applying([update], to: target)
        let seed = try XCTUnwrap(update.productOrderDependencySeed())
        let dependency = try XCTUnwrap(OpsCatalogEditorUpdate.missingProductDependencies([seed], in: ranked))
        var result = try OpsCatalogEditorUpdate.applying([dependency], to: ranked)
        XCTAssertEqual(result.products.count, 2)
        XCTAssertEqual(result.products.first { $0.id == "product" }?.priceCorrection?.stockPrice, 300)
        XCTAssertEqual(result.series[0].cover, "target-cover")
        XCTAssertEqual(CatalogProductOrdering.ordered(result.products).map(\.id), ["second", "product"])
        XCTAssertEqual(result.saleEvents, source.saleEvents)
        XCTAssertEqual(result.variants, source.variants)
        XCTAssertThrowsError(try OpsSeriesConfigUpdate.verifyProductOrders([update], in: result),
                            "关联补齐追加的商品也必须在发布前落实数组顺序")
        result.products = CatalogProductOrdering.publicationOrder(result.products)
        XCTAssertNoThrow(try OpsSeriesConfigUpdate.verifyProductOrders([update], in: result))
        target.removedProductIDs = ["second"]
        XCTAssertThrowsError(try OpsCatalogEditorUpdate.missingProductDependencies([seed], in: target))
    }

    func testPublishedOrderSnapshotSurvivesScheduleCoalescingAndEncoding() throws {
        let source = catalog(cover: "cover")
        let order = OpsSeriesConfigUpdate(series: source.series[0], shop: shop, fields: [.productOrder],
            productOrders: ["product": 0], publishedOrderCatalog: source)
        let combined = OpsSeriesConfigUpdate.coalescing([order], with: .init(series: source.series[0], shop: nil, fields: [.schedule]))
        let restored = try JSONDecoder().decode([OpsSeriesConfigUpdate].self, from: JSONEncoder().encode(combined))
        XCTAssertEqual(restored[0].publishedOrderCatalog, source)
        XCTAssertEqual(restored[0].productOrders, ["product": 0])
    }

    func testReadbackWithCorrectRanksButOldPhysicalArrayCannotConfirmOrder() throws {
        var remote = catalog(cover: "cover")
        remote.products[0].displayOrder = 1
        var first = remote.products[0]; first.id = "first"; first.name = "先显示的组合款"; first.displayOrder = 0
        remote.products.append(first)
        let update = OpsSeriesConfigUpdate(series: remote.series[0], shop: shop, fields: [.productOrder],
            productOrders: ["first": 0, "product": 1], publishedOrderCatalog: remote)
        XCTAssertThrowsError(try OpsSeriesConfigUpdate.verifyProductOrders([update], in: remote))
        let fixed = try OpsSeriesConfigUpdate.applying([update], to: remote)
        XCTAssertEqual(fixed.products.map(\.id), ["first", "product"])
        XCTAssertEqual(Set(fixed.products), Set(remote.products))
        XCTAssertNoThrow(try OpsSeriesConfigUpdate.verifyProductOrders([update], in: fixed))
        XCTAssertEqual(try OpsSeriesConfigUpdate.applying([update], to: fixed), fixed)
    }

    func testSortAndScheduleSavesCoalesceWithoutLosingSortAndSurviveDecoding() throws {
        let source = catalog(cover: "cover").series[0]
        let order = OpsSeriesConfigUpdate(series: source, shop: shop, fields: [.productOrder], productOrders: ["product": 1])
        var updates = OpsSeriesConfigUpdate.coalescing([order], with: .init(series: source, shop: shop, fields: [.schedule]))
        XCTAssertEqual(updates[0].productOrders, ["product": 1])
        updates = OpsSeriesConfigUpdate.coalescing(updates, with: .init(series: source, shop: shop, fields: [.productOrder], productOrders: ["product": 0]))
        let restored = try JSONDecoder().decode([OpsSeriesConfigUpdate].self, from: JSONEncoder().encode(updates))
        XCTAssertEqual(restored[0].fields, [.schedule, .productOrder])
        XCTAssertEqual(restored[0].productOrders, ["product": 0])
    }

    func testConfirmedSortUpdatesOnlyItsBaselineFieldAndNextLocalSortDoesNotConflict() throws {
        var remote = catalog(cover: "cover")
        remote.products[0].description = "原描述"
        let update = OpsSeriesConfigUpdate(series: remote.series[0], shop: shop,
            fields: [.productOrder], productOrders: ["product": 1])
        let head = ShopCatalogBaseline(releaseSeq: 18, environment: "production")
        let ancestor = try OpsCatalogMergeBaseline(head: head, catalog: remote).acknowledging([update], head: head)
        var online = try OpsSeriesConfigUpdate.applying([update], to: remote)
        online.products[0].description = "另一端稍后修改描述"
        var local = remote
        local.products[0].displayOrder = 0
        let result = try ShopCatalogThreeWayMerge.merge(local: local, remote: online, baseline: ancestor.catalog)
        XCTAssertEqual(result.conflicts, [])
        XCTAssertEqual(result.catalog.products[0].displayOrder, 0)
        XCTAssertEqual(result.catalog.products[0].description, "另一端稍后修改描述")
    }

    func testFrozenPublishRetryRequiresSuccessfulQueryAndExactOriginalBaseline() {
        let request = ShopCatalogPublishRequest(requestID: "frozen", jobID: "saved", draftID: "draft",
            draftRevision: 8, baseReleaseSeq: 23, baseRootIndexHash: "original-hash",
            targetEnvironment: .development, releaseSeq: 24, inputDirectory: "/unused/input",
            archivePath: "/unused/archive", outputDirectory: "/unused/output",
            receiptPath: "/unused/receipt", payloadHash: "frozen-payload")
        let original = ShopCatalogOnlineHead(environment: "development", releaseSeq: 23, rootIndexHash: "original-hash")
        func allowed(_ code: Int32?, _ outcome: ShopCatalogPublishOutcome?, _ head: ShopCatalogOnlineHead?) -> Bool {
            OpsSeriesConfigUpdate.canRetryFrozenPublish(queryExitCode: code, outcome: outcome, head: head, request: request)
        }
        XCTAssertTrue(allowed(0, .failed, original))
        XCTAssertFalse(allowed(nil, .failed, original))
        XCTAssertFalse(allowed(7, .failed, original))
        XCTAssertFalse(allowed(0, .pendingConfirmation, original))
        XCTAssertFalse(allowed(0, .failed, nil))
        XCTAssertFalse(allowed(0, .failed, .init(environment: "production", releaseSeq: 23, rootIndexHash: "original-hash")))
        XCTAssertFalse(allowed(0, .failed, .init(environment: "development", releaseSeq: 23)))
        XCTAssertFalse(allowed(0, .failed, .init(environment: "development", releaseSeq: 23, rootIndexHash: "changed-hash")))
        XCTAssertFalse(allowed(0, .confirmed, .init(environment: "development", releaseSeq: 24, rootIndexHash: "new-hash")))
        XCTAssertFalse(allowed(0, .replaced, .init(environment: "development", releaseSeq: 25, rootIndexHash: "newer-hash")))
    }

    private let shop = CatalogShop(id: "shop", name: "店家")
    private func catalog(cover: String) -> ShopCatalog {
        ShopCatalog(shops: [shop], series: [.init(id: "series", shopID: shop.id, name: "系列", cover: cover)],
            products: [.init(id: "product", shopID: shop.id, seriesID: "series", name: "商品", category: "JSK")])
    }

    func testScheduleSaveUpdatesBothEnvironmentSnapshotsWithoutPublishingOtherLocalFields() throws {
        var saved = try XCTUnwrap(catalog(cover: "local:unpublished.jpg").series.first)
        saved.description = "本机其它未提交修改"
        saved.reservationBatches = [.init(id: "first", name: "先行团", balanceDueKind: .approximate,
                                         balanceDueText: "2027年2月中上旬")]
        let update = OpsSeriesConfigUpdate(series: saved, shop: shop, fields: [.schedule])
        for cover in ["development-cover", "production-cover"] {
            let remote = catalog(cover: cover)
            let updated = try OpsSeriesConfigUpdate.applying([update], to: remote)
            XCTAssertEqual(updated.series.first?.reservationBatches, saved.reservationBatches)
            XCTAssertEqual(updated.series.first?.cover, cover)
            XCTAssertNil(updated.series.first?.description)
            XCTAssertEqual(updated.products, remote.products)
            XCTAssertEqual(updated.shops, remote.shops)
        }
    }

    func testPendingSavesCoalesceAcrossFieldsAndSeriesAndSurviveRestore() throws {
        var first = catalog(cover: "new-cover").series[0]
        var updates = [OpsSeriesConfigUpdate(series: first, shop: shop, fields: [.cover])]
        first.reservationBatches = [.init(id: "stable", name: "一团")]
        updates = OpsSeriesConfigUpdate.coalescing(updates, with: .init(series: first, shop: shop, fields: [.schedule]))
        let other = CatalogSeries(id: "other", shopID: shop.id, name: "另一系列")
        updates = OpsSeriesConfigUpdate.coalescing(updates, with: .init(series: other, shop: shop, fields: [.schedule]))
        updates = try JSONDecoder().decode([OpsSeriesConfigUpdate].self, from: JSONEncoder().encode(updates))
        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(updates[0].fields, [.cover, .schedule])
        let updated = try OpsSeriesConfigUpdate.applying(updates, to: catalog(cover: "old-cover"))
        XCTAssertEqual(updated.series.first?.cover, "new-cover")
        XCTAssertEqual(updated.series.first?.reservationBatches?.first?.id, "stable")
        XCTAssertEqual(updated.series.last?.id, "other")
    }

    func testExplicitRemovalDoesNotReviveOldGroupsFromEitherEnvironment() throws {
        var remote = catalog(cover: "cover")
        remote.series[0].reservationBatches = [.init(id: "old", name: "旧团")]
        var saved = remote.series[0]
        saved.reservationBatches = nil
        let updated = try OpsSeriesConfigUpdate.applying([.init(series: saved, shop: shop, fields: [.schedule])], to: remote)
        XCTAssertNil(updated.series.first?.reservationBatches)
        XCTAssertEqual(try OpsSeriesConfigUpdate.applying([.init(series: saved, shop: shop, fields: [.schedule])], to: updated), updated)
    }

    func testTargetTombstoneIsNeverOverwrittenByAutomaticSave() throws {
        let saved = catalog(cover: "cover").series[0]
        let remote = ShopCatalog(shops: [shop], removedSeriesIDs: [saved.id])
        XCTAssertThrowsError(try OpsSeriesConfigUpdate.applying([.init(series: saved, shop: shop, fields: [.schedule])], to: remote))
    }

    func testCoverUpdateCarriesReferencedAssetAndArchiveRejectsMissingLocalBytes() throws {
        let saved = catalog(cover: "new-asset").series[0]
        let update = OpsSeriesConfigUpdate(series: saved, shop: shop, fields: [.cover],
            assets: [.init(id: "new-asset", type: .productImage, originalURL: "local:cover.jpg")])
        let updated = try OpsSeriesConfigUpdate.applying([update], to: catalog(cover: "old"))
        XCTAssertEqual(updated.assets.first?.id, "new-asset")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try OpsSeriesConfigUpdate.archive(catalog: updated, mediaDirectory: directory))
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("cover.jpg"))
        XCTAssertFalse(try OpsSeriesConfigUpdate.archive(catalog: updated, mediaDirectory: directory).isEmpty)
    }
}
