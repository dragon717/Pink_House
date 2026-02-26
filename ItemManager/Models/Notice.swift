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
    var mediaURL: String? = nil  // 图片或视频URL (使用外部存储)
    var mediaType: MediaType = MediaType.none
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isActive: Bool = true  // 是否显示
    var priority: Int = 0   // 优先级，数字越大越靠前
    var version: Int = 1    // 版本号，用于数据迁移兼容

    // MARK: - CloudKit 元数据 (系统自动管理)
    // creatorUserRecordID 由 CloudKit 自动记录，无法伪造

    // MARK: - 预留字段 (用于未来扩展)
    var metadata: String? = nil

    enum MediaType: String, Codable {
        case none
        case image
        case video
    }

    init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        mediaURL: String? = nil,
        mediaType: MediaType = .none,
        priority: Int = 0,
        isActive: Bool = true
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.mediaURL = mediaURL
        self.mediaType = mediaType
        self.createdAt = Date()
        self.updatedAt = Date()
        self.priority = priority
        self.isActive = isActive
        self.version = 1
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
}
