import XCTest
import SwiftUI
import UIKit
import Combine
@testable import ItemManager

@MainActor
final class WardrobeStorageCabinetFrameTests: XCTestCase {
    func testInventoryAddsOnlyMiddleBaysAndNeverLeavesAGapAboveBase() {
        for category in WardrobeStorageCategory.allCases {
            for size in [CGSize(width: 300, height: 600), CGSize(width: 190, height: 900)] {
                let layout = WardrobeStorageCabinetLayout(size: size, category: category)
                let emptyRows = layout.rowCount(for: 0)
                XCTAssertEqual(layout.rowCount(for: 1), emptyRows)
                XCTAssertEqual(layout.rowCount(for: emptyRows * 2), emptyRows)
                XCTAssertEqual(layout.rowCount(for: emptyRows * 2 + 1), emptyRows + 1)
                XCTAssertEqual(layout.rowCount(for: 101), 51)
                XCTAssertGreaterThanOrEqual(CGFloat(emptyRows) * layout.shelfHeight, layout.viewportHeight)
                XCTAssertEqual(layout.crownHeight + layout.viewportHeight + layout.baseHeight + 30, size.height, accuracy: 0.001)
            }
        }
    }

    func testCompactRoomsPreserveBothEndsAndOneFullBayWithoutOverflow() {
        for category in WardrobeStorageCategory.allCases {
            for size in [CGSize(width: 520, height: 240), CGSize(width: 280, height: 180)] {
                let layout = WardrobeStorageCabinetLayout(size: size, category: category)
                XCTAssertLessThanOrEqual(layout.width + 28, size.width)
                XCTAssertGreaterThanOrEqual(layout.viewportHeight + 0.001, layout.shelfHeight)
                XCTAssertEqual(layout.crownHeight / layout.width, 281.0 / 780, accuracy: 0.001)
                XCTAssertEqual(layout.baseHeight / layout.width, 274.0 / 780, accuracy: 0.001)
                XCTAssertEqual(layout.crownHeight + layout.viewportHeight + layout.baseHeight + 30, size.height, accuracy: 0.001)
            }
        }
    }

