import Foundation

/// 图像字段既可存 CatalogAsset.id，也可存 local / thmedia / HTTP / Bundle 引用。
/// 先解资源表再解路径，不能把资源 ID 当成文件名；canonical mediaKey 独立保留。
public struct ShopCatalogImageSource: Hashable, Sendable {
    public let references: [String]
    public let mediaKey: String?

    /// canonical 原图优先，其次是原图 / 预览图 / 缩略图中的其它云端候选。
    public var mediaKeys: [String] {
        var seen = Set<String>()
        return ([mediaKey] + references.map { ShopCatalogSyncProtocol.mediaContentHash(in: $0) })
            .compactMap { $0 }.filter { seen.insert($0).inserted }
    }

    public static func resolve(_ reference: String?, mediaKey: String? = nil,
                               asset: (String) -> CatalogAsset?) -> Self {
        func clean(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        let raw = clean(reference)
        let record = raw.flatMap(asset)
        let candidates: [String?] = record.map { [$0.originalURL, $0.previewURL, $0.thumbnailURL] } ?? [raw]
        var seen = Set<String>()
        let references = candidates.compactMap(clean).filter { seen.insert($0).inserted }
        let key = ShopCatalogSyncProtocol.resolvedMediaKey(mediaKey)
            ?? ShopCatalogSyncProtocol.resolvedMediaKey(record?.mediaKey, fallbackReferences: references)
        return Self(references: references, mediaKey: key)
    }
}
