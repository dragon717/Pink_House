//
//  MonthSelectorView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI

struct DepositMonthStats {
    let count: Int
    let amount: Decimal
    let paidDeposit: Decimal
}

struct DepositYearStatsSummary {
    let totalCount: Int
    let styleCount: Int
    let paidDeposit: Decimal
    let pendingBalance: Decimal
}

struct DepositMonthSelectorSummary {
    private let statsByMonth: [Int: DepositMonthStats]
    private let styleKeysByMonth: [Int: Set<String>]
    let recentMonth: Int

    init(
        statsByMonth: [Int: DepositMonthStats] = [:],
        styleKeysByMonth: [Int: Set<String>] = [:],
        recentMonth: Int = Calendar.current.component(.month, from: Date())
    ) {
        self.statsByMonth = statsByMonth
        self.styleKeysByMonth = styleKeysByMonth
        self.recentMonth = recentMonth
    }

    init(clothings: [Clothing], calendar: Calendar = .current, now: Date = Date()) {
        let interval = PerformanceSignpost.monthStats(month: "base", itemCount: clothings.count)
        defer { PerformanceSignpost.end(interval, detail: "summary") }

        var monthlyCounts: [Int: Int] = [:]
        var monthlyAmounts: [Int: Decimal] = [:]
        var monthlyPaidDeposits: [Int: Decimal] = [:]
        var monthlyStyleKeys: [Int: Set<String>] = [:]

        for clothing in clothings {
            guard let date = clothing.reservationGroupingDate else { continue }

            let month = calendar.component(.month, from: date)
            monthlyCounts[month, default: 0] += clothing.stock
            monthlyAmounts[month, default: 0] += clothing.reservationListAmount
            monthlyPaidDeposits[month, default: 0] += clothing.reservationPaidAmount
            monthlyStyleKeys[month, default: []].insert(Self.styleKey(for: clothing))
        }

        let stats = monthlyCounts.reduce(into: [Int: DepositMonthStats]()) { result, element in
            let (month, count) = element
            result[month] = DepositMonthStats(
                count: count,
                amount: monthlyAmounts[month, default: 0],
                paidDeposit: monthlyPaidDeposits[month, default: 0]
            )
        }

        let monthsWithData = Set(monthlyCounts.keys).sorted()
        let currentMonth = calendar.component(.month, from: now)
        let recentMonth = monthsWithData.first(where: { $0 >= currentMonth })
            ?? monthsWithData.last
            ?? currentMonth

        self.init(
            statsByMonth: stats,
            styleKeysByMonth: monthlyStyleKeys,
            recentMonth: recentMonth
        )
    }

    func statsForMonth(_ month: Int) -> DepositMonthStats {
        statsByMonth[month] ?? DepositMonthStats(count: 0, amount: 0, paidDeposit: 0)
    }

    func yearStats(selectedMonths: Set<Int>) -> DepositYearStatsSummary {
        let months = selectedMonths.isEmpty ? Set(statsByMonth.keys) : selectedMonths
        var totalCount = 0
        var pendingBalance: Decimal = 0
        var paidDeposit: Decimal = 0
        var styleKeys: Set<String> = []

        for month in months {
            let stats = statsForMonth(month)
            totalCount += stats.count
            pendingBalance += stats.amount
            paidDeposit += stats.paidDeposit
            styleKeys.formUnion(styleKeysByMonth[month, default: []])
        }

        return DepositYearStatsSummary(
            totalCount: totalCount,
            styleCount: styleKeys.count,
            paidDeposit: paidDeposit,
            pendingBalance: pendingBalance
        )
    }

    var currentMonthStats: (month: Int, count: Int, amount: Decimal, hasData: Bool) {
        let stats = statsForMonth(recentMonth)
        return (recentMonth, stats.count, stats.amount, stats.count > 0)
    }

    private static func styleKey(for clothing: Clothing) -> String {
        "\(clothing.name)|\(clothing.deposit)|\(clothing.balance)"
    }
}

