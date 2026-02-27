//
//  ImmersiveFlightView.swift
//  ItemManager
//
//  世界书 - 沉浸式飞行体验
//

import SwiftUI
import MapKit

// MARK: - 沉浸式飞行主视图
struct ImmersiveFlightView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @State private var flightPhase: FlightPhase = .taxi
    @State private var planeOffset: CGFloat = 0
    @State private var cloudOffset: CGFloat = 0
    @State private var turbulence: Double = 0
    @State private var showNarrative = true
    @State private var showAirplaneWindow = false

    enum FlightPhase {
        case taxi      // 滑行
        case takeoff   // 起飞
        case cruise    // 巡航
        case descent   // 下降
        case landing   // 着陆
    }

    var body: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            // 导航栏高度约 44pt，加上间距
            let navBarOffset = safeAreaTop + 70
            // TabBar 高度约 49pt，加上间距
            let tabBarOffset = safeAreaBottom + 90
            
            ZStack {
                // 一直保持地图界面（图一）
                AirportMapView(viewModel: viewModel, flightPhase: flightPhase)
                
                // 飞机震动效果（仅在巡航及以后阶段）
                if flightPhase != .taxi && flightPhase != .takeoff {
                    VStack {
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: CGFloat.random(in: -turbulence...turbulence),
                            y: CGFloat.random(in: -turbulence...turbulence))
                }
                
                // UI 覆盖层 - 使用 GeometryReader 精确定位
                VStack(spacing: 0) {
                    // 顶部状态栏（在导航栏下方）
                    Spacer().frame(height: navBarOffset)
                    
                    FlightStatusBar(viewModel: viewModel, flightPhase: flightPhase)
                    
                    Spacer()
                    
                    // 底部控制面板（在 TabBar 上方）
                    FlightControlPanel(
                        viewModel: viewModel,
                        flightPhase: $flightPhase,
                        showAirplaneWindow: $showAirplaneWindow
                    )
                    
                    Spacer().frame(height: tabBarOffset)
                }
                
                // 叙事文字
                if showNarrative, !viewModel.currentNarrative.isEmpty {
                    NarrativeOverlay(text: viewModel.currentNarrative)
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            startFlightSimulation()
        }
        .onChange(of: viewModel.flightProgress) { progress in
            updateFlightPhase(progress)
        }
        .sheet(isPresented: $showAirplaneWindow) {
            AirplaneWindowView(
                flightPhase: flightPhase,
                progress: viewModel.flightProgress,
                destination: viewModel.selectedLandmark
            )
            .presentationDetents([.fraction(0.9)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(40)
        }
    }
    
    private func startFlightSimulation() {
        // 震动效果
        withAnimation(.easeInOut(duration: 0.1).repeatForever(autoreverses: true)) {
            turbulence = 1.5
        }
        
        // 叙事显示循环
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            withAnimation {
                showNarrative.toggle()
            }
        }
    }
    
    private func updateFlightPhase(_ progress: Double) {
        switch progress {
        case 0..<0.1:
            flightPhase = .taxi
        case 0.1..<0.2:
            flightPhase = .takeoff
        case 0.2..<0.8:
            flightPhase = .cruise
        case 0.8..<0.9:
            flightPhase = .descent
        default:
            flightPhase = .landing
        }
    }
}

// MARK: - Lo 裙设计理念
struct LolitaDesignPhilosophy {
    static let quotes = [
        "每一针一线，都是对美好生活的向往",
        "蕾丝与缎带编织的，是少女心中的童话",
        "在繁复的褶皱中，藏着对细节的执着",
        "裙摆飞扬的瞬间，是自由与优雅的共舞",
        "精致的不仅是衣裳，更是对生活的态度",
        "每一次穿上 Lo 裙，都是与自己的浪漫约会",
        "在快节奏的世界里，慢下来做一场关于美的梦"
    ]
    
    static func randomQuote() -> String {
        quotes.randomElement() ?? quotes[0]
    }
}

// MARK: - 飞机舷窗视图（Sheet 方式）
struct AirplaneWindowView: View {
    let flightPhase: ImmersiveFlightView.FlightPhase
    let progress: Double
    let destination: Landmark?
    @Environment(\.dismiss) private var dismiss

    @State private var sunPosition: CGFloat = 0
    @State private var cloudLayers: [CloudLayer] = []
    @State private var quote: String = ""

