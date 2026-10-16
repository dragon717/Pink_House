import SwiftUI
import UIKit
import XCTest
@testable import ItemManager

@MainActor
final class BackgroundImageOpacityTests: XCTestCase {
    private var savedDefaults: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        savedDefaults = UserDefaults.standard.dictionaryRepresentation().filter { Self.isThemeKey($0.key) }
        UserDefaults.standard.removeObject(forKey: "theme_skin.active_selection")
        ThemeSkinManager.shared.reloadFromDisk(applyBackgroundHarmony: false)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys.filter({ Self.isThemeKey($0) }) {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in savedDefaults { defaults.set(value, forKey: key) }
        ThemeSkinManager.shared.reloadFromDisk(applyBackgroundHarmony: false)
        super.tearDown()
    }

    func testAppBackgroundFadesWithoutThemeTintForFilledAndTiledImages() throws {
        try assertNeutralFade { LiquidBackground().environment($0) }
    }

    func testShareBackgroundFadesWithoutThemeTint() throws {
        try assertNeutralFade { ShareCardBackground().environment($0) }
    }

    func testSolidColorAndMissingImageKeepSelectedBackgroundColor() throws {
        let theme = ThemeManager()
        theme.backgroundColorHex = "#FF00AA"
        for style in BackgroundStyle.allCases {
            theme.backgroundStyle = style
            theme.backgroundImage = nil
            for scheme in [ColorScheme.light, .dark] {
                let pixel = try renderPixel(theme.backgroundBaseColor(for: scheme), scheme: scheme)
                XCTAssertEqual(pixel[0], 255, accuracy: 2)
                XCTAssertEqual(pixel[1], 0, accuracy: 2)
                XCTAssertEqual(pixel[2], 170, accuracy: 2)
            }
        }
    }

    private func assertNeutralFade<V: View>(@ViewBuilder background: (ThemeManager) -> V) throws {
        let theme = ThemeManager()
        theme.backgroundStyle = .image
        theme.isBlurEnabled = false
        // A gray source makes any color leaked from the underlying theme detectable.
        for size in [CGSize(width: 100, height: 100), CGSize(width: 8, height: 8)] {
            theme.backgroundImage = UIGraphicsImageRenderer(size: size).image { context in
                UIColor(white: 0.25, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            for scheme in [ColorScheme.light, .dark] {
                for color in ["#F4DADB", "#00FF00"] {
                    theme.backgroundColorHex = color
                    var levels: [Double] = []
                    for opacity in [0.0, 0.53, 1.0] {
                        theme.backgroundOpacity = opacity
                        let pixel = try renderPixel(background(theme), scheme: scheme)
                        XCTAssertEqual(pixel[0], pixel[1], accuracy: 2, "Image opacity must not add theme tint")
                        XCTAssertEqual(pixel[1], pixel[2], accuracy: 2, "Image opacity must not add theme tint")
                        levels.append(pixel[0])
                    }
                    XCTAssertEqual(levels[0], scheme == .dark ? 0 : 255, accuracy: 2)
                    if scheme == .light {
                        XCTAssertGreaterThan(levels[0], levels[1])
                        XCTAssertGreaterThan(levels[1], levels[2])
                    } else {
                        XCTAssertLessThan(levels[0], levels[1])
                        XCTAssertLessThan(levels[1], levels[2])
                    }
                }
            }
        }
    }

    private func renderPixel<V: View>(_ view: V, scheme: ColorScheme) throws -> [Double] {
        let renderer = ImageRenderer(content: view.frame(width: 40, height: 40).environment(\.colorScheme, scheme))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        let center = try XCTUnwrap(image.cropping(to: CGRect(x: 20, y: 20, width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(center, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return rgba.map(Double.init)
    }

    private static func isThemeKey(_ key: String) -> Bool {
        key.hasPrefix("theme_") || key == "pet_chat_skin_theme" || key == "app_theme_version" ||
            key == "UserPreference_WardrobeNavigationStyle"
    }
}
