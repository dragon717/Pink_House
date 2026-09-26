//
//  OpsPublisherBridge.swift
//  PinkHouseOps
//
//  受控发布桥接器的调用端（方案 §5.2）：**固定可执行 + 固定参数 + NDJSON 事件**。
//
//  ## 为什么参数是拼出来的一段常量，而不是「让界面填命令行」
//
//  桥接器只接受两个业务参数：`--mode` 与 `--request <请求文件>`。业务内容
//  （发布号、环境、产物路径…）全部写在请求 JSON 里。这样：
//    · 界面不可能拼出一条我们没审过的命令行；
//    · 请求文件本身可以留档，事后能逐字复现「当时提交的是什么」；
//    · 桥接器的参数永远变不了，加功能也不会把「参数注入」这个面打开。
//
//  ## 为什么必须自己管超时与取消
//
//  发布是**长事务**：上传几十兆图片、切换发布头。如果只是「跑起来等结束」，
//  一次网络挂死会让界面永远停在「上传中」，而运营并不知道线上到底动了没有 ——
//  这正是 R09 最怕的状态。所以：
//    · 超时到点 → 向子进程发终止信号，并把原因记成「超时」；
//    · 运营点取消 → 同一个入口，原因记成「取消」；
//    · 中断原因**只有一个记录点**（`interrupt(_:)`）：曾经把两个 `Bool` 分散在
//      各处 `mark*()`，结果「取消」那条漏了标记、错误分支一辈子走不到 ——
//      详见 `OpsBridgeInterruption` 的注释；
//    · 超时/取消**不是**「失败可重试」的同义词：走到切头之后被打断，
//      结论只能是「结果不明」，由上层按阶段判定（见 `OpsPublishCenter`）。
//
//  ## 沙盒
//
//  发布脚本在**仓库目录**里，而沙盒 App 默认读不到容器外的路径。
//  所以仓库目录需要由用户通过选择面板授权，并把 **security-scoped bookmark**
//  存下来；运行时 `startAccessingSecurityScopedResource()`，子进程会继承这个
//  授权（沙盒扩展是进程级的，会随 fork/exec 传给子进程）。
//  没有授权时**不假装能跑**：直接给出「去设置里选仓库目录」的明确指引。
//

import Combine
import Foundation
import SharedCatalog

// MARK: - 模式

/// 桥接器的四种模式。**每一种都是独立的、审过的入口**；参数永远只有两个
/// （`--mode` 与 `--request`），所以多一种模式不会把「参数注入」这个面打开。
///
/// 其中**只有 `publish` 会写**，另外三种全是只读 —— 这一点在桥接器侧由
/// `apply=False` 的读/写闸门保证（读走 `_send` 照发、写走 `_post` 静默拦住），
/// 不是靠调用方自觉。
public enum OpsBridgeMode: String, Sendable {
    /// 只读线上发布头（R07 的基线核对）
    case baseline
    /// 构建并发布
    case publish
    /// 结果待确认时的查询（R09：**先查询，不换号重发**）
    case query
    /// **只读**把线上商店目录整份拉回本地（方案 §5 的「当前线上完整基线」）。
    ///
    /// 为什么必须补这一条：在此之前 App 只有「导入 JSON」一个入口，
    /// 没有任何从线上回读目录的通道 —— 于是「基线内容」全靠人手导出 / 导入，
    /// 桥接器也无从核对 `baseRootIndexHash`（它根本没见过线上那份内容）。
    /// 注意 rawValue 是 `pull-catalog`（带连字符），**不能**靠枚举名默认推导。
    case pullCatalog = "pull-catalog"

    public var displayName: String {
        switch self {
        case .baseline: return "读取线上基线"
        case .publish: return "发布"
        case .query: return "查询发布结果"
        case .pullCatalog: return "从线上拉回基线"
        }
    }

    /// 这一模式会不会写远端。**只有 `publish` 会** ——
    /// 界面上但凡与「会不会动线上」有关的文案都必须读这个属性，
    /// 而不是各处自己判断（漏一处就会出现「只读操作把我们吓成会覆盖线上」）。
    public var writesRemote: Bool { self == .publish }
}

// MARK: - 设置

/// 桥接器的定位信息（持久化在 `UserDefaults`）。
public struct OpsBridgeSettings: Codable, Equatable {

    public static let defaultsKey = "ops.publishBridgeSettings"

