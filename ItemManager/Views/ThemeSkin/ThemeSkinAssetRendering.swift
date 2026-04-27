import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum ThemeSkinAssetName {
    static let topBarMain = "top_bar_main_default"
    static let topBarIconButton = "top_bar_icon_button_default"
    static let topBarSegment = "top_bar_segment_default"
    static let searchBarCompact = "search_bar_compact_default"
    static let tabBarMain = "tab_bar_main_default"
    static let tabBarItemDefault = "tab_bar_item_default"
    static let tabBarItemSelected = "tab_bar_item_selected"
    static let cardStatsDefault = "card_stats_default"
    static let cardWardrobeItem = "card_wardrobe_item_default"
    static let cardWardrobeRibbonTopLeft = "card_wardrobe_item_ribbon_top_left"
    static let cardSettingsGrid = "card_settings_grid_default"
    static let previewStoreHero = "preview_store_hero"

    static func capInsets(for name: String) -> EdgeInsets {
        switch name {
        case topBarMain:
            return EdgeInsets(top: 40, leading: 60, bottom: 40, trailing: 60)
        case tabBarMain:
            return EdgeInsets(top: 80, leading: 90, bottom: 80, trailing: 90)
        case searchBarCompact:
            return EdgeInsets(top: 30, leading: 60, bottom: 30, trailing: 60)
        case cardWardrobeItem:
            return EdgeInsets(top: 80, leading: 80, bottom: 80, trailing: 80)
        case cardStatsDefault:
            return EdgeInsets(top: 30, leading: 30, bottom: 30, trailing: 30)
        case cardSettingsGrid:
            return EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24)
        default:
            return EdgeInsets()
        }
    }
}

enum ThemeSkinAssetAvailability {
    static func hasImage(named name: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(named: name) != nil
        #else
        return false
        #endif
    }
}

struct ThemeSkinOptionalResizableAsset<Placeholder: View>: View {
    let name: String
    var capInsets: EdgeInsets
    var resizingMode: Image.ResizingMode
    private let placeholder: () -> Placeholder

    init(
        _ name: String,
        capInsets: EdgeInsets = EdgeInsets(),
        resizingMode: Image.ResizingMode = .stretch,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.name = name
        self.capInsets = capInsets
        self.resizingMode = resizingMode
        self.placeholder = placeholder
    }

    var body: some View {
        #if canImport(UIKit)
        if let image = UIImage(named: name) {
            Image(uiImage: image)
                .resizable(capInsets: capInsets, resizingMode: resizingMode)
        } else {
            placeholder()
        }
        #else
        placeholder()
        #endif
    }
}

struct ThemeSkinOptionalFittedAsset<Placeholder: View>: View {
    let name: String
    private let placeholder: () -> Placeholder

    init(
        _ name: String,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.name = name
        self.placeholder = placeholder
    }

    var body: some View {
        #if canImport(UIKit)
        if let image = UIImage(named: name) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            placeholder()
        }
        #else
        placeholder()
        #endif
    }
}
