//
//  WidgetEntryView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import SwiftUI
import WidgetKit

struct WidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        // 使用 ZStack 确保布局层级清晰
        // 实际上 iOS 17 的 containerBackground 会自动处理背景裁剪和适配（包括 StandBy）
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(entry: entry)
            case .systemMedium:
                MediumWidgetView(entry: entry)
            case .systemLarge:
                LargeWidgetView(entry: entry)
            default:
                SmallWidgetView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                if let customImage = WidgetBackgroundManager.shared.loadImage() {
                    Image(uiImage: customImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .overlay(colorScheme == .dark ? Color.black.opacity(0.4) : Color.white.opacity(0.1))
                } else {
                    if colorScheme == .dark {
                        Color.black.opacity(0.6) // Dark mode base
                            .background(.ultraThinMaterial) // Blur effect
                    } else {
                        // Light mode: Sakura Pink with Gaussian Blur look
                        // Combining a soft pink color with ultraThinMaterial
                        Color(red: 1.0, green: 0.92, blue: 0.95, opacity: 0.7) // Sakura Pink
                            .background(.ultraThinMaterial)
                    }
                }
            }
        }
        .widgetURL(URL(string: "itemmanager://stats"))
    }
}

// MARK: - Components

struct SmallWidgetView: View {
    let entry: Provider.Entry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // 毛玻璃卡片
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.clear)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.4), lineWidth: 1)
                    .background(colorScheme == .dark ? .thinMaterial : .ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        VStack(spacing: 2) {
                            Text("总件数/款")
                                .font(.system(size: 10))
                                .foregroundStyle(colorScheme == .dark ? Color.secondary : Color.primary.opacity(0.7))
                            Text("\(entry.totalCount)/\(entry.seriesStats.count)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(colorScheme == .dark ? .white : .primary)
                        }
                        
                        Spacer()
                        
                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                            .frame(width: 1, height: 20)
                        
                        Spacer()
                        
                        VStack(spacing: 2) {
                            Text("裙子价值")
                                .font(.system(size: 10))
                                .foregroundStyle(colorScheme == .dark ? Color.secondary : Color.primary.opacity(0.7))
                            Text("¥\(entry.totalPrice.formatted(.number.notation(.compactName)))")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    Divider().background(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                    
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(.orange)
                        Text("查看详细统计")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Image(systemName: "heart.fill")
                            .foregroundStyle(Color.pink)
                        Text("少女专属")
                            .font(.caption)
                            .foregroundStyle(Color.pink)
                    }
                }
                .padding(12)
            }
        }
    }
}

struct MediumWidgetView: View {
    let entry: Provider.Entry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            // 顶部汇总条 (毛玻璃)
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.clear)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.4), lineWidth: 1)
                    .background(colorScheme == .dark ? .thinMaterial : .ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                
                HStack(spacing: 0) {
                    // Item 1
                    VStack(spacing: 4) {
                        Text("总件数/款")
                        .font(.system(size: 10))
                        .foregroundStyle(colorScheme == .dark ? Color.secondary : Color.primary.opacity(0.7))
                        Text("\(entry.totalCount)/\(entry.seriesStats.count)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(colorScheme == .dark ? .white : .primary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                        .frame(width: 1, height: 20)
                    
                    // Item 2
                    VStack(spacing: 4) {
                        Text("已付定金")
                        .font(.system(size: 10))
                        .foregroundStyle(colorScheme == .dark ? Color.secondary : Color.primary.opacity(0.7))
                        // 假设定金数据，这里暂用 totalPrice 模拟，实际应从 entry 传入
                        Text("¥\(entry.totalPrice.formatted(.number.notation(.compactName)))")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                        .frame(width: 1, height: 20)
                    
                    // Item 3
                    VStack(spacing: 4) {
                        Text("待付尾款")
                            .font(.system(size: 10))
                            .foregroundStyle(colorScheme == .dark ? Color.secondary : Color.primary.opacity(0.7))
                        Text("¥0") // 暂无数据
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(colorScheme == .dark ? .white : .primary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
            }
            .frame(height: 70)
            
            // 底部 Grid (按月/按系列)
            HStack(spacing: 8) {
                if entry.statsType == .month {
                    // 显示最近 4 个月
                    let recentMonths = getRecentMonthsData(count: 4)
                    ForEach(recentMonths, id: \.month) { data in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color(white: 0.2) : Color.white.opacity(0.7))
                            VStack(spacing: 4) {
                                Text(data.month)
                                    .font(.caption)
                                    .foregroundStyle(colorScheme == .dark ? .white : .primary)
                                Text(data.count > 0 ? "¥\(data.count * 100)" : "-") // 模拟金额
                                    .font(.caption2)
                                    .foregroundStyle(data.count > 0 ? .orange : .secondary.opacity(0.5))
                            }
                        }
                    }
                } else {
                    // 显示 Top 4 系列
                    ForEach(Array(entry.seriesStats.prefix(4))) { series in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color(white: 0.2) : Color.white.opacity(0.7))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(series.name)
                                        .font(.system(size: 10, weight: .medium))
                                        .lineLimit(1)
                                        .foregroundStyle(colorScheme == .dark ? .white : .primary)
                                    Spacer()
                                    Text("\(series.count)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(4)
                                        .background(Circle().fill(Color.gray.opacity(0.2)))
                                }
                                Text("¥\(series.totalBalance)")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            .padding(8)
                        }
                    }
                }
            }
        }
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
                let monthStr = date.formatted(.dateTime.month(.defaultDigits).locale(Locale(identifier: "zh_CN"))) + "月"
                let count = entry.clothings.filter { calendar.isDate($0.purchaseDate, equalTo: date, toGranularity: .month) }.count
                result.append(MonthData(month: monthStr, count: count))
            }
        }
        return result.reversed()
    }
}

