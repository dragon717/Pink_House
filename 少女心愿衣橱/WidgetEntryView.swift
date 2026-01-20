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
                        // Dark mode: Slightly Dimmed Sakura Pink
                        // Use the same pink base but overlay a very light black to dim it just enough
                        // without losing the pink hue.
                        ZStack {
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.96, blue: 0.96),
                                    Color(red: 1.0, green: 0.92, blue: 0.94)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Color.black.opacity(0.2) // 20% dimming
                        }
                    } else {
                        // Light mode: Default Sakura Pink Gradient
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.96, blue: 0.96),
                                Color(red: 1.0, green: 0.92, blue: 0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
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
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.3 : 0.6), lineWidth: 1)
                    .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        VStack(spacing: 2) {
                            Text("总件数/款")
                                .font(.system(size: 10))
                                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.9) : Color.primary.opacity(0.8))
                                .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0)
                            Text("\(entry.totalCount)/\(entry.totalStyleCount)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(colorScheme == .dark ? .white : .primary)
                                .shadow(color: .white.opacity(0.5), radius: 2, x: 0, y: 0)
                        }
                        
                        Spacer()
                        
                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.2))
                            .frame(width: 1, height: 20)
                        
                        Spacer()
                        
                        VStack(spacing: 2) {
                            Text("裙子价值")
                                .font(.system(size: 10))
                                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.9) : Color.primary.opacity(0.8))
                                .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0)
                            Text("¥\(entry.totalPrice.formatted(.number.notation(.compactName)))")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0)
                        }
                    }
                    
                    Divider().background(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.2))
                    
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(.orange)
                            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0)
                        Text("查看详细统计")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0)
                        Spacer()
                        // Debug Time
                        Text(entry.date, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.8))
                            .shadow(color: .white.opacity(0.5), radius: 1, x: 0, y: 0)
                        Image(systemName: "heart.fill")
                            .foregroundStyle(Color.pink)
                            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0)
                        Text("少女专属")
                            .font(.caption)
                            .foregroundStyle(Color.pink)
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0)
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
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.3 : 0.6), lineWidth: 1)
                    .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                
                HStack(spacing: 0) {
                    // Item 1
                    VStack(spacing: 4) {
                        Text("总件数/款")
                        .font(.system(size: 10))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.9) : Color.primary.opacity(0.8))
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0)
                        Text("\(entry.depositCount)/\(entry.depositStyleCount)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(colorScheme == .dark ? .white : .primary)
                            .shadow(color: .white.opacity(0.5), radius: 2, x: 0, y: 0)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.2))
                        .frame(width: 1, height: 20)
                    
                    // Item 2
                    VStack(spacing: 4) {
                        Text("已付定金")
                        .font(.system(size: 10))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.9) : Color.primary.opacity(0.8))
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0)
                        Text("¥\(entry.totalDeposit.formatted(.number.notation(.compactName)))")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.2))
                        .frame(width: 1, height: 20)
                    
                    // Item 3
                    VStack(spacing: 4) {
                        Text("待付尾款")
                            .font(.system(size: 10))
                            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.9) : Color.primary.opacity(0.8))
                            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0)
                        Text("¥\(entry.totalBalance.formatted(.number.notation(.compactName)))")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(colorScheme == .dark ? .white : .primary)
                            .shadow(color: .white.opacity(0.5), radius: 2, x: 0, y: 0)
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
                    ForEach(recentMonths, id: \.id) { data in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color(white: 0.2).opacity(0.6) : Color.white.opacity(0.4))
                                .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                            VStack(spacing: 4) {
                                Text("\(data.month)月")
                                    .font(.caption)
                                    .foregroundStyle(colorScheme == .dark ? .white : .primary)
                                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0)
                                Text(data.totalBalance > 0 ? "¥\(data.totalBalance.formatted(.number.notation(.compactName)))" : "-")
                                    .font(.caption2)
                                    .foregroundStyle(data.totalBalance > 0 ? .orange : .secondary.opacity(0.8))
                                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0)
                            }
                        }
                    }
                } else {
                    // 显示 Top 4 系列
                    ForEach(Array(entry.seriesStats.prefix(4))) { series in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.4))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(series.name)
                                        .font(.system(size: 10, weight: .medium))
                                        .lineLimit(1)
                                        .foregroundStyle(colorScheme == .dark ? .white : .primary)
                                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0)
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
                                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0)
                            }
                            .padding(8)
                        }
                    }
                }
            }
        }
    }
    
    private func getRecentMonthsData(count: Int) -> [WidgetMonthInfo] {
        return Array(entry.monthStats.prefix(count))
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
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.3 : 0.6), lineWidth: 1)
                    .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text("总件数/款")
                            .font(.caption)
                            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.9) : Color.primary.opacity(0.8))
                            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0)
                        Text("\(entry.depositCount)/\(entry.depositStyleCount)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(colorScheme == .dark ? .white : .primary)
                            .shadow(color: .white.opacity(0.5), radius: 2, x: 0, y: 0)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.2))
                        .frame(width: 1, height: 30)
                    
                    VStack(spacing: 4) {
                        Text("已付定金")
                            .font(.caption)
                            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.9) : Color.primary.opacity(0.8))
                            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0)
                        Text("¥\(entry.totalDeposit.formatted(.number.notation(.compactName)))")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.2))
                        .frame(width: 1, height: 30)
                    
                    VStack(spacing: 4) {
                        Text("待付尾款")
                            .font(.caption)
                            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.9) : Color.primary.opacity(0.8))
                            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0)
                        Text("¥\(entry.totalBalance.formatted(.number.notation(.compactName)))")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(colorScheme == .dark ? .white : .primary)
                            .shadow(color: .white.opacity(0.5), radius: 2, x: 0, y: 0)
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
                    .foregroundStyle(Color.blue.opacity(0.8))
                    .shadow(color: .white.opacity(0.5), radius: 1, x: 0, y: 0)
                Spacer()
                Text(String(Calendar.current.component(.year, from: Date())) + "年")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(colorScheme == .dark ? .white : .primary)
                    .shadow(color: .white.opacity(0.5), radius: 1, x: 0, y: 0)
            }
            .padding(.horizontal, 4)
            
            // Full Grid
            LazyVGrid(columns: columns, spacing: 10) {
                if entry.statsType == .month {
                    // 显示 12 个月
                    let yearData = getRecentMonthsData(count: 12)
                    ForEach(yearData, id: \.id) { data in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color(white: 0.2).opacity(0.6) : Color.white.opacity(0.4))
                                .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                                .frame(height: 60)
                            
                            VStack(spacing: 2) {
                                Text("\(data.month)月")
                                    .font(.system(size: 12))
                                    .foregroundStyle(colorScheme == .dark ? .white : .primary)
                                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0)
                                if data.totalBalance > 0 {
                                    Text("¥\(data.totalBalance.formatted(.number.notation(.compactName)))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.orange)
                                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0)
                                } else {
                                    Text("-")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary.opacity(0.5))
                                        .shadow(color: .white.opacity(0.3), radius: 1, x: 0, y: 0)
                                }
                            }
                        }
                    }
                } else {
                    // 显示 Top 12 系列
                    ForEach(Array(entry.seriesStats.prefix(12))) { series in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.4))
                                .frame(height: 60)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(series.name)
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                        .foregroundStyle(colorScheme == .dark ? .white : .primary)
                                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0)
                                    Spacer()
                                    Text("\(series.count)")
                                        .font(.system(size: 9))
                                        .padding(3)
                                        .background(Circle().fill(Color.gray.opacity(0.2)))
                                }
                                Text("¥\(series.totalBalance)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0)
                            }
                            .padding(6)
                        }
                    }
                }
            }
            Spacer()
        }
    }
    
    private func getRecentMonthsData(count: Int) -> [WidgetMonthInfo] {
        return Array(entry.monthStats.prefix(count))
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
