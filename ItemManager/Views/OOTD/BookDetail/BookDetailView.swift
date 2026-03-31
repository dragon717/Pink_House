import SwiftUI
import SwiftData
import PhotosUI

struct BookDetailView: View {
    @Bindable var book: BookGroup
    @Binding var navigationPath: NavigationPath
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(filter: #Predicate<BookGroup> { $0.deletedAt == nil }) private var allBooks: [BookGroup]

    @Binding var isSidebarVisible: Bool
    var onBack: (() -> Void)?
    var showLeadingToolbar: Bool = true
    var showBackButton: Bool = true // 控制是否显示返回按钮
    var showSidebarToggle: Bool = true // 控制是否显示侧边栏切换按钮（在平面模式下从Tab管理器进入时隐藏）
    var onPageTap: ((Outfit) -> Void)? = nil

    // 使用 @State 存储书页数据，确保每次进入视图都重新获取
    @State private var pages: [Outfit] = []

    var sortedPages: [Outfit] {
        pages.filter { $0.book?.id == book.id }.sorted {
            if $0.sortIndex == $1.sortIndex {
                return $0.createdAt < $1.createdAt
            }
            return $0.sortIndex < $1.sortIndex
        }
    }

    var deleteConfirmationMessage: String {
        if let page = pageToDelete {
            return "确定要删除书页「\(page.note)」吗？删除后可在回收站中恢复。"
        } else {
            return "确定要删除此书页吗？删除后可在回收站中恢复。"
        }
    }

    @State var isEditing = false

    @State var showingRenameAlert = false
    @State var pageToRename: Outfit?
    @State var newPageName = ""

    @State var showingCoverPicker = false
    @State var selectedCoverItem: PhotosPickerItem?

    @State var showingBackgroundPicker = false
    @State var selectedBackgroundItem: PhotosPickerItem?
    @State var tempBackgroundImage: UIImage?
    @State var showingBackgroundCropper = false

    @State var showingTrash = false

    @State var showingMoveSheet = false
    @State var pageToMove: Outfit?
    
    // 分享卡片
    @State var showingShareCard = false
    @State var pageToShare: Outfit?
    
    // Rename Book
    @State var showingRenameBookAlert = false
    @State var renameBookName = ""
    
    // 批量添加图片书页
    @State var showingBatchPhotoPicker = false
    @State var selectedBatchPhotos: [PhotosPickerItem] = []
    @State var isBatchProcessing = false
    @State var batchProcessingProgress = 0
    @State var batchTotalCount = 0
    
    // 删除确认对话框
    @State var showingDeleteConfirmation = false
    @State var pageToDelete: Outfit?
    
    // 批量处理相关状态
    @State var showingBatchConfirmation = false
    @State var showingRepairConfirmation = false
    @State var showingBatchReplaceSheet = false
    @State var isProcessing = false
    @State var processingMessage = ""
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) private var allClothing: [Clothing]
    
    // 批量编辑相关状态
    @State var isBatchEditing = false
    @State var selectedPages = Set<UUID>()
    @State var showingBatchDeleteConfirmation = false
    @State var showingBatchCopyConfirmation = false

    @AppStorage("bookDetailGridMode") var gridModeValue = 2

    var gridMode: GridMode {
        GridMode(rawValue: gridModeValue) ?? .double
    }

