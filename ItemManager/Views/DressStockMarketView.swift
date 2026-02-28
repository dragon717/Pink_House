//
//  DressStockMarketView.swift
//  ItemManager
//
//  裙子股市 - 主界面
//  莫妮卡粉主题 + 金融级数据可视化
//  数据驱动展示
//

import SwiftUI
import SwiftData
import Charts

// MARK: - 主视图
struct DressStockMarketView: View {
    @StateObject private var viewModel = SkirtMarketViewModel()
    
    // MARK: - 状态
    @State private var marketIndices: [LolitaMarketIndex] = []
    @State private var stockMetrics: [SkirtStockMetric] = []
    @State private var recentItems: [LolitaItem] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 顶部导航
                    HeaderView(
                        latestIndex: marketIndices.first,
                        onlineNodes: viewModel.onlineNodes,
                        dataCount: stockMetrics.count
                    )
                    
                    // 标签页切换
                    TabSwitcher(selectedTab: $viewModel.selectedTab)
                    
                    // 内容区域
                    TabView(selection: $viewModel.selectedTab) {
                        MarketOverviewView(indices: marketIndices)
                            .tag(SkirtMarketViewModel.MarketTab.overview)
                        
                        SkirtListView(
                            metrics: stockMetrics,
                            selectedSkirt: $viewModel.selectedSkirt
                        )
                        .tag(SkirtMarketViewModel.MarketTab.skirts)
                        
                        NodeMonitorView()
                            .tag(SkirtMarketViewModel.MarketTab.nodes)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle("裙子股市")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NodeStatusView(onlineNodes: viewModel.onlineNodes)
                }
            }
            .navigationDestination(for: String.self) { skirtName in
                SkirtDetailView(skirtName: skirtName)
            }
        }
        .onAppear {
            Task {
                await loadData()
                viewModel.startAutoRefresh(interval: 30)
            }
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
        .refreshable {
            await loadData()
        }
        .alert("错误", isPresented: $viewModel.showError) {
            Button("确定") { viewModel.showError = false }
        } message: {
            Text(viewModel.errorMessage ?? "未知错误")
        }
    }
    
    // MARK: - 数据加载
    
    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let context = SkirtMarketPersistence.shared.mainContext else {
            print("❌ 无法获取裙子股市上下文")
            return
        }
        
        // 加载大盘指数
        let indexDescriptor = FetchDescriptor<LolitaMarketIndex>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        marketIndices = (try? context.fetch(indexDescriptor)) ?? []
        
        // 加载萌款指标
        let metricDescriptor = FetchDescriptor<SkirtStockMetric>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        stockMetrics = (try? context.fetch(metricDescriptor)) ?? []
        
        // 加载最新商品
        let itemDescriptor = FetchDescriptor<LolitaItem>(
            predicate: #Predicate { $0.isDeleted == false },
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        recentItems = (try? context.fetch(itemDescriptor)) ?? []
        
        // 更新视图模型数据
        await viewModel.loadAllData()
        
        print("✅ 裙子股市数据加载完成: \(marketIndices.count) 指数, \(stockMetrics.count) 指标, \(recentItems.count) 商品")
    }
}

// MARK: - 顶部视图（数据驱动）
struct HeaderView: View {
    let latestIndex: LolitaMarketIndex?
    let onlineNodes: Int
    let dataCount: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("LO-指数")
                    .font(SkirtMarketTheme.captionFont)
                    .foregroundStyle(.secondary)
                
                if let index = latestIndex {
                    IndexValueView(index: index)
                } else {
                    PlaceholderIndexView()
                }
            }
            
            Spacer()
            
            // 实时状态指示器
            LiveStatusView(dataCount: dataCount)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

// MARK: - 指数值视图
struct IndexValueView: View {
    let index: LolitaMarketIndex
    
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(String(format: "%.2f", index.indexValue))
                .font(SkirtMarketTheme.indexFont)
                .foregroundStyle(SkirtMarketTheme.primaryPink)
            
            ChangeBadge(changePercent: index.changePercent)
        }
    }
}

// MARK: - 占位指数视图
struct PlaceholderIndexView: View {
    var body: some View {
        Text("1,250.00")
            .font(SkirtMarketTheme.indexFont)
            .foregroundStyle(SkirtMarketTheme.primaryPink)
    }
}

