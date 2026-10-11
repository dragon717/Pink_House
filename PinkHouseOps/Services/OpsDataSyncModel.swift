import Combine
import Foundation
import PinkHouseOpsCore
import SharedCatalog

@MainActor
final class OpsDataSyncModel: ObservableObject {
    static let shared = OpsDataSyncModel()

    enum Operation: String, CaseIterable, Identifiable {
        case development, production, migration
        var id: String { rawValue }
        var title: String {
            switch self {
            case .development: "拉取开发环境"
            case .production: "拉取线上环境"
            case .migration: "开发环境 → 线上环境"
            }
        }
    }

    struct Result: Codable {
        let title: String
        let message: String
        let failed: Bool
        let logURL: URL?
    }

    @Published private(set) var isRunning = false
    @Published private(set) var currentTitle = ""
    @Published private(set) var result: Result?
    private let cloud = OpsCloudSyncModel.shared
    private let promotion = OpsEnvironmentPromotionModel.shared
    private var resultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PinkHouseOps/data-sync-result.json")
    }

    init() {
        if let data = try? Data(contentsOf: resultURL) {
            result = try? JSONDecoder().decode(Result.self, from: data)
        }
    }

    var isBusy: Bool { isRunning || cloud.isRunning || cloud.isSyncing }
    var migrationTitle: String { promotion.needsQuery ? "确认上次迁移结果" : Operation.migration.title }

    func run(_ operation: Operation, workspace: OpsWorkspace?) async {
        guard !isBusy else { return }
        isRunning = true
        currentTitle = operation == .migration ? migrationTitle : operation.title
        result = nil
        cloud.beginOperationLog(currentTitle)
        var message: String
        var failed = false
        do {
            if operation == .migration {
                if promotion.needsQuery { await promotion.query() }
                else { await promotion.synchronize() }
                message = promotion.message ?? "迁移未完成，请查看日志。"
                failed = promotion.failed
            } else {
                guard let workspace, !workspace.isCorrupted, workspace.draft != nil else {
                    throw error("请先打开可用的本地草稿。")
                }
                message = try await pull(operation == .development ? .development : .production,
                                         workspace: workspace)
            }
        } catch {
            message = error.localizedDescription
            failed = true
        }
        cloud.finishOperationLog(message)
        if operation != .migration {
            if failed { workspace?.reportFailure(message) }
            else { workspace?.reportSuccess(message) }
        }
        result = Result(title: currentTitle, message: message, failed: failed, logURL: cloud.lastRunLogURL)
        if let data = try? JSONEncoder().encode(result) { try? data.write(to: resultURL, options: .atomic) }
        isRunning = false
    }

    private func pull(_ environment: ShopCatalogPublishTargetEnvironment,
                      workspace: OpsWorkspace) async throws -> String {
        cloud.isSyncing = true
        defer { cloud.isSyncing = false }
        let draftID = workspace.draft?.id
        let generation = cloud.syncEnvironmentGeneration
        func stillCurrent() -> Bool {
            workspace.draft?.id == draftID && cloud.syncEnvironmentGeneration == generation
        }
        let directory = workspace.rootDirectory.appendingPathComponent("pulls/" + UUID().uuidString)
        cloud.updateOperationProgress(environment == .development ? "读取开发环境目录" : "读取线上环境目录")
        let request = ShopCatalogPublishRequest(requestID: UUID().uuidString,
            jobID: directory.lastPathComponent, draftID: draftID ?? "", draftRevision: workspace.currentRevision,
            targetEnvironment: environment, releaseSeq: 1,
            inputDirectory: directory.appendingPathComponent("input").path,
            archivePath: directory.appendingPathComponent("none.tar").path,
            outputDirectory: directory.path, receiptPath: directory.appendingPathComponent("receipt.json").path,
            dryRun: true, payloadHash: "pull-catalog")
        let response = await cloud.runEnvironmentBridge(mode: .pullCatalog, request: request,
            requestURL: directory.appendingPathComponent("request.json"))
        guard let response, response.exitCode == 0, response.outcome == .confirmed else {
            throw error(response?.outcomeMessage ?? cloud.lastError ?? "拉取未完成，当前草稿未合并。")
        }
        guard stillCurrent(),
              let pulled = OpsPulledCatalog.from(result: response, environment: environment.rawValue),
              pulled.releaseSeq == 0 || (pulled.rootIndexHash != nil
                && response.onlineHead?.environment == environment.rawValue) else {
            throw error("目录或版本信息不完整，或草稿已切换；未执行合并，请重新拉取。")
        }
        let url = URL(fileURLWithPath: pulled.path)
        let remote = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: Data(contentsOf: url))
        cloud.updateOperationProgress("检查并补齐目录图片")
        let media = await cloud.recoverSyncMedia(workspace: workspace, remote: remote,
            environment: environment.rawValue, updateReport: false,
            includeLocalReferences: false, stillCurrent: stillCurrent)
        guard stillCurrent(), let preview = workspace.mergePreview(from: url, environment: environment.rawValue) else {
            throw error(workspace.lastError ?? "草稿或环境已切换，请重新拉取。")
        }
        let baseline = ShopCatalogBaseline(releaseSeq: pulled.releaseSeq,
            rootIndexHash: pulled.rootIndexHash, environment: environment.rawValue, observedAt: pulled.pulledAt)
        let backup = directory.appendingPathComponent("local-before-merge.json")
        cloud.updateOperationProgress("合并并保存本地数据")
        try ShopCatalogJSONCoding.encoder(prettyPrinted: true).encode(workspace.catalog)
            .write(to: backup, options: .atomic)
        cloud.appendOperationLog("合并前本地快照：" + backup.path)
        guard let merged = workspace.mergeRemoteIntoLocal(from: url, baseline: baseline,
            preferLocalOnConflict: false, advanceBaseline: true) else {
            throw error(workspace.lastError ?? "合并保存失败，请重新拉取。")
        }
        cloud.appendOperationLog("图片：\(media.detail)\n合并：补进 \(merged.added) 条、更新 \(merged.overwritten) 条、本地独有保留 \(merged.keptLocalOnly) 条、按删除标记移除 \(merged.removed) 条\n冲突处理：采用本次拉取环境的值；本地独有条目保留\n"
            + preview.conflicts.joined(separator: "\n") + "\n"
            + media.issues.map { "\($0.owner)：\($0.message)" }.joined(separator: "\n"))
        let summary = "已拉取并合并\(environment.displayName)，发布号 \(pulled.releaseSeq)。"
        if !media.issues.isEmpty {
            throw error(summary + " 还有 \(media.issues.count) 张图片未下载，请重试拉取。")
        }
        return summary + (preview.conflicts.isEmpty ? "" : " \(preview.conflicts.count) 处差异采用本次拉取的环境，详情见日志。")
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "OpsDataSync", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
