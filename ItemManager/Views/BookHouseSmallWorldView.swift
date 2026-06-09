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
    @State private var selectedPlacementItem: BookHouseEditableItemSelection?
    @State private var selectedFeatureID: AppFeatureID?
    @State private var lockedFeature: AppFeatureDescriptor?
    @State private var showUnlockAlert = false

    var body: some View {
        BookHousePrototypeStage(
            rooms: BookHousePrototypeData.rooms,
            layoutStore: layoutStore,
            isPlacementMode: $isPlacementMode,
            selectedPlacementItem: $selectedPlacementItem,
            selectedFeatureID: $selectedFeatureID,
            onResetLayout: resetAllRooms
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
            .presentationDetents([.height(292)])
            .presentationDragIndicator(.visible)
        }
        .alert("功能未解锁".appLocalized, isPresented: $showUnlockAlert) {
            Button("知道了".appLocalized, role: .cancel) { }
            Button("去解锁".appLocalized) {
                NotificationCenter.default.post(name: .navigateToMagicTasks, object: nil)
            }
        } message: {
            if let unlockFeature = lockedFeature?.unlockFeature {
                let condition = featureManager.getCondition(for: unlockFeature)
                let title = lockedFeature?.localizedTitle ?? "该功能".appLocalized
                Text("「%@」尚未解锁\n%@".appLocalized(title, condition.localizedDescription))
            } else {
                Text("该功能尚未解锁，请先完成对应任务".appLocalized)
            }
        }
        .onDisappear {
            isPlacementMode = false
            selectedPlacementItem = nil
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
    @Binding var selectedPlacementItem: BookHouseEditableItemSelection?
    @Binding var selectedFeatureID: AppFeatureID?
    let onResetLayout: () -> Void
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

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

                BookHouseLayoutControls(
                    isPlacementMode: $isPlacementMode,
                    onResetLayout: {
                        selectedPlacementItem = nil
                        onResetLayout()
                    }
                )
                .padding(.top, geometry.safeAreaInsets.top + 82)
                .padding(.trailing, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                if isPlacementMode {
                    placementHint(in: geometry)
                }

            }
        }
        .ignoresSafeArea()
        .onChange(of: isPlacementMode) { _, newValue in
            if !newValue {
                selectedPlacementItem = nil
            }
        }
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
            selectedPlacementItem: $selectedPlacementItem,
            selectedFeatureID: $selectedFeatureID
        )
        .frame(width: roomWidth, height: roomHeight)
        .position(room.slot.position(in: geometry))
        .zIndex(room.slot.zIndex)
    }

    private func placementHint(in geometry: GeometryProxy) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 12, weight: .bold))
            Text("拖动物件调整入口位置".appLocalized)
        }
            .font(.caption.weight(.semibold))
            .foregroundStyle(themeManager.accentTextColor)
            .themeSkinLegibleText(level: .chip, slot: .sectionCard)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 18, showsDecoration: false) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.78 : 0.88))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.64), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 10, x: 0, y: 5)
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

private struct BookHouseLayoutControls: View {
    @Binding var isPlacementMode: Bool
    let onResetLayout: () -> Void
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            if isPlacementMode {
                controlButton(systemImage: "arrow.counterclockwise", label: "恢复默认摆放".appLocalized) {
                    onResetLayout()
                }
                .transition(.scale.combined(with: .opacity))
            }

