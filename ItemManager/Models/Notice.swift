import Foundation
import SwiftData
import CloudKit
import SwiftUI
import Combine

// MARK: - 公告数据模型 (SwiftData + CloudKit Public Database)
// 注意：Public DB 需要特殊权限配置，所有用户可见
// CloudKit 要求：所有属性必须是可选的或有默认值，不支持唯一约束

@Model
class Notice {
    enum Status: String, Codable, CaseIterable {
        case draft
        case scheduled
        case published
        case archived
    }

    enum Channel: String, Codable, CaseIterable {
        case inbox
        case banner
        case modal
        case mixed
    }

    enum Severity: String, Codable, CaseIterable {
        case info
        case important
        case critical
    }

    enum ActionType: String, Codable, CaseIterable {
        case none
        case deeplink
        case tab
        case page
        case externalURL
    }

    enum Environment: String, Codable, CaseIterable {
        case development
        case production
    }

    // MARK: - 基础字段 (全部有默认值，满足 CloudKit 要求)
    var id: UUID = UUID()
    var title: String = ""
    var summary: String? = nil
    var content: String = ""
    var locale: String? = nil
    var mediaURL: String? = nil  // 图片或视频URL (本地沙盒路径)
    var cloudKitMediaURL: String? = nil  // CloudKit 媒体资源 URL
    var builtinMediaName: String? = nil  // 内置图片资源名称
    var mediaType: MediaType = MediaType.none
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Notice CMS 字段
    var statusRaw: String? = Notice.Status.draft.rawValue
    var channelRaw: String? = Notice.Channel.inbox.rawValue
    var severityRaw: String? = Notice.Severity.info.rawValue
    var displayPriority: Int = 0
    var isPinned: Bool = false
    var requiresAck: Bool = false
    var isSilent: Bool = false
    var publishAt: Date? = nil
    var startAt: Date? = nil
    var endAt: Date? = nil
    var archivedAt: Date? = nil
    var audience: String = "all"
    var minAppVersion: String? = nil
    var maxAppVersion: String? = nil
    var actionTypeRaw: String? = Notice.ActionType.none.rawValue
    var actionTarget: String? = nil
    var actionLabel: String? = nil
    var environmentRaw: String? = Notice.currentEnvironment.rawValue
    var revision: Int = 1
    var rollbackFrom: String? = nil
    var createdBy: String? = nil
    var updatedBy: String? = nil
    var publishedBy: String? = nil

    // MARK: - 旧字段兼容
    var isActive: Bool = true  // 是否显示
    var priority: Int = 0   // 优先级，数字越大越靠前
    var version: Int = 1    // 版本号，用于数据迁移兼容
    var recordName: String? = nil  // CloudKit Record ID
    var creatorID: String? = nil  // 创建者 iCloud ID

    // MARK: - 预留字段 (用于未来扩展)
    var metadata: String? = nil

    enum MediaType: String, Codable, CaseIterable {
        case none
        case image
        case video
    }

    init(
        id: UUID = UUID(),
        title: String = "",
        summary: String? = nil,
        content: String = "",
        locale: String? = nil,
        mediaURL: String? = nil,
        cloudKitMediaURL: String? = nil,
        builtinMediaName: String? = nil,
        mediaType: MediaType = .none,
        priority: Int = 0,
        displayPriority: Int? = nil,
        isActive: Bool = true,
        status: Status? = nil,
        channel: Channel = .inbox,
        severity: Severity = .info,
        isPinned: Bool = false,
        requiresAck: Bool = false,
        isSilent: Bool = false,
        publishAt: Date? = nil,
        startAt: Date? = nil,
        endAt: Date? = nil,
        archivedAt: Date? = nil,
        audience: String = "all",
        minAppVersion: String? = nil,
        maxAppVersion: String? = nil,
        actionType: ActionType = .none,
        actionTarget: String? = nil,
        actionLabel: String? = nil,
        environment: Environment = Notice.currentEnvironment,
        revision: Int? = nil,
        rollbackFrom: String? = nil,
        recordName: String? = nil,
        creatorID: String? = nil,
        createdBy: String? = nil,
        updatedBy: String? = nil,
        publishedBy: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.content = content
        self.locale = locale
        self.mediaURL = mediaURL
        self.cloudKitMediaURL = cloudKitMediaURL
        self.builtinMediaName = builtinMediaName
        self.mediaType = mediaType
        self.createdAt = Date()
        self.updatedAt = Date()
        self.displayPriority = displayPriority ?? priority
        self.priority = self.displayPriority
        self.statusRaw = (status ?? (isActive ? .published : .archived)).rawValue
        self.channelRaw = channel.rawValue
        self.severityRaw = severity.rawValue
        self.isPinned = isPinned
        self.requiresAck = requiresAck
        self.isSilent = isSilent
        self.publishAt = publishAt
        self.startAt = startAt
        self.endAt = endAt
        self.archivedAt = archivedAt
        self.audience = audience
        self.minAppVersion = minAppVersion
        self.maxAppVersion = maxAppVersion
        self.actionTypeRaw = actionType.rawValue
        self.actionTarget = actionTarget
        self.actionLabel = actionLabel
        self.environmentRaw = environment.rawValue
        self.revision = revision ?? 1
        self.version = self.revision
        self.rollbackFrom = rollbackFrom
        self.isActive = self.status == .published
        self.recordName = recordName
        self.creatorID = creatorID
        self.createdBy = createdBy ?? creatorID
        self.updatedBy = updatedBy
        self.publishedBy = publishedBy
        normalizeLegacyFields()
    }
}

