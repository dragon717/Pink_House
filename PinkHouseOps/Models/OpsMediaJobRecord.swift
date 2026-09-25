//
//  OpsMediaJobRecord.swift
//  PinkHouseOps
//
//  图片上传任务的落盘形态（SwiftData）+ 与共享层 `MediaUploadJob` 的互转。
//
//  状态机本身在共享层（`MediaUploadJobMachine`），这里只负责「存得住、取得回」。
//  两边用 **rawValue 字符串**对接，而不是把 `MediaUploadJobState` 直接塞进模型：
//  SwiftData 对自定义 Codable 枚举的存储形态会随实现变化，存字符串最稳，
//  将来枚举加 case 也不会让旧草稿解不出来（解码失败按 `.staged` 兜底）。
//

import Foundation
import SwiftData

@Model
final class OpsMediaJobRecord {
    /// 就是 `mediaKey`：同内容的图天然只有一条任务，幂等复用不需要额外查重
    @Attribute(.unique) var mediaKey: String
    /// 草稿归属（一个草稿一个 staging 目录）
    var draftID: String
    var stagedFileName: String
    var byteCount: Int
    var mimeType: String
    var stateRawValue: String
    var attemptCount: Int
    var failureKindRawValue: String?
    var lastErrorMessage: String?
    var createdAt: Date
    var updatedAt: Date
    var verifiedAt: Date?

    init(
        mediaKey: String,
        draftID: String,
        stagedFileName: String,
        byteCount: Int,
        mimeType: String,
        stateRawValue: String = MediaUploadJobState.staged.rawValue,
        attemptCount: Int = 0,
        failureKindRawValue: String? = nil,
        lastErrorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        verifiedAt: Date? = nil
    ) {
        self.mediaKey = mediaKey
        self.draftID = draftID
        self.stagedFileName = stagedFileName
        self.byteCount = byteCount
        self.mimeType = mimeType
        self.stateRawValue = stateRawValue
        self.attemptCount = attemptCount
        self.failureKindRawValue = failureKindRawValue
        self.lastErrorMessage = lastErrorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.verifiedAt = verifiedAt
    }
}

// MARK: - 与共享层互转

extension OpsMediaJobRecord {

    /// 落盘形态 → 共享层任务
    var job: MediaUploadJob {
        MediaUploadJob(
            mediaKey: mediaKey,
            stagedFileName: stagedFileName,
            byteCount: byteCount,
            mimeType: mimeType,
            // 未知字符串按 `.staged` 兜底：宁可让运营看成「待上传」，
            // 也不要因为一个新 case 让整条记录解不出来
            state: MediaUploadJobState(rawValue: stateRawValue) ?? .staged,
            attemptCount: attemptCount,
            failureKind: failureKindRawValue.flatMap(MediaUploadFailureKind.init(rawValue:)),
            lastErrorMessage: lastErrorMessage,
            createdAt: createdAt,
            updatedAt: updatedAt,
            verifiedAt: verifiedAt)
    }

    /// 共享层任务 → 落盘形态（状态机推进后回写）
    func apply(_ job: MediaUploadJob) {
        stagedFileName = job.stagedFileName
        byteCount = job.byteCount
        mimeType = job.mimeType
        stateRawValue = job.state.rawValue
        attemptCount = job.attemptCount
        failureKindRawValue = job.failureKind?.rawValue
        lastErrorMessage = job.lastErrorMessage
        updatedAt = job.updatedAt
        verifiedAt = job.verifiedAt
    }
}
