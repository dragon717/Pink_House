import Foundation
import PinkHouseOpsCore
import SharedCatalog

extension OpsWorkspace {
    /// 保存后的后台任务：分别读取两套最新目录，只覆盖已保存字段，逐环境回读确认。
    func synchronizeSavedSeries(requestID: String, updates: [OpsSeriesConfigUpdate],
                                cloud: OpsCloudSyncModel) async -> OpsPublishInvocationResult {
        guard !cloud.isRunning, !cloud.isSyncing, let draftID = draft?.id else {
            return .failed("另一个同步任务正在运行，系列保存仍在队列中。")
        }
        cloud.isSyncing = true
        let ownsLog = cloud.beginOperationLog("自动同步已保存的系列配置")
        var conclusion = "系列配置同步未完成"
        defer {
            cloud.isSyncing = false
            if ownsLog { cloud.finishOperationLog(conclusion) }
        }
        var receipts = (draft?.catalogSyncSeriesReceiptsJSON).flatMap {
            try? JSONDecoder().decode([String: Int].self, from: $0)
        } ?? [:]
        let root = rootDirectory.appendingPathComponent("series-config-sync/" + requestID)
        let staging = stagingDirectory
        func checkOwner() throws {
            guard draft?.id == draftID else { throw syncFailure("草稿已切换，未修改新草稿。") }
        }
        func checkpoint(_ environment: ShopCatalogPublishTargetEnvironment, seq: Int,
                        hash: String?, previousRemote: ShopCatalog) throws {
            guard let hash, ShopCatalogSyncProtocol.isPayloadHash(hash) else {
                throw syncFailure("回读缺少有效根摘要，尚未记录该环境已同步。")
            }
            try recordConfirmedSeriesSync(requestID: requestID, updates: updates,
                previousRemote: previousRemote, head: .init(releaseSeq: seq, rootIndexHash: hash,
                    environment: environment.rawValue, observedAt: Date()))
            receipts[environment.rawValue] = seq
        }
        do {
            for environment in [ShopCatalogPublishTargetEnvironment.development, .production] {
                try checkOwner()
                if receipts[environment.rawValue] != nil { continue }
                catalogEditSyncMessage = "本地已保存，正在自动更新\(environment.displayName)…"
                let directory = root.appendingPathComponent(environment.rawValue)
                let frozenURL = directory.appendingPathComponent("publish-request.json")
                if FileManager.default.fileExists(atPath: frozenURL.path) {
                    // 上次发送结果不确定时先查询冻结请求，禁止换号盲发。
                    let frozen = try ShopCatalogPublishRequest.decoded(from: Data(contentsOf: frozenURL))
                    let queried = await cloud.runEnvironmentBridge(mode: .query, request: frozen,
                        requestURL: directory.appendingPathComponent("query-request.json"))
                    try checkOwner()
                    var confirmedHash: String?
                    if OpsSeriesConfigUpdate.canRetryFrozenPublish(queryExitCode: queried?.exitCode,
                        outcome: queried?.outcome, head: queried?.onlineHead, request: frozen) {
                        let retried = await cloud.runEnvironmentBridge(mode: .publish, request: frozen,
                            requestURL: frozenURL)
                        try checkOwner()
                        guard retried?.outcome == .confirmed,
                              retried?.receipt?.readBackConfirmed == true,
                              retried?.receipt?.releaseSeq == frozen.releaseSeq else {
                            throw syncFailure(retried?.outcomeMessage ?? cloud.lastError ?? "原任务重试结果尚未确认。")
                        }
                        confirmedHash = retried?.receipt?.rootIndexHash
                    } else {
                        let artifact = (try? Data(contentsOf: URL(fileURLWithPath: frozen.outputDirectory)
                            .appendingPathComponent("release.json"))).flatMap {
                                (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
                            }
                        guard queried?.exitCode == 0, queried?.outcome == .confirmed,
                              let expectedHash = artifact?["rootIndexHash"] as? String, !expectedHash.isEmpty,
                              queried?.onlineHead?.releaseSeq == frozen.releaseSeq,
                              queried?.onlineHead?.rootIndexHash == expectedHash else {
                            if queried?.outcome == .confirmed {
                                throw syncFailure("云端发布号或根清单摘要未通过核对，未确认本次更新；请打开更新日志核对。")
                            }
                            if queried?.outcome == .replaced || queried?.outcome == .conflict {
                                throw syncFailure("线上已有不同版本，请核对该系列后重新保存；本地修改已保留。")
                            }
                            throw syncFailure(queried?.outcomeMessage ?? cloud.lastError ?? "上次保存的云端结果尚未确认。")
                        }
                        confirmedHash = expectedHash
                    }
                    let previousRemote = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self,
                        from: Data(contentsOf: directory.appendingPathComponent("pulled/shop-catalog.json")))
                    try checkpoint(environment, seq: frozen.releaseSeq, hash: confirmedHash,
                                   previousRemote: previousRemote)
                    continue
                }
                let pull = ShopCatalogPublishRequest(requestID: UUID().uuidString, jobID: requestID,
                    draftID: draftID, draftRevision: currentRevision, targetEnvironment: environment,
                    releaseSeq: 1, inputDirectory: directory.appendingPathComponent("input").path,
                    archivePath: directory.appendingPathComponent("none.tar").path,
                    outputDirectory: directory.appendingPathComponent("pulled").path,
                    receiptPath: directory.appendingPathComponent("read-receipt.json").path,
                    dryRun: true, payloadHash: "saved-series-read")
                let result = await cloud.runEnvironmentBridge(mode: .pullCatalog, request: pull,
                    requestURL: directory.appendingPathComponent("pull-request.json"))
                try checkOwner()
                guard let result, result.exitCode == 0, result.outcome == .confirmed,
                      let pulled = OpsPulledCatalog.from(result: result, environment: environment.rawValue) else {
                    throw syncFailure(cloud.lastError ?? result?.outcomeMessage ?? "目录读取未完成。")
                }
                let remote = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self,
                    from: Data(contentsOf: URL(fileURLWithPath: pulled.path)))
                let updated = try OpsSeriesConfigUpdate.applying(updates, to: remote)
                if updated == remote {
                    try checkpoint(environment, seq: pulled.releaseSeq, hash: pulled.rootIndexHash,
                                   previousRemote: remote)
                    continue
                }
                let media = await cloud.recoverSyncMedia(workspace: self, remote: updated,
                    environment: environment.rawValue, updateReport: false, includeLocalReferences: false,
                    stillCurrent: { self.draft?.id == draftID })
                try checkOwner()
                guard media.issues.isEmpty else {
                    throw syncFailure(media.issues.map(\.message).joined(separator: "；"))
                }
                let archive = try await Task.detached(priority: .userInitiated) {
                    try OpsSeriesConfigUpdate.archive(catalog: updated, mediaDirectory: staging)
                }.value
                try checkOwner()
                let archiveURL = directory.appendingPathComponent("release.tar")
                try archive.write(to: archiveURL, options: .atomic)
                let hash = ShopCatalogSyncProtocol.sha256Hex(archive)
                let publish = ShopCatalogPublishRequest(
                    requestID: ShopCatalogPublishRequestKey.make(draftID: draftID,
                        draftRevision: currentRevision, payloadHash: hash,
                        targetEnvironment: environment, releaseSeq: pulled.releaseSeq + 1),
                    jobID: requestID, draftID: draftID, draftRevision: currentRevision,
                    baseReleaseSeq: pulled.releaseSeq, baseRootIndexHash: pulled.rootIndexHash,
                    targetEnvironment: environment, releaseSeq: pulled.releaseSeq + 1,
                    inputDirectory: directory.appendingPathComponent("input").path,
                    archivePath: archiveURL.path, outputDirectory: directory.appendingPathComponent("output").path,
                    receiptPath: directory.appendingPathComponent("receipt.json").path,
                    preserveTargetPartitions: true, payloadHash: hash)
                // 冻结先落盘，再允许发布；后续恢复走上面的 query 分支。
                try publish.encoded().write(to: frozenURL, options: .atomic)
                let published = await cloud.runEnvironmentBridge(mode: .publish, request: publish,
                    requestURL: frozenURL)
                try checkOwner()
                guard published?.outcome == .confirmed,
                      published?.receipt?.readBackConfirmed == true,
                      published?.receipt?.releaseSeq == publish.releaseSeq else {
                    throw syncFailure(published?.outcomeMessage ?? cloud.lastError ?? "发布结果尚未确认。")
                }
                try checkpoint(environment, seq: publish.releaseSeq, hash: published?.receipt?.rootIndexHash,
                               previousRemote: remote)
            }
            conclusion = "已自动同步：Development \(receipts["development"] ?? 0)，Production \(receipts["production"] ?? 0)，均已回读确认。"
            return .confirmed(releaseSeq: receipts[cloud.targetEnvironment.rawValue] ?? 0)
        } catch {
            let completed = receipts.keys.sorted().map { "\($0) 已确认发布号 \(receipts[$0]!)" }.joined(separator: "；")
            conclusion = (completed.isEmpty ? "" : completed + "；") + error.localizedDescription
            return .failed(conclusion)
        }
    }

    private func syncFailure(_ message: String) -> NSError {
        NSError(domain: "OpsSeriesConfigSync", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