    /// 仓库根目录（用户授权选择的那个）。nil = 还没授权。
    public var repoRootPath: String?
    /// 该目录的 security-scoped bookmark。
    ///
    /// 为什么存 bookmark 而不是只用路径：沙盒下路径本身不携带权限，
    /// 重启后光有路径会被系统直接拒绝（表现为「脚本不存在」这种误导性错误）。
    public var repoRootBookmark: Data?
    /// `python3` 可执行文件路径。nil = 自动探测。
    public var pythonPath: String?
    /// 单次调用的超时（秒）。默认 15 分钟：上传几十兆图片 + 切头足够，
    /// 又不至于让一次挂死拖到运营以为「工具坏了」。
    /// 实际生效值会被 `minimumTimeoutSeconds` 抬底，见 `effectiveTimeout(configured:)`。
    public var timeoutSeconds: Int = 900

    // 跨模块构造入口：`public` 结构体的合成逐成员 init 是 internal，外部模块必须显式声明。
    public init(
        repoRootPath: String? = nil,
        repoRootBookmark: Data? = nil,
        pythonPath: String? = nil,
        timeoutSeconds: Int = 900
    ) {
        self.repoRootPath = repoRootPath
        self.repoRootBookmark = repoRootBookmark
        self.pythonPath = pythonPath
        self.timeoutSeconds = timeoutSeconds
    }

    /// 超时的**安全下限**。误配成 1 秒会让每一次发布都在中途被打断，
    /// 而中断在切头之后就是「结果待确认」—— 一个配置手滑能造出一堆待确认任务。
    public static let minimumTimeoutSeconds = 30

    /// 实际生效的超时秒数。抽成纯函数是为了能直接测「下限真的生效」——
    /// 否则只能靠等 30 秒去观察，那种测试没人愿意跑。
    public static func effectiveTimeout(configured: Int) -> Int {
        max(minimumTimeoutSeconds, configured)
    }

    /// `tools/time_hall/publication` 目录
    public var publicationDirectory: URL? {
        guard let repoRootPath, !repoRootPath.isEmpty else { return nil }
        return URL(fileURLWithPath: repoRootPath, isDirectory: true)
            .appendingPathComponent("tools/time_hall/publication", isDirectory: true)
    }

    /// 桥接脚本路径（**固定文件名**，不允许界面指定任意脚本）
    public var scriptPath: URL? {
        publicationDirectory?.appendingPathComponent("ops_publish_bridge.py")
    }

    /// 解释器候选：优先用户显式设置，其次**仓库内的 venv**，最后才是系统解释器。
    ///
    /// 为什么不去 `which python3`：沙盒 App 的 `PATH` 极简。
    ///
    /// ⭐ 为什么**仓库内 `.venv` 必须排在系统解释器前面**（2026-09-27 探针实测）：
    /// 本机 `/opt/homebrew/bin/python3` 与 `/usr/local/bin/python3` **都不存在**，
    /// 于是自动探测会选中 `/usr/bin/python3` —— 而它在沙盒里**根本跑不起来**，
    /// 子进程直接吐：
    ///
    ///     xcrun: error: cannot be used within an App Sandbox.
    ///
    /// （`/usr/bin/python3` 是 Command Line Tools 的替身，不是真解释器。）
    /// 而发布脚本真正需要的 `cryptography` 本来就只装在
    /// `tools/time_hall/publication/.venv` 里 —— 也就是说，**候选表原来的顺序
    /// 让「自动探测」在沙盒下 100% 选错**。这个顺序是有证据的，不是偏好。
    public static func pythonCandidates(explicit: String?, publicationDirectory: URL? = nil) -> [String] {
        var list: [String] = []
        if let explicit, !explicit.isEmpty { list.append(explicit) }
        if let publicationDirectory {
            list.append(publicationDirectory.appendingPathComponent(".venv/bin/python3").path)
        }
        list.append("/opt/homebrew/bin/python3")
        list.append("/usr/local/bin/python3")
        list.append("/usr/bin/python3")
        return list
    }