    struct CloudLayer: Identifiable {
        let id = UUID()
        let scale: CGFloat
        let opacity: Double
        let speed: Double
        let yPosition: CGFloat  // 固定的垂直位置
    }

    var body: some View {
        GeometryReader { geo in
            // 舷窗占界面 50%
            let windowWidth: CGFloat = geo.size.width * 0.5
            let windowHeight: CGFloat = windowWidth * 1.1
            // 大圆角
            let cornerRadius: CGFloat = 50

            ZStack {
                // 透明背景
                Color.clear
                    .ignoresSafeArea()

                VStack(spacing: 30) {
                    Spacer()

                    // 舷窗视图
                    ZStack {
                        // 外层深色背景（机身内壁）
                        RoundedRectangle(cornerRadius: cornerRadius + 12)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.15, green: 0.15, blue: 0.18),
                                        Color(red: 0.08, green: 0.08, blue: 0.10),
                                        Color(red: 0.12, green: 0.12, blue: 0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: windowWidth + 24, height: windowHeight + 24)
                            .shadow(color: Color.black.opacity(0.8), radius: 20, x: 0, y: 8)

                        // 中层窗框（白色/灰色边框）
                        RoundedRectangle(cornerRadius: cornerRadius + 4)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.85, green: 0.87, blue: 0.90),
                                        Color(red: 0.70, green: 0.72, blue: 0.75),
                                        Color(red: 0.55, green: 0.57, blue: 0.60)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: windowWidth + 8, height: windowHeight + 8)
                            .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)

                        // 主窗框（更亮的边框）
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.95, green: 0.96, blue: 0.98),
                                        Color(red: 0.80, green: 0.82, blue: 0.85),
                                        Color(red: 0.65, green: 0.67, blue: 0.70)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: windowWidth + 4, height: windowHeight + 4)

                        // 窗外景色（在边框内部）
                        ZStack {
                            // 天空渐变背景 - 使用明确的颜色
                            LinearGradient(
                                colors: [
                                    Color(red: 0.2, green: 0.5, blue: 0.9),
                                    Color(red: 0.6, green: 0.8, blue: 0.95)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )

                            // 太阳/月亮
                            CelestialBodyView(phase: flightPhase, progress: progress)
                                .offset(y: sunPosition)

                            // 远景薄雾层（增加深度感）
                            MistLayerView()

                            // 云层
                            ForEach(cloudLayers) { cloud in
                                CloudView(
                                    scale: cloud.scale,
                                    opacity: cloud.opacity,
                                    speed: cloud.speed
                                )
                                .position(
                                    x: (windowWidth - 16) * 0.5,
                                    y: (windowHeight - 16) * cloud.yPosition
                                )
                            }

                            // 近景雾气层（增加氛围感）
                            ForegroundMistView()

                            // 地面景观（仅在低空显示）
                            if flightPhase == .takeoff || flightPhase == .landing || progress < 0.1 || progress > 0.9 {
                                GroundView(destination: destination)
                                    .offset(y: (windowHeight - 16) * 0.3)
                            }
                        }
                        .frame(width: windowWidth - 16, height: windowHeight - 16)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius - 8))

                        // 内部阴影边缘（叠加在景色上）
                        RoundedRectangle(cornerRadius: cornerRadius - 2)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.6),
                                        Color.clear,
                                        Color.black.opacity(0.4)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 6
                            )
                            .frame(width: windowWidth - 6, height: windowHeight - 6)

                        // 顶部高光（玻璃反光效果）
                        RoundedRectangle(cornerRadius: cornerRadius - 4)
                            .trim(from: 0.0, to: 0.5)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.4),
                                        Color.white.opacity(0.1),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 4
                            )
                            .frame(width: windowWidth - 12, height: windowHeight - 12)
                            .offset(y: -3)

                        // 左侧边缘光
                        RoundedRectangle(cornerRadius: cornerRadius - 4)
                            .trim(from: 0.15, to: 0.35)
                            .stroke(
                                Color.white.opacity(0.2),
                                lineWidth: 3
                            )
                            .frame(width: windowWidth - 10, height: windowHeight - 10)
                            .offset(x: -1)
                    }

                    // Lo 裙设计理念文字
                    VStack(spacing: 12) {
                        Text("✦ 茶会物语 ✦")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(quote)
                            .font(.system(size: 16, weight: .medium, design: .serif))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                            .padding(.horizontal, 40)
                    }
                    .padding(.vertical, 20)

                    Spacer()
                }
            }
        }
        .onAppear {
            // 初始化云层 - 创建多层次的高空云层效果
            cloudLayers = (0..<6).map { i in
                CloudLayer(
                    scale: CGFloat.random(in: 0.6...1.4),
                    opacity: Double.random(in: 0.4...0.9),
                    speed: Double.random(in: 12...25),
                    yPosition: CGFloat.random(in: 0.2...0.7)
                )
            }
            // 随机选择一条理念
            quote = LolitaDesignPhilosophy.randomQuote()
            
            // 设置太阳位置
            withAnimation(.easeInOut(duration: 2)) {
                sunPosition = -50
            }
        }
    }
}

