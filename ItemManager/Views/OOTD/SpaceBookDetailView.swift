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

    // Sort pages by sortIndex (primary) then createdAt (secondary)
    var sortedPages: [SpaceOutfit] {
        book.pages.filter { !$0.isDeleted }.sorted {
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

    var body: some View {
        mainContent
            .navigationTitle(book.title)
            .toolbar {
                SpaceBookToolbar(
                    isSidebarVisible: $isSidebarVisible,
                    gridModeValue: $gridModeValue,
                    isEditing: $isEditing,
                    showingNewPageAlert: $showingNewPageAlert,
                    showingCoverPicker: $showingCoverPicker,
                    dismissAction: { dismiss() },
                    onRenameBook: { showingRenameBookAlert = true }
                )
            }
            .alert("新建空间书页", isPresented: $showingNewPageAlert) {
                TextField("备注", text: $newPageNote)
                Button("取消", role: .cancel) {}
                Button("创建") {
                    let newPage = SpaceOutfit(note: newPageNote, book: book)
                    newPage.sortIndex = (sortedPages.last?.sortIndex ?? 0) + 1
                    modelContext.insert(newPage)
                    
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
            .photosPicker(isPresented: $showingCoverPicker, selection: $selectedCoverItem, matching: .images)
            .onChange(of: selectedCoverItem) { _, newItem in
                if let newItem {
                    updateCover(with: newItem)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .alert("重命名手帐", isPresented: $showingRenameBookAlert) {
                TextField("名称", text: $renameBookName)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    book.title = renameBookName
                    try? modelContext.save()
                }
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
        if isEditing {
            editingPageCell(for: page, itemWidth: itemWidth, itemHeight: itemHeight)
        } else {
            normalPageCell(for: page, itemWidth: itemWidth, itemHeight: itemHeight)
        }
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

    // MARK: - Actions

    private func updateCover(with item: PhotosPickerItem) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let path = ImageManager.shared.saveImage(image, context: modelContext) {
                await MainActor.run {
                    book.coverImage = path
                    selectedCoverItem = nil
                }
            }
        }
    }

    private func deletePage(_ page: SpaceOutfit) {
        page.isDeleted = true
        page.deletedAt = Date()
        try? modelContext.save()
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
