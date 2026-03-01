//
//  SkirtDetailView.swift
//  裙子股市 - 萌款详情视图
//
//  展示单个裙子的详细股市数据和K线图
//

import SwiftUI
import SwiftData
import Charts

// MARK: - 萌款详情视图
struct SkirtDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - 参数
    let skirtName: String
    
    // MARK: - 查询
    @Query private var metrics: [SkirtStockMetric]
    @Query private var items: [LolitaItem]
    
    // MARK: - 状态
    @State private var selectedTimeRange: TimeRange = .week
    @State private var showingAIAnalysis = false
    
    // MARK: - 时间范围枚举
    enum TimeRange: String, CaseIterable {
        case day = "日K"
        case week = "周K"
        case month = "月K"
        
        var days: Int {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            }
        }
    }
    
    // MARK: - 初始化
    init(skirtName: String) {
        self.skirtName = skirtName
        
        // 配置查询 - 该裙子的历史数据
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let name = skirtName
        
        _metrics = Query(
            filter: #Predicate { metric in
                metric.skirtName == name && metric.timestamp > startDate
            },
            sort: \.timestamp,
            order: .forward
        )
        
        // 查询当前在售的商品
        _items = Query(
            filter: #Predicate { item in
                item.cleanedName == name && item.isDeleted == false
            },
            sort: \.currentPrice,
            order: .forward
        )
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SkirtMarketTheme.standardSpacing) {
                    // 价格概览卡片
                    DetailPriceOverviewCard(metrics: metrics, skirtName: skirtName)
                    
                    // K线图
                    DetailKLineChartCard(
                        metrics: filteredMetrics,
                        timeRange: selectedTimeRange
                    )
                    
                    // 时间范围选择器
                    DetailTimeRangeSelector(selection: $selectedTimeRange)
                    
                    // 市场统计
                    MarketDetailStatsCard(metrics: latestMetric, items: items)
                    
                    // AI投资建议
                    DetailAIAnalysisCard(metric: latestMetric)
                    
                    // 在售商品列表
                    ActiveListingsCard(items: items)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle(skirtName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundStyle(SkirtMarketTheme.primaryPink)
                }
            }
            .background(SkirtMarketTheme.laceWhite.ignoresSafeArea())
        }
    }
    
    // MARK: - 计算属性
    
    /// 根据时间范围过滤的数据
    private var filteredMetrics: [SkirtStockMetric] {
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -selectedTimeRange.days,
            to: Date()
        ) ?? Date()
        
        return metrics.filter { $0.timestamp >= cutoffDate }
    }
    
    /// 最新指标
    private var latestMetric: SkirtStockMetric? {
        metrics.last
    }
}

// MARK: - 价格概览卡片
struct DetailPriceOverviewCard: View {
    let metrics: [SkirtStockMetric]
    let skirtName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(skirtName)
                    .font(SkirtMarketTheme.titleFont)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // 实时标签
                HStack(spacing: 4) {
                    PulsingDot()
                    Text("实时")
                        .font(SkirtMarketTheme.captionFont)
                }
                .foregroundStyle(SkirtMarketTheme.primaryPink)
            }
            
            if let latest = metrics.last {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text("¥\(String(format: "%.0f", latest.averagePrice))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    // 涨跌幅
                    let change = calculateChange()
                    HStack(spacing: 2) {
                        Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                        Text("\(String(format: "%.2f", abs(change)))%")
                    }
                    .font(SkirtMarketTheme.subtitleFont)
                    .foregroundStyle(change >= 0 ? SkirtMarketTheme.riseGreen : SkirtMarketTheme.fallRed)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (change >= 0 ? SkirtMarketTheme.riseGreen : SkirtMarketTheme.fallRed)
                            .opacity(0.1)
                    )
                    .cornerRadius(6)
                }
                
                // 价格区间
                HStack(spacing: 16) {
                    DetailPriceRangeItem(title: "最高", value: latest.highPrice, color: SkirtMarketTheme.riseGreen)
                    DetailPriceRangeItem(title: "最低", value: latest.lowPrice, color: SkirtMarketTheme.fallRed)
                    DetailPriceRangeItem(title: "中位数", value: latest.medianPrice ?? latest.averagePrice, color: SkirtMarketTheme.primaryPink)
                }
            } else {
                // 无数据占位
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 40))
                        .foregroundStyle(SkirtMarketTheme.primaryPink.opacity(0.5))
                    Text("暂无数据")
                        .font(SkirtMarketTheme.bodyFont)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
        .skirtMarketCardStyle()
    }
    
    /// 计算涨跌幅
    private func calculateChange() -> Double {
        guard metrics.count >= 2,
              let latest = metrics.last,
              let previous = metrics.dropLast().last else {
            return 0
        }
        
        guard previous.averagePrice > 0 else { return 0 }
        return ((latest.averagePrice - previous.averagePrice) / previous.averagePrice) * 100
    }
}

