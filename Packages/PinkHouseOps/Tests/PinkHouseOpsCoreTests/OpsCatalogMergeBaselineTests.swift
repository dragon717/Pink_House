import XCTest
import SharedCatalog
@testable import PinkHouseOpsCore

final class OpsCatalogMergeBaselineTests: XCTestCase {
    private let head = ShopCatalogBaseline(releaseSeq: 16, rootIndexHash: String(repeating: "a", count: 64), environment: "production")
    private var original: ShopCatalog {
        .init(shops: [.init(id: "shop", name: "店家")],
              series: [.init(id: "series", shopID: "shop", name: "双子星")])
    }
    private func merge(_ local: ShopCatalog, _ remote: ShopCatalog, _ baseline: OpsCatalogMergeBaseline) throws -> ShopCatalogThreeWayMerge.Result {
        try ShopCatalogThreeWayMerge.merge(local: local, remote: remote, baseline: baseline.catalog,
            knownBaselineFields: baseline.knownFields, preferLocalOnConflict: true)
    }

    func testScreenshotSixLocalEditsAgainstHistoricallyUnchangedProductionAreNotConflicts() throws {
        var local = original
        local.series[0].salePhase = .balancePending
        local.series[0].balanceDueKind = .exact
        local.series[0].balanceDueAt = Date(timeIntervalSince1970: 1_800_000_000)
        local.series[0].balanceDueEndAt = Date(timeIntervalSince1970: 1_800_086_400)
        local.series[0].cover = "new-cover"
        local.series[0].priceChart = .init(id: "chart", seriesID: "series", unit: "元", columns: [], rows: [])
        let old = try ShopCatalogThreeWayMerge.merge(local: local, remote: original, baseline: nil)
        XCTAssertEqual(old.conflicts.count, 6, "旧流程因环境不同丢弃基线，准确复现截图六项")
        let ancestor = try OpsCatalogMergeBaseline.commonAncestor(legacy: original, previouslyConfirmed: original, head: head)
        let fixed = try merge(local, original, ancestor)
        XCTAssertEqual(fixed.conflicts, [])
        XCTAssertEqual(fixed.catalog.series, local.series)
    }

    func testDifferentEnvironmentContentDoesNotBecomeAnAncestor() throws {
        var target = original, local = original
        target.series[0].description = "线上独立修改"
        local.series[0].description = "本地另一个修改"
        let ancestor = try OpsCatalogMergeBaseline.commonAncestor(legacy: original, previouslyConfirmed: target, head: head)
        XCTAssertNil(ancestor.knownFields?["series.series"])
        XCTAssertTrue(try merge(local, target, ancestor).conflicts.contains("series.series.description"))
    }

    func testScopedAcknowledgementPreservesUnrelatedRemoteChangesAndNewerLocalEdits() throws {
        var local = original, remote = original
        var saved = original.series[0]
        saved.reservationBatches = [.init(id: "first", name: "先行团")]
        local.series[0] = saved
        local.series[0].cover = "unpublished-cover"
        local.series[0].reservationBatches?[0].name = "保存后又改名"
        remote.shops[0].name = "另一端修改店家"
        remote.series[0] = saved
        let ancestor = try OpsCatalogMergeBaseline(head: head, catalog: original)
            .acknowledging([.init(series: saved, shop: nil, fields: [.schedule])], head: head)
        XCTAssertNil(ancestor.catalog.series[0].cover)
        XCTAssertEqual(ancestor.catalog.shops[0].name, "店家")
        let result = try merge(local, remote, ancestor)
        XCTAssertEqual(result.conflicts, [])
        XCTAssertEqual(result.catalog.shops[0].name, "另一端修改店家")
        XCTAssertEqual(result.catalog.series[0].cover, "unpublished-cover")
        XCTAssertEqual(result.catalog.series[0].reservationBatches?[0].name, "保存后又改名")
    }

