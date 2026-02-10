//
//  SmallWorldView.swift
//  ItemManager
//
//  Created by Pink House Dev on 2/10/26.
//

import SwiftUI
import UIKit // 导入 UIKit 以使用 UITabBar 等 API
import RealityKit
import CoreMotion

enum SmallWorldDestination {
    case menu
    case ootd
    case pet
    case wealth
    case calendar
}

struct SmallWorldView: View {
    @Binding var selectedTab: Int // MainTabView selection
    @Binding var homeTab: HomeTab // HomeView selection
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    
    // 图片原始尺寸 1919x1079
    private let imageSize = CGSize(width: 1919, height: 1079)
    
    // 调试模式：开启后显示热区范围 (仅在 Debug 模式下生效)
    private var showDebugHotspots: Bool {
        return false
//        return true
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            Group {
                                // 限制 iOS 26 生效
                                if #available(iOS 26.0, *) {
                                    SpatialBackgroundView(
                                        imageName: "small_world_bg",
                                        imageExtension: "png",
                                        onSelectOOTD: { destination = .ootd },
                                        onSelectWardrobe: {
                                            withAnimation(.easeIn(duration: 0.5)) {
                                                isPlayingOpeningAnimation = true
                                            }
                                        },
                                        onSelectWealth: { destination = .wealth },
                                        onSelectCalendar: { destination = .calendar }
                                    )
                                } else {
                                    Image("small_world_bg") // 确保图片已添加至 Assets
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                }
                            }
                            .frame(width: geometry.size.height * (imageSize.width / imageSize.height), height: geometry.size.height)
                            .overlay(
                                    ZStack(alignment: .topLeading) {
                                        // 1. OOTD (今日穿搭) - 最左侧
                                        InteractionHotspot(rect: CGRect(x: 0.22, y: 0.3, width: 0.12, height: 0.6), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots, debugColor: .orange) {
                                            destination = .ootd
                                        }
                                        
                                        // 2. 衣橱 (少女衣橱)
                                        InteractionHotspot(rect: CGRect(x: 0.38, y: 0.26, width: 0.175, height: 0.7), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots) {
                                            withAnimation(.easeIn(duration: 0.5)) {
                                                isPlayingOpeningAnimation = true
                                            }
                                        }
                                        
                                        // 3. 猪 (来财)
                                        InteractionHotspot(rect: CGRect(x: 0.63, y: 0.55, width: 0.15, height: 0.16), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots) {
                                            destination = .wealth
                                        }
                                        
                                        // 4. 墙上的日历 (梦裙日历)
                                        CalendarHotspot(rect: CGRect(x: 0.585, y: 0.35, width: 0.102, height: 0.155), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots) {
                                            destination = .calendar
                                        }
                                        
                                        // 中心锚点，用于初始定位
                                        Color.clear
                                            .frame(width: 1, height: 1)
                                            .position(x: (geometry.size.height * (imageSize.width / imageSize.height)) / 2,
                                                      y: geometry.size.height / 2)
                                            .id("centerAnchor")
                                    }
                                )
                        }
                        .disableScrollBounce() // 禁用边缘回弹，必须放在 ScrollView 内容视图上
                    }
                    .ignoresSafeArea()
                    .onAppear {
                        // 延迟滚动以确保视图加载完成
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                scrollProxy.scrollTo("centerAnchor", anchor: .center)
                            }
                        }
                    }
                }
            }
            .background(Color.black) // 防止滑动穿透露出底层背景
            .ignoresSafeArea() // 确保 GeometryReader 获取全屏尺寸
            .toolbarBackground(.hidden, for: .tabBar) // 尝试 SwiftUI 原生隐藏
            .onAppear {
                // 强制设置 UITabBar 为完全透明
                let appearance = UITabBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundColor = .clear
                appearance.shadowImage = UIImage()
                appearance.backgroundImage = UIImage()
                
                UITabBar.appearance().standardAppearance = appearance
                if #available(iOS 15.0, *) {
                    UITabBar.appearance().scrollEdgeAppearance = appearance
                }
            }
            .onDisappear {
            // 恢复默认的半透明背景
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            
            UITabBar.appearance().standardAppearance = appearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
        }
    }
}
}