// MARK: - 价格区间项
struct DetailPriceRangeItem: View {
    let title: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SkirtMarketTheme.captionFont)
                .foregroundStyle(.secondary)
            
            Text("¥\(String(format: "%.0f", value))")
                .font(SkirtMarketTheme.subtitleFont)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - K线图卡片
struct DetailKLineChartCard: View {
    let metrics: [SkirtStockMetric]
    let timeRange: SkirtDetailView.TimeRange
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("价格走势")
                    .font(SkirtMarketTheme.subtitleFont)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(timeRange.rawValue)
                    .font(SkirtMarketTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SkirtMarketTheme.ultraLightPink)
                    .cornerRadius(4)
            }
            
            if metrics.count >= 2 {
                Chart(metrics) { metric in
                    // K线蜡烛图（使用LineMark兼容所有iOS版本）
                    CandleStickMark(
                        timestamp: metric.timestamp,
                        high: metric.highPrice,
                        low: metric.lowPrice,
                        open: metric.openPrice ?? metric.averagePrice,
                        close: metric.closePrice ?? metric.averagePrice
                    )
                }
                .frame(height: 200)
                .chartYScale(domain: .automatic(includesZero: false))
            } else {
                // 占位图
                RoundedRectangle(cornerRadius: 8)
                    .fill(SkirtMarketTheme.ultraLightPink)
                    .frame(height: 200)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "chart.candlestick")
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

// MARK: - 时间范围选择器
struct DetailTimeRangeSelector: View {
    @Binding var selection: SkirtDetailView.TimeRange
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(SkirtDetailView.TimeRange.allCases, id: \.self) { range in
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        selection = range
                    }
                }) {
                    Text(range.rawValue)
                        .font(SkirtMarketTheme.subtitleFont)
                        .foregroundStyle(selection == range ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selection == range ? SkirtMarketTheme.primaryPink : SkirtMarketTheme.ultraLightPink
                        )
                        .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - 市场详细统计卡片
struct MarketDetailStatsCard: View {
    let metrics: SkirtStockMetric?
    let items: [LolitaItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("市场统计")
                .font(SkirtMarketTheme.subtitleFont)
                .foregroundStyle(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                DetailStatBox(
                    title: "挂牌数量",
                    value: "\(metrics?.listingCount ?? 0)",
                    icon: "doc.text",
                    color: SkirtMarketTheme.primaryPink
                )
                
                DetailStatBox(
                    title: "市场热度",
                    value: String(format: "%.0f%%", (metrics?.marketHeat ?? 0) * 100),
                    icon: "flame.fill",
                    color: SkirtMarketTheme.gold
                )
                
                DetailStatBox(
                    title: "情绪指数",
                    value: String(format: "%.2f", metrics?.sentimentScore ?? 0),
                    icon: "face.smiling",
                    color: SkirtMarketTheme.mintGreen
                )
                
                DetailStatBox(
                    title: "价格振幅",
                    value: String(format: "%.1f%%", (metrics?.priceAmplitude ?? 0) * 100),
                    icon: "arrow.up.arrow.down",
                    color: SkirtMarketTheme.deepPink
                )
            }
            
            // 平台分布
            if let metric = metrics {
                PlatformDistributionView(metric: metric)
            }
        }
        .skirtMarketCardStyle()
    }
}

