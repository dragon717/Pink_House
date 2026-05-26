//
//  BigWorldView.swift
//  ItemManager
//
//  世界书 - 主入口视图（升级版）
//

import SwiftUI
import MapKit
import UIKit

struct BigWorldView: View {
    @StateObject private var viewModel = BigWorldViewModel()
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: BigWorldTab = .explore
    
    enum BigWorldTab: String, CaseIterable, Identifiable {
        case explore = "世界书"
        case dream = "后花园"
        
        var id: String { rawValue }

        var localizedTitle: String {
            rawValue.appLocalized
        }
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
                // 顶部导航栏 - 世界书/梦幻页签（参考马上来财的分段选择器）
                if case .idle = viewModel.flightStatus {
                    ToolbarItem(placement: .principal) {
                        Picker("功能".appLocalized, selection: $selectedTab) {
                            ForEach(BigWorldTab.allCases) { tab in
                                Text(tab.localizedTitle).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                }

                // 关闭按钮 - 仅在非世界书页面显示
                if case .idle = viewModel.flightStatus, selectedTab != .explore {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            viewModel.resetFlight()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(themeManager.primaryTextColor)
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
                                .foregroundStyle(themeManager.primaryTextColor)
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
    @Environment(ThemeManager.self) private var themeManager
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundStyle(themeManager.accentTextColor.opacity(0.5))
                
                Text("梦幻世界".appLocalized)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(themeManager.primaryTextColor)
                
                Text("即将开启，敬请期待...".appLocalized)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.secondaryTextColor)
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
                        Text("已到达目的地".appLocalized)
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.8))
                        
                        if let landmark = viewModel.selectedLandmark {
                            Text(landmark.localizedName)
                                .font(.system(size: 36, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                            
                            Text(landmark.localizedSubtitle)
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
                            Text("立即打卡".appLocalized)
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
            Text(label.appLocalized)
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
    @State private var isGeneratingShareImage = false
    
    var body: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            // 导航栏高度约 44pt，加上间距
            let navBarOffset = safeAreaTop + 70
            // TabBar 高度约 49pt，加上间距
            let tabBarOffset = safeAreaBottom + 90
            
            ZStack {
                // 背景
                Color.black.ignoresSafeArea()
                
                // 彩带效果
                if showConfetti {
                    ConfettiView()
                }
                
                VStack(spacing: 0) {
                    // 顶部安全区域偏移
                    Spacer().frame(height: navBarOffset)
                    
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
                            Text("欢迎来到%@".appLocalized(landmark.localizedName))
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
                                
                                Text(badge.iconName)
                                    .font(.system(size: 60))
                            }
                            .scaleEffect(badgeScale)
                            .rotation3DEffect(.degrees(rotation * 0.5), axis: (x: 0, y: 1, z: 0))
                        }
                        
                        Text("获得徽章：%@".appLocalized(badge.localizedName))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.top, 20)
                    }
                    
                    Spacer()
                    
                    // 按钮组
                    VStack(spacing: 16) {
                        // 分享按钮
                        Button {
                            Task {
                                await generateShareImage()
                            }
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
                        .disabled(isGeneratingShareImage)
                        
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
                        .disabled(isGeneratingShareImage)
                    }
                    .padding(.horizontal, 40)
                    
                    // 底部安全区域偏移
                    Spacer().frame(height: tabBarOffset)
                }
                
                // 猫爪加载遮罩（统一使用 ShareCardManager 的加载动画）
                if isGeneratingShareImage {
                    ShareLoadingOverlay(message: "正在生成分享卡片...")
                }
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
    
    @MainActor
    private func generateShareImage() async {
        guard let badge = viewModel.unlockedBadges.last,
              let landmark = viewModel.selectedLandmark else { 
            print("DEBUG: Missing badge or landmark")
            return 
        }
        
        // 显示加载动画
        isGeneratingShareImage = true
        
        // 记录开始时间
        let startTime = Date()
        
        // 给 UI 一些时间来显示加载动画
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3秒
        
        print("DEBUG: Generating share image for badge: \(badge.name), landmark: \(landmark.name)")
        
        // 在主线程生成图片（UIGraphicsImageRenderer 必须在主线程）
        let image = await MainActor.run {
            let shareCard = CheckInShareCard(badge: badge, landmark: landmark)
            
            // 使用 UIHostingController + UIGraphicsImageRenderer 渲染
            let controller = UIHostingController(rootView: shareCard)
            let view = controller.view
            
            let size = CGSize(width: 390, height: 844)
            view?.bounds = CGRect(origin: .zero, size: size)
            view?.backgroundColor = .clear
            
            // 强制布局
            view?.layoutIfNeeded()
            
            let format = UIGraphicsImageRendererFormat()
            format.scale = UIScreen.main.scale
            format.opaque = false
            
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            let image = renderer.image { _ in
                view?.drawHierarchy(in: view?.bounds ?? CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            }
            
            controller.removeFromParent()
            
            return image
        }
        
        // 计算已经过的时间
        let elapsedTime = Date().timeIntervalSince(startTime)
        let minimumDisplayTime: TimeInterval = 2.0 // 最少显示 2 秒
        
        // 如果生成时间少于 2 秒，等待剩余时间
        if elapsedTime < minimumDisplayTime {
            let remainingTime = minimumDisplayTime - elapsedTime
            try? await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
        }
        
        // 隐藏加载动画
        isGeneratingShareImage = false
        
        print("DEBUG: Generated image size: \(image.size)")
        
        // 直接弹出系统分享界面
        print("DEBUG: About to call presentShareSheet")
        presentShareSheet(with: image)
        print("DEBUG: After calling presentShareSheet")
    }
    
    @MainActor
    private func presentShareSheet(with image: UIImage) {
        print("DEBUG: Presenting share sheet...")
        
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        
        // 获取当前窗口场景来呈现分享表
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            print("DEBUG: No window scene found")
            return
        }
        
        guard let rootVC = windowScene.windows.first?.rootViewController else {
            print("DEBUG: No root view controller found")
            return
        }
        
        // 找到最顶部的视图控制器
        var topVC = rootVC
        while let presentedVC = topVC.presentedViewController {
            topVC = presentedVC
        }
        
        print("DEBUG: Top view controller: \(type(of: topVC))")
        
        // iPad 需要设置弹出位置
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        // 延迟一点再呈现，确保视图层级稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            print("DEBUG: Presenting activity view controller")
            topVC.present(activityVC, animated: true) {
                print("DEBUG: Activity view controller presented")
            }
        }
    }
}

// MARK: - 打卡分享卡片
struct CheckInShareCard: View {
    let badge: TeaPartyBadge
    let landmark: Landmark
    
