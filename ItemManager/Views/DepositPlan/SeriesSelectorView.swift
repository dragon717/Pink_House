//
//  SeriesSelectorView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI

struct SeriesSelectorView: View {
    @Binding var selectedSeries: Set<String>
    @Binding var year: Int
    let seriesList: [SeriesInfo]
    let isAnalyzing: Bool
    @Binding var showYearStats: Bool
    let clothings: [Clothing] // 用于计算当前月统计（不区分系列）
    @Binding var isExpanded: Bool
    @State private var showTips: Bool = false

    // Adaptive grid columns
    let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)]

    // 计算系列视图的年份统计（根据选中的系列筛选，未选中则显示全部系列）
    private var yearStats: (totalCount: Int, styleCount: Int, paidDeposit: Decimal, pendingBalance: Decimal) {
        // 根据选中的系列筛选，未选中则使用全部系列
        let filteredSeries: [SeriesInfo]
        if selectedSeries.isEmpty {
            filteredSeries = seriesList
        } else {
            filteredSeries = seriesList.filter { selectedSeries.contains($0.name) }
        }
        
        // 从筛选后的系列计算总计
        let totalCount = filteredSeries.reduce(0) { $0 + $1.itemCount }
        let styleCount = filteredSeries.count
        let paidDeposit = filteredSeries.reduce(0) { $0 + $1.totalDeposit }
        let pendingBalance = filteredSeries.reduce(0) { $0 + $1.totalBalance }

        return (totalCount, styleCount, paidDeposit, pendingBalance)
    }

    // 计算最近添加的统计（一个月内添加的商品，不区分系列）
    private var recentAddedStats: (title: String, count: Int, amount: Decimal, hasData: Bool) {
        let calendar = Calendar.current
        let now = Date()
        // 获取一个月前的日期
        guard let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) else {
            return ("最近添加", 0, 0, false)
        }

        // 统计最近一个月内添加的商品（按 createdAt 字段）
        let recentClothings = clothings.filter { clothing in
            clothing.createdAt >= oneMonthAgo
        }

        let count = recentClothings.reduce(0) { $0 + $1.stock }
        let amount = recentClothings.reduce(0) { $0 + $1.reservationListAmount }

        return ("最近添加", count, amount, count > 0)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(isExpanded ? "按系列预约 (点我折叠)" : "按系列预约 (点我展开)")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    
                    // Tips Icon
                    Button {
                        showTips = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .themeSkinLegibleSymbol(level: .inline, slot: .sectionCard)
                    }
                    .buttonStyle(.plain)
                    .alert("系列分类规则", isPresented: $showTips) {
                        Button("知道了", role: .cancel) { }
                    } message: {
                        Text("系统会自动根据商品名称的前 2-4 个字（去除特殊符号）作为系列前缀进行归类。\n\n例如：\n\"少女心愿 连衣裙\"\n\"少女心愿 半裙\"\n\n都会被归类为 \"Pink\" 系列。\n注：同名属于同一款商品。")
                    }
                    
                    if isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 8)
                    }
                    
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if isExpanded {
                // Year Selector（带小眼睛按钮）
                YearSelectorView(
                    year: $year,
                    showStats: showYearStats,
                    onToggleStats: { showYearStats.toggle() }
                )
                
                // 年份统计（简洁显示）
                YearStatsCard(
                    stats: yearStats,
                    year: year,
                    isVisible: showYearStats
                )
                
                if seriesList.isEmpty {
                    if isAnalyzing {
                        Text("正在分析系列...")
                            .foregroundStyle(.secondary)
                            .themeSkinLegibleText(level: .inline, slot: .emptyState)
                            .padding()
                    } else {
                        Text("暂无系列数据")
                            .foregroundStyle(.secondary)
                            .themeSkinLegibleText(level: .inline, slot: .emptyState)
                            .padding()
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(seriesList) { series in
                                let isSelected = selectedSeries.contains(series.name)
                                
                                Button {
                                    if isSelected {
                                        selectedSeries.remove(series.name)
                                    } else {
                                        selectedSeries = [series.name]
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(series.name)
                                                .font(.caption)
                                                .fontWeight(isSelected ? .bold : .medium)
                                                .lineLimit(1)
                                                .themeSkinLegibleText(level: .inline, slot: .filterChip)
                                            Spacer()
                                            Text("\(series.itemCount)")
                                                .font(.system(size: 9))
                                                .themeSkinLegibleText(level: .chip, slot: .filterChip)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 4)
                                                .background(Color.black.opacity(0.1))
                                                .clipShape(Capsule())
                                        }
                                        .foregroundStyle(isSelected ? .white : .primary)
                                        
                                        Text("¥\(NSDecimalNumber(decimal: series.totalBalance).stringValue)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(isSelected ? .white.opacity(0.9) : (series.totalBalance > 0 ? .orange : .secondary.opacity(0.7)))
                                            .themeSkinLegibleText(level: .inline, slot: .filterChip)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .padding(8)
                                    .themeSkinAdaptiveSectionCard(
                                        slot: .filterChip,
                                        cornerRadius: 8,
                                        showsDecoration: false
                                    ) {
                                        if isSelected {
                                            Color.brown
                                        } else {
                                            CardBackgroundView(cornerRadius: 8)
                                        }
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.primary.opacity(0.1), lineWidth: isSelected ? 0 : 1)
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 300) // Limit height to avoid taking too much space
                }
            } else {
                // 隐藏时显示最近添加统计（一个月内）
                RecentAddedCard(stats: recentAddedStats)
            }
        }
    }
}

