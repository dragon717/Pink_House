//
//  FlightExperienceViews.swift
//  ItemManager
//
//  大世界 - 飞行体验视图
//

import SwiftUI

// MARK: - 飞行准备视图
struct FlightPreparationView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let safeAreaTop = geometry.safeAreaInsets.top
                let safeAreaBottom = geometry.safeAreaInsets.bottom
                let navBarOffset = safeAreaTop + 60
                let tabBarOffset = safeAreaBottom + 90
                
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        Spacer().frame(height: navBarOffset)
                        
                        if let landmark = viewModel.selectedLandmark {
                            // 目的地预览
                            VStack(spacing: 20) {
                                ZStack {
                                    Circle()
                                        .fill(landmark.type.themeColor.opacity(0.2))
                                        .frame(width: 150, height: 150)
                                    
                                    Image(systemName: landmark.type.icon)
                                        .font(.system(size: 80))
                                        .foregroundStyle(landmark.type.themeColor)
                                }
                                
                                VStack(spacing: 8) {
                                    Text("即将前往")
                                        .font(.subheadline)
                                        .foregroundStyle(.gray)
                                    
                                    Text(landmark.name)
                                        .font(.system(size: 28, weight: .bold, design: .serif))
                                        .foregroundStyle(.white)
                                    
                                    Text(landmark.subtitle)
                                        .font(.title3)
                                        .foregroundStyle(landmark.type.themeColor)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // 隐私设置
                        VStack(spacing: 16) {
                            Toggle(isOn: $viewModel.isDepartureHidden) {
                                HStack {
                                    Image(systemName: viewModel.isDepartureHidden ? "eye.slash" : "eye")
                                        .foregroundStyle(.gray)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("隐藏出发地")
                                            .font(.subheadline)
                                            .foregroundStyle(.white)
                                        Text("分享时出发地将显示为???")
                                            .font(.caption)
                                            .foregroundStyle(.gray)
                                    }
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 1.0, green: 0.41, blue: 0.71)))
                            .padding(.horizontal, 30)
                            
                            // 开始登机按钮
                            Button {
                                viewModel.startBoarding()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "airplane")
                                    Text("开始登机")
                                }
                                .font(.system(size: 18, weight: .semibold))
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
                            .padding(.horizontal, 30)
                        }
                        
                        Spacer().frame(height: tabBarOffset)
                    }
                }
            }
            .navigationTitle("飞行准备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.41, blue: 0.71))
                }
            }
        }
    }
}

// MARK: - 登机视图
struct BoardingView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @State private var pulseAnimation = false
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let safeAreaTop = geometry.safeAreaInsets.top
                let safeAreaBottom = geometry.safeAreaInsets.bottom
                let navBarOffset = safeAreaTop + 60
                let tabBarOffset = safeAreaBottom + 90
                
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        Spacer().frame(height: navBarOffset)
                        
                        // 登机牌动画
                        ZStack {
                            // 背景光晕
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.3),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 50,
                                        endRadius: 150
                                    )
                                )
                                .frame(width: 300, height: 300)
                                .scaleEffect(pulseAnimation ? 1.2 : 0.8)
                                .opacity(pulseAnimation ? 0.5 : 1)
                                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
                            
                            // 登机牌
                            BoardingPassCard(viewModel: viewModel)
                                .rotation3DEffect(
                                    .degrees(pulseAnimation ? 5 : -5),
                                    axis: (x: 0, y: 1, z: 0)
                                )
                                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulseAnimation)
                        }
                        .onAppear {
                            pulseAnimation = true
                        }
                        
                        // 登机信息
                        VStack(spacing: 12) {
                            Text("正在登机...")
                                .font(.title2)
                                .foregroundStyle(.white)
                            
                            if case .boarding(let seatNumber) = viewModel.flightStatus {
                                Text("座位号: \(seatNumber)")
                                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.4)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                            
                            Text(viewModel.currentNarrative)
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        
                        Spacer()
                        
                        // 进度指示
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(Color(red: 1.0, green: 0.84, blue: 0.0))
                        
                        Spacer().frame(height: tabBarOffset)
                    }
                }
            }
            .navigationTitle("正在登机")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 登机牌卡片
