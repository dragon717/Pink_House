//
//  ShopCatalogPublishProtocol.swift
//  SharedCatalog
//
//  Mac 工作台 ↔ 受控发布桥接器的**机器可读协议**（方案 §5.2 / §6 / R09）。
//
//  ## 为什么需要一份新协议，而不是解析 CLI 的人类输出
//
//  现有 Python 发布器输出的是「给人看的」文本（`[3/7] 上传缺失媒体…`）。
//  App 去正则匹配这些行，会在任何一次文案调整后静默失效 —— 而失效的表现是
//  「界面停在『上传中』」，看起来像网络问题。
//
//  所以桥接器另出一个**机器可读入口**（`tools/time_hall/publication/ops_publish_bridge.py`），
//  逐行吐 NDJSON 事件；本文件定义这些事件的 Swift 形态。
//  发布算法本身**一行都不重复实现**：桥接只调用既有的
//  `build_release.py` 与 `publish_cloudkit.py`（方案 §4 明确：禁止另造发布算法）。
//
//  ## 归零铁律（贯穿本文件）
//
//  这几个状态**永远不能合并成一个绿勾**（方案 §2 表「业务状态与发布状态不能合并」）：
//
//      导出成功 ≠ 发布成功 ≠ 远端已生效 ≠ 每台设备已同步
//
//  所以「产物」与「发布头」是两个独立的阶段，`ShopCatalogPublishOutcome.confirmed`
//  只由**回读发布头**产生。
//

import Foundation

// MARK: - 目标环境

/// 发布目标环境。**选定后本任务内不得切换**（方案 §5.4），
/// 因为切换环境会让「基线核对」与「回执核对」指向两份互不相干的事实。
///
/// ⚠️ 这里原本还有第三个环境 `.localFixture`（本机演练，走 filesystem 适配器，
/// 不联网、到不了任何设备），2026-09-29 **已移除**：既定发布通道只有下面这两个
/// 真实远端，多一个环境只会让运营在面板上多一个「点了也没意义」的选项，
/// 而它派生出来的分支（`adapter` / `isRealRemote` / 免凭证）全是不可达的死代码。
/// 桥接器（`ops_publish_bridge.py`）同步改成了 CloudKit-only：环境不是
/// development / production 就直接报错，不再静默回落到 development，
/// `filesystem` 那一支（含 `filesystemRoot`）在桥接器里已没有入口。
/// 协议枚举里仍保留 `filesystem` 一项，只是**不再由任何环境派生**。
public nonisolated enum ShopCatalogPublishTargetEnvironment: String, Codable, CaseIterable, Sendable, Identifiable {
    case development
    case production

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .development: return "Development"
        case .production: return "Production"
        }
    }

    public var guidance: String {
        switch self {
        case .development:
            return "Development 只有团队成员与本地构建能读到；TestFlight / App Store 读的是 Production。"
        case .production:
            return "Production 面向全部用户。发之前请确认已在 Development 验证过同一份产物。"
        }
    }
}

/// 发布适配器（与 `publish_cloudkit.py --adapter` 同值）。
public nonisolated enum ShopCatalogPublishAdapter: String, Codable, CaseIterable, Sendable {
    case cloudkit
    case filesystem

    public var displayName: String {
        self == .cloudkit ? "CloudKit 公共库" : "本机目录演练"
    }
}

// MARK: - 发布阶段（与 Python 七步顺序逐条对应）

