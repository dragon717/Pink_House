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
    @State private var isSidebarVisible = false
    
    // Custom Sort Editing
    @Binding var isEditing: Bool
    @Binding var isBatchEditingBooks: Bool
    @Binding var selectedBookIDs: Set<UUID>
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
            LiquidBackground(themeSkinWallpaperContext: .journal, includeThemeSkinStickers: false)
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
                        .id(selectedBook.persistentModelID)
                        .transition(.opacity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationBarBackButtonHidden(true) // 隐藏系统返回按钮，使用自定义返回按钮
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                // Grid Layout (Bookshelf Mode)
                bookGridContent
            }
        }
        .fullScreenCover(isPresented: openingAnimationPresented) {
            if let book = openingBook {
                BookOpeningAnimationView(book: book) {
                    selectedBook = book
                    openingBook = nil
                }
                .presentationBackground(.clear)
            }
        }
        .onChange(of: isEditing) { _, newValue in
            if newValue {
                editableBooks = books
            } else {
                // Save sort order
                for (index, book) in editableBooks.enumerated() {
                    book.sortIndex = index
                    book.lastModified = Date()
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

    private var openingAnimationPresented: Binding<Bool> {
        Binding(
            get: { openingBook != nil },
            set: { isPresented in
                if !isPresented {
                    openingBook = nil
                }
            }
        )
    }
    
    @ViewBuilder
    private var bookGridContent: some View {
        Group {
            if isEditing {
                ScrollView {
                    // Editing Mode: Draggable Grid
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 24)], spacing: 32) {
                        ForEach(editableBooks, id: \.persistentModelID) { book in
                            editingBookCell(for: book)
                        }
                    }
                    .padding(24)
                    .animation(.default, value: editableBooks)
                }
                // 底部悬浮 Dock 避让（编辑态）。正常态走 BookGridView 自己的避让，不要在此 Group 上加，会重复。
                .avoidingBottomDock()
            } else if isBatchEditingBooks {
                batchBookGridContent
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
        .alert("重命名手帐".appLocalized, isPresented: $showingRenameBookAlert) {
            TextField("名称".appLocalized, text: $renameBookName)
            Button("取消".appLocalized, role: .cancel) { bookToRename = nil }
            Button("保存".appLocalized) {
                if let book = bookToRename {
                    book.title = renameBookName
                    book.lastModified = Date()
                    try? modelContext.save()
                }
                bookToRename = nil
            }
        }
    }

    private var batchBookGridContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 24)], spacing: 32) {
                ForEach(books, id: \.persistentModelID) { book in
                    batchEditingBookCell(for: book)
                }
            }
            .padding(24)
            .animation(.default, value: selectedBookIDs)
        }
        // 底部悬浮 Dock 避让（批量态）。
        .avoidingBottomDock()
    }

    private func batchEditingBookCell(for book: BookGroup) -> some View {
        let isSelected = selectedBookIDs.contains(book.id)

        return ThreeDBookView(book: book, namespace: namespace)
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
    private func editingBookCell(for book: BookGroup) -> some View {
        ThreeDBookView(book: book, namespace: namespace)
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
                return NSItemProvider(object: String(describing: book.persistentModelID) as NSString)
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

        DispatchQueue.main.async {
            if let sourceIndex = books.firstIndex(where: { $0.persistentModelID == draggingItem.persistentModelID }),
               let destinationIndex = books.firstIndex(where: { $0.persistentModelID == item.persistentModelID }) {
                if sourceIndex != destinationIndex {
                    withAnimation {
                        let item = books.remove(at: sourceIndex)
                        books.insert(item, at: destinationIndex)
                    }
                }
            }
        }
        return true
    }
}