    /// 解析出实际可用的解释器路径
    ///
    /// ⚠️ 必须在 `beginAuthorizedRepoRootScope()` **之后**调用：仓库内 venv 的
    /// 可执行位与内容都在被授权的那一个目录里，授权之前一律「看不见」。
    public func resolvedPythonPath(fileManager: FileManager = .default) -> String? {
        for candidate in Self.pythonCandidates(explicit: pythonPath,
                                               publicationDirectory: publicationDirectory) {
            if fileManager.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// 脚本是否**真的读得出来**（而不是只 `stat` 得到）。
    ///
    /// ## 为什么要专门做这个，不能只 `fileExists`
    ///
    /// 2026-09-27 探针实测：沙盒下 `stat` 与 `open` 走的是**两套**权限判定。
    /// 没有 security-scoped 扩展时：
    ///
    ///     fileExists("/…/tools/time_hall/publication/ops_publish_bridge.py")  →  true
    ///     Data(contentsOf:) 同一个路径                                        →  Operation not permitted
    ///     子进程 ls 同一个目录                                                →  Operation not permitted
    ///
    /// 于是原来那句 `guard fileManager.fileExists(atPath: script.path)` 在
    /// **「用户还没授权」这个最常见的场景下放行**，流程一路跑到 `process.run()`，
    /// 最后以「退出码 1、没有任何输出」收场（`OpsBridgeError.noDiagnostics`）——
    /// 一句对运营毫无指向性的结论，而且看起来像「脚本坏了」。
    /// 换成「能不能读出第一个字节」当判据，才能在这一步就把话说清楚。
    ///
    /// 空文件算**可读**：这里判的是权限，不是内容。
    /// （若判成不可读，一个被 `: >` 截空的脚本会得到「没有权限」这种完全错的指引。）
    ///
    /// ⚠️ 判据的写法是有讲究的（实测踩过）：**不能**用
    /// `(try? handle.read(upToCount: 1)) != nil` —— `read(upToCount:)` 在 EOF
    /// 本来就会返回 `nil`，于是空文件会被判成「读不了」。正确写法是
    /// 「打开成功 + 读这一步**不抛错**」：目录会在 `read` 抛 `EISDIR`，
    /// 没权限会在 `FileHandle(forReadingFrom:)` 就抛 —— 两者都落进 `catch`。
    public static func isReadableFile(_ url: URL, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        do {
            _ = try handle.read(upToCount: 1)
            return true
        } catch {
            return false
        }
    }

    /// 打开仓库目录的 **security-scoped 授权**。返回的 `stop` 闭包必须被调用。
    ///
    /// ⭐ 顺序不变量：**任何落盘判断（`fileExists` / `isReadableFile` /
    /// `isExecutableFile` / `contentsOfDirectory`）都必须在它之后**。
    /// 反了的后果是「权限没打开」被报成「文件不存在」——一个把运维引向
    /// 错误方向的错误（见 `OpsPublisherBridge.run` 里的长注释）。
    ///
    /// `accessed` 是 `startAccessingSecurityScopedResource()` 的**原始返回值**，
    /// 只给诊断用（探针要报它）。没有 bookmark 时它是 `false`、`stop` 是空操作 ——
    /// 非沙盒或手填路径的场景靠这条兜底。
    public func beginAuthorizedRepoRootScope() -> (accessed: Bool, stop: () -> Void) {
        guard let bookmark = repoRootBookmark else {
            return (false, {})
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale) else {
            return (false, {})
        }
        let accessed = url.startAccessingSecurityScopedResource()
        return (accessed, { if accessed { url.stopAccessingSecurityScopedResource() } })
    }

    /// 人类可读的自检结果（发布中心顶部常驻显示）。
    /// 空数组 = 一切就绪。
    ///
    /// ⚠️ 它会**自己打开一次授权**，因为它检查的正是授权之后才看得见的东西。
    /// 不打开的话，一个已经授权好的配置会被报成「找不到桥接脚本」——
    /// 而那会把运营推向「反复重新选择目录」这种无效动作。
    public func diagnosis(fileManager: FileManager = .default) -> [String] {
        var problems: [String] = []
        if repoRootPath?.isEmpty ?? true {
            problems.append("还没有授权仓库目录：受控发布脚本在仓库里，沙盒 App 需要你显式选择一次。")
            return problems
        }
        guard let scriptPath else {
            problems.append("仓库目录无效，无法定位发布脚本。")
            return problems
        }
        let access = beginAuthorizedRepoRootScope()
        defer { access.stop() }

        if !fileManager.fileExists(atPath: scriptPath.path) {
            problems.append("找不到桥接脚本：\(scriptPath.path)（仓库目录选对了吗？）")
        } else if !Self.isReadableFile(scriptPath, fileManager: fileManager) {
            // 「存在但读不到」与「不存在」是两件事，分开说 —— 处置办法也不一样。
            problems.append("桥接脚本在，但本 App 读不到它：\(scriptPath.path)。"
                + "这是沙盒权限问题，不是文件问题 —— 请在发布中心里重新选择一次仓库目录。")
        }
        if resolvedPythonPath(fileManager: fileManager) == nil {
            problems.append("找不到可用的 python3：已尝试 "
                + Self.pythonCandidates(explicit: pythonPath,
                                        publicationDirectory: publicationDirectory)
                    .joined(separator: "、")
                + "。请在设置里指定解释器。")
        }
        return problems
    }
}

// MARK: - 结果

/// 一次桥接调用的全部可见结果。
///
/// ⚠️ 这里**没有** `timedOut` / `cancelled` 两个字段，是有意的：
/// 超时与取消不是「跑完了的结果」，它们是**抛出**（`OpsBridgeError`）。
/// 早先留过这两个字段，但它们恒为 `false`（`run` 在构造结果之前就 throw 了），
/// 读的人会以为「返回了结果就说明没超时」—— 那是假的。
public struct OpsBridgeRunResult: Sendable {

    public var exitCode: Int32
    public var events: [ShopCatalogPublishEvent]
    /// 不像 JSON 的行（桥接器本不该有；出现就是异常，必须留痕而不是丢掉）
    public var nonJSONLines: [String]
    public var executablePath: String
    public var scriptPath: String

    /// 桥接器声明的协议版本（来自 `hello`）
    public var bridgeSchemaVersion: Int?
    /// 桥接器给出的结论（`result` 事件）。nil = 它没有下结论。
    public var outcome: ShopCatalogPublishOutcome?
    public var outcomeMessage: String?
    public var outcomeRetryable: Bool = false

    /// 线上发布头（`baseline` 事件）
    public var onlineHead: ShopCatalogOnlineHead?
    /// 产物信息（`artifact` 事件）
    public var artifactReleaseSeq: Int?
    public var artifactRootIndexHash: String?

    /// 拉回的线上目录（`catalog` 事件，只有 `pullCatalog` 模式会有）。
    /// nil = 线上确实没有可拉回的商店目录（**不是失败**：首次发布前就是这个状态），
    /// 或者这次跑的不是 `pullCatalog`。
    public var pulledCatalogPath: String?
    public var pulledCatalogItemCounts: [String: Int]?
    public var pulledCatalogPayloadHash: String?

    /// 回执原文（`receipt` 事件里的路径读回来）
    public var receipt: ShopCatalogPublishReceipt?
    public var receiptPathFromEvent: String?

    /// 阶段轨迹（`stage` 事件去重后按出现顺序）
    public var stageTrail: [ShopCatalogPublishStage] = []


    /// 最后一条给运营看的事件文案
    public var lastDisplayLine: String? {
        for event in events.reversed() {
            if let line = event.displayLine { return line }
        }
        return nil
    }

    /// 是否真的走到了「切换发布头」这一步（**R09 判定的关键输入**）
    public var reachedHeadSwitch: Bool {
        stageTrail.contains { $0.stepOrdinal.map { $0 >= 6 } ?? false }
    }

    /// 协议版本是否匹配
    public var isProtocolCompatible: Bool {
        guard let bridgeSchemaVersion else { return true }   // 老桥接器没这个字段，不据此拒绝
        return bridgeSchemaVersion == ShopCatalogPublishProtocol.schemaVersion
    }
}

// MARK: - 错误

public enum OpsBridgeError: LocalizedError, Equatable {
    case executableNotFound([String])
    case scriptNotFound(String)
    case launchFailed(String)
    case timedOut(seconds: Int)
    case cancelled
    case protocolMismatch(bridge: Int?, app: Int)
    case noDiagnostics(exitCode: Int32)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let tried):
            return "找不到可用的 python3（已尝试：\(tried.joined(separator: "、"))）。"
                + "请在发布中心里指定解释器路径。"
        case .scriptNotFound(let path):
            return "找不到受控发布脚本：\(path)。请在发布中心里重新选择仓库目录。"
        case .launchFailed(let reason):
            return "无法启动受控发布器：\(reason)"
        case .timedOut(let seconds):
            return "受控发布器超过 \(seconds) 秒仍未结束，已终止。"
                + "**这不等于失败**：如果它已经走到切换发布头，结果就不确定了 —— 请用「查询结果」确认，不要直接重发。"
        case .cancelled:
            return "受控发布已取消。**这不等于没发生**："
                + "如果它已经走到切换发布头，结果就不确定了 —— 请用「查询结果」确认，不要直接重发。"
        case .protocolMismatch(let bridge, let app):
            return "桥接器协议版本不匹配（桥接器 \(bridge.map(String.init) ?? "未声明")，本机 App \(app)）。"
                + "请把仓库目录更新到与 App 同一版本后再试。"
        case .noDiagnostics(let exitCode):
            return "受控发布器以退出码 \(exitCode) 结束，但没有输出任何可读信息。"
                + "请先在终端手动跑一次桥接脚本确认环境可用。"
        }
    }
}