            controlButton(
                systemImage: isPlacementMode ? "checkmark" : "arrow.up.and.down.and.arrow.left.and.right",
                label: isPlacementMode ? "完成整理".appLocalized : "整理房间".appLocalized,
                active: isPlacementMode
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    isPlacementMode.toggle()
                }
            }
        }
        .padding(6)
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 26, showsDecoration: false) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.78 : 0.90))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.70), lineWidth: 1)
                }
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.26 : 0.10), radius: 10, x: 0, y: 5)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: isPlacementMode)
    }

    private func controlButton(systemImage: String, label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if active {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    themeManager.accentTextColor.opacity(0.96),
                                    themeManager.accentTextColor.opacity(0.74)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.58), lineWidth: 1)
                        }

                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .themeSkinLegibleSymbol(level: .badge, slot: .iconCircleButton)
                } else {
                    ThemeSkinIconBadge(
                        systemName: systemImage,
                        fallbackColor: themeManager.accentTextColor,
                        size: 38,
                        symbolSize: 15
                    )
                }
            }
            .frame(width: 40, height: 40)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct PrototypeBookRoomView: View {
    let room: BookHousePrototypeRoom
    let roomSize: CGSize
    @ObservedObject var layoutStore: BookHouseLayoutStore
    let isPlacementMode: Bool
    @Binding var selectedPlacementItem: BookHouseEditableItemSelection?
    @Binding var selectedFeatureID: AppFeatureID?
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared

    var body: some View {
        let isDark = colorScheme == .dark
        let hasThemeSkin = themeSkinManager.activeProduct != nil

        ZStack {
            BookHouseRoomPedestalShadow(roomSize: roomSize)

            Image("book_house_room_shell")
                .resizable()
                .scaledToFit()
                .overlay {
                    BookHouseRoomOpulenceOverlay(
                        accent: themeManager.accentTextColor,
                        isDark: isDark,
                        hasThemeSkin: hasThemeSkin
                    )
                }
                .overlay {
                    BookHouseRoomPageEdgeOverlay(isDark: isDark, hasThemeSkin: hasThemeSkin)
                }
                .shadow(color: Color(hex: "604A35").opacity(isDark ? 0.34 : 0.24), radius: 16, x: 0, y: 12)
                .shadow(color: Color.white.opacity(isDark ? 0.02 : (hasThemeSkin ? 0.08 : 0.18)), radius: 5, x: 0, y: -2)

            ForEach(room.decorations) { decoration in
                BookHouseRoomDecorationView(
                    decoration: decoration,
                    roomSize: roomSize
                )
            }

            ForEach(room.items) { item in
                let selection = BookHouseEditableItemSelection(roomID: room.id, featureID: item.feature.id)
                let layout = layoutStore.layout(for: item.feature.id, in: room.id, fallback: item.defaultLayout)

                PrototypeRoomItemView(
                    item: item,
                    layout: layout,
                    roomSize: roomSize,
                    isPlacementMode: isPlacementMode,
                    isSelected: selectedPlacementItem == selection,
                    onSelect: {
                        selectedPlacementItem = selection
                    },
                    onTap: {
                        guard !isPlacementMode else { return }
                        selectedFeatureID = item.feature.id
                    },
                    onMove: { position in
                        layoutStore.setPosition(position, for: item.feature.id, in: room.id, fallback: item.defaultLayout)
                    },
                    onScaleChange: { scale in
                        layoutStore.setScale(scale, for: item.feature.id, in: room.id, fallback: item.defaultLayout)
                    },
                    onToggleHorizontalFlip: {
                        layoutStore.toggleHorizontalFlip(for: item.feature.id, in: room.id, fallback: item.defaultLayout)
                    }
                )
            }
        }
        .frame(width: roomSize.width, height: roomSize.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(room.localizedTitle)
    }
}

private struct BookHouseRoomDecorationView: View {
    let decoration: BookHouseRoomDecoration
    let roomSize: CGSize
    @Environment(\.colorScheme) private var colorScheme

    private var scaledSize: CGSize {
        let scale = roomSize.width / 360
        return CGSize(
            width: decoration.size.width * scale,
            height: decoration.size.height * scale
        )
    }

    var body: some View {
        Image(decoration.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: scaledSize.width, height: scaledSize.height)
            .shadow(color: Color(hex: "5D3F2C").opacity(colorScheme == .dark ? 0.18 : 0.11), radius: 4, x: 0, y: 3)
            .position(
                x: decoration.position.x * roomSize.width,
                y: decoration.position.y * roomSize.height
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct BookHouseRoomOpulenceOverlay: View {
    let accent: Color
    let isDark: Bool
    let hasThemeSkin: Bool

    var body: some View {
        GeometryReader { geometry in
            let detailOpacity = hasThemeSkin ? 0.54 : 0.88
            let gold = Color(hex: "C69A54")
            let rose = Color(hex: "D7A6A0")

            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: "FFF4DC").opacity(isDark ? 0.04 : 0.16),
                        rose.opacity(isDark ? 0.03 : 0.09),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(isDark ? .screen : .softLight)

                BookHouseFloorInlay(
                    gold: gold,
                    rose: rose,
                    isDark: isDark,
                    detailOpacity: detailOpacity
                )

                BookHouseWallPanels(
                    gold: gold,
                    rose: rose,
                    accent: accent,
                    isDark: isDark,
                    detailOpacity: detailOpacity
                )

                BookHouseCenterSpine(
                    gold: gold,
                    isDark: isDark,
                    detailOpacity: detailOpacity
                )

                BookHouseWindowLight(
                    gold: gold,
                    isDark: isDark,
                    detailOpacity: detailOpacity
                )

                BookHouseArchedWindow(
                    gold: gold,
                    isDark: isDark,
                    detailOpacity: detailOpacity
                )
                .frame(width: geometry.size.width * 0.17, height: geometry.size.height * 0.28)
                .position(x: geometry.size.width * 0.29, y: geometry.size.height * 0.38)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BookHouseWallPanels: View {
    let gold: Color
    let rose: Color
    let accent: Color
    let isDark: Bool
    let detailOpacity: Double

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let goldLine = gold.opacity((isDark ? 0.24 : 0.44) * detailOpacity)
            let roseLine = rose.opacity((isDark ? 0.18 : 0.30) * detailOpacity)

            ZStack {
                wallPanelPath(points: [
                    CGPoint(x: w * 0.18, y: h * 0.23),
                    CGPoint(x: w * 0.43, y: h * 0.17),
                    CGPoint(x: w * 0.44, y: h * 0.58),
                    CGPoint(x: w * 0.19, y: h * 0.63)
                ])
                .stroke(roseLine, lineWidth: 3.2)

                wallPanelPath(points: [
                    CGPoint(x: w * 0.20, y: h * 0.26),
                    CGPoint(x: w * 0.40, y: h * 0.21),
                    CGPoint(x: w * 0.40, y: h * 0.54),
                    CGPoint(x: w * 0.21, y: h * 0.58)
                ])
                .stroke(goldLine, lineWidth: 1.4)

                wallPanelPath(points: [
                    CGPoint(x: w * 0.57, y: h * 0.18),
                    CGPoint(x: w * 0.82, y: h * 0.25),
                    CGPoint(x: w * 0.81, y: h * 0.62),
                    CGPoint(x: w * 0.56, y: h * 0.57)
                ])
                .stroke(roseLine, lineWidth: 3.2)

                wallPanelPath(points: [
                    CGPoint(x: w * 0.60, y: h * 0.22),
                    CGPoint(x: w * 0.79, y: h * 0.27),
                    CGPoint(x: w * 0.78, y: h * 0.57),
                    CGPoint(x: w * 0.60, y: h * 0.53)
                ])
                .stroke(goldLine, lineWidth: 1.4)

                ForEach([0.18, 0.82], id: \.self) { xRatio in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    gold.opacity((isDark ? 0.20 : 0.34) * detailOpacity),
                                    accent.opacity((isDark ? 0.10 : 0.16) * detailOpacity)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: max(2, w * 0.012), height: h * 0.33)
                        .position(x: w * xRatio, y: h * 0.44)
                }
            }
        }
    }

    private func wallPanelPath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
    }
}

private struct BookHouseCenterSpine: View {
    let gold: Color
    let isDark: Bool
    let detailOpacity: Double

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height

            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "9A684E").opacity((isDark ? 0.24 : 0.40) * detailOpacity),
                                Color(hex: "D0A270").opacity((isDark ? 0.18 : 0.32) * detailOpacity),
                                Color(hex: "8B5A45").opacity((isDark ? 0.22 : 0.36) * detailOpacity)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay {
                        Capsule()
                            .stroke(gold.opacity((isDark ? 0.28 : 0.52) * detailOpacity), lineWidth: 1.2)
                    }
                    .frame(width: w * 0.06, height: h * 0.42)
                    .position(x: w * 0.50, y: h * 0.39)

                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(gold.opacity((isDark ? 0.28 : 0.56) * detailOpacity))
                        .frame(width: w * 0.067, height: 1.4)
                        .position(x: w * 0.50, y: h * (0.23 + CGFloat(index) * 0.10))
                }

                Circle()
                    .stroke(gold.opacity((isDark ? 0.30 : 0.62) * detailOpacity), lineWidth: 1.2)
                    .frame(width: w * 0.035, height: w * 0.035)
                    .position(x: w * 0.50, y: h * 0.39)
            }
        }
    }
}