// MARK: - 天空渐变
// MARK: - 天空背景视图（用于巡航阶段）
struct SkyBackgroundView: View {
    let phase: ImmersiveFlightView.FlightPhase
    let progress: Double
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { _ in
            LinearGradient(
                colors: skyColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
    
    private var skyColors: [Color] {
        switch phase {
        case .taxi, .takeoff:
            return [
                Color(red: 0.4, green: 0.7, blue: 0.9),
                Color(red: 0.7, green: 0.85, blue: 0.95)
            ]
        case .cruise:
            // 根据进度改变天空颜色（模拟时间流逝）
            if progress < 0.3 {
                return [
                    Color(red: 0.2, green: 0.5, blue: 0.9),
                    Color(red: 0.6, green: 0.8, blue: 0.95)
                ]
            } else if progress < 0.7 {
                return [
                    Color(red: 0.1, green: 0.4, blue: 0.8),
                    Color(red: 0.5, green: 0.75, blue: 0.95)
                ]
            } else {
                return [
                    Color(red: 0.9, green: 0.5, blue: 0.3),
                    Color(red: 0.95, green: 0.7, blue: 0.5)
                ]
            }
        case .descent, .landing:
            return [
                Color(red: 0.95, green: 0.6, blue: 0.4),
                Color(red: 0.98, green: 0.8, blue: 0.6)
            ]
        }
    }
}

// MARK: - 天空渐变（用于舷窗内部）
struct SkyGradientView: View {
    let phase: ImmersiveFlightView.FlightPhase
    let progress: Double
    
    var body: some View {
        LinearGradient(
            colors: skyColors,
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var skyColors: [Color] {
        switch phase {
        case .taxi, .takeoff:
            return [
                Color(red: 0.4, green: 0.7, blue: 0.9),
                Color(red: 0.7, green: 0.85, blue: 0.95)
            ]
        case .cruise:
            // 根据进度改变天空颜色（模拟时间流逝）
            if progress < 0.3 {
                return [
                    Color(red: 0.2, green: 0.5, blue: 0.9),
                    Color(red: 0.6, green: 0.8, blue: 0.95)
                ]
            } else if progress < 0.7 {
                return [
                    Color(red: 0.1, green: 0.4, blue: 0.8),
                    Color(red: 0.5, green: 0.75, blue: 0.95)
                ]
            } else {
                return [
                    Color(red: 0.9, green: 0.5, blue: 0.3),
                    Color(red: 0.95, green: 0.7, blue: 0.5)
                ]
            }
        case .descent, .landing:
            return [
                Color(red: 0.95, green: 0.6, blue: 0.4),
                Color(red: 0.98, green: 0.8, blue: 0.6)
            ]
        }
    }
}

// MARK: - 天体（太阳/月亮）
struct CelestialBodyView: View {
    let phase: ImmersiveFlightView.FlightPhase
    let progress: Double
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 太阳光晕
                if phase == .cruise && progress < 0.7 {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.yellow.opacity(0.3),
                                    Color.yellow.opacity(0.1),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 20,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                }
                
                // 太阳/月亮本体
                Circle()
                    .fill(celestialColor)
                    .frame(width: 60, height: 60)
                    .shadow(color: celestialColor.opacity(0.5), radius: 20)
            }
            .position(
                x: geo.size.width * 0.8,
                y: geo.size.height * 0.2
            )
        }
    }
    
    private var celestialColor: Color {
        switch phase {
        case .taxi, .takeoff:
            return Color.yellow
        case .cruise:
            return progress > 0.7 ? Color.orange : Color.yellow
        case .descent, .landing:
            return Color.orange
        }
    }
}

// MARK: - 云朵视图
struct CloudView: View {
    let scale: CGFloat
    let opacity: Double
    let speed: Double
    @State private var offset: CGFloat = -300
    @State private var isAnimating = false
    
