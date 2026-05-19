import Combine
import MetalKit
import SwiftUI

struct BookHouseSmallWorldView: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool

    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    @StateObject private var featureManager = FeatureUnlockManager.shared
    @StateObject private var layoutStore = BookHouseLayoutStore()

    @State private var selectedBook: HouseBook?
    @State private var transitionBook: HouseBook?
    @State private var transitionProgress = 0.0
    @State private var isBookOpen = false
    @State private var isPlacementMode = false
    @State private var selectedFeatureID: AppFeatureID?
    @State private var lockedFeature: AppFeatureDescriptor?
    @State private var showUnlockAlert = false

    private var activeBook: HouseBook {
        selectedBook ?? HouseBook.catalog[0]
    }

    var body: some View {
        ZStack {
            LiquidBackground(themeSkinWallpaperContext: .house)
                .ignoresSafeArea()

            if isBookOpen {
                BookHouseInteriorView(
                    book: activeBook,
                    nodes: nodes(for: activeBook),
                    layoutStore: layoutStore,
                    isPlacementMode: $isPlacementMode,
                    selectedFeatureID: $selectedFeatureID,
                    onBackToBooks: closeBook,
                    onResetLayout: { layoutStore.reset(bookID: activeBook.id) },
                    onOpenFeature: openFeature
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                BookHouseLibraryView(
                    books: HouseBook.catalog,
                    onOpenBook: openBook
                )
                .transition(.opacity)
            }

            if let transitionBook {
                BookOpeningOverlay(
                    book: transitionBook,
                    progress: transitionProgress
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: isBookOpen)
        .onDisappear {
            transitionBook = nil
            isBookOpen = false
            isPlacementMode = false
        }
        .sheet(item: $selectedFeatureID) { featureID in
            let feature = AppFeatureRegistry.descriptor(for: featureID)
            BookHouseFeatureSheet(
                feature: feature,
                onEnter: {
                    selectedFeatureID = nil
                    openFeature(feature)
                }
            )
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.visible)
        }
        .alert("功能未解锁", isPresented: $showUnlockAlert) {
            Button("知道了", role: .cancel) { }
            Button("去解锁") {
                NotificationCenter.default.post(name: .navigateToMagicTasks, object: nil)
            }
        } message: {
            if let unlockFeature = lockedFeature?.unlockFeature {
                let condition = featureManager.getCondition(for: unlockFeature)
                Text("\(lockedFeature?.title ?? "该功能") 尚未解锁\n\(condition.description)")
            } else {
                Text("该功能尚未解锁，请先完成对应任务")
            }
        }
    }

    private func nodes(for book: HouseBook) -> [BookHouseFeatureNode] {
        book.featureIDs.enumerated().map { index, featureID in
            BookHouseFeatureNode(
                feature: AppFeatureRegistry.descriptor(for: featureID),
                defaultPosition: book.defaultPositions[index % book.defaultPositions.count]
            )
        }
    }

    private func openBook(_ book: HouseBook) {
        guard transitionBook == nil else { return }
        selectedBook = book
        transitionBook = book
        transitionProgress = 0
        isPlacementMode = false

        withAnimation(.easeInOut(duration: 0.95)) {
            transitionProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.98) {
            isBookOpen = true
            transitionBook = nil
            transitionProgress = 0
        }
    }

    private func closeBook() {
        withAnimation(.easeInOut(duration: 0.24)) {
            isBookOpen = false
            isPlacementMode = false
            selectedFeatureID = nil
        }
    }

    private func openFeature(_ feature: AppFeatureDescriptor) {
        guard feature.isUnlocked else {
            lockedFeature = feature
            showUnlockAlert = true
            return
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            switch feature.route {
            case .tab(let tabIndex):
                selectedTab = tabIndex
            case .wardrobe(let tab):
                homeTab = tab
                selectedTab = 0
            case .smallWorld(let nextDestination):
                tabNavigationManager.markNavigatingInsideSmallWorld()
                destination = nextDestination
            }
        }
    }
}

private struct HouseBook: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let accentHex: String
    let featureIDs: [AppFeatureID]
    let defaultPositions: [CGPoint]

    var accent: Color { Color(hex: accentHex) }

    static let catalog: [HouseBook] = [
        HouseBook(
            id: "default-house",
            title: "默认 House",
            subtitle: "一本打开后可以自由布置的功能书",
            symbol: "book.closed.fill",
            accentHex: "EFA4BE",
            featureIDs: [.wardrobe, .outfitJournal, .magicSticker, .calendar, .wealth, .depositPlan, .bigWorld, .perler, .petHome, .petChat, .dressStock, .recycleBin],
            defaultPositions: [
                CGPoint(x: 0.18, y: 0.62), CGPoint(x: 0.34, y: 0.48), CGPoint(x: 0.49, y: 0.64),
                CGPoint(x: 0.66, y: 0.48), CGPoint(x: 0.82, y: 0.62), CGPoint(x: 0.28, y: 0.76),
                CGPoint(x: 0.52, y: 0.80), CGPoint(x: 0.74, y: 0.76), CGPoint(x: 0.22, y: 0.34),
                CGPoint(x: 0.78, y: 0.34), CGPoint(x: 0.42, y: 0.28), CGPoint(x: 0.60, y: 0.28)
            ]
        ),
        HouseBook(
            id: "creation-book",
            title: "创作书",
            subtitle: "手帐、贴纸、拼豆和空间创作",
            symbol: "paintpalette.fill",
            accentHex: "C9A7FF",
            featureIDs: [.outfitJournal, .magicSticker, .perler, .bigWorld],
            defaultPositions: [
                CGPoint(x: 0.24, y: 0.62), CGPoint(x: 0.44, y: 0.44),
                CGPoint(x: 0.60, y: 0.72), CGPoint(x: 0.78, y: 0.50)
            ]
        ),
        HouseBook(
            id: "daily-book",
            title: "日常书",
            subtitle: "衣橱、日历、来财和提醒",
            symbol: "books.vertical.fill",
            accentHex: "91C9F7",
            featureIDs: [.wardrobe, .depositPlan, .calendar, .wealth, .dressStock, .recycleBin],
            defaultPositions: [
                CGPoint(x: 0.20, y: 0.62), CGPoint(x: 0.36, y: 0.44), CGPoint(x: 0.52, y: 0.70),
                CGPoint(x: 0.68, y: 0.44), CGPoint(x: 0.82, y: 0.62), CGPoint(x: 0.50, y: 0.30)
            ]
        )
    ]
}

