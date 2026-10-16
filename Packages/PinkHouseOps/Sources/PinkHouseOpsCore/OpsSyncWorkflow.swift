import Foundation

public nonisolated enum OpsSyncStep: String, Codable, CaseIterable, Sendable, Identifiable {
    case download, upload, merge
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .download: return "1 · 下载平台内容"
        case .upload: return "2 · 上传本地变更"
        case .merge: return "3 · 合并落盘确认"
        }
    }
}

public nonisolated enum OpsSyncState: String, Codable, Sendable {
    case waiting, running, completed, partial, blocked, failed, skipped
    public var title: String {
        switch self {
        case .waiting: return "等待"
        case .running: return "进行中"
        case .completed: return "完成"
        case .partial: return "部分完成"
        case .blocked: return "待修复"
        case .failed: return "未完成"
        case .skipped: return "未执行"
        }
    }
}

public nonisolated struct OpsSyncIssue: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var step: OpsSyncStep
    public var owner: String
    public var message: String
    public var productIDs: [String]
    public init(id: String, step: OpsSyncStep, owner: String, message: String, productIDs: [String] = []) {
        self.id = id; self.step = step; self.owner = owner; self.message = message
        self.productIDs = productIDs
    }
}

public nonisolated struct OpsSyncStepReport: Codable, Equatable, Sendable, Identifiable {
    public var step: OpsSyncStep
    public var state: OpsSyncState = .waiting
    public var detail: String = "尚未执行"
    public var progress: Double?
    public var logPaths: [String] = []
    public var id: String { step.rawValue }
    public init(step: OpsSyncStep) { self.step = step }
}

public nonisolated struct OpsSyncReport: Codable, Equatable, Sendable {
    public var draftID: String
    public var environment: String
    public var steps: [OpsSyncStepReport] = OpsSyncStep.allCases.map { .init(step: $0) }
    public var issues: [OpsSyncIssue] = []
    public var releaseSeq: Int?
    public init(draftID: String, environment: String) {
        self.draftID = draftID; self.environment = environment
    }
    public var isRunning: Bool { steps.contains { $0.state == .running } }
    public var isComplete: Bool { steps.allSatisfy { $0.state == .completed } }
    public var hasProgress: Bool { steps.contains { $0.state == .completed || $0.state == .partial } }
    public var title: String {
        if isRunning { return "同步中" }
        if isComplete { return "同步完成" }
        return hasProgress ? "同步部分完成" : "同步未完成"
    }
    public var summary: String {
        let progress = steps.map { "\($0.step.title)：\($0.state.title)（\($0.detail)）" }.joined(separator: "\n")
        guard !issues.isEmpty else { return progress }
        return progress + "\n" + issues.map { "待处理 · \($0.owner)：\($0.message)" }.joined(separator: "\n")
    }
    public mutating func update(_ step: OpsSyncStep, state: OpsSyncState, detail: String,
                                progress: Double? = nil, logPaths: [String] = []) {
        guard let index = steps.firstIndex(where: { $0.step == step }) else { return }
        steps[index].state = state; steps[index].detail = detail
        steps[index].progress = state == .completed ? 1 : progress
        if !logPaths.isEmpty { steps[index].logPaths = logPaths }
    }
    public mutating func addIssues(_ issues: [OpsSyncIssue]) {
        for issue in issues where !self.issues.contains(where: { $0.id == issue.id }) { self.issues.append(issue) }
    }
    public mutating func recoverInterruptedRun() {
        guard isRunning else { return }
        for index in steps.indices {
            if steps[index].state == .running {
                let step = steps[index].step
                let message = step == .upload
                    ? "上次同步在上传阶段中断，云端结果尚未确认；请先查询发布结果再决定是否重试"
                    : "上次同步在此步骤中断，已完成步骤保留；请核对日志后继续"
                steps[index].state = .failed
                steps[index].detail = message
                addIssues([.init(id: "interrupted-\(step.rawValue)", step: step, owner: "上次同步", message: message)])
            } else if steps[index].state == .waiting {
                steps[index].state = .skipped
                steps[index].detail = "上次运行中断，此步骤未执行"
            }
        }
    }
}

public nonisolated struct OpsSyncStepResult: Sendable {
    public var state: OpsSyncState
    public var detail: String
    public var canContinue: Bool
    public var issues: [OpsSyncIssue]
    public var logPaths: [String]
    public var releaseSeq: Int?
    public var progress: Double?
    public init(_ state: OpsSyncState, _ detail: String, canContinue: Bool = true,
                issues: [OpsSyncIssue] = [], logPaths: [String] = [], releaseSeq: Int? = nil,
                progress: Double? = nil) {
        self.state = state; self.detail = detail; self.canContinue = canContinue
        self.issues = issues; self.logPaths = logPaths; self.releaseSeq = releaseSeq
        self.progress = progress
    }
}

/// 下载、上传与本地保存独立结算。上传受阻不能阻止已下载内容合并落盘。
@MainActor public enum OpsSyncWorkflow {
    public static func run(
        report: OpsSyncReport,
        download: () async -> OpsSyncStepResult,
        upload: () async -> OpsSyncStepResult,
        merge: () async -> OpsSyncStepResult,
        changed: (OpsSyncReport) -> Void
    ) async -> OpsSyncReport {
        var report = report
        for step in OpsSyncStep.allCases {
            report.update(step, state: .running, detail: step.title)
            changed(report)
            let result: OpsSyncStepResult
            switch step {
            case .download: result = await download()
            case .upload: result = await upload()
            case .merge: result = await merge()
            }
            report.update(step, state: result.state, detail: result.detail,
                          progress: result.progress, logPaths: result.logPaths)
            report.addIssues(result.issues)
            if let seq = result.releaseSeq { report.releaseSeq = seq }
            changed(report)
            // 只有没有可信下载基线时才停止后续动作。上传失败仍执行 merge。
            if step == .download && !result.canContinue {
                report.update(.upload, state: .skipped, detail: "没有可信线上目录，尚未尝试上传")
                report.update(.merge, state: .skipped, detail: "未取得目录，当前草稿保留")
                changed(report)
                break
            }
        }
        return report
    }
}