    var body: some View {
        Canvas { context, size in
            // 绘制云朵形状 - 使用更拟物的高空云层样式
            let cloudPath = createCloudPath(in: CGRect(origin: .zero, size: size))
            
            // 绘制云层阴影/深度效果
            context.fill(cloudPath, with: .color(Color.white.opacity(opacity * 0.3)))
            
            // 主云层 - 使用渐变营造立体感
            context.fill(cloudPath, with: .color(Color.white.opacity(opacity)))
            
            // 高光部分
            let highlightPath = createCloudHighlight(in: CGRect(origin: .zero, size: size))
            context.fill(highlightPath, with: .color(Color.white.opacity(opacity * 0.6)))
        }
        .frame(width: 180 * scale, height: 100 * scale)
        .offset(x: offset)
        .onAppear {
            // 延迟启动动画，创造层次感
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0...2)) {
                isAnimating = true
                withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) {
                    offset = 400
                }
            }
        }
    }
    
    private func createCloudPath(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        // 高空云层 - 更扁平、更飘逸的形状
        // 主云团
        path.addEllipse(in: CGRect(x: width * 0.1, y: height * 0.4, width: width * 0.5, height: height * 0.4))
        path.addEllipse(in: CGRect(x: width * 0.25, y: height * 0.2, width: width * 0.55, height: height * 0.5))
        path.addEllipse(in: CGRect(x: width * 0.5, y: height * 0.35, width: width * 0.4, height: height * 0.4))
        path.addEllipse(in: CGRect(x: width * 0.35, y: height * 0.5, width: width * 0.45, height: height * 0.35))
        
        // 添加飘逸的云尾
        path.addEllipse(in: CGRect(x: -width * 0.1, y: height * 0.5, width: width * 0.3, height: height * 0.25))
        path.addEllipse(in: CGRect(x: width * 0.8, y: height * 0.45, width: width * 0.25, height: height * 0.3))
        
        return path
    }
    
    private func createCloudHighlight(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        // 云层顶部高光
        path.addEllipse(in: CGRect(x: width * 0.3, y: height * 0.25, width: width * 0.35, height: height * 0.25))
        path.addEllipse(in: CGRect(x: width * 0.4, y: height * 0.3, width: width * 0.25, height: height * 0.2))
        
        return path
    }
}

// MARK: - 远景薄雾层
struct MistLayerView: View {
    @State private var offset: CGFloat = 0
    
    var body: some View {
        Canvas { context, size in
            // 绘制多层薄雾
            for i in 0..<3 {
                let yOffset = CGFloat(i) * size.height * 0.3
                let path = Path { path in
                    path.move(to: CGPoint(x: 0, y: yOffset))
                    path.addCurve(
                        to: CGPoint(x: size.width, y: yOffset + 20),
                        control1: CGPoint(x: size.width * 0.3, y: yOffset - 30),
                        control2: CGPoint(x: size.width * 0.7, y: yOffset + 50)
                    )
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.addLine(to: CGPoint(x: 0, y: size.height))
                }
                context.fill(path, with: .color(Color.white.opacity(0.08 - Double(i) * 0.02)))
            }
        }
        .offset(x: offset)
        .onAppear {
            withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) {
                offset = -100
            }
        }
    }
}

// MARK: - 近景雾气层
struct ForegroundMistView: View {
    @State private var opacity: Double = 0
    
    var body: some View {
        LinearGradient(
            colors: [
                Color.clear,
                Color.white.opacity(0.1),
                Color.white.opacity(0.05),
                Color.clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .mask(
            Canvas { context, size in
                // 绘制流动的雾气带
                for i in 0..<2 {
                    let path = Path { path in
                        let baseY = size.height * (0.6 + CGFloat(i) * 0.2)
                        path.move(to: CGPoint(x: 0, y: baseY))
                        
                        for x in stride(from: 0, to: Int(size.width), by: 10) {
                            let wave = sin(Double(x) * 0.02 + Double(i) * 2) * 15
                            path.addLine(to: CGPoint(x: CGFloat(x), y: baseY + CGFloat(wave)))
                        }
                        
                        path.addLine(to: CGPoint(x: size.width, y: size.height))
                        path.addLine(to: CGPoint(x: 0, y: size.height))
                    }
                    context.fill(path, with: .color(Color.white))
                }
            }
        )
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                opacity = 0.6
            }
        }
    }
}

