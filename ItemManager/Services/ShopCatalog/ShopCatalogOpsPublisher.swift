//
//  ShopCatalogOpsPublisher.swift
//  ItemManager
//
//  运营上传 · 编排层（iOS 运营上传实施方案 §3 全流程）。
//
//  ## 流程（与方案 §3.1–§3.4 逐条对应）
//
//    1. 暂存：扫 `local:` 引用 → 算 hash/MIME/字节数 → 建任务（`staged`）
//    2. 媒体：按 `th.media.<mediaKey>` 精确读 → 已存在且一致则跳过 → 否则上传
//             → **回读并校验 hash** → `mediaVerified`（方案 §3.2）
//    3. 打包：把 `mediaKey` 写进商品 JSON → 压缩 → 算 hash → 上传不可变 `THDataPack`
//    4. 发布：读发布头拿 `recordChangeTag` → 条件更新 → 序号 +1（方案 §3.4）
//    5. 验证：**用普通只读路径**拉 `THRelease → 根清单 → THDataPack → THMedia`，
//             全过才显示「已发布」（方案 §3.4 第 6/7 步）
//
//  ## 失败边界（方案 §3.4 末段）
//
//    · 发布头切换**之前**任何一步失败：用户看到的仍是旧版本，不存在半套商品；
//    · 发布头切换**之后**回读失败：只能标「已发布但未验证」，不承诺全局回滚，
//      必要时由运营发布更高 `releaseSeq` 的回滚快照。
//
//  ⚠️ 本层是 `@MainActor` 编排；纯逻辑（暂存 / 改写）在
//     `ShopCatalogOpsMediaStaging`，网络在 `ShopCatalogOpsCloudWriter`，都可单测。
//

import Foundation
import Combine
import CryptoKit

// MARK: - 结果

nonisolated enum ShopCatalogOpsPublishResult: Equatable {
    /// 全链路成功：发布头已切换且只读端回读验证通过
    case published(releaseSeq: Int, mediaCount: Int)
    /// **发布头未切换**：媒体或数据包阶段失败 → 线上仍是旧版本（方案 §3.4 末段）
    case notPublished(String)
    /// 发布头已切换但只读端回读失败 → 只计数「已发布未验证」（方案 §4 最后一行）
    case publishedButUnverified(releaseSeq: Int, detail: String)

    var isSuccess: Bool {
        if case .published = self { return true }
        return false
    }

    var summary: String {
        switch self {
        case .published(let releaseSeq, let mediaCount):
            return "已发布并验证成功（发布序号 \(releaseSeq)，图片 \(mediaCount) 张）"
        case .notPublished(let reason):
            return "未发布：\(reason)"
        case .publishedButUnverified(let releaseSeq, let detail):
            return "已发布但未验证（发布序号 \(releaseSeq)）：\(detail)"
        }
    }
}

// MARK: - 图片账

/// 一次发布里图片的去重结果。
///
/// **拦截必须可见**：如果界面只说「图片 450 张」，运营看不出「是不是又全传了一遍」，
/// 也就没法判断限流风险。这里把「新传 / 线上已有跳过 / 失败」分开报。
nonisolated struct ShopCatalogOpsMediaStats: Equatable, Sendable {
    /// 本次真的把字节传上去的张数
    let uploaded: Int
    /// 线上已存在且摘要一致、被拦截掉的张数
    let skipped: Int
    /// 未通过校验的张数（发布头不会切换）
    let failed: Int

    var summaryText: String {
        "图片：新上传 \(uploaded) 张 · 线上已有跳过 \(skipped) 张 · 未通过 \(failed) 张"
    }
}

// MARK: - 发布范围常量

/// 商店目录分片的固定内容源（与 Mac 端 `sources.yaml` / 协议常量逐字一致）。
/// 单独放一个 `nonisolated` 命名空间：纯逻辑函数（组装负载 / 根清单）要能直接读它，
/// 不能挂在有全局 actor 隔离的类上。
nonisolated enum ShopCatalogOpsPublishScope {
    static let brandID = ShopCatalogSyncProtocol.shopCatalogBrandID
    static let entityType = ShopCatalogSyncProtocol.shopCatalogEntityType
    static var partitionID: String { ShopCatalogSyncProtocol.shopCatalogPartitionID }
}

// MARK: - 编排

@MainActor
final class ShopCatalogOpsPublisher: ObservableObject {

    static let shared = ShopCatalogOpsPublisher()