struct BoardingPassCard: View {
    @ObservedObject var viewModel: BigWorldViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            HStack {
                Image(systemName: "airplane")
                    .font(.title2)
                    .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                
                Text("LOLITA AIR")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text("BOARDING PASS")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.1))
            
            // 航线信息
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.isDepartureHidden ? "???" : (viewModel.currentLocation.prefix(3).uppercased()))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(viewModel.isDepartureHidden ? "神秘出发地" : viewModel.currentLocation)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                
                Spacer()
                
                Image(systemName: "airplane")
                    .font(.title2)
                    .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                    .rotationEffect(.degrees(90))
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if let landmark = viewModel.selectedLandmark {
                        Text(landmark.name.prefix(3).uppercased())
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundStyle(landmark.type.themeColor)
                        Text(landmark.name)
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
            }
            .padding(16)
            
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 16)
            
            // 航班信息
            HStack(spacing: 30) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FLIGHT")
                        .font(.system(size: 8))
                        .foregroundStyle(.gray)
                    Text("LO-\(Int.random(in: 100...999))")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("DATE")
                        .font(.system(size: 8))
                        .foregroundStyle(.gray)
                    Text(Date(), style: .date)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                if case .boarding(let seatNumber) = viewModel.flightStatus {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SEAT")
                            .font(.system(size: 8))
                            .foregroundStyle(.gray)
                        Text(seatNumber)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                    }
                }
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.5), Color(red: 1.0, green: 0.6, blue: 0.4).opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .frame(width: 320)
    }
}

// MARK: - 飞行体验视图
struct FlightExperienceView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @State private var cloudOffset: CGFloat = 0
    @State private var planeBounce: CGFloat = 0
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let safeAreaTop = geometry.safeAreaInsets.top
                let safeAreaBottom = geometry.safeAreaInsets.bottom
                let navBarOffset = safeAreaTop + 60
                let tabBarOffset = safeAreaBottom + 90
                
                ZStack {
                    // 天空背景
                    LinearGradient(
                        colors: [
                            Color(red: 0.1, green: 0.15, blue: 0.3),
                            Color(red: 0.3, green: 0.4, blue: 0.7),
                            Color(red: 0.6, green: 0.7, blue: 0.9)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    
                    // 云朵层
                    CloudsView(offset: cloudOffset)
                    
                    // 主内容
                    VStack(spacing: 0) {
                        Spacer().frame(height: navBarOffset)
                        
                        // 飞机舷窗效果
                        ZStack {
                            // 舷窗外框
                            RoundedRectangle(cornerRadius: 80)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.9, green: 0.9, blue: 0.95),
                                            Color(red: 0.7, green: 0.75, blue: 0.85)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 280, height: 380)
                                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                            
                            // 舷窗玻璃
                            RoundedRectangle(cornerRadius: 70)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.4, green: 0.6, blue: 0.9).opacity(0.8),
                                            Color(red: 0.6, green: 0.8, blue: 1.0).opacity(0.6)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 260, height: 360)
                                .overlay(
                                    // 玻璃反光
                                    RoundedRectangle(cornerRadius: 70)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.4),
                                                    Color.white.opacity(0)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .center
                                            )
                                        )
                                )
                            
                            // 飞机图标
                            Image(systemName: "airplane")
                                .font(.system(size: 60))
                                .foregroundStyle(.white.opacity(0.8))
                                .rotationEffect(.degrees(45))
                                .offset(y: planeBounce)
                        }
                        
                        Spacer()
                        
                        // 底部信息面板
                        VStack(spacing: 20) {
                            // 进度条
                            VStack(spacing: 8) {
                                HStack {
                                    Text("飞行中")
                                        .font(.caption)
                                        .foregroundStyle(.gray)
                                    
                                    Spacer()
                                    
                                    Text("\(Int(viewModel.flightProgress * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                                }
                                
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.white.opacity(0.1))
                                            .frame(height: 8)
                                        
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.4)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: geo.size.width * viewModel.flightProgress, height: 8)
                                    }
                                }
                                .frame(height: 8)
                            }
                            
                            // 叙事文字
                            Text(viewModel.currentNarrative)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .frame(height: 40)
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.black.opacity(0.5))
                                .background(.ultraThinMaterial)
                        )
                        .padding(.horizontal, 20)
                        
                        Spacer().frame(height: tabBarOffset)
                    }
                }
            }
            .navigationTitle("飞行体验")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // 云朵动画
                withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                    cloudOffset = -200
                }
                
                // 飞机颠簸动画
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    planeBounce = 10
                }
            }
        }
    }
}