// MARK: - 地面景观
struct GroundView: View {
    let destination: Landmark?
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 地面渐变
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: groundColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // 地形特征
                if let landmark = destination {
                    TerrainFeaturesView(landmarkType: landmark.type)
                }
            }
            .frame(height: geo.size.height * 0.4)
        }
    }
    
    private var groundColors: [Color] {
        guard let landmark = destination else {
            return [Color.green.opacity(0.6), Color.green.opacity(0.8)]
        }
        
        switch landmark.type {
        case .glacier:
            return [Color.white.opacity(0.8), Color(red: 0.8, green: 0.9, blue: 0.95)]
        case .canyon:
            return [Color(red: 0.8, green: 0.6, blue: 0.4), Color(red: 0.6, green: 0.4, blue: 0.2)]
        case .oasis:
            return [Color(red: 0.9, green: 0.8, blue: 0.5), Color(red: 0.4, green: 0.7, blue: 0.4)]
        case .prairie:
            return [Color(red: 0.6, green: 0.8, blue: 0.3), Color(red: 0.5, green: 0.7, blue: 0.2)]
        case .aurora:
            return [Color(red: 0.2, green: 0.3, blue: 0.5), Color(red: 0.1, green: 0.2, blue: 0.4)]
        case .castle:
            return [Color(red: 0.5, green: 0.7, blue: 0.4), Color(red: 0.4, green: 0.6, blue: 0.3)]
        case .sakura:
            return [Color(red: 0.95, green: 0.8, blue: 0.85), Color(red: 0.9, green: 0.7, blue: 0.75)]
        case .lavender:
            return [Color(red: 0.7, green: 0.6, blue: 0.9), Color(red: 0.6, green: 0.5, blue: 0.8)]
        }
    }
}

// MARK: - 地形特征
struct TerrainFeaturesView: View {
    let landmarkType: LandmarkType
    
    var body: some View {
        Canvas { context, size in
            switch landmarkType {
            case .glacier:
                drawGlacier(context: context, size: size)
            case .canyon:
                drawCanyon(context: context, size: size)
            case .oasis:
                drawOasis(context: context, size: size)
            case .prairie:
                drawPrairie(context: context, size: size)
            default:
                drawDefaultTerrain(context: context, size: size)
            }
        }
    }
    
    private func drawGlacier(context: GraphicsContext, size: CGSize) {
        // 绘制冰山
        var path = Path()
        path.move(to: CGPoint(x: size.width * 0.2, y: size.height))
        path.addLine(to: CGPoint(x: size.width * 0.35, y: size.height * 0.3))
        path.addLine(to: CGPoint(x: size.width * 0.5, y: size.height))
        context.fill(path, with: .color(Color.white.opacity(0.9)))
        
        var path2 = Path()
        path2.move(to: CGPoint(x: size.width * 0.5, y: size.height))
        path2.addLine(to: CGPoint(x: size.width * 0.7, y: size.height * 0.2))
        path2.addLine(to: CGPoint(x: size.width * 0.9, y: size.height))
        context.fill(path2, with: .color(Color.white.opacity(0.8)))
    }
    
    private func drawCanyon(context: GraphicsContext, size: CGSize) {
        // 绘制峡谷层次
        for i in 0..<5 {
            var path = Path()
            let y = size.height * (0.3 + Double(i) * 0.15)
            path.move(to: CGPoint(x: 0, y: y))
            path.addCurve(
                to: CGPoint(x: size.width, y: y + 20),
                control1: CGPoint(x: size.width * 0.3, y: y - 30),
                control2: CGPoint(x: size.width * 0.7, y: y + 50)
            )
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            let opacity = 0.3 + Double(i) * 0.15
            context.fill(path, with: .color(Color(red: 0.7 - Double(i) * 0.1, green: 0.5 - Double(i) * 0.08, blue: 0.3 - Double(i) * 0.05).opacity(opacity)))
        }
    }
    