struct MonthSelectorView: View {
    @Binding var selectedMonths: Set<Int>
    @Binding var year: Int
    let summary: DepositMonthSelectorSummary
    @Binding var showYearStats: Bool
    @Binding var isExpanded: Bool

    let months = Array(1...12)
    let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    // 计算年份统计（根据选中的月份筛选，未选中则显示全年）
    private var yearStats: (totalCount: Int, styleCount: Int, paidDeposit: Decimal, pendingBalance: Decimal) {
        let stats = summary.yearStats(selectedMonths: selectedMonths)
        return (stats.totalCount, stats.styleCount, stats.paidDeposit, stats.pendingBalance)
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
                    Text((isExpanded ? "年度预约 (点我折叠)" : "年度预约 (点我展开)").appLocalized)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
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
                
                // Month Grid
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(months, id: \.self) { month in
                        let stats = summary.statsForMonth(month)
                        let isSelected = selectedMonths.contains(month)
                        
                        Button {
                            if isSelected {
                                selectedMonths.remove(month)
                            } else {
                                selectedMonths = [month]
                            }
                        } label: {
                            VStack(spacing: 4) {
                                HStack(spacing: 2) {
                                    Text(DepositPlanFormatters.monthText(month))
                                        .font(.caption)
                                        .fontWeight(isSelected ? .bold : .regular)
                                        .foregroundStyle(isSelected ? .white : .primary)
                                        .themeSkinLegibleText(level: .inline, slot: .filterChip)
                                    
                                    if stats.count > 0 {
                                        Text("\(stats.count)")
                                            .font(.system(size: 8))
                                            .themeSkinLegibleText(level: .chip, slot: .filterChip)
                                            .padding(3)
                                            .background(isSelected ? Color.white.opacity(0.3) : Color.black.opacity(0.1))
                                            .clipShape(Circle())
                                            .foregroundStyle(isSelected ? .white : .primary)
                                            .offset(y: -1)
                                    }
                                }
                                
                                if stats.count > 0 {
                                    Text(DepositPlanFormatters.currencyText(stats.amount))
                                        .font(.system(size: 10))
                                        .foregroundStyle(isSelected ? .white.opacity(0.9) : .orange)
                                        .themeSkinLegibleText(level: .inline, slot: .filterChip)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                } else {
                                    Text("-")
                                        .font(.system(size: 10))
                                        .foregroundStyle(isSelected ? .white.opacity(0.6) : .secondary.opacity(0.3))
                                        .themeSkinLegibleText(level: .inline, slot: .filterChip)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .themeSkinAdaptiveSectionCard(
                                slot: .filterChip,
                                cornerRadius: 12,
                                showsDecoration: false
                            ) {
                                if isSelected {
                                    Color.brown
                                } else {
                                    CardBackgroundView(cornerRadius: 12)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: isSelected ? 0 : 1)
                            )
                        }
                    }
                }
            } else {
                // 隐藏时显示当前月统计
                RecentMonthCard(stats: summary.currentMonthStats)
            }
        }
    }
}

// MARK: - 最近月统计卡片
struct RecentMonthCard: View {
    let stats: (month: Int, count: Int, amount: Decimal, hasData: Bool)
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
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(titleColor)
                    .themeSkinLegibleSymbol(level: .chip, slot: .statsCard, descriptor: activeStatsDescriptor)
                Text("最近月统计".appLocalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(titleColor)
                    .themeSkinLegibleText(level: .chip, slot: .statsCard, descriptor: activeStatsDescriptor)
                Spacer()
                if stats.hasData {
                    Text(DepositPlanFormatters.monthText(stats.month))
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
                        value: DepositPlanFormatters.currencyText(stats.amount),
                        valueColor: titleColor,
                        titleColor: supportingTextColor
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            } else {
                Text("暂无预约数据".appLocalized)
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
