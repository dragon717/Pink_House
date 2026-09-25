//
//  ShopCatalogUploadJob.swift
//  ItemManager
//
//  运营上传任务（iOS 运营上传实施方案 §3.1 / §4）。
//
//  ## 只做本地草稿，绝不上云
//
//  方案 §2.1：运营草稿、上传任务、失败原因和重试次数用 SwiftData **本地**保存，
//  显式 `ModelConfiguration(cloudKitDatabase: .none)`。两条理由：
//
//    · Apple 当前的 `ModelConfiguration.CloudKitDatabase` **没有 `.public` 选项**，
//      公共目录必须走显式 CloudKit API（`THMedia` / `THDataPack` / `THRelease`）；
//    · 草稿一旦自动同步，就等于把未审核内容散进运营账号的私有库。
//
//  ⚠️ 所以本模型**不能**进主容器：主容器在开启 iCloud 时是 `.private(...)`，
//     把上传任务放进去会被自动同步。它由 `ShopCatalogOpsUploadStore`
//     用独立容器（`.none`）承载。
//
//  ⚠️ 新增字段必须 Optional 或带默认值：任务表会被旧版本 App 读回，
//     非 Optional 的必填字段会让旧落盘数据整体解码失败（见项目反模式清单）。
//

import Foundation
import SwiftData

// MARK: - 阶段

/// 任务处在发布流程的哪一步（方案 §3：媒体 → 数据包 → 发布头）。
nonisolated enum ShopCatalogUploadStage: String, Codable, CaseIterable, Sendable {
    /// 图片上传 `THMedia`
    case media
    /// 商品整包上传 `THDataPack`
    case pack
    /// 切换发布头 `THRelease`
    case release

    var displayName: String {
        switch self {
        case .media: return "图片"
        case .pack: return "商品包"
        case .release: return "发布头"
        }
    }
}

// MARK: - 状态

/// 任务状态。正常链路上的四个值对应方案 §6 的 `staged → uploading → verified`，
/// 其余六个**逐条对应**方案 §4 的错误表 —— 不新增表外状态。
nonisolated enum ShopCatalogUploadStatus: String, Codable, CaseIterable, Sendable {
    /// 已暂存（算好 hash / MIME / 字节数，等上传）
    case staged
    /// 正在上传
    case uploading
    /// 已上传并**从公共库回读校验通过**（方案 §3.2 第 6 步）
    case mediaVerified
    /// 发布头已切换且只读端回读验证成功（方案 §3.4 第 7 步）
    case published

    /// 选图读取 / 压缩失败（§4）
    case stagedFailed
    /// 无 iCloud 账号 / CloudKit 权限拒绝（§4）：不自动重试
    case blocked
    /// 网络超时 / 服务暂不可用 / 资产上传成功但记录写入失败（§4）：指数退避
    case retryable
    /// `THMedia` 回读 hash 不一致等硬失败（§4）：不发布包，保留诊断信息
    case failed
    /// `THRelease` changeTag 冲突（§4）：重新读头、重算序号，由运营确认，不强制覆盖
    case conflict
    /// 发布头已切换但只读端拉不到图片（§4）：**不得**显示「验证成功」
    case publishedButUnverified

    /// 是否属于「可以继续往下走」的状态（只有它才允许进入下一步）
    var isHealthy: Bool {
        switch self {
        case .staged, .uploading, .mediaVerified, .published: return true
        default: return false
        }
    }

    /// 是否终态失败（不再自动重试；`retryable` 除外，它由退避时间驱动）
    var isTerminalFailure: Bool {
        switch self {
        case .stagedFailed, .blocked, .failed, .conflict, .publishedButUnverified: return true
        default: return false
        }
    }

    /// 运营是否可以点「重试」：阻塞类要先解决账号/权限，冲突类要先人工确认
    var allowsManualRetry: Bool {
        switch self {
        case .stagedFailed, .retryable, .failed: return true
        case .blocked, .conflict, .publishedButUnverified, .staged, .uploading,
             .mediaVerified, .published: return false
        }
    }

    var displayName: String {
        switch self {
        case .staged: return "待上传"
        case .uploading: return "上传中"
        case .mediaVerified: return "媒体已校验"
        case .published: return "已发布"
        case .stagedFailed: return "暂存失败"
        case .blocked: return "被阻塞"
        case .retryable: return "可重试"
        case .failed: return "失败"
        case .conflict: return "发布头冲突"
        case .publishedButUnverified: return "已发布未验证"
        }
    }
}

// MARK: - 上传策略常量（方案 §2.3 的输入约束）

