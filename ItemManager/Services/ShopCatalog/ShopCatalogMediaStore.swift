//
//  ShopCatalogMediaStore.swift
//  ItemManager
//
//  「店家上新」远端图片（THMedia）按需下载与缓存（消费端）。
//
//  ## 为什么需要这一层
//
//  运营上传的商品图在设备沙盒里是 `local:<文件名>` 引用 —— **只在原设备有效**。
//  发布端（Mac）把这些图上传成 THMedia，并把包里的引用改写成
//  `thmedia:<contentHash>`；没有这一层，换台设备解析不到文件 →
//  商品图一律占位（2026-09-25 实测：目录数据全拉到了，图全空）。
//
//  ## 取舍
//
//    · **按需下载**，不在同步包里一起拉：图有几 MB 到几十 MB，首屏只需要屏内那几张；
//    · 同一张图并发请求合并成一次（列表快速滚动会重复命中同一 hash）；
//    · 本次会话内失败的 hash 不再重试，避免「图没传」变成无限打网络；
//    · 缓存落在 Caches（可重下、可被系统清理），清理后重新解析即可。
//

import Foundation

@MainActor
final class ShopCatalogMediaStore {

    static let shared = ShopCatalogMediaStore()

    private let reader: any ShopCatalogPublicReading

    /// 正在下载的任务（按内容摘要合并）
    private var inFlight: [String: Task<URL?, Never>] = [:]
    /// 本次会话内已确认失败的摘要（不再重试）
    private var failed: Set<String> = []

    init(reader: any ShopCatalogPublicReading = ShopCatalogPublicCloudReader()) {
        self.reader = reader
    }

    /// 解析图片引用 → 可直接读的本地文件。
    /// - Returns: 本地文件 URL；**nil = 不是远端媒体引用 / 下载失败**，
    ///            调用方回退到既有解析（Bundle / 本地上传图）或占位图。
    func resolvedURL(for reference: String?) async -> URL? {
        await resolvedURL(
            mediaKey: ShopCatalogSyncProtocol.resolvedMediaKey(nil, fallbackReferences: [reference]))
    }

    /// 按**媒体键**解析（公共数据库字段配置方案 §2.2 的 canonical 口径）。
    /// 调用方应当先用 `ShopCatalogSyncProtocol.resolvedMediaKey(_:fallbackReferences:)`
    /// 把 `mediaKey` 与旧 `thmedia:` 引用归一，再进这里。
    func resolvedURL(mediaKey: String?) async -> URL? {
        guard let hash = mediaKey else { return nil }
        if let cached = ShopCatalogPackCache.cachedMediaURL(contentHash: hash) { return cached }
        if failed.contains(hash) { return nil }
        if let task = inFlight[hash] { return await task.value }

        let task = Task<URL?, Never> { await download(hash) }
        inFlight[hash] = task
        let url = await task.value
        inFlight[hash] = nil
        if url == nil { failed.insert(hash) }
        return url
    }

    /// 测试用：清空本次会话的失败记忆
    func resetSessionFailuresForTesting() {
        failed.removeAll()
    }

    /// 清掉某个摘要的「本次会话内已失败」记忆，让下一次 `resolvedURL` 重新尝试。
    ///
    /// 供 UI 的「重试」入口调用（iOS 运营上传实施方案 §5：下载失败必须显示明确占位
    /// **和重试入口**，不能把加载失败当成「这张图本来就没有」）。
    /// 只清失败记忆，不动已装好的缓存 —— 缓存命中时 `resolvedURL` 根本不会走到网络。
    func clearSessionFailure(mediaKey: String) {
        failed.remove(mediaKey)
    }

    private func download(_ hash: String) async -> URL? {
        do {
            let data = try await reader.fetchMedia(contentHash: hash)
            let url = try ShopCatalogPackCache.installMedia(
                data, contentHash: hash, fileExtension: Self.inferredFileExtension(data))
            return url
        } catch {
            print("[ShopCatalogSync] 媒体下载失败 \(hash.prefix(12))：\(error.localizedDescription)")
            return nil
        }
    }

    /// 缓存文件后缀（按魔数判定；UIImage 不靠后缀解码，这里只为文件名可读 / 便于排查）
    nonisolated static func inferredFileExtension(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 4 else { return "bin" }
        if bytes[0] == 0xFF && bytes[1] == 0xD8 { return "jpg" }
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 { return "png" }
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 { return "gif" }
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 {
            return bytes.count >= 12 && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42
                ? "webp" : "heic"
        }
        return "bin"
    }
}
