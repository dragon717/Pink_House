//
//  BoardingExperienceView.swift
//  ItemManager
//
//  大世界 - 检票登机沉浸式体验
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
    
    enum BoardingStage {
        case privacyCheck
        case seatSelection
        case boardingPass
        case scanner
        case complete
    }
    
    var body: some View {
        ZStack {
            // 机场背景
            AirportBackgroundView()
            
            VStack {
                // 进度指示器
                BoardingProgressView(currentStage: boardingStage)
                    .padding(.top, 60)
                
                Spacer()
                
                // 主要内容
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
                
                Spacer()
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
    
    var body: some View {
        VStack(spacing: 30) {
            // 图标
            ZStack {
                Circle()
                    .fill(Color(red: 0.9, green: 0.95, blue: 1.0))
                    .frame(width: 100, height: 100)
                
                Image(systemName: showDeparture ? "eye" : "eye.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(Color(red: 0.2, green: 0.5, blue: 0.9))
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
                    } else {
                        Text("出发地")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "airplane")
                        .foregroundStyle(.blue)
                    
                    Spacer()
                    
                    if let landmark = viewModel.selectedLandmark {
                        Text("飞往 \(landmark.name)")
                            .font(.subheadline)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.05), radius: 8)
                )
            }
            .padding(.horizontal, 30)
            
            // 开关
            Toggle("显示出发地", isOn: $showDeparture)
                .onChange(of: showDeparture) { newValue in
                    viewModel.isDepartureHidden = !newValue
                }
                .padding(.horizontal, 40)
            
            Spacer()
            
            Button(action: onContinue) {
                HStack {
                    Text("继续")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.5, blue: 0.9), Color(red: 0.3, green: 0.6, blue: 1.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(25)
            }
            .padding(.horizontal, 30)
        }
        .padding(.top, 40)
    }
}

// MARK: - 座位选择视图
struct SeatSelectionView: View {
    @Binding var selectedSeat: String
    let onConfirm: () -> Void
    @State private var selectedClass: SeatClass = .business
    
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
                SeatLegend(color: Color(red: 0.2, green: 0.5, blue: 0.9), label: "可选")
                SeatLegend(color: Color.gray.opacity(0.3), label: "已占")
                SeatLegend(color: Color.orange, label: "已选")
            }
            
            // 座位图
            ScrollView {
                VStack(spacing: 8) {
                    // 机头方向
                    Image(systemName: "airplane")
                        .font(.system(size: 30))
                        .foregroundStyle(.gray)
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
                                        isAvailable: isSeatAvailable(row: row, letter: letter)
                                    ) {
                                        selectedSeat = "\(row)\(letter)"
                                    }
                                }
                            }
                            
                            // 过道
                            Text("\(row)")
                                .font(.caption)
                                .foregroundStyle(.gray)
                                .frame(width: 30)
                            
                            // DEF
                            HStack(spacing: 8) {
                                ForEach(seatLetters[3..<6], id: \.self) { letter in
                                    SeatButton(
                                        seat: "\(row)\(letter)",
                                        isSelected: selectedSeat == "\(row)\(letter)",
                                        isAvailable: isSeatAvailable(row: row, letter: letter)
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
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 10)
            )
            .padding(.horizontal, 16)
            
            // 已选座位
            if !selectedSeat.isEmpty {
                HStack {
                    Text("已选座位")
                        .foregroundStyle(.secondary)
                    Text(selectedSeat)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.orange)
                }
                .padding(.vertical, 8)
            }
            
            Button(action: onConfirm) {
                Text("确认选座")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        selectedSeat.isEmpty ?
                        AnyView(Color.gray) :
                        AnyView(LinearGradient(
                            colors: [Color(red: 0.2, green: 0.5, blue: 0.9), Color(red: 0.3, green: 0.6, blue: 1.0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                    )
                    .cornerRadius(25)
            }
            .disabled(selectedSeat.isEmpty)
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
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(String(seat.last!))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : (isAvailable ? .primary : .gray))
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
            return Color.orange
        } else if isAvailable {
            return Color(red: 0.2, green: 0.5, blue: 0.9).opacity(0.2)
        } else {
            return Color.gray.opacity(0.2)
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
    
    var body: some View {
        VStack(spacing: 0) {
            // 上半部分
            VStack(alignment: .leading, spacing: 16) {
                // 航空公司信息
                HStack {
                    Image(systemName: "airplane.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color(red: 0.2, green: 0.5, blue: 0.9))
                    
                    VStack(alignment: .leading) {
                        Text("LOLITA AIR")
                            .font(.system(size: 16, weight: .bold))
                        Text("茶会专机")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("BOARDING PASS")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.2, green: 0.5, blue: 0.9))
                }
                
                Divider()
                
                // 航班信息
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FROM")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if viewModel.isDepartureHidden {
                            Text("***")
                                .font(.system(size: 20, weight: .bold))
                        } else if let city = viewModel.departureCity {
                            Text(city.prefix(3).uppercased())
                                .font(.system(size: 20, weight: .bold))
                        }
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 4) {
                        Image(systemName: "airplane")
                            .foregroundStyle(Color(red: 0.2, green: 0.5, blue: 0.9))
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
                    }
                }
                
                // 详细信息网格
                HStack {
                    InfoItem(title: "DATE", value: formattedDate(viewModel.currentBoardingPass?.flightDate))
                    InfoItem(title: "TIME", value: formattedTime(viewModel.currentBoardingPass?.flightDate))
                    InfoItem(title: "SEAT", value: viewModel.currentBoardingPass?.seatNumber ?? "--")
                    InfoItem(title: "GATE", value: viewModel.currentBoardingPass?.gate ?? "--")
                }
            }
            .padding(20)
            .background(Color.white)
            
            // 虚线分隔
            HStack(spacing: 0) {
                ForEach(0..<20) { _ in
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 8, height: 1)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 8, height: 1)
                }
            }
            
            // 下半部分 - 条形码区域
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.currentBoardingPass?.passengerName ?? "PASSENGER")
                        .font(.system(size: 14, weight: .medium))
                    
                    // 模拟条形码
                    HStack(spacing: 2) {
                        ForEach(0..<30) { i in
                            Rectangle()
                                .fill(Color.black)
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
                    .foregroundStyle(.black)
            }
            .padding(20)
            .background(
                Color(red: 0.98, green: 0.98, blue: 0.99)
                    .overlay(
                        // 闪光效果
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.8),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .offset(x: shimmerOffset)
                    )
            )
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 30)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                shimmerOffset = 400
            }
        }
    }
}

