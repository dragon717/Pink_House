//
//  OpsPublishJobRecord.swift
//  PinkHouseOps
//
//  发布任务台账（SwiftData 落盘形态 + 与纯值类型 `OpsPublishJob` 的互转）。
//
//  ## 为什么发布任务必须落盘，而且必须记这么多字段
//
//  一次发布最贵的错误是「**切头之后结果不明**」：线上可能已经生效，也可能没有。
//  这时如果 App 重启后什么都记不住，运营唯一能做的就是「再发一次」——
//  而那会造成重复发布，甚至用旧内容回写已经前进的线上版本（方案 R09）。
//
//  所以落盘的最小充分集是：
//    · `requestID` —— 幂等键。同一份冻结快照重试要复用它（不是新任务）；
//    · `jobID` / `draftID` / `draftRevision` —— 这份任务对应哪一版草稿；
//    · `baseReleaseSeq` / `baseRootIndexHash` —— 冻结时的基线，用于冲突判定；
//    · `targetEnvironment` —— **选定后本任务内不得切换**（切换会让回执张冠李戴）；
//    · `releaseSeq` / `payloadHash` —— 回读核对要靠「发布号 + 产物摘要」两个一起比，
//      只比发布号会把「别人发了同一个号」误判成自己成功；
//    · `stateRawValue` / `stageRawValue` —— 执行状态轴（§6.2 的第二条轴，与编辑状态独立）；
//    · `receiptJSON` —— 回执原文，**它才是「发布已确认」的唯一依据**。
//
//  ## 命名与迁移
//
//  全新实体（新表），但仍沿用仓库口径：除了唯一键 `requestID`，**其余全部 Optional**，
//  取值统一走计算属性兜底。理由同 `OpsCatalogDraftRecord` 文件头 ——
//  不可空列要靠默认值推断，推断失败 = `ModelContainer` 抛错 = App 打不开。
//

import Foundation
import SwiftData

// MARK: - 值类型（服务层 / 视图层用）

/// 一条发布任务。`id` 就是 `requestID`（幂等键）。
struct OpsPublishJob: Identifiable, Equatable {

    var id: String { requestID }

    var requestID: String
    var jobID: String
    var draftID: String
    var draftRevision: Int
    var baseReleaseSeq: Int?
    var baseRootIndexHash: String?
    /// 运营是否显式确认过「没有其他人先发过」（基线读不到时的唯一出口，可审计）
    var baselineAcknowledged: Bool
    var targetEnvironment: ShopCatalogPublishTargetEnvironment
    var adapter: ShopCatalogPublishAdapter
    var releaseSeq: Int
    var payloadHash: String

    var state: ShopCatalogPublishExecutionState
    var stage: ShopCatalogPublishStage?
    var completedUnits: Int
    var totalUnits: Int
    var failureKind: MediaUploadFailureKind?
    var lastErrorMessage: String?
    /// 结构化事件的可见留痕（只留最后若干条，避免无限膨胀）
    var logLines: [String]
    var receipt: ShopCatalogPublishReceipt?
    var outputDirectory: String?

    var createdAt: Date
    var updatedAt: Date
    var submittedAt: Date?
    var finishedAt: Date?
    var attemptCount: Int

    init(
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
        payloadHash: String,
        state: ShopCatalogPublishExecutionState = .frozen,
        stage: ShopCatalogPublishStage? = nil,
        completedUnits: Int = 0,
        totalUnits: Int = 0,
        failureKind: MediaUploadFailureKind? = nil,
        lastErrorMessage: String? = nil,
        logLines: [String] = [],
        receipt: ShopCatalogPublishReceipt? = nil,
        outputDirectory: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        submittedAt: Date? = nil,
        finishedAt: Date? = nil,
        attemptCount: Int = 0
    ) {
        self.requestID = requestID
        self.jobID = jobID
        self.draftID = draftID
        self.draftRevision = draftRevision
        self.baseReleaseSeq = baseReleaseSeq
        self.baseRootIndexHash = baseRootIndexHash
        self.baselineAcknowledged = baselineAcknowledged
        self.targetEnvironment = targetEnvironment
        self.adapter = adapter ?? targetEnvironment.adapter
        self.releaseSeq = releaseSeq
        self.payloadHash = payloadHash
        self.state = state
        self.stage = stage
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
        self.failureKind = failureKind
        self.lastErrorMessage = lastErrorMessage
        self.logLines = logLines
        self.receipt = receipt
        self.outputDirectory = outputDirectory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.submittedAt = submittedAt
        self.finishedAt = finishedAt
        self.attemptCount = attemptCount
    }

