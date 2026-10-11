import Foundation
import PinkHouseOpsCore
import SharedCatalog

extension OpsCloudSyncModel {
    /// 补齐工作副本引用的字节后才导出，避免只下载线上目录的图而漏掉本地引用。
    func recoverSyncMedia(workspace: OpsWorkspace, remote: ShopCatalog, environment: String,
                          updateReport: Bool = true, includeLocalReferences: Bool = true, stillCurrent: () -> Bool) async -> OpsSyncStepResult {
        var logs: [String] = []
        var failures: [String] = []
        var added = 0
        let result = await OpsSyncMediaRecovery.download(local: includeLocalReferences ? workspace.catalog : remote, remote: remote,
            environment: environment, available: { workspace.stagedMediaKeys }, fetch: { hashes, source in
                guard stillCurrent(), let source = ShopCatalogPublishTargetEnvironment(rawValue: source) else { return nil }
                if updateReport {
                    self.syncReport?.update(.download, state: .running,
                        detail: "正在从\(source.displayName)补齐 \(hashes.count) 张图片")
                }
                let fetched = await self.fetchMedia(hashes: hashes, environment: source)
                if let path = self.lastRunLogURL?.path { logs.append(path) }
                if let error = self.lastError { failures.append(error) }
                return stillCurrent() ? fetched : nil
            }, receive: { fetched in
                guard stillCurrent() else { return }
                added += workspace.absorbDownloadedMedia(from: fetched.directoryURL)
                if let error = workspace.lastError { failures.append(error) }
            })
        let issues = result.unresolved.map { hash in
            OpsSyncIssue(id: "remote-\(hash)", step: .download, owner: "图片 \(hash.prefix(12))…",
                message: "目录引用的图片尚未补齐，请重试拉取或补齐图片。"
                    + (failures.last.map { " \($0)" } ?? "目标环境与可用来源没有返回可验证的图片字节。"))
        }
        let summary = result.downloads.map(\.summaryText).joined(separator: "；")
        return .init(issues.isEmpty ? .completed : .partial,
            result.requested.isEmpty ? "本地与线上目录的图片本机已齐" : "本次收进 \(added) 张图片；\(summary)",
            canContinue: stillCurrent(), issues: issues, logPaths: logs,
            progress: result.requested.isEmpty ? 1 : Double(result.requested.count - result.unresolved.count) / Double(result.requested.count))
    }
}
