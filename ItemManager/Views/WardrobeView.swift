//
//  WardrobeView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private struct WardrobeClothingRevision: Hashable {
    let id: UUID
    let updatedAt: Date
    let lastModified: Date
    let deletedAt: Date?
    let sortIndex: Int
}

private struct WardrobeFilterSignature: Hashable {
    let searchText: String
    let selectedTagIDs: [UUID]
    let selectedBrandIDs: [UUID]
    let selectedTypes: [String]
    let selectedColors: [String]
    let selectedSizes: [String]
    let selectedLengths: [String]
    let selectedConditions: [String]
    let selectedAccessories: [String]
    let depositStatusFilterRawValue: String
    let sortOptionRawValue: String
    let privacyShowPrice: Bool
    let privacyShowOriginalPrice: Bool
    let clothingRevisions: [WardrobeClothingRevision]

    init(
        searchText: String,
        selectedTagIDs: Set<UUID>,
        selectedBrandIDs: Set<UUID>,
        selectedTypes: Set<String>,
        selectedColors: Set<String>,
        selectedSizes: Set<String>,
        selectedLengths: Set<String>,
        selectedConditions: Set<String>,
        selectedAccessories: Set<String>,
        depositStatusFilterRawValue: String,
        sortOptionRawValue: String,
        privacyShowPrice: Bool,
        privacyShowOriginalPrice: Bool,
        clothingRevisions: [WardrobeClothingRevision]
    ) {
        self.searchText = searchText
        self.selectedTagIDs = selectedTagIDs.sorted { $0.uuidString < $1.uuidString }
        self.selectedBrandIDs = selectedBrandIDs.sorted { $0.uuidString < $1.uuidString }
        self.selectedTypes = selectedTypes.sorted()
        self.selectedColors = selectedColors.sorted()
        self.selectedSizes = selectedSizes.sorted()
        self.selectedLengths = selectedLengths.sorted()
        self.selectedConditions = selectedConditions.sorted()
        self.selectedAccessories = selectedAccessories.sorted()
        self.depositStatusFilterRawValue = depositStatusFilterRawValue
        self.sortOptionRawValue = sortOptionRawValue
        self.privacyShowPrice = privacyShowPrice
        self.privacyShowOriginalPrice = privacyShowOriginalPrice
        self.clothingRevisions = clothingRevisions
    }
}

private struct WardrobeClothingSnapshot: Sendable {
    let id: UUID
    let name: String
    let brandID: UUID?
    let brandName: String?
    let tagIDs: Set<UUID>
    let tagNames: [String]
    let types: String
    let colors: String
    let sizes: String
    let length: String
    let condition: String
    let accessories: String
    let note: String
    let price: Decimal
    let inventoryTotalPrice: Decimal
    let stock: Int
    let isDepositPlan: Bool
    let sortIndex: Int
    let purchaseDate: Date
    let createdAt: Date
    let deletedAt: Date?

    @MainActor
    init(clothing: Clothing) {
        self.id = clothing.id
        self.name = clothing.name
        self.brandID = clothing.brand?.id
        self.brandName = clothing.brand?.name
        self.tagIDs = Set(clothing.tags?.map { $0.id } ?? [])
        self.tagNames = clothing.tags?.map { $0.name } ?? []
        self.types = clothing.types
        self.colors = clothing.colors
        self.sizes = clothing.sizes
        self.length = clothing.length
        self.condition = clothing.condition
        self.accessories = clothing.accessories
        self.note = clothing.note
        self.price = clothing.price
        self.inventoryTotalPrice = clothing.inventoryTotalPrice
        self.stock = clothing.stock
        self.isDepositPlan = clothing.isDepositPlan
        self.sortIndex = clothing.sortIndex
        self.purchaseDate = clothing.purchaseDate
        self.createdAt = clothing.createdAt
        self.deletedAt = clothing.deletedAt
    }
}

private struct WardrobeFilterInput: Sendable {
    let snapshots: [WardrobeClothingSnapshot]
    let searchText: String
    let selectedTagIDs: Set<UUID>
    let selectedBrandIDs: Set<UUID>
    let selectedTypes: Set<String>
    let selectedColors: Set<String>
    let selectedSizes: Set<String>
    let selectedLengths: Set<String>
    let selectedConditions: Set<String>
    let selectedAccessories: Set<String>
    let depositStatusFilterRawValue: String
    let sortOptionRawValue: String
}

struct WardrobeStatsSummary: Equatable, Sendable {
    var styleCount: Int
    var totalCount: Int
    var dressValue: Decimal
    var totalValue: Decimal

    nonisolated static let empty = WardrobeStatsSummary(
        styleCount: 0,
        totalCount: 0,
        dressValue: Decimal(0),
        totalValue: Decimal(0)
    )
}

private struct WardrobeFilterResult: Sendable {
    let ids: [UUID]
    let stats: WardrobeStatsSummary
    let conditionOptions: [String]
}

private enum WardrobeFilterEngine {
    nonisolated static func evaluate(_ input: WardrobeFilterInput) -> WardrobeFilterResult {
        if Task.isCancelled {
            return WardrobeFilterResult(ids: [], stats: .empty, conditionOptions: ["全新"])
        }

        var result = input.snapshots.filter { $0.deletedAt == nil }
        let query = input.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !query.isEmpty {
            result = result.filter { matchesSearch($0, query: query) }
        }

        result = result.filter { snapshot in
            matchesTag(snapshot, selectedTagIDs: input.selectedTagIDs) &&
            matchesBrand(snapshot, selectedBrandIDs: input.selectedBrandIDs) &&
            matchesStringField(snapshot.types, selectedValues: input.selectedTypes, emptyMarker: "__NO_TYPE__") &&
            matchesStringField(snapshot.colors, selectedValues: input.selectedColors, emptyMarker: "__NO_COLOR__") &&
            matchesStringField(snapshot.sizes, selectedValues: input.selectedSizes, emptyMarker: "__NO_SIZE__") &&
            matchesStringField(snapshot.length, selectedValues: input.selectedLengths, emptyMarker: "__NO_LENGTH__") &&
            matchesStringField(snapshot.condition, selectedValues: input.selectedConditions, emptyMarker: "__NO_CONDITION__") &&
            matchesStringField(snapshot.accessories, selectedValues: input.selectedAccessories, emptyMarker: "__NO_ACCESSORY__") &&
            matchesDepositStatus(snapshot, rawValue: input.depositStatusFilterRawValue)
        }

        result = sorted(result, sortOptionRawValue: input.sortOptionRawValue)
        let stats = statsSummary(for: result)
        let conditionOptions = conditionOptions(from: input.snapshots)

        return WardrobeFilterResult(
            ids: result.map(\.id),
            stats: stats,
            conditionOptions: conditionOptions
        )
    }

    private nonisolated static func matchesSearch(_ snapshot: WardrobeClothingSnapshot, query: String) -> Bool {
        if let (minPrice, maxPrice) = parsePriceRange(from: query) {
            let clothingPrice = NSDecimalNumber(decimal: snapshot.price).doubleValue
            return clothingPrice >= minPrice && clothingPrice <= maxPrice
        }

        let stockMatch: Bool
        if let searchStock = Int(query.trimmingCharacters(in: .whitespaces)), searchStock > 0 {
            stockMatch = snapshot.stock == searchStock
        } else {
            stockMatch = false
        }

        return snapshot.name.localizedCaseInsensitiveContains(query) ||
            (snapshot.brandName?.localizedCaseInsensitiveContains(query) ?? false) ||
            snapshot.tagNames.contains { $0.localizedCaseInsensitiveContains(query) } ||
            snapshot.types.localizedCaseInsensitiveContains(query) ||
            snapshot.colors.localizedCaseInsensitiveContains(query) ||
            snapshot.sizes.localizedCaseInsensitiveContains(query) ||
            snapshot.length.localizedCaseInsensitiveContains(query) ||
            snapshot.condition.localizedCaseInsensitiveContains(query) ||
            snapshot.accessories.localizedCaseInsensitiveContains(query) ||
            snapshot.note.localizedCaseInsensitiveContains(query) ||
            stockMatch
    }

    private nonisolated static func parsePriceRange(from searchText: String) -> (min: Double, max: Double)? {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        let separators = ["-", "~", "到", " "]

        for separator in separators {
            let components = trimmed.components(separatedBy: separator)
            if components.count == 2,
               let min = Double(components[0].trimmingCharacters(in: .whitespaces)),
               let max = Double(components[1].trimmingCharacters(in: .whitespaces)) {
                return (min, max)
            }
        }

        return nil
    }

    private nonisolated static func matchesTag(_ snapshot: WardrobeClothingSnapshot, selectedTagIDs: Set<UUID>) -> Bool {
        let noTagUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        if selectedTagIDs.isEmpty {
            return true
        } else if selectedTagIDs.contains(noTagUUID) {
            return snapshot.tagIDs.isEmpty
        } else {
            return !selectedTagIDs.isDisjoint(with: snapshot.tagIDs)
        }
    }

    private nonisolated static func matchesBrand(_ snapshot: WardrobeClothingSnapshot, selectedBrandIDs: Set<UUID>) -> Bool {
        let noBrandUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        if selectedBrandIDs.isEmpty {
            return true
        } else if selectedBrandIDs.contains(noBrandUUID) {
            return snapshot.brandID == nil
        } else if let brandID = snapshot.brandID {
            return selectedBrandIDs.contains(brandID)
        } else {
            return false
        }
    }

    private nonisolated static func matchesStringField(_ value: String, selectedValues: Set<String>, emptyMarker: String) -> Bool {
        if selectedValues.isEmpty {
            return true
        } else if selectedValues.contains(emptyMarker) {
            return value.isEmpty
        } else {
            return !selectedValues.isDisjoint(with: splitValues(value))
        }
    }

    private nonisolated static func matchesDepositStatus(_ snapshot: WardrobeClothingSnapshot, rawValue: String) -> Bool {
        switch rawValue {
        case "owned":
            return !snapshot.isDepositPlan
        case "depositPlan":
            return snapshot.isDepositPlan
        default:
            return true
        }
    }

