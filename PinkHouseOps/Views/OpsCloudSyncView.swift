//
//  OpsCloudSyncView.swift
//  PinkHouseOps
//
//  「云端同步」面板：让 Mac 端**真的能从云端下载、也能上传到云端**。
//
//  ## 它补的是什么洞（2026-09-28 实测的根因）
//
//  在此之前本 App 与 CloudKit 之间**没有任何一条通路**：
//
//    · 向导 S5 的「提交」只写本机草稿，界面上写着「交给受控发布器」，
//      但导出待发布包的入口随 09-27 的分区清理一起消失了（服务层还在）；
//    · 受控发布器（`OpsPublisherBridge` + `ops_publish_bridge.py`）已经写好，
//      却没有任何界面调它 —— 于是 CloudKit 发布头自 09-25 起纹丝未动；
//    · 「读取线上基线 / 从线上拉回基线」两条只读模式同样只在 CLI 里存在，
//      App 里看不到线上有什么，也就永远看不到 iOS 端上传的内容。
//
//  本文件只做一件事：把**已有的服务层与受控发布器接上界面**，
//  不重写发布算法、不碰凭证内容、不新增第二条发布格式。
//
//  ## 硬约束（与既有一致）
//
//    · App **不直连** CloudKit：发布/回读全部经受控发布器（方案 §5.2）；
//    · 界面不能拼命令行：只有 `--mode` 与 `--request` 两个业务参数，
//      业务内容写进**请求文件**（`ShopCatalogPublishRequest`）；
//    · 上架状态只认回执里的**回读确认**，绝不显示虚假的「已上架」；
//    · 失败必须可见：桥接器的每一条事件都落到日志区，结论按退出码给出。
//
//  ## 沙盒三关（缺一不可，界面上要分别说清楚）
//
//    ① 仓库目录要用户授权（发布脚本在仓库里）；
//    ② 解释器要能用（`cryptography` 只在仓库内 `.venv` 里）；
//    ③ 凭证：子进程继承 App 沙盒，**读不到登录钥匙串**，
//       所以必须有一份凭证 JSON 放在 App 容器内，由环境变量交给子进程。
//    这三关的自检结果就是下面「桥接器自检」那张卡片，不合并、不笼统说「环境有问题」。
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
            resetEnvironmentScopedState(from: oldValue)
        }
    }

    @Published var dryRun: Bool = true
    /// 运营是否显式确认「我知道线上变了，仍按本基线发布」（R07 的唯一出口）。
    @Published var baselineAcknowledged: Bool = false

    // MARK: 运行态

    @Published private(set) var isRunning = false
    @Published private(set) var runningMode: OpsBridgeMode?
    @Published private(set) var logLines: [String] = []
    @Published private(set) var onlineHead: ShopCatalogOnlineHead?
    @Published private(set) var pulled: OpsPulledCatalog?
    /// 上一次「拉回目录」**失败**的原因（成功时为 nil）。
    ///
    /// 为什么要单独存一份：下载卡片原先写成 `if let pulled` —— 拉回失败时那张卡片
    /// **一个字都不显示**，运营点完按钮像没反应一样，唯一的线索浮在上传卡片的结果区里。
    /// 「点了没反应」和「报错了」必须区分开，否则现场只会得到一句「还是没拉下来」。
    @Published private(set) var pullFailure: String?
    /// 这次拉回失败是不是**原样重试即可**（桥接器的 `retryable`）。
    @Published private(set) var pullFailureRetryable = false
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
    /// 最近一次落盘的运行日志（`bridge/logs/latest.log`）。
    ///
    /// ## 为什么日志必须落盘（2026-09-29）
    ///
    /// 在这之前，桥接器的输出**只活在内存里**：`logLines` 上限 60 行、关掉面板
    /// 或重启 App 就没了，而且那段红色报错在旧写法里连选中都做不到。
    /// 结果就是「出了问题但拿不出日志」—— 现场只能截图，读的人只能靠放大截图认字
    /// （我自己就这么干过）。日志是排查的**唯一凭据**，它不该是一次性的 UI 状态。
    @Published private(set) var logFileURL: URL?

    /// 面板是否展开（由工具栏或 S5 触发）
    @Published var showsSheet = false

    private static let logLimit = 60

    /// 本次运行的**完整**日志（不受 `logLimit` 截断），落盘与复制都用它。
    private var runLog: [String] = []

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
    }

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: OpsBridgeSettings.defaultsKey)
    }

    // MARK: 自检

    /// 桥接器自检（空 = 就绪）。它会自己打开一次仓库授权。
    var diagnosis: [String] { settings.diagnosis() }

    /// 当前环境的容器内凭证文件（存在才有值）。没有它，子进程在沙盒里读不到 Keychain。
    ///
    /// **按环境取**：CloudKit 的 s2s key 是按环境注册的，一份凭证不可能同时
    /// 对 Development 与 Production 有效。
    var credentialFileURL: URL? {
        OpsPublisherBridge.existingCredentialFile(environmentName: targetEnvironment.rawValue)
    }

    /// 当前环境的凭证摘要（只含 containerID / keyID，私钥永不进这里）
    var credentialSummary: OpsPublisherBridge.OpsCredentialSummary? {
        OpsPublisherBridge.credentialSummary(environmentName: targetEnvironment.rawValue)
    }

    var credentialText: String {
        guard let url = credentialFileURL else {
            return "未配置（约定位置："
                + "\(OpsPublisherBridge.credentialFileURL(environmentName: targetEnvironment.rawValue).path)）"
        }
        return "已配置：\(url.path)"
    }

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

    /// 当前环境缺凭证时的**分步指引**。
    ///
    /// 为什么不写一句「请配置凭证」就完事：Production 缺凭证的根因几乎总是
    /// 「只注册过 Development 的 s2s key」，而它的处置是**去 Console 再注册一个**，
    /// 不是「再把同一个文件选一次」——指引必须指向真正能解决问题的那个动作。
    var credentialGuidance: String {
        // 协议里只有 Development / Production 两个环境（本机演练已移除），
        // 所以按「是否 Production」分流，不需要再为第三个环境留分支。
        if targetEnvironment == .production {
            return "需要一份 **Production** 凭证 JSON。s2s key 是**按环境注册**的，"
                + "Development 那一份打 Production 只会 401，必须单独注册："
                + "CloudKit Console → 顶部环境切 **Production** → API Access → Server-to-Server Keys → 新建 key；"
                + "再确认 Schema 已从 Development **Deploy to Production**（否则记录类型根本不存在）。"
                + "三个字段同上，`containerID` 仍是 `iCloud.bugod2.ItemManager`。"
        }
        return "需要一份 **Development** 凭证 JSON（`keyID` / `privateKey` / `containerID`）："
            + "CloudKit Console → 环境切 Development → API Access → Server-to-Server Keys → "
            + "取 Key ID 与私钥 PEM，`containerID` 填 `iCloud.bugod2.ItemManager`。"
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
        onlineHead = nil
        pulled = nil
        pullFailure = nil
        pullFailureRetryable = false
        outcome = nil
        outcomeMessage = nil
        outcomeRetryable = false
        lastError = nil
        lastReceiptSeq = nil
        lastReceiptConfirmed = false
        // 「已知线上已变」是针对**那一版**的确认，换环境后它没有任何依据。
        baselineAcknowledged = false
        append("⇄ 环境 \(previous.displayName) → \(targetEnvironment.displayName)："
            + "已清空上一个环境的线上发布号 / 拉回内容 / 发布结论"
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
    private var jobsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PinkHouseOps", isDirectory: true)
            .appendingPathComponent("bridge", isDirectory: true)
    }

    private func jobDirectory(_ id: String) -> URL {
        jobsDirectory.appendingPathComponent(id, isDirectory: true)
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

    // MARK: 从 iOS 交接（不走云端的那条路）

    /// 导入 iOS「导出整包（含图片）」的产物。
    ///
    /// 这是**云端之外的第二条路**，而且是当前唯一能走通的一条：
    /// 线上发布头自 09-25 起停在 seq 1，iOS 的发布并没有切换它，
    /// 所以「从云端拉回」拿不到 iOS 上新内容 —— 只能靠整包交接。
    /// 图片会**按原文件名**进 staging，目录里的 `local:` 引用才不会悬空。
    func importHandoff(workspace: OpsWorkspace) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择整包"
        panel.message = "请选择 iOS「导出整包（含图片）」解出来的目录"
            + "（里面有 shop-catalog.json 与 images/），或直接选那个 shop-catalog.json。"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        lastError = nil
        append("⇢ 导入整包：\(url.lastPathComponent)")
        if let report = workspace.importHandoffPackage(from: url) {
            append("✓ \(report.summary)")
            if let missing = report.missingText {
                append("⚠️ \(missing)")
                lastError = missing
            }
        } else {
            let reason = workspace.lastError ?? "导入失败（未说明原因）"
            append("✖ \(reason)")
            lastError = reason
        }
    }

    // MARK: 只读：线上基线

    /// 读线上发布头。**不写任何东西**（桥接器侧 `apply=False`）。
    func readOnlineBaseline() async {
        guard await ensureReady(.baseline) else { return }
        let directory = jobDirectory("baseline-\(Int(Date().timeIntervalSince1970))")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            lastError = "创建工作目录失败：\(error.localizedDescription)"
            return
        }
        let request = makeRequest(
            requestID: "baseline-\(UUID().uuidString)",
            jobID: "baseline",
            releaseSeq: max(1, (onlineHead?.releaseSeq ?? 0)),
            archivePath: directory.appendingPathComponent("none.tar").path,
            input: directory.appendingPathComponent("input"),
            output: directory.appendingPathComponent("output"),
            receipt: directory.appendingPathComponent("receipt.json"),
            payloadHash: "baseline")
        guard let requestURL = write(request, to: directory) else { return }

        await perform(mode: .baseline, requestPath: requestURL) { [weak self] result in
            guard let self else { return }
            self.onlineHead = result.onlineHead
            self.outcome = result.outcome
            self.outcomeMessage = result.outcomeMessage ?? result.lastDisplayLine
            self.outcomeRetryable = result.outcomeRetryable
        }
    }

    /// 把读到的线上版本采用为这份草稿的基线（R07：运营的显式动作，不是自动回填）。
    func adoptBaseline(_ workspace: OpsWorkspace) {
        guard let head = onlineHead else {
            lastError = "还没有读到线上基线：请先点「读取线上基线」。"
            return
        }
        workspace.adoptBaseline(head)
    }

    // MARK: 只读：从线上拉回整份目录

    func pullCatalog() async {
        guard await ensureReady(.pullCatalog) else { return }
        pullFailure = nil
        pullFailureRetryable = false
        let directory = jobDirectory("pull-\(Int(Date().timeIntervalSince1970))")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            lastError = "创建工作目录失败：\(error.localizedDescription)"
            return
        }
        let request = makeRequest(
            requestID: "pull-\(UUID().uuidString)",
            jobID: "pull",
            releaseSeq: max(1, (onlineHead?.releaseSeq ?? 0)),
            archivePath: directory.appendingPathComponent("none.tar").path,
            input: directory.appendingPathComponent("input"),
            output: directory,
            receipt: directory.appendingPathComponent("receipt.json"),
            payloadHash: "pull")
        guard let requestURL = write(request, to: directory) else { return }

        await perform(mode: .pullCatalog, requestPath: requestURL) { [weak self] result in
            guard let self else { return }
            self.onlineHead = result.onlineHead ?? self.onlineHead
            self.outcome = result.outcome
            self.outcomeMessage = result.outcomeMessage ?? result.lastDisplayLine
            self.outcomeRetryable = result.outcomeRetryable
            self.pulled = OpsPulledCatalog.from(
                result: result, environment: self.targetEnvironment.rawValue)
            // 失败时**必须**在下载卡片里留下一句话，否则「点了没反应」会被读成
            // 「功能不存在」，而不是「这次请求失败了」。
            self.pullFailure = self.pulled == nil
                ? (result.outcomeMessage ?? result.lastDisplayLine)
                : nil
            self.pullFailureRetryable = self.pulled == nil && result.outcomeRetryable
        }
        // `perform` 里「超时 / 取消」走的是 catch（不是回调），那条路没有 outcome
        // 事件可读 —— 这里兜一下，保证下载卡片**任何**失败都有话说。
        if pulled == nil, pullFailure == nil {
            pullFailure = lastError ?? "这次拉回没有拿到任何结果，请重试。"
        }
    }

    /// 用拉回的内容替换当前草稿。**替换前必须让运营读到这些话**。
    func adoptionBlockers(_ pulled: OpsPulledCatalog, workspace: OpsWorkspace) -> [String] {
        OpsPulledCatalogAdoption.blockers(
            pulled: pulled,
            isDraftCorrupted: workspace.isCorrupted,
            isCatalogFileReadable: OpsBridgeSettings.isReadableFile(URL(fileURLWithPath: pulled.path)))
    }

    func adoptionCaveats(_ pulled: OpsPulledCatalog, workspace: OpsWorkspace) -> [String] {
        OpsPulledCatalogAdoption.caveats(pulled: pulled, currentItemCounts: nil)
    }

    @discardableResult
    func adoptPulled(_ pulled: OpsPulledCatalog, workspace: OpsWorkspace) -> Bool {
        let blockers = adoptionBlockers(pulled, workspace: workspace)
        guard blockers.isEmpty else {
            lastError = blockers.joined(separator: " ")
            return false
        }
        let baseline = OpsPulledCatalogAdoption.baseline(afterAdopting: pulled)
        return workspace.adoptPulledCatalogContent(
            from: URL(fileURLWithPath: pulled.path), baseline: baseline)
    }

    // MARK: 写：构建待发布包并发布

    /// 导出待发布整包 → 写冻结请求 → 交受控发布器。
    ///
    /// 顺序不能改：**先**由 App 复校验并导出（缺图会在这里硬失败，不会带上残缺产物），
    /// **再**写请求文件（请求文件就是唯一的「提交」动作）。
    func publish(workspace: OpsWorkspace) async {
        guard await ensureReady(.publish) else { return }
        guard workspace.isCorrupted == false else {
            failBeforeBridge("草稿处于只读隔离状态，不能发布。请先「另存为新草稿」。", mode: .publish)
            return
        }
        guard let head = onlineHead else {
            failBeforeBridge("还不知道线上当前版本：请先点「读取线上基线」，"
                + "发布号必须严格大于线上（R07：不能拿一份不知道基于哪一版的整包去覆盖线上）。",
                mode: .publish)
            return
        }
        // 发布号是**按环境**编号的：拿 Development 的号发 Production 会覆盖掉
        // 另一个环境的发布头，而这一步之前没有任何一层会拦。
        guard head.environment == targetEnvironment.rawValue else {
            failBeforeBridge("读到的线上基线属于 \(head.environment)，"
                + "与当前目标环境 \(targetEnvironment.rawValue) 不一致。"
                + "请先重新读取当前环境的线上基线（切换环境会自动清空上一次的结果）。",
                mode: .publish)
            return
        }
        let seq = head.releaseSeq + 1

        let directory = jobDirectory("publish-seq\(seq)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            failBeforeBridge("创建工作目录失败：\(error.localizedDescription)", mode: .publish)
            return
        }

        // ---- 1) 导出待发布整包（服务层自带复校验 + 缺图硬报错）
        let archive: Data
        do {
            archive = try workspace.makePublicationArchive(
                targetEnvironmentName: targetEnvironment.displayName)
        } catch {
            failBeforeBridge("生成待发布整包失败：\(error.localizedDescription)", mode: .publish)
            return
        }
        let archiveURL = directory.appendingPathComponent("release.tar")
        do {
            try archive.write(to: archiveURL, options: .atomic)
        } catch {
            failBeforeBridge("待发布整包落盘失败：\(error.localizedDescription)", mode: .publish)
            return
        }
        let payloadHash = ShopCatalogSyncProtocol.sha256Hex(archive)

        // ---- 2) 冻结请求（App 唯一的「提交」动作）
        let revision = workspace.currentRevision
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
            baselineAcknowledged: baselineAcknowledged,
            targetEnvironment: targetEnvironment,
            releaseSeq: seq,
            inputDirectory: directory.appendingPathComponent("input").path,
            archivePath: archiveURL.path,
            outputDirectory: directory.appendingPathComponent("output").path,
            receiptPath: directory.appendingPathComponent("receipt.json").path,
            filesystemRoot: nil,
            dryRun: dryRun,
            payloadHash: payloadHash)
        guard let requestURL = write(request, to: directory) else { return }

        // ---- 3) 交受控发布器
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
            if self.dryRun == false, let receipt, receipt.readBackConfirmed == true,
               let seq = receipt.releaseSeq {
                _ = workspace.recordConfirmedPublish(
                    releaseSeq: seq,
                    rootIndexHash: receipt.rootIndexHash,
                    environment: self.targetEnvironment.rawValue,
                    revision: revision)
            }
        }
    }

    // MARK: 内部

    /// 三关自检：仓库目录 / 解释器 / 凭证。不通过就不跑，且每一条单独说明。
    private func ensureReady(_ mode: OpsBridgeMode) async -> Bool {
        let problems = diagnosis
        if !problems.isEmpty {
            failBeforeBridge("受控发布器还没准备好：" + problems.joined(separator: " "), mode: mode)
            return false
        }
        if credentialFileURL == nil {
            failBeforeBridge("容器内没有 \(targetEnvironment.displayName) 的 CloudKit 凭证："
                + "子进程继承 App 沙盒，读不到登录钥匙串，只能靠容器里的这份文件。"
                + "请先点「选择凭证 JSON…」把它放进 App 容器。", mode: mode)
            return false
        }
        if let summary = credentialSummary, summary.declaredEnvironmentMatches == false {
            failBeforeBridge("这份凭证自己声明的是 \(summary.declaredEnvironment ?? "（未知）")，"
                + "与当前目标环境 \(targetEnvironment.rawValue) 不一致。"
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

    /// 跑一次桥接调用。**在后台线程阻塞执行**（`OpsPublisherBridge.run` 是同步的）。
    private func perform(
        mode: OpsBridgeMode,
        requestPath: URL,
        interpret: @escaping @MainActor (OpsBridgeRunResult) -> Void
    ) async {
        isRunning = true
        runningMode = mode
        outcome = nil
        outcomeMessage = nil
        outcomeRetryable = false
        lastError = nil
        // 每次运行从干净的一份开始：`runLog` 是**按运行**归属的，留着上一次的行
        // 会让落盘的日志里混进两次运行的输出（跨环境时尤其误导）。
        runLog = []
        let runID = "\(Self.runIDFormatter.string(from: Date()))-\(mode.rawValue)"
        append("▶ \(mode.displayName)（\(targetEnvironment.displayName)）")

        let bridge = OpsPublisherBridge(settings: settings)
        let environmentName = targetEnvironment.rawValue
        do {
            let result = try await Task.detached(priority: .userInitiated) { () throws -> OpsBridgeRunResult in
                try bridge.run(
                    mode: mode,
                    requestPath: requestPath,
                    environmentName: environmentName
                ) { event in
                    guard let line = event.displayLine else { return }
                    Task { @MainActor in OpsCloudSyncModel.shared.append(line) }
                }
            }.value
            append("退出码 \(result.exitCode)"
                + (result.outcome.map { " · 结论 \($0.rawValue)" } ?? ""))
            interpret(result)
        } catch {
            // 超时 / 取消不是「没发生」：文案里有「先查询再决定」的要求。
            lastError = error.localizedDescription
            append("✖ \(error.localizedDescription)")
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
    }

    func clearLog() {
        logLines = []
        runLog = []
        // `logFileURL` 刻意不清：那是一个**已经写在磁盘上的产物**，
        // 清空面板不等于删文件，把链接一起抹掉只会让人更找不到它。
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
        lines.append("目标环境：\(targetEnvironment.rawValue)（\(targetEnvironment.displayName)）")
        if let runID { lines.append("本次运行：\(runID)") }
        if let mode { lines.append("运行模式：\(mode.rawValue)") }
        if let head = onlineHead {
            lines.append("线上发布号：seq \(head.releaseSeq)"
                + (head.rootIndexHash.map { " · 根清单摘要 \($0.prefix(12))…" } ?? ""))
        }
        if let seq = lastReceiptSeq {
            lines.append("回执发布号：\(seq)"
                + (lastReceiptConfirmed ? "（已回读确认）" : "（未回读确认）"))
        }
        if let failure = pullFailure {
            lines.append("拉回失败：\(failure)"
                + (pullFailureRetryable ? "（可原样重试）" : "（不可原样重试）"))
        }
        if let message = outcomeMessage { lines.append("结论文案：\(message)") }
        if let error = lastError { lines.append("✖ 错误：\(error)") }
        lines.append("--- 桥接器输出（最近一次运行，"
            + "\(runLog.isEmpty ? logLines.count : runLog.count) 行）---")
        lines.append(contentsOf: runLog.isEmpty ? logLines : runLog)
        return lines.joined(separator: "\n")
    }

    /// 把本次运行的日志落成文件：`bridge/logs/<runID>.log` + 覆盖 `latest.log`。
    ///
    /// 写失败**刻意静默**：一次同步已经跑完了，不该因为「日志没写成」再报一个错。
    /// 但此时 `logFileURL` 保持 nil，界面上的按钮会是灰的 —— 这一点要能看出来。
    private func persistLog(runID: String, mode: OpsBridgeMode) {
        let directory = logsDirectory
        let manager = FileManager.default
        guard (try? manager.createDirectory(
            at: directory, withIntermediateDirectories: true)) != nil else { return }
        let text = copyableLogText(runID: runID, mode: mode)
        guard let data = text.data(using: .utf8) else { return }
        let stamped = directory.appendingPathComponent("\(runID).log")
        try? data.write(to: stamped, options: .atomic)
        let latest = directory.appendingPathComponent("latest.log")
        guard (try? data.write(to: latest, options: .atomic)) != nil else { return }
        logFileURL = latest
    }

    /// 在访达里选中最近一次的日志文件。
    func revealLogFile() {
        guard let url = logFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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

// MARK: - 面板

struct OpsCloudSyncSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    @ObservedObject private var model = OpsCloudSyncModel.shared
    /// 「复制日志」成功后的短提示。放在视图里而不是 model 里：
    /// 它是一次交互反馈，不是跨入口共享的状态。
    @State private var copyLogHint: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    diagnosisCard
                    onlineCard
                    downloadCard
                    handoffCard
                    uploadCard
                    logCard
                }
                .padding(16)
                .frame(maxWidth: 820, alignment: .leading)
            }
        }
        .frame(minWidth: 860, minHeight: 620)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cloud.fill").font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("云端同步").font(.headline)
                opsMarkdown("所有发布与回读都走**受控发布器**（仓库里的 Python CLI）；"
                            + "本 App 不直连 CloudKit，私钥也不进 App。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRunning {
                ProgressView().controlSize(.small)
                Text(model.runningMode?.displayName ?? "运行中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("关闭") { model.showsSheet = false }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: 桥接器自检

    private var diagnosisCard: some View {
        let problems = model.diagnosis
        return OpsCard(title: "桥接器自检（①仓库目录 ②解释器 ③凭证）", systemImage: "stethoscope") {
            VStack(alignment: .leading, spacing: 8) {
                if problems.isEmpty {
                    Label("三关都通过，可以跑受控发布器。", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                } else {
                    ForEach(problems, id: \.self) { problem in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            opsMarkdown(problem)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Divider()
                LabeledContent("仓库目录", value: model.settings.repoRootPath ?? "（未授权）")
                LabeledContent("解释器", value: model.interpreterText)
                LabeledContent("当前环境", value: model.targetEnvironment.displayName)
                HStack(spacing: 10) {
                    Button("选择仓库目录…") { model.chooseRepoRoot() }
                    Button("选择凭证 JSON…") { model.importCredentialFile() }
                    // 协议里只有 Development / Production 两个真实远端
                    // （原 `localFixture`「本机演练」已于 2026-09-29 连同离线演练一起移除）。
                    Picker("环境", selection: $model.targetEnvironment) {
                        ForEach(ShopCatalogPublishTargetEnvironment.allCases) { environment in
                            Text(environment.displayName).tag(environment)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    // 跑到一半换环境会让「刚读到的线上基线」属于另一个环境
                    .disabled(model.isRunning)
                }
                .controlSize(.small)
                opsMarkdown(model.targetEnvironment.guidance)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()
                Text("凭证（按环境分开，私钥不显示）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(model.credentialStates) { state in
                    HStack(spacing: 6) {
                        Image(systemName: state.isConfigured ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(state.isConfigured ? Color.green : Color.orange)
                        Text("\(state.environment.displayName)：\(state.isConfigured ? "已配置" : "未配置")")
                            .font(.callout)
                    }
                }
                // 两个环境**都必须**有凭证（原先免凭证的本机演练已移除），
                // 所以这里不再分「需要 / 不需要凭证」两支 —— 那支已经走不到了。
                opsMarkdown(model.credentialText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let summary = model.credentialSummary {
                    if let parseError = summary.parseError {
                        opsMarkdown("⚠️ 凭证文件读不出来：\(parseError)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(summary.displayText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if summary.declaredEnvironmentMatches == false {
                            opsMarkdown("⚠️ 这份凭证声明的是"
                                        + " \(summary.declaredEnvironment ?? "（未知）")，"
                                        + "与当前环境 \(model.targetEnvironment.rawValue) 不符，"
                                        + "混用只会 401。")
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if model.credentialFileURL == nil {
                    opsMarkdown(model.credentialGuidance)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: 线上状态

    private var onlineCard: some View {
        OpsCard(title: "线上基线（只读）", systemImage: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 8) {
                if let head = model.onlineHead {
                    LabeledContent("环境", value: head.environment)
                    if head.releaseSeq == 0 {
                        // 「线上还没有发布头」不是错误，是**首次发布**的正常前置状态。
                        // 不把它说清楚，运营会以为「读基线失败」而去反复重试。
                        opsMarkdown("**\(head.environment) 线上还没有发布头**："
                                    + "这个环境还没发过任何一版，首次发布会从 releaseSeq 1 开始。")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        opsMarkdown("发之前请确认该环境的 Schema 已就绪 —— "
                                    + "Production 需要先在 CloudKit Console 里把 Development 的 Schema "
                                    + "**Deploy to Production**，否则记录类型不存在。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        LabeledContent("线上发布号", value: "releaseSeq \(head.releaseSeq)")
                        LabeledContent("根清单摘要", value: head.hashText)
                        if let publishedAt = head.publishedAt {
                            LabeledContent("发布时间", value: publishedAt)
                        }
                        Button("把这一版采用为草稿基线") { model.adoptBaseline(workspace) }
                            .controlSize(.small)
                        OpsFootnote(text: "采用基线是**你的显式决定**（R07）：采用之后本机才知道"
                                    + "「这份草稿基于哪一版」，严格策略的作用域才不会把存量内容全算进去。")
                    }
                } else {
                    opsMarkdown("还不知道线上当前版本。**发布号必须严格大于线上**，"
                                + "所以发布前必须先读一次。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button("读取线上基线") {
                    Task { await model.readOnlineBaseline() }
                }
                .disabled(model.isRunning)
            }
        }
    }

    // MARK: 从云端下载

    private var downloadCard: some View {
        OpsCard(title: "从云端下载（拉回线上目录）", systemImage: "icloud.and.arrow.down") {
            VStack(alignment: .leading, spacing: 8) {
                Button("从线上拉回基线") {
                    Task { await model.pullCatalog() }
                }
                .disabled(model.isRunning)
                // 失败时这张卡片**必须**有话说：原先只有 `if let pulled`，
                // 拉回失败就一个字都不显示，看起来像「按钮不管用」。
                if let failure = model.pullFailure {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                        Text("这次没拉回来").font(.callout)
                        if model.pullFailureRetryable {
                            Text("可原样重试")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.orange)
                        }
                    }
                    opsMarkdown(failure)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let pulled = model.pulled {
                    Divider()
                    Text(pulled.summaryText).font(.callout)
                    ForEach(pulled.sortedItemCounts) { item in
                        Text("· \(item.label) \(item.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let blockers = model.adoptionBlockers(pulled, workspace: workspace)
                    let caveats = model.adoptionCaveats(pulled, workspace: workspace)
                    if !blockers.isEmpty {
                        ForEach(blockers, id: \.self) { text in
                            opsMarkdown("⚠️ \(text)")
                                .font(.callout)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        ForEach(caveats, id: \.self) { text in
                            opsMarkdown("· \(text)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("用拉回的内容替换当前草稿") {
                            _ = model.adoptPulled(pulled, workspace: workspace)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: 从 iOS 交接（整包导入）

    private var handoffCard: some View {
        OpsCard(title: "从 iOS 交接（导入整包 · 含图片）", systemImage: "shippingbox") {
            VStack(alignment: .leading, spacing: 8) {
                Button("选择 iOS 导出的整包…") { model.importHandoff(workspace: workspace) }
                    .controlSize(.small)
                opsMarkdown("在 iOS 端用「**导出整包（含图片）**」拿到一个 `.tar`，"
                            + "在访达里双击解开，然后在这里选**解开出来的那个目录**"
                            + "（里面有 `shop-catalog.json` 与 `images/`）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                OpsFootnote(text: "图片会**按原文件名**进 staging —— 目录里的 `local:` 引用"
                            + "是交接方给的名字，改成哈希名会让所有引用悬空、发布时全报缺图。")
                if let message = workspace.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: 上传到云端

    private var uploadCard: some View {
        OpsCard(title: "上传到云端（构建待发布包 → 受控发布）", systemImage: "icloud.and.arrow.up") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("演练（dry-run，不写云端）", isOn: $model.dryRun)
                Toggle("已知线上已变，仍按本基线发布", isOn: $model.baselineAcknowledged)
                opsMarkdown("发布号 = 线上当前号 + 1。缺图会在**导出那一步**硬失败"
                            + "（不会带着残缺产物去发布），门禁由服务层自己复校验。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button(model.dryRun ? "演练一次（不写云端）" : "构建并发布到 \(model.targetEnvironment.displayName)") {
                    Task { await model.publish(workspace: workspace) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRunning || workspace.isCorrupted)
                if let outcome = model.outcome {
                    HStack(spacing: 6) {
                        Image(systemName: outcome == .confirmed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(outcome == .confirmed ? Color.green : Color.orange)
                        Text(outcome.rawValue).font(.callout)
                        // 「原样重试是安全的」必须和「失败了」分开说：前者是网络抖动，
                        // 后者要改东西。混在一起运营只能靠猜（R07/R09 都栽在这类含糊上）。
                        if model.outcomeRetryable {
                            Text("可原样重试")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.orange)
                        }
                    }
                }
                if let message = model.outcomeMessage {
                    opsMarkdown(message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let seq = model.lastReceiptSeq {
                    // 变量文案必须过 opsMarkdown：`Text(变量)` 与 `Text("a" + "b")`
                    // **不解析** Markdown，`**未**` 会逐字显示成星号。
                    opsMarkdown("回执发布号 \(seq) · "
                                + (model.lastReceiptConfirmed
                                   ? "已回读确认"
                                   : "**未**回读确认（先查询再下结论）"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: 日志

    private var logCard: some View {
        OpsCard(title: "受控发布器输出", systemImage: "terminal") {
            VStack(alignment: .leading, spacing: 6) {
                if let error = model.lastError {
                    // 与下面的日志行一样允许选中：这段是**最需要被带走**的一段文字，
                    // 旧写法漏了 `.textSelection`，于是唯二的取字方式只剩截图。
                    opsMarkdown("✖ \(error)")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.logLines.isEmpty {
                    Text("（还没有输出）").font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(model.logLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(height: 160)
                }
                HStack(spacing: 8) {
                    Button("复制日志") { copyLog() }
                        .controlSize(.small)
                        .disabled(model.logLines.isEmpty && model.lastError == nil)
                    Button("打开日志文件") { model.revealLogFile() }
                        .controlSize(.small)
                        .disabled(model.logFileURL == nil)
                    Button("清空") { model.clearLog() }
                        .controlSize(.small)
                    if let hint = copyLogHint {
                        Text(hint).font(.caption).foregroundStyle(.secondary)
                    }
                }
                opsMarkdown(model.logFileURL == nil
                    ? "运行一次后（读取基线 / 拉回目录 / 发布）日志会同时落到 "
                        + "`bridge/logs/latest.log`，「复制日志」是一次性拿走全文的入口。"
                    : "**「复制日志」= 头部 + 全文**（头部含环境、模式、线上发布号与失败原因，"
                        + "贴出去别人才能判断该不该重试）；完整历史在 `bridge/logs/`。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 复制成功后的短提示（3 秒后自己消失，免得看起来像常驻状态）。
    private func copyLog() {
        let text = model.copyableLogText()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        copyLogHint = "已复制 \(lineCount) 行"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            copyLogHint = nil
        }
    }
}
