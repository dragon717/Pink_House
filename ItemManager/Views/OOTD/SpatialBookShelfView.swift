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

    // Sidebar visibility
    @State private var isSidebarVisible = true

    var body: some View {
        ZStack {
            // Background
            LiquidBackground()
                .ignoresSafeArea()

            if let selectedBook = selectedBook {
                // Split Layout (Detail Mode)
                let _ = print("[DEBUG] Detail mode - selectedBook: \(selectedBook.title), books count: \(books.count)")
                HStack(spacing: 0) {
                    // Sidebar: List of Books (可手动隐藏)
                    if isSidebarVisible {
                        SpaceBookSidebarView(
                            books: books,
                            selectedBook: selectedBook,
                            onSelect: { book in
                                print("[DEBUG] onSelect called with book: \(book.title)")
                                self.selectedBook = book
                            }
                        )
                        .transition(.move(edge: .leading))
                    }

                    // Content: Book Detail
                    SpaceBookDetailView(
                        book: selectedBook,
                        isSidebarVisible: $isSidebarVisible
                    )
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
                                    Image(systemName: "chevron.left")
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
            Text("确定要将「\(bookToDelete?.title ?? "此手帐")」移入回收站吗？")
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