public nonisolated enum ShopCatalogPublishStage: String, Codable, CaseIterable, Sendable {

    /// 冻结草稿快照（App 侧完成，不在 Python 里）
    case freeze
    /// 构建不可变产物（`build_release.py`）
    case build
    /// 复校验产物（`publish_cloudkit.py` 第 1 步 / `validate_release.py`）
    case verifyArtifact
    /// 读当前 THRelease + changeTag（第 2 步）
    case readHead
    /// 上传缺失 THMedia（第 3 步）
    case uploadMedia
    /// 上传缺失 THDataPack（第 4 步）
    case uploadPacks
    /// 回读资源并核对摘要（第 5 步）
    case readBack
    /// 条件更新 THRelease（第 6 步，**唯一**版本生效点）
    case switchHead
    /// 回读确认发布头（第 7 步）
    case confirmHead
    /// 读线上基线（只读，用于 R07 的过期检测）
    case baseline

    public var id: String { rawValue }

    /// 七步里的序号（`baseline` 与 `freeze` 不在七步内，返回 nil）。
    public var stepOrdinal: Int? {
        switch self {
        case .freeze, .baseline: return nil
        case .build: return 1
        case .verifyArtifact: return 1
        case .readHead: return 2
        case .uploadMedia: return 3
        case .uploadPacks: return 4
        case .readBack: return 5
        case .switchHead: return 6
        case .confirmHead: return 7
        }
    }

    public var displayName: String {
        switch self {
        case .freeze: return "冻结草稿快照"
        case .build: return "构建不可变产物"
        case .verifyArtifact: return "复校验产物"
        case .readHead: return "读取发布头"
        case .uploadMedia: return "上传缺失图片"
        case .uploadPacks: return "上传缺失数据包"
        case .readBack: return "回读核对资源"
        case .switchHead: return "切换发布头"
        case .confirmHead: return "回读确认发布头"
        case .baseline: return "读取线上基线"
        }
    }

    /// 这一步完成后，线上版本是否已经改变。**只有 `switchHead` 之后才是「已生效」**。
    public var changesLiveVersion: Bool { self == .switchHead }

    /// 在这一步之前失败 = 线上还是旧版本（可安全重试）；
    /// 在这之后失败 = 结果待确认（**禁止**换号重发）。
    public var isBeforeHeadSwitch: Bool {
        guard let ordinal = stepOrdinal else { return true }
        return ordinal < 6
    }
}

public nonisolated enum ShopCatalogPublishStageState: String, Codable, Sendable {
    case started
    case succeeded
    case failed
    case skipped
}

// MARK: - 发布执行状态（方案 §6.2 的第二条状态轴）

