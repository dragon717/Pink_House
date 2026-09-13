import Compression
import CryptoKit
import Foundation

// MARK: - 缓存目录布局
//
// 对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md §13.1。
//
//   Library/Caches/TimeHall/
//     packs/     可重下的结构化数据包
//     media/     可重下的图片
//     staging/   未完成或待验证下载
//     index/     可重建索引
//   Library/Application Support/TimeHall/
//     control.json   最小控制状态（撤回版本、必要禁用状态）
//
// 可重建的大型内容**不加入**用户个人备份或私有云同步；
// 既有个人存储（`timeHall.treasured.v1`）与衣橱 / 照片 / 手账都不在这里。

nonisolated struct TimeHallCacheLayout: Sendable {
    let cachesRoot: URL
    let supportRoot: URL

    var packsDirectory: URL { cachesRoot.appendingPathComponent("packs", isDirectory: true) }
    var mediaDirectory: URL { cachesRoot.appendingPathComponent("media", isDirectory: true) }
    var stagingDirectory: URL { cachesRoot.appendingPathComponent("staging", isDirectory: true) }
    var indexDirectory: URL { cachesRoot.appendingPathComponent("index", isDirectory: true) }
    var controlFileURL: URL { supportRoot.appendingPathComponent("control.json") }
    var packIndexURL: URL { indexDirectory.appendingPathComponent("packs.json") }
    var mediaIndexURL: URL { indexDirectory.appendingPathComponent("media.json") }

    var allDirectories: [URL] {
        [cachesRoot, supportRoot, packsDirectory, mediaDirectory, stagingDirectory, indexDirectory]
    }

    static func live(fileManager: FileManager = .default) -> TimeHallCacheLayout {
        let caches =
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let support =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return TimeHallCacheLayout(
            cachesRoot: caches.appendingPathComponent("TimeHall", isDirectory: true),
            supportRoot: support.appendingPathComponent("TimeHall", isDirectory: true)
        )
    }

    /// 测试用布局：所有状态落在给定根目录下，不触碰真实缓存目录。
    static func testing(at root: URL) -> TimeHallCacheLayout {
        TimeHallCacheLayout(
            cachesRoot: root.appendingPathComponent("Caches/TimeHall", isDirectory: true),
            supportRoot: root.appendingPathComponent("Support/TimeHall", isDirectory: true)
        )
    }
}

// MARK: - 缓存错误

nonisolated enum TimeHallCacheError: Error, Sendable, Equatable, Hashable {
    case invalidIdentifier
    case staleGeneration
    case writeFailed
    case readFailed
    case sizeLimitExceeded
    case checksumMismatch
    case unsupportedEncoding
    case malformedArchive
    case notInstalled

    var readError: TimeHallReadError {
        switch self {
        case .invalidIdentifier: return .invalidIdentifier
        case .staleGeneration: return .cancelled
        case .writeFailed, .readFailed: return .unknown
        case .sizeLimitExceeded: return .packTooLarge
        case .checksumMismatch: return .packHashMismatch
        case .unsupportedEncoding: return .unsupportedEncoding
        case .malformedArchive: return .packDecodeFailed
        case .notInstalled: return .missingDependency
        }
    }
}

// MARK: - gzip 解码

/// CRC-32（IEEE 802.3，gzip 尾部校验用）
nonisolated enum TimeHallCRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

