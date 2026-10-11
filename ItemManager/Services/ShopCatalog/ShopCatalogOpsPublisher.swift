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
    case upToDate(releaseSeq: Int)
    /// **发布头未切换**：媒体或数据包阶段失败 → 线上仍是旧版本（方案 §3.4 末段）
    case notPublished(String)
    /// 发布头已切换但只读端回读失败 → 只计数「已发布未验证」（方案 §4 最后一行）
    case publishedButUnverified(releaseSeq: Int, detail: String)

    var isSuccess: Bool {
        switch self {
        case .published, .upToDate: return true
        default: return false
        }
    }

    var summary: String {
        switch self {
        case .published(let releaseSeq, let mediaCount):
            return "已发布并验证成功（发布序号 \(releaseSeq)，图片 \(mediaCount) 张）"
        case .upToDate(let releaseSeq):
            return "已是最新（发布序号 \(releaseSeq)），没有待上传的修改"
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

    nonisolated deinit {}

    static let shared = ShopCatalogOpsPublisher()

    /// 粗粒度进度（UI 只用来做「正在做什么」的提示，细状态看任务表）
    enum Phase: Equatable {
        case idle
        case synchronizing
        case staging
        case uploadingMedia
        case publishing
        case verifying

        var displayName: String {
            switch self {
            case .idle: return "空闲"
            case .synchronizing: return "拉取与合并"
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

    /// 上一次「暂存」阶段的问题清单（一次列全：缺图 / 读不出 / 类型不许 / 超上限）。
    ///
    /// 2026-09-29 新增。**这是「上传失败」唯一的可见证据** ——
    /// iOS 侧上传/发布流程本身不打日志（整个类只有 1 处 print），
    /// 界面若不展示它，运营看到的就是「点了没反应」。
    @Published private(set) var lastStagingIssues: [ShopCatalogOpsMediaIssue] = []

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

    #if DEBUG
    static let environmentName = "development"
    #else
    static let environmentName = "production"
    #endif

    private func checkBaseline(_ baseline: ShopCatalogBaseline?,
                               against snapshot: ShopCatalogOpsReleaseSnapshot?) throws {
        guard let baseline, let seq = baseline.releaseSeq,
              baseline.environment == Self.environmentName,
              seq == 0 || !(baseline.rootIndexHash ?? "").isEmpty else {
            throw ShopCatalogOpsUploadError.conflict("请先取回线上内容，再同步更新。")
        }
        let onlineSeq = snapshot?.header.releaseSeq ?? 0
        guard seq == onlineSeq,
              (seq == 0 ? snapshot == nil : baseline.rootIndexHash == snapshot?.header.rootIndexHash) else {
            throw ShopCatalogOpsUploadError.conflict("线上内容已更新，请再次同步更新，合并最新修改。")
        }
    }

    // MARK: 对外入口

    struct ConflictResolution {
        let token: String
        let preferLocal: Bool
    }

    enum SyncResult {
        case conflicts(fields: [String], token: String)
        case finished(ShopCatalogOpsPublishResult)
    }

    /// 唯一运营更新入口：完整读取远端、三方合并、本机落盘，再条件发布。
    /// 冲突选择只适用于本次看到的远端版本和本机内容；重试也必须先重新拉取。
    func synchronizeAndPublish(
        store: ShopCatalogStore, resolution: ConflictResolution? = nil
    ) async -> SyncResult {
        phase = .synchronizing
        lastResult = nil
        lastStagingIssues = []
        lastMediaStats = nil
        defer { phase = .idle }
        do {
            let header: ShopCatalogReleaseHeader?
            do { header = try await reader.fetchReleaseHeader() }
            catch let error as ShopCatalogSyncError {
                guard case .recordMissing(let type, let name) = error,
                      type == "THRelease", name == ShopCatalogSyncProtocol.releaseRecordName else { throw error }
                header = nil
            }
            let remote: ShopCatalog
            if let header {
                guard header.schemaVersion == ShopCatalogSyncProtocol.schemaVersion,
                      header.minimumReaderVersion <= ShopCatalogSyncProtocol.readerVersion else {
                    throw ShopCatalogSyncValidationError.unsupportedSchema("请更新 App 后再同步更新")
                }
                let rootData = try await reader.fetchRootIndex()
                guard ShopCatalogSyncProtocol.sha256Hex(rootData) == header.rootIndexHash else {
                    throw ShopCatalogSyncValidationError.rootIndexMismatch("线上版本正在变化，请重新同步更新")
                }
                let root = try ShopCatalogJSONCoding.decoder().decode(ShopCatalogRootIndex.self, from: rootData)
                guard root.releaseSeq == header.releaseSeq else {
                    throw ShopCatalogSyncValidationError.rootIndexMismatch("根清单版本与发布头不一致")
                }
                if let partition = root.shopCatalogPartition {
                    let pack = try await reader.fetchPack(payloadHash: partition.payloadHash)
                    remote = try ShopCatalogCloudSyncValidator.validatedShopCatalog(
                        header: header, rootIndexData: rootData, packCompressed: pack)
                } else { remote = ShopCatalog() }
            } else { remote = ShopCatalog() }

            let local = store.catalog ?? ShopCatalog()
            let diagnosis = ShopCatalogOpsMediaStaging.diagnose(for: local)
            var hashes: [String: String] = [:]
            for media in diagnosis.staged {
                for owner in media.owners { hashes[owner.reference] = media.mediaKey }
            }
            let baseline = ShopCatalogPackCache.loadPublicationBaseline()
            let token = ShopCatalogSyncProtocol.sha256Hex(
                try ShopCatalogJSONCoding.encoder().encode(local)) + ":" + (header?.rootIndexHash ?? "empty")
            let merged = try ShopCatalogThreeWayMerge.merge(
                local: local, remote: remote,
                baseline: baseline?.environment == Self.environmentName
                    ? ShopCatalogPackCache.loadPublicationCatalog() : nil,
                mediaHashesByLocalReference: hashes,
                preferLocalOnConflict: resolution?.preferLocal ?? false)
            if !merged.conflicts.isEmpty, resolution?.token != token {
                return .conflicts(fields: merged.conflicts, token: token)
            }
            let issues = ShopCatalogCloudSyncValidator.structuralIssues(
                merged.catalog, coverageStatus: Self.entityCount(of: merged.catalog) > 0 ? "complete" : "empty")
            guard issues.isEmpty else {
                throw ShopCatalogOpsUploadError.blocked("目录关联不完整，请先恢复缺失商品：" + issues.prefix(3).joined(separator: "；"))
            }
            let unchanged = header != nil && !diagnosis.isBlocked
                && Self.catalogForPublication(ShopCatalogOpsMediaStaging.rewrite(merged.catalog, mediaKeys: hashes)) == remote
            try store.installMergedCatalog(merged.catalog, remote: remote)
            try ShopCatalogPackCache.savePublicationBaseline(ShopCatalogBaseline(
                releaseSeq: header?.releaseSeq ?? 0, rootIndexHash: header?.rootIndexHash,
                environment: Self.environmentName, observedAt: Date()), catalog: remote)
            if unchanged, let header {
                let result = ShopCatalogOpsPublishResult.upToDate(releaseSeq: header.releaseSeq)
                lastResult = result
                return .finished(result)
            }
            let result = await run(catalog: merged.catalog)
            lastResult = result
            return .finished(result)
        } catch {
            let result = ShopCatalogOpsPublishResult.notPublished(error.localizedDescription)
            lastResult = result
            return .finished(result)
        }
    }

    /// 全流程：暂存 → 上传 → 发布 → 回读验证
    @discardableResult
    func publish(catalog: ShopCatalog) async -> ShopCatalogOpsPublishResult {
        let result = await run(catalog: catalog)
        lastResult = result
        phase = .idle
        return result
    }

    // MARK: 主流程

    private func run(catalog: ShopCatalog) async -> ShopCatalogOpsPublishResult {
        phase = .staging
        verifiedThisRun = []
        lastMediaStats = nil
        let structure = ShopCatalogCloudSyncValidator.structuralIssues(
            catalog, coverageStatus: Self.entityCount(of: catalog) > 0 ? "complete" : "empty")
        guard structure.isEmpty else {
            return .notPublished("目录关联不完整，请先恢复缺失商品或修复归属："
                + structure.prefix(3).joined(separator: "；"))
        }
        // **一次列全**：缺图往往不止一张（线上实测 174 张 / 560 处引用），
        // 只说第一条等于没说 —— 运营没法据此补齐。
        let publication = Self.catalogForPublication(catalog)
        let diagnosis = ShopCatalogOpsMediaStaging.diagnose(for: publication)
        lastStagingIssues = diagnosis.issues
        guard !diagnosis.isBlocked else {
            // 方案 §4 第 1 行：选图读取 / 压缩失败 → stagedFailed，允许重新选图。
            // 缺图是**发布前置条件不满足**，不进入媒体上传阶段，也绝不碰发布头。
            return .notPublished(diagnosis.summary)
        }
        let staged = diagnosis.staged
        // 在任何云端写入前冻结来源版本；上传期间再次检查，随后仍使用 changeTag。
        var baseline = ShopCatalogPackCache.loadPublicationBaseline()
        var previousRootData: Data?
        do {
            let initial = try await writer.fetchRelease()
            // 真正读到空公共库才允许首次发布；读取失败不能落到这条分支。
            if baseline == nil, initial == nil {
                baseline = ShopCatalogBaseline(releaseSeq: 0, environment: Self.environmentName)
            }
            try checkBaseline(baseline, against: initial)
            if let initial {
                let data = try await reader.fetchRootIndex()
                guard ShopCatalogSyncProtocol.sha256Hex(data) == initial.header.rootIndexHash else {
                    throw ShopCatalogOpsUploadError.conflict("线上内容已更新，请再次同步更新")
                }
                previousRootData = data
            }
        } catch {
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
        let rewritten = ShopCatalogOpsMediaStaging.rewrite(publication, mediaKeys: keys)

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
        let catalogSummary = Self.publicationTitle(catalog: rewritten,
            baseline: ShopCatalogPackCache.loadPublicationCatalog())
        uploadStore.upsertTask(
            jobID: releaseJobID,
            mediaKey: payloadHash,
            stage: .pack,
            mimeType: "application/gzip",
            byteCount: compressed.count,
            catalogSummary: catalogSummary)

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
                releaseSeq: releaseSeq,
                catalogSummary: catalogSummary)
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
            try checkBaseline(baseline, against: snapshot)
            let newSeq = (snapshot?.header.releaseSeq ?? 0) + 1
            let rootIndexData = try Self.makeRootIndexData(
                releaseSeq: newSeq,
                revocationEpoch: snapshot?.header.revocationEpoch ?? 0,
                payloadHash: payloadHash,
                compressedByteCount: compressed.count,
                recordCount: Self.entityCount(of: rewritten), previousRootData: previousRootData
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
            do {
                try ShopCatalogPackCache.savePublicationBaseline(ShopCatalogBaseline(
                    releaseSeq: newSeq, rootIndexHash: rootIndexHash,
                    environment: Self.environmentName, observedAt: Date()), catalog: rewritten)
            } catch {
                let detail = "线上发布已验证，但本机未保存核对结果：\(error.localizedDescription)。请再次同步更新。"
                markReleaseJob(stage: .release, status: .publishedButUnverified,
                               reason: detail, releaseSeq: newSeq)
                return .publishedButUnverified(releaseSeq: newSeq, detail: detail)
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
            // 用普通消费读取通道确认图片已可取回，不能只验证写入账号能读。
            let readBack = try await Self.retrying(times: 3, delay: 1.0) {
                try await self.reader.fetchMedia(contentHash: media.mediaKey)
            }
            let digest = ShopCatalogSyncProtocol.sha256Hex(readBack)
            guard digest == media.mediaKey else {
                uploadStore.update(mediaKey: media.mediaKey) {
                    $0.markFailure(.failed, reason: "回读 hash 不一致（期望 \(media.mediaKey.prefix(12))…，"
                                   + "实际 \(digest.prefix(12))…）")
                }
                return .failed
            }
            // 已经通过普通消费路径验过字节，末尾不重复下载。
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
            let installed = try ShopCatalogCloudSyncValidator.validatedShopCatalog(
                header: header, rootIndexData: rootData, packCompressed: packCompressed)
            guard installed == catalog else { return "回读目录与本次提交的商品内容不一致" }

            // 图片链路**独立**校验：数据包校验成功不等于图片能拉到（方案 §5）
            // 同时覆盖店家图标、系列封面、尺码表和资源的各个图片字段。
            var mediaKeys = Set(ShopCatalogMediaReferences.publisherRewritten(in: catalog).compactMap {
                ShopCatalogSyncProtocol.resolvedMediaKey(nil, fallbackReferences: [$0.reference])
            })
            mediaKeys.formUnion(catalog.assets.compactMap {
                ShopCatalogSyncProtocol.resolvedMediaKey($0.mediaKey,
                    fallbackReferences: [$0.originalURL, $0.thumbnailURL, $0.previewURL])
            })
            for mediaKey in mediaKeys.sorted() {
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

    /// 原目录已先通过结构门禁。下架商品的历史留在本机与旧不可变包，
    /// 公共包只携带可关联商品的事件，与 Mac 构建器口径一致，兼容现有读取器。
    nonisolated static func catalogForPublication(_ catalog: ShopCatalog) -> ShopCatalog {
        var output = catalog
        let products = Set(catalog.products.map(\.id))
        output.saleEvents = catalog.saleEvents.filter { products.contains($0.productID) }
        return output
    }

    nonisolated static func publicationTitle(catalog: ShopCatalog, baseline: ShopCatalog?) -> String {
        let changed = catalog.products.filter { product in
            guard let baseline else { return true }
            return !baseline.products.contains(product)
                || catalog.saleEvents.filter { $0.productID == product.id }
                    != baseline.saleEvents.filter { $0.productID == product.id }
                || catalog.shops.first { $0.id == product.shopID }
                    != baseline.shops.first { $0.id == product.shopID }
                || catalog.series.first { $0.id == product.seriesID }
                    != baseline.series.first { $0.id == product.seriesID }
        }
        let products = changed.isEmpty ? catalog.products : changed
        let labels = products.prefix(3).map { product in
            [catalog.shops.first { $0.id == product.shopID }?.name,
             catalog.series.first { $0.id == product.seriesID }?.name, product.name]
                .compactMap { $0 }.joined(separator: " · ")
        }
        if !labels.isEmpty {
            return labels.joined(separator: "；") + (products.count > 3 ? " 等 \(products.count) 件" : "")
        }
        return "店家 \(catalog.shops.count) · 系列 \(catalog.series.count) · 商品 0（无商品）"
    }

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
            checkedThrough: timestamp(),
            shopCatalog: catalog
        )
    }

    /// 根清单字节（`THRelease.rootIndexAsset` 的内容）。
    /// `rootIndexHash` 按**未压缩字节**的 SHA-256 计算 —— 与 Mac 端
    /// `build_release.py`（`root_bytes = canonical_json_bytes(root_index)`）同口径。
    nonisolated static func makeRootIndexData(
        releaseSeq: Int, revocationEpoch: Int,
        payloadHash: String, compressedByteCount: Int, recordCount: Int,
        previousRootData: Data? = nil
    ) throws -> Data {
        let partition = ShopCatalogRootIndex.Partition(
            partitionID: ShopCatalogOpsPublishScope.partitionID,
            brandID: ShopCatalogOpsPublishScope.brandID,
            entityType: ShopCatalogOpsPublishScope.entityType,
            partitionRevision: 1,
            coverageStatus: recordCount > 0
                ? ShopCatalogRootIndex.Partition.Coverage.complete
                : ShopCatalogRootIndex.Partition.Coverage.empty,
            checkedThrough: timestamp(),
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
        let fresh = try ShopCatalogJSONCoding.encoder().encode(rootIndex)
        guard let previousRootData else { return fresh }
        var previous = try JSONSerialization.jsonObject(with: previousRootData) as! [String: Any]
        let update = try JSONSerialization.jsonObject(with: fresh) as! [String: Any]
        for key in ["schemaVersion", "releaseSeq", "publishedAt", "revocationEpoch"] {
            previous[key] = update[key]
        }
        let replacement = (update["partitions"] as! [[String: Any]])[0]
        var partitions = previous["partitions"] as? [[String: Any]] ?? []
        if let index = partitions.firstIndex(where: { $0["partitionID"] as? String == ShopCatalogOpsPublishScope.partitionID }) {
            partitions[index] = replacement
        } else { partitions.append(replacement) }
        previous["partitions"] = partitions
        return try JSONSerialization.data(withJSONObject: previous, options: [.sortedKeys])
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
