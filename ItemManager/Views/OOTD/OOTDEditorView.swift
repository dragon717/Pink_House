
import SwiftUI
import SwiftData
import PhotosUI

struct OOTDEditorView: View {
    @Bindable var outfit: Outfit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // 获取同一本书的所有书页（用于翻页导航）
    @Query(filter: #Predicate<Outfit> { $0.isDeleted == false }, sort: \Outfit.sortIndex) private var allPages: [Outfit]
    
    // 页面切换回调
    var onPageChange: ((Outfit) -> Void)?
    
    // 初始状态配置（用于魔法贴纸模式）
    var initialToolbarVisible: Bool = true
    var initialStickerLibraryVisible: Bool = false
    
    // States copied from OOTDView
    @State private var isListExpanded = false
    @State private var isProcessing = false
    @State private var processingMessage = ""
    @State private var showingActionSheet = false
    @State private var showingCamera = false
    @State private var cameraImage: UIImage?
    @State private var shouldCutoutCameraImage = false
    @State private var isImagePickerPresented = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingLimitAlert = false
    @State private var showingSaveSuccessAlert = false
    @State private var showingSaveToClothingSheet = false
    @State private var showingRenameAlert = false
    @State private var newName = ""
    @State private var showingDeleteAlert = false
    @State private var showingMultiPhotoPicker = false
    @State private var showingShareSheet = false
    
    // 批量处理相关状态
    @State private var showingBatchConfirmation = false
    @State private var showingRepairConfirmation = false
    @State private var showingBatchReplaceSheet = false
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) private var allClothing: [Clothing]
    
    // 编辑底图相关状态
    @State private var showingBackgroundPicker = false
    @State private var selectedBackgroundItem: PhotosPickerItem?
    @State private var tempBackgroundImage: UIImage?
    @State private var showingBackgroundCropper = false
    @State private var showingBackgroundSelectionSheet = false
    
    // 工具栏和贴纸库显示状态
    @State private var isToolbarVisible: Bool
    @State private var isStickerLibraryVisible: Bool
    @State private var isAvatarMotionEnabled = false
    
    // 初始化时设置默认值
    init(outfit: Outfit, onPageChange: ((Outfit) -> Void)? = nil, initialToolbarVisible: Bool = true, initialStickerLibraryVisible: Bool = false) {
        self.outfit = outfit
        self.onPageChange = onPageChange
        self.initialToolbarVisible = initialToolbarVisible
        self.initialStickerLibraryVisible = initialStickerLibraryVisible
        // 初始化 State 值
        _isToolbarVisible = State(initialValue: initialToolbarVisible)
        _isStickerLibraryVisible = State(initialValue: initialStickerLibraryVisible)
    }
    
    // 当前书页索引
    private var currentPageIndex: Int {
        bookPages.firstIndex { $0.id == outfit.id } ?? 0
    }
    
    // 当前书的所有书页
    private var bookPages: [Outfit] {
        allPages.filter { $0.book?.id == outfit.book?.id }
    }
    
    // 是否有上一页
    private var hasPreviousPage: Bool {
        currentPageIndex > 0
    }
    
    // 是否有下一页
    private var hasNextPage: Bool {
        currentPageIndex < bookPages.count - 1
    }
    
    // 上一页
    private var previousPage: Outfit? {
        guard hasPreviousPage else { return nil }
        return bookPages[currentPageIndex - 1]
    }
    
    // 下一页
    private var nextPage: Outfit? {
        guard hasNextPage else { return nil }
        return bookPages[currentPageIndex + 1]
    }