private struct BookHouseWindowLight: View {
    let gold: Color
    let isDark: Bool
    let detailOpacity: Double

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let lightOpacity = (isDark ? 0.12 : 0.24) * detailOpacity

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: w * 0.25, y: h * 0.40))
                    path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.63))
                    path.addLine(to: CGPoint(x: w * 0.47, y: h * 0.73))
                    path.addLine(to: CGPoint(x: w * 0.20, y: h * 0.51))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(lightOpacity * 1.2),
                            Color(hex: "FFDCA1").opacity(lightOpacity),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)

                Path { path in
                    path.move(to: CGPoint(x: w * 0.31, y: h * 0.49))
                    path.addLine(to: CGPoint(x: w * 0.54, y: h * 0.66))
                    path.move(to: CGPoint(x: w * 0.26, y: h * 0.54))
                    path.addLine(to: CGPoint(x: w * 0.48, y: h * 0.72))
                }
                .stroke(gold.opacity((isDark ? 0.10 : 0.18) * detailOpacity), lineWidth: 0.8)
                .blendMode(.screen)
            }
        }
    }
}

private struct BookHouseArchedWindow: View {
    let gold: Color
    let isDark: Bool
    let detailOpacity: Double

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let strokeOpacity = (isDark ? 0.30 : 0.58) * detailOpacity

