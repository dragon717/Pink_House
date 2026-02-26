//
//  PerlerBeadPatternListView.swift
//  ItemManager
//
//  拼豆/像素画列表视图
//

import SwiftUI
import SwiftData
import PhotosUI
import Combine

struct PerlerBeadPatternListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    
    // 查询
    @Query(filter: #Predicate<PerlerBeadPattern> { $0.isDeleted == false }, sort: \PerlerBeadPattern.sortIndex)
    private var patterns: [PerlerBeadPattern]
    
    // 视图布局
    @State private var viewLayout: ViewLayout = .grid2
    
    // 搜索
    @State private var searchText = ""
    
    // 选择模式
    @State private var isSelectionMode = false
    @State private var selectedItemIDs: Set<UUID> = []
    
    // 长按菜单状态
    @State private var itemToEdit: PerlerBeadPattern?
    @State private var itemToDelete: PerlerBeadPattern?
    @State private var itemToCopy: PerlerBeadPattern?
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingCopyAlert = false
    @State private var showingRenameAlert = false
    @State private var newName = ""
    
    // 批量删除确认
    @State private var showingBatchDeleteAlert = false
    
    // 导航状态
    @State private var selectedPattern: PerlerBeadPattern?
    @State private var showEditor = false
    @State private var showNewCanvasSheet = false
    @State private var showImagePicker = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var newCanvasModel: PixelCanvasModel?
    @State private var croppedImage: UIImage?
    
    // 从衣橱添加状态
    @State private var showWardrobeSelection = false
    
    enum ViewLayout: String, CaseIterable {
        case grid2 = "两列"
        case grid3 = "三列"
        
        var icon: String {
            switch self {
            case .grid2: return "square.grid.2x2"
            case .grid3: return "square.grid.3x3"
            }
        }
        
        var columns: [GridItem] {
            switch self {
            case .grid2:
                return Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
            case .grid3:
                return Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
            }
        }
    }
    
    var filteredPatterns: [PerlerBeadPattern] {
        if searchText.isEmpty {
            return patterns
        }
        return patterns.filter { pattern in
            pattern.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            mainContent
        }
        .photosPicker(
            isPresented: $showImagePicker,
            selection: $selectedItem,
            matching: .images
        )
        .onChange(of: selectedItem) { _, newItem in
            handleImageSelection(newItem)
        }
    }
    
    // MARK: - 主内容视图
    private var mainContent: some View {
        ZStack {
            LiquidBackground()
                .ignoresSafeArea()
            
            patternGridView
        }
        .navigationTitle("拼豆工坊")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "搜索图案")
        .toolbar { toolbarContent }
        .sheet(item: $selectedImage, onDismiss: handleCropPreviewDismiss) { image in
            ImageCropPreviewView(
                sourceImage: image,
                isPresented: .constant(true),
                onConfirm: handleCropConfirm(croppedImage:resolution:paletteSize:style:)
            )
        }
        .sheet(isPresented: $showNewCanvasSheet) {
            newCanvasSheet
        }
        .navigationDestination(isPresented: $showEditor) {
            editorDestination
        }

        .sheet(isPresented: $showingEditSheet) {
            editNameSheet
        }
        .sheet(isPresented: $showWardrobeSelection) {
            WardrobeSelectionSheet { clothing in
                handleWardrobeSelection(clothing)
            }
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            deleteAlertActions
        } message: {
            deleteAlertMessage
        }
        .alert("确认复制", isPresented: $showingCopyAlert) {
            copyAlertActions
        } message: {
            copyAlertMessage
        }
        .alert("确认删除", isPresented: $showingBatchDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                batchDelete()
            }
        } message: {
            Text("确定要删除选中的 \(selectedItemIDs.count) 个图案吗？删除后可以在回收站中恢复。")
        }
        .safeAreaInset(edge: .bottom) {
            selectionModeToolbar
        }
    }
    
    // MARK: - 图案网格视图
    private var patternGridView: some View {
        ScrollView {
            if filteredPatterns.isEmpty {
                emptyStateView
            } else {
                patternGrid 
            }
        }
    }
    
    private var patternGrid: some View {
        LazyVGrid(columns: viewLayout.columns, spacing: viewLayout == .grid2 ? 16 : 12) {
            ForEach(filteredPatterns) { pattern in
                patternCell(for: pattern)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 100)
    }
    
    private func patternCell(for pattern: PerlerBeadPattern) -> some View {
        Group {
            if isSelectionMode {
                selectionModeCell(for: pattern)
            } else {
                normalModeCell(for: pattern)
            }
        }
    }
    
    private func selectionModeCell(for pattern: PerlerBeadPattern) -> some View {
        PatternCard(pattern: pattern)
            .overlay(
                SelectionOverlay(isSelected: selectedItemIDs.contains(pattern.id))
            )
            .onTapGesture {
                toggleSelection(pattern.id)
            }
    }
    
    private func normalModeCell(for pattern: PerlerBeadPattern) -> some View {
        PatternCard(pattern: pattern)
            .onTapGesture {
                selectedPattern = pattern
                showEditor = true
            }
            .contextMenu {
                patternContextMenu(for: pattern)
            }
    }
    
    private func patternContextMenu(for pattern: PerlerBeadPattern) -> some View {
        Group {
            Button {
                isSelectionMode = true
                selectedItemIDs.insert(pattern.id)
            } label: {
                Label("选择", systemImage: "checkmark.circle")
            }
            
            Button {
                selectedPattern = pattern
                showEditor = true
            } label: {
                Label("查看详情", systemImage: "info.circle")
            }
            
            Divider()
            
            Button {
                itemToEdit = pattern
                newName = pattern.name
                showingEditSheet = true
            } label: {
                Label("编辑名称", systemImage: "pencil")
            }
            
            Button {
                itemToCopy = pattern
                showingCopyAlert = true
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            
            Button(role: .destructive) {
                itemToDelete = pattern
                showingDeleteAlert = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
    
    // MARK: - 工具栏
    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigationBarLeading) {
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    layoutMenu
                    trailingToolbarItem
                }
            }
        }
    }
    
    private var layoutMenu: some View {
        Group {
            if !isSelectionMode {
                Menu {
                    ForEach(ViewLayout.allCases, id: \.self) { layout in
                        Button {
                            withAnimation {
                                viewLayout = layout
                            }
                        } label: {
                            Label(layout.rawValue, systemImage: layout.icon)
                            if viewLayout == layout {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    Image(systemName: viewLayout.icon)
                }
            }
        }
    }
    
    private var trailingToolbarItem: some View {
        Group {
            if isSelectionMode {
                Button("完成") {
                    withAnimation {
                        isSelectionMode = false
                        selectedItemIDs.removeAll()
                    }
                }
            } else {
                addMenu
            }
        }
    }
    
    private var addMenu: some View {
        Menu {
            Button {
                showImagePicker = true
            } label: {
                Label("图片转拼豆/像素画", systemImage: "photo")
            }
            
            Button {
                showWardrobeSelection = true
            } label: {
                Label("从衣橱添加", systemImage: "hanger")
            }
            
            Button {
                showNewCanvasSheet = true
            } label: {
                Label("自由绘制", systemImage: "pencil")
            }
            
            Divider()
            
            Button {
                // 手动触发删除同步
                DeleteTracker.shared.applyAllDeletes(context: modelContext)
            } label: {
                Label("同步删除状态", systemImage: "arrow.triangle.2.circlepath")
            }
        } label: {
            Image(systemName: "plus")
        }
    }
    
    // MARK: - Sheet 内容
    @ViewBuilder
    private var cropPreviewSheet: some View {
        if let image = selectedImage {
            ImageCropPreviewView(
                sourceImage: image,
                isPresented: .constant(true),
                onConfirm: handleCropConfirm(croppedImage:resolution:paletteSize:style:)
            )
        } else {
            ProgressView("加载中...")
        }
    }
    
    private var newCanvasSheet: some View {
        NewCanvasConfigSheet { resolution, paletteSize, style in
            let canvasModel = PixelCanvasModel(
                resolution: resolution,
                paletteSize: paletteSize,
                canvasStyle: style
            )
            newCanvasModel = canvasModel
            // 清除之前选中的图案，确保显示新画布
            selectedPattern = nil
            // 清除裁剪图片，避免与自由绘制混淆
            croppedImage = nil
            showEditor = true
        }
    }
    
    private var editorDestination: some View {
        Group {
            if let pattern = selectedPattern {
                PerlerBeadsEditorView(
                    existingPattern: pattern,
                    onSave: { _ in }
                )
            } else if let canvasModel = newCanvasModel {
                PerlerBeadsEditorView(
                    sourceImage: croppedImage,
                    initialCanvasModel: canvasModel,
                    onSave: { _ in }
                )
            } else {
                PerlerBeadsEditorView()
            }
        }
    }
    
    private var editNameSheet: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("输入新名称", text: $newName)
                }
            }
            .navigationTitle("编辑名称")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showingEditSheet = false
                        itemToEdit = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let item = itemToEdit {
                            renamePattern(item, newName: newName)
                        }
                        showingEditSheet = false
                    }
                    .disabled(newName.isEmpty)
                }
            }
        }
    }
    
    // MARK: - Alert 内容
    private var deleteAlertActions: some View {
        Group {
            Button("取消", role: .cancel) {
                itemToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let item = itemToDelete {
                    deletePattern(item)
                }
            }
        }
    }
    
    private var deleteAlertMessage: some View {
        Group {
            if let item = itemToDelete {
                Text("确定要删除「\(item.name)」吗？删除后可以在回收站中恢复。")
            }
        }
    }
    
    private var copyAlertActions: some View {
        Group {
            Button("取消", role: .cancel) {
                itemToCopy = nil
            }
            Button("复制") {
                if let item = itemToCopy {
                    copyPattern(item)
                }
            }
        }
    }
    
    private var copyAlertMessage: some View {
        Group {
            if let item = itemToCopy {
                Text("确定要复制「\(item.name)」吗？")
            }
        }
    }
    
    // MARK: - 选择模式工具栏
    private var selectionModeToolbar: some View {
        Group {
            if isSelectionMode {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Button(role: .destructive) {
                            showingBatchDeleteAlert = true
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
                            toggleSelectAll()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: isAllSelected ? "xmark.circle" : "checkmark.circle")
                                Text(isAllSelected ? "取消全选" : "全选")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding()
                    .background(.regularMaterial)
                }
            }
        }
    }
    
    // MARK: - 事件处理
    private func handleImageSelection(_ newItem: PhotosPickerItem?) {
        Task {
            do {
                if let newItem = newItem {
                    print("[PerlerBeads] Loading selected image...")
                    // 重置之前裁剪的图片，避免使用缓存
                    await MainActor.run {
                        croppedImage = nil
                    }
                    // 使用 Data 加载，然后转换为 UIImage
                    if let data = try await newItem.loadTransferable(type: Data.self) {
                        if let image = UIImage(data: data) {
                            await MainActor.run {
                                print("[PerlerBeads] Image loaded successfully, showing crop preview")
                                // 设置 selectedImage 会自动触发 sheet(item:) 显示
                                selectedImage = image
                            }
                        } else {
                            print("[PerlerBeads] Failed to create UIImage from data")
                        }
                    } else {
                        print("[PerlerBeads] Failed to load image data")
                    }
                } else {
                    print("[PerlerBeads] No item selected")
                }
            } catch {
                print("[PerlerBeads] Error loading image: \(error)")
            }
        }
    }
    
    private func handleCropPreviewDismiss() {
        selectedItem = nil
        // selectedImage 已经被 sheet(item:) 自动设为 nil
    }
    
    private func handleCropConfirm(croppedImage: UIImage, resolution: PerlerBeadsConfig.Resolution, paletteSize: PerlerBeadsConfig.PaletteSize, style: PerlerBeadsConfig.CanvasStyle) {
        let canvasModel = PixelCanvasModel(
            resolution: resolution,
            paletteSize: paletteSize,
            canvasStyle: style
        )
        self.croppedImage = croppedImage
        newCanvasModel = canvasModel
        // 清除之前选中的图案，确保显示新导入的图片
        selectedPattern = nil
        showEditor = true
        // sheet(item:) 会在视图关闭时自动将 selectedImage 设为 nil
        selectedItem = nil
    }
    
    // MARK: - 从衣橱选择处理
    private func handleWardrobeSelection(_ clothing: Clothing) {
        guard let firstImagePath = clothing.imagePaths.first else {
            print("[PerlerBeads] Selected clothing has no images")
            return
        }
        
        print("[PerlerBeads] Loading image from wardrobe: \(clothing.name), path: \(firstImagePath)")
        
        // 重置之前裁剪的图片，避免使用缓存
        croppedImage = nil
        // 清除之前选中的图案，确保显示新导入的图片
        selectedPattern = nil
        
        Task {
            // 加载原图，不使用缩略图
            let image: UIImage?
            
            // 先尝试从缓存获取原图
            if let cachedImage = ImageManager.shared.cachedImage(fileName: firstImagePath, targetSize: nil) {
                print("[PerlerBeads] Using cached original image")
                image = cachedImage
            } else {
                // 异步加载原图
                image = await ImageManager.shared.loadImageAsync(fileName: firstImagePath, targetSize: nil)
            }
            
            await MainActor.run {
                if let image = image {
                    print("[PerlerBeads] Image loaded from wardrobe: \(image.size), showing crop preview")
                    self.selectedImage = image
                } else {
                    print("[PerlerBeads] Failed to load image from wardrobe")
                }
            }
        }
    }
    
    // MARK: - 辅助方法
    
    private var isAllSelected: Bool {
        let displayedIDs = Set(filteredPatterns.map { $0.id })
        guard !displayedIDs.isEmpty else { return false }
        return selectedItemIDs.isSuperset(of: displayedIDs)
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }
    
    private func toggleSelectAll() {
        let displayedIDs = Set(filteredPatterns.map { $0.id })
        if selectedItemIDs.isSuperset(of: displayedIDs) {
            selectedItemIDs.subtract(displayedIDs)
        } else {
            selectedItemIDs.formUnion(displayedIDs)
        }
    }
    
    private func renamePattern(_ pattern: PerlerBeadPattern, newName: String) {
        pattern.name = newName
        pattern.updatedAt = Date()
        pattern.lastModified = Date()
        try? modelContext.save()
        itemToEdit = nil
    }
    
    private func deletePattern(_ pattern: PerlerBeadPattern) {
        pattern.isDeleted = true
        pattern.deletedAt = Date()
        pattern.lastModified = Date()
        try? modelContext.save()
        
        // 记录删除操作，防止iCloud同步覆盖
        DeleteTracker.shared.recordDeletedPerlerPattern(id: pattern.id)
        
        itemToDelete = nil
    }
    
    private func copyPattern(_ pattern: PerlerBeadPattern) {
        let newPattern = PerlerBeadPattern(
            name: "\(pattern.name) 副本",
            patternType: pattern.typeEnum,
            resolution: pattern.resolutionEnum,
            paletteSize: pattern.paletteSizeEnum,
            canvasStyle: pattern.canvasStyleEnum,
            pixelData: pattern.pixelData,
            paletteSortOrder: pattern.paletteSortOrderEnum,
            thumbnailPath: pattern.thumbnailPath
        )
        modelContext.insert(newPattern)
        try? modelContext.save()
        itemToCopy = nil
    }
    
    private func batchDelete() {
        let itemsToDelete = patterns.filter { selectedItemIDs.contains($0.id) }
        for item in itemsToDelete {
            item.isDeleted = true
            item.deletedAt = Date()
            item.lastModified = Date()
            
            // 记录删除操作，防止iCloud同步覆盖
            DeleteTracker.shared.recordDeletedPerlerPattern(id: item.id)
        }
        try? modelContext.save()
        isSelectionMode = false
        selectedItemIDs.removeAll()
    }
    
    // MARK: - 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "circle.grid.2x2")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("还没有拼豆/像素画")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text("点击右上角 + 号新增拼豆/像素画")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .padding(.horizontal, 40)
    }
}

