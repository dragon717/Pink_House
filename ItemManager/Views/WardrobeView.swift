//
//  WardrobeView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
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
    @State private var showingBatchCopyAlert = false
    @State private var showingTagSelection = false
    @State private var tempSelectedTags: [Tag] = []
    @State private var showingAddTagsConfirmation = false
    @State private var showingBrandSelection = false
    @State private var tempSelectedBrand: Brand?
    @State private var showingSetBrandConfirmation = false
    
    // Batch Edit States
    @State private var showingColorSelection = false
    @State private var tempSelectedColors: [String] = []
    @State private var showingSizeSelection = false
    @State private var tempSelectedSizes: [String] = []
    @State private var showingLengthSelection = false
    @State private var tempSelectedLengths: [String] = []
    @State private var showingAccessorySelection = false
    @State private var tempSelectedAccessories: [String] = []
    @State private var showingStatusSelection = false
    @State private var tempSelectedStatus: String? = nil
    
    // Context Menu Actions
    @State private var itemToDelete: Clothing?
    @State private var showingDeleteSingleAlert = false
    @State private var itemToCopy: Clothing?
    @State private var showingCopyAlert = false
    
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
    private func clothingItemView(clothing: Clothing) -> some View {
        if viewLayout == .grid6 {
            ClothingThumbnail(clothing: clothing)
        } else {
            ClothingCard(clothing: clothing)
        }
    }
    
    @ViewBuilder
    private func clothingRowView(clothing: Clothing) -> some View {
        if viewLayout == .listBrief {
            ClothingRowBrief(clothing: clothing)
        } else {
            ClothingRow(clothing: clothing)
        }
    }
    
    var filteredClothings: [Clothing] {
        // 使用 ClothingSearchService 进行搜索
        let searchService = ClothingSearchService(clothings: clothings)
        let searchResults = searchService.search(query: searchText)
        
        // 如果没有搜索词，返回所有衣物
        let baseResults = searchText.isEmpty ? clothings : searchResults
        
        let result = baseResults.filter { clothing in
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
            
            return matchesTag && matchesBrand && matchesType && matchesColor && matchesSize && matchesLength && matchesCondition && matchesAccessory
        }
        
        // Apply sorting based on sortOption
        // Note: @Query doesn't update dynamically when sortOption changes,
        // so we need to sort here explicitly
        switch sortOption {
        case .custom:
            return result.sorted { $0.sortIndex < $1.sortIndex }
        case .priceAsc:
            return result.sorted { $0.price < $1.price }
        case .priceDesc:
            return result.sorted { $0.price > $1.price }
        case .nameAsc:
            return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .purchaseDateAsc:
            return result.sorted { $0.purchaseDate < $1.purchaseDate }
        case .purchaseDateDesc:
            return result.sorted { $0.purchaseDate > $1.purchaseDate }
        case .createdAtDesc:
            return result.sorted { $0.createdAt > $1.createdAt }
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
                listView

            case .grid2, .grid3, .grid6:
                ScrollViewReader { proxy in
                    ZStack {
                        ScrollView {
                            VStack(spacing: 8) {
                                statsSection
                                    .padding(.horizontal, viewLayout == .grid6 ? 2 : 16)
                                
                                LazyVGrid(columns: gridColumns, spacing: viewLayout == .grid6 ? 2 : 16) {
                                ForEach((isEditing || (isSelectionMode && sortOption == .custom)) ? editableClothings : filteredClothings) { clothing in
                    if isSelectionMode {
                        // 选择模式：显示卡片和选择覆盖层，支持点击选择
                        ZStack(alignment: .topTrailing) {
                            clothingItemView(clothing: clothing)
                            
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
                        .onAppear { visibleItemIDs.insert(clothing.id) }
                        .onDisappear { visibleItemIDs.remove(clothing.id) }
                        // 在选择模式下，如果是自定义排序或开启了排序按钮，允许拖拽
                        .onDrag {
                            guard sortOption == .custom || isEditing else { return NSItemProvider() }
                            self.draggingItem = clothing
                            return NSItemProvider(object: clothing.id.uuidString as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: DropViewDelegate(item: clothing, items: $editableClothings, draggingItem: $draggingItem, isEditing: sortOption == .custom || isEditing, selectedItemIDs: selectedItemIDs))
                        
                    } else if isEditing {
                        // 编辑模式：仅显示卡片，支持拖拽
                        ZStack(alignment: .topTrailing) {
                            clothingItemView(clothing: clothing)
                        }
                        .contentShape(Rectangle())
                        .onAppear { visibleItemIDs.insert(clothing.id) }
                        .onDisappear { visibleItemIDs.remove(clothing.id) }
                        .onDrag {
                            self.draggingItem = clothing
                            return NSItemProvider(object: clothing.id.uuidString as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: DropViewDelegate(item: clothing, items: $editableClothings, draggingItem: $draggingItem, isEditing: true, selectedItemIDs: selectedItemIDs))
                        
                    } else {
                                        // 正常模式：使用 NavigationLink 包裹卡片，支持长按菜单
                                        NavigationLink(destination: ClothingDetailView(clothing: clothing)) {
                                            ZStack(alignment: .topTrailing) {
                                                clothingItemView(clothing: clothing)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button {
                                                isSelectionMode = true
                                                selectedItemIDs.insert(clothing.id)
                                            } label: {
                                                Label("选择", systemImage: "checkmark.circle")
                                            }
                                            
                                            NavigationLink(destination: ClothingDetailView(clothing: clothing)) {
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
                                        .onAppear { visibleItemIDs.insert(clothing.id) }
                                        .onDisappear { visibleItemIDs.remove(clothing.id) }
                                    }
                                }
                            }
                            .animation(isEditing ? .default : nil, value: editableClothings)
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
        // 应用容器就近配色，支持魔法配色和客制化配色
        .containerAdaptiveColors(background: .ultraThinMaterial)
        .onChange(of: isEditing) { oldValue, newValue in
            if newValue {
                // Start editing
                if editableClothings.isEmpty {
                    editableClothings = filteredClothings
                }
            } else {
                // Save order
                saveOrder()
                
                // Only clear if we are NOT in selection mode with custom sort (because selection mode needs it for drag)
                // 也要考虑如果 selection mode 下开启了 isEditing，也不能清除
                if !(isSelectionMode && (sortOption == .custom || isEditing)) {
                    editableClothings = []
                }
            }
        }
        .onChange(of: isSelectionMode) { oldValue, newValue in
            if newValue {
                // Entered selection mode
                
                // 如果是自定义排序模式，或者在选择模式下开启了排序按钮，初始化 editableClothings 以支持拖拽
                if (sortOption == .custom || isEditing) && editableClothings.isEmpty {
                    editableClothings = filteredClothings
                }
            } else {
                // Exited selection mode
                selectedItemIDs.removeAll()
                
                // 如果是自定义排序模式，保存排序结果并清理
                if sortOption == .custom || isEditing {
                    // Only clear if we are NOT in isEditing mode
                    if !isEditing {
                        saveOrder()
                        editableClothings = []
                    }
                }
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

                        // Copy
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

                        // More Actions Menu
                        Menu {
                            Button {
                                tempSelectedTags = []
                                showingTagSelection = true
                            } label: {
                                Label("添加标签", systemImage: "tag")
                            }
                            
                            Button {
                                tempSelectedBrand = nil
                                showingBrandSelection = true
                            } label: {
                                Label("归类品牌", systemImage: "bag")
                            }
                            
                            Divider()
                            
                            Button {
                                tempSelectedColors = []
                                showingColorSelection = true
                            } label: {
                                Label("染上颜色", systemImage: "paintbrush")
                            }
                            
                            Button {
                                tempSelectedSizes = []
                                showingSizeSelection = true
                            } label: {
                                Label("变换尺码", systemImage: "ruler")
                            }
                            
                            Button {
                                tempSelectedLengths = []
                                showingLengthSelection = true
                            } label: {
                                Label("设置衣长", systemImage: "lines.measurement.vertical")
                            }
                            
                            Button {
                                tempSelectedAccessories = []
                                showingAccessorySelection = true
                            } label: {
                                Label("搭配小物", systemImage: "sparkles")
                            }
                            
                            Button {
                                tempSelectedStatus = nil
                                showingStatusSelection = true
                            } label: {
                                Label("改变状态", systemImage: "arrow.2.circlepath")
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "ellipsis.circle")
                                Text("更多")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(selectedItemIDs.isEmpty)

                        Divider()
                            .frame(height: 20)

                        // Select All
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
                    // iOS 18 及以下需要额外底部padding避开TabBar，iOS 19+ 不需要
                    .padding(.bottom, {
                        let version = UIDevice.current.systemVersion
                        let majorVersion = Int(version.split(separator: ".").first ?? "0") ?? 0
                        return majorVersion <= 18 ? 60 : 0
                    }())
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
        .sheet(isPresented: $showingColorSelection) {
            BatchStringSelectionView(
                title: "染上颜色",
                options: SuggestionManager.shared.getAllColors(),
                selectedItems: $tempSelectedColors
            )
            .onDisappear {
                if !tempSelectedColors.isEmpty {
                    batchSetColors(tempSelectedColors)
                }
            }
        }
        .sheet(isPresented: $showingSizeSelection) {
            BatchStringSelectionView(
                title: "变换尺码",
                options: SuggestionManager.shared.getAllSizes(),
                selectedItems: $tempSelectedSizes
            )
            .onDisappear {
                if !tempSelectedSizes.isEmpty {
                    batchSetSizes(tempSelectedSizes)
                }
            }
        }
        .sheet(isPresented: $showingLengthSelection) {
            BatchStringSelectionView(
                title: "设置衣长",
                options: SuggestionManager.shared.getAllLengths(),
                selectedItems: $tempSelectedLengths
            )
            .onDisappear {
                if !tempSelectedLengths.isEmpty {
                    batchSetLengths(tempSelectedLengths)
                }
            }
        }
        .sheet(isPresented: $showingAccessorySelection) {
            BatchStringSelectionView(
                title: "搭配小物",
                options: SuggestionManager.shared.getAllAccessories(),
                selectedItems: $tempSelectedAccessories
            )
            .onDisappear {
                if !tempSelectedAccessories.isEmpty {
                    batchSetAccessories(tempSelectedAccessories)
                }
            }
        }
        .sheet(isPresented: $showingStatusSelection) {
            BatchStatusSelectionView(selectedStatus: $tempSelectedStatus)
                .onDisappear {
                    if let status = tempSelectedStatus {
                        batchSetStatus(status)
                    }
                }
        }
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
                Text("确定要复制“\(item.name)”吗？")
            }
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
        newItem.tags = item.tags
        
        // Duplicate accessory items
        if let items = item.accessoryItems {
            newItem.accessoryItems = items.map { item in
                AccessoryItem(name: item.name, price: item.price, deposit: item.deposit, balance: item.balance, sortIndex: item.sortIndex)
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
                newItem.tags = item.tags
                
                // 复制小物
                if let items = item.accessoryItems {
                    newItem.accessoryItems = items.map { item in
                        AccessoryItem(name: item.name, price: item.price, deposit: item.deposit, balance: item.balance, sortIndex: item.sortIndex)
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
    
    // MARK: - Batch Edit Methods
    
    private func batchSetColors(_ colors: [String]) {
        let items = clothings.filter { selectedItemIDs.contains($0.id) }
        let colorString = colors.joined(separator: ",")
        for item in items {
            item.colors = colorString
        }
        try? modelContext.save()
        tempSelectedColors = []
    }
    
    private func batchSetSizes(_ sizes: [String]) {
        let items = clothings.filter { selectedItemIDs.contains($0.id) }
        let sizeString = sizes.joined(separator: ",")
        for item in items {
            item.sizes = sizeString
        }
        try? modelContext.save()
        tempSelectedSizes = []
    }
    
    private func batchSetLengths(_ lengths: [String]) {
        let items = clothings.filter { selectedItemIDs.contains($0.id) }
        // 衣长通常是单选，取第一个
        let lengthString = lengths.first ?? ""
        for item in items {
            item.length = lengthString
        }
        try? modelContext.save()
        tempSelectedLengths = []
    }
    
    private func batchSetAccessories(_ accessories: [String]) {
        let items = clothings.filter { selectedItemIDs.contains($0.id) }
        let accessoryString = accessories.joined(separator: ",")
        for item in items {
            item.accessories = accessoryString
        }
        try? modelContext.save()
        tempSelectedAccessories = []
    }
    
    private func batchSetStatus(_ status: String) {
        let items = clothings.filter { selectedItemIDs.contains($0.id) }
        if let newStatus = ClothingStatus(rawValue: status) {
            for item in items {
                item.status = newStatus
            }
            try? modelContext.save()
        }
        tempSelectedStatus = nil
    }
    
    private func saveOrder() {
        for (index, clothing) in editableClothings.enumerated() {
            clothing.sortIndex = index
        }
        try? modelContext.save()
    }
    
    /// 更新衣物数量缓存，用于魔法任务进度实时显示
    private func updateClothingCountCache() {
        do {
            let descriptor = FetchDescriptor<Clothing>(predicate: #Predicate { $0.isDeleted == false })
            let count = try modelContext.fetchCount(descriptor)
            FeatureUnlockManager.shared.updateClothingCount(count)
            print("👗 衣物数量缓存已更新: \(count)")
        } catch {
            print("❌ 更新衣物数量缓存失败: \(error)")
        }
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
                                  filterDescription: filterDescription,
                                  onClearFilter: onClearFilter)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var listView: some View {
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
        ZStack {
            VStack(spacing: 0) {
                clothingRowView(clothing: clothing)
                Divider()
                    .padding(.leading)
            }

            NavigationLink(destination: ClothingDetailView(clothing: clothing)) {
                EmptyView()
            }
            .opacity(0)
        }
        .contextMenu {
            contextMenuItems(for: clothing)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            swipeActions(for: clothing)
        }
    }

    private func contextMenuItems(for clothing: Clothing) -> some View {
        Group {
            Button {
                isSelectionMode = true
                selectedItemIDs.insert(clothing.id)
            } label: {
                Label("选择", systemImage: "checkmark.circle")
            }

            NavigationLink(destination: ClothingDetailView(clothing: clothing)) {
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
}

struct WardrobeStatsView: View {
    let clothings: [Clothing]
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
        VStack(spacing: 12) {
            // Main Stats
            HStack(spacing: 0) {
                statItem(title: "总件数/款", value: "\(totalCount)/\(styleCount)", isVisible: $showCountAndStyle)

                Divider()

                statItem(title: "裙子价值", value: "¥\(NSDecimalNumber(decimal: dressValue).stringValue)", isVisible: $showDressValue, valueColor: Color(hex: "FF9800"))

                Divider()

                statItem(title: "总价值", value: "¥\(NSDecimalNumber(decimal: totalValue).stringValue)", isVisible: $showTotalValue)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .sheet(isPresented: $showDailyCheckIn) {
            DailyCheckInView()
        }
    }

    private func statItem(title: String, value: String, isVisible: Binding<Bool>, valueColor: Color? = nil) -> some View {
        VStack(spacing: 4) {
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

            Text(isVisible.wrappedValue ? value : "****")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor ?? palette.primary)
                .contentTransition(.numericText())
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
        
        guard let targetIndex = items.firstIndex(where: { $0.id == targetItem.id }) else { return }
        
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