    func testUnknownEnvironmentAcknowledgesOnlySavedFieldsIncludingExplicitNil() throws {
        var local = original, target = original
        local.series[0].description = "本机描述"
        target.series[0].description = "线上描述"
        var saved = target.series[0]
        saved.reservationBatches = [.init(id: "first", name: "一团")]
        let partial = try OpsCatalogMergeBaseline.commonAncestor(legacy: nil, previouslyConfirmed: target, head: head)
            .acknowledging([.init(series: saved, shop: nil, fields: [.schedule])], head: head)
        target.series[0] = saved
        local.series[0].reservationBatches = [.init(id: "first", name: "二团")]
        let result = try merge(local, target, partial)
        XCTAssertEqual(result.conflicts, ["series.series.description"])
        XCTAssertFalse(partial.knownFields?["series.series"]?.contains("description") == true)
        let restored = try ShopCatalogJSONCoding.decoder().decode(OpsCatalogMergeBaseline.self,
            from: ShopCatalogJSONCoding.encoder().encode(partial))
        XCTAssertEqual(restored, partial)
    }

    func testRealConcurrentEditStillBlocksAfterAcknowledgement() throws {
        var local = original, remote = original
        local.series[0].cover = "local-new"
        remote.series[0].cover = "remote-new"
        let result = try merge(local, remote, .init(head: head, catalog: original))
        XCTAssertEqual(result.conflicts, ["series.series.cover"])
    }

    func testRecoveryRequiresMatchingConfirmedReceiptAndFrozenBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("output"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("pulled"), withIntermediateDirectories: true)
        var published = original
        published.series[0].reservationBatches = [.init(id: "first", name: "先行团")]
        published.assets = [.init(id: "new-asset", type: .productImage,
            originalURL: "thmedia:" + String(repeating: "b", count: 64))]
        let json = try ShopCatalogJSONCoding.encoder().encode(published)
        let archive = ShopCatalogExportArchive.tarData(entries: [.init(name: "shop-catalog.json", data: json)])
        let archiveURL = directory.appendingPathComponent("release.tar")
        try archive.write(to: archiveURL)
        try ShopCatalogJSONCoding.encoder().encode(original).write(to: directory.appendingPathComponent("pulled/shop-catalog.json"))
        let digest = ShopCatalogSyncProtocol.sha256Hex(archive)
        let request = ShopCatalogPublishRequest(requestID: "request", jobID: "job", draftID: "draft",
            draftRevision: 3, targetEnvironment: .production, releaseSeq: 16,
            inputDirectory: directory.appendingPathComponent("input").path, archivePath: archiveURL.path,
            outputDirectory: directory.appendingPathComponent("output").path,
            receiptPath: directory.appendingPathComponent("receipt.json").path, payloadHash: digest)
        try request.encoded().write(to: directory.appendingPathComponent("publish-request.json"))
        try JSONSerialization.data(withJSONObject: ["releaseSeq": 16, "rootIndexHash": head.rootIndexHash!])
            .write(to: directory.appendingPathComponent("output/release.json"))
        var receipt = ShopCatalogPublishReceipt(environment: "production", applied: true, releaseSeq: 16,
            rootIndexHash: head.rootIndexHash, requestID: "request", jobID: "job", draftID: "draft",
            draftRevision: 3, artifactDigest: digest, readBackConfirmed: true)
        func saveReceipt() throws { try ShopCatalogJSONCoding.encoder().encode(receipt).write(to: directory.appendingPathComponent("receipt.json")) }
        func recovered(_ draft: String = "draft") throws -> OpsCatalogMergeBaseline? {
            try OpsCatalogMergeBaseline.recoverConfirmedSeriesJob(at: directory, draftID: draft, legacy: original)
        }
        try saveReceipt()
        let restored = try XCTUnwrap(recovered())
        XCTAssertEqual(restored.catalog.series[0].reservationBatches, published.series[0].reservationBatches)
        XCTAssertTrue(restored.knownFields?["series.series"]?.contains("reservationBatches") == true)
        XCTAssertEqual(restored.knownFields?["assets.new-asset"], ["*"])
        XCTAssertNil(try recovered("another-draft"))
        receipt.readBackConfirmed = false; try saveReceipt(); XCTAssertNil(try recovered())
        receipt.readBackConfirmed = true; receipt.requestID = "other"; try saveReceipt(); XCTAssertNil(try recovered())
        receipt.requestID = "request"; try saveReceipt()
        try Data([1, 2, 3]).write(to: archiveURL); XCTAssertNil(try recovered())
    }
}
