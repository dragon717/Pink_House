import Foundation
import PinkHouseOpsCore
import SharedCatalog

extension OpsCloudSyncModel {
    /// 内部在上传前合成安全工作副本；第三步确认落盘，上传失败也执行。
    func synchronize(workspace: OpsWorkspace) async -> OpsPublishInvocationResult {
        guard !isSyncing, !isRunning else { return .failed("另一个同步任务正在运行。") }
        guard let draftID = workspace.draft?.id, !workspace.isCorrupted else {
            return .failed("没有可同步的草稿，或草稿已损坏。")
        }
        let ownsLog = beginOperationLog("发布到" + targetEnvironment.displayName)
        isSyncing = true
        defer { isSyncing = false }

        let environment = targetEnvironment.rawValue
        let generation = syncEnvironmentGeneration
        func stillCurrent() -> Bool {
            workspace.draft?.id == draftID && targetEnvironment.rawValue == environment
                && syncEnvironmentGeneration == generation
        }
        var pulled: OpsPulledCatalog?
        var remote: ShopCatalog?
        var uploadResult: OpsPublishInvocationResult = .failed("尚未上传")
        var mergeFailed: String?
        var mediaIssues: [OpsSyncIssue] = []
        let final = await OpsSyncWorkflow.run(
            report: OpsSyncReport(draftID: draftID, environment: environment),
            download: {
                guard let content = await self.pullCatalog(), stillCurrent() else {
                    return .init(.failed, self.lastError ?? "目录下载未完成或草稿/环境已切换",
                                 canContinue: false, logPaths: self.syncLogPaths)
                }
                pulled = content
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: content.path))
                    remote = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: data)
                } catch {
                    return .init(.failed, "目录下载后无法解析：\(error.localizedDescription)", canContinue: false)
                }
                var logs = self.syncLogPaths
                // 接回旧版本超时前已落盘的图片。absorb 会逐文件核对 SHA-256，
                // 只有与文件名内容摘要相符的字节能进入 staging。
                for directory in OpsDownloadedMediaRecovery.directories(in: self.jobsDirectory, environment: environment) {
                    workspace.absorbDownloadedMedia(from: directory)
                }
                let recovery = await self.recoverSyncMedia(workspace: workspace, remote: remote!,
                    environment: environment, stillCurrent: stillCurrent)
                logs += recovery.logPaths
                mediaIssues = recovery.issues
                return .init(mediaIssues.isEmpty ? .completed : .partial,
                             "目录已下载；" + recovery.detail, canContinue: stillCurrent(),
                             issues: mediaIssues, logPaths: logs, progress: recovery.progress)
            }, upload: {
                guard stillCurrent(), let pulled, remote != nil else {
                    return .init(.blocked, "草稿或环境已切换，未尝试上传")
                }
                let url = URL(fileURLWithPath: pulled.path)
                guard let preview = workspace.mergePreview(from: url, environment: environment) else {
                    mergeFailed = workspace.lastError ?? "下载内容无法合并"
                    return .init(.blocked, "合并预处理受阻，尚未尝试上传：\(mergeFailed!)")
                }
                let baseline = ShopCatalogBaseline(releaseSeq: pulled.releaseSeq,
                    rootIndexHash: pulled.rootIndexHash, environment: environment, observedAt: pulled.pulledAt)
                // 暂留争议字段的本地值且不推进共同基线，保证下次仍能看到未确认冲突。
                guard workspace.mergeRemoteIntoLocal(from: url, baseline: baseline,
                    preferLocalOnConflict: true, advanceBaseline: preview.conflicts.isEmpty) != nil else {
                    mergeFailed = workspace.lastError ?? "合并预处理保存失败"
                    return .init(.blocked, "合并预处理受阻，尚未尝试上传：\(mergeFailed!)")
                }
                let issues = mediaIssues + self.uploadIssues(workspace: workspace) + preview.conflicts.map {
                    OpsSyncIssue(id: "conflict-\($0)", step: .upload, owner: $0,
                                 message: "双方都修改了此字段，暂保留本地值；请核对双方修改后再发布")
                }
                if !issues.isEmpty {
                    return .init(.blocked, "上传前待修复 \(issues.count) 项，尚未发送发布请求；下载内容已保留", issues: issues)
                }
                uploadResult = await self.publish(workspace: workspace)
                switch uploadResult {
                case .confirmed(let seq):
                    return .init(.completed, "上传已回读确认，releaseSeq \(seq)", logPaths: self.syncLogPaths, releaseSeq: seq)
                case .failed(let reason):
                    return .init(.failed, reason, issues: [.init(id: "publish", step: .upload,
                        owner: "云端发布", message: reason)], logPaths: self.syncLogPaths)
                }
            }, merge: {
                guard stillCurrent() else { return .init(.failed, "草稿或环境已切换，未改动新工作区") }
                if let mergeFailed { return .init(.failed, mergeFailed) }
                guard workspace.saveDraft() else { return .init(.failed, workspace.lastError ?? "合并结果保存失败") }
                let detail: String
                if case .confirmed = uploadResult {
                    detail = "下载内容与本地编辑已合并保存，发布回执已记录"
                } else {
                    detail = "下载内容与本地编辑已合并保存；上传受阻的内容保留，修复后可再次上传"
                }
                return .init(.completed, detail)
            }, changed: {
                self.syncReport = $0
                self.persistSyncReport($0, workspace: workspace)
            })
        syncReport = final
        persistSyncReport(final, workspace: workspace)
        appendOperationLog(final.steps.map { "\($0.step.title)：\($0.detail)" }.joined(separator: "\n")
            + "\n" + final.issues.map { "\($0.owner)：\($0.message)" }.joined(separator: "\n"))
        if ownsLog { finishOperationLog(final.summary) }
        if final.isComplete, case .confirmed = uploadResult { return uploadResult }
        // 系列草稿箱不能因为下载/合并成功就删除待发布任务。
        return .failed(final.summary)
    }

    private var syncLogPaths: [String] { lastRunLogURL.map { [$0.path] } ?? [] }

    private func uploadIssues(workspace: OpsWorkspace) -> [OpsSyncIssue] {
        let references = ShopCatalogMediaReferences.all(in: workspace.catalog)
        let missing = workspace.missingStagedImages().map { file in
            let owners = references.filter { $0.reference == "local:" + file.fileName }
            let products = Set(owners.map(\.productID).filter { !$0.isEmpty })
            let names = workspace.catalog.products.filter { products.contains($0.id) }.map(\.name)
            return OpsSyncIssue(id: "local-\(file.fileName)", step: .upload,
                                owner: (names + file.owners).joined(separator: " / "),
                                message: "缺少本机文件 \(file.fileName)，请在设置 → 导入与数据修复补齐图片，再发布",
                                productIDs: products.sorted())
        }
        let structure = workspace.review(targetEnvironmentName: targetEnvironment.displayName).catalogIssues
            .enumerated().map { index, message in
                OpsSyncIssue(id: "structure-\(index)", step: .upload, owner: "目录数据", message: message)
            }
        return missing + structure
    }

    func receiveSyncProgress(_ event: ShopCatalogPublishEvent, mode: OpsBridgeMode) {
        guard isSyncing, !isPromotingEnvironment,
              let index = syncReport?.steps.firstIndex(where: { $0.state == .running }) else { return }
        let step = syncReport?.steps[index].step
        guard (step == .download && (mode == .pullCatalog || mode == .fetchMedia))
                || (step == .upload && mode == .publish) else { return }
        if let completed = event.completed, let total = event.total, total > 0, mode == .fetchMedia {
            syncReport?.steps[index].progress = Double(completed) / Double(total)
            syncReport?.steps[index].detail = "目录已下载；远端图片 \(completed)/\(total) 项已处理"
        } else if event.type == "stage", let stage = event.stage {
            syncReport?.steps[index].detail = event.message ?? event.displayLine ?? stage.displayName
            if mode == .publish, let ordinal = stage.stepOrdinal {
                syncReport?.steps[index].progress = Double(ordinal - 1) / 7
            }
        } else if mode == .publish, event.type == "progress", event.stage == .uploadMedia,
                  let completed = event.completed, let total = event.total, total > 0 {
            syncReport?.steps[index].detail = "上传图片 \(completed)/\(total) 张"
            syncReport?.steps[index].progress = (2 + Double(completed) / Double(total)) / 7
        }
    }

    private func reportURL(_ workspace: OpsWorkspace) -> URL {
        workspace.rootDirectory.appendingPathComponent("sync-status")
            .appendingPathComponent("\(workspace.draft?.id ?? "unknown").json")
    }

    private func persistSyncReport(_ report: OpsSyncReport, workspace: OpsWorkspace) {
        guard report.draftID == workspace.draft?.id else { return }
        do {
            let url = reportURL(workspace)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(report).write(to: url, options: .atomic)
        } catch { workspace.reportFailure("同步结果已生成，但状态记录保存失败：\(error.localizedDescription)") }
    }

    func restoreSyncReport(workspace: OpsWorkspace) {
        guard !isSyncing, let data = try? Data(contentsOf: reportURL(workspace)),
              var report = try? JSONDecoder().decode(OpsSyncReport.self, from: data),
              report.environment == targetEnvironment.rawValue else { return }
        report.recoverInterruptedRun()
        syncReport = report
        persistSyncReport(report, workspace: workspace)
    }
}
