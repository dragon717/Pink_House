//
//  ShopCatalogCloudSyncService.swift
//  ItemManager
//
//  「店家上新」云同步 · 编排层（消费端，@MainActor）。
//
//  ## 读取算法（设计文档 §11.2 的商店版收敛）
//
//    1. 节流：距上次检查不足 30 分钟直接返回（手动刷新可跳过节流）
//    2. 取发布头元数据 → 协议版本不受支持就停（提示更新 App）
//    3. 序号未变 → 只刷新「已检查」时间，零下载
//    4. 序号变了 → 取根清单 → 校验 rootIndexHash
//    5. 商店分片的 payloadHash 没变 → 只推进序号（画册更新不牵连商店下载）
//    6. 下载包 → 三层校验（协议 / 摘要 / 结构）→ 原子安装 → 交给 Store 合并
//    7. 任何失败：保留本地已有数据，状态如实上报，绝不把失败当「暂无上新」
//
//  ## 边界
//
//    · 本服务只读公共库；写入只在运营 Mac 发布流水线（tools/time_hall/publication/）。
//    · 清缓存不删控制状态；缓存目录被系统清理后按「未安装」恢复（索引与文件同时校验）。
//    · 媒体（商品图）本期不下载：包内 `local:` 引用在本机解析失败时展示占位图，
//      远端媒体走 THMedia 的按需获取在后续版本接入（见 publication/README.md 的坑位说明）。
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class ShopCatalogCloudSyncService: ObservableObject {

    static let shared = ShopCatalogCloudSyncService()

    /// 同步状态（UI 可直接读；failed 携带可展示原因，绝不静默）
    enum State: Equatable {
        case idle
        case syncing
        /// 版本未变（或包内容未变），本地已是最新
        case upToDate(releaseSeq: Int)
        /// 拉到了新版本并已生效
        case updated(releaseSeq: Int, recordCount: Int)
        /// 公共库还没有发布过任何内容（正常空态，不算故障）
        case nothingPublished
        /// 失败原因（本地数据未受影响，可重试）
        case failed(String)

        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    @Published private(set) var state: State = .idle

    /// 发布头最短自动检查间隔（§11.6 初始值；产品参数，待测量调整）
    static let minimumCheckInterval: TimeInterval = 30 * 60

    private let reader: any ShopCatalogPublicReading
    private unowned let store: ShopCatalogStore

    /// 是否正在同步（防并发重入：同分片并发请求合并为一项，§11.6）
    private var isSyncing = false

    /// App 内统一走 `shared`；测试注入替身 reader 与独立 store
    init(
        reader: any ShopCatalogPublicReading = ShopCatalogPublicCloudReader(),
        store: ShopCatalogStore = .shared
    ) {
        self.reader = reader
        self.store = store
    }

    // MARK: 入口

    /// 检查并同步商店内容。可安全重复调用（节流 + 重入保护）。
    /// - Parameter force: 用户手动刷新时置 true，跳过 30 分钟节流（但不绕过服务端重试约束）
    func syncIfNeeded(force: Bool = false) async {
        guard !isSyncing else { return }
        isSyncing = true
        state = .syncing
        defer {
            isSyncing = false
            if state == .syncing { state = .idle }
        }

        var control = ShopCatalogPackCache.loadControl()

        // 1) 节流：刚刚检查过且本地不是失败态就直接返回
        if !force, let lastChecked = control.lastCheckedAt,
           Date().timeIntervalSince(lastChecked) < Self.minimumCheckInterval,
           !state.isFailure {
            state = control.installedReleaseSeq > 0
                ? .upToDate(releaseSeq: control.installedReleaseSeq)
                : .idle
            return
        }

        do {
            // 2) 发布头（唯一版本生效点）
            let header = try await reader.fetchReleaseHeader()
            guard header.schemaVersion == ShopCatalogSyncProtocol.schemaVersion else {
                throw ShopCatalogSyncValidationError.unsupportedSchema(
                    "发布头 schemaVersion \(header.schemaVersion) 不受支持")
            }
            guard header.minimumReaderVersion <= ShopCatalogSyncProtocol.readerVersion else {
                throw ShopCatalogSyncValidationError.unsupportedSchema(
                    "需要更新 App 才能读取发布协议 \(header.minimumReaderVersion)")
            }

            // 3) 序号未变 → 零下载
            guard header.releaseSeq != control.installedReleaseSeq else {
                control.lastCheckedAt = Date()
                ShopCatalogPackCache.saveControl(control)
                state = header.releaseSeq > 0
                    ? .upToDate(releaseSeq: header.releaseSeq)
                    : .idle
                return
            }

            // 4) 根清单 + 摘要自证
            let rootData = try await reader.fetchRootIndex()
            guard ShopCatalogSyncProtocol.sha256Hex(rootData) == header.rootIndexHash else {
                throw ShopCatalogSyncValidationError.rootIndexMismatch("根清单 SHA-256 与发布头不符")
            }
            let rootIndex: ShopCatalogRootIndex
            do {
                rootIndex = try ShopCatalogJSONCoding.decoder().decode(
                    ShopCatalogRootIndex.self, from: rootData)
            } catch {
                throw ShopCatalogSyncValidationError.rootIndexMismatch(
                    "根清单解码失败：\(error.localizedDescription)")
            }

            // 5) 商店分片（nil = 这版发布没带商店内容，只推进序号）
            guard let partition = rootIndex.shopCatalogPartition else {
                control.lastCheckedAt = Date()
                control.installedReleaseSeq = header.releaseSeq
                control.installedPayloadHash = nil
                ShopCatalogPackCache.saveControl(control)
                store.installRemoteCatalog(nil)
                state = .nothingPublished
                return
            }
            try ShopCatalogCloudSyncValidator.checkPartitionContract(partition)

            if !ShopCatalogPackCache.needsDownload(
                releaseSeq: header.releaseSeq, payloadHash: partition.payloadHash, control: control) {
                control.lastCheckedAt = Date()
                ShopCatalogPackCache.saveControl(control)
                state = .upToDate(releaseSeq: header.releaseSeq)
                return
            }

            // 6) 下载 + 三层校验
            let compressed = try await reader.fetchPack(payloadHash: partition.payloadHash)
            let catalog = try ShopCatalogCloudSyncValidator.validatedShopCatalog(
                header: header,
                rootIndexData: rootData,
                packCompressed: compressed
            )

            // 7) 原子安装：先落盘包，再推进控制状态，最后进 Store ——
            //    顺序反过来会出现「状态说装了、文件不存在」或「文件在、状态没记」
            try ShopCatalogPackCache.installPack(compressed, payloadHash: partition.payloadHash)
            control.installedReleaseSeq = header.releaseSeq
            control.installedPayloadHash = partition.payloadHash
            control.revocationEpoch = max(control.revocationEpoch, header.revocationEpoch)
            control.lastCheckedAt = Date()
            ShopCatalogPackCache.saveControl(control)

            store.installRemoteCatalog(catalog)
            state = .updated(releaseSeq: header.releaseSeq, recordCount: partition.recordCount)
        } catch let error as ShopCatalogSyncError {
            // 发布头缺失 = 公共库还没有发布过任何内容（正常空态）
            if case .recordMissing(let recordType, _) = error, recordType == "THRelease" {
                control.lastCheckedAt = Date()
                ShopCatalogPackCache.saveControl(control)
                state = .nothingPublished
                return
            }
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
