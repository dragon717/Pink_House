//
//  WidgetEntryView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/20/26.
//

import SwiftUI
import WidgetKit

struct WidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme
    
    private var currentFamilyType: WidgetFamilyType {
        switch family {
        case .systemSmall: return .small
        case .systemMedium: return .medium
        case .systemLarge: return .large
        default: return .common
        }
    }
    
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
                if let customImage = WidgetBackgroundManager.shared.loadImage(for: currentFamilyType) {
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

// MARK: - Components

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

struct WidgetOutlinedText: View {
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
            // Header
            HStack {
                WidgetOutlinedText(text: "本月", size: 12, weight: .bold)
                Spacer()
            }
            .padding(.bottom, 4)
            
            // Content
            // Find current month data
            let currentMonth = Calendar.current.component(.month, from: Date())
            let monthData = entry.monthStats.first(where: { $0.month == currentMonth })
            
            VStack(spacing: 4) {
                Spacer()
                VStack(spacing: 0) {
                    WidgetOutlinedText(text: "\(monthData?.count ?? 0)", size: 28, weight: .heavy)
                    WidgetOutlinedText(text: "款待付", size: 10, weight: .medium, color: .white.opacity(0.8))
                }
                
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 1)
                    .padding(.vertical, 4)
                
                VStack(spacing: 0) {
                    WidgetOutlinedText(text: "¥\((monthData?.totalBalance ?? 0).formatted(.number.notation(.compactName)))", size: 16, weight: .bold, color: .orange)
                    WidgetOutlinedText(text: "尾款", size: 10, weight: .medium, color: .orange.opacity(0.8))
                }
                Spacer()
            }
        }
        .padding(12)
    }
}

struct MediumWidgetView: View {
    let entry: Provider.Entry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 10) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundStyle(.white)
                        let currentYear = Calendar.current.component(.year, from: Date())
                        WidgetOutlinedText(text: "\(currentYear)年月度尾款天使", size: 14, weight: .bold)
                    }
                    WidgetOutlinedText(text: "总定金 ¥\(entry.totalDeposit.formatted(.number.notation(.compactName))) · 总尾款 ¥\(entry.totalBalance.formatted(.number.notation(.compactName)))", size: 10, weight: .regular, color: .white.opacity(0.9))
                }
                Spacer()
            }
            
            // Content Grid
            HStack(spacing: 8) {
                // Show next 4 active months (months with balance > 0) or recent months
                // Logic: Show current month + next 3 months
                let currentMonth = Calendar.current.component(.month, from: Date())
                let displayMonths = entry.monthStats.filter { $0.month >= currentMonth }.prefix(4)
                
                if displayMonths.isEmpty {
                    EmptyStateView(text: "本年暂无更多计划")
                } else {
                    ForEach(displayMonths, id: \.id) { data in
                        StatCard(
                            title: "\(data.month)月",
                            value: "¥\(data.totalBalance.formatted(.number.notation(.compactName)))",
                            subValue: "\(data.count)款",
                            highlight: data.month == currentMonth
                        )
                    }
                }
            }
        }
        .padding(16)
    }
}

struct LargeWidgetView: View {
    let entry: Provider.Entry
    @Environment(\.colorScheme) var colorScheme
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "calendar")
                            .font(.title3)
                            .foregroundStyle(.white)
                        let currentYear = Calendar.current.component(.year, from: Date())
                        WidgetOutlinedText(text: "\(currentYear)年度尾款天使表", size: 20, weight: .heavy)
                    }
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.pink).frame(width: 6, height: 6)
                            WidgetOutlinedText(text: "总定金 ¥\(entry.totalDeposit.formatted(.number.notation(.compactName)))", size: 12)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 6, height: 6)
                            WidgetOutlinedText(text: "总尾款 ¥\(entry.totalBalance.formatted(.number.notation(.compactName)))", size: 12)
                        }
                    }
                }
                Spacer()
            }
            
            // Content
            LazyVGrid(columns: columns, spacing: 12) {
                // Show all months with data
                let months = entry.monthStats.filter { $0.count > 0 || $0.totalBalance > 0 }
                if months.isEmpty {
                    EmptyStateView(text: "暂无数据")
                } else {
                    ForEach(months.prefix(12), id: \.id) { data in
                        StatCard(
                            title: "\(data.month)月",
                            value: "¥\(data.totalBalance.formatted(.number.notation(.compactName)))",
                            subValue: "定金 ¥\(data.totalDeposit.formatted(.number.notation(.compactName)))",
                            highlight: Calendar.current.component(.month, from: Date()) == data.month
                        )
                    }
                }
            }
            Spacer()
        }
        .padding(16)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subValue: String
    let highlight: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(highlight ? Color.white.opacity(0.2) : Color.clear)
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.5),
                    lineWidth: 1
                )
            
            VStack(spacing: 4) {
                WidgetOutlinedText(text: title, size: 12, weight: .bold)
                    .lineLimit(1)
                
                WidgetOutlinedText(text: value, size: 14, weight: .heavy, color: .orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                WidgetOutlinedText(text: subValue, size: 10, weight: .medium, color: .white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(8)
        }
        .frame(height: 60)
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
