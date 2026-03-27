//
//  HomeView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI
import SwiftData

enum SortOption: String, CaseIterable, Identifiable {
    case createdAtDesc = "添加时间从晚到早"
    case priceAsc = "价格从低到高"
    case priceDesc = "价格从高到低"
    case purchaseDateAsc = "购买时间从早到晚"
    case purchaseDateDesc = "购买时间从晚到早"
    case nameAsc = "名称从A到Z"
    case nameDesc = "名称从Z到A"
    case custom = "自定义顺序"
    
    var id: String { rawValue }
    
    var sortDescriptors: [SortDescriptor<Clothing>] {
        switch self {
        case .createdAtDesc:
            return [SortDescriptor(\Clothing.createdAt, order: .reverse)]
        case .priceAsc:
            return [SortDescriptor(\Clothing.price, order: .forward)]
        case .priceDesc:
            return [SortDescriptor(\Clothing.price, order: .reverse)]
        case .purchaseDateAsc:
            return [SortDescriptor(\Clothing.purchaseDate, order: .forward)]
        case .purchaseDateDesc:
            return [SortDescriptor(\Clothing.purchaseDate, order: .reverse)]
        case .nameAsc:
            return [SortDescriptor(\Clothing.name, order: .forward)]
        case .nameDesc:
            return [SortDescriptor(\Clothing.name, order: .reverse)]
        case .custom:
            return [SortDescriptor(\Clothing.sortIndex, order: .forward)]
        }
    }
}

// Helper view for Calendar Day Icon compatibility
struct CalendarDayIcon: View {
    let day: Int
    
