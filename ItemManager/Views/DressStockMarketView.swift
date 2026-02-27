//
//  DressStockMarketView.swift
//  ItemManager
//
//  裙子股市 - 主界面
//  莫妮卡粉主题 + 金融级数据可视化
//

import SwiftUI
import SwiftData
import Charts

// MARK: - 主视图
struct DressStockMarketView: View {
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - 查询
    @Query(sort: \LolitaMarketIndex.timestamp, order: .reverse) private var marketIndices: [LolitaMarketIndex]
    @Query(sort: \SkirtStockMetric.timestamp, order: .reverse) private var stockMetrics: [SkirtStockMetric]
    
    // MARK: - 状态
    @State private var selectedTab: MarketTab = .overview
    @State private var selectedSkirt: String?
    @State private var showingNodePanel = false
    @State private var onlineNodes: Int = 0
    
    // MARK: - 枚举
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
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 顶部导航
                    headerView
                    
                    // 标签页切换
                    tabSwitcher
                    
                    // 内容区域
                    TabView(selection: $selectedTab) {
                        MarketOverviewView(indices: marketIndices)
                            .tag(MarketTab.overview)
                        
                        SkirtListView(metrics: stockMetrics, selectedSkirt: $selectedSkirt)
                            .tag(MarketTab.skirts)
                        
                        NodeMonitorView()
                            .tag(MarketTab.nodes)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle("裙子股市")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(SkirtMarketTheme.riseGreen)
                            .frame(width: 8, height: 8)
                        Text("\(onlineNodes) 节点")
                            .font(SkirtMarketTheme.captionFont)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            updateOnlineNodes()
        }
    }
    
    // MARK: - 顶部视图
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("LO-指数")
                    .font(SkirtMarketTheme.captionFont)
                    .foregroundStyle(.secondary)
                
                if let latestIndex = marketIndices.first {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(String(format: "%.2f", latestIndex.indexValue))
                            .font(SkirtMarketTheme.indexFont)
                            .foregroundStyle(SkirtMarketTheme.primaryPink)
                        
                        HStack(spacing: 2) {
                            Image(systemName: latestIndex.changePercent >= 0 ? "arrow.up" : "arrow.down")
                            Text(String(format: "%.2f%%", abs(latestIndex.changePercent)))
                        }
                        .font(SkirtMarketTheme.subtitleFont)
                        .foregroundStyle(latestIndex.changePercent >= 0 ? SkirtMarketTheme.riseGreen : SkirtMarketTheme.fallRed)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (latestIndex.changePercent >= 0 ? SkirtMarketTheme.riseGreen : SkirtMarketTheme.fallRed)
                                .opacity(0.1)
                        )
                        .cornerRadius(6)
                    }
                } else {
                    Text("1,250.00")
                        .font(SkirtMarketTheme.indexFont)
                        .foregroundStyle(SkirtMarketTheme.primaryPink)
                }
            }
            
            Spacer()
            
            // 实时状态指示器
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    PulsingDot()
                    Text("实时")
                        .font(SkirtMarketTheme.captionFont)
                        .foregroundStyle(SkirtMarketTheme.primaryPink)
                }
                
                Text("\(stockMetrics.count) 条数据")
                    .font(SkirtMarketTheme.captionFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
    
    // MARK: - 标签切换器
    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(MarketTab.allCases, id: \.self) { tab in
                Button(action: { 
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18))
                        Text(tab.rawValue)
                            .font(SkirtMarketTheme.captionFont)
                    }
                    .foregroundStyle(selectedTab == tab ? SkirtMarketTheme.primaryPink : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selectedTab == tab ? SkirtMarketTheme.ultraLightPink : Color.clear
                    )
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    // MARK: - 更新在线节点数
    private func updateOnlineNodes() {
        // 从TaskDispatcher获取在线节点数
        onlineNodes = TaskDispatcher.shared.getOnlineNodeCount()
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
            HStack {
                Text("大盘走势")
                    .font(SkirtMarketTheme.subtitleFont)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("24H")
                    .font(SkirtMarketTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SkirtMarketTheme.ultraLightPink)
                    .cornerRadius(4)
            }
            
            if indices.count >= 2 {
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
            } else {
                // 占位图
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
        .skirtMarketCardStyle()
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
                ForEach(Array(groupedMetrics.values.sorted { $0.averagePrice > $1.averagePrice }), id: \.skirtName) { metric in
                    SkirtRow(metric: metric)
                        .onTapGesture {
                            selectedSkirt = metric.skirtName
                        }
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
            ZStack {
                Circle()
                    .fill(SkirtMarketTheme.ultraLightPink)
                    .frame(width: 48, height: 48)
                
                Image(systemName: "hanger")
                    .font(.system(size: 20))
                    .foregroundStyle(SkirtMarketTheme.primaryPink)
            }
            
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
        // 从TaskDispatcher获取节点信息
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
}
