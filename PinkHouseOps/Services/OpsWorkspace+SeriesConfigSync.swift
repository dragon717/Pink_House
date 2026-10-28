import Foundation
import PinkHouseOpsCore
import SharedCatalog

extension OpsWorkspace {
    /// 保存字段逐环境应用；重新下载并核验业务内容之后，才能记录确认回执。
    func synchronizeSavedSeries(requestID: String, updates: [OpsSeriesConfigUpdate],
                                cloud: OpsCloudSyncModel, editorUpdates: [OpsCatalogEditorUpdate] = [],
                                bridge: ((OpsBridgeMode, ShopCatalogPublishRequest, URL) async -> OpsBridgeRunResult?)? = nil) async -> OpsPublishInvocationResult {
        guard !cloud.isRunning, !cloud.isSyncing, let draftID = draft?.id else {
            return .failed("另一个同步任务正在运行，保存仍在队列中。")
        }
        let revision = draft?.catalogSyncRevision ?? currentRevision
        cloud.isSyncing = true
        let ownsLog = cloud.beginOperationLog("同步已保存修改到开发环境和线上环境")
        var conclusion = "保存内容尚未完成全部同步"
        defer {
            cloud.savedEditorProgress = nil
            cloud.isSyncing = false
            if ownsLog { cloud.finishOperationLog(conclusion) }
        }
        var receipts = draft?.catalogSyncSeriesReceiptsJSON.flatMap {
            try? JSONDecoder().decode([String: Int].self, from: $0)
        } ?? [:]
        let root = rootDirectory.appendingPathComponent("series-config-sync/" + requestID)
        let staging = stagingDirectory
        // 仅使用已确认发布的快照补旧版漏发商品的关联资料，不读取网络期间的新输入。
        let confirmedSource = draft?.baseline.rootIndexHash == draft?.lastPublishedRootIndexHash ? baselineCatalog : nil
        var verificationUpdates = editorUpdates
        var mediaHashes: [String: String] = [:]
        for snapshot in editorUpdates.flatMap({ [$0.before, $0.after] }) + updates.compactMap(\.publishedOrderCatalog) + [catalog] + [confirmedSource].compactMap({ $0 }) {
            for asset in snapshot.assets {
                if let hash = ShopCatalogSyncProtocol.resolvedMediaKey(asset.mediaKey) {
                    for ref in [asset.id, asset.originalURL, asset.previewURL, asset.thumbnailURL].compactMap({ $0 }) {
                        mediaHashes[ref] = hash
                    }
                }
            }
            for ref in ShopCatalogMediaReferences.all(in: snapshot) where ref.reference.hasPrefix("local:") {
                if let file = stagedFileURL(forReference: ref.reference), let data = try? Data(contentsOf: file) {
                    mediaHashes[ref.reference] = ShopCatalogSyncProtocol.sha256Hex(data)
                }
            }
        }
        func checkOwner() throws {
            guard draft?.id == draftID else { throw syncFailure("草稿已切换，未修改新草稿。") }
        }
        func advance(_ environment: ShopCatalogPublishTargetEnvironment, _ stage: Int, _ detail: String) {
            advanceSavedSync(requestID: requestID, environment: environment.rawValue, stage: stage, detail: detail)
        }
        cloud.savedEditorProgress = { [weak self] event, mode, environment in
            guard ["stage", "progress"].contains(event.type), let stage = event.stage else { return }
            var detail: String
            switch stage {
            case .freeze, .build: detail = "准备商品资料"
            case .verifyArtifact: detail = "检查商品资料"
            case .readHead, .baseline: detail = "核对云端版本"
            case .uploadMedia: detail = "上传商品图片"
            case .uploadPacks: detail = "上传商品资料"
            case .readBack: detail = "回读核对图片和资料"
            case .switchHead: detail = "保存云端更新"
            case .confirmHead: detail = "确认云端更新结果"
            case .remoteMedia: detail = "检查已有图片"
            case .fetchMedia: detail = "下载所需图片"
            }
            if let completed = event.completed, let total = event.total, total > 0, completed >= 0 {
                detail += "（\(min(completed, total))/\(total)）"
            }
            self?.advanceSavedSync(requestID: requestID, environment: environment.rawValue,
                stage: mode == .publish ? 2 : 1, detail: detail)
        }
        func run(_ mode: OpsBridgeMode, _ request: ShopCatalogPublishRequest, _ url: URL) async -> OpsBridgeRunResult? {
            if let bridge { return await bridge(mode, request, url) }
            return await cloud.runEnvironmentBridge(mode: mode, request: request, requestURL: url)
        }
        func read(_ environment: ShopCatalogPublishTargetEnvironment, directory: URL) async throws -> (OpsPulledCatalog, ShopCatalog) {
            let request = ShopCatalogPublishRequest(requestID: UUID().uuidString, jobID: requestID,
                draftID: draftID, draftRevision: revision, targetEnvironment: environment, releaseSeq: 1,
                inputDirectory: directory.appendingPathComponent("input").path,
                archivePath: directory.appendingPathComponent("none.tar").path,
                outputDirectory: directory.path, receiptPath: directory.appendingPathComponent("read-receipt.json").path,
                dryRun: true, payloadHash: "saved-edit-read")
            let result = await run(.pullCatalog, request, directory.appendingPathComponent("pull-request.json"))
            try checkOwner()
            guard let result, result.exitCode == 0, result.outcome == .confirmed,
                  let pulled = OpsPulledCatalog.from(result: result, environment: environment.rawValue),
                  result.onlineHead?.environment == environment.rawValue,
                  pulled.releaseSeq == 0 || pulled.rootIndexHash.map(ShopCatalogSyncProtocol.isPayloadHash) == true else {
                throw syncFailure(cloud.lastError ?? result?.outcomeMessage ?? "目录读取缺少可核验的版本或摘要。")
            }
            let remote = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self,
                from: Data(contentsOf: URL(fileURLWithPath: pulled.path)))
            return (pulled, remote)
        }
        func verify(_ remote: ShopCatalog) throws {
            try OpsCatalogEditorUpdate.verify(verificationUpdates, in: remote, mediaHashes: mediaHashes)
            try OpsSeriesConfigUpdate.verifyProductOrders(updates, in: remote)
            let reapplied = try OpsSeriesConfigUpdate.applying(updates, to: remote)
            guard try OpsCatalogEditorUpdate.equivalent(reapplied, remote, mediaHashes: mediaHashes) else {
                throw syncFailure("回读系列配置仍与保存内容不一致，未确认同步完成。")
            }
        }
        func checkpoint(_ environment: ShopCatalogPublishTargetEnvironment, pulled: OpsPulledCatalog,
                        verified: ShopCatalog) throws {
            try recordConfirmedEditorSync(requestID: requestID, verified: verified,
                head: .init(releaseSeq: pulled.releaseSeq, rootIndexHash: pulled.rootIndexHash,
                    environment: environment.rawValue, observedAt: Date()))
            receipts[environment.rawValue] = pulled.releaseSeq
            guard draft?.catalogSyncRequestID == requestID else { return }
            var progress = catalogEditSyncProgress ?? .init(requestID: requestID, revision: revision)
            progress.confirm(environment: environment.rawValue, releaseSeq: pulled.releaseSeq)
            catalogEditSyncProgress = progress
            draft?.catalogSyncProgressJSON = try JSONEncoder().encode(progress)
            try saveCatalogContext(context)
        }
        func confirmPublished(_ result: OpsBridgeRunResult?, request: ShopCatalogPublishRequest) throws -> String {
            guard let result, result.exitCode == 0, result.outcome == .confirmed,
                  let receipt = result.receipt, receipt.applied == true, receipt.readBackConfirmed == true,
                  receipt.requestID == request.requestID, receipt.jobID == request.jobID,
                  receipt.draftID == request.draftID, receipt.draftRevision == request.draftRevision,
                  receipt.environment == request.targetEnvironment.rawValue,
                  receipt.artifactDigest == request.payloadHash, receipt.releaseSeq == request.releaseSeq,
                  let hash = receipt.rootIndexHash, ShopCatalogSyncProtocol.isPayloadHash(hash) else {
                throw syncFailure(result?.outcomeMessage ?? cloud.lastError ?? "本次发布回执身份或回读确认不完整，结果仍待核对。")
            }
            return hash
        }
        do {
            for environment in [ShopCatalogPublishTargetEnvironment.development, .production] {
                try checkOwner()
                if receipts[environment.rawValue] != nil { continue }
                advance(environment, 0, "读取最新目录")
                let directory = root.appendingPathComponent(environment.rawValue)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let frozenURL = directory.appendingPathComponent("publish-request.json")
                var expected: (Int, String)?
                verificationUpdates = editorUpdates
                let dependencyURL = directory.appendingPathComponent("missing-products-update.json")
                if FileManager.default.fileExists(atPath: frozenURL.path) {
                    if FileManager.default.fileExists(atPath: dependencyURL.path) {
                        let dependency = try ShopCatalogJSONCoding.decoder().decode(OpsCatalogEditorUpdate.self,
                            from: Data(contentsOf: dependencyURL))
                        verificationUpdates.insert(dependency, at: 0)
                    }
                    let frozen = try ShopCatalogPublishRequest.decoded(from: Data(contentsOf: frozenURL))
                    guard frozen.draftID == draftID, frozen.targetEnvironment == environment else {
                        throw syncFailure("冻结任务与当前草稿或环境不符，已停止。")
                    }
                    advance(environment, 1, "查询上次保存的发布结果")
                    let queried = await run(.query, frozen, directory.appendingPathComponent("query-request.json"))
                    try checkOwner()
                    if OpsSeriesConfigUpdate.canRetryFrozenPublish(queryExitCode: queried?.exitCode,
                        outcome: queried?.outcome, head: queried?.onlineHead, request: frozen) {
                        let retried = await run(.publish, frozen, frozenURL)
                        expected = (frozen.releaseSeq, try confirmPublished(retried, request: frozen))
                    } else {
                        let artifact = try JSONSerialization.jsonObject(with: Data(contentsOf:
                            URL(fileURLWithPath: frozen.outputDirectory).appendingPathComponent("release.json"))) as? [String: Any]
                        guard queried?.exitCode == 0, queried?.outcome == .confirmed,
                              let hash = artifact?["rootIndexHash"] as? String,
                              queried?.onlineHead?.environment == environment.rawValue,
                              queried?.onlineHead?.releaseSeq == frozen.releaseSeq,
                              queried?.onlineHead?.rootIndexHash == hash else {
                            throw syncFailure(queried?.outcomeMessage ?? "上次任务尚未回读确认，请先核对同步结果。")
                        }
                        expected = (frozen.releaseSeq, hash)
                    }
                } else {
                    let (pulled, remote) = try await read(environment, directory: directory.appendingPathComponent("pulled"))
                    advance(environment, 1, "核对本次保存的修改")
                    let base = try OpsSeriesConfigUpdate.applying(updates, to: remote)
                    if let dependency = try OpsCatalogEditorUpdate.missingProductDependencies(updates.compactMap { $0.productOrderDependencySeed() } + editorUpdates,
                        in: base, confirmedSource: confirmedSource) {
                        try ShopCatalogJSONCoding.encoder().encode(dependency).write(to: dependencyURL, options: .atomic)
                        verificationUpdates.insert(dependency, at: 0)
                    } else if FileManager.default.fileExists(atPath: dependencyURL.path) {
                        try FileManager.default.removeItem(at: dependencyURL)
                    }
                    var updated = try OpsCatalogEditorUpdate.applying(verificationUpdates, to: base, mediaHashes: mediaHashes)
                    // 关联补齐可能在数组末尾追加商品；发布前再次落实旧客户端实际读取的数组顺序。
                    if updates.contains(where: { $0.fields.contains(.productOrder) }) {
                        updated.products = CatalogProductOrdering.publicationOrder(updated.products)
                    }
                    if try OpsCatalogEditorUpdate.equivalent(updated, remote, mediaHashes: mediaHashes) {
                        try verify(remote)
                        try checkpoint(environment, pulled: pulled, verified: remote)
                        continue
                    }
                    let media = await cloud.recoverSyncMedia(workspace: self, remote: updated,
                        environment: environment.rawValue, updateReport: false, includeLocalReferences: false,
                        stillCurrent: { self.draft?.id == draftID })
                    try checkOwner()
                    guard media.issues.isEmpty else { throw syncFailure(media.issues.map(\.message).joined(separator: "；")) }
                    let archive = try await Task.detached(priority: .userInitiated) {
                        try OpsSeriesConfigUpdate.archive(catalog: updated, mediaDirectory: staging)
                    }.value
                    let archiveURL = directory.appendingPathComponent("release.tar")
                    try archive.write(to: archiveURL, options: .atomic)
                    let hash = ShopCatalogSyncProtocol.sha256Hex(archive)
                    let publish = ShopCatalogPublishRequest(requestID: ShopCatalogPublishRequestKey.make(
                        draftID: draftID, draftRevision: revision, payloadHash: hash, targetEnvironment: environment,
                        releaseSeq: pulled.releaseSeq + 1), jobID: requestID, draftID: draftID, draftRevision: revision,
                        baseReleaseSeq: pulled.releaseSeq, baseRootIndexHash: pulled.rootIndexHash,
                        targetEnvironment: environment, releaseSeq: pulled.releaseSeq + 1,
                        inputDirectory: directory.appendingPathComponent("input").path, archivePath: archiveURL.path,
                        outputDirectory: directory.appendingPathComponent("output").path,
                        receiptPath: directory.appendingPathComponent("receipt.json").path,
                        preserveTargetPartitions: true, payloadHash: hash)
                    try publish.encoded().write(to: frozenURL, options: .atomic)
                    advance(environment, 2, "上传本次修改")
                    let published = await run(.publish, publish, frozenURL)
                    try checkOwner()
                    expected = (publish.releaseSeq, try confirmPublished(published, request: publish))
                }
                advance(environment, 3, "重新读取并核对商品内容")
                let (pulled, remote) = try await read(environment, directory: directory.appendingPathComponent("verified"))
                guard pulled.releaseSeq == expected?.0, pulled.rootIndexHash == expected?.1 else {
                    throw syncFailure("重新读取的环境版本或摘要已变化，未确认本次修改生效。")
                }
                try verify(remote)
                try checkpoint(environment, pulled: pulled, verified: remote)
            }
            conclusion = "开发环境与线上环境的保存内容均已重新回读核对。"
            return .confirmed(releaseSeq: receipts[cloud.targetEnvironment.rawValue] ?? 0)
        } catch {
            conclusion = receipts.keys.sorted().map { "\($0) 已确认第 \(receipts[$0]!) 版" }.joined(separator: "；")
                + (receipts.isEmpty ? "" : "；") + error.localizedDescription
            return .failed(conclusion)
        }
    }

    private func syncFailure(_ message: String) -> NSError {
        NSError(domain: "OpsSavedEditSync", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
