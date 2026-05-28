//
//  HomeView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI
import SwiftData
import Combine
import UIKit

enum SortOption: String, CaseIterable, Identifiable, Hashable, Sendable {
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

enum WardrobeTopBarMetrics {
    static let shellHorizontalPadding: CGFloat = 8
    static let shellVerticalPadding: CGFloat = 4
    static let segmentVisualHeight: CGFloat = 32
    static let segmentInterItemSpacing: CGFloat = 8
    static let segmentStackSpacing: CGFloat = 1
    static let segmentIconSize: CGFloat = 13
    static let segmentCalendarIconSize: CGFloat = 15
    static let segmentCalendarFrame: CGFloat = 20
    static let segmentTextSize: CGFloat = 9
    static let segmentItemHorizontalPadding: CGFloat = 8
    static let segmentItemVerticalPadding: CGFloat = 4
    // 时尚导航左右操作区的透明占位宽度；背景本身通过 fixedSize 贴合内部按钮组。
    static let fashionSideGroupWidth: CGFloat = 98

    // 主题态经典导航左侧双标签专用尺寸：背景宽度稳定，避免右侧菜单组或系统 Menu 打开时挤占。
    static let classicSegmentShellWidth: CGFloat = 116
    static let classicSegmentShellHorizontalPadding: CGFloat = 6
    static let classicSegmentShellVerticalPadding: CGFloat = 3
    static let classicSegmentInterItemSpacing: CGFloat = 4
    static let classicSegmentItemHorizontalPadding: CGFloat = 5
    static let classicSegmentItemVerticalPadding: CGFloat = 3

    static var classicSegmentContentWidth: CGFloat {
        classicSegmentShellWidth - classicSegmentShellHorizontalPadding * 2
    }
}

private struct WardrobeMenuFacetClothingRow: Equatable, Sendable {
    let id: UUID
    let updatedAt: Date
    let lastModified: Date
    let deletedAt: Date?
    let types: String
    let colors: String
    let sizes: String
    let length: String
    let condition: String
    let accessories: String

    init(_ clothing: Clothing) {
        id = clothing.id
        updatedAt = clothing.updatedAt
        lastModified = clothing.lastModified
        deletedAt = clothing.deletedAt
        types = clothing.types
        colors = clothing.colors
        sizes = clothing.sizes
        length = clothing.length
        condition = clothing.condition
        accessories = clothing.accessories
    }
}

private struct WardrobeMenuFacetNamedRow: Equatable, Sendable {
    let id: UUID
    let name: String
    let lastModified: Date
}

private struct WardrobeMenuFacetSourceKey: Equatable, Sendable {
    let clothings: [WardrobeMenuFacetClothingRow]
    let tags: [WardrobeMenuFacetNamedRow]
    let brands: [WardrobeMenuFacetNamedRow]
}

private struct WardrobeMenuNamedOption: Identifiable, Equatable {
    let id: UUID
    let name: String
}

private struct WardrobeMenuFacetSnapshot: Equatable, Sendable {
    let types: [String]
    let colors: [String]
    let sizes: [String]
    let lengths: [String]
    let conditions: [String]
    let accessories: [String]
    let tagNameByID: [UUID: String]
    let brandNameByID: [UUID: String]
    let tagOptions: [WardrobeMenuFacetNamedRow]
    let brandOptions: [WardrobeMenuFacetNamedRow]

    var optionCount: Int {
        types.count + colors.count + sizes.count + lengths.count + conditions.count + accessories.count + tagOptions.count + brandOptions.count
    }
}

private final class WardrobeMenuFacetCache: ObservableObject {
    @Published private(set) var types: [String] = []
    @Published private(set) var colors: [String] = []
    @Published private(set) var sizes: [String] = []
    @Published private(set) var lengths: [String] = []
    @Published private(set) var conditions: [String] = []
    @Published private(set) var accessories: [String] = []
    @Published private(set) var tagNameByID: [UUID: String] = [:]
    @Published private(set) var brandNameByID: [UUID: String] = [:]
    @Published private(set) var tagOptions: [WardrobeMenuNamedOption] = []
    @Published private(set) var brandOptions: [WardrobeMenuNamedOption] = []

    private var lastSourceKey: WardrobeMenuFacetSourceKey?
    private var lastSnapshot: WardrobeMenuFacetSnapshot?
    private var refreshTask: Task<Void, Never>?

    deinit {
        refreshTask?.cancel()
    }

    func refresh(from sourceKey: WardrobeMenuFacetSourceKey) {
        guard sourceKey != lastSourceKey else { return }
        lastSourceKey = sourceKey
        refreshTask?.cancel()

        refreshTask = Task.detached(priority: .utility) {
            let snapshot = WardrobeMenuFacetCache.buildSnapshot(from: sourceKey)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.apply(snapshot)
            }
        }
    }

    func options(for field: ClothingField) -> [String] {
        switch field {
        case .types: return types
        case .colors: return colors
        case .sizes: return sizes
        case .length: return lengths
        case .condition: return conditions
        case .accessories: return accessories
        }
    }

    var filterFacetSnapshot: WardrobeFilterFacetSnapshot {
        WardrobeFilterFacetSnapshot(
            tags: tagOptions.map { WardrobeFilterNamedOption(id: $0.id, name: $0.name) },
            brands: brandOptions.map { WardrobeFilterNamedOption(id: $0.id, name: $0.name) },
            types: types,
            colors: colors,
            sizes: sizes,
            lengths: lengths,
            conditions: conditions,
            accessories: accessories,
            tagNameByID: tagNameByID,
            brandNameByID: brandNameByID
        )
    }

    private func apply(_ snapshot: WardrobeMenuFacetSnapshot) {
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        types = snapshot.types
        colors = snapshot.colors
        sizes = snapshot.sizes
        lengths = snapshot.lengths
        conditions = snapshot.conditions
        accessories = snapshot.accessories
        tagNameByID = snapshot.tagNameByID
        brandNameByID = snapshot.brandNameByID
        tagOptions = snapshot.tagOptions.map { WardrobeMenuNamedOption(id: $0.id, name: $0.name) }
        brandOptions = snapshot.brandOptions.map { WardrobeMenuNamedOption(id: $0.id, name: $0.name) }
        _ = MenuPerfSignpost.facetCacheRefresh(inputCount: snapshot.tagOptions.count + snapshot.brandOptions.count, outputCount: snapshot.optionCount)
    }