            ZStack {
                BookHouseArchedWindowShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.12 : 0.62),
                                Color(hex: "FFE5B4").opacity(isDark ? 0.08 : 0.36)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                BookHouseArchedWindowShape()
                    .stroke(gold.opacity(strokeOpacity), lineWidth: 1.4)

                Path { path in
                    path.move(to: CGPoint(x: w * 0.50, y: h * 0.10))
                    path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.92))
                    path.move(to: CGPoint(x: w * 0.22, y: h * 0.45))
                    path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.45))
                    path.move(to: CGPoint(x: w * 0.22, y: h * 0.66))
                    path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.66))
                }
                .stroke(gold.opacity(strokeOpacity * 0.85), lineWidth: 0.9)
                .clipShape(BookHouseArchedWindowShape())

                BookHouseArchedWindowShape()
                    .stroke(Color.white.opacity(isDark ? 0.08 : 0.36), lineWidth: 0.7)
                    .offset(x: -1, y: -1)
            }
        }
    }
}

private struct BookHouseArchedWindowShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.34))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.34),
                control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.10)
            )
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct BookHouseFloorInlay: View {
    let gold: Color
    let rose: Color
    let isDark: Bool
    let detailOpacity: Double

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height

            ZStack {
                BookHouseFloorShape()
                    .fill(Color(hex: "F1D8AF").opacity((isDark ? 0.05 : 0.16) * detailOpacity))
                    .blendMode(isDark ? .screen : .multiply)

                ZStack {
                    ForEach(0..<9, id: \.self) { index in
                        Path { path in
                            let y = h * 0.60 + CGFloat(index) * h * 0.035
                            path.move(to: CGPoint(x: w * 0.22, y: y))
                            path.addLine(to: CGPoint(x: w * 0.78, y: y + h * 0.11))
                        }
                        .stroke(Color(hex: "8E623D").opacity((isDark ? 0.06 : 0.13) * detailOpacity), lineWidth: 0.7)

                        Path { path in
                            let y = h * 0.60 + CGFloat(index) * h * 0.035
                            path.move(to: CGPoint(x: w * 0.78, y: y))
                            path.addLine(to: CGPoint(x: w * 0.22, y: y + h * 0.11))
                        }
                        .stroke(Color.white.opacity((isDark ? 0.03 : 0.16) * detailOpacity), lineWidth: 0.7)
                    }
                }
                .clipShape(BookHouseFloorShape())

                BookHouseFloorRug(
                    gold: gold,
                    rose: rose,
                    isDark: isDark,
                    detailOpacity: detailOpacity
                )

                BookHouseFloorShape()
                    .stroke(gold.opacity((isDark ? 0.18 : 0.38) * detailOpacity), lineWidth: 1.1)
            }
        }
    }
}

