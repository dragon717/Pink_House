import Foundation
import SharedCatalog
import PinkHouseOpsCore

extension OpsWorkspace {
    /// 回执与比较祖先同次落盘；网络中途的新保存不会被旧任务清掉。
    func recordConfirmedSeriesSync(requestID: String, updates: [OpsSeriesConfigUpdate],
                                   previousRemote: ShopCatalog, head: ShopCatalogBaseline) throws {
        guard let draft, let environment = head.environment, !draft.isCorrupted else {
            throw NSError(domain: "OpsBaseline", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "草稿已切换或不可写，尚未记录同步结果。"])
        }
        let oldStates = draft.environmentBaselinesJSON
        let oldReceipts = draft.catalogSyncSeriesReceiptsJSON
        let ancestor = try draft.mergeBaseline(environment: environment)
            ?? OpsCatalogMergeBaseline.commonAncestor(legacy: baselineCatalog,
                previouslyConfirmed: previousRemote, head: head)
        let confirmed = try ancestor.acknowledging(updates, head: head)
        draft.setMergeBaseline(confirmed, environment: environment)
        if draft.catalogSyncRequestID == requestID {
            var receipts = try oldReceipts.map { try JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
            receipts[environment] = head.releaseSeq
            draft.catalogSyncSeriesReceiptsJSON = try JSONEncoder().encode(receipts)
        }
        do { try saveCatalogContext(context) } catch {
            draft.environmentBaselinesJSON = oldStates
            draft.catalogSyncSeriesReceiptsJSON = oldReceipts
            throw error
        }
    }

    func mergeConflictReason(path: String, environment: String) -> String {
        let parts = path.split(separator: ".", maxSplits: 2).map(String.init)
        let state = draft?.mergeBaseline(environment: environment)
        let keys = parts.count == 3 ? state?.knownFields?[parts[0] + "." + parts[1]] : nil
        if state == nil || (state?.knownFields != nil &&
            !(keys?.contains("*") == true || (parts.count == 3 && keys?.contains(parts[2].components(separatedBy: ".")[0]) == true))) {
            return "该字段没有\(environment)的共同基线，无法判断修改来源；暂保留本地值，请核对后再发布"
        }
        return "双方都修改了此字段，暂保留本地值；请核对双方修改后再发布"
    }

    /// 仅迁移已确认发布的旧系列任务，不采用失败同步里刚下载的快照作为祖先。
    /// 不触碰目录、编辑版本、发布草稿箱或待同步意图。
    func restoreConfirmedSeriesBaselines() {
        guard let draft, !draft.isCorrupted else { return }
        let root = rootDirectory.appendingPathComponent("series-config-sync")
        let requests = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var candidates: [(URL, ShopCatalogPublishRequest)] = []
        for request in requests {
            for environment in ShopCatalogPublishTargetEnvironment.allCases {
                let directory = request.appendingPathComponent(environment.rawValue)
                guard let data = try? Data(contentsOf: directory.appendingPathComponent("publish-request.json")),
                      let frozen = try? ShopCatalogPublishRequest.decoded(from: data),
                      frozen.draftID == draft.id, frozen.targetEnvironment == environment else { continue }
                candidates.append((directory, frozen))
            }
        }
        let oldStates = draft.environmentBaselinesJSON
        var changed = false
        for (directory, request) in candidates.sorted(by: { $0.1.releaseSeq < $1.1.releaseSeq }) {
            let environment = request.targetEnvironment.rawValue
            let existing = draft.mergeBaseline(environment: environment)
            guard request.releaseSeq > (existing?.head.releaseSeq ?? -1),
                  let recovered = try? OpsCatalogMergeBaseline.recoverConfirmedSeriesJob(
                    at: directory, draftID: draft.id, legacy: baselineCatalog, existing: existing) else { continue }
            draft.setMergeBaseline(recovered, environment: environment)
            changed = true
        }
        guard changed else { return }
        do { try saveCatalogContext(context) } catch {
            draft.environmentBaselinesJSON = oldStates
            lastError = "历史发布基线恢复未保存，内容仍保留：\(error.localizedDescription)"
        }
    }
}
