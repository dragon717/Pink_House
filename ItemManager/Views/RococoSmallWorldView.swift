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
        let action: () -> Void
    }
    
    // Room 1 (Floor 1) Hotspots
    private var room1Hotspots: [HotspotData] {
        [
            HotspotData(name: "穿搭手帐", rect: CGRect(x: 0.35, y: 0.53, width: 0.08, height: 0.19), color: .orange, label: "穿搭手帐", labelStyle: .diagonal(angle: -35), labelPosition: CGPoint(x: 0.41, y: 0.725)) {
                destination = .ootd
            },
            HotspotData(name: "来财", rect: CGRect(x: 0.46, y: 0.68, width: 0.06, height: 0.08), color: .yellow, label: "马上来财", labelStyle: .diagonal(angle: -35), labelPosition: CGPoint(x: 0.52, y: 0.77)) {
                destination = .wealth
            },
            HotspotData(name: "衣橱", rect: CGRect(x: 0.45, y: 0.12, width: 0.24, height: 0.24), color: .blue, label: "少女衣橱", labelStyle: .diagonal(angle: -35), labelPosition: CGPoint(x: 0.525, y: 0.12)) {
                withAnimation(.easeIn(duration: 0.5)) {
                    isPlayingOpeningAnimation = true
                }
            },
        ]
    }
    
    // Room 2 (Floor 2) Hotspots
    private var room2Hotspots: [HotspotData] {
        [
            HotspotData(name: "衣橱", rect: CGRect(x: 0.05, y: 0.25, width: 0.125, height: 0.29), color: .blue, label: "少女衣橱", labelStyle: .diagonal(angle: -35), labelPosition: CGPoint(x: 0.095, y: 0.24)) {
                withAnimation(.easeIn(duration: 0.5)) {
                    isPlayingOpeningAnimation = true
                }
            },
            HotspotData(name: "尾款天使", rect: CGRect(x: 0.08, y: 0.54, width: 0.1, height: 0.11), color: .blue, label: "尾款天使", labelStyle: .diagonal(angle: 35), labelPosition: CGPoint(x: 0.1, y: 0.66)) {
                selectedTab = 0
                homeTab = .depositPlan
            },
            // 萌宠会动
//            HotspotData(name: "萌宠", rect: CGRect(x: 0.45, y: 0.48, width: 0.13, height: 0.21), color: .pink) {
//                destination = .pet
//            },

            HotspotData(name: "日历", rect: CGRect(x: 0.44, y: 0.77, width: 0.082, height: 0.121), color: .purple, label: "梦裙日历", labelStyle: .diagonal(angle: 35), labelPosition: CGPoint(x: 0.45, y: 0.92)) {
                destination = .calendar
            },

            HotspotData(name: "拼豆工坊", rect: CGRect(x: 0.70, y: 0.45, width: 0.12, height: 0.15), color: .pink, label: "拼豆工坊", labelStyle: .diagonal(angle: -35), labelPosition: CGPoint(x: 0.78, y: 0.62)) {
                destination = .perler
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
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay(
                        roomContent(imageName: imageName, hotspots: hotspots)
                    )
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }
    
    @ViewBuilder
    private func roomContent(imageName: String, hotspots: [HotspotData]) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(hotspots) { hotspot in
                    ZStack {
                        Button(action: {
                            print("[RococoSmallWorldView] 热区点击: \(hotspot.name), 坐标: (\(hotspot.rect.minX), \(hotspot.rect.minY)), 尺寸: \(geo.size)")
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
                            width: max(1, hotspot.rect.width * geo.size.width),
                            height: max(1, hotspot.rect.height * geo.size.height)
                        )
                        .position(
                            x: (hotspot.rect.minX + hotspot.rect.width/2) * geo.size.width,
                            y: (hotspot.rect.minY + hotspot.rect.height/2) * geo.size.height
                        )
                        
                        if let label = hotspot.label {
                            let labelPos = hotspot.labelPosition ?? CGPoint(x: hotspot.rect.midX, y: hotspot.rect.midY)
                            
                            FloatingTextLabel(text: label, style: hotspot.labelStyle)
                                .allowsHitTesting(false)
                                .position(
                                    x: labelPos.x * geo.size.width,
                                    y: labelPos.y * geo.size.height
                                )
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                
                SmallWorldPetOverlay(
                    viewModel: petViewModel,
                    roomIndex: imageName.contains("rococo_1") ? 0 : 1,
                    geometry: geo
                )
                .allowsHitTesting(petViewModel.isDebugMode)
            }
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