/// **发布执行状态**：与「编辑/审核状态」完全独立的一条轴。
///
/// 两条轴不能合并的典型反例：
///   · 编辑状态 = 草稿（本地还没保存），发布状态 = 已确认（线上是上一版）→ 完全正常；
///   · 编辑状态 = 已审核（本地校验通过），发布状态 = 结果待确认 → 也完全正常。
/// 合并成一个「状态」列之后，运营看到的就是一个说不清含义的绿点。
public nonisolated enum ShopCatalogPublishExecutionState: String, Codable, CaseIterable, Sendable {

    /// 已冻结快照，还没提交
    case frozen
    case building
    case uploading
    case verifying
    /// 正在切发布头（唯一生效点）
    case switchingHead
    /// **结果不明**：必须先回读查询，禁止换号重发（R09）
    case pendingConfirmation
    /// 回读确认：线上发布头已指向本次产物
    case confirmed
    /// 切头前失败：旧版仍有效，可安全重试
    case retryableFailure
    /// 基线 / changeTag 冲突：必须先合并再重新确认
    case conflict
    /// 已被更高版本取代：不得回写旧版
    case replaced
    /// 校验 / 权限 / 环境拒绝：重试无用
    case refused

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .frozen: return "已冻结"
        case .building: return "构建产物"
        case .uploading: return "上传资源"
        case .verifying: return "回读核对"
        case .switchingHead: return "切换发布头"
        case .pendingConfirmation: return "结果待确认"
        case .confirmed: return "发布已确认"
        case .retryableFailure: return "可重试失败"
        case .conflict: return "冲突待处理"
        case .replaced: return "已被取代"
        case .refused: return "已拒绝"
        }
    }

    /// 终态（不会再自己前进）
    public var isTerminal: Bool {
        switch self {
        case .pendingConfirmation, .confirmed, .retryableFailure, .conflict, .replaced, .refused:
            return true
        case .frozen, .building, .uploading, .verifying, .switchingHead:
            return false
        }
    }

    /// 是否已经对用户生效（**只有 confirmed**）。
    /// 「已上传」「产物已构建」「回读核对通过」都不算。
    public var isLive: Bool { self == .confirmed }

    /// 允许再次提交同一份快照。`pendingConfirmation` 必须**先查询**，
    /// 因为它很可能已经生效了 —— 换号重发会造成重复发布 + 旧版回写。
    public var allowsResubmit: Bool {
        switch self {
        case .frozen, .retryableFailure, .refused: return true
        case .building, .uploading, .verifying, .switchingHead,
             .pendingConfirmation, .confirmed, .conflict, .replaced:
            return false
        }
    }

    /// 是否必须先做「结果查询」才能决定下一步
    public var requiresResultQuery: Bool { self == .pendingConfirmation }

    public var guidance: String {
        switch self {
        case .frozen:
            return "快照已冻结，可以提交。同一份快照重复提交会复用同一个请求号（幂等）。"
        case .building:
            return "正在构建不可变产物。这一步失败时线上仍是旧版本。"
        case .uploading:
            return "正在上传不可变资源。中断只会留下未被引用的孤儿资源，下次按摘要复用。"
        case .verifying:
            return "正在回读核对资源摘要。摘要漂移会在这一步中止，比覆盖上去安全。"
        case .switchingHead:
            return "正在条件更新发布头 —— 这是**唯一**让新版本对用户生效的动作。"
        case .pendingConfirmation:
            return "切头后没有拿到明确结果。**先查询线上发布头再决定**："
                + "与本次产物一致 = 已经成功；未生效 = 按原任务安全恢复；已被更高版本取代 = 不得回写。"
        case .confirmed:
            return "已回读确认线上发布头指向本次产物。这不代表每一台离线设备都已经刷新。"
        case .retryableFailure:
            return "在切换发布头之前失败，线上仍是旧版本，可以安全重试同一份快照。"
        case .conflict:
            return "线上发布头已被改动（changeTag 变化或基线过期）。"
                + "需要重新读取线上版本、合并对方改动后再确认，不能直接覆盖。"
        case .replaced:
            return "线上已经出现更高的发布号，本次产物已被取代。**不要**回写旧版本。"
        case .refused:
            return "产物没通过校验 / 权限不足 / 环境不符，重试不会改变结果，请先修配置。"
        }
    }

    /// 允许的状态转移（写死成表，避免各处 `switch` 各写一套而分叉）。
    public static func canTransition(
        from: ShopCatalogPublishExecutionState, to: ShopCatalogPublishExecutionState
    ) -> Bool {
        switch (from, to) {
        case (.frozen, .building),
             (.building, .uploading),
             (.building, .retryableFailure),
             (.building, .refused),
             (.building, .conflict),
             (.uploading, .verifying),
             (.uploading, .retryableFailure),
             (.uploading, .refused),
             (.uploading, .conflict),
             (.verifying, .switchingHead),
             (.verifying, .retryableFailure),
             (.verifying, .refused),
             (.verifying, .conflict),
             // 切头之后只有三种归宿：确认 / 待确认 / 冲突。
             // 注意 (.switchingHead, .retryableFailure) **不在表里** ——
             // 那正是「把结果不明当成可重试」的错误，会造成重复发布。
             (.switchingHead, .confirmed),
             (.switchingHead, .pendingConfirmation),
             (.switchingHead, .conflict),
             // 查询结果待确认的任务 → 三种结论
             (.pendingConfirmation, .confirmed),
             (.pendingConfirmation, .retryableFailure),
             (.pendingConfirmation, .replaced),
             (.pendingConfirmation, .conflict),
             // 重试 / 修好配置后重来
             (.retryableFailure, .building),
             (.conflict, .frozen),
             (.conflict, .building),
             (.refused, .frozen),
             // 同一状态重复上报（同一步重试）是允许的
             (.frozen, .frozen),
             (.confirmed, .confirmed):
            return true
        default:
            return false
        }
    }
}

// MARK: - 结果分类

/// 桥接器给出的**最终结论**。
public nonisolated enum ShopCatalogPublishOutcome: String, Codable, CaseIterable, Sendable {
    /// 回读确认，线上发布头已指向本次产物
    case confirmed
    /// 结果不明（切头后响应丢失 / 进程被杀 / 超时）：先查询
    case pendingConfirmation
    /// changeTag 冲突或基线过期
    case conflict
    /// 已被更高版本取代
    case replaced
    /// 校验 / 权限 / 环境拒绝（重试无用）
    case refused
    /// 可重试失败（切头前）
    case failed

    public var displayName: String {
        switch self {
        case .confirmed: return "发布已确认"
        case .pendingConfirmation: return "结果待确认"
        case .conflict: return "冲突"
        case .replaced: return "已被取代"
        case .refused: return "已拒绝"
        case .failed: return "失败"
        }
    }

    /// 直接映射到执行状态。**所有映射都只往保守方向走**：
    /// 任何「说不清」的结论一律落到 `pendingConfirmation`，绝不落到 `confirmed`。
    public var executionState: ShopCatalogPublishExecutionState {
        switch self {
        case .confirmed: return .confirmed
        case .pendingConfirmation: return .pendingConfirmation
        case .conflict: return .conflict
        case .replaced: return .replaced
        case .refused: return .refused
        case .failed: return .retryableFailure
        }
    }
}

// MARK: - 发布请求

