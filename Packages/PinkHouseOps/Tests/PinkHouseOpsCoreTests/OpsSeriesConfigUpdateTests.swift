import XCTest
import SharedCatalog
@testable import PinkHouseOpsCore

final class OpsSeriesConfigUpdateTests: XCTestCase {
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
