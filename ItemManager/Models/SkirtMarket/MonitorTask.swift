//
//  MonitorTask.swift
//  裙装股市 - 分布式任务模型
//
//  用于任务分发和抢占式监听，实现分布式计算
//

import Foundation
import SwiftData
import UIKit

/// 任务状态
enum TaskStatus: String, Codable, CaseIterable {
    case pending = "pending"        // 等待分配
    case assigned = "assigned"       // 已分配给某个节点
    case processing = "processing"     // 正在抓取
    case completed = "completed"      // 抓取完成
    case failed = "failed"           // 抓取失败
    case expired = "expired"        // 任务过期
    
    var displayName: String {
        switch self {
        case .pending: return "待处理"
        case .assigned: return "已分配"
        case .processing: return "处理中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .expired: return "已过期"
        }
    }
}

/// 任务类型
enum TaskType: String, Codable, CaseIterable {
    case search = "search"           // 关键词搜索
    case detail = "detail"           // 商品详情
    case userItems = "userItems"     // 用户所有商品
    case comment = "comment"       // 采集评论
    
    var displayName: String {
        switch self {
        case .search: return "搜索"
        case .detail: return "详情"
        case .userItems: return "用户商品"
        case .comment: return "评论采集"
        }
    }
}

/// 监控任务 - 存储在CloudKit Public DB中实现分布式任务分发
@Model
final class MonitorTask {
    // MARK: - 唯一标识
    
    /// 任务唯一ID
    /// 注意：CloudKit不支持unique约束
    var taskID: String = ""
    
    /// 内部UUID
    var id: UUID = UUID()
    
    // MARK: - 任务定义
    
    /// 任务类型
    var taskType: TaskType = TaskType.search
    
    /// 目标平台
    var platform: PlatformType = PlatformType.other
    
    /// 搜索关键词（如果是搜索任务）
    var keyword: String?
    
    /// 目标URL（如果是详情任务）
    var targetURL: String?
    
    /// 目标用户ID（如果是用户商品任务）
    var targetUserId: String?
    
    /// 附加参数（JSON格式）
    var parameters: String?
    
    // MARK: - 任务状态
    
    /// 当前状态
    var status: TaskStatus = TaskStatus.pending
    
    /// 优先级（1-10，数字越大优先级越高）
    var priority: Int = 5
    
    /// 分配给的节点ID
    var assignedNodeId: String?
    
    /// 分配时间
    var assignedAt: Date?
    
    /// 开始处理时间
    var startedAt: Date?
    
    /// 完成时间
    var completedAt: Date?
    
    /// 失败原因
    var failureReason: String?
    
    /// 重试次数
    var retryCount: Int = 0
    
    /// 最大重试次数
    var maxRetries: Int = 3
    
    // MARK: - 时间约束
    
    /// 任务创建时间
    var createdAt: Date = Date()
    
    /// 任务过期时间
    var expiresAt: Date = Date()
    
    /// 下次执行时间（用于定时任务）
    var nextRunAt: Date?
    
    /// 执行间隔（秒，用于循环任务）
    var interval: Int?
    
    // MARK: - 执行结果
    
    /// 抓取到的商品数量
    var itemsFound: Int?
    
    /// 新增商品数量
    var itemsNew: Int?
    
    /// 处理耗时（秒）
    var processingTime: Double?
    
    /// 执行日志
    var executionLog: String?
    
    // MARK: - 分布式协调
    
    /// 创建该任务的节点ID
    var creatorNodeId: String = ""
    
    /// 最后心跳时间（用于检测节点是否存活）
    var lastHeartbeat: Date?
    
    /// 版本号（用于乐观锁）
    var version: Int = 1
    
    // MARK: - 初始化
    
