//
//  BookShelfView.swift
//  ItemManager
//
//  书架主视图
//

import SwiftUI
import SwiftData
import PhotosUI

struct BookShelfView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BookGroup> { $0.deletedAt == nil }, sort: \BookGroup.sortIndex, order: .forward) private var books: [BookGroup]
    
    // 从衣橱进入时隐藏返回按钮
    var hideBackButton: Bool = false
    
    // View Mode Switcher
    enum ViewMode: String, CaseIterable, Identifiable {
        case planar = "平面"
        case spatial = "空间"
        var id: Self { self }

        var localizedTitle: String {
            rawValue.appLocalized
        }
    }
    @AppStorage("bookShelfViewMode") var viewMode: ViewMode = .planar

    private var guardedViewModeBinding: Binding<ViewMode> {
        Binding(
            get: { viewMode },
            set: { newValue in
                if newValue == .spatial && !FeatureUnlockManager.shared.isUnlocked(.spaceBook) {
                    viewMode = .planar
                    ToastManager.shared.showWarning("请先完成「空间手帐」任务，再进入「空间」页签".appLocalized)
                    return
                }
                viewMode = newValue
            }
        )
    }
    
    @State var showingNewBookAlert = false
    @State var newBookName = ""
    
    // Cover Picker
    @State var showingCoverPicker = false
    @State var selectedBookForCover: BookGroup?
    @State var selectedCoverItem: PhotosPickerItem?
    
    @State var showingTrash = false
    
    // For navigation
    @State var selectedBook: BookGroup?
    @State var navigationPath = NavigationPath()
    
    // 用于外部监听当前是否选中了书（书页列表模式下隐藏全局导航返回按钮）
    @Binding var isBookSelected: Bool
    
    // Animation
    @Namespace var animationNamespace
    @State var openingBook: BookGroup?
    
    // Delete Confirmation
    @State var bookToDelete: BookGroup?
    @State var showingDeleteBookAlert = false
    
    // Track spatial book selection state
    @State var isSpatialBookSelected = false
    
    // 用于外部监听当前是否选中了空间书（空间书页列表模式下隐藏全局导航返回按钮）
    @Binding var isSpaceBookSelected: Bool

    // 从魔法贴纸加入手帐后需要自动导航到的书
    @Binding var navigateToBookID: UUID?

    // Custom Sort Editing
    @State var isEditing = false
    @State var editableBooks: [BookGroup] = []

    // Batch delete
    @State var isBatchEditingBooks = false
    @State var selectedBookIDs = Set<UUID>()
    @State var showingBatchDeleteBooksAlert = false

    private var orderedBooks: [BookGroup] {
        books.sorted {
            if $0.sortIndex != $1.sortIndex {
                return $0.sortIndex < $1.sortIndex
            }
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return String(describing: $0.persistentModelID) < String(describing: $1.persistentModelID)
        }
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            applyBookShelfModifiers(to: bookShelfContent)
        }
    }

    private var bookShelfContent: some View {
        BookShelfContentView(
            viewMode: guardedViewModeBinding,
            selectedBook: $selectedBook,
            isSpatialBookSelected: $isSpatialBookSelected,
            openingBook: $openingBook,
            bookToDelete: $bookToDelete,
            showingDeleteBookAlert: $showingDeleteBookAlert,
            selectedBookForCover: $selectedBookForCover,
            showingCoverPicker: $showingCoverPicker,
            books: orderedBooks,
            namespace: animationNamespace,
            onBookTap: openBook,
            onDelete: requestDeleteBook,
            isEditing: $isEditing,
            isBatchEditingBooks: $isBatchEditingBooks,
            selectedBookIDs: $selectedBookIDs
        )
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hideBackButton)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            BookShelfToolbar(
                viewMode: guardedViewModeBinding,
                selectedBook: $selectedBook,
                isSpatialBookSelected: $isSpatialBookSelected,
                newBookName: $newBookName,
                showingNewBookAlert: $showingNewBookAlert,
                showingTrash: $showingTrash,
                isEditing: $isEditing,
                isBatchEditingBooks: $isBatchEditingBooks,
                selectedBookIDs: $selectedBookIDs,
                showingBatchDeleteBooksAlert: $showingBatchDeleteBooksAlert,
                books: orderedBooks
            )
        }
    }

    private func applyBookShelfModifiers<Content: View>(to content: Content) -> some View {
        let withNavigation = applyNavigationDestinations(to: content)
        let withPresentation = applyPresentationModifiers(to: withNavigation)
        return applyLifecycleHandlers(to: withPresentation)
    }

    private func applyNavigationDestinations<Content: View>(to content: Content) -> some View {
        content
            .navigationDestination(for: BookGroup.self) { book in
                BookDetailView(
                    book: book,
                    navigationPath: $navigationPath,
                    isSidebarVisible: .constant(true),
                    onBack: handleBookDetailBack
                )
                .navigationBarBackButtonHidden(true)
            }
            .navigationDestination(for: SpaceBookGroup.self) { book in
                SpaceBookDetailView(book: book, isSidebarVisible: .constant(true))
                    .navigationBarBackButtonHidden(true)
            }
            .navigationDestination(for: SpaceOutfit.self) { outfit in
                spatialCanvasDestination(for: outfit)
            }
    }

    private func applyPresentationModifiers<Content: View>(to content: Content) -> some View {
        content
            .alert("新建手帐本".appLocalized, isPresented: $showingNewBookAlert) {
                TextField("名称".appLocalized, text: $newBookName)
                Button("取消".appLocalized, role: .cancel) {}
                Button("创建".appLocalized, action: createBook)
            }
            .sheet(isPresented: $showingTrash) {
                RecycleBinSheetView(initialTab: 1)
            }
            .photosPicker(isPresented: $showingCoverPicker, selection: $selectedCoverItem, matching: .images)
            .alert("删除手帐".appLocalized, isPresented: $showingDeleteBookAlert) {
                Button("取消".appLocalized, role: .cancel) { bookToDelete = nil }
                Button("删除".appLocalized, role: .destructive, action: confirmDeleteBook)
            } message: {
                Text("确定要将「%@」移入回收站吗？".appLocalized(bookToDelete?.title ?? "此手帐".appLocalized))
            }
            .alert("确认批量删除".appLocalized, isPresented: $showingBatchDeleteBooksAlert) {
                Button("取消".appLocalized, role: .cancel) {}
                Button("删除".appLocalized, role: .destructive, action: confirmBatchDeleteBooks)
            } message: {
                Text("确定要将选中的 %d 个手帐及其中书页移入回收站吗？".appLocalized(selectedBookIDs.count))
            }
    }

    private func applyLifecycleHandlers<Content: View>(to content: Content) -> some View {
        content
            .onChange(of: selectedCoverItem) { _, newItem in
                handleSelectedCoverItemChange(newItem)
            }
            .onAppear(perform: handleAppear)
            .onReceive(NotificationCenter.default.publisher(for: .ootdRestoreCompleted)) { _ in
                handleRestoreCompleted()
            }
            .onChange(of: showingNewBookAlert) { _, isVisible in
                postBookCreationPromptVisibilityChanged(isVisible: isVisible)
            }
            .onChange(of: books) { _, newBooks in
                handleBooksChanged(newBooks)
            }
            .onChange(of: selectedBook) { _, newValue in
                handleSelectedBookChanged(newValue)
            }
            .onChange(of: isSpatialBookSelected) { _, newValue in
                isSpaceBookSelected = newValue
            }
            .onChange(of: isEditing) { _, newValue in
                handleEditingChanged(newValue)
            }
            .onChange(of: isBatchEditingBooks) { _, newValue in
                handleBatchEditingChanged(newValue)
            }
            .onChange(of: navigateToBookID) { _, newBookID in
                handleNavigateToBookChange(newBookID)
            }
            .onDisappear {
                postBookCreationPromptVisibilityChanged(isVisible: false)
            }
    }

    private func openBook(_ book: BookGroup) {
        selectedBook = book
    }

    private func requestDeleteBook(_ book: BookGroup) {
        bookToDelete = book
        showingDeleteBookAlert = true
    }

    private func handleBookDetailBack() {
        navigationPath.removeLast()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .ootdReturnedToShelfFromDetail, object: nil)
            notifyOotdShelfGuideState()
        }
    }

    @ViewBuilder
    private func spatialCanvasDestination(for outfit: SpaceOutfit) -> some View {
        if #available(iOS 18.0, *) {
            SpatialCanvasEditorView(
                spaceOutfit: outfit,
                currentBook: outfit.book,
                onSave: { updatedOutfit in
                    print("[BookShelf] 编辑器保存回调，outfit.id: \(updatedOutfit.id)")
                }
            )
        } else {
            SpatialCanvasUnsupportedView()
        }
    }

    private func createBook() {
        let maxSortIndex = books.map { $0.sortIndex }.max() ?? -1
        let book = BookGroup(
            title: newBookName.isEmpty ? "新书本".appLocalized : newBookName,
            sortIndex: maxSortIndex + 1
        )
        book.lastModified = Date()
        modelContext.insert(book)
        try? modelContext.save()
        NotificationCenter.default.post(name: .ootdBookCreated, object: nil)
    }

    private func confirmDeleteBook() {
        if let book = bookToDelete {
            deleteBook(book)
        }
        bookToDelete = nil
    }

    private func handleSelectedCoverItemChange(_ newItem: PhotosPickerItem?) {
        if let newItem, let book = selectedBookForCover {
            updateCover(for: book, with: newItem)
        }
    }

    private func handleAppear() {
        if viewMode == .spatial && !FeatureUnlockManager.shared.isUnlocked(.spaceBook) {
            viewMode = .planar
        }
        repairPlanarOrphansIfNeeded(source: "onAppear")
        isBookSelected = selectedBook != nil
        notifyOotdShelfGuideState()
    }

    private func handleRestoreCompleted() {
        performMigration(source: "restoreCompleted")
        notifyOotdShelfGuideState()
    }

    private func postBookCreationPromptVisibilityChanged(isVisible: Bool) {
        NotificationCenter.default.post(
            name: .ootdBookCreationPromptVisibilityChanged,
            object: nil,
            userInfo: ["isVisible": isVisible]
        )
    }

    private func handleBooksChanged(_ newBooks: [BookGroup]) {
        notifyOotdShelfGuideState()
        let activeIDs = Set(newBooks.map(\.id))
        selectedBookIDs = selectedBookIDs.intersection(activeIDs)
    }

    private func handleSelectedBookChanged(_ newValue: BookGroup?) {
        isBookSelected = newValue != nil
        if newValue != nil {
            isBatchEditingBooks = false
            selectedBookIDs.removeAll()
        }
    }

    private func handleEditingChanged(_ newValue: Bool) {
        if newValue {
            isBatchEditingBooks = false
            selectedBookIDs.removeAll()
        }
    }

    private func handleBatchEditingChanged(_ newValue: Bool) {
        if newValue {
            isEditing = false
        } else {
            selectedBookIDs.removeAll()
        }
    }
    
    private var navigationTitle: String {
        if viewMode == .spatial {
            return isSpatialBookSelected ? "" : ""
        }
        return selectedBook == nil ? "穿搭手帐".appLocalized : selectedBook!.title
    }

    private func handleNavigateToBookChange(_ newBookID: UUID?) {
        guard let bookID = newBookID else { return }
        guard let targetBook = books.first(where: { $0.id == bookID }) else { return }

        withAnimation {
            navigationPath.append(targetBook)
        }
        navigateToBookID = nil
    }

    private func notifyOotdShelfGuideState() {
        AppFirstLaunchGuideManager.shared.requestGuideTargetRecapture()
        let hasUserBooks = hasUserCreatedBooks()
        let hasUserPages = hasUserCreatedPages()
        print("[Guide] BookShelf state notify - hasUserBooks: \(hasUserBooks), hasUserPages: \(hasUserPages), totalBooks: \(books.count)")
        NotificationCenter.default.post(
            name: .ootdShelfOpened,
            object: nil,
            userInfo: ["hasBooks": hasUserBooks, "hasPages": hasUserPages]
        )
        NotificationCenter.default.post(
            name: .ootdBookShelfOpened,
            object: nil,
            userInfo: ["hasNonDefaultBooks": hasUserBooks, "hasPages": hasUserPages]
        )
    }
    
    /// 检查是否有用户手动创建的非默认手帐
    private func hasUserCreatedBooks() -> Bool {
        let defaultBookTitle = "默认手帐"
        // 查询非默认且未删除的手帐
        var descriptor = FetchDescriptor<BookGroup>(
            predicate: #Predicate { $0.deletedAt == nil && $0.title != defaultBookTitle }
        )
        descriptor.fetchLimit = 1
        do {
            let userBooks = try modelContext.fetch(descriptor)
            return !userBooks.isEmpty
        } catch {
            print("[BookShelf] Failed to fetch user created books: \(error)")
            return false
        }
    }

    /// 检查用户手动创建的手帐中是否有书页
    private func hasUserCreatedPages() -> Bool {
        let defaultBookTitle = "默认手帐"
        // 查询属于非默认手帐且未删除的书页
        var descriptor = FetchDescriptor<Outfit>(
            predicate: #Predicate {
                $0.deletedAt == nil &&
                $0.book?.deletedAt == nil &&
                $0.book?.title != defaultBookTitle
            }
        )
        descriptor.fetchLimit = 1
        do {
            let userPages = try modelContext.fetch(descriptor)
            return !userPages.isEmpty
        } catch {
            print("[BookShelf] Failed to fetch user created pages: \(error)")
            return false
        }
    }

    private func deleteBook(_ book: BookGroup) {
        let pages = book.pages ?? []
        book.isDeleted = true
        book.deletedAt = Date()
        book.lastModified = Date()
        for page in pages {
            page.isDeleted = true
            page.deletedAt = Date()
            page.lastModified = Date()
        }
        do {
            try modelContext.save()

            // 记录删除到 DeleteTracker，防止iCloud同步覆盖
            DeleteTracker.shared.recordDeletedBookGroup(id: book.id)
            DeleteTracker.shared.recordDeletedOutfits(ids: pages.map(\.id))
        } catch {
            print("BookShelfView: Failed to save deletion: \(error)")
        }
    }

    private func confirmBatchDeleteBooks() {
        let booksToDelete = orderedBooks.filter { selectedBookIDs.contains($0.id) }
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
            DeleteTracker.shared.recordDeletedBookGroups(ids: booksToDelete.map(\.id))
            DeleteTracker.shared.recordDeletedOutfits(ids: deletedPageIDs)
        } catch {
            print("BookShelfView: Failed to save batch deletion: \(error)")
        }

        selectedBookIDs.removeAll()
        isBatchEditingBooks = false
        notifyOotdShelfGuideState()
    }
    
    private func updateCover(for book: BookGroup, with item: PhotosPickerItem) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let path = ImageManager.shared.saveImage(image, context: modelContext) {
                await MainActor.run {
                    book.coverImage = path
                    book.lastModified = Date()
                    selectedCoverItem = nil
                    selectedBookForCover = nil
                    // 保存到数据库
                    try? modelContext.save()
                }
            }
        }
    }
    
    private func performMigration(source: String = "onAppear") {
        let identityReport = OOTDIdentityRepairService.repairIfNeeded(
            context: modelContext,
            source: source
        )
        let orphanOutfits = fetchPlanarOrphanOutfits()
        let orphanReport = OOTDOrphanPageRepairService.repairPlanarOrphans(
            context: modelContext,
            activeBooks: orderedBooks,
            allOutfits: orphanOutfits,
            source: source
        )
        if identityReport.didChange || orphanReport.movedToDefaultBook > 0 || orphanReport.createdDefaultBook {
            _ = OOTDIdentityRepairService.repairIfNeeded(
                context: modelContext,
                source: "\(source)-post-orphan"
            )
        }
    }

    private func repairPlanarOrphansIfNeeded(source: String) {
        let orphanOutfits = fetchPlanarOrphanOutfits(fetchLimit: 1)
        guard !orphanOutfits.isEmpty else { return }

        let repairOutfits = fetchPlanarOrphanOutfits()
        let orphanReport = OOTDOrphanPageRepairService.repairPlanarOrphans(
            context: modelContext,
            activeBooks: orderedBooks,
            allOutfits: repairOutfits,
            source: source
        )
        if orphanReport.movedToDefaultBook > 0 || orphanReport.createdDefaultBook {
            notifyOotdShelfGuideState()
        }
    }

    private func fetchPlanarOrphanOutfits(fetchLimit: Int? = nil) -> [Outfit] {
        var descriptor = FetchDescriptor<Outfit>(
            predicate: #Predicate {
                $0.book == nil &&
                $0.isDeleted == false &&
                $0.deletedAt == nil
            },
            sortBy: [SortDescriptor(\Outfit.createdAt)]
        )
        if let fetchLimit {
            descriptor.fetchLimit = fetchLimit
        }

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("[BookShelf] Failed to fetch orphan OOTD pages: \(error)")
            return []
        }
    }

}

private struct SpatialCanvasUnsupportedView: View {
    var body: some View {
        ContentUnavailableView(
            "空间手帐需要 iOS 18 或更高版本",
            systemImage: "cube.transparent",
            description: Text("当前系统暂不支持 3D 空间画布，请升级系统后再使用。")
        )
    }
}
