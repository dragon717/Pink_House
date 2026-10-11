import Foundation
import SwiftData
import UIKit

/// Catalog 的下载缓存可被清理；入橱图片必须进入 ImageManager 的持久化与引用计数体系。
@MainActor
enum ShopCatalogWardrobeImageImporter {
    enum ImportError: LocalizedError {
        case unavailable
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .unavailable: return "商品图片下载失败，请重试后再加入衣橱"
            case .saveFailed: return "商品图片保存失败，请重试后再加入衣橱"
            }
        }
    }

    static func materialize(
        product: CatalogProduct,
        store: ShopCatalogStore,
        modelContext: ModelContext,
        mediaStore: ShopCatalogMediaStore? = nil,
        session: URLSession = .shared,
        maxCount: Int = 6
    ) async throws -> [String] {
        let mediaStore = mediaStore ?? .shared
        var paths: [String] = []
        var seen = Set<ShopCatalogImageSource>()
        do {
            for reference in product.images {
                guard paths.count < maxCount else { break }
                try Task.checkCancellation()
                let source = ShopCatalogImageSource.resolve(reference, asset: { store.asset(id: $0) })
                guard seen.insert(source).inserted else { continue }
                let image = try await ShopCatalogImageLoader.load(source, mediaStore: mediaStore, session: session)
                try Task.checkCancellation()
                guard let path = ImageManager.shared.saveImage(
                    image, context: modelContext, triggerImageSync: false) else {
                    throw ImportError.saveFailed
                }
                paths.append(path)
            }
            return paths
        } catch {
            release(paths, modelContext: modelContext)
            throw error
        }
    }

    static func release(_ paths: [String], modelContext: ModelContext) {
        guard !paths.isEmpty else { return }
        for path in paths {
            ImageManager.shared.deleteImage(fileName: path, context: modelContext)
        }
        do {
            try modelContext.save()
        } catch {
            AppLogger.error("释放入橱图片引用失败：\(error.localizedDescription)")
        }
    }

}
