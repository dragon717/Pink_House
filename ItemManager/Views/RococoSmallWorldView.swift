//
//  RococoSmallWorldView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2/12/26.
//

import SwiftUI

struct RococoSmallWorldView: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    
    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    @StateObject private var featureManager = FeatureUnlockManager.shared
    
    enum ViewMode: String, CaseIterable, Identifiable {
        case both = "并排显示"
        case upper = "显示上层"
        case lower = "显示下层"
        
        var id: String { rawValue }
    }
    
    @AppStorage("rococoViewMode") private var viewMode: ViewMode = .both
    @AppStorage("isSpatialSceneEnabled") private var isSpatialSceneEnabled = false
    @State private var showDebugHotspots: Bool = false
    @State private var isViewModeMenuOpen: Bool = false
    @StateObject private var petViewModel = SmallWorldPetViewModel()
    @Environment(\.scenePhase) private var scenePhase
    
    // 未解锁功能提示
    @State private var showUnlockAlert = false
    @State private var lockedDestination: SmallWorldDestination? = nil
    
    // Zoom & Pan State
    @State private var currentZoomScale: CGFloat = 1.0
    @State private var finalZoomScale: CGFloat = 1.0
    @State private var currentDragOffset: CGSize = .zero
    @State private var finalDragOffset: CGSize = .zero

    private var isZoomedInForPanGesture: Bool {
        finalZoomScale > 1.01 || currentZoomScale > 1.01
    }
    
    // Room 1 (Floor 1) Hotspots
    private var room1Hotspots: [SmallWorldHotspotSpec] {
        [
            SmallWorldHotspotSpec(
                id: "rococo-room1-ootd",
                name: "穿搭手帐",
                rect: CGRect(x: 0.372, y: 0.542, width: 0.048, height: 0.128),
                debugColor: .orange,
                label: SmallWorldHotspotLabelSpec(
                    text: "穿搭手帐",
                    style: .diagonal(angle: -35),
                    position: CGPoint(x: 0.41, y: 0.725),
                    hitPadding: EdgeInsets(top: 12, leading: 20, bottom: 14, trailing: 20)
                ),
                destination: .ootd,
                guideTargetKey: .ootdEntry,
                hitPolicy: .directional(
                    top: 6,
                    leading: 8,
                    bottom: 24,
                    trailing: 16,
                    minimumWidth: 56,
                    minimumHeight: 84
                )
            ) {
                navigate(to: .ootd)
            },
            SmallWorldHotspotSpec(
                id: "rococo-room1-wealth",
                name: "来财",
                rect: CGRect(x: 0.46, y: 0.68, width: 0.06, height: 0.08),
                debugColor: .yellow,
                label: SmallWorldHotspotLabelSpec(
                    text: "马上来财",
                    style: .diagonal(angle: -35),
                    position: CGPoint(x: 0.52, y: 0.77)
                ),
                destination: .wealth(nil),
                guideTargetKey: .wealthEntry,
                hitPolicy: .expanded(extraWidth: 16, extraHeight: 16, minimumWidth: 1, minimumHeight: 1)
            ) {
                navigate(to: .wealth(nil))
            },
            SmallWorldHotspotSpec(
                id: "rococo-room1-wardrobe",
                name: "衣橱",
                rect: CGRect(x: 0.45, y: 0.12, width: 0.24, height: 0.24),
                debugColor: .blue,
                label: SmallWorldHotspotLabelSpec(
                    text: "少女衣橱",
                    style: .diagonal(angle: -35),
                    position: CGPoint(x: 0.525, y: 0.12)
                )
            ) {
                withAnimation(.easeIn(duration: 0.5)) {
                    isPlayingOpeningAnimation = true
                }
            },
        ]
    }
    
    // Room 2 (Floor 2) Hotspots
    private var room2Hotspots: [SmallWorldHotspotSpec] {
        [
            SmallWorldHotspotSpec(
                id: "rococo-room2-wardrobe",
                name: "衣橱",
                rect: CGRect(x: 0.05, y: 0.25, width: 0.125, height: 0.29),
                debugColor: .blue,
                label: SmallWorldHotspotLabelSpec(
                    text: "少女衣橱",
                    style: .diagonal(angle: -35),
                    position: CGPoint(x: 0.095, y: 0.24)
                )
            ) {
                withAnimation(.easeIn(duration: 0.5)) {
                    isPlayingOpeningAnimation = true
                }
            },
            SmallWorldHotspotSpec(
                id: "rococo-room2-deposit-plan",
                name: "心愿尾款",
                rect: CGRect(x: 0.08, y: 0.54, width: 0.1, height: 0.11),
                debugColor: .blue,
                label: SmallWorldHotspotLabelSpec(
                    text: "心愿尾款",
                    style: .diagonal(angle: 35),
                    position: CGPoint(x: 0.1, y: 0.66)
                ),
                destination: .depositPlan
            ) {
                navigate(to: .depositPlan)
            },
            SmallWorldHotspotSpec(
                id: "rococo-room2-calendar",
                name: "日历",
                rect: CGRect(x: 0.44, y: 0.77, width: 0.082, height: 0.121),
                debugColor: .purple,
                label: SmallWorldHotspotLabelSpec(
                    text: "梦裙日历",
                    style: .diagonal(angle: 35),
                    position: CGPoint(x: 0.45, y: 0.92),
                    hitPadding: EdgeInsets(top: 12, leading: 20, bottom: 14, trailing: 20)
                ),
                destination: .calendar,
                guideTargetKey: .calendarEntry,
                hitPolicy: .directional(
                    top: 8,
                    leading: 10,
                    bottom: 28,
                    trailing: 12,
                    minimumWidth: 60,
                    minimumHeight: 68
                )
            ) {
                navigate(to: .calendar)
            },
            SmallWorldHotspotSpec(
                id: "rococo-room2-perler",
                name: "拼豆工坊",
                rect: CGRect(x: 0.70, y: 0.45, width: 0.12, height: 0.15),
                debugColor: .pink,
                label: SmallWorldHotspotLabelSpec(
                    text: "拼豆工坊",
                    style: .diagonal(angle: -35),
                    position: CGPoint(x: 0.78, y: 0.62)
                ),
                destination: .perler
            ) {
                navigate(to: .perler)
            }
        ]
    }
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            
            ZStack(alignment: .topLeading) {
                // App Global Background
                LiquidBackground()
                
                Group {
                    switch viewMode {
                    case .both:
                        if isLandscape {
                            // Landscape: Side by Side (Left: Floor 1, Right: Floor 2)
                            HStack(spacing: 0) {
                                roomView(imageName: "small_world_rococo_1", geometry: geometry, width: geometry.size.width / 2, height: geometry.size.height)
                                roomView(imageName: "small_world_rococo_2", geometry: geometry, width: geometry.size.width / 2, height: geometry.size.height)
                            }
                        } else {
                            // Portrait: Stacked (Top: Floor 1, Bottom: Floor 2)
                            VStack(spacing: -80) { // Negative spacing to bring them closer
                                roomView(imageName: "small_world_rococo_1", geometry: geometry, width: geometry.size.width, height: geometry.size.height / 2)
                                roomView(imageName: "small_world_rococo_2", geometry: geometry, width: geometry.size.width, height: geometry.size.height / 2)
                            }
                        }
                    case .upper:
                        roomView(imageName: "small_world_rococo_1", geometry: geometry, width: geometry.size.width, height: geometry.size.height)
                    case .lower:
                        roomView(imageName: "small_world_rococo_2", geometry: geometry, width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .scaleEffect(finalZoomScale * currentZoomScale)
                .offset(x: finalDragOffset.width + currentDragOffset.width, y: finalDragOffset.height + currentDragOffset.height)
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            currentZoomScale = scale
                        }
                        .onEnded { scale in
                            let newScale = finalZoomScale * scale
                            withAnimation {
                                finalZoomScale = max(1.0, min(newScale, 3.0))
                                currentZoomScale = 1.0
                                if finalZoomScale == 1.0 {
                                    finalDragOffset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            if finalZoomScale > 1.0 {
                                currentDragOffset = value.translation
                            }
                        }
                        .onEnded { value in
                            if finalZoomScale > 1.0 {
                                finalDragOffset.width += value.translation.width
                                finalDragOffset.height += value.translation.height
                                currentDragOffset = .zero
                            }
                        }
                    ,
                    // 未放大时优先交给子热区，避免拖拽手势吃掉按钮抬手事件。
                    including: isZoomedInForPanGesture ? .gesture : .subviews
                )
                .onChange(of: viewMode) { _ in
                    withAnimation {
                        finalZoomScale = 1.0
                        currentZoomScale = 1.0
                        finalDragOffset = .zero
                        currentDragOffset = .zero
                    }
                }
                .transition(.opacity)
                .allowsHitTesting(!isViewModeMenuOpen)

                if isViewModeMenuOpen {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeViewModeMenu()
                        }
                        .accessibilityHidden(true)
                        .zIndex(10)
                }

                RococoViewModeFloatingMenu(
                    viewMode: $viewMode,
                    isPresented: $isViewModeMenuOpen,
                    showDebugHotspots: $showDebugHotspots,
                    petViewModel: petViewModel
                )
                .padding(.leading, 16)
                .padding(.top, 50) // Adjust for safe area
                .zIndex(20)
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isLandscape)
            .animation(.easeInOut, value: viewMode)
            .animation(.easeInOut(duration: 0.18), value: isViewModeMenuOpen)
        }
        .ignoresSafeArea()
        .onAppear {
            resetState()
            petViewModel.startMovement()
        }
        .onDisappear {
            resetState()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                resetState()
                petViewModel.startMovement()
            }
        }
        .alert("功能未解锁", isPresented: $showUnlockAlert) {
            if let dest = lockedDestination,
               let feature = dest.featureItem {
                if feature.isComingSoonFeature {
                    Button("我知道啦～", role: .cancel) { }
                } else {
                    Button("取消", role: .cancel) { }
                    Button("去解锁") {
                        // 跳转到魔法任务页面
                        NotificationCenter.default.post(
                            name: .navigateToMagicTasks,
                            object: nil
                        )
                    }
                }
            } else {
                Button("取消", role: .cancel) { }
                Button("去解锁") {
                    // 跳转到魔法任务页面
                    NotificationCenter.default.post(
                        name: .navigateToMagicTasks,
                        object: nil
                    )
                }
            }
        } message: {
            if let dest = lockedDestination,
               let feature = dest.featureItem {
                let condition = featureManager.getCondition(for: feature)
                Text("\(feature.displayName) 尚未解锁\n\(condition.description)")
            } else {
                Text("该功能尚未解锁，请先完成对应任务")
            }
        }
    }
    
    // MARK: - 导航方法
    private func navigate(to destination: SmallWorldDestination) {
        // 检查功能是否已解锁
        if destination.canAccess {
            // 特殊处理：心愿尾款和衣橱需要跳转到 Tab 0 (衣橱Tab)
            if case .depositPlan = destination {
                tabNavigationManager.navigate(to: .wardrobe(.depositPlan))
            } else if case .wardrobe = destination {
                tabNavigationManager.navigate(to: .wardrobe(.wardrobe))
            } else {
                // 已解锁，正常导航到House内部页面
                tabNavigationManager.markNavigatingInsideSmallWorld()
                self.destination = destination
            }
        } else {
            // 未解锁，显示提示
            lockedDestination = destination
            showUnlockAlert = true
        }
    }
    
    private func resetState() {
        isViewModeMenuOpen = false

        // 修复：当从视频播放返回时，强制重置缩放和动画状态，防止交互锁死
        // 使用 withAnimation 确保平滑过渡，但在某些情况下可能需要立即重置
        withAnimation {
            finalZoomScale = 1.0
            currentZoomScale = 1.0
            finalDragOffset = .zero
            currentDragOffset = .zero
        }
        
        // 停止宠物移动，确保状态重置
        petViewModel.stopMovement()
        
        // 确保视频播放状态已重置
        if isPlayingOpeningAnimation {
            isPlayingOpeningAnimation = false
        }
    }
    
    private func closeViewModeMenu() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isViewModeMenuOpen = false
        }
    }
    
    @ViewBuilder
    private func roomView(imageName: String, geometry: GeometryProxy, width: CGFloat, height: CGFloat) -> some View {
        let hotspots = imageName.contains("rococo_1") ? room1Hotspots : room2Hotspots
        
        Group {
            if #available(iOS 26.0, *), isSpatialSceneEnabled {
                SpatialBackgroundView(imageName: imageName) {
                    roomContent(imageName: imageName, hotspots: hotspots)
                }
            } else {
                GeometryReader { imageGeo in
                    let imageFrame = displayedImageFrame(for: imageName, in: imageGeo.size)

                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: imageGeo.size.width, height: imageGeo.size.height)
                        .overlay(
                            roomContent(
                                imageName: imageName,
                                hotspots: hotspots,
                                containerSize: imageGeo.size,
                                imageFrame: imageFrame
                            ),
                            alignment: .topLeading
                        )
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }
    
    @ViewBuilder
    private func roomContent(
        imageName: String,
        hotspots: [SmallWorldHotspotSpec],
        containerSize: CGSize? = nil,
        imageFrame: CGRect? = nil
    ) -> some View {
        if let containerSize, let imageFrame {
            roomHotspotsContent(
                imageName: imageName,
                hotspots: hotspots,
                containerSize: containerSize,
                imageFrame: imageFrame
            )
        } else {
            GeometryReader { geo in
                roomHotspotsContent(
                    imageName: imageName,
                    hotspots: hotspots,
                    containerSize: geo.size,
                    imageFrame: displayedImageFrame(for: imageName, in: geo.size)
                )
            }
        }
    }
    
    @ViewBuilder
    private func roomHotspotsContent(
        imageName: String,
        hotspots: [SmallWorldHotspotSpec],
        containerSize: CGSize,
        imageFrame: CGRect
    ) -> some View {
        ZStack(alignment: .topLeading) {
            SmallWorldHotspotOverlay(
                logPrefix: "RococoSmallWorldView",
                hotspots: hotspots,
                containerSize: containerSize,
                imageFrame: imageFrame,
                showDebug: showDebugHotspots
            )
            
            SmallWorldPetOverlay(
                viewModel: petViewModel,
                roomIndex: imageName.contains("rococo_1") ? 0 : 1,
                containerSize: imageFrame.size
            )
            .frame(width: imageFrame.width, height: imageFrame.height)
            .offset(x: imageFrame.minX, y: imageFrame.minY)
            .allowsHitTesting(petViewModel.isDebugMode)
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
    }

    private func displayedImageFrame(for imageName: String, in containerSize: CGSize) -> CGRect {
        let imageSize = roomImageSize(for: imageName)
        return SmallWorldImageLayout.aspectFitFrame(imageSize: imageSize, in: containerSize)
    }

    private func roomImageSize(for imageName: String) -> CGSize {
        guard let image = UIImage(named: imageName), image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: 1, height: 1)
        }
        return image.size
    }
}