/// 交给桥接器的**冻结请求**。它是一份数据，不是可执行指令：
/// 里面没有 shell 片段、没有凭证、没有可被拼接的命令行参数（方案 §5.2）。
public nonisolated struct ShopCatalogPublishRequest: Codable, Equatable, Sendable {

    /// 协议版本（桥接器与 App 必须一致）
    public var schemaVersion: Int = ShopCatalogPublishProtocol.schemaVersion
    /// 幂等键：同一份冻结快照必须复用同一个 requestID（见 `RequestKey`）
    public var requestID: String
    /// 本次执行的任务号（同一 requestID 重试也算同一次任务）
    public var jobID: String
    public var draftID: String
    /// 冻结时的编辑版本号
    public var draftRevision: Int
    public var baseReleaseSeq: Int?
    public var baseRootIndexHash: String?
    /// 运营是否**显式确认**「没有其他人先发过」（基线未知时的唯一出口）。
    /// 记录在请求里 = 可审计，而不是界面上一句口头承诺。
    public var baselineAcknowledged: Bool
    public var targetEnvironment: ShopCatalogPublishTargetEnvironment
    public var adapter: ShopCatalogPublishAdapter
    /// 本次要发布的号（必须严格大于线上当前值；由运营确认）
    public var releaseSeq: Int
    /// `build_release.py --input`：存放其他分片与已审核输入的目录
    public var inputDirectory: String
    /// `build_release.py --shop-catalog-archive`：运营导出的待发布整包（tar）
    public var archivePath: String
    /// `build_release.py --output`：不可变产物目录
    public var outputDirectory: String
    /// `publish_cloudkit.py --receipt`：回执落盘路径
    public var receiptPath: String
    /// `filesystem` 适配器的演练根目录
    public var filesystemRoot: String?
    /// 演练（不写入）
    public var dryRun: Bool
    /// 待发布包摘要（SHA-256，App 侧算好）——用于回执核对与「同一产物」判定
    public var payloadHash: String
    public var createdAt: Date

    // 跨模块构造入口：`public` 结构体的合成逐成员 init 是 internal，外部模块必须显式声明。
    public init(
        schemaVersion: Int = ShopCatalogPublishProtocol.schemaVersion,
        requestID: String,
        jobID: String,
        draftID: String,
        draftRevision: Int,
        baseReleaseSeq: Int? = nil,
        baseRootIndexHash: String? = nil,
        baselineAcknowledged: Bool = false,
        targetEnvironment: ShopCatalogPublishTargetEnvironment,
        adapter: ShopCatalogPublishAdapter? = nil,
        releaseSeq: Int,
        inputDirectory: String,
        archivePath: String,
        outputDirectory: String,
        receiptPath: String,
        filesystemRoot: String? = nil,
        dryRun: Bool = false,
        payloadHash: String,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.jobID = jobID
        self.draftID = draftID
        self.draftRevision = draftRevision
        self.baseReleaseSeq = baseReleaseSeq
        self.baseRootIndexHash = baseRootIndexHash
        self.baselineAcknowledged = baselineAcknowledged
        self.targetEnvironment = targetEnvironment
        // 适配器不再由环境派生（两个环境都走 CloudKit）：想用 filesystem 就显式传。
        self.adapter = adapter ?? .cloudkit
        self.releaseSeq = releaseSeq
        self.inputDirectory = inputDirectory
        self.archivePath = archivePath
        self.outputDirectory = outputDirectory
        self.receiptPath = receiptPath
        self.filesystemRoot = filesystemRoot
        self.dryRun = dryRun
        self.payloadHash = payloadHash
        self.createdAt = createdAt
    }

    /// 落盘用的 JSON 字节。**写请求文件是 App 唯一的「提交」动作**，
    /// 之后桥接器只读这个文件，不从命令行接收任何业务参数。
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> ShopCatalogPublishRequest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ShopCatalogPublishRequest.self, from: data)
    }

    /// 请求摘要（界面显示 / 日志留痕；**不含任何路径之外的敏感信息**）。
    public var summaryText: String {
        "\(targetEnvironment.displayName) · releaseSeq \(releaseSeq) · 第 \(draftRevision) 版"
            + " · 产物 \(payloadHash.prefix(12))…"
    }
}

// MARK: - 幂等键

public nonisolated enum ShopCatalogPublishProtocol {
    /// 与桥接器 `PROTOCOL_SCHEMA_VERSION` 逐字对齐
    public static let schemaVersion = 1
}

