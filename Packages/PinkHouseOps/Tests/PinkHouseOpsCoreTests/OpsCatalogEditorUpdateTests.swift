import XCTest
import SharedCatalog
@testable import PinkHouseOpsCore

final class OpsCatalogEditorUpdateTests: XCTestCase {
    private func catalog(_ name: String = "旧款") -> ShopCatalog {
        .init(shops: [.init(id: "shop", name: "店家")], series: [.init(id: "series", shopID: "shop", name: "系列")],
            products: [.init(id: "product", shopID: "shop", seriesID: "series", name: name, category: "JSK", designName: name)])
    }
    func testSaveOnlyChangesNamedFieldsAndKeepsEachEnvironmentPricesAndImages() throws {
        let old = catalog(), saved = catalog("新款")
        var remote = old
        remote.products[0].images = ["https://example.com/online.jpg"]
        remote.products[0].description = "此环境独有描述"
        remote.saleEvents = [.init(id: "sale", productID: "product", type: .stock, price: 399, currency: .cny)]
        let result = try OpsCatalogEditorUpdate.applying([.init(before: old, after: saved)], to: remote)
        XCTAssertEqual(result.products[0].name, "新款")
        XCTAssertEqual(result.products[0].designName, "新款")
        XCTAssertEqual(result.products[0].images, remote.products[0].images)
        XCTAssertEqual(result.products[0].description, remote.products[0].description)
        XCTAssertEqual(result.saleEvents, remote.saleEvents)
        try OpsCatalogEditorUpdate.verify([.init(before: old, after: saved)], in: result)
    }
    func testReadBackOldNameCannotBeReportedAsComplete() {
        XCTAssertThrowsError(try OpsCatalogEditorUpdate.verify([.init(before: catalog(), after: catalog("新名"))], in: catalog()))
    }
    func testConcurrentNameEditFailsInsteadOfOverwritingIt() {
        XCTAssertThrowsError(try OpsCatalogEditorUpdate.applying([.init(before: catalog(), after: catalog("新名"))], to: catalog("其他运营的新名")))
    }
    func testRepeatedSavesAreIdempotentAtAnyKnownIntermediateState() throws {
        let edits = [OpsCatalogEditorUpdate(before: catalog("A"), after: catalog("B")),
                     .init(before: catalog("B"), after: catalog("C"))]
        for name in ["A", "B", "C"] {
            let result = try OpsCatalogEditorUpdate.applying(edits, to: catalog(name))
            XCTAssertEqual(result.products[0].name, "C")
            try OpsCatalogEditorUpdate.verify(edits, in: result)
        }
    }
    func testMissingPublishedProductIsNotSilentlySkipped() {
        var remote = catalog(); remote.products = []
        XCTAssertThrowsError(try OpsCatalogEditorUpdate.applying([.init(before: catalog(), after: catalog("新名"))], to: remote))
    }
    func testMissingEditedProductBootstrapsOnlyItsDependenciesAndKeepsTargetContent() throws {
        var old = catalog(), saved = catalog("新款"), remote = catalog()
        let hash = String(repeating: "a", count: 64)
        old.products[0].images = ["photo"]; saved.products[0].images = ["photo"]
        saved.assets = [.init(id: "photo", type: .productImage, originalURL: "thmedia:" + hash)]
        saved.variants = [.init(id: "variant", productID: "product", color: "蓝色", imageAssetID: "photo")]
        saved.sizeCharts = [.init(id: "chart", productID: "product", columns: ["M"])]
        saved.saleEvents = [.init(id: "sale", productID: "product", type: .reservation, price: 399, currency: .cny)]
        remote.products = [.init(id: "unrelated", shopID: "shop", seriesID: "series", name: "环境独有", category: "OP")]
        remote.series[0].description = "环境自己的系列资料"
        let edits = [OpsCatalogEditorUpdate(before: old, after: saved)]
        let dependency = try XCTUnwrap(OpsCatalogEditorUpdate.missingProductDependencies(edits, in: remote))
        let result = try OpsCatalogEditorUpdate.applying([dependency] + edits, to: remote)
        XCTAssertEqual(result.products.count, 2)
        XCTAssertEqual(result.products.first { $0.id == "product" }?.name, "新款")
        XCTAssertEqual(result.products.first { $0.id == "product" }?.images, ["photo"])
        XCTAssertEqual(result.series[0].description, "环境自己的系列资料")
        XCTAssertEqual(result.variants, saved.variants)
        XCTAssertEqual(result.sizeCharts, saved.sizeCharts)
        XCTAssertEqual(result.saleEvents, saved.saleEvents)
        try OpsCatalogEditorUpdate.verify([dependency] + edits, in: result)
        XCTAssertNil(try OpsCatalogEditorUpdate.missingProductDependencies(edits, in: result))
    }
    func testMissingEditedProductNeverResurrectsTombstones() throws {
        let edits = [OpsCatalogEditorUpdate(before: catalog(), after: catalog("新款"))]
        for kind in ["product", "series", "shop"] {
            var remote = catalog(); remote.products = []
            if kind == "product" { remote.removedProductIDs = ["product"] }
            if kind == "series" { remote.removedSeriesIDs = ["series"] }
            if kind == "shop" { remote.removedShopIDs = ["shop"] }
            XCTAssertThrowsError(try OpsCatalogEditorUpdate.missingProductDependencies(edits, in: remote))
        }
    }
    func testNameChangeMigratesEachEnvironmentOwnStyleProfileWithoutCopyingFabric() throws {
        var old = catalog("旧款"), saved = catalog("新款"), remote = catalog("旧款")
        old.styleProfiles = [.init(id: "series|JSK|旧款", seriesID: "series", category: "JSK", designName: "旧款", fabric: "源面料")]
        saved.styleProfiles = [.init(id: "series|JSK|新款", seriesID: "series", category: "JSK", designName: "新款", fabric: "源面料")]
        remote.styleProfiles = [.init(id: "series|JSK|旧款", seriesID: "series", category: "JSK", designName: "旧款", fabric: "目标面料")]
        let edits = [OpsCatalogEditorUpdate(before: old, after: saved)]
        let result = try OpsCatalogEditorUpdate.applying(edits, to: remote)
        XCTAssertEqual(result.styleProfiles.first?.id, "series|JSK|新款")
        XCTAssertEqual(result.styleProfiles.first?.fabric, "目标面料")
        try OpsCatalogEditorUpdate.verify(edits, in: result)
    }
    func testArchivedLocalColorAbsentFromPublicPackDoesNotBlockWholeDesignRename() throws {
        var old = catalog(), saved = catalog("新款")
        var archived = old.products[0]; archived.id = "archived"; archived.archivedAt = Date(timeIntervalSince1970: 1)
        old.products.append(archived)
        archived.name = "新款"; archived.designName = "新款"
        saved.products.append(archived)
        let result = try OpsCatalogEditorUpdate.applying([.init(before: old, after: saved)], to: catalog())
        XCTAssertEqual(result.products.count, 1)
        XCTAssertEqual(result.products[0].name, "新款")
    }
    func testNewEntityFollowedByAnotherEditIsIdempotent() throws {
        var empty = catalog(); empty.products = []
        let edits = [OpsCatalogEditorUpdate(before: empty, after: catalog("A")), .init(before: catalog("A"), after: catalog("B"))]
        for remote in [empty, catalog("A"), catalog("B")] {
            XCTAssertEqual(try OpsCatalogEditorUpdate.applying(edits, to: remote).products[0].name, "B")
        }
    }
    func testMediaReadBackComparesContentIdentityAndKeepsRemoteURL() throws {
        let hash = String(repeating: "a", count: 64)
        var old = catalog(), saved = old, online = old
        old.products[0].images = []
        saved.products[0].images = ["local:image.jpg"]
        online.products[0].images = ["thmedia:" + hash]
        try OpsCatalogEditorUpdate.verify([.init(before: old, after: saved)], in: online,
            mediaHashes: ["local:image.jpg": hash])
    }
    func testProgressRequiresBothEnvironmentReceiptsAndFailureNeverShows100Percent() {
        var progress = OpsCatalogEditProgress(requestID: "request", revision: 3)
        progress.advance(environment: "development", stage: 2, detail: "上传图片已完成")
        XCTAssertLessThan(progress.fraction, 1)
        progress.confirm(environment: "development", releaseSeq: 22)
        XCTAssertNotEqual(progress.state, .complete)
        progress.fail("线上尚未确认")
        XCTAssertLessThan(progress.fraction, 1)
        progress.confirm(environment: "production", releaseSeq: 17)
        XCTAssertEqual(progress.state, .complete)
        XCTAssertEqual(progress.fraction, 1)
    }
}
