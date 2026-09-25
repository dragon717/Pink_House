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

    /// 本次进程生命周期内，Store 里是否已经装有远端层。
    ///
    /// ⚠️ 远端层是**纯内存态**（`ShopCatalogStore.installRemoteCatalog`），进程重启即归零；
    /// 而控制状态（`installedReleaseSeq` / `installedPayloadHash`）与包缓存是落盘的。
    /// 旧实现只看控制状态判断「要不要下载 / 能不能跳过」，于是出现
    /// 「序号没变 → 直接 return，缓存里的包永远不再装回 Store」：
    /// 装过一次之后，往后每次冷启动商店内容都是空的
    /// （2026-09-25 真机「看不到店家上线数据」的根因）。
    /// 这里显式区分「磁盘上装过」与「内存里有」两件事。
    private var hasRemoteLayer = false

    /// App 内统一走 `shared`；测试注入替身 reader 与独立 store
    ///
    /// ⚠️ `store` 是 `unowned`：**调用方必须自己持有 Store 的强引用**。
    /// 把 `ShopCatalogSeedFixture.makeStore()` 直接塞进参数会立刻释放，
    /// 首帧访问即崩溃（宿主被杀，表现为「用例 started 却没有 passed」，2026-09-25 实测）。
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

        // 0) 冷启动恢复：先把「已落盘的缓存包」装回 Store，再谈要不要联网。
        //    远端层只在内存，不恢复就会出现「控制状态说已安装、界面上一个店家都没有」。
        if !hasRemoteLayer {
            if let restored = ShopCatalogPackCache.restoredCatalog() {
                store.installRemoteCatalog(restored)
                hasRemoteLayer = true
                Self.log("冷启动恢复缓存包 seq=\(control.installedReleaseSeq) "
                         + "hash=\((control.installedPayloadHash ?? "-").prefix(12))")
            } else if control.installedPayloadHash != nil {
                // 索引说装过、包却读不出来（系统清了 Caches / 文件损坏）→ 本次必须重新下载
                Self.log("缓存包不可用（已清或已损坏），本次重新下载")
            }
        }

        // 1) 节流：**只有本地确实有远端内容时才允许跳过检查**。
        //    本地还没有内容（首次启动 / 换环境 / 缓存被清）时不节流 —— 否则
        //    「上一次检查是空的」会把这一次真正有内容的检查一起吞掉。
        if !force, hasRemoteLayer, let lastChecked = control.lastCheckedAt,
           Date().timeIntervalSince(lastChecked) < Self.minimumCheckInterval {
            state = control.installedReleaseSeq > 0
                ? .upToDate(releaseSeq: control.installedReleaseSeq)
                : .idle
            Self.log("节流命中（\(Int(Self.minimumCheckInterval / 60)) 分钟内且本地已有内容），跳过检查")
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

            Self.log("发布头 seq=\(header.releaseSeq) schema=\(header.schemaVersion) "
                     + "（本地已装 seq=\(control.installedReleaseSeq)，内存有远端层=\(hasRemoteLayer)）")

            // 3) 序号未变**且**本地确实有远端层 → 零下载。
            //    序号未变但内存里没有（缓存恢复失败/首次启动）时不能跳过，否则永远装不上。
            guard header.releaseSeq != control.installedReleaseSeq || !hasRemoteLayer else {
                control.lastCheckedAt = Date()
                ShopCatalogPackCache.saveControl(control)
                state = header.releaseSeq > 0
                    ? .upToDate(releaseSeq: header.releaseSeq)
                    : .idle
                Self.log("序号未变且本地已有内容，零下载")
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
                hasRemoteLayer = false
                state = .nothingPublished
                Self.log("根清单里没有 shop-catalog 分片 → 公共库未发布商店内容")
                return
            }
            try ShopCatalogCloudSyncValidator.checkPartitionContract(partition)

            //    内容没变**且**内存里有远端层才跳过下载；
            //    内存里没有（首次启动 / 缓存恢复失败）时按「需要下载」处理。
            let needsDownload = !hasRemoteLayer
                || ShopCatalogPackCache.needsDownload(
                    releaseSeq: header.releaseSeq, payloadHash: partition.payloadHash, control: control)
            if !needsDownload {
                control.lastCheckedAt = Date()
                ShopCatalogPackCache.saveControl(control)
                state = .upToDate(releaseSeq: header.releaseSeq)
                Self.log("分片内容未变且本地已有内容，跳过下载")
                return
            }
            Self.log("开始下载分片 hash=\(partition.payloadHash.prefix(12)) "
                     + "recordCount=\(partition.recordCount)")

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
            hasRemoteLayer = true
            state = .updated(releaseSeq: header.releaseSeq, recordCount: partition.recordCount)
            Self.log("已生效 seq=\(header.releaseSeq) 店家=\(catalog.shops.count) "
                     + "系列=\(catalog.series.count) 商品=\(catalog.products.count)")
        } catch let error as ShopCatalogSyncError {
            // 发布头缺失 = 公共库还没有发布过任何内容（正常空态）
            if case .recordMissing(let recordType, _) = error, recordType == "THRelease" {
                control.lastCheckedAt = Date()
                ShopCatalogPackCache.saveControl(control)
                state = .nothingPublished
                // 环境提示：Xcode 调试构建读 Development，TestFlight / App Store 读 Production。
                // 两边数据不通 —— 「Mac 发布过但这里读不到」先怀疑环境不一致。
                Self.log("公共库没有发布头（正常空态）。注意：Xcode 调试读 Development，"
                         + "TestFlight/App Store 读 Production，两边不互通")
                return
            }
            state = .failed(error.localizedDescription)
            Self.log("同步失败（保留本地数据）：\(error.localizedDescription)")
        } catch {
            state = .failed(error.localizedDescription)
            Self.log("同步失败（保留本地数据）：\(error.localizedDescription)")
        }
    }

    // MARK: 诊断

    /// 同步链路日志。**刻意保留在发布版**：本链路的失败此前完全静默
    /// （界面上只表现为「列表空的」），没有日志就无法区分
    /// 「没发布 / 没触发 / 下载失败 / 校验失败」。
    private static func log(_ message: String) {
        print("[ShopCatalogSync] \(message)")
    }
}
