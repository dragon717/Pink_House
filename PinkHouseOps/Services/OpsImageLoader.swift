import AppKit
import ImageIO
import SwiftUI

/// 文件读取、解码和缩小全部在独立 actor 执行；缓存限制解码后的像素内存。
actor OpsImageLoader {
    static let shared = OpsImageLoader()
    struct Decoded: @unchecked Sendable { let image: CGImage }
    private let cache = NSCache<NSString, CGImage>()

    init() { cache.totalCostLimit = 64 * 1024 * 1024 }

    func load(_ url: URL, pixels: Int) -> Decoded? {
        guard !Task.isCancelled else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let stamp = "\(attributes?[.modificationDate] ?? ""):\(attributes?[.size] ?? ""):\(attributes?[.systemFileNumber] ?? "")"
        let key = "\(url.path):\(pixels):\(stamp)" as NSString
        if let image = cache.object(forKey: key) { return Decoded(image: image) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, pixels),
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return Decoded(image: image)
    }
}

/// URL 身份变化时先隐藏旧图；取消的旧请求不能把结果覆盖到新款式上。
struct OpsAsyncImage: View {
    let url: URL?
    var pixels = 256
    var contentMode: ContentMode = .fill
    @State private var loadedURL: URL?
    @State private var image: OpsImageLoader.Decoded?

    private struct Request: Hashable { let url: URL?; let pixels: Int }

    var body: some View {
        Group {
            if loadedURL == url, let image {
                Image(decorative: image.image, scale: 1)
                    .resizable().aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    Color.secondary.opacity(0.10)
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
        }
        .task(id: Request(url: url, pixels: pixels)) {
            guard let url else { image = nil; loadedURL = nil; return }
            let result = await OpsImageLoader.shared.load(url, pixels: pixels)
            guard !Task.isCancelled else { return }
            image = result
            loadedURL = url
        }
    }
}
