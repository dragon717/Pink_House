
import SwiftUI
import SwiftData
import SceneKit

struct SpatialBookShelfView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<SpaceBookGroup> { $0.deletedAt == nil }, sort: \SpaceBookGroup.createdAt, order: .reverse) private var books: [SpaceBookGroup]
    
    @State private var showingNewBookAlert = false
    @State private var newBookName = ""
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            ScrollView {
                if books.isEmpty {
                    ContentUnavailableView {
                        Label("暂无空间手帐", systemImage: "cube.transparent")
                    } description: {
                        Text("点击右上角 + 创建新的空间手帐")
                    }
                    .foregroundStyle(.gray)
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 24)], spacing: 32) {
                        ForEach(books) { book in
                            NavigationLink(value: book) {
                                SpaceBookView(book: book)
                            }
                            .buttonStyle(BouncingButtonStyle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteBook(book)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newBookName = ""
                    showingNewBookAlert = true
                } label: {
                    Image(systemName: "plus")
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

// MARK: - Space Book Detail View

struct SpaceBookDetailView: View {
    let book: SpaceBookGroup
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // Sort pages by creation date
    var sortedPages: [SpaceOutfit] {
        book.pages.filter { !$0.isDeleted }.sorted { $0.createdAt > $1.createdAt }
    }
    
    @State private var showingNewPageAlert = false
    @State private var newPageNote = ""
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                if sortedPages.isEmpty {
                    ContentUnavailableView {
                        Label("暂无空间书页", systemImage: "doc.text.image")
                    } description: {
                        Text("点击 + 创建新的空间书页")
                    }
                    .foregroundStyle(.gray)
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 24)], spacing: 32) {
                        ForEach(sortedPages) { page in
                            NavigationLink(value: page) {
                                SpaceOutfitCard(page: page)
                            }
                            .buttonStyle(BouncingButtonStyle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    deletePage(page)
                                } label: {
                                    Label("删除书页", systemImage: "trash")
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
                Button {
                    showingNewPageAlert = true
                } label: {
                    Image(systemName: "plus")
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
    }
    
    private func deletePage(_ page: SpaceOutfit) {
        page.isDeleted = true
        page.deletedAt = Date()
        try? modelContext.save()
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