/// 交互热区组件
struct InteractionHotspot: View {
    let rect: CGRect // 归一化坐标 (0.0 - 1.0)
    let geometry: GeometryProxy
    let imageSize: CGSize
    var showDebug: Bool = false
    var debugColor: Color = .red
    let action: () -> Void
    
    var body: some View {
        let width = geometry.size.height * (imageSize.width / imageSize.height)
        let height = geometry.size.height
        
        Button(action: action) {
            if showDebug {
                Rectangle()
                    .fill(debugColor.opacity(0.3))
                    .border(debugColor)
            } else {
                Color.clear
                    .contentShape(Rectangle())
            }
        }
        .frame(width: rect.width * width, height: rect.height * height)
        .offset(x: rect.minX * width, y: rect.minY * height)
    }
}



/// 日历专属热区，带容器跟随效果
struct CalendarHotspot: View {
    let rect: CGRect
    let geometry: GeometryProxy
    let imageSize: CGSize
    var showDebug: Bool = false
    let action: () -> Void
    
    var body: some View {
        let width = geometry.size.height * (imageSize.width / imageSize.height)
        let height = geometry.size.height
        
        ZStack(alignment: .topLeading) {
            // 点击跳转
            Button(action: action) {
                if showDebug {
                    Rectangle()
                        .fill(Color.blue.opacity(0.3))
                        .border(Color.blue)
                } else {
                    Color.clear
                        .contentShape(Rectangle())
                }
            }
            
            // 随动内容：当月界面预览
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.month, from: Date()))月")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.pink)
                
                // 简单的网格模拟
                let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)
                LazyVGrid(columns: columns, spacing: 1) {
                    ForEach(0..<28) { _ in
                        Circle()
                            .fill(Color.pink.opacity(0.3))
                            .frame(width: 2, height: 2)
                    }
                }
            }
            .padding(4)
            .background(Color.white.opacity(0.8))
            .cornerRadius(4)
            .frame(width: rect.width * width * 0.8, height: rect.height * height * 0.6)
            .position(x: rect.midX * width, y: rect.midY * height)
            .allowsHitTesting(false) // 让点击穿透到下层 Button
        }
        .frame(width: rect.width * width, height: rect.height * height)
        .offset(x: rect.minX * width, y: rect.minY * height)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var selectedTab = 1
        @State var homeTab: HomeTab = .wardrobe
        @State var destination: SmallWorldDestination = .menu
        @State var isPlayingOpeningAnimation = false
        
        var body: some View {
            SmallWorldView(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination,
                isPlayingOpeningAnimation: $isPlayingOpeningAnimation
            )
        }
    }
    return PreviewWrapper()
}


// MARK: - iOS 26 Spatial Scene Support
// 以下代码实现了 iOS 26 的 Spatial Scene 效果。

@available(iOS 26.0, *)
struct SpatialBackgroundView: View {
    let imageName: String
    let imageExtension: String
    
    // 监听全局资源管理器
    @ObservedObject private var assetManager = SpatialAssetManager.shared
    
    // Binding to pass actions back to parent
    var onSelectOOTD: () -> Void
    var onSelectWardrobe: () -> Void
    var onSelectWealth: () -> Void
    var onSelectCalendar: () -> Void
    
    // 模拟陀螺仪视差效果（Mock 环境增强版）
    // 即使在 Mock 模式下，我们也希望看到背景的动态反馈
    @State private var motionManager = CMMotionManager()
    @State private var parallaxOffset: CGSize = .zero
    
    // 缓存背景图，避免 GeometryReader 重绘时反复 IO
    @State private var cachedBackgroundImage: UIImage?
    
