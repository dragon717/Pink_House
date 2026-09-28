//
//  ShopCatalogOpsCloudWriter.swift
//  ItemManager
//
//  运营上传 · 公共库写入通道（iOS 运营上传实施方案 §2.2 / §3.2 / §3.4）。
//
//  ## 与消费端的边界
//
//  消费端类型层面**无写能力**（`ShopCatalogPublicReading` 只有 fetch，见
//  `ShopCatalogPublicCloudReader`）。本文件是唯一有写方法的通道，且只被
//  运营入口调用；普通用户的只读由 CloudKit Security Role 在**服务端**保证
//  （Console 配置见 docs/TIME_HALL_CLOUDKIT_CONSOLE_SETUP.md），
//  客户端白名单只负责隐藏入口，不是安全边界（方案 §3.2）。
//
//  ## 只写三种记录，不复用消费协议之外的形状
//
//    THMedia      th.media.<sha256>     mediaKey / mimeType / sha256 / byteCount / asset
//    THDataPack   th.pack.<payloadHash> partitionID / releaseSeq / sha256 / byteCount / asset
//    THRelease    th.release.catalog-v1（全库唯一） 发布头字段 + rootIndexAsset
//
//  ## 条件更新
//
//  `THMedia` / `THDataPack` 按 hash 寻址、不可变：先按精确 ID 读，已存在且
//  `sha256` / `byteCount` 一致就跳过（方案 §3.2 第 1 步、§7「旧数据不覆盖」）。
//  `THRelease` 是唯一可见版本，必须用**读取到的系统字段**（含 `recordChangeTag`）
//  做乐观锁更新；冲突如实回报给运营，绝不强制覆盖（方案 §3.4 第 4 步、§4）。
//

import Foundation
import CloudKit

// MARK: - 错误分类（方案 §4 错误表 → 任务状态）

/// 写入通道的统一错误。分类决定任务落到哪个状态、要不要自动重试。
nonisolated enum ShopCatalogOpsUploadError: LocalizedError, Equatable {
    /// 无 iCloud 账号 / 权限拒绝 / 配额不足 → `blocked`，不自动重试
    case blocked(String)
    /// 网络或服务暂不可用 → `retryable`，指数退避
    case retryable(String)
    /// `THRelease` changeTag 冲突 → `conflict`，由运营确认后再发
    case conflict(String)
    /// 其它硬失败 → `failed`，保留诊断信息，不发布包
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .blocked(let detail): return detail
        case .retryable(let detail): return detail
        case .conflict(let detail): return detail
        case .failed(let detail): return detail
        }
    }

    /// 对应到任务状态（方案 §4 表格逐行）
    var status: ShopCatalogUploadStatus {
        switch self {
        case .blocked: return .blocked
        case .retryable: return .retryable
        case .conflict: return .conflict
        case .failed: return .failed
        }
    }

    /// CKError → 分类。**默认落到 `failed` 而不是 `retryable`**：
    /// 没识别出来的错误反复自动重试只会无限打网络，而运营看不到原因。
    static func mapped(_ error: Error, what: String) -> ShopCatalogOpsUploadError {
        guard let ckError = error as? CKError else {
            if let typed = error as? ShopCatalogOpsUploadError { return typed }
            return .failed("\(what)失败：\(error.localizedDescription)")
        }
        switch ckError.code {
        case .notAuthenticated, .accountTemporarilyUnavailable:
            return .blocked("运营账号未登录 iCloud，无法写入公共库（\(what)）")
        case .permissionFailure, .serverRejectedRequest:
            return .blocked("CloudKit 权限拒绝（Security Role 未授权当前账号）："
                            + ckError.localizedDescription)
        case .quotaExceeded, .limitExceeded:
            return .blocked("CloudKit 配额不足，\(what)失败：\(ckError.localizedDescription)")
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy, .internalError, .serverResponseLost:
            return .retryable("网络或服务暂不可用，\(what)失败：\(ckError.localizedDescription)")
        case .serverRecordChanged:
            return .conflict("记录已被其它端覆盖（changeTag 冲突），\(what)未生效")
        default:
            return .failed("\(what)失败（CKError \(ckError.code.rawValue)）："
                           + ckError.localizedDescription)
        }
    }
}

