//
//  BigWorldView.swift
//  ItemManager
//
//  大世界 - 主入口视图（升级版）
//

import SwiftUI
import MapKit

struct BigWorldView: View {
    @StateObject private var viewModel = BigWorldViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: BigWorldTab = .explore
    
    enum BigWorldTab: String, CaseIterable, Identifiable {
        case explore = "探索"
        case dream = "梦幻"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // App背景图片
                Image("SplashScreen")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                
                // 根据状态显示不同内容
                Group {
                    switch viewModel.flightStatus {
                    case .idle:
                        // 根据选择的页签显示不同内容（禁用滑动切换）
                        Group {
                            switch selectedTab {
                            case .explore:
                                // 3D地球 - 目的地选择
                                EnhancedGlobeView(viewModel: viewModel)
                            case .dream:
                                // 梦幻页面（预留）
                                DreamPlaceholderView()
                            }
                        }
                        
                    case .selecting:
                        // 飞行准备 - 检票登机体验
                        BoardingExperienceView(viewModel: viewModel)
                        
                    case .boarding:
                        // 登机中
                        BoardingExperienceView(viewModel: viewModel)
                        
                    case .flying:
                        // 沉浸式飞行体验
                        ImmersiveFlightView(viewModel: viewModel)
                        
                    case .arrived:
                        // 到达
                        EnhancedArrivalView(viewModel: viewModel)
                        
                    case .checkedIn:
                        // 打卡完成
                        EnhancedCheckInView(viewModel: viewModel)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                // 顶部导航栏 - 探索/梦幻页签（参考马上来财的分段选择器）
                if case .idle = viewModel.flightStatus {
                    ToolbarItem(placement: .principal) {
                        Picker("功能", selection: $selectedTab) {
                            ForEach(BigWorldTab.allCases) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                }

                // 关闭按钮 - 仅在非探索页面显示
                if case .idle = viewModel.flightStatus, selectedTab != .explore {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            viewModel.resetFlight()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.clear)
                        }
                    }
                } else if viewModel.flightStatus != .idle {
                    // 飞行状态下始终显示关闭按钮
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            viewModel.resetFlight()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.clear)
                        }
                    }
                }
            }
            // 顶部安全区域 - 确保内容不被导航栏覆盖
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: 0)
            }
            // 底部安全区域 - 确保内容不被 TabBar 覆盖
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 0)
            }
        }
    }
}

// MARK: - 梦幻页面占位
struct DreamPlaceholderView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.5))
                
                Text("梦幻世界")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                
                Text("即将开启，敬请期待...")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            }
        }
    }
}

// MARK: - 增强到达视图
struct EnhancedArrivalView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @State private var showContent = false
    @State private var planeOffset: CGFloat = -200
    
    var body: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            let navBarOffset = safeAreaTop + 60
            let tabBarOffset = safeAreaBottom + 90
            
            ZStack {
                // 背景
                if let landmark = viewModel.selectedLandmark {
                    LandmarkThemeBackground(type: landmark.type)
                }
                
                // 主内容
                VStack(spacing: 30) {
                    Spacer().frame(height: navBarOffset)
                    
                    // 飞机降落动画
                    Image(systemName: "airplane")
                        .font(.system(size: 80))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(45))
                        .offset(x: planeOffset)
                        .onAppear {
                            withAnimation(.easeOut(duration: 2)) {
                                planeOffset = 0
                            }
                        }
                    
                    // 到达信息
                    VStack(spacing: 16) {
                        Text("已到达目的地")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.8))
                        
                        if let landmark = viewModel.selectedLandmark {
                            Text(landmark.name)
                                .font(.system(size: 36, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                            
                            Text(landmark.subtitle)
                                .font(.title3)
                                .foregroundStyle(landmark.type.themeColor)
                        }
                        
                        // 天气信息（模拟）
                        HStack(spacing: 20) {
                            WeatherInfo(icon: "sun.max.fill", value: "24°C", label: "温度")
                            WeatherInfo(icon: "wind", value: "3级", label: "风速")
                            WeatherInfo(icon: "drop.fill", value: "45%", label: "湿度")
                        }
                        .padding(.top, 20)
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 30)
                    
                    Spacer()
                    
                    // 打卡按钮
                    Button {
                        viewModel.checkIn()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("立即打卡")
                        }
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(30)
                    }
                    .padding(.horizontal, 40)
                    .opacity(showContent ? 1 : 0)
                    
                    // 底部留出 TabBar 空间
                    Spacer().frame(height: tabBarOffset)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.spring()) {
                        showContent = true
                    }
                }
            }
        }
    }
}

