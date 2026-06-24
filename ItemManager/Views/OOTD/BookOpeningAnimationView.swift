import SwiftUI
import SwiftData

/// Self-contained opening animation for planar journals.
struct BookOpeningAnimationView: View {
    let book: BookGroup
    var onAnimationComplete: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var hasEntered = false
    @State private var coverIsOpen = false
    @State private var coverIsBehindPages = false
    @State private var flippedPageCount = 0
    @State private var paperGlowOpacity: Double = 0
    @State private var didComplete = false
    @State private var sequenceTask: Task<Void, Never>?
    @State private var imageLoadingTask: Task<Void, Never>?
    @State private var pageImages: [UIImage?] = []
    @State private var pageImageSources: [String?] = []

    private let bookWidth: CGFloat = 200
    private let bookHeight: CGFloat = 280
    private let maxPageCount = 6
    private let imageTargetSize = CGSize(width: 320, height: 448)
    private let coverOpenAngle: Double = -174
    private let pageTargetAngles: [Double] = [-162, -156, -150, -144, -138, -132]

    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()

            animatedBook
                .frame(width: bookWidth, height: bookHeight)
                .scaleEffect(hasEntered ? 1.18 : 0.68)
                .rotation3DEffect(
                    .degrees(hasEntered ? 0 : 22),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.55
                )
                .offset(y: hasEntered ? -8 : 180)
                .opacity(hasEntered ? 1 : 0.75)
                .shadow(color: .black.opacity(hasEntered ? 0.35 : 0.1), radius: 26, x: 0, y: 18)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        .accessibilityHidden(true)
        .onAppear(perform: prepareAndStartAnimation)
        .onDisappear {
            sequenceTask?.cancel()
            imageLoadingTask?.cancel()
            sequenceTask = nil
            imageLoadingTask = nil
        }
    }

    private var animatedBook: some View {
        ZStack(alignment: .leading) {
            OpeningBookBackCover(width: bookWidth, height: bookHeight)
                .offset(x: 10)
                .zIndex(0)

            ForEach(0..<pageImageSources.count, id: \.self) { index in
                OpeningPaperPage(
                    index: index,
                    width: bookWidth - 14,
                    height: bookHeight - 16,
                    glowOpacity: paperGlowOpacity,
                    image: pageImage(at: index)
                )
                .offset(x: pageHorizontalOffset(for: index))
                .rotation3DEffect(
                    .degrees(pageAngle(for: index)),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .leading,
                    anchorZ: pageAnchorZ(for: index),
                    perspective: 0.62
                )
                .zIndex(pageZIndex(for: index))
            }

            OpeningBookFrontCover(book: book, width: bookWidth, height: bookHeight)
                .rotation3DEffect(
                    .degrees(coverIsOpen ? coverOpenAngle : 0),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .leading,
                    perspective: 0.62
                )
                .offset(x: coverIsOpen ? 4 : 0)
                .zIndex(coverZIndex)
        }
    }

    private var coverZIndex: Double {
        coverIsBehindPages ? 4 : 40
    }

    private func pageAngle(for index: Int) -> Double {
        guard index < flippedPageCount else { return 0 }
        return pageTargetAngles[index]
    }

    private func pageHorizontalOffset(for index: Int) -> CGFloat {
        let baseOffset = 12 + CGFloat(index) * 1.2
        guard index < flippedPageCount else { return baseOffset }
        return baseOffset + 3 + CGFloat(index) * 0.6
    }

    private func pageAnchorZ(for index: Int) -> CGFloat {
        guard index < flippedPageCount else { return 0 }
        return 8 + CGFloat(index) * 0.8
    }

    private func pageZIndex(for index: Int) -> Double {
        if index < flippedPageCount {
            return 20 + Double(index)
        }
        return 8 + Double(pageImageSources.count - index)
    }

    private func pageImage(at index: Int) -> UIImage? {
        guard pageImages.indices.contains(index) else { return nil }
        return pageImages[index]
    }

    @MainActor
    private func prepareAndStartAnimation() {
        guard sequenceTask == nil else { return }

        let sources = resolveAnimationPageSources()
        pageImageSources = sources
        pageImages = sources.map { cachedAnimationImage(from: $0) }

        imageLoadingTask = Task {
            await loadAnimationPageImages(sources)
        }
        sequenceTask = Task {
            await runAnimationSequence()
        }
    }

    @MainActor
    private func runAnimationSequence() async {
        resetAnimationState()

        // Let SwiftUI commit the inserted overlay once before changing state.
        guard await pause(milliseconds: 90) else { return }

        withAnimation(.spring(response: 0.58, dampingFraction: 0.74)) {
            hasEntered = true
        }

        guard await pause(milliseconds: 520) else { return }

        withAnimation(.easeInOut(duration: 0.62)) {
            coverIsOpen = true
            paperGlowOpacity = 1
        }

        guard await pause(milliseconds: 660) else { return }
        coverIsBehindPages = true

        guard await pause(milliseconds: 120) else { return }

        if !pageImageSources.isEmpty {
            for page in 1...pageImageSources.count {
                withAnimation(.interpolatingSpring(stiffness: 190, damping: 23)) {
                    flippedPageCount = page
                }
                guard await pause(milliseconds: 115) else { return }
            }
        }

        guard await pause(milliseconds: 330) else { return }
        completeAnimation()
    }

    @MainActor
    private func resetAnimationState() {
        didComplete = false
        hasEntered = false
        coverIsOpen = false
        coverIsBehindPages = false
        flippedPageCount = 0
        paperGlowOpacity = 0
    }

    @MainActor
    private func completeAnimation() {
        guard !didComplete else { return }
        didComplete = true
        onAnimationComplete()
    }

    private func pause(milliseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    @MainActor
    private func resolveAnimationPageSources() -> [String?] {
        let bookID = book.id
        var descriptor = FetchDescriptor<Outfit>(
            predicate: #Predicate { outfit in
                outfit.book?.id == bookID &&
                outfit.isDeleted == false &&
                outfit.deletedAt == nil
            },
            sortBy: [
                SortDescriptor(\Outfit.sortIndex),
                SortDescriptor(\Outfit.createdAt)
            ]
        )
        descriptor.fetchLimit = maxPageCount

        let pages = (try? modelContext.fetch(descriptor)) ?? []
        return pages.map { page -> String? in
            guard page.shouldUseStoredSnapshot,
                  let snapshotPath = page.snapshotPath,
                  !snapshotPath.isEmpty else {
                return nil
            }
            return snapshotPath
        }
    }

    private func cachedAnimationImage(from source: String?) -> UIImage? {
        guard let source, !source.isEmpty else { return nil }
        return ImageManager.shared.cachedImage(fileName: source, targetSize: imageTargetSize)
    }

    @MainActor
    private func loadAnimationPageImages(_ pageSources: [String?]) async {
        let pages = await loadAnimationPageImages(from: pageSources)
        guard !Task.isCancelled else { return }
        pageImages = pages
    }

    private func loadAnimationPageImages(from sources: [String?]) async -> [UIImage?] {
        var images: [UIImage?] = Array(repeating: nil, count: sources.count)
        let targetSize = imageTargetSize

        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, source) in sources.enumerated() {
                guard let source, !source.isEmpty else { continue }

                group.addTask {
                    if let cached = await ImageManager.shared.cachedImage(fileName: source, targetSize: targetSize) {
                        return (index, cached)
                    }

                    let image = await ImageManager.shared.loadImageAsync(
                        fileName: source,
                        targetSize: targetSize,
                        priority: .userInitiated
                    )
                    return (index, image)
                }
            }

            for await (index, image) in group {
                images[index] = image
            }
        }

        return images
    }
}