private struct RococoViewModeFloatingMenu: View {
    @Binding var viewMode: RococoSmallWorldView.ViewMode
    @Binding var isPresented: Bool
    @Binding var showDebugHotspots: Bool
    @ObservedObject var petViewModel: SmallWorldPetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            menuButton

            if isPresented {
                menuPanel
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.96, anchor: .topLeading)
                        )
                    )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var menuButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isPresented.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isPresented ? 0.95 : 0.58), lineWidth: 1.2)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
                    .shadow(color: Color(red: 1.0, green: 0.54, blue: 0.75).opacity(isPresented ? 0.45 : 0.22), radius: isPresented ? 14 : 6)

                Image(systemName: buttonIconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .frame(width: 56, height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("洛可可视图菜单")
        .accessibilityValue(isPresented ? "已展开" : "已收起")
        .accessibilityIdentifier("smallworld.rococo.viewModeMenu.button")
    }

    private var menuPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("视图模式")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 4)

            ForEach(RococoSmallWorldView.ViewMode.allCases) { mode in
                menuRow(
                    title: mode.rawValue,
                    systemImage: iconForMode(mode),
                    isSelected: viewMode == mode,
                    accessibilityIdentifier: "smallworld.rococo.viewModeMenu.option.\(mode.id)"
                ) {
                    viewMode = mode
                    closeMenu()
                }
            }

            #if DEBUG
            Divider()
                .padding(.vertical, 2)

            menuRow(
                title: "显示热区调试",
                systemImage: showDebugHotspots ? "checkmark.rectangle.stack" : "rectangle.dashed",
                isSelected: showDebugHotspots,
                accessibilityIdentifier: "smallworld.rococo.viewModeMenu.debug.hotspots"
            ) {
                showDebugHotspots.toggle()
                closeMenu()
            }

            menuRow(
                title: "显示路径调试",
                systemImage: petViewModel.isDebugMode ? "checkmark.circle" : "arrow.triangle.swap",
                isSelected: petViewModel.isDebugMode,
                accessibilityIdentifier: "smallworld.rococo.viewModeMenu.debug.petPath"
            ) {
                petViewModel.isDebugMode.toggle()
                if petViewModel.isDebugMode, petViewModel.activePathId == nil {
                    petViewModel.startMovement()
                }
                closeMenu()
            }
            #endif
        }
        .padding(8)
        .frame(width: 224, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.48), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
        .accessibilityIdentifier("smallworld.rococo.viewModeMenu.panel")
    }

    private func menuRow(
        title: String,
        systemImage: String,
        isSelected: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(red: 1.0, green: 0.36, blue: 0.67) : Color.secondary)
                    .frame(width: 22)

                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.36, blue: 0.67))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.34) : Color.white.opacity(0.001))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var buttonIconName: String {
        if #available(iOS 26.0, *) {
            return "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
        } else {
            return "line.3.horizontal.circle"
        }
    }

    private func closeMenu() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isPresented = false
        }
    }

    private func iconForMode(_ mode: RococoSmallWorldView.ViewMode) -> String {
        switch mode {
        case .both: return "rectangle.split.1x2"
        case .upper: return "rectangle.topthird.inset.filled"
        case .lower: return "rectangle.bottomthird.inset.filled"
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var selectedTab = 1
        @State var homeTab: HomeTab = .wardrobe
        @State var destination: SmallWorldDestination = .menu
        @State var isPlayingOpeningAnimation = false
        @State var themeManager = ThemeManager.shared
        
        var body: some View {
            RococoSmallWorldView(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination,
                isPlayingOpeningAnimation: $isPlayingOpeningAnimation
            )
            .environment(themeManager)
        }
    }
    return PreviewWrapper()
}
