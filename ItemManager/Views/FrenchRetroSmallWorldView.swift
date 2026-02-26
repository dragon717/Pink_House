//
//  SmallWorldView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2/10/26.
//

import SwiftUI
import SwiftData
import UIKit // 导入 UIKit 以使用 UITabBar 等 API
import RealityKit
import CoreMotion

struct FrenchRetroSmallWorldView: View {
    @Binding var selectedTab: Int // MainTabView selection
    @Binding var homeTab: HomeTab // HomeView selection
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    
    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    
    // 图片原始尺寸 1919x1079
    @State private var imageSize = CGSize(width: 1919, height: 1079)
    @AppStorage("isSpatialSceneEnabled") private var isSpatialSceneEnabled = false
    @AppStorage("smallWorldSceneMode") private var sceneModeRaw: Int = SmallWorldSceneMode.auto.rawValue
    
    // 法式复古场景文字旋转角度控制
    static let horizontalLabelRotation: Double = 0
    static let verticalLabelRotation: Double = 0
    
    private var sceneMode: SmallWorldSceneMode {
        SmallWorldSceneMode(rawValue: sceneModeRaw) ?? .auto
    }
    
    // 调试模式：开启后显示热区范围 (仅在 Debug 模式下生效)
    private var showDebugHotspots: Bool {
         return false
//        return true // canvas调整用
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    // 是否显示日历热区 (3D场景开启时隐藏)
    private var shouldShowCalendar: Bool {
        if #available(iOS 26.0, *) {
            return !isSpatialSceneEnabled
        }
        return true
    }
    
