import Foundation
import SwiftData
import CloudKit
import UIKit
import Combine

// MARK: - 公告服务
// 处理公告的CRUD操作和CloudKit同步
// 注意：Public Database 的权限需要在 CloudKit Dashboard 中配置

@MainActor
class NoticeService: ObservableObject {
    static let shared = NoticeService()
    
    @Published var notices: [Notice] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var modelContext: ModelContext?
    private let cloudKitContainer = CKContainer.default()
    
    private init() {}
    
    // MARK: - 设置 ModelContext
    func setup(with context: ModelContext) {
        self.modelContext = context
        Task {
            await fetchNotices()
        }
    }
    
    // MARK: - 获取公告列表
    func fetchNotices() async {
        guard let context = modelContext else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // 从本地 SwiftData 获取
            let descriptor = FetchDescriptor<Notice>(
                predicate: #Predicate { $0.isActive == true },
                sortBy: [SortDescriptor(\.priority, order: .reverse),
                         SortDescriptor(\.createdAt, order: .reverse)]
            )
            notices = try context.fetch(descriptor)
            
            // 可选：从 CloudKit Public Database 同步最新数据
            // await syncFromCloudKit()
            
        } catch {
            errorMessage = "获取公告失败: \(error.localizedDescription)"
        }
    }
    
    // MARK: - 创建公告 (使用 Data)
    func createNotice(
        title: String,
        content: String,
        mediaData: Data? = nil,
        mediaType: Notice.MediaType = .none,
        priority: Int = 0
    ) async -> Notice? {
        // 保存媒体到本地 (如果存在)
        var mediaURL: String?
        if let mediaData = mediaData, mediaType != .none {
            print("💾 保存媒体到本地...")
            mediaURL = saveMediaToLocal(mediaData, type: mediaType)
            print("💾 媒体保存完成: \(mediaURL ?? "nil")")
        }

        return await createNoticeWithURL(
            title: title,
            content: content,
            mediaURL: mediaURL,
            mediaType: mediaType,
            priority: priority
        )
    }

    // MARK: - 创建公告 (使用 URL)
    func createNoticeWithURL(
        title: String,
        content: String,
        mediaURL: String? = nil,
        mediaType: Notice.MediaType = .none,
        priority: Int = 0
    ) async -> Notice? {
        guard let context = modelContext else {
            print("❌ 创建公告失败: modelContext 为 nil")
            errorMessage = "系统错误，请重试"
            return nil
        }

        print("📝 开始创建公告: title=\(title), content=\(content), mediaType=\(mediaType)")

        // 检查重复 (避免使用 .unique 约束)
        let existing = notices.first { $0.title == title && $0.content == content }
        if existing != nil {
            print("⚠️ 相同内容的公告已存在")
            errorMessage = "相同内容的公告已存在"
            return nil
        }

        let notice = Notice(
            title: title,
            content: content,
            mediaURL: mediaURL,
            mediaType: mediaType,
            priority: priority
        )

        print("💾 插入公告到 context...")
        context.insert(notice)

        do {
            print("💾 保存 context...")
            try context.save()
            print("✅ 公告保存成功")
            await fetchNotices()
            return notice
        } catch {
            print("❌ 保存公告失败: \(error)")
            print("❌ 错误详情: \(error.localizedDescription)")
            errorMessage = "保存公告失败: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - 保存媒体数据并返回 URL (公开方法)
    func saveMediaData(_ data: Data, type: Notice.MediaType) -> String? {
        return saveMediaToLocal(data, type: type)
    }
    
    // MARK: - 更新公告
    func updateNotice(_ notice: Notice) async {
        guard let context = modelContext else { return }
        
        notice.updatedAt = Date()
        
        do {
            try context.save()
            await fetchNotices()
        } catch {
            errorMessage = "更新公告失败: \(error.localizedDescription)"
        }
    }
    
    // MARK: - 删除公告 (软删除)
    func deleteNotice(_ notice: Notice) async {
        guard let context = modelContext else { return }
        
        // 软删除：标记为不活跃，而不是真正删除
        // 这样可以避免 iCloud 同步冲突
        notice.isActive = false
        notice.updatedAt = Date()
        
        do {
            try context.save()
            await fetchNotices()
        } catch {
            errorMessage = "删除公告失败: \(error.localizedDescription)"
        }
    }
    
    // MARK: - 硬删除 (仅管理员使用)
    func hardDeleteNotice(_ notice: Notice) async {
        guard let context = modelContext else { return }
        
        context.delete(notice)
        
        do {
            try context.save()
            await fetchNotices()
        } catch {
            errorMessage = "删除公告失败: \(error.localizedDescription)"
        }
    }
    
    // MARK: - 保存媒体到本地
    private func saveMediaToLocal(_ data: Data, type: Notice.MediaType) -> String? {
        // 保存到应用沙盒的 Documents 目录
        let fileManager = FileManager.default
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ 无法获取 Documents 目录")
            return nil
        }
        
        let mediaDir = documentsDir.appendingPathComponent("NoticeMedia", isDirectory: true)
        
        // 创建目录
        do {
            try fileManager.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        } catch {
            print("❌ 创建媒体目录失败: \(error)")
            return nil
        }
        
        // 生成文件名
        let fileExtension = type == .image ? "jpg" : "mp4"
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let fileURL = mediaDir.appendingPathComponent(fileName)
        
        // 保存数据
        do {
            try data.write(to: fileURL)
            print("✅ 媒体保存成功: \(fileURL.absoluteString)")
            return fileURL.absoluteString
        } catch {
            print("❌ 保存媒体失败: \(error)")
            return nil
        }
    }
    
    // MARK: - 加载媒体数据
    func loadMediaData(from urlString: String?) -> Data? {
        guard let urlString = urlString,
              let url = URL(string: urlString) else {
            return nil
        }
        
        do {
            return try Data(contentsOf: url)
        } catch {
            print("❌ 加载媒体失败: \(error)")
            return nil
        }
    }
    
    // MARK: - 检查用户是否为管理员
    func isAdmin() async -> Bool {
        // 实际实现：检查用户的 iCloud ID 是否在管理员列表中
        // 或者使用 CloudKit 的 Security Roles
        
        // 示例：获取当前用户的 iCloud ID
        do {
            let recordID = try await cloudKitContainer.userRecordID()
            // 检查是否在管理员列表中
            // return adminList.contains(recordID.recordName)
            return false // 默认非管理员
        } catch {
            return false
        }
    }
    
    // MARK: - 频率限制检查
    func checkRateLimit() -> Bool {
        // 简单的客户端频率限制
        let lastPostKey = "lastNoticePostTime"
        let minInterval: TimeInterval = 60 // 1分钟
        
        if let lastPost = UserDefaults.standard.object(forKey: lastPostKey) as? Date {
            if Date().timeIntervalSince(lastPost) < minInterval {
                return false
            }
        }
        
        UserDefaults.standard.set(Date(), forKey: lastPostKey)
        return true
    }
}

// MARK: - CKContainer 扩展
extension CKContainer {
    func userRecordID() async throws -> CKRecord.ID {
        return try await withCheckedThrowingContinuation { continuation in
            fetchUserRecordIDWithCheck { recordID, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let recordID = recordID {
                    continuation.resume(returning: recordID)
                } else {
                    continuation.resume(throwing: NSError(domain: "NoticeService", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取用户ID"]))
                }
            }
        }
    }
    
    private func fetchUserRecordIDWithCheck(completion: @escaping (CKRecord.ID?, Error?) -> Void) {
        accountStatus { status, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard status == .available else {
                completion(nil, NSError(domain: "NoticeService", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud 账户不可用"]))
                return
            }
            
            self.fetchUserRecordID { recordID, error in
                completion(recordID, error)
            }
        }
    }
}