private struct BookHouseLibraryView: View {
    let books: [HouseBook]
    let onOpenBook: (HouseBook) -> Void

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: geometry.size.height * 0.09)

                VStack(alignment: .leading, spacing: 7) {
                    Text("House")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("选择一本书，打开后布置你的功能房间")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 18) {
                        ForEach(books) { book in
                            FlatHouseBookButton(book: book) {
                                onOpenBook(book)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                }

                Spacer()

                BookShelfBase()
                    .padding(.horizontal, 22)
                    .padding(.bottom, 92)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private struct FlatHouseBookButton: View {
    let book: HouseBook
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [book.accent.opacity(0.9), Color.white.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 188, height: 244)
                    .rotation3DEffect(.degrees(62), axis: (x: 1, y: 0, z: 0), perspective: 0.68)
                    .shadow(color: book.accent.opacity(0.28), radius: 22, x: 0, y: 20)

                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: book.symbol)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(book.accent.opacity(0.85), in: Circle())

                    Spacer()

                    Text(book.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(book.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(18)
                .frame(width: 188, height: 204, alignment: .topLeading)
            }
            .frame(width: 204, height: 250)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开\(book.title)")
    }
}

private struct BookShelfBase: View {
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "9E7058").opacity(0.42))
                .frame(height: 18)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: "5E3E35").opacity(0.18))
                .frame(height: 54)
        }
    }
}

private struct BookOpeningOverlay: View {
    let book: HouseBook
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                BookOpeningMetalTransitionView(progress: progress, accentHex: book.accentHex)
                    .frame(height: 360)
                    .padding(.horizontal, 18)

