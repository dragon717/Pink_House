//
//  SpaceBookViews.swift
//  ItemManager
//
//  空间书架相关子视图
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Space Book View

struct SpaceBookView: View {
    let book: SpaceBookGroup
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

// MARK: - Space Book Cover Visuals

struct SpaceBookCoverVisuals: View {
    let book: SpaceBookGroup
    @Environment(\.colorScheme) private var colorScheme
    @State private var loadedCoverImage: UIImage?
    @State private var isLoading = true

    private let coverTargetSize = CGSize(width: 180, height: 248)

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
                    .fill(Color.black.opacity(0.1))
                    .frame(width: 6)
                Spacer()
            }
        }
        .clipShape(RoundedCorner(radius: 4, corners: [.topRight, .bottomRight]))
        .overlay(ThemeSkinBookCoverFrame(cornerRadius: 4))
        .task(id: book.id) {
            await loadCoverImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .spaceOutfitThumbnailUpdated)) { notification in
            // 监听缩略图更新通知，重新加载封面
            if let updatedPageID = notification.object as? UUID {
                // 检查更新的书页是否属于这本书
                let validPages = (book.pages ?? []).filter { !$0.isDeleted }
                if validPages.contains(where: { $0.id == updatedPageID }) {
                    Task {
                        await loadCoverImage()
                    }
                }
            }
        }
    }

    @MainActor
    private func loadCoverImage() async {
        isLoading = true
        defer { isLoading = false }

        // 1. 优先加载用户设置的封面图片
        if let coverPath = book.coverImage, !coverPath.isEmpty {
            if let cached = ImageManager.shared.cachedImage(fileName: coverPath, targetSize: coverTargetSize) {
                loadedCoverImage = cached
                return
            }

            try? await Task.sleep(nanoseconds: 25_000_000)
            guard !Task.isCancelled else { return }

            let image = await ImageManager.shared.loadImageAsync(
                fileName: coverPath,
                targetSize: coverTargetSize,
                priority: .utility
            )
            if let image = image {
                self.loadedCoverImage = image
                return
            }
        }

        // 2. 如果没有设置封面，查找第一个有缩略图的空间书页
        let validPages = (book.pages ?? [])
            .filter { !$0.isDeleted }
            .sorted(by: { $0.createdAt > $1.createdAt })
        
        // 优先查找有缓存缩略图的书页
        for page in validPages {
            if let thumbnail = SpaceOutfitThumbnailCache.shared.getThumbnail(for: page.id) {
                await MainActor.run {
                    self.loadedCoverImage = thumbnail
                }
                return
            }
        }
        
        // 3. 如果没有缓存缩略图，查找有snapshotPath的书页
        if let firstPageWithSnapshot = validPages.first(where: { $0.snapshotPath != nil }),
           let snapshotPath = firstPageWithSnapshot.snapshotPath {
            if let cached = ImageManager.shared.cachedImage(fileName: snapshotPath, targetSize: coverTargetSize) {
                loadedCoverImage = cached
                return
            }

            try? await Task.sleep(nanoseconds: 25_000_000)
            guard !Task.isCancelled else { return }

            let image = await ImageManager.shared.loadImageAsync(
                fileName: snapshotPath,
                targetSize: coverTargetSize,
                priority: .utility
            )
            if let image = image {
                self.loadedCoverImage = image
                return
            }
        }
        
        // 4. 都没有找到，显示占位符
        self.loadedCoverImage = nil
    }
}

// MARK: - Space Outfit Card

struct SpaceOutfitCard: View {
    let page: SpaceOutfit
    var width: CGFloat? = nil
    var height: CGFloat? = nil

    var body: some View {
        SpaceOutfitCover(page: page)
            .frame(width: width, height: height ?? 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                Text(page.note.isEmpty ? "未命名".appLocalized : page.note)
                    .font(.caption)
                    .lineLimit(1)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(8)
            }
            .themeSkinPageThumbnailSurface()
    }
}

// MARK: - Space Outfit Cover

struct SpaceOutfitCover: View {
    let page: SpaceOutfit
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                colorScheme == .dark ? Color(uiColor: .systemGray6) : Color.white

                // 使用ARView实时渲染3D场景预览
                SpaceOutfitPreviewView(page: page)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }
}

// MARK: - Space Book Opening Animation View

struct SpaceBookOpeningAnimationView: View {
    let book: SpaceBookGroup
    let onComplete: () -> Void
    @Namespace var animationNamespace

    // 动画状态
    @State private var isMovingToCenter = false
    @State private var isOpening = false
    @State private var pagesFlipped: [Bool] = Array(repeating: false, count: 6)
    @State private var isReady = false

    // 书页图片缓存
    @State private var pageImages: [UIImage?] = Array(repeating: nil, count: 6)
    @State private var coverImage: UIImage? = nil

    // 配置参数
    private let bookWidth: CGFloat = 200
    private let bookHeight: CGFloat = 280
    private let animationImageTargetSize = CGSize(width: 320, height: 448)

    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .opacity(isMovingToCenter ? 1 : 0)
                .animation(.easeIn(duration: 0.5), value: isMovingToCenter)

