import Combine
import Foundation
import PinkHouseOpsCore
import SharedCatalog

/// 使用独立快照迁移已发布目录，日常草稿与目标环境设置不参与合并。
@MainActor
final class OpsEnvironmentPromotionModel: ObservableObject {
    static let shared = OpsEnvironmentPromotionModel()
    @Published private(set) var isRunning = false
    @Published private(set) var plan: OpsEnvironmentPromotion.Plan?
    @Published private(set) var source: OpsPulledCatalog?
    @Published private(set) var target: OpsPulledCatalog?
    @Published private(set) var message: String? {
        didSet {
            if isRunning, let message { cloud.updateOperationProgress(message) }
        }
    }
    @Published private(set) var failed = false
    @Published private(set) var pendingRequest: ShopCatalogPublishRequest?
    private let cloud: OpsCloudSyncModel
    private let root: URL
    private var mediaDirectory: URL { root.appendingPathComponent("images", isDirectory: true) }
    private var pendingURL: URL { root.appendingPathComponent("pending.json") }

    init(cloud: OpsCloudSyncModel? = nil, root: URL? = nil) {
        self.cloud = cloud ?? .shared
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PinkHouseOps/environment-promotion", isDirectory: true)
        if FileManager.default.fileExists(atPath: pendingURL.path) {
            do {
                pendingRequest = try ShopCatalogPublishRequest.decoded(from: Data(contentsOf: pendingURL))
                message = "上次同步结果待确认，请先查询线上结果。"
            } catch {
                failed = true
                message = "上次同步记录无法读取，需核对记录后再发布：\(pendingURL.path)"
            }
        }
    }

    var needsQuery: Bool { FileManager.default.fileExists(atPath: pendingURL.path) }
    var isBusy: Bool { isRunning || cloud.isRunning || cloud.isSyncing }

    func synchronize() async {
        guard !needsQuery, begin() else { return }
        defer { end() }
        await prepare()
        if !failed, plan?.hasChanges == true { await publish() }
    }

    private func prepare() async {
        plan = nil; source = nil; target = nil
        do {
            message = "正在读取开发环境 Development…"
            let (source, development) = try await pull(.development)
            guard source.releaseSeq > 0 else { throw error("开发环境还没有已发布目录，请先发布开发环境内容。") }
            message = "正在读取线上环境 Production…"
            let (target, production) = try await pull(.production)
            self.source = source; self.target = target
            plan = try OpsEnvironmentPromotion.plan(development: development, production: production,
                                                     choice: .development)
            if let plan {
                cloud.appendOperationLog("迁移合并：新增 \(plan.added) 条、更新 \(plan.updated) 条。\n"
                    + plan.differenceDescriptions.joined(separator: "\n"))
            }
            message = plan?.hasChanges == true
                ? "已读取两个环境，正在增量同步。"
                : "线上环境已是最新，无需迁移。"
        } catch { report(error) }
    }

    private func publish() async {
        guard !needsQuery, let plan, plan.hasChanges, let source, let target else { return }
        do {
            message = "正在核对开发环境版本…"
            let sourceHead = try await run(.baseline, environment: .development)
            guard sourceHead.onlineHead?.releaseSeq == source.releaseSeq,
                  sourceHead.onlineHead?.rootIndexHash == source.rootIndexHash else {
                throw error("开发环境已变化，请重新迁移。")
            }
            message = "正在补齐开发环境图片…"
            try await download(hashes: plan.requiredSourceMedia)
            message = "正在打包并校验同步数据…"
            let directory = runDirectory()
            let archiveURL = directory.appendingPathComponent("release.tar")
            let mediaDirectory = self.mediaDirectory
            let hash = try await Task.detached(priority: .userInitiated) {
                let archive = try OpsEnvironmentPromotion.archive(plan: plan, mediaDirectory: mediaDirectory)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try archive.write(to: archiveURL, options: .atomic)
                return ShopCatalogSyncProtocol.sha256Hex(archive)
            }.value
            let seq = target.releaseSeq + 1
            let request = ShopCatalogPublishRequest(
                requestID: ShopCatalogPublishRequestKey.make(draftID: "environment-promotion",
                    draftRevision: source.releaseSeq, payloadHash: hash, targetEnvironment: .production, releaseSeq: seq),
                jobID: directory.lastPathComponent, draftID: "environment-promotion",
                draftRevision: source.releaseSeq, baseReleaseSeq: target.releaseSeq,
                baseRootIndexHash: target.rootIndexHash, targetEnvironment: .production,
                releaseSeq: seq, inputDirectory: directory.appendingPathComponent("input").path,
                archivePath: archiveURL.path, outputDirectory: directory.appendingPathComponent("output").path,
                receiptPath: directory.appendingPathComponent("receipt.json").path,
                preserveTargetPartitions: true, payloadHash: hash)
            // 在写云端前冻结任务，退出、超时或崩溃后必须先查询此任务。
            try request.encoded().write(to: pendingURL, options: .atomic)
            pendingRequest = request
            message = "正在增量上传到线上环境 Production…"
            let result = await cloud.runEnvironmentBridge(mode: .publish, request: request,
                requestURL: directory.appendingPathComponent("request.json"))
            if let result, result.outcome == .confirmed,
               result.receipt?.readBackConfirmed == true, result.receipt?.releaseSeq == seq {
                try clearPending()
                message = "已同步到线上环境 Production，发布号 \(seq)；新增 \(plan.added) 条、更新 \(plan.updated) 条，已回读确认。"
                failed = false
                self.plan = nil
                self.source = nil; self.target = nil
            } else {
                if let outcome = result?.outcome,
                   [.failed, .refused, .conflict, .replaced].contains(outcome) {
                    try clearPending()
                }
                throw error(result?.outcomeMessage ?? cloud.lastError ?? "结果待确认，请先查询同步结果。")
            }
        } catch {
            self.plan = nil
            report(error)
        }
    }