    private func drawOasis(context: GraphicsContext, size: CGSize) {
        // 绘制绿洲湖泊
        context.fill(
            Path(ellipseIn: CGRect(x: size.width * 0.3, y: size.height * 0.4, width: size.width * 0.4, height: size.height * 0.3)),
            with: .color(Color.blue.opacity(0.6))
        )
        // 棕榈树
        for i in 0..<3 {
            let x = size.width * (0.2 + Double(i) * 0.3)
            drawPalmTree(context: context, at: CGPoint(x: x, y: size.height * 0.6))
        }
    }
    
    private func drawPalmTree(context: GraphicsContext, at position: CGPoint) {
        // 树干
        var trunk = Path()
        trunk.move(to: CGPoint(x: position.x - 3, y: position.y))
        trunk.addLine(to: CGPoint(x: position.x - 2, y: position.y - 40))
        trunk.addLine(to: CGPoint(x: position.x + 2, y: position.y - 40))
        trunk.addLine(to: CGPoint(x: position.x + 3, y: position.y))
        context.fill(trunk, with: .color(Color.brown))
        
        // 树冠
        for angle in stride(from: 0, to: 360, by: 45) {
            var leaf = Path()
            let rad = Double(angle) * .pi / 180
            let endX = position.x + cos(rad) * 25
            let endY = position.y - 40 + sin(rad) * 10
            leaf.move(to: CGPoint(x: position.x, y: position.y - 40))
            leaf.addQuadCurve(
                to: CGPoint(x: endX, y: endY),
                control: CGPoint(x: position.x + cos(rad) * 15, y: position.y - 55)
            )
            context.stroke(leaf, with: .color(Color.green), lineWidth: 3)
        }
    }
    
    private func drawPrairie(context: GraphicsContext, size: CGSize) {
        // 绘制起伏的草原
        for i in 0..<8 {
            var path = Path()
            let baseY = size.height * (0.5 + Double(i) * 0.08)
            path.move(to: CGPoint(x: 0, y: baseY))
            
            for x in stride(from: 0, to: Int(size.width), by: 20) {
                let y = baseY + sin(Double(x) * 0.02 + Double(i)) * 10
                path.addLine(to: CGPoint(x: CGFloat(x), y: y))
            }
            
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            
            let greenValue = 0.7 - Double(i) * 0.05
            context.fill(path, with: .color(Color(red: 0.4, green: greenValue, blue: 0.2).opacity(0.6)))
        }
    }
    
    private func drawDefaultTerrain(context: GraphicsContext, size: CGSize) {
        // 默认地形
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height * 0.5))
        path.addCurve(
            to: CGPoint(x: size.width, y: size.height * 0.6),
            control1: CGPoint(x: size.width * 0.3, y: size.height * 0.3),
            control2: CGPoint(x: size.width * 0.7, y: size.height * 0.7)
        )
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        context.fill(path, with: .color(Color.green.opacity(0.5)))
    }
}

// MARK: - 舷窗边框（大圆角矩形）
struct WindowFrameView: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            // 外层深色背景（机身内壁）
            RoundedRectangle(cornerRadius: cornerRadius + 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.15, blue: 0.18),
                            Color(red: 0.08, green: 0.08, blue: 0.10),
                            Color(red: 0.12, green: 0.12, blue: 0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: width + 24, height: height + 24)
                .shadow(color: Color.black.opacity(0.8), radius: 20, x: 0, y: 8)

            // 中层窗框（白色/灰色边框）
            RoundedRectangle(cornerRadius: cornerRadius + 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.85, green: 0.87, blue: 0.90),
                            Color(red: 0.70, green: 0.72, blue: 0.75),
                            Color(red: 0.55, green: 0.57, blue: 0.60)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: width + 8, height: height + 8)
                .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)

            // 内层窗框阴影
            RoundedRectangle(cornerRadius: cornerRadius + 2)
                .fill(Color.black.opacity(0.3))
                .frame(width: width + 6, height: height + 6)
                .offset(x: 1, y: 2)

            // 主窗框（更亮的边框）
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.96, blue: 0.98),
                            Color(red: 0.80, green: 0.82, blue: 0.85),
                            Color(red: 0.65, green: 0.67, blue: 0.70)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: width + 4, height: height + 4)

            // 内部深色凹槽
            RoundedRectangle(cornerRadius: cornerRadius - 2)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.10, blue: 0.12),
                            Color(red: 0.20, green: 0.20, blue: 0.22),
                            Color(red: 0.15, green: 0.15, blue: 0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width, height: height)

            // 内部阴影边缘
            RoundedRectangle(cornerRadius: cornerRadius - 2)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.6),
                            Color.clear,
                            Color.black.opacity(0.4)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 6
                )
                .frame(width: width - 6, height: height - 6)

            // 顶部高光（玻璃反光效果）
            RoundedRectangle(cornerRadius: cornerRadius - 4)
                .trim(from: 0.0, to: 0.5)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.1),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 4
                )
                .frame(width: width - 12, height: height - 12)
                .offset(y: -3)

            // 左侧边缘光
            RoundedRectangle(cornerRadius: cornerRadius - 4)
                .trim(from: 0.15, to: 0.35)
                .stroke(
                    Color.white.opacity(0.2),
                    lineWidth: 3
                )
                .frame(width: width - 10, height: height - 10)
                .offset(x: -1)
        }
    }
}

