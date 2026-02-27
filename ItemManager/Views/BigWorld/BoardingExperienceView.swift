//
//  BoardingExperienceView.swift
//  ItemManager
//
//  世界书 - 检票登机沉浸式体验
//

import SwiftUI

// MARK: - 登机体验主视图
struct BoardingExperienceView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @State private var boardingStage: BoardingStage = .privacyCheck
    @State private var selectedSeat: String = ""
    @State private var showScanner = false
    @State private var scanProgress: Double = 0
    @State private var boardingPassScale: CGFloat = 0.8
    @State private var boardingPassRotation: Double = -5
    @Environment(\.colorScheme) var colorScheme
    
    enum BoardingStage {
        case privacyCheck
        case seatSelection
        case boardingPass
        case scanner
        case complete
    }
    
    // 获取目的地主题色
    private var destinationThemeColor: Color {
        viewModel.selectedLandmark?.type.themeColor ?? Color(red: 0.2, green: 0.5, blue: 0.9)
    }
    
    // 根据目的地主题生成背景渐变
    private var themeBackground: some View {
        let baseColor = destinationThemeColor
        return Group {
            if colorScheme == .dark {
                // 暗夜模式背景
                LinearGradient(
                    colors: [
                        baseColor.opacity(0.3),
                        baseColor.opacity(0.15),
                        Color(red: 0.05, green: 0.05, blue: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                // 亮色模式背景
                LinearGradient(
                    colors: [
                        baseColor.opacity(0.2),
                        baseColor.opacity(0.1),
                        Color(red: 0.95, green: 0.95, blue: 0.97)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
    
    var body: some View {
        ZStack {
            // 目的地主题背景 - 铺满整个屏幕
            themeBackground
                .ignoresSafeArea()
            
            // 装饰性主题元素
            GeometryReader { geo in
                ZStack {
                    // 顶部装饰圆
                    Circle()
                        .fill(destinationThemeColor.opacity(colorScheme == .dark ? 0.2 : 0.25))
                        .frame(width: 400, height: 400)
                        .offset(x: -150, y: -150)
                        .blur(radius: 80)
                    
                    // 右侧装饰圆
                    Circle()
                        .fill(destinationThemeColor.opacity(colorScheme == .dark ? 0.15 : 0.2))
                        .frame(width: 300, height: 300)
                        .offset(x: geo.size.width - 100, y: geo.size.height * 0.3)
                        .blur(radius: 60)
                    
                    // 底部装饰圆
                    Circle()
                        .fill(destinationThemeColor.opacity(colorScheme == .dark ? 0.1 : 0.15))
                        .frame(width: 350, height: 350)
                        .offset(x: 100, y: geo.size.height - 100)
                        .blur(radius: 70)
                }
            }
            .ignoresSafeArea()
            
            // UI 覆盖层 - 使用 GeometryReader 精确定位
            GeometryReader { geometry in
                let safeAreaTop = geometry.safeAreaInsets.top
                let safeAreaBottom = geometry.safeAreaInsets.bottom
                // 导航栏高度约 44pt，加上间距
                let navBarOffset = safeAreaTop + 70
                // TabBar 高度约 49pt，加上间距
                let tabBarOffset = safeAreaBottom + 90
                
                // 进度指示器（在导航栏下方）
                VStack {
                    Spacer().frame(height: navBarOffset)
                    
                    BoardingProgressView(currentStage: boardingStage)
                        .frame(maxWidth: .infinity)
                    
                    Spacer()
                }
                .allowsHitTesting(false)
                
                // 主要内容区域（在进度指示器下方，TabBar 上方）
                VStack {
                    Spacer().frame(height: navBarOffset + 70)
                    
                    // 根据阶段显示不同内容
                    switch boardingStage {
                    case .privacyCheck:
                        PrivacyCheckView(viewModel: viewModel) {
                            withAnimation(.spring()) {
                                boardingStage = .seatSelection
                            }
                        }
                        
                    case .seatSelection:
                        SeatSelectionView(selectedSeat: $selectedSeat) {
                            viewModel.generateCurrentBoardingPass(seatNumber: selectedSeat)
                            withAnimation(.spring()) {
                                boardingStage = .boardingPass
                            }
                        } onBack: {
                            withAnimation(.spring()) {
                                boardingStage = .privacyCheck
                            }
                        }
                        
                    case .boardingPass:
                        BoardingPassView(viewModel: viewModel)
                            .scaleEffect(boardingPassScale)
                            .rotationEffect(.degrees(boardingPassRotation))
                            .onAppear {
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                    boardingPassScale = 1.0
                                    boardingPassRotation = 0
                                }
                                // 3秒后自动进入扫描
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    withAnimation {
                                        boardingStage = .scanner
                                    }
                                }
                            }
                        
                    case .scanner:
                        ScannerView(viewModel: viewModel, scanProgress: $scanProgress) {
                            withAnimation(.spring()) {
                                boardingStage = .complete
                            }
                        }
                        
                    case .complete:
                        BoardingCompleteView(viewModel: viewModel)
                    }
                    
                    Spacer().frame(height: tabBarOffset)
                }
            }
        }
    }
}

// MARK: - 机场背景
struct AirportBackgroundView: View {
    @State private var moveOffset: CGFloat = 0
    
    var body: some View {
        ZStack {
            // 渐变背景
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.95, blue: 0.97),
                    Color(red: 0.9, green: 0.9, blue: 0.95),
                    Color(red: 0.85, green: 0.87, blue: 0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // 动态光线
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(0..<5) { i in
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0),
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 2)
                            .offset(x: moveOffset + CGFloat(i) * geo.size.width / 5)
                    }
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    moveOffset = 100
                }
            }
            
            // 顶部装饰条
            VStack {
                HStack(spacing: 0) {
                    ForEach([Color.red, Color.orange, Color.yellow, Color.green, Color.blue, Color.purple], id: \.self) { color in
                        Rectangle()
                            .fill(color.opacity(0.6))
                            .frame(height: 4)
                    }
                }
                Spacer()
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 登机进度指示器
struct BoardingProgressView: View {
    let currentStage: BoardingExperienceView.BoardingStage
    
    private var stages: [(icon: String, title: String, stage: BoardingExperienceView.BoardingStage)] {
        [
            ("eye.slash", "隐私", .privacyCheck),
            ("square.grid.2x2", "选座", .seatSelection),
            ("ticket", "机票", .boardingPass),
            ("barcode.viewfinder", "检票", .scanner),
            ("airplane", "登机", .complete)
        ]
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 4) {
                    // 步骤圆圈
                    ZStack {
                        Circle()
                            .fill(stageColor(item.stage))
                            .frame(width: 32, height: 32)
                        
                        if isCompleted(item.stage) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: item.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(isActive(item.stage) ? .white : .gray)
                        }
                    }
                    
                    // 连接线
                    if index < stages.count - 1 {
                        Rectangle()
                            .fill(isCompleted(item.stage) ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 30, height: 2)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.9))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        )
    }
    
    private func stageColor(_ stage: BoardingExperienceView.BoardingStage) -> Color {
        if isCompleted(stage) {
            return .green
        } else if isActive(stage) {
            return Color(red: 0.2, green: 0.5, blue: 0.9)
        } else {
            return Color.gray.opacity(0.2)
        }
    }
    
    private func isActive(_ stage: BoardingExperienceView.BoardingStage) -> Bool {
        currentStage == stage
    }
    
    private func isCompleted(_ stage: BoardingExperienceView.BoardingStage) -> Bool {
        let stageOrder: [BoardingExperienceView.BoardingStage] = [.privacyCheck, .seatSelection, .boardingPass, .scanner, .complete]
        guard let currentIndex = stageOrder.firstIndex(of: currentStage),
              let stageIndex = stageOrder.firstIndex(of: stage) else {
            return false
        }
        return stageIndex < currentIndex
    }
}

// MARK: - 隐私检查视图
struct PrivacyCheckView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    let onContinue: () -> Void
    @State private var showDeparture = false
    @Environment(\.colorScheme) var colorScheme
    
    // 获取目的地主题色
    private var destinationThemeColor: Color {
        viewModel.selectedLandmark?.type.themeColor ?? Color(red: 0.2, green: 0.5, blue: 0.9)
    }
    
    // 根据目的地主题生成亮色模式背景渐变
    private var lightModeBackground: some View {
        let baseColor = destinationThemeColor
        return LinearGradient(
            colors: [
                baseColor.opacity(0.15),
                baseColor.opacity(0.08),
                Color(red: 0.95, green: 0.95, blue: 0.97)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // 根据目的地主题生成暗夜模式背景渐变
    private var darkModeBackground: some View {
        let baseColor = destinationThemeColor
        return LinearGradient(
            colors: [
                baseColor.opacity(0.25),
                baseColor.opacity(0.12),
                Color(red: 0.05, green: 0.05, blue: 0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // 动态主题色 - 适配暗夜模式
    private var themePrimary: Color { colorScheme == .dark ? destinationThemeColor.opacity(0.9) : destinationThemeColor }
    private var themeSecondary: Color { colorScheme == .dark ? destinationThemeColor.opacity(0.7) : destinationThemeColor.opacity(0.8) }
    private var themeBackground: Color { colorScheme == .dark ? destinationThemeColor.opacity(0.15) : destinationThemeColor.opacity(0.1) }
    private var cardBackground: Color { colorScheme == .dark ? Color(red: 0.12, green: 0.14, blue: 0.18) : Color.white }
    
    var body: some View {
        ZStack {
            // 目的地主题背景
            Group {
                if colorScheme == .dark {
                    darkModeBackground
                } else {
                    lightModeBackground
                }
            }
            .ignoresSafeArea()
            
            // 装饰性主题元素
            GeometryReader { geo in
                ZStack {
                    // 顶部装饰圆
                    Circle()
                        .fill(themePrimary.opacity(colorScheme == .dark ? 0.15 : 0.2))
                        .frame(width: 300, height: 300)
                        .offset(x: -100, y: -100)
                        .blur(radius: 60)
                    
                    // 底部装饰圆
                    Circle()
                        .fill(themeSecondary.opacity(colorScheme == .dark ? 0.1 : 0.15))
                        .frame(width: 250, height: 250)
                        .offset(x: 150, y: geo.size.height - 150)
                        .blur(radius: 50)
                }
            }
            
            VStack(spacing: 30) {
            // 图标
            ZStack {
                Circle()
                    .fill(themeBackground)
                    .frame(width: 100, height: 100)
                
                Image(systemName: showDeparture ? "eye" : "eye.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(themePrimary)
                    .symbolEffect(.bounce, value: showDeparture)
            }
            
            VStack(spacing: 12) {
                Text("隐私设置")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text("您可以选择是否显示出发地信息")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // 预览卡片
            VStack(alignment: .leading, spacing: 12) {
                Text("分享预览")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.pink)
                    
                    if showDeparture, let city = viewModel.departureCity {
                        Text("从 \(city) 出发")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    } else {
                        Text("出发地")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "airplane")
                        .foregroundStyle(themePrimary)
                    
                    Spacer()
                    
                    if let landmark = viewModel.selectedLandmark {
                        Text("飞往 \(landmark.name)")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(cardBackground)
                        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.05), radius: 8)
                )
            }
            .padding(.horizontal, 30)
            
            // 开关
            Toggle("显示出发地", isOn: $showDeparture)
                .onChange(of: showDeparture) { newValue in
                    viewModel.isDepartureHidden = !newValue
                }
                .padding(.horizontal, 40)
                .tint(themePrimary)
            
            Spacer()
            
            // 液态玻璃风格按钮
            Button(action: onContinue) {
                HStack(spacing: 8) {
                    Text("继续")
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(colorScheme == .dark ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
                .background(
                    ZStack {
                        // 毛玻璃背景
                        RoundedRectangle(cornerRadius: 25)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white.opacity(0.7))
                        
                        // 边框
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.3) : Color.white.opacity(0.8), lineWidth: 1)
                    }
                )
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 25))
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 20)
        }
        .padding(.top, 20)
        }
    }
}

// MARK: - 座位选择视图
struct SeatSelectionView: View {
    @Binding var selectedSeat: String
    let onConfirm: () -> Void
    let onBack: () -> Void
    @State private var selectedClass: SeatClass = .business
    @Environment(\.colorScheme) var colorScheme
    
    // 莫妮卡色系 - 适配暗夜模式
    private var monicaPrimary: Color { colorScheme == .dark ? Color(red: 0.4, green: 0.7, blue: 1.0) : Color(red: 0.2, green: 0.5, blue: 0.9) }
    private var monicaSecondary: Color { colorScheme == .dark ? Color(red: 0.3, green: 0.6, blue: 0.9) : Color(red: 0.3, green: 0.6, blue: 1.0) }
    private var seatMapBackground: Color { colorScheme == .dark ? Color(red: 0.1, green: 0.12, blue: 0.18) : Color.white }
    private var availableSeatColor: Color { colorScheme == .dark ? Color(red: 0.3, green: 0.5, blue: 0.8) : Color(red: 0.2, green: 0.5, blue: 0.9) }
    private var occupiedSeatColor: Color { colorScheme == .dark ? Color(red: 0.25, green: 0.25, blue: 0.28) : Color.gray.opacity(0.3) }
    private var selectedSeatColor: Color { colorScheme == .dark ? Color(red: 1.0, green: 0.6, blue: 0.3) : Color.orange }
    
    enum SeatClass {
        case first, business, economy
    }
    
    private let seatRows = Array(1...10)
    private let seatLetters = ["A", "B", "C", "D", "E", "F"]
    
    var body: some View {
        VStack(spacing: 20) {
            // 舱位选择
            Picker("舱位", selection: $selectedClass) {
                Text("头等舱").tag(SeatClass.first)
                Text("商务舱").tag(SeatClass.business)
                Text("经济舱").tag(SeatClass.economy)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            
            // 座位图例
            HStack(spacing: 20) {
                SeatLegend(color: availableSeatColor, label: "可选")
                SeatLegend(color: occupiedSeatColor, label: "已占")
                SeatLegend(color: selectedSeatColor, label: "已选")
            }
            
            // 座位图
            ScrollView {
                VStack(spacing: 8) {
                    // 机头方向
                    Image(systemName: "airplane")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(-90))
                        .padding(.bottom, 20)
                    
                    ForEach(seatRows, id: \.self) { row in
                        HStack(spacing: 12) {
                            // ABC
                            HStack(spacing: 8) {
                                ForEach(seatLetters[0..<3], id: \.self) { letter in
                                    SeatButton(
                                        seat: "\(row)\(letter)",
                                        isSelected: selectedSeat == "\(row)\(letter)",
                                        isAvailable: isSeatAvailable(row: row, letter: letter),
                                        colorScheme: colorScheme
                                    ) {
                                        selectedSeat = "\(row)\(letter)"
                                    }
                                }
                            }
                            
                            // 过道
                            Text("\(row)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 30)
                            
                            // DEF
                            HStack(spacing: 8) {
                                ForEach(seatLetters[3..<6], id: \.self) { letter in
                                    SeatButton(
                                        seat: "\(row)\(letter)",
                                        isSelected: selectedSeat == "\(row)\(letter)",
                                        isAvailable: isSeatAvailable(row: row, letter: letter),
                                        colorScheme: colorScheme
                                    ) {
                                        selectedSeat = "\(row)\(letter)"
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(seatMapBackground)
                    .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.05), radius: 10)
            )
            .padding(.horizontal, 16)
            
            // 已选座位
            if !selectedSeat.isEmpty {
                HStack {
                    Text("已选座位")
                        .foregroundStyle(.secondary)
                    Text(selectedSeat)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(selectedSeatColor)
                }
                .padding(.vertical, 8)
            }
            
            // 底部按钮：左边上一步，右边确定选座
            HStack(spacing: 16) {
                // 上一步按钮
                Button(action: onBack) {
                    Text("上一步")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.gray.opacity(0.15))
                        )
                }
                
                // 确定选座按钮
                Button(action: onConfirm) {
                    Text("确定选座")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            selectedSeat.isEmpty ?
                            AnyView(Color.gray) :
                            AnyView(LinearGradient(
                                colors: [monicaPrimary, monicaSecondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                        )
                        .cornerRadius(25)
                }
                .disabled(selectedSeat.isEmpty)
            }
            .padding(.horizontal, 30)
        }
    }

    private func isSeatAvailable(row: Int, letter: String) -> Bool {
        // 模拟一些座位已被占用
        let occupiedSeats = ["1A", "1F", "2B", "2E", "3C", "3D", "5A", "5F", "7B", "7E"]
        return !occupiedSeats.contains("\(row)\(letter)")
    }
}

// MARK: - 座位按钮
struct SeatButton: View {
    let seat: String
    let isSelected: Bool
    let isAvailable: Bool
    let colorScheme: ColorScheme
    let action: () -> Void
    
    // 莫妮卡色系 - 适配暗夜模式
    private var availableSeatColor: Color { colorScheme == .dark ? Color(red: 0.25, green: 0.45, blue: 0.7) : Color(red: 0.2, green: 0.5, blue: 0.9) }
    private var selectedSeatColor: Color { colorScheme == .dark ? Color(red: 1.0, green: 0.6, blue: 0.3) : Color.orange }
    
    var body: some View {
        Button(action: action) {
            Text(String(seat.last!))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : (isAvailable ? .primary : .secondary))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(backgroundColor)
                )
        }
        .disabled(!isAvailable)
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return selectedSeatColor
        } else if isAvailable {
            return availableSeatColor.opacity(colorScheme == .dark ? 0.3 : 0.2)
        } else {
            return Color.gray.opacity(colorScheme == .dark ? 0.25 : 0.2)
        }
    }
}

// MARK: - 座位图例
struct SeatLegend: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 16, height: 16)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 登机牌视图
struct BoardingPassView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @State private var shimmerOffset: CGFloat = -200
    @State private var isTorn = false
    @State private var bottomPartOffset: CGFloat = 0
    @State private var bottomPartRotation: Double = 0
    @State private var tearProgress: CGFloat = 0
    @Environment(\.colorScheme) var colorScheme
    
    // 莫妮卡色系 - 适配暗夜模式
    private var monicaPrimary: Color { colorScheme == .dark ? Color(red: 0.4, green: 0.7, blue: 1.0) : Color(red: 0.2, green: 0.5, blue: 0.9) }
    private var cardBackground: Color { colorScheme == .dark ? Color(red: 0.12, green: 0.14, blue: 0.18) : Color.white }
    private var cardSecondaryBackground: Color { colorScheme == .dark ? Color(red: 0.08, green: 0.1, blue: 0.14) : Color(red: 0.98, green: 0.98, blue: 0.99) }
    private var barcodeColor: Color { colorScheme == .dark ? Color.white : Color.black }
    private var shimmerColor: Color { colorScheme == .dark ? Color.white.opacity(0.2) : Color.white.opacity(0.8) }
    
    var body: some View {
        ZStack {
            // 上半部分（固定）
            VStack(spacing: 0) {
                // 上半部分内容
                VStack(alignment: .leading, spacing: 16) {
                    // 航空公司信息
                    HStack {
                        Image(systemName: "airplane.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(monicaPrimary)
                        
                        VStack(alignment: .leading) {
                            Text("LOLITA AIR")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.primary)
                            Text("茶会专机")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("BOARDING PASS")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(monicaPrimary)
                    }
                    
                    Divider()
                        .background(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.2))
                    
                    // 航班信息
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FROM")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if viewModel.isDepartureHidden {
                                Text("***")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.primary)
                            } else if let city = viewModel.departureCity {
                                Text(city.prefix(3).uppercased())
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(spacing: 4) {
                            Image(systemName: "airplane")
                                .foregroundStyle(monicaPrimary)
                            Text(viewModel.currentBoardingPass?.formattedFlightNumber ?? "LA888")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("TO")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(viewModel.selectedLandmark?.code ?? "???")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    // 详细信息网格
                    HStack {
                        InfoItem(title: "DATE", value: formattedDate(viewModel.currentBoardingPass?.flightDate), colorScheme: colorScheme)
                        InfoItem(title: "TIME", value: formattedTime(viewModel.currentBoardingPass?.flightDate), colorScheme: colorScheme)
                        InfoItem(title: "SEAT", value: viewModel.currentBoardingPass?.seatNumber ?? "--", colorScheme: colorScheme)
                        InfoItem(title: "GATE", value: viewModel.currentBoardingPass?.gate ?? "--", colorScheme: colorScheme)
                    }
                }
                .padding(20)
                .background(cardBackground)
                
                // 虚线分隔（可点击撕票）
                TearLineView(isTorn: isTorn, progress: tearProgress, colorScheme: colorScheme)
                    .onTapGesture {
                        tearTicket()
                    }
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onEnded { _ in
                                tearTicket()
                            }
                    )
            }
            .background(cardBackground)
            .cornerRadius(16)
            .shadow(color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 30)
            
            // 下半部分（可撕下）
            if !isTorn {
                VStack(spacing: 0) {
                    Spacer().frame(height: 220) // 上半部分高度
                    
                    // 虚线分隔
                    TearLineView(isTorn: isTorn, progress: tearProgress, colorScheme: colorScheme)
                        .opacity(0) // 隐藏，只用于占位
                    
                    // 下半部分内容
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(viewModel.currentBoardingPass?.passengerName ?? "PASSENGER")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            
                            // 模拟条形码
                            HStack(spacing: 2) {
                                ForEach(0..<30) { i in
                                    Rectangle()
                                        .fill(barcodeColor)
                                        .frame(width: CGFloat.random(in: 1...3), height: 40)
                                }
                            }
                            
                            Text(viewModel.currentBoardingPass?.qrCodeData ?? "LA8888888888")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        // QR码
                        Image(systemName: "qrcode")
                            .font(.system(size: 60))
                            .foregroundStyle(barcodeColor)
                    }
                    .padding(20)
                    .background(
                        cardSecondaryBackground
                            .overlay(
                                // 闪光效果
                                LinearGradient(
                                    colors: [
                                        Color.clear,
                                        shimmerColor,
                                        Color.clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .offset(x: shimmerOffset)
                            )
                    )
                    .background(cardBackground)
                    .cornerRadius(16)
                    .shadow(color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
                    .offset(y: bottomPartOffset)
                    .rotationEffect(.degrees(bottomPartRotation))
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: bottomPartOffset)
                }
                .padding(.horizontal, 30)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                shimmerOffset = 400
            }
        }
    }
    
    private func tearTicket() {
        guard !isTorn else { return }
        
        // 撕票动画
        withAnimation(.easeInOut(duration: 0.3)) {
            tearProgress = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                isTorn = true
                bottomPartOffset = 300
                bottomPartRotation = 15
            }
            
            // 触发完成回调
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 可以在这里添加撕票后的逻辑
            }
        }
    }
    
    private func formattedDate(_ date: Date?) -> String {
        guard let date = date else { return "--/--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
    
    private func formattedTime(_ date: Date?) -> String {
        guard let date = date else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 撕票虚线视图
struct TearLineView: View {
    let isTorn: Bool
    let progress: CGFloat
    let colorScheme: ColorScheme
    
    // 莫妮卡色系 - 适配暗夜模式
    private var lineColor: Color { colorScheme == .dark ? Color.gray.opacity(0.4) : Color.gray.opacity(0.3) }
    private var scissorsColor: Color { colorScheme == .dark ? Color.gray.opacity(0.6) : Color.gray.opacity(0.5) }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<20) { i in
                let itemProgress = CGFloat(i) / 20.0
                let isTornPart = itemProgress < progress
                
                Rectangle()
                    .fill(isTornPart ? Color.clear : lineColor)
                    .frame(width: 8, height: 1)
                
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8, height: 1)
            }
        }
        .frame(height: 20)
        .background(Color.clear)
        .contentShape(Rectangle())
        .overlay(
            // 撕票提示图标
            HStack {
                Spacer()
                Image(systemName: "scissors")
                    .font(.system(size: 12))
                    .foregroundStyle(scissorsColor)
                    .rotationEffect(.degrees(180))
                Spacer()
            }
        )
    }
}

// MARK: - 信息项
struct InfoItem: View {
    let title: String
    let value: String
    let colorScheme: ColorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 扫描器视图
struct ScannerView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @Binding var scanProgress: Double
    let onComplete: () -> Void
    @State private var scanLineOffset: CGFloat = -150
    @Environment(\.colorScheme) var colorScheme
    
    // 莫妮卡色系 - 适配暗夜模式
    private var monicaPrimary: Color { colorScheme == .dark ? Color(red: 0.4, green: 0.7, blue: 1.0) : Color(red: 0.2, green: 0.5, blue: 0.9) }
    private var monicaSecondary: Color { colorScheme == .dark ? Color(red: 0.3, green: 0.7, blue: 1.0) : Color(red: 0.3, green: 0.7, blue: 1.0) }
    private var scanLineColor: Color { colorScheme == .dark ? Color(red: 0.4, green: 0.7, blue: 1.0).opacity(0.9) : Color(red: 0.2, green: 0.5, blue: 0.9).opacity(0.8) }
    private var progressBgColor: Color { colorScheme == .dark ? Color(red: 0.2, green: 0.2, blue: 0.22) : Color.gray.opacity(0.2) }
    private var cardBackground: Color { colorScheme == .dark ? Color(red: 0.15, green: 0.17, blue: 0.22) : Color.white }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // 中下内容容器 - 圆角矩形主题色美化
            VStack(spacing: 24) {
                // 扫描框
                ZStack {
                    // 外框
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(monicaPrimary, lineWidth: 3)
                        .frame(width: 280, height: 180)

                    // 扫描线
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    scanLineColor,
                                    Color.clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 260, height: 2)
                        .offset(y: scanLineOffset)

                    // 登机牌缩略图
                    VStack(spacing: 8) {
                        Image(systemName: "airplane")
                            .font(.system(size: 40))
                            .foregroundStyle(monicaPrimary)

                        HStack {
                            Text(viewModel.isDepartureHidden ? "***" : (viewModel.departureCity?.prefix(3).uppercased() ?? "???"))
                                .foregroundStyle(.primary)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            Text(viewModel.selectedLandmark?.code ?? "???")
                                .foregroundStyle(.primary)
                        }
                        .font(.system(size: 16, weight: .semibold))
                    }
                }

                // 扫描文字
                VStack(spacing: 12) {
                    Text("正在检票...")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.primary)

                    // 进度条
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(progressBgColor)
                                .frame(height: 6)
                                .cornerRadius(3)

                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [monicaPrimary, monicaSecondary],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * scanProgress, height: 6)
                                .cornerRadius(3)
                        }
                    }
                    .frame(width: 200, height: 6)
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 30)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(cardBackground)
                    .shadow(
                        color: monicaPrimary.opacity(colorScheme == .dark ? 0.2 : 0.15),
                        radius: 20,
                        x: 0,
                        y: 8
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        monicaPrimary.opacity(colorScheme == .dark ? 0.3 : 0.2),
                        lineWidth: 1.5
                    )
            )
            .padding(.horizontal, 20)
            
            Spacer().frame(height: 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // 扫描线动画
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: true)) {
                scanLineOffset = 150
            }
            
            // 进度动画
            withAnimation(.linear(duration: 2)) {
                scanProgress = 1.0
            }
            
            // 完成后跳转
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                onComplete()
            }
        }
    }
}

