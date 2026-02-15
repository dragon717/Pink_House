
import SwiftUI
import SwiftData
import SceneKit
import PhotosUI

struct SpatialBookShelfView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<SpaceBookGroup> { $0.deletedAt == nil }, sort: \SpaceBookGroup.createdAt, order: .reverse) private var books: [SpaceBookGroup]
    
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
    
    // Rename Book
    @State private var bookToRename: SpaceBookGroup?
    @State private var showingRenameBookAlert = false
    @State private var renameBookName = ""
    
    // Cover Picker
    @State private var showingCoverPicker = false
    @State private var selectedBookForCover: SpaceBookGroup?
    @State private var selectedCoverItem: PhotosPickerItem?
    
    var body: some View {
        ZStack {
            // Background
            LiquidBackground()
                .ignoresSafeArea()
            
            if let selectedBook = selectedBook {
                // Split Layout (Detail Mode)
                let _ = print("[DEBUG] Detail mode - selectedBook: \(selectedBook.title), books count: \(books.count)")
                HStack(spacing: 0) {
                    // Sidebar: List of Books
                    SpaceBookSidebarView(
                        books: books,
                        selectedBook: selectedBook,
                        onSelect: { book in
                            print("[DEBUG] onSelect called with book: \(book.title)")
                            self.selectedBook = book
                        }
                    )
                    .transition(.move(edge: .leading))
                    
                    // Content: Book Detail
                    SpaceBookDetailView(book: selectedBook)
                        .id(selectedBook.id) // Force refresh
                        .transition(.opacity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                }
                            }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                // Grid Layout (Bookshelf Mode)
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
            
            // Animation Overlay
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
        .onChange(of: selectedBook) { _, newValue in
            onSelectionChange?(newValue != nil)
        }
        .toolbar {
            if selectedBook == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            newBookName = ""
                            showingNewBookAlert = true
                        } label: {
                            Label("新建空间手帐", systemImage: "plus.rectangle.on.folder")
                        }
                        
                        Divider()
                        
                        NavigationLink(destination: RecycleBinView(initialTab: 2)) {
                            Label("垃圾篓", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .alert("新建空间手帐", isPresented: $showingNewBookAlert) {
            TextField("名称", text: $newBookName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                let book = SpaceBookGroup(title: newBookName.isEmpty ? "新空间" : newBookName)
                modelContext.insert(book)
            }
        }
        .alert("删除手帐", isPresented: $showingDeleteBookAlert) {
            Button("取消", role: .cancel) { bookToDelete = nil }
            Button("删除", role: .destructive) {
                if let book = bookToDelete {
                    deleteBook(book)
                    if selectedBook?.id == book.id {
                        selectedBook = nil
                    }
                }
                bookToDelete = nil
            }
        } message: {
            Text("确定要将“\(bookToDelete?.title ?? "此手帐")”移入回收站吗？")
        }
        .alert("重命名手帐", isPresented: $showingRenameBookAlert) {
            TextField("名称", text: $renameBookName)
            Button("取消", role: .cancel) { bookToRename = nil }
            Button("保存") {
                if let book = bookToRename {
                    book.title = renameBookName
                    try? modelContext.save()
                }
                bookToRename = nil
            }
        }
        .photosPicker(isPresented: $showingCoverPicker, selection: $selectedCoverItem, matching: .images)
        .onChange(of: selectedCoverItem) { _, newItem in
            if let newItem, let book = selectedBookForCover {
                updateCover(for: book, with: newItem)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
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
                }
            }
        }
    }
    
    private func deleteBook(_ book: SpaceBookGroup) {
        book.isDeleted = true
        book.deletedAt = Date()
        // Also mark pages as deleted
        for page in book.pages {
            page.isDeleted = true
            page.deletedAt = Date()
        }
        try? modelContext.save()
    }
}

// MARK: - Space Book Grid View
    
    struct SpaceBookGridView: View {
    let books: [SpaceBookGroup]
    let onBookTap: (SpaceBookGroup) -> Void
    let onDelete: (SpaceBookGroup) -> Void
    let onRename: (SpaceBookGroup) -> Void
    let onSetCover: (SpaceBookGroup) -> Void
    var namespace: Namespace.ID?
    var openingBook: SpaceBookGroup?
    
    var body: some View {
        ScrollView {
            if books.isEmpty {
                ContentUnavailableView {
                    Label("暂无空间手帐", systemImage: "cube.transparent")
                } description: {
                    Text("点击右上角 + 创建新的空间手帐")
                }
                .foregroundStyle(.secondary)
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 24)], spacing: 32) {
                    ForEach(books) { book in
                        Button {
                            onBookTap(book)
                        } label: {
                            if book.id == openingBook?.id {
                                Color.clear.frame(width: 160, height: 220)
                            } else {
                                SpaceBookView(book: book, namespace: namespace)
                            }
                        }
                        .buttonStyle(BouncingButtonStyle())
                        .contextMenu {
                                Button {
                                    onRename(book)
                                } label: {
                                    Label("重命名", systemImage: "pencil")
                                }
                                
                                Button {
                                    onSetCover(book)
                                } label: {
                                    Label("设置封面", systemImage: "photo")
                                }
                                
                                Button(role: .destructive) {
                                    onDelete(book)
                                } label: {
                                    Label("删除手帐", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(24)
            }
        }
    }
}

// MARK: - Space Book Detail View

struct SpaceBookDetailView: View {
    @Bindable var book: SpaceBookGroup
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<SpaceBookGroup> { $0.deletedAt == nil }) private var allBooks: [SpaceBookGroup]
    
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
        ScrollView {
            if sortedPages.isEmpty {
                ContentUnavailableView {
                    Label("暂无空间书页", systemImage: "doc.text.image")
                } description: {
                    Text("点击 + 创建新的空间书页")
                }
                .foregroundStyle(.secondary)
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: gridMode.columns, spacing: 16) {
                    ForEach(sortedPages) { page in
                        Group {
                            if isEditing {
                                SpaceOutfitCard(page: page)
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
                            } else {
                                NavigationLink(value: page) {
                                    SpaceOutfitCard(page: page)
                                }
                                .buttonStyle(BouncingButtonStyle())
                                .contextMenu {
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
                            }
                        }
                    }
                }
                .padding(24)
                .animation(.default, value: sortedPages)
            }
        }
        .navigationTitle(book.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    // View Options
                    Menu {
                        Picker("视图", selection: $gridModeValue) {
                            ForEach(GridMode.allCases) { mode in
                                Label(mode.displayName, systemImage: mode.iconName)
                                    .tag(mode.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: gridMode.iconName)
                            .foregroundStyle(.primary)
                    }
                    
                    // Custom Sort Edit Button
                    Button {
                        withAnimation {
                            isEditing.toggle()
                        }
                    } label: {
                        if isEditing {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.pink)
                        } else {
                            Image(systemName: "list.number")
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    // More Actions
                    Menu {
                        Button {
                            showingNewPageAlert = true
                        } label: {
                            Label("新建空间搭配", systemImage: "plus")
                        }
                        
                        Button {
                            showingCoverPicker = true
                        } label: {
                            Label("修改手帐封面", systemImage: "photo")
                        }
                        
                        Divider()
                        
                        NavigationLink(destination: RecycleBinView(initialTab: 2)) {
                            Label("垃圾篓", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .alert("新建空间书页", isPresented: $showingNewPageAlert) {
            TextField("备注", text: $newPageNote)
            Button("取消", role: .cancel) {}
            Button("创建") {
                let newPage = SpaceOutfit(note: newPageNote, book: book)
                newPage.sortIndex = (sortedPages.last?.sortIndex ?? 0) + 1
                modelContext.insert(newPage)
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
    }
    
    // MARK: - Custom Sort
    
    private func movePage(from source: SpaceOutfit, to destination: SpaceOutfit) {
        var pages = sortedPages
        guard let sourceIndex = pages.firstIndex(where: { $0.id == source.id }),
              let destIndex = pages.firstIndex(where: { $0.id == destination.id }) else { return }
        
        if sourceIndex == destIndex { return }
        
        withAnimation {
            let item = pages.remove(at: sourceIndex)
            pages.insert(item, at: destIndex)
            
            // Update sort indices
            for (index, page) in pages.enumerated() {
                page.sortIndex = index
            }
        }
        
        try? modelContext.save()
    }
    
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
        
        // Insert after current
        let pages = sortedPages
        if let index = pages.firstIndex(where: { $0.id == page.id }) {
            newPage.sortIndex = page.sortIndex + 1
            for p in pages where p.sortIndex > page.sortIndex {
                p.sortIndex += 1
            }
        } else {
            newPage.sortIndex = (pages.last?.sortIndex ?? 0) + 1
        }
        
        // Copy 3D scene configuration
        newPage.modelPath = page.modelPath
        newPage.camPosX = page.camPosX
        newPage.camPosY = page.camPosY
        newPage.camPosZ = page.camPosZ
        newPage.lightingIntensity = page.lightingIntensity
        
        modelContext.insert(newPage)
        
        // Copy snapshot image
        if let path = page.snapshotPath,
           let image = ImageManager.shared.loadImage(fileName: path),
           let newPath = ImageManager.shared.saveImage(image, context: modelContext) {
            newPage.snapshotPath = newPath
        }
        
        try? modelContext.save()
    }
    
    private func insertPage(after page: SpaceOutfit) {
        let newPage = SpaceOutfit(note: "新书页", book: book)
        
        // Insert logic: shift everyone after this page by 1
        let pages = sortedPages
        if let index = pages.firstIndex(where: { $0.id == page.id }) {
            newPage.sortIndex = page.sortIndex + 1
            for p in pages where p.sortIndex > page.sortIndex {
                p.sortIndex += 1
            }
        } else {
            newPage.sortIndex = (pages.last?.sortIndex ?? 0) + 1
        }
        
        modelContext.insert(newPage)
    }
    
    private func insertPage(before page: SpaceOutfit) {
        let newPage = SpaceOutfit(note: "新书页", book: book)
        
        let pages = sortedPages
        if let index = pages.firstIndex(where: { $0.id == page.id }) {
            newPage.sortIndex = page.sortIndex
            // Shift everyone from this index onwards
            for p in pages where p.sortIndex >= page.sortIndex {
                p.sortIndex += 1
            }
        } else {
            newPage.sortIndex = (pages.last?.sortIndex ?? 0) + 1
        }
        
        modelContext.insert(newPage)
    }
}

struct SpaceMovePageSheet: View {
    let page: SpaceOutfit
    let currentBook: SpaceBookGroup
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<SpaceBookGroup> { $0.deletedAt == nil }) private var books: [SpaceBookGroup]
    
    var body: some View {
        NavigationStack {
            List(books) { targetBook in
                if targetBook.id != currentBook.id {
                    Button {
                        page.book = targetBook
                        dismiss()
                    } label: {
                        HStack {
                            Text(targetBook.title)
                            Spacer()
                            Text("\(targetBook.pages.filter({ !$0.isDeleted }).count) 页").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("移动到...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct SpaceOutfitCard: View {
    let page: SpaceOutfit
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Snapshot or Placeholder
            ZStack {
                if let path = page.snapshotPath,
                   let image = ImageManager.shared.loadImage(fileName: path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color(uiColor: .systemGray6))
                        .overlay {
                            Image(systemName: "cube.transparent")
                                .font(.largeTitle)
                                .foregroundStyle(.gray)
                        }
                }
            }
            .aspectRatio(3/4, contentMode: .fit)
            .clipped()
            
            // Footer
            VStack(alignment: .leading, spacing: 4) {
                Text(page.note.isEmpty ? "未命名书页" : page.note)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.black)
                
                Text(page.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            .padding(12)
            .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Reorderable Drop Delegate for SpaceOutfit

struct SpaceReorderableDropDelegate: DropDelegate {
    let item: SpaceOutfit
    var pages: [SpaceOutfit]
    var onMove: (SpaceOutfit, SpaceOutfit) -> Void
    
    func dropEntered(info: DropInfo) {
        guard info.hasItemsConforming(to: [.text]) else { return }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.text])
    }
    
    func performDrop(info: DropInfo) -> Bool {
        if let itemProvider = info.itemProviders(for: [.text]).first {
            itemProvider.loadItem(forTypeIdentifier: "public.text", options: nil) { (data, error) in
                if let data = data as? Data, let idString = String(data: data, encoding: .utf8), let uuid = UUID(uuidString: idString) {
                    DispatchQueue.main.async {
                        if let source = pages.first(where: { $0.id == uuid }) {
                            onMove(source, item)
                        }
                    }
                }
            }
            return true
        }
        return false
    }
}

// MARK: - Animation Helpers

/// 3D 空间手帐翻页动画组件 - 复用平面手帐的翻书动画效果
struct SpaceBookOpeningAnimationView: View {
    let book: SpaceBookGroup
    let onFinish: () -> Void
    
    // 动画状态
    @State private var isMovingToCenter = false
    @State private var isOpening = false
    @State private var pagesFlipped: [Bool] = Array(repeating: false, count: 6)
    
    // 书页图片缓存
    @State private var pageImages: [UIImage?] = Array(repeating: nil, count: 6)
    
    // 配置参数
    private let bookWidth: CGFloat = 200
    private let bookHeight: CGFloat = 280
    private let coverColor = Color(hex: "5D4037") // 深棕色封面（空间手帐用深色）
    private let pageColor = Color(hex: "F5F5DC") // 米色纸张
    
    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .opacity(isMovingToCenter ? 1 : 0)
                .animation(.easeIn(duration: 0.5), value: isMovingToCenter)
            
            // 3D 书本容器
            ZStack {
                // 1. 封底
                SpaceBookCoverView(book: book, width: bookWidth, height: bookHeight, color: coverColor)
                
                // 2. 书页 (多层)
                ForEach(0..<6) { index in
                    SpaceBookPageView(width: bookWidth - 10, height: bookHeight - 10, color: pageColor, image: pageImages[index])
                        .rotation3DEffect(
                            .degrees(pagesFlipped[index] ? -175 + Double.random(in: -5...5) : 0),
                            axis: (x: 0.0, y: 1.0, z: 0.0),
                            anchor: .leading,
                            anchorZ: 0,
                            perspective: 0.5
                        )
                        .offset(x: 5, y: 0)
                        .zIndex(Double(6 - index))
                }
                
                // 3. 封面
                SpaceBookCoverView(book: book, width: bookWidth, height: bookHeight, color: coverColor, isFront: true)
                    .rotation3DEffect(
                        .degrees(isOpening ? -180 : 0),
                        axis: (x: 0.0, y: 1.0, z: 0.0),
                        anchor: .leading,
                        anchorZ: 0,
                        perspective: 0.5
                    )
                    .zIndex(10)
            }
            // 整体变换：移动到中心并放大
            .scaleEffect(isMovingToCenter ? 1.5 : 0.2)
            .rotation3DEffect(
                .degrees(isMovingToCenter ? 0 : 45),
                axis: (x: 0.0, y: 1.0, z: 0.0)
            )
            .offset(y: isMovingToCenter ? 0 : 300)
        }
        .onAppear {
            loadPageImages()
            startAnimationSequence()
        }
    }
    
    private func loadPageImages() {
        // 获取书页数据（过滤已删除的，按创建时间倒序）
        let validPages = book.pages.filter { !$0.isDeleted }.sorted { $0.createdAt > $1.createdAt }
        
        // 如果没有书页，直接返回
        if validPages.isEmpty { return }
        
        // 填充 6 张图片
        for i in 0..<6 {
            // 循环使用书页内容，如果书页少于 6 页
            let pageIndex = i % validPages.count
            let page = validPages[pageIndex]
            
            if let snapshotPath = page.snapshotPath,
               let image = ImageManager.shared.loadImage(fileName: snapshotPath) {
                pageImages[i] = image
            }
        }
    }
    
    private func startAnimationSequence() {
        // 1. 移动到中心并放大
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
            isMovingToCenter = true
        }
        
        // 2. 打开封面 (延迟 0.6s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.8)) {
                isOpening = true
            }
        }
        
        // 3. 随机翻页 (延迟 1.2s 开始，每隔 0.15s 翻一页)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            for i in 0..<6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        pagesFlipped[i] = true
                    }
                }
            }
        }
        
        // 4. 动画结束，进入列表 (延迟 2.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            onFinish()
        }
    }
}

// MARK: - 3D Book Animation Subviews for Spatial Book

struct SpaceBookCoverView: View {
    let book: SpaceBookGroup
    let width: CGFloat
    let height: CGFloat
    let color: Color
    var isFront: Bool = false
    
    var body: some View {
        ZStack {
            // Base Cover
            if let coverPath = book.coverImage,
               let image = ImageManager.shared.loadImage(fileName: coverPath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .cornerRadius(4)
            } else {
                Rectangle()
                    .fill(color)
                    .frame(width: width, height: height)
                    .cornerRadius(4)
            }
            
            // Shadow
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                .frame(width: width, height: height)
                .shadow(radius: 5)
            
            // 装饰线条 (仅封面)
            if isFront {
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: width - 20, height: height - 20)
                
                VStack {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.8))
                    
                    Text(book.title)
                        .font(.custom("Didot", size: 20))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        .padding(.top, 8)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            
            // 书脊纹理
            HStack {
                LinearGradient(colors: [.black.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 20)
                Spacer()
            }
        }
        .frame(width: width, height: height)
    }
}

struct SpaceBookPageView: View {
    let width: CGFloat
    let height: CGFloat
    let color: Color
    var image: UIImage? = nil
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(color)
                .frame(width: width, height: height)
                .cornerRadius(2)
                .shadow(color: .black.opacity(0.1), radius: 1, x: 1, y: 0)
            
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width - 8, height: height - 8)
                    .clipped()
                    .cornerRadius(1)
            } else {
                // 空白页纹理
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 20))
                            .foregroundStyle(.gray.opacity(0.3))
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Subviews for Space BookShelf

struct SpaceBookSidebarView: View {
    let books: [SpaceBookGroup]
    let selectedBook: SpaceBookGroup?
    let onSelect: (SpaceBookGroup) -> Void
    
    var body: some View {
        let _ = print("[DEBUG] SpaceBookSidebarView - books count: \(books.count), selectedBook: \(selectedBook?.id.uuidString ?? "nil")")
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                ForEach(books) { book in
                    let _ = print("[DEBUG] Rendering book: \(book.title), id: \(book.id)")
                    SpaceBookView(book: book, isSelected: selectedBook?.id == book.id)
                        .frame(width: 60, height: 80)
                        .scaleEffect(0.4)
                        .frame(width: 60, height: 80)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            print("[DEBUG] Book tapped: \(book.title), id: \(book.id)")
                            withAnimation {
                                onSelect(book)
                            }
                        }
                        .opacity(book.id == selectedBook?.id ? 1.0 : 0.6)
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 10)
        }
        .frame(width: 90)
        .frame(maxHeight: .infinity)
        .background(Color.clear)
        .overlay(
            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(width: 1),
            alignment: .trailing
        )
    }
}

struct SpaceBookView: View {
    let book: SpaceBookGroup
    var namespace: Namespace.ID? = nil
    var isSelected: Bool = false
    
    var body: some View {
        ZStack {
            // Thickness (Pages)
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: .systemGray6))
                    .frame(width: 156, height: 216)
                    .offset(x: CGFloat(index) * 1.5, y: 0)
                    .shadow(color: .black.opacity(0.05), radius: 1, x: 1, y: 0)
            }
            
            // Front Cover Visuals
            SpaceBookCoverVisuals(book: book)
                .overlay(
                    RoundedCorner(radius: 4, corners: [.topRight, .bottomRight])
                        .stroke(Color.accentColor, lineWidth: isSelected ? 4 : 0)
                )
                .frame(width: 160, height: 220)
                .rotation3DEffect(.degrees(-8), axis: (0, 1, 0), anchor: .leading, perspective: 0.5)
        }
        .padding(.trailing, 10) // Reserve space for 3D thickness
        .if(namespace != nil) { view in
            view.matchedGeometryEffect(id: "space_book_\(book.id)", in: namespace!)
        }
    }
}

struct SpaceBookCoverVisuals: View {
    let book: SpaceBookGroup
    
    var coverImage: UIImage? {
        if let coverPath = book.coverImage,
           let image = ImageManager.shared.loadImage(fileName: coverPath) {
            return image
        }
        // Fallback to first page
        if let firstPage = book.pages.filter({ !$0.isDeleted }).sorted(by: { $0.createdAt > $1.createdAt }).first,
           let snapshotPath = firstPage.snapshotPath,
           let image = ImageManager.shared.loadImage(fileName: snapshotPath) {
            return image
        }
        return nil
    }
    
    var body: some View {
        ZStack {
            Color.white
            
            if let image = coverImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 160, height: 220)
                    .clipped()
            } else {
                VStack {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(book.title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            
            // Title Overlay if has image
            if coverImage != nil {
                VStack {
                    Spacer()
                    ZStack {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .frame(height: 50)
                        Text(book.title)
                            .font(.headline)
                            .lineLimit(2)
                            .padding(.horizontal, 8)
                    }
                }
            }
            
            // Spine Hint (Left edge)
            HStack {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(width: 6)
                Spacer()
            }
        }
        .clipShape(RoundedCorner(radius: 4, corners: [.topRight, .bottomRight]))
    }
}
