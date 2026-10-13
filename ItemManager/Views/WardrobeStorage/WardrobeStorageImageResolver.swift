import SwiftUI
import UIKit

@MainActor
enum WardrobeStorageImageResolver {
    static func resolve(_ source: WardrobeStorageImageSource, imagesDirectory: URL? = nil,
                        cache: WardrobeStorageCutoutCache = .shared) async -> WardrobeStorageResolvedImage {
        let directory = imagesDirectory ?? ImageManager.shared.imagesDirectory
        // Let the existing image manager request missing iCloud files before segmentation.
        if imagesDirectory == nil {
            for path in [source.preferredCutout].compactMap({ $0 }) + source.originals {
                if Task.isCancelled { break }
                let file = (path as NSString).lastPathComponent
                if !file.isEmpty && !FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path) {
                    _ = await ImageManager.shared.loadImageAsync(fileName: file, targetSize: CGSize(width: 256, height: 256))
                }
            }
        }
        return await cache.resolve(source, imagesDirectory: directory)
    }
}

private struct WardrobeStorageImageRefreshKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var wardrobeStorageImageRefresh: Int {
        get { self[WardrobeStorageImageRefreshKey.self] }
        set { self[WardrobeStorageImageRefreshKey.self] = newValue }
    }
}
