import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 轮盘配置（统一管理角度范围）
enum WheelConfig {
    // 轮盘角度范围（以正左方为0°，顺时针为正）
    static let startAngle: Double = -135  // 左边界
    static let endAngle: Double = -45     // 右边界
    static var totalAngle: Double { endAngle - startAngle }  // 总角度范围

    // 内层一级菜单配置
    static let innerMenuCount = 3
    static var innerMenuStep: Double { totalAngle / Double(innerMenuCount - 1) }

    // 外层二级菜单配置
    static let outerMenuPadding: Double = 5  // 边距
    static var outerMenuTotalAngle: Double { totalAngle - outerMenuPadding * 2 }
}

// MARK: - 轮盘菜单数据模型
struct WheelMenuCategory: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let items: [WheelMenuItem]
}

struct WheelMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let destination: SmallWorldDestination
    let color: Color
}

struct SmallWorldMenuOverlay: View {
    @Binding var selectedTab: Int
    @Binding var smallWorldDestination: SmallWorldDestination
    @Binding var homeTab: HomeTab

    @Environment(\.scenePhase) private var scenePhase

    @State private var showMenu = false
    @State private var pressProgress: CGFloat = 0.0
    @State private var isPressing: Bool = false
    @State private var didLongPressTrigger: Bool = false
    @State private var menuOrigin: CGPoint = .zero
    @State private var startLocation: CGPoint = .zero
    @State private var timer: Timer?
    private let longPressDuration: TimeInterval = 0.35

    // 轮盘旋转状态
    @State private var outerRotation: Double = 0
    @State private var lastOuterRotation: Double = 0
    @State private var selectedCategoryIndex: Int = 0

    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var petDataManager = PetDataManager.shared

    private let isLowMemoryDevice: Bool = {
        return ProcessInfo.processInfo.physicalMemory < 4 * 1024 * 1024 * 1024
    }()

