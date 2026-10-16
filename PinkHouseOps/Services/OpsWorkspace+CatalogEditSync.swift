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
                        draft.catalogSyncFullCatalogAfterSeries)
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
                    assets: catalog.assets.filter { references.contains($0.id) })
                let pending = try draft.catalogSyncSeriesUpdatesJSON.map {
                    try JSONDecoder().decode([OpsSeriesConfigUpdate].self, from: $0)
                } ?? []
                draft.catalogSyncSeriesUpdatesJSON = try JSONEncoder().encode(
                    OpsSeriesConfigUpdate.coalescing(pending, with: update))
                draft.catalogSyncSeriesReceiptsJSON = nil
            } catch { lastError = "保存系列同步任务失败：\(error.localizedDescription)"; return false }
        } else if draft.catalogSyncSeriesUpdatesJSON != nil {
            // 系列同步等待期间又显式保存商品/店家编辑，仍保留其原有整目录同步意图。
            draft.catalogSyncFullCatalogAfterSeries = true
        }
        draft.catalogSyncRequestID = UUID().uuidString
        draft.catalogSyncRevision = currentRevision
        draft.catalogSyncEnvironment = OpsCloudSyncModel.shared.targetEnvironment.rawValue
        draft.catalogSyncError = nil
        guard saveDraft() else {
            (draft.catalogSyncRequestID, draft.catalogSyncRevision,
             draft.catalogSyncEnvironment, draft.catalogSyncError,
             draft.catalogSyncSeriesUpdatesJSON, draft.catalogSyncSeriesReceiptsJSON,
             draft.catalogSyncFullCatalogAfterSeries) = previous
            return false
        }
        catalogEditSyncMessage = draft.catalogSyncSeriesUpdatesJSON != nil
            ? "已保存到本机，正在自动同步到开发环境和用户环境…"
            : "已保存到本机，正在同步到 App（\(OpsCloudSyncModel.shared.targetEnvironment.displayName)）…"
        catalogEditSyncQueue.resume()
        return true
    }

    func resumeCatalogEditorSync() {
        let cloud = OpsCloudSyncModel.shared
        guard !cloud.isRunning, !cloud.isSyncing else { return }
        // 旧版本的系列保存可能被整目录预检拦下。明确未发送过请求时，自动接续已保存团次。
        if let draft, draft.catalogSyncRequestID != nil, draft.catalogSyncSeriesUpdatesJSON == nil,
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
        if draft?.catalogSyncSeriesUpdatesJSON == nil, let environment = draft?.catalogSyncEnvironment,
           environment != cloud.targetEnvironment.rawValue {
            let name = ShopCatalogPublishTargetEnvironment(rawValue: environment)?.displayName ?? environment
            catalogEditSyncMessage = "本地已保存，等待切换回 \(name) 后同步。"
        } else if let error = draft?.catalogSyncError {
            catalogEditSyncMessage = "本地已保存，云端同步未完成：\(error)"
        } else if let draft, draft.catalogSyncSeriesUpdatesJSON == nil, draft.catalogSyncRequestID != nil,
                  draft.catalogSyncRequestID == draft.catalogSyncAttemptedID {
            catalogEditSyncMessage = "本地已保存，上次同步未确认完成；请先查看云端更新结果。"
        }
        catalogEditSyncQueue.resume()
    }

    var canRetrySavedSeriesSync: Bool {
        guard let draft, draft.catalogSyncRequestID != nil,
              draft.catalogSyncSeriesUpdatesJSON != nil else { return false }
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
                    (draft.catalogSyncSeriesUpdatesJSON != nil && draft.catalogSyncError == nil)),
                  let revision = draft.catalogSyncRevision,
                  let environment = draft.catalogSyncEnvironment,
                  (draft.catalogSyncSeriesUpdatesJSON != nil || environment == cloud.targetEnvironment.rawValue) else { return nil }
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
            if let data = draft.catalogSyncSeriesUpdatesJSON {
                do {
                    let updates = try JSONDecoder().decode([OpsSeriesConfigUpdate].self, from: data)
                    if let publishSeries { result = await publishSeries(request, updates) }
                    else { result = await self.synchronizeSavedSeries(requestID: request.id, updates: updates, cloud: cloud) }
                } catch { result = .failed("系列同步任务无法读取：\(error.localizedDescription)") }
            } else { result = await cloud.publishNow(workspace: self) }
            if case .confirmed = result, draft.catalogSyncFullCatalogAfterSeries == true,
               draft.catalogSyncRequestID == request.id {
                result = await cloud.publishNow(workspace: self)
            }
            switch result {
            case .confirmed(let seq): return .confirmed(seq)
            case .failed(let reason): return .failed(reason)
            }
        }, finished: { [weak self] request, result in
            guard let self, let draft = self.draft, draft.id == request.draftID,
                  draft.catalogSyncEnvironment == request.environment,
                  (draft.catalogSyncSeriesUpdatesJSON != nil || cloud.targetEnvironment.rawValue == request.environment) else { return }
            if draft.catalogSyncSeriesUpdatesJSON != nil {
                guard draft.catalogSyncRequestID == request.id else { return }
                switch result {
                case .confirmed:
                    let receipts = draft.catalogSyncSeriesReceiptsJSON.flatMap {
                        try? JSONDecoder().decode([String: Int].self, from: $0)
                    } ?? [:]
                    self.catalogEditSyncMessage = "已自动同步到开发环境和用户环境，均已回读确认"
                        + (receipts.isEmpty ? "。" : "（Development \(receipts["development"] ?? 0)，Production \(receipts["production"] ?? 0)）。")
                    draft.catalogSyncRequestID = nil
                    draft.catalogSyncRevision = nil
                    draft.catalogSyncEnvironment = nil
                    draft.catalogSyncError = nil
                    draft.catalogSyncSeriesUpdatesJSON = nil
                    draft.catalogSyncSeriesReceiptsJSON = nil
                    draft.catalogSyncFullCatalogAfterSeries = nil
                case .failed(let reason):
                    draft.catalogSyncError = reason
                    self.catalogEditSyncMessage = "本地已保存，自动同步未完成：\(reason)"
                }
                do { try self.saveCatalogContext(self.context) } catch {
                    self.catalogEditSyncMessage = "云端结果已收到，同步状态保存失败：\(error.localizedDescription)"
                }
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
