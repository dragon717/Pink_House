//
//  TaskDispatcher.swift
//  裙子股市 - 分布式任务分发器
//
//  实现抢占式任务分配，让多台iPhone协同工作
//

import Foundation
import SwiftData
import BackgroundTasks
import Combine
import UIKit

/// 任务分发器 - 分布式计算的核心协调器
@MainActor
final class TaskDispatcher: ObservableObject {
    static let shared = TaskDispatcher()
    
    // MARK: - 发布属性
    
    /// 当前节点ID
    @Published private(set) var currentNodeId: String
    
    /// 当前节点名称
    @Published private(set) var currentNodeName: String
    
    /// 是否正在运行
    @Published private(set) var isRunning = false
    
    /// 当前正在处理的任务
    @Published private(set) var currentTasks: [MonitorTask] = []
    
    /// 在线节点列表
    @Published private(set) var onlineNodes: [MonitorNode] = []
    
    /// 任务统计
    @Published private(set) var taskStats = TaskStatistics()
    
    // MARK: - 私有属性
    
    /// 定时器
    private var heartbeatTimer: Timer?
    private var taskCheckTimer: Timer?
    
    /// 后台任务标识
    private let backgroundTaskIdentifier = "com.yourapp.skirtmarket.fetch"
    
    /// 当前上下文
    private var context: ModelContext? {
        SkirtMarketPersistence.shared.mainContext
    }
    
    // MARK: - 初始化
    
    private init() {
        // 生成唯一节点ID
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let nodeId = "node_\(deviceId.prefix(8))"
        self.currentNodeId = nodeId
        
        // 生成节点名称
        let deviceName = UIDevice.current.name
        self.currentNodeName = "\(deviceName) (\(nodeId.suffix(4)))"
        
        print("🖥️ 节点初始化: \(currentNodeName) [\(currentNodeId)]")
    }
    
    // MARK: - 生命周期管理
    
    /// 启动任务分发器
    func start() async {
        guard !isRunning else { return }
        
        print("🚀 启动任务分发器...")
        
        // 1. 注册或更新节点
        await registerNode()
        
        // 2. 启动心跳
        startHeartbeat()
        
        // 3. 启动任务检查
        startTaskChecking()
        
        // 4. 注册后台任务
        registerBackgroundTask()
        
        isRunning = true
        print("✅ 任务分发器已启动")
    }
    
    /// 停止任务分发器
    func stop() {
        guard isRunning else { return }
        
        print("🛑 停止任务分发器...")
        
        // 停止定时器
        heartbeatTimer?.invalidate()
        taskCheckTimer?.invalidate()
        
        // 标记节点离线
        Task {
            await markNodeOffline()
        }
        
        // 释放当前任务
        releaseCurrentTasks()
        
        isRunning = false
        print("✅ 任务分发器已停止")
    }
    
    // MARK: - 节点管理
    
    /// 注册当前节点
    private func registerNode() async {
        guard let context = context else { return }
        
        // 查询是否已存在
        let descriptor = FetchDescriptor<MonitorNode>(
            predicate: #Predicate { $0.nodeId == currentNodeId }
        )
        
        let node: MonitorNode
        if let existing = try? context.fetch(descriptor).first {
            node = existing
            node.updateActivity()
            print("📝 更新节点状态: \(currentNodeName)")
        } else {
            node = MonitorNode(
                nodeId: currentNodeId,
                nodeName: currentNodeName,
                deviceType: UIDevice.current.model
            )
            context.insert(node)
            print("🆕 注册新节点: \(currentNodeName)")
        }
        
        try? context.save()
    }
    
    /// 标记节点离线
    private func markNodeOffline() async {
        guard let context = context else { return }
        
        let descriptor = FetchDescriptor<MonitorNode>(
            predicate: #Predicate { $0.nodeId == currentNodeId }
        )
        
        if let node = try? context.fetch(descriptor).first {
            node.markOffline()
            try? context.save()
        }
    }
    
    /// 更新节点心跳
    @objc private func sendHeartbeat() {
        Task {
            guard let context = context else { return }
            
            let descriptor = FetchDescriptor<MonitorNode>(
                predicate: #Predicate { $0.nodeId == currentNodeId }
            )
            
            if let node = try? context.fetch(descriptor).first {
                node.updateActivity()
                try? context.save()
            }
            
            // 同时更新在线节点列表
            await fetchOnlineNodes()
        }
    }
    
