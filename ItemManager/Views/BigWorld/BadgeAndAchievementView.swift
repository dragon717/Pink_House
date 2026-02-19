//
//  BadgeAndAchievementView.swift
//  ItemManager
//
//  大世界 - 徽章墙与成就系统
//

import SwiftUI

// MARK: - 徽章墙主视图
struct BadgeWallView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @State private var selectedBadge: TeaPartyBadge?
    @State private var showDetail = false
    @State private var wallRotation: Double = 0
    @Environment(\.dismiss) private var dismiss
    
    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 20)
    ]
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let safeAreaTop = geometry.safeAreaInsets.top
                let safeAreaBottom = geometry.safeAreaInsets.bottom
                let navBarOffset = safeAreaTop + 60
                let tabBarOffset = safeAreaBottom + 90
                
                ZStack {
                    // 背景
                    BadgeWallBackground()
                    
                    VStack(spacing: 0) {
                        // 顶部安全区域偏移
                        Spacer().frame(height: navBarOffset)
                        
                        // 顶部标题
                        BadgeWallHeader(unlockedCount: viewModel.unlockedBadges.count, totalCount: viewModel.availableLandmarks.count)
                        
                        // 徽章网格
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 24) {
                                ForEach(viewModel.availableLandmarks) { landmark in
                                    BadgeCell(
                                        landmark: landmark,
                                        isUnlocked: viewModel.unlockedBadges.contains(where: { $0.landmarkId == landmark.id })
                                    ) {
                                        if let badge = viewModel.unlockedBadges.first(where: { $0.landmarkId == landmark.id }) {
                                            selectedBadge = badge
                                            showDetail = true
                                        }
                                    }
                                }
                            }
                            .padding(20)
                        }
                        
                        // 成就进度
                        AchievementSummaryView(viewModel: viewModel)
                            .padding(.horizontal, 20)
                        
                        // 底部安全区域偏移
                        Spacer().frame(height: tabBarOffset)
                    }
                }
            }
            .navigationTitle("茶会徽章墙")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.41, blue: 0.71))
                }
            }
            .sheet(isPresented: $showDetail) {
                if let badge = selectedBadge {
                    BadgeDetailView(badge: badge)
                }
            }
        }
    }
}

