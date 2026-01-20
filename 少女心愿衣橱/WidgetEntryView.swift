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
                    // 统一使用梦幻粉白背景，不再区分亮暗模式
                    // 这样可以避免系统误判模式导致背景变黑，同时也符合“少女心”全天候粉嫩的主题
                    DreamyBackgroundView(date: entry.date)
                }
            }
        }
        .widgetURL(URL(string: "itemmanager://stats"))
    }
}

// MARK: - Background Components

struct DreamyBackgroundView: View {
    let date: Date
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. 基础粉色渐变底色 (加深粉色，减少白色)
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.88, blue: 0.92), // 较深的樱花粉
                        Color(red: 1.0, green: 0.80, blue: 0.88)  // 偏紫的粉色
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // 2. 动态旋转的极光光晕 (基于时间变化角度)
                // 使用 date.timeIntervalSince1970 产生变化，模拟“律动”
                let timeFactor = date.timeIntervalSince1970
                
                // 光斑 A: 亮粉色 (提亮)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.92, blue: 0.96, opacity: 0.5),
                                Color(red: 1.0, green: 0.92, blue: 0.96, opacity: 0.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.8
                        )
                    )
                    .frame(width: geometry.size.width * 1.5, height: geometry.size.width * 1.5)
                    .offset(
                        x: cos(timeFactor / 3600) * 30, // 随时间缓慢移动
                        y: sin(timeFactor / 3600) * 30
                    )
                
                // 光斑 B: 深粉色 (增加饱和度)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.70, blue: 0.80, opacity: 0.4),
                                Color(red: 1.0, green: 0.70, blue: 0.80, opacity: 0.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.5
                        )
                    )
                    .frame(width: geometry.size.width, height: geometry.size.width)
                    .offset(
                        x: -cos(timeFactor / 1800) * 50,
                        y: -sin(timeFactor / 1800) * 50
                    )
                
                // 光斑 C: 梦幻紫 (增加层次)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.90, green: 0.70, blue: 0.90, opacity: 0.3),
                                Color(red: 0.90, green: 0.70, blue: 0.90, opacity: 0.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.6
                        )
                    )
                    .frame(width: geometry.size.width * 1.2, height: geometry.size.width * 1.2)
                    .position(x: geometry.size.width, y: geometry.size.height)
                
                // 3. 叠加一层暖色滤镜，统一色调，避免过白
                Color(red: 1.0, green: 0.60, blue: 0.75, opacity: 0.1)
                    .blendMode(.overlay)
            }
        }
    }
}

// MARK: - Components

struct OutlinedText: View {
    let text: String
    var size: CGFloat
    var weight: Font.Weight = .bold
    var color: Color = .white
    var outlineColor: Color = .black
    
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .rounded))
            .foregroundStyle(color)
            .shadow(color: outlineColor, radius: 0, x: 1, y: 1)
            .shadow(color: outlineColor, radius: 0, x: -1, y: -1)
            .shadow(color: outlineColor, radius: 0, x: 1, y: -1)
            .shadow(color: outlineColor, radius: 0, x: -1, y: 1)
    }
}

