//
//  SmallWorldView.swift
//  ItemManager
//
//  Created by Pink House Dev on 2/10/26.
//

import SwiftUI
import SwiftData
import UIKit // 导入 UIKit 以使用 UITabBar 等 API
import RealityKit
import CoreMotion

enum SmallWorldDestination {
    case menu
    case ootd
    case pet
    case wealth
    case calendar
}

struct SmallWorldView: View {
    @Binding var selectedTab: Int // MainTabView selection
    @Binding var homeTab: HomeTab // HomeView selection
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    
    // 图片原始尺寸 1919x1079
    @State private var imageSize = CGSize(width: 1919, height: 1079)
    @AppStorage("isSpatialSceneEnabled") private var isSpatialSceneEnabled = false
    
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
    
    // 根据时间动态获取背景图片名称
    private var currentBackgroundImageName: String {
        let hour = Calendar.current.component(.hour, from: Date())
        
        // 清晨: 5:00 - 9:00 (不包含 9:00)
        let isMorning = hour >= 5 && hour < 9
        
        // 黄昏: 16:00 - 19:00 (不包含 19:00)
        let isDusk = hour >= 16 && hour < 19
        
        if isMorning || isDusk {
            return "small_world_bg_sun"
        } else {
            return "small_world_bg_normal"
        }
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
                                        imageExtension: "png",
                                        onSelectOOTD: { destination = .ootd },
                                        onSelectWardrobe: {
                                            withAnimation(.easeIn(duration: 0.5)) {
                                                isPlayingOpeningAnimation = true
                                            }
                                        },
                                        onSelectWealth: { destination = .wealth },
                                        onSelectCalendar: { destination = .calendar },
                                        onSelectBalanceAngel: {
                                            selectedTab = 0
                                            homeTab = .depositPlan
                                        }
                                    )
                                } else {
                                    Image(currentBackgroundImageName) // 确保图片已添加至 Assets
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                }
                            }
                            .frame(width: geometry.size.height * (imageSize.width / imageSize.height), height: geometry.size.height)
                            .overlay(
                                    ZStack(alignment: .topLeading) {
                                        // 1. OOTD (今日穿搭) - 最左侧
                                        InteractionHotspot(rect: CGRect(x: 0.08, y: 0.1, width: 0.12, height: 0.8), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots, debugColor: .orange) {
                                            destination = .ootd
                                        }
                                        
                                        // 2. 衣橱 (少女衣橱)
                                        InteractionHotspot(rect: CGRect(x: 0.41, y: 0.06, width: 0.155, height: 0.7), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots) {
                                            withAnimation(.easeIn(duration: 0.5)) {
                                                isPlayingOpeningAnimation = true
                                            }
                                        }
                                        
                                        // 3. 猪 (来财)
                                        InteractionHotspot(rect: CGRect(x: 0.72, y: 0.43, width: 0.12, height: 0.35), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots) {
                                            destination = .wealth
                                        }
                                        
                                        // 4. 墙上的日历 (梦裙日历)
                                        if shouldShowCalendar {
                                            CalendarHotspot(rect: CGRect(x: 0.61, y: 0.155, width: 0.15, height: 0.23), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots) {
                                                destination = .calendar
                                            }
                                        }
                                        
                                        // 5. 尾款天使 (衣橱右边)
                                        InteractionHotspot(rect: CGRect(x: 0.6, y: 0.42, width: 0.07, height: 0.12), geometry: geometry, imageSize: imageSize, showDebug: showDebugHotspots, debugColor: .purple) {
                                            selectedTab = 0
                                            homeTab = .depositPlan
                                        }
                                        
                                        // 中心锚点，用于初始定位
                                        Color.clear
                                            .frame(width: 1, height: 1)
                                            .position(x: (geometry.size.height * (imageSize.width / imageSize.height)) / 2,
                                                      y: geometry.size.height / 2)
                                            .id("centerAnchor")
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
    let action: () -> Void
    
    var body: some View {
        let width = geometry.size.height * (imageSize.width / imageSize.height)
        let height = geometry.size.height
        
        Button(action: action) {
            if showDebug {
                Rectangle()
                    .fill(debugColor.opacity(0.3))
                    .border(debugColor)
            } else {
                Color.clear
                    .contentShape(Rectangle())
            }
        }
        .frame(width: rect.width * width, height: rect.height * height)
        .offset(x: rect.minX * width, y: rect.minY * height)
    }
}



/// 日历专属热区，带容器跟随效果
struct CalendarHotspot: View {
    let rect: CGRect
    let geometry: GeometryProxy
    let imageSize: CGSize
    var showDebug: Bool = false
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
            // 随动内容：当月界面预览
            // 使用白色半透明背景模拟纸张质感
            calendarContent
                .frame(width: hotspotWidth, height: hotspotHeight)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                )
            
            // 点击跳转
            Button(action: action) {
                if showDebug {
                    Rectangle()
                        .fill(Color.blue.opacity(0.3))
                        .border(Color.blue)
                } else {
                    Color.clear
                        .contentShape(Rectangle())
                }
            }
        }
        .frame(width: hotspotWidth, height: hotspotHeight)
        .offset(x: rect.minX * width, y: rect.minY * height)
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
            SmallWorldView(
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


// MARK: - iOS 26 Spatial Scene Support
// 以下代码实现了 iOS 26 的 Spatial Scene 效果。

@available(iOS 26.0, *)
struct SpatialBackgroundView: View {
    let imageName: String
    let imageExtension: String
    
    // 监听全局资源管理器
    @ObservedObject private var assetManager = SpatialAssetManager.shared
    
    // Binding to pass actions back to parent
    var onSelectOOTD: () -> Void
    var onSelectWardrobe: () -> Void
    var onSelectWealth: () -> Void
    var onSelectCalendar: () -> Void
    var onSelectBalanceAngel: () -> Void
    
    // 模拟陀螺仪视差效果（Mock 环境增强版）
    // 即使在 Mock 模式下，我们也希望看到背景的动态反馈
    @State private var motionManager = CMMotionManager()
    @State private var parallaxOffset: CGSize = .zero
    
    // 缓存背景图，避免 GeometryReader 重绘时反复 IO
    @State private var cachedBackgroundImage: UIImage?
    
    var body: some View {
        ZStack {
            if let spatialImage = assetManager.spatialImage {
                // 如果是真实环境，RealityView 会自动处理
                // 这里我们在 Mock 环境下增加手动视差模拟
                
                // 暂时禁用 RealityView 以避免 Mock 环境下的渲染错误日志
                // 在未来真实 iOS 26 环境下，可以恢复此代码块
                /*
                RealityView { content in
                    print("[SpatialBackgroundView] 初始化 RealityView")
                    
                    var presentation = ImagePresentationComponent(spatial3DImage: spatialImage)
                    presentation.desiredViewingMode = .spatial3D
                    
                    let entity = Entity()
                    entity.components.set(presentation)
                    
                    // --- 核心优化：将热区挂载到 3D 空间 ---
                    // 在真实 RealityKit 中，我们需要创建不可见的碰撞体 Entity，并将其位置与背景图中的物体对齐
                    // 这里的坐标 (x, y, z) 需要根据实际图片的 UV 映射来调试
                    
                    // 1. OOTD 热区
                    addSpatialHotspot(to: entity, name: "OOTD", position: [-0.3, 0, 0.1], size: [0.3, 0.8, 0.1], action: onSelectOOTD)
                    
                    // 2. 衣橱热区
                    addSpatialHotspot(to: entity, name: "Wardrobe", position: [-0.1, 0, 0.05], size: [0.3, 0.8, 0.1], action: onSelectWardrobe)
                    
                    // 3. 财富热区
                    addSpatialHotspot(to: entity, name: "Wealth", position: [0.3, -0.1, 0.2], size: [0.3, 0.3, 0.1], action: onSelectWealth)
                    
                    // 4. 日历热区
                    addSpatialHotspot(to: entity, name: "Calendar", position: [0.25, 0.2, 0.0], size: [0.2, 0.3, 0.1], action: onSelectCalendar)
                    
                    content.add(entity)
                }
                .overlay(
                    // 叠加一个调试层，仅在模拟器显示，证明进入了 3D 模式
                    VStack {
                        Spacer()
                        Text("Spatial Scene Active (Mock + Parallax)")
                            .font(.caption)
                            .padding(4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)
                            .padding()
                    }
                )
                */
                
                // Mock 回退渲染层：仅当 RealityKit 无法工作时（例如模拟器不支持）才生效
                // 在 Mock 环境下，我们恢复 CoreMotion 视差，作用于背景占位图
                // .background( // 移除 background 修饰符，直接作为主视图
                    GeometryReader { geo in
                        if let image = cachedBackgroundImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width * 1.15, height: geo.size.height * 1.15)
                                .offset(parallaxOffset)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                                .overlay(
                                    // 叠加交互热区 (2D Fallback)
                                    // 仅在 Mock 模式下启用，因为 RealityView 被禁用了
                                    ZStack(alignment: .topLeading) {
                                        // 这里需要手动转换归一化坐标到 GeometryReader 的 frame
                                        // 为简化演示，我们暂时省略热区重建，或者可以将原来的 InteractionHotspot 移回来
                                        // 但为了响应用户点击，我们必须添加热区
                                        
                                        // 1. OOTD
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .frame(width: geo.size.width * 0.15, height: geo.size.height * 0.7)
                                            .position(x: geo.size.width * 0.275, y: geo.size.height * 0.55) // 估算位置
                                            .onTapGesture(perform: onSelectOOTD)
                                            
                                        // 2. 衣橱
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .frame(width: geo.size.width * 0.2, height: geo.size.height * 0.8)
                                            .position(x: geo.size.width * 0.49, y: geo.size.height * 0.5)
                                            .onTapGesture(perform: onSelectWardrobe)
                                            
                                        // 3. 财富
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .frame(width: geo.size.width * 0.18, height: geo.size.height * 0.22)
                                            .position(x: geo.size.width * 0.79, y: geo.size.height * 0.56)
                                            .onTapGesture(perform: onSelectWealth)
                                            
                                        // 4. 日历
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .frame(width: geo.size.width * 0.13, height: geo.size.height * 0.21)
                                            .position(x: geo.size.width * 0.705, y: geo.size.height * 0.295)
                                            .onTapGesture(perform: onSelectCalendar)

                                        // 5. 尾款天使
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .frame(width: geo.size.width * 0.14, height: geo.size.height * 0.25)
                                            .position(x: geo.size.width * 0.64, y: geo.size.height * 0.525) // 0.57 + 0.14/2 = 0.64, 0.40 + 0.25/2 = 0.525
                                            .onTapGesture(perform: onSelectBalanceAngel)
                                    }
                                )
                        } else {
                            Color.black
                        }
                    }
                // )
                .onAppear {
                    // 加载并缓存图片
                    if cachedBackgroundImage == nil {
                        // 在后台线程加载图片
                        DispatchQueue.global(qos: .userInitiated).async {
                            if let image = UIImage(contentsOfFile: spatialImage.url.path) {
                                DispatchQueue.main.async {
                                    self.cachedBackgroundImage = image
                                }
                            }
                        }
                    }
                    startMotionUpdates()
                }
                .onDisappear { motionManager.stopDeviceMotionUpdates() }
                // 简单的淡入过渡
                .transition(.opacity.animation(.easeOut(duration: 0.8)))
                
            } else {
                // 加载占位
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(
                        ZStack {
                            Color.black.opacity(0.3)
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(.white)
                                Text("AI 空间数据生成中...")
                                    .font(.callout)
                                    .foregroundStyle(.white)
                            }
                        }
                    )
            }
        }
        .task {
            // 视图出现时，如果还没准备好，尝试再次触发预加载（防止 App 启动时没触发成功）
            if !assetManager.isReady {
                assetManager.preload(imageName: imageName, extension: imageExtension)
            }
        }
    }
    
    // 辅助函数：添加空间热区
    // 在 Mock 环境下，我们仅模拟这个函数签名，实际上无法在 iOS 平台添加真实的 RealityKit 碰撞体
    // 除非我们处于 visionOS 或未来的 iOS 26+ 环境
    private func addSpatialHotspot(to parent: Entity, name: String, position: SIMD3<Float>, size: SIMD3<Float>, action: @escaping () -> Void) {
        // 创建一个不可见的 ModelEntity 作为热区
        // 使用 UnlitMaterial 且 opacity 为 0，确保完全不可见且不产生高光
        // 注意：在 RealityKit 中，如果要响应输入，通常需要 CollisionComponent，
        // 而 ModelComponent 仅用于可视。这里为了消除白线，我们只保留 CollisionComponent (如果支持)，
        // 或者使用完全透明的材质。
        
        let material = UnlitMaterial(color: .clear)
        let hotspot = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [material]
        )
        
        // 进一步确保透明度为 0
        hotspot.components.set(OpacityComponent(opacity: 0.0))
        
        // 设置位置（相对于父实体）
        hotspot.position = position
        hotspot.name = name
        
        // 添加碰撞组件 (CollisionComponent)
        // 注意：在 Mock 环境下，RealityView 的 TapGesture 需要配合 SpatialTapGesture 才能生效
        // 这里仅作代码演示
        // hotspot.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
        // hotspot.components.set(InputTargetComponent())
        
        parent.addChild(hotspot)
    }
    
    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            // 如果设备不支持陀螺仪（如模拟器），使用简单的呼吸动画
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                parallaxOffset = CGSize(width: -20, height: -10)
            }
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 0.02 // 50Hz
        motionManager.startDeviceMotionUpdates(to: .main) { data, error in
            guard let data = data else { return }
            
            // 获取倾斜角度 (Roll & Pitch)
            let roll = CGFloat(data.attitude.roll)
            let pitch = CGFloat(data.attitude.pitch)
            
            // 计算位移：最大移动范围 30pt (稍微收敛一点，避免过度移动)
            let targetX = roll * 30
            let targetY = pitch * 30
            
            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8)) {
                self.parallaxOffset = CGSize(width: -targetX, height: targetY)
            }
        }
    }
}
