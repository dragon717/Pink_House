import XCTest
import SwiftUI
import UIKit
import ImageIO
@testable import ItemManager

@MainActor
final class WardrobeStorageCustomIconTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var directory: URL!
    private var store: WardrobeStorageIconStore!
    private var settings: WardrobeStorageSettings!

    override func setUpWithError() throws {
        suite = "wardrobe-storage-custom-icon-tests-" + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        store = WardrobeStorageIconStore(directory: directory)
        settings = WardrobeStorageSettings(defaults: defaults, iconStore: store)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func testLegacyCabinetsWithoutImageFieldStillDecodeAndRetainMembers() throws {
        let id = UUID(), member = UUID()
        let legacy = """
        [{"id":"\(id)","name":"礼帽柜","icon":"hat","clothingIDs":["\(member)"]}]
        """
        defaults.set(Data(legacy.utf8), forKey: "wardrobe.storage.custom-cabinets.v1")
        let restored = WardrobeStorageSettings(defaults: defaults, iconStore: store)
        XCTAssertEqual(restored.cabinets.first?.id, id)
        XCTAssertEqual(restored.cabinets.first?.clothingIDs, [member])
        XCTAssertEqual(restored.cabinets.first?.icon, .hat)
        XCTAssertNil(restored.cabinets.first?.iconImageFile)
        XCTAssertTrue(restored.destinations.prefix(4).allSatisfy { $0.iconImageFile == nil })
    }

    func testPhotoSurvivesReloadRenameAndMembershipUpdatesWithoutChangingCabinetStyle() throws {
        let destination = try settings.saveCabinet(name: "出游包", icon: .bags, iconUpdate: .replace(fixture()))
        let id = try XCTUnwrap(destination.customID), file = try XCTUnwrap(destination.iconImageFile)
        let member = UUID()
        try settings.include(member, in: id)
        let restoredStore = WardrobeStorageIconStore(directory: directory)
        let restored = WardrobeStorageSettings(defaults: defaults, iconStore: restoredStore)
        let renamed = try restored.saveCabinet(id: id, name: "小包柜", icon: .bags)
        XCTAssertEqual(renamed.id, destination.id)
        XCTAssertEqual(renamed.iconImageFile, file)
        XCTAssertEqual(renamed.category, .bags)
        XCTAssertEqual(restored.cabinets.first?.clothingIDs, [member])
        XCTAssertNotNil(restoredStore.image(named: file))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [file])
    }

    func testReplacingPhotoAndReturningToBuiltInOnlyRemoveObsoleteOwnedImages() throws {
        let first = try settings.saveCabinet(name: "帽子柜", icon: .hat, iconUpdate: .replace(fixture()))
        let other = try settings.saveCabinet(name: "其他柜", icon: .star, iconUpdate: .replace(fixture()))
        let id = try XCTUnwrap(first.customID), old = try XCTUnwrap(first.iconImageFile)
        let replacement = try settings.saveCabinet(id: id, name: "帽子柜", icon: .hat, iconUpdate: .replace(fixture()))
        let new = try XCTUnwrap(replacement.iconImageFile)
        XCTAssertNotEqual(old, new)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(old).path))
        XCTAssertNil(store.image(named: old))
        let builtIn = try settings.saveCabinet(id: id, name: "帽子柜", icon: .star, iconUpdate: .useBuiltIn)
        XCTAssertNil(builtIn.iconImageFile)
        XCTAssertEqual(builtIn.icon, .star)
        XCTAssertNil(store.image(named: new))
        XCTAssertNotNil(store.image(named: try XCTUnwrap(other.iconImageFile)))
    }

    func testInvalidNameOrImageCannotReplaceSavedPhotoOrPreferences() throws {
        let destination = try settings.saveCabinet(name: "礼帽柜", icon: .hat, iconUpdate: .replace(fixture()))
        let id = try XCTUnwrap(destination.customID), file = try XCTUnwrap(destination.iconImageFile)
        let before = defaults.data(forKey: "wardrobe.storage.custom-cabinets.v1")
        let bytes = try Data(contentsOf: directory.appendingPathComponent(file))
        XCTAssertThrowsError(try settings.saveCabinet(id: id, name: "礼帽柜", icon: .star, iconUpdate: .replace(Data("bad image".utf8))))
        XCTAssertThrowsError(try settings.saveCabinet(id: id, name: "鞋柜", icon: .star, iconUpdate: .replace(fixture())))
        XCTAssertEqual(defaults.data(forKey: "wardrobe.storage.custom-cabinets.v1"), before)
        XCTAssertEqual(settings.cabinets.first?.iconImageFile, file)
        XCTAssertEqual(settings.cabinets.first?.icon, .hat)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(file)), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [file])
    }

    func testImageWriteFailureLeavesExistingCabinetAndPreferencesIntact() throws {
        let destination = try settings.saveCabinet(name: "礼帽柜", icon: .hat, iconUpdate: .replace(fixture()))
        let before = defaults.data(forKey: "wardrobe.storage.custom-cabinets.v1")
        let blocked = directory.appendingPathComponent("not-a-directory")
        try Data("owned test file".utf8).write(to: blocked)
        let failing = WardrobeStorageSettings(defaults: defaults, iconStore: WardrobeStorageIconStore(directory: blocked))
        XCTAssertThrowsError(try failing.saveCabinet(id: destination.customID, name: "新的名称", icon: .star, iconUpdate: .replace(fixture())))
        XCTAssertEqual(defaults.data(forKey: "wardrobe.storage.custom-cabinets.v1"), before)
        XCTAssertEqual(failing.cabinets.first?.name, "礼帽柜")
        XCTAssertNotNil(store.image(named: try XCTUnwrap(destination.iconImageFile)))
    }

    func testIconIsSmallSquareAndPreservesTransparencyAndSourceBytes() throws {
        let data = try fixture(size: CGSize(width: 640, height: 320), scale: 3)
        let before = data
        let file = try store.save(data)
        let fresh = WardrobeStorageIconStore(directory: directory)
        let image = try XCTUnwrap(fresh.image(named: file))
        XCTAssertEqual(image.cgImage?.width, 256)
        XCTAssertEqual(image.cgImage?.height, 256)
        XCTAssertEqual(image.scale, 1)
        XCTAssertEqual(try pixel(image, at: .zero)[3], 0)
        XCTAssertEqual(data, before)
        XCTAssertLessThanOrEqual(try Data(contentsOf: directory.appendingPathComponent(file)).count, 512 * 1024)
    }

    func testPhotoPreparationHonorsOrientationAndBoundsDecodedPixels() throws {
        let source = try XCTUnwrap(UIImage(data: fixture(size: CGSize(width: 1600, height: 800)))?.cgImage)
        let data = NSMutableData()
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, source, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        let decoded = try XCTUnwrap(WardrobeStorageIconStore.cropImage(from: data as Data))
        XCTAssertEqual(decoded.width, 512)
        XCTAssertEqual(decoded.height, 1024)
        XCTAssertNil(WardrobeStorageIconStore.cropImage(from: Data("not a photo".utf8)))
    }

    func testMissingOrUnsafePathsFallBackWithoutTouchingOtherFiles() throws {
        let file = try store.save(fixture())
        for unsafe in ["../" + file, "/" + file, "photo.png", file + "/.."] {
            XCTAssertNil(store.image(named: unsafe))
            store.remove(named: unsafe)
        }
        XCTAssertNotNil(store.image(named: file))
        XCTAssertNil(store.image(named: UUID().uuidString + ".png"))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("pink-house-storage-custom-icon-validation")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let photoData = try Data(contentsOf: directory.appendingPathComponent(file))
        for dark in [false, true] {
            let palette = WardrobeStoragePalette.resolve(dark: dark)
            let root = HStack(spacing: 16) {
                WardrobeStorageIcon(kind: .hat, size: 60, selected: true, imageData: photoData)
                WardrobeStorageIcon(kind: .hat, size: 60, imageFile: "../invalid.png")
                WardrobeStorageIcon(kind: .star, size: 60)
            }.padding(16).background(palette.label.color)
                .environment(\.wardrobeStoragePalette, palette).environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: root)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let center = try pixel(image, at: CGPoint(x: 46 * 2, y: 46 * 2))
            XCTAssertGreaterThan(center[0], 180, "The chosen photo must render, rather than the hat vector")
            XCTAssertLessThan(center[2], 100)
            let name = "custom-icons-\(dark ? "dark" : "light").png"
            try XCTUnwrap(image.pngData()).write(to: output.appendingPathComponent(name))
            let attachment = XCTAttachment(image: image)
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    private func fixture(size: CGSize = CGSize(width: 512, height: 512), scale: CGFloat = 1) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale; format.opaque = false; format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor(red: 0.85, green: 0.18, blue: 0.22, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.1, dy: size.height * 0.1), cornerRadius: 40).fill()
        }
        return try XCTUnwrap(image.pngData())
    }

    private func pixel(_ image: UIImage, at point: CGPoint) throws -> [UInt8] {
        let source = try XCTUnwrap(image.cgImage)
        let pixel = try XCTUnwrap(source.cropping(to: CGRect(origin: point, size: CGSize(width: 1, height: 1))))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return rgba
    }
}
