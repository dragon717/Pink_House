import XCTest
import SwiftUI
import UIKit
@testable import ItemManager

@MainActor
final class ShopCatalogAlbumAppearanceTests: XCTestCase {
    /// Real page layout with isolated catalog data, including selected year / series states.
    func testRenderYearRailAndSeriesNamesInBothSchemes() async throws {
        let defaults = UserDefaults.standard
        let before = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("theme_") || $0.key == "pet_chat_skin_theme" }
        defer {
            let keys = Set(before.keys).union(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("theme_") || $0 == "pet_chat_skin_theme" })
            for key in keys {
                if let value = before[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        let json = #"""
        {"version":1,"shops":[{"id":"album-shop","name":"店铺时光册"}],"series":[
          {"id":"dogs","shopID":"album-shop","name":"小狗仪仗队","year":2026},
          {"id":"swans","shopID":"album-shop","name":"天鹅之歌","year":2026},
          {"id":"garden","shopID":"album-shop","name":"花园系列","year":2025},
          {"id":"unknown","shopID":"album-shop","name":"未标年份系列"}],
         "products":[],"variants":[],"sizeCharts":[],"saleEvents":[],"assets":[]}
        """#
        let catalog = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: Data(json.utf8))
        let store = ShopCatalogStore(catalog: catalog)
        let manager = ThemeManager()
        manager.colorSchemeMode = .magic
        manager.backgroundStyle = .color
        manager.cardStyle = .solid
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 780)
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        for (name, dark, selection) in [
            ("album-all-light", false, ShopCatalogAlbumSelection()),
            ("album-2026-dark", true, ShopCatalogAlbumSelection(year: .year(2026))),
            ("album-series-light", false, ShopCatalogAlbumSelection(year: .year(2026), seriesID: "swans"))
        ] {
            manager.backgroundColorHex = dark ? "#182B40" : "#E3EFF8"
            let root = NavigationStack {
                ShopCatalogShopView(shopID: "album-shop", store: store, initialSelection: selection)
            }.environment(manager).environment(\.colorScheme, dark ? .dark : .light)
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            let host = UIHostingController(rootView: root)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(500))
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 1000)
            let attachment = XCTAttachment(image: image)
            attachment.name = name + ".png"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
