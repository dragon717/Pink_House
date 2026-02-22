
import SwiftUI
import SwiftData

struct OOTDSidebarView: View {
    @Binding var isVisible: Bool
    @Binding var currentBook: BookGroup?
    @Binding var currentOutfit: Outfit?
    
    @Query(filter: #Predicate<BookGroup> { $0.deletedAt == nil }, sort: \BookGroup.createdAt, order: .reverse) private var books: [BookGroup]
    @Environment(\.modelContext) private var modelContext
    
    var onAdd: (String) -> Void
    var onDelete: (Outfit) -> Void
    
    @State private var expandedBookIDs: Set<UUID> = []
    @State private var showingNewBookAlert = false
    @State private var newBookName = ""
    @State private var showingTrash = false
    
    // Delete Book State
    @State private var bookToDelete: BookGroup?
    @State private var showingDeleteBookAlert = false
    
    // Rename Book State
    @State private var bookToRename: BookGroup?
    @State private var showingRenameBookAlert = false
    @State private var renameBookName = ""
    
    // Move to New Book State
    @State private var outfitToMove: Outfit?
    @State private var showingMoveToNewBookAlert = false
    @State private var newBookNameForMove = ""
    
    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                // Header Area
                HStack {
                    Text("穿搭手帐")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    // Add Book Button
                    Button {
                        newBookName = ""
                        showingNewBookAlert = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 18))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // New Outfit Menu (Create in current book)
                        Menu {
                            Button { onAdd("mannequin") } label: { Label("人台画布", systemImage: "tshirt") }
                            Button { onAdd("blank") } label: { Label("空白画布", systemImage: "square.dashed") }
                            Button { onAdd("custom") } label: { Label("自定义图片", systemImage: "photo") }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.1))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                                Text("新建搭配书页")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        
                        // Books List
                        if books.isEmpty {
                            ContentUnavailableView("暂无手帐本", systemImage: "book.closed")
                                .padding(.top, 40)
                        } else {
                            ForEach(books) { book in
                                BookGroupView(
                                    book: book,
                                    allBooks: books,
                                    isExpanded: expandedBookIDs.contains(book.id),
                                    currentOutfit: $currentOutfit,
                                    currentBook: $currentBook,
                                    onToggle: {
                                        withAnimation {
                                            if expandedBookIDs.contains(book.id) {
                                                expandedBookIDs.remove(book.id)
                                            } else {
                                                expandedBookIDs.insert(book.id)
                                                currentBook = book
                                            }
                                        }
                                    },
                                    onDeleteOutfit: onDelete,
                                    onMoveOutfit: { outfit, targetBook in
                                        moveOutfit(outfit, to: targetBook)
                                    },
                                    onMoveToNewBook: { outfit in
                                        outfitToMove = outfit
                                        newBookNameForMove = ""
                                        showingMoveToNewBookAlert = true
                                    },
                                    onDeleteBook: {
                                        bookToDelete = book
                                        showingDeleteBookAlert = true
                                    },
                                    onRenameBook: {
                                        bookToRename = book
                                        renameBookName = book.title
                                        showingRenameBookAlert = true
                                    }
                                )
                            }
                        }
                    }
                    .padding(.bottom, 80) // Space for Trash Button
                }
                .scrollIndicators(.hidden)
                
                // Trash Button Area
                VStack {
                    Divider()
                    Button {
                        showingTrash = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("回收站")
                            Spacer()
                        }
                        .padding()
                        .foregroundStyle(.secondary)
                    }
                }
                .background(Color(uiColor: .systemBackground))
            }
            .frame(width: 280)
            .background(Color(uiColor: .systemBackground))
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 1),
                    alignment: .trailing
            )
            .transition(.move(edge: .leading).combined(with: .opacity))
            // Alerts
            .alert("新建手帐本", isPresented: $showingNewBookAlert) {
                TextField("名称", text: $newBookName)
                Button("取消", role: .cancel) {}
                Button("创建") {
                    let book = BookGroup(title: newBookName.isEmpty ? "新书本" : newBookName)
                    modelContext.insert(book)
                    currentBook = book
                    expandedBookIDs.insert(book.id)
                }
            }
            .alert("删除手帐本", isPresented: $showingDeleteBookAlert, presenting: bookToDelete) { book in
                Button("删除", role: .destructive) {
                    deleteBook(book)
                }
                Button("取消", role: .cancel) {}
            } message: { book in
                Text("确定要删除“\(book.title)”吗？里面的书页也会一同移入回收站。")
            }
            .alert("重命名", isPresented: $showingRenameBookAlert) {
                TextField("名称", text: $renameBookName)
                Button("取消", role: .cancel) {}
                Button("确定") {
                    if let book = bookToRename {
                        book.title = renameBookName
                        try? modelContext.save()
                    }
                }
            }
            .alert("移动到新手帐本", isPresented: $showingMoveToNewBookAlert) {
                TextField("新书本名称", text: $newBookNameForMove)
                Button("取消", role: .cancel) {}
                Button("创建并移动") {
                    let newBook = BookGroup(title: newBookNameForMove.isEmpty ? "新书本" : newBookNameForMove)
                    modelContext.insert(newBook)
                    
                    if let outfit = outfitToMove {
                        moveOutfit(outfit, to: newBook)
                        currentOutfit = outfit
                    }
                    
                    expandedBookIDs.insert(newBook.id)
                    currentBook = newBook
                }
            }
            .sheet(isPresented: $showingTrash) {
                RecycleBinView() // We need to update this view
            }
        }
    }
    
    private func deleteBook(_ book: BookGroup) {
        // Soft delete book
        book.isDeleted = true
        book.deletedAt = Date()
        book.lastModified = Date()

        // Also soft delete all pages?
        // Logic: If we delete a book, pages should "disappear" from active view.
        // We can either mark them deleted, OR rely on the fact that if book is deleted, we don't fetch it.
        // But the requirement says "recover individually or as group".
        // So marking pages as deleted is better for consistency if we query "all deleted outfits".
        for page in book.pages ?? [] {
            page.isDeleted = true
            page.deletedAt = Date()
            page.lastModified = Date()
        }

        do {
            try modelContext.save()

            // 记录删除到 DeleteTracker，防止iCloud同步覆盖
            DeleteTracker.shared.recordDeletedBookGroup(id: book.id)
            for page in book.pages ?? [] {
                DeleteTracker.shared.recordDeletedOutfit(id: page.id)
            }
        } catch {
            print("OOTDSidebarView: Failed to save deletion: \(error)")
        }

        if currentBook?.id == book.id {
            currentBook = nil
            currentOutfit = nil
        }
    }
    
    private func moveOutfit(_ outfit: Outfit, to targetBook: BookGroup) {
        withAnimation {
            outfit.book = targetBook
            try? modelContext.save()
        }
    }
}

