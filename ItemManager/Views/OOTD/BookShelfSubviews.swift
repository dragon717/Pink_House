import SwiftUI
import SwiftData

// MARK: - Subviews for BookShelf

struct BookSidebarView: View {
    let books: [BookGroup]
    let selectedBook: BookGroup?
    let onSelect: (BookGroup) -> Void
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                ForEach(books) { book in
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
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 10)
        }
        .frame(width: 90)
        .frame(maxHeight: .infinity)
        // Transparent UI as requested
        .background(Color.clear)
        .overlay(
            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(width: 1),
            alignment: .trailing
        )
    }
}

struct BookGridView: View {
    let books: [BookGroup]
    @Binding var selectedBook: BookGroup?
    @Binding var selectedBookForCover: BookGroup?
    @Binding var showingCoverPicker: Bool
    let onDelete: (BookGroup) -> Void
    var namespace: Namespace.ID?
    var onBookTap: ((BookGroup) -> Void)?
    var openingBook: BookGroup?
    
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
                    .contextMenu {
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
}

struct ThreeDBookView: View {
    let book: BookGroup
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
                    .fill(Color.black.opacity(0.1))
                    .frame(width: 6)
                Spacer()
            }
        }
        .frame(width: 160, height: 220)
        .background(Color.white)
        .cornerRadius(4, corners: [.topRight, .bottomRight])
        .shadow(color: .black.opacity(0.2), radius: 5, x: 5, y: 5)
    }
}

struct BouncingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(), value: configuration.isPressed)
    }
}


