import Foundation
import SwiftData
import UIKit
import SharedCatalog

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
        selectedColor: String? = nil,
        mediaStore: ShopCatalogMediaStore? = nil,
        session: URLSession = .shared,
        maxCount: Int = 6
    ) async throws -> [String] {
        let mediaStore = mediaStore ?? .shared
        var paths: [String] = []
        var seen = Set<ShopCatalogImageSource>()
        do {
            let references = references(product: product, store: store, selectedColor: selectedColor)
            let hasProductImages = !product.images.isEmpty || store.variants(forProduct: product.id)
                .contains { CatalogVariantColorGrouping.normalizedColor($0.imageAssetID) != nil }
            guard !references.isEmpty || !hasProductImages else { throw ImportError.unavailable }
            for reference in references {
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

    /// 优先取得所选配色的图，并保留未绑定其它配色的商品通用图。
    /// 旧商品未配置规格图时也必须带上商品相册。规格图可以不在 product.images 中。
    static func references(product: CatalogProduct, store: ShopCatalogStore, selectedColor: String?) -> [String] {
        func colorKey(_ value: String?) -> String? {
            CatalogVariantColorGrouping.normalizedColor(value)?
                .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        }
        func identity(_ reference: String) -> String {
            let source = ShopCatalogImageSource.resolve(reference, asset: { store.asset(id: $0) })
            return source.mediaKey.map { "media/" + $0 } ?? source.references.first ?? reference
        }
        let variants = store.variants(forProduct: product.id)
        guard let selected = colorKey(selectedColor) else {
            return product.images.isEmpty ? variants.compactMap(\.imageAssetID) : product.images
        }
        let colors = Set(variants.compactMap { colorKey($0.color) })
        guard colors.isEmpty || colors.contains(selected) else { return [] }
        let matching = variants.filter { colorKey($0.color) == selected }
            .compactMap { CatalogVariantColorGrouping.normalizedColor($0.imageAssetID) }
        let otherImages = Set(variants.filter {
            if let color = colorKey($0.color) { return color != selected }
            return false
        }.compactMap { CatalogVariantColorGrouping.normalizedColor($0.imageAssetID) }.map(identity))
        // 明确绑定到其它颜色的图片不能带入；没有配色绑定的商品图仍是有效通用图。
        let candidates = matching + product.images
        var seen = Set<String>()
        return candidates.filter {
            let key = identity($0)
            return !otherImages.contains(key) && seen.insert(key).inserted
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
