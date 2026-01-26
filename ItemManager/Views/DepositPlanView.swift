//
//  DepositPlanView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import SwiftData

enum DepositViewMode {
    case monthly
    case series
}

struct DepositPlanView: View {
    @Binding var searchText: String
    @Query private var depositClothings: [Clothing]
    
    @State private var viewMode: DepositViewMode = .monthly
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonths: Set<Int> = []
    @State private var selectedSeries: Set<String> = []
    @State private var seriesList: [SeriesInfo] = []
    @State private var isAnalyzing: Bool = false
    @State private var showStats = true
    
    @State private var filteredClothings: [Clothing] = []
    @State private var baseClothings: [Clothing] = []
    
    // Money Counting Animation State
    struct MoneyCountingState: Identifiable {
        let id = UUID()
        let amount: Decimal
    }
    
    @State private var moneyCountingState: MoneyCountingState?
    
    // Filter properties
    let selectedTagIDs: Set<UUID>
    let selectedBrandIDs: Set<UUID>
    let selectedTypes: Set<String>
    let selectedColors: Set<String>
    let selectedSizes: Set<String>
    let selectedLengths: Set<String>
    let selectedConditions: Set<String>
    let selectedAccessories: Set<String>
    
    init(searchText: Binding<String>, 
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
        let filter = #Predicate<Clothing> { $0.isDepositPlan == true }
        _depositClothings = Query(filter: filter, sort: sortOption.sortDescriptors)
        
        self.selectedTagIDs = selectedTagIDs
        self.selectedBrandIDs = selectedBrandIDs
        self.selectedTypes = selectedTypes
        self.selectedColors = selectedColors
        self.selectedSizes = selectedSizes
        self.selectedLengths = selectedLengths
        self.selectedConditions = selectedConditions
        self.selectedAccessories = selectedAccessories
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
        
        self.baseClothings = result
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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
                
                // Stats Section
                VStack(spacing: 8) {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation {
                                showStats.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(showStats ? "隐藏统计" : "显示统计")
                                Image(systemName: showStats ? "chevron.up" : "chevron.down")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    
                    if showStats {
                        DepositStatsView(clothings: filteredClothings) { amount in
                            self.moneyCountingState = MoneyCountingState(amount: amount)
                        }
                            .padding(.horizontal)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                
                // Selector Area
                if viewMode == .monthly {
                    // Pass filtered clothings (base) so it knows what months have data?
                    // Or pass baseClothings to calculate stats for each month
                    MonthSelectorView(selectedMonths: $selectedMonths, year: $selectedYear, clothings: baseClothings)
                        .padding(.horizontal)
                } else {
                    SeriesSelectorView(selectedSeries: $selectedSeries, year: $selectedYear, seriesList: seriesList, isAnalyzing: isAnalyzing)
                        .padding(.horizontal)
                }
                
                // List
                LazyVStack(spacing: 16) {
                    ForEach(filteredClothings) { clothing in
                        NavigationLink {
                            ClothingDetailView(clothing: clothing)
                        } label: {
                            DepositItemRow(clothing: clothing)
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

struct DepositStatsView: View {
    let clothings: [Clothing]
    var onCountMoney: ((Decimal) -> Void)? = nil
    
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
        // Sum of deposit * stock for ALL clothings
        clothings.reduce(0) { $0 + ($1.deposit * Decimal($1.stock)) }
    }
    
    var pendingBalance: Decimal {
        // Sum of balance * stock for ALL clothings
        clothings.reduce(0) { $0 + ($1.balance * Decimal($1.stock)) }
    }
    
    var body: some View {
        GlassCard {
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
        }
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
            GlassCard(cornerRadius: 16) {
                Color.clear // Placeholder content for GlassCard
            }
        )
    }
}

struct MonthSelectorView: View {
    @Binding var selectedMonths: Set<Int>
    @Binding var year: Int
    let clothings: [Clothing] // Pass in all deposit clothings to calculate monthly stats
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
        let amount = monthlyClothings.reduce(0) { $0 + ($1.balance * Decimal($1.stock)) }
        return (itemCount, amount)
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
                            .background(isSelected ? Color.brown : Color(uiColor: .secondarySystemGroupedBackground))
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

struct SeriesSelectorView: View {
    @Binding var selectedSeries: Set<String>
    @Binding var year: Int
    let seriesList: [SeriesInfo]
    let isAnalyzing: Bool
    @State private var expanded: Bool = true
    @State private var showTips: Bool = false
    
    // Adaptive grid columns
    let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)]
    
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
                        Text("系统会自动根据商品名称的前2-4个字（去除特殊符号）作为系列前缀进行归类。\n\n例如：\n“Pink House 连衣裙”\n“Pink House 半裙”\n\n都会被归类为 “Pink” 系列。\n注：同名属于同一款商品。")
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
                                    .background(isSelected ? Color.brown : Color(uiColor: .secondarySystemGroupedBackground))
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