                Text(book.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("书脊变成柱子，封面与书背展开成墙")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.76))
            }
            .padding(.bottom, 32)
        }
    }
}

private struct BookHouseInteriorView: View {
    let book: HouseBook
    let nodes: [BookHouseFeatureNode]
    @ObservedObject var layoutStore: BookHouseLayoutStore
    @Binding var isPlacementMode: Bool
    @Binding var selectedFeatureID: AppFeatureID?
    let onBackToBooks: () -> Void
    let onResetLayout: () -> Void
    let onOpenFeature: (AppFeatureDescriptor) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                BookRoomBackground(accent: book.accent)

                ForEach(nodes) { node in
                    BookHouseFeatureNodeView(
                        node: node,
                        bookID: book.id,
                        normalizedPosition: layoutStore.position(for: node.feature.id, in: book.id, fallback: node.defaultPosition),
                        canvasSize: geometry.size,
                        isPlacementMode: isPlacementMode,
                        onTap: {
                            if isPlacementMode {
                                selectedFeatureID = nil
                            } else {
                                selectedFeatureID = node.feature.id
                            }
                        },
                        onMove: { position in
                            layoutStore.setPosition(position, for: node.feature.id, in: book.id)
                        }
                    )
                }

                VStack {
                    HStack(spacing: 10) {
                        Button(action: onBackToBooks) {
                            Image(systemName: "books.vertical.fill")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .bookHouseFloatingButtonStyle()

                        Spacer()

                        if isPlacementMode {
                            Button(action: onResetLayout) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .bookHouseFloatingButtonStyle()
                        }

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                isPlacementMode.toggle()
                            }
                        } label: {
                            Image(systemName: isPlacementMode ? "checkmark" : "hand.point.up.left.fill")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .bookHouseFloatingButtonStyle(active: isPlacementMode)
                        .accessibilityLabel(isPlacementMode ? "完成自由摆放" : "开启自由摆放模式")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 48)

                    Spacer()
                }

                VStack {
                    Spacer()
                    Text(isPlacementMode ? "自由摆放中：拖动物件调整入口位置" : "点击物件查看功能，右上角可进入自由摆放")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.72))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 96)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }
}

private struct BookRoomBackground: View {
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "FFF7EF"), Color(hex: "F3DCE6"), Color(hex: "DDEAF4")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                wallShape(left: true)
                    .fill(Color(hex: "FFF5E8").opacity(0.94))
                    .overlay(wallShape(left: true).stroke(accent.opacity(0.26), lineWidth: 1.2))
                    .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 8)

                wallShape(left: false)
                    .fill(Color(hex: "FFFDF4").opacity(0.94))
                    .overlay(wallShape(left: false).stroke(accent.opacity(0.26), lineWidth: 1.2))
                    .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 8)

                floorShape
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "F7D6B7"), Color(hex: "FBE8D5")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(floorShape.stroke(Color.white.opacity(0.46), lineWidth: 1.2))
                    .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: -2)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "C68A54"), Color(hex: "F2C576"), Color(hex: "8E5A35")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: max(16, geometry.size.width * 0.035), height: geometry.size.height * 0.58)
                    .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.38)
                    .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
            }
        }
    }

    private var floorShape: NormalizedPolygon {
        NormalizedPolygon(points: [
            CGPoint(x: 0.08, y: 0.58),
            CGPoint(x: 0.92, y: 0.58),
            CGPoint(x: 0.74, y: 0.94),
            CGPoint(x: 0.26, y: 0.94)
        ])
    }

    private func wallShape(left: Bool) -> NormalizedPolygon {
        if left {
            return NormalizedPolygon(points: [
                CGPoint(x: 0.08, y: 0.18),
                CGPoint(x: 0.50, y: 0.08),
                CGPoint(x: 0.50, y: 0.58),
                CGPoint(x: 0.08, y: 0.58)
            ])
        }
        return NormalizedPolygon(points: [
            CGPoint(x: 0.50, y: 0.08),
            CGPoint(x: 0.92, y: 0.18),
            CGPoint(x: 0.92, y: 0.58),
            CGPoint(x: 0.50, y: 0.58)
        ])
    }
}

