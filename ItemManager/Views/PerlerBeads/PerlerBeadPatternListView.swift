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
    
    // 导航状态
    @State private var selectedPattern: PerlerBeadPattern?
    @State private var showEditor = false
    @State private var showNewCanvasSheet = false
    @State private var showImagePicker = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showCropPreview = false
    @State private var newCanvasModel: PixelCanvasModel?
    @State private var croppedImage: UIImage?
    
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
            ZStack {
                LiquidBackground()
                    .ignoresSafeArea()

                ScrollView {
                    if filteredPatterns.isEmpty {
                        emptyStateView
                    } else {
                        LazyVGrid(columns: viewLayout.columns, spacing: viewLayout == .grid2 ? 16 : 12) {
                            ForEach(filteredPatterns) { pattern in
                                if isSelectionMode {
                                    // 选择模式
                                    PatternCard(pattern: pattern)
                                        .overlay(
                                            SelectionOverlay(isSelected: selectedItemIDs.contains(pattern.id))
                                        )
                                        .onTapGesture {
                                            toggleSelection(pattern.id)
                                        }
                                } else {
                                    // 正常模式 - 支持长按菜单
                                    PatternCard(pattern: pattern)
                                        .onTapGesture {
                                            selectedPattern = pattern
                                            showEditor = true
                                        }
                                        .contextMenu {
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
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("拼豆工坊")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "搜索图案")
            .toolbar {
                // 左侧：视图切换
                ToolbarItem(placement: .navigationBarLeading) {
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

                // 右侧：添加按钮或选择模式完成按钮
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSelectionMode {
                        Button("完成") {
                            withAnimation {
                                isSelectionMode = false
                                selectedItemIDs.removeAll()
                            }
                        }
                    } else {
                        Menu {
                            Button {
                                showImagePicker = true
                            } label: {
                                Label("图片转拼豆/像素画", systemImage: "photo")
                            }

                            Button {
                                showNewCanvasSheet = true
                            } label: {
                                Label("自由绘制", systemImage: "pencil")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            // 图片裁剪预览 - 使用 sheet 显示
            .sheet(isPresented: $showCropPreview, onDismiss: {
                selectedItem = nil
                selectedImage = nil
            }) {
                Group {
                    if let image = selectedImage {
                        ImageCropPreviewView(
                            sourceImage: image,
                            isPresented: $showCropPreview,
                            onConfirm: { resolution, paletteSize, style in
                                let canvasModel = PixelCanvasModel(
                                    resolution: resolution,
                                    paletteSize: paletteSize,
                                    canvasStyle: style
                                )
                                newCanvasModel = canvasModel
                                showEditor = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    selectedItem = nil
                                    selectedImage = nil
                                }
                            }
                        )
                    } else {
                        ProgressView("加载中...")
                    }
                }
            }
            // 新建画布配置
            .sheet(isPresented: $showNewCanvasSheet) {
                NewCanvasConfigSheet { resolution, paletteSize, style in
                    let canvasModel = PixelCanvasModel(
                        resolution: resolution,
                        paletteSize: paletteSize,
                        canvasStyle: style
                    )
                    newCanvasModel = canvasModel
                    showEditor = true
                }
            }
            // 编辑器
            .navigationDestination(isPresented: $showEditor) {
                if let pattern = selectedPattern {
                    PerlerBeadsEditorView(
                        existingPattern: pattern,
                        onSave: { _ in
                            // 保存后刷新
                        }
                    )
                } else if let canvasModel = newCanvasModel {
                    PerlerBeadsEditorView(
                        sourceImage: croppedImage,
                        initialCanvasModel: canvasModel,
                        onSave: { _ in
                            // 保存后刷新
                        }
                    )
                } else {
                    PerlerBeadsEditorView()
                }
            }
            // 接收裁剪后的图片
            .onReceive(NotificationCenter.default.publisher(for: .imageCropCompleted)) { notification in
                if let image = notification.userInfo?["croppedImage"] as? UIImage {
                    croppedImage = image
                }
            }
            // 编辑名称 Sheet
            .sheet(isPresented: $showingEditSheet) {
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
            // 删除确认
            .alert("确认删除", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) {
                    itemToDelete = nil
                }
                Button("删除", role: .destructive) {
                    if let item = itemToDelete {
                        deletePattern(item)
                    }
                }
            } message: {
                if let item = itemToDelete {
                    Text("确定要删除「\(item.name)」吗？删除后可以在回收站中恢复。")
                }
            }
            // 复制确认
            .alert("确认复制", isPresented: $showingCopyAlert) {
                Button("取消", role: .cancel) {
                    itemToCopy = nil
                }
                Button("复制") {
                    if let item = itemToCopy {
                        copyPattern(item)
                    }
                }
            } message: {
                if let item = itemToCopy {
                    Text("确定要复制「\(item.name)」吗？")
                }
            }
            // 选择模式底部工具栏
            .safeAreaInset(edge: .bottom) {
                if isSelectionMode {
                    VStack(spacing: 0) {
                        Divider()
                        HStack {
                            Button(role: .destructive) {
                                batchDelete()
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
        // 图片选择器 - 放在 NavigationStack 外部
        .photosPicker(
            isPresented: $showImagePicker,
            selection: $selectedItem,
            matching: .images
        )
        .onChange(of: selectedItem) { _, newItem in
            Task {
                do {
                    if let newItem = newItem {
                        print("[PerlerBeads] Loading selected image...")
                        if let data = try await newItem.loadTransferable(type: Data.self) {
                            if let image = UIImage(data: data) {
                                await MainActor.run {
                                    print("[PerlerBeads] Image loaded successfully, showing crop preview")
                                    selectedImage = image
                                    showCropPreview = true
                                }
                            } else {
                                print("[PerlerBeads] Failed to create UIImage from data")
                            }
                        } else {
                            print("[PerlerBeads] Failed to load transferable data")
                        }
                    } else {
                        print("[PerlerBeads] No item selected")
                    }
                } catch {
                    print("[PerlerBeads] Error loading image: \(error)")
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
            // 缩略图
            ZStack {
                if let thumbnailPath = pattern.thumbnailPath,
                   let uiImage = ImageManager.shared.loadImage(fileName: thumbnailPath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .background(Color.white)
                } else {
                    // 占位图
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: pattern.typeEnum.icon)
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        )
                }
            }
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