// MARK: - 飞行状态栏
struct FlightStatusBar: View {
    @ObservedObject var viewModel: BigWorldViewModel
    let flightPhase: ImmersiveFlightView.FlightPhase
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                // 出发地
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.isDepartureHidden ? "***" : (viewModel.departureCity ?? "出发地"))
                        .font(.system(size: 18, weight: .semibold))
                    Text("FROM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // 飞机图标和进度
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "airplane")
                            .rotationEffect(.degrees(-45))
                        Text(phaseText)
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                    
                    // 进度条
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * viewModel.flightProgress, height: 4)
                        }
                    }
                    .frame(width: 120, height: 4)
                    
                    Text("\(Int(viewModel.flightProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // 目的地
                VStack(alignment: .trailing, spacing: 4) {
                    Text(viewModel.selectedLandmark?.code ?? "???")
                        .font(.system(size: 18, weight: .semibold))
                    Text("TO")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 10)
            )
            .padding(.horizontal, 20)
        }
    }
    
    private var phaseText: String {
        switch flightPhase {
        case .taxi: return "滑行中"
        case .takeoff: return "起飞中"
        case .cruise: return "巡航中"
        case .descent: return "下降中"
        case .landing: return "着陆中"
        }
    }
}

// MARK: - 飞行控制面板
struct FlightControlPanel: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @Binding var flightPhase: ImmersiveFlightView.FlightPhase
    @Binding var showAirplaneWindow: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // 打开舷窗按钮（扁胶囊样式）
            Button {
                showAirplaneWindow = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "airplane.window")
                        .font(.system(size: 14))
                    Text("打开舷窗")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            
            // 高度和速度
            HStack(spacing: 40) {
                FlightMetricView(
                    icon: "arrow.up.forward",
                    title: "海拔",
                    value: String(format: "%.0f", 10000 + viewModel.flightProgress * 0),
                    unit: "m"
                )
                
                FlightMetricView(
                    icon: "speedometer",
                    title: "速度",
                    value: String(format: "%.0f", 800 + Double.random(in: -20...20)),
                    unit: "km/h"
                )
                
                FlightMetricView(
                    icon: "thermometer",
                    title: "舱外",
                    value: String(format: "%.0f", -50 + viewModel.flightProgress * 100),
                    unit: "°C"
                )
            }
            
            // 时间信息
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text("预计到达时间: \(calculateETA())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 10)
        )
        .padding(.horizontal, 20)
    }
    
    private func calculateETA() -> String {
        let remainingMinutes = Int((1 - viewModel.flightProgress) * 25)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let arrivalTime = Date().addingTimeInterval(TimeInterval(remainingMinutes * 60))
        return formatter.string(from: arrivalTime)
    }
}

// MARK: - 飞行指标视图
struct FlightMetricView: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 机场标注数据
struct AirportAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let name: String
}