// MARK: - 涨跌幅徽章
struct ChangeBadge: View {
    let changePercent: Double
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: changePercent >= 0 ? "arrow.up" : "arrow.down")
            Text(String(format: "%.2f%%", abs(changePercent)))
        }
        .font(SkirtMarketTheme.subtitleFont)
        .foregroundStyle(changePercent >= 0 ? SkirtMarketTheme.riseGreen : SkirtMarketTheme.fallRed)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (changePercent >= 0 ? SkirtMarketTheme.riseGreen : SkirtMarketTheme.fallRed)
                .opacity(0.1)
        )
        .cornerRadius(6)
    }
}

// MARK: - 实时状态视图
struct LiveStatusView: View {
    let dataCount: Int
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                PulsingDot()
                Text("实时")
                    .font(SkirtMarketTheme.captionFont)
                    .foregroundStyle(SkirtMarketTheme.primaryPink)
            }
            
            Text("\(dataCount) 条数据")
                .font(SkirtMarketTheme.captionFont)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 节点状态视图
struct NodeStatusView: View {
    let onlineNodes: Int
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: NodeCountFormatter.statusColor(onlineNodes)))
                .frame(width: 8, height: 8)
            Text("\(NodeCountFormatter.format(onlineNodes)) 节点")
                .font(SkirtMarketTheme.captionFont)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 标签切换器
struct TabSwitcher: View {
    @Binding var selectedTab: SkirtMarketViewModel.MarketTab
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(SkirtMarketViewModel.MarketTab.allCases, id: \.self) { tab in
                TabButton(
                    tab: tab,
                    isSelected: selectedTab == tab
                ) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = tab
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

// MARK: - 标签按钮
struct TabButton: View {
    let tab: SkirtMarketViewModel.MarketTab
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18))
                Text(tab.rawValue)
                    .font(SkirtMarketTheme.captionFont)
            }
            .foregroundStyle(isSelected ? SkirtMarketTheme.primaryPink : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isSelected ? SkirtMarketTheme.ultraLightPink : Color.clear
            )
        }
    }
}

// MARK: - 脉冲动画点
struct PulsingDot: View {
    @State private var isPulsing = false
    
    var body: some View {
        Circle()
            .fill(SkirtMarketTheme.riseGreen)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(SkirtMarketTheme.riseGreen, lineWidth: 2)
                    .scaleEffect(isPulsing ? 2 : 1)
                    .opacity(isPulsing ? 0 : 1)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - 大盘概览视图
struct MarketOverviewView: View {
    let indices: [LolitaMarketIndex]
    
    var body: some View {
        ScrollView {
            VStack(spacing: SkirtMarketTheme.standardSpacing) {
                // 指数走势图
                IndexChartCard(indices: indices)
                
                // 市场统计
                MarketStatsCard(indices: indices)
                
                // 热门板块
                HotSectorsCard()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - 指数走势图卡片
struct IndexChartCard: View {
    let indices: [LolitaMarketIndex]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChartHeader(title: "大盘走势", badge: "24H")
            
            if indices.count >= 2 {
                IndexChart(indices: indices)
            } else {
                ChartPlaceholder()
            }
        }
        .skirtMarketCardStyle()
    }
}

// MARK: - 图表头部
struct ChartHeader: View {
    let title: String
    let badge: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(SkirtMarketTheme.subtitleFont)
                .foregroundStyle(.primary)
            
            Spacer()
            
            Text(badge)
                .font(SkirtMarketTheme.captionFont)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(SkirtMarketTheme.ultraLightPink)
                .cornerRadius(4)
        }
    }
}

// MARK: - 指数图表
struct IndexChart: View {
    let indices: [LolitaMarketIndex]
    
    var body: some View {
        Chart(indices.suffix(24)) { index in
            LineMark(
                x: .value("时间", index.timestamp),
                y: .value("指数", index.indexValue)
            )
            .foregroundStyle(SkirtMarketTheme.primaryPink)
            .interpolationMethod(.catmullRom)
            
            AreaMark(
                x: .value("时间", index.timestamp),
                y: .value("指数", index.indexValue)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [SkirtMarketTheme.primaryPink.opacity(0.3), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)
        }
        .frame(height: 180)
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

// MARK: - 图表占位
struct ChartPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(SkirtMarketTheme.ultraLightPink)
            .frame(height: 180)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 40))
                        .foregroundStyle(SkirtMarketTheme.primaryPink.opacity(0.5))
                    Text("数据采集中...")
                        .font(SkirtMarketTheme.captionFont)
                        .foregroundStyle(.secondary)
                }
            )
    }
}