private struct BookHouseFloorRug: View {
    let gold: Color
    let rose: Color
    let isDark: Bool
    let detailOpacity: Double

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let rugOpacity = (isDark ? 0.12 : 0.26) * detailOpacity

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: w * 0.50, y: h * 0.61))
                    path.addLine(to: CGPoint(x: w * 0.73, y: h * 0.74))
                    path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.88))
                    path.addLine(to: CGPoint(x: w * 0.27, y: h * 0.74))
                    path.closeSubpath()
                }
                .fill(rose.opacity(rugOpacity * 0.55))

                Path { path in
                    path.move(to: CGPoint(x: w * 0.50, y: h * 0.61))
                    path.addLine(to: CGPoint(x: w * 0.73, y: h * 0.74))
                    path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.88))
                    path.addLine(to: CGPoint(x: w * 0.27, y: h * 0.74))
                    path.closeSubpath()
                }
                .stroke(gold.opacity((isDark ? 0.22 : 0.48) * detailOpacity), lineWidth: 1.1)

                Circle()
                    .stroke(gold.opacity((isDark ? 0.20 : 0.45) * detailOpacity), lineWidth: 1)
                    .frame(width: w * 0.12, height: w * 0.12)
                    .position(x: w * 0.50, y: h * 0.74)

                Capsule()
                    .fill(gold.opacity((isDark ? 0.15 : 0.32) * detailOpacity))
                    .frame(width: w * 0.18, height: 1.2)
                    .position(x: w * 0.50, y: h * 0.74)

                Capsule()
                    .fill(gold.opacity((isDark ? 0.15 : 0.32) * detailOpacity))
                    .frame(width: w * 0.18, height: 1.2)
                    .rotationEffect(.degrees(90))
                    .position(x: w * 0.50, y: h * 0.74)
            }
        }
    }
}

private struct BookHouseFloorShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.17, y: rect.minY + rect.height * 0.62))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.50))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.83, y: rect.minY + rect.height * 0.62))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.90))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.98))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.90))
            path.closeSubpath()
        }
    }
}