// MARK: - 徽章墙背景
struct BadgeWallBackground: View {
    var body: some View {
        ZStack {
            // 深色背景
            Color(red: 0.08, green: 0.08, blue: 0.12)
                .ignoresSafeArea()
            
            // 网格纹理
            GeometryReader { geo in
                Canvas { context, size in
                    // 绘制网格线
                    let gridSize: CGFloat = 40
                    
                    // 垂直线
                    for x in stride(from: 0, to: size.width, by: gridSize) {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(Color.white.opacity(0.03)), lineWidth: 1)
                    }
                    
                    // 水平线
                    for y in stride(from: 0, to: size.height, by: gridSize) {
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(path, with: .color(Color.white.opacity(0.03)), lineWidth: 1)
                    }
                }
            }
            
            // 顶部光晕
            VStack {
                LinearGradient(
                    colors: [
                        Color.purple.opacity(0.2),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 300)
                
                Spacer()
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - 徽章墙头部
struct BadgeWallHeader: View {
    let unlockedCount: Int
    let totalCount: Int
    @State private var glowOpacity: Double = 0.5
    
    var body: some View {
        VStack(spacing: 12) {
            // 标题
            Text("茶会徽章墙")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.84, blue: 0.0),
                            Color(red: 1.0, green: 0.6, blue: 0.4)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            // 进度
            HStack(spacing: 8) {
                Text("\(unlockedCount)/\(totalCount)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("枚徽章")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            }
            
            // 进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.84, blue: 0.0),
                                    Color(red: 1.0, green: 0.6, blue: 0.4)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * (Double(unlockedCount) / Double(totalCount)), height: 8)
                        .shadow(color: Color(red: 1.0, green: 0.84, blue: 0.0).opacity(glowOpacity), radius: 10)
                }
            }
            .frame(width: 200, height: 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    glowOpacity = 1.0
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - 徽章单元格
struct BadgeCell: View {
    let landmark: Landmark
    let isUnlocked: Bool
    let action: () -> Void
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1
    @State private var shimmerOffset: CGFloat = -100
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // 外框
                HexagonShape()
                    .fill(
                        isUnlocked ?
                        LinearGradient(
                            colors: [
                                landmark.type.themeColor.opacity(0.3),
                                landmark.type.themeColor.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [
                                Color.gray.opacity(0.1),
                                Color.gray.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        HexagonShape()
                            .stroke(
                                isUnlocked ? landmark.type.themeColor : Color.gray.opacity(0.3),
                                lineWidth: 2
                            )
                    )
                
                // 徽章内容
                VStack(spacing: 8) {
                    ZStack {
                        // 徽章背景
                        Circle()
                            .fill(
                                isUnlocked ?
                                landmark.type.themeColor.opacity(0.2) :
                                Color.gray.opacity(0.1)
                            )
                            .frame(width: 50, height: 50)
                        
                        // 徽章图标
                        Image(systemName: isUnlocked ? landmark.type.icon : "lock.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(isUnlocked ? landmark.type.themeColor : .gray)
                    }
                    
                    Text(landmark.badgeName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isUnlocked ? .white : .gray)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(12)
                
                // 闪光效果（仅解锁的徽章）
                if isUnlocked {
                    HexagonShape()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.white.opacity(0.3),
                                    Color.clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: shimmerOffset)
                }
            }
            .frame(width: 100, height: 110)
            .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
            .scaleEffect(scale)
        }
        .disabled(!isUnlocked)
        .onAppear {
            if isUnlocked {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    shimmerOffset = 100
                }
            }
        }
        .onHover { hovering in
            withAnimation(.spring()) {
                scale = hovering ? 1.1 : 1.0
                rotation = hovering ? 5 : 0
            }
        }
    }
}

// MARK: - 六边形形状
struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        path.move(to: CGPoint(x: width * 0.5, y: 0))
        path.addLine(to: CGPoint(x: width, y: height * 0.25))
        path.addLine(to: CGPoint(x: width, y: height * 0.75))
        path.addLine(to: CGPoint(x: width * 0.5, y: height))
        path.addLine(to: CGPoint(x: 0, y: height * 0.75))
        path.addLine(to: CGPoint(x: 0, y: height * 0.25))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - 徽章详情视图
struct BadgeDetailView: View {
    let badge: TeaPartyBadge
    @Environment(\.dismiss) private var dismiss
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            // 背景
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                // 关闭按钮
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.gray)
                    }
                }
                .padding()
                
                Spacer()
                
                // 3D徽章展示
                ZStack {
                    // 光晕
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    badge.themeColor.opacity(0.4),
                                    badge.themeColor.opacity(0.1),
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
                            .frame(width: 180, height: 180)
                            .shadow(color: badge.themeColor.opacity(0.5), radius: 30)
                        
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
                                lineWidth: 4
                            )
                            .frame(width: 170, height: 170)
                        
                        Image(systemName: badge.iconName)
                            .font(.system(size: 70))
                            .foregroundStyle(badge.themeColor)
                    }
                    .rotation3DEffect(.degrees(rotation * 0.5), axis: (x: 0, y: 1, z: 0))
                }
                
                // 徽章信息
                VStack(spacing: 12) {
                    Text(badge.name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Text(badge.description)
                        .font(.body)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    // 获得时间
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.gray)
                        Text("获得于 \(badge.earnedDate.formatted(date: .long, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                    .padding(.top, 8)
                }
                
                Spacer()
                
                // 分享按钮
                Button(action: {
                    // 分享徽章
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("分享徽章")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [badge.themeColor, badge.themeColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(25)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - 成就摘要视图
struct AchievementSummaryView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("成就进度")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            
            ForEach(viewModel.achievements.prefix(3)) { achievement in
                AchievementRow(achievement: achievement)
            }
            
            NavigationLink(destination: AchievementListView(viewModel: viewModel)) {
                HStack {
                    Text("查看全部成就")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - 成就列表视图
struct AchievementListView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            BadgeWallBackground()
            
            ScrollView {
                VStack(spacing: 16) {
                    // 统计卡片
                    AchievementStatsCard(viewModel: viewModel)
                    
                    // 成就列表
                    ForEach(viewModel.achievements) { achievement in
                        AchievementCard(achievement: achievement)
                    }
                }
                .padding(20)
                .padding(.top, 60)
            }
        }
        .navigationTitle("成就")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
    }
}

// MARK: - 成就统计卡片
struct AchievementStatsCard: View {
    @ObservedObject var viewModel: BigWorldViewModel
    
    var unlockedCount: Int {
        viewModel.achievements.filter { $0.isUnlocked }.count
    }
    
    var body: some View {
        HStack(spacing: 20) {
            StatItem(value: "\(unlockedCount)", label: "已解锁", color: .green)
            Divider().background(Color.white.opacity(0.2))
            StatItem(value: "\(viewModel.achievements.count)", label: "总成就", color: .blue)
            Divider().background(Color.white.opacity(0.2))
            StatItem(value: "\(Int(Double(unlockedCount) / Double(viewModel.achievements.count) * 100))%", label: "完成度", color: .orange)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.15, blue: 0.2),
                            Color(red: 0.1, green: 0.1, blue: 0.15)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
    }
}

// MARK: - 统计项
struct StatItem: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 成就卡片
struct AchievementCard: View {
    let achievement: Achievement
    @State private var showConfetti = false
    
    var body: some View {
        HStack(spacing: 16) {
            // 图标
            ZStack {
                Circle()
                    .fill(achievement.isUnlocked ? achievement.themeColor.opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(width: 56, height: 56)
                
                Image(systemName: achievement.iconName)
                    .font(.system(size: 24))
                    .foregroundStyle(achievement.isUnlocked ? achievement.themeColor : .gray)
            }
            
            // 信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(achievement.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(achievement.isUnlocked ? .white : .gray)
                    
                    if achievement.isUnlocked {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                
                Text(achievement.description)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
                
                // 进度条
                if !achievement.isUnlocked {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(achievement.themeColor)
                                .frame(width: geo.size.width * achievement.progress, height: 4)
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 4)
                    
                    Text("\(Int(achievement.progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
            
            Spacer()
            
            // 奖励
            if achievement.isUnlocked {
                VStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                    Text("+\(achievement.rewardPoints)")
                        .font(.caption)
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(achievement.isUnlocked ? 0.08 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(achievement.isUnlocked ? achievement.themeColor.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }
}

// MARK: - 成就行（用于摘要）
struct AchievementRow: View {
    let achievement: Achievement
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achievement.iconName)
                .font(.system(size: 18))
                .foregroundStyle(achievement.isUnlocked ? achievement.themeColor : .gray)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(achievement.isUnlocked ? achievement.themeColor.opacity(0.2) : Color.gray.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(achievement.isUnlocked ? .white : .gray)
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 3)
                        
                        Capsule()
                            .fill(achievement.isUnlocked ? achievement.themeColor : Color.gray)
                            .frame(width: geo.size.width * achievement.progress, height: 3)
                    }
                }
                .frame(height: 3)
            }
            
            Spacer()
            
            if achievement.isUnlocked {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }
}

#Preview {
    BadgeWallView(viewModel: BigWorldViewModel())
}