// MARK: - 读取结果

nonisolated struct ShopCatalogOpsRemoteMediaMeta: Equatable, Sendable {
    let sha256: String
    let byteCount: Int
}

nonisolated struct ShopCatalogOpsRemotePackMeta: Equatable, Sendable {
    let sha256: String
    let byteCount: Int
}

/// 发布头快照：`systemFields` 是归档后的系统字段（含 `recordChangeTag`），
/// 条件更新的唯一凭据；nil = 公共库还没有发布头（首次发布 → 创建）。
nonisolated struct ShopCatalogOpsReleaseSnapshot: Sendable {
    let header: ShopCatalogReleaseHeader
    let systemFields: Data
}

/// 一次发布头写入的入参（方案 §3.4 第 4 步）
nonisolated struct ShopCatalogOpsReleaseUpdate: Sendable {
    var releaseSeq: Int
    var schemaVersion: Int
    var revocationEpoch: Int
    var minimumReaderVersion: Int
    var previousReleaseSeq: Int
    var publishedAt: String
    var rootIndexHash: String
    var rootIndexData: Data
}

// MARK: - 写入协议（测试可注入替身）

nonisolated protocol ShopCatalogOpsCloudWriting: Sendable {

    /// 写入前置：公共库**读**不需要账号，但**写**需要活动 iCloud 账号（方案 §2.2）
    func ensureWritableAccount() async throws

    /// 按精确 ID 读媒体元数据；nil = 不存在（→ 需要上传）
    func fetchMediaMetadata(mediaKey: String) async throws -> ShopCatalogOpsRemoteMediaMeta?

    /// **批量**读媒体元数据；结果里没有的 key = 线上不存在（→ 需要上传）。
    ///
    /// ⚠️ 必须成批取，不能靠上面那个单点方法循环：
    /// 一次发布要问 450 张图在不在公共库，逐张单点就是 450 次 `record(for:)`，
    /// 必然撞 CloudKit 限流（`requestRateLimited`）→ 一部分任务落到 `retryable`
    /// → `unresolved` 非空 → 整次发布在媒体阶段就被判失败、
    /// **发布头永远切不动**（2026-09-28 实测：线上发布头停在 seq 1 就是这个原因）。
    func fetchMediaMetadata(
        mediaKeys: [String]
    ) async throws -> [String: ShopCatalogOpsRemoteMediaMeta]

    /// 新建不可变媒体记录（`th.media.<mediaKey>`）
    func saveMedia(
        mediaKey: String, mimeType: String, sha256: String, byteCount: Int, fileURL: URL
    ) async throws

    /// 回读媒体字节（方案 §3.2 第 6 步：hash 校验通过才算 `mediaVerified`）
    func fetchMediaBytes(mediaKey: String) async throws -> Data

    /// 按精确 ID 读数据包元数据；nil = 不存在
    func fetchPackMetadata(payloadHash: String) async throws -> ShopCatalogOpsRemotePackMeta?

    /// 新建不可变数据包记录（`th.pack.<payloadHash>`）
    func savePack(
        payloadHash: String, partitionID: String, releaseSeq: Int,
        sha256: String, byteCount: Int, fileURL: URL
    ) async throws

    /// 读发布头 + 系统字段；nil = 公共库还没发布过
    func fetchRelease() async throws -> ShopCatalogOpsReleaseSnapshot?

    /// 条件更新发布头。`systemFields` nil = 首次创建。
    func saveRelease(
        systemFields: Data?, update: ShopCatalogOpsReleaseUpdate
    ) async throws
}

// MARK: - 分块

/// 内部可见：编排层（`ShopCatalogOpsPublisher`）也要按同样的块大小切分。
extension Array {
    /// 按固定大小切块（`stride` 版，避免手写下标越界）
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - 批量查询的默认实现

extension ShopCatalogOpsCloudWriting {

