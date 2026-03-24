//
//  RococoSmallWorldView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2/12/26.
//

import SwiftUI
import UIKit

struct RococoSmallWorldView: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    
    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    @StateObject private var featureManager = FeatureUnlockManager.shared
    
    // Isometric Layout Constants
    private let tileWidth: CGFloat = 100
    private let tileHeight: CGFloat = 50
    
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
    
    // MARK: - Hotspot Data
    private struct HotspotData: Identifiable {
        let id = UUID()
        let name: String
        let rect: CGRect // Normalized 0-1
        let color: Color
        var label: String? = nil
        var labelStyle: SmallWorldLabelStyle = .diagonal(angle: 45)
        var labelPosition: CGPoint? = nil // 独立的标签位置 (Normalized 0-1)
        var destination: SmallWorldDestination? = nil // 对应的功能目的地，用于解锁检查
        let action: () -> Void
    }
    
    // Room 1 (Floor 1) Hotspots
    private var room1Hotspots: [HotspotData] {
        [
            HotspotData(name: "穿搭手帐", rect: CGRect(x: 0.35, y: 0.53, width: 0.08, height: 0.19), color: .orange, label: "穿搭手帐", labelStyle: .diagonal(angle: -35), labelPosition: CGPoint(x: 0.41, y: 0.725), destination: .ootd) {
                navigate(to: .ootd)
            },
            HotspotData(name: "来财", rect: CGRect(x: 0.46, y: 0.68, width: 0.06, height: 0.08), color: .yellow, label: "马上来财", labelStyle: .diagonal(angle: -35), labelPosition: CGPoint(x: 0.52, y: 0.77), destination: .wealth(nil)) {
                navigate(to: .wealth(nil))
            },
            HotspotData(name: "衣橱", rect: CGRect(x: 0.45, y: 0.12, width: 0.24, height: 0.24), color: .blue, label: "少女衣橱", labelStyle: .diagonal(angle: -35), labelPosition: CGPoint(x: 0.525, y: 0.12), destination: nil) {
                withAnimation(.easeIn(duration: 0.5)) {
                    isPlayingOpeningAnimation = true
                }
            },
        ]
    }
    
    // Room 2 (Floor 2) Hotspots
    private var room2Hotspots: [HotspotData] {
        [
            HotspotData(name: "衣橱", rect: CGRect(x: 0.05, y: 0.25, width: 0.125, height: 0.29), color: .blue, label: "少女衣橱", labelStyle: .diagonal(angle: -35), labelPosition: CGPoint(x: 0.095, y: 0.24), destination: nil) {
                withAnimation(.easeIn(duration: 0.5)) {
                    isPlayingOpeningAnimation = true
                }
            },
            HotspotData(name: "心愿尾款", rect: CGRect(x: 0.08, y: 0.54, width: 0.1, height: 0.11), color: .blue, label: "心愿尾款", labelStyle: .diagonal(angle: 35), labelPosition: CGPoint(x: 0.1, y: 0.66), destination: .depositPlan) {
                navigate(to: .depositPlan)
            },
            // 萌宠会动
//            HotspotData(name: "萌宠", rect: CGRect(x: 0.45, y: 0.48, width: 0.13, height: 0.21), color: .pink) {
//                destination = .pet
//            },

            HotspotData(name: "日历", rect: CGRect(x: 0.44, y: 0.77, width: 0.082, height: 0.121), color: .purple, label: "梦裙日历", labelStyle: .diagonal(angle: 35), labelPosition: CGPoint(x: 0.45, y: 0.92), destination: .calendar) {
                navigate(to: .calendar)
            },

            HotspotData(name: "拼豆工坊", rect: CGRect(x: 0.70, y: 0.45, width: 0.12, height: 0.15), color: .pink, label: "拼豆工坊", labelStyle: .diagonal(angle: -35), labelPosition: CGPoint(x: 0.78, y: 0.62), destination: .perler) {
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
                .gesture(
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
        }
        .onDisappear {
            resetState()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                resetState()
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
        hotspots: [HotspotData],
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
        hotspots: [HotspotData],
        containerSize: CGSize,
        imageFrame: CGRect
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(hotspots) { hotspot in
                ZStack {
                    Group {
                        if isWealthDestination(hotspot.destination) {
                            wealthHotspotButton(hotspot: hotspot, imageFrame: imageFrame)
                            wealthEntryCaptureAnchor(hotspot: hotspot, imageFrame: imageFrame)
                        } else {
                            hotspotButton(hotspot: hotspot, imageFrame: imageFrame)
                            if let key = guideTargetKey(for: hotspot.destination) {
                                genericCaptureAnchor(hotspot: hotspot, imageFrame: imageFrame, key: key)
                            }
                        }
                    }
                    
                    if let label = hotspot.label {
                        let labelPos = hotspot.labelPosition ?? CGPoint(x: hotspot.rect.midX, y: hotspot.rect.midY)
                        
                        FloatingTextLabel(text: label, style: hotspot.labelStyle)
                            .allowsHitTesting(false)
                            .position(
                                x: imageFrame.minX + labelPos.x * imageFrame.width,
                                y: imageFrame.minY + labelPos.y * imageFrame.height
                            )
                    }
                }
                .frame(width: containerSize.width, height: containerSize.height)
            }
            
            if FeatureUnlockManager.shared.isUnlocked(.pet) {
                SmallWorldPetOverlay(
                    viewModel: petViewModel,
                    roomIndex: imageName.contains("rococo_1") ? 0 : 1,
                    containerSize: imageFrame.size
                )
                .frame(width: imageFrame.width, height: imageFrame.height)
                .offset(x: imageFrame.minX, y: imageFrame.minY)
                .allowsHitTesting(petViewModel.isDebugMode)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
    }

    private func hotspotButton(hotspot: HotspotData, imageFrame: CGRect) -> some View {
        Button(action: {
            print("[RococoSmallWorldView] 热区点击: \(hotspot.name), 坐标: (\(hotspot.rect.minX), \(hotspot.rect.minY)), 尺寸: \(imageFrame.size)")
            hotspot.action()
        }) {
            if showDebugHotspots {
                ZStack {
                    Rectangle()
                        .fill(hotspot.color.opacity(0.3))
                        .border(hotspot.color, width: 2)
                    Text(hotspot.name)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.6))
                        .cornerRadius(4)
                }
                .contentShape(Rectangle())
            } else {
                // 修复：使用极低的透明度而非 clear，确保首次加载时按钮可点击
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
            }
        }
        .frame(
            width: max(1, hotspot.rect.width * imageFrame.width),
            height: max(1, hotspot.rect.height * imageFrame.height)
        )
        .position(
            x: imageFrame.minX + (hotspot.rect.minX + hotspot.rect.width / 2) * imageFrame.width,
            y: imageFrame.minY + (hotspot.rect.minY + hotspot.rect.height / 2) * imageFrame.height
        )
    }

    private func wealthHotspotButton(hotspot: HotspotData, imageFrame: CGRect) -> some View {
        let baseWidth = max(1, hotspot.rect.width * imageFrame.width)
        let baseHeight = max(1, hotspot.rect.height * imageFrame.height)
        let expandedWidth = baseWidth + 16
        let expandedHeight = baseHeight + 16

        return Button(action: {
            print("[RococoSmallWorldView] 来财热区点击: \(hotspot.name), 原始尺寸: \(baseWidth)x\(baseHeight), 扩展尺寸: \(expandedWidth)x\(expandedHeight)")
            hotspot.action()
        }) {
            if showDebugHotspots {
                ZStack {
                    Rectangle()
                        .fill(hotspot.color.opacity(0.3))
                        .border(hotspot.color, width: 2)
                    Text("\(hotspot.name)\n扩展点击")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(4)
                        .background(.black.opacity(0.6))
                        .cornerRadius(4)
                }
                .contentShape(Rectangle())
            } else {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
            }
        }
        .frame(width: expandedWidth, height: expandedHeight)
        .position(
            x: imageFrame.minX + (hotspot.rect.minX + hotspot.rect.width / 2) * imageFrame.width,
            y: imageFrame.minY + (hotspot.rect.minY + hotspot.rect.height / 2) * imageFrame.height
        )
    }

    private func wealthEntryCaptureAnchor(hotspot: HotspotData, imageFrame: CGRect) -> some View {
        let baseWidth = max(1, hotspot.rect.width * imageFrame.width)
        let baseHeight = max(1, hotspot.rect.height * imageFrame.height)
        let expandedWidth = baseWidth + 16
        let expandedHeight = baseHeight + 16

        return Color.clear
            .frame(
                width: expandedWidth,
                height: expandedHeight
            )
            .captureGuideTarget(.wealthEntry)
            .position(
                x: imageFrame.minX + (hotspot.rect.minX + hotspot.rect.width / 2) * imageFrame.width,
                y: imageFrame.minY + (hotspot.rect.minY + hotspot.rect.height / 2) * imageFrame.height
            )
            .allowsHitTesting(false)
    }

    private func genericCaptureAnchor(hotspot: HotspotData, imageFrame: CGRect, key: GuideTargetKey) -> some View {
        Color.clear
            .frame(
                width: max(1, hotspot.rect.width * imageFrame.width),
                height: max(1, hotspot.rect.height * imageFrame.height)
            )
            .captureGuideTarget(key)
            .position(
                x: imageFrame.minX + (hotspot.rect.minX + hotspot.rect.width / 2) * imageFrame.width,
                y: imageFrame.minY + (hotspot.rect.minY + hotspot.rect.height / 2) * imageFrame.height
            )
            .allowsHitTesting(false)
    }

    private func guideTargetKey(for destination: SmallWorldDestination?) -> GuideTargetKey? {
        switch destination {
        case .ootd:
            return .ootdEntry
        case .calendar:
            return .calendarEntry
        default:
            return nil
        }
    }

    private func displayedImageFrame(for imageName: String, in containerSize: CGSize) -> CGRect {
        guard containerSize.width > 0, containerSize.height > 0 else { return .zero }

        let imageSize = roomImageSize(for: imageName)
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let imageAspectRatio = imageSize.width / imageSize.height
        let containerAspectRatio = containerSize.width / containerSize.height

        if containerAspectRatio > imageAspectRatio {
            let height = containerSize.height
            let width = height * imageAspectRatio
            return CGRect(
                x: (containerSize.width - width) / 2,
                y: 0,
                width: width,
                height: height
            )
        } else {
            let width = containerSize.width
            let height = width / imageAspectRatio
            return CGRect(
                x: 0,
                y: (containerSize.height - height) / 2,
                width: width,
                height: height
            )
        }
    }

    private func roomImageSize(for imageName: String) -> CGSize {
        guard let image = UIImage(named: imageName), image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: 1, height: 1)
        }
        return image.size
    }

    private func isWealthDestination(_ destination: SmallWorldDestination?) -> Bool {
        guard let destination else { return false }
        if case .wealth = destination {
            return true
        }
        return false
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
