import SwiftUI
import SwiftData
import PhotosUI

struct BookDetailView: View {
    @Bindable var book: BookGroup
    @Binding var navigationPath: NavigationPath
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var isSidebarVisible: Bool

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
    
    @State private var showingBackgroundPicker = false
    @State private var selectedBackgroundItem: PhotosPickerItem?
    @State private var tempBackgroundImage: UIImage?
    @State private var showingBackgroundCropper = false
    
    @State private var showingTrash = false
    
    @State private var showingMoveSheet = false
    @State private var pageToMove: Outfit?
    
    @AppStorage("bookDetailGridMode") private var gridModeValue = 2
    
    private var gridMode: GridMode {
        GridMode(rawValue: gridModeValue) ?? .double
    }
    
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: gridMode.rawValue)
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(sortedPages) { page in
                    Group {
                        if isEditing {
                            PageThumbnailView(page: page, gridMode: gridMode)
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
                                PageThumbnailView(page: page, gridMode: gridMode)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(book.title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 8) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    }

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isSidebarVisible.toggle()
                        }
                    } label: {
                        Image(systemName: isSidebarVisible ? "sidebar.left" : "sidebar.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    Menu {
                        Picker("视图布局", selection: $gridModeValue) {
                            ForEach(GridMode.allCases, id: \.rawValue) { mode in
                                Label(mode.displayName, systemImage: mode.iconName)
                                    .tag(mode.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: gridMode.iconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    Button {
                        withAnimation {
                            isEditing.toggle()
                        }
                    } label: {
                        if isEditing {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.pink)
                        } else {
                            Image(systemName: "list.number")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }

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
                            showingCoverPicker = true
                        } label: {
                            Label("修改封面", systemImage: "photo")
                        }

                        Divider()

                        Button {
                            showingTrash = true
                        } label: {
                            Label("垃圾篓", systemImage: "trash")
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
                    aspectRatio: 0.75,
                    targetWidth: 1080
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
    
    private func movePage(from source: Outfit, to destination: Outfit) {
        var pages = sortedPages
        guard let sourceIndex = pages.firstIndex(where: { $0.id == source.id }),
              let destIndex = pages.firstIndex(where: { $0.id == destination.id }) else { return }
        
        if sourceIndex == destIndex { return }
        
        withAnimation {
            let item = pages.remove(at: sourceIndex)
            pages.insert(item, at: destIndex)
            
            for (index, page) in pages.enumerated() {
                page.sortIndex = index
            }
        }
        
        try? modelContext.save()
    }
    
    private func addNewPage(canvasType: String = "mannequin", customImage: UIImage? = nil) {
        let newPage = Outfit(note: "新书页 \(Date().formatted(date: .numeric, time: .shortened))", canvasType: canvasType, book: book)
        newPage.sortIndex = (sortedPages.last?.sortIndex ?? 0) + 1
        
        if canvasType == "custom", let image = customImage {
            if let path = ImageManager.shared.saveImage(image, context: modelContext) {
                newPage.backgroundImagePath = path
                newPage.snapshotPath = path
            }
        }
        
        modelContext.insert(newPage)
    }
    
    private func insertPage(after page: Outfit) {
        let newPage = Outfit(note: "新书页", book: book)
        
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
            for p in pages where p.sortIndex >= page.sortIndex {
                p.sortIndex += 1
            }
        }
        
        modelContext.insert(newPage)
    }
    
    private func duplicatePage(_ page: Outfit) {
        let newPage = Outfit(note: page.note + " 副本", canvasType: page.canvasType, backgroundImagePath: page.backgroundImagePath, book: book)
        
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
