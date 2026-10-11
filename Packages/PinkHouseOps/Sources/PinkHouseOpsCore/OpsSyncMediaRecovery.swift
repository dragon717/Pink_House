import Foundation
import SharedCatalog

/// 补图覆盖本地与线上工作副本；仅按可验证的内容摘要跨环境找回字节。
public enum OpsSyncMediaRecovery {
    public struct Result {
        public let requested: [String]
        public let unresolved: [String]
        public let downloads: [OpsFetchedMedia]
    }

    public static func hashes(in catalog: ShopCatalog) -> Set<String> {
        var hashes = Set(ShopCatalogMediaReferences.all(in: catalog).compactMap {
            ShopCatalogSyncProtocol.mediaContentHash(in: $0.reference)
        })
        hashes.formUnion(catalog.assets.compactMap {
            ShopCatalogSyncProtocol.resolvedMediaKey($0.mediaKey)
        })
        return hashes
    }

    @MainActor
    public static func download(
        local: ShopCatalog, remote: ShopCatalog, environment: String,
        available: () -> Set<String>,
        fetch: ([String], String) async -> OpsFetchedMedia?,
        receive: (OpsFetchedMedia) -> Void
    ) async -> Result {
        let localHashes = hashes(in: local), remoteHashes = hashes(in: remote)
        let requested = localHashes.union(remoteHashes).subtracting(available()).sorted()
        var downloads: [OpsFetchedMedia] = []
        if !requested.isEmpty, let target = await fetch(requested, environment),
           target.environment == environment {
            receive(target)
            downloads.append(target)
            // 只有 Production 明确不存在、且来自本地的引用才能回开发环境补图。
            // 网络、鉴权或摘要异常不能当成 NOT_FOUND，也不能切换当前发布目标。
            let recoverable = Set(target.missing).intersection(localHashes)
                .subtracting(remoteHashes).subtracting(available()).sorted()
            if environment == "production", !recoverable.isEmpty,
               let source = await fetch(recoverable, "development"),
               source.environment == "development" {
                receive(source)
                downloads.append(source)
            }
        }
        return Result(requested: requested,
                      unresolved: Set(requested).subtracting(available()).sorted(), downloads: downloads)
    }
}
