import XCTest
import SwiftUI
import SwiftData
import UIKit
@testable import ItemManager

@MainActor
final class WardrobeStorageThemeTests: XCTestCase {
    private func withTheme<T>(_ work: (ThemeManager) throws -> T) rethrows -> T {
        let defaults = UserDefaults.standard
        let before = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("theme_") || $0.key == "pet_chat_skin_theme" }
        defer {
            let keys = Set(before.keys).union(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("theme_") || $0 == "pet_chat_skin_theme" })
            for key in keys {
                if let value = before[key] { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        return try work(ThemeManager())
    }

    private func assertRGB(_ actual: WardrobeStorageRGB, _ expected: WardrobeStorageRGB,
                           file: StaticString = #filePath, line: UInt = #line) {
        // UIColor bridges components through Float; sub-pixel conversion noise is expected.
        XCTAssertEqual(actual.r, expected.r, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(actual.g, expected.g, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(actual.b, expected.b, accuracy: 0.000001, file: file, line: line)
    }

    private func configure(_ manager: ThemeManager, preset: ThemePreset) {
        var config = manager.themeColorConfig
        config.colorSchemeMode = .custom
        config.followSystemDarkMode = true
        config.customColorConfig.selectedPresetId = preset.id
        var custom = config.customColorConfig.currentCustom
        custom.textPrimaryRGBA = preset.textPrimaryRGBA
        custom.textSecondaryRGBA = preset.textSecondaryRGBA
        custom.textTertiaryRGBA = preset.textTertiaryRGBA
        custom.textAccentRGBA = preset.textAccentRGBA
        custom.cardConfig = preset.cardConfig
        custom.darkTextPrimaryRGBA = preset.darkTextPrimaryRGBA ?? preset.textPrimaryRGBA
        custom.darkTextSecondaryRGBA = preset.darkTextSecondaryRGBA ?? preset.textSecondaryRGBA
        custom.darkTextTertiaryRGBA = preset.darkTextTertiaryRGBA ?? preset.textTertiaryRGBA
        custom.darkTextAccentRGBA = preset.darkTextAccentRGBA ?? preset.textAccentRGBA
        custom.darkCardConfig = preset.darkCardConfig ?? preset.cardConfig
        config.customColorConfig.currentCustom = custom
        manager.themeColorConfig = config
    }

    func testEveryPresetSuppliesItsOwnCardAndTextColorsInBothSchemes() throws {
        try withTheme { manager in
            for preset in CustomColorPresets.all {
                configure(manager, preset: preset)
                for scheme in [ColorScheme.light, .dark] {
                    let palette = WardrobeStoragePalette.themed(manager, scheme: scheme, contrast: .standard)
                    let card = preset.cardColors(forDarkMode: scheme == .dark).backgroundRGBA
                    assertRGB(palette.card, WardrobeStorageRGB(card.r, card.g, card.b))
                    let source = manager.getPaletteForContainer(containerBackground: .solid(color: manager.cardSurfaceColor(for: scheme)), colorScheme: scheme)
                    let sourceAccent = try XCTUnwrap(source.accent.rgba)
                    // The actual theme accent is the input; only insufficient contrast changes it.
                    let expected = WardrobeStorageRGB(sourceAccent.r, sourceAccent.g, sourceAccent.b)
                        .ensuringContrast(on: palette.textSurfaces, dark: palette.label.luminance < 0.18, minimum: 7)
                    assertRGB(palette.accent, expected)
                    for text in [palette.primary, palette.secondary, palette.accent] {
                        for surface in palette.textSurfaces { XCTAssertGreaterThanOrEqual(text.contrast(against: surface), 6.99) }
                    }
                }
            }
        }
    }

    func testMagicBackgroundAndTintChangesPropagateWithoutUsingStorageSwatches() throws {
        try withTheme { manager in
            manager.colorSchemeMode = .magic
            manager.backgroundColorHex = "#165C45"
            manager.cardTintColorHex = "#0099CC"
            let green = WardrobeStoragePalette.themed(manager, scheme: .dark, contrast: .standard)
            assertRGB(green.scene, WardrobeStorageRGB(hex: 0x165C45))
            XCTAssertEqual(green.card, green.scene)
            manager.backgroundColorHex = "#182953"
            manager.cardTintColorHex = "#EC8C2D"
            let blue = WardrobeStoragePalette.themed(manager, scheme: .dark, contrast: .standard)
            assertRGB(blue.scene, WardrobeStorageRGB(hex: 0x182953))
            XCTAssertNotEqual(green.card, blue.card)
            XCTAssertNotEqual(green.accent, blue.accent)
            let lightCard = try XCTUnwrap(manager.cardSurfaceColor(for: .light).rgba)
            XCTAssertEqual(lightCard.a, 0.95, accuracy: 0.001)
        }
    }

    func testMidToneThemeKeepsItsSurfaceWhileReadingPlatesStayLegible() {
        for value in stride(from: 0.1, through: 0.9, by: 0.1) {
            let surface = WardrobeStorageRGB(value, value, value)
            for increased in [false, true] {
                let palette = WardrobeStoragePalette.fromUnified(dark: true, increasedContrast: increased,
                    scene: surface, surface: surface, primary: surface, secondary: surface, accent: surface)
                XCTAssertEqual(palette.scene, surface)
                XCTAssertEqual(palette.card, surface)
                for text in [palette.primary, palette.secondary, palette.accent] {
                    for plate in palette.textSurfaces {
                        XCTAssertGreaterThanOrEqual(text.contrast(against: plate), increased ? 8.99 : 6.99)
                    }
                }
            }
        }
    }

    /// Exercise the full room with a synthetic wallpaper, never insert example inventory.
    func testRenderUnifiedThemesAndWallpaperInEmptyRoom() async throws {
        let defaults = UserDefaults.standard
        let before = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("theme_") || $0.key == "pet_chat_skin_theme" }
        defer {
            let keys = Set(before.keys).union(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("theme_") || $0 == "pet_chat_skin_theme" })
            for key in keys {
                if let value = before[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        let manager = ThemeManager()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Clothing.self, CutoutItem.self, configurations: configuration)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 850)
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("pink-house-storage-theme-validation")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let wallpaper = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 850)).image { context in
            UIColor(red: 0.14, green: 0.35, blue: 0.55, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 390, height: 850))
            UIColor(red: 0.58, green: 0.80, blue: 0.67, alpha: 1).setFill()
            for y in stride(from: 0, to: 850, by: 120) { context.fill(CGRect(x: 0, y: y, width: 390, height: 60)) }
        }
        let cases: [(String, String, ColorScheme, Bool)] = [
            ("preset-blue-light", "cinderella", .light, false), ("preset-green-dark", "matcha", .dark, false),
            ("wallpaper-light", "cinderella", .light, true), ("wallpaper-dark", "cinderella", .dark, true)
        ]
        for (name, presetID, scheme, imageBackground) in cases {
            configure(manager, preset: try XCTUnwrap(CustomColorPresets.all.first { $0.id == presetID }))
            manager.backgroundColorHex = imageBackground ? "#182953" : "#E4EEE9"
            manager.cardStyle = imageBackground ? .fullyTransparent : .tinted
            manager.tintOpacity = 0.55
            manager.isBlurEnabled = false
            manager.backgroundStyle = imageBackground ? .image : .color
            manager.backgroundImage = imageBackground ? wallpaper : nil
            manager.backgroundOpacity = 0.8
            let root = NavigationStack {
                WardrobeStorageRoomView(destination: WardrobeStorageDestination(.shoes))
            }.modelContainer(container).environment(manager).preferredColorScheme(scheme)
            window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
            let host = UIHostingController(rootView: root)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(700))
            var rendered = false
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            XCTAssertTrue(rendered)
            if imageBackground {
                // Sample the wallpaper at the left edge, away from labels and furniture.
                // Both colored bands differ from the plain navy fallback by this margin.
                let cgImage = try XCTUnwrap(image.cgImage)
                let pixel = try XCTUnwrap(cgImage.cropping(to: CGRect(x: 3 * image.scale, y: 600 * image.scale, width: 1, height: 1)))
                var rgba = [UInt8](repeating: 0, count: 4)
                let sampled = rgba.withUnsafeMutableBytes { bytes -> Bool in
                    guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                        bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                    context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                    return true
                }
                XCTAssertTrue(sampled)
                XCTAssertGreaterThan(Int(rgba[1]) - Int(rgba[0]), 22, "Theme wallpaper must remain visible: \(name), \(rgba)")
            }
            try XCTUnwrap(image.pngData()).write(to: output.appendingPathComponent(name + ".png"))
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
