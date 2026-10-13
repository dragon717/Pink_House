import Foundation
import UIKit
import ImageIO

/// Small local derivatives owned by custom cabinets, separate from wardrobe / iCloud photos.
@MainActor
final class WardrobeStorageIconStore {
    static let shared = WardrobeStorageIconStore()
    private let directory: URL
    private let cache = NSCache<NSString, UIImage>()

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WardrobeStorage/Icons", isDirectory: true)
        cache.countLimit = 64
        cache.totalCostLimit = 16 * 1024 * 1024
    }

    /// Decode only a bounded, orientation-corrected thumbnail before opening the crop UI.
    nonisolated static func cropImage(from data: Data) -> CGImage? {
        thumbnail(from: data, maxPixels: 1024)
    }

    func save(_ data: Data) throws -> String {
        guard let thumbnail = Self.thumbnail(from: data, maxPixels: 256) else { throw ImageError.invalidImage }
        let image = UIImage(cgImage: thumbnail)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = false; format.preferredRange = .standard
        let normalized = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { _ in
            let scale = 256 / min(image.size.width, image.size.height)
            let width = image.size.width * scale, height = image.size.height * scale
            image.draw(in: CGRect(x: (256 - width) / 2, y: (256 - height) / 2, width: width, height: height))
        }
        guard let png = normalized.pngData(), png.count <= 512 * 1024 else { throw ImageError.invalidImage }
        let name = UUID().uuidString + ".png"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent(name), options: .atomic)
        cache.setObject(normalized, forKey: name as NSString, cost: 256 * 256 * 4)
        return name
    }

    func image(named name: String) -> UIImage? {
        guard let url = fileURL(named: name) else { return nil }
        if let image = cache.object(forKey: name as NSString) { return image }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 512 * 1024,
              let data = try? Data(contentsOf: url), let image = Self.thumbnail(from: data, maxPixels: 256) else { return nil }
        let result = UIImage(cgImage: image)
        cache.setObject(result, forKey: name as NSString, cost: image.width * image.height * 4)
        return result
    }

    /// Called only for obsolete cabinet-owned derivatives after a successful save / rollback.
    func remove(named name: String) {
        guard let url = fileURL(named: name) else { return }
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: url)
    }

    private func fileURL(named name: String) -> URL? {
        guard name.hasSuffix(".png"), UUID(uuidString: String(name.dropLast(4))) != nil else { return nil }
        return directory.appendingPathComponent(name)
    }

    nonisolated private static func thumbnail(from data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ] as CFDictionary)
    }

    nonisolated enum ImageError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "这张图片无法用作图标，请重新选择。" }
    }
}
