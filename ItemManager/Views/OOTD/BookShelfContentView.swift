//
//  BookShelfContentView.swift
//  ItemManager
//
//  书架内容视图组件
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BookShelfContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Binding var viewMode: BookShelfView.ViewMode
    @Binding var selectedBook: BookGroup?
    @Binding var isSpatialBookSelected: Bool
    @Binding var openingBook: BookGroup?
    @Binding var bookToDelete: BookGroup?
    @Binding var showingDeleteBookAlert: Bool
    @Binding var selectedBookForCover: BookGroup?
    @Binding var showingCoverPicker: Bool
    
    let books: [BookGroup]
    let namespace: Namespace.ID
    let onBookTap: (BookGroup) -> Void
    let onDelete: (BookGroup) -> Void
    
    // Sidebar visibility for planar mode
    @State private var isSidebarVisible = true
    
    // Custom Sort Editing
    @Binding var isEditing: Bool
    @State private var editableBooks: [BookGroup] = []
    @State private var draggingItem: BookGroup?
    
    // Rename Book
    @State private var bookToRename: BookGroup?
    @State private var showingRenameBookAlert = false
    @State private var renameBookName = ""
    
    var body: some View {
        Group {
            if viewMode == .planar {
                planarContent
            } else {
                SpatialBookShelfView(onSelectionChange: { isSelected in
                    isSpatialBookSelected = isSelected
                })
            }
        }
    }
    
    @ViewBuilder
    private var planarContent: some View {
        ZStack {
            // Global Background
            LiquidBackground()
                .ignoresSafeArea()
            
            if let selectedBook = selectedBook {
                // Split Layout (Detail Mode) - 类似空间书页
                HStack(spacing: 0) {
                    // Sidebar: List of Books (可手动隐藏)
                    if isSidebarVisible {
                        BookSidebarView(
                            books: isEditing ? editableBooks : books,
                            selectedBook: selectedBook,
                            onSelect: { book in
                                if !isEditing {
                                    self.selectedBook = book
                                }
                            },
                            isEditing: isEditing
                        )
                        .transition(.move(edge: .leading))
                    }
                    
                    // Content: Book Detail
                    BookDetailView(
                        book: selectedBook,
                        navigationPath: .constant(NavigationPath()),
                        isSidebarVisible: $isSidebarVisible,
                        onBack: {
                            self.selectedBook = nil
                        }
                    )
                        .id(selectedBook.id)
                        .transition(.opacity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationBarBackButtonHidden(true) // 隐藏系统返回按钮，使用自定义返回按钮
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                // Grid Layout (Bookshelf Mode)
                bookGridContent
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
        .onChange(of: isEditing) { _, newValue in
            if newValue {
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
        }
    }
    
    @ViewBuilder
    private var bookGridContent: some View {
        ScrollView {
            if isEditing {
                // Editing Mode: Draggable Grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 24)], spacing: 32) {
                    ForEach(editableBooks) { book in
                        editingBookCell(for: book)
                    }
                }
                .padding(24)
                .animation(.default, value: editableBooks)
            } else {
                // Normal Mode: Navigation Grid
                BookGridView(
                    books: books,
                    selectedBook: $selectedBook,
                    selectedBookForCover: $selectedBookForCover,
                    showingCoverPicker: $showingCoverPicker,
                    onDelete: onDelete,
                    onRename: { book in
                        bookToRename = book
                        renameBookName = book.title
                        showingRenameBookAlert = true
                    },
                    namespace: namespace,
                    onBookTap: onBookTap,
                    openingBook: openingBook
                )
            }
        }
        .transition(.opacity)
        .opacity(openingBook == nil ? 1 : 0)
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
    }
    
    @ViewBuilder
    private func editingBookCell(for book: BookGroup) -> some View {
        ThreeDBookView(book: book, namespace: namespace)
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
                self.draggingItem = book
                return NSItemProvider(object: book.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: BookReorderableDropDelegate(item: book, books: $editableBooks, draggingItem: $draggingItem))
    }
}

// MARK: - Book Reorderable Drop Delegate

struct BookReorderableDropDelegate: DropDelegate {
    let item: BookGroup
    @Binding var books: [BookGroup]
    @Binding var draggingItem: BookGroup?
    
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