    nonisolated private static func buildSnapshot(from sourceKey: WardrobeMenuFacetSourceKey) -> WardrobeMenuFacetSnapshot {
        let tagOptions = deduplicatedNamedRows(sourceKey.tags)
        let brandOptions = deduplicatedNamedRows(sourceKey.brands)

        return WardrobeMenuFacetSnapshot(
            types: distinctValues(sourceKey.clothings.map(\.types)),
            colors: distinctValues(sourceKey.clothings.map(\.colors)),
            sizes: distinctValues(sourceKey.clothings.map(\.sizes)),
            lengths: distinctValues(sourceKey.clothings.map(\.length)),
            conditions: distinctValues(sourceKey.clothings.map(\.condition)),
            accessories: distinctValues(sourceKey.clothings.map(\.accessories)),
            tagNameByID: nameByID(from: tagOptions),
            brandNameByID: nameByID(from: brandOptions),
            tagOptions: tagOptions,
            brandOptions: brandOptions
        )
    }

    nonisolated private static func distinctValues(_ values: [String]) -> [String] {
        let normalized = values
            .joined(separator: ",")
            .replacingOccurrences(of: "，", with: ",")
        return Array(Set(
            normalized
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )).sorted()
    }

    nonisolated private static func deduplicatedNamedRows(_ rows: [WardrobeMenuFacetNamedRow]) -> [WardrobeMenuFacetNamedRow] {
        var rowByID: [UUID: WardrobeMenuFacetNamedRow] = [:]
        var firstIndexByID: [UUID: Int] = [:]

        for (index, row) in rows.enumerated() {
            if let existing = rowByID[row.id] {
                rowByID[row.id] = preferredNamedRow(existing, row)
            } else {
                rowByID[row.id] = row
                firstIndexByID[row.id] = index
            }
        }

        return rowByID.values.sorted { lhs, rhs in
            firstIndexByID[lhs.id, default: Int.max] < firstIndexByID[rhs.id, default: Int.max]
        }
    }

    nonisolated private static func preferredNamedRow(_ existing: WardrobeMenuFacetNamedRow, _ candidate: WardrobeMenuFacetNamedRow) -> WardrobeMenuFacetNamedRow {
        let existingNameIsEmpty = existing.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let candidateNameIsEmpty = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if candidate.lastModified > existing.lastModified {
            return candidateNameIsEmpty && !existingNameIsEmpty ? existing : candidate
        }

        if existingNameIsEmpty && !candidateNameIsEmpty {
            return candidate
        }

        return existing
    }

    nonisolated private static func nameByID(from rows: [WardrobeMenuFacetNamedRow]) -> [UUID: String] {
        var result: [UUID: String] = [:]
        for row in rows {
            result[row.id] = row.name
        }
        return result
    }
}

private struct FilterSubmenuView: View, Equatable {
    let field: ClothingField
    let options: [String]
    let noValueMarker: String
    @Binding var selection: Set<String>

    static func == (lhs: FilterSubmenuView, rhs: FilterSubmenuView) -> Bool {
        lhs.field == rhs.field &&
            lhs.options == rhs.options &&
            lhs.noValueMarker == rhs.noValueMarker &&
            lhs.selection == rhs.selection
    }