            // 3D 书本容器
            ZStack {
                // 1. 封底
                SpaceBookCoverWithImage(book: book, width: bookWidth, height: bookHeight, isFront: false, image: coverImage)

                // 2. 书页 (多层)
                ForEach(0..<6) { index in
                    SpaceBookPage(width: bookWidth - 10, height: bookHeight - 10, image: pageImages[index])
                        .rotation3DEffect(
                            .degrees(pagesFlipped[index] ? -175 + Double.random(in: -5...5) : 0),
                            axis: (x: 0.0, y: 1.0, z: 0.0),
                            anchor: .leading,
                            anchorZ: 0,
                            perspective: 0.5
                        )
                        .offset(x: 5, y: 0)
                        .zIndex(Double(6 - index))
                }

                // 3. 封面
                SpaceBookCoverWithImage(book: book, width: bookWidth, height: bookHeight, isFront: true, image: coverImage)
                    .rotation3DEffect(
                        .degrees(isOpening ? -180 : 0),
                        axis: (x: 0.0, y: 1.0, z: 0.0),
                        anchor: .leading,
                        anchorZ: 0,
                        perspective: 0.5
                    )
                    .zIndex(10)
            }
            // 整体变换：移动到中心并放大
            .scaleEffect(isMovingToCenter ? 1.5 : 0.2)
            .rotation3DEffect(
                .degrees(isMovingToCenter ? 0 : -8),
                axis: (x: 0.0, y: 1.0, z: 0.0)
            )
            .offset(y: isMovingToCenter ? 0 : 300)
            .opacity(isReady ? 1 : 0)
        }
        .task {
            guard !Task.isCancelled else { return }
            isReady = true
            startAnimationSequence()
            await preloadAllImages()
        }
    }

    @MainActor
    private func preloadAllImages() async {
        // 并行加载封面和书页图片
        async let coverTask = loadCoverImage()
        async let pagesTask = loadPageImages()

        let loadedCover = await coverTask
        guard !Task.isCancelled else { return }
        coverImage = loadedCover

        await pagesTask
    }

    @MainActor
    private func loadCoverImage() async -> UIImage? {
        // 优先加载用户设置的封面图片
        if let coverPath = book.coverImage {
            if let cached = ImageManager.shared.cachedImage(fileName: coverPath, targetSize: animationImageTargetSize) {
                return cached
            }

            if let image = await ImageManager.shared.loadImageAsync(
                fileName: coverPath,
                targetSize: animationImageTargetSize,
                priority: .userInitiated
            ) {
                return image
            }
        }

        // 如果没有封面，使用第一页作为封面
        let validPages = (book.pages ?? []).filter { !$0.isDeleted }.sorted { $0.createdAt > $1.createdAt }
        if let firstPage = validPages.first {
            // 优先使用缩略图缓存（ARView预览）
            if let thumbnail = SpaceOutfitThumbnailCache.shared.getThumbnail(for: firstPage.id) {
                return thumbnail
            }
            // 其次使用 snapshotPath
            if let snapshotPath = firstPage.snapshotPath {
                if let cached = ImageManager.shared.cachedImage(fileName: snapshotPath, targetSize: animationImageTargetSize) {
                    return cached
                }

                return await ImageManager.shared.loadImageAsync(
                    fileName: snapshotPath,
                    targetSize: animationImageTargetSize,
                    priority: .userInitiated
                )
            }
        }

        return nil
    }

    @MainActor
    private func loadPageImages() async {
        // 获取书页数据（过滤已删除的，按创建时间倒序）
        let validPages = (book.pages ?? []).filter { !$0.isDeleted }.sorted { $0.createdAt > $1.createdAt }
        let targetSize = animationImageTargetSize

        // 如果没有书页，直接返回
        if validPages.isEmpty { return }

        var snapshotLoads: [(index: Int, path: String)] = []
        snapshotLoads.reserveCapacity(6)

        for i in 0..<6 {
            let pageIndex = i % validPages.count
            let page = validPages[pageIndex]

            if let thumbnail = SpaceOutfitThumbnailCache.shared.getThumbnail(for: page.id) {
                pageImages[i] = thumbnail
            } else if let snapshotPath = page.snapshotPath, !snapshotPath.isEmpty {
                snapshotLoads.append((index: i, path: snapshotPath))
            }
        }

        guard !snapshotLoads.isEmpty else { return }

        // 并行加载所有书页图片
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for load in snapshotLoads {
                group.addTask {
                    if let cached = await ImageManager.shared.cachedImage(fileName: load.path, targetSize: targetSize) {
                        return (load.index, cached)
                    }

                    let image = await ImageManager.shared.loadImageAsync(
                        fileName: load.path,
                        targetSize: targetSize,
                        priority: .userInitiated
                    )
                    return (load.index, image)
                }
            }

            for await (index, image) in group {
                await MainActor.run {
                    self.pageImages[index] = image
                }
            }
        }
    }

    private func startAnimationSequence() {
        // 1. 移动到中心并放大
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
            isMovingToCenter = true
        }

        // 2. 打开封面 (延迟 0.6s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.8)) {
                isOpening = true
            }
        }

        // 3. 随机翻页 (延迟 1.2s 开始，每隔 0.15s 翻一页)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            for i in 0..<6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        pagesFlipped[i] = true
                    }
                }
            }
        }

        // 4. 动画结束，进入列表 (延迟 2.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            onComplete()
        }
    }
}

