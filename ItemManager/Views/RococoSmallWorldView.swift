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
                
                // View Mode Menu Button (Top Left)
                Menu {
                    Picker("视图模式", selection: $viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: iconForMode(mode)).tag(mode)
                        }
                    }
                    
                    Divider()
                    
                    #if DEBUG
                    Button(action: {
                        showDebugHotspots.toggle()
                    }) {
                        Label("显示热区调试", systemImage: showDebugHotspots ? "checkmark.rectangle.stack" : "rectangle.dashed")
                    }
                    
                    Button(action: {
                        petViewModel.isDebugMode.toggle()
                        if petViewModel.isDebugMode, petViewModel.activePathId == nil {
                            petViewModel.startMovement()
                        }
                    }) {
                        Label("显示路径调试", systemImage: petViewModel.isDebugMode ? "checkmark.circle" : "arrow.triangle.swap")
                    }
                    #endif
                } label: {
                    if #available(iOS 26.0, *) {
                        Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .padding(12)
                            .background(Material.thin)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "line.3.horizontal.circle")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .padding(12)
                            .background(Material.thin)
                            .clipShape(Circle())
                    }
                }
                .padding(.leading, 16)
                .padding(.top, 50) // Adjust for safe area
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isLandscape)
            .animation(.easeInOut, value: viewMode)
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
                let condition = featureManager.getCondition(for: feature)
                // 兑换码解锁的功能只显示"我知道啦～"按钮
                if condition.type == UnlockConditionType.redeemCode.rawValue {
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
    
    private func iconForMode(_ mode: ViewMode) -> String {
        switch mode {
        case .both: return "rectangle.split.1x2"
        case .upper: return "rectangle.topthird.inset.filled"
        case .lower: return "rectangle.bottomthird.inset.filled"
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
