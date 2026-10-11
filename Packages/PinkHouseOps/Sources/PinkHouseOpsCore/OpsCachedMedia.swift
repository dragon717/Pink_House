import Foundation
import SharedCatalog

/// 预览、缺图检查与发布打包使用同一份经过摘要校验的缓存清单。
public enum OpsCachedMedia {
    public static func files(in directory: URL, hash: String? = nil) -> [String: URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        var result: [String: URL] = [:]
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let digest = file.deletingPathExtension().lastPathComponent
            guard ShopCatalogSyncProtocol.isPayloadHash(digest),
                  hash == nil || hash == digest, result[digest] == nil,
                  let data = try? Data(contentsOf: file),
                  ShopCatalogSyncProtocol.sha256Hex(data) == digest else { continue }
            result[digest] = file
        }
        return result
    }
}
