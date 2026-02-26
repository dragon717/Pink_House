//
//  DepositPlanView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI
import SwiftData

enum DepositViewMode {
    case monthly
    case series
}

enum DepositDisplayMode: String, CaseIterable, Identifiable {
    case detail = "详情"
    case simple = "简略"
    
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .detail: return "list.bullet.rectangle.portrait"
        case .simple: return "list.bullet"
        }
    }
}

struct DepositPlanView: View {
    @Binding var searchText: String
    @Binding var displayMode: DepositDisplayMode
    @Query private var depositClothings: [Clothing]
    
    @State private var viewMode: DepositViewMode = .monthly
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonths: Set<Int> = []
    @State private var selectedSeries: Set<String> = []
    @State private var seriesList: [SeriesInfo] = []
    @State private var isAnalyzing: Bool = false
    @State private var showStats = false // 默认隐藏总待付尾款统计
    @State private var showYearStats = false // 默认隐藏年份统计（独立控制）
    
    @State private var filteredClothings: [Clothing] = []
    @State private var baseClothings: [Clothing] = []
    
    // Money Counting Animation State
    struct MoneyCountingState: Identifiable {
        let id = UUID()
        let amount: Decimal
    }
    
    @State private var moneyCountingState: MoneyCountingState?
    
    // 显示确认弹窗
    @State private var showConfirmDialog = false
    
    // Filter properties
    let selectedTagIDs: Set<UUID>
    let selectedBrandIDs: Set<UUID>
    let selectedTypes: Set<String>
    let selectedColors: Set<String>
    let selectedSizes: Set<String>
    let selectedLengths: Set<String>
    let selectedConditions: Set<String>
    let selectedAccessories: Set<String>
    
    // Sort option - stored to apply sorting manually since @Query doesn't update dynamically
    let sortOption: SortOption
    
    init(searchText: Binding<String>, 
         displayMode: Binding<DepositDisplayMode>,
         sortOption: SortOption,
         selectedTagIDs: Set<UUID>,
         selectedBrandIDs: Set<UUID>,
         selectedTypes: Set<String>,
         selectedColors: Set<String>,
         selectedSizes: Set<String>,
         selectedLengths: Set<String>,
         selectedConditions: Set<String>,
         selectedAccessories: Set<String>) {
        _searchText = searchText
        _displayMode = displayMode
        let filter = #Predicate<Clothing> { $0.isDepositPlan == true && $0.isDeleted == false }
        // Use default sort since we'll apply sorting manually in updateBaseClothings
        _depositClothings = Query(filter: filter, sort: \Clothing.createdAt, order: .reverse)
        
        self.selectedTagIDs = selectedTagIDs
        self.selectedBrandIDs = selectedBrandIDs
        self.selectedTypes = selectedTypes
        self.selectedColors = selectedColors
        self.selectedSizes = selectedSizes
        self.selectedLengths = selectedLengths
        self.selectedConditions = selectedConditions
        self.selectedAccessories = selectedAccessories
        self.sortOption = sortOption
    }
    
