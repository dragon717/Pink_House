import XCTest
import SwiftUI
import UIKit
@testable import ItemManager

@MainActor
final class ShopCatalogCoverImageTests: XCTestCase {
    func testAssetIDCoverActuallyRendersUploadedPixels() async throws {
        let original = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let reference = try XCTUnwrap(ShopCatalogImageStore.save(try XCTUnwrap(original.pngData())))
        let file = try XCTUnwrap(ShopCatalogImageStore.url(for: reference))
        defer { try? FileManager.default.removeItem(at: file) }
        let asset = CatalogAsset(id: "uploaded-cover-id", type: .productImage, originalURL: reference)
        let store = ShopCatalogStore(catalog: ShopCatalog(assets: [asset]))
        let view = ShopCatalogAssetImage(reference: asset.id, store: store)
        XCTAssertEqual(view.resolvedSource.references, [reference])
        let renderer = ImageRenderer(content: view.frame(width: 32, height: 32))
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        XCTAssertGreaterThan(pixel[0], 230)
        XCTAssertLessThan(pixel[1], 30, "资源 ID 必须显示红色原图，不能落进灰色照片占位")
        XCTAssertLessThan(pixel[2], 30)
    }

    func testSameCoverIDReloadsSourceAfterRemoteCatalogUpdate() async throws {
        let oldHash = String(repeating: "a", count: 64)
        let newHash = String(repeating: "b", count: 64)
        let oldAsset = CatalogAsset(id: "cover", type: .productImage, originalURL: "thmedia:" + oldHash, mediaKey: oldHash)
        let newAsset = CatalogAsset(id: "cover", type: .productImage, originalURL: "thmedia:" + newHash, mediaKey: newHash)
        let store = ShopCatalogStore(catalog: ShopCatalog(assets: [oldAsset]))
        let view = ShopCatalogAssetImage(reference: "cover", store: store)
        let before = view.resolvedSource
        XCTAssertEqual(before.mediaKey, oldHash)
        store.installRemoteCatalog(ShopCatalog(assets: [newAsset]))
        XCTAssertEqual(view.resolvedSource.mediaKey, newHash)
        XCTAssertNotEqual(view.resolvedSource, before, "task identity 必须包含资源解析结果，不能只用不变的 cover ID")
    }

    func testCanonicalOnlyCoverAndLegacyDirectReferenceRemainReadable() async throws {
        let hash = String(repeating: "c", count: 64)
        let asset = CatalogAsset(id: "cover", type: .productImage, originalURL: "", mediaKey: hash)
        let store = ShopCatalogStore(catalog: ShopCatalog(assets: [asset]))
        XCTAssertEqual(ShopCatalogAssetImage(reference: "cover", store: store).resolvedSource.mediaKey, hash)
        XCTAssertEqual(ShopCatalogAssetImage(reference: "bundle:old-cover.jpg", store: store).resolvedSource.references,
                       ["bundle:old-cover.jpg"])
        XCTAssertTrue(ShopCatalogAssetImage(reference: nil, store: store).resolvedSource.references.isEmpty)
    }
}