// MARK: - 图案卡片
struct PatternCard: View {
    let pattern: PerlerBeadPattern
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 缩略图 - 使用矢量渲染
            PatternVectorPreview(pattern: pattern)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            
            // 信息
            VStack(alignment: .leading, spacing: 2) {
                Text(pattern.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                
                HStack {
                    Label("\(pattern.totalPixels)", systemImage: "circle.grid.2x2")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(pattern.typeEnum.rawValue)
                        .font(.caption2)
                        .foregroundColor(.pink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.pink.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - 矢量渲染的拼豆图案预览
struct PatternVectorPreview: View {
    let pattern: PerlerBeadPattern
    
    // 缓存调色板，避免重复计算
    private var palette: [BeadColor] {
        BeadColorPalette.colors(for: pattern.paletteSizeEnum, sortedBy: pattern.paletteSortOrderEnum)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let resolution = pattern.resolution
            let pixelSize = size / CGFloat(resolution)
            
            Canvas { context, canvasSize in
                // 绘制白色背景
                context.fill(
                    Path(CGRect(origin: .zero, size: canvasSize)),
                    with: .color(.white)
                )
                
                // 矢量渲染每个像素
                for y in 0..<resolution {
                    for x in 0..<resolution {
                        let index = y * resolution + x
                        guard index < pattern.pixelData.count else { continue }
                        
                        let colorIndex = pattern.pixelData[index]
                        guard colorIndex >= 0 && colorIndex < palette.count else { continue }
                        
                        let beadColor = palette[colorIndex]
                        let rect = CGRect(
                            x: CGFloat(x) * pixelSize,
                            y: CGFloat(y) * pixelSize,
                            width: pixelSize,
                            height: pixelSize
                        )
                        
                        if pattern.canvasStyleEnum == .pixelArt {
                            // 像素画模式：填充方形
                            context.fill(Path(rect), with: .color(beadColor.color))
                        } else {
                            // 拼豆模式：绘制圆形
                            let drawSize = pixelSize * 0.85
                            let beadRect = CGRect(
                                x: rect.midX - drawSize / 2,
                                y: rect.midY - drawSize / 2,
                                width: drawSize,
                                height: drawSize
                            )
                            context.fill(
                                Path(ellipseIn: beadRect),
                                with: .color(beadColor.color)
                            )
                        }
                    }
                }
            }
            .frame(width: size, height: size)
        }
        .background(Color.white)
    }
}

// MARK: - 选择覆盖层
struct SelectionOverlay: View {
    let isSelected: Bool
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? .pink : .white)
                .background(Circle().fill(isSelected ? .white : .black.opacity(0.3)))
                .shadow(radius: 2)
                .padding(8)
        }
    }
}

// MARK: - 预览
#Preview {
    PerlerBeadPatternListView()
}
