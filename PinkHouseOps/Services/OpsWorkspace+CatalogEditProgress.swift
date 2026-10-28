import Foundation
import PinkHouseOpsCore
import SharedCatalog

extension OpsWorkspace {
    func advanceSavedSync(requestID: String, environment: String, stage: Int, detail: String) {
        guard let draft, draft.catalogSyncRequestID == requestID else { return }
        var progress = catalogEditSyncProgress.flatMap { $0.requestID == requestID ? $0 : nil }
            ?? OpsCatalogEditProgress(requestID: requestID, revision: draft.catalogSyncRevision ?? currentRevision)
        progress.advance(environment: environment, stage: stage, detail: detail)
        catalogEditSyncProgress = progress
        draft.catalogSyncProgressJSON = try? JSONEncoder().encode(progress)
        do { try saveCatalogContext(context) }
        catch { catalogEditSyncMessage = "同步进度记录保存失败：\(error.localizedDescription)" }
    }

    func finishSavedCatalogSync(request: OpsCatalogEditSyncQueue.Request, result: OpsCatalogEditSyncQueue.Outcome) {
        guard let draft, draft.catalogSyncRequestID == request.id else { return }
        var progress = catalogEditSyncProgress ?? .init(requestID: request.id, revision: request.revision)
        let receipts = draft.catalogSyncSeriesReceiptsJSON.flatMap {
            try? JSONDecoder().decode([String: Int].self, from: $0)
        } ?? [:]
        for (environment, seq) in receipts { progress.confirm(environment: environment, releaseSeq: seq) }
        var failure: String?
        switch result {
        case .failed(let reason): failure = reason
        case .confirmed:
            if !["development", "production"].allSatisfy({ receipts[$0] != nil }) {
                failure = "缺少开发环境或线上环境的内容回读确认，尚未完成全部同步。"
            }
        }
        if let failure {
            progress.fail(failure)
            draft.catalogSyncError = failure
            catalogEditSyncMessage = "本机已保存，同步未完成：\(failure)"
        } else {
            catalogEditSyncMessage = "开发环境与线上环境的本次修改均已回读确认。"
        }
        let previous = (draft.catalogSyncRequestID, draft.catalogSyncRevision, draft.catalogSyncEnvironment,
                        draft.catalogSyncSeriesUpdatesJSON, draft.catalogSyncEditorUpdatesJSON,
                        draft.catalogSyncSeriesReceiptsJSON, draft.catalogSyncProgressJSON)
        if failure == nil {
            draft.catalogSyncRequestID = nil; draft.catalogSyncRevision = nil
            draft.catalogSyncEnvironment = nil; draft.catalogSyncError = nil
            draft.catalogSyncSeriesUpdatesJSON = nil; draft.catalogSyncEditorUpdatesJSON = nil
            draft.catalogSyncSeriesReceiptsJSON = nil
        }
        draft.catalogSyncProgressJSON = try? JSONEncoder().encode(progress)
        do { try saveCatalogContext(context) }
        catch {
            (draft.catalogSyncRequestID, draft.catalogSyncRevision, draft.catalogSyncEnvironment,
             draft.catalogSyncSeriesUpdatesJSON, draft.catalogSyncEditorUpdatesJSON,
             draft.catalogSyncSeriesReceiptsJSON, draft.catalogSyncProgressJSON) = previous
            let reason = "云端结果已收到，但本机同步记录保存失败；请重试核对：\(error.localizedDescription)"
            draft.catalogSyncError = reason
            progress.fail(reason)
            catalogEditSyncMessage = reason
        }
        catalogEditSyncProgress = progress
    }
}