struct SmallWidgetView: View {
    let entry: Provider.Entry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // 卡片容器
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.clear) // 透明底
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.8), // 亮色: 乳白边框; 暗色: 微弱边框
                        lineWidth: 1.5
                    )
                
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        VStack(spacing: 2) {
                            OutlinedText(text: "总件数/款", size: 10, weight: .regular)
                            OutlinedText(text: "\(entry.totalCount)/\(entry.totalStyleCount)", size: 16)
                        }
                        
                        Spacer()
                        
                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                            .frame(width: 1, height: 20)
                        
                        Spacer()
                        
                        VStack(spacing: 2) {
                            OutlinedText(text: "裙子价值", size: 10, weight: .regular)
                            OutlinedText(text: "¥\(entry.totalPrice.formatted(.number.notation(.compactName)))", size: 16, color: .orange)
                        }
                    }
                    
                    Divider().background(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                    
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(.orange)
                            .shadow(color: .black, radius: 0, x: 0.5, y: 0.5)
                        OutlinedText(text: "查看详细统计", size: 10, weight: .medium, color: .orange)
                        Spacer()
                        Image(systemName: "heart.fill")
                            .foregroundStyle(Color.pink)
                            .shadow(color: .black, radius: 0, x: 0.5, y: 0.5)
                        OutlinedText(text: "少女专属", size: 10, weight: .medium, color: .pink)
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
            // 顶部汇总条 (卡片容器)
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.clear) // 透明底
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.8),
                        lineWidth: 1.5
                    )
                
                HStack(spacing: 0) {
                    // Item 1
                    VStack(spacing: 4) {
                        OutlinedText(text: "总件数/款", size: 10, weight: .regular)
                        OutlinedText(text: "\(entry.depositCount)/\(entry.depositStyleCount)", size: 16)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                        .frame(width: 1, height: 20)
                    
                    // Item 2
                    VStack(spacing: 4) {
                        OutlinedText(text: "已付定金", size: 10, weight: .regular)
                        OutlinedText(text: "¥\(entry.totalDeposit.formatted(.number.notation(.compactName)))", size: 16, color: .orange)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                        .frame(width: 1, height: 20)
                    
                    // Item 3
                    VStack(spacing: 4) {
                        OutlinedText(text: "待付尾款", size: 10, weight: .regular)
                        OutlinedText(text: "¥\(entry.totalBalance.formatted(.number.notation(.compactName)))", size: 16)
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
                                .fill(Color.clear)
                                .stroke(
                                    colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.8),
                                    lineWidth: 1
                                )
                            VStack(spacing: 4) {
                                OutlinedText(text: "\(data.month)月", size: 12, weight: .regular)
                                if data.totalBalance > 0 {
                                    OutlinedText(text: "¥\(data.totalBalance.formatted(.number.notation(.compactName)))", size: 10, color: .orange)
                                } else {
                                    Text("-")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary.opacity(0.5))
                                }
                            }
                        }
                    }
                } else {
                    // 显示 Top 4 系列
                    ForEach(Array(entry.seriesStats.prefix(4))) { series in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.clear)
                                .stroke(
                                    colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.8),
                                    lineWidth: 1
                                )
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    OutlinedText(text: series.name, size: 10, weight: .medium)
                                        .lineLimit(1)
                                    Spacer()
                                    OutlinedText(text: "\(series.count)", size: 10, weight: .regular, color: .secondary)
                                        .padding(4)
                                        .background(Circle().fill(Color.gray.opacity(0.2)))
                                }
                                OutlinedText(text: "¥\(series.totalBalance)", size: 10, color: .orange)
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
                    .fill(Color.clear) // 透明底
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.8),
                        lineWidth: 1.5
                    )
                
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        OutlinedText(text: "总件数/款", size: 12, weight: .regular)
                        OutlinedText(text: "\(entry.depositCount)/\(entry.depositStyleCount)", size: 22)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                        .frame(width: 1, height: 30)
                    
                    VStack(spacing: 4) {
                        OutlinedText(text: "已付定金", size: 12, weight: .regular)
                        OutlinedText(text: "¥\(entry.totalDeposit.formatted(.number.notation(.compactName)))", size: 22, color: .orange)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                        .frame(width: 1, height: 30)
                    
                    VStack(spacing: 4) {
                        OutlinedText(text: "待付尾款", size: 12, weight: .regular)
                        OutlinedText(text: "¥\(entry.totalBalance.formatted(.number.notation(.compactName)))", size: 22)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 16)
            }
            .frame(height: 90)
            
            // Grid Title
            HStack {
                OutlinedText(text: entry.statsType == .month ? "按月预估尾款" : "按系列预估尾款", size: 12, weight: .medium, color: .blue.opacity(0.8))
                Spacer()
                OutlinedText(text: String(Calendar.current.component(.year, from: Date())) + "年", size: 12, weight: .bold)
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
                                .fill(Color.clear)
                                .stroke(
                                    colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.8),
                                    lineWidth: 1
                                )
                                .frame(height: 60)
                            
                            VStack(spacing: 2) {
                                OutlinedText(text: "\(data.month)月", size: 12, weight: .regular)
                                if data.totalBalance > 0 {
                                    OutlinedText(text: "¥\(data.totalBalance.formatted(.number.notation(.compactName)))", size: 10, color: .orange)
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
                                .fill(Color.clear)
                                .stroke(
                                    colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.8),
                                    lineWidth: 1
                                )
                                .frame(height: 60)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    OutlinedText(text: series.name, size: 10, weight: .medium)
                                        .lineLimit(1)
                                    Spacer()
                                    OutlinedText(text: "\(series.count)", size: 9, weight: .regular, color: .secondary)
                                        .padding(3)
                                        .background(Circle().fill(Color.gray.opacity(0.1)))
                                }
                                OutlinedText(text: "¥\(series.totalBalance)", size: 10, color: .orange)
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
