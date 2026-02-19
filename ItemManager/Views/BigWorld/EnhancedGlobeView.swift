//
//  EnhancedGlobeView.swift
//  ItemManager
//
//  大世界 - 3D地球与航线系统
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - 3D地球视图
struct EnhancedGlobeView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @State private var rotationAngle: Double = 0
    @State private var selectedLandmark: Landmark?
    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 30, longitude: 0), distance: 20000000)
    )
    @State private var showRoute = false
    @State private var routeProgress: Double = 0
    @State private var isMapLoaded = false
    @State private var showBadgeWall = false
    @State private var showLandmarkSheet = false
    
    var body: some View {
        ZStack {
            // 星空背景
            StarfieldView()
            
            // 3D地球 - 使用Map组件
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom, .rotate]) {
                // 用户当前位置标记 - 外白圈内主题色
                if let userLoc = viewModel.userCoordinate {
                    Annotation("当前位置", coordinate: userLoc) {
                        UserLocationAnnotationView()
                    }
                }
                
                // 地标标记
                ForEach(viewModel.availableLandmarks) { landmark in
                    Annotation(landmark.name, coordinate: landmark.coordinate) {
                        LandmarkAnnotationView(landmark: landmark, isSelected: selectedLandmark?.id == landmark.id) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                selectedLandmark = landmark
                                focusOnLandmark(landmark)
                                showLandmarkSheet = true
                            }
                        }
                    }
                }
                
                // 航线
                if showRoute, let selected = selectedLandmark, let userLoc = viewModel.userCoordinate {
                    MapPolyline(coordinates: calculateRoute(from: userLoc, to: selected.coordinate))
                        .stroke(landmarkTypeColor(selected.type), lineWidth: 3)
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .mapControlVisibility(.hidden)
            .onMapCameraChange { context in
                isMapLoaded = true
            }
            .safeAreaPadding(.top, 110)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 85)
            }
            
            // UI 覆盖层
            GeometryReader { geometry in
                let safeAreaTop = geometry.safeAreaInsets.top
                // 导航栏高度约44pt，加上一些间距，让内容显示在导航栏下方
                let navBarOffset = safeAreaTop + 60
                
                // 左侧：标题（在导航栏下方）
                VStack {
                    Spacer().frame(height: navBarOffset)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("选择目的地")
                                .font(.system(size: 24, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                            Text("探索全球茶会圣地")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        .padding(.leading, 20)
                        
                        Spacer()
                    }
                    
                    Spacer()
                }
                .allowsHitTesting(false)
                
                // 右侧：等级入口（在导航栏下方，与标题对齐）
                VStack {
                    Spacer().frame(height: navBarOffset)
                    
                    HStack {
                        Spacer()
                        
                        // 等级徽章入口
                        LevelBadgeEntry(viewModel: viewModel) {
                            showBadgeWall = true
                        }
                        .padding(.trailing, 20)
                    }
                    
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showBadgeWall) {
            UserLevelSheet(viewModel: viewModel)
                .presentationDetents([.height(200), .medium])
        }
        .sheet(isPresented: $showLandmarkSheet) {
            if let landmark = selectedLandmark {
                LandmarkDetailSheet(landmark: landmark, viewModel: viewModel) {
                    viewModel.selectLandmark(landmark)
                    showLandmarkSheet = false
                }
                .presentationDetents([.height(280), .medium, .large])
            }
        }
        .onAppear {
            // 自动旋转地球
            withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }
    
    private func focusOnLandmark(_ landmark: Landmark) {
        withAnimation(.easeInOut(duration: 1.0)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: landmark.coordinate,
                    distance: 5000000,
                    pitch: 60
                )
            )
        }
        
        // 显示航线动画
        showRoute = true
        withAnimation(.linear(duration: 1.5)) {
            routeProgress = 1.0
        }
    }
    
    private func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        // 计算大圆航线
        let steps = 50
        var coordinates: [CLLocationCoordinate2D] = []
        
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let lat = from.latitude + (to.latitude - from.latitude) * t
            let lon = from.longitude + (to.longitude - from.longitude) * t
            // 添加一些弧度使航线更自然
            let arcHeight = sin(t * .pi) * 20
            coordinates.append(CLLocationCoordinate2D(latitude: lat + arcHeight, longitude: lon))
        }
        
        return coordinates
    }
    
    private func landmarkTypeColor(_ type: LandmarkType) -> Color {
        switch type {
        case .glacier: return Color(red: 0.6, green: 0.85, blue: 0.95)
        case .canyon: return Color(red: 0.95, green: 0.6, blue: 0.4)
        case .oasis: return Color(red: 0.4, green: 0.8, blue: 0.6)
        case .prairie: return Color(red: 0.7, green: 0.9, blue: 0.4)
        case .aurora: return Color(red: 0.4, green: 0.9, blue: 0.8)
        case .castle: return Color(red: 0.9, green: 0.7, blue: 0.5)
        case .sakura: return Color(red: 1.0, green: 0.75, blue: 0.85)
        case .lavender: return Color(red: 0.75, green: 0.6, blue: 0.9)
        }
    }
}