// MARK: - 信息项
struct InfoItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 日期时间格式化辅助函数
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

// MARK: - 扫描器视图
struct ScannerView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @Binding var scanProgress: Double
    let onComplete: () -> Void
    @State private var scanLineOffset: CGFloat = -150
    
    var body: some View {
        VStack(spacing: 30) {
            // 扫描框
            ZStack {
                // 外框
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(red: 0.2, green: 0.5, blue: 0.9), lineWidth: 3)
                    .frame(width: 280, height: 180)
                
                // 角标
                CornerMarkers()
                
                // 扫描线
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color(red: 0.2, green: 0.5, blue: 0.9).opacity(0.8),
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
                        .foregroundStyle(Color(red: 0.2, green: 0.5, blue: 0.9))
                    
                    HStack {
                        Text(viewModel.isDepartureHidden ? "***" : (viewModel.departureCity?.prefix(3).uppercased() ?? "???"))
                        Image(systemName: "arrow.right")
                        Text(viewModel.selectedLandmark?.code ?? "???")
                    }
                    .font(.system(size: 16, weight: .semibold))
                }
            }
            
            // 扫描文字
            VStack(spacing: 8) {
                Text("正在检票...")
                    .font(.system(size: 18, weight: .medium))
                
                // 进度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)
                            .cornerRadius(3)
                        
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.2, green: 0.5, blue: 0.9), Color(red: 0.3, green: 0.7, blue: 1.0)],
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
    var body: some View {
        ZStack {
            // 左上
            VStack(spacing: 0) {
                Rectangle().fill(Color(red: 0.2, green: 0.5, blue: 0.9)).frame(width: 30, height: 4)
                Rectangle().fill(Color(red: 0.2, green: 0.5, blue: 0.9)).frame(width: 4, height: 30)
            }
            .position(x: 20, y: 20)
            
            // 右上
            VStack(spacing: 0) {
                Rectangle().fill(Color(red: 0.2, green: 0.5, blue: 0.9)).frame(width: 30, height: 4)
                Rectangle().fill(Color(red: 0.2, green: 0.5, blue: 0.9)).frame(width: 4, height: 30)
            }
            .rotationEffect(.degrees(90))
            .position(x: 260, y: 20)
            
            // 左下
            VStack(spacing: 0) {
                Rectangle().fill(Color(red: 0.2, green: 0.5, blue: 0.9)).frame(width: 30, height: 4)
                Rectangle().fill(Color(red: 0.2, green: 0.5, blue: 0.9)).frame(width: 4, height: 30)
            }
            .rotationEffect(.degrees(-90))
            .position(x: 20, y: 160)
            
            // 右下
            VStack(spacing: 0) {
                Rectangle().fill(Color(red: 0.2, green: 0.5, blue: 0.9)).frame(width: 30, height: 4)
                Rectangle().fill(Color(red: 0.2, green: 0.5, blue: 0.9)).frame(width: 4, height: 30)
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
    
    var body: some View {
        VStack(spacing: 24) {
            // 成功图标
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                Circle()
                    .stroke(Color.green, lineWidth: 3)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(Color.green)
            }
            .scaleEffect(scale)
            
            VStack(spacing: 8) {
                Text("检票成功")
                    .font(.system(size: 24, weight: .bold))
                
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
                BoardingInfoItem(icon: "number", title: "登机口", value: viewModel.currentBoardingPass?.gate ?? "A1")
                BoardingInfoItem(icon: "airplane", title: "座位", value: viewModel.currentBoardingPass?.seatNumber ?? "--")
            }
            .padding(.top, 20)
            .opacity(opacity)
        }
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
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Color(red: 0.2, green: 0.5, blue: 0.9))
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.system(size: 20, weight: .bold))
        }
        .frame(width: 80)
    }
}

#Preview {
    BoardingExperienceView(viewModel: BigWorldViewModel())
}