/// 请求号（幂等键）派生。
///
/// 口径（方案 §5.2）：
///   · **同一份冻结快照**重复点提交 → 同一个 requestID（幂等，不会重复发布）；
///   · 改了内容 → draftRevision 与 payloadHash 都变 → 新 requestID；
///   · 明确改了发布号（例如冲突后重新定号）→ 也是新 requestID。
public nonisolated enum ShopCatalogPublishRequestKey {
    public static func make(
        draftID: String,
        draftRevision: Int,
        payloadHash: String,
        targetEnvironment: ShopCatalogPublishTargetEnvironment,
        releaseSeq: Int
    ) -> String {
        [
            draftID,
            "rev\(draftRevision)",
            "seq\(releaseSeq)",
            targetEnvironment.rawValue,
            payloadHash,
        ].joined(separator: "|")
    }
}

// MARK: - 进度事件（NDJSON 一行一条）

/// 桥接器逐行吐出的结构化事件。
///
/// 用一个「字段全可选」的扁平结构而不是 `enum` + associated values：
/// NDJSON 解码端要能**忽略不认识的 type 与字段**（前后版本共存），
/// 枚举会让一个新 type 直接把整行解不出来 —— 那样的失败是静默的。
public nonisolated struct ShopCatalogPublishEvent: Codable, Equatable, Sendable {

    /// `stage` / `log` / `artifact` / `receipt` / `result` / `baseline` / `catalog` / `hello`
    public var type: String
    public var at: Date?

    /// 桥接器在 `hello` 事件里声明的协议版本。App 在**开始跑之前**就能据此
    /// 判断「对面是不是我认识的桥接器」，而不是等一个人畜无害的失败。
    public var schemaVersion: Int?

    // stage
    public var stage: ShopCatalogPublishStage?
    public var state: ShopCatalogPublishStageState?
    public var stepOrdinal: Int?
    public var completed: Int?
    public var total: Int?

    // log
    public var level: String?
    public var message: String?

    // artifact / receipt / result / baseline
    public var releaseSeq: Int?
    public var rootIndexHash: String?
    public var payloadHash: String?
    public var path: String?
    public var itemCounts: [String: Int]?
    public var outcome: ShopCatalogPublishOutcome?
    public var exitCode: Int?
    public var retryable: Bool?

    // 跨模块构造入口：`public` 结构体的合成逐成员 init 是 internal，外部模块必须显式声明。
    public init(
        type: String,
        at: Date? = nil,
        schemaVersion: Int? = nil,
        stage: ShopCatalogPublishStage? = nil,
        state: ShopCatalogPublishStageState? = nil,
        stepOrdinal: Int? = nil,
        completed: Int? = nil,
        total: Int? = nil,
        level: String? = nil,
        message: String? = nil,
        releaseSeq: Int? = nil,
        rootIndexHash: String? = nil,
        payloadHash: String? = nil,
        path: String? = nil,
        itemCounts: [String: Int]? = nil,
        outcome: ShopCatalogPublishOutcome? = nil,
        exitCode: Int? = nil,
        retryable: Bool? = nil
    ) {
        self.type = type
        self.at = at
        self.schemaVersion = schemaVersion
        self.stage = stage
        self.state = state
        self.stepOrdinal = stepOrdinal
        self.completed = completed
        self.total = total
        self.level = level
        self.message = message
        self.releaseSeq = releaseSeq
        self.rootIndexHash = rootIndexHash
        self.payloadHash = payloadHash
        self.path = path
        self.itemCounts = itemCounts
        self.outcome = outcome
        self.exitCode = exitCode
        self.retryable = retryable
    }

    /// 解码一行 NDJSON。**解不开返回 nil，调用方原样留痕** ——
    /// 悄悄丢弃会让「桥接器升级后界面不再前进」变成无法定位的问题。
    public static func decoded(fromLine line: String) -> ShopCatalogPublishEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ShopCatalogPublishEvent.self, from: data)
    }

    /// 给运营看的一行文案（nil = 这条事件不需要单独显示）
    public var displayLine: String? {
        switch type {
        case "hello":
            return message ?? "已连接受控发布器"
        case "log":
            guard let message else { return nil }
            return "[\(level ?? "info")] \(message)"
        case "stage":
            guard let stage else { return nil }
            switch state {
            case .started: return "\(stage.displayName)…"
            case .succeeded: return "\(stage.displayName)：完成"
            case .failed: return "\(stage.displayName)：失败"
            case .skipped: return "\(stage.displayName)：跳过"
            case .none: return nil
            }
        case "artifact":
            return "产物已就绪：releaseSeq \(releaseSeq ?? 0) · 摘要 \(String((rootIndexHash ?? "").prefix(12)))…"
        case "baseline":
            guard let releaseSeq else { return "线上基线：未读到" }
            return "线上基线：releaseSeq \(releaseSeq)"
        case "catalog":
            // 只有 `pull-catalog` 会发这条。明细（各类条数）由界面自己排，
            // 这里只说「拉回来了」—— 一行文案扛不下十几个计数，硬塞会变成噪音。
            return "已拉回线上商店目录：releaseSeq \(releaseSeq ?? 0) · 摘要 \(String((rootIndexHash ?? "").prefix(12)))…"
        case "receipt":
            return "发布回执已写入 \(path ?? "（路径未知）")"
        case "result":
            guard let outcome else { return nil }
            return "结论：\(outcome.displayName)\(message.map { " —— \($0)" } ?? "")"
        default:
            return nil
        }
    }
}

