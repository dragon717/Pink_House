import XCTest
import SwiftUI
import UIKit
@testable import ItemManager

@MainActor
final class ShopCatalogProductOrderingTests: XCTestCase {
    private func product(_ id: String, _ category: String, _ order: Int? = nil) -> CatalogProduct {
        .init(id: id, shopID: "shop", seriesID: "series", name: "款式 " + id, category: category, displayOrder: order)
    }
    private func catalog(_ products: [CatalogProduct]) -> ShopCatalog {
        .init(shops: [.init(id: "shop", name: "排序验收店家")],
            series: [.init(id: "series", shopID: "shop", name: "运营排序验收")], products: products)
    }

    func testLegacySeriesShowsOPBeforeJSKAndFiltersWithoutReordering() {
        let store = ShopCatalogStore(catalog: catalog([product("jsk", "JSK"), product("op-2", "OP"), product("op-1", "OP")]))
        XCTAssertEqual(store.categories(inSeries: "series"), ["OP", "JSK"])
        XCTAssertEqual(store.products(inSeries: "series").map(\.id), ["op-2", "op-1", "jsk"])
        XCTAssertEqual(store.products(inSeries: "series", category: "OP").map(\.id), ["op-2", "op-1"])
    }

    func testPublishedDragOrderAndCustomGroupSurviveRefreshAndArchiveFiltering() {
        var hidden = product("hidden", "隐藏类型", 0)
        hidden.archivedAt = Date()
        let store = ShopCatalogStore(baseCatalog: catalog([]))
        let online = catalog([product("jsk", "JSK", 4), product("op-a", "OP", 3),
            product("custom", "自定义", 1), product("op-b", "OP", 2), hidden])
        for _ in 0..<2 {
            store.installRemoteCatalog(online)
            XCTAssertEqual(store.categories(inSeries: "series"), ["自定义", "OP", "JSK"])
            XCTAssertEqual(store.products(inSeries: "series").map(\.id), ["custom", "op-b", "op-a", "jsk"])
        }
    }

    func testLatestPublishedOrderWinsOverOldLocalOperatorCopy() throws {
        ShopCatalogStorage.useTemporaryForTesting()
        defer { ShopCatalogStorage.restoreDefaultForTesting() }
        try ShopCatalogDraftStore.replaceOverlay(with: catalog([product("a", "OP"), product("b", "OP")]))
        let store = ShopCatalogStore(baseCatalog: catalog([]))
        store.reloadWithOverlay()
        store.installRemoteCatalog(catalog([product("a", "OP", 1), product("b", "OP", 0)]))
        XCTAssertNil(store.product(id: "a")?.displayOrder, "本机编辑副本不被改写")
        XCTAssertEqual(store.products(inSeries: "series").map(\.id), ["b", "a"])
        store.installRemoteCatalog(catalog([product("a", "OP"), product("b", "OP")]))
        XCTAssertEqual(store.products(inSeries: "series").map(\.id), ["a", "b"], "新发布版本未指定顺序时沿用旧目录兼容规则")
    }

    func testRenderRealSeriesMenuWithOperatorOrder() async throws {
        let store = ShopCatalogStore(catalog: catalog([product("JSK-背心裙", "JSK", 2),
            product("OP-第二款", "OP", 1), product("OP-第一款", "OP", 0), product("小物-发带", "小物", 3)]))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 1100)
        window.overrideUserInterfaceStyle = .light
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let host = UIHostingController(rootView: ShopCatalogSeriesMenuView(store: store, seriesID: "series")
            .environment(ThemeManager.shared).environment(\.colorScheme, .light))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "operator-product-order.png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
