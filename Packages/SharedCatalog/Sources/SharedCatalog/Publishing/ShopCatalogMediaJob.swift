//
//  ShopCatalogMediaJob.swift
//  SharedCatalog
//
//  图片上传任务的状态机（计划 §6 P0）。
//
//  ## 为什么要有显式状态机
//
//  发布是一串**有顺序、有幂等要求**的动作：规范化 → 上传 THMedia → 回读核对 hash
//  → 上传 THDataPack → 条件切换 THRelease。任何一步失败都必须能**从原地重来**，
//  而不是重跑整条链（重跑会重复上传、甚至在发布头已经切了的情况下再切一次）。
//
//  计划 §7 给的口径，本文件逐条落实：
//    · 网络失败：本地任务不丢，指数退避后可重试；
//    · **权限失败：显示环境、账号和角色，不盲目重试**（所以要区分失败种类）；
//    · 图片上传成功但发布头尚未切换：允许孤儿 `THMedia` 留在公共库，
//      下一次按 hash 复用 —— 也就是说 `verified` 是可以跨会话复用的终态，
//      不要因为「本次运行没走完」就把它清掉。
//
//  ## 状态转移图
//
//      staged ──▶ uploading ──▶ verified        （终态；同 hash 复用）
//                     │
//                     └──▶ failed ──▶ retryable ──▶ uploading
//                            │            │
//                            └────────────┴──▶ failed（预算耗尽 / 不可重试）
//
//  `verified` 之外的终态只有「重试预算耗尽」，此时必须让人看见并人工决定。
//

import Foundation

// MARK: - 状态

public nonisolated enum MediaUploadJobState: String, Codable, CaseIterable, Sendable {
    /// 已规范化落盘，还没上传
    case staged
    /// 正在上传（上传中进程被杀 → 下次启动按 `uploading` 恢复成 `retryable`）
    case uploading
    /// 已上传且回读核对通过 —— 终态，按 hash 幂等复用
    case verified
    /// 失败且**当前不允许**重试（权限 / 校验类），需要人工处理
    case failed
    /// 失败但可重试（网络类），等退避时间到了就能再发
    case retryable

    public var displayName: String {
        switch self {
        case .staged: return "待上传"
        case .uploading: return "上传中"
        case .verified: return "已上传"
        case .failed: return "失败"
        case .retryable: return "待重试"
        }
    }

    /// 是否还需要动作（进度统计用；`verified` / `failed` 不再自动推进）
    public var needsWork: Bool {
        switch self {
        case .staged, .uploading, .retryable: return true
        case .verified, .failed: return false
        }
    }
}

// MARK: - 失败分类

/// 失败**必须分类**，否则「权限不够」会被当成「网络抖动」无限重试 ——
/// 计划 §7 明确要求权限失败要显示环境/账号/角色，不盲目重试。
public nonisolated enum MediaUploadFailureKind: String, Codable, CaseIterable, Sendable {
    /// 网络/超时/5xx：退避后可重试
    case network
    /// 权限 / 未登录 iCloud / 角色不足：重试无用，要人去改配置
    case permission
    /// 发布头 changeTag 冲突或 releaseSeq 不递增：要重新读线上状态再决定
    case conflict
    /// 校验失败（hash 不符 / MIME 被拒 / 结构不合法）：产物本身有问题
    case validation
    /// 环境选错（Development / Production 弄反）：必须人工纠正
    case environment
    /// 其余：允许有限重试，但要在界面上原样显示底层错误
    case unknown

    /// 只有「换一次网络就好」和「重读状态再来一次」适合自动重试
    public var isRetryable: Bool {
        switch self {
        case .network, .conflict, .unknown: return true
        case .permission, .validation, .environment: return false
        }
    }

    /// 给运营看的处置建议（不允许只显示一个红色感叹号）
    public var guidance: String {
        switch self {
        case .network:
            return "网络或服务端暂时不可用，稍后会自动重试；也可以立即手动重试。"
        case .permission:
            return "当前账号没有写入公共库的权限。请确认发布用的 iCloud 账号/CloudKit 角色与环境（Development / Production）配置，改好再重试。"
        case .conflict:
            return "线上发布头已被改动（changeTag 变化）。需要重新读取线上版本后再决定是否发布，不能直接覆盖。"
        case .validation:
            return "本地产物没通过校验（图片 hash、类型或目录结构）。请检查素材后重新生成，重试不会改变结果。"
        case .environment:
            return "发布环境与预期不符（Development / Production 弄反了）。请人工确认后再操作。"
        case .unknown:
            return "出现了未归类的错误，界面下方有原始信息。可以有限重试。"
        }
    }
}

// MARK: - 任务

/// 一条媒体上传任务。`id` 就是 `mediaKey` —— 同内容的图天然只有一条任务，
/// 幂等复用不需要额外查重逻辑。
public struct MediaUploadJob: Identifiable, Codable, Hashable, Sendable {
    public var id: String { mediaKey }

    /// 规范化后字节的 SHA-256
    public var mediaKey: String
    /// staging 目录里的文件名（`<mediaKey>.<ext>`）
    public var stagedFileName: String
    public var byteCount: Int
    public var mimeType: String
    public var state: MediaUploadJobState
    /// 已尝试次数（进入 `uploading` 就 +1）
    public var attemptCount: Int
    public var failureKind: MediaUploadFailureKind?
    public var lastErrorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var verifiedAt: Date?