// MARK: - 详情页统计盒子
struct DetailStatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
            
            Text(title)
                .font(SkirtMarketTheme.captionFont)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(SkirtMarketTheme.ultraLightPink)
        .cornerRadius(8)
    }
}

// MARK: - 平台分布视图
struct PlatformDistributionView: View {
    let metric: SkirtStockMetric
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("平台分布")
                .font(SkirtMarketTheme.captionFont)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                DetailPlatformBadge(name: "闲鱼", count: metric.xianyuCount, color: .yellow)
                DetailPlatformBadge(name: "小红书", count: metric.xiaohongshuCount, color: .red)
                DetailPlatformBadge(name: "淘宝", count: metric.taobaoCount, color: .orange)
                DetailPlatformBadge(name: "微店", count: metric.weidianCount, color: .green)
            }
        }
    }
}

// MARK: - 平台徽章
struct DetailPlatformBadge: View {
    let name: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text("\(name) \(count)")
                .font(SkirtMarketTheme.captionFont)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(4)
    }
}

// MARK: - AI分析卡片
struct DetailAIAnalysisCard: View {
    let metric: SkirtStockMetric?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(SkirtMarketTheme.primaryPink)
                
                Text("AI 投资建议")
                    .font(SkirtMarketTheme.subtitleFont)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if let suggestion = metric?.investmentSuggestion {
                    Text(suggestion.rawValue)
                        .font(SkirtMarketTheme.captionFont)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: suggestion.color))
                        .cornerRadius(12)
                }
            }
            
            // AI分析内容
            if let metric = metric {
                VStack(alignment: .leading, spacing: 8) {
                    DetailAnalysisRow(
                        title: "好价比例",
                        value: String(format: "%.0f%%", (metric.bargainRatio ?? 0) * 100),
                        progress: metric.bargainRatio ?? 0
                    )
                    
                    DetailAnalysisRow(
                        title: "急出比例",
                        value: String(format: "%.0f%%", (metric.urgentSaleRatio ?? 0) * 100),
                        progress: metric.urgentSaleRatio ?? 0
                    )
                    
                    DetailAnalysisRow(
                        title: "溢价比例",
                        value: String(format: "%.0f%%", (metric.premiumRatio ?? 0) * 100),
                        progress: metric.premiumRatio ?? 0
                    )
                }
            } else {
                Text("暂无AI分析数据")
                    .font(SkirtMarketTheme.bodyFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .skirtMarketCardStyle()
    }
}

// MARK: - 分析行
struct DetailAnalysisRow: View {
    let title: String
    let value: String
    let progress: Double
    
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(SkirtMarketTheme.bodyFont)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SkirtMarketTheme.ultraLightPink)
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: geometry.size.width * CGFloat(min(max(progress, 0), 1)), height: 8)
                }
            }
            .frame(height: 8)
            
            Text(value)
                .font(SkirtMarketTheme.captionFont)
                .foregroundStyle(.primary)
                .frame(width: 50, alignment: .trailing)
        }
    }
    
    var progressColor: Color {
        if progress < 0.3 {
            return SkirtMarketTheme.mintGreen
        } else if progress < 0.7 {
            return SkirtMarketTheme.gold
        } else {
            return SkirtMarketTheme.primaryPink
        }
    }
}

