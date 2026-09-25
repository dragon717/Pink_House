//
//  ShopCatalogPublicCloudReader.swift
//  ItemManager
//
//  「店家上新」云同步 · 公共库只读读者（消费端）。
//
//  ## 类型层面无写能力（设计文档 §10.1 硬约束）
//
//  本协议**只暴露读取接口**——不存在 `save` / `delete` / `modify`，
//  普通用户对公共库零写权限同时由 CloudKit 服务端 Security Role 保证
//  （Console 配置见 docs/TIME_HALL_CLOUDKIT_CONSOLE_SETUP.md §2），
//  客户端类型设计只是第二道防线，不是权限本身。
//
//  ## 读取路径（§6.6：正常读链路全部按已知 Record ID 精确取，不扫描公共库）
//
//    THRelease（固定记录名 th.release.catalog-v1）
//      → rootIndexAsset（根清单）
//      → THDataPack（记录名 th.pack.<payloadHash>）
//
//  公共库读取**不以登录 iCloud 为前提**（设计文档 §1.2 E：
//  `publicCloudDatabase` 无账户也可访问，可读内容由数据库权限决定），
//  所以这里刻意**不**做 `accountStatus == .available` 前置检查。
//

import Foundation
import CloudKit

// MARK: - 只读读者协议（测试可注入替身）

nonisolated protocol ShopCatalogPublicReading: Sendable {
    /// 取发布头元数据（唯一版本生效点）
    func fetchReleaseHeader() async throws -> ShopCatalogReleaseHeader
    /// 取根清单原始字节（调用方自行校验 rootIndexHash）
    func fetchRootIndex() async throws -> Data
    /// 按载荷摘要取不可变数据包
    func fetchPack(payloadHash: String) async throws -> Data
    /// 按内容摘要取不可变媒体（商品图 / 尺码表原图）
    func fetchMedia(contentHash: String) async throws -> Data
}

extension ShopCatalogPublicReading {
    /// 默认实现：不支持媒体的读者（如测试替身）不实现也不会编译失败，
    /// 取用时如实报「找不到」，绝不静默返回空数据。
    func fetchMedia(contentHash: String) async throws -> Data {
        throw ShopCatalogSyncError.recordMissing(
            recordType: "THMedia",
            recordName: ShopCatalogSyncProtocol.mediaRecordName(contentHash: contentHash))
    }
}

// MARK: - CloudKit 真实现

struct ShopCatalogPublicCloudReader: ShopCatalogPublicReading {

    /// 与 Notice 公共公告同容器（entitlements 已声明），Schema 互不混用
    private let container: CKContainer
    /// 注意：struct 里 lazy var 的 getter 是 mutating 的，async 方法里访问会报
    /// 「cannot use mutating getter on immutable value」——必须用计算属性
    private var database: CKDatabase { container.publicCloudDatabase }

    init(containerID: String = "iCloud.bugod2.ItemManager") {
        self.container = CKContainer(identifier: containerID)
    }

    // MARK: 发布头

    func fetchReleaseHeader() async throws -> ShopCatalogReleaseHeader {
        let record = try await record(
            recordType: "THRelease",
            recordName: ShopCatalogSyncProtocol.releaseRecordName
        )
        // CKRecord 没有 `.fields` 字典：字段经下标 `record[key]` 逐个取
        func int32(_ key: String) -> Int {
            (record[key] as? NSNumber)?.intValue ?? 0
        }

        guard let rootIndexHash = record["rootIndexHash"] as? String, !rootIndexHash.isEmpty else {
            throw ShopCatalogSyncError.malformedRecord("发布头缺少 rootIndexHash")
        }
        return ShopCatalogReleaseHeader(
            releaseSeq: int32("releaseSeq"),
            schemaVersion: int32("schemaVersion"),
            revocationEpoch: int32("revocationEpoch"),
            minimumReaderVersion: int32("minimumReaderVersion"),
            previousReleaseSeq: int32("previousReleaseSeq"),
            publishedAt: record["publishedAt"] as? String,
            rootIndexHash: rootIndexHash
        )
    }

    // MARK: 根清单

    func fetchRootIndex() async throws -> Data {
        let record = try await record(
            recordType: "THRelease",
            recordName: ShopCatalogSyncProtocol.releaseRecordName
        )
        return try data(from: record, assetKey: "rootIndexAsset", what: "根清单")
    }

    // MARK: 数据包

    func fetchPack(payloadHash: String) async throws -> Data {
        let record = try await record(
            recordType: "THDataPack",
            recordName: ShopCatalogSyncProtocol.packRecordName(payloadHash: payloadHash)
        )
        return try data(from: record, assetKey: "asset", what: "数据包 \(payloadHash.prefix(12))")
    }

    // MARK: 媒体

    func fetchMedia(contentHash: String) async throws -> Data {
        let record = try await record(
            recordType: "THMedia",
            recordName: ShopCatalogSyncProtocol.mediaRecordName(contentHash: contentHash)
        )
        return try data(from: record, assetKey: "asset", what: "媒体 \(contentHash.prefix(12))")
    }

    // MARK: 内部

    private func record(recordType: String, recordName: String) async throws -> CKRecord {
        do {
            return try await database.record(for: CKRecord.ID(recordName: recordName))
        } catch let error as CKError {
            switch error.code {
            case .unknownItem:
                // 记录不存在 ≠ 网络故障：发布头缺失 = 公共库还没发布过（正常空态）
                throw ShopCatalogSyncError.recordMissing(recordType: recordType, recordName: recordName)
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
                throw ShopCatalogSyncError.network(error.localizedDescription)
            case .permissionFailure:
                // 理论上不该发生：Security Role 配置错误才会读到拒绝，如实上报
                throw ShopCatalogSyncError.network("公共库读取被拒绝（Security Role 配置异常）")
            default:
                throw ShopCatalogSyncError.network("CloudKit 错误 \(error.code.rawValue)：\(error.localizedDescription)")
            }
        }
    }

    private func data(from record: CKRecord, assetKey: String, what: String) throws -> Data {
        guard let asset = record[assetKey] as? CKAsset else {
            throw ShopCatalogSyncError.malformedRecord("\(what) 缺少资产字段 \(assetKey)")
        }
        guard let url = asset.fileURL else {
            throw ShopCatalogSyncError.malformedRecord("\(what) 资产文件尚未落地")
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ShopCatalogSyncError.malformedRecord("\(what) 资产读取失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 同步错误

/// 同步链路错误。CKError 与校验错误在这里归一，UI 只需要展示 `localizedDescription`。
nonisolated enum ShopCatalogSyncError: LocalizedError, Equatable {
    /// 记录不存在（发布头缺失 = 公共库还没发布过；数据包缺失 = 根清单指向了不存在的包）
    case recordMissing(recordType: String, recordName: String)
    /// 网络 / 服务端临时故障（保留本地数据，延迟重试）
    case network(String)
    /// 记录存在但字段形状不对（发布端配置错误，如实上报）
    case malformedRecord(String)

    var errorDescription: String? {
        switch self {
        case .recordMissing(let recordType, let recordName):
            return "公共库中找不到 \(recordType)（\(recordName.prefix(24))…）"
        case .network(let detail):
            return "暂时无法检查商店上新更新：\(detail)"
        case .malformedRecord(let detail):
            return "公共库记录形状异常：\(detail)"
        }
    }
}