// MARK: - 角标
struct CornerMarkers: View {
    @Environment(\.colorScheme) var colorScheme
    
    // 莫妮卡色系 - 适配暗夜模式
    private var monicaPrimary: Color { colorScheme == .dark ? Color(red: 0.4, green: 0.7, blue: 1.0) : Color(red: 0.2, green: 0.5, blue: 0.9) }
    
    var body: some View {
        ZStack {
            // 左上
            VStack(spacing: 0) {
                Rectangle().fill(monicaPrimary).frame(width: 30, height: 4)
                Rectangle().fill(monicaPrimary).frame(width: 4, height: 30)
            }
            .position(x: 20, y: 20)
            
            // 右上
            VStack(spacing: 0) {
                Rectangle().fill(monicaPrimary).frame(width: 30, height: 4)
                Rectangle().fill(monicaPrimary).frame(width: 4, height: 30)
            }
            .rotationEffect(.degrees(90))
            .position(x: 260, y: 20)
            
            // 左下
            VStack(spacing: 0) {
                Rectangle().fill(monicaPrimary).frame(width: 30, height: 4)
                Rectangle().fill(monicaPrimary).frame(width: 4, height: 30)
            }
            .rotationEffect(.degrees(-90))
            .position(x: 20, y: 160)
            
            // 右下
            VStack(spacing: 0) {
                Rectangle().fill(monicaPrimary).frame(width: 30, height: 4)
                Rectangle().fill(monicaPrimary).frame(width: 4, height: 30)
            }
            .rotationEffect(.degrees(180))
            .position(x: 260, y: 160)
        }
        .frame(width: 280, height: 180)
    }
}

