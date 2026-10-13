import XCTest
import SwiftUI
import UIKit
@testable import ItemManager

@MainActor
final class WardrobeStorageAppearanceTests: XCTestCase {
    func testSmallTextRemainsReadableWithAnyThemeAccent() {
        let accents = [WardrobeStorageRGB(hex: 0x000000), .init(hex: 0xFFFFFF), .init(hex: 0xFFB6C1),
                       .init(hex: 0x224422), .init(hex: 0x777777), .init(hex: 0xFFFF00)]
        for dark in [false, true] {
            for increased in [false, true] {
                for accent in accents {
                    let palette = WardrobeStoragePalette.resolve(dark: dark, increasedContrast: increased, accent: accent)
                    for foreground in [palette.primary, palette.secondary, palette.accent] {
                        for surface in palette.textSurfaces {
                            XCTAssertGreaterThanOrEqual(foreground.contrast(against: surface), increased ? 8.99 : 6.99)
                        }
                    }
                }
            }
        }
    }

    func testDarkModeAndContrastChangesRecomputeWithoutChangingStoredAccent() {
        let theme = WardrobeStorageRGB(hex: 0xFFB6C1)
        let light = WardrobeStoragePalette.resolve(dark: false, accent: theme)
        let dark = WardrobeStoragePalette.resolve(dark: true, accent: theme)
        XCTAssertLessThan(dark.scene.luminance, 0.02)
        XCTAssertGreaterThan(light.scene.luminance, 0.8)
        XCTAssertNotEqual(light.accent, dark.accent)
        XCTAssertEqual(theme, WardrobeStorageRGB(hex: 0xFFB6C1))
        XCTAssertEqual(light, WardrobeStoragePalette.resolve(dark: false, accent: theme))
        let increased = WardrobeStoragePalette.resolve(dark: true, increasedContrast: true, accent: theme)
        XCTAssertGreaterThan(increased.border.contrast(against: increased.rear), dark.border.contrast(against: dark.rear))
    }

    func testInvalidColorChannelsCannotProduceInvalidContrast() {
        let invalid = WardrobeStorageRGB(.nan, -.infinity, 8)
        XCTAssertEqual(invalid, WardrobeStorageRGB(0, 0, 1))
        let palette = WardrobeStoragePalette.resolve(dark: true, accent: invalid)
        XCTAssertTrue(palette.accent.luminance.isFinite)
        XCTAssertGreaterThanOrEqual(palette.accent.contrast(against: palette.label), 7)
    }

    /// Capture the real SwiftUI GPU composition; no records are inserted into SwiftData.
    func testRenderShelfLightingAndPricePrivacyForVisualInspection() async throws {
        let imageDirectory = ImageManager.shared.imagesDirectory
        let prefix = "storage-lighting-test-" + UUID().uuidString
        var files: [URL] = []
        defer { files.forEach { try? FileManager.default.removeItem(at: $0) } }
        let names = ["storage_shoes_sneakers", "storage_shoes_black", "storage_bags_blush", "storage_accessories_bow"]
        var entries: [WardrobeStorageEntry] = []
        for (index, name) in names.enumerated() {
            let image = try XCTUnwrap(UIImage(named: name))
            let file = imageDirectory.appendingPathComponent(prefix + "-\(index).png")
            try XCTUnwrap(image.pngData()).write(to: file)
            files.append(file)
            entries.append(WardrobeStorageEntry(id: "fixture-\(index)", title: ["白色鞋款", "黑色鞋款", "粉色包包", "蝴蝶结配饰"][index],
                category: index < 2 ? .shoes : index == 2 ? .bags : .accessories,
                searchTerms: "", originalImagePath: nil, cutoutImagePath: file.lastPathComponent,
                price: 280 + Decimal(index) * 40, quantity: 1, clothing: nil))
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("pink-house-storage-lighting-validation")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        for dark in [false, true] {
            for showPrice in [true, false] {
                let palette = WardrobeStoragePalette.resolve(dark: dark)
                let root = VStack(spacing: 12) {
                    HStack(spacing: 14) {
                        ForEach(WardrobeStorageIconKind.allCases) { kind in WardrobeStorageIcon(kind: kind, size: 30) }
                    }
                    Text(dark ? "夜间收纳柜" : "日间收纳柜").font(.headline).foregroundStyle(palette.primary.color)
                    WardrobeStorageShelf(category: .shoes, entries: Array(entries.prefix(2)), width: 350, number: 1, showPrice: showPrice, onSelect: { _ in })
                    WardrobeStorageShelf(category: .bags, entries: [entries[2]], width: 350, number: 2, showPrice: showPrice, onSelect: { _ in })
                    WardrobeStorageShelf(category: .accessories, entries: [entries[3]], width: 350, number: 3, showPrice: showPrice, onSelect: { _ in })
                    WardrobeStorageShelf(category: .shoes, entries: [], width: 350, number: 4, showPrice: showPrice, onSelect: { _ in })
                }.padding(20).frame(width: 390, height: 800).background(palette.rear.color)
                    .environment(\.wardrobeStoragePalette, palette).environment(\.colorScheme, dark ? .dark : .light)
                let host = UIHostingController(rootView: root)
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(800))
                let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
                let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let filename = "\(dark ? "dark" : "light")-shelves-price-\(showPrice ? "visible" : "hidden").png"
                try XCTUnwrap(image.pngData()).write(to: output.appendingPathComponent(filename))
                let attachment = XCTAttachment(image: image)
                attachment.name = filename; attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
