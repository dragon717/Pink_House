import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

enum WheelExpansionDirection {
    case upward
    case downward
}

// MARK: - 轮盘配置（统一管理角度范围）
enum WheelConfig {
    static let menuPadding: Double = 10

    static func leftAngle(for direction: WheelExpansionDirection) -> Double {
        switch direction {
        case .upward:
            return -135
        case .downward:
            return 135
        }
    }

    static func rightAngle(for direction: WheelExpansionDirection) -> Double {
        switch direction {
        case .upward:
            return -45
        case .downward:
            return 45
        }
    }

    static func backgroundStartAngle(for direction: WheelExpansionDirection) -> Double {
        min(leftAngle(for: direction), rightAngle(for: direction))
    }

    static func backgroundEndAngle(for direction: WheelExpansionDirection) -> Double {
        max(leftAngle(for: direction), rightAngle(for: direction))
    }
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
    @State private var menuExpansionProgress: CGFloat = 0
    @State private var menuHideWorkItem: DispatchWorkItem?
    @State private var startLocation: CGPoint = .zero
    @State private var timer: Timer?
    private let longPressDuration: TimeInterval = 0.35

    // 轮盘旋转状态
    @State private var wheelRotation: Double = 0

    // iOS26萌宠对话搜索栏展开状态（展开时禁用长按交互）
    @State private var isPetChatSearching = false

    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var petDataManager = PetDataManager.shared
    @ObservedObject private var tabNavigationManager = TabNavigationManager.shared
    @ObservedObject private var guideManager = AppFirstLaunchGuideManager.shared

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