// MARK: - 市场统计卡片
struct MarketStatsCard: View {
    let indices: [LolitaMarketIndex]
    
    var latestIndex: LolitaMarketIndex? { indices.first }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("市场统计")
                .font(SkirtMarketTheme.subtitleFont)
                .foregroundStyle(.primary)
            
            HStack(spacing: 16) {
                MarketStatItem(
                    title: "总挂牌",
                    value: "\(latestIndex?.totalListings ?? 0)",
                    icon: "doc.text",
                    color: SkirtMarketTheme.primaryPink
                )
                
                MarketStatItem(
                    title: "萌款数",
                    value: "\(latestIndex?.componentCount ?? 0)",
                    icon: "star.fill",
                    color: SkirtMarketTheme.gold
                )
                
                MarketStatItem(
                    title: "情绪指数",
                    value: String(format: "%.2f", latestIndex?.averageSentiment ?? 0),
                    icon: "face.smiling",
                    color: SkirtMarketTheme.mintGreen
                )
                
                MarketStatItem(
                    title: "活跃节点",
                    value: "\(latestIndex?.activeNodes ?? 1)",
                    icon: "iphone",
                    color: SkirtMarketTheme.deepPink
                )
            }
        }
        .skirtMarketCardStyle()
    }
}

// MARK: - 统计项
struct MarketStatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            
            Text(title)
                .font(SkirtMarketTheme.captionFont)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 热门板块卡片
struct HotSectorsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("热门板块")
                .font(SkirtMarketTheme.subtitleFont)
                .foregroundStyle(.primary)
            
            VStack(spacing: 10) {
                SectorRow(name: "AP", change: 3.5, volume: 128)
                SectorRow(name: "Baby", change: -1.2, volume: 96)
                SectorRow(name: "IW", change: 0.8, volume: 64)
                SectorRow(name: "VM", change: 2.1, volume: 52)
            }
        }
        .skirtMarketCardStyle()
    }
}

// MARK: - 板块行
struct SectorRow: View {
    let name: String
    let change: Double
    let volume: Int
    
    var body: some View {
        HStack {
            Text(name)
                .font(SkirtMarketTheme.subtitleFont)
                .foregroundStyle(.primary)
                .frame(width: 60, alignment: .leading)
            
            Spacer()
            
            Text("\(volume)件")
                .font(SkirtMarketTheme.captionFont)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            ChangeLabel(change: change)
        }
    }
}

// MARK: - 涨跌标签
struct ChangeLabel: View {
    let change: Double
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
            Text(String(format: "%.1f%%", abs(change)))
        }
        .font(SkirtMarketTheme.captionFont)
        .foregroundStyle(change >= 0 ? SkirtMarketTheme.riseGreen : SkirtMarketTheme.fallRed)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (change >= 0 ? SkirtMarketTheme.riseGreen : SkirtMarketTheme.fallRed)
                .opacity(0.1)
        )
        .cornerRadius(4)
    }
}

// MARK: - 萌款列表视图
struct SkirtListView: View {
    let metrics: [SkirtStockMetric]
    @Binding var selectedSkirt: String?
    
    // 按裙子名称分组，取最新数据
    var groupedMetrics: [String: SkirtStockMetric] {
        Dictionary(grouping: metrics) { $0.skirtName }
            .compactMapValues { $0.first }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(
                    Array(groupedMetrics.values.sorted { $0.averagePrice > $1.averagePrice }),
                    id: \.skirtName
                ) { metric in
                    NavigationLink(value: metric.skirtName) {
                        SkirtRow(metric: metric)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - 萌款行
struct SkirtRow: View {
    let metric: SkirtStockMetric
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标
            SkirtIcon()
            
            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.skirtName)
                    .font(SkirtMarketTheme.subtitleFont)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 8) {
                    Label("\(metric.listingCount)", systemImage: "doc.text")
                    Label(String(format: "¥%.0f", metric.averagePrice), systemImage: "yensign")
                }
                .font(SkirtMarketTheme.captionFont)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // 投资建议
            let suggestion = metric.investmentSuggestion
            Text(suggestion.icon)
                .font(.title2)
                .padding(8)
                .background(Color(hex: suggestion.color).opacity(0.1))
                .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: SkirtMarketTheme.primaryPink.opacity(0.1), radius: 8, x: 0, y: 2)
    }
}

