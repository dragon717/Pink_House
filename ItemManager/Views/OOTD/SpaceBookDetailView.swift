//
//  SpaceBookDetailView.swift
//  ItemManager
//
//  空间书页详情视图
//

import SwiftUI
import SwiftData
import PhotosUI

struct SpaceBookDetailView: View {
    @Bindable var book: SpaceBookGroup
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query(filter: #Predicate<SpaceBookGroup> { $0.deletedAt == nil }) private var allBooks: [SpaceBookGroup]

    // Sidebar visibility control
    @Binding var isSidebarVisible: Bool

    // 使用 @Query 获取书页数据，这样删除后会自动刷新
    @Query(filter: #Predicate<SpaceOutfit> { $0.isDeleted == false }, sort: \SpaceOutfit.sortIndex) private var allPages: [SpaceOutfit]

    // Sort pages by sortIndex (primary) then createdAt (secondary)
    var sortedPages: [SpaceOutfit] {
        allPages.filter { $0.book?.id == book.id }.sorted {
            if $0.sortIndex == $1.sortIndex {
                return $0.createdAt < $1.createdAt
            }
            return $0.sortIndex < $1.sortIndex
        }
    }

    @State private var showingNewPageAlert = false
    @State private var newPageNote = ""

    // Rename Page
    @State private var showingRenameAlert = false
    @State private var pageToRename: SpaceOutfit?
    @State private var renamePageName = ""

    // Move Page
    @State private var pageToMove: SpaceOutfit?
    @State private var showingMoveSheet = false

    // Cover Picker
    @State private var showingCoverPicker = false
    @State private var selectedCoverItem: PhotosPickerItem?
    
    // Rename Book
    @State private var showingRenameBookAlert = false
    @State private var renameBookName = ""
    
    // 分享卡片
    @State private var showingShareCard = false
    @State private var pageToShare: SpaceOutfit?
    
    // 设置缩略图
    @State private var showingThumbnailEditor = false
    @State private var pageToEditThumbnail: SpaceOutfit?

    // Grid Layout
    enum GridMode: Int, CaseIterable, Identifiable {
        case single = 1
        case double = 2
        case triple = 3

        var id: Int { rawValue }

        var displayName: String {
            switch self {
            case .single: return "单列"
            case .double: return "双列"
            case .triple: return "三列"
            }
        }

        var iconName: String {
            switch self {
            case .single: return "rectangle.grid.1x2"
            case .double: return "rectangle.grid.2x2"
            case .triple: return "rectangle.grid.3x2"
            }
        }

        var columns: [GridItem] {
            Array(repeating: GridItem(.flexible(), spacing: 16), count: rawValue)
        }
    }
    @AppStorage("spatialBookDetailGridMode") private var gridModeValue = 2

    private var gridMode: GridMode {
        GridMode(rawValue: gridModeValue) ?? .double
    }

    // Editing Mode for custom sort
    @State private var isEditing = false

    // 用于强制刷新视图的触发器
    @State private var refreshTrigger = false

    // 批量编辑相关状态
    @State private var isBatchEditing = false
    @State private var selectedPages = Set<UUID>()
    @State private var showingBatchDeleteConfirmation = false
    @State private var showingBatchCopyConfirmation = false

    var body: some View {
        mainContent
            .id(refreshTrigger)
            .navigationTitle(isBatchEditing ? "已选择 \(selectedPages.count) 项" : book.title)
            .onAppear {
                NotificationCenter.default.post(name: .spaceBookDetailOpened, object: nil)
            }
            .toolbar {
                if isBatchEditing {
                    batchEditingToolbarContent
                } else {
                    SpaceBookToolbar(
                        isSidebarVisible: $isSidebarVisible,
                        gridModeValue: $gridModeValue,
                        isEditing: $isEditing,
                        isBatchEditing: $isBatchEditing,
                        selectedPages: $selectedPages,
                        showingNewPageAlert: $showingNewPageAlert,
                        showingCoverPicker: $showingCoverPicker,
                        dismissAction: { dismiss() },
                        onRenameBook: { showingRenameBookAlert = true }
                    )
                }
            }
            .alert("新建空间书页", isPresented: $showingNewPageAlert) {
                TextField("备注", text: $newPageNote)
                Button("取消", role: .cancel) {}
                Button("创建") {
                    let newPage = SpaceOutfit(note: newPageNote, book: book)
                    newPage.sortIndex = (sortedPages.last?.sortIndex ?? 0) + 1
                    modelContext.insert(newPage)
                    NotificationCenter.default.post(name: .spaceBookPageCreated, object: newPage.id)
                    
                    // 立即保存到磁盘
                    do {
                        try modelContext.save()
                        print("[SpaceBook] 新建页面已保存: \(newPage.id)")
                    } catch {
                        print("[SpaceBook] 保存新建页面失败: \(error)")
                    }
                }
            }
            .alert("修改名称", isPresented: $showingRenameAlert) {
                TextField("名称", text: $renamePageName)
                Button("取消", role: .cancel) {}
                Button("确定") {
                    if let page = pageToRename {
                        page.note = renamePageName
                        try? modelContext.save()
                    }
                }
            }
            .sheet(isPresented: $showingMoveSheet) {
                if let page = pageToMove {
                    SpaceMovePageSheet(page: page, currentBook: book)
                }
            }
            .fullScreenCover(isPresented: $showingShareCard) {
                if let page = pageToShare {
                    ShareCardSheet(
                        shareType: .spaceOutfit(page),
                        onDismiss: { showingShareCard = false }
                    )
                }
            }
            .fullScreenCover(isPresented: $showingThumbnailEditor) {
                if let page = pageToEditThumbnail {
                    SpaceOutfitThumbnailEditorView(page: page)
                }
            }
            .photosPicker(isPresented: $showingCoverPicker, selection: $selectedCoverItem, matching: .images)
            .onChange(of: selectedCoverItem) { _, newItem in
                if let newItem {
                    updateCover(with: newItem)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true) // 隐藏系统返回按钮，使用自定义的返回按钮
            .alert("重命名手帐", isPresented: $showingRenameBookAlert) {
                TextField("名称", text: $renameBookName)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    book.title = renameBookName
                    try? modelContext.save()
                }
            }
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
    }

    // MARK: - 批量编辑工具栏

    private var batchEditingToolbarContent: some ToolbarContent {
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
            refreshTrigger.toggle()
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
                let newPage = SpaceOutfit(note: page.note + " 副本", book: book)
                newPage.sortIndex = currentMaxSortIndex
                newPage.snapshotPath = page.snapshotPath
                newPage.modelPath = page.modelPath
                newPage.camPosX = page.camPosX
                newPage.camPosY = page.camPosY
                newPage.camPosZ = page.camPosZ
                newPage.lightingIntensity = page.lightingIntensity
                modelContext.insert(newPage)
            }

            try? modelContext.save()
            refreshTrigger.toggle()
            selectedPages.removeAll()
            isBatchEditing = false
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            if sortedPages.isEmpty {
                emptyStateView
            } else {
                pagesGridView
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("暂无空间书页", systemImage: "doc.text.image")
        } description: {
            Text("点击 + 创建新的空间书页")
        }
        .foregroundStyle(emptyStateForegroundColor)
        .padding(.top, 100)
    }
    
    private var emptyStateForegroundColor: some ShapeStyle {
        colorScheme == .dark ? Color.white.opacity(0.7) : Color.secondary
    }

    private var pagesGridView: some View {
        GeometryReader { geometry in
            let containerWidth = geometry.size.width
            let columnCount = gridMode.rawValue
            let totalSpacing: CGFloat = CGFloat(columnCount - 1) * 16
            let itemWidth = (containerWidth - totalSpacing) / CGFloat(columnCount)
            // 书页封面比例 4:3（竖4，横3）-> 高:宽 = 4:3
            let itemHeight = itemWidth * 4 / 3

            LazyVGrid(columns: gridMode.columns, spacing: 16) {
                ForEach(sortedPages) { page in
                    pageCell(for: page, itemWidth: itemWidth, itemHeight: itemHeight)
                }
            }
        }
        .padding(24)
        .animation(.default, value: sortedPages)
    }

    @ViewBuilder
    private func pageCell(for page: SpaceOutfit, itemWidth: CGFloat, itemHeight: CGFloat) -> some View {
        if isBatchEditing {
            batchEditingPageCell(for: page, itemWidth: itemWidth, itemHeight: itemHeight)
        } else if isEditing {
            editingPageCell(for: page, itemWidth: itemWidth, itemHeight: itemHeight)
        } else {
            normalPageCell(for: page, itemWidth: itemWidth, itemHeight: itemHeight)
        }
    }

    @ViewBuilder
    private func batchEditingPageCell(for page: SpaceOutfit, itemWidth: CGFloat, itemHeight: CGFloat) -> some View {
        let isSelected = selectedPages.contains(page.id)
        SpaceOutfitCard(page: page, width: itemWidth, height: itemHeight)
            .overlay(alignment: .topLeading) {
                selectionIndicator(isSelected: isSelected)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.pink : Color.clear, lineWidth: 3)
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.2)) {
                    if isSelected {
                        selectedPages.remove(page.id)
                    } else {
                        selectedPages.insert(page.id)
                    }
                }
            }
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.pink : Color.white.opacity(0.8))
                .frame(width: 24, height: 24)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(8)
    }

    private func editingPageCell(for page: SpaceOutfit, itemWidth: CGFloat, itemHeight: CGFloat) -> some View {
        SpaceOutfitCard(page: page, width: itemWidth, height: itemHeight)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .padding(4)
            }
            .onDrag {
                return NSItemProvider(object: page.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: SpaceReorderableDropDelegate(item: page, pages: sortedPages, onMove: movePage))
    }

    private func normalPageCell(for page: SpaceOutfit, itemWidth: CGFloat, itemHeight: CGFloat) -> some View {
        NavigationLink(value: page) {
            SpaceOutfitCard(page: page, width: itemWidth, height: itemHeight)
        }
        .captureGuideTarget(sortedPages.first?.id == page.id ? .spaceBookFirstPageCard : nil)
        .contextMenu {
            pageContextMenu(for: page)
        }
    }

    @ViewBuilder
    private func pageContextMenu(for page: SpaceOutfit) -> some View {
        Button {
            pageToRename = page
            renamePageName = page.note
            showingRenameAlert = true
        } label: {
            Label("修改名称", systemImage: "pencil")
        }

        Button {
            duplicatePage(page)
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }

        Button {
            sharePage(page)
        } label: {
            Label("分享成图片", systemImage: "square.and.arrow.up")
        }

        Button {
            pageToEditThumbnail = page
            showingThumbnailEditor = true
        } label: {
            Label("设置缩略图", systemImage: "photo")
        }

        Button {
            insertPage(after: page)
        } label: {
            Label("在后面新增", systemImage: "arrow.right.square")
        }

        Button {
            insertPage(before: page)
        } label: {
            Label("在前面新增", systemImage: "arrow.left.square")
        }

        Button {
            pageToMove = page
            showingMoveSheet = true
        } label: {
            Label("移动到...", systemImage: "folder")
        }

        Button(role: .destructive) {
            deletePage(page)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }
    
    private func sharePage(_ page: SpaceOutfit) {
        // 打开分享卡片动画界面
        pageToShare = page
        showingShareCard = true
    }

    // MARK: - Actions

    private func updateCover(with item: PhotosPickerItem) {
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

    private func deletePage(_ page: SpaceOutfit) {
        withAnimation {
            page.isDeleted = true
            page.deletedAt = Date()
            page.lastModified = Date()
            do {
                try modelContext.save()

                // 记录删除到 DeleteTracker，防止iCloud同步覆盖
                DeleteTracker.shared.recordDeletedOutfit(id: page.id)
            } catch {
                print("SpaceBookDetailView: Failed to save deletion: \(error)")
            }
            // 强制刷新视图
            refreshTrigger.toggle()
        }
    }

    private func duplicatePage(_ page: SpaceOutfit) {
        let newPage = SpaceOutfit(note: page.note + " 副本", book: book)
        newPage.sortIndex = (sortedPages.last?.sortIndex ?? 0) + 1
        modelContext.insert(newPage)
        try? modelContext.save()
    }

    private func insertPage(after page: SpaceOutfit) {
        let newPage = SpaceOutfit(note: "", book: book)
        newPage.sortIndex = page.sortIndex + 1
        modelContext.insert(newPage)
        try? modelContext.save()
    }

    private func insertPage(before page: SpaceOutfit) {
        let newPage = SpaceOutfit(note: "", book: book)
        newPage.sortIndex = page.sortIndex
        modelContext.insert(newPage)
        try? modelContext.save()
    }

    private func movePage(from source: IndexSet, to destination: Int) {
        var pages = sortedPages
        pages.move(fromOffsets: source, toOffset: destination)
        for (index, page) in pages.enumerated() {
            page.sortIndex = index
        }
        try? modelContext.save()
    }
}
