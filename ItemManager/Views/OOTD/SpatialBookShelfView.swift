//
//  SpatialBookShelfView.swift
//  ItemManager
//
//  空间书架主视图
//

import SwiftUI
import SwiftData
import PhotosUI

struct SpatialBookShelfView: View {
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<SpaceBookGroup> { $0.deletedAt == nil }, sort: \SpaceBookGroup.sortIndex, order: .forward) private var books: [SpaceBookGroup]

    @State private var showingNewBookAlert = false
    @State private var newBookName = ""

    // Selection & Navigation
    @State private var selectedBook: SpaceBookGroup?
    @Namespace private var animationNamespace
    @State private var openingBook: SpaceBookGroup?

    // Callback to notify parent when selection changes
    var onSelectionChange: ((Bool) -> Void)? = nil

    // Delete Confirmation
    @State private var bookToDelete: SpaceBookGroup?
    @State private var showingDeleteBookAlert = false
    @State private var showingTrash = false

    // Rename Book
    @State private var bookToRename: SpaceBookGroup?
    @State private var showingRenameBookAlert = false
    @State private var renameBookName = ""

    // Cover Picker
    @State private var showingCoverPicker = false
    @State private var selectedBookForCover: SpaceBookGroup?
    @State private var selectedCoverItem: PhotosPickerItem?

    // Sidebar visibility
    @State private var isSidebarVisible = true

    // Custom Sort Editing
    @State private var isEditing = false
    @State private var editableBooks: [SpaceBookGroup] = []
    @State private var draggingItem: SpaceBookGroup?

    // Batch delete
    @State private var isBatchEditingBooks = false
    @State private var selectedBookIDs = Set<UUID>()
    @State private var showingBatchDeleteBooksAlert = false

    var body: some View {
        applyPresentationModifiers(
            to: applyLifecycleAndToolbar(
                to: applyChangeHandlers(to: rootContent)
            )
        )
    }

    @ViewBuilder
    private var rootContent: some View {
        ZStack {
            backgroundView
            bookshelfMainContent
            openingBookOverlay
        }
    }

    private var backgroundView: some View {
        LiquidBackground(themeSkinWallpaperContext: .journal)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var bookshelfMainContent: some View {
        if let selectedBook {
            detailModeContent(for: selectedBook)
        } else {
            bookGridContent
        }
    }

    private func detailModeContent(for selectedBook: SpaceBookGroup) -> some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebarView(for: selectedBook)
            }
            detailContentView(for: selectedBook)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func sidebarView(for selectedBook: SpaceBookGroup) -> some View {
        SpaceBookSidebarView(
            books: isEditing ? editableBooks : books,
            selectedBook: selectedBook,
            onSelect: { book in
                print("[DEBUG] onSelect called with book: \(book.title)")
                if !isEditing {
                    self.selectedBook = book
                }
            },
            isEditing: isEditing
        )
        .transition(.move(edge: .leading))
    }

    private func detailContentView(for selectedBook: SpaceBookGroup) -> some View {
        SpaceBookDetailView(
            book: selectedBook,
            isSidebarVisible: $isSidebarVisible
        )
        .id(selectedBook.id)
        .transition(.opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar { detailBackToolbar }
    }

    @ToolbarContentBuilder
    private var detailBackToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                withAnimation {
                    self.selectedBook = nil
                }
            } label: {
                Image(systemName: "chevron.left")
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private var openingBookOverlay: some View {
        if let book = openingBook {
            SpaceBookOpeningAnimationView(book: book) {
                withAnimation {
                    selectedBook = book
                    openingBook = nil
                    onSelectionChange?(true)
                }
            }
            .zIndex(100)
        }
    }

    private func applyChangeHandlers<Content: View>(to content: Content) -> some View {
        content
        .onChange(of: selectedBook) { _, newValue in
            onSelectionChange?(newValue != nil)
            if newValue != nil {
                isBatchEditingBooks = false
                selectedBookIDs.removeAll()
            }
        }
        .onChange(of: isEditing) { _, newValue in
            if newValue {
                isBatchEditingBooks = false
                selectedBookIDs.removeAll()
                editableBooks = books
            } else {
                // Save sort order
                for (index, book) in editableBooks.enumerated() {
                    book.sortIndex = index
                }
                try? modelContext.save()
            }
        }
        .onChange(of: books) { _, newValue in
            if isEditing {
                editableBooks = newValue
            }
            let activeIDs = Set(newValue.map(\.id))
            selectedBookIDs = selectedBookIDs.intersection(activeIDs)
        }
        .onChange(of: isBatchEditingBooks) { _, newValue in
            if newValue {
                isEditing = false
            } else {
                selectedBookIDs.removeAll()
            }
        }
        .onChange(of: books.count) { _, _ in
            publishSpaceBookShelfGuideDataState()
        }
        .onChange(of: showingNewBookAlert) { _, isVisible in
            postSpaceBookCreationPromptVisibilityChanged(isVisible: isVisible)
        }
    }

    private func applyLifecycleAndToolbar<Content: View>(to content: Content) -> some View {
        content
            .onAppear(perform: handleViewAppear)
            .onDisappear(perform: handleViewDisappear)
            .toolbar { bookshelfToolbar }
    }

    private func applyPresentationModifiers<Content: View>(to content: Content) -> some View {
        let withNewBookAlert = applyNewBookAlert(to: content)
        let withDeleteBookAlert = applyDeleteBookAlert(to: withNewBookAlert)
        let withBatchDeleteBooksAlert = applyBatchDeleteBooksAlert(to: withDeleteBookAlert)
        let withRenameBookAlert = applyRenameBookAlert(to: withBatchDeleteBooksAlert)
        let withTrashSheet = applyTrashSheet(to: withRenameBookAlert)
        return applyCoverPicker(to: withTrashSheet)
    }

    private func applyNewBookAlert<Content: View>(to content: Content) -> some View {
        content.alert("新建空间手帐".appLocalized, isPresented: $showingNewBookAlert) {
            TextField("名称".appLocalized, text: $newBookName)
            Button("取消".appLocalized, role: .cancel) {}
            Button("创建".appLocalized) {
                let maxSortIndex = books.map { $0.sortIndex }.max() ?? -1
                let book = SpaceBookGroup(
                    title: newBookName.isEmpty ? "新空间".appLocalized : newBookName,
                    sortIndex: maxSortIndex + 1
                )
                modelContext.insert(book)

                if AppFirstLaunchGuideManager.shared.currentFeatureExperienceFeature == .spaceBook {
                    withAnimation {
                        selectedBook = book
                        onSelectionChange?(true)
                    }
                    NotificationCenter.default.post(name: .spaceBookDetailOpened, object: nil)
                }
            }
        }
    }

    private func applyDeleteBookAlert<Content: View>(to content: Content) -> some View {
        content.alert("删除手帐".appLocalized, isPresented: $showingDeleteBookAlert) {
            Button("取消".appLocalized, role: .cancel) { bookToDelete = nil }
            Button("删除".appLocalized, role: .destructive) {
                if let book = bookToDelete {
                    deleteBook(book)
                    if selectedBook?.id == book.id {
                        selectedBook = nil
                    }
                }
                bookToDelete = nil
            }
        } message: {
            Text("确定要将「%@」移入回收站吗？".appLocalized(bookToDelete?.title ?? "此手帐".appLocalized))
        }
    }

    private func applyBatchDeleteBooksAlert<Content: View>(to content: Content) -> some View {
        content.alert("确认批量删除".appLocalized, isPresented: $showingBatchDeleteBooksAlert) {
            Button("取消".appLocalized, role: .cancel) {}
            Button("删除".appLocalized, role: .destructive) {
                confirmBatchDeleteBooks()
            }
        } message: {
            Text("确定要将选中的 %d 个空间手帐及其中书页移入回收站吗？".appLocalized(selectedBookIDs.count))
        }
    }

    private func applyRenameBookAlert<Content: View>(to content: Content) -> some View {
        content.alert("重命名手帐".appLocalized, isPresented: $showingRenameBookAlert) {
            TextField("名称".appLocalized, text: $renameBookName)
            Button("取消".appLocalized, role: .cancel) { bookToRename = nil }
            Button("保存".appLocalized) {
                if let book = bookToRename {
                    book.title = renameBookName
                    try? modelContext.save()
                }
                bookToRename = nil
            }
        }
    }

    private func applyTrashSheet<Content: View>(to content: Content) -> some View {
        content.sheet(isPresented: $showingTrash) {
            RecycleBinSheetView(initialTab: 2)
        }
    }

    private func applyCoverPicker<Content: View>(to content: Content) -> some View {
        content
            .photosPicker(isPresented: $showingCoverPicker, selection: $selectedCoverItem, matching: .images)
            .onChange(of: selectedCoverItem) { _, newItem in
                if let newItem, let book = selectedBookForCover {
                    updateCover(for: book, with: newItem)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Book Grid Content

    @ToolbarContentBuilder
    private var bookshelfToolbar: some ToolbarContent {
        if selectedBook == nil {
            ToolbarItem(placement: .topBarTrailing) {
                if isBatchEditingBooks {
                    batchEditingToolbarControls
                } else {
                    normalToolbarControls
                }
            }
        }
    }

    private var normalToolbarControls: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation {
                    isEditing.toggle()
                    if isEditing {
                        selectedBookIDs.removeAll()
                    }
                }
            } label: {
                Image(systemName: isEditing ? "checkmark.circle" : "list.number")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isEditing ? .pink : .primary)
            }

            Group {
                if guideManager.shouldUseCustomGuideMenu(for: .spaceBookShelfMore) {
                    Button {
                        presentGuideMenuForSpaceBookShelfMore()
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.primary)
                    }
                } else {
                    Menu {
                        Button {
                            createSpaceBook()
                        } label: {
                            Label("新建空间手帐".appLocalized, systemImage: "plus.rectangle.on.folder")
                        }

                        Divider()

                        Button {
                            beginBatchDelete()
                        } label: {
                            Label("批量删除".appLocalized, systemImage: "checkmark.circle")
                        }
                        .disabled(books.isEmpty)

                        Button {
                            showingTrash = true
                        } label: {
                            Label("垃圾篓".appLocalized, systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .captureGuideToolbarIconTarget(.spaceBookShelfMoreMenuButton)
        }
    }

    private var batchEditingToolbarControls: some View {
        HStack(spacing: 16) {
            Button {
                toggleSelectAllBooks()
            } label: {
                Text((selectedBookIDs.count == books.count ? "取消全选" : "全选").appLocalized)
                    .font(.system(size: 16, weight: .medium))
            }
            .disabled(books.isEmpty)

            Button {
                if !selectedBookIDs.isEmpty {
                    showingBatchDeleteBooksAlert = true
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.red)
            }
            .disabled(selectedBookIDs.isEmpty)

            Button {
                withAnimation {
                    isBatchEditingBooks = false
                    selectedBookIDs.removeAll()
                }
            } label: {
                Text("完成".appLocalized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.pink)
            }
        }
    }

    private func createSpaceBook() {
        newBookName = ""
        showingNewBookAlert = true
    }

    private func beginBatchDelete() {
        withAnimation {
            isEditing = false
            isBatchEditingBooks = true
            selectedBookIDs.removeAll()
        }
    }

    private func toggleSelectAllBooks() {
        if selectedBookIDs.count == books.count {
            selectedBookIDs.removeAll()
        } else {
            selectedBookIDs = Set(books.map(\.id))
        }
    }

    private func presentGuideMenuForSpaceBookShelfMore() {
        guideManager.presentGuideMenu(
            GuideMenuPresentationState(
                scenario: .spaceBookShelfMore,
                anchorKey: .spaceBookShelfMoreMenuButton,
                width: 228,
                submenuDepth: 0,
                items: [
                    .action(
                        title: "新建空间手帐".appLocalized,
                        systemImage: "plus.rectangle.on.folder",
                        isHighlighted: true,
                        action: createSpaceBook
                    ),
                    .divider,
                    .action(
                        title: "批量删除".appLocalized,
                        systemImage: "checkmark.circle",
                        action: beginBatchDelete
                    ),
                    .action(
                        title: "垃圾篓".appLocalized,
                        systemImage: "trash",
                        action: { showingTrash = true }
                    )
                ]
            )
        )
    }

    @ViewBuilder
    private var bookGridContent: some View {
        Group {
            if isEditing {
                ScrollView {
                    // Editing Mode: Draggable Grid
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 24)], spacing: 32) {
                        ForEach(editableBooks) { book in
                            editingBookCell(for: book)
                        }
                    }
                    .padding(24)
                    .animation(.default, value: editableBooks)
                }
            } else if isBatchEditingBooks {
                batchBookGridContent
            } else {
                // Normal Mode: Navigation Grid
                SpaceBookGridView(
                    books: books,
                    onBookTap: { book in
                        withAnimation {
                            openingBook = book
                        }
                    },
                    onDelete: { book in
                        bookToDelete = book
                        showingDeleteBookAlert = true
                    },
                    onRename: { book in
                        bookToRename = book
                        renameBookName = book.title
                        showingRenameBookAlert = true
                    },
                    onSetCover: { book in
                        selectedBookForCover = book
                        showingCoverPicker = true
                    },
                    namespace: animationNamespace,
                    openingBook: openingBook
                )
                .transition(.opacity)
                .opacity(openingBook == nil ? 1 : 0)
            }
        }
    }

    private var batchBookGridContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 24)], spacing: 32) {
                ForEach(books) { book in
                    batchEditingBookCell(for: book)
                }
            }
            .padding(24)
            .animation(.default, value: selectedBookIDs)
        }
    }

    private func batchEditingBookCell(for book: SpaceBookGroup) -> some View {
        let isSelected = selectedBookIDs.contains(book.id)

        return SpaceBookView(book: book, namespace: animationNamespace)
            .overlay(alignment: .topLeading) {
                ThemeSkinSelectionBadge(isSelected: isSelected)
                    .padding(4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.pink : Color.clear, lineWidth: 3)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.2)) {
                    if isSelected {
                        selectedBookIDs.remove(book.id)
                    } else {
                        selectedBookIDs.insert(book.id)
                    }
                }
            }
    }

    @ViewBuilder
    private func editingBookCell(for book: SpaceBookGroup) -> some View {
        SpaceBookView(book: book, namespace: animationNamespace)
            .overlay(alignment: .topTrailing) {
                ThemeSkinIconBadge(
                    systemName: "line.3.horizontal",
                    fallbackColor: .gray,
                    size: 24,
                    symbolSize: 10
                )
                .padding(4)
            }
            .onDrag {
                self.draggingItem = book
                return NSItemProvider(object: book.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: SpaceBookReorderableDropDelegate(item: book, books: $editableBooks, draggingItem: $draggingItem))
    }

    private func updateCover(for book: SpaceBookGroup, with item: PhotosPickerItem) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let path = ImageManager.shared.saveImage(image, context: modelContext) {
                await MainActor.run {
                    book.coverImage = path
                    selectedCoverItem = nil
                    selectedBookForCover = nil
                    // 保存到数据库
                    try? modelContext.save()
                }
            }
        }
    }

    private func deleteBook(_ book: SpaceBookGroup) {
        let pages = book.pages ?? []
        book.isDeleted = true
        book.deletedAt = Date()
        book.lastModified = Date()
        // Also mark pages as deleted
        for page in pages {
            page.isDeleted = true
            page.deletedAt = Date()
            page.lastModified = Date()
        }
        do {
            try modelContext.save()

            // 记录删除到 DeleteTracker，防止iCloud同步覆盖
            DeleteTracker.shared.recordDeletedSpaceBookGroup(id: book.id)
            DeleteTracker.shared.recordDeletedSpaceOutfits(ids: pages.map(\.id))
        } catch {
            print("SpatialBookShelfView: Failed to save deletion: \(error)")
        }
    }

    private func confirmBatchDeleteBooks() {
        let booksToDelete = books.filter { selectedBookIDs.contains($0.id) }
        guard !booksToDelete.isEmpty else { return }

        var deletedPageIDs: [UUID] = []
        let deletionDate = Date()

        for book in booksToDelete {
            let pages = book.pages ?? []
            book.isDeleted = true
            book.deletedAt = deletionDate
            book.lastModified = deletionDate

            for page in pages {
                page.isDeleted = true
                page.deletedAt = deletionDate
                page.lastModified = deletionDate
                deletedPageIDs.append(page.id)
            }
        }

        do {
            try modelContext.save()
            DeleteTracker.shared.recordDeletedSpaceBookGroups(ids: booksToDelete.map(\.id))
            DeleteTracker.shared.recordDeletedSpaceOutfits(ids: deletedPageIDs)
        } catch {
            print("SpatialBookShelfView: Failed to save batch deletion: \(error)")
        }

        selectedBookIDs.removeAll()
        isBatchEditingBooks = false
        publishSpaceBookShelfGuideDataState()
    }

    private func handleViewAppear() {
        publishSpaceBookShelfGuideDataState()
        NotificationCenter.default.post(name: .spatialBookShelfOpened, object: nil)
    }

    private func handleViewDisappear() {
        postSpaceBookCreationPromptVisibilityChanged(isVisible: false)
        NotificationCenter.default.post(
            name: .spaceBookShelfDataStateChanged,
            object: nil,
            userInfo: ["hasBooks": false]
        )
    }

    private func postSpaceBookCreationPromptVisibilityChanged(isVisible: Bool) {
        NotificationCenter.default.post(
            name: .spaceBookCreationPromptVisibilityChanged,
            object: nil,
            userInfo: ["isVisible": isVisible]
        )
    }

    private func publishSpaceBookShelfGuideDataState() {
        NotificationCenter.default.post(
            name: .spaceBookShelfDataStateChanged,
            object: nil,
            userInfo: ["hasBooks": !books.isEmpty]
        )
    }
}

// MARK: - Space Book Reorderable Drop Delegate

struct SpaceBookReorderableDropDelegate: DropDelegate {
    let item: SpaceBookGroup
    @Binding var books: [SpaceBookGroup]
    @Binding var draggingItem: SpaceBookGroup?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingItem = draggingItem else { return false }

        if let itemProvider = info.itemProviders(for: [.text]).first {
            itemProvider.loadItem(forTypeIdentifier: "public.text", options: nil) { (data, error) in
                if let data = data as? Data,
                   let idString = String(data: data, encoding: .utf8),
                   let uuid = UUID(uuidString: idString) {
                    DispatchQueue.main.async {
                        if let sourceIndex = books.firstIndex(where: { $0.id == uuid }),
                           let destinationIndex = books.firstIndex(where: { $0.id == item.id }) {
                            if sourceIndex != destinationIndex {
                                withAnimation {
                                    let item = books.remove(at: sourceIndex)
                                    books.insert(item, at: destinationIndex)
                                }
                            }
                        }
                    }
                }
            }
            return true
        }
        return false
    }
}