    private var isIPad: Bool {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    // 莫妮卡粉色
    private let monicaPink = Color(red: 1.0, green: 0.41, blue: 0.71)

    // 常用菜单设置管理器
    @ObservedObject private var favoriteMenuManager = FavoriteMenuSettingsManager.shared

    // MARK: - 菜单数据
    private var categories: [WheelMenuCategory] {
        [
            // 常用（根据用户设置动态生成）
            WheelMenuCategory(
                title: "常用",
                icon: "star.fill",
                items: favoriteMenuItems
            ),
            // 乐玩
            WheelMenuCategory(
                title: "乐玩",
                icon: "gamecontroller.fill",
                items: [
                    WheelMenuItem(title: "马上来财", icon: "yensign.circle", destination: .wealth, color: Color(red: 1.0, green: 0.84, blue: 0.0)),
                    WheelMenuItem(title: "穿搭手帐", icon: "book.closed", destination: .ootd, color: Color(red: 1.0, green: 0.5, blue: 0.7)),
                    WheelMenuItem(title: "拼豆工坊", icon: "circle.grid.2x2", destination: .perler, color: Color(red: 1.0, green: 0.55, blue: 0.75)),
                    WheelMenuItem(title: "梦裙日历", icon: "calendar", destination: .calendar, color: Color(red: 0.80, green: 0.65, blue: 0.80)),
                ]
            ),
            // 大世界
            WheelMenuCategory(
                title: "大世界",
                icon: "globe",
                items: [
                    WheelMenuItem(title: "大世界", icon: "airplane", destination: .bigWorld, color: Color(red: 0.4, green: 0.8, blue: 0.9)),
                ]
            ),
        ]
    }

    // 根据用户设置生成常用菜单项
    private var favoriteMenuItems: [WheelMenuItem] {
        favoriteMenuManager.selectedItems.map { item in
            switch item {
            case .wardrobe:
                return WheelMenuItem(title: "衣橱", icon: "cabinet.fill", destination: .wardrobe, color: Color(red: 1.0, green: 0.41, blue: 0.71))
            case .finalPayment:
                return WheelMenuItem(title: "尾款天使", icon: "tag.fill", destination: .depositPlan, color: Color(red: 1.0, green: 0.07, blue: 0.58))
            case .pet:
                return WheelMenuItem(title: petDataManager.status.displayName, icon: "pawprint", destination: .pet, color: Color(red: 1.0, green: 0.65, blue: 0.55))
            case .ootd:
                return WheelMenuItem(title: "OOTD", icon: "book.pages", destination: .ootdDefaultBook, color: Color(red: 1.0, green: 0.41, blue: 0.71))
            case .fashionJournal:
                return WheelMenuItem(title: "穿搭手帐", icon: "book.closed", destination: .ootd, color: Color(red: 1.0, green: 0.53, blue: 0.76))
            case .smallWorld:
                return WheelMenuItem(title: "小世界", icon: "map", destination: .menu, color: Color(red: 0.4, green: 0.8, blue: 0.9))
            case .wealth:
                return WheelMenuItem(title: "来财", icon: "yensign.circle", destination: .wealth, color: Color(red: 1.0, green: 0.84, blue: 0.0))
            case .perler:
                return WheelMenuItem(title: "拼豆", icon: "circle.grid.2x2", destination: .perler, color: Color(red: 1.0, green: 0.55, blue: 0.75))
            case .calendar:
                return WheelMenuItem(title: "梦裙日历", icon: "calendar", destination: .calendar, color: Color(red: 0.80, green: 0.65, blue: 0.80))
            case .bigWorld:
                return WheelMenuItem(title: "大世界", icon: "airplane", destination: .bigWorld, color: Color(red: 0.4, green: 0.8, blue: 0.9))
            case .recycleBin:
                return WheelMenuItem(title: "回收站", icon: "trash.fill", destination: .recycleBin, color: Color(red: 0.5, green: 0.5, blue: 0.5))
            }
        }
    }

    // 布局参数
    private func getInnerRadius(geometry: GeometryProxy) -> CGFloat {
        let screenWidth = geometry.size.width
        if screenWidth < 380 { return 70 }
        else if screenWidth > 700 { return 100 }
        else { return 85 }
    }

    private func getOuterRadius(geometry: GeometryProxy) -> CGFloat {
        let screenWidth = geometry.size.width
        if screenWidth < 380 { return 160 }
        else if screenWidth > 700 { return 220 }
        else { return 190 }
    }

    var body: some View {
        GeometryReader { geometry in
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            let safeAreaTop = geometry.safeAreaInsets.top
            let tabBarHeight = 65.0 + safeAreaBottom
            let topBarHeight = 65.0 + safeAreaTop
            let triggerHeight = isIPad ? topBarHeight : tabBarHeight
            let triggerAreaWidth = min(geometry.size.width / 4, 100)
            let smallWorldTabCenterX = geometry.size.width * 0.375
            let smallWorldTabCenterY = isIPad ? triggerHeight / 2 : geometry.size.height - triggerHeight / 2

            ZStack(alignment: .bottom) {
                // 背景遮罩
                if showMenu {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture { closeMenu() }
                        .transition(.opacity)
                }

                // 轮盘菜单
                ZStack {
                    // 外层二级菜单
                    OuterWheelView(
                        categories: categories,
                        selectedIndex: selectedCategoryIndex,
                        rotation: outerRotation,
                        radius: getOuterRadius(geometry: geometry),
                        isLowMemoryDevice: isLowMemoryDevice,
                        monicaPink: monicaPink,
                        onItemSelected: { item in
                            selectItem(item.destination)
                        }
                    )
                    .position(x: menuOrigin.x, y: menuOrigin.y)
                    .opacity(showMenu ? 1 : 0)
                    .scaleEffect(showMenu ? 1 : 0.1)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showMenu)

                    // 内层固定分类菜单（带轮廓线和背景）
                    InnerWheelView(
                        categories: categories,
                        selectedIndex: $selectedCategoryIndex,
                        radius: getInnerRadius(geometry: geometry),
                        isLowMemoryDevice: isLowMemoryDevice,
                        monicaPink: monicaPink
                    )
                    .position(x: menuOrigin.x, y: menuOrigin.y)
                    .opacity(showMenu ? 1 : 0)
                    .scaleEffect(showMenu ? 1 : 0.1)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showMenu)
                    .onChange(of: selectedCategoryIndex) { newIndex in
                        // 内层选中变化时，震动反馈
                        hapticManager.playUIFeedback(intensity: 0.5, sharpness: 0.5, fallbackStyle: .light)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(showMenu)

                // 长按进度指示器
                if isPressing && !showMenu {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 4)
                            .frame(width: 60, height: 60)

                        Circle()
                            .trim(from: 0, to: pressProgress)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        monicaPink,
                                        Color(red: 0.85, green: 0.75, blue: 0.85)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 60, height: 60)
                            .shadow(color: monicaPink.opacity(0.5), radius: 5)
                    }
                    .position(x: smallWorldTabCenterX, y: smallWorldTabCenterY)
                }

                // 触发区域
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .frame(width: triggerAreaWidth, height: triggerHeight)
                    .position(x: smallWorldTabCenterX, y: smallWorldTabCenterY)
                    .onLongPressGesture(
                        minimumDuration: longPressDuration,
                        maximumDistance: 20,
                        pressing: { isPressing in
                            if isPressing {
                                self.isPressing = true
                                self.startLocation = CGPoint(x: smallWorldTabCenterX, y: smallWorldTabCenterY)
                                #if canImport(UIKit)
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                #endif
                                startLongPressTimer()
                            } else {
                                handlePressEnded()
                            }
                        },
                        perform: {
                            triggerMenu(smallWorldTabCenterX: smallWorldTabCenterX, smallWorldTabCenterY: smallWorldTabCenterY)
                        }
                    )
                    .onTapGesture {
                        if showMenu {
                            closeMenu()
                        } else {
                            handleTapAction()
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background || newPhase == .inactive {
                closeMenu()
            }
        }
        .onChange(of: selectedTab) { newValue in
            if newValue != 1 {
                closeMenu()
            }
        }
    }

    // MARK: - 内层固定轮盘（右上角90度）
    struct InnerWheelView: View {
        let categories: [WheelMenuCategory]
        @Binding var selectedIndex: Int
        let radius: CGFloat
        let isLowMemoryDevice: Bool
        let monicaPink: Color

        var body: some View {
            ZStack {
                // 轮盘背景（淡淡的莫妮卡粉）
                WheelBackground(
                    radius: radius + 35,
                    startAngle: WheelConfig.startAngle,
                    endAngle: WheelConfig.endAngle,
                    monicaPink: monicaPink
                )

                // 三个分类分布在-45°到45°范围内
                ForEach(0..<WheelConfig.innerMenuCount) { index in
                    let angle = WheelConfig.startAngle + Double(index) * WheelConfig.innerMenuStep
                    let radians = angle * .pi / 180
                    let x = radius * cos(radians)
                    let y = radius * sin(radians)

                    CategoryBubble(
                        category: categories[index],
                        isSelected: selectedIndex == index,
                        isLowMemoryDevice: isLowMemoryDevice,
                        monicaPink: monicaPink
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedIndex = index
                        }
                    }
                    .offset(x: x, y: y)
                }
            }
        }
    }

