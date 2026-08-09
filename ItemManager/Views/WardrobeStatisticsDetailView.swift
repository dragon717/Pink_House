//
//  WardrobeStatisticsDetailView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/24/26.
//

import SwiftUI
import Charts

private func wardrobeStatsDecimalText(_ decimal: Decimal, roundedToWhole: Bool = false) -> String {
    if roundedToWhole {
        var value = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
    return NSDecimalNumber(decimal: decimal).stringValue
}

private func wardrobeStatsCurrencyText(_ decimal: Decimal, roundedToWhole: Bool = false) -> String {
    "¥%@".appLocalized(wardrobeStatsDecimalText(decimal, roundedToWhole: roundedToWhole))
}

private func wardrobeStatsPercentText(_ percent: Int) -> String {
    "%@%%".appLocalized("\(percent)")
}

private func wardrobeStatsMonthLabel(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = LanguageManager.shared.locale
    formatter.calendar = Calendar.current
    formatter.setLocalizedDateFormatFromTemplate("MMM")
    return formatter.string(from: date)
}

struct WardrobeStatisticsDetailView: View {
    let clothings: [Clothing]
    var filterDescription: String? = nil
    var onClearFilter: (() -> Void)? = nil
    
    var body: some View {
        ZStack {
            // 背景
            LiquidBackground(themeSkinWallpaperContext: .wardrobe)
                .ignoresSafeArea()
            
            // 内容
            ScrollView {
                VStack(spacing: 20) {
                    // 1. 总览统计
                    OverviewStatsCard(clothings: clothings)
                    
                    // 2. 标签分类统计
                    TagStatsCard(clothings: clothings)
                    
                    // 3. 心愿尾款统计
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
            Text("衣橱统计".appLocalized)
                .font(.headline)
                .foregroundStyle(.primary)
                .themeSkinLegibleText(level: .inline, slot: .statsCard)
        }
    }
    
    @ToolbarContentBuilder
    private var trailingToolbarContent: some ToolbarContent {
        if let filterDescription, !filterDescription.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    Text("筛选:%@".appLocalized(filterDescription))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .themeSkinLegibleText(level: .inline, slot: .statsCard)
                    
                    Button("清除".appLocalized) {
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
        clothings.reduce(Decimal(0)) { $0 + $1.wardrobeValueAmount }
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
            Label("总览统计".appLocalized, systemImage: "chart.pie.fill")
                .font(.headline)
                .foregroundStyle(.brown)
                .themeSkinLegibleText(level: .inline, slot: .statsCard)
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    StatBox(title: "总裙装数", value: "\(totalCount)", unit: "件", color: .brown)
                    StatBox(title: "总裙装价值", value: wardrobeStatsCurrencyText(dressValue, roundedToWhole: true), unit: "", color: .orange)
                }
                
                HStack(spacing: 12) {
                    StatBox(title: "有小物的裙装", value: "\(accessoriesCount)", unit: "件", color: .purple.opacity(0.8))
                    StatBox(title: "总小物价值", value: wardrobeStatsCurrencyText(accessoriesValue, roundedToWhole: true), unit: "", color: .pink.opacity(0.8))
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("总价值".appLocalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .themeSkinLegibleText(level: .inline, slot: .statsCard)
                        Text(wardrobeStatsCurrencyText(totalValue, roundedToWhole: true))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.brown)
                            .themeSkinLegibleText(level: .chip, slot: .statsCard)
                        
                        if totalOriginalPrice > 0 {
                            Text("总原价(不包含小物和未填写的): ¥%@".appLocalized(wardrobeStatsDecimalText(totalOriginalPrice)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .themeSkinLegibleText(level: .inline, slot: .statsCard)
                                .padding(.top, 2)
                        }
                    }
                    Spacer()
                    Image(systemName: "star.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow.opacity(0.3))
                }
                .padding()
                .themeSkinAdaptiveSectionCard(slot: .statsCard, cornerRadius: 12, showsDecoration: false) {
                    Color(uiColor: .tertiarySystemGroupedBackground)
                }
            }
        }
        .padding()
        .themeSkinSectionCard(slot: .statsCard, cornerRadius: 16)
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.appLocalized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .themeSkinLegibleText(level: .inline, slot: .statsCard)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                    .themeSkinLegibleText(level: .chip, slot: .statsCard)
                if !unit.isEmpty {
                    Text(unit.appLocalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .themeSkinLegibleText(level: .inline, slot: .statsCard)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeSkinAdaptiveSectionCard(slot: .statsCard, cornerRadius: 12, showsDecoration: false) {
            color.opacity(0.1)
        }
    }
}

// MARK: - 2. 标签分类统计
struct TagStatsCard: View {
    let clothings: [Clothing]
    private static let noTagName = "无标签"
    
    struct TagStat: Identifiable {
        let id = UUID()
        let name: String
        let count: Int
        let value: Decimal
    }
    
    // 将无标签放到最后的排序统计
    var stats: [TagStat] {
        var map: [String: (count: Int, value: Decimal)] = [:]
        
        // Handle Tags (先处理有标签的)
        for clothing in clothings {
            guard let tags = clothing.tags, !tags.isEmpty else { continue }
            let itemValue = clothing.wardrobeValueAmount
            
            // 如果一个物品有多个标签，每个标签都计数
            for tag in tags {
                let current = map[tag.name, default: (0, 0)]
                map[tag.name] = (current.count + clothing.stock, current.value + itemValue)
            }
        }
        
        // Handle "No Tag" (放到最后)
        let noTagClothings = clothings.filter { $0.tags == nil || $0.tags!.isEmpty }
        var noTagStat: TagStat?
        if !noTagClothings.isEmpty {
            let count = noTagClothings.reduce(0) { $0 + $1.stock }
            let value = noTagClothings.reduce(Decimal(0)) { $0 + $1.wardrobeValueAmount }
            noTagStat = TagStat(name: Self.noTagName, count: count, value: value)
        } else {
            noTagStat = nil
        }
        
        // 有标签的按数量降序排列
        var sortedStats = map.map { TagStat(name: $0.key, count: $0.value.count, value: $0.value.value) }
            .sorted { $0.count > $1.count }
        
        // 将无标签放到最后
        if let noTagStat = noTagStat {
            sortedStats.append(noTagStat)
        }
        
        return sortedStats
    }
    
    var maxCount: Int {
        stats.map(\.count).max() ?? 1
    }
    
    var maxValue: Decimal {
        stats.map(\.value).max() ?? 1
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("标签分类统计".appLocalized, systemImage: "tag.fill")
                .font(.headline)
                .foregroundStyle(.brown)
                .themeSkinLegibleText(level: .inline, slot: .statsCard)
            
            if stats.isEmpty {
                Text("暂无标签数据".appLocalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .themeSkinLegibleText(level: .inline, slot: .statsCard)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    // Count Stats - 使用滚动条显示所有标签
                    VStack(alignment: .leading, spacing: 12) {
                        Text("数量统计".appLocalized)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .themeSkinLegibleText(level: .inline, slot: .statsCard)
                        
                        HeaderRow(left: "标签", right: "数量", extra: "占比")
                        
                        // 使用ScrollView支持滚动，显示所有标签
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: 8) {
                                ForEach(stats) { stat in
                                    StatRow(
                                        label: localizedTagName(stat.name),
                                        value: "\(stat.count)",
                                        percentage: Double(stat.count) / Double(maxCount),
                                        displayPercentage: wardrobeStatsPercentText(Int(Double(stat.count) / Double(stats.reduce(0) { $0 + $1.count }) * 100)),
                                        barColor: stat.name == Self.noTagName ? .gray.opacity(0.6) : .gray
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 200) // 限制最大高度，超出可滚动
                    }
                    
                    Divider()
                    
                    // Value Stats - 使用滚动条显示所有标签
                    VStack(alignment: .leading, spacing: 12) {
                        Text("价值统计".appLocalized)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .themeSkinLegibleText(level: .inline, slot: .statsCard)
                        
                        HeaderRow(left: "标签", right: "价值", extra: "占比")
                        
                        // 使用ScrollView支持滚动，显示所有标签
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: 8) {
                                ForEach(stats) { stat in
                                    let maxVal = Double(NSDecimalNumber(decimal: maxValue).doubleValue)
                                    let currentVal = Double(NSDecimalNumber(decimal: stat.value).doubleValue)
                                    
                                    StatRow(
                                        label: localizedTagName(stat.name),
                                        value: wardrobeStatsCurrencyText(stat.value),
                                        percentage: maxVal > 0 ? currentVal / maxVal : 0,
                                        displayPercentage: "",
                                        barColor: stat.name == Self.noTagName ? .gray.opacity(0.6) : .gray
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 200) // 限制最大高度，超出可滚动
                    }
                }
            }
        }
        .padding()
        .themeSkinSectionCard(slot: .statsCard, cornerRadius: 16)
    }

    private func localizedTagName(_ name: String) -> String {
        name == Self.noTagName ? Self.noTagName.appLocalized : name
    }
}

struct HeaderRow: View {
    let left: String
    let right: String
    let extra: String
    
    var body: some View {
        HStack {
            Text(left.appLocalized)
                .frame(width: 80, alignment: .leading)
            Spacer()
            Text(right.appLocalized)
            Text(extra.appLocalized)
                .frame(width: 40, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .themeSkinLegibleText(level: .inline, slot: .statsCard)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .themeSkinAdaptiveSectionCard(slot: .statsCard, cornerRadius: 8, showsDecoration: false) {
            Color(uiColor: .tertiarySystemGroupedBackground)
        }
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
                    .themeSkinLegibleText(level: .inline, slot: .statsCard)
            }
            .frame(width: 80, alignment: .leading)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .themeSkinLegibleText(level: .inline, slot: .statsCard)
            
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
                    .themeSkinLegibleText(level: .inline, slot: .statsCard)
                    .frame(width: 40, alignment: .trailing)
            } else {
                 Text("")
                    .frame(width: 40)
            }
        }
    }
}


// MARK: - 3. 心愿尾款统计
struct DepositStatsCard: View {
    let clothings: [Clothing]
    
    var depositPlans: [Clothing] {
        clothings.filter { $0.isFinalPaymentPlan }
    }
    
    var planCount: Int {
        depositPlans.count
    }
    
    var totalAmount: Decimal {
        // 注意：totalDeposit 和 totalBalance 已经包含了 stock 的乘法，所以这里直接使用
        depositPlans.reduce(0) { $0 + $1.totalDeposit + $1.totalBalance }
    }

    var paidDeposit: Decimal {
        // 注意：totalDeposit 已经包含了 stock 的乘法，所以这里直接使用
        depositPlans.reduce(0) { $0 + $1.totalDeposit }
    }

    var pendingBalance: Decimal {
        // 注意：totalBalance 已经包含了 stock 的乘法，所以这里直接使用
        depositPlans.reduce(0) { $0 + $1.totalBalance }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("心愿尾款统计".appLocalized, systemImage: "list.clipboard.fill")
                .font(.headline)
                .foregroundStyle(.brown)
                .themeSkinLegibleText(level: .inline, slot: .statsCard)
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    StatBox(title: "心愿尾款数量", value: "\(planCount)", unit: "件", color: .brown)
                    StatBox(title: "总金额", value: wardrobeStatsCurrencyText(totalAmount), unit: "", color: .green)
                }
                
                HStack(spacing: 12) {
                    StatBox(title: "已付定金总额", value: wardrobeStatsCurrencyText(paidDeposit), unit: "", color: .orange)
                    StatBox(title: "待付尾款总额", value: wardrobeStatsCurrencyText(pendingBalance), unit: "", color: .red)
                }
            }
        }
        .padding()
        .themeSkinSectionCard(slot: .statsCard, cornerRadius: 16)
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
        let value = filtered.reduce(Decimal(0)) { $0 + $1.wardrobeValueAmount }
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
            let amount = filtered.reduce(Decimal(0)) { $0 + $1.wardrobeValueAmount }
            
            let label = wardrobeStatsMonthLabel(for: date)
            stats.append(MonthlyStat(date: date, count: count, amount: amount, monthLabel: label))
        }
        
        return stats.reversed()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("购买时间统计".appLocalized, systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(.brown)
                .themeSkinLegibleText(level: .inline, slot: .statsCard)
            
            // This Month
            VStack(alignment: .leading, spacing: 8) {
                Text("本月购买".appLocalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .themeSkinLegibleText(level: .inline, slot: .statsCard)
                
                HStack(spacing: 12) {
                    StatBox(title: "数量", value: "\(thisMonthStats.count)", unit: "件", color: .brown)
                    StatBox(title: "总价值", value: wardrobeStatsCurrencyText(thisMonthStats.value), unit: "", color: .orange)
                }
            }
            
            Divider()
            
            // Charts
            VStack(alignment: .leading, spacing: 16) {
                Text("最近12个月购买数量".appLocalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .themeSkinLegibleText(level: .inline, slot: .statsCard)
                
                Chart(last12MonthsStats) { stat in
                    LineMark(
                        x: .value("月份".appLocalized, stat.monthLabel),
                        y: .value("数量".appLocalized, stat.count)
                    )
                    .foregroundStyle(Color.brown)
                    .symbol(Circle())
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("月份".appLocalized, stat.monthLabel),
                        y: .value("数量".appLocalized, stat.count)
                    )
                    .foregroundStyle(LinearGradient(colors: [.brown.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                    
                    if stat.count > 0 {
                        PointMark(
                            x: .value("月份".appLocalized, stat.monthLabel),
                            y: .value("数量".appLocalized, stat.count)
                        )
                        .annotation(position: .top) {
                            Text("\(stat.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .themeSkinLegibleText(level: .inline, slot: .statsCard)
                        }
                    }
                }
                .frame(height: 150)
                
                Divider()
                
                HStack {
                    Text("最近12个月金额".appLocalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .themeSkinLegibleText(level: .inline, slot: .statsCard)
                    
                    Spacer()
                    
                    if let selectedMonth,
                       let stat = last12MonthsStats.first(where: { $0.monthLabel == selectedMonth }) {
                        Text("%@: ¥%@".appLocalized(stat.monthLabel, wardrobeStatsDecimalText(stat.amount)))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                            .themeSkinLegibleText(level: .inline, slot: .statsCard)
                            .transition(.opacity)
                    }
                }
                
                Chart(last12MonthsStats) { stat in
                    BarMark(
                        x: .value("月份".appLocalized, stat.monthLabel),
                        y: .value("金额".appLocalized, NSDecimalNumber(decimal: stat.amount).doubleValue)
                    )
                    .foregroundStyle(selectedMonth == stat.monthLabel ? Color.orange : Color.orange.opacity(0.7))
                    .annotation(position: .top) {
                        if selectedMonth == stat.monthLabel {
                            Text(wardrobeStatsCurrencyText(stat.amount))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .themeSkinLegibleText(level: .inline, slot: .statsCard)
                        }
                    }
                }
                .chartXSelection(value: $selectedMonth)
                .frame(height: 150)
            }
        }
        .padding()
        .themeSkinSectionCard(slot: .statsCard, cornerRadius: 16)
    }
}
