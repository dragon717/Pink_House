//
//  SkirtStockMarketView.swift
//  裙子股市 - 股市可视化界面
//
//  实验室界面，展示K线图、节点监控、AI决策等
//

import SwiftUI
import SwiftData
import Charts

/// 裙子股市实验室主界面
struct SkirtStockMarketView: View {
    @Environment(\.modelContext) private var context
    
    // MARK: - 查询
    
    /// 大盘指数数据
    @Query(sort: \LolitaMarketIndex.timestamp, order: .reverse)
    private var marketIndices: [LolitaMarketIndex]
    
    /// 个股指标数据
    @Query(sort: \SkirtStockMetric.timestamp, order: .reverse)
    private var stockMetrics: [SkirtStockMetric]
    
    /// 在线节点（简化谓词，避免Date计算）
    @Query(
        filter: #Predicate<MonitorNode> {
            $0.isOnline == true
        },
        sort: \MonitorNode.lastActiveAt,
        order: .reverse
    )
    private var allNodes: [MonitorNode]
    
    /// 过滤后的在线节点（5分钟内活跃的）
    private var onlineNodes: [MonitorNode] {
        let cutoffTime = Date().addingTimeInterval(-300) // 5分钟前
        return allNodes.filter { $0.lastActiveAt > cutoffTime }
    }
    
    /// 最近任务
    @Query(
        sort: \MonitorTask.createdAt,
        order: .reverse
    )
    private var recentTasks: [MonitorTask]
    
    // MARK: - 状态
    
    @StateObject private var dispatcher = TaskDispatcher.shared
    @State private var selectedTimeRange: TimeRange = .day
    @State private var selectedSkirt: String?
    @State private var showNodeDetails = false
    @State private var showTaskCreator = false
    
    // MARK: - 配置
    
    /// 萌款列表（可配置）
    let popularSkirts = [
        "AP 辉夜姬",
        "Baby 铭记",
        "古典玩偶 小熊童子",
        "JEJ 抱猫",
        "IW 中古",
        "VM 中古"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. 大盘指数卡片
                    marketIndexCard
                    
                    // 2. 分布式节点监控
                    nodeMonitorCard
                    
                    // 3. K线图
                    stockChartSection
                    
                    // 4. AI决策雷达
                    aiDecisionSection
                    
                    // 5. 任务队列
                    taskQueueSection
                }
                .padding()
            }
            .navigationTitle("裙子实验室 🧪")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showTaskCreator = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showTaskCreator) {
                TaskCreatorView()
            }
        }
    }
    
    // MARK: - 大盘指数卡片
    
    private var marketIndexCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("萌款大盘指数", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                
                Spacer()
                
                // 时间范围选择器
                Picker("", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            
            if let latestIndex = marketIndices.first {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(String(format: "%.2f", latestIndex.indexValue))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    
                    HStack(spacing: 4) {
                        Image(systemName: latestIndex.changePercent >= 0 ? "arrow.up" : "arrow.down")
                        Text(String(format: "%.2f%%", latestIndex.changePercent * 100))
                    }
                    .font(.title3.bold())
                    .foregroundColor(latestIndex.changePercent >= 0 ? .green : .red)
                }
                
                HStack(spacing: 16) {
                    StatBadge(
                        icon: "bag.fill",
                        label: "总挂牌",
                        value: "\(latestIndex.totalListings)"
                    )
                    
                    StatBadge(
                        icon: "iphone.radiowaves.left.and.right",
                        label: "在线节点",
                        value: "\(latestIndex.activeNodes)"
                    )
                    
                    StatBadge(
                        icon: "sparkles",
                        label: "情绪指数",
                        value: String(format: "%.2f", latestIndex.averageSentiment)
                    )
                }
            } else {
                // 无数据状态
                ContentUnavailableView(
                    "暂无数据",
                    systemImage: "chart.line.downtrend.xyaxis",
                    description: Text("等待分布式节点采集数据...")
                )
                .frame(height: 120)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - 节点监控卡片
    
    private var nodeMonitorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("分布式算力监控", systemImage: "network")
                    .font(.headline)
                
                Spacer()
                
                // 当前节点状态
                HStack(spacing: 4) {
                    Circle()
                        .fill(dispatcher.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(dispatcher.isRunning ? "运行中" : "已停止")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // 节点列表
            LazyVStack(spacing: 8) {
                ForEach(onlineNodes.prefix(5)) { node in
                    NodeRow(node: node)
                }
            }
            
            // 统计信息
            HStack(spacing: 16) {
                Text("在线节点: \(onlineNodes.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("当前任务: \(dispatcher.currentTasks.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("成功率: \(Int(dispatcher.taskStats.successRate * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - K线图区域
    
    private var stockChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("价格波动", systemImage: "chart.candlestick")
                    .font(.headline)
                
                Spacer()
                
                // 萌款选择
                Menu {
                    ForEach(popularSkirts, id: \.self) { skirt in
                        Button(skirt) {
                            selectedSkirt = skirt
                        }
                    }
                } label: {
                    Label(selectedSkirt ?? "选择萌款", systemImage: "chevron.down")
                        .font(.subheadline)
                }
            }
            
            // K线图
            if let selectedSkirt = selectedSkirt,
               !filteredMetrics(for: selectedSkirt).isEmpty {
                
                StockChart(metrics: filteredMetrics(for: selectedSkirt))
                    .frame(height: 200)
                
                // 最新指标
                if let latest = filteredMetrics(for: selectedSkirt).first {
                    HStack(spacing: 16) {
                        PriceBadge(
                            label: "最高",
                            price: latest.highPrice,
                            color: .red
                        )
                        PriceBadge(
                            label: "最低",
                            price: latest.lowPrice,
                            color: .green
                        )
                        PriceBadge(
                            label: "平均",
                            price: latest.averagePrice,
                            color: .blue
                        )
                    }
                }
            } else {
                ContentUnavailableView(
                    "选择萌款查看价格走势",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - AI决策区域
    
    private var aiDecisionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI 实验室决策", systemImage: "brain.head.profile")
                .font(.headline)
            
            // AI建议列表
            LazyVStack(spacing: 8) {
                ForEach(stockMetrics.prefix(5), id: \.metricID) { metric in
                    AIDecisionRow(metric: metric)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - 任务队列区域
    
    private var taskQueueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("任务队列", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                
                Spacer()
                
                Text("\(recentTasks.filter { $0.status == .pending }.count) 待处理")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // 任务列表
            LazyVStack(spacing: 8) {
                ForEach(recentTasks.prefix(5)) { task in
                    TaskRow(task: task)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - 辅助方法
    
    private func filteredMetrics(for skirtName: String) -> [SkirtStockMetric] {
        stockMetrics.filter { $0.skirtName == skirtName }
    }
}

// MARK: - 子视图组件

/// 统计徽章
struct StatBadge: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption.bold())
            }
        }
    }
}

/// 节点行
struct NodeRow: View {
    let node: MonitorNode
    
    var body: some View {
        HStack {
            // 节点图标
            ZStack {
                Circle()
                    .fill(node.isOnline ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "iphone")
                    .font(.caption)
                    .foregroundColor(node.isOnline ? .green : .gray)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(node.nodeName)
                    .font(.subheadline.bold())
                
                HStack(spacing: 8) {
                    Label("\(node.totalTasksProcessed)", systemImage: "checkmark.circle")
                        .font(.caption2)
                    
                    Label("\(node.totalItemsFound)", systemImage: "bag")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 成功率
            Text("\(Int(node.successRate * 100))%")
                .font(.caption.bold())
                .foregroundColor(node.successRate > 0.8 ? .green : .orange)
        }
        .padding(.vertical, 4)
    }
}

/// 价格徽章
struct PriceBadge: View {
    let label: String
    let price: Double
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("¥\(Int(price))")
                .font(.caption.bold())
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

/// AI决策行
struct AIDecisionRow: View {
    let metric: SkirtStockMetric
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.skirtName)
                    .font(.subheadline.bold())
                
                HStack(spacing: 8) {
                    Text("情绪: \(String(format: "%.2f", metric.sentimentScore))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let bargainRatio = metric.bargainRatio {
                        Text("好价: \(Int(bargainRatio * 100))%")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
            
            // 投资建议
            let suggestion = metric.investmentSuggestion
            Text(suggestion.icon + " " + suggestion.rawValue)
                .font(.caption.bold())
                .foregroundColor(Color(hex: suggestion.color))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: suggestion.color).opacity(0.1))
                .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }
}

/// 任务行
struct TaskRow: View {
    let task: MonitorTask
    
    var body: some View {
        HStack {
            // 状态图标
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(task.taskDescription)
                    .font(.subheadline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(task.platform.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let itemsFound = task.itemsFound {
                        Text("发现 \(itemsFound) 个")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            // 优先级
            Text("P\(task.priority)")
                .font(.caption2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(priorityColor)
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
    }
    
    private var statusIcon: String {
        switch task.status {
        case .pending: return "clock"
        case .assigned: return "person.fill.checkmark"
        case .processing: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .expired: return "exclamationmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch task.status {
        case .pending: return .gray
        case .assigned: return .blue
        case .processing: return .orange
        case .completed: return .green
        case .failed: return .red
        case .expired: return .gray
        }
    }
    
    private var priorityColor: Color {
        switch task.priority {
        case 8...10: return .red
        case 5...7: return .orange
        default: return .gray
        }
    }
}

/// K线图
struct StockChart: View {
    let metrics: [SkirtStockMetric]
    
    var body: some View {
        Chart(metrics.reversed()) { metric in
            // 蜡烛图主体（高低价范围）
            RectangleMark(
                x: .value("时间", metric.timestamp),
                yStart: .value("最低", metric.lowPrice),
                yEnd: .value("最高", metric.highPrice),
                width: .fixed(8)
            )
            .foregroundStyle(metric.priceChangeRatio ?? 0 >= 0 ? Color.red : Color.green)
            
            // 平均线
            RuleMark(
                y: .value("平均", metric.averagePrice)
            )
            .foregroundStyle(.blue)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5))
        }
    }
}

/// 时间范围枚举
enum TimeRange: String, CaseIterable, Identifiable {
    case hour = "1小时"
    case day = "1天"
    case week = "1周"
    case month = "1月"
    
    var id: String { rawValue }
}

// MARK: - 任务创建视图

struct TaskCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlatform: PlatformType = .xianyu
    @State private var keyword = ""
    @State private var priority = 5
    
    var body: some View {
        NavigationStack {
            Form {
                Section("任务类型") {
                    Picker("平台", selection: $selectedPlatform) {
                        ForEach(PlatformType.allCases, id: \.self) { platform in
                            Text(platform.rawValue).tag(platform)
                        }
                    }
                }
                
                Section("搜索参数") {
                    TextField("关键词", text: $keyword)
                }
                
                Section("优先级") {
                    Stepper("优先级: \(priority)", value: $priority, in: 1...10)
                }
            }
            .navigationTitle("创建任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        createTask()
                    }
                    .disabled(keyword.isEmpty)
                }
            }
        }
    }
    
    private func createTask() {
        Task {
            await TaskDispatcher.shared.createTask(
                type: .search,
                platform: selectedPlatform,
                keyword: keyword,
                priority: priority
            )
            dismiss()
        }
    }
}

// MARK: - 预览

#Preview {
    SkirtStockMarketView()
        .modelContainer(for: [
            LolitaItem.self,
            SkirtStockMetric.self,
            LolitaMarketIndex.self,
            MonitorTask.self,
            MonitorNode.self
        ], inMemory: true)
}