// MARK: - 登机完成视图
struct BoardingCompleteView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @Environment(\.colorScheme) var colorScheme
    
    // 莫妮卡色系 - 适配暗夜模式
    private var successColor: Color { colorScheme == .dark ? Color(red: 0.3, green: 0.8, blue: 0.5) : Color.green }
    private var successBgColor: Color { colorScheme == .dark ? Color(red: 0.08, green: 0.25, blue: 0.15) : Color.green.opacity(0.2) }
    private var monicaPrimary: Color { colorScheme == .dark ? Color(red: 0.4, green: 0.7, blue: 1.0) : Color(red: 0.2, green: 0.5, blue: 0.9) }
    private var cardBackground: Color { colorScheme == .dark ? Color(red: 0.15, green: 0.17, blue: 0.22) : Color.white }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // 中下内容容器 - 圆角矩形主题色美化
            VStack(spacing: 24) {
                // 成功图标
                ZStack {
                    Circle()
                        .fill(successBgColor)
                        .frame(width: 120, height: 120)
                    
                    Circle()
                        .stroke(successColor, lineWidth: 3)
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundStyle(successColor)
                }
                .scaleEffect(scale)
                
                VStack(spacing: 8) {
                    Text("检票成功")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text("欢迎搭乘 LOLITA AIR")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if let landmark = viewModel.selectedLandmark {
                        Text("目的地: \(landmark.name)")
                            .font(.headline)
                            .foregroundStyle(landmark.type.themeColor)
                            .padding(.top, 8)
                    }
                }
                .opacity(opacity)
                
                // 登机口信息
                HStack(spacing: 30) {
                    BoardingInfoItem(icon: "number", title: "登机口", value: viewModel.currentBoardingPass?.gate ?? "A1", colorScheme: colorScheme)
                    BoardingInfoItem(icon: "airplane", title: "座位", value: viewModel.currentBoardingPass?.seatNumber ?? "--", colorScheme: colorScheme)
                }
                .padding(.top, 20)
                .opacity(opacity)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 30)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(cardBackground)
                    .shadow(
                        color: successColor.opacity(colorScheme == .dark ? 0.2 : 0.15),
                        radius: 20,
                        x: 0,
                        y: 8
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        successColor.opacity(colorScheme == .dark ? 0.3 : 0.2),
                        lineWidth: 1.5
                    )
            )
            .padding(.horizontal, 20)
            
            Spacer().frame(height: 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                scale = 1.0
            }
            withAnimation(.easeIn.delay(0.3)) {
                opacity = 1.0
            }
            
            // 自动开始飞行
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                viewModel.startFlight()
            }
        }
    }
}

// MARK: - 登机信息项
struct BoardingInfoItem: View {
    let icon: String
    let title: String
    let value: String
    let colorScheme: ColorScheme
    
    // 莫妮卡色系 - 适配暗夜模式
    private var monicaPrimary: Color { colorScheme == .dark ? Color(red: 0.4, green: 0.7, blue: 1.0) : Color(red: 0.2, green: 0.5, blue: 0.9) }
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(monicaPrimary)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(width: 80)
    }
}

#Preview {
    BoardingExperienceView(viewModel: BigWorldViewModel())
}