// MARK: - Animation Pieces

private struct OpeningBookFrontCover: View {
    let book: BookGroup
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        BookCoverVisuals(book: book)
            .scaleEffect(x: width / 160, y: height / 220, anchor: .center)
            .frame(width: width, height: height)
    }
}

private struct OpeningBookBackCover: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "6F443D"),
                        Color(hex: "3F2827")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.black.opacity(0.2))
                    .frame(width: 24)
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.2), radius: 8, x: 4, y: 6)
    }
}

private struct OpeningPaperPage: View {
    let index: Int
    let width: CGFloat
    let height: CGFloat
    let glowOpacity: Double
    let image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "FFF8E6"),
                            Color(hex: "F2E4C9")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width - 18, height: height - 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(0..<8, id: \.self) { line in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "B99175").opacity(line == 0 ? 0.3 : 0.18))
                            .frame(width: lineWidth(for: line), height: line == 0 ? 4 : 2)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 30)

                Circle()
                    .fill(Color(hex: "EBA7AF").opacity(0.18 + Double(index) * 0.015))
                    .frame(width: 42, height: 42)
                    .offset(x: width * 0.27, y: -height * 0.28)
            }

            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.white.opacity(0.9 * glowOpacity), lineWidth: 1)
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.12), radius: 3, x: 2, y: 2)
    }

    private func lineWidth(for line: Int) -> CGFloat {
        let widths: [CGFloat] = [112, 132, 98, 126, 88, 116, 104, 72]
        return widths[line % widths.count]
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: BookGroup.self, configurations: config)
    let book = BookGroup(title: "Preview Book")

    return BookOpeningAnimationView(book: book) {
        print("Animation Completed")
    }
    .modelContainer(container)
}