struct BookGroupView: View {
    let book: BookGroup
    let allBooks: [BookGroup]
    let isExpanded: Bool
    @Binding var currentOutfit: Outfit?
    @Binding var currentBook: BookGroup?
    
    var onToggle: () -> Void
    var onDeleteOutfit: (Outfit) -> Void
    var onMoveOutfit: (Outfit, BookGroup) -> Void
    var onMoveToNewBook: (Outfit) -> Void
    var onDeleteBook: () -> Void
    var onRenameBook: () -> Void
    
    // We need to sort pages
    var sortedPages: [Outfit] {
        (book.pages ?? []).filter { !$0.isDeleted }.sorted { $0.createdAt > $1.createdAt }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Book Header
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isExpanded ? "book.fill" : "book.closed.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 18))
                    
                    Text(book.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .rotationEffect(Angle(degrees: isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(currentBook?.id == book.id ? Color.accentColor.opacity(0.05) : Color.clear)
                )
            }
            .contextMenu {
                Button(action: onRenameBook) {
                    Label("重命名", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDeleteBook) {
                    Label("删除", systemImage: "trash")
                }
            }
            .padding(.horizontal, 8)
            
            // Pages List
            if isExpanded {
                if sortedPages.isEmpty {
                    Text("暂无书页")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(sortedPages) { outfit in
                            OutfitCard(
                                outfit: outfit,
                                isSelected: currentOutfit?.id == outfit.id,
                                onDelete: {
                                    onDeleteOutfit(outfit)
                                }
                            )
                            .contextMenu {
                                Menu {
                                    Button {
                                        onMoveToNewBook(outfit)
                                    } label: {
                                        Label("新建手帐本...", systemImage: "plus.rectangle.on.folder")
                                    }
                                    
                                    if allBooks.count > 1 {
                                        Divider()
                                    }
                                    
                                    ForEach(allBooks) { targetBook in
                                        if targetBook.id != book.id {
                                            Button(targetBook.title) {
                                                onMoveOutfit(outfit, targetBook)
                                            }
                                        }
                                    }
                                } label: {
                                    Label("移动到...", systemImage: "folder")
                                }
                                
                                Button(role: .destructive) {
                                    onDeleteOutfit(outfit)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .onTapGesture {
                                currentOutfit = outfit
                                currentBook = book
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
}

struct OutfitCard: View {
    let outfit: Outfit
    let isSelected: Bool
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 12) {
                // Thumbnail
                Group {
                    if let snapshotPath = outfit.snapshotPath,
                       let uiImage = ImageManager.shared.loadImage(fileName: snapshotPath) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color(uiColor: .tertiarySystemFill)
                            Image(systemName: "tshirt")
                                .font(.system(size: 24))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(outfit.note.isEmpty ? "未命名书页" : outfit.note)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(outfit.createdAt.formatted(date: .numeric, time: .shortened))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Selection Indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                        .padding(.trailing, 8)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            
            // Delete Button (Top Right corner) - keep this for quick action, or remove since context menu has it?
            // User requested visual metaphor. Let's keep it but maybe subtler.
            // Or remove it to make it look more like a book page and rely on context menu/swipe.
            // But swipe in LazyVStack is tricky.
            // I'll keep the button for now as it's existing behavior.
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.red.gradient)
                    .clipShape(Circle())
                    .shadow(color: .red.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            .offset(x: 8, y: -8)
        }
    }
}