    /// 默认逐张查 —— 只给不需要改的替身兜底。
    ///
    /// 真实实现必须覆盖它（见 `ShopCatalogOpsPublicCloudWriter`）：
    /// 默认实现只是为了**新增协议方法时不打断既有测试替身**，
    /// 线上链路走它等于没做限流治理。
    func fetchMediaMetadata(
        mediaKeys: [String]
    ) async throws -> [String: ShopCatalogOpsRemoteMediaMeta] {
        var result: [String: ShopCatalogOpsRemoteMediaMeta] = [:]
        for key in mediaKeys {
            if let meta = try await fetchMediaMetadata(mediaKey: key) {
                result[key] = meta
            }
        }
        return result
    }
}

// MARK: - CloudKit 真实现

/// 与 Notice / 消费端同容器（entitlements 已声明），Schema 互不混用。
///
/// 本类是全局 actor 隔离（工程默认 `MainActor`），因此本身满足协议的 `Sendable` 约束，
/// 不需要额外标注 —— 与既有 `ShopCatalogPublicCloudReader` 同一写法。
final class ShopCatalogOpsPublicCloudWriter: ShopCatalogOpsCloudWriting {

    private let container: CKContainer
    /// struct 里 lazy var 的 getter 是 mutating 的，async 方法里访问会报
    /// 「cannot use mutating getter on immutable value」——用计算属性
    private var database: CKDatabase { container.publicCloudDatabase }

    /// 单次批量查询的条数上限（分块发送，避免一次请求过大被拒）
    private static let batchLookupSize = 200

    init(containerID: String = "iCloud.bugod2.ItemManager") {
        self.container = CKContainer(identifier: containerID)
    }

    // MARK: 账号

    func ensureWritableAccount() async throws {
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            throw ShopCatalogOpsUploadError.mapped(error, what: "检查 iCloud 账号")
        }
        switch status {
        case .available:
            return
        case .noAccount:
            throw ShopCatalogOpsUploadError.blocked("运营设备没有登录 iCloud，公共库写入需要活动账号")
        case .restricted:
            throw ShopCatalogOpsUploadError.blocked("当前 iCloud 账号受限，无法写入公共库")
        case .temporarilyUnavailable:
            throw ShopCatalogOpsUploadError.retryable("iCloud 账号暂时不可用，稍后重试")
        case .couldNotDetermine:
            throw ShopCatalogOpsUploadError.retryable("无法确定 iCloud 账号状态，稍后重试")
        @unknown default:
            throw ShopCatalogOpsUploadError.retryable("iCloud 账号状态异常，稍后重试")
        }
    }

    // MARK: 媒体

    func fetchMediaMetadata(mediaKey: String) async throws -> ShopCatalogOpsRemoteMediaMeta? {
        guard let record = try await record(
            recordType: "THMedia",
            recordName: ShopCatalogSyncProtocol.mediaRecordName(contentHash: mediaKey),
            missingIsNil: true
        ) else { return nil }
        return ShopCatalogOpsRemoteMediaMeta(
            sha256: record["sha256"] as? String ?? "",
            byteCount: (record["byteCount"] as? NSNumber)?.intValue ?? 0
        )
    }

    func fetchMediaMetadata(
        mediaKeys: [String]
    ) async throws -> [String: ShopCatalogOpsRemoteMediaMeta] {
        var result: [String: ShopCatalogOpsRemoteMediaMeta] = [:]
        // 分块：单次批量取太多会被服务端拒，200 是 CloudKit 常见的稳妥档位
        for chunk in mediaKeys.chunked(into: Self.batchLookupSize) {
            let ids = chunk.map {
                CKRecord.ID(recordName: ShopCatalogSyncProtocol.mediaRecordName(contentHash: $0))
            }
            let found: [CKRecord.ID: Result<CKRecord, Error>]
            do {
                found = try await database.records(for: ids)
            } catch {
                throw ShopCatalogOpsUploadError.mapped(error, what: "批量查询已上传图片")
            }
            for key in chunk {
                let id = CKRecord.ID(
                    recordName: ShopCatalogSyncProtocol.mediaRecordName(contentHash: key))
                // 缺记录属于正常情况（还没传过），按「不存在」处理
                guard case .success(let record)? = found[id] else { continue }
                result[key] = ShopCatalogOpsRemoteMediaMeta(
                    sha256: record["sha256"] as? String ?? "",
                    byteCount: (record["byteCount"] as? NSNumber)?.intValue ?? 0)
            }
        }
        return result
    }