private struct BookHouseRoomPageEdgeOverlay: View {
    let isDark: Bool
    let hasThemeSkin: Bool

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let edgeOpacity = isDark ? 0.16 : (hasThemeSkin ? 0.18 : 0.34)
            let pageLine = Color(hex: "8C6044").opacity(edgeOpacity)

            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    let inset = CGFloat(index) * 2.4
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.09 + inset, y: h * 0.18 + inset * 1.2))
                        path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.06 + inset * 0.7))
                        path.addLine(to: CGPoint(x: w * 0.91 - inset, y: h * 0.18 + inset * 1.2))
                    }
                    .stroke(pageLine.opacity(1.0 - CGFloat(index) * 0.13), lineWidth: 0.7)
                }

                Path { path in
                    path.move(to: CGPoint(x: w * 0.08, y: h * 0.20))
                    path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.78))
                    path.move(to: CGPoint(x: w * 0.92, y: h * 0.20))
                    path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.78))
                    path.move(to: CGPoint(x: w * 0.27, y: h * 0.93))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.73, y: h * 0.93),
                        control: CGPoint(x: w * 0.50, y: h * 1.02)
                    )
                }
                .stroke(Color(hex: "C79A5A").opacity(edgeOpacity * 1.2), lineWidth: 1.0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
    let layout: BookHouseItemLayout
    let roomSize: CGSize
    let isPlacementMode: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onTap: () -> Void
    let onMove: (CGPoint) -> Void
    let onScaleChange: (CGFloat) -> Void
    let onToggleHorizontalFlip: () -> Void

    @State private var dragStart: CGPoint?
    @State private var resizeStartScale: CGFloat?
    @State private var pinchStartScale: CGFloat?
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var scaledSize: CGSize {
        let scale = roomSize.width / 360
        return CGSize(
            width: item.size.width * scale,
            height: item.size.height * scale
        )
    }

    var body: some View {
        let itemSize = scaledSize
        let scale = BookHouseItemLayout.clampedScale(layout.scale)
        let visualSize = CGSize(width: itemSize.width * scale, height: itemSize.height * scale)
        let frameSize = CGSize(width: max(visualSize.width, 46), height: max(visualSize.height, 46))
        let controlInset: CGFloat = isPlacementMode && isSelected ? 28 : 0

        ZStack {
            itemContent(visualSize: visualSize, frameSize: frameSize)
                .contentShape(Rectangle())
                .onTapGesture(perform: handleTap)
                .gesture(moveGesture)
                .simultaneousGesture(pinchGesture)

            if isPlacementMode && isSelected {
                selectedEditor(frameSize: frameSize)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: frameSize.width + controlInset * 2, height: frameSize.height + controlInset * 2)
        .captureGuideTarget(guideTarget(for: item.feature.id))
        .position(
            x: layout.position.x * roomSize.width,
            y: layout.position.y * roomSize.height
        )
        .zIndex(isSelected ? 20 : Double(layout.position.y * 10))
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isSelected)
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: layout.scale)
        .animation(.easeInOut(duration: 0.16), value: layout.isHorizontallyFlipped)
        .accessibilityLabel(item.feature.localizedTitle)
    }

    private func itemContent(visualSize: CGSize, frameSize: CGSize) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "6E4B33").opacity(colorScheme == .dark ? 0.18 : 0.17),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: max(visualSize.width, visualSize.height) * 0.55
                        )
                    )
                    .frame(width: visualSize.width * 1.08, height: max(8, visualSize.height * 0.18))
                    .blur(radius: 1.4)
                    .offset(y: visualSize.height * 0.43)

                Image(item.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: visualSize.width, height: visualSize.height)
                    .scaleEffect(x: layout.isHorizontallyFlipped ? -1 : 1, y: 1)
                    .shadow(color: Color(hex: "5D3F2C").opacity(colorScheme == .dark ? 0.26 : 0.16), radius: 5, x: 0, y: 4)
                    .shadow(color: Color.white.opacity(colorScheme == .dark ? 0.02 : 0.20), radius: 2, x: -1, y: -1)
            }

            if isPlacementMode {
                featureBadge
                    .offset(x: isSelected ? 5 : 4, y: isSelected ? -5 : -4)
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .overlay {
            if isPlacementMode {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? themeManager.accentTextColor.opacity(0.88) : Color(hex: "C69A54").opacity(0.66),
                        style: StrokeStyle(lineWidth: isSelected ? 1.8 : 1.3, dash: isSelected ? [] : [4, 3])
                    )
            }
        }
    }

    private var featureBadge: some View {
        Image(systemName: item.feature.systemImage)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color(hex: item.feature.tintHex))
            .frame(width: 20, height: 20)
            .background(.white.opacity(colorScheme == .dark ? 0.78 : 0.88), in: Circle())
            .overlay(Circle().stroke(Color(hex: item.feature.tintHex).opacity(0.34), lineWidth: 1))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 4, x: 0, y: 2)
    }

    private func selectedEditor(frameSize: CGSize) -> some View {
        ZStack {
            editorHandle(systemImage: "flip.horizontal", tint: Color(hex: item.feature.tintHex))
                .frame(width: frameSize.width, height: frameSize.height, alignment: .topLeading)
                .offset(x: -14, y: -14)
                .onTapGesture {
                    onSelect()
                    onToggleHorizontalFlip()
                }
                .accessibilityLabel("水平翻转".appLocalized)

            editorHandle(systemImage: "arrow.up.left.and.arrow.down.right.circle.fill", tint: themeManager.accentTextColor)
                .frame(width: frameSize.width, height: frameSize.height, alignment: .bottomTrailing)
                .offset(x: 14, y: 14)
                .gesture(resizeGesture)
                .accessibilityLabel("缩放大小".appLocalized)

            Text("\(Int(round(BookHouseItemLayout.clampedScale(layout.scale) * 100)))%")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(themeManager.accentTextColor)
                .lineLimit(1)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(colorScheme == .dark ? 0.16 : 0.86), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(themeManager.accentTextColor.opacity(colorScheme == .dark ? 0.28 : 0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 4, x: 0, y: 2)
                .fixedSize()
                .frame(width: frameSize.width, height: frameSize.height, alignment: .bottom)
                .offset(y: 28)
                .allowsHitTesting(false)
        }
        .frame(width: frameSize.width, height: frameSize.height)
    }

    private func editorHandle(systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(.white.opacity(colorScheme == .dark ? 0.82 : 0.94), in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.20 : 0.72), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.14), radius: 5, x: 0, y: 3)
            .contentShape(Circle())
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard isPlacementMode else { return }
                onSelect()
                let start = dragStart ?? layout.position
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
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard isPlacementMode else { return }
                onSelect()
                let start = pinchStartScale ?? layout.scale
                pinchStartScale = start
                onScaleChange(BookHouseItemLayout.clampedScale(start * value))
            }
            .onEnded { _ in
                pinchStartScale = nil
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                onSelect()
                let start = resizeStartScale ?? layout.scale
                resizeStartScale = start
                let baseLength = max(44, max(scaledSize.width, scaledSize.height))
                let delta = (value.translation.width + value.translation.height) / (baseLength * 1.55)
                onScaleChange(BookHouseItemLayout.clampedScale(start + delta))
            }
            .onEnded { _ in
                resizeStartScale = nil
            }
    }

    private func handleTap() {
        if isPlacementMode {
            onSelect()
        } else {
            onTap()
        }
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
            title: "书页 House",
            slot: .main,
            decorations: [
                decoration(assetName: "book_house_wall_decor", x: 0.42, y: 0.35, width: 34, height: 40),
                decoration(assetName: "book_house_vanity", x: 0.73, y: 0.31, width: 34, height: 32),
                decoration(assetName: "book_house_phone", x: 0.45, y: 0.49, width: 40, height: 37)
            ],
            items: [
                item(.petChat, assetName: "book_house_pet_chat", x: 0.30, y: 0.48, width: 36, height: 34, scale: 0.92),
                item(.dressStock, assetName: "book_house_dress_stock", x: 0.64, y: 0.39, width: 52, height: 50, scale: 1.02),
                item(.wardrobe, assetName: "book_house_wardrobe", x: 0.80, y: 0.57, width: 72, height: 107, scale: 1.05),
                item(.calendar, assetName: "book_house_calendar", x: 0.58, y: 0.55, width: 48, height: 57, scale: 0.96),
                item(.petHome, assetName: "book_house_pet_home", x: 0.40, y: 0.50, width: 45, height: 41, scale: 0.98),
                item(.bigWorld, assetName: "book_house_big_world", x: 0.24, y: 0.70, width: 50, height: 68),
                item(.magicSticker, assetName: "book_house_magic_sticker", x: 0.36, y: 0.79, width: 44, height: 35, scale: 0.94, isHorizontallyFlipped: true),
                item(.wealth, assetName: "book_house_wealth", x: 0.51, y: 0.72, width: 78, height: 75, scale: 1.12),
                item(.perler, assetName: "book_house_perler", x: 0.61, y: 0.83, width: 42, height: 38, scale: 0.92),
                item(.depositPlan, assetName: "book_house_deposit_plan", x: 0.72, y: 0.82, width: 56, height: 50, scale: 1.04),
                item(.outfitJournal, assetName: "book_house_outfit_journal", x: 0.47, y: 0.87, width: 48, height: 33, scale: 0.94),
                item(.recycleBin, assetName: "book_house_recycle_bin", x: 0.25, y: 0.85, width: 42, height: 46, scale: 0.86, isHorizontallyFlipped: true)
            ]
        )
    ]

    private static func item(
        _ featureID: AppFeatureID,
        assetName: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat = BookHouseItemLayout.defaultScale,
        isHorizontallyFlipped: Bool = false
    ) -> BookHouseRoomItem {
        BookHouseRoomItem(
            feature: AppFeatureRegistry.descriptor(for: featureID),
            assetName: assetName,
            defaultLayout: BookHouseItemLayout(
                position: CGPoint(x: x, y: y),
                scale: scale,
                isHorizontallyFlipped: isHorizontallyFlipped
            ),
            size: CGSize(width: width, height: height)
        )
    }

    private static func decoration(
        assetName: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> BookHouseRoomDecoration {
        BookHouseRoomDecoration(
            assetName: assetName,
            position: CGPoint(x: x, y: y),
            size: CGSize(width: width, height: height)
        )
    }
}

