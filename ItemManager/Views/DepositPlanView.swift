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
    @Environment(ThemeManager.self) private var themeManager
    @Query private var depositClothings: [Clothing]
    
    @State private var viewMode: DepositViewMode = .monthly
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonths: Set<Int> = []
    @State private var selectedSeries: Set<String> = []
    @State private var seriesList: [SeriesInfo] = []
    @State private var isAnalyzing: Bool = false
    @State private var showStats = false // 默认隐藏总待付尾款统计
    @State private var showYearStats = false // 默认隐藏年份统计（独立控制）
    @State private var isMonthSelectorExpanded: Bool = true // 月份选择器展开状态
    @State private var isSeriesSelectorExpanded: Bool = true // 系列选择器展开状态
    
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
        // 统一使用 deletedAt == nil 作为未删除的判断条件，与衣橱列表保持一致
        // 避免 isDeleted 和 deletedAt 不一致导致的数据问题
        let filter = #Predicate<Clothing> { $0.isDepositPlan == true && $0.deletedAt == nil }
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
        let normalized = string.replacingOccurrences(of: ",", with: ",")
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
                // 月份视图
                if !isMonthSelectorExpanded {
                    // 面板隐藏时，显示当前月
                    return isClothingInCurrentMonth(clothing)
                }
                if selectedMonths.isEmpty {
                    // 面板展开且未选中月份：显示全年
                    return true
                } else {
                    // 有选中月份时，只显示选中的月份
                    return isClothingInSelectedMonths(clothing)
                }
            } else {
                // Series Mode
                if !isSeriesSelectorExpanded {
                    // 面板隐藏时，显示最近添加（一个月内）
                    return isClothingRecentlyAdded(clothing)
                }
                if selectedSeries.isEmpty {
                    // 面板展开且未选中系列：显示全部系列
                    return true
                } else {
                    // 有选中系列时，只显示选中的系列
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
    
    // 检查商品是否在当前月份（只判断预计尾款开始时间）
    private func isClothingInCurrentMonth(_ clothing: Clothing) -> Bool {
        guard let start = clothing.finalPaymentDate else { return false }
        let month = Calendar.current.component(.month, from: start)
        return month == currentMonth
    }

    // 检查商品是否在选中的月份（只判断预计尾款开始时间）
    private func isClothingInSelectedMonths(_ clothing: Clothing) -> Bool {
        guard let start = clothing.finalPaymentDate else { return false }
        let month = Calendar.current.component(.month, from: start)
        return selectedMonths.contains(month)
    }

    // 检查商品是否是最近添加（一个月内）
    private func isClothingRecentlyAdded(_ clothing: Clothing) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        guard let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) else {
            return false
        }
        return clothing.createdAt >= oneMonthAgo
    }
    
    // 计算所有待付尾款（不受年份筛选影响）
    private var totalPendingBalanceAll: Decimal {
        // 注意：totalBalance 已经包含了 stock 的乘法，所以这里直接使用，不要再乘 stock
        depositClothings.reduce(0) { $0 + $1.totalBalance }
    }
    
    // 计算当前月
    private var currentMonth: Int {
        Calendar.current.component(.month, from: Date())
    }

    // 视图模式选择器
    private var viewModePicker: some View {
        Picker("视图模式", selection: $viewMode) {
            Text("按月视图")
                .tag(DepositViewMode.monthly)
                .foregroundStyle(themeManager.primaryTextColor)
            Text("按系列视图")
                .tag(DepositViewMode.series)
                .foregroundStyle(themeManager.primaryTextColor)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .onChange(of: viewMode) { oldValue, newValue in
            updateFilteredClothings()
            if newValue == .series && seriesList.isEmpty {
                analyzeSeries()
            }
        }
    }

    // 选择器区域
    private var selectorArea: some View {
        Group {
            if viewMode == .monthly {
                MonthSelectorView(
                    selectedMonths: $selectedMonths,
                    year: $selectedYear,
                    clothings: baseClothings,
                    showYearStats: $showYearStats,
                    isExpanded: $isMonthSelectorExpanded
                )
                .padding(.horizontal)
            } else {
                SeriesSelectorView(
                    selectedSeries: $selectedSeries,
                    year: $selectedYear,
                    seriesList: seriesList,
                    isAnalyzing: isAnalyzing,
                    showYearStats: $showYearStats,
                    clothings: baseClothings,
                    isExpanded: $isSeriesSelectorExpanded
                )
                .padding(.horizontal)
            }
        }
        .onChange(of: selectedMonths) { updateFilteredClothings() }
        .onChange(of: selectedSeries) { updateFilteredClothings() }
        .onChange(of: isMonthSelectorExpanded) { updateFilteredClothings() }
        .onChange(of: isSeriesSelectorExpanded) { updateFilteredClothings() }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 总待付尾款统计（最顶部）
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
                viewModePicker

                // Selector Area
                selectorArea

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
        .alert("真的要解锁\"钱包瘦身\"副本吗？", isPresented: $showConfirmDialog) {
            Button("取消", role: .cancel) { }
            Button("我准备好了！", role: .none) {
                withAnimation {
                    showStats = true
                }
            }
        } message: {
            Text("⚠️ 前方尾款大军已集结！\n温馨提示：看完请抱紧你的钱包，深呼吸是没用的，不如默念\"美貌无价\"！\n(｡•́ω•̀｡)")
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
        .onChange(of: selectedYear) { oldValue, newValue in
            updateBaseClothings()
            if viewMode == .series {
                analyzeSeries()
            }
            // Clear selections when year changes to avoid confusion
            selectedMonths.removeAll()
            selectedSeries.removeAll()
        }
        .onChange(of: searchText) { updateBaseClothings() }
        .onChange(of: selectedTagIDs) { updateBaseClothings() }
        .onChange(of: selectedBrandIDs) { updateBaseClothings() }
        .onChange(of: selectedTypes) { updateBaseClothings() }
        .onChange(of: selectedColors) { updateBaseClothings() }
        .onChange(of: selectedSizes) { updateBaseClothings() }
        .onChange(of: selectedLengths) { updateBaseClothings() }
        .onChange(of: selectedConditions) { updateBaseClothings() }
        .onChange(of: selectedAccessories) { updateBaseClothings() }
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