    var body: some View {
        ZStack {
            // 主题背景渐变
            LinearGradient(
                colors: backgroundColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // 简单的装饰圆圈
            decorationCircles
            
            VStack(spacing: 30) {
                Spacer()
                
                // 打卡成功标题
                VStack(spacing: 8) {
                    Text("打卡成功！")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("欢迎来到%@".appLocalized(landmark.localizedName))
                        .font(.title3)
                        .foregroundStyle(.white)
                    
                    Text("参加了\(landmark.teaPartyTheme)")
                        .font(.subheadline)
                        .foregroundStyle(landmark.type.themeColor)
                }
                
                // 徽章展示
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
                        .frame(width: 280, height: 280)
                    
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
                            .frame(width: 140, height: 140)
                            .shadow(color: badge.themeColor.opacity(0.6), radius: 20)
                        
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        badge.themeColor,
                                        badge.themeColor.opacity(0.5),
                                        badge.themeColor
                                    ],
                                    center: .center,
                                    angle: .degrees(0)
                                ),
                                lineWidth: 3
                            )
                            .frame(width: 130, height: 130)
                        
                        // 徽章图标 - 使用 Text 显示 emoji
                        Text(badge.iconName)
                            .font(.system(size: 56))
                    }
                }
                
                // 徽章名称
                Text("获得徽章：%@".appLocalized(badge.localizedName))
                    .font(.headline)
                    .foregroundStyle(.white)
                
                Spacer()
                
                // App Logo
                HStack(spacing: 8) {
                    Image(systemName: "airplane")
                        .font(.title3)
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                    
                    Text("LOLITA AIR")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 30)
            }
            .padding()
        }
        .frame(width: 390, height: 844)
    }
    
    // 简化的装饰圆圈
    private var decorationCircles: some View {
        ZStack {
            Circle()
                .fill(badge.themeColor.opacity(0.1))
                .frame(width: 200, height: 200)
                .offset(x: -100, y: -200)
            
            Circle()
                .fill(badge.themeColor.opacity(0.08))
                .frame(width: 150, height: 150)
                .offset(x: 120, y: 150)
            
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 100, height: 100)
                .offset(x: 80, y: -300)
        }
    }
    
    private var backgroundColors: [Color] {
        switch landmark.type {
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
