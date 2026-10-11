import Foundation
import UIKit
import SharedCatalog

/// 长期入橱与相册保存共用 canonical 媒体/候选引用读取。
@MainActor
enum ShopCatalogImageLoader {
    static func load(_ source: ShopCatalogImageSource,
                             mediaStore: ShopCatalogMediaStore,
                             session: URLSession) async throws -> UIImage {
        if let key = source.mediaKey {
            mediaStore.clearSessionFailure(mediaKey: key)
            if let url = await mediaStore.resolvedURL(mediaKey: key),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        for reference in source.references {
            guard let url = ShopCatalogImageResolver.url(for: reference) else { continue }
            if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                return image
            }
            if ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                do {
                    let (data, response) = try await session.data(from: url)
                    if let response = response as? HTTPURLResponse,
                       (200..<300).contains(response.statusCode),
                       let image = UIImage(data: data) { return image }
                } catch {
                    try Task.checkCancellation()
                    // 原图暂不可用时仍尝试该素材的其它候选引用。
                }
            }
        }
        throw ShopCatalogWardrobeImageImporter.ImportError.unavailable
    }
}
