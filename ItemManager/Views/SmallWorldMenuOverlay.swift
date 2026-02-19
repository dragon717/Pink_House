import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SmallWorldMenuOverlay: View {
    @Binding var selectedTab: Int
    @Binding var smallWorldDestination: SmallWorldDestination

    // 环境遍历，用于监听 App 生命周期
    @Environment(\.scenePhase) private var scenePhase

    // 菜单状态
    @State private var showMenu = false

    // 长按动画状态
    @State private var pressProgress: CGFloat = 0.0
    @State private var isPressing: Bool = false
    @State private var didLongPressTrigger: Bool = false
    @State private var touchLocation: CGPoint = .zero
    @State private var startLocation: CGPoint = .zero // 记录拖动起始位置
    @State private var menuOrigin: CGPoint = .zero // 菜单发射源点
    @State private var timer: Timer?
    private let longPressDuration: TimeInterval = 0.35 // 缩短长按时间，提升响应速度，缓解系统手势冲突

    // 震动管理器
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var petDataManager = PetDataManager.shared

    // 性能优化：检测低内存设备 (小于 4GB 内存)
    private let isLowMemoryDevice: Bool = {
        return ProcessInfo.processInfo.physicalMemory < 4 * 1024 * 1024 * 1024
    }()

    // 检测 iPad
    private var isIPad: Bool {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    // 菜单项数据
    struct MenuItem: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let destination: SmallWorldDestination
        let color: Color
    }

    private var menuItems: [MenuItem] {
        [
            // 萌宠: 莫妮卡珊瑚 (自定义暖色，对应萌宠活力)
            MenuItem(title: petDataManager.status.displayName, icon: "pawprint", destination: .pet, color: Color(red: 1.0, green: 0.65, blue: 0.55)),
            // 穿搭: 莫妮卡热粉 (对应 MonicaTheme FinalPayment)
            MenuItem(title: "穿搭手帐", icon: "book.pages", destination: .ootd, color: Color(red: 1.0, green: 0.41, blue: 0.71)),
            // 来财: 莫妮卡金 (对应 MonicaTheme Deposit)
            MenuItem(title: "来财", icon: "yensign.circle", destination: .wealth, color: Color(red: 1.0, green: 0.84, blue: 0.0)),
            // 日历: 莫妮卡紫 (对应 MonicaTheme Accent，略加深以提升白色图标对比度)
            MenuItem(title: "梦裙日历", icon: "calendar", destination: .calendar, color: Color(red: 0.80, green: 0.65, blue: 0.80)),
            // 大世界: 梦幻渐变 (对应全球茶会主题)
            MenuItem(title: "大世界", icon: "airplane", destination: .bigWorld, color: Color(red: 0.4, green: 0.8, blue: 0.9)),
        ]
    }

    // 布局参数
    // 根据屏幕宽度动态计算半径，适配小屏设备 (如 iPhone SE) 和 iPad
    private func getRadius(geometry: GeometryProxy) -> CGFloat {
        // 基础半径 110，但在小屏上适当缩小，在大屏上适当增加
        let baseRadius: CGFloat = 110
        let screenWidth = geometry.size.width

        if screenWidth < 380 { // iPhone SE, mini 等
            return 90
        } else if screenWidth > 700 { // iPad
            return 140
        } else {
            return baseRadius
        }
    }

    private let bubbleSize: CGFloat = 50

    var body: some View {
        GeometryReader { geometry in
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            let safeAreaTop = geometry.safeAreaInsets.top

            // 动态计算交互区域高度
            // iPhone: 底部 TabBar (标准高度 49 + 安全区域)，增加到 65 以覆盖图标
            // iPad: 顶部区域，同样使用 65 + 安全区域
            let tabBarHeight = 65.0 + safeAreaBottom
            let topBarHeight = 65.0 + safeAreaTop

            let triggerHeight = isIPad ? topBarHeight : tabBarHeight

            // 动态计算触发区域宽度 (限制最大宽度以适配 iPad)
            let triggerAreaWidth = min(geometry.size.width / 4, 100)

            // 计算小世界 TabBar 按钮的中心位置
            // 使用屏幕宽度的比例：4 个 Tab，小世界是第 2 个，中心在 3/8 处
            let smallWorldTabCenterX = geometry.size.width * 0.375 // 3/8
            let smallWorldTabCenterY = isIPad ? triggerHeight / 2 : geometry.size.height - triggerHeight / 2

            ZStack(alignment: .bottom) {
                // 1. 背景遮罩 (当菜单显示时)
                if showMenu {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture {
                            closeMenu()
                        }
                        .transition(.opacity)
                }

                        // 2. 菜单气泡
                ZStack(alignment: .topLeading) {
                    ForEach(menuItems.indices, id: \.self) { index in
                        let item = menuItems[index]

                        // 计算角度
                        // iPhone: 分布在 -160 (左下) 到 -20 (右下) 之间，上方是 -90 (向上发射)
                        // iPad: 分布在 160 (左上) 到 20 (右上) 之间，下方是 90 (向下发射)
                        let totalAngle: Double = isIPad ? -140 : 140
                        let startAngle: Double = isIPad ? 160 : -160
                        let step = totalAngle / Double(menuItems.count - 1)
                        let degrees = startAngle + Double(index) * step

                        // 转换为弧度
                        let radians = degrees * .pi / 180

                        // 计算相对于中心的偏移
                        let currentRadius = getRadius(geometry: geometry)
                        let xOffset = currentRadius * cos(radians)
                        let yOffset = currentRadius * sin(radians)

                        MenuBubbleView(item: item, isLowMemoryDevice: isLowMemoryDevice) {
                            selectItem(item.destination)
                        }
                        // 调整修饰符顺序：
                        // 1. 先应用缩放和透明度 (作用于气泡自身)
                        .scaleEffect(showMenu ? 1.0 : 0.1)
                        .opacity(showMenu ? 1.0 : 0.0)
                        // 2. 应用展开位移 (相对于中心点)
                        .offset(
                            x: showMenu ? xOffset : 0,
                            y: showMenu ? yOffset : 0
                        )
                        // 3. 配置动画 (作用于上述属性)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0.5)
                            .delay(showMenu ? Double(index) * 0.03 : 0),
                            value: showMenu
                        )
                        // 4. 最后进行绝对定位 (将气泡中心放置在发射源点)
                        // 注意：position 必须放在最后，因为它会改变视图大小为占满父视图，
                        // 如果放在 scaleEffect 之前，会导致缩放中心变为屏幕中心。
                        .position(
                            x: menuOrigin.x,
                            y: menuOrigin.y
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity) // 确保 ZStack 占满全屏，使内部 position 坐标系与全屏一致
                .allowsHitTesting(showMenu) // 只有显示时才允许点击，避免隐藏时遮挡

                // 3. 长按进度指示器 - 定位在小世界 TabBar 按钮中心
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
                                        Color(red: 1.0, green: 0.41, blue: 0.71), // Hot Pink
                                        Color(red: 0.85, green: 0.75, blue: 0.85) // Thistle
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 60, height: 60)
                            .shadow(color: Color(red: 1.0, green: 0.41, blue: 0.71).opacity(0.5), radius: 5)
                    }
                    .position(x: smallWorldTabCenterX, y: smallWorldTabCenterY)
                }

                // 4. 触发区域 - 定位在小世界 TabBar 按钮位置
                // 使用绝对定位确保触发区域精确跟随小世界 Tab 位置
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .frame(width: triggerAreaWidth, height: triggerHeight)
                    .position(x: smallWorldTabCenterX, y: smallWorldTabCenterY)
                    .onLongPressGesture(
                        minimumDuration: longPressDuration,
                        maximumDistance: 20,
                        pressing: { isPressing in
                            if isPressing {
                                print("SmallWorldMenuOverlay: Long press started")
                                self.isPressing = true

                                // 使用小世界 TabBar 按钮中心作为触发位置
                                self.startLocation = CGPoint(x: smallWorldTabCenterX, y: smallWorldTabCenterY)
                                self.touchLocation = self.startLocation

                                #if canImport(UIKit)
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                #endif

                                startLongPressTimer()
                            } else {
                                print("SmallWorldMenuOverlay: Long press ended")
                                handlePressEnded()
                            }
                        },
                        perform: {
                            print("SmallWorldMenuOverlay: Long press performed")
                            triggerMenu(smallWorldTabCenterX: smallWorldTabCenterX, smallWorldTabCenterY: smallWorldTabCenterY)
                        }
                    )
                    .onTapGesture {
                        print("SmallWorldMenuOverlay: Tap detected")
                        if showMenu {
                            closeMenu()
                        } else {
                            handleTapAction()
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // 确保外层 ZStack 占满全屏
            .coordinateSpace(name: "MenuOverlay")
        }
        .ignoresSafeArea() // 让 GeometryReader 获取全屏尺寸
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background || newPhase == .inactive {
                closeMenu()
            }
        }
        .onChange(of: selectedTab) { newValue in
            // 如果切换到其他 Tab，关闭菜单
            if newValue != 1 {
                closeMenu()
            }
        }
    }

    private func startLongPressTimer() {
        // 重置状态
        pressProgress = 0.0
        didLongPressTrigger = false

        // 进度条动画 - 与 onLongPressGesture 的 minimumDuration 同步
        withAnimation(.linear(duration: longPressDuration)) {
            pressProgress = 1.0
        }

        // 注意：不再使用 Timer 触发菜单
        // 菜单触发现在由 onLongPressGesture 的 perform 闭包处理
        // Timer 仅用于在长按被取消时清理状态
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: longPressDuration + 0.1, repeats: false) { _ in
            // 如果定时器触发但菜单未显示，说明长按被取消，清理状态
            if !self.showMenu && self.isPressing {
                DispatchQueue.main.async {
                    self.isPressing = false
                    self.pressProgress = 0.0
                }
            }
        }
    }

    // 抽取单击逻辑
    private func handleTapAction() {
        print("SmallWorldMenuOverlay: handleTapAction executed")

        // 使用 DispatchQueue 避免在手势回调中直接触发 Tab 切换导致的层级重建问题
        DispatchQueue.main.async {
            if self.selectedTab == 1 {
                if self.smallWorldDestination != .menu {
                    print("SmallWorldMenuOverlay: Switching Destination to .menu")
                    self.smallWorldDestination = .menu
                } else {
                    print("SmallWorldMenuOverlay: Already at .menu")
                }
            } else {
                print("SmallWorldMenuOverlay: Switching Tab to 1")
                self.selectedTab = 1
            }
        }
    }

    private func cancelLongPress() {
        timer?.invalidate()
        timer = nil
        isPressing = false
        withAnimation(.easeOut(duration: 0.2)) {
            pressProgress = 0.0
        }
        didLongPressTrigger = false
    }

    private func handlePressEnded() {
        timer?.invalidate()
        timer = nil

        // 如果是长按刚刚触发了菜单，则忽略此次抬起事件
        if didLongPressTrigger {
            didLongPressTrigger = false
            isPressing = false
            pressProgress = 0.0
            return
        }

        // 长按被取消（未达到触发时间），视为普通按压结束
        // 立即停止长按动画
        isPressing = false
        withAnimation(.easeOut(duration: 0.2)) {
            pressProgress = 0.0
        }

        // 注意：点击逻辑现在由 onTapGesture 处理，这里不再重复处理
        // 以避免与 onTapGesture 冲突导致重复触发
        print("SmallWorldMenuOverlay: Press ended without triggering menu")
    }

    private func triggerMenu(smallWorldTabCenterX: CGFloat, smallWorldTabCenterY: CGFloat) {
        // 使用 HapticEngineManager 播放强震动 (模拟 Heavy Impact)
        // Intensity: 0.8 (强烈), Sharpness: 0.7 (较脆), Fallback: .heavy
        hapticManager.playUIFeedback(intensity: 0.8, sharpness: 0.7, fallbackStyle: .heavy)

        // 标记长按已触发
        didLongPressTrigger = true

        // 锁定小世界 TabBar 按钮中心为菜单发射源点，并禁用动画防止位置跳变
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            menuOrigin = CGPoint(x: smallWorldTabCenterX, y: smallWorldTabCenterY)
            print("SmallWorldMenuOverlay: Trigger Menu. menuOrigin locked at: \(menuOrigin)")
        }

        // 显示菜单
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showMenu = true
        }

        // 进度条消失
        isPressing = false
        pressProgress = 0.0
    }

    private func closeMenu() {
        withAnimation(.easeOut(duration: 0.2)) {
            showMenu = false
        }
    }

    private func selectItem(_ dest: SmallWorldDestination) {
        // 性能优化：立即跳转，减少等待感
        // 关闭菜单
        withAnimation(.easeOut(duration: 0.15)) {
            showMenu = false
        }

        // 使用 DispatchQueue 避免在手势处理回调中直接触发布局剧烈变化
        // 这有助于规避 '_UIReparentingView' 相关的层级错误
        DispatchQueue.main.async {
            // 立即切换状态，不使用延迟
            // 使用 Transaction 禁用动画或加速过渡，提升"跟手"感
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedTab = 1
                smallWorldDestination = dest
            }
        }
    }
}

struct MenuBubbleView: View {
    let item: SmallWorldMenuOverlay.MenuItem
    // 传入低内存模式标志
    var isLowMemoryDevice: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(item.color)
                        .frame(width: 56, height: 56)
                        // 性能优化：低内存设备移除阴影
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
                    // 性能优化：低内存设备使用普通颜色代替 Material 模糊效果
                    .background {
                        if isLowMemoryDevice {
                            Color.white.opacity(0.95)
                        } else {
                            Rectangle().fill(.regularMaterial)
                        }
                    }
                    .clipShape(Capsule())
                    // 性能优化：低内存设备移除文字阴影
                    .shadow(color: .black.opacity(isLowMemoryDevice ? 0 : 0.1), radius: isLowMemoryDevice ? 0 : 2, x: 0, y: 1)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