    init(
        taskType: TaskType,
        platform: PlatformType,
        keyword: String? = nil,
        targetURL: String? = nil,
        priority: Int = 5,
        creatorNodeId: String,
        expiresIn: TimeInterval = 3600  // 默认1小时过期
    ) {
        let newId = UUID()
        self.id = newId
        self.taskType = taskType
        self.platform = platform
        self.keyword = keyword
        self.targetURL = targetURL
        self.priority = priority
        self.creatorNodeId = creatorNodeId
        
        // 生成任务ID
        let timestamp = Int(Date().timeIntervalSince1970)
        self.taskID = "\(platform.rawValue)_\(taskType.rawValue)_\(timestamp)_\(newId.uuidString.prefix(8))"
        
        // 初始状态
        self.status = .pending
        self.retryCount = 0
        self.maxRetries = 3
        self.version = 1
        
        // 时间戳
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(expiresIn)
    }
    
    // MARK: - 计算属性
    
    /// 任务是否过期
    var isExpired: Bool {
        Date() > expiresAt
    }
    
    /// 任务是否可以重试
    var canRetry: Bool {
        retryCount < maxRetries && status == .failed
    }
    
    /// 任务描述
    var taskDescription: String {
        switch taskType {
        case .search:
            return "搜索: \(keyword ?? "未知")"
        case .detail:
            return "详情: \(targetURL?.prefix(30) ?? "未知")..."
        case .userItems:
            return "用户: \(targetUserId ?? "未知")"
        case .comment:
            return "评论采集"
        }
    }
    
    /// 等待时间（从创建到现在）
    var waitingTime: TimeInterval {
        if let assigned = assignedAt {
            return assigned.timeIntervalSince(createdAt)
        }
        return Date().timeIntervalSince(createdAt)
    }
    
    // MARK: - 状态变更方法
    
    /// 分配任务给节点
    func assign(to nodeId: String) -> Bool {
        // 乐观锁检查：只有pending状态才能分配
        guard status == .pending else {
            return false
        }
        
        self.assignedNodeId = nodeId
        self.assignedAt = Date()
        self.status = .assigned
        self.version += 1
        return true
    }
    
    /// 开始处理
    func startProcessing() -> Bool {
        guard status == .assigned else {
            return false
        }
        
        self.startedAt = Date()
        self.status = .processing
        self.version += 1
        return true
    }
    
    /// 标记完成
    func complete(itemsFound: Int, itemsNew: Int) {
        self.completedAt = Date()
        self.status = .completed
        self.itemsFound = itemsFound
        self.itemsNew = itemsNew
        
        if let started = startedAt {
            self.processingTime = Date().timeIntervalSince(started)
        }
        
        self.version += 1
        
        // 如果是循环任务，设置下次执行时间
        if let interval = self.interval {
            self.nextRunAt = Date().addingTimeInterval(TimeInterval(interval))
            self.status = .pending  // 重置为待处理状态
            self.assignedNodeId = nil
            self.assignedAt = nil
            self.startedAt = nil
        }
    }
    
    /// 标记失败
    func fail(reason: String) {
        self.failureReason = reason
        self.retryCount += 1
        
        if retryCount >= maxRetries {
            self.status = .failed
            self.completedAt = Date()
        } else {
            // 重试：重置为待处理状态
            self.status = .pending
            self.assignedNodeId = nil
            self.assignedAt = nil
            self.startedAt = nil
        }
        
        self.version += 1
    }
    
    /// 更新心跳
    func heartbeat() {
        self.lastHeartbeat = Date()
    }
    
    /// 重置任务（用于手动重试）
    func reset() {
        self.status = .pending
        self.assignedNodeId = nil
        self.assignedAt = nil
        self.startedAt = nil
        self.completedAt = nil
        self.failureReason = nil
        self.version += 1
    }
}

// MARK: - 任务查询扩展

extension MonitorTask {
    /// 查询分配给特定节点的任务
    static func predicateForNode(_ nodeId: String) -> Predicate<MonitorTask> {
        #Predicate { task in
            task.assignedNodeId == nodeId
        }
    }
    
    // 注意：所有涉及枚举的查询改为内存过滤，避免在#Predicate中使用枚举
    
    /// 查询待处理的任务（内存过滤）
    static func filterPending(from tasks: [MonitorTask]) -> [MonitorTask] {
        tasks.filter { $0.status == .pending }
    }
    
    /// 查询过期的任务（内存过滤）
    static func filterExpired(from tasks: [MonitorTask]) -> [MonitorTask] {
        tasks.filter { $0.status != .completed && $0.status != .failed }
    }
    
    /// 查询需要执行的任务（内存过滤）
    static func filterExecutable(from tasks: [MonitorTask]) -> [MonitorTask] {
        tasks.filter { $0.status == .pending || $0.status == .assigned }
    }
    
    /// 查询特定平台的任务（内存过滤）
    static func filterByPlatform(_ platform: PlatformType, from tasks: [MonitorTask]) -> [MonitorTask] {
        tasks.filter { $0.platform == platform }
    }
}

