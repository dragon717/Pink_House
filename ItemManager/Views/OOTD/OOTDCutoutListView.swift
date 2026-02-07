
import SwiftUI
import SwiftData

struct OOTDCutoutListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CutoutItem.timestamp, order: .reverse) private var cutouts: [CutoutItem]
    // Fetch all clothings to build a map for lookup (Performance trade-off: Fetching all is better than N+1 queries)
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) private var allClothings: [Clothing]
    
    private var clothingMap: [UUID: Clothing] {
        Dictionary(uniqueKeysWithValues: allClothings.map { ($0.id, $0) })
    }
    
    @Binding var isExpanded: Bool
    var isLandscape: Bool = false
    var onSelect: (CutoutItem) -> Void
    var onAddPhoto: () -> Void
    var onBatchAdd: (([CutoutItem]) -> Bool)? // Optional batch callback, returns success
    
    @State private var showErrorAlert = false
    @State private var searchText = ""
    @State private var selectedCategory = "全部"
    
    // Selection Mode State
    @State private var isEditing = false
    @State private var selectedItems = Set<UUID>()
    @State private var displayItems: [CutoutItem] = []
    
    // Swipe Selection States
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var isDraggingSelection = false
    @State private var dragInitialSelectionState: Bool? = nil // true: selecting, false: deselecting
    @State private var draggedItems = Set<UUID>() // Items touched in current drag
    
    // Batch Action States
    @State private var showDeleteConfirmation = false
    @State private var showAddConfirmation = false
    @State private var showBatchCategorySheet = false
    
    // Single Action States
    @State private var itemToDelete: CutoutItem?
    @State private var showSingleDeleteConfirmation = false
    
    // Reclassify & Reprocess States
    @State private var itemToReclassify: CutoutItem?
    // @State private var showReclassifySheet = false // Removed in favor of item-based sheet
    @State private var processingItem: UUID? = nil // ID of item being processed
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    // Toast State
    @State private var showToast = false
    @State private var toastMessage = ""
    
    private let categories = ["全部", "裙子", "外套", "鞋子", "袜子", "玩偶", "小物", "未分类"]
    // For picker (exclude "全部")
    private var selectableCategories: [String] {
        categories.filter { $0 != "全部" }
    }
    
    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "全部": return "square.grid.2x2.fill"
        case "裙子": return "frock.fill"
        case "外套": return "jacket.fill"
        case "鞋子": return "shoe.fill"
        case "袜子": return "sun.min.fill" // 暂替代
        case "玩偶": return "teddybear.fill"
        case "小物": return "bag.fill"
        case "未分类": return "questionmark.circle.fill"
        default: return "tag.fill"
        }
    }
    
    private func updateDisplayItems() {
        var result = cutouts
        
        // Use a lightweight lookup for clothing info since we decoupled the relationship
        // We can't query all clothings every time, so we might need a strategy.
        // For now, let's fetch all clothings once or rely on an injected map?
        // Actually, for displayItems, we need to know the linked clothing's name/type.
        // Since we are inside a View, we can use a Query to get all clothings and build a map.
        // But @Query is already there in other views. Let's add it here.
        
        // Filter by Category
        if selectedCategory != "全部" {
            result = result.filter { item in
                // 精确匹配
                if item.category == selectedCategory { return true }
                
                // 兼容旧数据
                if let standardized = CutoutService.shared.standardizeCategory(item.category),
                   standardized == selectedCategory {
                    return true
                }
                
                // 救援逻辑：利用关联服饰的名称/类型修正分类显示
                // Need to find the clothing by ID
                if ["小物", "未分类"].contains(item.category), 
                   let clothingID = item.linkedClothingID,
                   let clothing = clothingMap[clothingID] {
                    
                    let nameInfo = (clothing.name + clothing.types).lowercased()
                    
                    if selectedCategory == "裙子" && (nameInfo.contains("裙") || nameInfo.contains("jsk") || nameInfo.contains("op") || nameInfo.contains("dress")) {
                        return true
                    }
                    if selectedCategory == "外套" && (nameInfo.contains("外套") || nameInfo.contains("上衣") || nameInfo.contains("开衫") || nameInfo.contains("shirt") || nameInfo.contains("top")) {
                        return true
                    }
                    if selectedCategory == "袜子" && (nameInfo.contains("袜") || nameInfo.contains("sock")) {
                        return true
                    }
                    if selectedCategory == "鞋子" && (nameInfo.contains("鞋") || nameInfo.contains("靴") || nameInfo.contains("shoe") || nameInfo.contains("boot")) {
                        return true
                    }
                    if selectedCategory == "玩偶" && (nameInfo.contains("玩偶") || nameInfo.contains("娃") || nameInfo.contains("toy") || nameInfo.contains("公仔") || nameInfo.contains("手办") || nameInfo.contains("doll") || nameInfo.contains("毛绒") || nameInfo.contains("bear") || nameInfo.contains("rabbit") || nameInfo.contains("熊")) {
                        return true
                    }
                }
                
                // 特殊处理 "未分类"
                if selectedCategory == "未分类" {
                    let standardCategories = ["裙子", "外套", "鞋子", "袜子", "玩偶", "小物"]
                    if standardCategories.contains(item.category) { return false }
                    if let _ = CutoutService.shared.standardizeCategory(item.category) {
                        return false
                    }
                    return true
                }
                
                return false
            }
        }
        
        // Filter by Search Text
        if !searchText.isEmpty {
            result = result.filter { item in
                let categoryMatch = item.category.localizedCaseInsensitiveContains(searchText)
                var clothingNameMatch = false
                if let clothingID = item.linkedClothingID, let clothing = clothingMap[clothingID] {
                    clothingNameMatch = clothing.name.localizedCaseInsensitiveContains(searchText)
                }
                return categoryMatch || clothingNameMatch
            }
        }
        
        withAnimation {
            displayItems = result
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle (Only in Portrait)
            if !isLandscape {
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 5)
            }
            
            if isExpanded || isLandscape {
                // Header, Search, Filter (Show if expanded, or if landscape and expanded)
                // In Landscape + Collapsed, we hide these to save space
                if isExpanded {
                    // Header
                    HStack {
                        Text("贴纸库")
                            .font(.headline)
                        Spacer()
                        
                        if isEditing {
                            let currentIDs = Set(displayItems.map { $0.id })
                            let isAllSelected = !displayItems.isEmpty && currentIDs.isSubset(of: selectedItems)
                            
                            // 全选按钮
                            Button(action: {
                                withAnimation {
                                    if isAllSelected {
                                        selectedItems.subtract(currentIDs)
                                    } else {
                                        selectedItems.formUnion(currentIDs)
                                    }
                                }
                            }) {
                                Text(isAllSelected ? "取消全选" : "全选")
                                    .font(.subheadline)
                            }
                            .padding(.trailing, 8)
                            
                            // 选中/总数
                            Text("\(selectedItems.count)/\(displayItems.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } else {
                            Text("共 \(displayItems.count) 个")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Button(action: {
                            withAnimation {
                                isEditing.toggle()
                                selectedItems.removeAll()
                            }
                        }) {
                            Text(isEditing ? "完成" : "多选")
                                .fontWeight(isEditing ? .bold : .regular)
                                .foregroundColor(isEditing ? .accentColor : .primary)
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("搜索分类或关联服饰...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    
                    // Category Filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories, id: \.self) { category in
                                CategoryChip(title: category, icon: iconForCategory(category), isSelected: selectedCategory == category) {
                                    withAnimation {
                                        selectedCategory = category
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
                
                // Expanded View (Grid)
                // In Landscape + Collapsed (Narrow), this grid will adapt to 1 column
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 16)], spacing: 16) {
                        if !isEditing {
                            addButton
                        }
                        
                        ForEach(displayItems) { item in
                            menuForItem(item)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .preference(key: ItemFrameKey.self, value: [item.id: geo.frame(in: .named("gridSpace"))])
                                    }
                                )
                        }
                    }
                    .padding()
                    .padding(.bottom, isEditing ? 80 : 0) // Space for toolbar
                }
                .coordinateSpace(name: "gridSpace")
                .onPreferenceChange(ItemFrameKey.self) { frames in
                    itemFrames = frames
                }
                .gesture(
                    isEditing ? DragGesture(minimumDistance: 10, coordinateSpace: .named("gridSpace"))
                        .onChanged { value in
                            handleDragSelection(value: value)
                        }
                        .onEnded { _ in
                            endDragSelection()
                        } : nil
                )
                
                // Bottom Toolbar (Batch Actions)
                if isEditing {
                    VStack(spacing: 0) {
                        Divider()
                        HStack {
                            // Delete
                            Button(action: { showDeleteConfirmation = true }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 20))
                                    Text("删除")
                                        .font(.caption)
                                }
                                .foregroundColor(.red)
                            }
                            .disabled(selectedItems.isEmpty)
                            
                            Spacer()
                            
                            // Categorize
                            Button(action: { showBatchCategorySheet = true }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "tag")
                                        .font(.system(size: 20))
                                    Text("分类")
                                        .font(.caption)
                                }
                            }
                            .disabled(selectedItems.isEmpty)
                            
                            Spacer()
                            
                            // Add to Canvas
                            Button(action: {
                                showAddConfirmation = true
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "plus.square.on.square")
                                        .font(.system(size: 20))
                                    Text("添加到画布")
                                        .font(.caption)
                                }
                            }
                            .disabled(selectedItems.isEmpty)
                        }
                        .padding()
                        .background(Color(uiColor: .systemBackground))
                    }
                    .transition(.move(edge: .bottom))
                }
            } else {
                // Minimized View (Horizontal Scroll) - Only for Portrait!
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        addButton
                        
                        ForEach(cutouts.prefix(20)) { item in
                            // In minimized view, tap still adds directly? 
                            // Or should we enforce menu here too? 
                            // User said "提供点击不是直接放到画布上...是先弹出菜单"
                            // Let's use menu here too for consistency.
                            menuForItem(item)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(
            Color(uiColor: .systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 10, x: isLandscape ? -5 : 0, y: isLandscape ? 0 : -5)
        )
        .clipShape(RoundedRectangle(cornerRadius: isLandscape ? 0 : 24, style: .continuous)) // No rounded corners in landscape
        .onTapGesture {
            // Expand on tap if not tapping an item
            // Only relevant for Portrait Minimized view? 
            // In Landscape Collapsed, tapping empty space might expand?
            if !isExpanded && !isLandscape {
                 // withAnimation { isExpanded = true } 
                 // Removing this as it might conflict with item taps if not careful, 
                 // but originally it was there (implied). 
                 // Original code had empty onTapGesture comment.
            }
        }
        .gesture(
            // Drag to expand/collapse - Only for Portrait
            !isLandscape ? DragGesture()
                .onEnded { value in
                    if value.translation.height < -50 {
                        withAnimation { isExpanded = true }
                    } else if value.translation.height > 50 {
                        withAnimation { isExpanded = false }
                    }
                } : nil
        )
        .alert("提示", isPresented: $showAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("删除 \(selectedItems.count) 项", role: .destructive) {
                batchDelete()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("确定要删除选中的 \(selectedItems.count) 个抠图吗？此操作无法撤销。")
        }
        .alert("确认添加", isPresented: $showAddConfirmation) {
            Button("添加", role: .none) {
                batchAddToCanvas()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("确定将选中的 \(selectedItems.count) 个抠图添加到当前画布吗？")
        }
        .alert("确认删除", isPresented: $showSingleDeleteConfirmation) {
            Button("删除", role: .destructive) {
                if let item = itemToDelete {
                    deleteCutout(item)
                }
                itemToDelete = nil
            }
            Button("取消", role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            Text("确定要删除这个贴纸吗？此操作无法撤销。")
        }
        .sheet(isPresented: $showBatchCategorySheet) {
            BatchReclassifyView(categories: selectableCategories) { newCategory in
                batchReclassify(to: newCategory)
                showBatchCategorySheet = false
            }
            .presentationDetents([.height(350)])
        }
        .sheet(item: $itemToReclassify) { item in
            ReclassifyView(item: item, categories: selectableCategories) { newCategory in
                item.category = newCategory
                try? modelContext.save()
                itemToReclassify = nil
            }
            .presentationDetents([.height(350)])
        }
        .task(id: cutouts) { updateDisplayItems() }
        .onChange(of: searchText) { _, _ in updateDisplayItems() }
        .onChange(of: selectedCategory) { _, _ in updateDisplayItems() }
        .overlay(alignment: .bottom) {
            if showToast {
                toastView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
            }
        }
    }
    
    private func menuForItem(_ item: CutoutItem) -> some View {
        Group {
            if isEditing {
                Button {
                    toggleSelection(for: item)
                } label: {
                    itemThumbnailView(item)
                        .overlay(alignment: .bottomTrailing) {
                            if selectedItems.contains(item.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.white, .blue)
                                    .font(.title3)
                                    .padding(4)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.white)
                                    .shadow(radius: 2)
                                    .font(.title3)
                                    .padding(4)
                            }
                        }
                }
            } else {
                Menu {
                    Button {
                        onSelect(item)
                        withAnimation { isExpanded = false }
                    } label: {
                        Label("添加到画布", systemImage: "plus.square.on.square")
                    }
                    
                    Button {
                        reprocessCutout(item)
                    } label: {
                        Label("重新抠图", systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    Button {
                        itemToReclassify = item
                    } label: {
                        Label("修改分类", systemImage: "tag")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        itemToDelete = item
                        showSingleDeleteConfirmation = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    itemThumbnailView(item)
                }
            }
        }
    }
    
    private func itemThumbnailView(_ item: CutoutItem) -> some View {
        CutoutThumbnail(imagePath: item.imagePath, category: item.category)
            .overlay {
                if processingItem == item.id {
                    ZStack {
                        Color.black.opacity(0.3)
                            .cornerRadius(12)
                        ProgressView()
                            .tint(.white)
                    }
                }
            }
    }
    
    private func toggleSelection(for item: CutoutItem) {
        if selectedItems.contains(item.id) {
            selectedItems.remove(item.id)
        } else {
            selectedItems.insert(item.id)
        }
    }
    
    private func batchDelete() {
        let itemsToDelete = cutouts.filter { selectedItems.contains($0.id) }
        var imagePaths: [String] = []
        imagePaths.reserveCapacity(itemsToDelete.count)
        
        for item in itemsToDelete {
            imagePaths.append(item.imagePath)
            CutoutService.shared.handleCutoutDeletion(imagePath: item.imagePath, context: modelContext)
        }
        
        autoreleasepool {
            for item in itemsToDelete {
                modelContext.delete(item)
            }
        }
        
        ImageManager.shared.batchDeleteImages(fileNames: imagePaths, context: modelContext)
        
        do {
            try modelContext.save()
            withAnimation {
                selectedItems.removeAll()
                updateDisplayItems()
            }
            toastMessage = "已删除 \(itemsToDelete.count) 个贴纸"
            withAnimation { showToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showToast = false }
            }
        } catch {
            alertMessage = "批量删除失败，请稍后重试。"
            showAlert = true
        }
    }
    
    private func batchReclassify(to category: String) {
        let itemsToUpdate = cutouts.filter { selectedItems.contains($0.id) }
        for item in itemsToUpdate {
            item.category = category
        }
        try? modelContext.save()
        // selectedItems.removeAll() // User requested to keep selection
        // isEditing = false // User requested to stay in edit mode
        updateDisplayItems()
    }
    
    private func batchAddToCanvas() {
        let itemsToAdd = cutouts.filter { selectedItems.contains($0.id) }
        // Keep order somewhat consistent (e.g. oldest first or newest first?)
        // Let's add oldest first so they stack naturally? Or newest on top?
        // Usually adding means "append", so first added is bottom.
        let sortedItems = itemsToAdd.sorted { $0.timestamp < $1.timestamp }
        
        var success = true
        
        if let onBatchAdd = onBatchAdd {
            // Use optimized batch add if available
            success = onBatchAdd(sortedItems)
        } else {
            // Fallback to individual add (assume always success for individual calls as we don't have return value there)
            for item in sortedItems {
                onSelect(item)
            }
        }
        
        if !success {
            return
        }
        
        withAnimation {
            // isEditing = false // User requested to stay in edit mode
            // isExpanded = false // Keep expanded to continue editing
            // selectedItems.removeAll() // User requested to keep selection
        }
        
        // Show Toast
        toastMessage = "已添加 \(itemsToAdd.count) 个贴纸"
        withAnimation {
            showToast = true
        }
        
        // Auto hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showToast = false
            }
        }
    }
    
    // MARK: - Drag Selection Logic
    
    private func handleDragSelection(value: DragGesture.Value) {
        if !isDraggingSelection {
            isDraggingSelection = true
            draggedItems.removeAll()
            dragInitialSelectionState = nil
        }
        
        let location = value.location
        
        // Find which item is under the drag location
        // Optimized: only check if we haven't processed it yet or if we need to set initial state
        for (id, frame) in itemFrames {
            if frame.contains(location) {
                // If this is the first item touched, determine the target state (select or deselect)
                if dragInitialSelectionState == nil {
                    let isCurrentlySelected = selectedItems.contains(id)
                    dragInitialSelectionState = !isCurrentlySelected
                }
                
                // Only process if we haven't processed this item in this gesture yet
                if !draggedItems.contains(id) {
                    draggedItems.insert(id)
                    
                    if let targetState = dragInitialSelectionState {
                        if targetState {
                            selectedItems.insert(id)
                        } else {
                            selectedItems.remove(id)
                        }
                        
                        // Haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }
                }
                break // Found the item under finger, stop checking others
            }
        }
    }
    
    private func endDragSelection() {
        isDraggingSelection = false
        draggedItems.removeAll()
        dragInitialSelectionState = nil
    }
    
    private func reprocessCutout(_ item: CutoutItem) {
        // 1. Check if linked clothing exists and has images
        guard let clothingID = item.linkedClothingID,
              let clothing = clothingMap[clothingID],
              let firstImagePath = clothing.imagePaths.first else {
            alertMessage = "找不到关联的原图，无法重新抠图。\n(仅支持通过关联服饰创建的抠图)"
            showAlert = true
            return
        }
        
        // 2. Load original image
        processingItem = item.id
        Task {
            // Use ImageManager to load the original image
            // Note: clothing.imagePaths stores filenames
            if let originalImage = ImageManager.shared.loadImage(fileName: firstImagePath) {
                do {
                    try await CutoutService.shared.reprocessItem(item: item, with: originalImage, context: modelContext)
                    // Success feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                } catch {
                    print("Reprocess failed: \(error)")
                    alertMessage = "重新抠图失败，请稍后重试。"
                    showAlert = true
                }
            } else {
                alertMessage = "原图文件已丢失。"
                showAlert = true
            }
            
            processingItem = nil
        }
    }
    
    private func deleteCutout(_ item: CutoutItem) {
        // Capture the image path before deleting the item
        let imagePath = item.imagePath
        
        // 2. Immediately delete from UI/Context with animation
        withAnimation {
            modelContext.delete(item)
        }
        
        // 3. Handle resource cleanup and persistence synchronously on MainActor
        // Decrement ref count / delete image file (file IO is backgrounded internally in ImageManager)
        ImageManager.shared.deleteImage(fileName: imagePath, context: modelContext)
        
        // Save context with error handling
        do {
            try modelContext.save()
        } catch {
            // If save fails, show error alert
            print("Delete failed: \(error)")
            showErrorAlert = true
        }
    }
    
    var addButton: some View {
        Button(action: onAddPhoto) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                Text("添加")
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
            .frame(width: 72, height: 72)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
        }
    }
    
    private var toastView: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            Text(toastMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.8))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
        .padding(.bottom, 60) // Lift up a bit
    }
}