// MARK: - 中断

/// 一次调用被打断的原因。
///
/// ## 为什么要有这个类型，而不是两个 `Bool`
///
/// 早先的写法是收集器里放 `_timedOut` / `_cancelled` 两个布尔，各处分别调 `mark*()`。
/// 结果是：**「运营点取消」这条链路上的标记忘了写** —— 而这类遗漏编译器**不会报**，
/// 于是 `OpsBridgeError.cancelled` 成了一辈子走不到的分支，界面永远说不出「已取消」。
///
/// 现在终止子进程只有**一个**入口（`OpsPublisherBridge.interrupt(_:)`），
/// 中断原因必须作为参数给出。新增一种原因时：
///   · `error` 的 `switch` 会因为**穷尽性**编译不过 → 强制补上「映射成哪个错误」；
///   · 记录标记与发信号在同一个函数体内 → 结构上不可能只做一半。
///
/// **把「不可能写错」交给结构，把「映射正确」交给测试。**
public enum OpsBridgeInterruption: Equatable, Sendable {
    /// 超过 `timeoutSeconds` 仍未结束（**系统判定**）
    case timedOut(seconds: Int)
    /// 运营点了「取消当前运行」（**人的决定**）
    case cancelledByUser

    /// 中断 → 错误的**唯一**映射点。
    public var error: OpsBridgeError {
        switch self {
        case .timedOut(let seconds): return .timedOut(seconds: seconds)
        case .cancelledByUser: return .cancelled
        }
    }
}