private struct BookHouseFeatureNode: Identifiable {
    let feature: AppFeatureDescriptor
    let defaultPosition: CGPoint

    var id: AppFeatureID { feature.id }

    var assetName: String {
        switch feature.id {
        case .wardrobe:
            return "book_house_wardrobe"
        case .depositPlan:
            return "book_house_deposit_plan"
        case .house:
            return "book_house_outfit_journal"
        case .me:
            return "book_house_pet_chat"
        case .petHome:
            return "book_house_pet_home"
        case .petChat:
            return "book_house_pet_chat"
        case .magicSticker:
            return "book_house_magic_sticker"
        case .outfitJournal:
            return "book_house_outfit_journal"
        case .wealth:
            return "book_house_wealth"
        case .calendar:
            return "book_house_calendar"
        case .bigWorld:
            return "book_house_big_world"
        case .perler:
            return "book_house_perler"
        case .dressStock:
            return "book_house_dress_stock"
        case .recycleBin:
            return "book_house_recycle_bin"
        }
    }
}

private struct BookHouseFeatureNodeView: View {
    let node: BookHouseFeatureNode
    let bookID: String
    let normalizedPosition: CGPoint
    let canvasSize: CGSize
    let isPlacementMode: Bool
    let onTap: () -> Void
    let onMove: (CGPoint) -> Void

    @State private var dragStart: CGPoint?

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                ZStack(alignment: .bottomTrailing) {
                    Image(node.assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 70, height: 64)
                        .saturation(node.feature.isUnlocked ? 1 : 0)
                        .opacity(node.feature.isUnlocked ? 1 : 0.38)
                        .shadow(color: Color(hex: node.feature.tintHex).opacity(node.feature.isUnlocked ? 0.22 : 0.05), radius: 8, x: 0, y: 5)

                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                        Circle()
                            .stroke(Color(hex: node.feature.tintHex).opacity(0.45), lineWidth: 1)
                        Image(systemName: node.feature.isUnlocked ? node.feature.systemImage : "lock.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(node.feature.isUnlocked ? Color(hex: node.feature.tintHex) : .secondary)
                    }
                    .frame(width: 26, height: 26)
                    .offset(x: 4, y: 2)
                }
                .frame(width: 76, height: 68)

                Text(node.feature.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isPlacementMode ? 0.70 : 0.42))
                    .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isPlacementMode ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.45), lineWidth: 1)
            )
        }
        .captureGuideTarget(guideTarget(for: node.feature.id))
        .buttonStyle(.plain)
        .position(
            x: normalizedPosition.x * canvasSize.width,
            y: normalizedPosition.y * canvasSize.height
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard isPlacementMode else { return }
                    let start = dragStart ?? normalizedPosition
                    dragStart = start
                    onMove(
                        CGPoint(
                            x: clamp(start.x + value.translation.width / max(1, canvasSize.width), 0.08, 0.92),
                            y: clamp(start.y + value.translation.height / max(1, canvasSize.height), 0.16, 0.88)
                        )
                    )
                }
                .onEnded { _ in dragStart = nil }
        )
        .accessibilityLabel(node.feature.title)
    }

    private func clamp(_ value: CGFloat, _ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
    }

    private func guideTarget(for featureID: AppFeatureID) -> GuideTargetKey? {
        switch featureID {
        case .outfitJournal:
            return .ootdEntry
        case .wealth:
            return .wealthEntry
        case .calendar:
            return .calendarEntry
        default:
            return nil
        }
    }
}

private struct BookHouseFeatureSheet: View {
    let feature: AppFeatureDescriptor
    let onEnter: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: feature.systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color(hex: feature.tintHex))
                    .frame(width: 58, height: 58)
                    .background(Color(hex: feature.tintHex).opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.title)
                        .font(.title3.weight(.bold))
                    Text(feature.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 12) {
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button(feature.isUnlocked ? "进入" : "查看解锁条件") {
                    onEnter()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
    }
}

private final class BookHouseLayoutStore: ObservableObject {
    @Published private var positions: [String: CGPoint] = [:]

