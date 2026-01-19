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
            // 自适应背景色
            if colorScheme == .dark {
                Color(red: 0.2, green: 0.15, blue: 0.15) // Dark Brownish
            } else {
                switch family {
                case .systemMedium:
                    Color(red: 1.0, green: 0.98, blue: 0.90) // Cream for Medium
                default:
                    Color(red: 1.0, green: 0.95, blue: 0.95) // Light Pink for others
                }
            }
        }
        // 添加全局跳转链接，点击整个 Widget 打开 App
        // 可以在具体 View 内部用 Link 覆盖
        .widgetURL(URL(string: "itemmanager://stats"))
    }
}

// MARK: - Components

struct SmallWidgetView: View {
    let entry: Provider.Entry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.pink)
                Text("心愿概览")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Date().formatted(.dateTime.day()))
                    .font(.caption2)
                    .padding(4)
                    .background(Circle().fill(Color.pink.opacity(0.1)))
            }
            .padding(.bottom, 8)
            
            // Main Content
            if entry.statsType == .month {
                let currentMonthCount = countForCurrentMonth()
                HStack(alignment: .lastTextBaseline) {
                    Text("\(currentMonthCount)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(colorScheme == .dark ? Color(red: 0.9, green: 0.8, blue: 0.7) : Color(red: 0.6, green: 0.4, blue: 0.2))
                    Text("件本月")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
                
                Spacer()
                
                // Footer Info
                HStack {
                    VStack(alignment: .leading) {
                        Text("总收藏")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Text("\(entry.totalCount)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("总价值")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Text("¥\(entry.totalPrice.formatted(.number.notation(.compactName)))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                }
            } else {
                if let topSeries = entry.seriesStats.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(topSeries.name)
                            .font(.headline)
                            .lineLimit(2)
                            .foregroundStyle(colorScheme == .dark ? .white : .primary)
                        
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.yellow)
                            Text("Top 1")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    HStack {
                        Text("\(topSeries.count)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.pink)
                        Text("件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                    }
                } else {
                    EmptyStateView(text: "暂无系列")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func countForCurrentMonth() -> Int {
        let calendar = Calendar.current
        let now = Date()
        return entry.clothings.filter { calendar.isDate($0.purchaseDate, equalTo: now, toGranularity: .month) }.count
    }
}

struct MediumWidgetView: View {
    let entry: Provider.Entry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 0) {
            // Left: Recent Item Highlight
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.pink)
                    Text("最近入手")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let recent = entry.recentClothings.first {
                    VStack(alignment: .leading, spacing: 4) {
                        // Placeholder for Image or Icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.pink.opacity(0.1))
                                .frame(width: 40, height: 40)
                            Image(systemName: "tshirt.fill")
                                .foregroundStyle(.pink.opacity(0.6))
                        }
                        
                        Text(recent.name)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(2)
                            .foregroundStyle(colorScheme == .dark ? .white : .primary)
                        
                        Text(recent.purchaseDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("暂无记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 12)
            
            Divider()
                .padding(.vertical)
            
            // Right: Statistics
            VStack(alignment: .leading, spacing: 0) {
                if entry.statsType == .month {
                    Text("近三月趋势")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                        .padding(.leading, 12)
                    
                    let recentMonths = getRecentMonthsData(count: 3)
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(recentMonths, id: \.month) { data in
                            VStack {
                                Spacer()
                                // Simple Bar
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(data.count > 0 ? Color.pink.opacity(0.6) : Color.gray.opacity(0.2))
                                    .frame(width: 16, height: CGFloat(max(4, min(data.count * 5, 50))))
                                
                                Text("\(data.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text(data.month.replacingOccurrences(of: "月", with: ""))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: 80)
                    .padding(.leading, 12)
                } else {
                    // Series List
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(entry.seriesStats.prefix(3))) { series in
                            HStack {
                                Circle()
                                    .fill(Color.pink.opacity(0.3))
                                    .frame(width: 6, height: 6)
                                Text(series.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(series.count)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.pink)
                            }
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.top, 8)
                }
                Spacer()
            }
            .frame(width: 140)
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
        VStack(spacing: 16) {
            // Top Section: Dashboard
            HStack(spacing: 16) {
                // Total Count Box
                VStack(alignment: .leading) {
                    Text("总收藏")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(entry.totalCount)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.pink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.pink.opacity(0.05)))
                
                // Total Price Box
                VStack(alignment: .leading) {
                    Text("总投入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("¥\(entry.totalPrice.formatted(.number.notation(.compactName)))")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.6, green: 0.4, blue: 0.2))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.orange.opacity(0.05)))
            }
            
            Divider()
            
            // Bottom Section: Recent Items List
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .foregroundStyle(.pink)
                    Text("最新入库")
                        .font(.headline)
                        .foregroundStyle(colorScheme == .dark ? .white : .black.opacity(0.8))
                    Spacer()
                }
                
                if entry.recentClothings.isEmpty {
                    Text("暂无记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(entry.recentClothings.prefix(4))) { item in
                            HStack {
                                // Status Dot
                                Circle()
                                    .fill(item.status == .onShelf ? Color.green : Color.gray)
                                    .frame(width: 6, height: 6)
                                
                                Text(item.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text("¥\(item.price.formatted())")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.gray.opacity(0.05)))
                        }
                    }
                }
            }
            
            Spacer()
        }
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