    var body: some View {
        if #available(iOS 26.0, *) {
            Image(systemName: "\(day).calendar")
        } else {
            Image(systemName: "calendar")
                .overlay {
                    Text("\(day)")
                        .font(.system(size: 10, weight: .bold))
                        .offset(y: 1)
                }
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) private var allClothings: [Clothing]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \Brand.name) private var brands: [Brand]
    @Query(filter: #Predicate<DepositNotificationRecord> { $0.isTriggered == true && $0.isRead == false }) private var unreadNotificationRecords: [DepositNotificationRecord]

    /// 未读通知数量（用于小红点显示）
    private var unreadNotificationCount: Int {
        unreadNotificationRecords.count
    }

    @Binding var selectedTab: HomeTab
    @State private var showingAddSheet = false
    @State private var showingBatchImportSheet = false
    @State private var isSelectionMode = false
    @State private var isEditing = false
    @State private var isSearchActive = false
    @AppStorage("UserPreference_SortOption") private var sortOption: SortOption = .createdAtDesc
    @AppStorage("UserPreference_WardrobeNavigationStyle") private var wardrobeNavigationStyle: WardrobeNavigationStyle = .classic
    @AppStorage("UserPreference_FilterMode") private var filterMode: FilterMode = .classic
    
    private var effectiveWardrobeNavigationStyle: WardrobeNavigationStyle {
        wardrobeNavigationStyle.resolvedForCurrentDevice
    }
    
    // Filter States
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var selectedBrandIDs: Set<UUID> = []
    @State private var selectedTypes: Set<String> = []
    @State private var selectedColors: Set<String> = []
    @State private var selectedSizes: Set<String> = []
    @State private var selectedLengths: Set<String> = []
    @State private var selectedConditions: Set<String> = []
    @State private var selectedAccessories: Set<String> = []
    
    // 特殊筛选值：用于表示"无标签"、"无品牌"等
    static let noTagUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let noBrandUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    
    // 字符串类型字段的"无"标记
    static let noTypeMarker = "__NO_TYPE__"
    static let noColorMarker = "__NO_COLOR__"
    static let noSizeMarker = "__NO_SIZE__"
    static let noLengthMarker = "__NO_LENGTH__"
    static let noConditionMarker = "__NO_CONDITION__"
    static let noAccessoryMarker = "__NO_ACCESSORY__"
    
    // For Wardrobe View
    @State private var wardrobeSearchText = ""
    @State private var showingMultiDimensionalFilterSheet = false
    @State private var depositStatusFilter: DepositStatusFilter = .all
    @State private var depositSearchText = ""
    @State private var showingDepositNotificationSheet = false
    @AppStorage("UserPreference_DepositDisplayMode") private var depositDisplayMode: DepositDisplayMode = .detail
    
    // View Layout Management
    enum ViewLayout: String, CaseIterable, Identifiable {
        case listBrief = "单行简略"
        case listDetailed = "单行详细"
        case grid2 = "双列"
        case grid3 = "三列"
        case grid6 = "六列"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .listBrief: return "list.bullet"
            case .listDetailed: return "list.bullet.rectangle.portrait"
            case .grid2: return "square.grid.2x2"
            case .grid3: return "square.grid.3x3"
            case .grid6: return "square.grid.3x2"
            }
        }
    }
    
    @AppStorage("UserPreference_ViewLayout") private var viewLayout: ViewLayout = .grid2
    @State private var showingCommunityImportAlert = false
    
    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared
    @ObservedObject private var networkManager = NetworkSettingsManager.shared

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Background
                LiquidBackground()
                    .ignoresSafeArea()
                
                // Content
                if selectedTab == .wardrobe {
                    WardrobeView(
                        searchText: $wardrobeSearchText,
                        isSelectionMode: $isSelectionMode,
                        isEditing: $isEditing,
                        sortOption: sortOption,
                        viewLayout: viewLayout,
                        selectedTagIDs: selectedTagIDs,
                        selectedBrandIDs: selectedBrandIDs,
                        selectedTypes: selectedTypes,
                        selectedColors: selectedColors,
                        selectedSizes: selectedSizes,
                        selectedLengths: selectedLengths,
                        selectedConditions: selectedConditions,
                        selectedAccessories: selectedAccessories,
                        depositStatusFilter: depositStatusFilter,
                        filterDescription: getFilterDescription(),
                        onClearFilter: clearAllFilters
                    )
                    // Force recreation when sortOption changes to ensure proper sorting
                    .id("wardrobe_\(sortOption.id)")
                } else {
                    DepositPlanView(
                        searchText: $depositSearchText,
                        displayMode: $depositDisplayMode,
                        sortOption: sortOption,
                        selectedTagIDs: selectedTagIDs,
                        selectedBrandIDs: selectedBrandIDs,
                        selectedTypes: selectedTypes,
                        selectedColors: selectedColors,
                        selectedSizes: selectedSizes,
                        selectedLengths: selectedLengths,
                        selectedConditions: selectedConditions,
                        selectedAccessories: selectedAccessories
                    )
                    // Force recreation when sortOption changes to ensure proper sorting
                    .id("deposit_\(sortOption.id)")
                }
            }
            .onChange(of: viewLayout) { _, _ in
                RewardManager.shared.triggerReward(type: .firstTimeFeature("ViewLayoutChange"))
            }
            .onChange(of: selectedTab) { _, _ in
                // 切换标签页时关闭搜索栏
                isSearchActive = false
            }
            .sheet(isPresented: $showingBatchImportSheet) {
                BatchImportView()
            }
            .onChange(of: showingBatchImportSheet) { _, newValue in
                if newValue {
                    NotificationCenter.default.post(name: .wardrobeBatchImportOpened, object: nil)
                }
            }
            .toolbar {
                if effectiveWardrobeNavigationStyle == .classic {
                    ToolbarItem(placement: .topBarLeading) {
                        tabSwitcher
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        classicActionButtons
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        fashionLeadingButtons
                    }

                    ToolbarItem(placement: .principal) {
                        fashionTabSwitcher
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        fashionTrailingButtons
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(magicPalette.navigationBackground.isDark ? .dark : .light, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .tint(magicPalette.accent)
            // 只在搜索激活时显示搜索栏，默认隐藏常驻搜索框
            .applySearchableIfNeeded(
                text: Binding(
                    get: { selectedTab == .wardrobe ? wardrobeSearchText : depositSearchText },
                    set: { newValue in
                        if selectedTab == .wardrobe {
                            wardrobeSearchText = newValue
                        } else {
                            depositSearchText = newValue
                        }
                    }
                ),
                isPresented: $isSearchActive,
                prompt: "搜索名称、品牌、标签、类型、颜色、尺码、价格范围等..."
            )
            .onAppear {
                // 确保初始状态下搜索栏不显示
                isSearchActive = false
                wardrobeNavigationStyle = WardrobeNavigationStyle.normalizeStoredPreference()
            }
            .sheet(isPresented: $showingAddSheet) {
                NavigationStack {
                    ClothingEditView(
                        clothing: nil,
                        initialBrandID: selectedBrandIDs.first,
                        initialTypes: selectedTypes,
                        continueFromDraft: continueFromDraft
                    )
                }
            }
            .onChange(of: showingAddSheet) { _, newValue in
                if newValue {
                    NotificationCenter.default.post(name: .wardrobeManualCreateOpened, object: nil)
                }
            }
            .onChange(of: isSelectionMode) { _, newValue in
                NotificationCenter.default.post(
                    name: .wardrobeSelectionModeChanged,
                    object: nil,
                    userInfo: ["isSelectionMode": newValue]
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .guideRequestWardrobeManualCreate)) { _ in
                guard selectedTab == .wardrobe else { return }
                continueFromDraft = false
                showingAddSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .guideRequestWardrobeBatchImport)) { _ in
                guard selectedTab == .wardrobe else { return }
                showingBatchImportSheet = true
            }
            .sheet(isPresented: $showingDepositNotificationSheet) {
                NavigationStack {
                    DepositNotificationView()
                }
            }
        }
    }
    
    private var tabSwitcher: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation {
                    selectedTab = .wardrobe
                }
            } label: {
                VStack(spacing: 2) {
                    Group {
                        if #available(iOS 18.0, *) {
                            Image(systemName: selectedTab == .wardrobe ? "cabinet" : "cabinet.fill")
                        } else {
                            Image(systemName: selectedTab == .wardrobe ? "tshirt" : "tshirt.fill")
                        }
                    }
                    .font(.system(size: 16))
                    Text("少女衣橱")
                        .font(.system(size: 10, weight: selectedTab == .wardrobe ? .bold : .medium))
                }
                .foregroundStyle(selectedTab == .wardrobe ? magicPalette.accent : magicPalette.secondaryText)
                .frame(height: 44) // Ensure touch target meets guidelines
            }
            
            Button {
                withAnimation {
                    selectedTab = .depositPlan
                }
            } label: {
                VStack(spacing: 2) {
                    if selectedTab == .wardrobe {
                        if let indicator = depositMonthIndicator {
                            switch indicator {
                            case .current(let day):
                                CalendarDayIcon(day: day)
                                    .font(.system(size: 18))
                                    .foregroundStyle(magicPalette.accent)
                                    .frame(width: 24, height: 24)
                            case .next(let day):
                                CalendarDayIcon(day: day)
                                    .font(.system(size: 18))
                                    .foregroundStyle(magicPalette.cardAccent)
                                .frame(width: 24, height: 24)
                            }
                        } else {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 16))
                        }
                    } else {
                        Image(systemName: selectedTab == .depositPlan ? "calendar.badge.clock" : "calendar")
                            .font(.system(size: 16))
                    }
                    Text("心愿尾款")
                        .font(.system(size: 10, weight: selectedTab == .depositPlan ? .bold : .medium))
                }
                .foregroundStyle(selectedTab == .depositPlan ? magicPalette.cardAccent : magicPalette.secondaryText)
                .frame(height: 44) // Ensure touch target meets guidelines
            }
        }
    }
    
    private var fashionTabSwitcher: some View {
        WardrobeFashionTabSwitcher(selectedTab: $selectedTab, monthIndicator: depositMonthIndicator)
    }
    
    private var isInWardrobeEditMode: Bool {
        selectedTab == .wardrobe && (isSelectionMode || (sortOption == .custom && isEditing))
    }
    
    private var classicActionButtons: some View {
        HStack(spacing: 6) {
            // 完成编辑按钮（编辑模式时直接显示）
            if selectedTab == .wardrobe && isSelectionMode {
                doneEditButton
            }
            
            // 完成排序按钮（自定义排序编辑模式时直接显示）
            if selectedTab == .wardrobe && sortOption == .custom && isEditing {
                doneSortButton
            }
            
            // 排序、筛选、视图直接显示在导航栏（非编辑模式时显示）
            if !isInWardrobeEditMode {
                sortButton
                filterButton
                displayButton
            }
            
            // 补款提醒（仅心愿尾款标签页，且非编辑模式）
            if selectedTab == .depositPlan && !isInWardrobeEditMode {
                notificationButton
            }
            
            // 更多菜单 - 包含搜索、编辑、自定义排序等功能
            moreMenuButton
            
            addButton
        }
    }
    
    private var fashionLeadingButtons: some View {
        HStack(spacing: 4) {
            if selectedTab == .wardrobe && isSelectionMode {
                doneEditButton
            }

            if selectedTab == .wardrobe && sortOption == .custom && isEditing {
                doneSortButton
            }

            if !isInWardrobeEditMode {
                sortButton
                displayButton
            }
        }
    }

    private var fashionTrailingButtons: some View {
        HStack(spacing: 4) {
            if !isInWardrobeEditMode {
                filterButton
            }

            // 补款提醒（仅心愿尾款标签页，且非编辑模式）
            if selectedTab == .depositPlan && !isInWardrobeEditMode {
                notificationButton
            }

            moreMenuButton

            // 仅在少女衣橱标签页显示创建按钮
            if selectedTab == .wardrobe {
                addButton
            }
        }
    }
    
    private var doneEditButton: some View {
        Button {
            withAnimation {
                isSelectionMode = false
            }
        } label: {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(magicPalette.accent)
        }
        .captureGuideTarget(.wardrobeDoneSelectionButton)
    }

    private var doneSortButton: some View {
        Button {
            withAnimation {
                isEditing = false
            }
        } label: {
            if #available(iOS 26.0, *) {
                Image(systemName: "list.number.badge.ellipsis")
                    .font(.system(size: 18))
                    .foregroundStyle(magicPalette.accent)
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(magicPalette.accent)
            }
        }
    }
    
    private var notificationButton: some View {
        Button {
            showingDepositNotificationSheet = true
        } label: {
            ZStack {
                Image(systemName: unreadNotificationCount > 0 ? "bell.badge" : "bell")
                    .font(.system(size: 14))
                    .foregroundStyle(magicPalette.navigationForeground)

                if unreadNotificationCount > 0 {
                    Text("\(min(unreadNotificationCount, 99))")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(magicPalette.cardAccent)
                        .clipShape(Capsule())
                        .offset(x: 8, y: -6)
                }
            }
        }
    }
    
    private var moreMenuButton: some View {
        Menu {
            // 搜索功能
            Button {
                isSearchActive = true
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
            }
            
            if selectedTab == .wardrobe {
                Divider()
                
                // 编辑模式（仅在非编辑模式时显示入口）
                if !isSelectionMode {
                    Button {
                        withAnimation {
                            isSelectionMode = true
                        }
                    } label: {
                        Label("编辑", systemImage: "pencil.circle")
                    }
                    .captureGuideTarget(.wardrobeEditMenuEntry)
                }
                
                // 自定义排序编辑（仅在非编辑模式且排序为自定义时显示入口）
                if sortOption == .custom && !isEditing {
                    Button {
                        withAnimation {
                            isEditing = true
                        }
                    } label: {
                        Label("调整顺序", systemImage: "list.number")
                    }
                }
            }
            
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(magicPalette.navigationForeground)
                .captureGuideTarget(.wardrobeMoreMenuButton)
                .onTapGesture {
                    NotificationCenter.default.post(name: .wardrobeMoreMenuOpened, object: nil)
                }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                NotificationCenter.default.post(name: .wardrobeMoreMenuOpened, object: nil)
            }
        )
    }

    private var sortButton: some View {
        Menu {
            Picker("排序", selection: $sortOption) {
                ForEach(SortOption.allCases) { option in
                    Text(option.rawValue)
                        .tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 14))
                .foregroundStyle(magicPalette.navigationForeground)
        }
    }
    
    private var filterButton: some View {
        Group {
            if filterMode == .multiDimensional {
                // 多维筛选模式 - 使用Sheet
                Button {
                    showingMultiDimensionalFilterSheet = true
                } label: {
                    filterButtonLabel
                }
                .sheet(isPresented: $showingMultiDimensionalFilterSheet) {
                    MultiDimensionalFilterSheet(
                        clothings: allClothings,
                        tags: tags,
                        brands: brands,
                        selectedTagIDs: $selectedTagIDs,
                        selectedBrandIDs: $selectedBrandIDs,
                        selectedTypes: $selectedTypes,
                        selectedColors: $selectedColors,
                        selectedSizes: $selectedSizes,
                        selectedLengths: $selectedLengths,
                        selectedConditions: $selectedConditions,
                        selectedAccessories: $selectedAccessories,
                        depositStatusFilter: $depositStatusFilter
                    )
                }
            } else {
                // 经典筛选模式 - 使用Menu
                classicFilterMenu
            }
        }
    }
    
    // 筛选按钮标签
    private var filterButtonLabel: some View {
        Image(systemName: "line.3.horizontal.decrease.circle")
            .font(.system(size: 14))
            .foregroundStyle(magicPalette.navigationForeground)
            .symbolVariant(selectedTagIDs.isEmpty && selectedBrandIDs.isEmpty && selectedTypes.isEmpty && selectedColors.isEmpty && selectedSizes.isEmpty && selectedLengths.isEmpty && selectedConditions.isEmpty && selectedAccessories.isEmpty ? .none : .fill)
    }
    
    // 经典筛选菜单
    private var classicFilterMenu: some View {
        Menu {
            // Tags Filter
            Menu {
                Button(role: .destructive) {
                    selectedTagIDs.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无标签选项
                Button {
                    if selectedTagIDs.contains(HomeView.noTagUUID) {
                        selectedTagIDs.remove(HomeView.noTagUUID)
                    } else {
                        selectedTagIDs.removeAll()
                        selectedTagIDs.insert(HomeView.noTagUUID)
                    }
                } label: {
                    HStack {
                        Text("无标签")
                        if selectedTagIDs.contains(HomeView.noTagUUID) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(tags) { tag in
                    Button {
                        if selectedTagIDs.contains(tag.id) {
                            selectedTagIDs.remove(tag.id)
                        } else {
                            selectedTagIDs.removeAll()
                            selectedTagIDs.insert(tag.id)
                        }
                    } label: {
                        HStack {
                            Text(tag.name)
                            if selectedTagIDs.contains(tag.id) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedTagName: String? = selectedTagIDs.first.flatMap { id in
                    if id == HomeView.noTagUUID {
                        return "无标签"
                    }
                    return tags.first(where: { $0.id == id })?.name
                }
                Label(selectedTagName ?? "标签", systemImage: selectedTagIDs.isEmpty ? "tag" : "tag.fill")
            }
            
            // Brands Filter
            Menu {
                Button(role: .destructive) {
                    selectedBrandIDs.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无品牌选项
                Button {
                    if selectedBrandIDs.contains(HomeView.noBrandUUID) {
                        selectedBrandIDs.remove(HomeView.noBrandUUID)
                    } else {
                        selectedBrandIDs.removeAll()
                        selectedBrandIDs.insert(HomeView.noBrandUUID)
                    }
                } label: {
                    HStack {
                        Text("无品牌")
                        if selectedBrandIDs.contains(HomeView.noBrandUUID) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(brands) { brand in
                    Button {
                        if selectedBrandIDs.contains(brand.id) {
                            selectedBrandIDs.remove(brand.id)
                        } else {
                            selectedBrandIDs.removeAll()
                            selectedBrandIDs.insert(brand.id)
                        }
                    } label: {
                        HStack {
                            Text(brand.name)
                            if selectedBrandIDs.contains(brand.id) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedBrandName: String? = selectedBrandIDs.first.flatMap { id in
                    if id == HomeView.noBrandUUID {
                        return "无品牌"
                    }
                    return brands.first(where: { $0.id == id })?.name
                }
                Label(selectedBrandName ?? "品牌", systemImage: selectedBrandIDs.isEmpty ? "bag" : "bag.fill")
            }
            
            // Dynamic String-based Filters
            ForEach(visibilityManager.fieldOrder, id: \.self) { field in
                if visibilityManager.isVisible(field) {
                    buildFilterSection(for: field)
                }
            }
            
        } label: {
            filterButtonLabel
        }
    }
    
    @ViewBuilder
    private func buildFilterSection(for field: ClothingField) -> some View {
        switch field {
        case .types:
            Menu {
                Button(role: .destructive) {
                    selectedTypes.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无类型选项
                Button {
                    if selectedTypes.contains(HomeView.noTypeMarker) {
                        selectedTypes.remove(HomeView.noTypeMarker)
                    } else {
                        selectedTypes.removeAll()
                        selectedTypes.insert(HomeView.noTypeMarker)
                    }
                } label: {
                    HStack {
                        Text("无类型")
                        if selectedTypes.contains(HomeView.noTypeMarker) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(getAllValues(for: \.types), id: \.self) { type in
                    Button {
                        if selectedTypes.contains(type) {
                            selectedTypes.remove(type)
                        } else {
                            selectedTypes.removeAll()
                            selectedTypes.insert(type)
                        }
                    } label: {
                        HStack {
                            Text(type)
                            if selectedTypes.contains(type) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedTypeName: String? = selectedTypes.first.flatMap { type in
                    type == HomeView.noTypeMarker ? "无类型" : type
                }
                Label(selectedTypeName ?? "类型", systemImage: selectedTypes.isEmpty ? "tshirt" : "tshirt.fill")
            }
            
        case .colors:
            Menu {
                Button(role: .destructive) {
                    selectedColors.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无颜色选项
                Button {
                    if selectedColors.contains(HomeView.noColorMarker) {
                        selectedColors.remove(HomeView.noColorMarker)
                    } else {
                        selectedColors.removeAll()
                        selectedColors.insert(HomeView.noColorMarker)
                    }
                } label: {
                    HStack {
                        Text("无颜色")
                        if selectedColors.contains(HomeView.noColorMarker) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(getAllValues(for: \.colors), id: \.self) { color in
                    Button {
                        if selectedColors.contains(color) {
                            selectedColors.remove(color)
                        } else {
                            selectedColors.removeAll()
                            selectedColors.insert(color)
                        }
                    } label: {
                        HStack {
                            Text(color)
                            if selectedColors.contains(color) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedColorName: String? = selectedColors.first.flatMap { color in
                    color == HomeView.noColorMarker ? "无颜色" : color
                }
                Label(selectedColorName ?? "颜色", systemImage: selectedColors.isEmpty ? "paintpalette" : "paintpalette.fill")
            }
            
        case .sizes:
            Menu {
                Button(role: .destructive) {
                    selectedSizes.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无尺码选项
                Button {
                    if selectedSizes.contains(HomeView.noSizeMarker) {
                        selectedSizes.remove(HomeView.noSizeMarker)
                    } else {
                        selectedSizes.removeAll()
                        selectedSizes.insert(HomeView.noSizeMarker)
                    }
                } label: {
                    HStack {
                        Text("无尺码")
                        if selectedSizes.contains(HomeView.noSizeMarker) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(getAllValues(for: \.sizes), id: \.self) { size in
                    Button {
                        if selectedSizes.contains(size) {
                            selectedSizes.remove(size)
                        } else {
                            selectedSizes.removeAll()
                            selectedSizes.insert(size)
                        }
                    } label: {
                        HStack {
                            Text(size)
                            if selectedSizes.contains(size) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedSizeName: String? = selectedSizes.first.flatMap { size in
                    size == HomeView.noSizeMarker ? "无尺码" : size
                }
                Label(selectedSizeName ?? "尺码", systemImage: selectedSizes.isEmpty ? "ruler" : "ruler.fill")
            }
            
        case .length:
            Menu {
                Button(role: .destructive) {
                    selectedLengths.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无衣长选项
                Button {
                    if selectedLengths.contains(HomeView.noLengthMarker) {
                        selectedLengths.remove(HomeView.noLengthMarker)
                    } else {
                        selectedLengths.removeAll()
                        selectedLengths.insert(HomeView.noLengthMarker)
                    }
                } label: {
                    HStack {
                        Text("无衣长")
                        if selectedLengths.contains(HomeView.noLengthMarker) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(getAllValues(for: \.length), id: \.self) { length in
                    Button {
                        if selectedLengths.contains(length) {
                            selectedLengths.remove(length)
                        } else {
                            selectedLengths.removeAll()
                            selectedLengths.insert(length)
                        }
                    } label: {
                        HStack {
                            Text(length)
                            if selectedLengths.contains(length) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedLengthName: String? = selectedLengths.first.flatMap { length in
                    length == HomeView.noLengthMarker ? "无衣长" : length
                }
                Label(selectedLengthName ?? "衣长", systemImage: selectedLengths.isEmpty ? "arrow.up.and.down" : "arrow.up.and.down.circle.fill")
            }
            
        case .condition:
            Menu {
                Button(role: .destructive) {
                    selectedConditions.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无状态选项
                Button {
                    if selectedConditions.contains(HomeView.noConditionMarker) {
                        selectedConditions.remove(HomeView.noConditionMarker)
                    } else {
                        selectedConditions.removeAll()
                        selectedConditions.insert(HomeView.noConditionMarker)
                    }
                } label: {
                    HStack {
                        Text("无状态")
                        if selectedConditions.contains(HomeView.noConditionMarker) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(getAllValues(for: \.condition), id: \.self) { condition in
                    Button {
                        if selectedConditions.contains(condition) {
                            selectedConditions.remove(condition)
                        } else {
                            selectedConditions.removeAll()
                            selectedConditions.insert(condition)
                        }
                    } label: {
                        HStack {
                            Text(condition)
                            if selectedConditions.contains(condition) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedConditionName: String? = selectedConditions.first.flatMap { condition in
                    condition == HomeView.noConditionMarker ? "无状态" : condition
                }
                Label(selectedConditionName ?? "状态", systemImage: selectedConditions.isEmpty ? "star" : "star.fill")
            }
            
        case .accessories:
            Menu {
                Button(role: .destructive) {
                    selectedAccessories.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无小物选项
                Button {
                    if selectedAccessories.contains("__NO_ACCESSORY__") {
                        selectedAccessories.remove("__NO_ACCESSORY__")
                    } else {
                        selectedAccessories.removeAll()
                        selectedAccessories.insert("__NO_ACCESSORY__")
                    }
                } label: {
                    HStack {
                        Text("无小物")
                        if selectedAccessories.contains("__NO_ACCESSORY__") {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(getAllValues(for: \.accessories), id: \.self) { accessory in
                    Button {
                        if selectedAccessories.contains(accessory) {
                            selectedAccessories.remove(accessory)
                        } else {
                            selectedAccessories.removeAll()
                            selectedAccessories.insert(accessory)
                        }
                    } label: {
                        HStack {
                            Text(accessory)
                            if selectedAccessories.contains(accessory) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedAccessoryName: String? = selectedAccessories.first.flatMap { accessory in
                    accessory == "__NO_ACCESSORY__" ? "无小物" : accessory
                }
                Label(selectedAccessoryName ?? "小物", systemImage: selectedAccessories.isEmpty ? "crown" : "crown.fill")
            }
        }
    }
    
    // Helper to extract unique values from comma-separated strings
    private func getAllValues(for keyPath: KeyPath<Clothing, String>) -> [String] {
        let allString = allClothings.map { $0[keyPath: keyPath] }.joined(separator: ",")
        // Replace Chinese comma with English comma before splitting
        let normalizedString = allString.replacingOccurrences(of: "，", with: ",")
        return Array(Set(normalizedString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
    }
    
    private var displayButton: some View {
        Menu {
            if selectedTab == .wardrobe {
                Picker("布局", selection: $viewLayout) {
                    ForEach(ViewLayout.allCases) { layout in
                        Label(layout.rawValue, systemImage: layout.icon)
                            .tag(layout)
                    }
                }
            } else {
                Picker("布局", selection: $depositDisplayMode) {
                    ForEach(DepositDisplayMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
            }
        } label: {
            Image(systemName: selectedTab == .wardrobe ? viewLayout.icon : depositDisplayMode.icon)
                .font(.system(size: 14))
                .foregroundStyle(magicPalette.navigationForeground)
        }
    }

    // 草稿管理器
    private var draftManager: ClothingEditDraftManager { ClothingEditDraftManager.shared }
    
    // 标记是否从草稿继续
    @State private var continueFromDraft = false

    private func notifyWardrobeAddMenuOpened() {
        NotificationCenter.default.post(name: .wardrobeAddMenuOpened, object: nil)
    }
    
    private var addButton: some View {
        Menu {
            // 如果有草稿，显示"从上次未保存继续"选项
            if draftManager.hasDraft() {
                Button { 
                    notifyWardrobeAddMenuOpened()
                    continueFromDraft = true
                    showingAddSheet = true 
                } label: { 
                    Label("从上次未保存继续", systemImage: "doc.badge.clock") 
                }
                
                Divider()
            }
            
            Button { 
                notifyWardrobeAddMenuOpened()
                continueFromDraft = false
                showingAddSheet = true 
            } label: { 
                Label("手动创建", systemImage: "square.and.pencil")
            }
            .captureGuideTarget(.wardrobeManualCreateEntry)
            
            Button {
                notifyWardrobeAddMenuOpened()
                showingBatchImportSheet = true
            } label: {
                Label("批量导入", systemImage: "square.and.arrow.down.on.square")
            }
            .captureGuideTarget(.wardrobeBatchImportEntry)
            
            // 从社区导入：跟随联网功能显示/隐藏
            if networkManager.canShowNetworkUI() {
                Button {
                    notifyWardrobeAddMenuOpened()
                    showingCommunityImportAlert = true
                } label: {
                    Label("从社区导入", systemImage: "icloud.and.arrow.down")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14))
                .foregroundStyle(magicPalette.navigationForeground)
                .captureGuideTarget(.wardrobeAddButton)
                .onTapGesture {
                    notifyWardrobeAddMenuOpened()
                }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                notifyWardrobeAddMenuOpened()
            }
        )
        .alert("该功能敬请期待，联网版本激情开拓中～！", isPresented: $showingCommunityImportAlert) {
            Button("好的", role: .cancel) { }
        }
    }
    
    private func getFilterDescription() -> String? {
        var descriptions: [String] = []
        
        // Tags
        if !selectedTagIDs.isEmpty {
            var names: [String] = []
            for id in selectedTagIDs {
                if id == HomeView.noTagUUID {
                    names.append("无标签")
                } else if let tag = tags.first(where: { $0.id == id }) {
                    names.append(tag.name)
                }
            }
            if !names.isEmpty { descriptions.append(names.joined(separator: "/")) }
        }
        
        // Brands
        if !selectedBrandIDs.isEmpty {
            var names: [String] = []
            for id in selectedBrandIDs {
                if id == HomeView.noBrandUUID {
                    names.append("无品牌")
                } else if let brand = brands.first(where: { $0.id == id }) {
                    names.append(brand.name)
                }
            }
            if !names.isEmpty { descriptions.append(names.joined(separator: "/")) }
        }
        
        // Types
        if !selectedTypes.isEmpty {
            let names = selectedTypes.map { $0 == HomeView.noTypeMarker ? "无类型" : $0 }
            descriptions.append(names.joined(separator: "/"))
        }
        
        // Colors
        if !selectedColors.isEmpty {
            let names = selectedColors.map { $0 == HomeView.noColorMarker ? "无颜色" : $0 }
            descriptions.append(names.joined(separator: "/"))
        }
        
        // Sizes
        if !selectedSizes.isEmpty {
            let names = selectedSizes.map { $0 == HomeView.noSizeMarker ? "无尺码" : $0 }
            descriptions.append(names.joined(separator: "/"))
        }
        
        // Lengths
        if !selectedLengths.isEmpty {
            let names = selectedLengths.map { $0 == HomeView.noLengthMarker ? "无衣长" : $0 }
            descriptions.append(names.joined(separator: "/"))
        }
        
        // Conditions
        if !selectedConditions.isEmpty {
            let names = selectedConditions.map { $0 == HomeView.noConditionMarker ? "无状态" : $0 }
            descriptions.append(names.joined(separator: "/"))
        }
        
        // Accessories
        if !selectedAccessories.isEmpty {
            let names = selectedAccessories.map { $0 == HomeView.noAccessoryMarker ? "无小物" : $0 }
            descriptions.append(names.joined(separator: "/"))
        }
        
        if descriptions.isEmpty { return nil }
        return descriptions.joined(separator: " + ")
    }
    
    private func clearAllFilters() {
        selectedTagIDs.removeAll()
        selectedBrandIDs.removeAll()
        selectedTypes.removeAll()
        selectedColors.removeAll()
        selectedSizes.removeAll()
        selectedLengths.removeAll()
        selectedConditions.removeAll()
        selectedAccessories.removeAll()
        depositStatusFilter = .all
    }
}

#Preview {
    HomeView(selectedTab: .constant(.wardrobe))
}

extension HomeView {
    private var depositMonthIndicator: WardrobeMonthIndicator? {
        let calendar = Calendar.current
        let now = Date()
        
        // Month intervals
        guard let currentInterval = calendar.dateInterval(of: .month, for: now) else { return nil }
        let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: now)!
        guard let nextInterval = calendar.dateInterval(of: .month, for: nextMonthDate) else { return nil }
        
        func pickDay(in interval: DateInterval) -> Int? {
            var candidates: [Date] = []
            for c in allClothings where c.isDepositPlan {
                if let end = c.finalPaymentEndDate, interval.contains(end) {
                    candidates.append(end)
                    continue
                }
                if let start = c.finalPaymentDate, interval.contains(start) {
                    candidates.append(start)
                }
            }
            if candidates.isEmpty { return nil }
            let future = candidates.filter { $0 >= now }
            let chosen = future.min() ?? candidates.min()
            return chosen.map { calendar.component(.day, from: $0) }
        }
        
        if let day = pickDay(in: currentInterval) { return .current(day) }
        if let day = pickDay(in: nextInterval) { return .next(day) }
        return nil
    }
}

// MARK: - View 扩展：条件应用 searchable
extension View {
    /// 只在 isPresented 为 true 时应用 searchable，实现默认隐藏搜索栏的效果
    @ViewBuilder
    func applySearchableIfNeeded(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        prompt: String
    ) -> some View {
        if isPresented.wrappedValue {
            self.searchable(
                text: text,
                isPresented: isPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: prompt
            )
        } else {
            self
        }
    }
}
