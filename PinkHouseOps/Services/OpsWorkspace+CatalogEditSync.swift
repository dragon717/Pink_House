import Foundation
import SwiftData
import PinkHouseOpsCore

extension OpsWorkspace {
    /// 只由显式编辑保存调用；向导击键、图片暂存不自动发布。
    @discardableResult
    func saveCatalogEditorChanges() -> Bool {
        guard let draft else { return false }
        let previous = (draft.catalogSyncRequestID, draft.catalogSyncRevision,
                        draft.catalogSyncEnvironment, draft.catalogSyncError)
        draft.catalogSyncRequestID = UUID().uuidString
        draft.catalogSyncRevision = currentRevision
        draft.catalogSyncEnvironment = OpsCloudSyncModel.shared.targetEnvironment.rawValue
        draft.catalogSyncError = nil
        guard saveDraft() else {
            (draft.catalogSyncRequestID, draft.catalogSyncRevision,
             draft.catalogSyncEnvironment, draft.catalogSyncError) = previous
            return false
        }
        catalogEditSyncMessage = "已保存到本机，正在同步到 App（\(OpsCloudSyncModel.shared.targetEnvironment.displayName)）…"
        catalogEditSyncQueue.resume()
        return true
    }

    func resumeCatalogEditorSync() {
        let cloud = OpsCloudSyncModel.shared
        guard !cloud.isRunning, !cloud.isSyncing else { return }
        if let environment = draft?.catalogSyncEnvironment,
           environment != cloud.targetEnvironment.rawValue {
            let name = ShopCatalogPublishTargetEnvironment(rawValue: environment)?.displayName ?? environment
            catalogEditSyncMessage = "本地已保存，等待切换回 \(name) 后同步。"
        } else if let error = draft?.catalogSyncError {
            catalogEditSyncMessage = "本地已保存，云端同步未完成：\(error)"
        } else if let draft, draft.catalogSyncRequestID != nil,
                  draft.catalogSyncRequestID == draft.catalogSyncAttemptedID {
            catalogEditSyncMessage = "本地已保存，上次同步未确认完成；请先查看云端更新结果。"
        }
        catalogEditSyncQueue.resume()
    }

    func makeCatalogEditSyncQueue() -> OpsCatalogEditSyncQueue {
        let cloud = OpsCloudSyncModel.shared
        return OpsCatalogEditSyncQueue(pending: { [weak self] in
            guard let draft = self?.draft, let id = draft.catalogSyncRequestID,
                  id != draft.catalogSyncAttemptedID,
                  let revision = draft.catalogSyncRevision,
                  let environment = draft.catalogSyncEnvironment,
                  environment == cloud.targetEnvironment.rawValue else { return nil }
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
            switch await cloud.publishNow(workspace: self) {
            case .confirmed(let seq): return .confirmed(seq)
            case .failed(let reason): return .failed(reason)
            }
        }, finished: { [weak self] request, result in
            guard let self, let draft = self.draft, draft.id == request.draftID,
                  draft.catalogSyncEnvironment == request.environment,
                  cloud.targetEnvironment.rawValue == request.environment else { return }
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