// MARK: - 回执

/// 发布回执。字段名与 `publish_cloudkit.py --receipt` 写出的 JSON 对齐，
/// 另外补上「任务归属」与「回读确认」两组字段（App 侧核对用）。
public nonisolated struct ShopCatalogPublishReceipt: Codable, Equatable, Sendable {

    public var adapter: String?
    public var environment: String?
    public var applied: Bool?
    public var releaseSeq: Int?
    public var revocationEpoch: Int?
    public var rootIndexHash: String?
    public var previousChangeTag: String?
    public var newChangeTag: String?
    public var uploadedPacks: Int?
    public var uploadedMedia: Int?
    public var totalPacks: Int?
    public var totalMedia: Int?

    /// 任务归属（App 写进请求、桥接器原样回填）
    public var requestID: String?
    public var jobID: String?
    public var draftID: String?
    public var draftRevision: Int?
    /// 待发布包摘要（App 侧计算）
    public var artifactDigest: String?
    /// 桥接器回读到的线上发布头是否与本次产物一致
    public var readBackConfirmed: Bool?
    /// 回读时刻
    public var verifiedAt: Date?
    /// 产物里的条目计数（商品 / 规格 / 图片…）
    public var itemCounts: [String: Int]?

    // 跨模块构造入口：`public` 结构体的合成逐成员 init 是 internal，外部模块必须显式声明。
    public init(
        adapter: String? = nil,
        environment: String? = nil,
        applied: Bool? = nil,
        releaseSeq: Int? = nil,
        revocationEpoch: Int? = nil,
        rootIndexHash: String? = nil,
        previousChangeTag: String? = nil,
        newChangeTag: String? = nil,
        uploadedPacks: Int? = nil,
        uploadedMedia: Int? = nil,
        totalPacks: Int? = nil,
        totalMedia: Int? = nil,
        requestID: String? = nil,
        jobID: String? = nil,
        draftID: String? = nil,
        draftRevision: Int? = nil,
        artifactDigest: String? = nil,
        readBackConfirmed: Bool? = nil,
        verifiedAt: Date? = nil,
        itemCounts: [String: Int]? = nil
    ) {
        self.adapter = adapter
        self.environment = environment
        self.applied = applied
        self.releaseSeq = releaseSeq
        self.revocationEpoch = revocationEpoch
        self.rootIndexHash = rootIndexHash
        self.previousChangeTag = previousChangeTag
        self.newChangeTag = newChangeTag
        self.uploadedPacks = uploadedPacks
        self.uploadedMedia = uploadedMedia
        self.totalPacks = totalPacks
        self.totalMedia = totalMedia
        self.requestID = requestID
        self.jobID = jobID
        self.draftID = draftID
        self.draftRevision = draftRevision
        self.artifactDigest = artifactDigest
        self.readBackConfirmed = readBackConfirmed
        self.verifiedAt = verifiedAt
        self.itemCounts = itemCounts
    }

    public static func decoded(from data: Data) throws -> ShopCatalogPublishReceipt {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ShopCatalogPublishReceipt.self, from: data)
    }

    /// 一句话结论（**不含「已生效」以外的任何幻觉措辞**）
    public var summaryText: String {
        guard applied == true else {
            return "演练（未写入）：\(environment ?? "未知环境") · releaseSeq \(releaseSeq ?? 0)"
        }
        let env = environment ?? "未知环境"
        let confirmed = (readBackConfirmed == true) ? "已回读确认" : "未回读确认"
        return "\(env) · releaseSeq \(releaseSeq ?? 0) · \(confirmed)"
    }
}