    /// 进度是否可展示（`totalUnits == 0` 时不该显示 0/0）
    var hasUnitProgress: Bool { totalUnits > 0 }

    /// 任务是否在跑
    var isRunning: Bool {
        switch state {
        case .building, .uploading, .verifying, .switchingHead: return true
        default: return false
        }
    }

    /// 一句话状态（**不合并不同轴**：这里只说发布执行状态）
    var statusText: String {
        var parts = [state.displayName]
        if let stage, isRunning { parts.append(stage.displayName) }
        if hasUnitProgress { parts.append("\(completedUnits)/\(totalUnits)") }
        return parts.joined(separator: " · ")
    }

    /// 恢复时把「正在跑」的状态收成一个保守结论。
    ///
    /// 进程被杀时任务停在 `building/uploading/verifying` → 线上还是旧版本 → **可安全重试**；
    /// 停在 `switchingHead` → **结果不明** → 必须先查询，禁止重发。
    /// 把后者当成前者，就是 R09 要防的那次重复发布。
    static func recovered(_ job: OpsPublishJob, now: Date = Date()) -> OpsPublishJob {
        var copy = job
        switch job.state {
        case .building, .uploading, .verifying:
            copy.state = .retryableFailure
            copy.lastErrorMessage = (job.lastErrorMessage.map { $0 + "\n" } ?? "")
                + "上次运行在「\(job.stage?.displayName ?? job.state.displayName)」阶段中断，"
                + "线上仍是旧版本，可以安全重试。"
            copy.updatedAt = now
        case .switchingHead:
            copy.state = .pendingConfirmation
            copy.lastErrorMessage = (job.lastErrorMessage.map { $0 + "\n" } ?? "")
                + "上次运行在切换发布头时中断，**结果不明**：请先查询线上发布头再决定，"
                + "不要直接重发。"
            copy.updatedAt = now
        default:
            break
        }
        return copy
    }

    /// 需要人处理（工作台「待处理事项」用）
    var needsAttention: Bool {
        switch state {
        case .pendingConfirmation, .conflict, .retryableFailure, .replaced: return true
        case .refused: return true
        case .frozen, .building, .uploading, .verifying, .switchingHead, .confirmed: return false
        }
    }
}

// MARK: - 落盘形态

@Model
final class OpsPublishJobRecord {

    /// 幂等键（`ShopCatalogPublishRequestKey.make` 的产物），全库唯一
    @Attribute(.unique) var requestID: String

    var jobID: String?
    var draftID: String?
    var draftRevision: Int?
    var baseReleaseSeq: Int?
    var baseRootIndexHash: String?
    var baselineAcknowledged: Bool?
    var targetEnvironmentRaw: String?
    var adapterRaw: String?
    var releaseSeq: Int?
    var payloadHash: String?

    var stateRawValue: String?
    var stageRawValue: String?
    var completedUnits: Int?
    var totalUnits: Int?
    var failureKindRawValue: String?
    var lastErrorMessage: String?
    var logLinesJSON: Data?
    var receiptJSON: Data?
    var outputDirectory: String?

    var createdAt: Date?
    var updatedAt: Date?
    var submittedAt: Date?
    var finishedAt: Date?
    var attemptCount: Int?

