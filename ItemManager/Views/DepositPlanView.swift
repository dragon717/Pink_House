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
    
    var filteredClothings: [Clothing] {
        depositClothings.filter { clothing in
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
            
            // Time Filter / Series Filter
            let matchesTimeOrSeries: Bool
            
            if viewMode == .monthly {
                if let date = clothing.finalPaymentDate {
                    let calendar = Calendar.current
                    let year = calendar.component(.year, from: date)
                    let month = calendar.component(.month, from: date)
                    
                    if year != selectedYear {
                        matchesTimeOrSeries = false
                    } else {
                        if selectedMonths.isEmpty {
                            matchesTimeOrSeries = true
                        } else {
                            matchesTimeOrSeries = selectedMonths.contains(month)
                        }
                    }
                } else {
                    // If no date is set, show it only if we're not filtering by specific months
                    matchesTimeOrSeries = false
                }
            } else {
                // Series Mode
                if selectedSeries.isEmpty {
                    matchesTimeOrSeries = true
                } else {
                    matchesTimeOrSeries = selectedSeries.contains { seriesName in
                        clothing.name.localizedCaseInsensitiveContains(seriesName)
                    }
                }
            }
            
            return matchesSearch && matchesTag && matchesBrand && matchesType && matchesColor && matchesSize && matchesLength && matchesCondition && matchesAccessory && matchesTimeOrSeries
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // View Mode Switcher
            Picker("视图模式", selection: $viewMode) {
                Text("按月视图").tag(DepositViewMode.monthly)
                Text("按系列视图").tag(DepositViewMode.series)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: viewMode) { oldValue, newValue in
                if newValue == .series && seriesList.isEmpty {
                    analyzeSeries()
                }
            }
            .task {
                // Initial analysis if needed, or wait for switch
                if viewMode == .series && seriesList.isEmpty {
                    analyzeSeries()
                }
            }
            .onChange(of: depositClothings) { oldValue, newValue in
                if viewMode == .series {
                    analyzeSeries()
                }
            }
            
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
                    DepositStatsView(clothings: filteredClothings)
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            
            // Selector Area
            if viewMode == .monthly {
                MonthSelectorView(year: $selectedYear, selectedMonths: $selectedMonths, clothings: depositClothings)
                    .padding(.horizontal)
            } else {
                SeriesSelectorView(selectedSeries: $selectedSeries, seriesList: seriesList, isAnalyzing: isAnalyzing)
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
    
    private func analyzeSeries() {
        isAnalyzing = true
        Task {
            let series = await SeriesAnalyzer.shared.analyzeSeries(from: depositClothings)
            await MainActor.run {
                self.seriesList = series
                self.isAnalyzing = false
            }
        }
    }
}

struct DepositStatsView: View {
    let clothings: [Clothing]
    
    var styleCount: Int {
        clothings.count
    }
    
    var totalCount: Int {
        clothings.reduce(0) { $0 + $1.stock }
    }
    
    var paidDeposit: Decimal {
        clothings.reduce(0) { $0 + ($1.deposit * Decimal($1.stock)) }
    }
    
    var pendingBalance: Decimal {
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
                
                statItem(title: "待付尾款", value: "¥\(NSDecimalNumber(decimal: pendingBalance).stringValue)")
            }
        }
    }
    
    private func statItem(title: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MonthSelectorView: View {
    @Binding var year: Int
    @Binding var selectedMonths: Set<Int>
    let clothings: [Clothing] // Pass in all deposit clothings to calculate monthly stats
    @State private var expanded: Bool = true
    
    let months = Array(1...12)
    let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    
    // Calculate stats for a specific month
    private func statsForMonth(_ month: Int) -> (count: Int, amount: Decimal) {
        let calendar = Calendar.current
        let monthlyClothings = clothings.filter { clothing in
            guard let date = clothing.finalPaymentDate else { return false }
            let y = calendar.component(.year, from: date)
            let m = calendar.component(.month, from: date)
            return y == year && m == month
        }
        
        let count = monthlyClothings.count
        let amount = monthlyClothings.reduce(0) { $0 + ($1.balance * Decimal($1.stock)) }
        return (count, amount)
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
                HStack {
                    Button {
                        year -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("\(String(year))年")
                        .font(.headline)
                        .frame(width: 80)
                    
                    Button {
                        year += 1
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                
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
                                Text("\(month)月")
                                    .font(.caption)
                                    .fontWeight(isSelected ? .bold : .regular)
                                    .foregroundStyle(isSelected ? .white : .primary)
                                
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
    let seriesList: [SeriesInfo]
    let isAnalyzing: Bool
    @State private var expanded: Bool = true
    
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
                                            Text("\(series.count)")
                                                .font(.system(size: 9))
                                                .padding(4)
                                                .background(Color.black.opacity(0.1))
                                                .clipShape(Circle())
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