// MARK: - Animation Subviews

struct SpaceBookCoverWithImage: View {
    let book: SpaceBookGroup
    let width: CGFloat
    let height: CGFloat
    var isFront: Bool = false
    let image: UIImage?

    var body: some View {
        ZStack {
            // Base Cover
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .cornerRadius(4)
            } else {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: width, height: height)
                    .cornerRadius(4)

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

            // Shadow
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                .frame(width: width, height: height)
                .shadow(radius: 5)

            // 装饰线条 (仅封面)
            if isFront {
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: width - 16, height: height - 16)

                // Title at bottom
                VStack {
                    Spacer()
                    ZStack {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .frame(height: 40)
                        Text(book.title)
                            .font(.headline)
                            .lineLimit(2)
                            .padding(.horizontal, 8)
                    }
                }
                .frame(width: width, height: height)
            }

            // 书脊纹理
            HStack {
                LinearGradient(colors: [.black.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 8)
                Spacer()
            }
        }
        .frame(width: width, height: height)
    }
}

struct SpaceBookCoverForAnimation: View {
    let book: SpaceBookGroup
    let width: CGFloat
    let height: CGFloat
    var isFront: Bool = false
    @State private var loadedCoverImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            // Base Cover
            if let image = loadedCoverImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .cornerRadius(4)
            } else if isLoading {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: width, height: height)
                    .cornerRadius(4)

                VStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(book.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            } else {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: width, height: height)
                    .cornerRadius(4)

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

            // Shadow
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                .frame(width: width, height: height)
                .shadow(radius: 5)

            // 装饰线条 (仅封面)
            if isFront {
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: width - 16, height: height - 16)

                // Title at bottom
                VStack {
                    Spacer()
                    ZStack {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .frame(height: 40)
                        Text(book.title)
                            .font(.headline)
                            .lineLimit(2)
                            .padding(.horizontal, 8)
                    }
                }
                .frame(width: width, height: height)
            }

            // 书脊纹理
            HStack {
                LinearGradient(colors: [.black.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 8)
                Spacer()
            }
        }
        .frame(width: width, height: height)
        .task(id: book.id) {
            await loadCoverImage()
        }
    }

    private func loadCoverImage() async {
        isLoading = true
        defer { isLoading = false }

        // 优先加载封面图片
        if let coverPath = book.coverImage {
            let image = await ImageManager.shared.loadImageAsync(fileName: coverPath)
            if let image = image {
                await MainActor.run {
                    self.loadedCoverImage = image
                }
                return
            }
        }

        // 如果没有封面，使用第一页作为封面
        if let firstPage = (book.pages ?? []).filter({ !$0.isDeleted }).sorted(by: { $0.createdAt > $1.createdAt }).first,
           let snapshotPath = firstPage.snapshotPath {
            let image = await ImageManager.shared.loadImageAsync(fileName: snapshotPath)
            await MainActor.run {
                self.loadedCoverImage = image
            }
        }
    }
}

struct SpaceBookPage: View {
    let width: CGFloat
    let height: CGFloat
    var image: UIImage? = nil

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: width, height: height)
                .cornerRadius(2)
                .shadow(color: .black.opacity(0.1), radius: 1, x: 1, y: 0)

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width - 16, height: height - 16)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                 // 空白页纹理
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 20))
                            .foregroundStyle(.gray.opacity(0.3))
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Space Reorderable Drop Delegate

struct SpaceReorderableDropDelegate: DropDelegate {
    let item: SpaceOutfit
    let pages: [SpaceOutfit]
    let onMove: (IndexSet, Int) -> Void
    
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
                        if let sourceIndex = pages.firstIndex(where: { $0.id == uuid }),
                           let destinationIndex = pages.firstIndex(where: { $0.id == item.id }) {
                            if sourceIndex != destinationIndex {
                                onMove(IndexSet(integer: sourceIndex), destinationIndex)
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

// MARK: - Space Move Page Sheet

struct SpaceMovePageSheet: View {
    let page: SpaceOutfit
    let currentBook: SpaceBookGroup
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<SpaceBookGroup> { $0.deletedAt == nil }) private var books: [SpaceBookGroup]

    var body: some View {
        NavigationStack {
            List(books) { targetBook in
                if targetBook.id != currentBook.id {
                    Button {
                        page.book = targetBook
                        try? modelContext.save()
                        dismiss()
                    } label: {
                        HStack {
                            Text(targetBook.title)
                            Spacer()
                            Text("%d 页".appLocalized((targetBook.pages ?? []).filter({ !$0.isDeleted }).count))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("移动到...".appLocalized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".appLocalized) { dismiss() }
                }
            }
        }
    }
}
