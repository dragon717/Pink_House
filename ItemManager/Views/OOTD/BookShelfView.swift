import SwiftUI
import SwiftData
import PhotosUI

struct BookShelfView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BookGroup> { $0.deletedAt == nil }, sort: \BookGroup.createdAt, order: .reverse) private var books: [BookGroup]
    
    // View Mode Switcher
    enum ViewMode: String, CaseIterable, Identifiable {
        case planar = "平面"
        case spatial = "空间"
        var id: Self { self }
    }
    @AppStorage("bookShelfViewMode") private var viewMode: ViewMode = .planar
    
    @State private var showingNewBookAlert = false
    @State private var newBookName = ""
    // Migration
    @Query(filter: #Predicate<Outfit> { $0.deletedAt == nil }) private var allOutfits: [Outfit]
    
    @State private var showingBatchConfirmation = false
    @State private var showingRepairConfirmation = false
    @State private var showingBatchReplaceSheet = false
    @State private var isProcessing = false
    @State private var processingMessage = ""
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) private var allClothing: [Clothing]
    
    // Cover Picker
    @State private var showingCoverPicker = false
    @State private var selectedBookForCover: BookGroup?
    @State private var selectedCoverItem: PhotosPickerItem?
    
    @State private var showingTrash = false
    
    // For navigation
    @State private var selectedBook: BookGroup?
    @State private var navigationPath = NavigationPath()
    
    // Animation
    @Namespace private var animationNamespace
    @State private var openingBook: BookGroup?
    
    // Delete Confirmation
    @State private var bookToDelete: BookGroup?
    @State private var showingDeleteBookAlert = false
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewMode == .planar {
                    planarContent
                } else {
                    SpatialBookShelfView()
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if selectedBook == nil {
                    ToolbarItem(placement: .principal) {
                        Picker("模式", selection: $viewMode) {
                            ForEach(ViewMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                }
                
                // Only show top-level menu in Grid Mode (Planar)
                if viewMode == .planar && selectedBook == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                newBookName = ""
                                showingNewBookAlert = true
                            } label: {
                                Label("新建手帐", systemImage: "plus.rectangle.on.folder")
                            }
                            
                            Button {
                                showingTrash = true
                            } label: {
                                Label("垃圾篓", systemImage: "trash")
                            }
                            
                            Divider()
                            
                            Button {
                                showingBatchConfirmation = true
                            } label: {
                                Label("批量处理小裙子", systemImage: "wand.and.stars")
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
                                .font(.system(size: 22)) // Slightly larger to compensate for lack of background padding visual weight
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
                .alert("新建手帐本", isPresented: $showingNewBookAlert) {
                    TextField("名称", text: $newBookName)
                    Button("取消", role: .cancel) {}
                    Button("创建") {
                        let book = BookGroup(title: newBookName.isEmpty ? "新书本" : newBookName)
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
                    BookDetailView(book: book, navigationPath: $navigationPath)
                }
                .sheet(isPresented: $showingTrash) {
                    RecycleBinView(initialTab: 1) // Default to OOTD tab from BookShelf
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
                    Text("确定要将“\(bookToDelete?.title ?? "此手帐")”移入回收站吗？")
                }
        }
    }
    
    private var navigationTitle: String {
        if viewMode == .spatial {
            return ""
        }
        return selectedBook == nil ? "穿搭手帐" : selectedBook!.title
    }
    
    @ViewBuilder
    private var planarContent: some View {
        ZStack {
            // Global Background
            LiquidBackground()
                .ignoresSafeArea()
            
            if let selectedBook = selectedBook {
                // Split Layout (Detail Mode)
                HStack(spacing: 0) {
                    // Sidebar: List of Books
                    BookSidebarView(
                        books: books,
                        selectedBook: selectedBook,
                        onSelect: { book in
                            self.selectedBook = book
                        }
                    )
                    .transition(.move(edge: .leading))
                    
                    // Content: Book Detail
                    BookDetailView(book: selectedBook, navigationPath: $navigationPath)
                        .id(selectedBook.id) // Force refresh
                        .transition(.opacity)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    withAnimation {
                                        self.selectedBook = nil
                                    }
                                } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "chevron.left")
                                            Text("手帐架")
                                        }
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                        // Removed background for native look
                                    }
                            }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                // Grid Layout (Bookshelf Mode)
                BookGridView(
                    books: books,
                    selectedBook: $selectedBook,
                    selectedBookForCover: $selectedBookForCover,
                    showingCoverPicker: $showingCoverPicker,
                    onDelete: { book in
                        bookToDelete = book
                        showingDeleteBookAlert = true
                    },
                    namespace: animationNamespace,
                    onBookTap: { book in
                        withAnimation {
                            openingBook = book
                        }
                    },
                    openingBook: openingBook
                )
                .transition(.opacity)
                .opacity(openingBook == nil ? 1 : 0) // 这里其实已经控制了 opacity，但内部的占位符是为了 matchedGeometryEffect 彻底失效
            }
            
            // Animation Overlay
            if let book = openingBook {
                BookOpeningAnimationView(book: book) {
                    withAnimation {
                        selectedBook = book
                        openingBook = nil
                    }
                }
                .zIndex(100)
            }
        }
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
    
    // MARK: - Migration & Tools
    
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
            // Placeholder logic as per original
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                isProcessing = false
            }
        }
    }
}