    func saveMedia(
        mediaKey: String, mimeType: String, sha256: String, byteCount: Int, fileURL: URL
    ) async throws {
        let record = CKRecord(
            recordType: "THMedia",
            recordID: CKRecord.ID(
                recordName: ShopCatalogSyncProtocol.mediaRecordName(contentHash: mediaKey))
        )
        record["mediaKey"] = mediaKey as CKRecordValue
        record["mimeType"] = mimeType as CKRecordValue
        record["sha256"] = sha256 as CKRecordValue
        record["byteCount"] = NSNumber(value: byteCount)
        record["asset"] = CKAsset(fileURL: fileURL)
        do {
            // 不可变：内容寻址的记录名天然幂等
            try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // ⭐ 重复上传拦截的最后一道（2026-09-28）：
            // CloudKit 的 `save` **不是 upsert** —— 目标记录名已存在、而我们手里的
            // CKRecord 是新建的（没有 change tag）时，就报 `serverRecordChanged`。
            // 这恰好说明「线上已经有这条记录」。记录是**按内容寻址的不可变记录**，
            // 所以直接当「已存在」放行，交给调用方的**回读校验**确认内容一致；
            // 若线上那条真是别的内容，回读 hash 比对会如实失败，不会静默放过。
            //
            // （实测：上一场会话被杀时字节已到服务端、本地却没来得及记 `mediaVerified`；
            //  下一次发布的批量/单点查询再漏判，save 就撞上它 —— 31 条媒体任务
            //  被标成「发布头冲突」，而那明明是发布头才有的语义，纯属误导。）
            return
        } catch {
            throw ShopCatalogOpsUploadError.mapped(error, what: "上传图片 \(mediaKey.prefix(12))")
        }
    }

    func fetchMediaBytes(mediaKey: String) async throws -> Data {
        let record = try await record(
            recordType: "THMedia",
            recordName: ShopCatalogSyncProtocol.mediaRecordName(contentHash: mediaKey),
            missingIsNil: false
        )
        guard let record else {
            throw ShopCatalogOpsUploadError.failed("回读媒体失败：记录不存在")
        }
        return try assetData(from: record, key: "asset", what: "媒体 \(mediaKey.prefix(12))")
    }

    // MARK: 数据包

    func fetchPackMetadata(payloadHash: String) async throws -> ShopCatalogOpsRemotePackMeta? {
        guard let record = try await record(
            recordType: "THDataPack",
            recordName: ShopCatalogSyncProtocol.packRecordName(payloadHash: payloadHash),
            missingIsNil: true
        ) else { return nil }
        return ShopCatalogOpsRemotePackMeta(
            sha256: record["sha256"] as? String ?? "",
            byteCount: (record["byteCount"] as? NSNumber)?.intValue ?? 0
        )
    }

    func savePack(
        payloadHash: String, partitionID: String, releaseSeq: Int,
        sha256: String, byteCount: Int, fileURL: URL
    ) async throws {
        let record = CKRecord(
            recordType: "THDataPack",
            recordID: CKRecord.ID(
                recordName: ShopCatalogSyncProtocol.packRecordName(payloadHash: payloadHash))
        )
        record["partitionID"] = partitionID as CKRecordValue
        record["releaseSeq"] = NSNumber(value: releaseSeq)
        record["sha256"] = sha256 as CKRecordValue
        record["byteCount"] = NSNumber(value: byteCount)
        record["asset"] = CKAsset(fileURL: fileURL)
        do {
            try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // 与 `saveMedia` 同理：数据包也是按内容寻址的不可变记录，
            // 「已存在」不是失败 —— 回读端到端验证会确认内容一致
            return
        } catch {
            throw ShopCatalogOpsUploadError.mapped(error, what: "上传数据包")
        }
    }

    // MARK: 发布头