    private var canAnimateAvatar: Bool {
        outfit.canvasType == OOTDCanvasType.mannequin
        && OOTDMannequinBackground.resolve(outfit.mannequinAssetID).avatarCharacterID == .girlV1
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 主内容区域
                mainContentArea(geometry: geometry)
            }
        }
        .navigationTitle(outfit.note.isEmpty ? "编辑书页" : outfit.note)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 左侧：显示/隐藏工具栏按钮
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isToolbarVisible.toggle()
                    }
                } label: {
                    Image(systemName: isToolbarVisible ? "sidebar.leading" : "sidebar.trailing")
                        .font(.system(size: 16, weight: .medium))
                }
            }
            
            // 右侧：分享按钮和更多操作菜单
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    // 分享按钮
                    Button {
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    
                    // 更多操作菜单
                    Menu {
                       
                        
                     
                        
                        Button {
                            showingBackgroundSelectionSheet = true
                        } label: {
                            Label("更换底图", systemImage: "photo")
                        }

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isAvatarMotionEnabled.toggle()
                            }
                        } label: {
                            Label(
                                isAvatarMotionEnabled && canAnimateAvatar ? "停止动作" : "让它能动起来",
                                systemImage: isAvatarMotionEnabled && canAnimateAvatar ? "pause.circle" : "play.circle"
                            )
                        }
                        .disabled(!canAnimateAvatar)
                        
                        Button {
                            showingSaveToClothingSheet = true
                        } label: {
                            Label("保存为裙装主图", systemImage: "photo.badge.arrow.down")
                        }
                        
                        Button {
                            newName = outfit.note
                            showingRenameAlert = true
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                          
                        Divider()

                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }

                        Divider()
                         // 批量处理菜单组
                        Button {
                            showingBatchConfirmation = true
                        } label: {
                            Label("批量处理小裙装", systemImage: "wand.and.stars")
                        }
                        
                        Button {
                            showingRepairConfirmation = true
                        } label: {
                            Label("修复数据", systemImage: "hammer")
                        }
                        
                        Button {
                            showingBatchReplaceSheet = true
                        } label: {
                            Label("一键替换主图", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        // ... Pickers and Alerts ...
        .confirmationDialog("选择图片来源", isPresented: $showingActionSheet) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("拍照并抠图") {
                    shouldCutoutCameraImage = true
                    showingCamera = true
                }
            }
            Button("从图库多选") {
                showingMultiPhotoPicker = true
            }
            Button("取消", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(image: $cameraImage)
                .ignoresSafeArea()
        }
        .onChange(of: cameraImage) { _, newImage in
            if let image = newImage {
                processCameraImage(image, shouldCutout: shouldCutoutCameraImage)
            }
        }
        .sheet(isPresented: $showingMultiPhotoPicker) {
            MultiPhotoPickerView { cutouts in
                // 批量添加抠图到画布
                batchAddCutouts(cutouts)
            }
        }
        .sheet(isPresented: $showingSaveToClothingSheet) {
            ClothingPickerView { selectedClothing in
                // saveCanvasToClothing(clothing: selectedClothing)
                // Logic needs to be ported or accessed via static/shared helper
                // For now, let's just log or implement simple version
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareCardSheet(
                shareType: .outfit(outfit),
                onDismiss: { showingShareSheet = false }
            )
        }
        .alert("重命名", isPresented: $showingRenameAlert) {
            TextField("名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("确定") {
                outfit.note = newName
                try? modelContext.save()
            }
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                outfit.isDeleted = true
                outfit.deletedAt = Date()
                outfit.lastModified = Date()
                do {
                    try modelContext.save()

                    // 记录删除到 DeleteTracker，防止iCloud同步覆盖
                    DeleteTracker.shared.recordDeletedOutfit(id: outfit.id)
                } catch {
                    print("OOTDEditorView: Failed to save deletion: \(error)")
                }
                dismiss()
            }
        } message: {
            Text("确定要删除这张书页吗？")
        }
        // MARK: - 编辑底图相关 Sheets
        .sheet(isPresented: $showingBackgroundSelectionSheet) {
            OOTDBackgroundSelectionSheet(
                currentCanvasType: outfit.canvasType,
                currentMannequinAssetID: outfit.mannequinAssetID,
                onSelectBlank: applyBlankBackground,
                onSelectMannequin: applyMannequinBackground,
                onSelectCustomImage: {
                    showingBackgroundPicker = true
                }
            )
        }
        .photosPicker(isPresented: $showingBackgroundPicker, selection: $selectedBackgroundItem, matching: .images)
        .onChange(of: selectedBackgroundItem) { _, newItem in
            if let newItem {
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            tempBackgroundImage = image
                            showingBackgroundCropper = true
                            selectedBackgroundItem = nil
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingBackgroundCropper) {
            backgroundCropperSheet
        }
        // MARK: - 批量处理相关 Alerts & Sheets
        .alert("批量处理", isPresented: $showingBatchConfirmation) {
            Button("开始扫描", role: .destructive) {
                processWardrobeSkirts()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将扫描衣橱中所有裙装并尝试生成抠图。这可能需要一些时间。")
        }
        .alert("修复数据", isPresented: $showingRepairConfirmation) {
            Button("开始深度修复") {
                repairMissingCutouts()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将扫描所有搭配，尝试通过哈希匹配、关联服饰匹配等方式，找回丢失的图片引用。")
        }
        .sheet(isPresented: $showingBatchReplaceSheet) {
            BatchReplaceCutoutView()
        }
    }
    
    // MARK: - 底图裁剪 Sheet
    private var backgroundCropperSheet: some View {
        Group {
            if let image = tempBackgroundImage {
                ImageCropView(
                    image: image,
                    aspectRatio: 0.75, // 3:4 比例
                    targetWidth: 1080
                ) { croppedImage in
                    updateBackgroundImage(croppedImage)
                    showingBackgroundCropper = false
                    tempBackgroundImage = nil
                } onCancel: {
                    showingBackgroundCropper = false
                    tempBackgroundImage = nil
                }
            }
        }
    }
    
    // MARK: - 更新底图
    private func updateBackgroundImage(_ image: UIImage) {
        deleteCurrentBackgroundFiles()

        // 保存新底图
        if let path = ImageManager.shared.saveImage(image, context: modelContext) {
            isAvatarMotionEnabled = false
            outfit.backgroundImagePath = path
            outfit.canvasType = OOTDCanvasType.custom
            outfit.mannequinAssetID = nil
            outfit.snapshotPath = nil
            outfit.lastModified = Date()
            try? modelContext.save()

            // 统一通过 OOTDPreviewView 生成快照，确保贴纸、图库底图、人台底图一致。
            saveSnapshot()
        }
    }
    
    // MARK: - 更换为空白底图
    private func applyBlankBackground() {
        deleteCurrentBackgroundFiles()

        outfit.backgroundImagePath = nil
        outfit.canvasType = OOTDCanvasType.blank
        outfit.mannequinAssetID = nil
        isAvatarMotionEnabled = false
        outfit.snapshotPath = nil
        outfit.lastModified = Date()
        try? modelContext.save()
        
        // 重新生成快照
        saveSnapshot()
    }

    // MARK: - 更换为静态人台底图
    private func applyMannequinBackground(_ mannequin: OOTDMannequinBackground) {
        deleteCurrentBackgroundFiles()

        outfit.backgroundImagePath = nil
        outfit.canvasType = OOTDCanvasType.mannequin
        outfit.mannequinAssetID = mannequin.id
        if mannequin.avatarCharacterID != .girlV1 {
            isAvatarMotionEnabled = false
        }
        outfit.snapshotPath = nil
        outfit.lastModified = Date()
        try? modelContext.save()

        // 重新生成快照
        saveSnapshot()
    }

    private func deleteCurrentBackgroundFiles() {
        let oldBackgroundPath = outfit.backgroundImagePath
        let oldSnapshotPath = outfit.snapshotPath

        if let oldBackgroundPath {
            ImageManager.shared.deleteImage(fileName: oldBackgroundPath, context: modelContext)
        }

        if let oldSnapshotPath,
           oldSnapshotPath != oldBackgroundPath {
            ImageManager.shared.deleteImage(fileName: oldSnapshotPath, context: modelContext)
        }
    }
    
    // MARK: - Helper Methods
    
    private func addToOutfit(_ cutout: CutoutItem) {
        _ = addCutoutsToOutfit([cutout])
    }
    
    private func saveSnapshot() {
        Task { @MainActor in
            // Delay to ensure rendering is ready
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            let renderer = ImageRenderer(content: OOTDPreviewView(outfit: outfit))
            renderer.scale = 0.5 
            
            if let uiImage = renderer.uiImage,
               let path = ImageManager.shared.saveImage(uiImage, context: modelContext) {
                // Delete old snapshot if exists and different
                if let oldPath = outfit.snapshotPath, oldPath != path {
                    ImageManager.shared.deleteImage(fileName: oldPath, context: modelContext)
                }
                outfit.snapshotPath = path
                outfit.lastModified = Date()
                try? modelContext.save()
            }
        }
    }
    
    private func processPickedImage(_ item: PhotosPickerItem) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    Task {
                         if let cutout = try? await CutoutService.shared.processImage(image: image, category: "导入", clothing: nil, context: modelContext) {
                             await MainActor.run {
                                 addToOutfit(cutout)
                             }
                         }
                    }
                }
            }
        }
    }
    
    private func processCameraImage(_ image: UIImage, shouldCutout: Bool) {
        if shouldCutout {
            Task {
                if let cutout = try? await CutoutService.shared.processImage(image: image, category: "拍照", clothing: nil, context: modelContext) {
                     await MainActor.run {
                         addToOutfit(cutout)
                     }
                }
            }
        }
    }
    
    private func batchAddCutouts(_ cutouts: [CutoutItem]) {
        _ = addCutoutsToOutfit(cutouts)
    }

    @discardableResult
    private func addCutoutsToOutfit(_ cutouts: [CutoutItem]) -> Bool {
        guard !cutouts.isEmpty else { return true }

        // 检查是否超过限制
        if (outfit.items?.count ?? 0) + cutouts.count > 20 {
            showingLimitAlert = true
            return false
        }

        if outfit.items == nil {
            outfit.items = []
        }

        let baseIndex = outfit.items?.count ?? 0
        for (index, cutout) in cutouts.enumerated() {
            let offset = Double(index) * 0.05
            let item = OutfitItem(
                cutout: cutout,
                x: min(0.8, 0.5 + offset),
                y: min(0.8, 0.5 + offset),
                rotation: 0,
                scale: 1.0,
                zIndex: baseIndex + index,
                coordinateVersion: 2
            )
            outfit.items?.append(item)
        }

        saveSnapshot()
        return true
    }
    
    // MARK: - 翻页导航
    
    /// 前往上一页
    private func goToPreviousPage() {
        guard let prev = previousPage else { return }
        
        // 先保存当前页快照
        saveSnapshot()
        
        // 渐隐渐出效果切换页面
        withAnimation(.easeInOut(duration: 0.3)) {
            self.onPageChange?(prev)
        }
    }
    
    // MARK: - 主内容区域
    
    @ViewBuilder
    private func mainContentArea(geometry: GeometryProxy) -> some View {
        let isLandscape = geometry.size.width > geometry.size.height
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        // 根据设备类型和屏幕尺寸计算贴纸库宽度
        let sidebarWidth: CGFloat = {
            if isIPad {
                // iPad: 根据展开状态使用不同宽度
                return isListExpanded ? min(380, geometry.size.width * 0.35) : 120
            } else {
                // iPhone 横屏: 更窄的侧边栏
                return isListExpanded ? min(320, geometry.size.width * 0.4) : 90
            }
        }()

        ZStack {
            // 背景
            LiquidBackground(themeSkinWallpaperContext: .journal)
                .ignoresSafeArea()

            if isLandscape {
                // Landscape Layout: HStack (Canvas + Sidebar)
                HStack(spacing: 0) {
                    // Canvas Area with Page Flip Controls in Toolbar
                    OOTDCanvasView(
                        outfit: outfit,
                        isToolbarVisible: $isToolbarVisible,
                        isStickerLibraryVisible: $isStickerLibraryVisible,
                        isLandscape: true,
                        isAvatarMotionEnabled: isAvatarMotionEnabled && canAnimateAvatar,
                        currentPageIndex: currentPageIndex,
                        totalPages: bookPages.count,
                        hasPreviousPage: hasPreviousPage,
                        hasNextPage: hasNextPage,
                        onPreviousPage: { goToPreviousPage() },
                        onNextPage: { goToNextPage() },
                        onCanvasChange: { saveSnapshot() }
                    )
                    .id(outfit.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Right Sidebar (Cutout List) - 贴纸库
                    if isStickerLibraryVisible {
                        let _ = print("[OOTD Editor] 显示贴纸库（横屏）")
                        OOTDCutoutListView(
                            isExpanded: $isListExpanded,
                            isLandscape: true,
                            onSelect: { cutout in addToOutfit(cutout) },
                            onAddPhoto: { showingActionSheet = true },
                            onBatchAdd: { cutouts in
                                addCutoutsToOutfit(cutouts)
                            }
                        )
                        .frame(width: sidebarWidth)
                        .background(Color(uiColor: .systemBackground))
                        .transition(.move(edge: .trailing))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isListExpanded)
                    }
                }
            } else {
                // Portrait Layout: ZStack (Canvas + Bottom Sheet)
                ZStack {
                    OOTDCanvasView(
                        outfit: outfit,
                        isToolbarVisible: $isToolbarVisible,
                        isStickerLibraryVisible: $isStickerLibraryVisible,
                        isLandscape: false,
                        isAvatarMotionEnabled: isAvatarMotionEnabled && canAnimateAvatar,
                        currentPageIndex: currentPageIndex,
                        totalPages: bookPages.count,
                        hasPreviousPage: hasPreviousPage,
                        hasNextPage: hasNextPage,
                        onPreviousPage: { goToPreviousPage() },
                        onNextPage: { goToNextPage() },
                        onCanvasChange: { saveSnapshot() }
                    )
                    .id(outfit.id)

                    // 贴纸库 - 底部弹出
                    if isStickerLibraryVisible {
                        let _ = print("[OOTD Editor] 显示贴纸库（竖屏）")
                        VStack {
                            Spacer()
                            OOTDCutoutListView(
                                isExpanded: $isListExpanded,
                                isLandscape: false,
                                onSelect: { cutout in addToOutfit(cutout) },
                                onAddPhoto: { showingActionSheet = true },
                                onBatchAdd: { cutouts in
                                    addCutoutsToOutfit(cutouts)
                                }
                            )
                            .frame(height: isListExpanded ? geometry.size.height * 0.8 : 200)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isListExpanded)
                        }
                    }
                }
            }
            
            if isProcessing {
                Color.black.opacity(0.4)
                .ignoresSafeArea()
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text(processingMessage)
                        .foregroundColor(.white)
                        .padding(.top)
                }
            }
        }
    }
    
    /// 前往下一页
    private func goToNextPage() {
        guard let next = nextPage else { return }
        
        // 先保存当前页快照
        saveSnapshot()
        
        // 渐隐渐出效果切换页面
        withAnimation(.easeInOut(duration: 0.3)) {
            self.onPageChange?(next)
        }
    }
    
    // MARK: - 批量处理小裙装
    
    private func processWardrobeSkirts() {
        isProcessing = true
        processingMessage = "正在批量处理小裙装..."
        
        Task {
            var count = 0
            let descriptor = FetchDescriptor<CutoutItem>()
            let existingCutouts = (try? modelContext.fetch(descriptor)) ?? []
            let existingPaths = Set(existingCutouts.map { $0.imagePath })

            let itemsToProcess = allClothing.filter { clothing in
                !clothing.imagePaths.isEmpty
            }
            
            let total = itemsToProcess.count
            
            for (index, clothing) in itemsToProcess.enumerated() {
                if index % 5 == 0 {
                    await MainActor.run {
                        processingMessage = "正在处理 \(index + 1)/\(total)..."
                    }
                }
                
                if let firstImagePath = clothing.imagePaths.first,
                   !existingPaths.contains(firstImagePath),
                   let image = ImageManager.shared.loadImage(fileName: firstImagePath) {
                    
                    do {
                        let category = clothing.types.split(separator: ",").first.map(String.init) ?? "未分类"
                        _ = try await CutoutService.shared.processImage(image: image, category: category, clothing: clothing, context: modelContext)
                        count += 1
                    } catch {
                        // Ignore errors
                    }
                }
            }
            
            await MainActor.run {
                isProcessing = false
                processingMessage = ""
            }
        }
    }
    
    // MARK: - 修复数据
    
    private func repairMissingCutouts() {
        isProcessing = true
        processingMessage = "正在深度修复数据..."
        
        Task {
            let report = await OOTDDataRepairService.shared.deepRepair(context: modelContext) { message in
                Task { @MainActor in
                    processingMessage = message
                }
            }

            await MainActor.run {
                processingMessage = report.shortSummary
                print("[OOTD Repair] \(report.detailedSummary)")
                if !report.errors.isEmpty {
                    print("[OOTD Repair] Errors:\n\(report.errors.joined(separator: "\n"))")
                }
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                isProcessing = false
                processingMessage = ""
            }
        }
    }
}