// MARK: - 节点状态模型

/// 分布式节点状态 - 用于监控各节点健康状况
@Model
final class MonitorNode {
    /// 注意：CloudKit不支持unique约束
    var nodeId: String = ""
    
    /// 节点名称
    var nodeName: String = ""
    
    /// 节点类型（iPhone/iPad/Mac）
    var deviceType: String = ""
    
    /// 系统版本
    var osVersion: String = ""
    
    /// 应用版本
    var appVersion: String = ""
    
    /// 节点状态
    var isOnline: Bool = true
    
    /// 首次上线时间
    var firstSeenAt: Date = Date()
    
    /// 最后活跃时间
    var lastActiveAt: Date = Date()
    
    /// 累计处理任务数
    var totalTasksProcessed: Int = 0
    
    /// 累计发现商品数
    var totalItemsFound: Int = 0
    
    /// 当前正在处理的任务数
    var currentTaskCount: Int = 0
    
    /// 节点地区（用于反爬分析）
    var region: String?
    
    /// IP运营商
    var isp: String?
    
    /// 节点权重（性能好的节点权重高）
    var weight: Double = 1.0
    
    /// 节点评分（成功率）
    var successRate: Double = 1.0
    
    /// 该节点负责的平台列表
    var platforms: [String] = []
    
    /// 当前已完成的任务数
    var completedTasks: Int = 0
    
    /// 最后在线时间（用于计算离线状态）
    var lastSeenAt: Date?
    
    init(nodeId: String, nodeName: String, deviceType: String) {
        self.nodeId = nodeId
        self.nodeName = nodeName
        self.deviceType = deviceType
        self.osVersion = UIDevice.current.systemVersion
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.isOnline = true
        self.firstSeenAt = Date()
        self.lastActiveAt = Date()
        self.totalTasksProcessed = 0
        self.totalItemsFound = 0
        self.currentTaskCount = 0
        self.weight = 1.0
        self.successRate = 1.0
        self.platforms = []
        self.completedTasks = 0
        self.lastSeenAt = Date()
    }
    
    /// 更新活跃状态
    func updateActivity() {
        self.lastActiveAt = Date()
        self.isOnline = true
    }
    
    /// 标记离线
    func markOffline() {
        self.isOnline = false
    }
    
    /// 记录任务完成
    func recordTaskCompletion(itemsFound: Int, success: Bool) {
        self.totalTasksProcessed += 1
        self.totalItemsFound += itemsFound
        self.currentTaskCount = max(0, self.currentTaskCount - 1)
        
        // 更新成功率（指数移动平均）
        let alpha = 0.1
        let newSuccess = success ? 1.0 : 0.0
        self.successRate = (1 - alpha) * self.successRate + alpha * newSuccess
        
        self.updateActivity()
    }
    
    /// 记录任务开始
    func recordTaskStart() {
        self.currentTaskCount += 1
        self.updateActivity()
    }
}

// MARK: - 任务配置

/// 任务配置常量
enum TaskConfig {
    /// 任务超时时间（秒）
    static let taskTimeout: TimeInterval = 300  // 5分钟
    
    /// 心跳间隔（秒）
    static let heartbeatInterval: TimeInterval = 60  // 1分钟
    
    /// 节点离线判定时间（秒）
    static let nodeOfflineThreshold: TimeInterval = 300  // 5分钟无心跳视为离线
    
    /// 最大并发任务数（每个节点）
    static let maxConcurrentTasksPerNode = 3
    
    /// 任务分配重试间隔（秒）
    static let taskAssignmentRetryInterval: TimeInterval = 30
    
    /// 默认任务过期时间（秒）
    static let defaultTaskExpiry: TimeInterval = 3600  // 1小时
}