    func query() async {
        guard let request = pendingRequest, begin() else { return }
        defer { end() }
        message = "正在查询上次线上同步结果…"
        let directory = URL(fileURLWithPath: request.archivePath).deletingLastPathComponent()
        let result = await cloud.runEnvironmentBridge(mode: .query, request: request,
            requestURL: directory.appendingPathComponent("request.json"))
        do {
            if result?.outcome == .confirmed {
                let artifact = try JSONSerialization.jsonObject(with: Data(contentsOf:
                    URL(fileURLWithPath: request.outputDirectory).appendingPathComponent("release.json"))) as? [String: Any]
                guard let hash = artifact?["rootIndexHash"] as? String,
                      result?.onlineHead?.releaseSeq == request.releaseSeq,
                      result?.onlineHead?.rootIndexHash == hash else {
                    throw error("线上版本或摘要与冻结产物不符，结果仍待确认。")
                }
                try clearPending()
                message = "已确认同步到线上环境 Production，发布号 \(request.releaseSeq)。"
                failed = false
                source = nil; target = nil; plan = nil
            } else if let outcome = result?.outcome, [.failed, .conflict, .replaced].contains(outcome) {
                try clearPending()
                throw error((result?.outcomeMessage ?? "上次任务未生效。") + " 请重新迁移。")
            } else { throw error(result?.outcomeMessage ?? cloud.lastError ?? "查询未完成，结果仍待确认。") }
        } catch { report(error) }
    }

    private func pull(_ environment: ShopCatalogPublishTargetEnvironment) async throws -> (OpsPulledCatalog, ShopCatalog) {
        let result = try await run(.pullCatalog, environment: environment)
        guard let pulled = OpsPulledCatalog.from(result: result, environment: environment.rawValue),
              pulled.releaseSeq == 0 || pulled.rootIndexHash != nil else {
            throw error("\(environment.displayName) 未返回可核对的目录与版本。")
        }
        let catalog = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self,
            from: Data(contentsOf: URL(fileURLWithPath: pulled.path)))
        return (pulled, catalog)
    }

    private func run(_ mode: OpsBridgeMode, environment: ShopCatalogPublishTargetEnvironment,
                     hashes: [String]? = nil, output: URL? = nil) async throws -> OpsBridgeRunResult {
        let directory = runDirectory()
        let request = ShopCatalogPublishRequest(requestID: UUID().uuidString, jobID: directory.lastPathComponent,
            draftID: "environment-promotion", draftRevision: 0, targetEnvironment: environment,
            releaseSeq: 1, inputDirectory: directory.appendingPathComponent("input").path,
            archivePath: directory.appendingPathComponent("none.tar").path,
            outputDirectory: (output ?? directory).path, receiptPath: directory.appendingPathComponent("receipt.json").path,
            mediaHashes: hashes, dryRun: true, payloadHash: "environment-promotion")
        let result = await cloud.runEnvironmentBridge(mode: mode, request: request,
            requestURL: directory.appendingPathComponent("request.json"))
        guard let result, result.exitCode == 0, result.outcome == .confirmed else {
            throw error(result?.outcomeMessage ?? cloud.lastError ?? "\(environment.displayName) 读取失败。")
        }
        return result
    }

    private func download(hashes: [String]) async throws {
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        message = "正在校验已下载的开发环境图片…"
        let mediaDirectory = self.mediaDirectory
        let cached = await Task.detached(priority: .userInitiated) {
            Set(OpsCachedMedia.files(in: mediaDirectory).keys)
        }.value
        let missing = hashes.filter { !cached.contains($0) }
        guard !missing.isEmpty else { return }
        message = "正在下载开发环境图片，共 \(missing.count) 张…"
        let result = try await run(.fetchMedia, environment: .development, hashes: missing, output: mediaDirectory)
        guard let fetched = OpsFetchedMedia.from(result: result, environment: "development"),
              fetched.files.count == missing.count, fetched.missing.isEmpty, fetched.corrupt.isEmpty,
              fetched.unrecognizedFormat.isEmpty, fetched.pending.isEmpty else {
            throw error("开发环境图片未完整下载或校验失败，未上传到线上。")
        }
    }

    private func begin() -> Bool {
        guard !isBusy else { return false }
        isRunning = true; failed = false
        cloud.isPromotingEnvironment = true
        cloud.isSyncing = true
        return true
    }

    private func end() {
        cloud.isPromotingEnvironment = false
        cloud.isSyncing = false
        isRunning = false
    }

    private func runDirectory() -> URL { root.appendingPathComponent("runs/" + UUID().uuidString, isDirectory: true) }
    private func clearPending() throws {
        try FileManager.default.removeItem(at: pendingURL)
        pendingRequest = nil
    }
    private func report(_ error: Error) { message = error.localizedDescription; failed = true }
    private func error(_ message: String) -> NSError {
        NSError(domain: "OpsEnvironmentPromotion", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