    init(job: OpsPublishJob) {
        self.requestID = job.requestID
        apply(job)
    }
}

// MARK: - 互转

extension OpsPublishJobRecord {

    /// 落盘形态 → 值类型。
    ///
    /// 未知的枚举字符串**一律向保守方向兜底**：
    /// 状态兜成 `pendingConfirmation`（不是 `confirmed`，也不是「已完成」）——
    /// 宁可让运营多点一次「查询结果」，也不能把不明结论说成发布成功。
    var job: OpsPublishJob {
        OpsPublishJob(
            requestID: requestID,
            jobID: jobID ?? "",
            draftID: draftID ?? "",
            draftRevision: draftRevision ?? 0,
            baseReleaseSeq: baseReleaseSeq,
            baseRootIndexHash: baseRootIndexHash,
            baselineAcknowledged: baselineAcknowledged ?? false,
            targetEnvironment: targetEnvironmentRaw
                .flatMap(ShopCatalogPublishTargetEnvironment.init(rawValue:)) ?? .development,
            adapter: adapterRaw.flatMap(ShopCatalogPublishAdapter.init(rawValue:)),
            releaseSeq: releaseSeq ?? 0,
            payloadHash: payloadHash ?? "",
            state: stateRawValue.flatMap(ShopCatalogPublishExecutionState.init(rawValue:))
                ?? .pendingConfirmation,
            stage: stageRawValue.flatMap(ShopCatalogPublishStage.init(rawValue:)),
            completedUnits: completedUnits ?? 0,
            totalUnits: totalUnits ?? 0,
            failureKind: failureKindRawValue.flatMap(MediaUploadFailureKind.init(rawValue:)),
            lastErrorMessage: lastErrorMessage,
            logLines: Self.decodeLines(logLinesJSON),
            receipt: receiptJSON.flatMap { try? ShopCatalogPublishReceipt.decoded(from: $0) },
            outputDirectory: outputDirectory,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date(),
            submittedAt: submittedAt,
            finishedAt: finishedAt,
            attemptCount: attemptCount ?? 0)
    }

    /// 值类型 → 落盘形态
    func apply(_ job: OpsPublishJob) {
        jobID = job.jobID
        draftID = job.draftID
        draftRevision = job.draftRevision
        baseReleaseSeq = job.baseReleaseSeq
        baseRootIndexHash = job.baseRootIndexHash
        baselineAcknowledged = job.baselineAcknowledged
        targetEnvironmentRaw = job.targetEnvironment.rawValue
        adapterRaw = job.adapter.rawValue
        releaseSeq = job.releaseSeq
        payloadHash = job.payloadHash
        stateRawValue = job.state.rawValue
        stageRawValue = job.stage?.rawValue
        completedUnits = job.completedUnits
        totalUnits = job.totalUnits
        failureKindRawValue = job.failureKind?.rawValue
        lastErrorMessage = job.lastErrorMessage
        logLinesJSON = Self.encodeLines(job.logLines)
        if let receipt = job.receipt {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            receiptJSON = try? encoder.encode(receipt)
        }
        outputDirectory = job.outputDirectory
        createdAt = job.createdAt
        updatedAt = job.updatedAt
        submittedAt = job.submittedAt
        finishedAt = job.finishedAt
        attemptCount = job.attemptCount
    }

    /// 事件留痕的**上限**：超过就丢最旧的。
    /// 一个跑很久的发布可能吐几百行日志；全部落盘会让 SwiftData 表迅速膨胀，
    /// 而排查真正需要的永远是尾部（失败上下文）。
    static let maxLogLines = 200

    static func encodeLines(_ lines: [String]) -> Data? {
        guard !lines.isEmpty else { return nil }
        let trimmed = lines.count > maxLogLines ? Array(lines.suffix(maxLogLines)) : lines
        return try? JSONEncoder().encode(trimmed)
    }

    static func decodeLines(_ data: Data?) -> [String] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