    private let defaultsKey = "bookHouse.itemPositions.v1"

    init() {
        load()
    }

    func position(for featureID: AppFeatureID, in bookID: String, fallback: CGPoint) -> CGPoint {
        positions[key(bookID: bookID, featureID: featureID)] ?? fallback
    }

    func setPosition(_ position: CGPoint, for featureID: AppFeatureID, in bookID: String) {
        positions[key(bookID: bookID, featureID: featureID)] = position
        save()
    }

    func reset(bookID: String) {
        positions = positions.filter { !$0.key.hasPrefix("\(bookID)::") }
        save()
    }

    private func key(bookID: String, featureID: AppFeatureID) -> String {
        "\(bookID)::\(featureID.rawValue)"
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([String: StoredPoint].self, from: data)
        else { return }

        positions = decoded.mapValues { CGPoint(x: $0.x, y: $0.y) }
    }

    private func save() {
        let encoded = positions.mapValues { StoredPoint(x: $0.x, y: $0.y) }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private struct StoredPoint: Codable {
        let x: CGFloat
        let y: CGFloat
    }
}

private extension View {
    func bookHouseFloatingButtonStyle(active: Bool = false) -> some View {
        self
            .foregroundStyle(active ? Color.white : Color.primary)
            .frame(width: 44, height: 44)
            .background(active ? Color.accentColor : Color.white.opacity(0.74), in: Circle())
            .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 6)
    }
}

private struct BookOpeningMetalTransitionView: UIViewRepresentable {
    let progress: Double
    let accentHex: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        context.coordinator.attach(view: view)
        context.coordinator.progress = Float(progress)
        context.coordinator.accent = BookMetalColor(hex: accentHex).simd
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.attach(view: uiView)
        context.coordinator.progress = Float(progress)
        context.coordinator.accent = BookMetalColor(hex: accentHex).simd
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        var progress: Float = 0
        var accent = SIMD4<Float>(0.93, 0.64, 0.74, 1)

        private weak var view: MTKView?
        private var commandQueue: MTLCommandQueue?
        private var pipelineState: MTLRenderPipelineState?

        func attach(view: MTKView) {
            self.view = view
            guard commandQueue == nil, let device = view.device else { return }
            commandQueue = device.makeCommandQueue()
            pipelineState = makePipeline(device: device, pixelFormat: view.colorPixelFormat)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            _ = size
        }