    /// 粗粒度进度（UI 只用来做「正在做什么」的提示，细状态看任务表）
    enum Phase: Equatable {
        case idle
        case staging
        case uploadingMedia
        case publishing
        case verifying

        var displayName: String {
            switch self {
            case .idle: return "空闲"
            case .staging: return "暂存图片"
            case .uploadingMedia: return "上传图片"
            case .publishing: return "发布商品包"
            case .verifying: return "回读验证"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastResult: ShopCatalogOpsPublishResult?
    /// 上一次发布的分项图片账（新传 / 跳过 / 未通过）
    @Published private(set) var lastMediaStats: ShopCatalogOpsMediaStats?

    /// 本次运行里**已经回读校验过字节**的 mediaKey。
    /// 末尾的端到端验证复用它，不再把同一张图下载第二遍。
    private var verifiedThisRun: Set<String> = []

    private let writer: any ShopCatalogOpsCloudWriting
    private let reader: any ShopCatalogPublicReading
    private let uploadStore: ShopCatalogOpsUploadStore

    init(
        writer: any ShopCatalogOpsCloudWriting = ShopCatalogOpsPublicCloudWriter(),
        reader: any ShopCatalogPublicReading = ShopCatalogPublicCloudReader(),
        uploadStore: ShopCatalogOpsUploadStore? = nil
    ) {
        self.writer = writer
        self.reader = reader
        self.uploadStore = uploadStore ?? .shared
    }

    // MARK: 对外入口

    /// 只暂存（不碰网络）：让运营在真正上传前就看见「有引用但没图」这类问题
    @discardableResult
    func stageOnly(catalog: ShopCatalog) -> ShopCatalogOpsPublishResult {
        do {
            let staged = try ShopCatalogOpsMediaStaging.plan(for: catalog)
            register(staged)
            return .notPublished("已暂存 \(staged.count) 张图片，等待上传")
        } catch {
            return .notPublished(error.localizedDescription)
        }
    }

    /// 全流程：暂存 → 上传 → 发布 → 回读验证
    @discardableResult
    func publish(catalog: ShopCatalog) async -> ShopCatalogOpsPublishResult {
        let result = await run(catalog: catalog, retryOnlyFailed: false)
        lastResult = result
        phase = .idle
        return result
    }

    /// 只重试未成功的任务（方案 §4：失败后重跑是幂等的）
    @discardableResult
    func retryFailed(catalog: ShopCatalog) async -> ShopCatalogOpsPublishResult {
        let result = await run(catalog: catalog, retryOnlyFailed: true)
        lastResult = result
        phase = .idle
        return result
    }

    // MARK: 主流程

    private func run(
        catalog: ShopCatalog, retryOnlyFailed: Bool
    ) async -> ShopCatalogOpsPublishResult {
        phase = .staging
        verifiedThisRun = []
        lastMediaStats = nil
        let staged: [ShopCatalogOpsStagedMedia]
        do {
            staged = try ShopCatalogOpsMediaStaging.plan(for: catalog)
        } catch {
            // 方案 §4 第 1 行：选图读取 / 压缩失败 → stagedFailed，允许重新选图。
            // 缺图是**发布前置条件不满足**，不进入媒体上传阶段。
            return .notPublished(error.localizedDescription)
        }
        register(staged)

        // ---- 1) 媒体
        phase = .uploadingMedia
        do {
            try await writer.ensureWritableAccount()
        } catch {
            let typed = ShopCatalogOpsUploadError.mapped(error, what: "检查 iCloud 账号")
            for media in staged {
                uploadStore.update(mediaKey: media.mediaKey) {
                    $0.markFailure(typed.status, reason: typed.localizedDescription ?? "未知错误")
                }
            }
            return .notPublished(typed.localizedDescription ?? "无法写入公共库")
        }

        // 先**成批**问一次公共库「哪些图已经在」。
        // 逐张单点查询会让 450 张图变成 450 次请求，撞上限流后一部分任务落到
        // retryable → unresolved 非空 → 整次发布在媒体阶段就被判失败、
        // 发布头永远切不动（2026-09-28 实测：线上停在 seq 1 就是这么来的）。
        let remoteIndex = await fetchRemoteMediaIndex(for: staged)

        var uploaded = 0
        var skipped = 0
        var failed = 0
        for media in staged {
            let current = uploadStore.job(mediaKey: media.mediaKey)
            if current?.status == .mediaVerified || current?.status == .published { continue }
            if retryOnlyFailed, let status = current?.status,
               status != .retryable, status != .failed, status != .stagedFailed {
                continue
            }
            switch await uploadOne(media, remoteIndex: remoteIndex) {
            case .uploaded: uploaded += 1
            case .skippedAsRemoteDuplicate: skipped += 1
            case .failed: failed += 1
            }
        }
        lastMediaStats = ShopCatalogOpsMediaStats(
            uploaded: uploaded, skipped: skipped, failed: failed)

        let unresolved = staged.filter {
            uploadStore.job(mediaKey: $0.mediaKey)?.status != .mediaVerified
        }
        if !unresolved.isEmpty {
            let firstError = unresolved.compactMap {
                uploadStore.job(mediaKey: $0.mediaKey)?.lastError
            }.first
            return .notPublished(
                "\(unresolved.count) 张图片未通过校验"
                + (firstError.map { "：\($0)" } ?? "")
                + "（发布头未切换，线上仍是旧版本）")
        }

        // ---- 2) 数据包 + 发布头
        phase = .publishing
        var keys: [String: String] = [:]
        for media in staged {
            for owner in media.owners {
                keys[owner.reference] = media.mediaKey
            }
        }
        let rewritten = ShopCatalogOpsMediaStaging.rewrite(catalog, mediaKeys: keys)

        let payload: ShopCatalogPackPayload
        let compressed: Data
        let payloadHash: String
        do {
            payload = Self.makePayload(catalog: rewritten)
            let raw = try ShopCatalogJSONCoding.encoder().encode(payload)
            compressed = try ShopCatalogCloudSyncValidator.compress(raw)
            payloadHash = ShopCatalogSyncProtocol.sha256Hex(compressed)
        } catch {
            return .notPublished("生成商品包失败：\(error.localizedDescription)")
        }

        // 发布任务：把「商品包 + 发布头」这一步也落成一条可展示、可重跑的任务
        // （方案 §4 的 `阶段` 字段取值就来自这里）。
        let releaseJobID = "release:\(payloadHash)"
        uploadStore.upsertTask(
            jobID: releaseJobID,
            mediaKey: payloadHash,
            stage: .pack,
            mimeType: "application/gzip",
            byteCount: compressed.count)

        func markReleaseJob(
            stage: ShopCatalogUploadStage, status: ShopCatalogUploadStatus,
            reason: String? = nil, releaseSeq: Int = 0
        ) {
            uploadStore.upsertTask(
                jobID: releaseJobID,
                mediaKey: payloadHash,
                stage: stage,
                mimeType: "application/gzip",
                byteCount: compressed.count,
                releaseSeq: releaseSeq)
            uploadStore.updateTask(jobID: releaseJobID) { job in
                if let reason { job.markFailure(status, reason: reason) }
                else { job.markSuccess(status) }
            }
        }

        do {
            // 不可变数据包：已存在且摘要/字节数一致就跳过（§7 旧数据不覆盖）
            let existing = try await writer.fetchPackMetadata(payloadHash: payloadHash)
            if existing == nil {
                let file = try Self.writeTemporary(compressed, suffix: "json.gz")
                defer { try? FileManager.default.removeItem(at: file) }
                try await writer.savePack(
                    payloadHash: payloadHash,
                    partitionID: ShopCatalogOpsPublishScope.partitionID,
                    releaseSeq: 0,
                    sha256: payloadHash,
                    byteCount: compressed.count,
                    fileURL: file)
            }
            // 阶段推进到数据包完成；状态仍是「上传中」—— 整个发布任务还没结束
            markReleaseJob(stage: .release, status: .uploading)

            // 发布头：读当前 → 条件更新（§3.4 第 4 步）
            let snapshot = try await writer.fetchRelease()
            let newSeq = (snapshot?.header.releaseSeq ?? 0) + 1
            let rootIndexData = try Self.makeRootIndexData(
                releaseSeq: newSeq,
                revocationEpoch: snapshot?.header.revocationEpoch ?? 0,
                payloadHash: payloadHash,
                compressedByteCount: compressed.count,
                recordCount: Self.entityCount(of: rewritten)
            )
            let rootIndexHash = ShopCatalogSyncProtocol.sha256Hex(rootIndexData)
            let update = ShopCatalogOpsReleaseUpdate(
                releaseSeq: newSeq,
                schemaVersion: ShopCatalogSyncProtocol.schemaVersion,
                revocationEpoch: snapshot?.header.revocationEpoch ?? 0,
                // 方案 §5.3「只有旧客户端无法正确展示新内容时才提升」——本期**不提升**。
                //
                // 事实先说清楚：不认 `thmedia:` 的旧客户端读不到新包里的图。
                // `ShopCatalogOpsMediaStaging.rewrite` 把 `local:` 引用改写成 `thmedia:<hash>`
                // 时**连 `originalURL` 一起改写**，所以旧客户端既没有 `thmedia:` 分支、
                // 也没有 URL 兜底，商品图会全部落到占位（正文/价格仍能显示）。
                //
                // 那为什么仍不提升：提升**今天就会拦下所有客户端**，因为
                // `ShopCatalogSyncProtocol.readerVersion` 恒为 1，历史构建也都是 1 ——
                // 它当初在加入 `thmedia:` 支持时没有跟着抬，所以这个版本号目前
                // 区分不出「认不认 mediaKey 的读端」。
                //
                // 要真正启用 §5.3 这条闸门，必须配套做（顺序不能反）：
                //   1. 在消费端把 `readerVersion` 抬到 2 并发出新包，让市场上有 2 的读端；
                //   2. 届时把这里的默认值显式写成 2（注意别再依赖
                //      `?? ShopCatalogSyncProtocol.readerVersion`，否则运营端一升级
                //      就会把自己变成「只允许 2」的发布者）；
                //   3. 再发布 minimumReaderVersion=2 的包。
                // 在此之前提升 = 所有存量用户（含当前 TestFlight 包）直接拉不到目录，
                // 属于发布协调决策，不能在单侧静默做。
                minimumReaderVersion: snapshot?.header.minimumReaderVersion
                    ?? ShopCatalogSyncProtocol.readerVersion,
                previousReleaseSeq: snapshot?.header.releaseSeq ?? 0,
                publishedAt: Self.timestamp(),
                rootIndexHash: rootIndexHash,
                rootIndexData: rootIndexData
            )
            try await writer.saveRelease(systemFields: snapshot?.systemFields, update: update)
            markReleaseJob(stage: .release, status: .uploading, releaseSeq: newSeq)

            // ---- 3) 只读端回读验证（普通消费路径，不是写通道自证）
            phase = .verifying
            let verification = await verifyEndToEnd(
                expectedReleaseSeq: newSeq, payloadHash: payloadHash, catalog: rewritten)
            if let failure = verification {
                // 方案 §4 最后一行：不显示「验证成功」，只标「已发布未验证」
                markReleaseJob(stage: .release, status: .publishedButUnverified,
                               reason: failure, releaseSeq: newSeq)
                return .publishedButUnverified(releaseSeq: newSeq, detail: failure)
            }
            markReleaseJob(stage: .release, status: .published, releaseSeq: newSeq)
            return .published(releaseSeq: newSeq, mediaCount: staged.count)
        } catch let error as ShopCatalogOpsUploadError {
            markReleaseJob(stage: error.status == .conflict ? .release : .pack,
                           status: error.status,
                           reason: error.localizedDescription ?? "发布失败")
            return .notPublished(error.localizedDescription ?? "发布失败")
        } catch {
            markReleaseJob(stage: .pack, status: .failed, reason: error.localizedDescription)
            return .notPublished("发布失败：\(error.localizedDescription)")
        }
    }

    // MARK: 单张媒体

    private enum MediaOutcome {
        case uploaded
        case skippedAsRemoteDuplicate
        case failed
    }

    /// 批量问公共库「这些图哪些已经在」。失败时返回 nil —— 调用方退回逐张查询，
    /// **不因为一次网络抖动就把整次发布作废**（慢，但不会误判成「图没传」）。
    private func fetchRemoteMediaIndex(
        for staged: [ShopCatalogOpsStagedMedia]
    ) async -> [String: ShopCatalogOpsRemoteMediaMeta]? {
        let keys = staged.map(\.mediaKey)
        do {
            var index: [String: ShopCatalogOpsRemoteMediaMeta] = [:]
            for chunk in keys.chunked(into: Self.batchLookupSize) {
                let part = try await writer.fetchMediaMetadata(mediaKeys: chunk)
                index.merge(part) { existing, _ in existing }
            }
            return index
        } catch {
            print("[ShopCatalogOps] 批量查询已上传图片失败，退回逐张：\(error.localizedDescription)")
            return nil
        }
    }

    private func uploadOne(
        _ media: ShopCatalogOpsStagedMedia,
        remoteIndex: [String: ShopCatalogOpsRemoteMediaMeta]?
    ) async -> MediaOutcome {
        uploadStore.update(mediaKey: media.mediaKey) { $0.markSuccess(.uploading) }
        do {
            // 幂等跳过（方案 §3.2 第 1 步）：已存在且 sha256 / 字节数一致
            let existing: ShopCatalogOpsRemoteMediaMeta?
            if let remoteIndex {
                existing = remoteIndex[media.mediaKey]
            } else {
                existing = try await writer.fetchMediaMetadata(mediaKey: media.mediaKey)
            }
            let alreadyThere = existing?.sha256 == media.mediaKey
                && existing?.byteCount == media.byteCount

            if alreadyThere {
                // ⭐ 重复上传拦截（2026-09-28）：
                // `THMedia` 是**按内容寻址的不可变记录** —— 记录名就是内容摘要，
                // 摘要与字节数都对得上，内容就一定是同一份，
                // 所以既不再传字节，也**不再把整张图下载回来做回读校验**。
                //
                // 旧写法对「线上已有」的图照样全量下载一遍：450 张就是 450 次下载，
                // 撞上限流后一部分任务变 retryable → unresolved 非空 →
                // 整次发布在媒体阶段就被判失败、**发布头永远切不动**。
                // 只有**本次真上传**的才需要拉字节回读（写入到底生效没有，必须验）。
                uploadStore.update(mediaKey: media.mediaKey) { $0.markSuccess(.mediaVerified) }
                return .skippedAsRemoteDuplicate
            }

            try await writer.saveMedia(
                mediaKey: media.mediaKey,
                mimeType: media.mimeType,
                sha256: media.mediaKey,
                byteCount: media.byteCount,
                fileURL: URL(fileURLWithPath: media.filePath))
            // 回读校验（方案 §3.2 第 6 步）：hash 不一致一律不标 verified
            let readBack = try await writer.fetchMediaBytes(mediaKey: media.mediaKey)
            let digest = ShopCatalogSyncProtocol.sha256Hex(readBack)
            guard digest == media.mediaKey else {
                uploadStore.update(mediaKey: media.mediaKey) {
                    $0.markFailure(.failed, reason: "回读 hash 不一致（期望 \(media.mediaKey.prefix(12))…，"
                                   + "实际 \(digest.prefix(12))…）")
                }
                return .failed
            }
            // 记下「这次已经验过字节」，末尾端到端验证就不再下载第二遍
            verifiedThisRun.insert(media.mediaKey)
            uploadStore.update(mediaKey: media.mediaKey) { $0.markSuccess(.mediaVerified) }
            return .uploaded
        } catch {
            let typed = ShopCatalogOpsUploadError.mapped(error, what: "上传图片")
            uploadStore.update(mediaKey: media.mediaKey) {
                $0.markFailure(typed.status, reason: typed.localizedDescription ?? "未知错误")
            }
            return .failed
        }
    }

    /// 单次批量查询的分块大小（与写入端 `batchLookupSize` 同值）
    private static let batchLookupSize = 200

    // MARK: 回读验证

    /// 用**普通只读路径**验证整条链路（方案 §3.4 第 6 步）。
    /// - Returns: nil = 通过；非 nil = 失败原因
    private func verifyEndToEnd(
        expectedReleaseSeq: Int, payloadHash: String, catalog: ShopCatalog
    ) async -> String? {
        do {
            // 发布头切换后公共库可能有极短的可见性延迟：给 3 次、每次 1 秒的重试，
            // 不是「等它变成功」，超时仍然如实报「已发布未验证」。
            let header = try await Self.retrying(times: 3, delay: 1.0) {
                try await self.reader.fetchReleaseHeader()
            }
            guard header.releaseSeq == expectedReleaseSeq else {
                return "回读发布头序号是 \(header.releaseSeq)，期望 \(expectedReleaseSeq)"
            }
            let rootData = try await reader.fetchRootIndex()
            guard ShopCatalogSyncProtocol.sha256Hex(rootData) == header.rootIndexHash else {
                return "回读根清单 SHA-256 与发布头不符"
            }
            let packCompressed = try await reader.fetchPack(payloadHash: payloadHash)
            _ = try ShopCatalogCloudSyncValidator.validatedShopCatalog(
                header: header, rootIndexData: rootData, packCompressed: packCompressed)

            // 图片链路**独立**校验：数据包校验成功不等于图片能拉到（方案 §5）
            for asset in catalog.assets {
                guard let mediaKey = ShopCatalogSyncProtocol.resolvedMediaKey(
                    asset.mediaKey,
                    fallbackReferences: [asset.originalURL, asset.thumbnailURL, asset.previewURL]
                ) else { continue }
                // 本次已经回读校验过字节 → 不再下载第二遍（去重拦截的另一半）。
                // 450 张图在末尾再全量拉一遍，是撞限流的主要来源。
                if verifiedThisRun.contains(mediaKey) { continue }
                let data = try await Self.retrying(times: 3, delay: 1.0) {
                    try await self.reader.fetchMedia(contentHash: mediaKey)
                }
                guard ShopCatalogSyncProtocol.sha256Hex(data) == mediaKey else {
                    return "回读图片 \(mediaKey.prefix(12))… 的 hash 与声明不符"
                }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: 纯逻辑（可单测）

    /// 组装分片负载。载荷键是 `shopCatalog`（不是画册分片的 `records`）
    nonisolated static func makePayload(catalog: ShopCatalog) -> ShopCatalogPackPayload {
        ShopCatalogPackPayload(
            schemaVersion: ShopCatalogSyncProtocol.schemaVersion,
            partitionID: ShopCatalogOpsPublishScope.partitionID,
            brandID: ShopCatalogOpsPublishScope.brandID,
            entityType: ShopCatalogOpsPublishScope.entityType,
            partitionRevision: 1,
            coverageStatus: entityCount(of: catalog) > 0
                ? ShopCatalogRootIndex.Partition.Coverage.complete
                : ShopCatalogRootIndex.Partition.Coverage.empty,
            checkedThrough: nil,
            shopCatalog: catalog
        )
    }

    /// 根清单字节（`THRelease.rootIndexAsset` 的内容）。
    /// `rootIndexHash` 按**未压缩字节**的 SHA-256 计算 —— 与 Mac 端
    /// `build_release.py`（`root_bytes = canonical_json_bytes(root_index)`）同口径。
    nonisolated static func makeRootIndexData(
        releaseSeq: Int, revocationEpoch: Int,
        payloadHash: String, compressedByteCount: Int, recordCount: Int
    ) throws -> Data {
        let partition = ShopCatalogRootIndex.Partition(
            partitionID: ShopCatalogOpsPublishScope.partitionID,
            brandID: ShopCatalogOpsPublishScope.brandID,
            entityType: ShopCatalogOpsPublishScope.entityType,
            partitionRevision: 1,
            coverageStatus: recordCount > 0
                ? ShopCatalogRootIndex.Partition.Coverage.complete
                : ShopCatalogRootIndex.Partition.Coverage.empty,
            checkedThrough: nil,
            packRecordName: ShopCatalogSyncProtocol.packRecordName(payloadHash: payloadHash),
            payloadHash: payloadHash,
            recordCount: recordCount,
            dependencyPackRecordNames: nil
        )
        let rootIndex = ShopCatalogRootIndex(
            schemaVersion: ShopCatalogSyncProtocol.schemaVersion,
            releaseSeq: releaseSeq,
            publishedAt: timestamp(),
            revocationEpoch: revocationEpoch,
            partitions: [partition],
            withdrawals: nil
        )
        return try ShopCatalogJSONCoding.encoder().encode(rootIndex)
    }

    /// 条目数口径与 Mac 端 `shop_catalog_entity_count` / 客户端结构校验保持一致
    nonisolated static func entityCount(of catalog: ShopCatalog) -> Int {
        catalog.shops.count + catalog.series.count + catalog.products.count
            + catalog.variants.count + catalog.sizeCharts.count + catalog.saleEvents.count
            + catalog.assets.count + catalog.styleProfiles.count
    }

    nonisolated static func timestamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: date)
    }

    nonisolated static func writeTemporary(_ data: Data, suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("th-\(UUID().uuidString).\(suffix)")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 有限次重试（只为容忍刚写入记录的可见性延迟，不做无限退避）
    nonisolated static func retrying<T>(
        times: Int, delay: TimeInterval, _ body: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<max(1, times) {
            do {
                return try await body()
            } catch {
                lastError = error
                if attempt < times - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw lastError ?? ShopCatalogOpsUploadError.failed("重试后仍未成功")
    }

    // MARK: 任务登记

    private func register(_ staged: [ShopCatalogOpsStagedMedia]) {
        for media in staged {
            let owner = media.owners.first
            uploadStore.stage(
                mediaKey: media.mediaKey,
                productID: owner?.productID ?? "",
                assetID: owner?.assetID ?? "",
                filePath: media.filePath,
                mimeType: media.mimeType,
                byteCount: media.byteCount)
        }
    }
}