    /// 获取在线节点
    private func fetchOnlineNodes() async {
        guard let context = context else { return }
        
        let cutoffTime = Date().addingTimeInterval(-TaskConfig.nodeOfflineThreshold)
        
        let descriptor = FetchDescriptor<MonitorNode>(
            predicate: #Predicate { $0.lastActiveAt > cutoffTime && $0.isOnline == true },
            sortBy: [SortDescriptor(\.weight, order: .reverse)]
        )
        
        if let nodes = try? context.fetch(descriptor) {
            await MainActor.run {
                self.onlineNodes = nodes
            }
        }
    }
    
    // MARK: - 定时器管理
    
    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(
            timeInterval: TaskConfig.heartbeatInterval,
            target: self,
            selector: #selector(sendHeartbeat),
            userInfo: nil,
            repeats: true
        )
    }
    
    private func startTaskChecking() {
        // 立即检查一次
        Task {
            await checkAndClaimTasks()
        }
        
        // 设置定时检查
        taskCheckTimer = Timer.scheduledTimer(
            timeInterval: TaskConfig.taskAssignmentRetryInterval,
            target: self,
            selector: #selector(checkTasks),
            userInfo: nil,
            repeats: true
        )
    }
    
    @objc private func checkTasks() {
        Task {
            await checkAndClaimTasks()
        }
    }
    
    // MARK: - 任务分配核心逻辑
    
    /// 检查并领取任务
    private func checkAndClaimTasks() async {
        guard let context = context else { return }
        guard currentTasks.count < TaskConfig.maxConcurrentTasksPerNode else {
            print("⏸️ 当前任务已满 (\(currentTasks.count)/\(TaskConfig.maxConcurrentTasksPerNode))")
            return
        }
        
        // 0. 预刷新裙子索引缓存（用于高效去重）
        await SkirtIndexCache.shared.refreshCache()
        
        // 1. 查询所有任务，然后在内存中过滤待处理的任务
        let descriptor = FetchDescriptor<MonitorTask>(
            sortBy: [
                SortDescriptor(\.priority, order: .reverse),
                SortDescriptor(\.createdAt)
            ]
        )
        
        guard let allTasks = try? context.fetch(descriptor),
              !allTasks.isEmpty else {
            return
        }
        
        // 内存中过滤待处理的任务
        let pendingTasks = MonitorTask.filterPending(from: allTasks)
        guard !pendingTasks.isEmpty else {
            return
        }
        
        print("📋 发现 \(pendingTasks.count) 个待处理任务")
        
        // 2. 尝试领取任务（抢占式）
        let availableSlots = TaskConfig.maxConcurrentTasksPerNode - currentTasks.count
        let tasksToClaim = min(availableSlots, pendingTasks.count)
        
        for i in 0..<tasksToClaim {
            let task = pendingTasks[i]
            
            // 尝试分配任务给自己
            if claimTask(task) {
                // 启动任务执行
                Task {
                    await executeTask(task)
                }
            }
        }
    }
    
    /// 抢占式领取任务
    /// 使用乐观锁机制：先尝试分配，如果失败说明被其他节点抢走
    private func claimTask(_ task: MonitorTask) -> Bool {
        // 再次检查状态（可能被其他节点抢走）
        guard task.status == .pending else {
            return false
        }
        
        // 尝试分配
        let success = task.assign(to: currentNodeId)
        
        if success {
            // 保存到数据库
            if let context = context {
                try? context.save()
                
                // 更新当前任务列表
                Task { @MainActor in
                    self.currentTasks.append(task)
                }
                
                print("✅ 成功领取任务: \(task.taskDescription)")
            }
        }
        
        return success
    }
    
    /// 执行任务的包装方法
    private func executeTask(_ task: MonitorTask) async {
        guard task.startProcessing() else {
            print("❌ 无法开始任务: \(task.taskDescription)")
            return
        }
        
        // 保存状态变更
        if let context = context {
            try? context.save()
        }
        
        // 更新节点统计
        updateNodeTaskStart()
        
        // 执行实际任务
        let result = await performTask(task)
        
        // 处理结果
        await handleTaskResult(task, result: result)
    }
    
    /// 实际执行任务
    private func performTask(_ task: MonitorTask) async -> TaskResult {
        print("🔄 执行任务: \(task.taskDescription)")
        
        let startTime = Date()
        
        do {
            switch task.taskType {
            case .search:
                return await performSearchTask(task)
            case .detail:
                return await performDetailTask(task)
            case .userItems:
                return await performUserItemsTask(task)
            case .comment:
                return await performCommentTask(task)
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }
    
    /// 执行搜索任务
    private func performSearchTask(_ task: MonitorTask) async -> TaskResult {
        guard let keyword = task.keyword else {
            return .failure("缺少关键词")
        }
        
        print("🔍 搜索: \(keyword) on \(task.platform.rawValue)")
        
        // 这里调用实际的抓取逻辑
        // 暂时返回模拟结果
        let mockItems = await mockFetchItems(platform: task.platform, keyword: keyword)
        
        // 处理抓取到的商品
        let (totalCount, newCount) = await processFetchedItems(mockItems)
        
        return .success(itemsFound: totalCount, itemsNew: newCount)
    }
    
    /// 执行详情任务
    private func performDetailTask(_ task: MonitorTask) async -> TaskResult {
        guard let url = task.targetURL else {
            return .failure("缺少URL")
        }
        
        print("📄 获取详情: \(url)")
        
        // 模拟详情抓取
        return .success(itemsFound: 1, itemsNew: 0)
    }
    
    /// 执行用户商品任务
    private func performUserItemsTask(_ task: MonitorTask) async -> TaskResult {
        guard let userId = task.targetUserId else {
            return .failure("缺少用户ID")
        }
        
        print("👤 获取用户商品: \(userId)")
        
        return .success(itemsFound: 0, itemsNew: 0)
    }
    
    /// 执行评论采集任务
    private func performCommentTask(_ task: MonitorTask) async -> TaskResult {
        print("💬 采集评论")
        return .success(itemsFound: 0, itemsNew: 0)
    }
    
    /// 处理任务结果
    private func handleTaskResult(_ task: MonitorTask, result: TaskResult) async {
        switch result {
        case .success(let itemsFound, let itemsNew):
            task.complete(itemsFound: itemsFound, itemsNew: itemsNew)
            
            // 更新统计
            await MainActor.run {
                self.taskStats.completedTasks += 1
                self.taskStats.totalItemsFound += itemsFound
                self.taskStats.totalItemsNew += itemsNew
            }
            
            // 更新节点统计
            updateNodeTaskCompletion(itemsFound: itemsFound, success: true)
            
            print("✅ 任务完成: \(task.taskDescription), 发现 \(itemsFound) 个商品, 新增 \(itemsNew) 个")
            
        case .failure(let reason):
            task.fail(reason: reason)
            
            await MainActor.run {
                self.taskStats.failedTasks += 1
            }
            
            updateNodeTaskCompletion(itemsFound: 0, success: false)
            
            print("❌ 任务失败: \(task.taskDescription), 原因: \(reason)")
        }
        
        // 保存结果
        if let context = context {
            try? context.save()
        }
        
        // 从当前任务列表移除
        await MainActor.run {
            self.currentTasks.removeAll { $0.taskID == task.taskID }
        }
    }
    
    // MARK: - 数据处理
    
    /// 处理抓取到的商品
    private func processFetchedItems(_ items: [LolitaItem]) async -> (total: Int, new: Int) {
        guard let context = context else { return (0, 0) }
        
        var newCount = 0
        
        // 获取所有现有商品（简化谓词）
        let allDescriptor = FetchDescriptor<LolitaItem>()
        let allItems = (try? context.fetch(allDescriptor)) ?? []
        
        for item in items {
            // 在内存中检查是否已存在
            let existing = allItems.first { $0.platformID == item.platformID }
            
            if let existing = existing {
                // 更新现有记录
                existing.currentPrice = item.currentPrice
                existing.status = item.status
                existing.lastUpdated = Date()
            } else {
                // 新记录
                item.collectorDeviceId = currentNodeId
                item.collectorNodeName = currentNodeName
                context.insert(item)
                newCount += 1
            }
        }
        
        try? context.save()
        return (items.count, newCount)
    }
    
    /// 模拟抓取（实际项目中替换为真实抓取逻辑）
    private func mockFetchItems(platform: PlatformType, keyword: String) async -> [LolitaItem] {
        // 模拟网络延迟
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // 返回模拟数据
        var items: [LolitaItem] = []
        
        for i in 0..<5 {
            let item = LolitaItem(
                platform: platform,
                platformItemId: "mock_\(i)_\(Int.random(in: 1000...9999))",
                rawTitle: "\(keyword) 第\(i+1)件",
                currentPrice: Double.random(in: 100...2000)
            )
            item.brand = "测试品牌"
            item.status = .onSale
            items.append(item)
        }
        
        return items
    }
    
    // MARK: - 节点统计更新
    
    private func updateNodeTaskStart() {
        Task {
            guard let context = context else { return }
            
            let descriptor = FetchDescriptor<MonitorNode>(
                predicate: #Predicate { $0.nodeId == currentNodeId }
            )
            
            if let node = try? context.fetch(descriptor).first {
                node.recordTaskStart()
                try? context.save()
            }
        }
    }
    
    private func updateNodeTaskCompletion(itemsFound: Int, success: Bool) {
        Task {
            guard let context = context else { return }
            
            let descriptor = FetchDescriptor<MonitorNode>(
                predicate: #Predicate { $0.nodeId == currentNodeId }
            )
            
            if let node = try? context.fetch(descriptor).first {
                node.recordTaskCompletion(itemsFound: itemsFound, success: success)
                try? context.save()
            }
        }
    }
    
    private func releaseCurrentTasks() {
        Task {
            guard let context = context else { return }
            
            for task in currentTasks {
                // 将任务重置为待处理状态，让其他节点可以接手
                task.reset()
            }
            
            try? context.save()
            
            await MainActor.run {
                self.currentTasks.removeAll()
            }
        }
    }
    
    // MARK: - 后台任务
    
    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundTask(task as! BGAppRefreshTask)
        }
    }
    
    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            // 任务即将过期时的清理
            print("⏰ 后台任务即将过期")
        }
        
        Task {
            await checkAndClaimTasks()
            task.setTaskCompleted(success: true)
        }
    }
    
    /// 调度后台任务
    func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15分钟后
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("📅 后台任务已调度")
        } catch {
            print("❌ 调度后台任务失败: \(error)")
        }
    }
    
    // MARK: - 公共API（供UI调用）
    
    /// 获取在线节点数
    func getOnlineNodeCount() -> Int {
        return onlineNodes.filter { $0.isOnline }.count
    }
    
    /// 获取所有节点
    func getAllNodes() -> [MonitorNode] {
        return onlineNodes
    }
    
    /// 获取待处理任务数
    func getPendingTaskCount() -> Int {
        guard let context = context else { return 0 }
        let descriptor = FetchDescriptor<MonitorTask>()
        let allTasks = (try? context.fetch(descriptor)) ?? []
        return MonitorTask.filterPending(from: allTasks).count
    }
    
    /// 获取今日采集数
    func getTodayCollectedCount() -> Int {
        return taskStats.totalItemsFound
    }
    
    /// 获取成功率
    func getSuccessRate() -> Int {
        return Int(taskStats.successRate * 100)
    }
    
    // MARK: - 公共API
    
    /// 创建新任务
    func createTask(
        type: TaskType,
        platform: PlatformType,
        keyword: String? = nil,
        url: String? = nil,
        priority: Int = 5
    ) async {
        guard let context = context else { return }
        
        let task = MonitorTask(
            taskType: type,
            platform: platform,
            keyword: keyword,
            targetURL: url,
            priority: priority,
            creatorNodeId: currentNodeId
        )
        
        context.insert(task)
        try? context.save()
        
        print("📝 创建任务: \(task.taskDescription)")
    }
    
    /// 批量创建搜索任务
    func createSearchTasks(keywords: [String], platform: PlatformType) async {
        for keyword in keywords {
            await createTask(
                type: .search,
                platform: platform,
                keyword: keyword,
                priority: 5
            )
        }
    }
}

// MARK: - 任务结果枚举

enum TaskResult {
    case success(itemsFound: Int, itemsNew: Int)
    case failure(String)
}

// MARK: - 任务统计

struct TaskStatistics {
    var completedTasks: Int = 0
    var failedTasks: Int = 0
    var totalItemsFound: Int = 0
    var totalItemsNew: Int = 0
    
    var successRate: Double {
        let total = completedTasks + failedTasks
        guard total > 0 else { return 0 }
        return Double(completedTasks) / Double(total)
    }
}

// MARK: - 使用示例

/*
// 在App中启动任务分发器
@main
struct YourApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 配置裙子股市
        Task {
            await SkirtMarketPersistence.shared.configure()
            await TaskDispatcher.shared.start()
            
            // 创建一些示例任务
            await TaskDispatcher.shared.createSearchTasks(
                keywords: ["AP 辉夜姬", "Baby 铭记", "古典玩偶"],
                platform: .xianyu
            )
        }
        
        return true
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        TaskDispatcher.shared.scheduleBackgroundTask()
    }
}
*/
