import Combine
import SwiftUI

struct BookHouseSmallWorldView: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool

    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    @StateObject private var featureManager = FeatureUnlockManager.shared
    @StateObject private var layoutStore = BookHouseLayoutStore()

    @State private var isPlacementMode = false
    @State private var selectedFeatureID: AppFeatureID?
    @State private var lockedFeature: AppFeatureDescriptor?
    @State private var showUnlockAlert = false

    var body: some View {
        BookHousePrototypeStage(
            rooms: BookHousePrototypeData.rooms,
            layoutStore: layoutStore,
            isPlacementMode: $isPlacementMode,
            selectedFeatureID: $selectedFeatureID,
            onResetLayout: resetAllRooms,
            onOpenFeature: openFeature
        )
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
        .onDisappear {
            isPlacementMode = false
            selectedFeatureID = nil
        }
    }

    private func resetAllRooms() {
        for room in BookHousePrototypeData.rooms {
            layoutStore.reset(roomID: room.id)
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

private struct BookHousePrototypeStage: View {
    let rooms: [BookHousePrototypeRoom]
    @ObservedObject var layoutStore: BookHouseLayoutStore
    @Binding var isPlacementMode: Bool
    @Binding var selectedFeatureID: AppFeatureID?
    let onResetLayout: () -> Void
    let onOpenFeature: (AppFeatureDescriptor) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LiquidBackground(themeSkinWallpaperContext: .house)
                    .ignoresSafeArea()

                BookHouseStageAtmosphere()
                    .ignoresSafeArea()

                ForEach(rooms) { room in
                    roomView(room, in: geometry)
                }

                BookHouseTopChrome(
                    isPlacementMode: $isPlacementMode,
                    onResetLayout: onResetLayout,
                    onOpenFeature: onOpenFeature
                )
                .padding(.top, geometry.safeAreaInsets.top + 38)
                .padding(.horizontal, 22)
                .frame(maxHeight: .infinity, alignment: .top)

                if isPlacementMode {
                    placementHint(in: geometry)
                }

                Image("naicha_peeking")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(92, geometry.size.width * 0.23), height: 58)
                    .position(
                        x: geometry.size.width * 0.5,
                        y: geometry.size.height - geometry.safeAreaInsets.bottom - 124
                    )
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func roomView(_ room: BookHousePrototypeRoom, in geometry: GeometryProxy) -> some View {
        let roomWidth = room.slot.width(for: geometry.size.width)
        let roomHeight = roomWidth * BookHouseRoomSlot.aspectRatio

        PrototypeBookRoomView(
            room: room,
            roomSize: CGSize(width: roomWidth, height: roomHeight),
            layoutStore: layoutStore,
            isPlacementMode: isPlacementMode,
            selectedFeatureID: $selectedFeatureID
        )
        .frame(width: roomWidth, height: roomHeight)
        .position(room.slot.position(in: geometry))
        .zIndex(room.slot.zIndex)
    }

    private func placementHint(in geometry: GeometryProxy) -> some View {
        Text("拖动物件调整入口位置")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(hex: "7B5E61"))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white.opacity(0.78), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.8), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 5)
            .position(
                x: geometry.size.width * 0.5,
                y: geometry.size.height - geometry.safeAreaInsets.bottom - 158
            )
    }
}