// MARK: - 云朵视图
struct CloudsView: View {
    let offset: CGFloat
    
    var body: some View {
        ZStack {
            // 远处云朵
            ForEach(0..<5) { i in
                CloudShape()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 100 + CGFloat(i * 20), height: 60)
                    .offset(
                        x: CGFloat(i * 80) + offset,
                        y: CGFloat.random(in: -200...(-100))
                    )
            }
            
            // 近处云朵
            ForEach(0..<3) { i in
                CloudShape()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 150 + CGFloat(i * 30), height: 80)
                    .offset(
                        x: CGFloat(i * 120) + offset * 1.5,
                        y: CGFloat.random(in: 100...300)
                    )
            }
        }
    }
}

// MARK: - 云朵形状
struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        
        path.move(to: CGPoint(x: width * 0.2, y: height * 0.5))
        path.addCurve(
            to: CGPoint(x: width * 0.8, y: height * 0.5),
            control1: CGPoint(x: width * 0.3, y: height * 0.1),
            control2: CGPoint(x: width * 0.7, y: height * 0.1)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.2, y: height * 0.5),
            control1: CGPoint(x: width * 0.9, y: height * 0.9),
            control2: CGPoint(x: width * 0.1, y: height * 0.9)
        )
        
        return path
    }
}

// MARK: - 到达视图
struct ArrivalView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @State private var showContent = false
    @State private var scale: CGFloat = 0.8
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let safeAreaTop = geometry.safeAreaInsets.top
                let safeAreaBottom = geometry.safeAreaInsets.bottom
                let navBarOffset = safeAreaTop + 60
                let tabBarOffset = safeAreaBottom + 90
                
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        Spacer().frame(height: navBarOffset)
                        
                        if let landmark = viewModel.selectedLandmark {
                            // 到达动画
                            ZStack {
                                // 光环
                                Circle()
                                    .fill(landmark.type.themeColor.opacity(0.2))
                                    .frame(width: 250, height: 250)
                                    .scaleEffect(showContent ? 1.2 : 0.8)
                                
                                Circle()
                                    .fill(landmark.type.themeColor.opacity(0.1))
                                    .frame(width: 350, height: 350)
                                    .scaleEffect(showContent ? 1.0 : 0.6)
                                
                                // 地标图标
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                        .frame(width: 180, height: 180)
                                    
                                    Image(systemName: landmark.type.icon)
                                        .font(.system(size: 100))
                                        .foregroundStyle(landmark.type.themeColor)
                                }
                                .scaleEffect(scale)
                            }
                            
                            // 到达信息
                            VStack(spacing: 16) {
                                Text("已抵达")
                                    .font(.title3)
                                    .foregroundStyle(.gray)
                                
                                Text(landmark.name)
                                    .font(.system(size: 32, weight: .bold, design: .serif))
                                    .foregroundStyle(.white)
                                
                                Text(landmark.subtitle)
                                    .font(.title3)
                                    .foregroundStyle(landmark.type.themeColor)
                                
                                Text(viewModel.currentNarrative)
                                    .font(.subheadline)
                                    .foregroundStyle(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 20)
                        }
                        
                        Spacer()
                        
                        // 打卡按钮
                        Button {
                            viewModel.checkIn()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("茶会打卡")
                            }
                            .font(.system(size: 18, weight: .semibold))
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
                        .padding(.horizontal, 30)
                        .opacity(showContent ? 1 : 0)
                        
                        Spacer().frame(height: tabBarOffset)
                    }
                }
            }
            .navigationTitle("抵达目的地")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    showContent = true
                }
                
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                    scale = 1.0
                }
            }
        }
    }
}