// MARK: - 天气信息
struct WeatherInfo: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.yellow)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: 70)
    }
}

// MARK: - 地标主题背景
struct LandmarkThemeBackground: View {
    let type: LandmarkType
    
    var body: some View {
        LinearGradient(
            colors: backgroundColors,
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .overlay(
            // 装饰图案
            GeometryReader { geo in
                Canvas { context, size in
                    // 根据地标类型绘制不同的装饰
                    switch type {
                    case .glacier:
                        drawIceCrystals(context: context, size: size)
                    case .sakura:
                        drawPetals(context: context, size: size)
                    case .aurora:
                        drawAurora(context: context, size: size)
                    default:
                        break
                    }
                }
            }
        )
    }
    
    private var backgroundColors: [Color] {
        switch type {
        case .glacier:
            return [Color(red: 0.4, green: 0.7, blue: 0.9), Color(red: 0.2, green: 0.4, blue: 0.6)]
        case .canyon:
            return [Color(red: 0.9, green: 0.5, blue: 0.3), Color(red: 0.6, green: 0.3, blue: 0.2)]
        case .oasis:
            return [Color(red: 0.4, green: 0.8, blue: 0.6), Color(red: 0.2, green: 0.5, blue: 0.4)]
        case .prairie:
            return [Color(red: 0.6, green: 0.8, blue: 0.3), Color(red: 0.4, green: 0.6, blue: 0.2)]
        case .aurora:
            return [Color(red: 0.2, green: 0.4, blue: 0.5), Color(red: 0.1, green: 0.2, blue: 0.3)]
        case .castle:
            return [Color(red: 0.8, green: 0.6, blue: 0.7), Color(red: 0.5, green: 0.3, blue: 0.4)]
        case .sakura:
            return [Color(red: 0.95, green: 0.7, blue: 0.8), Color(red: 0.8, green: 0.5, blue: 0.6)]
        case .lavender:
            return [Color(red: 0.7, green: 0.5, blue: 0.9), Color(red: 0.5, green: 0.3, blue: 0.7)]
        }
    }
    
    private func drawIceCrystals(context: GraphicsContext, size: CGSize) {
        for _ in 0..<20 {
            let x = CGFloat.random(in: 0...size.width)
            let y = CGFloat.random(in: 0...size.height)
            let rect = CGRect(x: x, y: y, width: 4, height: 4)
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.3)))
        }
    }
    
    private func drawPetals(context: GraphicsContext, size: CGSize) {
        for _ in 0..<30 {
            let x = CGFloat.random(in: 0...size.width)
            let y = CGFloat.random(in: 0...size.height)
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addEllipse(in: CGRect(x: x, y: y, width: 8, height: 4))
            context.fill(path, with: .color(Color.pink.opacity(0.2)))
        }
    }
    
    private func drawAurora(context: GraphicsContext, size: CGSize) {
        for i in 0..<5 {
            var path = Path()
            let y = size.height * 0.3 + CGFloat(i) * 50
            path.move(to: CGPoint(x: 0, y: y))
            path.addCurve(
                to: CGPoint(x: size.width, y: y + 30),
                control1: CGPoint(x: size.width * 0.3, y: y - 50),
                control2: CGPoint(x: size.width * 0.7, y: y + 80)
            )
            path.addLine(to: CGPoint(x: size.width, y: y + 50))
            path.addCurve(
                to: CGPoint(x: 0, y: y + 20),
                control1: CGPoint(x: size.width * 0.7, y: y + 100),
                control2: CGPoint(x: size.width * 0.3, y: y - 30)
            )
            let colors: [Color] = [.green, .cyan, .purple, .pink, .blue]
            context.fill(path, with: .color(colors[i].opacity(0.1)))
        }
    }
}