// MARK: - CloudKit 转换扩展
extension Notice {
    // CloudKit Record Type 名称
    static let recordType = "Notice"
    static let mediaAssetType = "NoticeMedia"
    static let builtinMediaNameField = "builtinMediaName"
    static let currentEnvironment: Environment = {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }()
    static let currentAppVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    var status: Status {
        get { Status(rawValue: statusRaw ?? "") ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var channel: Channel {
        get { Channel(rawValue: channelRaw ?? "") ?? .inbox }
        set { channelRaw = newValue.rawValue }
    }

    var severity: Severity {
        get { Severity(rawValue: severityRaw ?? "") ?? .info }
        set { severityRaw = newValue.rawValue }
    }

    var actionType: ActionType {
        get { ActionType(rawValue: actionTypeRaw ?? "") ?? .none }
        set { actionTypeRaw = newValue.rawValue }
    }

    var environment: Environment {
        get { Environment(rawValue: environmentRaw ?? "") ?? Notice.currentEnvironment }
        set { environmentRaw = newValue.rawValue }
    }

    var stableIdentifier: String {
        recordName ?? id.uuidString
    }

    var readTrackingKey: String {
        let updatedTimestamp = Int(updatedAt.timeIntervalSince1970)
        return "\(stableIdentifier)#v\(version)#u\(updatedTimestamp)"
    }

    var legacyReadTrackingKeys: [String] {
        [id.uuidString, recordName].compactMap { $0 }
    }

    var shouldUseLegacyReadFallback: Bool {
        version <= 1 && abs(updatedAt.timeIntervalSince(createdAt)) < 1
    }

    static func builtinMediaURLString(for imageName: String) -> String {
        "builtin://\(imageName)"
    }

    var effectivePublishAt: Date {
        publishAt ?? startAt ?? createdAt
    }

    var primaryMediaURL: String? {
        mediaURL ?? cloudKitMediaURL
    }

    var isPublishedLike: Bool {
        status == .published
    }

    func effectiveStatus(at date: Date = Date()) -> Status {
        if status == .scheduled, let activationDate = publishAt ?? startAt, activationDate <= date {
            return .published
        }

        return status
    }

    func supportsChannel(_ candidate: Channel) -> Bool {
        switch candidate {
        case .inbox:
            return true
        case .banner:
            return channel == .banner || channel == .mixed
        case .modal:
            return channel == .modal || channel == .mixed
        case .mixed:
            return channel == .mixed
        }
    }

    func isWithinActiveWindow(at date: Date = Date()) -> Bool {
        if let startAt, date < startAt {
            return false
        }

        if let endAt, date > endAt {
            return false
        }

        return true
    }

    func matchesEnvironment(_ current: Environment = Notice.currentEnvironment) -> Bool {
        environment == current
    }

    func matchesAppVersion(_ currentVersion: String = Notice.currentAppVersion) -> Bool {
        if let minAppVersion, currentVersion.compare(minAppVersion, options: .numeric) == .orderedAscending {
            return false
        }

        if let maxAppVersion, currentVersion.compare(maxAppVersion, options: .numeric) == .orderedDescending {
            return false
        }

        return true
    }

    func isVisibleInInbox(
        at date: Date = Date(),
        currentEnvironment: Environment = Notice.currentEnvironment,
        currentAppVersion: String = Notice.currentAppVersion
    ) -> Bool {
        guard effectiveStatus(at: date) == .published else { return false }
        guard matchesEnvironment(currentEnvironment) else { return false }
        guard matchesAppVersion(currentAppVersion) else { return false }
        return isWithinActiveWindow(at: date)
    }

    func isEligibleForBanner(
        at date: Date = Date(),
        currentEnvironment: Environment = Notice.currentEnvironment,
        currentAppVersion: String = Notice.currentAppVersion
    ) -> Bool {
        guard !isSilent else { return false }
        guard severity == .important || severity == .critical else { return false }
        guard supportsChannel(.banner) else { return false }
        return isVisibleInInbox(at: date, currentEnvironment: currentEnvironment, currentAppVersion: currentAppVersion)
    }

    func isEligibleForModal(
        at date: Date = Date(),
        currentEnvironment: Environment = Notice.currentEnvironment,
        currentAppVersion: String = Notice.currentAppVersion
    ) -> Bool {
        guard !isSilent else { return false }
        guard severity == .critical else { return false }
        guard supportsChannel(.modal) else { return false }
        return isVisibleInInbox(at: date, currentEnvironment: currentEnvironment, currentAppVersion: currentAppVersion)
    }

    func applyLifecycleDefaults(now: Date = Date()) {
        if status == .published {
            if publishAt == nil {
                publishAt = now
            }
            if startAt == nil {
                startAt = publishAt
            }
        }

        if status == .scheduled {
            if publishAt == nil {
                publishAt = startAt
            }
        }

        if status == .archived, archivedAt == nil {
            archivedAt = now
        }

        normalizeLegacyFields()
    }

    func normalizeLegacyFields() {
        priority = displayPriority
        version = revision
        isActive = status == .published
        creatorID = createdBy ?? creatorID
        if createdBy == nil {
            createdBy = creatorID
        }
        if let builtinMediaName, mediaURL == nil {
            mediaURL = Notice.builtinMediaURLString(for: builtinMediaName)
        }
    }

    // 从 CloudKit Record 创建 Notice
    convenience init?(from record: CKRecord) {
        guard let title = record["title"] as? String,
              let content = record["content"] as? String else {
            return nil
        }

        let id = (record["id"] as? String).flatMap { UUID(uuidString: $0) } ?? UUID()
        let mediaTypeString = record["mediaType"] as? String ?? "none"
        let mediaType = MediaType(rawValue: mediaTypeString) ?? .none
        let priority = record["displayPriority"] as? Int ?? record["priority"] as? Int ?? 0
        let isActive = record["isActive"] as? Bool ?? true
        let createdAt = record["createdAt"] as? Date ?? record.creationDate ?? Date()
        let updatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? Date()
        let revision = record["revision"] as? Int ?? record["version"] as? Int ?? 1
        let creatorID = record.creatorUserRecordID?.recordName
        let builtinMediaName = record[Notice.builtinMediaNameField] as? String
        let status = Status(rawValue: record["status"] as? String ?? "") ?? (isActive ? .published : .archived)
        let channel = Channel(rawValue: record["channel"] as? String ?? "") ?? .inbox
        let severity = Severity(rawValue: record["severity"] as? String ?? "") ?? .info
        let actionType = ActionType(rawValue: record["actionType"] as? String ?? "") ?? .none
        let environment = Environment(rawValue: record["environment"] as? String ?? "") ?? Notice.currentEnvironment

        // 获取媒体 URL
        var cloudKitMediaURL: String?
        if let mediaAsset = record["mediaAsset"] as? CKAsset,
           let fileURL = mediaAsset.fileURL {
            cloudKitMediaURL = fileURL.absoluteString
        }

        let resolvedMediaURL: String?
        if let builtinMediaName {
            resolvedMediaURL = Notice.builtinMediaURLString(for: builtinMediaName)
        } else {
            resolvedMediaURL = cloudKitMediaURL
        }

        self.init(
            id: id,
            title: title,
            summary: record["summary"] as? String,
            content: content,
            locale: record["locale"] as? String,
            mediaURL: resolvedMediaURL,
            cloudKitMediaURL: cloudKitMediaURL,
            builtinMediaName: builtinMediaName,
            mediaType: mediaType,
            priority: priority,
            displayPriority: priority,
            isActive: isActive,
            status: status,
            channel: channel,
            severity: severity,
            isPinned: record["isPinned"] as? Bool ?? false,
            requiresAck: record["requiresAck"] as? Bool ?? false,
            isSilent: record["isSilent"] as? Bool ?? false,
            publishAt: record["publishAt"] as? Date,
            startAt: record["startAt"] as? Date,
            endAt: record["endAt"] as? Date,
            archivedAt: record["archivedAt"] as? Date,
            audience: record["audience"] as? String ?? "all",
            minAppVersion: record["minAppVersion"] as? String,
            maxAppVersion: record["maxAppVersion"] as? String,
            actionType: actionType,
            actionTarget: record["actionTarget"] as? String,
            actionLabel: record["actionLabel"] as? String,
            environment: environment,
            revision: revision,
            rollbackFrom: record["rollbackFrom"] as? String,
            recordName: record.recordID.recordName,
            creatorID: creatorID,
            createdBy: record["createdBy"] as? String ?? creatorID,
            updatedBy: record["updatedBy"] as? String,
            publishedBy: record["publishedBy"] as? String
        )

        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.version = revision
        self.normalizeLegacyFields()
    }

    // 转换为 CloudKit Record
    func toCloudKitRecord() -> CKRecord {
        applyLifecycleDefaults()
        let recordID: CKRecord.ID
        if let recordName = recordName {
            recordID = CKRecord.ID(recordName: recordName)
        } else {
            recordID = CKRecord.ID(recordName: "Notice_\(id.uuidString)")
        }

        let record = CKRecord(recordType: Notice.recordType, recordID: recordID)
        record["id"] = id.uuidString
        record["title"] = title
        record["summary"] = summary
        record["content"] = content
        record["locale"] = locale
        record["mediaType"] = mediaType.rawValue
        record["status"] = status.rawValue
        record["channel"] = channel.rawValue
        record["severity"] = severity.rawValue
        record["displayPriority"] = displayPriority
        record["priority"] = priority
        record["isPinned"] = isPinned
        record["requiresAck"] = requiresAck
        record["isSilent"] = isSilent
        record["isActive"] = isActive
        record["publishAt"] = publishAt
        record["startAt"] = startAt
        record["endAt"] = endAt
        record["archivedAt"] = archivedAt
        record["audience"] = audience
        record["minAppVersion"] = minAppVersion
        record["maxAppVersion"] = maxAppVersion
        record["actionType"] = actionType.rawValue
        record["actionTarget"] = actionTarget
        record["actionLabel"] = actionLabel
        record["environment"] = environment.rawValue
        record["revision"] = revision
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt
        record["version"] = version
        record["rollbackFrom"] = rollbackFrom
        record["createdBy"] = createdBy
        record["updatedBy"] = updatedBy
        record["publishedBy"] = publishedBy
        record[Notice.builtinMediaNameField] = builtinMediaName

        // 如果有本地媒体文件，创建 Asset
        if let mediaURL = mediaURL,
           !mediaURL.hasPrefix("builtin://"),
           let url = URL(string: mediaURL),
           FileManager.default.fileExists(atPath: url.path) {
            record["mediaAsset"] = CKAsset(fileURL: url)
        } else {
            record["mediaAsset"] = nil
        }

        return record
    }
}

// MARK: - 公告配置
enum NoticeConfig {
    // 莫妮卡粉 - 公告背景色
    static let monicaPink = Color(hex: "FCE2DB")

    // 圆角半径
    static let cornerRadius: CGFloat = 20

    // 内边距
    static let padding: CGFloat = 16

    // 边框内边距 - 边框距离卡片边缘的距离
    static let borderPadding: CGFloat = 12

    // 内容内边距 - 内容距离边框内部的距离
    static let contentPadding: CGFloat = 16

    // 卡片整体比例 (宽:高) - 正方形
    static let cardAspectRatio: CGFloat = 1 / 1

    // 图片/视频区域比例 (宽高比)
    static let mediaAspectRatio: CGFloat = 16 / 9

    // 文字区域最大高度
    static let textMaxHeight: CGFloat = 100

    // 动画时长
    static let animationDuration: Double = 0.3

    // CloudKit 同步配置
    static let syncInterval: TimeInterval = 300  // 5分钟同步一次
    static let maxNoticeAge: TimeInterval = 30 * 24 * 60 * 60  // 30天过期
}