// MARK: - 在售商品卡片
struct ActiveListingsCard: View {
    let items: [LolitaItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("在售商品 (\(items.count))")
                    .font(SkirtMarketTheme.subtitleFont)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if items.count > 5 {
                    Text("查看全部")
                        .font(SkirtMarketTheme.captionFont)
                        .foregroundStyle(SkirtMarketTheme.primaryPink)
                }
            }
            
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "hanger")
                        .font(.system(size: 40))
                        .foregroundStyle(SkirtMarketTheme.primaryPink.opacity(0.5))
                    
                    Text("暂无在售商品")
                        .font(SkirtMarketTheme.bodyFont)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 8) {
                    ForEach(items.prefix(5), id: \.platformID) { item in
                        DetailListingRow(item: item)
                        
                        if item.platformID != items.prefix(5).last?.platformID {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
            }
        }
        .skirtMarketCardStyle()
    }
}

// MARK: - 商品行
struct DetailListingRow: View {
    let item: LolitaItem
    
    var body: some View {
        HStack(spacing: 12) {
            // 平台图标
            PlatformIcon(platform: item.platform)
            
            // 商品信息
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(SkirtMarketTheme.bodyFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let condition = item.condition {
                        Text(condition)
                            .font(SkirtMarketTheme.captionFont)
                            .foregroundStyle(.secondary)
                    }
                    
                    if item.hasTags == true {
                        Label("有吊牌", systemImage: "tag.fill")
                            .font(SkirtMarketTheme.captionFont)
                            .foregroundStyle(SkirtMarketTheme.gold)
                    }
                }
            }
            
            Spacer()
            
            // 价格
            VStack(alignment: .trailing, spacing: 4) {
                Text("¥\(String(format: "%.0f", item.currentPrice))")
                    .font(SkirtMarketTheme.subtitleFont)
                    .foregroundStyle(priceColor)
                
                // 价格趋势标签
                PriceTrendBadge(trend: item.priceTrend)
            }
        }
        .padding(.vertical, 4)
    }
    
    var priceColor: Color {
        switch item.priceTrend {
        case .bargain:
            return SkirtMarketTheme.riseGreen
        case .premium:
            return SkirtMarketTheme.fallRed
        default:
            return .primary
        }
    }
}

// MARK: - 平台图标
struct PlatformIcon: View {
    let platform: PlatformType
    
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor.opacity(0.2))
                .frame(width: 40, height: 40)
            
            Text(iconText)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(backgroundColor)
        }
    }
    
    var iconText: String {
        switch platform {
        case .xianyu: return "闲"
        case .xiaohongshu: return "红"
        case .taobao: return "淘"
        case .weidian: return "微"
        case .other: return "?"
        }
    }
    
    var backgroundColor: Color {
        switch platform {
        case .xianyu: return .yellow
        case .xiaohongshu: return .red
        case .taobao: return .orange
        case .weidian: return .green
        case .other: return .gray
        }
    }
}

// MARK: - 价格趋势徽章
struct PriceTrendBadge: View {
    let trend: PriceTrend
    
    var body: some View {
        Text(trend.rawValue)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .cornerRadius(4)
    }
    
    var color: Color {
        switch trend {
        case .bargain: return SkirtMarketTheme.riseGreen
        case .fair: return SkirtMarketTheme.gold
        case .premium: return SkirtMarketTheme.fallRed
        case .unknown: return .gray
        }
    }
}

// MARK: - 蜡烛图标记（简化版）
// 使用简单的 LineMark 实现，兼容所有 iOS 版本
struct CandleStickMark: ChartContent {
    let timestamp: Date
    let high: Double
    let low: Double
    let open: Double
    let close: Double
    
    var body: some ChartContent {
        // 使用LineMark模拟K线，兼容所有iOS版本
        LineMark(
            x: .value("时间", timestamp),
            y: .value("最高", high)
        )
        .foregroundStyle(close >= open ? Color.green : Color.red)
        .lineStyle(StrokeStyle(lineWidth: 2))
    }
}

// MARK: - 预览
#Preview {
    SkirtDetailView(skirtName: "AP 辉夜姬")
        .modelContainer(for: [SkirtStockMetric.self, LolitaItem.self], inMemory: true)
}
