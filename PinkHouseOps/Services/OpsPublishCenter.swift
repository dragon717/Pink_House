//
//  OpsPublishCenter.swift
//  PinkHouseOps
//
//  发布中心：把「一次上新」走成**七步发布顺序**，并保证四个状态永不合并
//  （方案 §2 / §4 / §5 / §6，R07 / R08 / R09）。
//
//     导出成功 ≠ 发布成功 ≠ 远端已生效 ≠ 每台设备已同步
//
//  ## 它替运营挡住了什么
//
//  · **R07 基线过期**：拿一份基于旧线上版本的草稿去整包发布，会把别人后来的改动
//    整体抹掉，而线上看不出来（我们的目录本身是合法完整的）。所以提交前必须先
//    读线上发布头并核对；读不到就**不许假装核对过了** —— 只能由运营显式确认。
//  · **R08 双策略**：严格策略只收紧「本次新增 / 修改过」的内容，作用域来自与
//    基线快照的差分（推导，不是自觉上报）。存量旧数据继续按兼容口径走。
//  · **R09 结果待确认**：切发布头之后的结果不明时，界面**只给「查询结果」**，
//    不给「重发」。这一条是整个文件最贵的规则：把「不明」当「可重试」
//    就是重复发布，而重复发布会把已经前进的线上版本用旧内容写回去。
//
//  ## 为什么「冻结」要单独一步，而不是点发布就提交
//
//  冻结 = 把「这次要发的是什么」固化成一个**不可变请求**（产物摘要 + 编辑版本号
//  + 基线）。它让三件事成立：
//    · 幂等 —— 同一份冻结快照重复提交复用同一个请求号，不会发两遍；
//    · 可审计 —— 请求文件落盘，事后能逐字复现当时提交了什么；
//    · 可分辨 —— 编辑版本号变了就是新内容（新请求号），没变就还是那一次。
//

import Combine
import CryptoKit
import Foundation
// 桥接调用端（`OpsPublisherBridge` / `OpsBridgeSettings` / 中断类型）在本包里。
// `SharedCatalogBridge.swift` 已经 `@_exported` 了它，这里仍写一行：
// 本文件**在扩展外部类型**（`extension OpsBridgeSettings`），显式 import 更不容易误读。
import PinkHouseOpsCore
import SwiftData
import SwiftUI

@MainActor
final class OpsPublishCenter: ObservableObject {

    // MARK: 发布参数（运营在界面上选的）

    /// 桥接器定位（仓库目录 / 解释器 / 超时）
    @Published var settings: OpsBridgeSettings {
        didSet { persistSettings() }
    }
    /// 目标环境。**选定后本任务内不得切换**（切换会让基线核对与回执核对指向两件事）。
    @Published var targetEnvironment: ShopCatalogPublishTargetEnvironment = .localFixture
    /// 引用校验策略（R08）。默认严格：新内容是运营自己录的，理当能解析。
    @Published var strictPolicy: ShopCatalogStrictPolicy = .strict
    /// 本次要发布的号（文本输入，解析失败就不给提交）
    @Published var releaseSeqText: String = ""
    /// 读不到线上发布头时的唯一出口：运营显式确认「没有其他人先发过」。
    /// **可审计**（记进请求），而不是界面上一句口头承诺。
    @Published var baselineAcknowledged: Bool = false
    /// 演练：完整走一遍构建 + 校验 + 计划，但**不写线上**。默认开。
    @Published var useDryRun: Bool = true

    // MARK: 线上状态

    @Published private(set) var onlineHead: ShopCatalogOnlineHead?
    @Published private(set) var baselineVerdict: ShopCatalogBaselineVerdict =
        .unverified(reason: "尚未读取线上发布头")
    @Published private(set) var baselineReadAt: Date?
    @Published private(set) var isReadingBaseline = false
    /// 最近一次校验结果（严格策略 + 目标环境口径）
    @Published private(set) var review: ShopCatalogPublicationReview?

    // MARK: 从线上拉回基线（方案 §5 / R07）

    /// 上一次 `pull-catalog` 拉回来的目录。nil = 还没拉过。
    ///
    /// **它只是一份候选内容**：拉回来不会自动替换草稿 —— 替换是一次点击的事，
    /// 但它会丢掉本地未发布的改动，所以必须由运营看过告警之后再确认。
    @Published private(set) var pulledCatalog: OpsPulledCatalog?
    @Published private(set) var isPullingCatalog = false
    /// 拉回成功之后必须让运营读到的几句话（已下发口径 / 会替换什么 / 数量变化）。
    /// 由 `OpsPulledCatalogAdoption.caveats(...)` 产出，**不在视图里另写一份**。
    @Published private(set) var pulledCatalogCaveats: [String] = []
    /// 拉回时的说明（线上是空的 / 没有商店分片 —— 都是**事实**，不是失败）
    @Published private(set) var pulledCatalogNote: String?

    // MARK: 任务

    @Published private(set) var jobs: [OpsPublishJob] = []
    /// 正在跑的任务（事件流会持续更新它）
    @Published private(set) var activeJob: OpsPublishJob?
    @Published private(set) var isBusy = false
    @Published private(set) var lastMessage: String?
    @Published private(set) var lastError: String?
    /// 当前任务的可见留痕（尾部若干条）
    @Published private(set) var liveLines: [String] = []

    private let workspace: OpsWorkspace
    private let context: ModelContext
    private let fileManager = FileManager.default