// MARK: - 增强打卡视图
struct EnhancedCheckInView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @State private var showBadge = false
    @State private var badgeScale: CGFloat = 0
    @State private var showConfetti = false
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            // 背景
            Color.black.ignoresSafeArea()
            
            // 彩带效果
            if showConfetti {
                ConfettiView()
            }
            
            VStack(spacing: 30) {
                Spacer()
                
                // 打卡成功文字
                VStack(spacing: 12) {
                    Text("打卡成功！")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    if let landmark = viewModel.selectedLandmark {
                        Text("欢迎来到\(landmark.name)")
                            .font(.title3)
                            .foregroundStyle(.white)
                        
                        Text("参加了\(landmark.teaPartyTheme)")
                            .font(.subheadline)
                            .foregroundStyle(landmark.type.themeColor)
                    }
                }
                
                // 徽章展示
                if let badge = viewModel.unlockedBadges.last, showBadge {
                    ZStack {
                        // 光晕
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        badge.themeColor.opacity(0.5),
                                        badge.themeColor.opacity(0.2),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 50,
                                    endRadius: 150
                                )
                            )
                            .frame(width: 300, height: 300)
                        
                        // 徽章
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.2, green: 0.2, blue: 0.25),
                                            Color(red: 0.1, green: 0.1, blue: 0.15)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 150, height: 150)
                                .shadow(color: badge.themeColor.opacity(0.6), radius: 30)
                            
                            Circle()
                                .stroke(
                                    AngularGradient(
                                        colors: [
                                            badge.themeColor,
                                            badge.themeColor.opacity(0.5),
                                            badge.themeColor
                                        ],
                                        center: .center,
                                        angle: .degrees(rotation)
                                    ),
                                    lineWidth: 3
                                )
                                .frame(width: 140, height: 140)
                            
                            Image(systemName: badge.iconName)
                                .font(.system(size: 60))
                                .foregroundStyle(badge.themeColor)
                        }
                        .scaleEffect(badgeScale)
                        .rotation3DEffect(.degrees(rotation * 0.5), axis: (x: 0, y: 1, z: 0))
                    }
                    
                    Text("获得徽章：\(badge.name)")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.top, 20)
                }
                
                Spacer()
                
                // 按钮组
                VStack(spacing: 16) {
                    // 分享按钮
                    Button {
                        // 分享
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("分享打卡")
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(25)
                    }
                    
                    // 返回按钮
                    Button {
                        viewModel.resetFlight()
                    } label: {
                        Text("继续探索")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Capsule()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            // 动画序列
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showBadge = true
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    badgeScale = 1.0
                }
                showConfetti = true
                
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
    }
}

// MARK: - 彩带视图
struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    
    struct ConfettiParticle: Identifiable {
        let id = UUID()
        let x: CGFloat
        let color: Color
        let rotation: Double
        let delay: Double
    }
    
    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                for particle in particles {
                    var path = Path()
                    let rect = CGRect(x: particle.x, y: 0, width: 8, height: 12)
                    path.addRect(rect)
                    
                    context.translateBy(x: particle.x, y: size.height * 0.3)
                    context.rotate(by: .degrees(particle.rotation))
                    context.fill(path, with: .color(particle.color))
                }
            }
        }
        .onAppear {
            let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange, .pink]
            particles = (0..<50).map { _ in
                ConfettiParticle(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    color: colors.randomElement()!,
                    rotation: Double.random(in: 0...360),
                    delay: Double.random(in: 0...2)
                )
            }
        }
    }
}

#Preview {
    BigWorldView()
}
