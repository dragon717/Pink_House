//
//  OpsCloudSyncView.swift
//  PinkHouseOps
//
//  云端发布的**编排层**（`OpsCloudSyncModel`，单例）。
//  名字里还留着 View 是历史原因：2026-10-07 起「云端同步」面板已整块删除 ——
//  发布是**一键**的（工具栏「云端更新」/ 向导 S5「发布整个系列」），
//  环境与凭证在 设置（Cmd+,，`OpsSettingsView`）里配置。
//
//  ## 它补的是什么洞（2026-09-28 实测的根因）
//
//  在此之前本 App 与 CloudKit 之间**没有任何一条通路**：
//
//    · 向导 S5 的「提交」只写本机草稿，界面上写着「交给受控发布器」，
//      但导出待发布包的入口随 09-27 的分区清理一起消失了（服务层还在）；
//    · 受控发布器（`OpsPublisherBridge` + `ops_publish_bridge.py`）已经写好，
//      却没有任何界面调它 —— 于是 CloudKit 发布头自 09-25 起纹丝未动；
//    · 「读取线上基线」这条只读模式同样只在 CLI 里存在，App 里看不到线上有什么。
//
//  ## 硬约束（与既有一致）
//
//    · App **不直连** CloudKit：发布/回读全部经受控发布器（方案 §5.2）；
//    · 界面不能拼命令行：只有 `--mode` 与 `--request` 两个业务参数，
//      业务内容写进**请求文件**（`ShopCatalogPublishRequest`）；
//    · 上架状态只认回执里的**回读确认**，绝不显示虚假的「已上架」；
//    · 失败必须可见：每次运行的完整输出落到 `bridge/logs/<runID>.log`，
//      失败提示（悬浮框 / 草稿箱）直接给日志文件路径。
//
//  ## 沙盒三关（缺一不可；自检结果现在显示在 设置 里）
//
//    ① 仓库目录要用户授权（发布脚本在仓库里）；
//    ② 解释器要能用（`cryptography` 只在仓库内 `.venv` 里）；
//    ③ 凭证：子进程继承 App 沙盒，**读不到登录钥匙串**，
//       所以必须有一份凭证 JSON 放在 App 容器内，由环境变量交给子进程。
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MemberImportVisibility：`@Published` 的 `init(wrappedValue:)` 由 Combine 提供，
// 少了这一行会连带报「ObservableObject 不合规」——那个报错看不出真正原因。
import Combine

// MemberImportVisibility：用到哪些类型就在本文件里显式 import 哪些。
import PinkHouseOpsCore
import SharedCatalog

// MARK: - 编排层

/// 一次「受控发布」调用的判定结果。
///
/// 只有两种结局：**回读确认过**（`.confirmed(releaseSeq:)`）与「其余一切」（`.failed(reason)`）。
/// 「结果待确认」也落在 `.failed` 里 —— 按项目口径它绝不能被说成成功，
/// 原因文案里会带上桥接器的结论名（如「结果待确认」），调用方原样透传。
enum OpsPublishInvocationResult: Equatable {
    /// `dryRun == false` 且回执 `readBackConfirmed == true`：云端与公共库都确认了。
    case confirmed(releaseSeq: Int)
    /// 没能确认成功。`reason` 带可定位来源（自检项 / 导出错误 / 桥接器结论与退出码）。
    case failed(String)
}

/// 云端同步的编排与状态。
///
/// 刻意做成**单例**：工具栏与向导 S5 都要能打开同一个面板，
/// 而两边各自 `@State` 一份会让「线上基线」在两处显示不一样
/// （那正是本项目反复吃亏的「两处真相」）。
@MainActor
final class OpsCloudSyncModel: ObservableObject {

    static let shared = OpsCloudSyncModel()

    // MARK: 设置

    @Published var settings: OpsBridgeSettings {
        didSet { persistSettings() }
    }
    /// 目标环境。**它是下面这些运行态状态的作用域**，切换时必须清空它们
    /// （见 `resetEnvironmentScopedState(from:)`）—— 否则会拿着一个环境的发布号
    /// 去发另一个环境，而整个过程不会有任何一处报错。
    @Published var targetEnvironment: ShopCatalogPublishTargetEnvironment = .development {
        didSet {
            guard oldValue != targetEnvironment else { return }
            UserDefaults.standard.set(targetEnvironment.rawValue, forKey: "ops.cloud.target_environment")
            resetEnvironmentScopedState(from: oldValue)
        }
    }

    // MARK: 运行态