    /// 当前这次调用的桥接器（用于「取消」）
    private var runningBridge: OpsPublisherBridge?
    /// 实时进度用的任务副本（只在主线程读写）
    private var liveJob: OpsPublishJob?
    /// 实时事件是否还该被采纳（任务收尾后关掉，避免迟到的更新覆盖结论）
    private var liveEventsEnabled = false

    init(workspace: OpsWorkspace, context: ModelContext? = nil) {
        self.workspace = workspace
        self.context = context ?? workspace.modelContextForPublishing
        self.settings = Self.loadSettings()
        loadJobs()
        recoverInterruptedJobs()
        suggestedReleaseSeqText()
    }

    // MARK: 派生状态（视图只读这些）

    /// 桥接器可用性自检（空 = 就绪）
    var bridgeProblems: [String] { settings.diagnosis() }

    /// 建议的发布号：线上 + 1，且不低于本机记录过的最大号。
    /// 运营可以改，但界面会拿它跟线上比，不大于线上就不让提交。
    var suggestedReleaseSeq: Int {
        let candidates = [
            (onlineHead?.releaseSeq ?? 0) + 1,
            (workspace.draft?.lastPublishedReleaseSeq ?? 0) + 1,
            (workspace.baseline.releaseSeq ?? 0) + 1,
            1,
        ]
        return candidates.max() ?? 1
    }

