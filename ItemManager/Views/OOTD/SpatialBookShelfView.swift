
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
                HStack(spacing: 0) {
                    // Sidebar: List of Books
                    SpaceBookSidebarView(
                        books: books,
                        selectedBook: selectedBook,
                        onSelect: { book in
                            self.selectedBook = book
                        }
                    )
                    .transition(.move(edge: .leading))
                    
                    // Content: Book Detail
                    SpaceBookDetailView(book: selectedBook)
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
                                        Text("手帐书架")
                                    }
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                                }
                            }
                            
                            ToolbarItem(placement: .topBarTrailing) {
                                Menu {
                                    Button {
                                        bookToRename = selectedBook
                                        renameBookName = selectedBook.title
                                        showingRenameBookAlert = true
                                    } label: {
                                        Label("重命名", systemImage: "pencil")
                                    }
                                    
                                    Button(role: .destructive) {
                                        bookToDelete = selectedBook
                                        showingDeleteBookAlert = true
                                    } label: {
                                        Label("删除手帐", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                }
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
                    }
                }
                .zIndex(100)
            }
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
                            .foregroundStyle(.white)
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
    let book: SpaceBookGroup
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<SpaceBookGroup> { $0.deletedAt == nil }) private var allBooks: [SpaceBookGroup]
    
    // Sort pages by creation date
    var sortedPages: [SpaceOutfit] {
        book.pages.filter { !$0.isDeleted }.sorted { $0.createdAt > $1.createdAt }
    }
    
    @State private var showingNewPageAlert = false
    @State private var newPageNote = ""
    
    // Move Page
    @State private var pageToMove: SpaceOutfit?
    @State private var showingMoveSheet = false
    
    // Cover Picker
    @State private var showingCoverPicker = false
    @State private var selectedCoverItem: PhotosPickerItem?
    
    // Grid Layout
    enum GridMode: String, CaseIterable, Identifiable {
        case single = "单列"
        case double = "双列"
        case triple = "三列"
        var id: Self { self }
        
        var columns: [GridItem] {
            switch self {
            case .single: return [GridItem(.flexible())]
            case .double: return [GridItem(.adaptive(minimum: 160), spacing: 24)]
            case .triple: return [GridItem(.adaptive(minimum: 100), spacing: 16)]
            }
        }
    }
    @State private var gridMode: GridMode = .double
    
    // Editing Mode
    @State private var isEditing = false
    
    var body: some View {
        ZStack {
            // Background
            LiquidBackground()
                .ignoresSafeArea()
            
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
                    LazyVGrid(columns: gridMode.columns, spacing: gridMode == .triple ? 16 : 32) {
                        ForEach(sortedPages) { page in
                            NavigationLink(value: page) {
                                SpaceOutfitCard(page: page)
                            }
                            .buttonStyle(BouncingButtonStyle())
                            .disabled(isEditing) // Disable navigation in edit mode
                            .overlay(alignment: .topTrailing) {
                                if isEditing {
                                    Button {
                                        deletePage(page)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                            .background(Circle().fill(.white))
                                            .font(.title2)
                                    }
                                    .offset(x: 8, y: -8)
                                }
                            }
                            .contextMenu {
                                if !isEditing {
                                    Button {
                                        pageToMove = page
                                        showingMoveSheet = true
                                    } label: {
                                        Label("移动到...", systemImage: "folder")
                                    }
                                    
                                    Button(role: .destructive) {
                                        deletePage(page)
                                    } label: {
                                        Label("删除书页", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle(book.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    // View Options
                    Menu {
                        Picker("视图", selection: $gridMode) {
                            ForEach(GridMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: iconForGridMode(mode)).tag(mode)
                            }
                        }
                        
                        Button {
                            withAnimation {
                                isEditing.toggle()
                            }
                        } label: {
                            Label(isEditing ? "完成" : "整理书页", systemImage: isEditing ? "checkmark" : "arrow.up.arrow.down")
                        }
                    } label: {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "square.grid.2x2")
                            .foregroundStyle(.white)
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
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .alert("新建空间书页", isPresented: $showingNewPageAlert) {
            TextField("备注", text: $newPageNote)
            Button("取消", role: .cancel) {}
            Button("创建") {
                let page = SpaceOutfit(note: newPageNote, book: book)
                modelContext.insert(page)
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
    
    private func iconForGridMode(_ mode: GridMode) -> String {
        switch mode {
        case .single: return "rectangle.grid.1x2"
        case .double: return "square.grid.2x2"
        case .triple: return "square.grid.3x3"
        }
    }
    
    private func deletePage(_ page: SpaceOutfit) {
        page.isDeleted = true
        page.deletedAt = Date()
        try? modelContext.save()
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
                        .frame(height: 200)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(uiColor: .systemGray6))
                        .frame(height: 200)
                        .overlay {
                            Image(systemName: "cube.transparent")
                                .font(.largeTitle)
                                .foregroundStyle(.gray)
                        }
                }
            }
            .frame(height: 200)
            
            // Footer
            VStack(alignment: .leading, spacing: 4) {
                Text(page.note.isEmpty ? "未命名书页" : page.note)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                Text(page.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Animation Helpers

struct SpaceBookOpeningAnimationView: View {
    let book: SpaceBookGroup
    let onFinish: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    
    var body: some View {
        SpaceBookView(book: book)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    scale = 3.0
                    opacity = 0.0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    onFinish()
                }
            }
    }
}

// MARK: - Subviews for Space BookShelf

struct SpaceBookSidebarView: View {
    let books: [SpaceBookGroup]
    let selectedBook: SpaceBookGroup?
    let onSelect: (SpaceBookGroup) -> Void
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                ForEach(books) { book in
                    SpaceBookView(book: book, isSelected: selectedBook?.id == book.id)
                        .frame(width: 60, height: 80) // Small thumbnail
                        .scaleEffect(0.4) // Visual scaling
                        .frame(width: 60, height: 80) // Clip frame
                        .onTapGesture {
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
