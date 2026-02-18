import SwiftUI
import SwiftData
import PhotosUI

struct BookDetailView: View {
    @Bindable var book: BookGroup
    @Binding var navigationPath: NavigationPath
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(filter: #Predicate<BookGroup> { $0.deletedAt == nil }) private var allBooks: [BookGroup]

    @Binding var isSidebarVisible: Bool
    var onBack: (() -> Void)?

    // 使用 @Query 获取书页数据，这样删除后会自动刷新
    @Query(filter: #Predicate<Outfit> { $0.isDeleted == false }, sort: \Outfit.sortIndex) private var allPages: [Outfit]

    var sortedPages: [Outfit] {
        allPages.filter { $0.book?.id == book.id }.sorted {
            if $0.sortIndex == $1.sortIndex {
                return $0.createdAt < $1.createdAt
            }
            return $0.sortIndex < $1.sortIndex
        }
    }

    @State var isEditing = false

    @State var showingRenameAlert = false
    @State var pageToRename: Outfit?
    @State var newPageName = ""

    @State var showingCoverPicker = false
    @State var selectedCoverItem: PhotosPickerItem?

    @State var showingBackgroundPicker = false
    @State var selectedBackgroundItem: PhotosPickerItem?
    @State var tempBackgroundImage: UIImage?
    @State var showingBackgroundCropper = false

    @State var showingTrash = false

    @State var showingMoveSheet = false
    @State var pageToMove: Outfit?
    
    // 分享卡片
    @State var showingShareCard = false
    @State var pageToShare: Outfit?
    
    // Rename Book
    @State var showingRenameBookAlert = false
    @State var renameBookName = ""

    @AppStorage("bookDetailGridMode") var gridModeValue = 2

    var gridMode: GridMode {
        GridMode(rawValue: gridModeValue) ?? .double
    }

    var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: gridMode.rawValue)
    }

    // 用于强制刷新视图的触发器
    @State private var refreshTrigger = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(sortedPages) { page in
                    pageCell(for: page)
                }
            }
            .padding()
            .animation(.default, value: sortedPages)
        }
        .id(refreshTrigger)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            leadingToolbarContent
            trailingToolbarContent
        }
        .bookDetailSheets(
            showingTrash: $showingTrash,
            showingCoverPicker: $showingCoverPicker,
            selectedCoverItem: $selectedCoverItem,
            updateCover: updateCover,
            showingBackgroundPicker: $showingBackgroundPicker,
            selectedBackgroundItem: $selectedBackgroundItem,
            tempBackgroundImage: $tempBackgroundImage,
            showingBackgroundCropper: $showingBackgroundCropper,
            backgroundCropperSheet: { backgroundCropperSheet },
            showingRenameAlert: $showingRenameAlert,
            newPageName: $newPageName,
            pageToRename: $pageToRename,
            saveRename: saveRename,
            showingMoveSheet: $showingMoveSheet,
            movePageSheet: { movePageSheet }
        )
        .fullScreenCover(isPresented: $showingShareCard) {
            if let page = pageToShare {
                ShareCardSheet(
                    shareType: .outfit(page),
                    onDismiss: { showingShareCard = false }
                )
            }
        }
        .alert("重命名手帐", isPresented: $showingRenameBookAlert) {
            TextField("名称", text: $renameBookName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                book.title = renameBookName
                try? modelContext.save()
            }
        }
    }

    private var backgroundCropperSheet: some View {
        Group {
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
    }

    private var movePageSheet: some View {
        Group {
            if let page = pageToMove {
                MovePageSheet(page: page, currentBook: book)
            }
        }
    }

    private func saveRename() {
        if let page = pageToRename {
            page.note = newPageName
            try? modelContext.save()
        }
    }

    func movePage(from source: Outfit, to destination: Outfit) {
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

    func addNewPage(canvasType: String = "mannequin", customImage: UIImage? = nil) {
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

    func insertPage(after page: Outfit) {
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

    func insertPage(before page: Outfit) {
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

    func duplicatePage(_ page: Outfit) {
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

    func deletePage(_ page: Outfit) {
        withAnimation {
            page.isDeleted = true
            page.deletedAt = Date()
            try? modelContext.save()
            // 强制刷新视图
            refreshTrigger.toggle()
        }
    }

    func updateCover(with item: PhotosPickerItem) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let path = ImageManager.shared.saveImage(image, context: modelContext) {
                await MainActor.run {
                    book.coverImage = path
                    selectedCoverItem = nil
                    // 保存到数据库并刷新视图
                    try? modelContext.save()
                    refreshTrigger.toggle()
                }
            }
        }
    }
}
