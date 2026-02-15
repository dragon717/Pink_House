//
//  BookShelfContentView.swift
//  ItemManager
//
//  书架内容视图组件
//

import SwiftUI
import SwiftData

struct BookShelfContentView: View {
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
                // Split Layout (Detail Mode)
                HStack(spacing: 0) {
                    // Sidebar: List of Books (可隐藏)
                    if isSidebarVisible {
                        BookSidebarView(
                            books: books,
                            selectedBook: selectedBook,
                            onSelect: { book in
                                self.selectedBook = book
                            }
                        )
                        .transition(.move(edge: .leading))
                    }
                    
                    // Content: Book Detail
                    BookDetailView(
                        book: selectedBook,
                        navigationPath: .constant(NavigationPath()),
                        isSidebarVisible: $isSidebarVisible
                    )
                        .id(selectedBook.id)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                // Grid Layout (Bookshelf Mode)
                BookGridView(
                    books: books,
                    selectedBook: $selectedBook,
                    selectedBookForCover: $selectedBookForCover,
                    showingCoverPicker: $showingCoverPicker,
                    onDelete: onDelete,
                    namespace: namespace,
                    onBookTap: onBookTap,
                    openingBook: openingBook
                )
                .transition(.opacity)
                .opacity(openingBook == nil ? 1 : 0)
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
}