// MARK: - 打卡完成视图
struct CheckInCompleteView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @State private var showShareCard = false
    @State private var showBadge = false
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let safeAreaTop = geometry.safeAreaInsets.top
                let safeAreaBottom = geometry.safeAreaInsets.bottom
                let navBarOffset = safeAreaTop + 60
                let tabBarOffset = safeAreaBottom + 90
                
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        Spacer().frame(height: navBarOffset)
                        
                        if case .checkedIn(let record) = viewModel.flightStatus {
                            // 徽章获得动画
                            if showBadge {
                                BadgeEarnedView(badge: record.badgeEarned, landmark: record.landmark)
                                    .transition(.scale.combined(with: .opacity))
                            }
                            
                            Spacer()
                            
                            // 操作按钮
                            VStack(spacing: 16) {
                                // 分享按钮
                                Button {
                                    showShareCard = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("分享登机牌")
                                    }
                                    .font(.system(size: 18, weight: .semibold))
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
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 25)
                                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.horizontal, 30)
                            .sheet(isPresented: $showShareCard) {
                                ShareCardView(boardingPass: viewModel.generateBoardingPass(for: record))
                            }
                        }
                        
                        Spacer().frame(height: tabBarOffset)
                    }
                }
            }
            .navigationTitle("打卡完成")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                        showBadge = true
                    }
                }
            }
        }
    }
}

// MARK: - 徽章获得视图
struct BadgeEarnedView: View {
    let badge: TeaPartyBadge
    let landmark: Landmark
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 24) {
            // 徽章图标
            ZStack {
                // 光晕
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                landmark.type.themeColor.opacity(0.4),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                
                // 徽章
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.84, blue: 0.0),
                                    Color(red: 1.0, green: 0.6, blue: 0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                    
                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 3)
                        .frame(width: 110, height: 110)
                    
                    Image(systemName: "medal.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.white)
                }
                .rotationEffect(.degrees(rotation))
                .scaleEffect(scale)
            }
            
            // 文字
            VStack(spacing: 8) {
                Text("获得徽章")
                    .font(.title3)
                    .foregroundStyle(.gray)
                
                Text(badge.name)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.4)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(badge.description)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                scale = 1.0
            }
            
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                rotation = 10
            }
        }
    }
}

// MARK: - 分享卡片视图
struct ShareCardView: View {
    let boardingPass: BoardingPass
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 30) {
                    Spacer()
                    
                    // 分享卡片
                    ShareableBoardingPassCard(boardingPass: boardingPass)
                    
                    Spacer()
                    
                    // 分享按钮
                    Button {
                        shareBoardingPass()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("分享")
                        }
                        .font(.system(size: 18, weight: .semibold))
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
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("分享登机牌")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                }
            }
        }
    }
    
    private func shareBoardingPass() {
        // 实现分享功能
        let renderer = ImageRenderer(content: ShareableBoardingPassCard(boardingPass: boardingPass))
        renderer.scale = UIScreen.main.scale
        
        if let image = renderer.uiImage {
            let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        }
    }
}

// MARK: - 可分享的登机牌卡片
struct ShareableBoardingPassCard: View {
    let boardingPass: BoardingPass
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            HStack {
                Image(systemName: "airplane")
                    .font(.title2)
                    .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                
                Text("LOLITA AIR")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text("BOARDING PASS")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.1))
            
            // 航线信息
            HStack(spacing: 30) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(boardingPass.from.prefix(3).uppercased())
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(boardingPass.from)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                
                Spacer()
                
                Image(systemName: "airplane")
                    .font(.title2)
                    .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                    .rotationEffect(.degrees(90))
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 6) {
                    Text(boardingPass.to.prefix(3).uppercased())
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                    Text(boardingPass.to)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
            .padding(20)
            
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 20)
            
            // 航班详情
            HStack(spacing: 40) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("FLIGHT")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                    Text(boardingPass.formattedFlightNumber)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("DATE")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                    Text(boardingPass.flightDate, style: .date)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("SEAT")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                    Text(boardingPass.seatNumber)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                }
            }
            .padding(20)
            
            // 印章
            HStack {
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(Color(red: 1.0, green: 0.41, blue: 0.71).opacity(0.5), lineWidth: 2)
                        .frame(width: 80, height: 80)
                    
                    Text("已打卡")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.41, blue: 0.71))
                        .rotationEffect(.degrees(-15))
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.5), Color(red: 1.0, green: 0.6, blue: 0.4).opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
        )
        .padding(.horizontal, 20)
    }
}

#Preview {
    BigWorldView()
}