    // MARK: - 外层二级菜单（右上角90度）
    struct OuterWheelView: View {
        let categories: [WheelMenuCategory]
        let selectedIndex: Int
        let rotation: Double
        let radius: CGFloat
        let isLowMemoryDevice: Bool
        let monicaPink: Color
        let onItemSelected: (WheelMenuItem) -> Void

        var body: some View {
            ZStack {
                // 根据选中的分类显示对应的二级菜单
                let items = categories[selectedIndex].items
                ForEach(items.indices, id: \.self) { itemIndex in
                    // 在-45°到45°范围内分布
                    let itemStartAngle = WheelConfig.startAngle + WheelConfig.outerMenuPadding
                    let step = items.count > 1 ? WheelConfig.outerMenuTotalAngle / Double(items.count - 1) : 0
                    let angle = itemStartAngle + Double(itemIndex) * step
                    let radians = angle * .pi / 180
                    let x = radius * cos(radians)
                    let y = radius * sin(radians)

                    ItemBubble(
                        item: items[itemIndex],
                        isLowMemoryDevice: isLowMemoryDevice
                    ) {
                        onItemSelected(items[itemIndex])
                    }
                    .offset(x: x, y: y)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7).delay(Double(itemIndex) * 0.03), value: selectedIndex)
                }
            }
        }
    }

    // MARK: - 轮盘背景
    struct WheelBackground: View {
        let radius: CGFloat
        let startAngle: Double
        let endAngle: Double
        let monicaPink: Color

        var body: some View {
            // 淡淡的莫妮卡粉背景扇形
            SectorShape(
                radius: radius,
                startAngle: .degrees(startAngle),
                endAngle: .degrees(endAngle)
            )
            .fill(monicaPink.opacity(0.08))
        }
    }

    // MARK: - 扇形形状
    struct SectorShape: Shape {
        let radius: CGFloat
        let startAngle: Angle
        let endAngle: Angle

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let center = CGPoint(x: rect.midX, y: rect.midY)

            path.move(to: center)
            path.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )
            path.closeSubpath()

            return path
        }
    }

    // MARK: - 分类气泡
    struct CategoryBubble: View {
        let category: WheelMenuCategory
        let isSelected: Bool
        let isLowMemoryDevice: Bool
        let monicaPink: Color
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? monicaPink : Color.white)
                            .frame(width: 50, height: 50)
                            .shadow(
                                color: isSelected ? monicaPink.opacity(0.4) : Color.black.opacity(0.1),
                                radius: isSelected ? 8 : 4,
                                x: 0,
                                y: isSelected ? 4 : 2
                            )

                        Image(systemName: category.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(isSelected ? .white : Color(red: 0.4, green: 0.4, blue: 0.4))
                    }

                    Text(category.title)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? monicaPink : .primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            if isLowMemoryDevice {
                                Color.white.opacity(0.9)
                            } else {
                                Rectangle().fill(.ultraThinMaterial)
                            }
                        }
                        .clipShape(Capsule())
                }
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }

    // MARK: - 功能项气泡
    struct ItemBubble: View {
        let item: WheelMenuItem
        let isLowMemoryDevice: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(item.color)
                            .frame(width: 56, height: 56)
                            .shadow(color: item.color.opacity(isLowMemoryDevice ? 0 : 0.4), radius: isLowMemoryDevice ? 0 : 8, x: 0, y: 4)

                        Image(systemName: item.icon)
                            .font(.title2)
                            .foregroundColor(.white)
                    }

                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            if isLowMemoryDevice {
                                Color.white.opacity(0.95)
                            } else {
                                Rectangle().fill(.regularMaterial)
                            }
                        }
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(isLowMemoryDevice ? 0 : 0.1), radius: isLowMemoryDevice ? 0 : 2, x: 0, y: 1)
                }
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }

    private func startLongPressTimer() {
        pressProgress = 0.0
        didLongPressTrigger = false

        withAnimation(.linear(duration: longPressDuration)) {
            pressProgress = 1.0
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: longPressDuration + 0.1, repeats: false) { _ in
            if !self.showMenu && self.isPressing {
                DispatchQueue.main.async {
                    self.isPressing = false
                    self.pressProgress = 0.0
                }
            }
        }
    }

    private func handleTapAction() {
        DispatchQueue.main.async {
            if self.selectedTab == 1 {
                if self.smallWorldDestination != .menu {
                    self.smallWorldDestination = .menu
                }
            } else {
                self.selectedTab = 1
            }
        }
    }

    private func handlePressEnded() {
        timer?.invalidate()
        timer = nil

        if didLongPressTrigger {
            didLongPressTrigger = false
            isPressing = false
            pressProgress = 0.0
            return
        }

        isPressing = false
        withAnimation(.easeOut(duration: 0.2)) {
            pressProgress = 0.0
        }
    }

    private func triggerMenu(smallWorldTabCenterX: CGFloat, smallWorldTabCenterY: CGFloat) {
        hapticManager.playUIFeedback(intensity: 0.8, sharpness: 0.7, fallbackStyle: .heavy)
        didLongPressTrigger = true

        // 重置轮盘状态
        selectedCategoryIndex = 0
        outerRotation = 0
        lastOuterRotation = 0

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            menuOrigin = CGPoint(x: smallWorldTabCenterX, y: smallWorldTabCenterY)
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showMenu = true
        }

        isPressing = false
        pressProgress = 0.0
    }

    private func closeMenu() {
        withAnimation(.easeOut(duration: 0.2)) {
            showMenu = false
        }
    }

    private func selectItem(_ dest: SmallWorldDestination) {
        withAnimation(.easeOut(duration: 0.15)) {
            showMenu = false
        }

        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                switch dest {
                case .wardrobe:
                    // 跳转到衣橱 Tab
                    selectedTab = 0
                    homeTab = .wardrobe
                case .depositPlan:
                    // 跳转到尾款天使 Tab
                    selectedTab = 0
                    homeTab = .depositPlan
                default:
                    // 其他功能在小世界 Tab 内跳转
                    selectedTab = 1
                    smallWorldDestination = dest
                }
            }
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
