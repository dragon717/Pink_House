import SwiftUI
import SwiftData

enum WidgetSize: String, CaseIterable, Identifiable {
    case small = "小"
    case medium = "中"
    case large = "大"
    
    var id: String { self.rawValue }
}

enum StatsType: String, CaseIterable, Identifiable {
    case month = "按月份"
    case series = "按系列"
    
    var id: String { self.rawValue }
}

struct WidgetSettingsView: View {
    @Query(sort: \Clothing.purchaseDate, order: .reverse) private var clothings: [Clothing]
    
    @AppStorage("widgetSize") private var selectedSize: WidgetSize = .small
    @AppStorage("widgetStatsType") private var selectedStatsType: StatsType = .month
    @State private var seriesStats: [SeriesInfo] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. 尺寸选择
                Picker("尺寸", selection: $selectedSize) {
                    ForEach(WidgetSize.allCases) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // 2. 预览区域
                VStack(alignment: .leading, spacing: 8) {
                    Text("预览")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ZStack {
                        Color(.systemGroupedBackground)
                            .cornerRadius(12)
                        
                        // 根据尺寸显示不同的预览
                        Group {
                            switch selectedSize {
                            case .small:
                                SmallWidgetPreview(statsType: selectedStatsType, clothings: clothings, seriesStats: seriesStats)
                                    .frame(width: 155, height: 155)
                            case .medium:
                                MediumWidgetPreview(statsType: selectedStatsType, clothings: clothings, seriesStats: seriesStats)
                                    .frame(width: 329, height: 155)
                            case .large:
                                LargeWidgetPreview(statsType: selectedStatsType, clothings: clothings, seriesStats: seriesStats)
                                    .frame(width: 329, height: 345)
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .padding()
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1.2, contentMode: .fit) // 保持一个大致的比例
                }
                
                // 3. 统计设置
                VStack(alignment: .leading, spacing: 8) {
                    Text("统计设置")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    List {
                        Section {
                            Picker("统计方式", selection: $selectedStatsType) {
                                ForEach(StatsType.allCases) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                        } footer: {
                            Text(selectedStatsType == .month ? "统计每个月购买的服装数量和金额" : "自动分析服装名称前缀，统计各系列的收集情况")
                        }
                    }
                    .frame(height: 200) // 限制 List 高度
                    .scrollDisabled(true)
                }
                
                Spacer()
            }
            .padding(.vertical)
        }
        .navigationTitle("小组件设置")
        .background(Color(.systemGroupedBackground))
        .task {
            // 加载系列统计数据
            await loadSeriesData()
        }
        .onChange(of: clothings) {
            Task { await loadSeriesData() }
        }
    }
    
    private func loadSeriesData() async {
        self.seriesStats = await SeriesAnalyzer.shared.analyzeSeries(from: clothings)
    }
}

// MARK: - Widget Views

struct SmallWidgetPreview: View {
    let statsType: StatsType
    let clothings: [Clothing]
    let seriesStats: [SeriesInfo]
    
    var body: some View {
        VStack {
            if statsType == .month {
                let currentMonthCount = countForCurrentMonth()
                Text("\(currentMonthCount)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.brown)
                Text("本月新增")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if let topSeries = seriesStats.first {
                    Text("\(topSeries.count)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.pink)
                    Text(topSeries.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("0")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray)
                    Text("无系列数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
    
    private func countForCurrentMonth() -> Int {
        let calendar = Calendar.current
        let now = Date()
        return clothings.filter { calendar.isDate($0.purchaseDate, equalTo: now, toGranularity: .month) }.count
    }
}

struct MediumWidgetPreview: View {
    let statsType: StatsType
    let clothings: [Clothing]
    let seriesStats: [SeriesInfo]
    
    var body: some View {
        HStack {
            if statsType == .month {
                // 显示最近3个月的数据
                let recentMonths = getRecentMonthsData(count: 3)
                ForEach(recentMonths, id: \.month) { data in
                    VStack {
                        Text("\(data.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.brown)
                        Text(data.month)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                // 显示 Top 3 系列
                let topSeries = Array(seriesStats.prefix(3))
                if topSeries.isEmpty {
                     Text("暂无系列数据")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(topSeries) { series in
                        VStack {
                            Text("\(series.count)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.pink)
                            Text(series.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding()
    }
    
    struct MonthData {
        let month: String
        let count: Int
    }
    
    private func getRecentMonthsData(count: Int) -> [MonthData] {
        let calendar = Calendar.current
        var result: [MonthData] = []
        
        // 简单实现：取最近 N 个月
        for i in 0..<count {
            if let date = calendar.date(byAdding: .month, value: -i, to: Date()) {
                let monthStr = date.formatted(.dateTime.month().locale(Locale(identifier: "zh_CN")))
                let count = clothings.filter { calendar.isDate($0.purchaseDate, equalTo: date, toGranularity: .month) }.count
                result.append(MonthData(month: monthStr, count: count))
            }
        }
        return result.reversed() // 从左到右按时间顺序
    }
}

struct LargeWidgetPreview: View {
    let statsType: StatsType
    let clothings: [Clothing]
    let seriesStats: [SeriesInfo]
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(statsType == .month ? "年度概览" : "系列收藏")
                .font(.headline)
                .padding(.bottom, 8)
            
            LazyVGrid(columns: columns, spacing: 12) {
                if statsType == .month {
                    // 显示最近 12 个月的数据方块
                    let yearData = getRecentMonthsData(count: 12)
                    ForEach(yearData, id: \.month) { data in
                        VStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(data.count > 0 ? Color.brown.opacity(Double(data.count) * 0.2 + 0.1) : Color.gray.opacity(0.1))
                                    .aspectRatio(1, contentMode: .fit)
                                
                                if data.count > 0 {
                                    Text("\(data.count)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                }
                            }
                            Text(data.month)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    // 显示 Top 12 系列方块
                    let topSeries = Array(seriesStats.prefix(12))
                    if topSeries.isEmpty {
                        Text("暂无数据")
                            .gridCellColumns(4)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(topSeries) { series in
                            VStack {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.pink.opacity(0.15))
                                        .aspectRatio(1, contentMode: .fit)
                                    
                                    Text("\(series.count)")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.pink)
                                }
                                Text(series.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
    
    struct MonthData {
        let month: String
        let count: Int
    }
    
    private func getRecentMonthsData(count: Int) -> [MonthData] {
        let calendar = Calendar.current
        var result: [MonthData] = []
        
        for i in 0..<count {
            if let date = calendar.date(byAdding: .month, value: -i, to: Date()) {
                // 使用短月份名，如 "1月"
                let monthStr = date.formatted(.dateTime.month(.defaultDigits).locale(Locale(identifier: "zh_CN"))) + "月"
                let count = clothings.filter { calendar.isDate($0.purchaseDate, equalTo: date, toGranularity: .month) }.count
                result.append(MonthData(month: monthStr, count: count))
            }
        }
        return result.reversed()
    }
}

#Preview {
    WidgetSettingsView()
}