// MARK: - 裙子图标
struct SkirtIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(SkirtMarketTheme.ultraLightPink)
                .frame(width: 48, height: 48)
            
            Image(systemName: "hanger")
                .font(.system(size: 20))
                .foregroundStyle(SkirtMarketTheme.primaryPink)
        }
    }
}

// MARK: - 节点监控视图
struct NodeMonitorView: View {
    @State private var nodes: [MonitorNode] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: SkirtMarketTheme.standardSpacing) {
                // 节点统计
                NodeStatsCard()
                
                // 节点列表
                NodeListCard(nodes: nodes)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .onAppear {
            loadNodes()
        }
    }
    
    private func loadNodes() {
        nodes = TaskDispatcher.shared.getAllNodes()
    }
}

// MARK: - 节点统计卡片
struct NodeStatsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分布式算力")
                .font(SkirtMarketTheme.subtitleFont)
                .foregroundStyle(.primary)
            
            HStack(spacing: 16) {
                MarketStatItem(
                    title: "在线节点",
                    value: "\(TaskDispatcher.shared.getOnlineNodeCount())",
                    icon: "iphone.radiowaves.left.and.right",
                    color: SkirtMarketTheme.riseGreen
                )
                
                MarketStatItem(
                    title: "任务队列",
                    value: "\(TaskDispatcher.shared.getPendingTaskCount())",
                    icon: "list.bullet",
                    color: SkirtMarketTheme.gold
                )
                
                MarketStatItem(
                    title: "今日采集",
                    value: "\(TaskDispatcher.shared.getTodayCollectedCount())",
                    icon: "checkmark.circle",
                    color: SkirtMarketTheme.primaryPink
                )
                
                MarketStatItem(
                    title: "成功率",
                    value: "\(TaskDispatcher.shared.getSuccessRate())%",
                    icon: "chart.pie",
                    color: SkirtMarketTheme.mintGreen
                )
            }
        }
        .skirtMarketCardStyle()
    }
}

// MARK: - 节点列表卡片
struct NodeListCard: View {
    let nodes: [MonitorNode]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("节点状态")
                .font(SkirtMarketTheme.subtitleFont)
                .foregroundStyle(.primary)
            
            if nodes.isEmpty {
                EmptyNodeView()
            } else {
                VStack(spacing: 10) {
                    ForEach(nodes.prefix(5)) { node in
                        NodeRow(node: node)
                    }
                }
            }
        }
        .skirtMarketCardStyle()
    }
}

// MARK: - 空节点视图
struct EmptyNodeView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundStyle(SkirtMarketTheme.primaryPink.opacity(0.5))
            
            Text("暂无节点数据")
                .font(SkirtMarketTheme.bodyFont)
                .foregroundStyle(.secondary)
            
            Text("启动分布式任务后节点将显示在这里")
                .font(SkirtMarketTheme.captionFont)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 节点行
struct NodeRow: View {
    let node: MonitorNode
    
    var body: some View {
        HStack(spacing: 12) {
            // 状态指示
            Circle()
                .fill(node.isOnline ? SkirtMarketTheme.riseGreen : SkirtMarketTheme.fallRed)
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(node.nodeName)
                    .font(SkirtMarketTheme.bodyFont)
                    .foregroundStyle(.primary)
                
                Text("\(node.platforms.joined(separator: ", "))")
                    .font(SkirtMarketTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(node.completedTasks) 任务")
                    .font(SkirtMarketTheme.captionFont)
                    .foregroundStyle(.secondary)
                
                if let lastSeen = node.lastSeenAt {
                    Text(timeAgo(from: lastSeen))
                        .font(SkirtMarketTheme.captionFont)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "刚刚"
        } else if interval < 3600 {
            return "\(Int(interval / 60))分钟前"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))小时前"
        } else {
            return "\(Int(interval / 86400))天前"
        }
    }
}

// MARK: - 预览
#Preview {
    DressStockMarketView()
        .modelContainer(for: [LolitaMarketIndex.self, SkirtStockMetric.self, LolitaItem.self], inMemory: true)
}
