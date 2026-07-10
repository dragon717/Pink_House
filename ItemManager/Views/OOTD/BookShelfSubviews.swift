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
                ForEach(books) { book in
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
        ThreeDBookView(book: book, isSelected: selectedBook?.id == book.id)
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
                return NSItemProvider(object: book.id.uuidString as NSString)
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
        
        if let itemProvider = info.itemProviders(for: [.text]).first {
            itemProvider.loadItem(forTypeIdentifier: "public.text", options: nil) { (data, error) in
                if let data = data as? Data,
                   let idString = String(data: data, encoding: .utf8),
                   let uuid = UUID(uuidString: idString) {
                    DispatchQueue.main.async {
                        if let sourceIndex = books.firstIndex(where: { $0.id == uuid }),
                           let destinationIndex = books.firstIndex(where: { $0.id == item.id }) {
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
                                    }
                                } else {
                                    // Moving up
                                    for i in minIndex...maxIndex {
                                        if i == sourceIndex {
                                            books[i].sortIndex = destinationIndex
                                        } else {
                                            books[i].sortIndex += 1
                                        }
                                    }
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
                ForEach(books) { book in
                    Button {
                        if let onBookTap = onBookTap {
                            onBookTap(book)
                        } else {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                selectedBook = book
                            }
                        }
                    } label: {
                        if book.id == openingBook?.id {
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
                            Label("重命名", systemImage: "pencil")
                        }

                        Button {
                            selectedBookForCover = book
                            showingCoverPicker = true
                        } label: {
                            Label("修改封面", systemImage: "photo")
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

    /// 根据手帐返回对应的高亮目标键
    private func guideTargetKey(for book: BookGroup) -> GuideTargetKey? {
        // 第一个非默认手帐（用于 Step 3 引导）
        if book.id == firstNonDefaultBook?.id {
            return .ootdFirstNonDefaultBookCard
        }
        // 第一个手帐（用于其他场景）
        if book.id == books.first?.id {
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
            view.matchedGeometryEffect(id: "book_\(book.id)", in: namespace!)
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
    // 性能优化：封面图改为异步降采样加载（原先在 body 中同步解码全尺寸原图，导致书架进入卡顿）
    @State private var loadedCoverImage: UIImage?
    @State private var isLoading = true

    /// 封面显示尺寸（用于降采样，避免解码全尺寸原图）
    private static let coverTargetSize = CGSize(width: 320, height: 440)

    /// 封面来源标识：封面路径（或回退的首页快照路径）变化时触发重新加载。
    /// 有自定义封面时直接返回路径，避免在 body 中遍历 book.pages。
    private var coverSourceKey: String {
        if let coverPath = book.coverImage {
            return coverPath
        }
        return fallbackSnapshotPath ?? ""
    }

    /// 回退封面：最新一张未删除书页的快照路径（用 max(by:) 避免排序整个数组）
    private var fallbackSnapshotPath: String? {
        (book.pages ?? [])
            .filter { !$0.isDeleted }
            .max(by: { $0.createdAt < $1.createdAt })?
            .snapshotPath
    }

    var body: some View {
        ZStack {
            colorScheme == .dark ? Color(uiColor: .systemGray6) : Color.white
            
            if let image = loadedCoverImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 160, height: 220)
                    .clipped()
            } else if isLoading {
                // 加载中状态
                VStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(book.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
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
            if loadedCoverImage != nil {
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
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.2), radius: 5, x: 5, y: 5)
        // 封面路径（含回退的首页快照路径）变化时重新加载
        .task(id: coverSourceKey) {
            await loadCoverImage()
        }
    }

    private func loadCoverImage() async {
        isLoading = true
        defer { isLoading = false }

        // 1. 优先加载用户设置的封面图片（降采样到显示尺寸）
        if let coverPath = book.coverImage {
            if let image = await ImageManager.shared.loadImageAsync(fileName: coverPath, targetSize: Self.coverTargetSize) {
                loadedCoverImage = image
                return
            }
        }

        // 2. 回退到最新一张未删除书页的快照
        if let snapshotPath = fallbackSnapshotPath {
            if let image = await ImageManager.shared.loadImageAsync(fileName: snapshotPath, targetSize: Self.coverTargetSize) {
                loadedCoverImage = image
                return
            }
        }

        // 3. 都没有找到，显示占位符
        loadedCoverImage = nil
    }
}

struct BouncingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(), value: configuration.isPressed)
    }
}
