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
    // MARK: - 基础字段 (全部有默认值，满足 CloudKit 要求)
    var id: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var mediaURL: String? = nil  // 图片或视频URL (本地沙盒路径)
    var cloudKitMediaURL: String? = nil  // CloudKit 媒体资源 URL
    var mediaType: MediaType = MediaType.none
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
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
        content: String = "",
        mediaURL: String? = nil,
        cloudKitMediaURL: String? = nil,
        mediaType: MediaType = .none,
        priority: Int = 0,
        isActive: Bool = true,
        recordName: String? = nil,
        creatorID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.mediaURL = mediaURL
        self.cloudKitMediaURL = cloudKitMediaURL
        self.mediaType = mediaType
        self.createdAt = Date()
        self.updatedAt = Date()
        self.priority = priority
        self.isActive = isActive
        self.version = 1
        self.recordName = recordName
        self.creatorID = creatorID
    }
}

// MARK: - CloudKit 转换扩展
extension Notice {
    // CloudKit Record Type 名称
    static let recordType = "Notice"
    static let mediaAssetType = "NoticeMedia"

    // 从 CloudKit Record 创建 Notice
    convenience init?(from record: CKRecord) {
        guard let title = record["title"] as? String,
              let content = record["content"] as? String else {
            return nil
        }

        let id = (record["id"] as? String).flatMap { UUID(uuidString: $0) } ?? UUID()
        let mediaTypeString = record["mediaType"] as? String ?? "none"
        let mediaType = MediaType(rawValue: mediaTypeString) ?? .none
        let priority = record["priority"] as? Int ?? 0
        let isActive = record["isActive"] as? Bool ?? true
        let createdAt = record["createdAt"] as? Date ?? record.creationDate ?? Date()
        let updatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? Date()
        let creatorID = record.creatorUserRecordID?.recordName

        // 获取媒体 URL
        var cloudKitMediaURL: String?
        if let mediaAsset = record["mediaAsset"] as? CKAsset,
           let fileURL = mediaAsset.fileURL {
            cloudKitMediaURL = fileURL.absoluteString
        }

        self.init(
            id: id,
            title: title,
            content: content,
            mediaURL: nil,  // 本地路径需要下载后设置
            cloudKitMediaURL: cloudKitMediaURL,
            mediaType: mediaType,
            priority: priority,
            isActive: isActive,
            recordName: record.recordID.recordName,
            creatorID: creatorID
        )

        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // 转换为 CloudKit Record
    func toCloudKitRecord() -> CKRecord {
        let recordID: CKRecord.ID
        if let recordName = recordName {
            recordID = CKRecord.ID(recordName: recordName)
        } else {
            recordID = CKRecord.ID(recordName: "Notice_\(id.uuidString)")
        }

        let record = CKRecord(recordType: Notice.recordType, recordID: recordID)
        record["id"] = id.uuidString
        record["title"] = title
        record["content"] = content
        record["mediaType"] = mediaType.rawValue
        record["priority"] = priority
        record["isActive"] = isActive
        record["createdAt"] = createdAt
        record["updatedAt"] = Date()
        record["version"] = version

        // 如果有本地媒体文件，创建 Asset
        if let mediaURL = mediaURL,
           let url = URL(string: mediaURL),
           FileManager.default.fileExists(atPath: url.path) {
            record["mediaAsset"] = CKAsset(fileURL: url)
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