extension OpsWorkspace {
    /// 一次性补救旧版「只确认一个环境」的名称修改，保留每个环境自己的价格、图片和档期。
    /// 取最近一次已确认发布的身份字段，以另一环境保存的祖先作为冲突参照；不强制选本机赢。
    @discardableResult
    func enqueueLegacyNameRepairIfNeeded(previousSourceCatalog: ShopCatalog? = nil) -> Bool {
        guard let draft, !draft.isCorrupted, draft.catalogEditorDualSyncVersion == nil,
              draft.catalogSyncRequestID == nil, draft.hasEverPublished,
              let source = legacyConfirmedNameSource(), let sourceEnvironment = source.head.environment,
              let targetEnvironment = ShopCatalogPublishTargetEnvironment.allCases.first(where: { $0.rawValue != sourceEnvironment }),
              let target = draft.mergeBaseline(environment: targetEnvironment.rawValue) else { return false }
        let published = source.catalog
        var before = target.catalog
        // 旧版局部同步可能只有部分实体的祖先。只为缺失实体补入源环境上次实际下载的旧身份，
        // 不把源环境整包冒充目标环境基线；实际远端仍须匹配旧值或目标值，否则阻断。
        if let prior = previousSourceCatalog ?? legacyPreviousSourceCatalog(environment: sourceEnvironment,
                                                                           beforeRelease: source.head.releaseSeq ?? 0) {
            for product in prior.products where !before.products.contains(where: { $0.id == product.id }) {
                guard let current = published.products.first(where: { $0.id == product.id }),
                      product.name != current.name || product.designName != current.designName || product.category != current.category else { continue }
                before.products.append(product)
            }
        }
        var after = before
        var processed: Set<String> = []
        for source in published.products {
            guard let stored = after.products.first(where: { $0.id == source.id }),
                  stored.seriesID == source.seriesID, stored.shopID == source.shopID,
                  processed.insert(source.id).inserted,
                  stored.name != source.name || stored.category != source.category || stored.designName != source.designName else { continue }
            var edited = stored
            edited.name = source.name; edited.category = source.category
            let plan = ShopCatalogProductRename.plan(edited: edited, basedOn: stored,
                among: after.products, profiles: after.styleProfiles,
                explicitDesignName: ShopCatalogSameDesignGrouper.designName(of: source))
            let values = Dictionary(uniqueKeysWithValues: plan.products.map { ($0.id, $0) })
            for index in after.products.indices {
                if let value = values[after.products[index].id] { after.products[index] = value }
            }
            processed.formUnion(values.keys)
            let removed = Set(plan.styleProfile.removals + plan.styleProfile.upserts.map(\.id))
            after.styleProfiles.removeAll { removed.contains($0.id) }
            after.styleProfiles.append(contentsOf: plan.styleProfile.upserts)
        }
        for index in after.shops.indices {
            if let source = published.shops.first(where: { $0.id == after.shops[index].id }) {
                after.shops[index].name = source.name
            }
        }
        for index in after.series.indices {
            if let source = published.series.first(where: { $0.id == after.series[index].id }) {
                after.series[index].name = source.name
            }
        }
        let update = OpsCatalogEditorUpdate(before: before, after: after)
        guard !update.isEmpty else { return false }
        let id = UUID().uuidString
        let progress = OpsCatalogEditProgress(requestID: id, revision: draft.lastPublishedRevision ?? savedRevision)
        do {
            draft.catalogSyncEditorUpdatesJSON = try ShopCatalogJSONCoding.encoder().encode([update])
            draft.catalogSyncProgressJSON = try JSONEncoder().encode(progress)
            draft.catalogSyncRequestID = id; draft.catalogSyncRevision = progress.revision
            draft.catalogSyncEnvironment = sourceEnvironment
            draft.catalogSyncSeriesReceiptsJSON = nil; draft.catalogSyncError = nil
            draft.catalogEditorDualSyncVersion = 1
            try saveCatalogContext(context)
            catalogEditSyncProgress = progress
            catalogEditSyncMessage = "正在补核对旧版仅同步一个环境的名称修改…"
            return true
        } catch {
            draft.catalogSyncRequestID = nil; draft.catalogSyncRevision = nil
            draft.catalogSyncEnvironment = nil; draft.catalogSyncEditorUpdatesJSON = nil
            draft.catalogSyncProgressJSON = nil; draft.catalogEditorDualSyncVersion = nil
            catalogEditSyncMessage = "旧版名称补同步任务未保存：\(error.localizedDescription)"
            return false
        }
    }

    /// 手动拉取会移动当前比较基线；补救方向只能来自最后一次确认发布的摘要。
    private func legacyConfirmedNameSource() -> OpsCatalogMergeBaseline? {
        guard let draft, let hash = draft.lastPublishedRootIndexHash else { return nil }
        if draft.baseline.rootIndexHash == hash, let catalog = baselineCatalog {
            return .init(head: draft.baseline, catalog: catalog)
        }
        return draft.environmentBaselines.values.first { $0.head.rootIndexHash == hash }
    }

    private func legacyPreviousSourceCatalog(environment: String, beforeRelease: Int) -> ShopCatalog? {
        let root = OpsCloudSyncModel.shared.jobsDirectory
        let directories = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var latest: (Int, String, ShopCatalog)?
        for directory in directories where directory.lastPathComponent.hasPrefix("pull-") {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("pull-manifest.json")),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  manifest["targetEnvironment"] as? String == environment,
                  let seq = manifest["releaseSeq"] as? Int, seq < beforeRelease,
                  let hash = manifest["rootIndexHash"] as? String, ShopCatalogSyncProtocol.isPayloadHash(hash),
                  let payload = manifest["payloadHash"] as? String, ShopCatalogSyncProtocol.isPayloadHash(payload),
                  let catalogData = try? Data(contentsOf: directory.appendingPathComponent("shop-catalog.json")),
                  let catalog = try? ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: catalogData)
            else { continue }
            let at = manifest["pulledAt"] as? String ?? ""
            if let previous = latest, seq < previous.0 || (seq == previous.0 && at <= previous.1) { continue }
            latest = (seq, at, catalog)
        }
        return latest?.2
    }

}