// ⚠️ 这里**不能**写 `public extension`：Swift 不允许「声明了协议一致性」的 extension 带
// 访问级别修饰符（`'public' modifier cannot be used with extensions that declare
// protocol conformances`）。跨模块可见性由成员自己身上的 `public` 提供，够用。
extension OpsBridgeInterruption: CaseIterable {
    /// 手动列出全部情形（`timedOut` 带关联值，合成不出来）。
    /// 测试拿它做回归锁：每种中断都必须映射出**互不相同**的错误
    /// （防止有人复制粘贴时把两种中断指向同一个错误）。
    public static var allCases: [OpsBridgeInterruption] { [.timedOut(seconds: 1), .cancelledByUser] }
}

/// 中断账本：**先发生的那一个才算数**。
///
/// 为什么不让后到的覆盖：超时定时器与运营点取消可能几乎同时发生。
/// 若让「后写」覆盖「先写」，究竟是超时还是人为取消就取决于线程调度顺序 ——
/// 而这两件事对后续处置的含义完全不同（见 `OpsBridgeError.timedOut` 的文案），
/// 不能靠巧合决定。
public struct OpsBridgeInterruptionLedger: Equatable, Sendable {

    private(set) var interruption: OpsBridgeInterruption?

    public mutating func record(_ value: OpsBridgeInterruption) {
        if interruption == nil { interruption = value }
    }

    /// 中断应当抛出的错误（没有中断 = nil）
    public var resolvedError: OpsBridgeError? { interruption?.error }
}

// MARK: - 事件收集器（跨线程）

/// 收集子进程输出。`Process` 的管道读取在后台线程，所以这个盒子要能跨线程用。
private final class OpsBridgeOutputCollector: @unchecked Sendable {

    private let lock = NSLock()
    private let onEvent: (ShopCatalogPublishEvent) -> Void

    private var _events: [ShopCatalogPublishEvent] = []
    private var _nonJSONLines: [String] = []
    private var _tailLines: [String] = []
    private var _stages: [ShopCatalogPublishStage] = []
    private var _interruption = OpsBridgeInterruptionLedger()

    private static let maxTailLines = 400

    public init(onEvent: @escaping (ShopCatalogPublishEvent) -> Void) {
        self.onEvent = onEvent
    }

    /// 消费一行。JSON 就解成事件，解不出来就原样留痕（**不静默丢**）。
    public func consume(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let event = ShopCatalogPublishEvent.decoded(fromLine: trimmed) {
            lock.lock()
            _events.append(event)
            if event.type == "stage", let stage = event.stage, event.state == .started,
               _stages.last != stage {
                _stages.append(stage)
            }
            lock.unlock()
            onEvent(event)
        } else {
            lock.lock()
            _nonJSONLines.append(trimmed)
            _tailLines.append(trimmed)
            if _tailLines.count > Self.maxTailLines {
                _tailLines.removeFirst(_tailLines.count - Self.maxTailLines)
            }
            lock.unlock()
        }
    }

