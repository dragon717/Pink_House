import SwiftUI
import UIKit
import XCTest
@testable import ItemManager

@MainActor
final class ChartImageViewerTests: XCTestCase {
    func testChartPreviewHasImageOnFirstLayoutEvenWithoutSourceFile() throws {
        let image = chartImage(color: .systemPink)
        let host = UIHostingController(rootView: ChartImageViewer(
            preview: ChartImagePreview(imagePath: "missing-\(UUID()).jpg", image: image),
            onDismiss: {}
        ))
        let window = mount(host)
        defer { window.isHidden = true }

        // 不等待异步读取或下一轮 run loop：第一次布局必须已经有图。
        let imageView = try XCTUnwrap(descendant(UIImageView.self, in: host.view))
        XCTAssertTrue(imageView.image === image)
        XCTAssertGreaterThan(imageView.bounds.width, 0)
        XCTAssertGreaterThan(imageView.bounds.height, 0)
    }

    func testSwitchingFromSizeToPriceChartReplacesImageAndResetsZoom() throws {
        let sizeImage = chartImage(color: .systemPink)
        let priceImage = chartImage(color: .systemBlue)
        let host = UIHostingController(rootView: ZoomableImageView(
            imagePath: "size-chart.jpg", preloadedImage: sizeImage
        ))
        let window = mount(host)
        defer { window.isHidden = true }
        let scrollView = try XCTUnwrap(descendant(UIScrollView.self, in: host.view))
        scrollView.setZoomScale(3, animated: false)

        host.rootView = ZoomableImageView(imagePath: "price-chart.jpg", preloadedImage: priceImage)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let imageView = try XCTUnwrap(descendant(UIImageView.self, in: host.view))
        XCTAssertTrue(imageView.image === priceImage)
        XCTAssertEqual(scrollView.zoomScale, 1)
    }

    func testFullResolutionImageUpdatesWithoutResettingCurrentZoom() throws {
        let thumbnail = chartImage(color: .systemPink)
        let original = chartImage(color: .systemBlue)
        let host = UIHostingController(rootView: ZoomableImageView(
            imagePath: "same-chart.jpg", preloadedImage: thumbnail
        ))
        let window = mount(host)
        defer { window.isHidden = true }
        let scrollView = try XCTUnwrap(descendant(UIScrollView.self, in: host.view))
        scrollView.setZoomScale(3, animated: false)

        host.rootView = ZoomableImageView(imagePath: "same-chart.jpg", preloadedImage: original)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let imageView = try XCTUnwrap(descendant(UIImageView.self, in: host.view))
        XCTAssertTrue(imageView.image === original)
        XCTAssertEqual(scrollView.zoomScale, 3)
    }

    private func chartImage(color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 240, height: 320)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 320))
        }
    }

    private func mount<V: View>(_ host: UIHostingController<V>) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        return window
    }

    private func descendant<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.descendant(type, in: $0) }.first
    }
}