    private var menuExpansionDirection: WheelExpansionDirection {
        if isIPad {
            if #available(iOS 26.0, *) {
                return .downward
            }
            return .upward
        }
        return .upward
    }

    // 莫妮卡粉色
    private let monicaPink = Color(red: 1.0, green: 0.41, blue: 0.71)

    // 常用菜单设置管理器
    @ObservedObject private var favoriteMenuManager = FavoriteMenuSettingsManager.shared

    // MARK: - 菜单数据（单层结构，只显示常用菜单）
    private var menuItems: [WheelMenuItem] {
        favoriteMenuItems
    }

    // 根据用户设置生成常用菜单项，只显示已解锁的功能，最多 5 个
    private var favoriteMenuItems: [WheelMenuItem] {
        favoriteMenuManager.selectedItems.compactMap { item in
            // 检查功能是否已解锁，未解锁则不显示
            if !item.isUnlocked {
                return nil
            }
            
            // 萌宠功能不在常用菜单中显示（因为有独立的萌宠对话 Tab）
            if item == .pet {
                return nil
            }
            
            switch item {
            case .wardrobe:
                return WheelMenuItem(title: "衣橱", icon: "cabinet.fill", destination: .wardrobe, color: Color(red: 1.0, green: 0.41, blue: 0.71))
            case .finalPayment:
                return WheelMenuItem(title: "心愿尾款", icon: "tag.fill", destination: .depositPlan, color: Color(red: 1.0, green: 0.07, blue: 0.58))
            case .pet:
                return WheelMenuItem(title: petDataManager.status.displayName, icon: "pawprint", destination: .pet, color: Color(red: 1.0, green: 0.65, blue: 0.55))
            case .ootd:
                return WheelMenuItem(title: "魔法贴纸", icon: "book.pages", destination: .ootdDefaultBook, color: Color(red: 1.0, green: 0.41, blue: 0.71))
            case .fashionJournal:
                return WheelMenuItem(title: "穿搭手帐", icon: "book.closed", destination: .ootd, color: Color(red: 1.0, green: 0.53, blue: 0.76))
            case .smallWorld:
                return WheelMenuItem(title: "House", icon: "house.fill", destination: .menu, color: Color(red: 0.4, green: 0.8, blue: 0.9))
            case .wealth:
                return WheelMenuItem(title: "来财", icon: "yensign.circle", destination: .wealth(nil), color: Color(red: 1.0, green: 0.84, blue: 0.0))
            case .dressStock:
                return WheelMenuItem(title: "裙装股市", icon: "chart.line.uptrend.xyaxis", destination: .dressStock, color: Color(red: 1.0, green: 0.42, blue: 0.62))
            case .perler:
                return WheelMenuItem(title: "拼豆", icon: "circle.grid.2x2", destination: .perler, color: Color(red: 1.0, green: 0.55, blue: 0.75))
            case .calendar:
                return WheelMenuItem(title: "梦裙日历", icon: "calendar", destination: .calendar, color: Color(red: 0.80, green: 0.65, blue: 0.80))
            case .bigWorld:
                return WheelMenuItem(title: "世界书", icon: "globe.asia.australia", destination: .bigWorld, color: Color(red: 0.4, green: 0.8, blue: 0.9))
            case .recycleBin:
                return WheelMenuItem(title: "回收站", icon: "trash.fill", destination: .recycleBin, color: Color(red: 0.5, green: 0.5, blue: 0.5))
            }
        }.prefix(5).map { $0 } // 最多显示 5 个
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
            let fallbackTriggerHeight = isIPad ? topBarHeight : tabBarHeight
            // 移除固定宽度计算的 fallbackFrame，完全依赖 TabBarItemAnchorResolver 获取真实的 house tab 位置
            let fallbackFrame = CGRect(
                x: geometry.size.width / 2 - 34,  // 使用屏幕中心作为 fallback，避免固定宽度计算
                y: (isIPad ? 0 : geometry.size.height - fallbackTriggerHeight),
                width: 68,
                height: fallbackTriggerHeight
            )
            let houseTabFrame = resolvedHouseTabFrame(in: geometry, fallbackFrame: fallbackFrame)
            let triggerHeight = houseTabFrame.height
            let triggerAreaWidth = houseTabFrame.width
            let smallWorldTabCenterX = houseTabFrame.midX
            let smallWorldTabCenterY = houseTabFrame.midY

            // 只在菜单显示时才使用全屏遮罩，否则只显示触发区域
            if showMenu {
                // 背景遮罩
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { closeMenu() }
                    .transition(.opacity)
            }

            // 轮盘菜单（单层结构）- 只在显示时允许点击
            if showMenu {
                WheelMenuView(
                    items: menuItems,
                    radius: getMenuRadius(geometry: geometry),
                    isLowMemoryDevice: isLowMemoryDevice,
                    monicaPink: monicaPink,
                    direction: menuExpansionDirection,
                    expansionProgress: menuExpansionProgress,
                    onItemSelected: { item in
                        selectItem(item.destination)
                    }
                )
                .position(x: menuOrigin.x, y: menuOrigin.y)
            }

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

            // 触发区域 - 只在TabBar位置显示，不覆盖整个屏幕
            // 当在萌宠对话页面时，完全禁用触发区域（避免与搜索栏冲突）
            if selectedTab != 3 {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: triggerAreaWidth, height: triggerHeight)
                    .position(x: smallWorldTabCenterX, y: smallWorldTabCenterY)
                    .onLongPressGesture(
                        minimumDuration: longPressDuration,
                        maximumDistance: 20,
                        pressing: { pressing in
                            if pressing {
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
            // 当切换到非萌宠对话页面时，重置搜索状态
            if newValue != 3 {
                isPetChatSearching = false
            }
        }
        // 监听萌宠对话搜索栏状态变化
        .onReceive(NotificationCenter.default.publisher(for: .petChatSearchStateChanged)) { notification in
            if let isSearching = notification.userInfo?["isSearching"] as? Bool {
                isPetChatSearching = isSearching
            }
        }
    }

    private func resolvedHouseTabFrame(in geometry: GeometryProxy, fallbackFrame: CGRect) -> CGRect {
        TabBarItemAnchorResolver.resolvedFrame(
            for: .homeHouseTab,
            preferredTabIndex: 1,
            in: geometry,
            expansion: 0,  // 移除额外的扩展偏移，直接使用 tab 的原始位置
            fallback: fallbackFrame
        )
    }

    // MARK: - 单层轮盘菜单
    private struct WheelMenuView: View {
        let items: [WheelMenuItem]
        let radius: CGFloat
        let isLowMemoryDevice: Bool
        let monicaPink: Color
        let direction: WheelExpansionDirection
        let expansionProgress: CGFloat
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
            let leftAngle = WheelConfig.leftAngle(for: direction)
            let rightAngle = WheelConfig.rightAngle(for: direction)

            ZStack {
                // 轮盘背景（淡淡的莫妮卡粉）
                WheelBackground(
                    radius: radius + 40,
                    startAngle: WheelConfig.backgroundStartAngle(for: direction),
                    endAngle: WheelConfig.backgroundEndAngle(for: direction),
                    monicaPink: monicaPink
                )
                .scaleEffect(0.88 + 0.12 * expansionProgress)
                .opacity(0.35 + 0.65 * expansionProgress)
                .animation(.easeOut(duration: 0.2), value: expansionProgress)

                // 5个菜单项使用上下两排布局：下面2个，上面3个
                // 顺序：上排[0,2,4] 下排[1,3]（按选择顺序交叉排列）
                if items.count == 5 {
                    let outerAngles: [Double] = direction == .upward ? [-135, -95, -55] : [135, 95, 55]
                    let innerAngles: [Double] = direction == .upward ? [-120, -60] : [120, 60]

                    // 上排：3个菜单项（items[0,2,4]从左到右，间距更紧凑）
                    ForEach(0..<3) { position in
                        let index = position * 2  // 0, 2, 4
                        let angle = outerAngles[position]
                        let radians = angle * .pi / 180
                        let x = radius * cos(radians)
                        let y = radius * sin(radians)

                        ItemBubble(
                            item: items[index],
                            isLowMemoryDevice: isLowMemoryDevice,
                            iconSize: sizes.iconSize,
                            fontSize: sizes.fontSize,
                            circleSize: sizes.circleSize,
                            guideTargetKey: items[index].destination == .ootdDefaultBook ? .favoriteMenuMagicStickerEntry : nil
                        ) {
                            onItemSelected(items[index])
                        }
                        .offset(x: x * expansionProgress, y: y * expansionProgress)
                        .opacity(expansionProgress)
                        .scaleEffect(0.84 + 0.16 * expansionProgress)
                        .animation(
                            .spring(response: 0.32, dampingFraction: 0.72)
                                .delay(Double(index) * 0.02),
                            value: expansionProgress
                        )
                    }

                    // 下排：2个菜单项（items[1,3]从左到右）
                    ForEach(0..<2) { position in
                        let index = position * 2 + 1  // 1, 3
                        let angle = innerAngles[position]
                        let radians = angle * .pi / 180
                        let innerRadius = radius * 0.6
                        let x = innerRadius * cos(radians)
                        let y = innerRadius * sin(radians)

                        ItemBubble(
                            item: items[index],
                            isLowMemoryDevice: isLowMemoryDevice,
                            iconSize: sizes.iconSize,
                            fontSize: sizes.fontSize,
                            circleSize: sizes.circleSize,
                            guideTargetKey: items[index].destination == .ootdDefaultBook ? .favoriteMenuMagicStickerEntry : nil
                        ) {
                            onItemSelected(items[index])
                        }
                        .offset(x: x * expansionProgress, y: y * expansionProgress)
                        .opacity(expansionProgress)
                        .scaleEffect(0.84 + 0.16 * expansionProgress)
                        .animation(
                            .spring(response: 0.32, dampingFraction: 0.72)
                                .delay(Double(index) * 0.02),
                            value: expansionProgress
                        )
                    }
                } else {
                    // 其他数量使用原来的弧形布局
                    ForEach(items.indices, id: \.self) { index in
                        let t = items.count > 1 ? Double(index) / Double(items.count - 1) : 0.5
                        let angle = leftAngle + (rightAngle - leftAngle) * t
                        let paddedAngle = angle + (direction == .upward ? WheelConfig.menuPadding : -WheelConfig.menuPadding)
                        let paddedRadians = paddedAngle * .pi / 180
                        let x = radius * cos(paddedRadians)
                        let y = radius * sin(paddedRadians)

                        ItemBubble(
                            item: items[index],
                            isLowMemoryDevice: isLowMemoryDevice,
                            iconSize: sizes.iconSize,
                            fontSize: sizes.fontSize,
                            circleSize: sizes.circleSize,
                            guideTargetKey: items[index].destination == .ootdDefaultBook ? .favoriteMenuMagicStickerEntry : nil
                        ) {
                            onItemSelected(items[index])
                        }
                        .offset(x: x * expansionProgress, y: y * expansionProgress)
                        .opacity(expansionProgress)
                        .scaleEffect(0.84 + 0.16 * expansionProgress)
                        .animation(
                            .spring(response: 0.32, dampingFraction: 0.72)
                                .delay(Double(index) * 0.02),
                            value: expansionProgress
                        )
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
        var guideTargetKey: GuideTargetKey? = nil
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
            .modifier(OptionalGuideTargetModifier(key: guideTargetKey))
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
                if !self.isOnMenu {
                    self.smallWorldDestination = .menu
                }
            } else {
                self.selectedTab = 1
            }
        }
    }

    // 判断是否在菜单页面
    private var isOnMenu: Bool {
        if case .menu = smallWorldDestination {
            return true
        }
        return false
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

        menuHideWorkItem?.cancel()
        menuHideWorkItem = nil

        // 重置轮盘状态
        wheelRotation = 0

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            menuOrigin = CGPoint(x: smallWorldTabCenterX, y: smallWorldTabCenterY)
            menuExpansionProgress = 0
            showMenu = true
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.75)) {
            menuExpansionProgress = 1
        }
        NotificationCenter.default.post(name: .smallWorldQuickMenuOpened, object: nil)

        isPressing = false
        pressProgress = 0.0
    }

    private func closeMenu() {
        menuHideWorkItem?.cancel()
        menuHideWorkItem = nil

        withAnimation(.easeOut(duration: 0.16)) {
            menuExpansionProgress = 0
        }

        let hideWorkItem = DispatchWorkItem {
            self.showMenu = false
        }
        menuHideWorkItem = hideWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: hideWorkItem)
    }

    private func selectItem(_ dest: SmallWorldDestination) {
        closeMenu()

        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                switch dest {
                case .wardrobe:
                    // 使用 TabNavigationManager 跳转到衣橱 Tab
                    tabNavigationManager.navigate(to: .wardrobe(.wardrobe))
                case .depositPlan:
                    // 使用 TabNavigationManager 跳转到心愿尾款 Tab
                    tabNavigationManager.navigate(to: .wardrobe(.depositPlan))
                default:
                    // 其他功能在House Tab 内跳转
                    selectedTab = 1
                    // 如果当前已经在House Tab 内，标记为内部导航
                    if selectedTab == 1 {
                        tabNavigationManager.markNavigatingInsideSmallWorld()
                    }
                    smallWorldDestination = dest
                }
            }
        }
    }
}

private struct OptionalGuideTargetModifier: ViewModifier {
    let key: GuideTargetKey?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let key {
            content.captureGuideTarget(key)
        } else {
            content
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
