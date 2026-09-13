import Foundation
import ImageIO
import UIKit

// MARK: - 媒体缓存
//
// 对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md §12.1 / §13。
//
// 默认策略：
//   - 小量必要封面随 Bundle（离线种子）；
//   - 经授权可重分发的图片通过 `THMedia` 提供；
//   - 列表先取缩略图，进入详情再取较清晰版本；
//   - 缺图显示占位，**不悄悄切回任意第三方网址重新获取**；
//   - 缓存的 key 使用稳定媒体 ID（内容摘要 + 变体），**不是** URL
//     （CloudKit 返回的是带签名临时地址，会过期，不能当业务 ID）。

/// 一条本地媒体记录
nonisolated struct TimeHallMediaRecord: Codable, Sendable, Hashable {
    /// 稳定业务键（由调用方给出，例如 <canonicalEntityID>#thumb）
    let mediaKey: String
    /// 内容摘要，落盘文件名
    let contentHash: String
    let mimeType: String
    let byteCount: Int
    /// 该媒体在云端对应的 `THMedia` Record ID
    let recordName: String
    let storedAt: Date
}

actor TimeHallMediaCache {
    private let layout: TimeHallCacheLayout
    private let limits: TimeHallCacheLimits
    private let fileManager: FileManager

    private var records: [String: TimeHallMediaRecord] = [:]
    private var accessDates: [String: Date] = [:]
    private var isPrepared = false
    private var generationValue: UInt64 = 0

    /// 已解码图片的内存缓存。按张数 + 成本双限，避免大图把内存顶满（§15.3）。
    private let memoryCache = NSCache<NSString, UIImage>()

    init(
        layout: TimeHallCacheLayout = .live(),
        limits: TimeHallCacheLimits = .default,
        fileManager: FileManager = .default
    ) {
        self.layout = layout
        self.limits = limits
        self.fileManager = fileManager
        memoryCache.countLimit = 128
        memoryCache.totalCostLimit = 96 * 1024 * 1024
    }

    // MARK: 生命周期

    private func prepareIfNeeded() {
        guard !isPrepared else { return }
        isPrepared = true
        for directory in [layout.mediaDirectory, layout.stagingDirectory, layout.indexDirectory] {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        loadIndex()
    }

    // MARK: 安装

    func currentGeneration() -> UInt64 {
        prepareIfNeeded()
        return generationValue
    }

    @discardableResult
    func bumpGeneration() -> UInt64 {
        prepareIfNeeded()
        generationValue += 1
        return generationValue
    }

    /// 安装一份已下载的媒体。落盘前校验类型白名单、字节上限与内容摘要（§12.3）。
    ///
    /// `generation` 必须是发起下载时取得的缓存 generation：
    /// 清理缓存后 generation 递增，旧回调会因为不匹配而被拒绝（§13.3）。
    @discardableResult
    func install(
        media: TimeHallDownloadedMedia,
        mediaKey: String,
        generation: UInt64
    ) throws -> TimeHallMediaRecord {
        prepareIfNeeded()
        guard Self.isSafeMediaKey(mediaKey) else {
            throw TimeHallCacheError.invalidIdentifier
        }
        guard generation == generationValue else {
            throw TimeHallCacheError.staleGeneration
        }
        guard Self.allowedMimeTypes.contains(media.mimeType) else {
            throw TimeHallCacheError.unsupportedEncoding
        }
        guard media.bytes.count > 0, media.bytes.count <= limits.maxMediaBytes else {
            throw TimeHallCacheError.sizeLimitExceeded
        }
        guard TimeHallPackCodec.sha256Hex(media.bytes) == media.contentHash else {
            throw TimeHallCacheError.checksumMismatch
        }

        let target = fileURL(contentHash: media.contentHash, mimeType: media.mimeType)
        do {
            try fileManager.createDirectory(
                at: layout.mediaDirectory, withIntermediateDirectories: true)
            try media.bytes.write(to: target, options: .atomic)
        } catch {
            throw TimeHallCacheError.writeFailed
        }

        let record = TimeHallMediaRecord(
            mediaKey: mediaKey,
            contentHash: media.contentHash,
            mimeType: media.mimeType,
            byteCount: media.bytes.count,
            recordName: media.recordName,
            storedAt: Date()
        )
        records[mediaKey] = record
        accessDates[mediaKey] = Date()
        persistIndex()
        enforceBudget()
        return record
    }

    // MARK: 读取

    /// 本地是否已有该媒体
    func hasMedia(mediaKey: String) -> Bool {
        prepareIfNeeded()
        guard let record = records[mediaKey] else { return false }
        guard fileManager.fileExists(atPath: fileURL(for: record).path) else {
            records.removeValue(forKey: mediaKey)
            accessDates.removeValue(forKey: mediaKey)
            persistIndex()
            return false
        }
        return true
    }

    /// 读取并降采样图片。
    ///
    /// 返回 `nil` 表示本地没有该媒体——**调用方应显示占位图**，
    /// 不要因此改走第三方网址（§12.1）。
    func image(
        mediaKey: String,
        targetPixelDimension: CGFloat = 1200
    ) -> UIImage? {
        prepareIfNeeded()
        let cacheKey = "\(mediaKey)@\(Int(targetPixelDimension))" as NSString
        if let cached = memoryCache.object(forKey: cacheKey) { return cached }

        guard let record = records[mediaKey] else { return nil }
        let url = fileURL(for: record)
        guard fileManager.fileExists(atPath: url.path) else {
            records.removeValue(forKey: mediaKey)
            accessDates.removeValue(forKey: mediaKey)
            persistIndex()
            return nil
        }

        guard
            let image = TimeHallImageDownsampler.load(
                url: url, maxPixelDimension: targetPixelDimension)
        else { return nil }

        accessDates[mediaKey] = Date()
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        memoryCache.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }

    /// 清空内存图片缓存（收到内存警告时调用，不影响磁盘缓存）
    func purgeMemory() {
        memoryCache.removeAllObjects()
    }

    // MARK: 用量与预算

    func usage() -> TimeHallCacheUsage {
        prepareIfNeeded()
        var packUsage = TimeHallCacheUsage()
        packUsage.mediaBytes = directorySize(layout.mediaDirectory)
        packUsage.mediaCount = records.count
        packUsage.stagingBytes = directorySize(layout.stagingDirectory)
        packUsage.lastCheckedAt = accessDates.values.max()
        return packUsage
    }

    func enforceBudget() {
        prepareIfNeeded()
        var total = directorySize(layout.mediaDirectory)
        guard total > limits.mediaBudgetBytes else { return }

        let ordered = accessDates.sorted {
            if $0.value != $1.value { return $0.value < $1.value }
            return $0.key < $1.key
        }
        let protected = Set(accessDates.sorted { $0.value > $1.value }.prefix(8).map(\.key))

        for (mediaKey, _) in ordered {
            guard total > limits.mediaBudgetBytes else { break }
            guard !protected.contains(mediaKey) else { continue }
            guard let record = records[mediaKey] else { continue }
            let url = fileURL(for: record)
            total -= fileSize(url)
            try? fileManager.removeItem(at: url)
            records.removeValue(forKey: mediaKey)
            accessDates.removeValue(forKey: mediaKey)
            memoryCache.removeObject(forKey: "\(mediaKey)@1200" as NSString)
        }
        persistIndex()
    }

    /// 清理全部可重新下载的媒体
    func clearDownloadedContent() throws {
        prepareIfNeeded()
        generationValue += 1
        records.removeAll()
        accessDates.removeAll()
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: layout.mediaDirectory)
        try? fileManager.removeItem(at: layout.stagingDirectory)
        try? fileManager.createDirectory(
            at: layout.mediaDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(
            at: layout.stagingDirectory, withIntermediateDirectories: true)
        persistIndex()
    }

    // MARK: 内部

    static let allowedMimeTypes: Set<String> = [
        "image/jpeg", "image/png", "image/webp", "image/heic", "image/gif",
    ]

    /// 媒体键允许的字符集：字母数字与 `-._#/`，拒绝路径穿越
    static func isSafeMediaKey(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 200 else { return false }
        guard !value.contains(".."), !value.hasPrefix("/") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-._#/:")
        return value.lowercased().unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func fileExtension(for mimeType: String) -> String {
        switch mimeType {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        case "image/gif": return "gif"
        default: return "bin"
        }
    }

    private func fileURL(contentHash: String, mimeType: String) -> URL {
        layout.mediaDirectory.appendingPathComponent(
            "\(contentHash).\(Self.fileExtension(for: mimeType))")
    }

    private func fileURL(for record: TimeHallMediaRecord) -> URL {
        fileURL(contentHash: record.contentHash, mimeType: record.mimeType)
    }

    private func persistIndex() {
        do {
            try fileManager.createDirectory(
                at: layout.indexDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(records).write(to: layout.mediaIndexURL, options: .atomic)
        } catch {
            // 索引可重建，写失败不影响正确性
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: layout.mediaIndexURL) else { return }
        guard let decoded = try? JSONDecoder().decode([String: TimeHallMediaRecord].self, from: data)
        else { return }
        records = decoded
        let now = Date()
        for key in decoded.keys { accessDates[key] = now }
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else { return 0 }
        return entries.reduce(Int64(0)) { $0 + fileSize($1) }
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true else { return 0 }
        return Int64(values?.fileSize ?? 0)
    }
}

// MARK: - 图片降采样

/// 只解码到目标尺寸的图片加载器，避免整张原图进入内存（§12.3 降采样、§15.3 内存峰值）。
nonisolated enum TimeHallImageDownsampler {
    static func load(url: URL, maxPixelDimension: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image)
    }

    static func load(data: Data, maxPixelDimension: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image)
    }
}