    @Published private(set) var isRunning = false
    @Published var isSyncing = false
    @Published var isPromotingEnvironment = false
    @Published var syncReport: OpsSyncReport?
    var savedEditorProgress: ((ShopCatalogPublishEvent, OpsBridgeMode, ShopCatalogPublishTargetEnvironment) -> Void)?
    var syncEnvironmentGeneration: Int { environmentGeneration }
    @Published private(set) var runningMode: OpsBridgeMode?
    @Published private(set) var operationProgress: OpsDataSyncProgress?
    @Published private(set) var logLines: [String] = []
    @Published private(set) var onlineHead: ShopCatalogOnlineHead?
    @Published private(set) var outcome: ShopCatalogPublishOutcome?
    @Published private(set) var outcomeMessage: String?
    /// 这次失败**原样重试是安全的**吗（桥接器的 `retryable`）。
    ///
    /// 刻意的区分：网络抖动属于「重试即可」，而被拒绝 / 校验未通过属于「改了再来」。
    /// 把两者都说成「失败了」，运营就只能靠猜。发布模式下这个值恒为 false ——
    /// 请求可能已经落到线上，这时正确的动作是**结果查询**，不是重发（R09）。
    @Published private(set) var outcomeRetryable = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastReceiptSeq: Int?
    @Published private(set) var lastReceiptConfirmed: Bool = false
    /// 最近一次拉回的线上目录（**只读**产物：落盘路径 + 条数摘要）
    @Published private(set) var pulledCatalog: OpsPulledCatalog?
    /// 最近一次从远端下载的媒体（`fetchMedia` 模式；nil = 这次没跑 / 没拿到目录）。
    ///
    /// ⚠️ nil **不等于**「下载了 0 张」：桥接器没给目录通常意味着它没跑到那一步。
    /// 明细（`OpsFetchedMedia`）从 `fetch-manifest.json` 读，不在事件流里重复一遍。
    @Published private(set) var fetchedMedia: OpsFetchedMedia?
    /// 最近一次落盘的运行日志（`bridge/logs/latest.log`）。
    ///
    /// ## 为什么日志必须落盘（2026-09-29）
    ///
    /// 在这之前，桥接器的输出**只活在内存里**：`logLines` 上限 60 行、关掉面板
    /// 或重启 App 就没了，而且那段红色报错在旧写法里连选中都做不到。
    /// 结果就是「出了问题但拿不出日志」—— 现场只能截图，读的人只能靠放大截图认字
    /// （我自己就这么干过）。日志是排查的**唯一凭据**，它不该是一次性的 UI 状态。
    ///
    /// ## 落盘发生在模型里，不在视图里（2026-10-07 修正）
    ///
    /// 早先的口径写着「日志落盘只在视图层（`OpsCloudSyncView.persistLog`）」，
    /// 那是**错的**：`persistLog` 由 `perform` 调用，两者都在本模型内 ——
    /// 谁发起桥接调用都会落盘（向导 S5、探针、面板都一样）。
    /// 实测证据：容器内 `bridge/logs/` 里既有面板的日志，也有 S5 触发的
    /// `20261007-162258-publish.log`。别再按旧口径去「补视图层调用」。
    @Published private(set) var logFileURL: URL?
    /// 本次运行**专属**的日志文件（`bridge/logs/<runID>.log`）。
    ///
    /// `logFileURL` 是会被下一次覆盖的 `latest.log`；排查要给的是**这一次的**文件，
    /// 否则「把日志交给 Agent 修」时拿到的可能是另一次运行。失败提示里显示的是它。
    @Published private(set) var lastRunLogURL: URL?

    private var environmentGeneration = 0
    private static let logLimit = 60

    /// 本次运行的**完整**日志（不受 `logLimit` 截断），落盘与复制都用它。
    private var runLog: [String] = []
    private var operationLog: OpsOperationLog?
    private var runEnvironment: ShopCatalogPublishTargetEnvironment?
    private var runBridgeResult: OpsBridgeRunResult?
    private var activeBridgeRunID: String?

