//
//  SkirtMarketViewModel.swift
//  裙装股市 - 视图模型
//
//  管理裙装股市的数据状态和业务逻辑
//

import SwiftUI
import SwiftData
import Combine

/// 裙装股市视图模型 - 数据驱动的核心
@MainActor
final class SkirtMarketViewModel: ObservableObject {
    // MARK: - 发布属性
    
    /// 当前选中的标签页
    @Published var selectedTab: MarketTab = .overview
    
    /// 选中的裙装名称（用于详情展示）
    @Published var selectedSkirt: String?
    
    /// 是否显示节点面板
    @Published var showingNodePanel = false
    
    /// 在线节点数
    @Published var onlineNodes: Int = 0
    
    /// 大盘指数历史
    @Published var marketIndices: [LolitaMarketIndex] = []
    
    /// 萌款指标数据
    @Published var stockMetrics: [SkirtStockMetric] = []
    
    /// 最新商品列表
    @Published var recentItems: [LolitaItem] = []
    
    /// 任务统计
    @Published var taskStats = TaskExecutionStats()
    
    /// 是否正在加载
    @Published var isLoading = false
    
    /// 错误信息
    @Published var errorMessage: String?
    
    /// 是否显示错误
    @Published var showError = false
    
    // MARK: - 标签页枚举
    
    enum MarketTab: String, CaseIterable {
        case overview = "大盘"
        case skirts = "萌款"
        case nodes = "节点"
        
        var icon: String {
            switch self {
            case .overview: return "chart.line.uptrend.xyaxis"
            case .skirts: return "hanger"
            case .nodes: return "network"
            }
        }
    }
    
    // MARK: - 私有属性
    
    /// 模型上下文
    private var context: ModelContext?
    
    /// 取消令牌集合
    private var cancellables = Set<AnyCancellable>()
    
    /// 定时刷新计时器
    private var refreshTimer: Timer?
    
    // MARK: - 初始化
    
    init() {
        self.context = SkirtMarketPersistenceV2.shared.mainContext
        setupBindings()
    }
    
    // MARK: - 设置绑定
    
    private func setupBindings() {
        // 监听TaskDispatcher的任务统计更新
        TaskDispatcher.shared.$taskStats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.updateTaskStats(from: stats)
            }
            .store(in: &cancellables)
        
        // 监听在线节点变化
        TaskDispatcher.shared.$onlineNodes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] nodes in
                self?.onlineNodes = nodes.filter { $0.isOnline }.count
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 数据加载
    
    /// 加载所有数据
    func loadAllData() async {
        isLoading = true
        defer { isLoading = false }
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadMarketIndices() }
            group.addTask { await self.loadStockMetrics() }
            group.addTask { await self.loadRecentItems() }
            group.addTask { await self.updateOnlineNodes() }
        }
    }
    
    /// 加载大盘指数
    func loadMarketIndices() async {
        guard let context = context else { return }
        
        let descriptor = FetchDescriptor<LolitaMarketIndex>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            let indices = try context.fetch(descriptor)
            await MainActor.run {
                self.marketIndices = indices
            }
        } catch {
            showError(message: "加载大盘指数失败: \(error.localizedDescription)")
        }
    }
    
    /// 加载萌款指标
    func loadStockMetrics() async {
        guard let context = context else { return }
        
        let descriptor = FetchDescriptor<SkirtStockMetric>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            let metrics = try context.fetch(descriptor)
            await MainActor.run {
                self.stockMetrics = metrics
            }
        } catch {
            showError(message: "加载萌款数据失败: \(error.localizedDescription)")
        }
    }
    
    /// 加载最新商品
    func loadRecentItems() async {
        guard let context = context else { return }
        
        let descriptor = FetchDescriptor<LolitaItem>(
            predicate: #Predicate { $0.isDeleted == false },
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        
        do {
            let items = try context.fetch(descriptor)
            await MainActor.run {
                self.recentItems = Array(items.prefix(20))
            }
        } catch {
            showError(message: "加载商品数据失败: \(error.localizedDescription)")
        }
    }
    
    /// 更新在线节点数
    func updateOnlineNodes() async {
        onlineNodes = TaskDispatcher.shared.getOnlineNodeCount()
    }
    
    // MARK: - 数据操作
    
    /// 刷新索引缓存
    func refreshIndexCache() async {
        await SkirtIndexCache.shared.refreshCache()
    }
    
    // MARK: - 计算属性
    
    /// 最新大盘指数
    var latestMarketIndex: LolitaMarketIndex? {
        marketIndices.first
    }
    
    /// 按裙装分组的最新指标
    var groupedMetrics: [String: SkirtStockMetric] {
        Dictionary(grouping: stockMetrics) { $0.skirtName }
            .compactMapValues { $0.first }
    }
    
    /// 热门萌款列表（按平均价格排序）
    var popularSkirts: [SkirtStockMetric] {
        Array(groupedMetrics.values)
            .sorted { $0.averagePrice > $1.averagePrice }
    }
    
    /// 市场总挂牌数
    var totalListings: Int {
        latestMarketIndex?.totalListings ?? groupedMetrics.values.reduce(0) { $0 + $1.listingCount }
    }
    
    /// 市场涨跌幅
    var marketChangePercent: Double {
        latestMarketIndex?.changePercent ?? 0
    }
    
    /// 活跃萌款数
    var activeSkirtCount: Int {
        groupedMetrics.count
    }
    
    // MARK: - 定时刷新
    
    /// 启动定时刷新
    func startAutoRefresh(interval: TimeInterval = 30) {
        stopAutoRefresh()
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                await self?.loadAllData()
            }
        }
    }
    
    /// 停止定时刷新
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - 错误处理
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
    
    private func updateTaskStats(from dispatcherStats: TaskStatistics) {
        taskStats = TaskExecutionStats(
            completedTasks: dispatcherStats.completedTasks,
            failedTasks: dispatcherStats.failedTasks,
            totalItemsFound: dispatcherStats.totalItemsFound,
            totalItemsNew: dispatcherStats.totalItemsNew
        )
    }
}

// MARK: - 任务执行统计

struct TaskExecutionStats {
    var completedTasks: Int = 0
    var failedTasks: Int = 0
    var totalItemsFound: Int = 0
    var totalItemsNew: Int = 0
    
    var successRate: Double {
        let total = completedTasks + failedTasks
        guard total > 0 else { return 0 }
        return Double(completedTasks) / Double(total)
    }
    
    var successRatePercent: Int {
        Int(successRate * 100)
    }
}

// MARK: - 视图扩展

extension View {
    /// 应用裙装股市视图模型
    func skirtMarketViewModel(_ viewModel: SkirtMarketViewModel) -> some View {
        self.environmentObject(viewModel)
    }
}