    /// 记下一次中断。**只由 `OpsPublisherBridge.interrupt(_:)` 调用** ——
    /// 它就是那个唯一入口，别在别处再开一条。
    public func recordInterruption(_ value: OpsBridgeInterruption) {
        lock.lock(); _interruption.record(value); lock.unlock()
    }

    public var interruption: OpsBridgeInterruption? {
        lock.lock(); defer { lock.unlock() }; return _interruption.interruption
    }
    public var interruptionError: OpsBridgeError? {
        lock.lock(); defer { lock.unlock() }; return _interruption.resolvedError
    }
    public var tailText: String {
        lock.lock(); defer { lock.unlock() }
        return _tailLines.suffix(40).joined(separator: "\n")
    }
    public var snapshot: (events: [ShopCatalogPublishEvent], nonJSON: [String], stages: [ShopCatalogPublishStage]) {
        lock.lock(); defer { lock.unlock() }
        return (_events, _nonJSONLines, _stages)
    }
}

// MARK: - 桥接器

/// 受控发布桥接器的调用端。
///
/// 用法（在后台线程调用，`run` 会阻塞到子进程结束）：
///
///     let bridge = OpsPublisherBridge(settings: settings)
///     let result = try bridge.run(mode: .publish, requestPath: url) { event in ... }
///
/// `onEvent` 会在**管道读取线程**上被调用，调用方自己负责跳回主线程。
public final class OpsPublisherBridge: @unchecked Sendable {

    private let settings: OpsBridgeSettings
    private let fileManager: FileManager

    private let lock = NSLock()
    private var runningProcess: Process?
    /// 当前这次调用的输出收集器。`interrupt(_:)` 必须够得着它才能记录中断原因 ——
    /// 够不着就只能发信号，于是「用户取消」与「进程自己退了」在结果上分不开
    /// （那正是 `markCancelled` 无人调用的由来）。
    private var runningCollector: OpsBridgeOutputCollector?

    public init(settings: OpsBridgeSettings, fileManager: FileManager = .default) {
        self.settings = settings
        self.fileManager = fileManager
    }

    /// 让子进程停下来 —— **这是唯一的入口**（超时与取消都走它，只是原因不同）。
    ///
    /// `internal` 而非 `private`：单测要能直接驱动它来验证两种中断都被正确处理。
    ///
    /// 两件事的顺序是有意的：**先记录、再发信号**。反过来会有一个
    /// 「进程已经退出、原因还没写」的时间窗口，落在该窗口里的判定会把
    /// 人的主动取消报成系统故障（反之亦然）。
    ///
    /// 只发 `terminate()`（SIGTERM），**不发 SIGKILL**：留一点时间让 Python
    /// 把已经拿到的回执落盘 —— 那份回执是「发布到底成没成」的唯一凭据。
    public func interrupt(_ reason: OpsBridgeInterruption) {
        lock.lock()
        let process = runningProcess
        let collector = runningCollector
        lock.unlock()
        collector?.recordInterruption(reason)
        if process?.isRunning == true { process?.terminate() }
    }

    /// 运营点了「取消当前运行」。
    public func cancel() { interrupt(.cancelledByUser) }

