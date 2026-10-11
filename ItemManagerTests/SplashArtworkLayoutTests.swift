import XCTest
import SwiftUI
@testable import ItemManager

final class SplashArtworkLayoutTests: XCTestCase {
    @MainActor
    func testThemeCannotOverrideSystemNavigation() {
        XCTAssertEqual(ThemeSkinSlot.allCases.count, 18, "保留历史 slot 存档结构")
        for id in ["theme_skin.sky_concert", "theme_skin.swan_dream"] {
            XCTAssertNil(ThemeSkinManager.shared.descriptor(forThemeId: id, slot: .tabBarMain))
            XCTAssertNil(ThemeSkinManager.shared.descriptor(forThemeId: id, slot: .tabBarItem))
            XCTAssertNotNil(ThemeSkinManager.shared.descriptor(forThemeId: id, slot: .sectionCard))
        }
    }

    @MainActor
    func testRenderPreservedArtworkAcrossWindowShapes() throws {
        for (name, size) in [("phone-folded", CGSize(width: 402, height: 820)),
                             ("pad-portrait", CGSize(width: 1024, height: 1300)),
                             ("pad-landscape", CGSize(width: 1366, height: 980)),
                             ("phone-unfolded", CGSize(width: 800, height: 700))] {
            let renderer = ImageRenderer(content: SplashScreenView().frame(width: size.width, height: size.height))
            let rendered = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(rendered.size, size)
            let attachment = XCTAttachment(image: rendered)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testCompleteArtworkFitsPhonePadAndFoldedWindowSizes() {
        let sizes = [CGSize(width: 402, height: 820), CGSize(width: 820, height: 360),
                     CGSize(width: 1024, height: 1300), CGSize(width: 1366, height: 980),
                     CGSize(width: 800, height: 700), CGSize(width: 360, height: 700),
                     CGSize(width: 600, height: 900)]
        for size in sizes {
            let layout = SplashArtworkLayout(availableSize: size)
            let title = SplashArtworkRegion.title.sourceRect.size
            let wardrobe = SplashArtworkRegion.wardrobe.sourceRect.size
            let enter = SplashArtworkRegion.enter.sourceRect.size
            let width = layout.isHorizontal ? (title.width + wardrobe.width) * layout.scale + layout.spacing
                : SplashArtworkRegion.sourceSize.width * layout.scale
            let height = layout.isHorizontal ? max(wardrobe.height, title.height + enter.height + 44) * layout.scale
                : SplashArtworkRegion.sourceSize.height * layout.scale
            XCTAssertGreaterThan(layout.scale, 0)
            XCTAssertLessThanOrEqual(width, size.width - 32 + 0.01)
            XCTAssertLessThanOrEqual(height, size.height - 32 + 0.01)
        }
        XCTAssertFalse(SplashArtworkLayout(availableSize: sizes[0]).isHorizontal)
        XCTAssertFalse(SplashArtworkLayout(availableSize: sizes[2]).isHorizontal)
        XCTAssertTrue(SplashArtworkLayout(availableSize: sizes[3]).isHorizontal)
        XCTAssertTrue(SplashArtworkLayout(availableSize: sizes[4]).isHorizontal)
    }
}