    /// Verify actual GPU-rendered ends remain unchanged when inventory grows and scrolls.
    /// Fixtures exist only in this hosting window; no user records or photos are changed.
    func testRenderedCrownAndBaseStayFixedWhileLastInventoryRowIsReachable() async throws {
        let size = CGSize(width: 320, height: 640)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("pink-house-storage-fixed-frame-validation")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for (category, dark) in [(WardrobeStorageCategory.shoes, false), (.bags, true)] {
            let layout = WardrobeStorageCabinetLayout(size: size, category: category)
            let control = CabinetScrollControl()
            let entries = (1...24).map { number in
                WardrobeStorageEntry(id: "frame-test-\(number)", title: "收藏 \(number)", category: category,
                    searchTerms: "", originalImagePath: nil, cutoutImagePath: nil, price: Decimal(number * 20), quantity: 1, clothing: nil)
            }
            let palette = WardrobeStoragePalette.resolve(dark: dark)
            func install(_ inventory: [WardrobeStorageEntry]) async throws {
                let root = CabinetScrollFixture(control: control, entries: inventory, category: category, size: size)
                    .environment(\.wardrobeStoragePalette, palette)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .transaction { $0.animation = nil }
                    .background(Color.cyan).ignoresSafeArea()
                let host = UIHostingController(rootView: root)
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(600))
            }
            func capture(_ stage: String) throws -> UIImage {
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let name = "\(category.rawValue)-\(dark ? "dark" : "light")-\(stage).png"
                try XCTUnwrap(image.pngData()).write(to: output.appendingPathComponent(name))
                let attachment = XCTAttachment(image: image)
                attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                return image
            }
            try await install(Array(entries.prefix(2)))
            let few = try capture("2-items")
            try await install(entries)
            let first = try capture("24-items-first")
            control.atEnd = true
            try await Task.sleep(for: .milliseconds(600))
            let last = try capture("24-items-last")

            // The moving shelf can change the cast shadow below the curved crown.
            // Compare the carved end itself, excluding that adjacent shadow region.
            let crownBand = CGRect(x: 14, y: 12, width: size.width - 28, height: layout.crownHeight - 24)
            let baseBand = CGRect(x: 14, y: size.height - 18 - layout.baseHeight + 32,
                                  width: size.width - 28, height: layout.baseHeight - 32)
            for band in [crownBand, baseBand] {
                let baseline = try pixels(few, in: band)
                XCTAssertEqual(baseline, try pixels(first, in: band), "Inventory moved or changed an end of \(category)")
                XCTAssertEqual(baseline, try pixels(last, in: band), "Scrolling moved or changed an end of \(category)")
            }
            let viewport = CGRect(x: 50, y: 14 + layout.crownHeight, width: 220, height: layout.viewportHeight - 4)
            XCTAssertNotEqual(try pixels(first, in: viewport), try pixels(last, in: viewport), "Middle shelves did not scroll")
            let scroll = try XCTUnwrap(findScrollView(in: try XCTUnwrap(window.rootViewController?.view)))
            XCTAssertEqual(scroll.contentOffset.y + scroll.bounds.height - scroll.adjustedContentInset.bottom,
                           scroll.contentSize.height, accuracy: 2, "The last stored row must be fully reachable")

            let column = CGRect(x: 14 + layout.width * 0.055, y: 12 + layout.crownHeight + 2,
                                width: layout.width * 0.05, height: layout.viewportHeight - 4)
            let fixedColumn = try pixels(first, in: column)
            // Color.cyan is a system color; sample its actual RGB instead of assuming 0/255/255.
            let wallpaperRGB = Array(try pixels(first, in: CGRect(x: 0, y: 0, width: 1, height: 1)).prefix(3))
            for (stage, offset) in [("overscroll-top", CGFloat(-72)),
                                     ("overscroll-bottom", scroll.contentSize.height - scroll.bounds.height + 72)] {
                scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                // Capture the pull before the system's next run-loop snaps it back to a bay.
                scroll.layoutIfNeeded()
                XCTAssertEqual(scroll.contentOffset.y, offset, accuracy: 2, "Fixture must actually expose elastic overscroll")
                let pulled = try capture(stage)
                XCTAssertEqual(scroll.contentOffset.y, offset, accuracy: 2, "Capture must retain the pulled position")
                let currentColumn = try pixels(pulled, in: column)
                XCTAssertEqual(fixedColumn.count, currentColumn.count)
                // Native GPU compositing rounds the same fixed artwork by up to two levels.
                let difference = zip(fixedColumn, currentColumn).map { abs(Int($0) - Int($1)) }.max() ?? 0
                XCTAssertLessThanOrEqual(difference, 3, "Cabinet posts must remain attached")
                let bay = CGRect(x: 14 + layout.width * 0.2, y: 12 + layout.crownHeight + 2,
                                 width: layout.width * 0.6, height: layout.viewportHeight - 4)
                let data = try pixels(pulled, in: bay)
                let exposedWallpaper = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                    stride(from: 0, to: bytes.count, by: 4).contains { index in
                        (0..<3).allSatisfy { abs(Int(bytes[index + $0]) - Int(wallpaperRGB[$0])) <= 2 }
                    }
                }
                XCTAssertFalse(exposedWallpaper, "\(stage) detached the cabinet and exposed the cyan room wallpaper")
            }
        }
    }

    private func pixels(_ image: UIImage, in rect: CGRect) throws -> Data {
        let scale = image.scale
        let source = try XCTUnwrap(image.cgImage)
        let crop = try XCTUnwrap(source.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                                         width: rect.width * scale, height: rect.height * scale)))
        var data = Data(count: crop.width * crop.height * 4)
        try data.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        }
        return data
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap(findScrollView).first
    }
}

@MainActor
private final class CabinetScrollControl: ObservableObject {
    @Published var atEnd = false
}

private struct CabinetScrollFixture: View {
    @ObservedObject var control: CabinetScrollControl
    let entries: [WardrobeStorageEntry]
    let category: WardrobeStorageCategory
    let size: CGSize

    var body: some View {
        ScrollViewReader { proxy in
            WardrobeStorageCabinet(category: category, entries: entries, width: size.width, height: size.height, showPrice: true, onSelect: { _ in })
                .onChange(of: control.atEnd) { _, atEnd in
                    if atEnd { proxy.scrollTo((entries.count - 1) / 2, anchor: .bottom) }
                }
        }
    }
}
