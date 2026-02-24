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

    // 单层菜单配置
    static let menuPadding: Double = 10  // 边距
    static var menuTotalAngle: Double { totalAngle - menuPadding * 2 }
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
    @State private var wheelRotation: Double = 0

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

    // MARK: - 菜单数据（单层结构，只显示常用菜单）
    private var menuItems: [WheelMenuItem] {
        favoriteMenuItems
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
                return WheelMenuItem(title: "快捷OOTD", icon: "book.pages", destination: .ootdDefaultBook, color: Color(red: 1.0, green: 0.41, blue: 0.71))
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
                return WheelMenuItem(title: "蓝星OL", icon: "globe.asia.australia", destination: .bigWorld, color: Color(red: 0.4, green: 0.8, blue: 0.9))
            case .recycleBin:
                return WheelMenuItem(title: "回收站", icon: "trash.fill", destination: .recycleBin, color: Color(red: 0.5, green: 0.5, blue: 0.5))
            }
        }
    }

    // 布局参数
    private func getMenuRadius(geometry: GeometryProxy) -> CGFloat {
        let screenWidth = geometry.size.width
        if screenWidth < 380 { return 140 }
        else if screenWidth > 700 { return 200 }
        else { return 170 }
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

                // 轮盘菜单（单层结构）
                ZStack {
                    // 单层菜单
                    WheelMenuView(
                        items: menuItems,
                        radius: getMenuRadius(geometry: geometry),
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

    // MARK: - 单层轮盘菜单
    struct WheelMenuView: View {
        let items: [WheelMenuItem]
        let radius: CGFloat
        let isLowMemoryDevice: Bool
        let monicaPink: Color
        let onItemSelected: (WheelMenuItem) -> Void

        // 根据菜单数量计算自适应大小
        private func getAdaptiveSizes(count: Int) -> (iconSize: CGFloat, fontSize: CGFloat, circleSize: CGFloat) {
            switch count {
            case 1:
                return (28, 14, 64)
            case 2:
                return (26, 13, 60)
            case 3:
                return (24, 12, 58)
            case 4:
                return (22, 11, 54)
            case 5:
                return (22, 11, 54)
            default:
                return (22, 11, 54)
            }
        }

        var body: some View {
            let sizes = getAdaptiveSizes(count: items.count)

            ZStack {
                // 轮盘背景（淡淡的莫妮卡粉）
                WheelBackground(
                    radius: radius + 40,
                    startAngle: WheelConfig.startAngle,
                    endAngle: WheelConfig.endAngle,
                    monicaPink: monicaPink
                )

                // 5个菜单项使用上下两排布局：下面2个，上面3个
                if items.count == 5 {
                    // 下排：2个菜单项（角度 -120° 到 -60°）
                    ForEach(0..<2) { index in
                        let angle = -120 + Double(index) * 60
                        let radians = angle * .pi / 180
                        let innerRadius = radius * 0.6
                        let x = innerRadius * cos(radians)
                        let y = innerRadius * sin(radians)

                        ItemBubble(
                            item: items[index],
                            isLowMemoryDevice: isLowMemoryDevice,
                            iconSize: sizes.iconSize,
                            fontSize: sizes.fontSize,
                            circleSize: sizes.circleSize
                        ) {
                            onItemSelected(items[index])
                        }
                        .offset(x: x, y: y)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7).delay(Double(index) * 0.03), value: items.count)
                    }

                    // 上排：3个菜单项（角度 -135° 到 -45°）
                    ForEach(2..<5) { index in
                        let angle = -135 + Double(index - 2) * 45
                        let radians = angle * .pi / 180
                        let x = radius * cos(radians)
                        let y = radius * sin(radians)

                        ItemBubble(
                            item: items[index],
                            isLowMemoryDevice: isLowMemoryDevice,
                            iconSize: sizes.iconSize,
                            fontSize: sizes.fontSize,
                            circleSize: sizes.circleSize
                        ) {
                            onItemSelected(items[index])
                        }
                        .offset(x: x, y: y)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7).delay(Double(index) * 0.03), value: items.count)
                    }
                } else {
                    // 其他数量使用原来的弧形布局
                    ForEach(items.indices, id: \.self) { index in
                        let itemStartAngle = WheelConfig.startAngle + WheelConfig.menuPadding
                        let step = items.count > 1 ? WheelConfig.menuTotalAngle / Double(items.count - 1) : 0
                        let angle = itemStartAngle + Double(index) * step
                        let radians = angle * .pi / 180
                        let x = radius * cos(radians)
                        let y = radius * sin(radians)

                        ItemBubble(
                            item: items[index],
                            isLowMemoryDevice: isLowMemoryDevice,
                            iconSize: sizes.iconSize,
                            fontSize: sizes.fontSize,
                            circleSize: sizes.circleSize
                        ) {
                            onItemSelected(items[index])
                        }
                        .offset(x: x, y: y)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7).delay(Double(index) * 0.03), value: items.count)
                    }
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



    // MARK: - 功能项气泡
    struct ItemBubble: View {
        let item: WheelMenuItem
        let isLowMemoryDevice: Bool
        let iconSize: CGFloat
        let fontSize: CGFloat
        let circleSize: CGFloat
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(item.color)
                            .frame(width: circleSize, height: circleSize)
                            .shadow(color: item.color.opacity(isLowMemoryDevice ? 0 : 0.4), radius: isLowMemoryDevice ? 0 : 8, x: 0, y: 4)

                        Image(systemName: item.icon)
                            .font(.system(size: iconSize, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Text(item.title)
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
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
        wheelRotation = 0

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
