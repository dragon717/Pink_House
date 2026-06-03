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

    var localizedTitle: String {
        rawValue.appLocalized
    }

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
    @Environment(\.modelContext) private var modelContext
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
    @State private var isMonthSelectorExpanded: Bool = false // 默认折叠，显示最近月份
    @State private var isSeriesSelectorExpanded: Bool = true // 默认展开，显示系列
    
    @State private var filteredClothings: [Clothing] = []
    @State private var baseClothings: [Clothing] = []
    @State private var monthSelectorSummary = DepositMonthSelectorSummary()
    @State private var recentAddedStats = DepositRecentAddedStats()
    @State private var seriesAnalysisTask: Task<Void, Never>?
    
    // Money Counting Animation State
    struct MoneyCountingState: Identifiable {
        let id = UUID()
        let amount: Decimal
    }
    
    @State private var moneyCountingState: MoneyCountingState?
    
    // 显示确认弹窗
    @State private var showConfirmDialog = false

    private var isFloatingPetTransactionActive: Bool {
        moneyCountingState != nil
    }

    private var isFloatingPetPresentationActive: Bool {
        showConfirmDialog
    }
    
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
        // 避免 isDeleted 和 deletedAt 不一致导致的数据问题。全款预约仍复用 isDepositPlan 存储，
        // 后续用 isFinalPaymentPlan 收窄为真正的定金尾款。
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
    
    private var finalPaymentClothings: [Clothing] {
        depositClothings.filter { $0.isFinalPaymentPlan }
    }

    private var finalPaymentRefreshToken: String {
        depositClothings
            .map { clothing in
                [
                    clothing.id.uuidString,
                    clothing.isFinalPaymentPlan ? "final" : "non-final",
                    clothing.reservationKind.rawValue,
                    clothing.name,
                    clothing.condition,
                    String(clothing.stock),
                    Self.decimalToken(clothing.deposit),
                    Self.decimalToken(clothing.balance),
                    Self.decimalToken(clothing.totalBalance),
                    Self.dateToken(clothing.depositDate),
                    Self.dateToken(clothing.finalPaymentDate),
                    Self.dateToken(clothing.finalPaymentEndDate),
                    Self.dateToken(clothing.updatedAt),
                    Self.dateToken(clothing.lastModified),
                    Self.dateToken(clothing.deletedAt)
                ].joined(separator: "|")
            }
            .sorted()
            .joined(separator: "||")
    }

    private var filterRefreshToken: String {
        [
            searchText,
            sortOption.rawValue,
            selectedTagIDs.map(\.uuidString).sorted().joined(separator: ","),
            selectedBrandIDs.map(\.uuidString).sorted().joined(separator: ","),
            selectedTypes.sorted().joined(separator: ","),
            selectedColors.sorted().joined(separator: ","),
            selectedSizes.sorted().joined(separator: ","),
            selectedLengths.sorted().joined(separator: ","),
            selectedConditions.sorted().joined(separator: ","),
            selectedAccessories.sorted().joined(separator: ",")
        ].joined(separator: "|")
    }

    private static func decimalToken(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static func dateToken(_ value: Date?) -> String {
        value.map { String($0.timeIntervalSince1970) } ?? "nil"
    }

    private func refreshDepositData(reanalyzeSeries: Bool) {
        updateBaseClothings()
        if reanalyzeSeries {
            analyzeSeries()
        }
    }

    private func handleInitialLoad() {
        updateBaseClothings()
        if viewMode == .series && seriesList.isEmpty {
            analyzeSeries()
        }
    }

    private func handleDepositDataChanged() {
        refreshDepositData(reanalyzeSeries: viewMode == .series)
    }

    private func handleYearChanged() {
        updateBaseClothings()
        if viewMode == .series {
            analyzeSeries()
        }
        // Clear selections when year changes to avoid confusion
        selectedMonths.removeAll()
        selectedSeries.removeAll()
    }

    private func handleDisappear() {
        seriesAnalysisTask?.cancel()
        seriesAnalysisTask = nil
        isAnalyzing = false
    }

    private func updateBaseClothings() {
        let interval = PerformanceSignpost.depositUpdate(count: depositClothings.count, reason: "updateBaseClothings")
        defer {
            PerformanceSignpost.end(interval, detail: "base=\(baseClothings.count) filtered=\(filteredClothings.count)")
        }

        WealthSavingLedger.reconcilePaidFinalPaymentsIfNeededForView(
            context: modelContext,
            reason: "DepositPlanView"
        )

        // 使用 ClothingSearchService 进行搜索
        let searchService = ClothingSearchService(clothings: finalPaymentClothings)
        let searchResults = searchService.search(query: searchText)
        
        // 如果没有搜索词，返回所有衣物
        let baseResults = searchText.isEmpty ? finalPaymentClothings : searchResults
        
        // 使用统一的筛选服务（不包含年份筛选）
        let config = ClothingFilterService.FilterConfig(
            selectedTagIDs: selectedTagIDs,
            selectedBrandIDs: selectedBrandIDs,
            selectedTypes: selectedTypes,
            selectedColors: selectedColors,
            selectedSizes: selectedSizes,
            selectedLengths: selectedLengths,
            selectedConditions: selectedConditions,
            selectedAccessories: selectedAccessories,
            depositStatusFilter: .all // 心愿尾款视图已收窄为真正的定金尾款
        )
        
        let filtered = ClothingFilterService.filter(baseResults, config: config)
        
        // 应用年份筛选
        let result = filtered.filter { clothing in
            // Year Filter (Global)
            // 定金尾款按尾款开始日期，全款预约按预约日期归组
            if let date = clothing.reservationGroupingDate {
                let calendar = Calendar.current
                let year = calendar.component(.year, from: date)
                return year == selectedYear
            } else {
                return false
            }
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
        self.monthSelectorSummary = DepositMonthSelectorSummary(clothings: sortedResult)
        self.recentAddedStats = DepositRecentAddedStats(clothings: sortedResult)
        updateFilteredClothings()
    }
    
    private func updateFilteredClothings() {
        let calendar = Calendar.current
        let collapsedRecentMonth = monthSelectorSummary.recentMonth
        let selectedMonthsForFilter = selectedMonths
        let selectedSeriesForFilter = selectedSeries
        let isMonthlyMode = viewMode == .monthly
        let isMonthExpanded = isMonthSelectorExpanded
        let isSeriesExpanded = isSeriesSelectorExpanded
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: Date())

        let result = baseClothings.filter { clothing in
            if isMonthlyMode {
                // 月份视图
                guard let start = clothing.reservationGroupingDate else { return false }
                let month = calendar.component(.month, from: start)

                if !isMonthExpanded {
                    // 面板折叠时，显示最近月份
                    return month == collapsedRecentMonth
                }
                if selectedMonthsForFilter.isEmpty {
                    // 面板展开且未选中月份：显示全年
                    return true
                } else {
                    // 有选中月份时，只显示选中的月份
                    return selectedMonthsForFilter.contains(month)
                }
            } else {
                // Series Mode
                if !isSeriesExpanded {
                    // 面板隐藏时，显示最近添加（一个月内）
                    guard let oneMonthAgo else { return false }
                    return clothing.createdAt >= oneMonthAgo
                }
                if selectedSeriesForFilter.isEmpty {
                    // 面板展开且未选中系列：显示全部系列
                    return true
                } else {
                    // 有选中系列时，只显示选中的系列
                    return selectedSeriesForFilter.contains { seriesPrefix in
                        let sanitizedName = SeriesAnalyzer.shared.sanitize(clothing.name).lowercased()
                        let prefix = seriesPrefix.lowercased()
                        return sanitizedName.hasPrefix(prefix)
                    }
                }
            }
        }
        self.filteredClothings = result
    }
    
    // 计算所有待付尾款（不受年份筛选影响）
    private var totalPendingBalanceAll: Decimal {
        finalPaymentClothings.reduce(0) { $0 + $1.pendingFinalPaymentAmount }
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
                    summary: monthSelectorSummary,
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
                    recentAddedStats: recentAddedStats,
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
        lifecycleContent
    }

    private var scrollContent: some View {
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
    }

    private var presentedContent: some View {
        scrollContent
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
        .floatingPetHidden(.transactionFlow, isActive: isFloatingPetTransactionActive)
        .floatingPetHidden(.presentationActive, isActive: isFloatingPetPresentationActive)
    }

    private var lifecycleContent: some View {
        presentedContent
        .task {
            handleInitialLoad()
        }
        .onDisappear {
            handleDisappear()
        }
        .onChange(of: finalPaymentRefreshToken) { oldValue, newValue in
            handleDepositDataChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .depositPlanDataDidChange)) { _ in
            handleDepositDataChanged()
        }
        .onChange(of: selectedYear) { oldValue, newValue in
            handleYearChanged()
        }
        .onChange(of: filterRefreshToken) { oldValue, newValue in
            updateBaseClothings()
        }
    }

    private func analyzeSeries() {
        isAnalyzing = true
        // Analyze based on the YEAR filtered clothings
        let clothingsToAnalyze = baseClothings

        seriesAnalysisTask?.cancel()
        seriesAnalysisTask = Task {
            let series = await SeriesAnalyzer.shared.analyzeSeries(from: clothingsToAnalyze)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.seriesList = series
                let validSeriesNames = Set(series.map(\.name))
                self.selectedSeries.formIntersection(validSeriesNames)
                self.updateFilteredClothings()
                self.isAnalyzing = false
                self.seriesAnalysisTask = nil
            }
        }
    }
}

extension Notification.Name {
    static let depositPlanDataDidChange = Notification.Name("depositPlanDataDidChange")
}