// MARK: - 最近添加统计卡片
struct RecentAddedCard: View {
    let stats: (title: String, count: Int, amount: Decimal, hasData: Bool)
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared

    private var activeStatsDescriptor: ThemeSkinDescriptor? {
        themeSkinManager.activeThemeDescriptor(for: .statsCard, state: .default)
    }

    private var isSupportedThemeSkin: Bool {
        let namespace = activeStatsDescriptor?.assetNamespace
        return namespace == SkyConcertThemeSkin.namespace || namespace == SwanDreamThemeSkin.namespace
    }

    private var titleColor: Color {
        guard isSupportedThemeSkin else { return .primary }
        return Color(hex: "C94C72")
    }

    private var supportingTextColor: Color {
        guard isSupportedThemeSkin else { return .secondary }
        return SwanDreamThemeSkin.isSwanDream(activeStatsDescriptor) ? SwanDreamThemeSkin.text : SkyConcertThemeSkin.text
    }

    @ViewBuilder
    private var readableCardBase: some View {
        if isSupportedThemeSkin && colorScheme == .dark {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "FFF7FA").opacity(0.26),
                                    Color(hex: "EFF8FF").opacity(0.22)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(titleColor)
                    .themeSkinLegibleSymbol(level: .chip, slot: .statsCard, descriptor: activeStatsDescriptor)
                Text(stats.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(titleColor)
                    .themeSkinLegibleText(level: .chip, slot: .statsCard, descriptor: activeStatsDescriptor)
                Spacer()
                if stats.hasData {
                    Text("一个月内")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .themeSkinLegibleText(level: .chip, slot: .filterChip, descriptor: activeStatsDescriptor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.brown)
                        .clipShape(Capsule())
                }
            }

            if stats.hasData {
                HStack(spacing: 0) {
                    DepositStatItem(
                        title: "预约件数",
                        value: "\(stats.count)",
                        valueColor: titleColor,
                        titleColor: supportingTextColor
                    )

                    Divider()
                        .frame(height: 30)

                    DepositStatItem(
                        title: "预约金额",
                        value: "¥\(NSDecimalNumber(decimal: stats.amount).stringValue)",
                        valueColor: titleColor,
                        titleColor: supportingTextColor
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            } else {
                Text("暂无最近添加")
                    .font(.caption)
                    .foregroundStyle(supportingTextColor)
                    .themeSkinLegibleText(level: .inline, slot: .statsCard, descriptor: activeStatsDescriptor)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background {
            readableCardBase
        }
        .themeSkinSectionCard(slot: .statsCard, cornerRadius: 16, showsDecoration: false)
    }
}