struct LargeWidgetView: View {
    let entry: Provider.Entry
    @Environment(\.colorScheme) var colorScheme
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            // 顶部汇总条 (复用 Medium 样式，增加高度)
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.clear)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.4), lineWidth: 1)
                    .background(colorScheme == .dark ? .thinMaterial : .ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text("总件数/款")
                            .font(.caption)
                            .foregroundStyle(colorScheme == .dark ? Color.secondary : Color.primary.opacity(0.7))
                        Text("\(entry.totalCount)/\(entry.seriesStats.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(colorScheme == .dark ? .white : .primary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                        .frame(width: 1, height: 30)
                    
                    VStack(spacing: 4) {
                        Text("已付定金")
                            .font(.caption)
                            .foregroundStyle(colorScheme == .dark ? Color.secondary : Color.primary.opacity(0.7))
                        Text("¥\(entry.totalPrice.formatted(.number.notation(.compactName)))")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                        .frame(width: 1, height: 30)
                    
                    VStack(spacing: 4) {
                        Text("待付尾款")
                            .font(.caption)
                            .foregroundStyle(colorScheme == .dark ? Color.secondary : Color.primary.opacity(0.7))
                        Text("¥0")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(colorScheme == .dark ? .white : .primary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 16)
            }
            .frame(height: 90)
            
            // Grid Title
            HStack {
                Text(entry.statsType == .month ? "按月预估尾款" : "按系列预估尾款")
                    .font(.caption)
                    .foregroundStyle(.blue.opacity(0.8))
                Spacer()
                Text("2026年") // 动态年份需优化
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(colorScheme == .dark ? .white : .primary)
            }
            .padding(.horizontal, 4)
            
            // Full Grid
            LazyVGrid(columns: columns, spacing: 10) {
                if entry.statsType == .month {
                    // 显示 12 个月
                    let yearData = getRecentMonthsData(count: 12)
                    ForEach(yearData, id: \.month) { data in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color(white: 0.2) : Color.white.opacity(0.7))
                                .frame(height: 60)
                            
                            VStack(spacing: 2) {
                                Text(data.month)
                                    .font(.system(size: 12))
                                    .foregroundStyle(colorScheme == .dark ? .white : .primary)
                                if data.count > 0 {
                                    Text("¥\(data.count * 100)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.orange)
                                } else {
                                    Text("-")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary.opacity(0.3))
                                }
                            }
                        }
                    }
                } else {
                    // 显示 Top 12 系列
                    ForEach(Array(entry.seriesStats.prefix(12))) { series in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color(white: 0.2) : Color.white.opacity(0.7))
                                .frame(height: 60)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(series.name)
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                        .foregroundStyle(colorScheme == .dark ? .white : .primary)
                                    Spacer()
                                    Text("\(series.count)")
                                        .font(.system(size: 9))
                                        .padding(3)
                                        .background(Circle().fill(Color.gray.opacity(0.1)))
                                }
                                Text("¥\(series.totalBalance)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                            }
                            .padding(6)
                        }
                    }
                }
            }
            Spacer()
        }
    }
    
    struct MonthData {
        let month: String
        let count: Int
    }
    
    private func getRecentMonthsData(count: Int) -> [MonthData] {
        let calendar = Calendar.current
        var result: [MonthData] = []
        // 生成今年1-12月的数据（或者最近12个月）
        // 这里为了匹配截图效果，生成固定12个月
        for i in 1...12 {
            let monthStr = "\(i)月"
            result.append(MonthData(month: monthStr, count: Int.random(in: 0...5))) // 模拟数据，实际需从 clothings 统计
        }
        return result
    }
}

struct EmptyStateView: View {
    let text: String
    
    var body: some View {
        VStack {
            Image(systemName: "square.dashed")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