// MARK: - 等级徽章入口
struct LevelBadgeEntry: View {
    @ObservedObject var viewModel: BigWorldViewModel
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // 外圈光晕
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color(red: 1.0, green: 0.84, blue: 0.0),
                                Color(red: 1.0, green: 0.41, blue: 0.71),
                                Color(red: 1.0, green: 0.84, blue: 0.0)
                            ],
                            center: .center,
                            angle: .degrees(0)
                        )
                    )
                    .frame(width: 56, height: 56)
                    .blur(radius: 2)
                
                // 内圈
                Circle()
                    .fill(Color.black)
                    .frame(width: 52, height: 52)
                
                // 等级文字
                VStack(spacing: 0) {
                    Text("Lv")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                    Text("\(viewModel.userLevel)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - 徽章图标
struct BadgeIcon: View {
    let badge: TeaPartyBadge
    let index: Int
    let total: Int
    
    var body: some View {
        let offsetX = CGFloat(index - total / 2) * 8
        let offsetY = CGFloat(index % 2) * -4
        let scale = 1.0 - CGFloat(index) * 0.1
        
        ZStack {
            Circle()
                .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
                .frame(width: 28, height: 28)
                .shadow(color: badge.themeColor.opacity(0.5), radius: 4)
            
            Image(systemName: badge.iconName)
                .font(.system(size: 14))
                .foregroundStyle(badge.themeColor)
        }
        .offset(x: offsetX, y: offsetY)
        .scaleEffect(scale)
        .zIndex(Double(total - index))
    }
}

// MARK: - 用户等级Sheet（展示常佩戴/最近获得徽章）
struct UserLevelSheet: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @Environment(\.dismiss) private var dismiss
    
    // 常佩戴的徽章（这里用最近获得的3枚作为示例，实际应该从用户的佩戴设置中获取）
    private var equippedBadges: [TeaPartyBadge] {
        // 如果没有设置常佩戴，显示最近获得的3枚
        let badges = viewModel.unlockedBadges
        if badges.isEmpty {
            return []
        }
        return Array(badges.prefix(3))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 等级信息
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.84, blue: 0.0),
                                        Color(red: 1.0, green: 0.41, blue: 0.71),
                                        Color(red: 1.0, green: 0.84, blue: 0.0)
                                    ],
                                    center: .center,
                                    angle: .degrees(0)
                                )
                            )
                            .frame(width: 70, height: 70)
                            .blur(radius: 2)
                        
                        Circle()
                            .fill(Color.black)
                            .frame(width: 64, height: 64)
                        
                        VStack(spacing: 0) {
                            Text("Lv")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                            Text("\(viewModel.userLevel)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lo同好")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Text("已解锁 \(viewModel.unlockedBadges.count) 枚徽章")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                
                Divider()
                
                // 常佩戴/最近获得徽章
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(equippedBadges.isEmpty ? "最近获得" : "常佩戴徽章")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        NavigationLink {
                            BadgeWallView(viewModel: viewModel)
                        } label: {
                            Text("查看全部")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    if equippedBadges.isEmpty {
                        // 没有徽章时显示提示
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "medal")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.gray.opacity(0.5))
                                Text("还没有获得徽章")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("去探索世界获得徽章吧！")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    } else {
                        // 展示3枚徽章
                        HStack(spacing: 20) {
                            ForEach(equippedBadges) { badge in
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        badge.themeColor.opacity(0.3),
                                                        badge.themeColor.opacity(0.1)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 60, height: 60)
                                        
                                        Circle()
                                            .stroke(badge.themeColor, lineWidth: 2)
                                            .frame(width: 56, height: 56)
                                        
                                        Image(systemName: badge.iconName)
                                            .font(.system(size: 24))
                                            .foregroundStyle(badge.themeColor)
                                    }
                                    
                                    Text(badge.name)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("我的等级")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 地标详情Sheet（原生官方样式）
struct LandmarkDetailSheet: View {
    let landmark: Landmark
    @ObservedObject var viewModel: BigWorldViewModel
    let onBookFlight: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 地标图标和名称
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(landmark.type.themeColor.opacity(0.2))
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: landmark.type.icon)
                            .font(.system(size: 30))
                            .foregroundStyle(landmark.type.themeColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(landmark.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Text(landmark.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(landmark.type.themeColor)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption)
                            Text("\(String(format: "%.2f", abs(landmark.coordinate.latitude)))°\(landmark.coordinate.latitude >= 0 ? "N" : "S"), \(String(format: "%.2f", abs(landmark.coordinate.longitude)))°\(landmark.coordinate.longitude >= 0 ? "E" : "W")")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                
                Divider()
                
                // 茶会主题和徽章
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("茶会主题")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(landmark.teaPartyTheme)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // 可获得徽章
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("可获得")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Image(systemName: "medal.fill")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.4)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            Text(landmark.badgeName)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                
                Spacer()
                
                // 起飞按钮
                Button(action: onBookFlight) {
                    HStack(spacing: 8) {
                        Image(systemName: "airplane.departure")
                        Text("预订航班")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.4)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
            }
            .padding()
            .navigationTitle("目的地")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 星空背景
struct StarfieldView: View {
    @State private var stars: [Star] = []
    
    struct Star: Identifiable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
    }
    
    var body: some View {
        Canvas { context, size in
            // 深空背景
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(red: 0.02, green: 0.02, blue: 0.08))
            )
            
            // 绘制星星
            for star in stars {
                let rect = CGRect(
                    x: star.x * size.width,
                    y: star.y * size.height,
                    width: star.size,
                    height: star.size
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(Color.white.opacity(star.opacity))
                )
            }
        }
        .onAppear {
            // 生成随机星星
            stars = (0..<200).map { _ in
                Star(
                    x: CGFloat.random(in: 0...1),
                    y: CGFloat.random(in: 0...1),
                    size: CGFloat.random(in: 1...3),
                    opacity: Double.random(in: 0.3...1.0)
                )
            }
        }
    }
}