private struct BookHousePrototypeRoom: Identifiable {
    let id: String
    let title: String
    let slot: BookHouseRoomSlot
    var decorations: [BookHouseRoomDecoration] = []
    let items: [BookHouseRoomItem]

    var localizedTitle: String {
        title.appLocalized
    }
}

private enum BookHouseRoomSlot {
    case main

    static let aspectRatio: CGFloat = 1122.0 / 1402.0

    var zIndex: Double {
        1
    }

    func width(for screenWidth: CGFloat) -> CGFloat {
        min(screenWidth * 0.90, 390)
    }

    func position(in geometry: GeometryProxy) -> CGPoint {
        let size = geometry.size
        return CGPoint(
            x: size.width * 0.50,
            y: max(geometry.safeAreaInsets.top + 326, size.height * 0.43)
        )
    }
}

private struct BookHouseRoomDecoration: Identifiable {
    let assetName: String
    let position: CGPoint
    let size: CGSize

    var id: String { assetName }
}

private struct BookHouseRoomItem: Identifiable {
    let feature: AppFeatureDescriptor
    let assetName: String
    let defaultLayout: BookHouseItemLayout
    let size: CGSize

    var id: AppFeatureID { feature.id }

    var defaultPosition: CGPoint { defaultLayout.position }
}

private struct BookHouseEditableItemSelection: Equatable {
    let roomID: String
    let featureID: AppFeatureID
}

private struct BookHouseItemLayout: Equatable {
    static let defaultScale: CGFloat = 1.0
    static let minimumScale: CGFloat = 0.62
    static let maximumScale: CGFloat = 1.65

    var position: CGPoint
    var scale: CGFloat
    var isHorizontallyFlipped: Bool