    var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: gridMode.rawValue)
    }

    // 用于强制刷新视图的触发器
    @State private var refreshTrigger = false

    var body: some View {
        contentView
    }

    @ViewBuilder
    private var contentView: some View {
        let mainView = Group {
            if sortedPages.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(sortedPages) { page in
                            pageCell(for: page)
                        }
                    }
                    .padding()
                    .animation(.default, value: sortedPages)
                }
            }
        }
        .id(refreshTrigger)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        let withNav = mainView
            .navigationTitle(isBatchEditing ? "已选择 \(selectedPages.count) 项" : book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if showLeadingToolbar {
                    leadingToolbarContent
                }
                if isBatchEditing {
                    batchEditingToolbarContent
                } else {
                    trailingToolbarContent
                }
            }
        
        let withSheets = withNav
            .bookDetailSheets(
                showingTrash: $showingTrash,
                showingCoverPicker: $showingCoverPicker,
                selectedCoverItem: $selectedCoverItem,
                updateCover: updateCover,
                showingBackgroundPicker: $showingBackgroundPicker,
                selectedBackgroundItem: $selectedBackgroundItem,
                tempBackgroundImage: $tempBackgroundImage,
                showingBackgroundCropper: $showingBackgroundCropper,
                backgroundCropperSheet: { backgroundCropperSheet },
                showingRenameAlert: $showingRenameAlert,
                newPageName: $newPageName,
                pageToRename: $pageToRename,
                saveRename: saveRename,
                showingMoveSheet: $showingMoveSheet,
                movePageSheet: { movePageSheet }
            )
            .alert("确认删除", isPresented: $showingDeleteConfirmation, actions: {
                Button("取消", role: .cancel) {
                    pageToDelete = nil
                }
                Button("删除", role: .destructive) {
                    confirmDeletePage()
                }
            }, message: {
                Text(deleteConfirmationMessage)
            })
            .alert("确认批量删除", isPresented: $showingBatchDeleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    confirmBatchDelete()
                }
            } message: {
                Text("确定要删除选中的 \(selectedPages.count) 个书页吗？删除后可在回收站中恢复。")
            }
            .alert("确认批量复制", isPresented: $showingBatchCopyConfirmation) {
                Button("取消", role: .cancel) {}
                Button("复制") {
                    confirmBatchCopy()
                }
            } message: {
                Text("确定要复制选中的 \(selectedPages.count) 个书页吗？")
            }
            .fullScreenCover(isPresented: $showingShareCard) {
                if let page = pageToShare {
                    ShareCardSheet(
                        shareType: .outfit(page),
                        onDismiss: { showingShareCard = false }
                    )
                }
            }
            .alert("重命名手帐", isPresented: $showingRenameBookAlert) {
                TextField("名称", text: $renameBookName)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    book.title = renameBookName
                    try? modelContext.save()
                }
            }
            .photosPicker(
                isPresented: $showingBatchPhotoPicker,
                selection: $selectedBatchPhotos,
                maxSelectionCount: 20,
                selectionBehavior: .ordered,
                matching: .images
            )
            .onChange(of: selectedBatchPhotos) { _, newItems in
                if !newItems.isEmpty {
                    batchTotalCount = newItems.count
                    processBatchPhotos(newItems)
                    selectedBatchPhotos = []
                }
            }
        
        let withBatchOverlays = withSheets
            .overlay {
                if isBatchProcessing {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView(value: Double(batchProcessingProgress), total: Double(batchTotalCount))
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            Text("正在添加书页... \(batchProcessingProgress)/\(batchTotalCount)")
                                .foregroundStyle(.white)
                                .font(.headline)
                        }
                        .padding(32)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                    }
                }
            }
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
            .overlay {
                if isProcessing {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack {
                        ProgressView().tint(.white)
                        Text(processingMessage).foregroundStyle(.white).padding(.top)
                    }
                }
            }
        
        withBatchOverlays
            .onAppear {
                // 每次进入视图时重新获取书页数据
                loadPages()
                // 打印当前手帐的书页状态
                printBookPagesStatus()
                // 发送通知用于空间手帐前置任务引导（附带书页状态）
                let hasPages = sortedPages.contains { $0.deletedAt == nil }
                NotificationCenter.default.post(name: .ootdBookDetailOpened, object: nil, userInfo: ["hasPages": hasPages])
            }
    }

    // 打印当前手帐的书页状态
    func printBookPagesStatus() {
        print("=== 手帐『\(book.title)』书页状态 ===")
        print("手帐ID: \(book.id)")
        print("书页数量: \(sortedPages.count)")
        for page in sortedPages {
            print("  - 书页: \(page.note), isDeleted: \(page.isDeleted), deletedAt: \(String(describing: page.deletedAt)), book: \(String(describing: page.book?.title ?? "nil"))")
        }
        print("========================")
    }

    private func loadPages() {
        // 先查询所有书页（包括已删除的），用于调试
        let allDescriptor = FetchDescriptor<Outfit>(sortBy: [SortDescriptor(\Outfit.sortIndex)])
        do {
            let allPages = try modelContext.fetch(allDescriptor)
            print("### LOAD: Total pages in database: \(allPages.count)")
            for p in allPages {
                print("### LOAD: Page '\(p.note)' - isDeleted:\(p.isDeleted), deletedAt:\(String(describing: p.deletedAt)), book:\(p.book?.title ?? "nil")")
            }
        } catch {
            print("### LOAD: Failed to fetch all pages: \(error)")
        }

        // 正常查询只加载未删除的书页
        let descriptor = FetchDescriptor<Outfit>(
            predicate: #Predicate { $0.isDeleted == false },
            sortBy: [SortDescriptor(\Outfit.sortIndex)]
        )
        do {
            pages = try modelContext.fetch(descriptor)
            print("BookDetailView: Loaded \(pages.count) pages")
        } catch {
            print("BookDetailView: Failed to load pages: \(error)")
            pages = []
        }
    }
    
    private func processBatchPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        
        isBatchProcessing = true
        batchProcessingProgress = 0
        
        Task {
            let startSortIndex = (sortedPages.last?.sortIndex ?? 0) + 1
            
            for (index, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        let newPage = Outfit(
                            note: "图片书页 \(Date().formatted(date: .numeric, time: .shortened))",
                            canvasType: "custom",
                            book: book
                        )
                        newPage.sortIndex = startSortIndex + index
                        
                        // 裁剪图片为 3:4 比例
                        let croppedImage = cropImageToAspectRatio(image, aspectRatio: 0.75)
                        
                        if let path = ImageManager.shared.saveImage(croppedImage, context: modelContext) {
                            newPage.backgroundImagePath = path
                            newPage.snapshotPath = path
                        }
                        
                        modelContext.insert(newPage)
                        batchProcessingProgress = index + 1
                    }
                }
            }
            
            await MainActor.run {
                try? modelContext.save()
                // 批量添加完成后重新加载书页数据，确保视图即时刷新
                loadPages()
                refreshTrigger.toggle()
                isBatchProcessing = false
            }
        }
    }
    
    private func cropImageToAspectRatio(_ image: UIImage, aspectRatio: CGFloat) -> UIImage {
        let imageSize = image.size
        let targetRatio = aspectRatio
        let currentRatio = imageSize.width / imageSize.height
        
        var cropRect: CGRect
        
        if currentRatio > targetRatio {
            // 图片太宽，裁剪宽度
            let newWidth = imageSize.height * targetRatio
            let xOffset = (imageSize.width - newWidth) / 2
            cropRect = CGRect(x: xOffset, y: 0, width: newWidth, height: imageSize.height)
        } else {
            // 图片太高，裁剪高度
            let newHeight = imageSize.width / targetRatio
            let yOffset = (imageSize.height - newHeight) / 2
            cropRect = CGRect(x: 0, y: yOffset, width: imageSize.width, height: newHeight)
        }
        
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
            return image
        }
        
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private var backgroundCropperSheet: some View {
        Group {
            if let image = tempBackgroundImage {
                ImageCropView(
                    image: image,
                    aspectRatio: 0.75,
                    targetWidth: 1080
                ) { croppedImage in
                    addNewPage(canvasType: "custom", customImage: croppedImage)
                    showingBackgroundCropper = false
                    tempBackgroundImage = nil
                } onCancel: {
                    showingBackgroundCropper = false
                    tempBackgroundImage = nil
                }
            }
        }
    }

    private var movePageSheet: some View {
        Group {
            if let page = pageToMove {
                MovePageSheet(page: page, currentBook: book)
            }
        }
    }

    private func saveRename() {
        if let page = pageToRename {
            page.note = newPageName
            try? modelContext.save()
        }
    }

    func movePage(from source: Outfit, to destination: Outfit) {
        var localPages = sortedPages
        guard let sourceIndex = localPages.firstIndex(where: { $0.id == source.id }),
              let destIndex = localPages.firstIndex(where: { $0.id == destination.id }) else { return }

        if sourceIndex == destIndex { return }

        withAnimation {
            let item = localPages.remove(at: sourceIndex)
            localPages.insert(item, at: destIndex)

            for (index, page) in localPages.enumerated() {
                page.sortIndex = index
            }
        }

        do {
            try modelContext.save()
            // 重新加载数据以更新排序
            loadPages()
        } catch {
            print("BookDetailView: Failed to save move: \(error)")
        }
    }

    func addNewPage(canvasType: String = "mannequin", customImage: UIImage? = nil) {
        let newPage = Outfit(note: "新书页 \(Date().formatted(date: .numeric, time: .shortened))", canvasType: canvasType, book: book)
        newPage.sortIndex = (sortedPages.last?.sortIndex ?? 0) + 1

        if canvasType == "custom", let image = customImage {
            if let path = ImageManager.shared.saveImage(image, context: modelContext) {
                newPage.backgroundImagePath = path
                newPage.snapshotPath = path
            }
        }

        modelContext.insert(newPage)
        loadPages()
        // 发送通知用于空间手帐引导
        NotificationCenter.default.post(name: .ootdPageCreated, object: nil)
    }

    func insertPage(after page: Outfit) {
        let newPage = Outfit(note: "新书页", book: book)

        let localPages = sortedPages
        if let index = localPages.firstIndex(of: page) {
            newPage.sortIndex = page.sortIndex + 1
            for p in localPages where p.sortIndex > page.sortIndex {
                p.sortIndex += 1
            }
        } else {
            newPage.sortIndex = (localPages.last?.sortIndex ?? 0) + 1
        }

        modelContext.insert(newPage)
        loadPages()
    }

    func insertPage(before page: Outfit) {
        let newPage = Outfit(note: "新书页", book: book)

        let localPages = sortedPages
        if let index = localPages.firstIndex(of: page) {
            newPage.sortIndex = page.sortIndex
            for p in localPages where p.sortIndex >= page.sortIndex {
                p.sortIndex += 1
            }
        }

        modelContext.insert(newPage)
        loadPages()
    }

    func duplicatePage(_ page: Outfit) {
        let newPage = Outfit(note: page.note + " 副本", canvasType: page.canvasType, backgroundImagePath: page.backgroundImagePath, book: book)

        let localPages = sortedPages
        if let index = localPages.firstIndex(of: page) {
            newPage.sortIndex = page.sortIndex + 1
            for p in localPages where p.sortIndex > page.sortIndex {
                p.sortIndex += 1
            }
        }

        modelContext.insert(newPage)

        for item in page.items ?? [] {
            // 复制时保持原有的 coordinateVersion，不强制转换为新版本
            let newItem = OutfitItem(cutout: item.cutout, x: item.x, y: item.y, rotation: item.rotation, scale: item.scale, zIndex: item.zIndex, coordinateVersion: item.coordinateVersion)
            if newPage.items == nil {
                newPage.items = []
            }
            newPage.items?.append(newItem)
        }

        if let path = page.snapshotPath,
           let image = ImageManager.shared.loadImage(fileName: path),
           let newPath = ImageManager.shared.saveImage(image, context: modelContext) {
            newPage.snapshotPath = newPath
        }
        loadPages()
    }

    func deletePage(_ page: Outfit) {
        withAnimation {
            print("### DELETE: Setting isDeleted=true for page '\(page.note)' (ID: \(page.id))")

            // 设置删除标记
            page.isDeleted = true
            page.deletedAt = Date()
            page.lastModified = Date()

            print("### DELETE: Before save - isDeleted=\(page.isDeleted)")

            do {
                try modelContext.save()
                print("### DELETE: Saved successfully")
            } catch {
                print("### DELETE: Failed to save: \(error)")
            }

            // 记录删除到 DeleteTracker，防止iCloud同步覆盖
            DeleteTracker.shared.recordDeletedOutfit(id: page.id)

            // 删除成功后重新加载数据
            loadPages()
        }
    }

    func confirmDeletePage() {
        if let page = pageToDelete {
            deletePage(page)
            pageToDelete = nil
        }
    }

    func updateCover(with item: PhotosPickerItem) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let path = ImageManager.shared.saveImage(image, context: modelContext) {
                await MainActor.run {
                    book.coverImage = path
                    selectedCoverItem = nil
                    // 保存到数据库并刷新视图
                    try? modelContext.save()
                    refreshTrigger.toggle()
                }
            }
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
                loadPages()
                refreshTrigger.toggle()
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("还没有穿搭书页")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("点击右上角的+号新建新的穿搭书页")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 批量编辑工具栏

    var batchEditingToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                // 全选/取消全选
                Button {
                    toggleSelectAll()
                } label: {
                    Text(selectedPages.count == sortedPages.count ? "取消全选" : "全选")
                        .font(.system(size: 16, weight: .medium))
                }

                // 复制按钮
                Button {
                    if !selectedPages.isEmpty {
                        showingBatchCopyConfirmation = true
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 16, weight: .semibold))
                }
                .disabled(selectedPages.isEmpty)

                // 删除按钮
                Button {
                    if !selectedPages.isEmpty {
                        showingBatchDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .disabled(selectedPages.isEmpty)

                // 完成按钮
                Button {
                    isBatchEditing = false
                    selectedPages.removeAll()
                } label: {
                    Text("完成")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.pink)
                }
            }
        }
    }

    // MARK: - 批量编辑操作

    private func toggleSelectAll() {
        if selectedPages.count == sortedPages.count {
            selectedPages.removeAll()
        } else {
            selectedPages = Set(sortedPages.map { $0.id })
        }
    }

    private func confirmBatchDelete() {
        withAnimation {
            let pagesToDelete = sortedPages.filter { selectedPages.contains($0.id) }
            for page in pagesToDelete {
                page.isDeleted = true
                page.deletedAt = Date()
                page.lastModified = Date()
                DeleteTracker.shared.recordDeletedOutfit(id: page.id)
            }
            try? modelContext.save()
            loadPages()
            selectedPages.removeAll()
            isBatchEditing = false
        }
    }

    private func confirmBatchCopy() {
        withAnimation {
            let pagesToCopy = sortedPages.filter { selectedPages.contains($0.id) }
            var currentMaxSortIndex = sortedPages.last?.sortIndex ?? 0

            for page in pagesToCopy {
                currentMaxSortIndex += 1
                let newPage = Outfit(
                    note: page.note + " 副本",
                    canvasType: page.canvasType,
                    backgroundImagePath: page.backgroundImagePath,
                    book: book
                )
                newPage.sortIndex = currentMaxSortIndex
                modelContext.insert(newPage)

                // 复制书页中的物品
                if let items = page.items {
                    for item in items {
                        // 复制时保持原有的 coordinateVersion，不强制转换为新版本
                        let newItem = OutfitItem(
                            cutout: item.cutout,
                            x: item.x,
                            y: item.y,
                            rotation: item.rotation,
                            scale: item.scale,
                            zIndex: item.zIndex,
                            coordinateVersion: item.coordinateVersion
                        )
                        if newPage.items == nil {
                            newPage.items = []
                        }
                        newPage.items?.append(newItem)
                    }
                }

                // 复制缩略图
                if let path = page.snapshotPath,
                   let image = ImageManager.shared.loadImage(fileName: path),
                   let newPath = ImageManager.shared.saveImage(image, context: modelContext) {
                    newPage.snapshotPath = newPath
                }
            }

            try? modelContext.save()
            loadPages()
            selectedPages.removeAll()
            isBatchEditing = false
        }
    }
}

