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
    
    // View Mode Switcher
    enum ViewMode: String, CaseIterable, Identifiable {
        case planar = "平面"
        case spatial = "空间"
        var id: Self { self }
    }
    @AppStorage("bookShelfViewMode") var viewMode: ViewMode = .planar
    
    @State var showingNewBookAlert = false
    @State var newBookName = ""
    
    // Migration
    @Query(filter: #Predicate<Outfit> { $0.deletedAt == nil }) private var allOutfits: [Outfit]
    
    @State var showingBatchConfirmation = false
    @State var showingRepairConfirmation = false
    @State var showingBatchReplaceSheet = false
    @State var isProcessing = false
    @State var processingMessage = ""
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) private var allClothing: [Clothing]
    
    // Cover Picker
    @State var showingCoverPicker = false
    @State var selectedBookForCover: BookGroup?
    @State var selectedCoverItem: PhotosPickerItem?
    
    @State var showingTrash = false
    
    // For navigation
    @State var selectedBook: BookGroup?
    @State var navigationPath = NavigationPath()
    
    // Animation
    @Namespace var animationNamespace
    @State var openingBook: BookGroup?
    
    // Delete Confirmation
    @State var bookToDelete: BookGroup?
    @State var showingDeleteBookAlert = false
    
    // Track spatial book selection state
    @State var isSpatialBookSelected = false
    
    // Custom Sort Editing
    @State var isEditing = false
    @State var editableBooks: [BookGroup] = []
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            BookShelfContentView(
                viewMode: $viewMode,
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
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                BookShelfToolbar(
                    viewMode: $viewMode,
                    selectedBook: $selectedBook,
                    isSpatialBookSelected: $isSpatialBookSelected,
                    newBookName: $newBookName,
                    showingNewBookAlert: $showingNewBookAlert,
                    showingTrash: $showingTrash,
                    showingBatchConfirmation: $showingBatchConfirmation,
                    showingRepairConfirmation: $showingRepairConfirmation,
                    showingBatchReplaceSheet: $showingBatchReplaceSheet,
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
            .overlay {
                if isProcessing {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack {
                        ProgressView().tint(.white)
                        Text(processingMessage).foregroundStyle(.white).padding(.top)
                    }
                }
            }
            .navigationDestination(for: BookGroup.self) { book in
                BookDetailView(
                    book: book,
                    navigationPath: $navigationPath,
                    isSidebarVisible: .constant(true),
                    onBack: {
                        navigationPath.removeLast()
                    }
                )
            }
            .navigationDestination(for: SpaceBookGroup.self) { book in
                SpaceBookDetailView(book: book, isSidebarVisible: .constant(true))
            }
            .navigationDestination(for: SpaceOutfit.self) { outfit in
                SpatialCanvasEditorView(
                    spaceOutfit: outfit,
                    currentBook: outfit.book,  // 传递当前书
                    onSave: { updatedOutfit in
                        // 保存后确保数据持久化到磁盘
                        print("[BookShelf] 编辑器保存回调，outfit.id: \(updatedOutfit.id)")
                    }
                )
            }
            .sheet(isPresented: $showingTrash) {
                RecycleBinView(initialTab: 1)
            }
            .sheet(isPresented: $showingBatchReplaceSheet) {
                BatchReplaceCutoutView()
            }
            .photosPicker(isPresented: $showingCoverPicker, selection: $selectedCoverItem, matching: .images)
            .onChange(of: selectedCoverItem) { _, newItem in
                if let newItem, let book = selectedBookForCover {
                    updateCover(for: book, with: newItem)
                }
            }
            .onAppear {
                performMigration()
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
        }
    }
    
    private var navigationTitle: String {
        if viewMode == .spatial {
            return isSpatialBookSelected ? "" : ""
        }
        return selectedBook == nil ? "穿搭手帐" : selectedBook!.title
    }
    
    private func deleteBook(_ book: BookGroup) {
        book.isDeleted = true
        book.deletedAt = Date()
        for page in book.pages {
            page.isDeleted = true
            page.deletedAt = Date()
        }
        try? modelContext.save()
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
                }
            }
        }
    }
    
    private func performMigration() {
        let orphanOutfits = allOutfits.filter { $0.book == nil }
        
        if !orphanOutfits.isEmpty {
            let defaultBook: BookGroup
            if let existingDefault = books.first(where: { $0.title == "默认手帐" }) {
                defaultBook = existingDefault
            } else if let anyBook = books.first {
                defaultBook = anyBook
            } else {
                defaultBook = BookGroup(title: "默认手帐")
                modelContext.insert(defaultBook)
            }
            
            for outfit in orphanOutfits {
                outfit.book = defaultBook
            }
            
            try? modelContext.save()
        }
    }
    
    private func processWardrobeSkirts() {
        isProcessing = true
        processingMessage = "正在批量处理小裙子..."
        
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
    
    private func repairMissingCutouts() {
        isProcessing = true
        processingMessage = "正在深度修复数据..."
        
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                isProcessing = false
            }
        }
    }
}