// MARK: - 机场地图视图（起飞阶段）
struct AirportMapView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    let flightPhase: ImmersiveFlightView.FlightPhase
    @State private var planePosition: CGFloat = 0
    @State private var mapOffset: CGFloat = 0

    // 模拟机场位置（扬州泰州国际机场附近）
    private let airportCoordinate = CLLocationCoordinate2D(latitude: 32.5617, longitude: 119.7156)
    private let runwayHeading: Double = 180 // 跑道朝向（正南）

    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 32.5617, longitude: 119.7156),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )

    var body: some View {
        ZStack {
            // 地图背景 - 使用兼容的初始化方式
            Map(coordinateRegion: $mapRegion,
                annotationItems: [AirportAnnotation(coordinate: airportCoordinate, name: "扬州泰州国际机场")]) { item in
                MapMarker(coordinate: item.coordinate, tint: .blue)
            }
            .mapStyle(.standard)
            .disabled(true) // 禁用地图交互

            // 遮罩层 - 上下渐变淡出
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.3), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)

                Spacer()

                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 150)
            }
            .ignoresSafeArea()

            // 中央垂直线（飞行路径）
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1)
                .ignoresSafeArea()

            // 飞机图标
            Image(systemName: "airplane")
                .font(.system(size: 32))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4)
                .rotationEffect(.degrees(flightPhase == .takeoff ? 0 : -90))
                .offset(y: planePosition)
                .animation(.easeInOut(duration: 2), value: planePosition)

            // 航站楼标记
            VStack(spacing: 4) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)

                Text("T2航站楼")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
            }
            .offset(x: -80, y: 100)

            // 右侧控制按钮组
            VStack(spacing: 16) {
                // 定位按钮
                CircleButton(icon: "location.fill", isActive: true)

                // 地图类型按钮
                CircleButton(icon: "map.fill", isActive: false)

                // 3D视图按钮
                CircleButton(icon: "cube.fill", isActive: false)
            }
            .offset(x: 140, y: -80)

            // 左侧信息按钮组
            VStack(spacing: 16) {
                // 暂停按钮
                CircleButton(icon: "pause.fill", isActive: false)

                // 信号按钮
                CircleButton(icon: "antenna.radiowaves.left.and.right", isActive: false)
            }
            .offset(x: -140, y: -120)

            // 底部信息面板
            VStack {
                Spacer()

                HStack(spacing: 40) {
                    // 剩余飞行时间
                    VStack(alignment: .leading, spacing: 4) {
                        Text("剩余飞行时间")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        Text("32 min")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    // 剩余飞行距离
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("剩余飞行距离")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        Text("215 km")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 120)
            }
        }
        .onAppear {
            // 飞机位置动画
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                planePosition = flightPhase == .takeoff ? -50 : 0
            }
        }
    }
}

// MARK: - 圆形按钮
struct CircleButton: View {
    let icon: String
    let isActive: Bool

    var body: some View {
        Button(action: {}) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isActive ? .white : .primary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isActive ? Color.black : Color.white)
                )
                .shadow(color: .black.opacity(0.2), radius: 8)
        }
    }
}

// MARK: - 叙事覆盖层
struct NarrativeOverlay: View {
    let text: String
    @State private var opacity: Double = 0

    var body: some View {
        VStack {
            Spacer()

            Text(text)
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.6))
                        .blur(radius: 20)
                )
                .padding(.bottom, 200)
                .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5)) {
                opacity = 1
            }

            // 4秒后淡出
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    opacity = 0
                }
            }
        }
    }
}

// MARK: - 舷窗预览包装器
struct AirplaneWindowPreview: View {
    @State private var showWindow = false

    var body: some View {
        ZStack {
            // 背景
            Color.gray.ignoresSafeArea()

            // 打开舷窗按钮
            Button {
                showWindow = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "airplane.window")
                        .font(.system(size: 24))
                    Text("打开舷窗")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(30)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            }
        }
        .sheet(isPresented: $showWindow) {
            AirplaneWindowView(
                flightPhase: .cruise,
                progress: 0.5,
                destination: Landmark(
                    name: "撒哈拉·翡翠绿洲",
                    subtitle: "沙海蜃楼茶会",
                    type: .oasis,
                    coordinate: CLLocationCoordinate2D(latitude: 23.0, longitude: 12.0),
                    description: "在金色沙丘间，品一杯薄荷茶的清凉",
                    teaPartyTheme: "沙漠绿洲茶会",
                    imageName: "sahara_oasis",
                    badgeName: "沙漠行者",
                    badgeDescription: "在撒哈拉沙漠完成茶会",
                    requiredLevel: 1
                )
            )
            .presentationDetents([.fraction(0.9)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(40)
        }
    }
}

// MARK: - Xcode 预览
#Preview("沉浸式飞行") {
    ImmersiveFlightView(viewModel: BigWorldViewModel())
}

#Preview("舷窗视图") {
    AirplaneWindowPreview()
}
