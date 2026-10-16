import XCTest
import SwiftData
import UIKit
@testable import ItemManager

@MainActor
final class ShopCatalogWardrobeImageImportTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var savedPaths: [String] = []

    override func setUpWithError() throws {
        ShopCatalogStorage.useTemporaryForTesting()
        ShopCatalogSyncStorage.useTemporaryForTesting()
        container = try ModelContainer(for: Clothing.self, Brand.self, Tag.self, StoredImage.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        ShopCatalogWardrobeImageImporter.release(savedPaths, modelContext: context)
        try context.save()
        savedPaths = []
        ShopCatalogSyncStorage.restoreDefaultForTesting()
        ShopCatalogStorage.restoreDefaultForTesting()
    }

    func testCanonicalMediaSurvivesCatalogAndDownloadCacheRemoval() async throws {
        let bytes = imageData()
        let key = ShopCatalogSyncProtocol.sha256Hex(bytes)
        let asset = CatalogAsset(id: "cover", type: .productImage, originalURL: "", mediaKey: key)
        let product = product(images: [asset.id])
        let store = ShopCatalogStore(catalog: ShopCatalog(products: [product], assets: [asset]))
        let media = ShopCatalogMediaStore(reader: MediaReader(data: bytes))
        savedPaths = try await ShopCatalogWardrobeImageImporter.materialize(
            product: product, store: store, modelContext: context, mediaStore: media)
        XCTAssertEqual(savedPaths.count, 1)
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: product.id), store: store)).with(imagePaths: savedPaths)
        let clothing = try ShopCatalogWardrobeInserter.insert(
            draft: draft, selection: .init(productID: product.id), store: store, modelContext: context)
        let download = try XCTUnwrap(ShopCatalogPackCache.cachedMediaURL(contentHash: key))
        try FileManager.default.removeItem(at: download)
        store.installRemoteCatalog(ShopCatalog())
        XCTAssertNil(store.product(id: product.id))
        XCTAssertEqual(clothing.imagePaths, savedPaths)
        for path in clothing.imagePaths {
            let owned = ImageManager.shared.imagesDirectory.appendingPathComponent(path)
            XCTAssertNotEqual(owned, download)
            XCTAssertNotNil(UIImage(contentsOfFile: owned.path),
                            "删除时光馆目录和缓存后，衣橱必须仍有自己的可解码图片")
        }
    }

    func testLegacyMediaAndLocalUploadUseSamePersistentImageOwnership() async throws {
        let local = try XCTUnwrap(ShopCatalogImageStore.save(imageData()))
        let localURL = try XCTUnwrap(ShopCatalogImageStore.url(for: local))
        // 运营保存会做 JPEG 编码；远端应使用同一份已保存字节，而不是编码前的 PNG。
        let bytes = try Data(contentsOf: localURL)
        let key = ShopCatalogSyncProtocol.sha256Hex(bytes)
        let store = ShopCatalogStore(catalog: ShopCatalog())
        let first = try await ShopCatalogWardrobeImageImporter.materialize(
            product: product(images: ["thmedia:" + key]), store: store, modelContext: context,
            mediaStore: ShopCatalogMediaStore(reader: MediaReader(data: bytes)))
        let second = try await ShopCatalogWardrobeImageImporter.materialize(
            product: product(images: [local]), store: store, modelContext: context)
        savedPaths = first + second
        XCTAssertEqual(first, second, "同内容走 ImageManager 去重，而不是借用 Catalog 缓存路径")
        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<StoredImage>()).first)
        XCTAssertEqual(stored.refCount, 2)
        try FileManager.default.removeItem(at: localURL)
        ShopCatalogWardrobeImageImporter.release(first, modelContext: context)
        savedPaths = second
        try context.save()
        XCTAssertEqual(stored.refCount, 1)
        XCTAssertNotNil(UIImage(contentsOfFile: ImageManager.shared.imagesDirectory
            .appendingPathComponent(second[0]).path), "另一个衣橱引用仍持有图片")
    }

    func testHTTPImageDownloadsAndInvalidImageCannotBecomeBlankInsertion() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        ImageURLProtocol.bytes = imageData()
        let store = ShopCatalogStore(catalog: ShopCatalog())
        savedPaths = try await ShopCatalogWardrobeImageImporter.materialize(
            product: product(images: ["https://wardrobe-image.test/ok"]), store: store,
            modelContext: context, session: session)
        XCTAssertEqual(savedPaths.count, 1)
        do {
            _ = try await ShopCatalogWardrobeImageImporter.materialize(
                product: product(images: ["https://wardrobe-image.test/missing"]), store: store,
                modelContext: context, session: session)
            XCTFail("404 应明确失败，不能悄悄返回空图片数组")
        } catch {
            XCTAssertTrue(error is ShopCatalogWardrobeImageImporter.ImportError)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StoredImage>()), 1)
    }

    func testLaterImageFailureReleasesEarlierImageWithoutCreatingWardrobeRecord() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        ImageURLProtocol.bytes = imageData()
        do {
            _ = try await ShopCatalogWardrobeImageImporter.materialize(
                product: product(images: ["https://wardrobe-image.test/ok", "https://wardrobe-image.test/missing"]),
                store: ShopCatalogStore(catalog: ShopCatalog()), modelContext: context, session: session)
            XCTFail("图片必须全部保存成功才返回")
        } catch {
            XCTAssertTrue(error is ShopCatalogWardrobeImageImporter.ImportError)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StoredImage>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Clothing>()), 0)
    }

    func testDeduplicationRepairsMissingOwnedFileBeforeRetainingReference() async throws {
        let bytes = imageData()
        let key = ShopCatalogSyncProtocol.sha256Hex(bytes)
        let product = product(images: ["thmedia:" + key])
        let store = ShopCatalogStore(catalog: ShopCatalog())
        let media = ShopCatalogMediaStore(reader: MediaReader(data: bytes))
        let first = try await ShopCatalogWardrobeImageImporter.materialize(
            product: product, store: store, modelContext: context, mediaStore: media)
        savedPaths = first
        let ownedURL = ImageManager.shared.imagesDirectory.appendingPathComponent(first[0])
        try FileManager.default.removeItem(at: ownedURL)
        let second = try await ShopCatalogWardrobeImageImporter.materialize(
            product: product, store: store, modelContext: context, mediaStore: media)
        savedPaths += second
        XCTAssertEqual(first, second)
        XCTAssertNotNil(UIImage(contentsOfFile: ownedURL.path), "命中去重记录时也必须确保实际文件可读")
        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredImage>()).first?.refCount, 2)
    }

    func testSelectedColorPrefersBoundImagesAndKeepsGenericGalleryAcrossSizes() {
        let product = product(images: ["blue", "detail", "pink", "pink-alias"])
        let key = String(repeating: "a", count: 64)
        let store = ShopCatalogStore(catalog: ShopCatalog(products: [product], variants: [
            CatalogProductVariant(id: "pink-s", productID: product.id, color: "粉色", size: "S", imageAssetID: "pink"),
            CatalogProductVariant(id: "pink-m", productID: product.id, color: "粉色", size: "M", imageAssetID: "pink-alias"),
            CatalogProductVariant(id: "blue-s", productID: product.id, color: "蓝色", size: "S", imageAssetID: "blue")
        ], assets: [CatalogAsset(id: "pink", type: .productImage, originalURL: "", mediaKey: key),
                    CatalogAsset(id: "pink-alias", type: .productImage, originalURL: "", mediaKey: key)]))
        XCTAssertEqual(ShopCatalogWardrobeImageImporter.references(product: product, store: store, selectedColor: " 粉色 "), ["pink", "detail"])
        XCTAssertEqual(ShopCatalogWardrobeImageImporter.references(product: product, store: store, selectedColor: "蓝色"), ["blue", "detail"])
        XCTAssertEqual(ShopCatalogWardrobeImageImporter.references(product: product, store: store, selectedColor: nil), product.images)
        XCTAssertTrue(ShopCatalogWardrobeImageImporter.references(product: product, store: store, selectedColor: "绿色").isEmpty)
    }

    func testSingleColorRetainsDetailsAndVariantImageOutsideProductGallery() {
        let product = product(images: ["detail-a", "detail-b"])
        let store = ShopCatalogStore(catalog: ShopCatalog(products: [product], variants: [
            CatalogProductVariant(id: "white", productID: product.id, color: "白色", imageAssetID: "white-cover")
        ]))
        XCTAssertEqual(ShopCatalogWardrobeImageImporter.references(product: product, store: store, selectedColor: "白色"),
                       ["white-cover", "detail-a", "detail-b"])
    }

    func testMissingBindingsKeepGenericGalleryButExcludeImagesBoundToAnotherColor() {
        let product = product(images: ["shared", "gallery-cover", "unknown-detail"])
        let store = ShopCatalogStore(catalog: ShopCatalog(products: [product], variants: [
            CatalogProductVariant(id: "pink", productID: product.id, color: "粉色", imageAssetID: "shared"),
            CatalogProductVariant(id: "blue", productID: product.id, color: "蓝色", imageAssetID: "shared"),
            CatalogProductVariant(id: "green", productID: product.id, color: "绿色")
        ]))
        XCTAssertEqual(ShopCatalogWardrobeImageImporter.references(product: product, store: store, selectedColor: "粉色"),
                       ["gallery-cover", "unknown-detail"])
        XCTAssertEqual(ShopCatalogWardrobeImageImporter.references(product: product, store: store, selectedColor: "绿色"),
                       ["gallery-cover", "unknown-detail"])
        XCTAssertEqual(ShopCatalogWardrobeImageImporter.references(product: product,
            store: ShopCatalogStore(catalog: ShopCatalog(products: [product])), selectedColor: "粉色"), product.images)
    }

    func testProductGalleryPersistsWhenChosenColorHasNoVariantImageBinding() async throws {
        let reference = try XCTUnwrap(ShopCatalogImageStore.save(imageData()))
        let url = try XCTUnwrap(ShopCatalogImageStore.url(for: reference))
        defer { try? FileManager.default.removeItem(at: url) }
        var dress = product(images: [reference])
        dress.name = "粉色大蝴蝶结背心裙"
        for variants in [[], [CatalogProductVariant(id: "pink", productID: dress.id, color: "粉色"),
                              CatalogProductVariant(id: "red", productID: dress.id, color: "红色")]] {
            let store = ShopCatalogStore(catalog: ShopCatalog(products: [dress], variants: variants))
            let selection = ShopCatalogWardrobeDraftBuilder.Selection(productID: dress.id, color: "粉色")
            let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(selection: selection, store: store))
            let clothing = try await ShopCatalogWardrobeInserter.insertWithImages(
                draft: draft, selection: selection, store: store, modelContext: context)
            savedPaths += clothing.imagePaths
            XCTAssertEqual(clothing.imagePaths.count, 1, "没有规格图绑定也必须保留商品相册")
            XCTAssertNotNil(UIImage(contentsOfFile: ImageManager.shared.imagesDirectory
                .appendingPathComponent(try XCTUnwrap(clothing.imagePaths.first)).path))
        }
    }

    func testNoUsableSelectedColorImageFailsBeforeCreatingBlankWardrobeRecord() async throws {
        let dress = product(images: ["other-color"])
        let store = ShopCatalogStore(catalog: ShopCatalog(products: [dress], variants: [
            CatalogProductVariant(id: "pink", productID: dress.id, color: "粉色"),
            CatalogProductVariant(id: "blue", productID: dress.id, color: "蓝色", imageAssetID: "other-color")
        ]))
        let selection = ShopCatalogWardrobeDraftBuilder.Selection(productID: dress.id, color: "粉色")
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(selection: selection, store: store))
        do {
            _ = try await ShopCatalogWardrobeInserter.insertWithImages(
                draft: draft, selection: selection, store: store, modelContext: context)
            XCTFail("不能把已有图片的商品静默保存成空图衣物")
        } catch {
            XCTAssertTrue(error is ShopCatalogWardrobeImageImporter.ImportError)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Clothing>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StoredImage>()), 0)
    }

    func testChosenBatchAndProductGalleryAreSavedTogetherWithCorrectFinalPaymentDates() async throws {
        let reference = try XCTUnwrap(ShopCatalogImageStore.save(imageData()))
        let url = try XCTUnwrap(ShopCatalogImageStore.url(for: reference))
        defer { try? FileManager.default.removeItem(at: url) }
        let dress = product(images: [reference])
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
        let secondDate = firstDate.addingTimeInterval(86_400 * 60)
        let series = CatalogSeries(id: dress.seriesID, shopID: dress.shopID, name: "分团商品",
            reservationBatches: [
                .init(id: "first", name: "先行团", balanceDueKind: .exact, balanceDueAt: firstDate),
                .init(id: "second", name: "二团", balanceDueKind: .exact, balanceDueAt: secondDate)
            ])
        let store = ShopCatalogStore(catalog: ShopCatalog(
            shops: [.init(id: dress.shopID, name: "店家")], series: [series], products: [dress],
            saleEvents: [.init(id: "reservation", productID: dress.id, type: .reservation,
                              price: 400, deposit: 100, balance: 300, currency: .cny)]))
        for mode: ShopCatalogWardrobeDraftBuilder.PriceMode in [.stock, .reservation(depositPaid: 100), .fullReservation, .fullStock] {
            XCTAssertNil(ShopCatalogWardrobeDraftBuilder.makeDraft(
                selection: .init(productID: dress.id, priceMode: mode), store: store),
                "有多团的已购商品必须选择购买团次")
        }
        for (id, date) in [("first", firstDate), ("second", secondDate)] {
            let selection = ShopCatalogWardrobeDraftBuilder.Selection(productID: dress.id, color: "粉色",
                priceMode: .reservation(depositPaid: 100), reservationBatchID: id)
            let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(selection: selection, store: store))
            XCTAssertThrowsError(try ShopCatalogWardrobeInserter.insert(draft: draft,
                selection: .init(productID: dress.id), store: store, modelContext: context))
            let clothing = try await ShopCatalogWardrobeInserter.insertWithImages(
                draft: draft, selection: selection, store: store, modelContext: context)
            savedPaths += clothing.imagePaths
            XCTAssertEqual(clothing.catalogReservationBatchID, id)
            XCTAssertEqual(clothing.finalPaymentDate, date)
            XCTAssertEqual(clothing.finalPaymentEndDate, date)
            XCTAssertEqual(clothing.pendingFinalPaymentAmount, 300)
            XCTAssertTrue(clothing.isFinalPaymentPlan)
            XCTAssertEqual(clothing.imagePaths.count, 1)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Clothing>()), 2)
    }

    func testConfirmedInsertionPersistsSelectedColorOnlyIncludingAttachedAccessory() async throws {
        let selectedImage = try XCTUnwrap(ShopCatalogImageStore.save(imageData()))
        let imageURL = try XCTUnwrap(ShopCatalogImageStore.url(for: selectedImage))
        defer { try? FileManager.default.removeItem(at: imageURL) }
        let missing = "local:other-color-must-not-be-loaded.jpg"
        let dress = product(images: [missing, selectedImage])
        let bag = CatalogProduct(id: "bag", shopID: dress.shopID, seriesID: dress.seriesID,
                                 name: "配套包", category: "包", images: [missing, selectedImage])
        let variants = [dress, bag].flatMap { product in
            [CatalogProductVariant(id: product.id + "/pink", productID: product.id, color: "粉色", imageAssetID: selectedImage),
             CatalogProductVariant(id: product.id + "/blue", productID: product.id, color: "蓝色", imageAssetID: missing)]
        }
        let store = ShopCatalogStore(catalog: ShopCatalog(products: [dress, bag], variants: variants))
        let selection = ShopCatalogWardrobeDraftBuilder.Selection(productID: dress.id, color: "粉色")
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(selection: selection, store: store))
        let inserted = try await ShopCatalogWardrobeInserter.insertSetWithImages(
            drafts: [(draft, selection)], accessoryProductIDs: [bag.id],
            accessorySelections: [bag.id: .init(productID: bag.id, color: "粉色")],
            store: store, modelContext: context)
        let clothing = try XCTUnwrap(inserted.first)
        let accessoryPaths = try XCTUnwrap(clothing.accessoryItems?.first?.imagePaths)
        savedPaths = clothing.imagePaths + accessoryPaths
        XCTAssertEqual(clothing.colors, "粉色")
        XCTAssertEqual(clothing.imagePaths.count, 1, "详情滑动相册只读取这些持久化图片")
        XCTAssertEqual(accessoryPaths.count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StoredImage>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredImage>()).first?.refCount, 2)
        XCTAssertEqual(WardrobeStorageInventory.entries(clothings: inserted).map(\.category), [.wardrobe])
    }

    private func product(images: [String]) -> CatalogProduct {
        CatalogProduct(id: "image-test-product", shopID: "image-test-shop", seriesID: "image-test-series",
                       name: "图片持久化验收", category: "JSK", images: images)
    }

    private func imageData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 37, height: 29)).image { renderer in
            UIColor(red: CGFloat.random(in: 0.1...0.9), green: 0.63, blue: 0.79, alpha: 1).setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 37, height: 29))
        }.pngData()!
    }

    private struct MediaReader: ShopCatalogPublicReading {
        let data: Data
        func fetchReleaseHeader() async throws -> ShopCatalogReleaseHeader {
            throw ShopCatalogSyncError.recordMissing(recordType: "THRelease", recordName: "test")
        }
        func fetchRootIndex() async throws -> Data { Data() }
        func fetchPack(payloadHash: String) async throws -> Data { Data() }
        func fetchMedia(contentHash: String) async throws -> Data { data }
    }
}

private final class ImageURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var bytes = Data()
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "wardrobe-image.test"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = request.url?.path == "/missing" ? 404 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
