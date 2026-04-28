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
    static func hasImage(
        named name: String,
        namespace: String? = nil,
        allowShortNameFallback: Bool = true
    ) -> Bool {
        #if canImport(UIKit)
        return ThemeSkinAssetResolver.image(
            named: name,
            namespace: namespace,
            allowShortNameFallback: allowShortNameFallback
        ) != nil
        #else
        return false
        #endif
    }
}

#if canImport(UIKit)
enum ThemeSkinAssetResolver {
    static func image(
        named name: String,
        namespace: String? = nil,
        allowShortNameFallback: Bool = true
    ) -> UIImage? {
        for candidate in candidateNames(
            for: name,
            namespace: namespace,
            allowShortNameFallback: allowShortNameFallback
        ) {
            if let image = UIImage(named: candidate) {
                return image
            }
        }
        return nil
    }

    private static func candidateNames(
        for name: String,
        namespace: String?,
        allowShortNameFallback: Bool
    ) -> [String] {
        guard let namespace, !namespace.isEmpty else {
            return [name]
        }

        let prefixedName = "\(namespace)_\(name)"
        var names: [String] = []

        if name.hasPrefix("\(namespace)_") {
            names.append(name)
        } else {
            names.append(prefixedName)
        }

        if allowShortNameFallback {
            names.append(name)
        }

        return names.reduce(into: [String]()) { result, candidate in
            if !result.contains(candidate) {
                result.append(candidate)
            }
        }
    }
}
#endif

struct ThemeSkinOptionalResizableAsset<Placeholder: View>: View {
    let name: String
    let namespace: String?
    let allowShortNameFallback: Bool
    var capInsets: EdgeInsets
    var resizingMode: Image.ResizingMode
    private let placeholder: () -> Placeholder

    init(
        _ name: String,
        namespace: String? = nil,
        allowShortNameFallback: Bool = true,
        capInsets: EdgeInsets = EdgeInsets(),
        resizingMode: Image.ResizingMode = .stretch,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.name = name
        self.namespace = namespace
        self.allowShortNameFallback = allowShortNameFallback
        self.capInsets = capInsets
        self.resizingMode = resizingMode
        self.placeholder = placeholder
    }

    var body: some View {
        #if canImport(UIKit)
        if let image = ThemeSkinAssetResolver.image(
            named: name,
            namespace: namespace,
            allowShortNameFallback: allowShortNameFallback
        ) {
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
    let namespace: String?
    let allowShortNameFallback: Bool
    private let placeholder: () -> Placeholder

    init(
        _ name: String,
        namespace: String? = nil,
        allowShortNameFallback: Bool = true,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.name = name
        self.namespace = namespace
        self.allowShortNameFallback = allowShortNameFallback
        self.placeholder = placeholder
    }

    var body: some View {
        #if canImport(UIKit)
        if let image = ThemeSkinAssetResolver.image(
            named: name,
            namespace: namespace,
            allowShortNameFallback: allowShortNameFallback
        ) {
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
