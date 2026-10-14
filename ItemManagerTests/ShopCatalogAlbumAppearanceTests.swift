import XCTest
import SwiftUI
import UIKit
@testable import ItemManager

@MainActor
final class ShopCatalogAlbumAppearanceTests: XCTestCase {
    /// Real page layout with isolated catalog data, including selected year / series states.
    func testRenderYearRailAndSeriesNamesInBothSchemes() async throws {
        let defaults = UserDefaults.standard
        let skins = ThemeSkinManager.shared
        let before = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("theme_") || $0.key == "pet_chat_skin_theme" }
        defer {
            let keys = Set(before.keys).union(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("theme_") || $0 == "pet_chat_skin_theme" })
            for key in keys {
                if let value = before[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            skins.reloadFromDisk(applyBackgroundHarmony: false)
        }
        let json = #"""
        {"version":1,"shops":[{"id":"album-shop","name":"多年店铺时光册"},{"id":"short-shop","name":"店铺时光册"}],"series":[
          {"id":"dogs","shopID":"album-shop","name":"小狗仪仗队","year":2026},
          {"id":"swans","shopID":"album-shop","name":"天鹅之歌","year":2026},
          {"id":"garden","shopID":"album-shop","name":"花园系列","year":2025},
          {"id":"unknown","shopID":"album-shop","name":"未标年份系列"},
          {"id":"short-dogs","shopID":"short-shop","name":"小狗仪仗队","year":2026},
          {"id":"short-swans","shopID":"short-shop","name":"天鹅之歌","year":2026}],
         "products":[{"id":"dress","shopID":"short-shop","seriesID":"short-swans","name":"白色连衣裙","category":"JSK"}],"variants":[],"sizeCharts":[],"saleEvents":[],"assets":[]}
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
        let cases: [(String, Bool, String, ShopCatalogAlbumSelection, ThemeSkinProduct?)] = [
            ("album-rail-light", false, "album-shop", .init(), nil),
            ("album-compact-light", false, "short-shop", .init(), nil),
            ("album-search-dark", true, "short-shop", .init(keyword: "连衣裙"), nil),
            ("album-search-empty-dark", true, "short-shop", .init(keyword: "没有这个词"), nil),
            ("album-dark-background-light-system", false, "short-shop", .init(), nil),
            ("album-sky-light", false, "short-shop", .init(), .skyConcert),
            ("album-sky-dark", true, "short-shop", .init(), .skyConcert),
            ("album-swan-light", false, "short-shop", .init(), .swanDream),
            ("album-swan-dark", true, "short-shop", .init(), .swanDream)
        ]
        for (name, dark, shopID, selection, skin) in cases {
            let owned = skin.map { [OwnedThemeSkin(id: $0.themeId, purchasedAt: .distantPast, paidPrice: 0)] } ?? []
            let active = skin.map { ActiveThemeSkinSelection(activeThemeId: $0.themeId, enabledSlots: Set($0.defaultEnabledSlots)) } ?? .inactive
            defaults.set(try JSONEncoder().encode(owned), forKey: "theme_skin.owned")
            defaults.set(try JSONEncoder().encode(active), forKey: "theme_skin.active_selection")
            skins.reloadFromDisk(applyBackgroundHarmony: false)
            manager.backgroundColorHex = dark || name == "album-dark-background-light-system" ? "#182B40" : "#E3EFF8"
            let root = NavigationStack {
                ShopCatalogShopView(shopID: shopID, store: store, initialSelection: selection)
            }.environment(manager).environment(\.colorScheme, dark ? .dark : .light)
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            let host = UIHostingController(rootView: root)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(500))
            let field = try XCTUnwrap(findTextField(in: host.view))
            XCTAssertEqual(field.text ?? "", selection.keyword)
            XCTAssertGreaterThan(field.bounds.width, 200, "Search must span the page below the shop name")
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 1000)
            let attachment = XCTAttachment(image: image)
            attachment.name = name + ".png"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    private func findTextField(in view: UIView) -> UITextField? {
        if let field = view as? UITextField { return field }
        return view.subviews.lazy.compactMap(findTextField).first
    }
}
