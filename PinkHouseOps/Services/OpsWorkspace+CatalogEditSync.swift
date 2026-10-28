import Foundation
import SwiftData
import PinkHouseOpsCore
import SharedCatalog

extension OpsWorkspace {
    /// 只由显式编辑保存调用；向导击键、图片暂存不自动发布。
    @discardableResult
    func saveCatalogEditorChanges(seriesID: String? = nil,
                                  fields: Set<OpsSeriesConfigUpdate.Field> = []) -> Bool {
        guard let draft else { return false }
        let previous = (draft.catalogSyncRequestID, draft.catalogSyncRevision,
                        draft.catalogSyncEnvironment, draft.catalogSyncError,
                        draft.catalogSyncSeriesUpdatesJSON, draft.catalogSyncSeriesReceiptsJSON,
                        draft.catalogSyncFullCatalogAfterSeries, draft.catalogSyncEditorUpdatesJSON, draft.catalogSyncProgressJSON, draft.catalogEditorDualSyncVersion, draft.catalogOrderDualSyncVersion)
        if let seriesID {
            guard let series = catalog.series.first(where: { $0.id == seriesID }), !fields.isEmpty else {
                lastError = "找不到需要同步的系列配置。"; return false
            }
            do {
                var mediaSeries = series
                if !fields.contains(.cover) { mediaSeries.cover = nil }
                if !fields.contains(.priceChart) { mediaSeries.priceChart = nil }
                let references = Set(ShopCatalogMediaReferences.all(in: ShopCatalog(series: [mediaSeries])).map(\.reference))
                let update = OpsSeriesConfigUpdate(series: series,
                    shop: catalog.shops.first { $0.id == series.shopID }, fields: fields,
                    assets: catalog.assets.filter { references.contains($0.id) },
                    productOrders: fields.contains(.productOrder) ? Dictionary(uniqueKeysWithValues: catalog.products
                        .filter { $0.seriesID == seriesID && $0.archivedAt == nil }
                        .compactMap { product in product.displayOrder.map { (product.id, $0) } }) : nil,
                    publishedOrderCatalog: fields.contains(.productOrder) ? publishedCatalogForProductOrder(seriesID: seriesID) : nil)
                let pending = try draft.catalogSyncSeriesUpdatesJSON.map {
                    try JSONDecoder().decode([OpsSeriesConfigUpdate].self, from: $0)
                } ?? []
                draft.catalogSyncSeriesUpdatesJSON = try JSONEncoder().encode(
                    OpsSeriesConfigUpdate.coalescing(pending, with: update))
                draft.catalogSyncSeriesReceiptsJSON = nil
                if fields.contains(.productOrder) { draft.catalogOrderDualSyncVersion = 2 }
            } catch { lastError = "保存系列同步任务失败：\(error.localizedDescription)"; return false }
        } else {
            do {
                let before = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: draft.catalogJSON)
                let update = OpsCatalogEditorUpdate(before: before, after: catalog)
                var pending = try draft.catalogSyncEditorUpdatesJSON.map {
                    try ShopCatalogJSONCoding.decoder().decode([OpsCatalogEditorUpdate].self, from: $0)
                } ?? []
                if !update.isEmpty { pending.append(update) }
                draft.catalogSyncEditorUpdatesJSON = try ShopCatalogJSONCoding.encoder().encode(pending)
            } catch { lastError = "保存商品同步任务失败：\(error.localizedDescription)"; return false }
        }
        draft.catalogEditorDualSyncVersion = 1
        draft.catalogSyncFullCatalogAfterSeries = nil
        draft.catalogSyncSeriesReceiptsJSON = nil
        draft.catalogSyncRequestID = UUID().uuidString
        draft.catalogSyncRevision = currentRevision
        draft.catalogSyncEnvironment = OpsCloudSyncModel.shared.targetEnvironment.rawValue
        draft.catalogSyncError = nil
        let progress = OpsCatalogEditProgress(requestID: draft.catalogSyncRequestID!, revision: currentRevision)
        draft.catalogSyncProgressJSON = try? JSONEncoder().encode(progress)
        guard saveDraft() else {
            (draft.catalogSyncRequestID, draft.catalogSyncRevision,
             draft.catalogSyncEnvironment, draft.catalogSyncError,
             draft.catalogSyncSeriesUpdatesJSON, draft.catalogSyncSeriesReceiptsJSON,
             draft.catalogSyncFullCatalogAfterSeries, draft.catalogSyncEditorUpdatesJSON, draft.catalogSyncProgressJSON, draft.catalogEditorDualSyncVersion, draft.catalogOrderDualSyncVersion) = previous
            return false
        }
        catalogEditSyncProgress = progress
        catalogEditSyncMessage = "已保存到本机，等待分别同步开发环境和线上环境…"
        catalogEditSyncQueue.resume()
        return true
    }

    func resumeCatalogEditorSync() {
        let cloud = OpsCloudSyncModel.shared
        if catalogEditSyncProgress == nil, let data = draft?.catalogSyncProgressJSON {
            catalogEditSyncProgress = try? JSONDecoder().decode(OpsCatalogEditProgress.self, from: data)
        }
        guard !cloud.isRunning, !cloud.isSyncing else { return }
        enqueueLegacyNameRepairIfNeeded()
        enqueueLegacyProductOrderRepairIfNeeded()
        // 旧版本的系列保存可能被整目录预检拦下。明确未发送过请求时，自动接续已保存团次。
        if let draft, draft.catalogSyncRequestID != nil, draft.catalogSyncSeriesUpdatesJSON == nil, draft.catalogSyncEditorUpdatesJSON == nil,
           draft.catalogSyncError?.contains("尚未发送发布请求") == true, !hasUnsavedChanges {
            let baseline = baselineCatalog
            let changed = catalog.series.filter { series in
                !(series.reservationBatches ?? []).isEmpty &&
                    baseline?.series.first(where: { $0.id == series.id })?.reservationBatches != series.reservationBatches
            }
            if !changed.isEmpty {
                for series in changed {
                    guard saveCatalogEditorChanges(seriesID: series.id, fields: [.schedule]) else { return }
                }
                return
            }
        }
        if draft?.catalogSyncSeriesUpdatesJSON == nil, draft?.catalogSyncEditorUpdatesJSON == nil, let environment = draft?.catalogSyncEnvironment,
           environment != cloud.targetEnvironment.rawValue {
            let name = ShopCatalogPublishTargetEnvironment(rawValue: environment)?.displayName ?? environment
            catalogEditSyncMessage = "本地已保存，等待切换回 \(name) 后同步。"
        } else if let error = draft?.catalogSyncError {
            catalogEditSyncMessage = "本地已保存，云端同步未完成：\(error)"
        } else if let draft, draft.catalogSyncSeriesUpdatesJSON == nil, draft.catalogSyncEditorUpdatesJSON == nil, draft.catalogSyncRequestID != nil,
                  draft.catalogSyncRequestID == draft.catalogSyncAttemptedID {
            catalogEditSyncMessage = "本地已保存，上次同步未确认完成；请先查看云端更新结果。"
        }
        catalogEditSyncQueue.resume()
    }

    var canRetrySavedSeriesSync: Bool {
        guard let draft, draft.catalogSyncRequestID != nil,
              (draft.catalogSyncSeriesUpdatesJSON != nil || draft.catalogSyncEditorUpdatesJSON != nil) else { return false }
        return draft.catalogSyncError != nil
    }

    /// 保留请求 ID、已确认环境和冻结发布文件；不把结果未知的上传换号重发。
    @discardableResult
    func retrySavedSeriesSync() -> Bool {
        let cloud = OpsCloudSyncModel.shared
        guard canRetrySavedSeriesSync, !cloud.isRunning, !cloud.isSyncing, let draft else { return false }
        let previousError = draft.catalogSyncError
        draft.catalogSyncError = nil
        do { try saveCatalogContext(context) } catch {
            draft.catalogSyncError = previousError
            catalogEditSyncMessage = "重试任务保存失败：\(error.localizedDescription)"
            return false
        }
        catalogEditSyncMessage = "正在重试已保存的系列更新；已发送的请求先查询结果，再继续未完成的环境…"
        catalogEditSyncQueue.retryFailedRequest()
        return true
    }

    func makeCatalogEditSyncQueue(
        publishSeries: ((OpsCatalogEditSyncQueue.Request, [OpsSeriesConfigUpdate]) async -> OpsPublishInvocationResult)? = nil
    ) -> OpsCatalogEditSyncQueue {
        let cloud = OpsCloudSyncModel.shared
        return OpsCatalogEditSyncQueue(pending: { [weak self] in
            guard let draft = self?.draft, let id = draft.catalogSyncRequestID,
                  (id != draft.catalogSyncAttemptedID ||
                    ((draft.catalogSyncSeriesUpdatesJSON != nil || draft.catalogSyncEditorUpdatesJSON != nil) && draft.catalogSyncError == nil)),
                  let revision = draft.catalogSyncRevision,
                  let environment = draft.catalogSyncEnvironment,
                  (draft.catalogSyncSeriesUpdatesJSON != nil || draft.catalogSyncEditorUpdatesJSON != nil || environment == cloud.targetEnvironment.rawValue) else { return nil }
            return .init(id: id, draftID: draft.id, revision: revision, environment: environment)
        }, isBusy: { cloud.isRunning || cloud.isSyncing }, publish: { [weak self] request in
            guard let self, let draft = self.draft, draft.id == request.draftID else {
                return .failed("草稿已切换")
            }
            // 在网络请求前落盘尝试标记：退出/超时后不会盲目自动重发不确定的发布。
            let previous = draft.catalogSyncAttemptedID
            draft.catalogSyncAttemptedID = request.id
            do { try self.context.save() } catch {
                draft.catalogSyncAttemptedID = previous
                return .failed("同步状态保存失败：\(error.localizedDescription)")
            }
            var result: OpsPublishInvocationResult
            if draft.catalogSyncSeriesUpdatesJSON != nil || draft.catalogSyncEditorUpdatesJSON != nil {
                do {
                    let updates = try draft.catalogSyncSeriesUpdatesJSON.map {
                        try JSONDecoder().decode([OpsSeriesConfigUpdate].self, from: $0)
                    } ?? []
                    let edits = try draft.catalogSyncEditorUpdatesJSON.map {
                        try ShopCatalogJSONCoding.decoder().decode([OpsCatalogEditorUpdate].self, from: $0)
                    } ?? []
                    if let publishSeries { result = await publishSeries(request, updates) }
                    else { result = await self.synchronizeSavedSeries(requestID: request.id, updates: updates, cloud: cloud, editorUpdates: edits) }
                } catch { result = .failed("系列同步任务无法读取：\(error.localizedDescription)") }
            } else { result = await cloud.publishNow(workspace: self) }
            switch result {
            case .confirmed(let seq): return .confirmed(seq)
            case .failed(let reason): return .failed(reason)
            }
        }, finished: { [weak self] request, result in
            guard let self, let draft = self.draft, draft.id == request.draftID,
                  draft.catalogSyncEnvironment == request.environment,
                  (draft.catalogSyncSeriesUpdatesJSON != nil || draft.catalogSyncEditorUpdatesJSON != nil || cloud.targetEnvironment.rawValue == request.environment) else { return }
            if draft.catalogSyncSeriesUpdatesJSON != nil || draft.catalogSyncEditorUpdatesJSON != nil {
                self.finishSavedCatalogSync(request: request, result: result)
                return
            }
            switch result {
            case .confirmed(let seq):
                // 发布时冻结的版本确实覆盖了待同步保存，才清除意图。
                if (draft.catalogSyncRevision ?? Int.max) <= (draft.lastPublishedRevision ?? -1) {
                    draft.catalogSyncRequestID = nil
                    draft.catalogSyncRevision = nil
                    draft.catalogSyncEnvironment = nil
                    draft.catalogSyncError = nil
                    self.catalogEditSyncMessage = "已同步到 App（\(cloud.targetEnvironment.displayName)，发布号 \(seq)）"
                }
            case .failed(let reason):
                if draft.catalogSyncRequestID == request.id { draft.catalogSyncError = reason }
                self.catalogEditSyncMessage = "本地已保存，云端同步未完成：\(reason)"
            }
            do { try self.context.save() } catch {
                self.catalogEditSyncMessage = "云端结果已收到，同步状态保存失败：\(error.localizedDescription)"
            }
        })
    }

    func validShopLogo(_ reference: String?) -> Bool {
        guard let reference else { return true }
        guard catalog.shops.contains(where: { $0.logo == reference })
                || asset(for: reference) != nil || reference.hasPrefix("local:")
                || reference.hasPrefix("thmedia:") || reference.hasPrefix("https://") else {
            lastError = "店家 Logo 图片不存在，请重新上传。"
            return false
        }
        return true
    }

    @discardableResult
    func updateShopLogo(id: String, reference: String?) -> Bool {
        guard let shop = catalog.shops.first(where: { $0.id == id }) else {
            lastError = "找不到店家。"; return false
        }
        return updateShopProfile(id: id, name: shop.name, aliases: shop.aliases, logo: reference)
    }
}