// MARK: - 用户位置标注视图（外白圈，内主题色）
struct UserLocationAnnotationView: View {
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // 外圈脉冲动画
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 36)
                .scaleEffect(pulseScale)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        pulseScale = 1.4
                    }
                }
            
            // 外白圈
            Circle()
                .fill(Color.white)
                .frame(width: 24, height: 24)
                .shadow(color: Color.white.opacity(0.5), radius: 4)
            
            // 内主题色（粉色主题）
            Circle()
                .fill(Color(red: 1.0, green: 0.41, blue: 0.71))
                .frame(width: 16, height: 16)
            
            // 中心点
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
        }
    }
}

// MARK: - 地标标注视图
struct LandmarkAnnotationView: View {
    let landmark: Landmark
    let isSelected: Bool
    let action: () -> Void
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // 脉冲动画环
                if isSelected {
                    Circle()
                        .fill(landmark.type.themeColor.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .scaleEffect(pulseScale)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                                pulseScale = 1.3
                            }
                        }
                }
                
                // 地标图标
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 40, height: 40)
                    
                    Circle()
                        .stroke(landmark.type.themeColor, lineWidth: 2)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: landmark.type.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(landmark.type.themeColor)
                }
                
                // 标签
                if isSelected {
                    Text(landmark.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.7))
                        )
                        .offset(y: -35)
                }
            }
        }
    }
}

#Preview {
    EnhancedGlobeView(viewModel: BigWorldViewModel())
}
