//
//  ShopCatalogMediaStagingTests.swift
//
//  图片规范化 + 内容寻址（`mediaKey`）。
//
//  ## 为什么这些断言值钱
//
//  `mediaKey` 是发布链路的主键：`THMedia` 记录名 = `th.media.<mediaKey>`，
//  引用前缀 = `thmedia:<mediaKey>`，加载端还要拿它做层号定位。
//  它一旦不确定（同一张图算出两个 key），后果不是「多传一张」，
//  而是「线上永远有一半设备解不出这张图」——而且数据看起来完全正常。
//
//  所以这里**必须**锁死三件事：
//    1. 确定性：同字节 → 同字节 → 同 key（这是幂等复用的全部依据）；
//    2. 长边归一：同一张图在 iPhone 原图与 Mac 处理后的尺寸口径一致；
//    3. 超限与坏数据**硬报错**，不静默换容器 / 不静默压缩兜底。
//

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import SharedCatalog

final class ShopCatalogMediaStagingTests: XCTestCase {

    // MARK: 内容寻址

    func testStageIsDeterministicAndContentAddressed() throws {
        let source = try makeImage(width: 800, height: 600, type: UTType.png.identifier)

        let first = try ShopCatalogMediaStaging.stage(source)
        let second = try ShopCatalogMediaStaging.stage(source)

        XCTAssertEqual(first.mediaKey, second.mediaKey, "同字节必须得到同一个 mediaKey（幂等复用的全部依据）")
        XCTAssertEqual(first.data, second.data, "规范化必须是纯函数：同输入同输出")
        XCTAssertEqual(first.fileName, second.fileName)
        XCTAssertEqual(first.fileName, "\(first.mediaKey).png", "落盘文件名固定是 <mediaKey>.<ext>")

        // 协议侧的记录名由 mediaKey 派生，不是另一个独立键
        XCTAssertEqual(
            ShopCatalogSyncProtocol.mediaRecordName(contentHash: first.mediaKey),
            "th.media.\(first.mediaKey)")
        XCTAssertEqual(ShopCatalogSyncProtocol.mediaReference(contentHash: first.mediaKey),
                       "\(ShopCatalogSyncProtocol.mediaReferencePrefix)\(first.mediaKey)")
    }

    func testMediaKeyIsLowercaseHexSha256() throws {
        let staged = try ShopCatalogMediaStaging.stage(
            try makeImage(width: 320, height: 320, type: UTType.png.identifier))

        XCTAssertEqual(staged.mediaKey.count, 64)
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(
            staged.mediaKey.unicodeScalars.allSatisfy { hex.contains($0) },
            "mediaKey 必须是小写 hex：\(staged.mediaKey)")
        XCTAssertTrue(ShopCatalogSyncProtocol.isPayloadHash(staged.mediaKey))
    }

    func testMediaKeyForStoredBytesMatchesStageOutput() throws {
        let staged = try ShopCatalogMediaStaging.stage(
            try makeImage(width: 640, height: 480, type: UTType.png.identifier))
        // 「已经是规范形态的字节只做校验、不改写」——这条保证了重复导入不会
        // 因为「又编码了一次」而漂出一个新的 key。
        XCTAssertEqual(
            ShopCatalogMediaStaging.mediaKey(forStoredBytes: staged.data),
            staged.mediaKey)
    }

    // MARK: 长边归一

    func testStageDownscalesLongEdgeAndKeepsAspectRatio() throws {
        let source = try makeImage(width: 3200, height: 2000, type: UTType.png.identifier)
        let staged = try ShopCatalogMediaStaging.stage(source, maxDimension: 1600)

        XCTAssertEqual(max(staged.pixelWidth, staged.pixelHeight), 1600)
        XCTAssertEqual(staged.pixelWidth, 1600)
        XCTAssertLessThanOrEqual(abs(staged.pixelHeight - 1000), 2, "长边归一必须保持宽高比")
        XCTAssertEqual(staged.sourcePixelWidth, 3200, "原始尺寸要留档，供详情页标注")
        XCTAssertEqual(staged.sourcePixelHeight, 2000)
    }

    func testStageDoesNotUpscaleSmallerImages() throws {
        let source = try makeImage(width: 200, height: 150, type: UTType.png.identifier)
        let staged = try ShopCatalogMediaStaging.stage(source, maxDimension: 1600)
        XCTAssertEqual(staged.pixelWidth, 200, "比上限还小的图不该被放大")
        XCTAssertEqual(staged.pixelHeight, 150)
    }

