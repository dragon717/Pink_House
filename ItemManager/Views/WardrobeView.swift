//
//  WardrobeView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct WardrobeView: View {
    @Binding var searchText: String
    @Binding var isSelectionMode: Bool
    @Binding var isEditing: Bool
    @Environment(\.modelContext) private var modelContext
    @Query private var clothings: [Clothing]
    @State private var showStats = true
    
    // Edit Mode States
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var editableClothings: [Clothing] = []
    @State private var draggingItem: Clothing?
    
    // Batch Actions States
    @State private var showingDeleteAlert = false
    @State private var showingTagSelection = false
    @State private var tempSelectedTags: [Tag] = []
    @State private var showingAddTagsConfirmation = false
    @State private var showingBrandSelection = false
    @State private var tempSelectedBrand: Brand?
    @State private var showingSetBrandConfirmation = false
    
    // Auto-scroll
    @State private var visibleItemIDs: Set<UUID> = []
    @State private var autoScrollTask: Task<Void, Never>?
    
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
         filterDescription: String? = nil,
         onClearFilter: (() -> Void)? = nil) {
        _searchText = searchText
        _isSelectionMode = isSelectionMode
        _isEditing = isEditing
        self.sortOption = sortOption
        _clothings = Query(filter: #Predicate<Clothing> { $0.isDeleted == false }, sort: sortOption.sortDescriptors)
        self.viewLayout = viewLayout
        
        self.selectedTagIDs = selectedTagIDs
        self.selectedBrandIDs = selectedBrandIDs
        self.selectedTypes = selectedTypes
        self.selectedColors = selectedColors
        self.selectedSizes = selectedSizes
        self.selectedLengths = selectedLengths
        self.selectedConditions = selectedConditions
        self.selectedAccessories = selectedAccessories
        
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
    
    var filteredClothings: [Clothing] {
        clothings.filter { clothing in
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
            
            return matchesSearch && matchesTag && matchesBrand && matchesType && matchesColor && matchesSize && matchesLength && matchesCondition && matchesAccessory
        }
    }
    
    // Helper for splitting strings with support for both English and Chinese commas
    func splitValues(_ string: String) -> Set<String> {
        let normalized = string.replacingOccurrences(of: "，", with: ",")
        return Set(normalized.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }
    
    var body: some View {
        Group {
            switch viewLayout {
            case .listBrief, .listDetailed:
                List {
                    Section {
                        statsSection
                            .padding(.top, 10)
                            .padding(.bottom, 8)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    
                    if isEditing {
                        ForEach(editableClothings) { clothing in
                            ZStack {
                                VStack(spacing: 0) {
                                    if viewLayout == .listBrief {
                                        ClothingRowBrief(clothing: clothing)
                                    } else {
                                        ClothingRow(clothing: clothing)
                                    }
                                    
                                    Divider()
                                        .padding(.leading)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .onMove { from, to in
                            editableClothings.move(fromOffsets: from, toOffset: to)
                        }
                    } else {
                        ForEach(filteredClothings) { clothing in
                            ZStack {
                                if isSelectionMode {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedItemIDs.contains(clothing.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(selectedItemIDs.contains(clothing.id) ? .pink : .secondary)
                                        
                                        VStack(spacing: 0) {
                                            if viewLayout == .listBrief {
                                                ClothingRowBrief(clothing: clothing)
                                            } else {
                                                ClothingRow(clothing: clothing)
                                            }
                                            
                                            Divider()
                                                .padding(.leading)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        toggleSelection(clothing.id)
                                    }
                                } else {
                                    NavigationLink(destination: ClothingDetailView(clothing: clothing)) {
                                        EmptyView()
                                    }
                                    .opacity(0)
                                    
                                    VStack(spacing: 0) {
                                        if viewLayout == .listBrief {
                                            ClothingRowBrief(clothing: clothing)
                                        } else {
                                            ClothingRow(clothing: clothing)
                                        }
                                        
                                        Divider()
                                            .padding(.leading)
                                    }
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    
                    // Bottom padding
                    Color.clear.frame(height: 100)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(isEditing ? .active : .inactive))
                
            case .grid2, .grid3, .grid6:
                ScrollViewReader { proxy in
                    ZStack {
                        ScrollView {
                            VStack(spacing: 20) {
                                statsSection
                                
                                LazyVGrid(columns: gridColumns, spacing: viewLayout == .grid6 ? 2 : 16) {
                                    if isEditing {
                                        ForEach(editableClothings) { clothing in
                                            ZStack {
                                                if viewLayout == .grid6 {
                                                    ClothingThumbnail(clothing: clothing)
                                                } else {
                                                    ClothingCard(clothing: clothing)
                                                }
                                            }
                                            .contentShape(Rectangle())
                                            .onAppear { 
                                                if isEditing {
                                                    visibleItemIDs.insert(clothing.id) 
                                                }
                                            }
                                            .onDisappear { 
                                                if isEditing {
                                                    visibleItemIDs.remove(clothing.id) 
                                                }
                                            }
                                            .onDrag {
                                                self.draggingItem = clothing
                                                return NSItemProvider(object: clothing.id.uuidString as NSString)
                                            }
                                            .onDrop(of: [UTType.text], delegate: DropViewDelegate(item: clothing, items: $editableClothings, draggingItem: $draggingItem))
                                        }
                                    } else {
                                        ForEach(filteredClothings) { clothing in
                                            if isSelectionMode {
                                                ZStack(alignment: .topTrailing) {
                                                    if viewLayout == .grid6 {
                                                        ClothingThumbnail(clothing: clothing)
                                                    } else {
                                                        ClothingCard(clothing: clothing)
                                                    }
                                                    
                                                    // Selection Indicator
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
                                            } else {
                                                NavigationLink {
                                                    ClothingDetailView(clothing: clothing)
                                                } label: {
                                                    if viewLayout == .grid6 {
                                                        ClothingThumbnail(clothing: clothing)
                                                    } else {
                                                        ClothingCard(clothing: clothing)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                .id(isEditing ? "editing" : "viewing") // Force recreate LazyVGrid when mode changes
                                .animation(.default, value: editableClothings)
                                .padding(.horizontal, viewLayout == .grid6 ? 2 : 16)
                                .padding(.bottom, 100)
                            }
                            .padding(.top, 10)
                        }
                        .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                            self.draggingItem = nil
                            return true
                        }
                        
                        // Auto-scroll Drop Zones
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
        }
        .toolbar {
        }
        .onChange(of: isEditing) { oldValue, newValue in
            if newValue {
                // Start editing
                editableClothings = filteredClothings
            } else {
                // Save order
                saveOrder()
                editableClothings = []
            }
        }
        .onChange(of: isSelectionMode) { oldValue, newValue in
            if newValue {
                // Entered selection mode
                if isEditing {
                    isEditing = false // Will trigger saveOrder via onChange above
                }
            } else {
                // Exited selection mode
                selectedItemIDs.removeAll()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        // Delete
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
                        
                        // Add Tags
                        Button {
                            tempSelectedTags = []
                            showingTagSelection = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "tag")
                                Text("添加标签")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(selectedItemIDs.isEmpty)
                        
                        Divider()
                            .frame(height: 20)
                        
                        // Group to Brand
                        Button {
                            tempSelectedBrand = nil
                            showingBrandSelection = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "bag")
                                Text("归类品牌")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(selectedItemIDs.isEmpty)
                    }
                    .padding()
                    .background(.regularMaterial)
                }
            }
        }
        .sheet(isPresented: $showingTagSelection) {
            TagSelectionView(selectedTags: $tempSelectedTags)
                .onDisappear {
                    if !tempSelectedTags.isEmpty {
                        showingAddTagsConfirmation = true
                    }
                }
        }
        .sheet(isPresented: $showingBrandSelection) {
            BrandSelectionView(selectedBrand: $tempSelectedBrand)
                .onDisappear {
                    if tempSelectedBrand != nil {
                        showingSetBrandConfirmation = true
                    }
                }
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除 \(selectedItemIDs.count) 项", role: .destructive) {
                deleteSelectedItems()
            }
        }
        .alert("确认添加标签", isPresented: $showingAddTagsConfirmation) {
            Button("取消", role: .cancel) {
                tempSelectedTags = []
            }
            Button("确认添加") {
                if !tempSelectedTags.isEmpty {
                    addTagsToSelectedItems(tempSelectedTags)
                }
            }
        } message: {
            Text("确定要为选中的 \(selectedItemIDs.count) 件物品添加 \(tempSelectedTags.count) 个标签吗？")
        }
        .alert("确认归类品牌", isPresented: $showingSetBrandConfirmation) {
            Button("取消", role: .cancel) {
                tempSelectedBrand = nil
            }
            Button("确认修改") {
                if let brand = tempSelectedBrand {
                    setBrandForSelectedItems(brand)
                }
            }
        } message: {
            if let brand = tempSelectedBrand {
                Text("确定要将选中的 \(selectedItemIDs.count) 件物品归类到品牌“\(brand.name)”吗？")
            }
        }
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }
    
    private func deleteSelectedItems() {
        let itemsToDelete = clothings.filter { selectedItemIDs.contains($0.id) }
        for item in itemsToDelete {
            item.isDeleted = true
            item.deletedAt = Date()
        }
        try? modelContext.save()
        
        withAnimation {
            isSelectionMode = false
            selectedItemIDs.removeAll()
        }
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
        tempSelectedTags = []
    }
    
    private func setBrandForSelectedItems(_ brand: Brand) {
        let items = clothings.filter { selectedItemIDs.contains($0.id) }
        for item in items {
            item.brand = brand
        }
        try? modelContext.save()
        
        // Keep selection mode active as requested
        tempSelectedBrand = nil
    }
    
    private func saveOrder() {
        for (index, clothing) in editableClothings.enumerated() {
            clothing.sortIndex = index
        }
        try? modelContext.save()
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
                WardrobeStatsView(clothings: filteredClothings,
                                  filterDescription: filterDescription,
                                  onClearFilter: onClearFilter)
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

struct WardrobeStatsView: View {
    let clothings: [Clothing]
    var filterDescription: String? = nil
    var onClearFilter: (() -> Void)? = nil
    
    @AppStorage("showStatsCountAndStyle") private var showCountAndStyle = true
    @AppStorage("showStatsDressValue") private var showDressValue = true
    @AppStorage("showStatsTotalValue") private var showTotalValue = true
    
    var styleCount: Int {
        clothings.count
    }
    
    var totalCount: Int {
        clothings.reduce(0) { $0 + $1.stock }
    }
    
    var dressValue: Decimal {
        clothings.reduce(0) { $0 + ($1.price * Decimal($1.stock)) }
    }
    
    var totalValue: Decimal {
        clothings.reduce(0) { $0 + (($1.price + $1.accessoriesPrice) * Decimal($1.stock)) }
    }
    
    var body: some View {
        GlassCard {
            VStack(spacing: 16) {
                // Main Stats
                HStack(spacing: 0) {
                    statItem(title: "总件数/款", value: "\(totalCount)/\(styleCount)", isVisible: $showCountAndStyle)
                    
                    Divider()
                        .frame(height: 30)
                    
                    statItem(title: "裙子价值", value: "¥\(NSDecimalNumber(decimal: dressValue).stringValue)", isVisible: $showDressValue, valueColor: Color(hex: "FF9800"))
                    
                    Divider()
                        .frame(height: 30)
                    
                    statItem(title: "总价值", value: "¥\(NSDecimalNumber(decimal: totalValue).stringValue)", isVisible: $showTotalValue)
                }
                
                // Bottom Action
                NavigationLink(destination: WardrobeStatisticsDetailView(clothings: clothings, filterDescription: filterDescription, onClearFilter: onClearFilter)) {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                        Text("查看详细统计")
                        Spacer()
                        Image(systemName: "heart.fill")
                            .font(.caption)
                        Text("少女专属")
                    }
                    .padding()
                    .background(Color.brown.opacity(0.1))
                    .foregroundStyle(Color.brown)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    private func statItem(title: String, value: String, isVisible: Binding<Bool>, valueColor: Color = .primary) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button {
                    withAnimation {
                        isVisible.wrappedValue.toggle()
                    }
                } label: {
                    Image(systemName: isVisible.wrappedValue ? "eye" : "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .contentShape(Rectangle()) // Make it easier to tap
                }
            }
            
            Text(isVisible.wrappedValue ? value : "****")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }
}

struct DropViewDelegate: DropDelegate {
    let item: Clothing
    @Binding var items: [Clothing]
    @Binding var draggingItem: Clothing?
    
    func performDrop(info: DropInfo) -> Bool {
        self.draggingItem = nil
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem else { return }
        if draggingItem.id == item.id { return }
        
        guard let fromIndex = items.firstIndex(where: { $0.id == draggingItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else { return }
        
        if fromIndex != toIndex {
            withAnimation(.default) {
                let fromItem = items.remove(at: fromIndex)
                items.insert(fromItem, at: toIndex)
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