private struct BookHouseStageAtmosphere: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared

    var body: some View {
        GeometryReader { geometry in
            let isDark = colorScheme == .dark
            let hasThemeSkin = themeSkinManager.activeProduct != nil

            ZStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(isDark ? 0.02 : (hasThemeSkin ? 0.06 : 0.18)),
                        Color.clear,
                        themeManager.accentTextColor.opacity(isDark ? 0.05 : (hasThemeSkin ? 0.04 : 0.08))
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if !hasThemeSkin {
                    BookHousePaperTexture(
                        accent: themeManager.accentTextColor,
                        isDark: isDark
                    )
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDark ? 0.04 : (hasThemeSkin ? 0.14 : 0.38)),
                            themeManager.backgroundColor.opacity(isDark ? 0.14 : (hasThemeSkin ? 0.16 : 0.34)),
                            themeManager.accentTextColor.opacity(isDark ? 0.08 : (hasThemeSkin ? 0.06 : 0.12))
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: min(geometry.size.height * 0.34, 300))
                    .blur(radius: hasThemeSkin ? 8 : 16)
                    .offset(y: 50)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BookHousePaperTexture: View {
    let accent: Color
    let isDark: Bool

    var body: some View {
        GeometryReader { geometry in
            let spacing = max(68, geometry.size.width / 5.4)

            ZStack {
                Path { path in
                    var y = -spacing
                    while y < geometry.size.height + spacing {
                        path.move(to: CGPoint(x: -24, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width + 24, y: y + spacing * 0.28))
                        y += spacing
                    }
                }
                .stroke(Color.white.opacity(isDark ? 0.035 : 0.18), lineWidth: 1)

                Path { path in
                    var x = -spacing
                    while x < geometry.size.width + spacing {
                        path.move(to: CGPoint(x: x, y: -24))
                        path.addLine(to: CGPoint(x: x + spacing * 0.2, y: geometry.size.height + 24))
                        x += spacing
                    }
                }
                .stroke(accent.opacity(isDark ? 0.025 : 0.055), lineWidth: 0.8)
            }
        }
    }
}

private struct BookHouseTopChrome: View {
    @Binding var isPlacementMode: Bool
    let onResetLayout: () -> Void
    let onOpenFeature: (AppFeatureDescriptor) -> Void
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HomeThemeSkinToolbarShell(
                descriptor: topBarSegmentDescriptor,
                style: .segment,
                horizontalPadding: 5,
                verticalPadding: 5
            ) {
                HStack(spacing: 0) {
                    topTabButton(
                        title: "少女衣橱",
                        systemImage: "cabinet.fill",
                        featureID: .wardrobe
                    )

                    topTabButton(
                        title: "心愿尾款",
                        systemImage: "calendar.badge.clock",
                        featureID: .depositPlan
                    )
                }
            }

            Spacer(minLength: 8)

            HomeThemeSkinToolbarShell(
                descriptor: topBarMainDescriptor,
                style: .group,
                horizontalPadding: 6,
                verticalPadding: 6
            ) {
                HStack(spacing: 4) {
                    iconButton(
                        isPlacementMode ? "checkmark" : "arrow.up.and.down.and.arrow.left.and.right",
                        active: isPlacementMode
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            isPlacementMode.toggle()
                        }
                    }

                    iconButton("yensign.circle", featureID: .wealth)
                    iconButton("book.pages", featureID: .outfitJournal)
                    iconButton("bell", featureID: .calendar)
                    iconButton("ellipsis.circle", featureID: .petChat)

                    iconButton("plus") {
                        onResetLayout()
                    }
                }
            }
        }
    }

    private func topTabButton(title: String, systemImage: String, featureID: AppFeatureID) -> some View {
        Button {
            onOpenFeature(AppFeatureRegistry.descriptor(for: featureID))
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color(hex: featureID == .wardrobe ? "8E8288" : "D79AAD"))
                .themeSkinLegibleText(level: .chip, slot: .topBarSegment, descriptor: topBarSegmentDescriptor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 62, height: 34)
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ systemImage: String, featureID: AppFeatureID) -> some View {
        iconButton(systemImage) {
            onOpenFeature(AppFeatureRegistry.descriptor(for: featureID))
        }
    }

    private func iconButton(_ systemImage: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color(hex: "5F565C"))
                .themeSkinLegibleSymbol(level: .badge, slot: .topBarIconButton, descriptor: topBarIconButtonDescriptor)
                .frame(width: 28, height: 28)
                .background(active ? Color(hex: "E59AB0") : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemImage)
    }

    private var topBarMainDescriptor: ThemeSkinDescriptor? {
        themedDescriptor(for: .topBarMain)
    }

    private var topBarSegmentDescriptor: ThemeSkinDescriptor? {
        themedDescriptor(for: .topBarSegment)
    }

    private var topBarIconButtonDescriptor: ThemeSkinDescriptor? {
        themedDescriptor(for: .topBarIconButton)
    }

    private func themedDescriptor(for slot: ThemeSkinSlot) -> ThemeSkinDescriptor? {
        guard let descriptor = themeSkinManager.activeThemeDescriptor(for: slot, state: .default),
              WardrobeThemeSkinSupport.isThemeSkinDescriptor(descriptor) else {
            return nil
        }
        return descriptor
    }
}