        func draw(in view: MTKView) {
            guard
                let drawable = view.currentDrawable,
                let descriptor = view.currentRenderPassDescriptor,
                let commandQueue,
                let pipelineState,
                let commandBuffer = commandQueue.makeCommandBuffer()
            else { return }

            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            descriptor.colorAttachments[0].storeAction = .store

            let vertices = BookOpeningGeometry.vertices(progress: progress, accent: accent)
            guard let buffer = view.device?.makeBuffer(
                bytes: vertices,
                length: MemoryLayout<BookMetalVertex>.stride * vertices.count
            ) else { return }

            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
            encoder?.setRenderPipelineState(pipelineState)
            encoder?.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            encoder?.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        private func makePipeline(device: MTLDevice, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
            guard let library = try? device.makeLibrary(source: Self.shaderSource, options: nil) else {
                return nil
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "book_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: "book_fragment")
            descriptor.colorAttachments[0].pixelFormat = pixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }

        private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct Vertex {
            float2 position;
            float4 color;
        };

        struct VertexOut {
            float4 position [[position]];
            float4 color;
        };

        vertex VertexOut book_vertex(const device Vertex *vertices [[buffer(0)]], uint vid [[vertex_id]]) {
            VertexOut out;
            out.position = float4(vertices[vid].position, 0.0, 1.0);
            out.color = vertices[vid].color;
            return out;
        }

        fragment float4 book_fragment(VertexOut in [[stage_in]]) {
            return in.color;
        }
        """
    }
}

private struct BookMetalVertex {
    let position: SIMD2<Float>
    let color: SIMD4<Float>
}

private enum BookOpeningGeometry {
    static func vertices(progress: Float, accent: SIMD4<Float>) -> [BookMetalVertex] {
        let p = smooth(min(max(progress, 0), 1))
        var vertices: [BookMetalVertex] = []

        let paper = SIMD4<Float>(1.0, 0.94, 0.84, 0.96)
        let paperSide = SIMD4<Float>(0.98, 0.80, 0.70, 0.96)
        let gold = SIMD4<Float>(0.92, 0.64, 0.28, 0.98)
        let floor = mix(accent, SIMD4<Float>(0.98, 0.82, 0.68, 0.96), 0.72)

        appendQuad(
            &vertices,
            points: [
                interp(SIMD2<Float>(-0.62, -0.50), SIMD2<Float>(-0.62, -0.10), p),
                interp(SIMD2<Float>(0.00, -0.72), SIMD2<Float>(0.00, 0.08), p),
                interp(SIMD2<Float>(0.00, -0.18), SIMD2<Float>(0.00, 0.70), p),
                interp(SIMD2<Float>(-0.62, 0.02), SIMD2<Float>(-0.62, 0.42), p)
            ],
            color: paper
        )

        appendQuad(
            &vertices,
            points: [
                interp(SIMD2<Float>(0.00, -0.72), SIMD2<Float>(0.00, 0.08), p),
                interp(SIMD2<Float>(0.62, -0.50), SIMD2<Float>(0.62, -0.10), p),
                interp(SIMD2<Float>(0.62, 0.02), SIMD2<Float>(0.62, 0.42), p),
                interp(SIMD2<Float>(0.00, -0.18), SIMD2<Float>(0.00, 0.70), p)
            ],
            color: paperSide
        )

        appendQuad(
            &vertices,
            points: [
                interp(SIMD2<Float>(-0.62, -0.50), SIMD2<Float>(-0.62, -0.10), p),
                interp(SIMD2<Float>(0.62, -0.50), SIMD2<Float>(0.62, -0.10), p),
                interp(SIMD2<Float>(0.38, -0.78), SIMD2<Float>(0.42, -0.72), p),
                interp(SIMD2<Float>(-0.38, -0.78), SIMD2<Float>(-0.42, -0.72), p)
            ],
            color: floor
        )

        appendQuad(
            &vertices,
            points: [
                interp(SIMD2<Float>(-0.04, -0.70), SIMD2<Float>(-0.035, 0.02), p),
                interp(SIMD2<Float>(0.04, -0.70), SIMD2<Float>(0.035, 0.02), p),
                interp(SIMD2<Float>(0.04, -0.16), SIMD2<Float>(0.035, 0.78), p),
                interp(SIMD2<Float>(-0.04, -0.16), SIMD2<Float>(-0.035, 0.78), p)
            ],
            color: gold
        )

        return vertices
    }

    private static func appendQuad(_ vertices: inout [BookMetalVertex], points: [SIMD2<Float>], color: SIMD4<Float>) {
        guard points.count == 4 else { return }
        vertices.append(contentsOf: [
            BookMetalVertex(position: points[0], color: color),
            BookMetalVertex(position: points[1], color: color),
            BookMetalVertex(position: points[2], color: color),
            BookMetalVertex(position: points[0], color: color),
            BookMetalVertex(position: points[2], color: color),
            BookMetalVertex(position: points[3], color: color)
        ])
    }

    private static func interp(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ t: Float) -> SIMD2<Float> {
        a + (b - a) * t
    }

    private static func smooth(_ t: Float) -> Float {
        t * t * (3 - 2 * t)
    }

    private static func mix(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
        a + (b - a) * t
    }
}

private struct BookMetalColor {
    let simd: SIMD4<Float>

    init(hex: String) {
        let sanitized = hex.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)
        let r = Float((value >> 16) & 0xff) / 255
        let g = Float((value >> 8) & 0xff) / 255
        let b = Float(value & 0xff) / 255
        simd = SIMD4<Float>(r, g, b, 1)
    }
}

private struct NormalizedPolygon: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: scale(first, in: rect))
        for point in points.dropFirst() {
            path.addLine(to: scale(point, in: rect))
        }
        path.closeSubpath()
        return path
    }

    private func scale(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }
}