struct CutoutThumbnail: View {
    let imagePath: String
    var category: String? = nil
    
    @State private var image: UIImage?
    
    @Environment(\.displayScale) var displayScale
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .padding(4)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                        .overlay(alignment: .bottomLeading) {
                            if let category = category {
                                Text(category)
                                    .font(.system(size: 8))
                                    .padding(2)
                                    .background(Color.black.opacity(0.5))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                                    .padding(4)
                            }
                        }
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .frame(width: 72, height: 72)
                }
            }
            .task {
                if image == nil {
                    // Request downsampled image (72pt * scale)
                    let targetSize = CGSize(width: 72 * displayScale, height: 72 * displayScale)
                    image = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: targetSize)
                }
            }
        }
    }
}

struct CategoryChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(.caption)
            .fontWeight(isSelected ? .semibold : .regular)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.pink : Color(uiColor: .secondarySystemBackground))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

struct ReclassifyView: View {
    let item: CutoutItem
    let categories: [String]
    let onConfirm: (String) -> Void
    
    @State private var selectedCategory: String
    
    init(item: CutoutItem, categories: [String], onConfirm: @escaping (String) -> Void) {
        self.item = item
        self.categories = categories
        self.onConfirm = onConfirm
        _selectedCategory = State(initialValue: item.category)
    }
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("选择分类", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("当前分类: \(item.category)")
                }
            }
            .navigationTitle("修改分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        onConfirm(selectedCategory)
                    }
                }
            }
        }
    }
}

struct BatchReclassifyView: View {
    let categories: [String]
    let onConfirm: (String) -> Void
    
    @State private var selectedCategory: String
    @Environment(\.dismiss) var dismiss
    
    init(categories: [String], onConfirm: @escaping (String) -> Void) {
        self.categories = categories
        self.onConfirm = onConfirm
        _selectedCategory = State(initialValue: categories.first ?? "未分类")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Picker("选择分类", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(.inline)
            }
            .navigationTitle("批量修改分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        onConfirm(selectedCategory)
                    }
                }
            }
        }
    }
}

struct ItemFrameKey: PreferenceKey {
    typealias Value = [UUID: CGRect]
    static var defaultValue: [UUID: CGRect] = [:]
    
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