/// 媒体准入与重试参数。**与发布端 `tools/time_hall/publication/protocol.py`
/// 的 `MEDIA_MIME_ALLOWLIST` / `MAX_MEDIA_BYTES` 是同一个口径**：
/// 两端不一致就会出现「iOS 让传、Mac 拒发」或反过来。
nonisolated enum ShopCatalogUploadPolicy {

    /// 允许上传的 MIME（客户端确实能解码的类型）
    static let allowedMimeTypes: Set<String> = [
        "image/jpeg", "image/png", "image/gif", "image/webp", "image/heic",
    ]

    /// 单张媒体字节上限。方案未给数字，这里取 20 MiB：
    /// 运营图经「长边 1600 / JPEG 0.85」处理后远小于此，超过基本可判定是误选原图。
    static let maxMediaBytes = 20 * 1024 * 1024

    /// 单任务最大尝试次数（超过就停在 `failed`，不再自动重试）
    static let maxAttempts = 5

    /// 指数退避：30s → 60s → 120s → 240s（方案 §4「网络超时 → 指数退避」）
    static func retryDelay(attempt: Int) -> TimeInterval {
        let base: TimeInterval = 30
        let exponent = max(0, min(attempt, 4))
        return base * pow(2, Double(exponent))
    }

    /// MIME 是否在准入白名单内
    static func isAllowedMimeType(_ value: String?) -> Bool {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else { return false }
        return allowedMimeTypes.contains(normalized.lowercased())
    }
}

// MARK: - 任务

/// 一条上传任务 = 一张图（一个 `mediaKey`）。
///
/// 字段口径按方案 §4 收口：`jobID` / 商品与资产 ID / 阶段 / `mediaKey` /
/// 文件路径 / `attemptCount` / `lastError` / `nextRetryAt` / `releaseSeq`。
@Model
final class ShopCatalogUploadJob {

    /// 任务 ID：`mediaKey` 是内容寻址的，同图多处引用天然合并成一条（方案 §3.2「幂等」）
    @Attribute(.unique) var jobID: String
    /// 归属商品（店家 Logo / 系列封面等非商品图留空字符串）
    var productID: String
    /// 归属资产：`CatalogAsset.id`，或引用字段路径（如 `shops.logo`）
    var assetID: String
    var stageRawValue: String
    var statusRawValue: String
    /// 图片字节 SHA-256（同时是 `THMedia` 记录名后缀与 canonical `mediaKey`）
    var mediaKey: String
    /// 本地暂存文件的绝对路径。**只有公共库回读校验完成后才允许删除**（方案 §4 尾注）
    var filePath: String
    var mimeType: String
    var byteCount: Int
    var attemptCount: Int
    var lastError: String?
    var nextRetryAt: Date?
    /// 发布头序号（方案 §4：冲突时要能重算并留档）
    var releaseSeq: Int
    var updatedAt: Date

    init(
        jobID: String,
        productID: String = "",
        assetID: String = "",
        stage: ShopCatalogUploadStage = .media,
        status: ShopCatalogUploadStatus = .staged,
        mediaKey: String,
        filePath: String,
        mimeType: String,
        byteCount: Int,
        attemptCount: Int = 0,
        lastError: String? = nil,
        nextRetryAt: Date? = nil,
        releaseSeq: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.jobID = jobID
        self.productID = productID
        self.assetID = assetID
        self.stageRawValue = stage.rawValue
        self.statusRawValue = status.rawValue
        self.mediaKey = mediaKey
        self.filePath = filePath
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.nextRetryAt = nextRetryAt
        self.releaseSeq = releaseSeq
        self.updatedAt = updatedAt
    }

    // MARK: 枚举读写（SwiftData 不支持直接存 enum，落 rawValue）

    var stage: ShopCatalogUploadStage {
        get { ShopCatalogUploadStage(rawValue: stageRawValue) ?? .media }
        set { stageRawValue = newValue.rawValue }
    }

    var status: ShopCatalogUploadStatus {
        get { ShopCatalogUploadStatus(rawValue: statusRawValue) ?? .failed }
        set { statusRawValue = newValue.rawValue }
    }

    // MARK: 状态迁移

    /// 记录一次失败：状态 + 原因 + 尝试次数 + 退避时间一次写完，
    /// 避免出现「状态说 retryable 但 nextRetryAt 是空的」这种半更新。
    func markFailure(_ status: ShopCatalogUploadStatus, reason: String, now: Date = Date()) {
        self.status = status
        lastError = reason
        attemptCount += 1
        updatedAt = now
        // 只有可重试的失败才排下一次；其余保持 nil，UI 才不会显示「稍后自动重试」
        if status == .retryable && attemptCount < ShopCatalogUploadPolicy.maxAttempts {
            nextRetryAt = now.addingTimeInterval(
                ShopCatalogUploadPolicy.retryDelay(attempt: attemptCount))
        } else {
            nextRetryAt = nil
            if status == .retryable, attemptCount >= ShopCatalogUploadPolicy.maxAttempts {
                // 重试到上限：降级为硬失败，不再无限打网络
                self.status = .failed
            }
        }
    }

    /// 任务标题（UI 用）。图片任务按内容摘要前 12 位标识 —— 同一张图多处引用共享一条，
    /// 显示文件名反而会让人以为只传了一处。
    var displayTitle: String {
        switch stage {
        case .media:
            return "图片 " + String(mediaKey.prefix(12))
        case .pack, .release:
            return "商品包与发布头"
        }
    }

    /// 记录一次成功推进
    func markSuccess(_ status: ShopCatalogUploadStatus, now: Date = Date()) {
        self.status = status
        lastError = nil
        nextRetryAt = nil
        updatedAt = now
    }
}
