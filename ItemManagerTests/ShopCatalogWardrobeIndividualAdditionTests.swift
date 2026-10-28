import XCTest
import SwiftUI
import SwiftData
import UIKit
@testable import ItemManager

@MainActor
final class ShopCatalogWardrobeIndividualAdditionTests: XCTestCase {
    private var containers: [ModelContainer] = []
    override func setUpWithError() throws {
        ShopCatalogStorage.useTemporaryForTesting()
        ShopCatalogSyncStorage.useTemporaryForTesting()
    }

    override func tearDownWithError() throws {
        containers.removeAll()
        ShopCatalogSyncStorage.restoreDefaultForTesting()
        ShopCatalogStorage.restoreDefaultForTesting()
    }

    func testRepeatedSelectionKeepsCatalogOrderAndCreatesOneDraftPerProduct() throws {
        let addition = ShopCatalogWardrobeIndividualAddition(productIDs: ["jsk", "kc", "bag", "kc"])
        XCTAssertEqual(addition.productIDs, ["jsk", "kc", "bag"])
        let pairs = try addition.makeDrafts(selections: [
            .init(productID: "bag"), .init(productID: "kc"), .init(productID: "jsk")], store: store())
        XCTAssertEqual(pairs.map(\.selection.productID), ["jsk", "kc", "bag"])
        XCTAssertEqual(pairs.count, 3, "小物与包也必须分别生成独立记录")
        XCTAssertTrue(pairs.allSatisfy { $0.draft.accessories.isEmpty && $0.draft.accessoryList.isEmpty })
    }

    func testOneBatchSavePersistsEveryProductWithItsOwnPaymentColorAndSize() async throws {
        let store = store()
        let addition = ShopCatalogWardrobeIndividualAddition(productIDs: ["jsk", "kc", "bag"])
        let pairs = try addition.makeDrafts(selections: [
            .init(productID: "jsk", color: "星空蓝", size: "M", priceMode: .reservation(depositPaid: 128)),
            .init(productID: "kc", color: "粉色", priceMode: .fullReservation),
            .init(productID: "bag", color: "白色", size: "均码")], store: store, note: "一键入橱")
        let context = try context()
        let inserted = try await ShopCatalogWardrobeInserter.insertSetWithImages(
            drafts: pairs.map { (draft: $0.draft, selection: $0.selection) },
            accessoryProductIDs: [], store: store, modelContext: context)
        XCTAssertEqual(inserted.map(\.catalogProductID), ["jsk", "kc", "bag"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Clothing>()), 3)
        XCTAssertEqual(inserted.map(\.types), ["JSK", "KC", "包"])
        XCTAssertEqual(inserted.map(\.colors), ["星空蓝", "粉色", "白色"])
        XCTAssertEqual(inserted.map(\.sizes), ["M", "", "均码"])
        XCTAssertEqual(inserted.map(\.pendingFinalPaymentAmount), [300, 0, 0])
        XCTAssertEqual(inserted.map(\.reservationKind), [.depositPlan, .fullPaymentReservation, .owned])
        XCTAssertTrue(inserted.allSatisfy { $0.note == "一键入橱" && ($0.accessoryItems ?? []).isEmpty })
    }

    func testEmptyOrMissingSelectionCannotBuildPartialBatch() throws {
        let store = store()
        XCTAssertThrowsError(try ShopCatalogWardrobeIndividualAddition(productIDs: [])
            .makeDrafts(selections: [], store: store))
        let addition = ShopCatalogWardrobeIndividualAddition(productIDs: ["jsk", "missing"])
        XCTAssertThrowsError(try addition.makeDrafts(selections: [.init(productID: "jsk")], store: store))
        XCTAssertThrowsError(try addition.makeDrafts(selections: [
            .init(productID: "jsk"), .init(productID: "missing")], store: store))
    }

    func testLateBatchValidationFailureRollsBackAllIndependentRecords() async throws {
        let source = store()
        let pairs = try ShopCatalogWardrobeIndividualAddition(productIDs: ["jsk", "kc"])
            .makeDrafts(selections: [.init(productID: "jsk"), .init(productID: "kc")], store: source)
        // 在草稿构建后，第二个系列变为必须选团；第一条不能残留半批保存。
        let changed = store(splitSeriesWithRequiredBatch: true)
        let context = try context()
        do {
            _ = try await ShopCatalogWardrobeInserter.insertSetWithImages(
                drafts: pairs.map { (draft: $0.draft, selection: $0.selection) },
                accessoryProductIDs: [], store: changed, modelContext: context)
            XCTFail("第二件未选团，整批应失败")
        } catch {
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Clothing>()), 0)
        }
    }

    func testRenderMenuAndSinglePageConfirmationContainingAllProducts() async throws {
        let store = store()
        let context = try context()
        try await capture(ShopCatalogSeriesMenuView(store: store, seriesID: "series")
            .modelContainer(context.container), name: "individual-and-merge-entrances")
        let addition = ShopCatalogWardrobeIndividualAddition(productIDs: ["jsk", "kc", "bag"])
        try await capture(ShopCatalogWardrobeIndividualAdditionView(
            addition: addition, priceChoices: [:], colorByProduct: ["jsk": "星空蓝"],
            sizeByProduct: ["jsk": "M"], store: store, onProductsAdded: { _ in
                XCTFail("渲染不能保存商品")
            }).modelContainer(context.container), name: "individual-single-confirmation-3-products")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Clothing>()), 0)
    }

    private func store(splitSeriesWithRequiredBatch: Bool = false) -> ShopCatalogStore {
        ShopCatalogStore(catalog: ShopCatalog(
            shops: [.init(id: "shop", name: "一键入橱测试店家")],
            series: [.init(id: "series", shopID: "shop", name: "星光心愿"),
                     .init(id: "second", shopID: "shop", name: "小物团",
                           reservationBatches: [.init(id: "first", name: "一团"),
                                                .init(id: "second", name: "二团")])],
            products: [.init(id: "jsk", shopID: "shop", seriesID: "series", name: "星光背心裙", category: "JSK"),
                       .init(id: "kc", shopID: "shop", seriesID: splitSeriesWithRequiredBatch ? "second" : "series",
                             name: "星光发带", category: "KC"),
                       .init(id: "bag", shopID: "shop", seriesID: "series", name: "星光包", category: "包")],
            saleEvents: [.init(id: "jsk-sale", productID: "jsk", type: .reservation,
                               price: 428, deposit: 128, balance: 300, currency: .cny),
                         .init(id: "kc-sale", productID: "kc", type: .reservation,
                               price: 68, deposit: 18, balance: 50, currency: .cny),
                         .init(id: "bag-sale", productID: "bag", type: .stock, price: 128, currency: .cny)]))
    }

    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: Schema([Clothing.self, Brand.self, Tag.self, StoredImage.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        containers.append(container)
        return ModelContext(container)
    }

    private func capture<Content: View>(_ content: Content, name: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.overrideUserInterfaceStyle = .light
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let host = UIHostingController(rootView: content.environment(ThemeManager.shared))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name + ".png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