    // Helper for splitting strings with support for both English and Chinese commas
    func splitValues(_ string: String) -> Set<String> {
        let normalized = string.replacingOccurrences(of: "，", with: ",")
        return Set(normalized.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }
    
    private func updateBaseClothings() {
        let result = depositClothings.filter { clothing in
            let matchesSearch: Bool
            if searchText.isEmpty {
                matchesSearch = true
            } else {
                matchesSearch = clothing.name.localizedCaseInsensitiveContains(searchText) ||
                (clothing.brand?.name.localizedCaseInsensitiveContains(searchText) ?? false)
            }
            
            let matchesTag: Bool
            if selectedTagIDs.isEmpty {
                matchesTag = true
            } else {
                let clothingTagIDs = Set(clothing.tags?.map { $0.id } ?? [])
                matchesTag = !selectedTagIDs.isDisjoint(with: clothingTagIDs)
            }
            
            let matchesBrand: Bool
            if selectedBrandIDs.isEmpty {
                matchesBrand = true
            } else {
                if let brand = clothing.brand {
                    matchesBrand = selectedBrandIDs.contains(brand.id)
                } else {
                    matchesBrand = false
                }
            }
            
            let matchesType: Bool = selectedTypes.isEmpty || !selectedTypes.isDisjoint(with: splitValues(clothing.types))
            
            let matchesColor: Bool = selectedColors.isEmpty || !selectedColors.isDisjoint(with: splitValues(clothing.colors))
            
            let matchesSize: Bool = selectedSizes.isEmpty || !selectedSizes.isDisjoint(with: splitValues(clothing.sizes))
            
            let matchesLength: Bool = selectedLengths.isEmpty || !selectedLengths.isDisjoint(with: splitValues(clothing.length))
            
            let matchesCondition: Bool = selectedConditions.isEmpty || !selectedConditions.isDisjoint(with: splitValues(clothing.condition))
            
            let matchesAccessory: Bool = selectedAccessories.isEmpty || !selectedAccessories.isDisjoint(with: splitValues(clothing.accessories))
            
            // Year Filter (Global)
            // Year logic: Based on finalPaymentDate (Start of final payment period)
            let matchesYear: Bool
            if let date = clothing.finalPaymentDate {
                let calendar = Calendar.current
                let year = calendar.component(.year, from: date)
                matchesYear = (year == selectedYear)
            } else {
                matchesYear = false
            }
            
            return matchesSearch && matchesTag && matchesBrand && matchesType && matchesColor && matchesSize && matchesLength && matchesCondition && matchesAccessory && matchesYear
        }
        
        // Apply sorting based on sortOption
        // Note: @Query doesn't update dynamically when sortOption changes,
        // so we need to sort here explicitly
        let sortedResult: [Clothing]
        switch sortOption {
        case .custom:
            sortedResult = result.sorted { $0.sortIndex < $1.sortIndex }
        case .priceAsc:
            sortedResult = result.sorted { $0.price < $1.price }
        case .priceDesc:
            sortedResult = result.sorted { $0.price > $1.price }
        case .nameAsc:
            sortedResult = result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameDesc:
            sortedResult = result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .purchaseDateAsc:
            sortedResult = result.sorted { $0.purchaseDate < $1.purchaseDate }
        case .purchaseDateDesc:
            sortedResult = result.sorted { $0.purchaseDate > $1.purchaseDate }
        case .createdAtDesc:
            sortedResult = result.sorted { $0.createdAt > $1.createdAt }
        }
        
        self.baseClothings = sortedResult
        updateFilteredClothings()
    }
    
    private func updateFilteredClothings() {
        let result = baseClothings.filter { clothing in
            if viewMode == .monthly {
                if selectedMonths.isEmpty {
                    return true
                } else {
                    if let date = clothing.finalPaymentDate {
                        let month = Calendar.current.component(.month, from: date)
                        return selectedMonths.contains(month)
                    }
                    return false
                }
            } else {
                // Series Mode
                if selectedSeries.isEmpty {
                    return true
                } else {
                    return selectedSeries.contains { seriesPrefix in
                        let sanitizedName = SeriesAnalyzer.shared.sanitize(clothing.name).lowercased()
                        let prefix = seriesPrefix.lowercased()
                        return sanitizedName.hasPrefix(prefix)
                    }
                }
            }
        }
        self.filteredClothings = result
    }
    
    // 计算所有代付尾款（不受年份筛选影响）
    private var totalPendingBalanceAll: Decimal {
        depositClothings.reduce(0) { $0 + ($1.totalBalance * Decimal($1.stock)) }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 总代付尾款统计（最顶部）
                TotalBalanceCard(
                    totalBalance: totalPendingBalanceAll,
                    isVisible: showStats,
                    onToggleVisibility: {
                        if !showStats {
                            // 要显示时，先弹出确认框
                            showConfirmDialog = true
                        } else {
                            withAnimation {
                                showStats = false
                            }
                        }
                    },
                    onCountMoney: {
                        self.moneyCountingState = MoneyCountingState(amount: totalPendingBalanceAll)
                    }
                )
                .padding(.horizontal)
                
                // View Mode Switcher
                Picker("视图模式", selection: $viewMode) {
                    Text("按月视图").tag(DepositViewMode.monthly)
                    Text("按系列视图").tag(DepositViewMode.series)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: viewMode) { oldValue, newValue in
                    updateFilteredClothings()
                    if newValue == .series && seriesList.isEmpty {
                        analyzeSeries()
                    }
                }
                .task {
                    // Initial load
                    updateBaseClothings()
                    if viewMode == .series && seriesList.isEmpty {
                        analyzeSeries()
                    }
                }
                .onChange(of: depositClothings) { oldValue, newValue in
                    updateBaseClothings()
                    if viewMode == .series {
                        analyzeSeries()
                    }
                }
                // Re-analyze series if year changes
                .onChange(of: selectedYear) { oldValue, newValue in
                    updateBaseClothings()
                    if viewMode == .series {
                        analyzeSeries()
                    }
                    // Clear selections when year changes to avoid confusion
                    selectedMonths.removeAll()
                    selectedSeries.removeAll()
                }
                // Filter triggers
                .onChange(of: searchText) { updateBaseClothings() }
                .onChange(of: selectedTagIDs) { updateBaseClothings() }
                .onChange(of: selectedBrandIDs) { updateBaseClothings() }
                .onChange(of: selectedTypes) { updateBaseClothings() }
                .onChange(of: selectedColors) { updateBaseClothings() }
                .onChange(of: selectedSizes) { updateBaseClothings() }
                .onChange(of: selectedLengths) { updateBaseClothings() }
                .onChange(of: selectedConditions) { updateBaseClothings() }
                .onChange(of: selectedAccessories) { updateBaseClothings() }
                .onChange(of: selectedMonths) { updateFilteredClothings() }
                .onChange(of: selectedSeries) { updateFilteredClothings() }
                
                // Selector Area
                if viewMode == .monthly {
                    // Pass filtered clothings (base) so it knows what months have data?
                    // Or pass baseClothings to calculate stats for each month
                    MonthSelectorView(
                        selectedMonths: $selectedMonths,
                        year: $selectedYear,
                        clothings: baseClothings,
                        showYearStats: $showYearStats
                    )
                    .padding(.horizontal)
                } else {
                    SeriesSelectorView(
                        selectedSeries: $selectedSeries,
                        year: $selectedYear,
                        seriesList: seriesList,
                        isAnalyzing: isAnalyzing,
                        showYearStats: $showYearStats
                    )
                    .padding(.horizontal)
                }
                
                // List
                LazyVStack(spacing: 16) {
                    ForEach(filteredClothings) { clothing in
                        NavigationLink {
                            ClothingDetailView(clothing: clothing)
                        } label: {
                            if displayMode == .simple {
                                SimpleDepositItemRow(clothing: clothing)
                            } else {
                                DepositItemRow(clothing: clothing)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 100)
            }
            .padding(.top, 10)
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(item: $moneyCountingState) { state in
            MoneyCountingView(
                amount: state.amount,
                denomination: Denomination(value: 100, color: Color(hex: "D93842"), name: "100"),
                currency: .rmb,
                onComplete: {
                    moneyCountingState = nil
                },
                onSkip: {
                    moneyCountingState = nil
                }
            )
        }
        .alert("真的要看吗？你确定？", isPresented: $showConfirmDialog) {
            Button("取消", role: .cancel) { }
            Button("我准备好了！", role: .none) {
                withAnimation {
                    showStats = true
                }
            }
        } message: {
            Text("(๑°o°๑) 前方高能预警！\n准备好面对尾款的暴击了吗？\n记得深呼吸哦~ ✧*｡٩(ˊᗜˋ*)و✧*｡")
        }
    }
    
    private func analyzeSeries() {
        isAnalyzing = true
        // Analyze based on the YEAR filtered clothings
        let clothingsToAnalyze = baseClothings
        
        Task {
            let series = await SeriesAnalyzer.shared.analyzeSeries(from: clothingsToAnalyze)
            await MainActor.run {
                self.seriesList = series
                self.isAnalyzing = false
            }
        }
    }
}

// MARK: - 总代付尾款卡片
struct TotalBalanceCard: View {
    let totalBalance: Decimal
    let isVisible: Bool
    let onToggleVisibility: () -> Void
    let onCountMoney: () -> Void
    
    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // 三个功能入口（放在最上方）
            HStack(spacing: 0) {
                // 梦裙日历
                Button {
                    tabNavigationManager.navigate(to: .smallWorld(.calendar))
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 16))
                        Text("梦裙日历")
                            .font(.caption)
                    }
                    .foregroundStyle(.pink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                Divider()
                    .frame(height: 30)
                
                // 马上来财
                Button {
                    tabNavigationManager.navigate(to: .smallWorld(.wealth))
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle")
                            .font(.system(size: 16))
                        Text("马上来财")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                Divider()
                    .frame(height: 30)
                
                // 裙子股市
                Button {
                    tabNavigationManager.navigate(to: .smallWorld(.bigWorld))
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 16))
                        Text("裙子股市")
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
            
            // 分割线
            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            
            // 标题和按钮（始终显示）
            HStack {
                Text("总待付尾款")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // 小眼睛按钮
                Button(action: onToggleVisibility) {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .font(.system(size: 16))
                        .foregroundStyle(.pink)
                        .frame(width: 32, height: 32)
                        .background(Color.pink.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                // 数钱按钮（仅显示时）
                if isVisible {
                    Button(action: onCountMoney) {
                        Image(systemName: "banknote")
                            .font(.system(size: 16))
                            .foregroundStyle(.green)
                            .frame(width: 32, height: 32)
                            .background(Color.green.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            
            // 金额显示（仅显示时）
            if isVisible {
                Button(action: onCountMoney) {
                    Text("¥\(NSDecimalNumber(decimal: totalBalance).stringValue)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Color(hex: "C94C72"))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.bottom, 12)
            } else {
                // 隐藏状态只保留底部间距
                Spacer()
                    .frame(height: 8)
            }

        }
        .background(CardBackgroundView(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct DepositStatsView: View {
    let clothings: [Clothing]
    var onCountMoney: ((Decimal) -> Void)? = nil
    
    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    
    // Deduplicated clothings based on name, deposit, balance for Style Count
    // We ignore stock for style counting
    private var uniqueStyles: [Clothing] {
        var seenKeys: Set<String> = []
        var result: [Clothing] = []
        
        for clothing in clothings {
            // Style defined by Name + Price info
            let key = "\(clothing.name)|\(clothing.deposit)|\(clothing.balance)"
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                result.append(clothing)
            }
        }
        return result
    }
    
    var styleCount: Int {
        uniqueStyles.count
    }
    
    var totalCount: Int {
        // Sum of stock of ALL clothings (Inventory Count)
        clothings.reduce(0) { $0 + $1.stock }
    }
    
    var paidDeposit: Decimal {
        // Sum of deposit * stock for ALL clothings (Include accessories)
        clothings.reduce(0) { $0 + ($1.totalDeposit * Decimal($1.stock)) }
    }
    
    var pendingBalance: Decimal {
        // Sum of balance * stock for ALL clothings (Include accessories)
        clothings.reduce(0) { $0 + ($1.totalBalance * Decimal($1.stock)) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statItem(title: "总件数/款", value: "\(totalCount)/\(styleCount)")
                
                Divider()
                    .frame(height: 30)
                
                statItem(title: "已付定金", value: "¥\(NSDecimalNumber(decimal: paidDeposit).stringValue)", valueColor: Color(hex: "FF9800"))
                
                Divider()
                    .frame(height: 30)
                
                Button {
                    onCountMoney?(pendingBalance)
                } label: {
                    statItem(title: "待付尾款", value: "¥\(NSDecimalNumber(decimal: pendingBalance).stringValue)", showIcon: true)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .background(CardBackgroundView(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func statItem(title: String, value: String, valueColor: Color = .primary, showIcon: Bool = false) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if showIcon {
                    Image(systemName: "banknote")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity)
    }
}

struct YearSelectorView: View {
    @Binding var year: Int
    
    var body: some View {
        HStack {
            Button {
                withAnimation {
                    year -= 1
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text("\(String(year))年")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .monospacedDigit()
            
            Spacer()
            
            Button {
                withAnimation {
                    year += 1
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(
            CardBackgroundView(cornerRadius: 16)
        )
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct MonthSelectorView: View {
    @Binding var selectedMonths: Set<Int>
    @Binding var year: Int
    let clothings: [Clothing] // Pass in all deposit clothings to calculate monthly stats
    @Binding var showYearStats: Bool
    @State private var expanded: Bool = true
    
    let months = Array(1...12)
    let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    
    // Calculate stats for a specific month
    private func statsForMonth(_ month: Int) -> (count: Int, amount: Decimal) {
        let calendar = Calendar.current
        let monthlyClothings = clothings.filter { clothing in
            guard let date = clothing.finalPaymentDate else { return false }
            // Year is already filtered in baseClothings, but double check doesn't hurt
            // Actually baseClothings already filtered by year, so we just check month
            let m = calendar.component(.month, from: date)
            return m == month
        }
        
        // Count Items (Stock Sum) and Total Amount (Balance Sum)
        // No deduplication for totals
        let itemCount = monthlyClothings.reduce(0) { $0 + $1.stock }
        let amount = monthlyClothings.reduce(0) { $0 + ($1.totalBalance * Decimal($1.stock)) }
        return (itemCount, amount)
    }
    
    // 计算年份统计
    private var yearStats: (totalCount: Int, styleCount: Int, paidDeposit: Decimal, pendingBalance: Decimal) {
        // 去重计算款数
        var seenKeys: Set<String> = []
        var uniqueStyles: [Clothing] = []
        
        for clothing in clothings {
            let key = "\(clothing.name)|\(clothing.deposit)|\(clothing.balance)"
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                uniqueStyles.append(clothing)
            }
        }
        
        let totalCount = clothings.reduce(0) { $0 + $1.stock }
        let styleCount = uniqueStyles.count
        let paidDeposit = clothings.reduce(0) { $0 + ($1.totalDeposit * Decimal($1.stock)) }
        let pendingBalance = clothings.reduce(0) { $0 + ($1.totalBalance * Decimal($1.stock)) }
        
        return (totalCount, styleCount, paidDeposit, pendingBalance)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            Button {
                withAnimation {
                    expanded.toggle()
                }
            } label: {
                HStack {
                    Text("按月预估尾款")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if expanded {
                // Year Selector
                YearSelectorView(year: $year)
                
                // 年份统计（受年份控制，放在年份下面，带独立小眼睛控制）
                YearStatsCard(
                    stats: yearStats,
                    year: year,
                    isVisible: showYearStats,
                    onToggleVisibility: { showYearStats.toggle() }
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
                            .background {
                                if isSelected {
                                    Color.brown
                                } else {
                                    CardBackgroundView(cornerRadius: 12)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: isSelected ? 0 : 1)
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 年份统计卡片
struct YearStatsCard: View {
    let stats: (totalCount: Int, styleCount: Int, paidDeposit: Decimal, pendingBalance: Decimal)
    let year: Int
    var isVisible: Bool = true
    var onToggleVisibility: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 8) {
            // 标题提示和小眼睛按钮
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(year)年统计")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // 小眼睛按钮（独立控制）
                if let onToggle = onToggleVisibility {
                    Button(action: onToggle) {
                        Image(systemName: isVisible ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundStyle(.pink)
                            .frame(width: 24, height: 24)
                            .background(Color.pink.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            // 统计内容（可折叠）
            if isVisible {
                HStack(spacing: 0) {
                    DepositStatItem(title: "总件数/款", value: "\(stats.totalCount)/\(stats.styleCount)")
                    
                    Divider()
                        .frame(height: 30)
                    
                    DepositStatItem(title: "已付定金", value: "¥\(NSDecimalNumber(decimal: stats.paidDeposit).stringValue)", valueColor: Color(hex: "FF9800"))
                    
                    Divider()
                        .frame(height: 30)
                    
                    DepositStatItem(title: "代付尾款", value: "¥\(NSDecimalNumber(decimal: stats.pendingBalance).stringValue)", valueColor: Color(hex: "C94C72"))
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                // 隐藏状态显示提示
                HStack {
                    Spacer()
                    Text("点击眼睛查看统计")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.6))
                    Spacer()
                }
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .background(CardBackgroundView(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

struct DepositStatItem: View {
    let title: String
    let value: String
    var valueColor: Color = .primary
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

struct SeriesSelectorView: View {
    @Binding var selectedSeries: Set<String>
    @Binding var year: Int
    let seriesList: [SeriesInfo]
    let isAnalyzing: Bool
    @Binding var showYearStats: Bool
    @State private var expanded: Bool = true
    @State private var showTips: Bool = false
    
    // Adaptive grid columns
    let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)]
    
    // 计算系列视图的年份统计
    private var yearStats: (totalCount: Int, styleCount: Int, paidDeposit: Decimal, pendingBalance: Decimal) {
        // 从seriesList计算总计
        let totalCount = seriesList.reduce(0) { $0 + $1.itemCount }
        let styleCount = seriesList.count
        let paidDeposit = seriesList.reduce(0) { $0 + $1.totalDeposit }
        let pendingBalance = seriesList.reduce(0) { $0 + $1.totalBalance }
        
        return (totalCount, styleCount, paidDeposit, pendingBalance)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            Button {
                withAnimation {
                    expanded.toggle()
                }
            } label: {
                HStack {
                    Text("按系列预估尾款")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    
                    // Tips Icon
                    Button {
                        showTips = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .alert("系列分类规则", isPresented: $showTips) {
                        Button("知道了", role: .cancel) { }
                    } message: {
                        Text("系统会自动根据商品名称的前2-4个字（去除特殊符号）作为系列前缀进行归类。\n\n例如：\n“少女心愿 连衣裙”\n“少女心愿 半裙”\n\n都会被归类为 “Pink” 系列。\n注：同名属于同一款商品。")
                    }
                    
                    if isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 8)
                    }
                    
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if expanded {
                // Year Selector
                YearSelectorView(year: $year)
                
                // 年份统计（受年份控制，放在年份下面，带独立小眼睛控制）
                YearStatsCard(
                    stats: yearStats,
                    year: year,
                    isVisible: showYearStats,
                    onToggleVisibility: { showYearStats.toggle() }
                )
                
                if seriesList.isEmpty {
                    if isAnalyzing {
                        Text("正在分析系列...")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        Text("暂无系列数据")
                            .foregroundStyle(.secondary)
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
                                            Spacer()
                                            Text("\(series.itemCount)")
                                                .font(.system(size: 9))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 4)
                                                .background(Color.black.opacity(0.1))
                                                .clipShape(Capsule())
                                        }
                                        .foregroundStyle(isSelected ? .white : .primary)
                                        
                                        Text("¥\(NSDecimalNumber(decimal: series.totalBalance).stringValue)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(isSelected ? .white.opacity(0.9) : (series.totalBalance > 0 ? .orange : .secondary.opacity(0.7)))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .padding(8)
                                    .background {
                                        if isSelected {
                                            Color.brown
                                        } else {
                                            CardBackgroundView(cornerRadius: 8)
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
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
            }
        }
    }
}
