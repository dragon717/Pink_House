
import SwiftUI
import SwiftData
import PhotosUI

struct BookDetailView: View {
    @Bindable var book: BookGroup
    @Binding var navigationPath: NavigationPath
    @Environment(\.modelContext) private var modelContext
    
    // Sort pages by sortIndex (primary) then createdAt (secondary)
    var sortedPages: [Outfit] {
        book.pages.filter { !$0.isDeleted }.sorted {
            if $0.sortIndex == $1.sortIndex {
                return $0.createdAt < $1.createdAt
            }
            return $0.sortIndex < $1.sortIndex
        }
    }
    
    @State private var isEditing = false
    
    @State private var showingRenameAlert = false
    @State private var pageToRename: Outfit?
    @State private var newPageName = ""
    
    @State private var showingCoverPicker = false
    @State private var selectedCoverItem: PhotosPickerItem?
    
    // Background Picker
    @State private var showingBackgroundPicker = false
    @State private var selectedBackgroundItem: PhotosPickerItem?
    @State private var tempBackgroundImage: UIImage?
    @State private var showingBackgroundCropper = false
    
    @State private var showingTrash = false
    
    // For moving pages
    @State private var showingMoveSheet = false
    @State private var pageToMove: Outfit?
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                ForEach(sortedPages) { page in
                    Group {
                        if isEditing {
                            PageThumbnailView(page: page)
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
                                    return NSItemProvider(object: page.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: ReorderableDropDelegate(item: page, pages: sortedPages, onMove: movePage))
                        } else {
                            NavigationLink(value: page) {
                                PageThumbnailView(page: page)
                            }
                            .contextMenu {
                                Button {
                                    pageToRename = page
                                    newPageName = page.note
                                    showingRenameAlert = true
                                } label: {
                                    Label("修改名称", systemImage: "pencil")
                                }
                                
                                Button {
                                    duplicatePage(page)
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                
                                Button {
                                    insertPage(after: page)
                                } label: {
                                    Label("在后面新增", systemImage: "arrow.right.square")
                                }
                                
                                Button {
                                    insertPage(before: page)
                                } label: {
                                    Label("在前面新增", systemImage: "arrow.left.square")
                                }
                                
                                Button {
                                    pageToMove = page
                                    showingMoveSheet = true
                                } label: {
                                    Label("移动到...", systemImage: "folder")
                                }
                                
                                Button(role: .destructive) {
                                    deletePage(page)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .animation(.default, value: sortedPages)
        }
        .navigationTitle(book.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    // Edit / Sort Button
                    Button {
                        withAnimation {
                            isEditing.toggle()
                        }
                    } label: {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "arrow.up.arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    
                    // Add / More Menu
                    Menu {
                        Menu {
                            Button {
                                addNewPage(canvasType: "mannequin")
                            } label: {
                                Label("人台画布", systemImage: "tshirt")
                            }
                            
                            Button {
                                addNewPage(canvasType: "blank")
                            } label: {
                                Label("空白画布", systemImage: "square.dashed")
                            }
                            
                            Button {
                                showingBackgroundPicker = true
                            } label: {
                                Label("自定义图片", systemImage: "photo")
                            }
                        } label: {
                            Label("新增书页", systemImage: "doc.badge.plus")
                        }
                        
                        Button {
                            showingTrash = true
                        } label: {
                            Label("垃圾篓", systemImage: "trash")
                        }
                        
                        Button {
                            showingCoverPicker = true
                        } label: {
                            Label("修改封面", systemImage: "photo")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingTrash) {
            RecycleBinView(initialTab: 1)
        }
        .photosPicker(isPresented: $showingCoverPicker, selection: $selectedCoverItem, matching: .images)
        .onChange(of: selectedCoverItem) { _, newItem in
            if let newItem {
                updateCover(with: newItem)
            }
        }
        .photosPicker(isPresented: $showingBackgroundPicker, selection: $selectedBackgroundItem, matching: .images)
        .onChange(of: selectedBackgroundItem) { _, newItem in
            if let newItem {
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            tempBackgroundImage = image
                            showingBackgroundCropper = true
                            selectedBackgroundItem = nil
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingBackgroundCropper) {
            if let image = tempBackgroundImage {
                ImageCropView(
                    image: image,
                    aspectRatio: 0.75, // 3:4 aspect ratio
                    targetWidth: 1080  // Ensure high quality output
                ) { croppedImage in
                     addNewPage(canvasType: "custom", customImage: croppedImage)
                     showingBackgroundCropper = false
                     tempBackgroundImage = nil
                } onCancel: {
                     showingBackgroundCropper = false
                     tempBackgroundImage = nil
                }
            }
        }
        .alert("重命名", isPresented: $showingRenameAlert) {
            TextField("名称", text: $newPageName)
            Button("取消", role: .cancel) {}
            Button("确定") {
                if let page = pageToRename {
                    page.note = newPageName
                    try? modelContext.save()
                }
            }
        }
        .sheet(isPresented: $showingMoveSheet) {
            if let page = pageToMove {
                MovePageSheet(page: page, currentBook: book)
            }
        }
        .navigationDestination(for: Outfit.self) { outfit in
            OOTDEditorView(outfit: outfit)
        }
    }
    
    // MARK: - Actions
    
    private func movePage(from source: Outfit, to destination: Outfit) {
        var pages = sortedPages
        guard let sourceIndex = pages.firstIndex(where: { $0.id == source.id }),
              let destIndex = pages.firstIndex(where: { $0.id == destination.id }) else { return }
        
        if sourceIndex == destIndex { return }
        
        withAnimation {
            let item = pages.remove(at: sourceIndex)
            pages.insert(item, at: destIndex)
            
            // Update sort indices
            for (index, page) in pages.enumerated() {
                page.sortIndex = index
            }
        }
        
        try? modelContext.save()
    }
    
    private func addNewPage(canvasType: String = "mannequin", customImage: UIImage? = nil) {
        let newPage = Outfit(note: "新书页 \(Date().formatted(date: .numeric, time: .shortened))", canvasType: canvasType, book: book)
        // Set index to be last
        newPage.sortIndex = (sortedPages.last?.sortIndex ?? 0) + 1
        
        if canvasType == "custom", let image = customImage {
            // Save image with reference counting and compression (handled by ImageManager)
            if let path = ImageManager.shared.saveImage(image, context: modelContext) {
                newPage.backgroundImagePath = path
                // Also set snapshot for immediate display
                newPage.snapshotPath = path
            }
        }
        
        modelContext.insert(newPage)
    }
    
    private func insertPage(after page: Outfit) {
        let newPage = Outfit(note: "新书页", book: book)
        
        // Insert logic: shift everyone after this page by 1
        let pages = sortedPages
        if let index = pages.firstIndex(of: page) {
            newPage.sortIndex = page.sortIndex + 1
            for p in pages where p.sortIndex > page.sortIndex {
                p.sortIndex += 1
            }
        } else {
            newPage.sortIndex = (pages.last?.sortIndex ?? 0) + 1
        }
        
        modelContext.insert(newPage)
    }
    
    private func insertPage(before page: Outfit) {
        let newPage = Outfit(note: "新书页", book: book)
        
        let pages = sortedPages
        if let index = pages.firstIndex(of: page) {
            newPage.sortIndex = page.sortIndex
            // Shift everyone from this index onwards
            for p in pages where p.sortIndex >= page.sortIndex {
                p.sortIndex += 1
            }
        }
        
        modelContext.insert(newPage)
    }
    
    private func duplicatePage(_ page: Outfit) {
        let newPage = Outfit(note: page.note + " 副本", canvasType: page.canvasType, backgroundImagePath: page.backgroundImagePath, book: book)
        // Insert after current
        let pages = sortedPages
        if let index = pages.firstIndex(of: page) {
            newPage.sortIndex = page.sortIndex + 1
            for p in pages where p.sortIndex > page.sortIndex {
                p.sortIndex += 1
            }
        }
        
        modelContext.insert(newPage)
        
        for item in page.items {
            let newItem = OutfitItem(cutout: item.cutout, x: item.x, y: item.y, rotation: item.rotation, scale: item.scale, zIndex: item.zIndex)
            newPage.items.append(newItem)
        }
        
        if let path = page.snapshotPath,
           let image = ImageManager.shared.loadImage(fileName: path),
           let newPath = ImageManager.shared.saveImage(image, context: modelContext) {
            newPage.snapshotPath = newPath
        }
    }
    
    private func deletePage(_ page: Outfit) {
        page.isDeleted = true
        page.deletedAt = Date()
        try? modelContext.save()
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
}

// Better DropDelegate for Reordering
struct ReorderableDropDelegate: DropDelegate {
    let item: Outfit
    var pages: [Outfit]
    var onMove: (Outfit, Outfit) -> Void
    
    func dropEntered(info: DropInfo) {
        guard info.hasItemsConforming(to: [.text]) else { return }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.text])
    }
    
    func performDrop(info: DropInfo) -> Bool {
        if let itemProvider = info.itemProviders(for: [.text]).first {
            itemProvider.loadItem(forTypeIdentifier: "public.text", options: nil) { (data, error) in
                if let data = data as? Data, let idString = String(data: data, encoding: .utf8), let uuid = UUID(uuidString: idString) {
                    DispatchQueue.main.async {
                        if let source = pages.first(where: { $0.id == uuid }) {
                            onMove(source, item)
                        }
                    }
                }
            }
            return true
        }
        return false
    }
}

// Update the View to use ReorderableDropDelegate
extension BookDetailView {
    // Helper to fix the Delegate usage in body
    func dropDelegate(for page: Outfit) -> some DropDelegate {
        ReorderableDropDelegate(item: page, pages: sortedPages, onMove: movePage)
    }
}

// ... PageThumbnailView and MovePageSheet remain the same ...
struct PageThumbnailView: View {
    let page: Outfit
    
    var body: some View {
        VStack {
            Group {
                if let path = page.snapshotPath {
                    // Use AsyncDownsampledImage for efficient loading and display
                    AsyncDownsampledImage(
                        fileName: path,
                        targetSize: CGSize(width: 300, height: 400),
                        content: { uiImage in
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                        },
                        placeholder: {
                            // If snapshotPath exists but image is loading or failed
                            // We should also show the placeholder view to avoid black screen
                            placeholderView
                                .overlay {
                                    ProgressView()
                                }
                        }
                    )
                } else {
                    // No snapshot available, show type-specific placeholder
                    placeholderView
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            Text(page.note)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .padding(8)
    }
    
    @ViewBuilder
    private var placeholderView: some View {
        switch page.canvasType {
        case "mannequin":
            ZStack {
                Color.white
                Image(systemName: "tshirt")
                    .font(.system(size: 40))
                    .foregroundStyle(.gray.opacity(0.3))
                Text("人台")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .offset(y: 24)
            }
        case "blank":
            ZStack {
                Color.white
                RoundedRectangle(cornerRadius: 4)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.gray.opacity(0.3))
                    .padding(16)
                Text("空白")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
        case "custom":
            ZStack {
                Color.white
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(.gray.opacity(0.3))
                Text("图片丢失")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .offset(y: 24)
            }
        default:
            ZStack {
                Color.white
                Image(systemName: "doc.text")
                    .font(.system(size: 40))
                    .foregroundStyle(.gray.opacity(0.3))
            }
        }
    }
}

struct MovePageSheet: View {
    let page: Outfit
    let currentBook: BookGroup
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<BookGroup> { $0.deletedAt == nil }) private var books: [BookGroup]
    
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