    /// 同步跑一次。**会阻塞当前线程**。
    ///
    /// - Parameter environmentName: 目标环境名，写进读到的线上发布头
    ///   （`ShopCatalogOnlineHead.environment`）。桥接器本身不知道 App 选的是哪个环境，
    ///   而且**必须**一致：拿 Development 的基线核对 Production 是必然误判。
    public func run(
        mode: OpsBridgeMode,
        requestPath: URL,
        environmentName: String,
        onEvent: @escaping (ShopCatalogPublishEvent) -> Void
    ) throws -> OpsBridgeRunResult {

        guard let repoRootPath = settings.repoRootPath, !repoRootPath.isEmpty else {
            throw OpsBridgeError.scriptNotFound("（仓库目录未授权：请在发布中心里选择仓库目录）")
        }

        // ⭐ 拿到沙盒授权必须**先于任何落盘判断**。
        //
        // 为什么（2026-09-27 探针实测）：沙盒下**存在性检查与真读走两套判定**。
        // 没有 security-scoped 扩展时 `fileManager.fileExists` 返回 **true**，
        // 而真读是 `Operation not permitted`。也就是说这一句如果只是
        // `fileExists`，它会**放行**，一路跑到 `process.run()`，最后以
        // 「退出码 1、没有任何输出」收场 —— 一个把「没授权」说成「脚本坏了」的
        // 误导性结论。所以判据用 `isReadableFile`（真的读得出字节）。
        // 顺带：用户显式指定的解释器也可能就在仓库里（例如仓库内的 venv），
        // 所以 `resolvedPythonPath` 同样要在授权之后解析。
        let access = settings.beginAuthorizedRepoRootScope()
        defer { access.stop() }

        guard let python = settings.resolvedPythonPath(fileManager: fileManager) else {
            throw OpsBridgeError.executableNotFound(
                OpsBridgeSettings.pythonCandidates(
                    explicit: settings.pythonPath,
                    publicationDirectory: settings.publicationDirectory))
        }
        guard let script = settings.scriptPath,
              OpsBridgeSettings.isReadableFile(script, fileManager: fileManager) else {
            throw OpsBridgeError.scriptNotFound(settings.scriptPath?.path ?? repoRootPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        // `-u` 关掉 Python 的输出缓冲：不加的话事件会攒到进程结束才一次性吐出来，
        // 进度条就变成了「一直不动、最后突然完成」。
        process.arguments = ["-u", script.path, "--mode", mode.rawValue, "--request", requestPath.path]
        process.currentDirectoryURL = script.deletingLastPathComponent()
        process.standardInput = FileHandle.nullDevice
        // 子进程**继承本 App 的沙盒**，所以它读不了登录钥匙串（本 App 没有任何
        // keychain 权限），也拿不到我们这边刚打开的 security-scoped 扩展之外的路径。
        // 把凭证文件按 CLI 认的环境变量交给它 —— 不设就等于没配，CLI 仍按自己的
        // 顺序（Keychain）走，不静默改变它的行为（见 `credentialFileURL` 的说明）。
        if let credentialFile = Self.existingCredentialFile(fileManager: fileManager) {
            var environment = ProcessInfo.processInfo.environment
            environment[Self.credentialFileEnvironmentKey] = credentialFile.path
            process.environment = environment
        }

        let pipe = Pipe()
        // stdout 与 stderr 合并成一条管道：单读者不可能与写者互锁，
        // 而且桥接器本来就把人类诊断也写成事件（真出 traceback 时也能看见）。
        process.standardOutput = pipe
        process.standardError = pipe

        let collector = OpsBridgeOutputCollector(onEvent: onEvent)
        let timeout = OpsBridgeSettings.effectiveTimeout(configured: settings.timeoutSeconds)
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + .seconds(timeout))
        timer.setEventHandler { [weak self] in
            // 走同一个入口，只是原因不同 —— 不存在「超时忘了标记」这种可能。
            self?.interrupt(.timedOut(seconds: timeout))
        }
        timer.resume()

        lock.lock(); runningProcess = process; runningCollector = collector; lock.unlock()

        defer {
            timer.cancel()
            lock.lock(); runningProcess = nil; runningCollector = nil; lock.unlock()
            // 释放沙盒授权**不在这里** —— 它已在函数早段用 `defer { access.stop() }`
            // 挂上，两处都写会出现「同一个 scope 被释放两次」。
        }

        do {
            try process.run()
        } catch {
            throw OpsBridgeError.launchFailed(error.localizedDescription)
        }

        // 阻塞读直到 EOF。stdout/stderr 是同一条管道，所以这里是唯一读者。
        let handle = pipe.fileHandleForReading
        var pending = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                let lineData = pending[pending.startIndex..<newline]
                pending = pending[pending.index(after: newline)...]
                collector.consume(String(decoding: lineData, as: UTF8.self))
            }
        }
        if !pending.isEmpty {
            collector.consume(String(decoding: pending, as: UTF8.self))
        }
        process.waitUntilExit()

        let exitCode = process.terminationStatus

        // 中断（超时 / 取消）**不是「跑完了的结果」，是抛出**。
        //
        // 所以这里直接 throw，而不是把原因塞进 `OpsBridgeRunResult` 再返回：
        // 调用方（`OpsPublishCenter.runAndFinalize`）的 catch 分支会对中断做
        // **保守收尾**（走到切头之后一律判为「结果待确认」，禁止重发）。
        // 若改成「返回值 + 标志位」，那条路径就被绕过了 —— 而它恰恰是 R09 的落点。
        if let interruptionError = collector.interruptionError { throw interruptionError }

        let snapshot = collector.snapshot
        var result = OpsBridgeRunResult(
            exitCode: exitCode,
            events: snapshot.events,
            nonJSONLines: snapshot.nonJSON,
            executablePath: python,
            scriptPath: script.path)
        result.stageTrail = snapshot.stages

