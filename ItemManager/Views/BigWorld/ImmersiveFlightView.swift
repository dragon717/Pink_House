//
//  ImmersiveFlightView.swift
//  ItemManager
//
//  大世界 - 沉浸式飞行体验
//

import SwiftUI

// MARK: - 沉浸式飞行主视图
struct ImmersiveFlightView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @State private var flightPhase: FlightPhase = .taxi
    @State private var planeOffset: CGFloat = 0
    @State private var cloudOffset: CGFloat = 0
    @State private var turbulence: Double = 0
    @State private var showNarrative = true
    
    enum FlightPhase {
        case taxi      // 滑行
        case takeoff   // 起飞
        case cruise    // 巡航
        case descent   // 下降
        case landing   // 着陆
    }
    
    var body: some View {
        ZStack {
            // 舷窗视图
            AirplaneWindowView(
                flightPhase: flightPhase,
                progress: viewModel.flightProgress,
                destination: viewModel.selectedLandmark
            )
            
            // 飞机震动效果
            VStack {
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: CGFloat.random(in: -turbulence...turbulence),
                    y: CGFloat.random(in: -turbulence...turbulence))
            
            // UI 覆盖层
            VStack {
                // 顶部状态栏
                FlightStatusBar(viewModel: viewModel, flightPhase: flightPhase)
                    .padding(.top, 60)
                
                Spacer()
                
                // 底部控制面板
                FlightControlPanel(viewModel: viewModel, flightPhase: $flightPhase)
                    .padding(.bottom, 40)
            }
            
            // 叙事文字
            if showNarrative, !viewModel.currentNarrative.isEmpty {
                NarrativeOverlay(text: viewModel.currentNarrative)
                    .transition(.opacity)
            }
        }
        .onAppear {
            startFlightSimulation()
        }
        .onChange(of: viewModel.flightProgress) { progress in
            updateFlightPhase(progress)
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

// MARK: - 飞机舷窗视图
struct AirplaneWindowView: View {
    let flightPhase: ImmersiveFlightView.FlightPhase
    let progress: Double
    let destination: Landmark?
    
    @State private var sunPosition: CGFloat = 0
    @State private var cloudLayers: [CloudLayer] = []
    
    struct CloudLayer: Identifiable {
        let id = UUID()
        let offset: CGFloat
        let scale: CGFloat
        let opacity: Double
        let speed: Double
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 天空渐变背景
                SkyGradientView(phase: flightPhase, progress: progress)
                
                // 太阳/月亮
                CelestialBodyView(phase: flightPhase, progress: progress)
                    .offset(y: sunPosition)
                
                // 云层
                ForEach(cloudLayers) { cloud in
                    CloudView(scale: cloud.scale, opacity: cloud.opacity)
                        .offset(x: cloud.offset)
                        .animation(
                            .linear(duration: cloud.speed)
                            .repeatForever(autoreverses: false),
                            value: cloud.offset
                        )
                }
                
                // 地面景观（仅在低空显示）
                if flightPhase == .takeoff || flightPhase == .landing || progress < 0.1 || progress > 0.9 {
                    GroundView(destination: destination)
                        .offset(y: geo.size.height * 0.6)
                }
                
                // 舷窗边框
                WindowFrameView()
            }
        }
        .onAppear {
            // 初始化云层
            cloudLayers = (0..<5).map { i in
                CloudLayer(
                    offset: CGFloat(i) * 200 - 400,
                    scale: CGFloat.random(in: 0.5...1.5),
                    opacity: Double.random(in: 0.3...0.8),
                    speed: Double.random(in: 15...30)
                )
            }
        }
    }
}

// MARK: - 天空渐变
struct SkyGradientView: View {
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
    @State private var offset: CGFloat = 0
    
    var body: some View {
        Canvas { context, size in
            // 绘制云朵形状
            let cloudPath = createCloudPath(in: CGRect(origin: .zero, size: size))
            context.fill(cloudPath, with: .color(Color.white.opacity(opacity)))
        }
        .frame(width: 150 * scale, height: 80 * scale)
        .offset(x: offset)
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                offset = UIScreen.main.bounds.width + 200
            }
        }
    }
    
    private func createCloudPath(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        // 简化的云朵形状
        path.addEllipse(in: CGRect(x: 0, y: height * 0.3, width: width * 0.4, height: height * 0.5))
        path.addEllipse(in: CGRect(x: width * 0.2, y: 0, width: width * 0.5, height: height * 0.7))
        path.addEllipse(in: CGRect(x: width * 0.5, y: height * 0.2, width: width * 0.4, height: height * 0.5))
        path.addEllipse(in: CGRect(x: width * 0.3, y: height * 0.4, width: width * 0.5, height: height * 0.5))
        
        return path
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

// MARK: - 舷窗边框
struct WindowFrameView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 外框
                RoundedRectangle(cornerRadius: 150)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.3, green: 0.3, blue: 0.35),
                                Color(red: 0.5, green: 0.5, blue: 0.55),
                                Color(red: 0.3, green: 0.3, blue: 0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 20
                    )
                
                // 内阴影
                RoundedRectangle(cornerRadius: 140)
                    .stroke(Color.black.opacity(0.5), lineWidth: 8)
                    .padding(10)
                
                // 高光
                RoundedRectangle(cornerRadius: 150)
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .padding(8)
            }
            .frame(width: geo.size.width - 40, height: geo.size.height - 100)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
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
    
    var body: some View {
        VStack(spacing: 16) {
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

#Preview {
    ImmersiveFlightView(viewModel: BigWorldViewModel())
}