    func fetchRelease() async throws -> ShopCatalogOpsReleaseSnapshot? {
        guard let record = try await record(
            recordType: "THRelease",
            recordName: ShopCatalogSyncProtocol.releaseRecordName,
            missingIsNil: true
        ) else { return nil }
        guard let rootIndexHash = record["rootIndexHash"] as? String, !rootIndexHash.isEmpty else {
            throw ShopCatalogOpsUploadError.failed("公共库发布头缺少 rootIndexHash（发布端写坏了）")
        }
        func intValue(_ key: String) -> Int { (record[key] as? NSNumber)?.intValue ?? 0 }
        let header = ShopCatalogReleaseHeader(
            releaseSeq: intValue("releaseSeq"),
            schemaVersion: intValue("schemaVersion"),
            revocationEpoch: intValue("revocationEpoch"),
            minimumReaderVersion: intValue("minimumReaderVersion"),
            previousReleaseSeq: intValue("previousReleaseSeq"),
            publishedAt: record["publishedAt"] as? String,
            rootIndexHash: rootIndexHash
        )
        return ShopCatalogOpsReleaseSnapshot(
            header: header, systemFields: try Self.systemFields(of: record))
    }

    func saveRelease(systemFields: Data?, update: ShopCatalogOpsReleaseUpdate) async throws {
        let record: CKRecord
        if let systemFields {
            do {
                record = try Self.record(fromSystemFields: systemFields)
            } catch {
                throw ShopCatalogOpsUploadError.failed("发布头系统字段解档失败：\(error.localizedDescription)")
            }
        } else {
            record = CKRecord(
                recordType: "THRelease",
                recordID: CKRecord.ID(recordName: ShopCatalogSyncProtocol.releaseRecordName))
        }
        record["releaseSeq"] = NSNumber(value: update.releaseSeq)
        record["schemaVersion"] = NSNumber(value: update.schemaVersion)
        record["revocationEpoch"] = NSNumber(value: update.revocationEpoch)
        record["minimumReaderVersion"] = NSNumber(value: update.minimumReaderVersion)
        record["previousReleaseSeq"] = NSNumber(value: update.previousReleaseSeq)
        record["publishedAt"] = update.publishedAt as CKRecordValue
        record["rootIndexHash"] = update.rootIndexHash as CKRecordValue

        // CKAsset 只能从文件 URL 构造：根清单字节先落临时文件，写完即删
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("th-release-root-index-\(UUID().uuidString).json")
        do {
            try update.rootIndexData.write(to: temp, options: .atomic)
        } catch {
            throw ShopCatalogOpsUploadError.failed("根清单落临时文件失败：\(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: temp) }
        record["rootIndexAsset"] = CKAsset(fileURL: temp)

        do {
            // `CKDatabase.save(_:)` 默认策略 `.ifServerRecordUnchanged`：
            // 带系统字段（含 changeTag）的记录就是**条件更新** —— 方案 §3.4 第 4 步。
            try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            throw ShopCatalogOpsUploadError.conflict(
                "发布头已被其它发布覆盖（changeTag 冲突）；请重新读取当前头、重算序号后再确认发布")
        } catch {
            throw ShopCatalogOpsUploadError.mapped(error, what: "切换发布头")
        }
    }

    // MARK: 内部

    /// 精确读取。`missingIsNil` = 「记录不存在」按 nil 返回（用于幂等跳过），
    /// 否则如实抛错（回读校验时缺记录是失败，不是空态）。
    private func record(
        recordType: String, recordName: String, missingIsNil: Bool
    ) async throws -> CKRecord? {
        do {
            return try await database.record(for: CKRecord.ID(recordName: recordName))
        } catch let error as CKError {
            if error.code == .unknownItem, missingIsNil { return nil }
            if error.code == .unknownItem {
                throw ShopCatalogOpsUploadError.failed("\(recordType) 记录不存在（\(recordName)）")
            }
            throw ShopCatalogOpsUploadError.mapped(error, what: "读取 \(recordType)")
        }
    }

    private func assetData(from record: CKRecord, key: String, what: String) throws -> Data {
        guard let asset = record[key] as? CKAsset, let url = asset.fileURL else {
            throw ShopCatalogOpsUploadError.failed("\(what) 缺少资产或资产尚未落地")
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ShopCatalogOpsUploadError.failed("\(what) 资产读取失败：\(error.localizedDescription)")
        }
    }

    /// 归档系统字段（含 recordChangeTag）—— 重建记录时用它做乐观锁
    private static func systemFields(of record: CKRecord) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private static func record(fromSystemFields data: Data) throws -> CKRecord {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        guard let record = CKRecord(coder: unarchiver) else {
            throw ShopCatalogOpsUploadError.failed("系统字段里没有可还原的发布头记录")
        }
        return record
    }
}