    var body: some View {
        ZStack {
            if let spatialImage = assetManager.spatialImage {
                // 如果是真实环境，RealityView 会自动处理
                // 这里我们在 Mock 环境下增加手动视差模拟
                
                // 暂时禁用 RealityView 以避免 Mock 环境下的渲染错误日志
                // 在未来真实 iOS 26 环境下，可以恢复此代码块
                /*
                RealityView { content in
                    print("[SpatialBackgroundView] 初始化 RealityView")
                    
                    var presentation = ImagePresentationComponent(spatial3DImage: spatialImage)
                    presentation.desiredViewingMode = .spatial3D
                    
                    let entity = Entity()
                    entity.components.set(presentation)
                    
                    // --- 核心优化：将热区挂载到 3D 空间 ---
                    // 在真实 RealityKit 中，我们需要创建不可见的碰撞体 Entity，并将其位置与背景图中的物体对齐
                    // 这里的坐标 (x, y, z) 需要根据实际图片的 UV 映射来调试
                    
                    // 1. OOTD 热区
                    addSpatialHotspot(to: entity, name: "OOTD", position: [-0.3, 0, 0.1], size: [0.3, 0.8, 0.1], action: onSelectOOTD)
                    
                    // 2. 衣橱热区
                    addSpatialHotspot(to: entity, name: "Wardrobe", position: [-0.1, 0, 0.05], size: [0.3, 0.8, 0.1], action: onSelectWardrobe)
                    
                    // 3. 财富热区
                    addSpatialHotspot(to: entity, name: "Wealth", position: [0.3, -0.1, 0.2], size: [0.3, 0.3, 0.1], action: onSelectWealth)
                    
                    // 4. 日历热区
                    addSpatialHotspot(to: entity, name: "Calendar", position: [0.25, 0.2, 0.0], size: [0.2, 0.3, 0.1], action: onSelectCalendar)
                    
                    content.add(entity)
                }
                .overlay(
                    // 叠加一个调试层，仅在模拟器显示，证明进入了 3D 模式
                    VStack {
                        Spacer()
                        Text("Spatial Scene Active (Mock + Parallax)")
                            .font(.caption)
                            .padding(4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)
                            .padding()
                    }
                )
                */
                
                // Mock 回退渲染层：仅当 RealityKit 无法工作时（例如模拟器不支持）才生效
                // 在 Mock 环境下，我们恢复 CoreMotion 视差，作用于背景占位图
                // .background( // 移除 background 修饰符，直接作为主视图
                    GeometryReader { geo in
                        if let image = cachedBackgroundImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width * 1.15, height: geo.size.height * 1.15)
                                .offset(parallaxOffset)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                                .overlay(
                                    // 叠加交互热区 (2D Fallback)
                                    // 仅在 Mock 模式下启用，因为 RealityView 被禁用了
                                    ZStack(alignment: .topLeading) {
                                        // 这里需要手动转换归一化坐标到 GeometryReader 的 frame
                                        // 为简化演示，我们暂时省略热区重建，或者可以将原来的 InteractionHotspot 移回来
                                        // 但为了响应用户点击，我们必须添加热区
                                        
                                        // 1. OOTD
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .frame(width: geo.size.width * 0.15, height: geo.size.height * 0.7)
                                            .position(x: geo.size.width * 0.275, y: geo.size.height * 0.55) // 估算位置
                                            .onTapGesture(perform: onSelectOOTD)
                                            
                                        // 2. 衣橱
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .frame(width: geo.size.width * 0.2, height: geo.size.height * 0.8)
                                            .position(x: geo.size.width * 0.49, y: geo.size.height * 0.5)
                                            .onTapGesture(perform: onSelectWardrobe)
                                            
                                        // 3. 财富
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .frame(width: geo.size.width * 0.18, height: geo.size.height * 0.22)
                                            .position(x: geo.size.width * 0.79, y: geo.size.height * 0.56)
                                            .onTapGesture(perform: onSelectWealth)
                                            
                                        // 4. 日历
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .frame(width: geo.size.width * 0.13, height: geo.size.height * 0.21)
                                            .position(x: geo.size.width * 0.705, y: geo.size.height * 0.295)
                                            .onTapGesture(perform: onSelectCalendar)
                                    }
                                )
                        } else {
                            Color.black
                        }
                    }
                // )
                .onAppear {
                    // 加载并缓存图片
                    if cachedBackgroundImage == nil {
                        // 在后台线程加载图片
                        DispatchQueue.global(qos: .userInitiated).async {
                            if let image = UIImage(contentsOfFile: spatialImage.url.path) {
                                DispatchQueue.main.async {
                                    self.cachedBackgroundImage = image
                                }
                            }
                        }
                    }
                    startMotionUpdates()
                }
                .onDisappear { motionManager.stopDeviceMotionUpdates() }
                // 简单的淡入过渡
                .transition(.opacity.animation(.easeOut(duration: 0.8)))
                
            } else {
                // 加载占位
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(
                        ZStack {
                            Color.black.opacity(0.3)
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(.white)
                                Text("AI 空间数据生成中...")
                                    .font(.callout)
                                    .foregroundStyle(.white)
                            }
                        }
                    )
            }
        }
        .task {
            // 视图出现时，如果还没准备好，尝试再次触发预加载（防止 App 启动时没触发成功）
            if !assetManager.isReady {
                assetManager.preload(imageName: imageName, extension: imageExtension)
            }
        }
    }
    
    // 辅助函数：添加空间热区
    // 在 Mock 环境下，我们仅模拟这个函数签名，实际上无法在 iOS 平台添加真实的 RealityKit 碰撞体
    // 除非我们处于 visionOS 或未来的 iOS 26+ 环境
    private func addSpatialHotspot(to parent: Entity, name: String, position: SIMD3<Float>, size: SIMD3<Float>, action: @escaping () -> Void) {
        // 创建一个不可见的 ModelEntity 作为热区
        // 使用 UnlitMaterial 且 opacity 为 0，确保完全不可见且不产生高光
        // 注意：在 RealityKit 中，如果要响应输入，通常需要 CollisionComponent，
        // 而 ModelComponent 仅用于可视。这里为了消除白线，我们只保留 CollisionComponent (如果支持)，
        // 或者使用完全透明的材质。
        
        let material = UnlitMaterial(color: .clear)
        let hotspot = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [material]
        )
        
        // 进一步确保透明度为 0
        hotspot.components.set(OpacityComponent(opacity: 0.0))
        
        // 设置位置（相对于父实体）
        hotspot.position = position
        hotspot.name = name
        
        // 添加碰撞组件 (CollisionComponent)
        // 注意：在 Mock 环境下，RealityView 的 TapGesture 需要配合 SpatialTapGesture 才能生效
        // 这里仅作代码演示
        // hotspot.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
        // hotspot.components.set(InputTargetComponent())
        
        parent.addChild(hotspot)
    }
    
    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            // 如果设备不支持陀螺仪（如模拟器），使用简单的呼吸动画
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                parallaxOffset = CGSize(width: -20, height: -10)
            }
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 0.02 // 50Hz
        motionManager.startDeviceMotionUpdates(to: .main) { data, error in
            guard let data = data else { return }
            
            // 获取倾斜角度 (Roll & Pitch)
            let roll = CGFloat(data.attitude.roll)
            let pitch = CGFloat(data.attitude.pitch)
            
            // 计算位移：最大移动范围 30pt (稍微收敛一点，避免过度移动)
            let targetX = roll * 30
            let targetY = pitch * 30
            
            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8)) {
                self.parallaxOffset = CGSize(width: -targetX, height: targetY)
            }
        }
    }
}