    public init(
        mediaKey: String,
        stagedFileName: String,
        byteCount: Int,
        mimeType: String,
        state: MediaUploadJobState = .staged,
        attemptCount: Int = 0,
        failureKind: MediaUploadFailureKind? = nil,
        lastErrorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        verifiedAt: Date? = nil
    ) {
        self.mediaKey = mediaKey
        self.stagedFileName = stagedFileName
        self.byteCount = byteCount
        self.mimeType = mimeType
        self.state = state
        self.attemptCount = attemptCount
        self.failureKind = failureKind
        self.lastErrorMessage = lastErrorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.verifiedAt = verifiedAt
    }
}

// MARK: - 状态机

public nonisolated enum MediaUploadJobTransitionError: LocalizedError, Equatable {
    case illegal(from: MediaUploadJobState, to: MediaUploadJobState)
    case retryBudgetExhausted(attempts: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .illegal(let from, let to):
            return "非法的任务状态转移：\(from.rawValue) → \(to.rawValue)"
        case .retryBudgetExhausted(let attempts, let limit):
            return "重试次数已用尽（\(attempts)/\(limit)），请人工确认后再处理。"
        }
    }
}

public nonisolated enum MediaUploadJobMachine {

    /// 自动重试次数上限。超过后落到 `failed`，**必须让人看见**，
    /// 不允许无限重试把失败掩盖成「一直在转圈」。
    public static let maxAttempts = 5

    /// 指数退避：2s / 4s / 8s / 16s / 32s / 60s，之后一路 60s。
    /// 依据只有 `attemptCount`（纯函数，可单测），不读时钟。
    ///
    /// 注意指数取 `attemptCount` 本身而不是 `attemptCount - 1`：后者会让第 1、2 次
    /// 都退避 2s，而代码上限取 5 时 2^5=32 使「封顶 60s」永远走不到（死代码）。
    public static func retryDelay(forAttempt attemptCount: Int) -> TimeInterval {
        let exponent = min(max(attemptCount, 1), 6)
        return min(60, pow(2, Double(exponent)))
    }

    /// 允许的转移。写死成表，避免各处 `switch` 各写一套而分叉。
    public static func canTransition(
        from: MediaUploadJobState, to: MediaUploadJobState
    ) -> Bool {
        switch (from, to) {
        case (.staged, .uploading),
             (.uploading, .verified),
             (.uploading, .failed),
             (.uploading, .retryable),
             (.retryable, .uploading),
             (.retryable, .failed),
             // 幂等复用：已上传的图再走一次流程，直接确认仍是 verified
             (.verified, .verified),
             // 恢复用：上次进程被杀时停在 uploading，重新调度即回到 retryable
             (.uploading, .staged):
            return true
        default:
            return false
        }
    }

    /// 推进任务状态。失败时**不改动**入参，调用方据此保持原状态（不丢任务）。
    public static func advance(
        _ job: inout MediaUploadJob,
        to state: MediaUploadJobState,
        failureKind: MediaUploadFailureKind? = nil,
        errorMessage: String? = nil,
        now: Date = Date()
    ) throws {
        guard canTransition(from: job.state, to: state) else {
            throw MediaUploadJobTransitionError.illegal(from: job.state, to: state)
        }
        switch state {
        case .uploading:
            job.attemptCount += 1
            job.failureKind = nil
            job.lastErrorMessage = nil
        case .verified:
            job.verifiedAt = now
            job.failureKind = nil
            job.lastErrorMessage = nil
        case .failed:
            job.failureKind = failureKind ?? job.failureKind
            job.lastErrorMessage = errorMessage ?? job.lastErrorMessage
        case .retryable:
            job.failureKind = failureKind ?? .network
            job.lastErrorMessage = errorMessage ?? job.lastErrorMessage
        case .staged:
            break
        }
        job.state = state
        job.updatedAt = now
    }

    /// 失败入口：**按失败种类与剩余预算决定落到 `retryable` 还是 `failed`**。
    /// 这是计划 §7「权限失败不盲目重试」的落地点。
    public static func recordFailure(
        _ job: inout MediaUploadJob,
        kind: MediaUploadFailureKind,
        message: String,
        now: Date = Date()
    ) throws {
        let canRetry = kind.isRetryable && job.attemptCount < maxAttempts
        try advance(
            &job,
            to: canRetry ? .retryable : .failed,
            failureKind: kind,
            errorMessage: message,
            now: now)
    }

    /// 启动时的恢复：进程被杀留下的 `uploading` 一律回退成 `retryable`。
    ///
    /// 为什么不能保持 `uploading`：那个状态只对「正在跑的那一次运行」有意义，
    /// 新进程里它既不会前进也不会后退，界面上会永远卡在「上传中」。
    public static func recovered(_ job: MediaUploadJob, now: Date = Date()) -> MediaUploadJob {
        guard job.state == .uploading || job.state == .staged else { return job }
        var copy = job
        copy.state = .retryable
        copy.updatedAt = now
        return copy
    }

    /// 汇总进度（界面展示用）
    public struct Progress: Equatable, Sendable {
        public var total: Int
        public var verified: Int
        public var pending: Int
        public var failed: Int

        // 跨模块构造入口：`public` 结构体的合成逐成员 init 是 internal，外部模块必须显式声明。
        public init(total: Int, verified: Int, pending: Int, failed: Int) {
            self.total = total
            self.verified = verified
            self.pending = pending
            self.failed = failed
        }

        public var isComplete: Bool { total > 0 && verified == total }
        public var hasFailures: Bool { failed > 0 }
    }

    public static func progress(of jobs: [MediaUploadJob]) -> Progress {
        Progress(
            total: jobs.count,
            verified: jobs.filter { $0.state == .verified }.count,
            pending: jobs.filter { $0.state.needsWork }.count,
            failed: jobs.filter { $0.state == .failed }.count)
    }
}
