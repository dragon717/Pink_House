//
//  ShopCatalogMediaStaging.swift
//  SharedCatalog
//
//  「一张图 → 一个内容寻址的 mediaKey」的唯一口径（iOS / Mac 共用）。
//
//  ## 它解决的三件事
//
//  1. **规范化**：运营选的图尺寸/格式/EXIF 方向五花八门，直接上传会出现
//     「同一张图两个摘要」（因为导出了两次、或横竖方向不同），包会无谓地变大。
//     这里统一「长边压到 1600 + 应用 EXIF 方向」，让同一张图稳定产出同一份字节。
//  2. **内容寻址**：`mediaKey = 规范化后字节的 SHA-256`，与 Mac 端
//     `build_release.py` 的 `content_hash = sha256_hex(payload)` 同一口径，
//     也与 `THMedia` 记录名 `th.media.<contentHash>` 同源。
//  3. **入库前的硬门槛**：MIME 必须在白名单内、字节数不超上限。超限**报错**，
//     不静默压缩 —— 悄悄换掉运营选的图比构建失败难查得多。
//
//  ## 为什么不用 `UIImage` / `NSImage`
//
//  这两个类分属 UIKit / AppKit，一边一个就编不过对方。走 `ImageIO` +
//  `CoreGraphics`（两端都是系统框架）才能真正共用，这也是把这个文件放进
//  共享包而不是各自的 App 里的原因。
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - 错误

public nonisolated enum ShopCatalogMediaStagingError: LocalizedError, Equatable {
    /// 数据不是可解码的图片
    case unreadableImage(String)
    /// 规范化后仍超出单张上限
    case tooLarge(byteCount: Int, limit: Int)
    /// 类型不在 `ShopCatalogSyncProtocol.mediaMimeAllowlist` 内
    case unsupportedMimeType(String)
    /// 编码不出目标格式（ImageIO 不支持写该容器等）
    case encodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableImage(let detail):
            return "无法识别的图片：\(detail)"
        case .tooLarge(let byteCount, let limit):
            return "图片过大：\(byteCount) 字节 > 上限 \(limit) 字节（\(limit / 1024 / 1024) MiB）。"
                + "请压缩或裁切后重试，不要指望发布端替你换图。"
        case .unsupportedMimeType(let mimeType):
            return "不支持的图片类型「\(mimeType)」：客户端解不出来的类型不允许进公共库。"
        case .encodeFailed(let detail):
            return "图片编码失败：\(detail)"
        }
    }
}

// MARK: - 规范化 + 内容寻址