    func testPixelSizeReadsBackStoredBytes() throws {
        let staged = try ShopCatalogMediaStaging.stage(
            try makeImage(width: 512, height: 256, type: UTType.png.identifier))
        let size = try XCTUnwrap(ShopCatalogMediaStaging.pixelSize(of: staged.data))
        XCTAssertEqual(size.width, 512)
        XCTAssertEqual(size.height, 256)
    }

    // MARK: 容器保留

    func testStageKeepsWhitelistedContainers() throws {
        let png = try ShopCatalogMediaStaging.stage(
            try makeImage(width: 300, height: 300, type: UTType.png.identifier))
        XCTAssertEqual(png.mimeType, "image/png", "PNG 的透明通道不是我们能随便丢的，必须保留容器")
        XCTAssertTrue(png.fileName.hasSuffix(".png"))

        let jpeg = try ShopCatalogMediaStaging.stage(
            try makeImage(width: 300, height: 300, type: UTType.jpeg.identifier))
        XCTAssertEqual(jpeg.mimeType, "image/jpeg")
    }

    // MARK: 硬报错（不静默兜底）

    func testStageRejectsNonImageData() {
        let garbage = Data((0..<4096).map { UInt8($0 % 251) })
        XCTAssertThrowsError(try ShopCatalogMediaStaging.stage(garbage)) { error in
            guard case ShopCatalogMediaStagingError.unreadableImage = error else {
                return XCTFail("期望 unreadableImage，实际 \(error)")
            }
        }
    }

    func testStageRejectsBytesOverLimit() throws {
        let source = try makeImage(width: 400, height: 400, type: UTType.png.identifier)
        XCTAssertThrowsError(try ShopCatalogMediaStaging.stage(source, maxBytes: 64)) { error in
            guard case ShopCatalogMediaStagingError.tooLarge(let byteCount, let limit) = error else {
                return XCTFail("期望 tooLarge，实际 \(error)")
            }
            XCTAssertGreaterThan(byteCount, limit)
            XCTAssertEqual(limit, 64)
        }
    }

    func testRejectionReasonDistinguishesCleanAndBrokenBytes() throws {
        let staged = try ShopCatalogMediaStaging.stage(
            try makeImage(width: 300, height: 300, type: UTType.png.identifier))
        XCTAssertNil(
            ShopCatalogMediaStaging.rejectionReason(forStoredBytes: staged.data),
            "规范化产出的字节必须能反过门禁，否则「导入成功但发布被拦」")
        XCTAssertNotNil(
            ShopCatalogMediaStaging.rejectionReason(forStoredBytes: Data(repeating: 0, count: 128)))
    }

    // MARK: 协议常量与白名单（与 Mac 端 protocol.py 逐字对齐）

    func testMediaLimitsMatchPublishedProtocol() {
        XCTAssertEqual(ShopCatalogSyncProtocol.maxMediaBytes, 20 * 1024 * 1024)
        XCTAssertEqual(
            ShopCatalogSyncProtocol.mediaMimeAllowlist,
            ["image/jpeg", "image/png", "image/gif", "image/webp", "image/heic"])
        XCTAssertEqual(ShopCatalogSyncProtocol.mediaReferencePrefix, "thmedia:")
        XCTAssertEqual(ShopCatalogSyncProtocol.releaseRecordName, "th.release.catalog-v1")
    }

    func testMimeAllowlistIsCaseInsensitiveAndStrict() {
        XCTAssertTrue(ShopCatalogSyncProtocol.isAllowedMediaMimeType("image/PNG"))
        XCTAssertTrue(ShopCatalogSyncProtocol.isAllowedMediaMimeType("image/heic"))
        XCTAssertFalse(ShopCatalogSyncProtocol.isAllowedMediaMimeType("image/tiff"))
        XCTAssertFalse(ShopCatalogSyncProtocol.isAllowedMediaMimeType("text/plain"))
        XCTAssertFalse(ShopCatalogSyncProtocol.isAllowedMediaMimeType(""))
    }

    // MARK: 测试夹具

    /// 生成一张纯色图（同参数 → 同字节，便于验证确定性）。
    private func makeImage(width: Int, height: Int, type: String) throws -> Data {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw XCTSkip("无法创建 CGContext")
        }
        context.setFillColor(CGColor(red: 0.92, green: 0.45, blue: 0.63, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw XCTSkip("无法生成 CGImage")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, type as CFString, 1, nil) else {
            throw XCTSkip("无法创建图像目标：\(type)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("图像写出失败：\(type)")
        }
        return output as Data
    }
}
