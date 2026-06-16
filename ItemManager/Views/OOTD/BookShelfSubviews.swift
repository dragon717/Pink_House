import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Subviews for BookShelf

struct BookSidebarView: View {
    let books: [BookGroup]
    let selectedBook: BookGroup?
    let onSelect: (BookGroup) -> Void
    var isEditing: Bool = false
    @State private var draggingItem: BookGroup?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                ForEach(books, id: \.persistentModelID) { book in
                    if isEditing {
                        // Editing Mode: Draggable
                        editingBookCell(for: book)
                    } else {
                        // Normal Mode: Tappable
                        normalBookCell(for: book)
                    }
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 10)
        }
        .frame(width: 90)
        .frame(maxHeight: .infinity)
        // Transparent UI as requested
        .background(colorScheme == .dark ? Color(uiColor: .systemGray6).opacity(0.5) : Color.clear)
        .overlay(
            Rectangle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.05))
                .frame(width: 1),
            alignment: .trailing
        )
    }
    
    @ViewBuilder
    private func normalBookCell(for book: BookGroup) -> some View {
        ThreeDBookView(book: book, isSelected: selectedBook?.persistentModelID == book.persistentModelID)
            .frame(width: 60, height: 80) // Small thumbnail
            .scaleEffect(0.4) // Visual scaling
            .frame(width: 60, height: 80) // Clip frame
            .onTapGesture {
                withAnimation {
                    onSelect(book)
                }
            }
            .opacity(book.persistentModelID == selectedBook?.persistentModelID ? 1.0 : 0.6)
    }
    
    @ViewBuilder
    private func editingBookCell(for book: BookGroup) -> some View {
        ThreeDBookView(book: book, isSelected: false)
            .frame(width: 60, height: 80)
            .scaleEffect(0.4)
            .frame(width: 60, height: 80)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(2)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .offset(x: -5, y: 5)
            }
            .onDrag {
                self.draggingItem = book
                return NSItemProvider(object: String(describing: book.persistentModelID) as NSString)
            }
            .onDrop(of: [.text], delegate: BookSidebarReorderableDropDelegate(item: book, books: books, draggingItem: $draggingItem))
    }
}

// MARK: - Book Sidebar Reorderable Drop Delegate

struct BookSidebarReorderableDropDelegate: DropDelegate {
    let item: BookGroup
    let books: [BookGroup]
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
                    // Update sort indices
                    let minIndex = min(sourceIndex, destinationIndex)
                    let maxIndex = max(sourceIndex, destinationIndex)

                    if sourceIndex < destinationIndex {
                        // Moving down
                        for i in minIndex...maxIndex {
                            if i == sourceIndex {
                                books[i].sortIndex = destinationIndex
                            } else {
                                books[i].sortIndex -= 1
                            }
                            books[i].lastModified = Date()
                        }
                    } else {
                        // Moving up
                        for i in minIndex...maxIndex {
                            if i == sourceIndex {
                                books[i].sortIndex = destinationIndex
                            } else {
                                books[i].sortIndex += 1
                            }
                            books[i].lastModified = Date()
                        }
                    }
                }
            }
        }
        return true
    }
}

struct BookGridView: View {
    let books: [BookGroup]
    @Binding var selectedBook: BookGroup?
    @Binding var selectedBookForCover: BookGroup?
    @Binding var showingCoverPicker: Bool
    let onDelete: (BookGroup) -> Void
    let onRename: (BookGroup) -> Void
    var namespace: Namespace.ID?
    var onBookTap: ((BookGroup) -> Void)?
    var openingBook: BookGroup?
    