    /// 运行 ID 的时间部分（也是日志文件名）。用 POSIX locale 固定 24 小时制，
    /// 免得用户在「中文 + 12 小时制」下拿到 `09-29-... PM` 这种没法排序的名字。
    private static let runIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static let logTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    init() {
        if let data = UserDefaults.standard.data(forKey: OpsBridgeSettings.defaultsKey),
           let loaded = try? JSONDecoder().decode(OpsBridgeSettings.self, from: data) {
            settings = loaded
        } else {
            settings = OpsBridgeSettings()
        }
        if let raw = UserDefaults.standard.string(forKey: "ops.cloud.target_environment"),
           let environment = ShopCatalogPublishTargetEnvironment(rawValue: raw) {
            targetEnvironment = environment
        }
    }

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: OpsBridgeSettings.defaultsKey)
    }

    // MARK: 自检

    /// 桥接器自检（空 = 就绪）。它会自己打开一次仓库授权。
    var diagnosis: [String] { settings.diagnosis() }

    /// 每个远端环境各自有没有凭证。**分环境展示**是刻意的：
    /// 只显示「有没有凭证」会让「Development 配好了、Production 没配」看起来像
    /// 「都配好了」，而那正是 401 最常出现的形态。
    var credentialStates: [OpsEnvironmentCredentialState] {
        [.development, .production].map { environment in
            OpsEnvironmentCredentialState(
                environment: environment,
                isConfigured: OpsPublisherBridge.existingCredentialFile(
                    environmentName: environment.rawValue) != nil)
        }
    }

    // MARK: 环境作用域状态

    /// 清空只对**某一个环境**成立的运行态。
    ///
    /// ## 为什么必须清空（2026-09-28）
    ///
    /// 线上发布号、拉回的目录内容、发布结论、回执——这四个都只在读到它们的那个
    /// 环境里有意义。切了环境还留着，界面会显示「线上发布号 seq 1」，
    /// 而发布逻辑是「线上号 + 1」，于是一个 Development 的号会被写到 Production 上。
    /// 这类错误**没有任何一层会报错**：号是「合法」的、基线核对也是拿同环境的
    /// 那份 hash 在比，只有线上数据被悄悄换掉了。
    private func resetEnvironmentScopedState(
        from previous: ShopCatalogPublishTargetEnvironment
    ) {
        environmentGeneration += 1
        onlineHead = nil
        pulledCatalog = nil
        fetchedMedia = nil
        outcome = nil
        outcomeMessage = nil
        outcomeRetryable = false
        lastError = nil
        lastReceiptSeq = nil
        lastReceiptConfirmed = false
        append("⇄ 环境 \(previous.displayName) → \(targetEnvironment.displayName)："
            + "已清空上一个环境的线上发布号 / 发布结论"
            + "（它们只对原环境成立，请重新读取当前环境的线上基线）。")
    }

    var interpreterText: String {
        let access = settings.beginAuthorizedRepoRootScope()
        defer { access.stop() }
        guard let path = settings.resolvedPythonPath() else { return "未找到可用解释器" }
        return path
    }

    // MARK: 目录

    /// 桥接器产物的根目录（全部落在 App 容器内：子进程继承沙盒，读得到这里）。
    var jobsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PinkHouseOps", isDirectory: true)
            .appendingPathComponent("bridge", isDirectory: true)
    }

    private func jobDirectory(_ id: String) -> URL {
        jobsDirectory.appendingPathComponent("\(id)-\(UUID().uuidString)", isDirectory: true)
    }

    /// 运行日志的落盘目录（`bridge/logs/`）。与 `bridge/<jobID>/` 平级：
    /// 请求文件是**给子进程读的**，日志是**给人读的**，混在一起会互相干扰。
    private var logsDirectory: URL {
        jobsDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    // MARK: 仓库目录授权

    /// 让用户选择仓库目录，并保存 security-scoped bookmark。
    ///
    /// 为什么必须由用户选：沙盒 App 没有仓库目录的访问权，
    /// 而发布脚本就在那里。系统只在用户通过面板选择时才授予持久化扩展。
    func chooseRepoRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择仓库目录"
        panel.message = "请选择 Pink_House 仓库根目录（发布脚本在 tools/time_hall/publication 下）。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.repoRootPath = url.path
        settings.repoRootBookmark = OpsPublisherBridge.makeBookmark(for: url)
    }

    /// 把用户选的凭证 JSON 拷进 App 容器（子进程唯一能读到的位置），
    /// **按当前选中的环境命名**。
    ///
    /// 只拷文件，不读内容、不打印内容 —— 私钥永远不进界面与日志。
    func importCredentialFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "选择凭证 JSON"
        panel.message = "请选择 \(targetEnvironment.displayName) 环境的 CloudKit 凭证 JSON"
            + "（含 keyID / privateKey / containerID）。"
            + "注意：s2s key 按环境注册，Development 的那一份打 Production 会 401。"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let target = OpsPublisherBridge.credentialFileURL(
            environmentName: targetEnvironment.rawValue)
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try Data(contentsOf: source).write(to: target, options: .atomic)
            append("✓ 已写入 \(targetEnvironment.displayName) 凭证：\(target.lastPathComponent)")
        } catch {
            lastError = "凭证文件拷贝到 App 容器失败：\(error.localizedDescription)"
        }
    }

    // MARK: 拉回线上目录（只读）

    /// 把线上那一版目录**拉回本机**（`--mode pull-catalog`，全程 `apply=False`，不写线上）。
    ///
    /// 2026-10-07 用户需求：同步要能双向 —— 远端有本地没有的拉下来、
    /// 本地有远端没有的传上去、本地删掉的在远端标记删除。这是第一步（拉回）。
    /// 拉回只生成目录文件；三步同步会自动合并无冲突字段，争议字段留给设置页确认。
    @discardableResult
    func pullCatalog() async -> OpsPulledCatalog? {
        guard await ensureReady(.pullCatalog) else { return nil }
        pulledCatalog = nil
        onlineHead = nil
        let directory = jobDirectory("pull-\(Int(Date().timeIntervalSince1970))")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            lastError = "创建工作目录失败：\(error.localizedDescription)"
            return nil
        }
        let request = makeRequest(
            requestID: "pull-\(UUID().uuidString)",
            jobID: "pull",
            releaseSeq: max(1, (onlineHead?.releaseSeq ?? 0)),
            archivePath: directory.appendingPathComponent("none.tar").path,
            input: directory.appendingPathComponent("input"),
            output: directory,
            receipt: directory.appendingPathComponent("receipt.json"),
            payloadHash: "pull-catalog")
        guard let requestURL = write(request, to: directory) else { return nil }

        var pulled: OpsPulledCatalog?
        await perform(mode: .pullCatalog, requestPath: requestURL) { [weak self] result in
            guard let self else { return }
            self.onlineHead = result.onlineHead
            guard result.exitCode == 0, result.outcome == .confirmed else {
                self.lastError = result.outcomeMessage ?? "拉回失败"
                return
            }
            pulled = OpsPulledCatalog.from(result: result, environment: self.targetEnvironment.rawValue)
            if pulled == nil {
                // 「拉不到」两种可能：线上确实没目录（正常），或事件字段对不上（缺陷）。
                // 不区分就等于把缺陷说成正常 —— 两种都写进提示里。
                self.lastError = "没拿到线上目录（exitCode=\(result.exitCode)）："
                    + (result.outcomeMessage ?? "没有 catalog 事件")
                    + "。若该环境线上确实没有商店目录，这是正常结果；"
                    + "否则要查 `pulledCatalogPath` 的字段口径。"
            }
        }
        pulledCatalog = pulled
        return pulled
    }

    // MARK: 下载远端图片字节（只读）

    /// 把远端有、本机没有的图片**下载到本机**（`--mode fetch-media`，全程只读）。
    ///
    /// 这是双向同步的另一半：`publish` 是「上传」（本地 → 远端），这里是「下载」
    /// （远端 → 本地）。两半共用同一套内容寻址，所以：
    ///   · 已经在本机的不会重复下载（调用方按 `stagedMediaKeys` 过滤）；
    ///   · 下载下来的文件名就是内容摘要，可以直接进 staging
    ///     （`OpsWorkspace.absorbDownloadedMedia(from:)`）。
    ///
    /// - Parameter hashes: 要下载的内容摘要（64 位 hex）。空数组**不跑** ——
    ///   桥接器会把它当成「调用方没列清单」并拒绝，而那是调用方的 bug，
    ///   不该靠一次注定失败的子进程去发现。
    /// - Returns: 下载明细；nil = 没跑成（原因在 `lastError`）。
    @discardableResult
    func fetchMedia(hashes: [String], environment: ShopCatalogPublishTargetEnvironment? = nil) async -> OpsFetchedMedia? {
        guard !hashes.isEmpty else {
            lastError = "没有要下载的图片：本机已经齐了（或目录里没有 `thmedia:` 引用）。"
            return nil
        }
        let sourceEnvironment = environment ?? targetEnvironment
        guard await ensureReady(.fetchMedia, environment: sourceEnvironment) else { return nil }
        let directory = jobDirectory("fetch-\(Int(Date().timeIntervalSince1970))")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            lastError = "创建工作目录失败：\(error.localizedDescription)"
            return nil
        }
        var request = makeRequest(
            requestID: "fetch-\(UUID().uuidString)",
            jobID: "fetch",
            releaseSeq: max(1, (onlineHead?.releaseSeq ?? 0)),
            archivePath: directory.appendingPathComponent("none.tar").path,
            input: directory.appendingPathComponent("input"),
            output: directory.appendingPathComponent("images"),
            receipt: directory.appendingPathComponent("receipt.json"),
            payloadHash: "fetch-media")
        request.mediaHashes = hashes
        request.targetEnvironment = sourceEnvironment
        guard let requestURL = write(request, to: directory) else { return nil }

        var fetched: OpsFetchedMedia?
        let selectedEnvironment = targetEnvironment.rawValue
        let requestedEnvironment = sourceEnvironment.rawValue
        let requestedGeneration = environmentGeneration
        await perform(mode: .fetchMedia, requestPath: requestURL, environment: sourceEnvironment) { [weak self] result in
            guard let self else { return }
            fetched = OpsFetchedMedia.from(result: result, environment: requestedEnvironment)
            if fetched == nil {
                self.lastError = "没拿到下载结果（exitCode=\(result.exitCode)）："
                    + (result.outcomeMessage ?? "没有 media 事件 / 读不到 fetch-manifest.json")
            }
        }
        // 超时/取消不会产生最终 media 事件，但逐张落盘的原子清单仍可恢复。
        if fetched == nil, targetEnvironment.rawValue == selectedEnvironment,
           environmentGeneration == requestedGeneration {
            fetched = OpsFetchedMedia.load(directory: request.outputDirectory, environment: requestedEnvironment)
        }
        fetchedMedia = fetched
        return fetched
    }

    // MARK: 一键发布（云端更新 / 系列发布共用）

    /// 工具栏与系列发布共用三步同步；上传受阻仍保留下载和本地合并结果。
    func publishNow(workspace: OpsWorkspace) async -> OpsPublishInvocationResult {
        await synchronize(workspace: workspace)
    }

    /// 导出待发布整包 → 写冻结请求 → 交受控发布器。
    ///
    /// 顺序不能改：**先**由 App 复校验并导出（缺图会在这里硬失败，不会带上残缺产物），
    /// **再**写请求文件（请求文件就是唯一的「提交」动作）。
    ///
    /// ⚠️ 面板与「演练」开关已于 2026-10-07 随面板一起删除：本方法**恒为真实发布**。
    /// - Returns: 回执回读确认过才返回 `.confirmed(releaseSeq:)`；
    ///   其余一切（自检不过 / 导出失败 / 桥接器拒绝 / 结果待确认）都是 `.failed(原因)`。
    @discardableResult
    func publish(workspace: OpsWorkspace) async -> OpsPublishInvocationResult {
        guard await ensureReady(.publish) else {
            return .failed(lastError ?? "受控发布器还没准备好（自检未通过）。")
        }
        guard workspace.isCorrupted == false else {
            failBeforeBridge("草稿处于只读隔离状态，不能发布。请先「另存为新草稿」。", mode: .publish)
            return .failed(lastError ?? "草稿处于只读隔离状态。")
        }
        guard let head = onlineHead else {
            failBeforeBridge("还不知道线上当前版本：请先点「读取线上基线」，"
                + "发布号必须严格大于线上（R07：不能拿一份不知道基于哪一版的整包去覆盖线上）。",
                mode: .publish)
            return .failed(lastError ?? "还不知道线上当前版本。")
        }
        // 发布号是**按环境**编号的：拿 Development 的号发 Production 会覆盖掉
        // 另一个环境的发布头，而这一步之前没有任何一层会拦。
        guard head.environment == targetEnvironment.rawValue else {
            failBeforeBridge("读到的线上基线属于 \(head.environment)，"
                + "与当前目标环境 \(targetEnvironment.rawValue) 不一致。"
                + "请先重新读取当前环境的线上基线（切换环境会自动清空上一次的结果）。",
                mode: .publish)
            return .failed(lastError ?? "线上基线与目标环境不一致。")
        }
        let seq = head.releaseSeq + 1

        let directory = jobDirectory("publish-seq\(seq)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            failBeforeBridge("创建工作目录失败：\(error.localizedDescription)", mode: .publish)
            return .failed(lastError ?? "创建工作目录失败。")
        }

        // ---- 1) 导出待发布整包（服务层自带复校验 + 缺图硬报错）
        let archive: Data
        do {
            archive = try workspace.makePublicationArchive(
                targetEnvironmentName: targetEnvironment.displayName)
        } catch {
            failBeforeBridge("生成待发布整包失败：\(error.localizedDescription)", mode: .publish)
            return .failed(lastError ?? "生成待发布整包失败。")
        }
        let archiveURL = directory.appendingPathComponent("release.tar")
        do {
            try archive.write(to: archiveURL, options: .atomic)
        } catch {
            failBeforeBridge("待发布整包落盘失败：\(error.localizedDescription)", mode: .publish)
            return .failed(lastError ?? "待发布整包落盘失败。")
        }
        let payloadHash = ShopCatalogSyncProtocol.sha256Hex(archive)

        // ---- 2) 冻结请求（App 唯一的「提交」动作）
        let revision = workspace.currentRevision
        let publishedCatalog = workspace.catalog
        let draftID = workspace.draft?.id ?? "draft"
        let request = ShopCatalogPublishRequest(
            requestID: ShopCatalogPublishRequestKey.make(
                draftID: draftID,
                draftRevision: revision,
                payloadHash: payloadHash,
                targetEnvironment: targetEnvironment,
                releaseSeq: seq),
            jobID: "job-\(UUID().uuidString)",
            draftID: draftID,
            draftRevision: revision,
            baseReleaseSeq: workspace.baseReleaseSeq,
            baseRootIndexHash: workspace.baseRootIndexHash,
            targetEnvironment: targetEnvironment,
            releaseSeq: seq,
            inputDirectory: directory.appendingPathComponent("input").path,
            archivePath: archiveURL.path,
            outputDirectory: directory.appendingPathComponent("output").path,
            receiptPath: directory.appendingPathComponent("receipt.json").path,
            filesystemRoot: nil,
            dryRun: false,
            payloadHash: payloadHash)
        guard let requestURL = write(request, to: directory) else {
            return .failed(lastError ?? "写请求文件失败。")
        }

        // ---- 3) 交受控发布器
        var localReceiptSaved = false
        await perform(mode: .publish, requestPath: requestURL) { [weak self] result in
            guard let self else { return }
            self.outcome = result.outcome
            self.outcomeMessage = result.outcomeMessage ?? result.lastDisplayLine
            self.outcomeRetryable = result.outcomeRetryable
            self.onlineHead = result.onlineHead ?? self.onlineHead
            let receipt = result.receipt
            self.lastReceiptSeq = receipt?.releaseSeq ?? result.artifactReleaseSeq
            self.lastReceiptConfirmed = receipt?.readBackConfirmed ?? false
            // 只有「真的写了 + 回读确认过」才记一次已发布（R09：不承诺、不谎报）
            if let receipt, receipt.readBackConfirmed == true,
               let seq = receipt.releaseSeq {
                guard workspace.draft?.id == draftID else {
                    self.lastError = "发布已完成，但工作区已切换，未修改新草稿的基线。"
                    return
                }
                localReceiptSaved = workspace.recordConfirmedPublish(
                    releaseSeq: seq,
                    rootIndexHash: receipt.rootIndexHash,
                    environment: self.targetEnvironment.rawValue,
                    revision: revision,
                    publishedCatalog: publishedCatalog)
                if !localReceiptSaved { self.lastError = workspace.lastError }
            }
        }

        // ---- 判定：只有「真实发布 + 结论 confirmed + 回读确认」算成功
        if outcome == .confirmed, lastReceiptConfirmed, let seq = lastReceiptSeq {
            guard localReceiptSaved else {
                return .failed(lastError ?? "云端已发布，本地回执尚未保存；请先查看结果。")
            }
            return .confirmed(releaseSeq: seq)
        }
        // 其余一律失败，原因 = 结论名 + 桥接器文案 + 内部错误（可定位的一条）。
        // 超时 / 取消走 perform 的 catch（没有 outcome 事件），此时 lastError 一定有值。
        var reasonParts: [String] = []
        if let outcome { reasonParts.append(outcome.displayName) }
        if let message = outcomeMessage { reasonParts.append(message) }
        if let error = lastError, !reasonParts.contains(error) { reasonParts.append(error) }
        let reason = reasonParts.isEmpty
            ? "受控发布器没有返回结论（退出后无任何事件）。"
            : reasonParts.joined(separator: "：")
        return .failed(reason)
    }

    // MARK: 内部

    /// 三关自检：仓库目录 / 解释器 / 凭证。不通过就不跑，且每一条单独说明。
    private func ensureReady(_ mode: OpsBridgeMode,
                             environment: ShopCatalogPublishTargetEnvironment? = nil) async -> Bool {
        guard !isRunning else { return false }
        let environment = environment ?? targetEnvironment
        runEnvironment = environment
        runBridgeResult = nil
        let problems = diagnosis
        if !problems.isEmpty {
            failBeforeBridge("受控发布器还没准备好：" + problems.joined(separator: " "), mode: mode)
            return false
        }
        if OpsPublisherBridge.existingCredentialFile(environmentName: environment.rawValue) == nil {
            failBeforeBridge("容器内没有 \(environment.displayName) 的 CloudKit 凭证："
                + "子进程继承 App 沙盒，读不到登录钥匙串，只能靠容器里的这份文件。"
                + "请先点「选择凭证 JSON…」把它放进 App 容器。", mode: mode)
            return false
        }
        if let summary = OpsPublisherBridge.credentialSummary(environmentName: environment.rawValue),
           summary.declaredEnvironmentMatches == false {
            failBeforeBridge("这份凭证自己声明的是 \(summary.declaredEnvironment ?? "（未知）")，"
                + "与目标环境 \(environment.displayName) 不一致。"
                + "CloudKit 的 s2s key 按环境注册，混用只会 401 —— 请导入对应环境的凭证。",
                mode: mode)
            return false
        }
        return true
    }

    private func makeRequest(
        requestID: String,
        jobID: String,
        releaseSeq: Int,
        archivePath: String,
        input: URL,
        output: URL,
        receipt: URL,
        payloadHash: String
    ) -> ShopCatalogPublishRequest {
        ShopCatalogPublishRequest(
            requestID: requestID,
            jobID: jobID,
            draftID: "ops",
            draftRevision: 0,
            baseReleaseSeq: nil,
            baseRootIndexHash: nil,
            baselineAcknowledged: false,
            targetEnvironment: targetEnvironment,
            releaseSeq: releaseSeq,
            inputDirectory: input.path,
            archivePath: archivePath,
            outputDirectory: output.path,
            receiptPath: receipt.path,
            filesystemRoot: nil,
            dryRun: true,
            payloadHash: payloadHash)
    }

    private func write(_ request: ShopCatalogPublishRequest, to directory: URL) -> URL? {
        let url = directory.appendingPathComponent("request.json")
        do {
            try request.encoded().write(to: url, options: .atomic)
            return url
        } catch {
            failBeforeBridge("写请求文件失败：\(error.localizedDescription)", mode: .publish)
            return nil
        }
    }

    /// 跨环境任务显式绑定请求环境，不切换日常发布设置、不写其缓存基线。
    func runEnvironmentBridge(mode: OpsBridgeMode, request: ShopCatalogPublishRequest,
                              requestURL: URL) async -> OpsBridgeRunResult? {
        runEnvironment = request.targetEnvironment
        guard await ensureReady(mode, environment: request.targetEnvironment) else { return nil }
        do {
            try FileManager.default.createDirectory(at: requestURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try request.encoded().write(to: requestURL, options: .atomic)
        } catch {
            failBeforeBridge("环境同步请求保存失败：\(error.localizedDescription)", mode: mode)
            return nil
        }
        var result: OpsBridgeRunResult?
        await perform(mode: mode, requestPath: requestURL, environment: request.targetEnvironment) {
            result = $0
        }
        return result
    }

    /// 跑一次桥接调用。**在后台线程阻塞执行**（`OpsPublisherBridge.run` 是同步的）。
    private func perform(
        mode: OpsBridgeMode,
        requestPath: URL,
        environment: ShopCatalogPublishTargetEnvironment? = nil,
        interpret: @escaping @MainActor (OpsBridgeRunResult) -> Void
    ) async {
        guard !isRunning else { return }
        isRunning = true
        runningMode = mode
        outcome = nil
        outcomeMessage = nil
        outcomeRetryable = false
        lastError = nil
        // 每次运行从干净的一份开始：`runLog` 是**按运行**归属的，留着上一次的行
        // 会让落盘的日志里混进两次运行的输出（跨环境时尤其误导）。
        runLog = []
        runBridgeResult = nil
        let runID = "\(Self.runIDFormatter.string(from: Date()))-\(mode.rawValue)-\(UUID().uuidString.prefix(8))"
        activeBridgeRunID = runID
        defer { activeBridgeRunID = nil }
        let selectedEnvironment = environment ?? targetEnvironment
        runEnvironment = selectedEnvironment
        append("▶ \(mode.displayName)（\(selectedEnvironment.displayName)）")

        let bridge = OpsPublisherBridge(settings: settings)
        let environmentName = selectedEnvironment.rawValue
        let generation = environmentGeneration
        do {
            let result = try await Task.detached(priority: .userInitiated) { () throws -> OpsBridgeRunResult in
                try bridge.run(
                    mode: mode,
                    requestPath: requestPath,
                    environmentName: environmentName
                ) { event in
                    Task { @MainActor in
                        guard self.environmentGeneration == generation,
                              self.activeBridgeRunID == runID else { return }
                        let previous = self.operationProgress
                        self.operationProgress?.receive(event, mode: mode, environment: selectedEnvironment)
                        if event.type == "progress", self.operationProgress != previous,
                           let progress = self.operationProgress {
                            self.append(progress.title + (progress.countText.map { " · " + $0 } ?? ""))
                        }
                        self.receiveSyncProgress(event, mode: mode)
                        self.savedEditorProgress?(event, mode, selectedEnvironment)
                        if let line = event.displayLine {
                            self.append(event.type == "stage" ? (event.message ?? line) : line)
                        }
                    }
                }
            }.value
            append("退出码 \(result.exitCode)"
                + (result.outcome.map { " · 结论 \($0.rawValue)" } ?? ""))
            runBridgeResult = result
            guard (environment != nil || targetEnvironment.rawValue == environmentName),
                  environmentGeneration == generation else {
                lastError = "任务在 \(environmentName) 执行，期间目标环境已切换；请查询原环境结果。"
                isRunning = false
                runningMode = nil
                persistLog(runID: runID, mode: mode)
                return
            }
            interpret(result)
        } catch {
            // 超时 / 取消不是「没发生」：文案里有「先查询再决定」的要求。
            let detail = (error as? OpsBridgeError)?.diagnostic(for: mode) ?? error.localizedDescription
            lastError = detail
            append("✖ \(detail)")
        }
        isRunning = false
        runningMode = nil
        // 落盘放在最后：此时 `interpret(result)` 已经写好了结论、回执号与失败原因，
        // 日志头部才能带上它们（否则文件里只有裸输出，拿到的人也判断不了该不该重试）。
        persistLog(runID: runID, mode: mode)
    }

    private func append(_ line: String) {
        logLines.append(line)
        if logLines.count > Self.logLimit {
            logLines.removeFirst(logLines.count - Self.logLimit)
        }
        runLog.append(line)
        // 正在运行时同一日志也能读取；完整事件和结论仍在桥接结束时追加。
        appendOperationLog(line)
    }

    // MARK: 日志（复制 / 落盘）

    /// 可以直接粘进聊天、Issue 或邮件里的完整日志文本。
    ///
    /// ## 为什么头部不能省
    ///
    /// 只贴一句「退出码 6」没人能判断是网络、凭证还是数据；而「该不该原样重试」
    /// 恰恰取决于环境、模式与有没有写过线上。所以头部把这些**判定所需的最小事实**
    /// 固定带上，正文才是桥接器的原始输出。
    func copyableLogText(runID: String? = nil, mode: OpsBridgeMode? = nil) -> String {
        var lines: [String] = []
        lines.append("# PinkHouseOps 云端同步 · 受控发布器输出")
        lines.append("导出时间：\(Self.logTimeFormatter.string(from: Date()))")
        let environment = runEnvironment ?? targetEnvironment
        lines.append("目标环境：\(environment.rawValue)（\(environment.displayName)）")
        if let runID { lines.append("本次运行：\(runID)") }
        if let result = runBridgeResult { lines.append("退出码：\(result.exitCode)") }
        if let mode { lines.append("运行模式：\(mode.rawValue)") }
        if let head = runBridgeResult?.onlineHead ?? (isPromotingEnvironment ? nil : onlineHead),
           head.environment == environment.rawValue {
            lines.append("线上发布号：seq \(head.releaseSeq)"
                + (head.rootIndexHash.map { " · 根清单摘要 \($0.prefix(12))…" } ?? ""))
        }
        let receiptSeq = isPromotingEnvironment ? runBridgeResult?.receipt?.releaseSeq : lastReceiptSeq
        let receiptConfirmed = isPromotingEnvironment
            ? runBridgeResult?.receipt?.readBackConfirmed == true : lastReceiptConfirmed
        if let seq = receiptSeq {
            lines.append("回执发布号：\(seq)"
                + (receiptConfirmed ? "（已回读确认）" : "（未回读确认）"))
        }
        if let message = runBridgeResult?.outcomeMessage ?? outcomeMessage { lines.append("结论文案：\(message)") }
        if let error = lastError { lines.append("✖ 错误：\(error)") }
        // 日志文件路径必须带在头部：排查的人（以及接手修的 Agent）第一件事
        // 就是找到**这一次的**原始输出，而不是只看到一句结论文案。
        let diagnosticURL = operationLog?.url
            ?? runID.map { logsDirectory.appendingPathComponent("\($0).log") } ?? lastRunLogURL
        if let url = diagnosticURL { lines.append("日志文件：\(url.path)") }
        lines.append("--- 桥接器输出 ---")
        lines.append(contentsOf: runBridgeResult?.events.compactMap(\.displayLine)
            ?? (runLog.isEmpty ? logLines : runLog))
        if let result = runBridgeResult {
            lines.append("--- 事件明细 ---")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            lines.append(contentsOf: result.events.compactMap {
                (try? encoder.encode($0)).flatMap { String(data: $0, encoding: .utf8) }
            })
            if !result.nonJSONLines.isEmpty {
                lines.append("--- 非 JSON 输出 ---")
                lines.append(contentsOf: result.nonJSONLines)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 把本次运行的日志落成文件：`bridge/logs/<runID>.log` + 覆盖 `latest.log`。
    ///
    /// 写失败**刻意静默**：一次同步已经跑完了，不该因为「日志没写成」再报一个错。
    /// 但此时 `logFileURL` 保持 nil，界面上的按钮会是灰的 —— 这一点要能看出来。
    @discardableResult
    func beginOperationLog(_ title: String) -> Bool {
        guard operationLog == nil else { return false }
        operationLog = try? OpsOperationLog(directory: logsDirectory, title: title)
        operationProgress = OpsDataSyncProgress(title: "准备连接…")
        logFileURL = operationLog?.url
        lastRunLogURL = operationLog?.url
        return true
    }

    func appendOperationLog(_ text: String) { try? operationLog?.append(text) }

    func updateOperationProgress(_ title: String) {
        operationProgress?.advance(to: title)
        appendOperationLog(title)
    }

    func finishOperationLog(_ result: String) {
        try? operationLog?.finish(result)
        logFileURL = operationLog?.url
        lastRunLogURL = operationLog?.url
        operationLog = nil
    }

    private func persistLog(runID: String, mode: OpsBridgeMode) {
        if let operationLog {
            try? operationLog.append(copyableLogText(runID: runID, mode: mode))
            logFileURL = operationLog.url
            lastRunLogURL = operationLog.url
            return
        }
        let directory = logsDirectory
        let manager = FileManager.default
        guard (try? manager.createDirectory(
            at: directory, withIntermediateDirectories: true)) != nil else { return }
        let text = copyableLogText(runID: runID, mode: mode)
        guard let data = text.data(using: .utf8) else { return }
        let stamped = directory.appendingPathComponent("\(runID).log")
        try? data.write(to: stamped, options: .atomic)
        // 先记本次专属文件：即使 `latest.log` 没写成，排查的人至少拿得到这一次的路径。
        lastRunLogURL = stamped
        let latest = directory.appendingPathComponent("latest.log")
        guard (try? data.write(to: latest, options: .atomic)) != nil else { return }
        logFileURL = latest
    }

    /// 记一次**没走到桥接器**的失败，并把它落盘。
    ///
    /// ## 为什么这条路径必须单独照顾（2026-09-29）
    ///
    /// `perform` 里的失败会自动落盘，但「发布」有多条**在桥接器之前就返回**的早退路径：
    /// 门禁不过（草稿只读 / 没有线上基线 / 环境对不上）、导出整包失败、请求文件写不下去。
    /// 旧写法只在 `perform` 里落盘 —— 结果**恰恰是最需要日志的那一次失败没有日志**：
    /// 现场卡住的正是「导出整包失败：发布前校验未通过（560 条）」，而它一个文件都没留下。
    private func failBeforeBridge(_ message: String, mode: OpsBridgeMode) {
        runBridgeResult = nil
        runLog = ["✖ " + message]
        lastError = message
        persistLog(
            runID: "\(Self.runIDFormatter.string(from: Date()))-\(mode.rawValue)-preflight",
            mode: mode)
    }
}

/// 某个环境的凭证配置状态（自检卡片里按环境逐条列出）。
struct OpsEnvironmentCredentialState: Identifiable {
    let environment: ShopCatalogPublishTargetEnvironment
    let isConfigured: Bool

    var id: String { environment.rawValue }
}