    private nonisolated static func sorted(_ snapshots: [WardrobeClothingSnapshot], sortOptionRawValue: String) -> [WardrobeClothingSnapshot] {
        switch sortOptionRawValue {
        case "自定义顺序":
            return snapshots.sorted { $0.sortIndex < $1.sortIndex }
        case "价格从低到高":
            return snapshots.sorted { $0.price < $1.price }
        case "价格从高到低":
            return snapshots.sorted { $0.price > $1.price }
        case "名称从A到Z":
            return snapshots.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case "名称从Z到A":
            return snapshots.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case "购买时间从早到晚":
            return snapshots.sorted { $0.purchaseDate < $1.purchaseDate }
        case "购买时间从晚到早":
            return snapshots.sorted { $0.purchaseDate > $1.purchaseDate }
        default:
            return snapshots.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private nonisolated static func statsSummary(for snapshots: [WardrobeClothingSnapshot]) -> WardrobeStatsSummary {
        snapshots.reduce(into: WardrobeStatsSummary.empty) { partial, snapshot in
            partial.styleCount += 1
            partial.totalCount += snapshot.stock
            partial.dressValue += snapshot.price * Decimal(snapshot.stock)
            partial.totalValue += snapshot.inventoryTotalPrice
        }
    }

    private nonisolated static func conditionOptions(from snapshots: [WardrobeClothingSnapshot]) -> [String] {
        let values = snapshots
            .flatMap { splitValues($0.condition) }
            .filter { !$0.isEmpty }
        let options = Array(Set(values)).sorted()
        return options.isEmpty ? ["全新"] : options
    }

    private nonisolated static func splitValues(_ string: String) -> Set<String> {
        let normalized = string.replacingOccurrences(of: "，", with: ",")
        return Set(normalized.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }
}

private struct WardrobeVisibleItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct BatchEditDraft: Equatable {
    var selectedTags: [Tag] = []
    var selectedBrand: Brand?
    var selectedColors: [String] = []
    var selectedSizes: [String] = []
    var selectedLengths: [String] = []
    var selectedAccessories: [String] = []
    var selectedCondition: String?

    static func == (lhs: BatchEditDraft, rhs: BatchEditDraft) -> Bool {
        lhs.selectedTags.map(\.id) == rhs.selectedTags.map(\.id) &&
            lhs.selectedBrand?.id == rhs.selectedBrand?.id &&
            lhs.selectedColors == rhs.selectedColors &&
            lhs.selectedSizes == rhs.selectedSizes &&
            lhs.selectedLengths == rhs.selectedLengths &&
            lhs.selectedAccessories == rhs.selectedAccessories &&
            lhs.selectedCondition == rhs.selectedCondition
    }
}

struct WardrobeView: View {
    @Binding var searchText: String
    @Binding var isSelectionMode: Bool
    @Binding var isEditing: Bool
    @Environment(\.modelContext) private var modelContext
    @Query private var clothings: [Clothing]
    @State private var showStats = true
    @State private var filteredClothings: [Clothing] = []
    @State private var cellSnapshotCache: [UUID: WardrobeCellSnapshot] = [:]
    @State private var filteredStatsSummary: WardrobeStatsSummary = .empty
    @State private var conditionBatchOptionsCache: [String] = ["全新"]
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @AppStorage("privacyShowPrice") private var showPrice = true
    @AppStorage("privacyShowOriginalPrice") private var showOriginalPrice = true
    
    // Edit Mode States
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var editableClothings: [Clothing] = []
    @State private var draggingItem: Clothing?
    
    // Batch Actions States
    @State private var showingDeleteAlert = false
    @State private var showingBatchCopyAlert = false
    @State private var batchEditDraft = BatchEditDraft()
    @State private var showingTagSelection = false
    @State private var showingAddTagsConfirmation = false
    @State private var showingBrandSelection = false
    @State private var showingSetBrandConfirmation = false
    
    // Batch Edit States
    @State private var showingColorSelection = false
    @State private var showingSizeSelection = false
    @State private var showingLengthSelection = false
    @State private var showingAccessorySelection = false
    @State private var showingConditionSelection = false
    
    // 合并为小物到裙装
    @State private var showingMergeToAccessorySheet = false
    @State private var targetClothingForMerge: Clothing? = nil
    @State private var showingMergeConfirmation = false
    @State private var showingDeleteAfterMergeConfirmation = false
    @State private var mergedItemCount = 0
    
    // Context Menu Actions
    @State private var itemToDelete: Clothing?
    @State private var showingDeleteSingleAlert = false
    @State private var itemToCopy: Clothing?
    @State private var showingCopyAlert = false
    @State private var detailNavigationTarget: Clothing?
    @State private var isShowingDetailNavigation = false
    
    // Auto-scroll
    @State private var visibleItemIDs: Set<UUID> = []
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var visibleItemFrameUpdateTask: Task<Void, Never>?
    
    // Layout
    let viewLayout: HomeView.ViewLayout
    let sortOption: SortOption
    
    // Filter properties
    let selectedTagIDs: Set<UUID>
    let selectedBrandIDs: Set<UUID>
    let selectedTypes: Set<String>
    let selectedColors: Set<String>
    let selectedSizes: Set<String>
    let selectedLengths: Set<String>
    let selectedConditions: Set<String>
    let selectedAccessories: Set<String>
    let depositStatusFilter: DepositStatusFilter

    // Filter Actions
    let filterDescription: String?
    let onClearFilter: (() -> Void)?
    
    init(searchText: Binding<String>,
         isSelectionMode: Binding<Bool>,
         isEditing: Binding<Bool>,
         sortOption: SortOption,
         viewLayout: HomeView.ViewLayout,
         selectedTagIDs: Set<UUID>,
         selectedBrandIDs: Set<UUID>,
         selectedTypes: Set<String>,
         selectedColors: Set<String>,
         selectedSizes: Set<String>,
         selectedLengths: Set<String>,
         selectedConditions: Set<String>,
         selectedAccessories: Set<String>,
         depositStatusFilter: DepositStatusFilter,
         filterDescription: String? = nil,
         onClearFilter: (() -> Void)? = nil) {
        _searchText = searchText
        _isSelectionMode = isSelectionMode
        _isEditing = isEditing
        self.sortOption = sortOption
        _clothings = Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }, sort: sortOption.sortDescriptors)
        self.viewLayout = viewLayout

        self.selectedTagIDs = selectedTagIDs
        self.selectedBrandIDs = selectedBrandIDs
        self.selectedTypes = selectedTypes
        self.selectedColors = selectedColors
        self.selectedSizes = selectedSizes
        self.selectedLengths = selectedLengths
        self.selectedConditions = selectedConditions
        self.selectedAccessories = selectedAccessories
        self.depositStatusFilter = depositStatusFilter

        self.filterDescription = filterDescription
        self.onClearFilter = onClearFilter
    }
    
    // Grid layout
    private var gridColumns: [GridItem] {
        let count: Int
        let spacing: CGFloat
        switch viewLayout {
        case .grid2: 
            count = 2
            spacing = 16
        case .grid3: 
            count = 3
            spacing = 16
        case .grid6: 
            count = 6
            spacing = 2
        default: 
            count = 1
            spacing = 16
        }
        return Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
    }
    
    @ViewBuilder
    private func clothingItemView(clothing: Clothing, firstFilteredID: UUID?) -> some View {
        let snapshot = cellSnapshot(for: clothing)
        if viewLayout == .grid6 {
            guideSelectionAnchor(for: clothing, firstFilteredID: firstFilteredID) {
                ClothingThumbnail(
                    snapshot: snapshot,
                    imageTargetSize: wardrobeCellImageTargetSize
                )
            }
            .background(visibleItemFrameReporter(for: clothing))
        } else {
            guideSelectionAnchor(for: clothing, firstFilteredID: firstFilteredID) {
                ClothingCard(
                    snapshot: snapshot,
                    showPrice: showPrice,
                    showOriginalPrice: showOriginalPrice,
                    wardrobeThemeDescriptor: wardrobeThemeDescriptor,
                    imageTargetSize: wardrobeCellImageTargetSize
                )
            }
            .background(visibleItemFrameReporter(for: clothing))
        }
    }

    @ViewBuilder
    private func visibleItemFrameReporter(for clothing: Clothing) -> some View {
        if isReorderTrackingEnabled {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: WardrobeVisibleItemFramePreferenceKey.self,
                    value: [clothing.id: proxy.frame(in: .global)]
                )
            }
        }
    }

    @ViewBuilder
    private func guideSelectionAnchor<Content: View>(for clothing: Clothing, firstFilteredID: UUID?, @ViewBuilder content: () -> Content) -> some View {
        if clothing.id == firstFilteredID {
            content()
                .captureGuideTarget(.wardrobeSelectionCard)
        } else {
            content()
        }
    }
    
    @ViewBuilder
    private func clothingRowView(clothing: Clothing) -> some View {
        let snapshot = cellSnapshot(for: clothing)
        if viewLayout == .listBrief {
            ClothingRowBrief(
                snapshot: snapshot,
                showPrice: showPrice,
                showOriginalPrice: showOriginalPrice,
                wardrobeThemeDescriptor: wardrobeThemeDescriptor
            )
        } else {
            ClothingRow(
                snapshot: snapshot,
                showPrice: showPrice,
                showOriginalPrice: showOriginalPrice,
                wardrobeThemeDescriptor: wardrobeThemeDescriptor
            )
        }
    }

    @MainActor
    private func cellSnapshot(for clothing: Clothing) -> WardrobeCellSnapshot {
        cellSnapshotCache[clothing.id] ?? WardrobeCellSnapshot(clothing: clothing)
    }
    
    private var wardrobeThemeDescriptor: ThemeSkinDescriptor? {
        themeSkinManager.descriptor(for: .wardrobeItemCard)
    }

    private var filterSignature: WardrobeFilterSignature {
        WardrobeFilterSignature(
            searchText: searchText,
            selectedTagIDs: selectedTagIDs,
            selectedBrandIDs: selectedBrandIDs,
            selectedTypes: selectedTypes,
            selectedColors: selectedColors,
            selectedSizes: selectedSizes,
            selectedLengths: selectedLengths,
            selectedConditions: selectedConditions,
            selectedAccessories: selectedAccessories,
            depositStatusFilterRawValue: depositStatusFilter.rawValue,
            sortOptionRawValue: sortOption.rawValue,
            privacyShowPrice: showPrice,
            privacyShowOriginalPrice: showOriginalPrice,
            clothingRevisions: clothings.map { clothing in
                WardrobeClothingRevision(
                    id: clothing.id,
                    updatedAt: clothing.updatedAt,
                    lastModified: clothing.lastModified,
                    deletedAt: clothing.deletedAt,
                    sortIndex: clothing.sortIndex
                )
            }
        )
    }

    private var conditionBatchOptions: [String] {
        conditionBatchOptionsCache
    }
    
    var body: some View {
        applyAlerts(to:
            applySheets(to:
                applyBottomSelectionBar(to:
                    applyStateChangeHandlers(to: baseWardrobeView)
                )
            )
        )
    }

    private var baseWardrobeView: some View {
        Group {
            switch viewLayout {
            case .listBrief, .listDetailed:
                listView
            case .grid2, .grid3, .grid6:
                gridWardrobeView
            }
        }
        .toolbar {
        }
        .containerAdaptiveColors(background: .ultraThinMaterial)
        .navigationDestination(isPresented: $isShowingDetailNavigation) {
            if let detailNavigationTarget {
                ClothingDetailView(clothing: detailNavigationTarget)
            }
        }
    }

    private func applyStateChangeHandlers<Content: View>(to content: Content) -> some View {
        content
            .onChange(of: isEditing) { _, newValue in
                if newValue {
                    if editableClothings.isEmpty {
                        editableClothings = filteredClothings
                    }
                } else {
                    saveOrder()
                    visibleItemIDs.removeAll()
                    if !(isSelectionMode && (sortOption == .custom || isEditing)) {
                        editableClothings = []
                    }
                }
            }
            .onChange(of: isSelectionMode) { _, newValue in
                if newValue {
                    if (sortOption == .custom || isEditing) && editableClothings.isEmpty {
                        editableClothings = filteredClothings
                    }
                } else {
                    selectedItemIDs.removeAll()
                    if !isEditing {
                        visibleItemIDs.removeAll()
                    }
                    if (sortOption == .custom || isEditing) && !isEditing {
                        saveOrder()
                        editableClothings = []
                    }
                }
            }
            .onChange(of: selectedItemIDs) { _, newValue in
                NotificationCenter.default.post(
                    name: .wardrobeSelectionChanged,
                    object: nil,
                    userInfo: ["selectedCount": newValue.count]
                )
            }
            .task(id: filterSignature) {
                await rebuildFilteredClothings()
            }
            .onChange(of: viewLayout) { oldLayout, _ in
                ImageManager.shared.evictCachedImages(targetSize: wardrobeCellImageTargetSize(for: oldLayout))
                prefetchInitialWardrobeImages(filteredClothings)
            }
            .onDisappear {
                visibleItemFrameUpdateTask?.cancel()
                visibleItemFrameUpdateTask = nil
            }
    }

    private func applyBottomSelectionBar<Content: View>(to content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if isSelectionMode {
                selectionModeBottomBar
            }
        }
    }

    private var selectionModeBottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("删除")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(selectedItemIDs.isEmpty)

                Divider()
                    .frame(height: 20)

                Button {
                    showingBatchCopyAlert = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("复制")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(selectedItemIDs.isEmpty)

                Divider()
                    .frame(height: 20)

                // menu-perf: wardrobe batch edit more menu
                Menu {
                    let _ = MenuPerfSignpost.menuContent("wardrobe.batch.more")
                    Button {
                        batchEditDraft.selectedTags = []
                        showingTagSelection = true
                    } label: {
                        Label("添加标签", systemImage: "tag")
                    }

                    Button {
                        batchEditDraft.selectedBrand = nil
                        showingBrandSelection = true
                    } label: {
                        Label("归类品牌", systemImage: "bag")
                    }

                    Divider()

                    Button {
                        batchEditDraft.selectedColors = []
                        showingColorSelection = true
                    } label: {
                        Label("染上颜色", systemImage: "paintbrush")
                    }

                    Button {
                        batchEditDraft.selectedSizes = []
                        showingSizeSelection = true
                    } label: {
                        Label("变换尺码", systemImage: "ruler")
                    }

                    Button {
                        batchEditDraft.selectedLengths = []
                        showingLengthSelection = true
                    } label: {
                        Label("设置衣长", systemImage: "lines.measurement.vertical")
                    }

                    Button {
                        batchEditDraft.selectedAccessories = []
                        showingAccessorySelection = true
                    } label: {
                        Label("搭配小物", systemImage: "sparkles")
                    }

                    Button {
                        batchEditDraft.selectedCondition = nil
                        showingConditionSelection = true
                    } label: {
                        Label("改变成色", systemImage: "arrow.2.circlepath")
                    }

                    Divider()

                    Button {
                        showingMergeToAccessorySheet = true
                    } label: {
                        Label("合并为小物到裙装", systemImage: "arrow.down.square")
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "ellipsis.circle")
                        Text("更多")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        _ = MenuPerfSignpost.menuOpen("wardrobe.batch.more")
                    }
                }
                .disabled(selectedItemIDs.isEmpty)

                Divider()
                    .frame(height: 20)

                Button {
                    toggleSelectAll()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isAllSelectedInView ? "xmark.circle" : "checkmark.circle")
                        Text(isAllSelectedInView ? "取消全选" : "全选")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(filteredClothings.isEmpty)
            }
            .padding()
            .padding(.bottom, {
                let version = UIDevice.current.systemVersion
                let majorVersion = Int(version.split(separator: ".").first ?? "0") ?? 0
                return majorVersion <= 18 ? 60 : 0
            }())
            .background(.regularMaterial)
        }
        .captureGuideTarget(.wardrobeBatchEditToolbar)
    }

    private func applySheets<Content: View>(to content: Content) -> some View {
        content
            .sheet(isPresented: $showingTagSelection) {
                TagSelectionView(selectedTags: $batchEditDraft.selectedTags)
                    .onDisappear {
                        if !batchEditDraft.selectedTags.isEmpty {
                            showingAddTagsConfirmation = true
                        }
                    }
            }
            .sheet(isPresented: $showingBrandSelection) {
                BrandSelectionView(selectedBrand: $batchEditDraft.selectedBrand)
                    .onDisappear {
                        if batchEditDraft.selectedBrand != nil {
                            showingSetBrandConfirmation = true
                        }
                    }
            }
            .sheet(isPresented: $showingColorSelection) {
                BatchStringSelectionView(
                    title: "染上颜色",
                    options: SuggestionManager.shared.getAllColors(),
                    selectedItems: $batchEditDraft.selectedColors
                )
                .onDisappear {
                    if !batchEditDraft.selectedColors.isEmpty {
                        batchSetColors(batchEditDraft.selectedColors)
                    }
                }
            }
            .sheet(isPresented: $showingSizeSelection) {
                BatchStringSelectionView(
                    title: "变换尺码",
                    options: SuggestionManager.shared.getAllSizes(),
                    selectedItems: $batchEditDraft.selectedSizes
                )
                .onDisappear {
                    if !batchEditDraft.selectedSizes.isEmpty {
                        batchSetSizes(batchEditDraft.selectedSizes)
                    }
                }
            }
            .sheet(isPresented: $showingLengthSelection) {
                BatchStringSelectionView(
                    title: "设置衣长",
                    options: SuggestionManager.shared.getAllLengths(),
                    selectedItems: $batchEditDraft.selectedLengths
                )
                .onDisappear {
                    if !batchEditDraft.selectedLengths.isEmpty {
                        batchSetLengths(batchEditDraft.selectedLengths)
                    }
                }
            }
            .sheet(isPresented: $showingAccessorySelection) {
                BatchStringSelectionView(
                    title: "搭配小物",
                    options: SuggestionManager.shared.getAllAccessories(),
                    selectedItems: $batchEditDraft.selectedAccessories
                )
                .onDisappear {
                    if !batchEditDraft.selectedAccessories.isEmpty {
                        batchSetAccessories(batchEditDraft.selectedAccessories)
                    }
                }
            }
            .sheet(isPresented: $showingConditionSelection) {
                BatchConditionSelectionView(
                    selectedCondition: $batchEditDraft.selectedCondition,
                    options: conditionBatchOptions
                )
                    .onDisappear {
                        if let condition = batchEditDraft.selectedCondition {
                            batchSetCondition(condition)
                        }
                    }
            }
            .sheet(isPresented: $showingMergeToAccessorySheet) {
                MergeToAccessorySheet(
                    selectedItemIDs: selectedItemIDs,
                    allClothings: clothings,
                    onSelect: { targetClothing in
                        targetClothingForMerge = targetClothing
                        showingMergeConfirmation = true
                    }
                )
            }
    }

    private func applyAlerts<Content: View>(to content: Content) -> some View {
        content
            .alert("确认删除", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) { }
                Button("删除 \(selectedItemIDs.count) 项", role: .destructive) {
                    deleteSelectedItems()
                }
            }
            .alert("确认批量复制", isPresented: $showingBatchCopyAlert) {
                Button("取消", role: .cancel) { }
                Button("复制 \(selectedItemIDs.count) 项") {
                    batchCopySelectedItems()
                }
            } message: {
                Text("确定要复制选中的 \(selectedItemIDs.count) 件物品吗？")
            }
            .alert("确认添加标签", isPresented: $showingAddTagsConfirmation) {
                Button("取消", role: .cancel) {
                    batchEditDraft.selectedTags = []
                }
                Button("确认添加") {
                    if !batchEditDraft.selectedTags.isEmpty {
                        addTagsToSelectedItems(batchEditDraft.selectedTags)
                    }
                }
            } message: {
                Text("确定要为选中的 \(selectedItemIDs.count) 件物品添加 \(batchEditDraft.selectedTags.count) 个标签吗？")
            }
            .alert("确认归类品牌", isPresented: $showingSetBrandConfirmation) {
                Button("取消", role: .cancel) {
                    batchEditDraft.selectedBrand = nil
                }
                Button("确认修改") {
                    if let brand = batchEditDraft.selectedBrand {
                        setBrandForSelectedItems(brand)
                    }
                }
            } message: {
                if let brand = batchEditDraft.selectedBrand {
                    Text("确定要将选中的 \(selectedItemIDs.count) 件物品归类到品牌“\(brand.name)”吗？")
                }
            }
            .alert("确认删除", isPresented: $showingDeleteSingleAlert) {
                Button("取消", role: .cancel) {
                    itemToDelete = nil
                }
                Button("删除", role: .destructive) {
                    if let item = itemToDelete {
                        deleteItem(item)
                    }
                }
            } message: {
                if let item = itemToDelete {
                    Text("确定要删除“\(item.name)”吗？此操作无法撤销。")
                }
            }
            .alert("确认复制", isPresented: $showingCopyAlert) {
                Button("取消", role: .cancel) {
                    itemToCopy = nil
                }
                Button("复制") {
                    if let item = itemToCopy {
                        copyItem(item)
                    }
                }
            } message: {
                if let item = itemToCopy {
                    Text("确定要复制「\(item.name)」吗？")
                }
            }
            .alert("确认合并", isPresented: $showingMergeConfirmation) {
                Button("取消", role: .cancel) {
                    targetClothingForMerge = nil
                }
                Button("确认合并") {
                    if let target = targetClothingForMerge {
                        performMergeToAccessory(targetClothing: target)
                    }
                }
            } message: {
                if let target = targetClothingForMerge {
                    Text("确定要将选中的 \(selectedItemIDs.count) 件裙装作为小物合并到「\(target.name)」中吗？")
                }
            }
            .alert("合并完成", isPresented: $showingDeleteAfterMergeConfirmation) {
                Button("保留原裙装") {
                    selectedItemIDs.removeAll()
                    targetClothingForMerge = nil
                }
                Button("删除原裙装", role: .destructive) {
                    deleteSelectedItems()
                    targetClothingForMerge = nil
                }
            } message: {
                Text("已成功合并 \(mergedItemCount) 个小物。是否删除原选中的裙装？")
            }
    }

    private var isReorderTrackingEnabled: Bool {
        isEditing || (isSelectionMode && sortOption == .custom)
    }

    private var gridWardrobeView: some View {
        ScrollViewReader { proxy in
            let filtered = filteredClothings
            let displayed = isReorderTrackingEnabled ? editableClothings : filtered
            let firstFilteredID = filtered.first?.id
            ZStack {
                gridScrollContent(displayed: displayed, firstFilteredID: firstFilteredID)

                if isEditing {
                    VStack {
                        Color.clear.frame(height: 80)
                            .contentShape(Rectangle())
                            .onDrop(of: [UTType.text], delegate: ScrollDropDelegate(
                                onEnter: { startAutoScroll(up: true, proxy: proxy) },
                                onExit: { stopAutoScroll() }
                            ))
                        Spacer()
                        Color.clear.frame(height: 80)
                            .contentShape(Rectangle())
                            .onDrop(of: [UTType.text], delegate: ScrollDropDelegate(
                                onEnter: { startAutoScroll(up: false, proxy: proxy) },
                                onExit: { stopAutoScroll() }
                            ))
                    }
                    .allowsHitTesting(true)
                }
            }
        }
    }

    @ViewBuilder
    private func gridScrollContent(displayed: [Clothing], firstFilteredID: UUID?) -> some View {
        if isReorderTrackingEnabled {
            gridScrollBody(displayed: displayed, firstFilteredID: firstFilteredID)
                .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                    self.draggingItem = nil
                    return true
                }
                .onPreferenceChange(WardrobeVisibleItemFramePreferenceKey.self) { frames in
                    scheduleVisibleItemFrameUpdate(frames)
                }
        } else {
            gridScrollBody(displayed: displayed, firstFilteredID: firstFilteredID)
        }
    }

    private func gridScrollBody(displayed: [Clothing], firstFilteredID: UUID?) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                statsSection
                    .padding(.horizontal, viewLayout == .grid6 ? 2 : 16)

                LazyVGrid(columns: gridColumns, spacing: viewLayout == .grid6 ? 2 : 16) {
                    ForEach(displayed) { clothing in
                        wardrobeGridCell(for: clothing, firstFilteredID: firstFilteredID)
                    }
                }
                .animation(isEditing ? .default : nil, value: editableClothings)
                .padding(.horizontal, viewLayout == .grid6 ? 2 : 16)
                .padding(.bottom, 100)
            }
        }
    }

    @ViewBuilder
    private func wardrobeGridCell(for clothing: Clothing, firstFilteredID: UUID?) -> some View {
        if isSelectionMode {
            selectionGridCell(for: clothing, firstFilteredID: firstFilteredID)
        } else if isEditing {
            ZStack(alignment: .topTrailing) {
                clothingItemView(clothing: clothing, firstFilteredID: firstFilteredID)
            }
            .contentShape(Rectangle())
            .onDrag {
                self.draggingItem = clothing
                return NSItemProvider(object: clothing.id.uuidString as NSString)
            }
            .onDrop(of: [UTType.text], delegate: DropViewDelegate(item: clothing, items: $editableClothings, draggingItem: $draggingItem, isEditing: true, selectedItemIDs: selectedItemIDs))
        } else {
            Button {
                openDetail(clothing)
            } label: {
                ZStack(alignment: .topTrailing) {
                    clothingItemView(clothing: clothing, firstFilteredID: firstFilteredID)
                }
            }
            .buttonStyle(.plain)
            // menu-perf: wardrobe grid cell context menu
            .contextMenu {
                let _ = MenuPerfSignpost.contextMenuOpen("wardrobe.grid_cell")
                contextMenuItems(for: clothing)
            }
        }
    }

    @ViewBuilder
    private func selectionGridCell(for clothing: Clothing, firstFilteredID: UUID?) -> some View {
        let cell = ZStack(alignment: .topTrailing) {
            clothingItemView(clothing: clothing, firstFilteredID: firstFilteredID)

            Image(systemName: selectedItemIDs.contains(clothing.id) ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selectedItemIDs.contains(clothing.id) ? .pink : .secondary)
                .background(Circle().fill(.white).padding(2))
                .shadow(radius: 1)
                .padding(8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(clothing.id)
        }

        if isReorderTrackingEnabled {
            cell
                .onDrag {
                    self.draggingItem = clothing
                    return NSItemProvider(object: clothing.id.uuidString as NSString)
                }
                .onDrop(of: [UTType.text], delegate: DropViewDelegate(item: clothing, items: $editableClothings, draggingItem: $draggingItem, isEditing: true, selectedItemIDs: selectedItemIDs))
        } else {
            cell
        }
    }
    
    private var isAllSelectedInView: Bool {
        let displayedIDs = Set(filteredClothings.map { $0.id })
        guard !displayedIDs.isEmpty else { return false }
        return selectedItemIDs.isSuperset(of: displayedIDs)
    }
    
    private func toggleSelectAll() {
        let displayedIDs = Set(filteredClothings.map { $0.id })
        if selectedItemIDs.isSuperset(of: displayedIDs) {
            // Deselect all visible
            selectedItemIDs.subtract(displayedIDs)
        } else {
            // Select all visible
            selectedItemIDs.formUnion(displayedIDs)
        }
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    private func openDetail(_ clothing: Clothing) {
        detailNavigationTarget = clothing
        isShowingDetailNavigation = true
    }
    
    private func deleteSelectedItems() {
        let itemsToDelete = clothings.filter { selectedItemIDs.contains($0.id) }

        // Use autoreleasepool to optimize memory usage during batch operations
        autoreleasepool {
            for item in itemsToDelete {
                item.isDeleted = true
                item.deletedAt = Date()
                item.lastModified = Date()
            }
        }

        // Force save immediately to persist changes before any view switching
        do {
            try modelContext.save()
            print("WardrobeView: Successfully saved deletion of \(itemsToDelete.count) items.")

            // 记录删除到 DeleteTracker，防止iCloud同步覆盖
            for item in itemsToDelete {
                DeleteTracker.shared.recordDeletedClothing(id: item.id)
            }
        } catch {
            print("WardrobeView: Failed to save deletion: \(error)")
        }

        withAnimation {
            isSelectionMode = false
            selectedItemIDs.removeAll()
        }
    }

    private func deleteItem(_ item: Clothing) {
        item.isDeleted = true
        item.deletedAt = Date()
        item.lastModified = Date()
        do {
            try modelContext.save()

            // 记录删除到 DeleteTracker，防止iCloud同步覆盖
            DeleteTracker.shared.recordDeletedClothing(id: item.id)
            
            // 更新衣物数量缓存，用于魔法任务进度实时显示
            updateClothingCountCache()
        } catch {
            print("WardrobeView: Failed to save deletion: \(error)")
        }
        itemToDelete = nil
    }
    
    private func copyItem(_ item: Clothing) {
        let newItem = Clothing(
            name: "\(item.name) 副本",
            brand: item.brand,
            types: item.types,
            colors: item.colors,
            sizes: item.sizes,
            length: item.length,
            condition: item.condition,
            accessories: item.accessories,
            imagePaths: item.imagePaths,
            isShared: item.isShared,
            originalPrice: item.originalPrice,
            price: item.price,
            deposit: item.deposit,
            balance: item.balance,
            accessoriesPrice: item.accessoriesPrice,
            purchaseDate: Date(), // Reset purchase date to now
            depositDate: item.depositDate,
            isDepositPlan: item.isDepositPlan,
            finalPaymentDate: item.finalPaymentDate,
            finalPaymentEndDate: item.finalPaymentEndDate,
            note: item.note,
            stock: item.stock,
            status: item.status
        )
        newItem.copyCurrencyAndShippingMetadata(from: item)
        newItem.tags = item.tags
        
        // 复制尺码表图和价格表图
        newItem.sizeChartImagePath = item.sizeChartImagePath
        newItem.priceChartImagePath = item.priceChartImagePath
        
        // Duplicate accessory items
        if let items = item.accessoryItems {
            newItem.accessoryItems = items.map { item in
                AccessoryItem(name: item.name, price: item.price, deposit: item.deposit, balance: item.balance, sortIndex: item.sortIndex, imagePaths: item.imagePaths)
            }
        }
        
        // Copy image files to new paths to avoid sharing the same file
        var newImagePaths: [String] = []
        for path in item.imagePaths {
            if !path.isEmpty, let originalImage = ImageManager.shared.loadImage(fileName: path) {
                if let newPath = ImageManager.shared.saveImage(originalImage, context: modelContext) {
                    newImagePaths.append(newPath)
                }
            }
        }
        newItem.imagePaths = newImagePaths
        
        // 复制尺码表图和价格表图文件（避免共享同一文件）
        if let sizeChartPath = item.sizeChartImagePath, !sizeChartPath.isEmpty,
           let originalSizeChart = ImageManager.shared.loadImage(fileName: sizeChartPath) {
            newItem.sizeChartImagePath = ImageManager.shared.saveImage(originalSizeChart, context: modelContext)
        }
        if let priceChartPath = item.priceChartImagePath, !priceChartPath.isEmpty,
           let originalPriceChart = ImageManager.shared.loadImage(fileName: priceChartPath) {
            newItem.priceChartImagePath = ImageManager.shared.saveImage(originalPriceChart, context: modelContext)
        }
        
        modelContext.insert(newItem)
        do {
            try modelContext.save()
            // 更新衣物数量缓存，用于魔法任务进度实时显示
            updateClothingCountCache()
        } catch {
            print("WardrobeView: Failed to save copied item: \(error)")
        }
        itemToCopy = nil
    }
    
    private func batchCopySelectedItems() {
        let itemsToCopy = clothings.filter { selectedItemIDs.contains($0.id) }
        
        autoreleasepool {
            for item in itemsToCopy {
                let newItem = Clothing(
                    name: "\(item.name) 副本",
                    brand: item.brand,
                    types: item.types,
                    colors: item.colors,
                    sizes: item.sizes,
                    length: item.length,
                    condition: item.condition,
                    accessories: item.accessories,
                    imagePaths: [], // 先设置为空，后面单独复制图片
                    isShared: item.isShared,
                    originalPrice: item.originalPrice,
                    price: item.price,
                    deposit: item.deposit,
                    balance: item.balance,
                    accessoriesPrice: item.accessoriesPrice,
                    purchaseDate: Date(),
                    depositDate: item.depositDate,
                    isDepositPlan: item.isDepositPlan,
                    finalPaymentDate: item.finalPaymentDate,
                    finalPaymentEndDate: item.finalPaymentEndDate,
                    note: item.note,
                    stock: item.stock,
                    status: item.status
                )
                newItem.copyCurrencyAndShippingMetadata(from: item)
                newItem.tags = item.tags
                
                // 复制小物
                if let items = item.accessoryItems {
                    newItem.accessoryItems = items.map { item in
                        AccessoryItem(name: item.name, price: item.price, deposit: item.deposit, balance: item.balance, sortIndex: item.sortIndex, imagePaths: item.imagePaths)
                    }
                }
                
                // 复制图片文件
                var newImagePaths: [String] = []
                for path in item.imagePaths {
                    if !path.isEmpty, let originalImage = ImageManager.shared.loadImage(fileName: path) {
                        if let newPath = ImageManager.shared.saveImage(originalImage, context: modelContext) {
                            newImagePaths.append(newPath)
                        }
                    }
                }
                newItem.imagePaths = newImagePaths
                
                modelContext.insert(newItem)
            }
        }
        
        do {
            try modelContext.save()
            updateClothingCountCache()
        } catch {
            print("WardrobeView: Failed to save batch copied items: \(error)")
        }
        
        // 保持选择模式，清空选择
        selectedItemIDs.removeAll()
    }
    
    private func addTagsToSelectedItems(_ tags: [Tag]) {
        let items = clothings.filter { selectedItemIDs.contains($0.id) }
        for item in items {
            var itemTags = item.tags ?? []
            for tag in tags {
                if !itemTags.contains(where: { $0.id == tag.id }) {
                    itemTags.append(tag)
                }
            }
            item.tags = itemTags
        }
        try? modelContext.save()
        
        // Keep selection mode active as requested
        batchEditDraft.selectedTags = []
    }
    
    private func setBrandForSelectedItems(_ brand: Brand) {
        let items = clothings.filter { selectedItemIDs.contains($0.id) }
        for item in items {
            item.brand = brand
        }
        try? modelContext.save()
        
        // Keep selection mode active as requested
        batchEditDraft.selectedBrand = nil
    }
    
    // MARK: - Batch Edit Methods
    
    private func batchSetColors(_ colors: [String]) {
        let items = clothings.filter { selectedItemIDs.contains($0.id) }
        let colorString = colors.joined(separator: ",")
        for item in items {
            item.colors = colorString
        }
        try? modelContext.save()
        batchEditDraft.selectedColors = []
    }
    
    private func batchSetSizes(_ sizes: [String]) {
        let items = clothings.filter { selectedItemIDs.contains($0.id) }
        let sizeString = sizes.joined(separator: ",")
        for item in items {
            item.sizes = sizeString
        }
        try? modelContext.save()
        batchEditDraft.selectedSizes = []
    }
    
    private func batchSetLengths(_ lengths: [String]) {
        let items = clothings.filter { selectedItemIDs.contains($0.id) }
        // 衣长通常是单选，取第一个
        let lengthString = lengths.first ?? ""
        for item in items {
            item.length = lengthString
        }
        try? modelContext.save()
        batchEditDraft.selectedLengths = []
    }
    
    private func batchSetAccessories(_ accessories: [String]) {
        let items = clothings.filter { selectedItemIDs.contains($0.id) }
        let accessoryString = accessories.joined(separator: ",")
        for item in items {
            item.accessories = accessoryString
        }
        try? modelContext.save()
        batchEditDraft.selectedAccessories = []
    }
    
    private func batchSetCondition(_ condition: String) {
        let items = clothings.filter { selectedItemIDs.contains($0.id) }
        for item in items {
            item.condition = condition
        }
        try? modelContext.save()
        batchEditDraft.selectedCondition = nil
    }
    
    // MARK: - 合并为小物到裙装
    
    /// 将选中的裙装作为小物合并到目标裙装中
    private func performMergeToAccessory(targetClothing: Clothing) {
        // 获取选中的裙装（排除目标裙装本身）
        let selectedClothings = clothings.filter { 
            selectedItemIDs.contains($0.id) && $0.id != targetClothing.id 
        }
        
        guard !selectedClothings.isEmpty else {
            // 如果没有有效的选中项（可能只选中了目标本身），直接返回
            targetClothingForMerge = nil
            return
        }
        
        var newAccessoryItems: [AccessoryItem] = []
        var sortIndex = targetClothing.accessoryItems?.count ?? 0
        var allMergedImagePaths: [String] = [] // 收集所有被合并裙装的图片路径
        
        // 为每个选中的裙装创建小物
        for clothing in selectedClothings {
            let stock = clothing.stock
            let baseName = clothing.name
            let deposit = clothing.deposit
            let balance = clothing.balance
            let price = clothing.price
            let imagePaths = clothing.imagePaths.isEmpty ? nil : clothing.imagePaths // 复制原裙装的图片路径，空数组转为nil
            
            // 收集图片路径用于追加到目标裙装
            if let paths = imagePaths {
                allMergedImagePaths.append(contentsOf: paths)
            }
            
            // 如果库存大于1，拆分成多个小物
            if stock > 1 {
                for i in 1...stock {
                    let accessoryName = "\(baseName) #\(i)"
                    let accessory = AccessoryItem(
                        name: accessoryName,
                        price: price,
                        deposit: deposit,
                        balance: balance,
                        sortIndex: sortIndex,
                        imagePaths: imagePaths // 将原裙装图片路径复制给小物
                    )
                    accessory.clothing = targetClothing
                    newAccessoryItems.append(accessory)
                    sortIndex += 1
                }
            } else {
                // 库存为1，不添加编号
                let accessory = AccessoryItem(
                    name: baseName,
                    price: price,
                    deposit: deposit,
                    balance: balance,
                    sortIndex: sortIndex,
                    imagePaths: imagePaths // 将原裙装图片路径复制给小物
                )
                accessory.clothing = targetClothing
                newAccessoryItems.append(accessory)
                sortIndex += 1
            }
        }
        
        // 将图片路径追加到目标裙装的 imagePaths 后面
        if !allMergedImagePaths.isEmpty {
            targetClothing.imagePaths.append(contentsOf: allMergedImagePaths)
        }
        
        // 将小物添加到目标裙装
        if targetClothing.accessoryItems == nil {
            targetClothing.accessoryItems = []
        }
        targetClothing.accessoryItems?.append(contentsOf: newAccessoryItems)
        
        // 重新计算目标裙装的自定义小物总价，避免历史值累加漂移
        targetClothing.accessoriesPrice = targetClothing.resolvedAccessoriesPrice
        
        // 保存更改
        do {
            try modelContext.save()
            mergedItemCount = newAccessoryItems.count
            showingDeleteAfterMergeConfirmation = true
        } catch {
            print("❌ 合并小物失败: \(error)")
            targetClothingForMerge = nil
        }
    }
    
    private func saveOrder() {
        for (index, clothing) in editableClothings.enumerated() {
            clothing.sortIndex = index
        }
        try? modelContext.save()
    }
    
    /// 更新衣物数量缓存，用于魔法任务进度实时显示
    private func updateClothingCountCache() {
        FeatureUnlockManager.shared.refreshClothingCountCache(from: modelContext, reason: "wardrobe")
    }
    
    // MARK: - Auto Scroll Logic
    private func startAutoScroll(up: Bool, proxy: ScrollViewProxy) {
        stopAutoScroll()
        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                performScroll(up: up, proxy: proxy)
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            }
        }
    }
    
    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }
    
    private func performScroll(up: Bool, proxy: ScrollViewProxy) {
        guard !visibleItemIDs.isEmpty, !editableClothings.isEmpty else { return }
        
        let visibleIndices = editableClothings.indices.filter { visibleItemIDs.contains(editableClothings[$0].id) }
        guard !visibleIndices.isEmpty else { return }
        
        if up {
            if let minIndex = visibleIndices.min(), minIndex > 0 {
                // Scroll to the item just above the current view
                let targetIndex = max(0, minIndex - 3) // Jump a bit more for smoother feel in grid
                withAnimation {
                    proxy.scrollTo(editableClothings[targetIndex].id, anchor: .top)
                }
            }
        } else {
            if let maxIndex = visibleIndices.max(), maxIndex < editableClothings.count - 1 {
                let targetIndex = min(editableClothings.count - 1, maxIndex + 3)
                withAnimation {
                    proxy.scrollTo(editableClothings[targetIndex].id, anchor: .bottom)
                }
            }
        }
    }
    
    private var statsSection: some View {
        VStack(spacing: 4) {
            HStack {
                Spacer()
                Button {
                    withAnimation {
                        showStats.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(showStats ? "隐藏" : "显示")
                        Image(systemName: showStats ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if showStats {
                WardrobeStatsView(clothings: filteredClothings,
                                  statsSummary: filteredStatsSummary,
                                  filterDescription: filterDescription,
                                  onClearFilter: onClearFilter)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var listView: some View {
        Group {
            if isEditing {
                editableListView
            } else {
                lazyListView
            }
        }
    }

    private var editableListView: some View {
        List {
            Section {
                listContent
            } header: {
                statsSection
                    .padding(.horizontal, viewLayout == .grid6 ? 2 : 16)
                    .padding(.vertical, 8)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
    }

    private var lazyListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                statsSection
                    .padding(.horizontal, viewLayout == .grid6 ? 2 : 16)
                    .padding(.vertical, 8)

                ForEach(filteredClothings) { clothing in
                    listRow(for: clothing)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
    }

    private var listContent: some View {
        ForEach(isEditing ? editableClothings : filteredClothings) { clothing in
            listRow(for: clothing)
        }
        .onMove { from, to in
            if isEditing {
                editableClothings.move(fromOffsets: from, toOffset: to)
            }
        }
    }

    private func listRow(for clothing: Clothing) -> some View {
        ZStack {
            if isEditing {
                editingRow(for: clothing)
            } else if isSelectionMode {
                selectionRow(for: clothing)
            } else {
                normalRow(for: clothing)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func editingRow(for clothing: Clothing) -> some View {
        VStack(spacing: 0) {
            clothingRowView(clothing: clothing)
            Divider()
                .padding(.leading)
        }
    }

    private func selectionRow(for clothing: Clothing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selectedItemIDs.contains(clothing.id) ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selectedItemIDs.contains(clothing.id) ? .pink : .secondary)

            VStack(spacing: 0) {
                clothingRowView(clothing: clothing)
                Divider()
                    .padding(.leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(clothing.id)
        }
    }

    private func normalRow(for clothing: Clothing) -> some View {
        Button {
            openDetail(clothing)
        } label: {
            VStack(spacing: 0) {
                clothingRowView(clothing: clothing)
                Divider()
                    .padding(.leading)
            }
        }
        .buttonStyle(.plain)
        // menu-perf: wardrobe list cell context menu
        .contextMenu {
            let _ = MenuPerfSignpost.contextMenuOpen("wardrobe.list_cell")
            contextMenuItems(for: clothing)
        }
    }

    // MARK: keep this closure dependency-free for menu-perf
    private func contextMenuItems(for clothing: Clothing) -> some View {
        Group {
            Button {
                isSelectionMode = true
                selectedItemIDs.insert(clothing.id)
            } label: {
                Label("选择", systemImage: "checkmark.circle")
            }

            Button {
                openDetail(clothing)
            } label: {
                Label("查看详情", systemImage: "info.circle")
            }

            Divider()

            Button {
                itemToCopy = clothing
                showingCopyAlert = true
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                itemToDelete = clothing
                showingDeleteSingleAlert = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func swipeActions(for clothing: Clothing) -> some View {
        Group {
            Button(role: .destructive) {
                itemToDelete = clothing
                showingDeleteSingleAlert = true
            } label: {
                Label("删除", systemImage: "trash")
            }

            Button {
                itemToCopy = clothing
                showingCopyAlert = true
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .tint(.blue)
        }
    }

    @MainActor
    private func rebuildFilteredClothings() async {
        let snapshots = clothings.map(WardrobeClothingSnapshot.init(clothing:))
        let cellSnapshots = Dictionary(uniqueKeysWithValues: clothings.map { clothing in
            (clothing.id, WardrobeCellSnapshot(clothing: clothing))
        })
        let input = WardrobeFilterInput(
            snapshots: snapshots,
            searchText: searchText,
            selectedTagIDs: selectedTagIDs,
            selectedBrandIDs: selectedBrandIDs,
            selectedTypes: selectedTypes,
            selectedColors: selectedColors,
            selectedSizes: selectedSizes,
            selectedLengths: selectedLengths,
            selectedConditions: selectedConditions,
            selectedAccessories: selectedAccessories,
            depositStatusFilterRawValue: depositStatusFilter.rawValue,
            sortOptionRawValue: sortOption.rawValue
        )

        let result = await Task.detached(priority: .userInitiated) {
            WardrobeFilterEngine.evaluate(input)
        }.value

        guard !Task.isCancelled else { return }

        let clothingByID = Dictionary(uniqueKeysWithValues: clothings.map { ($0.id, $0) })
        let resolvedClothings = result.ids.compactMap { clothingByID[$0] }

        filteredClothings = resolvedClothings
        cellSnapshotCache = cellSnapshots
        filteredStatsSummary = result.stats
        conditionBatchOptionsCache = result.conditionOptions
        prefetchInitialWardrobeImages(resolvedClothings, snapshots: cellSnapshots)

        if isReorderTrackingEnabled && editableClothings.isEmpty {
            editableClothings = resolvedClothings
        }
    }

    private var wardrobeCellImageTargetSize: CGSize {
        wardrobeCellImageTargetSize(for: viewLayout)
    }

    private func wardrobeCellImageTargetSize(for layout: HomeView.ViewLayout) -> CGSize {
        switch layout {
        case .grid2:
            return CGSize(width: 160, height: 160)
        case .grid3:
            return CGSize(width: 112, height: 112)
        case .grid6:
            return CGSize(width: 64, height: 64)
        case .listDetailed:
            return CGSize(width: 60, height: 60)
        case .listBrief:
            return CGSize(width: 50, height: 50)
        }
    }

    private var initialImagePrefetchLimit: Int {
        switch viewLayout {
        case .grid2:
            return 8
        case .grid3:
            return 12
        case .grid6:
            return 30
        case .listBrief, .listDetailed:
            return 18
        }
    }

    private func prefetchInitialWardrobeImages(
        _ clothings: [Clothing],
        snapshots: [UUID: WardrobeCellSnapshot]? = nil
    ) {
        guard !clothings.isEmpty else { return }

        let limit = initialImagePrefetchLimit
        let snapshotSource = snapshots ?? cellSnapshotCache
        let fileNames = clothings
            .prefix(limit * 2)
            .compactMap { snapshotSource[$0.id]?.firstImagePath }

        ImageManager.shared.prefetchImages(
            fileNames: fileNames,
            targetSize: wardrobeCellImageTargetSize,
            limit: limit,
            priority: .background
        )
    }

    private func scheduleVisibleItemFrameUpdate(_ frames: [UUID: CGRect]) {
        guard isReorderTrackingEnabled else {
            visibleItemFrameUpdateTask?.cancel()
            visibleItemFrameUpdateTask = nil
            return
        }

        visibleItemFrameUpdateTask?.cancel()
        visibleItemFrameUpdateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, isReorderTrackingEnabled else { return }

            let expandedScreenBounds = UIScreen.main.bounds.insetBy(dx: -32, dy: -160)
            let visibleIDs = frames.compactMap { id, frame in
                expandedScreenBounds.intersects(frame) ? id : nil
            }
            visibleItemIDs = Set(visibleIDs)
        }
    }
}

struct WardrobeStatsView: View {
    let clothings: [Clothing]
    let statsSummary: WardrobeStatsSummary
    var filterDescription: String? = nil
    var onClearFilter: (() -> Void)? = nil
    
    @AppStorage("showStatsCountAndStyle") private var showCountAndStyle = true
    @AppStorage("showStatsDressValue") private var showDressValue = true
    @AppStorage("showStatsTotalValue") private var showTotalValue = true
    
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BookGroup> { $0.deletedAt == nil }, sort: \BookGroup.sortIndex, order: .forward) private var books: [BookGroup]
    
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.containerPalette) private var palette
    
    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    @State private var showDailyCheckIn = false
    
    var styleCount: Int {
        statsSummary.styleCount
    }
    
    var totalCount: Int {
        statsSummary.totalCount
    }
    
    var dressValue: Decimal {
        statsSummary.dressValue
    }

    var totalValue: Decimal {
        statsSummary.totalValue
    }

    // 将Decimal格式化为整数（个位精度）的字符串
    private func formatValue(_ value: Decimal) -> String {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        // 四舍五入到个位
        let roundedValue = round(doubleValue)
        return String(format: "%.0f", roundedValue)
    }
    
    // 获取默认手帐，如果没有则创建（只考虑未删除的手帐）
    var defaultBook: BookGroup {
        // 只考虑未删除的手帐
        let activeBooks = books.filter { !$0.isDeleted }
        if let existingDefault = activeBooks.first(where: { $0.title == "默认手帐" }) {
            return existingDefault
        } else if let firstBook = activeBooks.first {
            return firstBook
        } else {
            // 创建默认手帐
            let newBook = BookGroup(title: "默认手帐")
            modelContext.insert(newBook)
            try? modelContext.save()
            print("WardrobeView: Created new default book")
            return newBook
        }
    }
    
    // OOTD 跳转目标 - 从衣橱进入的特殊版本
    var defaultBookDestination: some View {
        BookDetailViewFromWardrobe(book: defaultBook)
    }
    
    var body: some View {
        WardrobeThemeStatsCardContainer {
            VStack(spacing: 12) {
                // Main Stats
                HStack(spacing: 0) {
                    statItem(title: "总件数/款", value: "\(totalCount)/\(styleCount)", isVisible: $showCountAndStyle)

                    Divider()

                    statItem(title: "裙装价值", value: "¥\(formatValue(dressValue))", isVisible: $showDressValue, valueColor: Color(hex: "FF9800"))

                    Divider()

                    statItem(title: "总价值", value: "¥\(formatValue(totalValue))", isVisible: $showTotalValue)
                }

                // Bottom Actions - 三个功能入口
                HStack(spacing: 8) {
                    // 今日穿搭色按钮 - 使用主题强调色
                    Button {
                        showDailyCheckIn = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 20))
                            Text("今日穿搭色")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                colors: [palette.accent.opacity(0.15), palette.accent.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundStyle(palette.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // 穿搭手帐按钮 - 使用主题强调色
                    Button {
                        tabNavigationManager.navigate(to: .smallWorld(.ootd))
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 20))
                            Text("穿搭手帐")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(palette.accent.opacity(0.1))
                        .foregroundStyle(palette.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .captureGuideTarget(.wardrobeOotdEntry)

                    // 详细统计按钮 - 使用主题次要色
                    NavigationLink(destination: WardrobeStatisticsDetailView(clothings: clothings, filterDescription: filterDescription, onClearFilter: onClearFilter)) {
                        VStack(spacing: 4) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 20))
                            Text("详细统计")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(palette.secondary.opacity(0.1))
                        .foregroundStyle(palette.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showDailyCheckIn) {
            DailyCheckInView()
        }
    }

    private func statItem(title: String, value: String, isVisible: Binding<Bool>, valueColor: Color? = nil) -> some View {
        VStack(spacing: 4) {
            // 标题行：使用固定高度确保对齐
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(palette.secondary)

                Button {
                    withAnimation {
                        isVisible.wrappedValue.toggle()
                    }
                } label: {
                    // 折叠价格时显示闭眼(eye.slash)，显示价格时显示睁眼(eye)
                    Image(systemName: isVisible.wrappedValue ? "eye" : "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(palette.tertiary)
                        .contentShape(Rectangle()) // Make it easier to tap
                }
            }
            .frame(height: 16) // 固定标题行高度

            // 数值行：使用固定高度确保对齐
            Text(isVisible.wrappedValue ? value : "****")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor ?? palette.primary)
                .contentTransition(.numericText())
                .frame(height: 28) // 固定数值行高度
        }
        .frame(maxWidth: .infinity)
    }
}

struct DropViewDelegate: DropDelegate {
    let item: Clothing
    @Binding var items: [Clothing]
    @Binding var draggingItem: Clothing?
    var isEditing: Bool = true
    var selectedItemIDs: Set<UUID> = []
    
    func performDrop(info: DropInfo) -> Bool {
        self.draggingItem = nil
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func dropEntered(info: DropInfo) {
        guard isEditing else { return }
        guard let draggingItem = draggingItem else { return }
        
        // 如果当前拖拽项和目标项相同，不做处理
        if draggingItem.id == item.id { return }
        
        // 检查是否是多选拖拽
        // 条件：拖拽项在选中列表中，且选中列表包含多个项目
        if selectedItemIDs.contains(draggingItem.id) && selectedItemIDs.count > 1 {
            handleMultiSelectionDrop(targetItem: item)
        } else {
            handleSingleItemDrop(targetItem: item, draggingItem: draggingItem)
        }
    }
    
    private func handleSingleItemDrop(targetItem: Clothing, draggingItem: Clothing) {
        guard let fromIndex = items.firstIndex(where: { $0.id == draggingItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == targetItem.id }) else { return }
        
        if fromIndex != toIndex {
            withAnimation(.default) {
                let fromItem = items.remove(at: fromIndex)
                items.insert(fromItem, at: toIndex)
            }
        }
    }
    
    private func handleMultiSelectionDrop(targetItem: Clothing) {
        // 如果目标项也是选中项之一，则不进行重排（因为它们是一体的）
        if selectedItemIDs.contains(targetItem.id) { return }
        
        guard items.contains(where: { $0.id == targetItem.id }) else { return }
        
        // 1. 提取所有选中的项目，并保持它们在原数组中的相对顺序（如果需要保持相对顺序）
        // 或者简单地按当前 items 中的顺序提取
        let selectedItems = items.filter { selectedItemIDs.contains($0.id) }
        
        // 2. 验证所有选中项都找到了
        guard selectedItems.count == selectedItemIDs.count else { return }
        
        withAnimation(.default) {
            // 3. 从数组中移除所有选中项
            items.removeAll { selectedItemIDs.contains($0.id) }
            
            // 4. 计算新的插入索引
            // 注意：因为移除了元素，targetIndex 可能需要调整
            // 重新获取目标项在移除后的数组中的索引
            if let newTargetIndex = items.firstIndex(where: { $0.id == targetItem.id }) {
                // 插入到目标项位置（挤占目标项，目标项后移）
                items.insert(contentsOf: selectedItems, at: newTargetIndex)
            } else {
                // 如果找不到目标项（理论上不应该发生，除非目标项也被删了），追加到末尾
                items.append(contentsOf: selectedItems)
            }
        }
    }
}

struct ScrollDropDelegate: DropDelegate {
    let onEnter: () -> Void
    let onExit: () -> Void

    func dropEntered(info: DropInfo) {
        onEnter()
    }

    func dropExited(info: DropInfo) {
        onExit()
    }

    func performDrop(info: DropInfo) -> Bool {
        onExit()
        return false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - 从衣橱进入的默认手帐视图

struct BookDetailViewFromWardrobe: View {
    let book: BookGroup
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOutfit: Outfit? = nil

    var body: some View {
        NavigationStack {
            BookDetailView(
                book: book,
                navigationPath: .constant(NavigationPath()),
                isSidebarVisible: .constant(false),
                onBack: {
                    dismiss()
                },
                showLeadingToolbar: false,
                onPageTap: { outfit in
                    selectedOutfit = outfit
                }
            )
            // 从衣橱进入时的特殊配置
            .background(LiquidBackground().ignoresSafeArea())
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .sheet(item: $selectedOutfit) { outfit in
            NavigationStack {
                PageFlipEditorContainer(initialOutfit: outfit)
            }
        }
    }
}

// MARK: - 合并为小物选择目标裙装 Sheet

struct MergeToAccessorySheet: View {
    let selectedItemIDs: Set<UUID>
    let allClothings: [Clothing]
    let onSelect: (Clothing) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \Brand.name) private var brands: [Brand]
    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared

    @State private var searchText = ""
    @State private var showingFilterSheet = false
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var selectedBrandIDs: Set<UUID> = []
    @State private var selectedTypes: Set<String> = []
    @State private var selectedColors: Set<String> = []
    @State private var selectedSizes: Set<String> = []
    @State private var selectedLengths: Set<String> = []
    @State private var selectedConditions: Set<String> = []
    @State private var selectedAccessories: Set<String> = []
    @State private var depositStatusFilter: DepositStatusFilter = .all

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var totalFilterCount: Int {
        selectedTagIDs.count +
        selectedBrandIDs.count +
        selectedTypes.count +
        selectedColors.count +
        selectedSizes.count +
        selectedLengths.count +
        selectedConditions.count +
        selectedAccessories.count +
        (depositStatusFilter != .all ? 1 : 0)
    }

    // 过滤掉已选中的裙装，只显示可选的目标裙装
    var availableClothings: [Clothing] {
        allClothings.filter { !selectedItemIDs.contains($0.id) && $0.deletedAt == nil }
    }

    var filteredClothings: [Clothing] {
        var result = availableClothings

        // 搜索过滤
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.brand?.name.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // 标签筛选
        if !selectedTagIDs.isEmpty {
            result = result.filter { clothing in
                if selectedTagIDs.contains(MergeToAccessorySheet.noTagUUID) {
                    return clothing.tags?.isEmpty ?? true
                }
                let clothingTagIDs = Set(clothing.tags?.map { $0.id } ?? [])
                return !selectedTagIDs.isDisjoint(with: clothingTagIDs)
            }
        }

        // 品牌筛选
        if !selectedBrandIDs.isEmpty {
            result = result.filter { clothing in
                if selectedBrandIDs.contains(MergeToAccessorySheet.noBrandUUID) {
                    return clothing.brand == nil
                }
                if let brand = clothing.brand {
                    return selectedBrandIDs.contains(brand.id)
                }
                return false
            }
        }

        // 类型筛选
        if !selectedTypes.isEmpty {
            result = result.filter { clothing in
                if selectedTypes.contains(MergeToAccessorySheet.noTypeMarker) {
                    return clothing.types.isEmpty
                }
                return selectedTypes.contains { type in
                    clothing.types.localizedCaseInsensitiveContains(type)
                }
            }
        }

        // 颜色筛选
        if !selectedColors.isEmpty {
            result = result.filter { clothing in
                if selectedColors.contains(MergeToAccessorySheet.noColorMarker) {
                    return clothing.colors.isEmpty
                }
                return selectedColors.contains { color in
                    clothing.colors.localizedCaseInsensitiveContains(color)
                }
            }
        }

        // 尺码筛选
        if !selectedSizes.isEmpty {
            result = result.filter { clothing in
                if selectedSizes.contains(MergeToAccessorySheet.noSizeMarker) {
                    return clothing.sizes.isEmpty
                }
                return selectedSizes.contains { size in
                    clothing.sizes.localizedCaseInsensitiveContains(size)
                }
            }
        }

        // 衣长筛选
        if !selectedLengths.isEmpty {
            result = result.filter { clothing in
                if selectedLengths.contains(MergeToAccessorySheet.noLengthMarker) {
                    return clothing.length.isEmpty
                }
                return selectedLengths.contains(clothing.length)
            }
        }

        // 状态筛选
        if !selectedConditions.isEmpty {
            result = result.filter { clothing in
                if selectedConditions.contains(MergeToAccessorySheet.noConditionMarker) {
                    return clothing.condition.isEmpty
                }
                return selectedConditions.contains(clothing.condition)
            }
        }

        // 小物筛选
        if !selectedAccessories.isEmpty {
            result = result.filter { clothing in
                if selectedAccessories.contains(MergeToAccessorySheet.noAccessoryMarker) {
                    return clothing.accessories.isEmpty
                }
                return selectedAccessories.contains { accessory in
                    clothing.accessories.localizedCaseInsensitiveContains(accessory)
                }
            }
        }

        // 心愿尾款筛选
        switch depositStatusFilter {
        case .all:
            break
        case .owned:
            result = result.filter { !$0.isDepositPlan }
        case .depositPlan:
            result = result.filter { $0.isDepositPlan }
        }

        return result
    }

    static let noTagUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let noBrandUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let noTypeMarker = "__NO_TYPE__"
    static let noColorMarker = "__NO_COLOR__"
    static let noSizeMarker = "__NO_SIZE__"
    static let noLengthMarker = "__NO_LENGTH__"
    static let noConditionMarker = "__NO_CONDITION__"
    static let noAccessoryMarker = "__NO_ACCESSORY__"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 已选条件标签
                selectedFiltersChips

                // 列表
                List {
                    if availableClothings.isEmpty {
                        Section {
                            ContentUnavailableView {
                                Label("没有可选的裙装", systemImage: "hanger")
                            } description: {
                                Text("请确保除了选中的裙装外，衣橱中还有其他裙装")
                            }
                        }
                    } else if filteredClothings.isEmpty {
                        Section {
                            ContentUnavailableView {
                                Label("没有符合条件的裙装", systemImage: "magnifyingglass")
                            } description: {
                                Text("试试调整筛选条件")
                            }
                        }
                    } else {
                        Section {
                            ForEach(filteredClothings) { clothing in
                                ClothingRow(clothing: clothing)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onSelect(clothing)
                                        dismiss()
                                    }
                            }
                        } header: {
                            if !searchText.isEmpty || totalFilterCount > 0 {
                                Text("找到 \(filteredClothings.count) 件裙装")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("选择目标裙装")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索裙装名称或品牌")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilterSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            if totalFilterCount > 0 {
                                Text("\(totalFilterCount)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(magicPalette.accent)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .foregroundStyle(totalFilterCount > 0 ? magicPalette.accent : magicPalette.secondaryText)
                }
            }
            .sheet(isPresented: $showingFilterSheet) {
                MergeAccessoryFilterSheet(
                    clothings: availableClothings,
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
        }
    }

    // 已选条件标签列表（显示在搜索框下方）
    @ViewBuilder
    private var selectedFiltersChips: some View {
        if totalFilterCount > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(selectedFilterItems.prefix(3)), id: \.self) { item in
                        filterChip(item: item)
                    }
                    if selectedFilterItems.count > 3 {
                        Text("+\(selectedFilterItems.count - 3)")
                            .font(.caption)
                            .foregroundStyle(magicPalette.secondaryText)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var selectedFilterItems: [String] {
        var items: [String] = []

        for id in selectedTagIDs {
            if id == MergeToAccessorySheet.noTagUUID {
                items.append("无标签")
            } else if let tag = tags.first(where: { $0.id == id }) {
                items.append(tag.name)
            }
        }

        for id in selectedBrandIDs {
            if id == MergeToAccessorySheet.noBrandUUID {
                items.append("无品牌")
            } else if let brand = brands.first(where: { $0.id == id }) {
                items.append(brand.name)
            }
        }

        items.append(contentsOf: selectedTypes.map { $0 == MergeToAccessorySheet.noTypeMarker ? "无类型" : $0 })
        items.append(contentsOf: selectedColors.map { $0 == MergeToAccessorySheet.noColorMarker ? "无颜色" : $0 })
        items.append(contentsOf: selectedSizes.map { $0 == MergeToAccessorySheet.noSizeMarker ? "无尺码" : $0 })
        items.append(contentsOf: selectedLengths.map { $0 == MergeToAccessorySheet.noLengthMarker ? "无衣长" : $0 })
        items.append(contentsOf: selectedConditions.map { $0 == MergeToAccessorySheet.noConditionMarker ? "无状态" : $0 })
        items.append(contentsOf: selectedAccessories.map { $0 == MergeToAccessorySheet.noAccessoryMarker ? "无小物" : $0 })

        return items
    }

    private func filterChip(item: String) -> some View {
        Text(item)
            .font(.caption)
            .foregroundStyle(magicPalette.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(magicPalette.accent.opacity(0.15))
            .cornerRadius(12)
    }
}

// MARK: - 合并小物筛选Sheet
struct MergeAccessoryFilterSheet: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let clothings: [Clothing]
    let tags: [Tag]
    let brands: [Brand]

    @Binding var selectedTagIDs: Set<UUID>
    @Binding var selectedBrandIDs: Set<UUID>
    @Binding var selectedTypes: Set<String>
    @Binding var selectedColors: Set<String>
    @Binding var selectedSizes: Set<String>
    @Binding var selectedLengths: Set<String>
    @Binding var selectedConditions: Set<String>
    @Binding var selectedAccessories: Set<String>
    @Binding var depositStatusFilter: DepositStatusFilter

    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared
    @State private var expandedSection: MergeFilterSection? = nil

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var totalFilterCount: Int {
        selectedTagIDs.count +
        selectedBrandIDs.count +
        selectedTypes.count +
        selectedColors.count +
        selectedSizes.count +
        selectedLengths.count +
        selectedConditions.count +
        selectedAccessories.count +
        (depositStatusFilter != .all ? 1 : 0)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if totalFilterCount > 0 {
                        selectedFiltersSummary
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    ScrollView {
                        VStack(spacing: 12) {
                            filterRow(section: .tags, title: "标签", icon: "tag", selectedCount: selectedTagIDs.count, options: tagOptions)
                            filterRow(section: .brands, title: "品牌", icon: "bag", selectedCount: selectedBrandIDs.count, options: brandOptions)

                            ForEach(visibilityManager.fieldOrder, id: \.self) { field in
                                if visibilityManager.isVisible(field) {
                                    dynamicFilterRow(for: field)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(magicPalette.secondaryText)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // 心愿尾款筛选
                        // menu-perf: merge target deposit status menu
                        Menu {
                            let _ = MenuPerfSignpost.menuContent("wardrobe.merge.deposit_status")
                            ForEach(DepositStatusFilter.allCases) { filter in
                                Button {
                                    depositStatusFilter = filter
                                } label: {
                                    HStack {
                                        Text(filter.displayName)
                                        if depositStatusFilter == filter {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: depositStatusFilter == .all ? "heart" : "heart.fill")
                                if depositStatusFilter != .all {
                                    Text("\(depositStatusFilter == .owned ? "已拥有" : "心愿")")
                                        .font(.caption)
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(depositStatusFilter == .all ? magicPalette.secondaryText : magicPalette.accent)
                        }

                        if totalFilterCount > 0 {
                            Button {
                                clearAllFilters()
                            } label: {
                                Text("清除")
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .tint(magicPalette.accent)
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
    }

    private var selectedFiltersSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已选条件 (\(totalFilterCount))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(magicPalette.primaryText)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedFilterItems, id: \.id) { item in
                        selectedFilterChip(item: item)
                    }
                }
            }
        }
        .padding(12)
        .background(magicPalette.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(magicPalette.secondaryText.opacity(0.3), lineWidth: 0.5)
        )
    }

    private struct SelectedFilterItem: Identifiable {
        let id = UUID()
        let section: MergeFilterSection
        let value: String
        let rawValue: String
    }

    private var selectedFilterItems: [SelectedFilterItem] {
        var items: [SelectedFilterItem] = []

        for id in selectedTagIDs {
            let name = id == MergeToAccessorySheet.noTagUUID ? "无标签" : tags.first(where: { $0.id == id })?.name ?? ""
            items.append(SelectedFilterItem(section: .tags, value: name, rawValue: id.uuidString))
        }

        for id in selectedBrandIDs {
            let name = id == MergeToAccessorySheet.noBrandUUID ? "无品牌" : brands.first(where: { $0.id == id })?.name ?? ""
            items.append(SelectedFilterItem(section: .brands, value: name, rawValue: id.uuidString))
        }

        for type in selectedTypes {
            let name = type == MergeToAccessorySheet.noTypeMarker ? "无类型" : type
            items.append(SelectedFilterItem(section: .types, value: name, rawValue: type))
        }

        for color in selectedColors {
            let name = color == MergeToAccessorySheet.noColorMarker ? "无颜色" : color
            items.append(SelectedFilterItem(section: .colors, value: name, rawValue: color))
        }

        for size in selectedSizes {
            let name = size == MergeToAccessorySheet.noSizeMarker ? "无尺码" : size
            items.append(SelectedFilterItem(section: .sizes, value: name, rawValue: size))
        }

        for length in selectedLengths {
            let name = length == MergeToAccessorySheet.noLengthMarker ? "无衣长" : length
            items.append(SelectedFilterItem(section: .length, value: name, rawValue: length))
        }

        for condition in selectedConditions {
            let name = condition == MergeToAccessorySheet.noConditionMarker ? "无状态" : condition
            items.append(SelectedFilterItem(section: .condition, value: name, rawValue: condition))
        }

        for accessory in selectedAccessories {
            let name = accessory == MergeToAccessorySheet.noAccessoryMarker ? "无小物" : accessory
            items.append(SelectedFilterItem(section: .accessories, value: name, rawValue: accessory))
        }

        return items
    }

    private func selectedFilterChip(item: SelectedFilterItem) -> some View {
        HStack(spacing: 4) {
            Text(item.value)
                .font(.caption)
                .fontWeight(.medium)

            Button {
                removeFilterItem(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
            }
        }
        .foregroundStyle(magicPalette.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(magicPalette.accent.opacity(0.15))
        .cornerRadius(16)
    }

    private func removeFilterItem(_ item: SelectedFilterItem) {
        switch item.section {
        case .tags:
            if let uuid = UUID(uuidString: item.rawValue) {
                selectedTagIDs.remove(uuid)
            }
        case .brands:
            if let uuid = UUID(uuidString: item.rawValue) {
                selectedBrandIDs.remove(uuid)
            }
        case .types:
            selectedTypes.remove(item.rawValue)
        case .colors:
            selectedColors.remove(item.rawValue)
        case .sizes:
            selectedSizes.remove(item.rawValue)
        case .length:
            selectedLengths.remove(item.rawValue)
        case .condition:
            selectedConditions.remove(item.rawValue)
        case .accessories:
            selectedAccessories.remove(item.rawValue)
        }
    }

    private func filterRow(section: MergeFilterSection, title: String, icon: String, selectedCount: Int, options: [MergeFilterOption]) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSection = expandedSection == section ? nil : section
                }
            } label: {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(selectedCount > 0 ? magicPalette.accent : magicPalette.secondaryText)
                        .frame(width: 28)

                    Text(title)
                        .font(.body)
                        .foregroundStyle(magicPalette.primaryText)

                    Spacer()

                    if selectedCount > 0 {
                        Text("\(selectedCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(magicPalette.accent)
                            .cornerRadius(10)
                    }

                    Image(systemName: expandedSection == section ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14))
                        .foregroundStyle(magicPalette.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(magicPalette.cardBackground)
            }
            .buttonStyle(.plain)

            if expandedSection == section {
                filterOptionsGrid(options: options, section: section)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .background(magicPalette.cardBackground)
            }
        }
        .background(magicPalette.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selectedCount > 0 ? magicPalette.accent.opacity(0.5) : magicPalette.secondaryText.opacity(0.3), lineWidth: selectedCount > 0 ? 1.5 : 0.5)
        )
    }

    private func dynamicFilterRow(for field: ClothingField) -> some View {
        let (title, icon, selectedCount, options) = fieldConfig(for: field)
        return filterRow(section: mergeFilterSection(for: field), title: title, icon: icon, selectedCount: selectedCount, options: options)
    }

    private func fieldConfig(for field: ClothingField) -> (title: String, icon: String, count: Int, options: [MergeFilterOption]) {
        switch field {
        case .types:
            return ("类型", "tshirt", selectedTypes.count, typeOptions)
        case .colors:
            return ("颜色", "paintpalette", selectedColors.count, colorOptions)
        case .sizes:
            return ("尺码", "ruler", selectedSizes.count, sizeOptions)
        case .length:
            return ("衣长", "arrow.up.and.down", selectedLengths.count, lengthOptions)
        case .condition:
            return ("状态", "star", selectedConditions.count, conditionOptions)
        case .accessories:
            return ("小物", "sparkles", selectedAccessories.count, accessoryOptions)
        }
    }

    private func mergeFilterSection(for field: ClothingField) -> MergeFilterSection {
        switch field {
        case .types: return .types
        case .colors: return .colors
        case .sizes: return .sizes
        case .length: return .length
        case .condition: return .condition
        case .accessories: return .accessories
        }
    }

    private func filterOptionsGrid(options: [MergeFilterOption], section: MergeFilterSection) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
            ForEach(options) { option in
                filterOptionButton(option: option, section: section)
            }
        }
    }

    private func filterOptionButton(option: MergeFilterOption, section: MergeFilterSection) -> some View {
        let isSelected = isOptionSelected(option: option, section: section)

        return Button {
            toggleOption(option: option, section: section)
        } label: {
            Text(option.displayName)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? magicPalette.accent : magicPalette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? magicPalette.accent.opacity(0.15) : magicPalette.cardBackground.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? magicPalette.accent : magicPalette.secondaryText.opacity(0.3), lineWidth: isSelected ? 1.5 : 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private struct MergeFilterOption: Identifiable {
        let id = UUID()
        let value: String
        let displayName: String
    }

    private var tagOptions: [MergeFilterOption] {
        var options: [MergeFilterOption] = []
        options.append(MergeFilterOption(value: MergeToAccessorySheet.noTagUUID.uuidString, displayName: "无标签"))
        options.append(contentsOf: tags.map { MergeFilterOption(value: $0.id.uuidString, displayName: $0.name) })
        return options
    }

    private var brandOptions: [MergeFilterOption] {
        var options: [MergeFilterOption] = []
        options.append(MergeFilterOption(value: MergeToAccessorySheet.noBrandUUID.uuidString, displayName: "无品牌"))
        options.append(contentsOf: brands.map { MergeFilterOption(value: $0.id.uuidString, displayName: $0.name) })
        return options
    }

    private var typeOptions: [MergeFilterOption] {
        var options: [MergeFilterOption] = []
        options.append(MergeFilterOption(value: MergeToAccessorySheet.noTypeMarker, displayName: "无类型"))
        let values = getAllValues(for: \.types)
        options.append(contentsOf: values.map { MergeFilterOption(value: $0, displayName: $0) })
        return options
    }

    private var colorOptions: [MergeFilterOption] {
        var options: [MergeFilterOption] = []
        options.append(MergeFilterOption(value: MergeToAccessorySheet.noColorMarker, displayName: "无颜色"))
        let values = getAllValues(for: \.colors)
        options.append(contentsOf: values.map { MergeFilterOption(value: $0, displayName: $0) })
        return options
    }

    private var sizeOptions: [MergeFilterOption] {
        var options: [MergeFilterOption] = []
        options.append(MergeFilterOption(value: MergeToAccessorySheet.noSizeMarker, displayName: "无尺码"))
        let values = getAllValues(for: \.sizes)
        options.append(contentsOf: values.map { MergeFilterOption(value: $0, displayName: $0) })
        return options
    }

    private var lengthOptions: [MergeFilterOption] {
        var options: [MergeFilterOption] = []
        options.append(MergeFilterOption(value: MergeToAccessorySheet.noLengthMarker, displayName: "无衣长"))
        let values = getAllValues(for: \.length)
        options.append(contentsOf: values.map { MergeFilterOption(value: $0, displayName: $0) })
        return options
    }

    private var conditionOptions: [MergeFilterOption] {
        var options: [MergeFilterOption] = []
        options.append(MergeFilterOption(value: MergeToAccessorySheet.noConditionMarker, displayName: "无状态"))
        let values = getAllValues(for: \.condition)
        options.append(contentsOf: values.map { MergeFilterOption(value: $0, displayName: $0) })
        return options
    }

    private var accessoryOptions: [MergeFilterOption] {
        var options: [MergeFilterOption] = []
        options.append(MergeFilterOption(value: MergeToAccessorySheet.noAccessoryMarker, displayName: "无小物"))
        let values = getAllValues(for: \.accessories)
        options.append(contentsOf: values.map { MergeFilterOption(value: $0, displayName: $0) })
        return options
    }

    private func isOptionSelected(option: MergeFilterOption, section: MergeFilterSection) -> Bool {
        switch section {
        case .tags:
            if let uuid = UUID(uuidString: option.value) {
                return selectedTagIDs.contains(uuid)
            }
            return false
        case .brands:
            if let uuid = UUID(uuidString: option.value) {
                return selectedBrandIDs.contains(uuid)
            }
            return false
        case .types:
            return selectedTypes.contains(option.value)
        case .colors:
            return selectedColors.contains(option.value)
        case .sizes:
            return selectedSizes.contains(option.value)
        case .length:
            return selectedLengths.contains(option.value)
        case .condition:
            return selectedConditions.contains(option.value)
        case .accessories:
            return selectedAccessories.contains(option.value)
        }
    }

    private func toggleOption(option: MergeFilterOption, section: MergeFilterSection) {
        switch section {
        case .tags:
            if let uuid = UUID(uuidString: option.value) {
                if selectedTagIDs.contains(uuid) {
                    selectedTagIDs.remove(uuid)
                } else {
                    selectedTagIDs.insert(uuid)
                }
            }
        case .brands:
            if let uuid = UUID(uuidString: option.value) {
                if selectedBrandIDs.contains(uuid) {
                    selectedBrandIDs.remove(uuid)
                } else {
                    selectedBrandIDs.insert(uuid)
                }
            }
        case .types:
            if selectedTypes.contains(option.value) {
                selectedTypes.remove(option.value)
            } else {
                selectedTypes.insert(option.value)
            }
        case .colors:
            if selectedColors.contains(option.value) {
                selectedColors.remove(option.value)
            } else {
                selectedColors.insert(option.value)
            }
        case .sizes:
            if selectedSizes.contains(option.value) {
                selectedSizes.remove(option.value)
            } else {
                selectedSizes.insert(option.value)
            }
        case .length:
            if selectedLengths.contains(option.value) {
                selectedLengths.remove(option.value)
            } else {
                selectedLengths.insert(option.value)
            }
        case .condition:
            if selectedConditions.contains(option.value) {
                selectedConditions.remove(option.value)
            } else {
                selectedConditions.insert(option.value)
            }
        case .accessories:
            if selectedAccessories.contains(option.value) {
                selectedAccessories.remove(option.value)
            } else {
                selectedAccessories.insert(option.value)
            }
        }
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

    private func getAllValues(for keyPath: KeyPath<Clothing, String>) -> [String] {
        let allString = clothings.map { $0[keyPath: keyPath] }.joined(separator: ",")
        let normalizedString = allString.replacingOccurrences(of: "，", with: ",")
        return Array(Set(normalizedString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
    }
}

enum MergeFilterSection {
    case tags, brands, types, colors, sizes, length, condition, accessories
}
