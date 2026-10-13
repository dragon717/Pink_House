import XCTest
import UIKit
import ImageIO
import CryptoKit
@testable import ItemManager

@MainActor
final class WardrobeStorageCutoutTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("storage-cutout-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testWhiteAndNearWhiteBackgroundsBothPreserveWhiteSubjectInteriors() async throws {
        for shade in [CGFloat(1), CGFloat(0.955)] {
            let input = Self.fixture(background: shade)
            let output = await Task.detached { WardrobeStorageCutoutProcessor.process(input, lift: { _ in nil }) }.value
            let image = try XCTUnwrap(output.flatMap(WardrobeStorageCutoutProcessor.decode))
            let pixels = try XCTUnwrap(WardrobeStorageCutoutProcessor.Pixels(image))
            XCTAssertTrue(pixels.isCutout)
            XCTAssertEqual(image.width, 84)
            XCTAssertEqual(image.height, 64)
            XCTAssertEqual(pixels.rgba[(image.height / 2 * image.width + image.width / 2) * 4 + 3], 0,
                           "两件主体之间连通外边缘的白底也必须去掉")
            XCTAssertGreaterThan(Self.whiteOpaquePixelCount(pixels), 2200, "主体内部的白色不能被全局白色键删除")
        }
    }

    func testAlreadyTransparentImageIsPreservedWithoutSegmentation() async throws {
        let input = Self.fixture(background: nil)
        let probe = CutoutProbe()
        let output = await Task.detached {
            WardrobeStorageCutoutProcessor.process(input, lift: { image in probe.record(); return image })
        }.value
        XCTAssertNotNil(output)
        XCTAssertEqual(probe.count, 0)
        XCTAssertGreaterThan(Self.whiteOpaquePixelCount(try XCTUnwrap(output.flatMap(WardrobeStorageCutoutProcessor.decode)
            .flatMap(WardrobeStorageCutoutProcessor.Pixels.init))), 2200)
    }

    func testOpaquePNGIsNotMistakenForACompletedCutout() async throws {
        let opaque = Self.fixture(background: 0.45)
        let probe = CutoutProbe()
        let output = await Task.detached {
            WardrobeStorageCutoutProcessor.process(opaque, lift: { image in probe.record(); return image })
        }.value
        XCTAssertNil(output, "完整不透明蒙版不能当作抠图成功")
        XCTAssertEqual(probe.count, 1)
    }

    func testForegroundMaskIsTriedBeforeLightBackgroundFallback() async throws {
        let input = Self.fixture(background: 0.45)
        let transparent = Self.fixture(background: nil)
        let probe = CutoutProbe()
        let result = await Task.detached {
            WardrobeStorageCutoutProcessor.process(input, lift: { _ in
                probe.record()
                return WardrobeStorageCutoutProcessor.decode(transparent)
            })
        }.value
        XCTAssertNotNil(result)
        XCTAssertEqual(probe.count, 1)
        XCTAssertFalse(probe.wasOnMainThread)
    }

    func testBlankWhiteImageDoesNotProduceAnEmptySuccessfulCutout() async {
        let blank = Self.fixture(background: 1, drawSubjects: false)
        let output = await Task.detached { WardrobeStorageCutoutProcessor.process(blank, lift: { _ in nil }) }.value
        XCTAssertNil(output)
    }

    func testRealWhiteShoesAreProcessedWithBothWhiteBackgrounds() async throws {
        let shoes = try XCTUnwrap(UIImage(named: "storage_shoes_sneakers")?.cgImage)
        let reference = try XCTUnwrap(WardrobeStorageCutoutProcessor.decode(Self.flatten(shoes, background: nil))
            .flatMap(WardrobeStorageCutoutProcessor.Pixels.init))
        let whiteSubjectPixels = Self.whiteOpaquePixelCount(reference)
        for shade in [CGFloat(1), CGFloat(0.955)] {
            let input = Self.flatten(shoes, background: shade)
            let output = await Task.detached { WardrobeStorageCutoutProcessor.process(input) }.value
            let processed = try XCTUnwrap(output.flatMap(WardrobeStorageCutoutProcessor.decode))
            let pixels = try XCTUnwrap(WardrobeStorageCutoutProcessor.Pixels(processed))
            XCTAssertTrue(pixels.isCutout)
            XCTAssertGreaterThan(Double(Self.whiteOpaquePixelCount(pixels)), Double(whiteSubjectPixels) * 0.98,
                                 "纯白底、偏白底都要保留白色鞋舌，不能只留下深色部分")
            // Also exercise the fallback explicitly; simulator foreground models may be unavailable.
            let fallback = await Task.detached { WardrobeStorageCutoutProcessor.process(input, lift: { _ in nil }) }.value
            let fallbackPixels = try XCTUnwrap(fallback.flatMap(WardrobeStorageCutoutProcessor.decode)
                .flatMap(WardrobeStorageCutoutProcessor.Pixels.init))
            XCTAssertGreaterThan(Double(Self.whiteOpaquePixelCount(fallbackPixels)), Double(whiteSubjectPixels) * 0.98)
            let validation = FileManager.default.temporaryDirectory.appendingPathComponent("pink-house-storage-cutout-validation")
            try FileManager.default.createDirectory(at: validation, withIntermediateDirectories: true)
            let name = shade == 1 ? "white-shoes" : "near-white-shoes"
            try input.write(to: validation.appendingPathComponent(name + "-original.png"))
            try XCTUnwrap(output).write(to: validation.appendingPathComponent(name + "-cutout.png"))
        }
    }

    func testConcurrentViewsAndCacheRelaunchOnlyProcessIdenticalBytesOnce() async throws {
        let input = Self.fixture(background: 1)
        try input.write(to: root.appendingPathComponent("first.png"))
        try input.write(to: root.appendingPathComponent("same-bytes.png"))
        let cacheDirectory = root.appendingPathComponent("cache")
        let probe = CutoutProbe()
        let cache = WardrobeStorageCutoutCache(directory: cacheDirectory, processor: { data in
            probe.record()
            return WardrobeStorageCutoutProcessor.process(data, lift: { _ in nil })
        })
        let directory = try XCTUnwrap(root)
        let source = WardrobeStorageImageSource(preferredCutout: nil, originals: ["first.png"], revision: 0)
        let alias = WardrobeStorageImageSource(preferredCutout: nil, originals: ["same-bytes.png"], revision: 0)
        async let a = cache.resolve(source, imagesDirectory: directory)
        async let b = cache.resolve(alias, imagesDirectory: directory)
        let results = await [a, b]
        XCTAssertTrue(results.allSatisfy { $0.isCutout && !$0.canRetry })
        XCTAssertEqual(probe.count, 1)
        XCTAssertFalse(probe.wasOnMainThread)
        let reopened = WardrobeStorageCutoutCache(directory: cacheDirectory, processor: { _ in probe.record(); return nil })
        let restored = await reopened.resolve(source, imagesDirectory: directory)
        XCTAssertTrue(restored.isCutout)
        XCTAssertEqual(restored.data, results.first?.data)
        XCTAssertEqual(probe.count, 1)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("first.png")), input)
    }

    func testMissingOrOpaqueLinkedCutoutStillTriesEveryOriginalPhoto() async throws {
        try Self.fixture(background: 0.4).write(to: root.appendingPathComponent("bad-linked.png"))
        try Self.fixture(background: 0.4).write(to: root.appendingPathComponent("first-photo.png"))
        try Self.fixture(background: 1).write(to: root.appendingPathComponent("white-photo.png"))
        let cache = WardrobeStorageCutoutCache(directory: root.appendingPathComponent("cache"), processor: {
            WardrobeStorageCutoutProcessor.process($0, lift: { _ in nil })
        })
        for linked in ["missing.png", "bad-linked.png"] {
            let source = WardrobeStorageImageSource(preferredCutout: linked,
                originals: ["first-photo.png", "white-photo.png"], revision: 0)
            let result = await WardrobeStorageImageResolver.resolve(source, imagesDirectory: root, cache: cache)
            XCTAssertTrue(result.isCutout)
            XCTAssertFalse(result.canRetry)
        }
    }

    func testFailureCanBeRetriedAndNeverBecomesPersistentOriginalImageCache() async throws {
        let input = Self.fixture(background: 1)
        try input.write(to: root.appendingPathComponent("photo.png"))
        let probe = CutoutProbe()
        let cacheDirectory = root.appendingPathComponent("cache")
        let cache = WardrobeStorageCutoutCache(directory: cacheDirectory, processor: { data in
            probe.record()
            return probe.enabled ? WardrobeStorageCutoutProcessor.process(data, lift: { _ in nil }) : nil
        })
        let source = WardrobeStorageImageSource(preferredCutout: nil, originals: ["photo.png"], revision: 0)
        let first = await cache.resolve(source, imagesDirectory: root)
        XCTAssertFalse(first.isCutout)
        XCTAssertTrue(first.canRetry)
        XCTAssertEqual(first.data, input)
        _ = await cache.resolve(source, imagesDirectory: root)
        XCTAssertEqual(probe.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDirectory.path))
        probe.enable()
        await cache.clearFailures()
        let retried = await cache.resolve(source, imagesDirectory: root)
        XCTAssertTrue(retried.isCutout)
        XCTAssertEqual(probe.count, 2)
    }

    func testSourceByteChangesInvalidateOldDerivativesAndCorruptCacheIsRebuilt() async throws {
        let input = Self.fixture(background: 1)
        let directory = try XCTUnwrap(root)
        let file = directory.appendingPathComponent("photo.png")
        try input.write(to: file)
        let cacheDirectory = directory.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let key = SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
        try Data("corrupt".utf8).write(to: cacheDirectory.appendingPathComponent(key + ".png"))
        let probe = CutoutProbe()
        let cache = WardrobeStorageCutoutCache(directory: cacheDirectory, processor: { data in
            probe.record()
            return WardrobeStorageCutoutProcessor.process(data, lift: { _ in nil })
        })
        let source = WardrobeStorageImageSource(preferredCutout: nil, originals: ["photo.png"], revision: 0)
        let repaired = await cache.resolve(source, imagesDirectory: directory)
        XCTAssertTrue(repaired.isCutout)
        try Self.fixture(background: 0.955).write(to: file)
        let changed = await cache.resolve(source, imagesDirectory: directory)
        XCTAssertTrue(changed.isCutout)
        XCTAssertEqual(probe.count, 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path).count, 2)
    }

    func testCancelledPreparationDoesNotCacheFailureForTheNextView() async throws {
        try Self.fixture(background: 1).write(to: root.appendingPathComponent("photo.png"))
        let directory = try XCTUnwrap(root)
        let probe = CutoutProbe()
        let cache = WardrobeStorageCutoutCache(directory: directory.appendingPathComponent("cache"), processor: { data in
            probe.record()
            return WardrobeStorageCutoutProcessor.process(data, lift: { _ in nil })
        })
        let source = WardrobeStorageImageSource(preferredCutout: nil, originals: ["photo.png"], revision: 0)
        _ = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return await cache.resolve(source, imagesDirectory: directory)
        }.value
        XCTAssertEqual(probe.count, 0)
        let next = await cache.resolve(source, imagesDirectory: directory)
        XCTAssertTrue(next.isCutout)
        XCTAssertEqual(probe.count, 1)
    }

    private nonisolated static func whiteOpaquePixelCount(_ pixels: WardrobeStorageCutoutProcessor.Pixels) -> Int {
        stride(from: 0, to: pixels.rgba.count, by: 4).filter {
            pixels.rgba[$0] > 230 && pixels.rgba[$0 + 1] > 230 && pixels.rgba[$0 + 2] > 230 && pixels.rgba[$0 + 3] > 240
        }.count
    }

    private nonisolated static func fixture(background: CGFloat?, drawSubjects: Bool = true) -> Data {
        let context = CGContext(data: nil, width: 120, height: 100, bitsPerComponent: 8, bytesPerRow: 480,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if let background {
            context.setFillColor(CGColor(gray: background, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 100))
        }
        if drawSubjects {
            for x in [20, 70] {
                context.setFillColor(CGColor(red: 0.4, green: 0.15, blue: 0.25, alpha: 1))
                context.fill(CGRect(x: x, y: 20, width: 30, height: 60))
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(CGRect(x: x + 3, y: 23, width: 24, height: 54))
            }
        }
        return png(context.makeImage()!)
    }

    private nonisolated static func flatten(_ image: CGImage, background: CGFloat?) -> Data {
        let context = CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 2048,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if let background {
            context.setFillColor(CGColor(gray: background, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 512, height: 512))
        return png(context.makeImage()!)
    }

    private nonisolated static func png(_ image: CGImage) -> Data {
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        assert(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

private nonisolated final class CutoutProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var mainThread = false
    private var allowsSuccess = false
    var count: Int { lock.withLock { calls } }
    var wasOnMainThread: Bool { lock.withLock { mainThread } }
    var enabled: Bool { lock.withLock { allowsSuccess } }
    func record() { lock.withLock { calls += 1; mainThread = mainThread || Thread.isMainThread } }
    func enable() { lock.withLock { allowsSuccess = true } }
}