    var parsedReleaseSeq: Int? {
        let trimmed = releaseSeqText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    /// 提交前的阻断项（空 = 可以提交）。**每一条都必须能解释清楚原因。**
    var submissionBlockers: [String] {
        var blockers: [String] = []
        if workspace.draft == nil {
            blockers.append("还没有草稿。")
        }
        if workspace.isCorrupted {
            blockers.append("草稿处于只读隔离状态，不能发布。请先「另存为新草稿」。")
        }
        if !bridgeProblems.isEmpty {
            blockers.append(contentsOf: bridgeProblems)
        }
        if parsedReleaseSeq == nil {
            blockers.append("请填一个大于 0 的发布号。")
        } else if let online = onlineHead, let seq = parsedReleaseSeq, seq <= online.releaseSeq {
            blockers.append("发布号 \(seq) 不大于线上 \(online.releaseSeq)："
                + "发布号必须严格递增（要回到旧内容请用回滚流程，那是另一个号）。")
        }
        if case .stale(_, let reasons) = baselineVerdict {
            blockers.append("基线已过期：\(reasons.joined(separator: "；"))。"
                + "直接覆盖会抹掉别人后来的改动，请先合并再重新确认。")
        }
        if !baselineVerdict.isVerified, !baselineAcknowledged {
            blockers.append("还没有核对线上基线。请先「读取线上基线」；"
                + "读不到时也要显式勾选「我已确认没有其他人先发过」。")
        }
        if workspace.hasUnsavedChanges {
            blockers.append("草稿有未保存的修改：发布的是**已保存**的内容，请先保存。")
        }
        return blockers
    }

    var canSubmit: Bool { submissionBlockers.isEmpty }

    /// 严格策略的作用域大小（界面上必须显示，否则运营会以为严格没生效）
    var strictScopeCount: Int { workspace.strictScopeIDs.count }

    /// 与基线快照的差分（发布前给运营确认「我只改了这几个」）
    var changeSet: ShopCatalogChangeSet { workspace.changeSet }

    /// 需要人处理的任务
    var jobsNeedingAttention: [OpsPublishJob] { jobs.filter(\.needsAttention) }

    // MARK: 校验（带上严格策略与目标环境）

    /// 跑一次完整校验并留下结果。提交路径会**再跑一次**（服务侧复校验），
    /// 所以这里的结果只用于界面展示。
    @discardableResult
    func validateNow() -> ShopCatalogPublicationReview {
        let result = workspace.validate(
            strict: strictPolicy,
            strictScope: workspace.strictScopeIDs,
            verifiedRemoteMediaKeys: verifiedRemoteMediaKeys(),
            targetEnvironmentName: targetEnvironment.displayName)
        review = result
        lastError = result.isBlocked ? result.blockingIssues.joined(separator: "\n") : nil
        return result
    }

    /// 已在**目标环境**回读确认过的媒体键。
    ///
    /// **永远是空集，这是刻意的**：本机离线判不出「那个远端键在目标环境里
    /// 是不是真的有那份字节」—— Development 有图 ≠ Production 有图。
    /// 真正的回读核对在发布器第 5 步做，结论由回执回传。
    /// 所以严格策略下这些键只会以**告警**形式列出，而不是本机假装阻断。
    private func verifiedRemoteMediaKeys() -> Set<String> { [] }

    // MARK: 读取线上基线（R07）

    /// 读线上发布头并给出核对结论。**只读，不写任何东西，也不改动草稿内容。**
    func refreshBaseline() async {
        guard !isReadingBaseline, !isBusy else { return }
        guard bridgeProblems.isEmpty else {
            lastError = bridgeProblems.joined(separator: "\n")
            return
        }
        isReadingBaseline = true
        lastError = nil
        lastMessage = "正在读取线上发布头…"

        // 读基线也要一个请求文件：桥接器只认请求（不从命令行接收业务参数）
        guard let requestPath = try? writeProbeRequest(mode: .baseline) else {
            isReadingBaseline = false
            lastError = "无法写出发起请求（检查应用容器目录是否可写）。"
            return
        }

        let settings = self.settings
        let environment = targetEnvironment
        do {
            let result = try await runBridge(mode: .baseline, requestPath: requestPath, settings: settings)
            applyBaselineResult(result, environment: environment)
        } catch {
            lastError = describe(error)
            baselineVerdict = .unverified(reason: shortReason(error))
        }
        isReadingBaseline = false
    }

    private func applyBaselineResult(_ result: OpsBridgeRunResult, environment: ShopCatalogPublishTargetEnvironment) {
        guard let head = result.onlineHead else {
            baselineVerdict = .unverified(reason: "桥接器没有返回线上发布头")
            lastError = result.outcomeMessage
            return
        }
        onlineHead = head
        baselineReadAt = head.observedAt
        baselineVerdict = ShopCatalogBaselineResolver.verdict(
            baseline: workspace.baseline, head: head)
        if baselineVerdict.isVerified { baselineAcknowledged = false }
        suggestedReleaseSeqText()
        // 基线读到了 → 严格策略的「已回读确认媒体键」集合才有意义
        lastMessage = "线上基线：" + head.hashText
            + "（releaseSeq \(head.releaseSeq)）· \(baselineVerdict.displayName)"
        lastError = nil
    }

    /// 把读到的线上头**显式**采用为草稿基线（运营的选择，不是自动回填）。
    func adoptOnlineHeadAsBaseline() {
        guard let head = onlineHead else {
            lastError = "还没有读到线上发布头。"
            return
        }
        workspace.adoptBaseline(head)
        baselineVerdict = ShopCatalogBaselineResolver.verdict(baseline: workspace.baseline, head: head)
        lastMessage = workspace.statusText
    }

    // MARK: 从线上拉回基线（方案 §5 / R07）

    /// 当前草稿的各类条数（键与线上载荷字段名同值）。
    ///
    /// 用来在替换前给运营一个「会从 N 变成 M」的**实数**，
    /// 而不是一句「内容会变动」——后者等于什么都没说。
    var currentContentItemCounts: [String: Int] {
        let catalog = workspace.catalog
        return [
            "shops": catalog.shops.count,
            "series": catalog.series.count,
            "products": catalog.products.count,
            "variants": catalog.variants.count,
            "sizeCharts": catalog.sizeCharts.count,
            "saleEvents": catalog.saleEvents.count,
            "assets": catalog.assets.count,
            "styleProfiles": catalog.styleProfiles.count,
        ]
    }

    /// 「用拉回的内容替换草稿」当前的阻断项（空 = 可以替换）。
    /// 判定在包里（`OpsPulledCatalogAdoption`），这里只负责把输入凑齐。
    var pulledCatalogAdoptionBlockers: [String] {
        guard let pulledCatalog else { return ["还没有从线上拉回任何内容。"] }
        // 判「能不能真读」用 `isReadableFile`，不是 `fileExists` ——
        // 沙盒下后者会骗人（存在但读不到），见 `OpsBridgeSettings` 的长注释。
        return OpsPulledCatalogAdoption.blockers(
            pulled: pulledCatalog,
            isDraftCorrupted: workspace.isCorrupted,
            isCatalogFileReadable: OpsBridgeSettings.isReadableFile(
                URL(fileURLWithPath: pulledCatalog.path)))
    }

    /// **只读**把线上商店目录整份拉回本地（方案 §5 的「当前线上完整基线」）。
    ///
    /// 两件「不会发生」的事要明确：**不写线上**（桥接器侧由 `apply=False` 的
    /// 读/写闸门保证），**不动当前草稿** —— 只在 `pulledCatalog` 里放一份候选内容。
    /// 替换是另一次显式点击（见 `adoptPulledCatalog()`）。
    func pullCatalogFromOnline() async {
        guard !isBusy, !isPullingCatalog else { return }
        guard bridgeProblems.isEmpty else {
            lastError = bridgeProblems.joined(separator: "\n")
            return
        }
        isPullingCatalog = true
        lastError = nil
        lastMessage = "正在从线上拉回商店目录（只读）…"

        guard let requestPath = try? writeProbeRequest(mode: .pullCatalog) else {
            isPullingCatalog = false
            lastError = "无法写出发起请求（检查应用容器目录是否可写）。"
            return
        }
        let settings = self.settings
        let environment = targetEnvironment
        do {
            let result = try await runBridge(
                mode: .pullCatalog, requestPath: requestPath, settings: settings)
            applyPulledCatalogResult(result, environment: environment)
        } catch {
            lastError = describe(error)
            pulledCatalogNote = shortReason(error)
        }
        isPullingCatalog = false
    }

    private func applyPulledCatalogResult(
        _ result: OpsBridgeRunResult, environment: ShopCatalogPublishTargetEnvironment
    ) {
        // pull-catalog 顺带读了发布头，不用再单独读一次基线
        if let head = result.onlineHead {
            onlineHead = head
            baselineReadAt = head.observedAt
            baselineVerdict = ShopCatalogBaselineResolver.verdict(
                baseline: workspace.baseline, head: head)
        }
        guard let pulled = OpsPulledCatalog.from(
            result: result, environment: environment.rawValue) else {
            // 线上没有可拉回的东西。这是**事实**，不是失败 ——
            // 桥接器的结论文案已经把它说清楚了（线上是空的 / 这一版没有商店分片）。
            pulledCatalog = nil
            pulledCatalogCaveats = []
            pulledCatalogNote = result.outcomeMessage
                ?? "线上没有可拉回的商店目录（首次发布前就是这个状态）。"
            lastMessage = pulledCatalogNote
            lastError = nil
            return
        }
        pulledCatalog = pulled
        // 告警在**拉回时就**算好，而不是等点了「替换」之后：
        // 运营要先读、再决定。顺序反了就成了先斩后奏。
        pulledCatalogCaveats = OpsPulledCatalogAdoption.caveats(
            pulled: pulled, currentItemCounts: currentContentItemCounts)
        pulledCatalogNote = nil
        lastMessage = "已拉回线上商店目录：" + pulled.summaryText
            + "。它**还没有**替换你的草稿。"
        lastError = nil
    }

    /// 用拉回的内容**替换当前草稿**，并把这一版记为草稿基线。
    ///
    /// 界面必须先让运营读过 `pulledCatalogCaveats` 再调用；这里再挡一道：
    /// 有阻断项直接拒绝，**绝不静默替换**（替换会丢掉本地未发布的改动）。
    @discardableResult
    func adoptPulledCatalog() -> Bool {
        guard let pulled = pulledCatalog else {
            lastError = "还没有从线上拉回任何内容。"
            return false
        }
        let blockers = pulledCatalogAdoptionBlockers
        guard blockers.isEmpty else {
            lastError = blockers.joined(separator: "\n")
            return false
        }
        let baseline = OpsPulledCatalogAdoption.baseline(afterAdopting: pulled)
        guard workspace.adoptPulledCatalogContent(
            from: URL(fileURLWithPath: pulled.path), baseline: baseline) else {
            lastError = workspace.lastError ?? "替换草稿内容失败。"
            return false
        }
        // 替换之后立刻核对一次：草稿基线 = 刚拉回那一版、线上头也是它 → 一致。
        let head = OpsPulledCatalogAdoption.head(afterAdopting: pulled)
        onlineHead = head
        baselineReadAt = pulled.pulledAt
        baselineVerdict = ShopCatalogBaselineResolver.verdict(
            baseline: workspace.baseline, head: head)
        baselineAcknowledged = false

        // 发布号：拉回之后线上号变大了，原来那个值通常已经「不大于线上」。
        // **只在当前值 ≤ 刚拉回的号时**抬到 线上+1（运营已经填了更大的号就不动它），
        // 否则运营会立刻撞上「发布号必须严格递增」，却不知道是被拉回动作顶掉的。
        if let current = parsedReleaseSeq, current <= pulled.releaseSeq {
            releaseSeqText = String(pulled.releaseSeq + 1)
        }
        pulledCatalogCaveats = []
        pulledCatalog = nil
        lastMessage = workspace.statusText
        lastError = nil
        return true
    }

    /// 放弃这份候选内容（**不动草稿**）。
    func discardPulledCatalog() {
        pulledCatalog = nil
        pulledCatalogCaveats = []
        pulledCatalogNote = "已放弃这次拉回的内容（草稿没有被改动）。"
        lastMessage = pulledCatalogNote
    }

    func suggestedReleaseSeqText() {
        if parsedReleaseSeq == nil || releaseSeqText.isEmpty {
            releaseSeqText = String(suggestedReleaseSeq)
        }
    }

    // MARK: 冻结快照

    /// 冻结一次发布：产物落盘 + 请求落盘 + 任务台账落一条 `frozen`。
    ///
    /// 冻结之后**任何编辑都不会改变这次要发的内容** —— 要改就重新冻结
    /// （编辑会让 `draftRevision` 变化，从而产生新的请求号，这是刻意的）。
    @discardableResult
    func freeze() -> OpsPublishJob? {
        lastError = nil
        let blockers = submissionBlockers
        guard blockers.isEmpty else {
            lastError = blockers.joined(separator: "\n")
            return nil
        }
        guard let releaseSeq = parsedReleaseSeq, let draft = workspace.draft else {
            lastError = "缺少发布号或草稿。"
            return nil
        }

        // 1) 先跑校验（严格策略 + 目标环境）
        let strictScope = workspace.strictScopeIDs
        let result = workspace.validate(
            strict: strictPolicy,
            strictScope: strictScope,
            verifiedRemoteMediaKeys: verifiedRemoteMediaKeys(),
            targetEnvironmentName: targetEnvironment.displayName)
        review = result
        guard !result.isBlocked else {
            lastError = "发布前校验未通过（\(result.blockingIssues.count + result.catalogIssues.count) 条），"
                + "已拒绝冻结：\n" + (result.catalogIssues + result.blockingIssues).prefix(5)
                    .joined(separator: "\n")
            return nil
        }

        // 2) 生成待发布整包（内部**再复校验一次**：R01 的「服务入口复校验」）
        let archive: Data
        do {
            archive = try workspace.makePublicationArchive(
                strict: strictPolicy,
                strictScope: strictScope,
                targetEnvironmentName: targetEnvironment.displayName)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
        let payloadHash = Self.sha256Hex(archive)

        // 3) 幂等请求号：内容 / 版本 / 环境 / 发布号 任一变化就是新任务
        let requestID = ShopCatalogPublishRequestKey.make(
            draftID: draft.id,
            draftRevision: draft.currentRevision,
            payloadHash: payloadHash,
            targetEnvironment: targetEnvironment,
            releaseSeq: releaseSeq)

        // 4) 落盘：请求文件 + 产物 + 产物目录
        let directory = publishDirectory(for: requestID)
        let inputDirectory = directory.appendingPathComponent("input", isDirectory: true)
        let outputDirectory = directory.appendingPathComponent("output", isDirectory: true)
        let archiveURL = directory.appendingPathComponent("shop-catalog.tar")
        let receiptURL = directory.appendingPathComponent("receipt.json")
        let requestURL = directory.appendingPathComponent("request.json")
        do {
            try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
            try archive.write(to: archiveURL, options: .atomic)
        } catch {
            lastError = "无法写入待发布包：\(error.localizedDescription)"
            return nil
        }

        let request = ShopCatalogPublishRequest(
            requestID: requestID,
            jobID: "job-\(UUID().uuidString.prefix(8).lowercased())",
            draftID: draft.id,
            draftRevision: draft.currentRevision,
            baseReleaseSeq: workspace.baseline.releaseSeq,
            baseRootIndexHash: workspace.baseline.rootIndexHash,
            baselineAcknowledged: baselineAcknowledged || baselineVerdict.isVerified,
            targetEnvironment: targetEnvironment,
            releaseSeq: releaseSeq,
            inputDirectory: inputDirectory.path,
            archivePath: archiveURL.path,
            outputDirectory: outputDirectory.path,
            receiptPath: receiptURL.path,
            filesystemRoot: targetEnvironment == .localFixture ? fixtureRoot().path : nil,
            dryRun: useDryRun,
            payloadHash: payloadHash)
        do {
            try request.encoded().write(to: requestURL, options: .atomic)
        } catch {
            lastError = "无法写入发布请求：\(error.localizedDescription)"
            return nil
        }

        // 5) 台账
        let existing = jobs.first { $0.requestID == requestID }
        var job = OpsPublishJob(
            requestID: requestID,
            jobID: request.jobID,
            draftID: draft.id,
            draftRevision: draft.currentRevision,
            baseReleaseSeq: workspace.baseline.releaseSeq,
            baseRootIndexHash: workspace.baseline.rootIndexHash,
            baselineAcknowledged: request.baselineAcknowledged,
            targetEnvironment: targetEnvironment,
            releaseSeq: releaseSeq,
            payloadHash: payloadHash,
            state: .frozen,
            totalUnits: 7,
            outputDirectory: outputDirectory.path,
            attemptCount: existing?.attemptCount ?? 0)
        job.logLines = existing?.logLines ?? []

        let auditNote = "已冻结：目标 \(targetEnvironment.displayName) · releaseSeq \(releaseSeq)"
            + " · 第 \(draft.currentRevision) 版 · 产物摘要 \(String(payloadHash.prefix(12)))…"
            + " · 严格策略作用域 \(strictScope.count) 个实体"
            + (useDryRun ? " · **本次为演练（不写线上）**" : "")
        job.logLines.append(auditNote)
        persist(job)
        activeJob = job
        liveLines = job.logLines
        lastMessage = auditNote
        lastError = nil
        return job
    }

    // MARK: 提交

    /// 提交一条已冻结的任务。
    func submit(_ job: OpsPublishJob) async {
        guard !isBusy else {
            lastError = "还有一个发布任务在跑，等它结束再提交。"
            return
        }
        guard job.state.allowsResubmit else {
            // 这条分支是 R09 的界面出口：结果待确认时**只能查询**
            lastError = job.state == .pendingConfirmation
                ? "这条任务的结果还不确定（切发布头之后没拿到结论）。请先「查询结果」，不要重新提交 —— 重发会造成重复发布。"
                : "任务处于「\(job.state.displayName)」，当前不允许再次提交。"
            return
        }
        guard let requestPath = requestFileURL(for: job) else {
            lastError = "找不到这条任务的请求文件：\(job.requestID)。请重新冻结后再提交。"
            return
        }
        guard fileManager.fileExists(atPath: requestPath.path) else {
            lastError = "请求文件已经不存在了（可能被清理过）：\(requestPath.lastPathComponent)。请重新冻结。"
            return
        }

        var running = job
        running.attemptCount += 1
        running.submittedAt = Date()
        running.finishedAt = nil
        running.lastErrorMessage = nil
        // `.refused` / `.conflict` 不能直接进 `.building`（状态机只给了
        // 「先回到已冻结」这条路）—— 语义上也对：修好配置之后应当重新冻结。
        if running.state != .building,
           !ShopCatalogPublishExecutionState.canTransition(from: running.state, to: .building) {
            running = transition(running, to: .frozen)
        }
        running = transition(running, to: .building, stage: .build)
        persist(running)
        activeJob = running
        liveLines = running.logLines

        await runAndFinalize(
            job: running,
            mode: .publish,
            requestPath: requestPath,
            startMessage: "正在发布…")
    }

    /// 结果待确认 / 失败后的**查询**（R09 的第一动作）。
    func queryResult(_ job: OpsPublishJob) async {
        guard !isBusy else { return }
        guard let requestPath = requestFileURL(for: job) else {
            lastError = "找不到这条任务的请求文件，无法查询。"
            return
        }
        activeJob = job
        await runAndFinalize(
            job: job,
            mode: .query,
            requestPath: requestPath,
            startMessage: "正在查询线上发布头…")
    }

    /// 重试：**只在切头之前失败**才允许（`allowsResubmit` 已经把这个条件编进状态机）。
    func retry(_ job: OpsPublishJob) async {
        guard job.state.allowsResubmit else {
            await queryResult(job)
            return
        }
        await submit(job)
    }

    func cancelCurrentRun() {
        guard let bridge = runningBridge else { return }
        lastMessage = "正在取消…（已进入远端写入的动作不会被撤回，取消后请查询结果确认）"
        bridge.cancel()
    }

    // MARK: 执行 + 收尾

    private func runAndFinalize(
        job: OpsPublishJob,
        mode: OpsBridgeMode,
        requestPath: URL,
        startMessage: String
    ) async {
        isBusy = true
        lastError = nil
        lastMessage = startMessage
        runningBridge = OpsPublisherBridge(settings: settings)

        let settings = self.settings
        var log = job.logLines
        log.append("— 开始\(mode.displayName)（第 \(job.attemptCount) 次）—")
        liveLines = log
        // 实时更新的落点：事件只写这个字段（主线程），
        // 最终状态由完整事件流**重放**得出（见下面 replay）。
        liveJob = job
        liveEventsEnabled = true

        var running = job
        do {
            let result = try await runBridge(
                mode: mode,
                requestPath: requestPath,
                settings: settings,
                onEvent: { [weak self] event in
                    // 事件在管道读取线程上到达。用 main.async 逐条投递：
                    // 单生产者 → 顺序保序（`Task` 不保序），而且所有状态变更
                    // 都发生在主线程，不存在跨线程改捕获变量。
                    DispatchQueue.main.async {
                        self?.applyLive(event)
                    }
                })
            liveEventsEnabled = false
            // 结束之后**重放**完整事件流：这样任务状态与阶段进度是
            // 事件序列的确定性函数，不受「实时更新是否刚好投递完」影响。
            running = liveJob ?? running
            for event in result.events { apply(event: event, to: &running) }
            for line in result.events.compactMap(\.displayLine) { log.append(line) }
            if let line = result.lastDisplayLine { log.append("— " + line + " —") }
            running.logLines = log
            running = finalize(running, with: result, mode: mode)
        } catch {
            liveEventsEnabled = false
            let message = describe(error)
            log.append("✗ " + message)
            running = liveJob ?? running
            running.logLines = log
            running.lastErrorMessage = message
            // 中断也要按阶段保守判定：走到切头之后 = 结果不明（R09）
            running = concludeInterruption(running)
            lastError = message
        }
        running.finishedAt = Date()
        persist(running)
        activeJob = running
        liveLines = running.logLines
        runningBridge = nil
        liveJob = nil
        isBusy = false
        lastMessage = running.statusText
    }

    /// 实时进度（**只在主线程调用**）。
    ///
    /// 只做展示：任务状态机与阶段进度的**最终**值由事件流重放决定。
    /// 这样即使某次实时更新没赶上（或者事件在进程被杀前只到了一半），
    /// 落到台账里的也是一个能自洽解释的状态。
    private func applyLive(_ event: ShopCatalogPublishEvent) {
        guard liveEventsEnabled, var job = liveJob else { return }
        apply(event: event, to: &job)
        liveJob = job
        activeJob = job
        if let line = event.displayLine {
            liveLines.append(line)
            if liveLines.count > 200 { liveLines.removeFirst(liveLines.count - 200) }
        }
    }

    /// 事件 → 任务状态 / 进度（只做**合法**的转移；非法转移留着不改并在留痕里说明）
    private func apply(event: ShopCatalogPublishEvent, to job: inout OpsPublishJob) {
        switch event.type {
        case "stage":
            guard let stage = event.stage, event.state == .started else { return }
            job.stage = stage
            if let ordinal = stage.stepOrdinal {
                job.completedUnits = max(0, ordinal - 1)
                job.totalUnits = 7
            }
            if let target = Self.state(for: stage), target != job.state,
               ShopCatalogPublishExecutionState.canTransition(from: job.state, to: target) {
                job.state = target
            }
            job.updatedAt = Date()
        default:
            job.updatedAt = Date()
        }
    }

    private static func state(for stage: ShopCatalogPublishStage) -> ShopCatalogPublishExecutionState? {
        switch stage {
        case .freeze, .baseline: return nil
        case .build, .verifyArtifact: return .building
        case .readHead, .uploadMedia, .uploadPacks, .readBack: return .uploading
        // 切头与回读确认都停在 `switchingHead`：**发布头已经（可能）切换了**，
        // 在拿到明确确认之前不能把状态往前推。
        case .switchHead, .confirmHead: return .switchingHead
        }
    }

    /// 用桥接器的结论收尾。
    private func finalize(_ job: OpsPublishJob, with result: OpsBridgeRunResult, mode: OpsBridgeMode) -> OpsPublishJob {
        var job = job
        job.receipt = result.receipt

        if let head = result.onlineHead {
            onlineHead = head
            baselineReadAt = head.observedAt
            baselineVerdict = ShopCatalogBaselineResolver.verdict(
                baseline: workspace.baseline, head: head)
        }

        guard let outcome = result.outcome else {
            // 桥接器没有下结论：
            //  · 演练成功返回 → 保持 `frozen`（可以再提交一次真正发布）
            //  · 其它情况一律按**保守**处理：走到切头就算结果不明
            if result.exitCode == 0, job.receipt?.applied == false {
                job.state = .frozen
                job.stage = nil
                job.completedUnits = 0
                job.lastErrorMessage = nil
                lastMessage = "演练完成：产物已构建并复校验通过，**线上没有任何改动**。"
                lastError = nil
                return job
            }
            return concludeInterruption(job, exitCode: result.exitCode)
        }

        let target = outcome.executionState
        if ShopCatalogPublishExecutionState.canTransition(from: job.state, to: target) || target == job.state {
            job.state = target
        } else {
            // 状态机不允许这条边 = 上游给了个我们没预期的结论。
            // **不强行写**，而是落到最保守的那个：结果待确认。
            job.logLines.append(
                "⚠️ 桥接器结论 \(outcome.displayName) 与当前状态 \(job.state.displayName) "
                    + "之间没有合法转移，已按「结果待确认」处理（不猜）。")
            job.state = .pendingConfirmation
        }
        job.failureKind = Self.failureKind(for: outcome, message: result.outcomeMessage)
        job.lastErrorMessage = outcome == .confirmed ? nil : result.outcomeMessage
        if let message = result.outcomeMessage { job.logLines.append("结论：" + message) }

        if outcome == .confirmed {
            if mode == .publish || mode == .query {
                // 回读确认 → 记录发布号、版本，并把当前内容写成新的基线快照。
                // 少了这一步，下次发布会把这次的改动又算成新改动。
                let recorded = workspace.recordConfirmedPublish(
                    releaseSeq: job.releaseSeq,
                    rootIndexHash: result.receipt?.rootIndexHash ?? result.artifactRootIndexHash,
                    environment: job.targetEnvironment.rawValue,
                    revision: job.draftRevision)
                if !recorded, let error = workspace.lastError {
                    job.logLines.append("⚠️ " + error)
                }
                lastMessage = "发布已确认：releaseSeq \(job.releaseSeq)（线上发布头已指向本次产物）。"
                    + "注意这不代表每台离线设备都已刷新。"
            }
        } else {
            lastMessage = "\(outcome.displayName)。"
        }
        job.updatedAt = Date()
        return job
    }

    /// 中断 / 没拿到结论时的保守判定（R09）。
    private func concludeInterruption(_ job: OpsPublishJob, exitCode: Int32? = nil) -> OpsPublishJob {
        var job = job
        let reachedSwitch = job.state == .switchingHead
            || (job.stage?.stepOrdinal ?? 0) >= 6
            || job.receipt?.applied == true
        if reachedSwitch {
            job.state = .pendingConfirmation
            job.failureKind = .unknown
            let note = "已进入切换发布头之后，但**没有拿到明确结论**：线上可能已经生效。"
                + "请用「查询结果」确认，不要重新提交（R09）。"
            job.lastErrorMessage = job.lastErrorMessage.map { $0 + "\n" + note } ?? note
            job.logLines.append("⚠️ " + note)
        } else {
            job.state = .retryableFailure
            job.failureKind = .network
            let note = "在切换发布头之前中断，线上仍是旧版本，可以安全重试同一份快照。"
            job.lastErrorMessage = job.lastErrorMessage.map { $0 + "\n" + note } ?? note
        }
        if let exitCode { job.logLines.append("（退出码 \(exitCode)）") }
        job.updatedAt = Date()
        return job
    }

    private static func failureKind(
        for outcome: ShopCatalogPublishOutcome, message: String?
    ) -> MediaUploadFailureKind? {
        switch outcome {
        case .confirmed: return nil
        case .conflict: return .conflict
        case .pendingConfirmation: return .unknown
        case .replaced: return .conflict
        case .failed: return .network
        case .refused:
            let text = message ?? ""
            if text.contains("凭证") || text.contains("环境") || text.contains("权限") {
                return .environment
            }
            return .validation
        }
    }

    private func transition(
        _ job: OpsPublishJob,
        to state: ShopCatalogPublishExecutionState,
        stage: ShopCatalogPublishStage? = nil
    ) -> OpsPublishJob {
        var copy = job
        if copy.state == state || ShopCatalogPublishExecutionState.canTransition(from: copy.state, to: state) {
            copy.state = state
        } else {
            copy.logLines.append(
                "⚠️ 无法从 \(copy.state.displayName) 转到 \(state.displayName)（状态机不允许），保持原状态。")
        }
        copy.stage = stage
        copy.updatedAt = Date()
        return copy
    }

    // MARK: 桥接器调用（阻塞 IO 放后台，事件回主线程）

    private func runBridge(
        mode: OpsBridgeMode,
        requestPath: URL,
        settings: OpsBridgeSettings,
        onEvent: @escaping (ShopCatalogPublishEvent) -> Void = { _ in }
    ) async throws -> OpsBridgeRunResult {
        let environmentName = targetEnvironment.rawValue
        let bridge = OpsPublisherBridge(settings: settings)
        runningBridge = bridge
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try bridge.run(
                        mode: mode,
                        requestPath: requestPath,
                        environmentName: environmentName,
                        onEvent: onEvent)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: 请求文件位置

    /// 发布产物根目录（应用容器内：沙盒下只有这里可写）
    var publishRootDirectory: URL {
        workspace.rootDirectory.appendingPathComponent("publish", isDirectory: true)
    }

    /// 本机演练目录（filesystem 适配器的目标）：也在容器里，不碰用户任何文件
    func fixtureRoot() -> URL {
        workspace.rootDirectory
            .appendingPathComponent("fixture", isDirectory: true)
            .appendingPathComponent(targetEnvironment.rawValue, isDirectory: true)
    }

    /// 用请求号的摘要做目录名：请求号里有 `|`，当目录名合法但很难看，
    /// 而目录名本来也不承担「可读」的职责（可读的是 request.json）。
    func publishDirectory(for requestID: String) -> URL {
        let digest = Self.sha256Hex(Data(requestID.utf8))
        return publishRootDirectory.appendingPathComponent(String(digest.prefix(16)), isDirectory: true)
    }

    private func requestFileURL(for job: OpsPublishJob) -> URL? {
        let url = publishDirectory(for: job.requestID).appendingPathComponent("request.json")
        return url
    }

    /// 只为「读基线」写一个最小请求（不会留下任务台账）。
    private func writeProbeRequest(mode: OpsBridgeMode) throws -> URL {
        let directory = publishRootDirectory.appendingPathComponent("probe", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let request = ShopCatalogPublishRequest(
            requestID: "probe-\(mode.rawValue)-\(targetEnvironment.rawValue)",
            jobID: "probe",
            draftID: workspace.draft?.id ?? "none",
            draftRevision: workspace.currentRevision,
            baseReleaseSeq: workspace.baseline.releaseSeq,
            baseRootIndexHash: workspace.baseline.rootIndexHash,
            baselineAcknowledged: false,
            targetEnvironment: targetEnvironment,
            releaseSeq: parsedReleaseSeq ?? suggestedReleaseSeq,
            inputDirectory: directory.appendingPathComponent("input").path,
            archivePath: directory.appendingPathComponent("none.tar").path,
            outputDirectory: directory.appendingPathComponent("output").path,
            receiptPath: directory.appendingPathComponent("receipt.json").path,
            filesystemRoot: targetEnvironment == .localFixture ? fixtureRoot().path : nil,
            dryRun: true,
            payloadHash: "probe")
        let url = directory.appendingPathComponent("request.json")
        try request.encoded().write(to: url, options: .atomic)
        return url
    }

    // MARK: 台账落盘

    private func loadJobs() {
        let descriptor = FetchDescriptor<OpsPublishJobRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let records = (try? context.fetch(descriptor)) ?? []
        jobs = records.map(\.job)
    }

    /// 启动恢复：上次进程被杀留下的「正在跑」状态，一律收成保守结论。
    ///
    /// **绝不自动重发**。把 `switchingHead` 恢复成「可重试」就是 R09 要防的
    /// 那次重复发布 —— 线上可能已经生效了。
    private func recoverInterruptedJobs() {
        var recoveredCount = 0
        var awaitingCount = 0
        for index in jobs.indices where jobs[index].isRunning {
            let restored = OpsPublishJob.recovered(jobs[index])
            jobs[index] = restored
            persist(restored)
            if restored.state == .pendingConfirmation { awaitingCount += 1 } else { recoveredCount += 1 }
        }
        if awaitingCount > 0 {
            lastError = "有 \(awaitingCount) 条任务在上次运行中**切到发布头之后中断**，结果不明："
                + "请到发布中心点「查询结果」，不要直接重发。"
        } else if recoveredCount > 0 {
            lastMessage = "有 \(recoveredCount) 条任务在上次运行中断（都在切发布头之前），"
                + "线上仍是旧版本，可以安全重试。"
        }
    }

    func persist(_ job: OpsPublishJob) {
        if let index = jobs.firstIndex(where: { $0.requestID == job.requestID }) {
            jobs[index] = job
        } else {
            jobs.insert(job, at: 0)
        }
        let key = job.requestID
        let descriptor = FetchDescriptor<OpsPublishJobRecord>(
            predicate: #Predicate { $0.requestID == key })
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.apply(job)
        } else {
            context.insert(OpsPublishJobRecord(job: job))
        }
        try? context.save()
        if activeJob?.requestID == job.requestID { activeJob = job }
    }

    func removeJob(_ job: OpsPublishJob) {
        guard !job.isRunning else {
            lastError = "任务还在跑，不能删除台账。"
            return
        }
        jobs.removeAll { $0.requestID == job.requestID }
        let key = job.requestID
        let descriptor = FetchDescriptor<OpsPublishJobRecord>(
            predicate: #Predicate { $0.requestID == key })
        for record in (try? context.fetch(descriptor)) ?? [] {
            context.delete(record)
        }
        try? context.save()
    }

    // MARK: 设置持久化

    private static func loadSettings() -> OpsBridgeSettings {
        guard let data = UserDefaults.standard.data(forKey: OpsBridgeSettings.defaultsKey),
              let decoded = try? JSONDecoder().decode(OpsBridgeSettings.self, from: data) else {
            var settings = OpsBridgeSettings()
            // 开发机上仓库位置固定；只在**没有任何设置**时给一个默认猜测，
            // 猜错也不会静默失败（自检会把「脚本不存在」直接说出来）。
            if FileManager.default.fileExists(atPath: OpsBridgeSettings.defaultRepoGuess) {
                settings.repoRootPath = OpsBridgeSettings.defaultRepoGuess
            }
            return settings
        }
        return decoded
    }

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: OpsBridgeSettings.defaultsKey)
    }

    /// 用户在面板里选完仓库目录之后调用：存路径 + security-scoped bookmark。
    func authorizeRepository(at directory: URL) {
        var updated = settings
        updated.repoRootPath = directory.path
        updated.repoRootBookmark = OpsPublisherBridge.makeBookmark(for: directory)
        settings = updated
        let problems = updated.diagnosis()
        if problems.isEmpty {
            lastMessage = "已授权仓库目录：\(directory.path)"
            lastError = nil
        } else {
            lastError = problems.joined(separator: "\n")
        }
    }

    // MARK: 文案

    private func describe(_ error: Error) -> String {
        if let bridgeError = error as? OpsBridgeError {
            return bridgeError.errorDescription ?? "\(bridgeError)"
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func shortReason(_ error: Error) -> String {
        if let bridgeError = error as? OpsBridgeError {
            switch bridgeError {
            case .timedOut: return "读取超时"
            case .cancelled: return "已取消"
            case .scriptNotFound: return "桥接脚本不可用"
            case .executableNotFound: return "python3 不可用"
            default: return "桥接器调用失败"
            }
        }
        return error.localizedDescription
    }

    func clearError() { lastError = nil }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension OpsBridgeSettings {
    /// 本机开发时的仓库位置猜测（仅用于「第一次打开、还没有任何设置」的场景）
    static let defaultRepoGuess = "/Users/sangyu/develop/Pink_House"
}