    // 根据设置动态获取背景图片名称
    private var currentBackgroundImageName: String {
        sceneMode.backgroundImageName()
    }
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            Group {
                                // 根据设置决定是否开启 3D 景深空间场景 (iOS 26 专属特性模拟)
                                if #available(iOS 26.0, *), isSpatialSceneEnabled {
                                    SpatialBackgroundView(
                                        imageName: currentBackgroundImageName,
                                        imageExtension: "png"
                                    ) {
                                        // 3D 模式下的热区内容
                                        // 此时 GeometryReader 的尺寸已经是被放大 1.15 倍后的尺寸
                                        GeometryReader { geo in
                                            hotspotContent(geometry: geo)
                                        }
                                    }
                                } else {
                                    Image(currentBackgroundImageName) // 确保图片已添加至 Assets
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                }
                            }
                            .frame(width: geometry.size.height * (imageSize.width / imageSize.height), height: geometry.size.height)
                            .overlay(sceneMode.overlayColor())
                            .overlay(
                                // 2D 模式下的热区叠加 (仅当非 3D 模式时才显示，或者作为 fallback)
                                Group {
                                    if #available(iOS 26.0, *), isSpatialSceneEnabled {
                                        // 3D 模式下不需要 overlay，因为热区已经在 SpatialBackgroundView 内部了
                                        EmptyView()
                                    } else {
                                        hotspotContent(geometry: geometry)
                                    }
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
                // 动态获取背景图尺寸，适配宽屏图片
                if let image = UIImage(named: currentBackgroundImageName) {
                    self.imageSize = image.size
                }
                
                // 强制设置 UITabBar 为完全透明
                let appearance = UITabBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundColor = .clear
                appearance.shadowImage = UIImage()
                appearance.backgroundImage = UIImage()
                
                UITabBar.appearance().standardAppearance = appearance
                if #available(iOS 26.0, *) {
                    UITabBar.appearance().scrollEdgeAppearance = appearance
                }
            }
            .onDisappear {
            // 恢复默认的半透明背景
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            
            UITabBar.appearance().standardAppearance = appearance
            if #available(iOS 26.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
        }
        .onAppear {
            // 确保视频播放状态已重置，防止交互锁死
            if isPlayingOpeningAnimation {
                isPlayingOpeningAnimation = false
            }
        }
        }
    }
    
    @ViewBuilder
    private func hotspotContent(geometry: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            // 1. OOTD (穿搭手帐) - 最左侧
            InteractionHotspot(rect: CGRect(x: 0.08, y: 0.1, width: 0.12, height: 0.8), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots, debugColor: .orange, label: "穿搭手帐", labelStyle: .horizontal(angle: -28), labelPosition: CGPoint(x: 0.17, y: 0.86)) {
                tabNavigationManager.markNavigatingInsideSmallWorld()
                destination = .ootd
            }
            
            // 2. 衣橱 (少女衣橱)
            InteractionHotspot(rect: CGRect(x: 0.41, y: 0.06, width: 0.155, height: 0.7), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots, label: "少女衣橱", labelPosition: CGPoint(x: 0.4, y: 0.38)) {
                withAnimation(.easeIn(duration: 0.5)) {
                    isPlayingOpeningAnimation = true
                }
            }
            
            // 3. 猪 (来财)
            InteractionHotspot(rect: CGRect(x: 0.72, y: 0.43, width: 0.12, height: 0.35), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots, label: "马上来财", labelPosition: CGPoint(x: 0.85, y: 0.72)) {
                tabNavigationManager.markNavigatingInsideSmallWorld()
                destination = .wealth
            }
            
            // 4. 墙上的日历 (梦裙日历)
            if shouldShowCalendar {
                CalendarHotspot(rect: CGRect(x: 0.61, y: 0.155, width: 0.15, height: 0.23), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots, label: "梦裙日历", labelPosition: CGPoint(x: 0.77, y: 0.27)) {
                    tabNavigationManager.markNavigatingInsideSmallWorld()
                    destination = .calendar
                }
            }
            
            // 5. 尾款天使 (衣橱右边)
            InteractionHotspot(rect: CGRect(x: 0.6, y: 0.42, width: 0.07, height: 0.12), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots, debugColor: .purple, label: "尾款天使", labelStyle: .horizontal(angle: 0), labelPosition: CGPoint(x: 0.635, y: 0.56)) {
                selectedTab = 0
                homeTab = .depositPlan
            }

            // 6. 拼豆工坊
            InteractionHotspot(rect: CGRect(x: 0.85, y: 0.15, width: 0.1, height: 0.15), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots, debugColor: .pink, label: "拼豆工坊", labelStyle: .horizontal(angle: -15), labelPosition: CGPoint(x: 0.92, y: 0.32)) {
                tabNavigationManager.markNavigatingInsideSmallWorld()
                destination = .perler
            }

            // 中心锚点，用于初始定位
            Color.clear
                .frame(width: 1, height: 1)
                .position(x: (geometry.size.height * (imageSize.width / imageSize.height)) / 2,
                          y: geometry.size.height / 2)
                .id("centerAnchor")
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
    var label: String? = nil
    var labelStyle: SmallWorldLabelStyle = .vertical(angle: FrenchRetroSmallWorldView.verticalLabelRotation)
    var labelPosition: CGPoint? = nil // 独立的标签位置 (Normalized 0-1)
    let action: () -> Void
    
    var body: some View {
        let width = geometry.size.height * (imageSize.width / imageSize.height)
        let height = geometry.size.height
        
        ZStack {
            // 热区本体
            Button(action: {
                print("[FrenchRetroSmallWorldView] 热区点击, 坐标: (\(rect.minX), \(rect.minY))")
                action()
            }) {
                if showDebug {
                    Rectangle()
                        .fill(debugColor.opacity(0.3))
                        .border(debugColor)
                } else {
                    // 修复：使用极低的透明度而非 clear，确保首次加载时按钮可点击
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                }
            }
            .frame(width: max(1, rect.width * width), height: max(1, rect.height * height))
            .position(x: (rect.minX + rect.width/2) * width, y: (rect.minY + rect.height/2) * height)
            
            // 独立控制的悬浮文字
            if let label = label {
                // 如果没有指定 labelPosition，默认使用热区中心
                let labelPos = labelPosition ?? CGPoint(x: rect.midX, y: rect.midY)
                
                FloatingTextLabel(text: label, style: labelStyle)
                    .allowsHitTesting(false)
                    .position(x: labelPos.x * width, y: labelPos.y * height)
            }
        }
        // 移除外层的 frame 和 offset，改为内部绝对定位，以便热区和文字可以分离
        .frame(width: width, height: height)
    }
}



/// 日历专属热区，带容器跟随效果
struct CalendarHotspot: View {
    let rect: CGRect
    let geometry: GeometryProxy
    let imageSize: CGSize
    var showDebug: Bool = false
    var label: String? = nil
    var labelStyle: SmallWorldLabelStyle = .vertical(angle: FrenchRetroSmallWorldView.verticalLabelRotation)
    var labelPosition: CGPoint? = nil // 独立的标签位置 (Normalized 0-1)
    let action: () -> Void
    