        for event in snapshot.events {
            switch event.type {
            case "hello":
                result.bridgeSchemaVersion = event.schemaVersion
            case "baseline":
                result.onlineHead = ShopCatalogOnlineHead(
                    environment: environmentName,
                    releaseSeq: event.releaseSeq ?? 0,
                    rootIndexHash: event.rootIndexHash)
            case "artifact":
                result.artifactReleaseSeq = event.releaseSeq
                result.artifactRootIndexHash = event.rootIndexHash
            case "catalog":
                result.pulledCatalogPath = event.path
                result.pulledCatalogItemCounts = event.itemCounts
                result.pulledCatalogPayloadHash = event.payloadHash
            case "receipt":
                result.receiptPathFromEvent = event.path
            case "result":
                result.outcome = event.outcome
                result.outcomeMessage = event.message
                result.outcomeRetryable = event.retryable ?? false
            default:
                break
            }
        }

        // 回执从**文件**读（事件里只有路径）：回执是唯一成功凭据，
        // 必须落盘留证，而不是只在事件流里飘一次。
        if let path = result.receiptPathFromEvent {
            result.receipt = Self.loadReceipt(at: URL(fileURLWithPath: path))
        }

        if !result.isProtocolCompatible {
            throw OpsBridgeError.protocolMismatch(
                bridge: result.bridgeSchemaVersion,
                app: ShopCatalogPublishProtocol.schemaVersion)
        }
        if result.events.isEmpty, exitCode != 0 {
            throw OpsBridgeError.noDiagnostics(exitCode: exitCode)
        }
        return result
    }

    /// 打开 security-scoped 资源，返回一个必须调用的释放闭包。
    ///
    /// 已上移到 `OpsBridgeSettings.beginAuthorizedRepoRootScope()`：
    /// `diagnosis()` 也要用它（它检查的正是授权之后才看得见的东西），
    /// 留在这里就得复制一份 bookmark 解析代码 —— 而副本必然与本体漂移。

    public static func loadReceipt(at url: URL) -> ShopCatalogPublishReceipt? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try? ShopCatalogPublishReceipt.decoded(from: data)
    }

    /// 为仓库目录建一个 security-scoped bookmark（用户在选择面板里选完之后调用）。
    public static func makeBookmark(for directory: URL) -> Data? {
        let accessed = directory.startAccessingSecurityScopedResource()
        defer { if accessed { directory.stopAccessingSecurityScopedResource() } }
        return try? directory.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil)
    }

    // MARK: - 凭证交接（沙盒内的可行通道）

    /// CLI 认的凭证文件环境变量名（对应 `publish_adapters.CREDENTIAL_ENV_VAR`）。
    ///
    /// **必须与那边逐字一致**：名字写错时 CLI 不会报错，它会安静地回退去读 Keychain，
    /// 然后在沙盒里失败，最终表现为笼统的「凭证不可用」—— 又是一次「失败伪装成正常」。
    public static let credentialFileEnvironmentKey = "PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE"

    /// 容器内的约定凭证文件位置：
    /// `<App Support>/PinkHouseOps/credentials/cloudkit.json`
    ///
    /// ## 为什么走文件，而不是让子进程读 Keychain
    ///
    /// 子进程**继承本 App 的沙盒**，而本 App 的 entitlements 里没有任何 keychain 权限
    /// （也不该加），所以 `security find-generic-password` 读不到登录钥匙串里的发布凭证。
    /// 而 CLI 自己支持 `PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE` 指向一个 JSON 凭证文件；
    /// App 容器**既是 App 可写、又是子进程可读**，于是这是沙盒内唯一
    /// **不需要放宽任何权限**的交接方式（`network.client` 已经开了，出网不受影响）。
    ///
    /// ## 代价必须说清楚
    ///
    /// **私钥会以文件形式落盘**（容器内）。所以这条路建议只给 Development 用；
    /// 生产发布走终端 + Keychain，那才是 CLI 的默认路径，也是 runbook 写的那条。
    /// 文件**不存在时什么都不做** —— 不创建目录、不猜、不把空壳路径塞给子进程。
    public static func credentialFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("PinkHouseOps", isDirectory: true)
            .appendingPathComponent("credentials", isDirectory: true)
            .appendingPathComponent("cloudkit.json")
    }

    /// 约定位置上的凭证文件（**存在才有值**）。UI 拿它显示「凭证来自容器文件 / 未配置」。
    public static func existingCredentialFile(fileManager: FileManager = .default) -> URL? {
        let url = credentialFileURL(fileManager: fileManager)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
}