    init(
        position: CGPoint,
        scale: CGFloat = BookHouseItemLayout.defaultScale,
        isHorizontallyFlipped: Bool = false
    ) {
        self.position = position
        self.scale = BookHouseItemLayout.clampedScale(scale)
        self.isHorizontallyFlipped = isHorizontallyFlipped
    }

    static func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minimumScale), maximumScale)
    }
}

private struct BookHouseFeatureSheet: View {
    let feature: AppFeatureDescriptor
    let onEnter: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ThemeSkinIconBadge(
                    systemName: feature.systemImage,
                    fallbackColor: Color(hex: feature.tintHex),
                    size: 58,
                    symbolSize: 25
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.localizedTitle)
                        .font(.title3.weight(.bold))
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    Text(feature.localizedSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 20) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.80 : 0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(hex: feature.tintHex).opacity(colorScheme == .dark ? 0.22 : 0.16), lineWidth: 1)
                    }
            }

            Spacer(minLength: 4)

            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Label("关闭".appLocalized, systemImage: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.72 : 0.84))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(themeManager.secondaryTextColor.opacity(colorScheme == .dark ? 0.20 : 0.14), lineWidth: 1)
                        }
                }

                Button {
                    onEnter()
                } label: {
                    Label(
                        feature.isUnlocked ? "进入".appLocalized : "查看解锁条件".appLocalized,
                        systemImage: feature.isUnlocked ? "arrow.right.circle.fill" : "lock.circle.fill"
                    )
                }
                .buttonStyle(ThemeSkinPrimaryButtonStyle(fallbackTint: Color(hex: feature.tintHex), cornerRadius: 16, verticalPadding: 11))
            }
        }
        .padding(18)
    }
}

private final class BookHouseLayoutStore: ObservableObject {
    @Published private var layouts: [String: StoredLayout] = [:]

    private let defaultsKey = "bookHouse.prototypeItemPositions.v3"

    init() {
        load()
    }

    func layout(for featureID: AppFeatureID, in roomID: String, fallback: BookHouseItemLayout) -> BookHouseItemLayout {
        guard let stored = layouts[key(roomID: roomID, featureID: featureID)] else {
            return fallback
        }

        return BookHouseItemLayout(
            position: CGPoint(x: stored.x, y: stored.y),
            scale: stored.scale ?? fallback.scale,
            isHorizontallyFlipped: stored.isHorizontallyFlipped ?? fallback.isHorizontallyFlipped
        )
    }

    func setPosition(_ position: CGPoint, for featureID: AppFeatureID, in roomID: String, fallback: BookHouseItemLayout) {
        updateLayout(for: featureID, in: roomID, fallback: fallback) { layout in
            layout.position = position
        }
    }

    func setScale(_ scale: CGFloat, for featureID: AppFeatureID, in roomID: String, fallback: BookHouseItemLayout) {
        updateLayout(for: featureID, in: roomID, fallback: fallback) { layout in
            layout.scale = BookHouseItemLayout.clampedScale(scale)
        }
    }

    func toggleHorizontalFlip(for featureID: AppFeatureID, in roomID: String, fallback: BookHouseItemLayout) {
        updateLayout(for: featureID, in: roomID, fallback: fallback) { layout in
            layout.isHorizontallyFlipped.toggle()
        }
    }

    func reset(roomID: String) {
        layouts = layouts.filter { !$0.key.hasPrefix("\(roomID)::") }
        save()
    }

    private func key(roomID: String, featureID: AppFeatureID) -> String {
        "\(roomID)::\(featureID.rawValue)"
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([String: StoredLayout].self, from: data)
        else { return }

        layouts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(layouts) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func updateLayout(
        for featureID: AppFeatureID,
        in roomID: String,
        fallback: BookHouseItemLayout,
        mutate: (inout BookHouseItemLayout) -> Void
    ) {
        let storageKey = key(roomID: roomID, featureID: featureID)
        var layout = self.layout(for: featureID, in: roomID, fallback: fallback)
        mutate(&layout)
        layout.scale = BookHouseItemLayout.clampedScale(layout.scale)
        layouts[storageKey] = StoredLayout(
            x: layout.position.x,
            y: layout.position.y,
            scale: layout.scale,
            isHorizontallyFlipped: layout.isHorizontallyFlipped
        )
        save()
    }

    private struct StoredLayout: Codable {
        let x: CGFloat
        let y: CGFloat
        let scale: CGFloat?
        let isHorizontallyFlipped: Bool?
    }
}