    // 监听数据变化
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) private var allClothings: [Clothing]
    
    var body: some View {
        let width = geometry.size.height * (imageSize.width / imageSize.height)
        let height = geometry.size.height
        
        // 计算热区实际尺寸
        let hotspotWidth = rect.width * width
        let hotspotHeight = rect.height * height
        
        ZStack {
            // 热区本体 (包含日历内容)
            ZStack {
                // 随动内容：当月界面预览
                calendarContent
                    .frame(width: hotspotWidth, height: hotspotHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                    )
                
                // 点击跳转
                Button(action: {
                    print("[FrenchRetroSmallWorldView] 日历热区点击, 坐标: (\(rect.minX), \(rect.minY))")
                    action()
                }) {
                    if showDebug {
                        Rectangle()
                            .fill(Color.blue.opacity(0.3))
                            .border(Color.blue)
                    } else {
                        // 修复：使用极低的透明度而非 clear，确保首次加载时按钮可点击
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                    }
                }
            }
            .frame(width: hotspotWidth, height: hotspotHeight)
            .position(x: (rect.minX + rect.width/2) * width, y: (rect.minY + rect.height/2) * height)
            
            // 独立控制的悬浮文字
            if let label = label {
                let labelPos = labelPosition ?? CGPoint(x: rect.midX, y: rect.midY)
                
                FloatingTextLabel(text: label, style: labelStyle)
                    .allowsHitTesting(false)
                    .position(x: labelPos.x * width, y: labelPos.y * height)
            }
        }
        .frame(width: width, height: height)
    }
    
    // 莫奈儿粉色系
    private let monetPink = Color(red: 0.96, green: 0.82, blue: 0.84)
    private let monetDarkPink = Color(red: 0.85, green: 0.65, blue: 0.68)
    
    private var calendarContent: some View {
        let today = Date()
        let calendar = Calendar.current
        let month = calendar.component(.month, from: today)
        // 获取当月日期数据
        let days = CalendarHelper.shared.generateDates(for: today)
        
        // 获取当前月的时间范围，用于过滤数据
        let startOfMonth = CalendarHelper.shared.firstOfMonth(today)
        let daysInMonth = CalendarHelper.shared.daysInMonth(today)
        let endOfMonth = calendar.date(byAdding: .day, value: daysInMonth, to: startOfMonth)!
        
        // 数据结构定义：记录每天应该显示什么
        enum DayContent {
            case thumbnail(Clothing) // 显示裙子缩略图
            case circleNumber // 显示带圈数字
        }
        
        // 预处理有事件的日期 -> 裙子
        let eventMap: [Date: DayContent] = {
            var map = [Date: DayContent]()
            
            for clothing in allClothings {
                // 1. 只看尾款天使
                guard clothing.isDepositPlan else { continue }
                
                // 2. 必须有尾款日期
                if let start = clothing.finalPaymentDate {
                    let startDate = calendar.startOfDay(for: start)
                    
                    if let end = clothing.finalPaymentEndDate {
                        let endDate = calendar.startOfDay(for: end)
                        
                        // 优化：如果整个时间段都不在当前月范围内，直接跳过
                        // 只要有一部分在当前月，就需要处理
                        if endDate < startOfMonth || startDate > endOfMonth {
                            continue
                        }
                        
                        // 优先级1：尾款结束日期 (显示缩略图)
                        map[endDate] = .thumbnail(clothing)
                        
                        // 优先级2：尾款开始日期 (显示缩略图)
                        if startDate != endDate {
                            if map[startDate] == nil {
                                map[startDate] = .thumbnail(clothing)
                            }
                            
                            // 处理中间日期 (显示带圈数字)
                            var curr = calendar.date(byAdding: .day, value: 1, to: startDate)!
                            while curr < endDate {
                                // 性能优化：只记录当前月范围内的日期
                                // 虽然 map 存了也没事，但过滤一下更稳妥
                                if curr >= startOfMonth && curr <= endOfMonth {
                                    if map[curr] == nil {
                                        map[curr] = .circleNumber
                                    }
                                }
                                curr = calendar.date(byAdding: .day, value: 1, to: curr)!
                            }
                        }
                        
                    } else {
                        // 只有开始日期（没有结束日期），视为单点事件
                        if startDate >= startOfMonth && startDate <= endOfMonth {
                            if map[startDate] == nil {
                                map[startDate] = .thumbnail(clothing)
                            }
                        }
                    }
                }
            }
            return map
        }()
        
        return GeometryReader { geo in
            VStack(spacing: 0) {
                // 莫奈儿粉月份标题条
                Text("\(month)月")
                    .font(.system(size: max(6, geo.size.height * 0.08), weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: geo.size.height * 0.12)
                    .background(monetDarkPink.opacity(0.9)) // 使用深一点的莫奈儿粉
                    .cornerRadius(2, corners: [.topLeft, .topRight])
                
                // 日期网格
                let rows = 6
                let cols = 7
                let cellWidth = geo.size.width / CGFloat(cols)
                let cellHeight = (geo.size.height * 0.88) / CGFloat(rows)
                // 字体大小自适应
                let fontSize = min(cellWidth, cellHeight) * 0.35
                
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: 7), spacing: 0) {
                    ForEach(days) { dayObj in
                        if dayObj.isCurrentMonth {
                            let dateStart = calendar.startOfDay(for: dayObj.date)
                            let content = eventMap[dateStart]
                            let isToday = dayObj.isToday
                            let dayNum = CalendarHelper.shared.dayOfMonth(dayObj.date)
                            
                            ZStack {
                                // 背景网格线
                                Rectangle()
                                    .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
                                
                                switch content {
                                case .thumbnail(let clothing):
                                    if let imagePath = clothing.imagePaths.first {
                                        // 显示缩略图
                                        AsyncDownsampledImage(
                                            fileName: imagePath,
                                            targetSize: CGSize(width: 20, height: 20), // 小图
                                            content: { uiImage in
                                                Image(uiImage: uiImage)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            },
                                            placeholder: {
                                                monetPink.opacity(0.5)
                                            }
                                        )
                                        .frame(width: cellWidth * 0.9, height: cellHeight * 0.9)
                                        .clipped()
                                        .cornerRadius(2)
                                        .overlay(
                                            // 如果是今天，添加深莫奈儿粉色加粗方框
                                            RoundedRectangle(cornerRadius: 2)
                                                .stroke(monetDarkPink, lineWidth: isToday ? 2 : 0)
                                        )
                                    } else {
                                        // 有数据但无图，显示莫奈儿粉方块
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(monetPink)
                                            .frame(width: cellWidth * 0.8, height: cellHeight * 0.8)
                                            .overlay(
                                                // 如果是今天，添加深莫奈儿粉色加粗方框
                                                RoundedRectangle(cornerRadius: 2)
                                                    .stroke(monetDarkPink, lineWidth: isToday ? 2 : 0)
                                            )
                                    }
                                    
                                case .circleNumber:
                                    // 显示带圈数字 (中间日期)
                                    Circle()
                                        .fill(monetPink)
                                        .frame(width: min(cellWidth, cellHeight) * 0.7)
                                    
                                    Text("\(dayNum)")
                                        .font(.system(size: fontSize, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                case nil:
                                    // 正常数字
                                    if isToday {
                                        Circle()
                                            .fill(monetDarkPink)
                                            .frame(width: min(cellWidth, cellHeight) * 0.7)
                                        
                                        Text("\(dayNum)")
                                            .font(.system(size: fontSize, weight: .bold))
                                            .foregroundColor(.white)
                                    } else {
                                        Text("\(dayNum)")
                                            .font(.system(size: fontSize))
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            .frame(width: cellWidth, height: cellHeight)
                        } else {
                            Color.clear
                                .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
        }
    }
}


#Preview {
    struct PreviewWrapper: View {
        @State var selectedTab = 1
        @State var homeTab: HomeTab = .wardrobe
        @State var destination: SmallWorldDestination = .menu
        @State var isPlayingOpeningAnimation = false
        
        var body: some View {
            FrenchRetroSmallWorldView(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination,
                isPlayingOpeningAnimation: $isPlayingOpeningAnimation
            )
            .task {
                // 预览模式下强制重置资源状态，确保看到最新图片
                SpatialAssetManager.shared.clearCache(for: "small_world_bg_normal")
                SpatialAssetManager.shared.clearCache(for: "small_world_bg_sun")
            }
        }
    }
    return PreviewWrapper()
}