    var body: some View {
        // menu-perf: wardrobe reusable string filter submenu
        Menu {
            let _ = MenuPerfSignpost.menuContent("wardrobe.filter.\(field.rawValue)")
            Button(role: .destructive) {
                selection.removeAll()
            } label: {
                Label("清除筛选", systemImage: "xmark.circle")
            }

            Button {
                if selection.contains(noValueMarker) {
                    selection.remove(noValueMarker)
                } else {
                    selection.removeAll()
                    selection.insert(noValueMarker)
                }
            } label: {
                HStack {
                    Text(emptyDisplayName)
                    if selection.contains(noValueMarker) {
                        Image(systemName: "checkmark")
                    }
                }
            }

            ForEach(options, id: \.self) { value in
                Button {
                    if selection.contains(value) {
                        selection.remove(value)
                    } else {
                        selection.removeAll()
                        selection.insert(value)
                    }
                } label: {
                    HStack {
                        Text(value)
                        if selection.contains(value) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(selectedDisplayName ?? field.displayName, systemImage: selection.isEmpty ? iconName : selectedIconName)
        }
    }

    private var selectedDisplayName: String? {
        guard let value = selection.first else { return nil }
        return value == noValueMarker ? emptyDisplayName : value
    }

    private var emptyDisplayName: String {
        switch field {
        case .types: return "无类型"
        case .colors: return "无颜色"
        case .sizes: return "无尺码"
        case .length: return "无衣长"
        case .condition: return "无状态"
        case .accessories: return "无小物"
        }
    }

    private var iconName: String {
        switch field {
        case .types: return "tshirt"
        case .colors: return "paintpalette"
        case .sizes: return "ruler"
        case .length: return "arrow.up.and.down"
        case .condition: return "sparkles"
        case .accessories: return "crown"
        }
    }

    private var selectedIconName: String {
        switch field {
        case .types: return "tshirt.fill"
        case .colors: return "paintpalette.fill"
        case .sizes: return "ruler.fill"
        case .length: return "arrow.up.and.down.circle.fill"
        case .condition: return "sparkles"
        case .accessories: return "crown.fill"
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared
    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    @StateObject private var menuFacetCache = WardrobeMenuFacetCache()
    @StateObject private var draftManager = ClothingEditDraftManager.shared
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
    @State private var batchImportUnlockAlert: FeatureUnlockAlert?
    @State private var isSelectionMode = false
    @State private var isEditing = false
    @State private var isSearchActive = false
    @FocusState private var isWardrobeSearchFocused: Bool
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
    @State private var notificationTargetClothing: Clothing?
    @State private var navigateToNotificationDetail = false
    @State private var hasLoadedDepositPlan = false
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

    private var menuFacetSourceKey: WardrobeMenuFacetSourceKey {
        WardrobeMenuFacetSourceKey(
            clothings: allClothings.map(WardrobeMenuFacetClothingRow.init),
            tags: tags.map { WardrobeMenuFacetNamedRow(id: $0.id, name: $0.name, lastModified: $0.lastModified) },
            brands: brands.map { WardrobeMenuFacetNamedRow(id: $0.id, name: $0.name, lastModified: $0.lastModified) }
        )
    }

    private func refreshMenuFacetCache() {
        menuFacetCache.refresh(from: menuFacetSourceKey)
    }

    private var themedTopBarGroupDescriptor: ThemeSkinDescriptor? {
        themeDescriptor(for: .topBarMain)
    }

    private var themedTopBarSegmentDescriptor: ThemeSkinDescriptor? {
        themeDescriptor(for: .topBarSegment)
    }

    private var themedTopBarButtonDescriptor: ThemeSkinDescriptor? {
        themeDescriptor(for: .topBarIconButton)
    }

    private var themedTopBarAddButtonDescriptor: ThemeSkinDescriptor? {
        themeDescriptor(for: .topBarAddButton, fallbackIfUnsupported: .topBarIconButton)
    }

    private var themedSearchEntryDescriptor: ThemeSkinDescriptor? {
        themeDescriptor(for: .searchBar)
    }

    private var activeTopBarThemeSkinDescriptor: ThemeSkinDescriptor? {
        themedTopBarButtonDescriptor ??
            themedTopBarAddButtonDescriptor ??
            themedTopBarGroupDescriptor ??
            themedTopBarSegmentDescriptor ??
            themedSearchEntryDescriptor
    }

    private var topBarToolbarColorScheme: ColorScheme {
        activeTopBarThemeSkinDescriptor == nil
            ? (magicPalette.navigationBackground.isDark ? .dark : .light)
            : colorScheme
    }

    private var topBarIconForeground: Color {
        guard let descriptor = activeTopBarThemeSkinDescriptor else {
            return magicPalette.navigationForeground
        }

        return SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme)
    }

    private var topBarAccentForeground: Color {
        guard let descriptor = activeTopBarThemeSkinDescriptor else {
            return magicPalette.accent
        }

        return SkyConcertThemeSkin.readableAccent(for: descriptor, colorScheme: colorScheme)
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Background
                LiquidBackground(themeSkinWallpaperContext: selectedTab == .wardrobe ? .wardrobe : .depositPlan)
                    .ignoresSafeArea()

                if selectedTab == .wardrobe {
                    SkyConcertWardrobeBackdrop(descriptor: themedTopBarGroupDescriptor)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                
                ZStack {
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
                    .opacity(selectedTab == .wardrobe ? 1 : 0)
                    .allowsHitTesting(selectedTab == .wardrobe)
                    .accessibilityHidden(selectedTab != .wardrobe)
                    .zIndex(selectedTab == .wardrobe ? 1 : 0)

                    if selectedTab == .depositPlan || hasLoadedDepositPlan {
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
                        .opacity(selectedTab == .depositPlan ? 1 : 0)
                        .allowsHitTesting(selectedTab == .depositPlan)
                        .accessibilityHidden(selectedTab != .depositPlan)
                        .zIndex(selectedTab == .depositPlan ? 1 : 0)
                    }
                }
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .onChange(of: viewLayout) { _, _ in
                RewardManager.shared.triggerReward(type: .firstTimeFeature("ViewLayoutChange"))
            }
            .onChange(of: selectedTab) { _, _ in
                // 切换标签页时关闭搜索栏
                isSearchActive = false
                if selectedTab == .depositPlan {
                    hasLoadedDepositPlan = true
                }
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
                if isSearchActive {
                    ToolbarItem(placement: .principal) {
                        wardrobeTopSearchBar
                    }
                } else if effectiveWardrobeNavigationStyle == .classic {
                    ToolbarItem(placement: .topBarLeading) {
                        HomeThemeSkinToolbarShell(
                            descriptor: themedTopBarSegmentDescriptor,
                            style: .segment,
                            horizontalPadding: classicSegmentShellHorizontalPadding,
                            verticalPadding: classicSegmentShellVerticalPadding
                        ) {
                            tabSwitcher
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        HomeThemeSkinToolbarShell(
                            descriptor: themedTopBarGroupDescriptor,
                            horizontalPadding: WardrobeTopBarMetrics.shellHorizontalPadding,
                            verticalPadding: WardrobeTopBarMetrics.shellVerticalPadding
                        ) {
                            classicActionButtons
                        }
                    }
                } else {
                    ToolbarItem(placement: .principal) {
                        fashionToolbar
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(topBarToolbarColorScheme, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .tint(topBarAccentForeground)
            .onAppear {
                // 确保初始状态下搜索栏不显示
                isSearchActive = false
                hasLoadedDepositPlan = hasLoadedDepositPlan || selectedTab == .depositPlan
                wardrobeNavigationStyle = WardrobeNavigationStyle.normalizeStoredPreference()
                draftManager.refreshDraftPresence()
                refreshMenuFacetCache()
            }
            .onChange(of: menuFacetSourceKey) { _, _ in
                refreshMenuFacetCache()
            }
            .sheet(isPresented: $showingAddSheet) {
                NavigationStack {
                    ClothingEditView(
                        clothing: nil,
                        initialBrandID: selectedBrandIDs.first,
                        initialTypes: selectedTypes,
                        continueFromDraft: continueFromDraft,
                        activityDraft: pendingActivityDraft
                    )
                }
            }
            .onChange(of: showingAddSheet) { _, newValue in
                if newValue {
                    NotificationCenter.default.post(name: .wardrobeManualCreateOpened, object: nil)
                } else {
                    pendingActivityDraft = nil
                }
            }
            .onContinueUserActivity(ClothingEditUserActivity.activityType) { activity in
                continueClothingEditUserActivity(activity)
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
                presentWardrobeManualCreate()
            }
            .onReceive(NotificationCenter.default.publisher(for: .guideRequestWardrobeBatchImport)) { _ in
                guard selectedTab == .wardrobe else { return }
                presentBatchImport()
            }
            .sheet(isPresented: $showingDepositNotificationSheet) {
                NavigationStack {
                    DepositNotificationView()
                }
            }
            .navigationDestination(isPresented: $navigateToNotificationDetail) {
                if let clothing = notificationTargetClothing {
                    ClothingDetailView(clothing: clothing)
                }
            }
            .onReceive(tabNavigationManager.$navigateToClothingID) { clothingID in
                guard let clothingID else { return }
                openNotificationClothingDetail(clothingID)
            }
            .alert(item: $batchImportUnlockAlert) { alert in
                if alert.canUnlock {
                    return Alert(
                        title: Text("解锁 \(alert.feature.displayName)"),
                        message: Text("\(alert.condition.description)\n\n确定要解锁吗？"),
                        primaryButton: .default(Text("解锁")) {
                            unlockBatchImportAndPresent()
                        },
                        secondaryButton: .cancel(Text("取消"))
                    )
                } else {
                    return Alert(
                        title: Text("尚未满足解锁条件"),
                        message: Text(alert.message ?? alert.condition.description),
                        dismissButton: .default(Text("知道了"))
                    )
                }
            }
            .floatingPetHidden(.wardrobeEditing, isActive: isInWardrobeEditMode)
            .floatingPetHidden(.presentationActive, isActive: isFloatingPetPresentationActive)
        }
    }

    private func openNotificationClothingDetail(_ clothingID: UUID) {
        let presentDetail = {
            guard let clothing = allClothings.first(where: { $0.id == clothingID }) else { return }
            notificationTargetClothing = clothing
            navigateToNotificationDetail = false

            DispatchQueue.main.async {
                navigateToNotificationDetail = true
                tabNavigationManager.navigateToClothingID = nil
            }
        }

        if selectedTab != .depositPlan {
            setHomeTabWithoutContentAnimation(.depositPlan)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                presentDetail()
            }
        } else {
            presentDetail()
        }
    }
    
    private var tabSwitcher: some View {
        HStack(spacing: classicSegmentInterItemSpacing) {
            Button {
                setHomeTabWithoutContentAnimation(.wardrobe)
            } label: {
                VStack(spacing: WardrobeTopBarMetrics.segmentStackSpacing) {
                    Group {
                        if #available(iOS 18.0, *) {
                            Image(systemName: selectedTab == .wardrobe ? "cabinet" : "cabinet.fill")
                        } else {
                            Image(systemName: selectedTab == .wardrobe ? "tshirt" : "tshirt.fill")
                        }
                    }
                    .font(.system(size: WardrobeTopBarMetrics.segmentIconSize))
                    Text("少女衣橱")
                        .font(.system(size: WardrobeTopBarMetrics.segmentTextSize, weight: selectedTab == .wardrobe ? .bold : .medium))
                        .themeSkinLegibleText(level: .inline, slot: .topBarSegment, descriptor: themedTopBarSegmentDescriptor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                }
                .foregroundStyle(classicNavigationTabForeground(isSelected: selectedTab == .wardrobe, fallbackActiveColor: magicPalette.accent))
                .padding(.horizontal, classicSegmentItemHorizontalPadding)
                .padding(.vertical, classicSegmentItemVerticalPadding)
                .background {
                    classicNavigationTabSelectionBackground(isSelected: selectedTab == .wardrobe)
                }
                .frame(height: WardrobeTopBarMetrics.segmentVisualHeight)
                .contentShape(Rectangle())
            }
            
            Button {
                setHomeTabWithoutContentAnimation(.depositPlan)
            } label: {
                VStack(spacing: WardrobeTopBarMetrics.segmentStackSpacing) {
                    if selectedTab == .wardrobe {
                        if let indicator = depositMonthIndicator {
                            switch indicator {
                            case .current(let day):
                                CalendarDayIcon(day: day)
                                    .font(.system(size: WardrobeTopBarMetrics.segmentCalendarIconSize))
                                    .foregroundStyle(classicNavigationTabForeground(isSelected: selectedTab == .depositPlan, fallbackActiveColor: magicPalette.accent))
                                    .frame(width: WardrobeTopBarMetrics.segmentCalendarFrame, height: WardrobeTopBarMetrics.segmentCalendarFrame)
                            case .next(let day):
                                CalendarDayIcon(day: day)
                                    .font(.system(size: WardrobeTopBarMetrics.segmentCalendarIconSize))
                                    .foregroundStyle(classicNavigationTabForeground(isSelected: selectedTab == .depositPlan, fallbackActiveColor: magicPalette.cardAccent))
                                    .frame(width: WardrobeTopBarMetrics.segmentCalendarFrame, height: WardrobeTopBarMetrics.segmentCalendarFrame)
                            }
                        } else {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: WardrobeTopBarMetrics.segmentIconSize))
                        }
                    } else {
                        Image(systemName: selectedTab == .depositPlan ? "calendar.badge.clock" : "calendar")
                            .font(.system(size: WardrobeTopBarMetrics.segmentIconSize))
                    }
                    Text("心愿尾款")
                        .font(.system(size: WardrobeTopBarMetrics.segmentTextSize, weight: selectedTab == .depositPlan ? .bold : .medium))
                        .themeSkinLegibleText(level: .inline, slot: .topBarSegment, descriptor: themedTopBarSegmentDescriptor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                }
                .foregroundStyle(classicNavigationTabForeground(isSelected: selectedTab == .depositPlan, fallbackActiveColor: magicPalette.cardAccent))
                .padding(.horizontal, classicSegmentItemHorizontalPadding)
                .padding(.vertical, classicSegmentItemVerticalPadding)
                .background {
                    classicNavigationTabSelectionBackground(isSelected: selectedTab == .depositPlan)
                }
                .frame(height: WardrobeTopBarMetrics.segmentVisualHeight)
                .contentShape(Rectangle())
            }
        }
        .frame(width: classicSegmentContentWidth)
    }

    private func setHomeTabWithoutContentAnimation(_ tab: HomeTab) {
        guard selectedTab != tab else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTab = tab
            isSearchActive = false
        }
    }

    private var classicSegmentShellHorizontalPadding: CGFloat {
        themedTopBarSegmentDescriptor == nil
            ? WardrobeTopBarMetrics.shellHorizontalPadding
            : WardrobeTopBarMetrics.classicSegmentShellHorizontalPadding
    }

    private var classicSegmentShellVerticalPadding: CGFloat {
        themedTopBarSegmentDescriptor == nil
            ? WardrobeTopBarMetrics.shellVerticalPadding
            : WardrobeTopBarMetrics.classicSegmentShellVerticalPadding
    }

    private var classicSegmentInterItemSpacing: CGFloat {
        themedTopBarSegmentDescriptor == nil
            ? WardrobeTopBarMetrics.segmentInterItemSpacing
            : WardrobeTopBarMetrics.classicSegmentInterItemSpacing
    }

    private var classicSegmentItemHorizontalPadding: CGFloat {
        themedTopBarSegmentDescriptor == nil
            ? 0
            : WardrobeTopBarMetrics.classicSegmentItemHorizontalPadding
    }

    private var classicSegmentItemVerticalPadding: CGFloat {
        themedTopBarSegmentDescriptor == nil
            ? 0
            : WardrobeTopBarMetrics.classicSegmentItemVerticalPadding
    }

    private var classicSegmentContentWidth: CGFloat? {
        themedTopBarSegmentDescriptor == nil
            ? nil
            : WardrobeTopBarMetrics.classicSegmentContentWidth
    }
    
    private var fashionTabSwitcher: some View {
        WardrobeFashionTabSwitcher(
            selectedTab: $selectedTab,
            monthIndicator: depositMonthIndicator,
            themeSkinDescriptor: themedTopBarSegmentDescriptor
        )
    }

    private var fashionToolbar: some View {
        ZStack {
            HStack {
                fashionSideToolbarGroup(alignment: .leading) {
                    fashionLeadingButtons
                }

                Spacer(minLength: 0)

                fashionSideToolbarGroup(alignment: .trailing) {
                    fashionTrailingButtons
                }
            }

            HomeThemeSkinToolbarShell(
                descriptor: themedTopBarSegmentDescriptor,
                style: .segment,
                horizontalPadding: WardrobeTopBarMetrics.shellHorizontalPadding,
                verticalPadding: WardrobeTopBarMetrics.shellVerticalPadding
            ) {
                fashionTabSwitcher
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: topBarContentWidth)
    }

    private func fashionSideToolbarGroup<Content: View>(
        alignment: Alignment,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HomeThemeSkinToolbarShell(
            descriptor: themedTopBarGroupDescriptor,
            horizontalPadding: WardrobeTopBarMetrics.shellHorizontalPadding,
            verticalPadding: WardrobeTopBarMetrics.shellVerticalPadding
        ) {
            content()
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(width: WardrobeTopBarMetrics.fashionSideGroupWidth, alignment: alignment)
    }

    private var topBarContentWidth: CGFloat {
        min(max(UIScreen.main.bounds.width - 32, 320), 620)
    }

    private var activeSearchText: Binding<String> {
        Binding(
            get: { selectedTab == .wardrobe ? wardrobeSearchText : depositSearchText },
            set: { newValue in
                if selectedTab == .wardrobe {
                    wardrobeSearchText = newValue
                } else {
                    depositSearchText = newValue
                }
            }
        )
    }

    private var activeSearchPrompt: String {
        selectedTab == .wardrobe
            ? "搜索名称、品牌、标签、类型、颜色、尺码、价格范围等..."
            : "搜索心愿尾款名称、品牌、标签、价格..."
    }

    private var wardrobeTopSearchBar: some View {
        HStack(spacing: 8) {
            if themedSearchEntryDescriptor != nil {
                HomeThemeSkinToolbarShell(
                    descriptor: themedSearchEntryDescriptor,
                    style: .searchEntry,
                    horizontalPadding: 10,
                    verticalPadding: 7
                ) {
                    wardrobeSearchFieldContent
                }
            } else {
                wardrobeSearchFieldContent
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(magicPalette.cardAccent.opacity(0.16), lineWidth: 0.8)
                    }
            }

            Button("取消") {
                activeSearchText.wrappedValue = ""
                isWardrobeSearchFocused = false
                isSearchActive = false
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(topBarAccentForeground)
        }
        .frame(width: topBarContentWidth)
        .onAppear {
            DispatchQueue.main.async {
                isWardrobeSearchFocused = true
            }
        }
    }

    private var wardrobeSearchFieldContent: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(magicPalette.secondaryText)

            TextField(activeSearchPrompt, text: activeSearchText)
                .font(.system(size: 13, weight: .medium))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($isWardrobeSearchFocused)
                .submitLabel(.search)

            if !activeSearchText.wrappedValue.isEmpty {
                Button {
                    activeSearchText.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(magicPalette.secondaryText.opacity(0.72))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func classicNavigationTabForeground(isSelected: Bool, fallbackActiveColor: Color) -> Color {
        guard let descriptor = themedTopBarSegmentDescriptor else {
            return isSelected ? fallbackActiveColor : magicPalette.secondaryText
        }

        return isSelected
            ? SkyConcertThemeSkin.readableAccent(for: descriptor, colorScheme: colorScheme)
            : SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme).opacity(0.72)
    }

    @ViewBuilder
    private func classicNavigationTabSelectionBackground(isSelected: Bool) -> some View {
        if let descriptor = themedTopBarSegmentDescriptor, isSelected {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.98),
                            SkyConcertThemeSkin.accentSoft(for: descriptor).opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Capsule()
                        .stroke(SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.72), lineWidth: 0.8)
                }
                .shadow(color: SkyConcertThemeSkin.shadowColor(for: descriptor).opacity(0.22), radius: 3, x: 0, y: 1)
        } else {
            Color.clear
        }
    }
    
    private var isInWardrobeEditMode: Bool {
        selectedTab == .wardrobe && (isSelectionMode || (sortOption == .custom && isEditing))
    }

    private var isFloatingPetPresentationActive: Bool {
        showingBatchImportSheet ||
            showingAddSheet ||
            showingDepositNotificationSheet ||
            showingMultiDimensionalFilterSheet ||
            navigateToNotificationDetail ||
            batchImportUnlockAlert != nil
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
        .fixedSize(horizontal: true, vertical: false)
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
        .fixedSize(horizontal: true, vertical: false)
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
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private var doneEditButton: some View {
        Button {
            withAnimation {
                isSelectionMode = false
            }
        } label: {
            HomeThemeSkinToolbarIconShell(descriptor: themedTopBarButtonDescriptor) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(topBarAccentForeground)
            }
        }
        .captureGuideTarget(.wardrobeDoneSelectionButton)
    }

    private var doneSortButton: some View {
        Button {
            withAnimation {
                isEditing = false
            }
        } label: {
            HomeThemeSkinToolbarIconShell(descriptor: themedTopBarButtonDescriptor) {
                if #available(iOS 26.0, *) {
                    Image(systemName: "list.number.badge.ellipsis")
                        .font(.system(size: 15))
                        .foregroundStyle(topBarAccentForeground)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(topBarAccentForeground)
                }
            }
        }
    }
    
    private var notificationButton: some View {
        Button {
            showingDepositNotificationSheet = true
        } label: {
            HomeThemeSkinToolbarIconShell(descriptor: themedTopBarButtonDescriptor) {
                ZStack {
                    Image(systemName: unreadNotificationCount > 0 ? "bell.badge" : "bell")
                        .font(.system(size: 12))
                        .foregroundStyle(topBarIconForeground)

                    if unreadNotificationCount > 0 {
                        Text("\(min(unreadNotificationCount, 99))")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white)
                            .themeSkinLegibleText(level: .chip, slot: .topBarIconButton, descriptor: themedTopBarButtonDescriptor)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(magicPalette.cardAccent)
                            .clipShape(Capsule())
                            .offset(x: 6, y: -5)
                    }
                }
            }
        }
    }
    
    private var moreMenuButton: some View {
        Group {
            if guideManager.shouldUseCustomGuideMenu(for: .wardrobeMore) {
                Button {
                    presentWardrobeMoreGuideMenu()
                } label: {
                    moreMenuIcon
                }
            } else {
                // menu-perf: wardrobe more menu
                Menu {
                    let _ = MenuPerfSignpost.menuContent("wardrobe.more")
                    wardrobeMoreMenuContent
                } label: {
                    moreMenuIcon
                        .onTapGesture {
                            _ = MenuPerfSignpost.menuOpen("wardrobe.more")
                            notifyWardrobeMoreMenuOpened()
                        }
                }
            }
        }
    }

    private var sortButton: some View {
        // menu-perf: wardrobe sort menu
        Menu {
            let _ = MenuPerfSignpost.menuContent("wardrobe.sort")
            Picker("排序", selection: $sortOption) {
                ForEach(SortOption.allCases) { option in
                    Text(option.rawValue)
                        .themeSkinLegibleText(level: .inline, slot: .filterChip)
                        .tag(option)
                }
            }
        } label: {
            HomeThemeSkinToolbarIconShell(descriptor: themedTopBarButtonDescriptor) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12))
                    .foregroundStyle(topBarIconForeground)
            }
            .onTapGesture {
                _ = MenuPerfSignpost.menuOpen("wardrobe.sort")
            }
        }
    }
    
    private var filterButton: some View {
        Group {
            if filterMode == .multiDimensional {
                // 多维筛选模式 - 使用Sheet
                Button {
                    refreshMenuFacetCache()
                    _ = MenuPerfSignpost.menuOpen("wardrobe.multi_filter.sheet_open")
                    showingMultiDimensionalFilterSheet = true
                } label: {
                    filterButtonLabel
                }
                .sheet(isPresented: $showingMultiDimensionalFilterSheet) {
                    MultiDimensionalFilterSheet(
                        facetSnapshot: menuFacetCache.filterFacetSnapshot,
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
        HomeThemeSkinToolbarIconShell(descriptor: themedTopBarButtonDescriptor) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 12))
                .foregroundStyle(topBarIconForeground)
                .symbolVariant(selectedTagIDs.isEmpty && selectedBrandIDs.isEmpty && selectedTypes.isEmpty && selectedColors.isEmpty && selectedSizes.isEmpty && selectedLengths.isEmpty && selectedConditions.isEmpty && selectedAccessories.isEmpty ? .none : .fill)
        }
    }
    
    // 经典筛选菜单
    private var classicFilterMenu: some View {
        // menu-perf: wardrobe classic filter menu
        Menu {
            let _ = MenuPerfSignpost.menuContent("wardrobe.filter")
            // Tags Filter
            // menu-perf: wardrobe tag filter submenu
            Menu {
                let _ = MenuPerfSignpost.menuContent("wardrobe.filter.tags")
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
                
                ForEach(menuFacetCache.tagOptions) { tag in
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
                    return menuFacetCache.tagNameByID[id]
                }
                Label(selectedTagName ?? "标签", systemImage: selectedTagIDs.isEmpty ? "tag" : "tag.fill")
            }
            
            // Brands Filter
            // menu-perf: wardrobe brand filter submenu
            Menu {
                let _ = MenuPerfSignpost.menuContent("wardrobe.filter.brands")
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
                
                ForEach(menuFacetCache.brandOptions) { brand in
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
                    return menuFacetCache.brandNameByID[id]
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
                .onTapGesture {
                    _ = MenuPerfSignpost.menuOpen("wardrobe.filter")
                }
        }
    }
    
    @ViewBuilder
    private func buildFilterSection(for field: ClothingField) -> some View {
        switch field {
        case .types:
            // menu-perf: wardrobe type filter submenu
            FilterSubmenuView(
                field: field,
                options: menuFacetCache.options(for: field),
                noValueMarker: HomeView.noTypeMarker,
                selection: $selectedTypes
            )
        case .colors:
            // menu-perf: wardrobe color filter submenu
            FilterSubmenuView(
                field: field,
                options: menuFacetCache.options(for: field),
                noValueMarker: HomeView.noColorMarker,
                selection: $selectedColors
            )
        case .sizes:
            // menu-perf: wardrobe size filter submenu
            FilterSubmenuView(
                field: field,
                options: menuFacetCache.options(for: field),
                noValueMarker: HomeView.noSizeMarker,
                selection: $selectedSizes
            )
        case .length:
            // menu-perf: wardrobe length filter submenu
            FilterSubmenuView(
                field: field,
                options: menuFacetCache.options(for: field),
                noValueMarker: HomeView.noLengthMarker,
                selection: $selectedLengths
            )
        case .condition:
            // menu-perf: wardrobe condition filter submenu
            FilterSubmenuView(
                field: field,
                options: menuFacetCache.options(for: field),
                noValueMarker: HomeView.noConditionMarker,
                selection: $selectedConditions
            )
        case .accessories:
            // menu-perf: wardrobe accessory filter submenu
            FilterSubmenuView(
                field: field,
                options: menuFacetCache.options(for: field),
                noValueMarker: HomeView.noAccessoryMarker,
                selection: $selectedAccessories
            )
        }
    }
    
    private var displayButton: some View {
        // menu-perf: wardrobe display menu
        Menu {
            let _ = MenuPerfSignpost.menuContent("wardrobe.display")
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
            HomeThemeSkinToolbarIconShell(descriptor: themedTopBarButtonDescriptor) {
                Image(systemName: selectedTab == .wardrobe ? viewLayout.icon : depositDisplayMode.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(topBarIconForeground)
            }
            .onTapGesture {
                _ = MenuPerfSignpost.menuOpen("wardrobe.display")
            }
        }
    }

    // 标记是否从草稿继续
    @State private var continueFromDraft = false
    @State private var pendingActivityDraft: ClothingEditDraft?

    private func notifyWardrobeAddMenuOpened() {
        NotificationCenter.default.post(name: .wardrobeAddMenuOpened, object: nil)
    }

    private func notifyWardrobeMoreMenuOpened() {
        NotificationCenter.default.post(name: .wardrobeMoreMenuOpened, object: nil)
    }

    private var moreMenuIcon: some View {
        HomeThemeSkinToolbarIconShell(descriptor: themedTopBarButtonDescriptor) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 12))
                .foregroundStyle(topBarIconForeground)
                .captureGuideToolbarIconTarget(.wardrobeMoreMenuButton)
        }
    }

    @ViewBuilder
    private var wardrobeMoreMenuContent: some View {
        Button {
            openWardrobeSearch()
        } label: {
            HomeThemeSkinSearchMenuLabel(
                descriptor: themedSearchEntryDescriptor,
                title: "搜索",
                systemImage: "magnifyingglass"
            )
        }

        if selectedTab == .wardrobe {
            Divider()

            if !isSelectionMode {
                Button {
                    enterWardrobeSelectionMode()
                } label: {
                    Label("编辑", systemImage: "pencil.circle")
                }
                .captureGuideTarget(.wardrobeEditMenuEntry)
            }

            if sortOption == .custom && !isEditing {
                Button {
                    startWardrobeCustomSortEditing()
                } label: {
                    Label("调整顺序", systemImage: "list.number")
                }
            }
        }
    }

    private func openWardrobeSearch() {
        DispatchQueue.main.async {
            isSearchActive = true
            isWardrobeSearchFocused = true
        }
    }

    private func enterWardrobeSelectionMode() {
        withAnimation {
            isSelectionMode = true
        }
    }

    private func startWardrobeCustomSortEditing() {
        withAnimation {
            isEditing = true
        }
    }

    private func presentWardrobeMoreGuideMenu() {
        notifyWardrobeMoreMenuOpened()
        guideManager.presentGuideMenu(
            GuideMenuPresentationState(
                scenario: .wardrobeMore,
                anchorKey: .wardrobeMoreMenuButton,
                width: 240,
                submenuDepth: 0,
                items: wardrobeMoreGuideMenuItems()
            )
        )
    }

    private func wardrobeMoreGuideMenuItems() -> [GuideMenuItem] {
        var items: [GuideMenuItem] = [
            .action(
                title: "搜索",
                systemImage: "magnifyingglass",
                action: openWardrobeSearch
            )
        ]

        if selectedTab == .wardrobe {
            items.append(.divider)

            if !isSelectionMode {
                items.append(
                    .action(
                        title: "编辑",
                        systemImage: "pencil.circle",
                        isHighlighted: true,
                        action: enterWardrobeSelectionMode
                    )
                )
            }

            if sortOption == .custom && !isEditing {
                items.append(
                    .action(
                        title: "调整顺序",
                        systemImage: "list.number",
                        action: startWardrobeCustomSortEditing
                    )
                )
            }
        }

        return items
    }

    private func continueWardrobeDraft() {
        pendingActivityDraft = nil
        continueFromDraft = true
        showingAddSheet = true
    }

    private func presentWardrobeManualCreate() {
        // 手动创建是一次“重新开始”动作，只在入口点击时清理旧草稿；
        // 前后台切换导致的编辑页重建不应再次清空。
        draftManager.clearDraft()
        pendingActivityDraft = nil
        continueFromDraft = false
        showingAddSheet = true
    }

    private func continueClothingEditUserActivity(_ activity: NSUserActivity) {
        guard let payload = ClothingEditUserActivity.payload(from: activity) else {
            AppLogger.error("DraftReliability: Missing clothing edit user activity payload")
            return
        }

        selectedTab = .wardrobe
        if payload.isEditing, let clothingID = payload.clothingID {
            draftManager.saveEditingDraft(payload.draft, for: clothingID, reason: "userActivity-continue")
            pendingActivityDraft = nil
            continueFromDraft = false
            showingAddSheet = false
            return
        }

        draftManager.saveDraft(payload.draft, reason: "userActivity-continue")
        pendingActivityDraft = payload.draft
        continueFromDraft = true
        showingAddSheet = true
    }

    private func presentCommunityImportAlert() {
        showingCommunityImportAlert = true
    }

    @ViewBuilder
    private var wardrobeAddMenuContent: some View {
        if draftManager.hasPersistedDraft {
            Button {
                continueWardrobeDraft()
            } label: {
                Label("从上次未保存继续", systemImage: "doc.badge.clock")
            }

            Divider()
        }

        Button {
            presentWardrobeManualCreate()
        } label: {
            Label("手动创建", systemImage: "square.and.pencil")
        }
        .captureGuideTarget(.wardrobeManualCreateEntry)

        Button {
            presentBatchImport()
        } label: {
            Label("批量导入", systemImage: "square.and.arrow.down.on.square")
        }
        .captureGuideTarget(.wardrobeBatchImportEntry)

        if networkManager.canShowNetworkUI() {
            Button {
                presentCommunityImportAlert()
            } label: {
                Label("从社区导入", systemImage: "icloud.and.arrow.down")
            }
        }
    }

    private func presentWardrobeAddGuideMenu() {
        notifyWardrobeAddMenuOpened()
        guideManager.presentGuideMenu(
            GuideMenuPresentationState(
                scenario: .wardrobeAdd,
                anchorKey: .wardrobeAddButton,
                width: 250,
                submenuDepth: 0,
                items: wardrobeAddGuideMenuItems()
            )
        )
    }

    private func wardrobeAddGuideMenuItems() -> [GuideMenuItem] {
        var items: [GuideMenuItem] = []
        let feature = guideManager.currentFeatureExperienceFeature
        let highlightBatchImport = feature == .batchImport && FeatureUnlockManager.shared.isUnlocked(.batchImport)
        let highlightManualCreate = feature == .batchImport && !highlightBatchImport

        if draftManager.hasPersistedDraft {
            items.append(
                .action(
                    title: "从上次未保存继续",
                    systemImage: "doc.badge.clock",
                    action: continueWardrobeDraft
                )
            )
            items.append(.divider)
        }

        items.append(
            .action(
                title: "手动创建",
                systemImage: "square.and.pencil",
                isHighlighted: highlightManualCreate,
                action: presentWardrobeManualCreate
            )
        )
        items.append(
            .action(
                title: "批量导入",
                systemImage: "square.and.arrow.down.on.square",
                isHighlighted: highlightBatchImport,
                action: presentBatchImport
            )
        )

        if networkManager.canShowNetworkUI() {
            items.append(
                .action(
                    title: "从社区导入",
                    systemImage: "icloud.and.arrow.down",
                    action: presentCommunityImportAlert
                )
            )
        }

        return items
    }
    
    private var addButton: some View {
        Group {
            if guideManager.shouldUseCustomGuideMenu(for: .wardrobeAdd) {
                Button {
                    presentWardrobeAddGuideMenu()
                } label: {
                    addButtonIcon
                }
            } else {
                // menu-perf: wardrobe add menu
                Menu {
                    let _ = MenuPerfSignpost.menuContent("wardrobe.add")
                    wardrobeAddMenuContent
                } label: {
                    addButtonIcon
                        .onTapGesture {
                            _ = MenuPerfSignpost.menuOpen("wardrobe.add")
                            notifyWardrobeAddMenuOpened()
                        }
                }
            }
        }
        .alert("该功能敬请期待，联网版本激情开拓中～！", isPresented: $showingCommunityImportAlert) {
            Button("好的", role: .cancel) { }
        }
    }

    private var addButtonIcon: some View {
        HomeThemeSkinToolbarIconShell(descriptor: themedTopBarAddButtonDescriptor) {
            Image(systemName: "plus")
                .font(.system(size: 12))
                .foregroundStyle(topBarIconForeground)
                .captureGuideToolbarIconTarget(.wardrobeAddButton)
        }
    }

    private func themeDescriptor(
        for slot: ThemeSkinSlot,
        fallbackIfUnsupported fallbackSlot: ThemeSkinSlot? = nil
    ) -> ThemeSkinDescriptor? {
        if let descriptor = resolveThemeDescriptor(for: slot) {
            return descriptor
        }

        guard !themeSkinManager.isSlotSupported(slot), let fallbackSlot else {
            return nil
        }

        return resolveThemeDescriptor(for: fallbackSlot)
    }

    private func resolveThemeDescriptor(for slot: ThemeSkinSlot) -> ThemeSkinDescriptor? {
        guard let descriptor = themeSkinManager.activeThemeDescriptor(for: slot, state: .default),
              WardrobeThemeSkinSupport.isThemeSkinDescriptor(descriptor) else {
            return nil
        }
        return descriptor
    }

    private func presentBatchImport() {
        if FeatureUnlockManager.shared.isUnlocked(.batchImport) {
            showingBatchImportSheet = true
            return
        }

        batchImportUnlockAlert = FeatureUnlockManager.shared.makeAlertItem(for: .batchImport)
    }

    private func unlockBatchImportAndPresent() {
        let manager = FeatureUnlockManager.shared
        switch manager.unlock(.batchImport) {
        case .success, .alreadyUnlocked:
            showingBatchImportSheet = true
        case .conditionNotMet:
            batchImportUnlockAlert = manager.makeAlertItem(for: .batchImport)
        case .insufficientResource(let type, let required, let current):
            let condition = manager.getCondition(for: .batchImport)
            batchImportUnlockAlert = FeatureUnlockAlert(
                feature: .batchImport,
                condition: condition,
                canUnlock: false,
                message: "\(type)不足：当前 \(current)，需要 \(required)"
            )
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
                } else if let tagName = menuFacetCache.tagNameByID[id] {
                    names.append(tagName)
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
                } else if let brandName = menuFacetCache.brandNameByID[id] {
                    names.append(brandName)
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
            for c in allClothings where c.isFinalPaymentPlan {
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