/// 数据包编解码（§6.3 `encoding` 初始限定 `json+gzip`）。
///
/// 已实测：Apple `Compression` 框架的 `COMPRESSION_ZLIB` 处理的是**裸 DEFLATE**（RFC 1951），
/// gzip 包体正好是裸 DEFLATE，因此去掉 gzip 头尾即可解。
/// 解压结果再由 gzip 尾部自带的 CRC-32 与 ISIZE 双向校验——
/// 一旦 DEFLATE 解出来的字节不对，CRC 必然不匹配，不会把错数据当成功。
nonisolated enum TimeHallPackCodec {
    /// SHA-256 十六进制摘要（小写）
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 把下载到的字节还原为 JSON 字节
    static func decodeJSON(
        _ data: Data,
        encoding: String,
        limits: TimeHallCacheLimits = .default
    ) throws -> Data {
        switch encoding {
        case TimeHallChannel.encodingJSONPlain:
            guard data.count <= limits.maxPackCompressedBytes else {
                throw TimeHallCacheError.sizeLimitExceeded
            }
            return data
        case TimeHallChannel.encodingJSONGzip:
            return try gunzip(data, limits: limits)
        default:
            throw TimeHallCacheError.unsupportedEncoding
        }
    }

    /// gzip → 原始字节
    static func gunzip(_ data: Data, limits: TimeHallCacheLimits = .default) throws -> Data {
        // 最短合法 gzip 流：10 字节头 + 至少 1 字节 DEFLATE + 8 字节尾
        guard data.count >= 19 else { throw TimeHallCacheError.malformedArchive }
        guard data[data.startIndex] == 0x1F, data[data.startIndex + 1] == 0x8B else {
            throw TimeHallCacheError.malformedArchive
        }
        guard data[data.startIndex + 2] == 0x08 else {
            // CM != 8，不是 deflate
            throw TimeHallCacheError.unsupportedEncoding
        }

        let flags = data[data.startIndex + 3]
        var offset = data.startIndex + 10

        // FEXTRA
        if flags & 0x04 != 0 {
            guard offset + 2 <= data.endIndex - 8 else { throw TimeHallCacheError.malformedArchive }
            let extraLength = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + extraLength
        }
        // FNAME
        if flags & 0x08 != 0 {
            offset = skipZeroTerminated(data, from: offset)
        }
        // FCOMMENT
        if flags & 0x10 != 0 {
            offset = skipZeroTerminated(data, from: offset)
        }
        // FHCRC
        if flags & 0x02 != 0 {
            offset += 2
        }

        let trailerStart = data.endIndex - 8
        guard offset >= data.startIndex, offset <= trailerStart else {
            throw TimeHallCacheError.malformedArchive
        }

        let expectedCRC = readUInt32LE(data, at: trailerStart)
        let expectedSize = Int(readUInt32LE(data, at: trailerStart + 4))

        guard expectedSize > 0 else { throw TimeHallCacheError.malformedArchive }
        guard expectedSize <= limits.maxPackUncompressedBytes else {
            throw TimeHallCacheError.sizeLimitExceeded
        }
        if data.count > 0 {
            let ratio = expectedSize / max(data.count, 1)
            guard ratio <= limits.maxDecompressionRatio else {
                throw TimeHallCacheError.sizeLimitExceeded
            }
        }

        let body = data.subdata(in: offset..<trailerStart)
        guard let decoded = inflateRaw(body, expectedSize: expectedSize) else {
            throw TimeHallCacheError.malformedArchive
        }
        guard decoded.count == expectedSize else {
            throw TimeHallCacheError.malformedArchive
        }
        guard TimeHallCRC32.checksum(decoded) == expectedCRC else {
            throw TimeHallCacheError.checksumMismatch
        }
        return decoded
    }

    private static func skipZeroTerminated(_ data: Data, from start: Int) -> Int {
        var index = start
        while index < data.endIndex, data[index] != 0 {
            index += 1
        }
        return index + 1
    }

    private static func readUInt32LE(_ data: Data, at index: Int) -> UInt32 {
        guard index + 4 <= data.endIndex else { return 0 }
        return UInt32(data[index])
            | (UInt32(data[index + 1]) << 8)
            | (UInt32(data[index + 2]) << 16)
            | (UInt32(data[index + 3]) << 24)
    }

    private static func inflateRaw(_ payload: Data, expectedSize: Int) -> Data? {
        guard !payload.isEmpty, expectedSize > 0 else { return nil }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            payload.withUnsafeBytes { source -> Int in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                    let sourceBase = source.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(
                    destinationBase,
                    expectedSize,
                    sourceBase,
                    payload.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        return output.prefix(written)
    }
}

// MARK: - 数据包缓存

/// 结构化数据包的文件缓存与安装状态（§10.2 / §11.2 步骤 13–14 / §13）。
///
/// 以 actor 串行化所有磁盘操作，因此安装事务在 `await` 之间不会被其它请求插入；
/// actor 的执行体不在主线程上，JSON 编解码与文件写入都不占用主线程（§10.4）。
actor TimeHallPackCache {
    private let layout: TimeHallCacheLayout
    private let limits: TimeHallCacheLimits
    private let fileManager: FileManager

    private var generationValue: UInt64 = 0
    private var installedPacks: [String: TimeHallInstalledPack] = [:]
    private var accessDates: [String: Date] = [:]
    private var isPrepared = false

    init(
        layout: TimeHallCacheLayout = .live(),
        limits: TimeHallCacheLimits = .default,
        fileManager: FileManager = .default
    ) {
        self.layout = layout
        self.limits = limits
        self.fileManager = fileManager
    }

    // MARK: 生命周期

    private func prepareIfNeeded() {
        guard !isPrepared else { return }
        isPrepared = true
        for directory in layout.allDirectories {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        loadIndex()
    }

    /// 当前缓存 generation。清理缓存时会递增（§13.3）。
    func currentGeneration() -> UInt64 {
        prepareIfNeeded()
        return generationValue
    }

    /// 递增 generation，用于让仍在飞行中的旧下载任务失效（§13.3 步骤 1–2）。
    ///
    /// 只递增 generation 不够——旧任务完成后必须比对 generation，
    /// 否则刚清空的缓存会被旧回调重新写满。
    @discardableResult
    func bumpGeneration() -> UInt64 {
        prepareIfNeeded()
        generationValue += 1
        return generationValue
    }

    // MARK: 安装

    /// 已安装分片。索引记录与文件存在性**同时校验**：
    /// 系统可能提前清理缓存目录，存在索引不代表文件还在（§13.1）。
    func installedPack(partitionID: String) -> TimeHallInstalledPack? {
        prepareIfNeeded()
        guard let record = installedPacks[partitionID] else { return nil }
        guard fileManager.fileExists(atPath: fileURL(for: record).path) else {
            // 文件已消失：清掉这条索引，让上层重新下载而不是误判命中（§18.3 C04）
            installedPacks.removeValue(forKey: partitionID)
            accessDates.removeValue(forKey: partitionID)
            persistIndex()
            return nil
        }
        return record
    }

    func isInstalled(partitionID: String) -> Bool {
        installedPack(partitionID: partitionID) != nil
    }

    /// 原子安装一个数据包。
    ///
    /// 流程：写 staging → 校验大小 → 检查 generation 未变 → 原子替换进 packs → 落索引。
    /// 任何一步失败都不修改既有有效快照（§16.1 / §18.3 C06）。
    @discardableResult
    func install(
        descriptor: TimeHallPartitionDescriptor,
        payload: TimeHallPackPayload,
        generation: UInt64
    ) throws -> TimeHallInstalledPack {
        prepareIfNeeded()
        guard TimeHallPartitionID.isSafe(descriptor.partitionID) else {
            throw TimeHallCacheError.invalidIdentifier
        }
        guard generation == generationValue else { throw TimeHallCacheError.staleGeneration }

        let jsonData = try JSONEncoder().encode(payload)
        guard jsonData.count <= limits.maxPackUncompressedBytes else {
            throw TimeHallCacheError.sizeLimitExceeded
        }

        let fileComponent = TimeHallPartitionID.fileNameComponent(for: descriptor.partitionID)
        let stagingURL = layout.stagingDirectory
            .appendingPathComponent("\(fileComponent).\(generation).json")
        let targetURL = layout.packsDirectory
            .appendingPathComponent("\(fileComponent).json")

        do {
            try jsonData.write(to: stagingURL, options: .atomic)
        } catch {
            throw TimeHallCacheError.writeFailed
        }

        // staging 已落地，再次确认没有在等待期间被清理
        guard generation == generationValue else {
            try? fileManager.removeItem(at: stagingURL)
            throw TimeHallCacheError.staleGeneration
        }

        do {
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: stagingURL, to: targetURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw TimeHallCacheError.writeFailed
        }

        let record = TimeHallInstalledPack(
            partitionID: descriptor.partitionID,
            brandID: descriptor.brandID,
            entityType: descriptor.entityType,
            packRecordName: descriptor.packRecordName,
            payloadHash: descriptor.payloadHash,
            partitionRevision: descriptor.partitionRevision,
            coverageStatus: descriptor.coverageStatus,
            checkedThrough: descriptor.checkedThrough,
            dayCoverage: descriptor.dayCoverage,
            recordCount: descriptor.recordCount,
            installedAt: Date(),
            generation: generation
        )
        installedPacks[descriptor.partitionID] = record
        accessDates[descriptor.partitionID] = Date()
        persistIndex()
        enforceBudget()
        return record
    }

    // MARK: 读取

    /// 读取并解码一个已安装分片。解码在 actor 上执行，不占用主线程。
    func fragment(partitionID: String) throws -> TimeHallCatalogFragmentDTO? {
        guard let record = installedPack(partitionID: partitionID) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL(for: record))
        } catch {
            // 文件在两次检查之间被系统清掉：移除索引并报告未安装
            installedPacks.removeValue(forKey: partitionID)
            persistIndex()
            return nil
        }
        do {
            let payload = try JSONDecoder().decode(TimeHallPackPayload.self, from: data)
            accessDates[partitionID] = Date()
            return payload.records
        } catch {
            // 落盘内容损坏：删除文件并移除索引，避免反复命中坏包
            try? fileManager.removeItem(at: fileURL(for: record))
            installedPacks.removeValue(forKey: partitionID)
            persistIndex()
            throw TimeHallCacheError.readFailed
        }
    }

    /// 批量读取多个分片
    func fragments(partitionIDs: [String]) -> [String: TimeHallCatalogFragmentDTO] {
        var result: [String: TimeHallCatalogFragmentDTO] = [:]
        for partitionID in partitionIDs {
            if let fragment = try? fragment(partitionID: partitionID) {
                result[partitionID] = fragment
            }
        }
        return result
    }

    /// 某品牌已安装的全部分片
    func installedPacks(brandID: String) -> [TimeHallInstalledPack] {
        prepareIfNeeded()
        return
            installedPacks
            .values
            .filter { $0.brandID == brandID }
            .filter { fileManager.fileExists(atPath: fileURL(for: $0).path) }
            .sorted { $0.partitionID < $1.partitionID }
    }

    // MARK: 用量与预算

    func usage() -> TimeHallCacheUsage {
        prepareIfNeeded()
        return TimeHallCacheUsage(
            packBytes: directorySize(layout.packsDirectory),
            // 媒体用量由 TimeHallMediaCache 统计；两者共用同一布局，但口径不重复计算
            mediaBytes: 0,
            stagingBytes: directorySize(layout.stagingDirectory),
            packCount: installedPacks.count,
            mediaCount: 0,
            lastCheckedAt: accessDates.values.max()
        )
    }

    /// 超出预算时按最近使用情况回收可重建内容（§13.4）。
    ///
    /// 只回收数据包；**不**触碰个人资产，也不回收当前正在展示的文件之外的任何私人数据。
    func enforceBudget() {
        prepareIfNeeded()
        var total = directorySize(layout.packsDirectory)
        guard total > limits.packBudgetBytes else { return }

        // 最近未使用的分片优先回收；按 partitionID 排序保证确定性
        let ordered = accessDates.sorted {
            if $0.value != $1.value { return $0.value < $1.value }
            return $0.key < $1.key
        }
        let protected = Set(accessDates.sorted { $0.value > $1.value }.prefix(2).map(\.key))

        for (partitionID, _) in ordered {
            guard total > limits.packBudgetBytes else { break }
            guard !protected.contains(partitionID) else { continue }
            guard let record = installedPacks[partitionID] else { continue }
            let url = fileURL(for: record)
            let size = fileSize(url)
            try? fileManager.removeItem(at: url)
            installedPacks.removeValue(forKey: partitionID)
            accessDates.removeValue(forKey: partitionID)
            total -= size
        }
        persistIndex()
    }

    // MARK: 清理

    /// 清空全部可重新下载的下载内容。
    ///
    /// 不删除：Bundle 种子、收藏、撤回控制版本（§13.3 步骤 7）。
    func clearDownloadedContent() throws {
        prepareIfNeeded()
        generationValue += 1
        installedPacks.removeAll()
        accessDates.removeAll()
        for directory in [layout.packsDirectory, layout.mediaDirectory, layout.stagingDirectory, layout.indexDirectory] {
            try? fileManager.removeItem(at: directory)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// 回收未被当前版本引用的孤儿包（§9.5），保留宽限期避免删除仍在下载的合法旧包。
    func collectOrphanedPacks(gracePeriod: TimeInterval = 24 * 3600) {
        prepareIfNeeded()
        let referenced = Set(installedPacks.keys.map {
            "\(TimeHallPartitionID.fileNameComponent(for: $0)).json"
        })
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: layout.packsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else { return }

        let cutoff = Date().addingTimeInterval(-gracePeriod)
        for url in entries where !referenced.contains(url.lastPathComponent) {
            let modified =
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            guard modified < cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: 内部

    private func fileURL(for record: TimeHallInstalledPack) -> URL {
        layout.packsDirectory.appendingPathComponent(
            "\(TimeHallPartitionID.fileNameComponent(for: record.partitionID)).json")
    }

    private func persistIndex() {
        do {
            try fileManager.createDirectory(
                at: layout.indexDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(installedPacks)
            try data.write(to: layout.packIndexURL, options: .atomic)
        } catch {
            // 索引只是加速器，写失败不影响正确性：下次读取会退回「无已安装分片」
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: layout.packIndexURL) else { return }
        guard let decoded = try? JSONDecoder().decode([String: TimeHallInstalledPack].self, from: data)
        else { return }
        installedPacks = decoded
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
