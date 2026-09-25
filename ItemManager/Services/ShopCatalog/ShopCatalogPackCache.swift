//
//  ShopCatalogPackCache.swift
//  ItemManager
//
//  「店家上新」云同步 · 本地包缓存与控制状态（消费端）。
//
//  ## 存储分层（设计文档 §13.1 的商店版）
//
//    Library/Caches/ShopCatalogSync/packs/   ← 不可变数据包（可重下、可清理）
//    Application Support/ShopCatalog/
//      sync-control.json                     ← 控制状态（清缓存**不得**删除：
//                                              installedReleaseSeq / payloadHash /
//                                              撤回版本 / 最近检查时间）
//
//  ## 测试隔离（红线）
//
//  单测宿主 = 主 App，`FileManager.default` 指向用户真实沙盒。任何落盘测试
//  必须先 `useTemporaryForTesting()`，结束 `restoreDefaultForTesting()`。
//  包目录有独立重定向；控制状态复用 `ShopCatalogStorage` 的重定向
//  （两者都要调用，缺一个就会污染生产数据）。
//

import Foundation

// MARK: - 控制状态

/// 同步控制状态。持久化在 Application Support（清缓存不删），
/// 只保存最小必要状态，不保存任何下载正文。
nonisolated struct ShopCatalogSyncControl: Codable, Equatable, Sendable {
    /// 已安装的发布序号（0 = 从未安装过）
    var installedReleaseSeq: Int = 0
    /// 已安装数据包的 payloadHash（与根清单比对，决定要不要下载）
    var installedPayloadHash: String?
    /// 最近一次检查发布头的时间（节流用；失败也会推进，避免节流被错误状态击穿）
    var lastCheckedAt: Date?
    /// 已知的撤回控制版本
    var revocationEpoch: Int = 0

    /// 旧文件兼容：缺键按零值处理（struct 带默认值不会被合成 Decodable 自动兜底）
    init(
        installedReleaseSeq: Int = 0,
        installedPayloadHash: String? = nil,
        lastCheckedAt: Date? = nil,
        revocationEpoch: Int = 0
    ) {
        self.installedReleaseSeq = installedReleaseSeq
        self.installedPayloadHash = installedPayloadHash
        self.lastCheckedAt = lastCheckedAt
        self.revocationEpoch = revocationEpoch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            installedReleaseSeq: try container.decodeIfPresent(Int.self, forKey: .installedReleaseSeq) ?? 0,
            installedPayloadHash: try container.decodeIfPresent(String.self, forKey: .installedPayloadHash),
            lastCheckedAt: try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt),
            revocationEpoch: try container.decodeIfPresent(Int.self, forKey: .revocationEpoch) ?? 0
        )
    }
}

// MARK: - 存储根目录（测试隔离）

nonisolated enum ShopCatalogSyncStorage {

    /// 测试注入的临时目录；nil = 生产路径（Caches/ShopCatalogSync）
    private nonisolated(unsafe) static var testOverride: URL?

    static var directory: URL {
        if let testOverride { return testOverride }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("ShopCatalogSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var packsDirectory: URL {
        let dir = directory.appendingPathComponent("packs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var isTestOverridden: Bool { testOverride != nil }

    /// 测试专用：重定向到全新临时目录（与 ShopCatalogStorage.useTemporaryForTesting 配对使用）
    @discardableResult
    static func useTemporaryForTesting() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShopCatalogSyncTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        testOverride = url
        return url
    }

    /// 测试专用：恢复生产路径并清理临时目录
    static func restoreDefaultForTesting() {
        if let url = testOverride {
            try? FileManager.default.removeItem(at: url)
        }
        testOverride = nil
    }
}

// MARK: - 包缓存

nonisolated enum ShopCatalogPackCache {

    /// 控制状态文件（跟随 ShopCatalogStorage 的目录与测试隔离：
    /// Application Support/ShopCatalog/sync-control.json）
    static var controlURL: URL {
        ShopCatalogStorage.directory.appendingPathComponent("sync-control.json")
    }

    // MARK: 数据包（不可变，按 payloadHash 寻址）

    static func packURL(payloadHash: String) -> URL {
        ShopCatalogSyncStorage.packsDirectory.appendingPathComponent("\(payloadHash).json.gz")
    }

    /// 已缓存的数据包字节；nil = 未缓存（或文件被系统清掉 —— 索引与文件必须同时校验）
    static func cachedPackData(payloadHash: String) -> Data? {
        let url = packURL(payloadHash: payloadHash)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// 原子安装数据包。写入失败抛错（调用方保留旧状态，不推进 installedRevision）
    static func installPack(_ data: Data, payloadHash: String) throws {
        try data.write(to: packURL(payloadHash: payloadHash), options: .atomic)
    }

    // MARK: 控制状态

    static func loadControl() -> ShopCatalogSyncControl {
        guard FileManager.default.fileExists(atPath: controlURL.path),
              let data = try? Data(contentsOf: controlURL) else {
            return ShopCatalogSyncControl()
        }
        // 坏控制文件按「从未同步」处理：最多多下一次包，不会丢任何用户数据
        return (try? ShopCatalogJSONCoding.decoder().decode(ShopCatalogSyncControl.self, from: data))
            ?? ShopCatalogSyncControl()
    }

    static func saveControl(_ control: ShopCatalogSyncControl) {
        guard let data = try? ShopCatalogJSONCoding.encoder().encode(control) else { return }
        try? data.write(to: controlURL, options: .atomic)
    }

    /// 判断某次发布是否需要下载：序号或载荷摘要任一变化都要
    static func needsDownload(releaseSeq: Int, payloadHash: String, control: ShopCatalogSyncControl) -> Bool {
        control.installedReleaseSeq != releaseSeq || control.installedPayloadHash != payloadHash
    }

    // MARK: 冷启动恢复

    /// 按控制状态记录的 `installedPayloadHash` 读回已验证的缓存包并解码。
    ///
    /// 远端层只存在于内存（`ShopCatalogStore.remoteCatalog`），进程重启即归零；
    /// 而包缓存是不可变正文、跨启动仍在。这个方法是「重启后内容还在」的**唯一**来源。
    /// nil = 没有可恢复内容（从未安装 / 包被系统清理 / 包损坏），调用方应重新下载。
    static func restoredCatalog() -> ShopCatalog? {
        guard let hash = loadControl().installedPayloadHash,
              let data = cachedPackData(payloadHash: hash) else { return nil }
        return ShopCatalogCloudSyncValidator.catalog(fromVerifiedPack: data)
    }

    // MARK: 清理（§13.3：只清可重下的包，绝不动控制状态与个人数据）

    /// 清理下载数据包。返回释放的字节数。
    /// 控制状态里的 installedPayloadHash 一并清空 —— 否则会出现
    /// 「索引说装了、文件已消失」的永久失配。
    static func clearDownloadedContent() -> Int {
        var freed = 0
        let directory = ShopCatalogSyncStorage.packsDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) {
            for url in files {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if (try? FileManager.default.removeItem(at: url)) != nil {
                    freed += size
                }
            }
        }
        var control = loadControl()
        control.installedPayloadHash = nil
        saveControl(control)
        return freed
    }

    /// 当前缓存占用（字节），供设置页展示
    static func usageBytes() -> Int {
        let directory = ShopCatalogSyncStorage.packsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
