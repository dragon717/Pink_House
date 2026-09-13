import CloudKit
import Foundation

// MARK: - CloudKit 公共只读 Reader
//
// 对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md §1.2 E / §6 / §7.3 / §16。
//
// 硬约束：
//   1. 只用 `publicCloudDatabase`，容器 `iCloud.bugod2.ItemManager`（不混入 Notice / 私人 Clothing /
//      `iCloud.bugod2.SkirtMarket` 的业务 schema）。
//   2. **类型层面只有读取能力**：本类型没有 save / delete / modify 方法，
//      普通用户客户端不具备对公共库任何写能力（§7.3）。
//   3. **不以用户登录 iCloud 为前提**：公共库在设备没有 iCloud 账户时也可访问，
//      因此这里**不**检查 `accountStatus`（§1.2 E）。
//   4. 正常读链路使用已知 Record ID 与显式批量 fetch，
//      不先扫描整个 Public Database（§6.6）。

/// 批量读取能力。仓储在可用时优先走批量 fetch，减少往返次数（§6.6）。
protocol TimeHallPublicBatchReading: Sendable {
    func fetchPacks(recordNames: [String]) async
        -> [String: Result<TimeHallDownloadedPack, TimeHallReadError>]
}

nonisolated struct TimeHallPublicCloudReader: TimeHallPublicReading, TimeHallPublicBatchReading {
    static let containerIdentifier = "iCloud.bugod2.ItemManager"

    let containerIdentifier: String
    let limits: TimeHallCacheLimits

    init(
        containerIdentifier: String = TimeHallPublicCloudReader.containerIdentifier,
        limits: TimeHallCacheLimits = .default
    ) {
        self.containerIdentifier = containerIdentifier
        self.limits = limits
    }

    /// 仅在容器可构造时返回 reader；CloudKit 完全不可用时由调用方退回本地只读。
    static func makeIfAvailable(limits: TimeHallCacheLimits = .default)
        -> TimeHallPublicCloudReader?
    {
        let identifier = containerIdentifier
        guard !identifier.isEmpty else { return nil }
        return TimeHallPublicCloudReader(containerIdentifier: identifier, limits: limits)
    }

    private var database: CKDatabase {
        CKContainer(identifier: containerIdentifier).publicCloudDatabase
    }

    // MARK: 发布头

    func fetchReleaseMetadata() async throws -> TimeHallReleaseMetadata {
        // 只取不含 Asset 的元数据，确认版本改变后才取根清单（§6.2）
        let records = try await fetchRecords(
            recordNames: [TimeHallChannel.releaseRecordName],
            desiredKeys: [
                "releaseSeq", "schemaVersion", "publishedAt", "rootIndexHash", "revocationEpoch",
                "minimumReaderVersion", "previousReleaseSeq",
            ]
        )
        guard let record = records[TimeHallChannel.releaseRecordName] else {
            throw TimeHallReadError.releaseMissing
        }
        return TimeHallReleaseMetadata(
            recordName: TimeHallChannel.releaseRecordName,
            releaseSeq: intValue(record, "releaseSeq") ?? 0,
            schemaVersion: intValue(record, "schemaVersion") ?? 0,
            publishedAt: dateString(record, "publishedAt"),
            rootIndexHash: stringValue(record, "rootIndexHash"),
            revocationEpoch: intValue(record, "revocationEpoch") ?? 0,
            minimumReaderVersion: intValue(record, "minimumReaderVersion") ?? 0,
            previousReleaseSeq: intValue(record, "previousReleaseSeq") ?? 0,
            changeTag: record.recordChangeTag
        )
    }

    func fetchRootIndex(for release: TimeHallReleaseMetadata) async throws
        -> TimeHallDownloadedRootIndex
    {
        let records = try await fetchRecords(
            recordNames: [release.recordName],
            desiredKeys: ["rootIndexHash", "rootIndexAsset"]
        )
        guard let record = records[release.recordName] else {
            throw TimeHallReadError.releaseMissing
        }
        guard let bytes = assetBytes(record, "rootIndexAsset") else {
            throw TimeHallReadError.rootIndexHashMismatch
        }
        guard bytes.count <= limits.maxPackCompressedBytes else {
            throw TimeHallReadError.packTooLarge
        }
        let declared = stringValue(record, "rootIndexHash")
        let rootIndex: TimeHallRootIndex
        do {
            rootIndex = try JSONDecoder().decode(TimeHallRootIndex.self, from: bytes)
        } catch {
            throw TimeHallReadError.unsupportedSchema
        }
        return TimeHallDownloadedRootIndex(
            rootIndex: rootIndex,
            rawBytes: bytes,
            declaredHash: declared
        )
    }

    // MARK: 数据包

    func fetchPack(recordName: String) async throws -> TimeHallDownloadedPack {
        let outcome = await fetchPacks(recordNames: [recordName])
        guard let result = outcome[recordName] else {
            throw TimeHallReadError.missingDependency
        }
        return try result.get()
    }

    /// 显式批量 fetch（§6.6）。缺失或失败的记录按各自原因返回，不把首个分页当完整数据集。
    func fetchPacks(recordNames: [String]) async
        -> [String: Result<TimeHallDownloadedPack, TimeHallReadError>]
    {
        guard !recordNames.isEmpty else { return [:] }
        var result: [String: Result<TimeHallDownloadedPack, TimeHallReadError>] = [:]
        do {
            let records = try await fetchRecords(
                recordNames: recordNames,
                desiredKeys: [
                    "payloadHash", "encoding", "compressedBytes", "uncompressedBytes", "payloadAsset",
                ]
            )
            for recordName in recordNames {
                guard let record = records[recordName] else {
                    result[recordName] = .failure(.missingDependency)
                    continue
                }
                result[recordName] = decodePack(record)
            }
        } catch let error as TimeHallReadError {
            for recordName in recordNames { result[recordName] = .failure(error) }
        } catch {
            for recordName in recordNames { result[recordName] = .failure(.cloudUnavailable) }
        }
        return result
    }

    private func decodePack(_ record: CKRecord) -> Result<TimeHallDownloadedPack, TimeHallReadError> {
        guard let raw = assetBytes(record, "payloadAsset") else {
            return .failure(.packDecodeFailed)
        }
        let declaredHash = stringValue(record, "payloadHash")
        let encoding = stringValue(record, "encoding")
        let compressedBytes = intValue(record, "compressedBytes") ?? raw.count
        let uncompressedBytes = intValue(record, "uncompressedBytes") ?? 0

        guard compressedBytes <= limits.maxPackCompressedBytes else {
            return .failure(.packTooLarge)
        }
        // 解码前校验摘要（§12.3）：比对的是压缩文件本身的字节摘要
        guard !declaredHash.isEmpty, TimeHallPackCodec.sha256Hex(raw) == declaredHash else {
            return .failure(.packHashMismatch)
        }
        let jsonData: Data
        do {
            jsonData = try TimeHallPackCodec.decodeJSON(raw, encoding: encoding, limits: limits)
        } catch let error as TimeHallCacheError {
            return .failure(error.readError)
        } catch {
            return .failure(.packDecodeFailed)
        }
        guard jsonData.count <= limits.maxPackUncompressedBytes else {
            return .failure(.packTooLarge)
        }
        // 声明解压大小与实际不符时拒绝：可能是发布侧问题，也可能是压缩炸弹
        if uncompressedBytes > 0, jsonData.count != uncompressedBytes {
            return .failure(.packDecodeFailed)
        }
        return .success(
            TimeHallDownloadedPack(
                recordName: record.recordID.recordName,
                payloadHash: declaredHash,
                encoding: encoding,
                jsonData: jsonData,
                compressedBytes: compressedBytes,
                uncompressedBytes: jsonData.count
            )
        )
    }

    // MARK: 媒体

    func fetchMedia(recordName: String) async throws -> TimeHallDownloadedMedia {
        let records = try await fetchRecords(
            recordNames: [recordName],
            desiredKeys: ["contentHash", "mimeType", "byteCount", "asset"]
        )
        guard let record = records[recordName] else {
            throw TimeHallReadError.missingDependency
        }
        guard let bytes = assetBytes(record, "asset") else {
            throw TimeHallReadError.packDecodeFailed
        }
        let mimeType = stringValue(record, "mimeType")
        guard TimeHallMediaCache.allowedMimeTypes.contains(mimeType) else {
            throw TimeHallReadError.unsupportedEncoding
        }
        guard bytes.count <= limits.maxMediaBytes else {
            throw TimeHallReadError.packTooLarge
        }
        let declaredHash = stringValue(record, "contentHash")
        guard !declaredHash.isEmpty, TimeHallPackCodec.sha256Hex(bytes) == declaredHash else {
            throw TimeHallReadError.packHashMismatch
        }
        let declaredBytes = intValue(record, "byteCount") ?? bytes.count
        guard declaredBytes == bytes.count else {
            throw TimeHallReadError.packDecodeFailed
        }
        return TimeHallDownloadedMedia(
            recordName: record.recordID.recordName,
            contentHash: declaredHash,
            mimeType: mimeType,
            bytes: bytes
        )
    }

    // MARK: 取记录

    /// 显式批量抓取。`desiredKeys` 控制字段集合，避免把 Asset 一起拉下来。
    private func fetchRecords(
        recordNames: [String],
        desiredKeys: [CKRecord.FieldKey]
    ) async throws -> [String: CKRecord] {
        let identifiers = recordNames.map { CKRecord.ID(recordName: $0) }
        let operation = CKFetchRecordsOperation(recordIDs: identifiers)
        operation.desiredKeys = desiredKeys
        operation.qualityOfService = .userInitiated

        let database = self.database
        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var collected: [String: CKRecord] = [:]
            var failure: Error?
            var isResumed = false

            func finish() {
                lock.lock()
                defer { lock.unlock() }
                guard !isResumed else { return }
                isResumed = true
                if let failure {
                    continuation.resume(throwing: failure)
                } else {
                    continuation.resume(returning: collected)
                }
            }

            operation.perRecordResultBlock = { _, result in
                lock.lock()
                switch result {
                case .success(let record):
                    collected[record.recordID.recordName] = record
                case .failure(let error):
                    if failure == nil { failure = error }
                }
                lock.unlock()
            }
            operation.completionBlock = { finish() }
            database.add(operation)
        }
    }

    private func stringValue(_ record: CKRecord, _ key: String) -> String {
        if let value = record[key] as? String { return value }
        if let value = record[key] as? NSString { return value as String }
        return ""
    }

    private func intValue(_ record: CKRecord, _ key: String) -> Int? {
        if let value = record[key] as? Int { return value }
        if let value = record[key] as? Int64 { return Int(value) }
        if let value = record[key] as? NSNumber { return value.intValue }
        return nil
    }

    private func dateString(_ record: CKRecord, _ key: String) -> String {
        guard let date = record[key] as? Date else { return stringValue(record, key) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func assetBytes(_ record: CKRecord, _ key: String) -> Data? {
        guard let asset = record[key] as? CKAsset, let url = asset.fileURL else { return nil }
        // CKAsset 给出的是临时文件地址，必须立刻读走，
        // 且**不得**把这个地址当作永久业务 ID（§6.4）。
        return try? Data(contentsOf: url)
    }
}

// MARK: - 错误映射

extension TimeHallReadError {
    /// 把 CloudKit 的错误转成时光馆自己的读取错误分类（§16.1）。
    ///
    /// CloudKit 的重试等待信息由 `retryAfterSeconds` 提供，
    /// 不能靠「用户下拉刷新」绕过节流等待（§11.6 / §16.1）。
    static func from(_ error: Error) -> TimeHallReadError {
        guard let ckError = error as? CKError else { return .cloudUnavailable }
        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return .offline
        case .requestRateLimited, .zoneBusy, .serviceUnavailable:
            return .throttled
        case .notAuthenticated, .permissionFailure:
            return .permissionDenied
        case .unknownItem:
            return .releaseMissing
        case .quotaExceeded:
            return .cloudUnavailable
        case .partialFailure:
            return .missingDependency
        case .serverRejectedRequest, .invalidArguments, .badDatabase:
            return .unsupportedSchema
        default:
            return .cloudUnavailable
        }
    }

    /// CloudKit 建议的重试等待秒数
    static func retryAfterSeconds(from error: Error) -> TimeInterval? {
        guard let ckError = error as? CKError else { return nil }
        return ckError.retryAfterSeconds
    }
}