public nonisolated enum ShopCatalogMediaStaging {

    /// 一次规范化的结果。`mediaKey` 就是 `THMedia` 记录名的后半段。
    public struct StagedMedia: Hashable, Sendable {
        /// 规范化后字节的 SHA-256（64 位小写 hex）
        public let mediaKey: String
        public let data: Data
        /// 落盘文件名：`<mediaKey>.<ext>`。发布端按文件名后缀推 MIME
        /// （`build_release.py` 用 `mimetypes.guess_type`），所以后缀必须与内容一致。
        public let fileName: String
        public let mimeType: String
        public let pixelWidth: Int
        public let pixelHeight: Int
        /// 原图（规范化前）的长边像素，用于在界面上如实展示「被压缩了多少」
        public let sourcePixelWidth: Int?
        public let sourcePixelHeight: Int?

        // 跨模块构造入口：`public` 结构体的合成逐成员 init 是 internal，外部模块必须显式声明。
        public init(
            mediaKey: String,
            data: Data,
            fileName: String,
            mimeType: String,
            pixelWidth: Int,
            pixelHeight: Int,
            sourcePixelWidth: Int?,
            sourcePixelHeight: Int?
        ) {
            self.mediaKey = mediaKey
            self.data = data
            self.fileName = fileName
            self.mimeType = mimeType
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.sourcePixelWidth = sourcePixelWidth
            self.sourcePixelHeight = sourcePixelHeight
        }

        public var byteCount: Int { data.count }

        /// 是否发生了实际压缩（尺寸被压小或格式被换掉）
        public var wasNormalized: Bool {
            guard let sourcePixelWidth, let sourcePixelHeight else { return true }
            return sourcePixelWidth != pixelWidth || sourcePixelHeight != pixelHeight
        }
    }

    /// 规范化后的长边上限。与 iOS 侧 `ShopCatalogImageStore` 的既有口径一致，
    /// 不要单独改这一边，否则同一张图在两端会得到不同的 `mediaKey`。
    public static let defaultMaxDimension = 1600
    /// JPEG 有损质量，同样是既有口径
    public static let defaultJPEGQuality = 0.85

    // MARK: 入口

    /// 规范化 + 内容寻址。**这是唯一允许生成 `mediaKey` 的地方。**
    ///
    /// - Parameters:
    ///   - maxDimension: 长边上限（像素）。只缩不放，比它还小的图保持原尺寸。
    ///   - jpegQuality: 仅对 JPEG 有损重编码生效。
    ///   - maxBytes: 单张上限，默认取协议常量。
    public static func stage(
        _ data: Data,
        maxDimension: Int = defaultMaxDimension,
        jpegQuality: Double = defaultJPEGQuality,
        maxBytes: Int = ShopCatalogSyncProtocol.maxMediaBytes
    ) throws -> StagedMedia {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw ShopCatalogMediaStagingError.unreadableImage(
                "不是 ImageIO 能解码的图片数据（\(data.count) 字节）")
        }
        let sourceType = (CGImageSourceGetType(source) as String?) ?? UTType.jpeg.identifier
        let sourceSize = pixelSize(of: source)

        // 1) 缩到长边上限，并**应用 EXIF 方向**（不应用的话同一张竖拍图
        //    会因为「旋转标记不同」而产出两份不同的字节 → 两个 mediaKey）
        guard let scaled = downscaledImage(from: source, maxDimension: maxDimension) else {
            throw ShopCatalogMediaStagingError.unreadableImage("解码出的图像为空")
        }

        // 2) 选输出容器：源类型在白名单内就原样保留（PNG 的透明通道、GIF 的帧
        //    号顺序都不是我们能随便丢的），不在白名单才落到 JPEG。
        let preferredType = outputType(forSourceType: sourceType)
        guard let encoded = encodeToContainer(
            scaled, as: preferredType, jpegQuality: jpegQuality) else {
            throw ShopCatalogMediaStagingError.encodeFailed(
                "ImageIO 无法写出 \(preferredType)")
        }

        let mimeType = (UTType(encoded.type)?.preferredMIMEType
            ?? fallbackMimeType(forIdentifier: encoded.type)).lowercased()
        guard ShopCatalogSyncProtocol.isAllowedMediaMimeType(mimeType) else {
            throw ShopCatalogMediaStagingError.unsupportedMimeType(mimeType)
        }
        guard encoded.data.count <= maxBytes else {
            throw ShopCatalogMediaStagingError.tooLarge(
                byteCount: encoded.data.count, limit: maxBytes)
        }

        let mediaKey = ShopCatalogSyncProtocol.sha256Hex(encoded.data)
        let ext = (UTType(encoded.type)?.preferredFilenameExtension)
            ?? (mimeType == "image/png" ? "png" : "jpg")

        return StagedMedia(
            mediaKey: mediaKey,
            data: encoded.data,
            fileName: "\(mediaKey).\(ext)",
            mimeType: mimeType,
            pixelWidth: scaled.width,
            pixelHeight: scaled.height,
            sourcePixelWidth: sourceSize?.width,
            sourcePixelHeight: sourceSize?.height)
    }

    /// 已经是规范形态的字节只做校验、不改写，直接算 `mediaKey`。
    ///
    /// 用途：发布端/校验器拿到 staging 目录里的现成文件时（例如上一轮已经
    /// 规范化过、这一轮只是要复用），不需要也不应该重新编码 ——
    /// 重新编码会得到不同的字节，进而得到不同的 `mediaKey`，把幂等复用打碎。
    public static func mediaKey(forStoredBytes data: Data) -> String {
        ShopCatalogSyncProtocol.sha256Hex(data)
    }

    /// 只读像素尺寸，不解码整张图（ImageIO 读头部即可）。
    public static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return pixelSize(of: source)
    }

    /// 现存文件是否可直接入库（MIME 与字节数门槛）。
    /// 返回 nil = 通过，否则是拒收原因。
    public static func rejectionReason(forStoredBytes data: Data) -> String? {
        if data.count > ShopCatalogSyncProtocol.maxMediaBytes {
            return "字节数 \(data.count) 超过上限 \(ShopCatalogSyncProtocol.maxMediaBytes)"
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let mimeType = UTType(identifier)?.preferredMIMEType?.lowercased() else {
            return "不是可识别的图片数据"
        }
        guard ShopCatalogSyncProtocol.isAllowedMediaMimeType(mimeType) else {
            return "类型 \(mimeType) 不在白名单内"
        }
        return nil
    }

    // MARK: 内部

    private static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0 else { return nil }
        return (width, height)
    }

    /// 缩到长边上限。`kCGImageSourceCreateThumbnailFromImageAlways` 保证即使源图
    /// 没有内嵌缩略图也会真的重采样；`...WithTransform` 保证 EXIF 方向被烘焙进像素，
    /// 这样下游不需要再关心方向标记。
    private static func downscaledImage(
        from source: CGImageSource, maxDimension: Int
    ) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 输出容器选择：**白名单内就地保留**，否则落到 JPEG。
    private static func outputType(forSourceType sourceType: String) -> String {
        let normalized = sourceType.lowercased()
        let keepable = [
            UTType.png.identifier,
            UTType.gif.identifier,
            UTType.jpeg.identifier,
            "public.heic",
            "public.heif",
            "org.webmproject.webp",
        ].map { $0.lowercased() }
        return keepable.contains(normalized) ? sourceType : UTType.jpeg.identifier
    }

    /// 编码；首选容器写不出来时回落 JPEG（ImageIO 能读 WebP 但**不能写**，
    /// 这类源图必须换容器，否则整张图直接失败）。
    ///
    /// ⚠️ 名字必须和下面那个 `encode(_:as:jpegQuality:)` 区分开：两者只在
    /// **返回类型**上不同（`(data:type:)?` vs `Data?`），而 Swift 重载解析
    /// 不看返回类型 —— 同名会让调用处直接报
    /// `ambiguous use of 'encode(_:as:jpegQuality:)'`。
    private static func encodeToContainer(
        _ image: CGImage, as preferredType: String, jpegQuality: Double
    ) -> (data: Data, type: String)? {
        if let data = encode(image, as: preferredType, jpegQuality: jpegQuality) {
            return (data, preferredType)
        }
        guard preferredType != UTType.jpeg.identifier,
              let data = encode(image, as: UTType.jpeg.identifier, jpegQuality: jpegQuality) else {
            return nil
        }
        return (data, UTType.jpeg.identifier)
    }

    private static func encode(
        _ image: CGImage, as type: String, jpegQuality: Double
    ) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, type as CFString, 1, nil) else { return nil }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func fallbackMimeType(forIdentifier identifier: String) -> String {
        switch identifier.lowercased() {
        case UTType.png.identifier.lowercased(): return "image/png"
        case UTType.gif.identifier.lowercased(): return "image/gif"
        case "public.heic", "public.heif": return "image/heic"
        case "org.webmproject.webp": return "image/webp"
        default: return "image/jpeg"
        }
    }
}
