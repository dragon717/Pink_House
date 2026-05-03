//
//  MonthSelectorView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI

struct MonthSelectorView: View {
    @Binding var selectedMonths: Set<Int>
    @Binding var year: Int
    let clothings: [Clothing] // Pass in all deposit clothings to calculate monthly stats
    @Binding var showYearStats: Bool
    @Binding var isExpanded: Bool
    
    let months = Array(1...12)
    let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    
    // Calculate stats for a specific month
    private func statsForMonth(_ month: Int) -> (count: Int, amount: Decimal) {
        let calendar = Calendar.current
        let monthlyClothings = clothings.filter { clothing in
            guard let date = clothing.reservationGroupingDate else { return false }
            // Year is already filtered in baseClothings, but double check doesn't hurt
            // Actually baseClothings already filtered by year, so we just check month
            let m = calendar.component(.month, from: date)
            return m == month
        }
        
        let itemCount = monthlyClothings.reduce(0) { $0 + $1.stock }
        let amount = monthlyClothings.reduce(0) { $0 + $1.reservationListAmount }
        return (itemCount, amount)
    }
    
    // 计算年份统计（根据选中的月份筛选，未选中则显示全年）
    private var yearStats: (totalCount: Int, styleCount: Int, paidDeposit: Decimal, pendingBalance: Decimal) {
        // 根据选中的月份筛选商品，未选中则使用全部
        let filteredClothings: [Clothing]
        if selectedMonths.isEmpty {
            filteredClothings = clothings
        } else {
            let calendar = Calendar.current
            filteredClothings = clothings.filter { clothing in
                guard let date = clothing.reservationGroupingDate else { return false }
                let month = calendar.component(.month, from: date)
                return selectedMonths.contains(month)
            }
        }
        
        // 去重计算款数
        var seenKeys: Set<String> = []
        var uniqueStyles: [Clothing] = []
        
        for clothing in filteredClothings {
            let key = "\(clothing.name)|\(clothing.deposit)|\(clothing.balance)"
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                uniqueStyles.append(clothing)
            }
        }
        
        let totalCount = filteredClothings.reduce(0) { $0 + $1.stock }
        let styleCount = uniqueStyles.count
        let paidDeposit = filteredClothings.reduce(0) { $0 + $1.reservationPaidAmount }
        let pendingBalance = filteredClothings.reduce(0) { $0 + $1.reservationListAmount }
        
        return (totalCount, styleCount, paidDeposit, pendingBalance)
    }
    
    // 计算最近有数据的月份（优先找当前时间之后的月份，如果没有则取最后一个有数据的月份）
    private var recentMonth: Int {
        let calendar = Calendar.current
        let now = Date()

        // 收集所有有数据的月份
        let monthsWithData = clothings.compactMap { clothing -> Int? in
            guard let date = clothing.reservationGroupingDate else { return nil }
            return calendar.component(.month, from: date)
        }

        guard !monthsWithData.isEmpty else {
            // 没有数据时返回当前月份
            return calendar.component(.month, from: now)
        }

        // 去重并排序
        let uniqueMonths = Set(monthsWithData).sorted()

        // 优先找当前月份之后的月份
        if let afterCurrent = uniqueMonths.first(where: { $0 >= calendar.component(.month, from: now) }) {
            return afterCurrent
        }

        // 没有之后的月份，取最后一个
        return uniqueMonths.last ?? calendar.component(.month, from: now)
    }

    // 计算最近月份的统计（使用最近月份而不是当前月份）
    private var currentMonthStats: (month: Int, count: Int, amount: Decimal, hasData: Bool) {
        let calendar = Calendar.current

        // 使用最近月份而不是当前月份
        let monthClothings = clothings.filter { clothing in
            guard let start = clothing.reservationGroupingDate else { return false }
            let m = calendar.component(.month, from: start)
            return m == recentMonth
        }

        let count = monthClothings.reduce(0) { $0 + $1.stock }
        let amount = monthClothings.reduce(0) { $0 + $1.reservationListAmount }

        return (recentMonth, count, amount, count > 0)
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
                    Text(isExpanded ? "年度预约 (点我折叠)" : "年度预约 (点我展开)")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
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
                        let stats = statsForMonth(month)
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
                                    Text("\(month)月")
                                        .font(.caption)
                                        .fontWeight(isSelected ? .bold : .regular)
                                        .foregroundStyle(isSelected ? .white : .primary)
                                    
                                    if stats.count > 0 {
                                        Text("\(stats.count)")
                                            .font(.system(size: 8))
                                            .padding(3)
                                            .background(isSelected ? Color.white.opacity(0.3) : Color.black.opacity(0.1))
                                            .clipShape(Circle())
                                            .foregroundStyle(isSelected ? .white : .primary)
                                            .offset(y: -1)
                                    }
                                }
                                
                                if stats.count > 0 {
                                    Text("¥\(NSDecimalNumber(decimal: stats.amount).stringValue)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(isSelected ? .white.opacity(0.9) : .orange)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                } else {
                                    Text("-")
                                        .font(.system(size: 10))
                                        .foregroundStyle(isSelected ? .white.opacity(0.6) : .secondary.opacity(0.3))
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
                RecentMonthCard(stats: currentMonthStats)
            }
        }
    }
}

// MARK: - 最近月统计卡片
struct RecentMonthCard: View {
    let stats: (month: Int, count: Int, amount: Decimal, hasData: Bool)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.brown)
                Text("最近月统计")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                if stats.hasData {
                    Text("\(stats.month)月")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
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
                        valueColor: .primary
                    )

                    Divider()
                        .frame(height: 30)

                    DepositStatItem(
                        title: "预约金额",
                        value: "¥\(NSDecimalNumber(decimal: stats.amount).stringValue)",
                        valueColor: Color(hex: "C94C72")
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            } else {
                Text("暂无预约数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .themeSkinSectionCard(slot: .statsCard, cornerRadius: 16, showsDecoration: false)
    }
}
