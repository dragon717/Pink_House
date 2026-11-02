import Foundation
import SharedCatalog

/// 工作区图片查找缓存。文件替换/增删后自动失效；发布门禁仍调用 OpsCachedMedia.files 全量核验。
/// 仅供同一工作区串行调用，不在后台任务之间共享。
public final class OpsCachedMediaLookup {
    private struct Stamp: Equatable {
        let modified: Date?
        let size: UInt64?
        let inode: UInt64?
        init?(_ url: URL) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
            modified = attributes[.modificationDate] as? Date
            size = attributes[.size] as? UInt64
            inode = attributes[.systemFileNumber] as? UInt64
        }
    }
    private var directory: URL?
    private var directoryStamp: Stamp?
    private var candidates: [String: [URL]] = [:]
    private var verified: [URL: (Stamp, Bool)] = [:]

    public init() {}

    public func file(in directory: URL, hash: String) -> URL? {
        let stamp = Stamp(directory)
        if self.directory != directory || stamp != directoryStamp {
            self.directory = directory
            directoryStamp = stamp
            candidates.removeAll(keepingCapacity: true)
            verified.removeAll(keepingCapacity: true)
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let digest = file.deletingPathExtension().lastPathComponent
                if ShopCatalogSyncProtocol.isPayloadHash(digest) { candidates[digest, default: []].append(file) }
            }
        }
        for file in candidates[hash] ?? [] {
            guard let stamp = Stamp(file) else { continue }
            if let cached = verified[file], cached.0 == stamp {
                if cached.1 { return file }
                continue
            }
            let valid = (try? Data(contentsOf: file)).map { ShopCatalogSyncProtocol.sha256Hex($0) == hash } ?? false
            verified[file] = (stamp, valid)
            if valid { return file }
        }
        return nil
    }
}
