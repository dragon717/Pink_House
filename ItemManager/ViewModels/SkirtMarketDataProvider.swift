//
//  SkirtMarketDataProvider.swift
//  裙子股市 - 独立容器数据提供者
//
//  由于裙子股市使用独立的 ModelContainer，无法使用 @Query
//  此类提供手动数据获取和状态管理功能
//

import Foundation
import SwiftData
import Combine

/// 裙子股市数据提供者
/// 管理独立容器中的数据获取和状态更新
@MainActor
final class SkirtMarketDataProvider: ObservableObject {
    static let shared = SkirtMarketDataProvider()
    
    // MARK: - 发布的数据状态
    
    /// 大盘指数列表
    @Published var marketIndices: [LolitaMarketIndex] = []
    
    /// 萌款指标列表
    @Published var stockMetrics: [SkirtStockMetric] = []
    
    /// 最新商品列表
    @Published var recentItems: [LolitaItem] = []
    
    /// 在线节点数
    @Published var onlineNodes: Int = 0
    
    /// 数据条数
    @Published var dataCount: Int = 0
    
    /// 是否正在加载
    @Published var isLoading = false
    
    /// 错误信息
    @Published var errorMessage: String?
    
    // MARK: - 私有属性
    
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // MARK: - 数据加载
    
    /// 加载所有数据
    func loadAllData() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        await loadMarketIndices()
        await loadStockMetrics()
        await loadRecentItems()
        await loadNodeStatus()
        
        print("✅ 裙子股市数据加载完成")
    }
    
    /// 加载大盘指数
    private func loadMarketIndices() async {
        guard let context = SkirtMarketPersistenceV2.shared.mainContext else {
            print("❌ 无法获取裙子股市上下文")
            return
        }
        
        let descriptor = FetchDescriptor<LolitaMarketIndex>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            marketIndices = try context.fetch(descriptor)
            print("📊 加载了 \(marketIndices.count) 条大盘指数")
        } catch {
            print("❌ 加载大盘指数失败: \(error)")
            errorMessage = "加载大盘指数失败"
        }
    }
    
    /// 加载萌款指标
    private func loadStockMetrics() async {
        guard let context = SkirtMarketPersistenceV2.shared.mainContext else { return }
        
        let descriptor = FetchDescriptor<SkirtStockMetric>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            stockMetrics = try context.fetch(descriptor)
            print("📈 加载了 \(stockMetrics.count) 条萌款指标")
        } catch {
            print("❌ 加载萌款指标失败: \(error)")
        }
    }
    
    /// 加载最新商品
    private func loadRecentItems() async {
        guard let context = SkirtMarketPersistenceV2.shared.mainContext else { return }
        
        let descriptor = FetchDescriptor<LolitaItem>(
            predicate: #Predicate { $0.isDeleted == false },
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        
        do {
            recentItems = try context.fetch(descriptor)
            dataCount = recentItems.count
            print("👗 加载了 \(recentItems.count) 个商品")
        } catch {
            print("❌ 加载商品失败: \(error)")
        }
    }
    
    /// 加载节点状态
    private func loadNodeStatus() async {
        guard let context = SkirtMarketPersistenceV2.shared.mainContext else { return }
        
        let descriptor = FetchDescriptor<MonitorNode>()
        
        do {
            let nodes = try context.fetch(descriptor)
            onlineNodes = nodes.filter { $0.isOnline }.count
            print("🖥️ 在线节点: \(onlineNodes)")
        } catch {
            print("❌ 加载节点状态失败: \(error)")
        }
    }
    
    // MARK: - 自动刷新
    
    /// 开始自动刷新
    func startAutoRefresh(interval: TimeInterval = 30) {
        stopAutoRefresh()
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadAllData()
            }
        }
        
        print("🔄 启动自动刷新，间隔: \(interval)秒")
    }
    
    /// 停止自动刷新
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - 数据操作
    
    /// 插入新商品
    func insertItem(_ item: LolitaItem) async {
        guard let context = SkirtMarketPersistenceV2.shared.mainContext else { return }
        
        context.insert(item)
        
        do {
            try context.save()
            print("✅ 插入商品: \(item.platformID)")
            await loadRecentItems() // 刷新列表
        } catch {
            print("❌ 插入商品失败: \(error)")
        }
    }
    
    /// 删除商品（软删除）
    func softDeleteItem(_ item: LolitaItem) async {
        guard let context = SkirtMarketPersistenceV2.shared.mainContext else { return }
        
        item.isDeleted = true
        item.lastUpdated = Date()
        
        do {
            try context.save()
            print("🗑️ 软删除商品: \(item.platformID)")
            await loadRecentItems() // 刷新列表
        } catch {
            print("❌ 删除商品失败: \(error)")
        }
    }
    
    // MARK: - 数据聚合
    
    /// 获取最新的大盘指数
    var latestMarketIndex: LolitaMarketIndex? {
        marketIndices.first
    }
    
    /// 按萌款名称分组的指标
    var groupedMetrics: [String: SkirtStockMetric] {
        Dictionary(grouping: stockMetrics) { $0.skirtName }
            .compactMapValues { $0.first }
    }
    
    /// 获取特定萌款的历史数据
    func metricsForSkirt(_ skirtName: String) -> [SkirtStockMetric] {
        stockMetrics.filter { $0.skirtName == skirtName }
            .sorted { $0.timestamp > $1.timestamp }
    }
}

// MARK: - 使用示例

/*
// 在视图中使用
struct SkirtMarketView: View {
    @StateObject private var dataProvider = SkirtMarketDataProvider.shared
    
    var body: some View {
        List {
            // 使用 dataProvider.marketIndices
            // 使用 dataProvider.stockMetrics
            // 使用 dataProvider.recentItems
        }
        .onAppear {
            Task {
                await dataProvider.loadAllData()
                dataProvider.startAutoRefresh(interval: 30)
            }
        }
        .onDisappear {
            dataProvider.stopAutoRefresh()
        }
        .refreshable {
            await dataProvider.loadAllData()
        }
    }
}
*/