    // 第一个非默认手帐（用于新手引导高亮）
    private var firstNonDefaultBook: BookGroup? {
        books.first { $0.title != "默认手帐" }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 24)], spacing: 32) {
                ForEach(books, id: \.persistentModelID) { book in
                    Button {
                        if let onBookTap = onBookTap {
                            onBookTap(book)
                        } else {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                selectedBook = book
                            }
                        }
                    } label: {
                        if book.persistentModelID == openingBook?.persistentModelID {
                            // 占位符，保持布局但不显示内容，移除 matchedGeometryEffect
                            Color.clear
                                .frame(width: 160, height: 220)
                        } else {
                            ThreeDBookView(book: book, namespace: namespace)
                        }
                    }
                    .buttonStyle(BouncingButtonStyle())
                    .captureGuideTarget(guideTargetKey(for: book))
                    .contextMenu {
                        Button {
                            onRename(book)
                        } label: {
                            Label("重命名".appLocalized, systemImage: "pencil")
                        }

                        Button {
                            selectedBookForCover = book
                            showingCoverPicker = true
                        } label: {
                            Label("修改封面".appLocalized, systemImage: "photo")
                        }

                        Button(role: .destructive) {
                            onDelete(book)
                        } label: {
                            Label("删除手帐".appLocalized, systemImage: "trash")
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    /// 根据手帐返回对应的高亮目标键
    private func guideTargetKey(for book: BookGroup) -> GuideTargetKey? {
        // 第一个非默认手帐（用于 Step 3 引导）
        if book.persistentModelID == firstNonDefaultBook?.persistentModelID {
            return .ootdFirstNonDefaultBookCard
        }
        // 第一个手帐（用于其他场景）
        if book.persistentModelID == books.first?.persistentModelID {
            return .ootdFirstBookCard
        }
        return nil
    }
}

struct ThreeDBookView: View {
    let book: BookGroup
    var namespace: Namespace.ID? = nil
    var isSelected: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Thickness (Pages)
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(colorScheme == .dark ? Color(uiColor: .systemGray5) : Color(uiColor: .systemGray6))
                    .frame(width: 156, height: 216)
                    .offset(x: CGFloat(index) * 1.5, y: 0)
                    .shadow(color: .black.opacity(0.05), radius: 1, x: 1, y: 0)
            }
            
            // Front Cover Visuals
            BookCoverVisuals(book: book)
                .overlay(
                    RoundedCorner(radius: 4, corners: [.topRight, .bottomRight])
                        .stroke(Color.accentColor, lineWidth: isSelected ? 4 : 0)
                )
                .frame(width: 160, height: 220)
                .rotation3DEffect(.degrees(-8), axis: (0, 1, 0), anchor: .leading, perspective: 0.5)
        }
        .padding(.trailing, 10) // Reserve space for 3D thickness
        .if(namespace != nil) { view in
            view.matchedGeometryEffect(id: "book_\(String(describing: book.persistentModelID))", in: namespace!)
        }
    }
}

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct BookCoverVisuals: View {
    let book: BookGroup
    @Environment(\.colorScheme) private var colorScheme
    
    var coverImage: UIImage? {
        if let coverPath = book.coverImage,
           let image = ImageManager.shared.loadImage(fileName: coverPath) {
            return image
        }
        // Fallback to first page
        if let firstPage = (book.pages ?? []).filter({ !$0.isDeleted }).sorted(by: { $0.createdAt > $1.createdAt }).first,
           firstPage.shouldUseStoredSnapshot,
           let snapshotPath = firstPage.snapshotPath,
           let image = ImageManager.shared.loadImage(fileName: snapshotPath) {
            return image
        }
        return nil
    }
    
    var body: some View {
        ZStack {
            colorScheme == .dark ? Color(uiColor: .systemGray6) : Color.white
            
            if let image = coverImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 160, height: 220)
                    .clipped()
            } else {
                VStack {
                    Image(systemName: "book.closed")
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
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1))
                    .frame(width: 6)
                Spacer()
            }
        }
        .frame(width: 160, height: 220)
        .background(colorScheme == .dark ? Color(uiColor: .systemGray6) : Color.white)
        .cornerRadius(4, corners: [.topRight, .bottomRight])
        .overlay(ThemeSkinBookCoverFrame(cornerRadius: 4))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.2), radius: 5, x: 5, y: 5)
    }
}

struct BouncingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(), value: configuration.isPressed)
    }
}