private struct PrototypeBookRoomView: View {
    let room: BookHousePrototypeRoom
    let roomSize: CGSize
    @ObservedObject var layoutStore: BookHouseLayoutStore
    let isPlacementMode: Bool
    @Binding var selectedFeatureID: AppFeatureID?

    var body: some View {
        ZStack {
            BookHouseRoomPedestalShadow(roomSize: roomSize)

            Image("book_house_room_shell")
                .resizable()
                .scaledToFit()
                .shadow(color: Color(hex: "604A35").opacity(0.22), radius: 14, x: 0, y: 10)

            ForEach(room.items) { item in
                PrototypeRoomItemView(
                    item: item,
                    roomID: room.id,
                    normalizedPosition: layoutStore.position(for: item.feature.id, in: room.id, fallback: item.defaultPosition),
                    roomSize: roomSize,
                    isPlacementMode: isPlacementMode,
                    onTap: {
                        guard !isPlacementMode else { return }
                        selectedFeatureID = item.feature.id
                    },
                    onMove: { position in
                        layoutStore.setPosition(position, for: item.feature.id, in: room.id)
                    }
                )
            }
        }
        .frame(width: roomSize.width, height: roomSize.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(room.title)
    }
}

private struct BookHouseRoomPedestalShadow: View {
    let roomSize: CGSize

    var body: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "7B6048").opacity(0.18),
                        Color(hex: "7B6048").opacity(0.04)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(
                width: roomSize.width * 0.78,
                height: max(24, roomSize.height * 0.13)
            )
            .blur(radius: 8)
            .offset(y: roomSize.height * 0.38)
    }
}

private struct PrototypeRoomItemView: View {
    let item: BookHouseRoomItem
    let roomID: String
    let normalizedPosition: CGPoint
    let roomSize: CGSize
    let isPlacementMode: Bool
    let onTap: () -> Void
    let onMove: (CGPoint) -> Void

    @State private var dragStart: CGPoint?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                Image(item.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: item.size.width, height: item.size.height)
                    .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 4)

                if isPlacementMode {
                    Image(systemName: item.feature.systemImage)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(hex: item.feature.tintHex))
                        .frame(width: 20, height: 20)
                        .background(.white.opacity(0.86), in: Circle())
                        .overlay(Circle().stroke(Color(hex: item.feature.tintHex).opacity(0.34), lineWidth: 1))
                        .offset(x: 4, y: -4)
                }
            }
            .frame(width: max(item.size.width, 46), height: max(item.size.height, 46))
            .overlay {
                if isPlacementMode {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: "E59AB0").opacity(0.75), style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                }
            }
            .contentShape(Rectangle())
        }
        .captureGuideTarget(guideTarget(for: item.feature.id))
        .buttonStyle(.plain)
        .position(
            x: normalizedPosition.x * roomSize.width,
            y: normalizedPosition.y * roomSize.height
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard isPlacementMode else { return }
                    let start = dragStart ?? normalizedPosition
                    dragStart = start
                    onMove(
                        CGPoint(
                            x: clamp(start.x + value.translation.width / max(1, roomSize.width), 0.12, 0.88),
                            y: clamp(start.y + value.translation.height / max(1, roomSize.height), 0.18, 0.88)
                        )
                    )
                }
                .onEnded { _ in
                    dragStart = nil
                }
        )
        .accessibilityLabel(item.feature.title)
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

