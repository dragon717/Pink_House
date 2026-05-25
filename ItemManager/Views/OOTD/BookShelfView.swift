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
    }
    @AppStorage("bookShelfViewMode") var viewMode: ViewMode = .planar

    private var guardedViewModeBinding: Binding<ViewMode> {
        Binding(
            get: { viewMode },
            set: { newValue in
                if newValue == .spatial && !FeatureUnlockManager.shared.isUnlocked(.spaceBook) {
                    viewMode = .planar
                    ToastManager.shared.showWarning("请先完成「空间手帐」任务，再进入「空间」页签")
                    return
                }
                viewMode = newValue
            }
        )
    }
    
    @State var showingNewBookAlert = false
    @State var newBookName = ""
    
    // Migration
    @Query(filter: #Predicate<Outfit> { $0.deletedAt == nil && $0.isDeleted == false }) private var allOutfits: [Outfit]
    
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
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            BookShelfContentView(
                viewMode: guardedViewModeBinding,
                selectedBook: $selectedBook,
                isSpatialBookSelected: $isSpatialBookSelected,
                openingBook: $openingBook,
                bookToDelete: $bookToDelete,
                showingDeleteBookAlert: $showingDeleteBookAlert,
                selectedBookForCover: $selectedBookForCover,
                showingCoverPicker: $showingCoverPicker,
                books: books,
                namespace: animationNamespace,
                onBookTap: { book in
                    withAnimation {
                        openingBook = book
                    }
                },
                onDelete: { book in
                    bookToDelete = book
                    showingDeleteBookAlert = true
                },
                isEditing: $isEditing
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
                    isEditing: $isEditing
                )
            }
            .alert("新建手帐本", isPresented: $showingNewBookAlert) {
                TextField("名称", text: $newBookName)
                Button("取消", role: .cancel) {}
                Button("创建") {
                    let maxSortIndex = books.map { $0.sortIndex }.max() ?? -1
                    let book = BookGroup(
                        title: newBookName.isEmpty ? "新书本" : newBookName,
                        sortIndex: maxSortIndex + 1
                    )
                    modelContext.insert(book)
                    // 发送通知用于空间手帐引导
                    NotificationCenter.default.post(name: .ootdBookCreated, object: nil)
                }
            }
            .navigationDestination(for: BookGroup.self) { book in
                BookDetailView(
                    book: book,
                    navigationPath: $navigationPath,
                    isSidebarVisible: .constant(true),
                    onBack: {
                        navigationPath.removeLast()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            NotificationCenter.default.post(name: .ootdReturnedToShelfFromDetail, object: nil)
                            notifyOotdShelfGuideState()
                        }
                    }
                )
                .navigationBarBackButtonHidden(true) // 隐藏系统返回按钮，使用自定义的backButton
            }
            .navigationDestination(for: SpaceBookGroup.self) { book in
                SpaceBookDetailView(book: book, isSidebarVisible: .constant(true))
                    .navigationBarBackButtonHidden(true) // 隐藏系统返回按钮，使用自定义的返回按钮
            }
            .navigationDestination(for: SpaceOutfit.self) { outfit in
                if #available(iOS 18.0, *) {
                    SpatialCanvasEditorView(
                        spaceOutfit: outfit,
                        currentBook: outfit.book,  // 传递当前书
                        onSave: { updatedOutfit in
                            // 保存后确保数据持久化到磁盘
                            print("[BookShelf] 编辑器保存回调，outfit.id: \(updatedOutfit.id)")
                        }
                    )
                } else {
                    SpatialCanvasUnsupportedView()
                }
            }
            .sheet(isPresented: $showingTrash) {
                RecycleBinView(initialTab: 1)
            }
            .photosPicker(isPresented: $showingCoverPicker, selection: $selectedCoverItem, matching: .images)
            .onChange(of: selectedCoverItem) { _, newItem in
                if let newItem, let book = selectedBookForCover {
                    updateCover(for: book, with: newItem)
                }
            }
            .onAppear {
                if viewMode == .spatial && !FeatureUnlockManager.shared.isUnlocked(.spaceBook) {
                    viewMode = .planar
                }
                performMigration()
                // 初始化时同步选中状态
                isBookSelected = selectedBook != nil
                notifyOotdShelfGuideState()
            }
            .onReceive(NotificationCenter.default.publisher(for: .ootdRestoreCompleted)) { _ in
                performMigration(source: "restoreCompleted")
                notifyOotdShelfGuideState()
            }
            .onChange(of: showingNewBookAlert) { _, isVisible in
                NotificationCenter.default.post(
                    name: .ootdBookCreationPromptVisibilityChanged,
                    object: nil,
                    userInfo: ["isVisible": isVisible]
                )
            }
            .onChange(of: books) { _, _ in
                notifyOotdShelfGuideState()
            }
            .onChange(of: selectedBook) { _, newValue in
                // 同步选中状态到外部
                isBookSelected = newValue != nil
            }
            .onChange(of: isSpatialBookSelected) { _, newValue in
                // 同步空间书选中状态到外部
                isSpaceBookSelected = newValue
            }
            .onChange(of: navigateToBookID) { _, newBookID in
                handleNavigateToBookChange(newBookID)
            }
            .alert("删除手帐", isPresented: $showingDeleteBookAlert) {
                Button("取消", role: .cancel) { bookToDelete = nil }
                Button("删除", role: .destructive) {
                    if let book = bookToDelete {
                        deleteBook(book)
                    }
                    bookToDelete = nil
                }
            } message: {
                Text("确定要将「\(bookToDelete?.title ?? "此手帐")」移入回收站吗？")
            }
            .onDisappear {
                NotificationCenter.default.post(
                    name: .ootdBookCreationPromptVisibilityChanged,
                    object: nil,
                    userInfo: ["isVisible": false]
                )
            }
        }
    }
    
    private var navigationTitle: String {
        if viewMode == .spatial {
            return isSpatialBookSelected ? "" : ""
        }
        return selectedBook == nil ? "穿搭手帐" : selectedBook!.title
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
    
    /// 直接查询获取有效书页数量（避免关系数据延迟加载问题）
    private func fetchValidPageCount() -> Int {
        let descriptor = FetchDescriptor<Outfit>(
            predicate: #Predicate { $0.deletedAt == nil && $0.book?.deletedAt == nil }
        )
        do {
            let pages = try modelContext.fetch(descriptor)
            return pages.count
        } catch {
            print("[BookShelf] Failed to fetch page count: \(error)")
            return 0
        }
    }

    /// 检查是否有用户手动创建的非默认手帐
    private func hasUserCreatedBooks() -> Bool {
        let defaultBookTitle = "默认手帐"
        // 查询非默认且未删除的手帐
        let descriptor = FetchDescriptor<BookGroup>(
            predicate: #Predicate { $0.deletedAt == nil && $0.title != defaultBookTitle }
        )
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
        let descriptor = FetchDescriptor<Outfit>(
            predicate: #Predicate {
                $0.deletedAt == nil &&
                $0.book?.deletedAt == nil &&
                $0.book?.title != defaultBookTitle
            }
        )
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
    
    private func updateCover(for book: BookGroup, with item: PhotosPickerItem) {
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
    
    private func performMigration(source: String = "onAppear") {
        _ = OOTDOrphanPageRepairService.repairPlanarOrphans(
            context: modelContext,
            activeBooks: books,
            allOutfits: allOutfits,
            source: source
        )

        // 打印默认手帐的书页状态
        printDefaultBookPagesStatus()
    }

    // 打印默认手帐的书页状态
    func printDefaultBookPagesStatus() {
        if let defaultBook = books.first(where: { $0.title == "默认手帐" }) {
            print("=== 默认手帐书页状态 ===")
            print("手帐ID: \(defaultBook.id)")
            print("书页数量: \(defaultBook.pages?.count ?? 0)")
            for page in defaultBook.pages ?? [] {
                print("  - 书页: \(page.note), isDeleted: \(page.isDeleted), deletedAt: \(String(describing: page.deletedAt))")
            }
            print("========================")
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
