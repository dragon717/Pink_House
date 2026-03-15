//
//  WardrobeStatisticsDetailView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/24/26.
//

import SwiftUI
import Charts

struct WardrobeStatisticsDetailView: View {
    let clothings: [Clothing]
    var filterDescription: String? = nil
    var onClearFilter: (() -> Void)? = nil
    
    var body: some View {
        ZStack {
            // 背景
            LiquidBackground()
                .ignoresSafeArea()
            
            // 内容
            ScrollView {
                VStack(spacing: 20) {
                    // 1. 总览统计
                    OverviewStatsCard(clothings: clothings)
                    
                    // 2. 标签分类统计
                    TagStatsCard(clothings: clothings)
                    
                    // 3. 尾款天使统计
                    DepositStatsCard(clothings: clothings)
                    
                    // 4. 购买时间统计
                    PurchaseTimeStatsCard(clothings: clothings)
                }
                .padding()
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            centerToolbarContent
            trailingToolbarContent
        }
        .onAppear {
            RewardManager.shared.triggerReward(type: .firstTimeFeature("WardrobeStats"))
        }
    }
    
    // MARK: - Toolbar Content
    
    @ToolbarContentBuilder
    private var centerToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("衣橱统计")
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }
    
    @ToolbarContentBuilder
    private var trailingToolbarContent: some ToolbarContent {
        if let filterDescription, !filterDescription.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    Text("筛选:\(filterDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button("清除") {
                        onClearFilter?()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

// MARK: - 1. 总览统计
struct OverviewStatsCard: View {
    let clothings: [Clothing]
    
    var totalCount: Int {
        clothings.reduce(0) { $0 + $1.stock }
    }
    
    var dressValue: Decimal {
        clothings.reduce(0) { $0 + ($1.price * Decimal($1.stock)) }
    }
    
    var accessoriesCount: Int {
        clothings.filter { !$0.accessories.isEmpty || $0.accessoriesPrice > 0 }.count
    }
    
    var accessoriesValue: Decimal {
        clothings.reduce(0) { total, clothing in
            let attachedValue = clothing.accessoriesPrice * Decimal(clothing.stock)
            let selfValue = clothing.types.contains("小物") ? (clothing.price * Decimal(clothing.stock)) : 0
            return total + attachedValue + selfValue
        }
    }
    
    var totalValue: Decimal {
        clothings.reduce(0) { $0 + (($1.price + $1.accessoriesPrice) * Decimal($1.stock)) }
    }
    
    var totalOriginalPrice: Decimal {
        clothings.reduce(0) { total, clothing in
            if clothing.originalPrice > 0 {
                return total + (clothing.originalPrice * Decimal(clothing.stock))
            }
            return total
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("总览统计", systemImage: "chart.pie.fill")
                .font(.headline)
                .foregroundStyle(.brown)
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    StatBox(title: "总裙装数", value: "\(totalCount)", unit: "件", color: .brown)
                    StatBox(title: "总裙装价值", value: "¥\(formatPrice(dressValue))", unit: "", color: .orange)
                }
                
                HStack(spacing: 12) {
                    StatBox(title: "有小物的裙装", value: "\(accessoriesCount)", unit: "件", color: .purple.opacity(0.8))
                    StatBox(title: "总小物价值", value: "¥\(formatPrice(accessoriesValue))", unit: "", color: .pink.opacity(0.8))
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("总价值")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("¥\(formatPrice(totalValue))")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.brown)
                        
                        if totalOriginalPrice > 0 {
                            Text("总原价(不包含小物和未填写的): ¥\(formatPrice(totalOriginalPrice))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    Spacer()
                    Image(systemName: "star.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow.opacity(0.3))
                }
                .padding()
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func formatPrice(_ decimal: Decimal) -> String {
        let number = NSDecimalNumber(decimal: decimal)
        return number.stringValue
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - 2. 标签分类统计
struct TagStatsCard: View {
    let clothings: [Clothing]
    
    struct TagStat: Identifiable {
        let id = UUID()
        let name: String
        let count: Int
        let value: Decimal
    }
    
    var stats: [TagStat] {
        var map: [String: (count: Int, value: Decimal)] = [:]
        
        // Handle "No Tag"
        let noTagClothings = clothings.filter { $0.tags == nil || $0.tags!.isEmpty }
        if !noTagClothings.isEmpty {
            let count = noTagClothings.reduce(0) { $0 + $1.stock }
            let value = noTagClothings.reduce(0) { $0 + (($1.price + $1.accessoriesPrice) * Decimal($1.stock)) }
            map["无标签"] = (count, value)
        }
        
        // Handle Tags
        for clothing in clothings {
            guard let tags = clothing.tags, !tags.isEmpty else { continue }
            let itemValue = (clothing.price + clothing.accessoriesPrice) * Decimal(clothing.stock)
            
            // If item has multiple tags, how do we count?
            // Usually we count it for EACH tag.
            for tag in tags {
                let current = map[tag.name, default: (0, 0)]
                map[tag.name] = (current.count + clothing.stock, current.value + itemValue)
            }
        }
        
        return map.map { TagStat(name: $0.key, count: $0.value.count, value: $0.value.value) }
            .sorted { $0.count > $1.count }
    }
    
    var maxCount: Int {
        stats.map(\.count).max() ?? 1
    }
    
    var maxValue: Decimal {
        stats.map(\.value).max() ?? 1
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("标签分类统计", systemImage: "tag.fill")
                .font(.headline)
                .foregroundStyle(.brown)
            
            if stats.isEmpty {
                Text("暂无标签数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    // Count Stats
                    VStack(alignment: .leading, spacing: 12) {
                        Text("数量统计")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HeaderRow(left: "标签", right: "数量", extra: "占比")
                        
                        ForEach(stats.prefix(5)) { stat in
                            StatRow(
                                label: stat.name,
                                value: "\(stat.count)",
                                percentage: Double(stat.count) / Double(maxCount), // Bar width relative to max
                                displayPercentage: "\(Int(Double(stat.count) / Double(stats.reduce(0) { $0 + $1.count }) * 100))%", // Share of total? No, usually share of total items? But items can have multiple tags.
                                // Let's use share of displayed Max for bar, and share of THIS category relative to max?
                                // The screenshot shows "100.0%" for "No Tag" which is the only one.
                                // Let's calculate percentage relative to max or total?
                                // Screenshot: 2 items, No Tag: 2, 100%.
                                // So it's percentage of total items (or total tag occurrences).
                                barColor: .gray
                            )
                        }
                    }
                    
                    Divider()
                    
                    // Value Stats
                    VStack(alignment: .leading, spacing: 12) {
                        Text("价值统计")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HeaderRow(left: "标签", right: "价值", extra: "占比")
                        
                        ForEach(stats.prefix(5)) { stat in
                            let maxVal = Double(NSDecimalNumber(decimal: maxValue).doubleValue)
                            let currentVal = Double(NSDecimalNumber(decimal: stat.value).doubleValue)
                            
                            StatRow(
                                label: stat.name,
                                value: "¥\(NSDecimalNumber(decimal: stat.value).stringValue)",
                                percentage: maxVal > 0 ? currentVal / maxVal : 0,
                                displayPercentage: "", // Value percentage might be complex if sum > total due to overlap.
                                // Let's just show bar and value.
                                barColor: .gray
                            )
                        }
                    }
                }
            }
        }
        .padding()
        .background(CardBackgroundView(cornerRadius: 16))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct HeaderRow: View {
    let left: String
    let right: String
    let extra: String
    
    var body: some View {
        HStack {
            Text(left)
                .frame(width: 80, alignment: .leading)
            Spacer()
            Text(right)
            Text(extra)
                .frame(width: 40, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .cornerRadius(8)
    }
}

struct StatRow: View {
    let label: String
    let value: String
    let percentage: Double // 0.0 - 1.0 for bar width
    let displayPercentage: String
    let barColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(barColor)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .frame(width: 80, alignment: .leading)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
            
            // Progress Bar
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                    
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(0, proxy.size.width * percentage))
                }
            }
            .frame(height: 4)
            .frame(width: 60)
            
            if !displayPercentage.isEmpty {
                Text(displayPercentage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            } else {
                 Text("")
                    .frame(width: 40)
            }
        }
    }
}


// MARK: - 3. 尾款天使统计
struct DepositStatsCard: View {
    let clothings: [Clothing]
    
    var depositPlans: [Clothing] {
        clothings.filter { $0.isDepositPlan }
    }
    
    var planCount: Int {
        depositPlans.count
    }
    
    var totalAmount: Decimal {
        depositPlans.reduce(0) { $0 + (($1.totalDeposit + $1.totalBalance) * Decimal($1.stock)) }
    }
    
    var paidDeposit: Decimal {
        depositPlans.reduce(0) { $0 + ($1.totalDeposit * Decimal($1.stock)) }
    }
    
    var pendingBalance: Decimal {
        depositPlans.reduce(0) { $0 + ($1.totalBalance * Decimal($1.stock)) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("尾款天使统计", systemImage: "list.clipboard.fill")
                .font(.headline)
                .foregroundStyle(.brown)
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    StatBox(title: "尾款天使数量", value: "\(planCount)", unit: "件", color: .brown)
                    StatBox(title: "总金额", value: "¥\(NSDecimalNumber(decimal: totalAmount).stringValue)", unit: "", color: .green)
                }
                
                HStack(spacing: 12) {
                    StatBox(title: "已付定金总额", value: "¥\(NSDecimalNumber(decimal: paidDeposit).stringValue)", unit: "", color: .orange)
                    StatBox(title: "待付尾款总额", value: "¥\(NSDecimalNumber(decimal: pendingBalance).stringValue)", unit: "", color: .red)
                }
            }
        }
        .padding()
        .background(CardBackgroundView(cornerRadius: 16))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - 4. 购买时间统计
struct PurchaseTimeStatsCard: View {
    let clothings: [Clothing]
    @State private var selectedMonth: String?
    
    var currentMonth: Date { Date() }
    
    var thisMonthStats: (count: Int, value: Decimal) {
        let calendar = Calendar.current
        let now = Date()
        let currentMonthComponents = calendar.dateComponents([.year, .month], from: now)
        
        let filtered = clothings.filter {
            let components = calendar.dateComponents([.year, .month], from: $0.purchaseDate)
            return components.year == currentMonthComponents.year && components.month == currentMonthComponents.month
        }
        
        let count = filtered.reduce(0) { $0 + $1.stock }
        let value = filtered.reduce(0) { $0 + (($1.price + $1.accessoriesPrice) * Decimal($1.stock)) }
        return (count, value)
    }
    
    // Last 12 months data
    struct MonthlyStat: Identifiable {
        let id = UUID()
        let date: Date
        let count: Int
        let amount: Decimal
        let monthLabel: String
    }
    
    var last12MonthsStats: [MonthlyStat] {
        let calendar = Calendar.current
        var stats: [MonthlyStat] = []
        let now = Date()
        
        // Go back 11 months + current month
        for i in 0..<12 {
            guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            let components = calendar.dateComponents([.year, .month], from: date)
            
            let filtered = clothings.filter {
                let c = calendar.dateComponents([.year, .month], from: $0.purchaseDate)
                return c.year == components.year && c.month == components.month
            }
            
            let count = filtered.reduce(0) { $0 + $1.stock }
            let amount = filtered.reduce(0) { $0 + (($1.price + $1.accessoriesPrice) * Decimal($1.stock)) }
            
            let label = "\(components.month ?? 0)月"
            stats.append(MonthlyStat(date: date, count: count, amount: amount, monthLabel: label))
        }
        
        return stats.reversed()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("购买时间统计", systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(.brown)
            
            // This Month
            VStack(alignment: .leading, spacing: 8) {
                Text("本月购买")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    StatBox(title: "数量", value: "\(thisMonthStats.count)", unit: "件", color: .brown)
                    StatBox(title: "总价值", value: "¥\(NSDecimalNumber(decimal: thisMonthStats.value).stringValue)", unit: "", color: .orange)
                }
            }
            
            Divider()
            
            // Charts
            VStack(alignment: .leading, spacing: 16) {
                Text("最近12个月购买数量")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Chart(last12MonthsStats) { stat in
                    LineMark(
                        x: .value("月份", stat.monthLabel),
                        y: .value("数量", stat.count)
                    )
                    .foregroundStyle(Color.brown)
                    .symbol(Circle())
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("月份", stat.monthLabel),
                        y: .value("数量", stat.count)
                    )
                    .foregroundStyle(LinearGradient(colors: [.brown.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                    
                    if stat.count > 0 {
                        PointMark(
                            x: .value("月份", stat.monthLabel),
                            y: .value("数量", stat.count)
                        )
                        .annotation(position: .top) {
                            Text("\(stat.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 150)
                
                Divider()
                
                HStack {
                    Text("最近12个月金额")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if let selectedMonth,
                       let stat = last12MonthsStats.first(where: { $0.monthLabel == selectedMonth }) {
                        Text("\(stat.monthLabel): ¥\(NSDecimalNumber(decimal: stat.amount).stringValue)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                            .transition(.opacity)
                    }
                }
                
                Chart(last12MonthsStats) { stat in
                    BarMark(
                        x: .value("月份", stat.monthLabel),
                        y: .value("金额", NSDecimalNumber(decimal: stat.amount).doubleValue)
                    )
                    .foregroundStyle(selectedMonth == stat.monthLabel ? Color.orange : Color.orange.opacity(0.7))
                    .annotation(position: .top) {
                        if selectedMonth == stat.monthLabel {
                            Text("¥\(NSDecimalNumber(decimal: stat.amount).stringValue)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartXSelection(value: $selectedMonth)
                .frame(height: 150)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}