private enum BookHousePrototypeData {
    static let rooms: [BookHousePrototypeRoom] = [
        BookHousePrototypeRoom(
            id: "book-house-main",
            title: "主书页房间",
            slot: .top,
            items: [
                item(.wardrobe, assetName: "book_house_wardrobe", x: 0.52, y: 0.52, width: 60, height: 88),
                item(.magicSticker, assetName: "book_house_magic_sticker", x: 0.30, y: 0.66, width: 42, height: 34),
                item(.depositPlan, assetName: "book_house_deposit_plan", x: 0.74, y: 0.70, width: 48, height: 43),
                item(.outfitJournal, assetName: "book_house_outfit_journal", x: 0.50, y: 0.82, width: 48, height: 34)
            ]
        ),
        BookHousePrototypeRoom(
            id: "book-house-daily",
            title: "日常书页房间",
            slot: .left,
            items: [
                item(.calendar, assetName: "book_house_calendar", x: 0.28, y: 0.64, width: 42, height: 50),
                item(.wealth, assetName: "book_house_wealth", x: 0.47, y: 0.80, width: 50, height: 48),
                item(.bigWorld, assetName: "book_house_big_world", x: 0.70, y: 0.69, width: 42, height: 55)
            ]
        ),
        BookHousePrototypeRoom(
            id: "book-house-comfort",
            title: "收藏书页房间",
            slot: .right,
            items: [
                item(.dressStock, assetName: "book_house_dress_stock", x: 0.68, y: 0.43, width: 52, height: 50),
                item(.petHome, assetName: "book_house_phone", x: 0.40, y: 0.78, width: 46, height: 42),
                item(.petChat, assetName: "book_house_vanity", x: 0.57, y: 0.77, width: 42, height: 40),
                item(.perler, assetName: "book_house_perler", x: 0.33, y: 0.66, width: 42, height: 34)
            ]
        )
    ]

    private static func item(
        _ featureID: AppFeatureID,
        assetName: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> BookHouseRoomItem {
        BookHouseRoomItem(
            feature: AppFeatureRegistry.descriptor(for: featureID),
            assetName: assetName,
            defaultPosition: CGPoint(x: x, y: y),
            size: CGSize(width: width, height: height)
        )
    }
}

private struct BookHousePrototypeRoom: Identifiable {
    let id: String
    let title: String
    let slot: BookHouseRoomSlot
    let items: [BookHouseRoomItem]
}

private enum BookHouseRoomSlot {
    case top
    case left
    case right

    static let aspectRatio: CGFloat = 365.0 / 320.0

    var zIndex: Double {
        switch self {
        case .top: return 3
        case .left: return 2
        case .right: return 1
        }
    }

    func width(for screenWidth: CGFloat) -> CGFloat {
        switch self {
        case .top:
            return min(screenWidth * 0.45, 188)
        case .left, .right:
            return min(screenWidth * 0.42, 174)
        }
    }

    func position(in geometry: GeometryProxy) -> CGPoint {
        let size = geometry.size
        let topY = max(geometry.safeAreaInsets.top + 254, size.height * 0.36)
        let bottomY = max(topY + min(size.width * 0.39, 156), size.height * 0.58)

        switch self {
        case .top:
            return CGPoint(x: size.width * 0.50, y: topY)
        case .left:
            return CGPoint(x: size.width * 0.31, y: bottomY)
        case .right:
            return CGPoint(x: size.width * 0.69, y: bottomY)
        }
    }
}

private struct BookHouseRoomItem: Identifiable {
    let feature: AppFeatureDescriptor
    let assetName: String
    let defaultPosition: CGPoint
    let size: CGSize

    var id: AppFeatureID { feature.id }
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

    private let defaultsKey = "bookHouse.prototypeItemPositions.v2"

    init() {
        load()
    }

    func position(for featureID: AppFeatureID, in roomID: String, fallback: CGPoint) -> CGPoint {
        positions[key(roomID: roomID, featureID: featureID)] ?? fallback
    }

    func setPosition(_ position: CGPoint, for featureID: AppFeatureID, in roomID: String) {
        positions[key(roomID: roomID, featureID: featureID)] = position
        save()
    }

    func reset(roomID: String) {
        positions = positions.filter { !$0.key.hasPrefix("\(roomID)::") }
        save()
    }

    private func key(roomID: String, featureID: AppFeatureID) -> String {
        "\(roomID)::\(featureID.rawValue)"
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
