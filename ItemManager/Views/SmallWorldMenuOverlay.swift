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
            MenuItem(title: "穿搭手帐", icon: "tshirt", destination: .ootd, color: Color(red: 1.0, green: 0.41, blue: 0.71)),
            // 来财: 莫妮卡金 (对应 MonicaTheme Deposit)
            MenuItem(title: "来财", icon: "yensign.circle", destination: .wealth, color: Color(red: 1.0, green: 0.84, blue: 0.0)),
            // 日历: 莫妮卡紫 (对应 MonicaTheme Accent，略加深以提升白色图标对比度)
            MenuItem(title: "梦裙日历", icon: "calendar", destination: .calendar, color: Color(red: 0.80, green: 0.65, blue: 0.80)),
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
            let triggerAreaWidth = min(geometry.size.width / 3, 150)
            
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
                
                // 3. 长按进度指示器
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
                    .position(
                        x: touchLocation == .zero ? geometry.size.width / 2 : touchLocation.x,
                        y: touchLocation == .zero ? (isIPad ? triggerHeight / 2 : geometry.size.height - (triggerHeight / 2)) : touchLocation.y
                    )
                }
                
                // 4. 触发区域 (iPad 在顶部，iPhone 在底部)
                VStack {
                    if !isIPad {
                        Spacer()
                    }
                    
                    HStack {
                        Spacer()
                        // 中间区域
                        // Color.white.opacity(0.01) // 确保有背景色以响应点击，clear 有时会穿透
                        // 使用 Color.black.opacity(0.001) 更稳妥
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .frame(width: triggerAreaWidth, height: triggerHeight) // 动态高度和宽度
                            // 替换为同时支持点击和长按的组合手势
                            // DragGesture(minimumDistance: 0) 会独占事件，导致极短的点击可能被误判或不触发
                            // 更好的方式是使用 simultaneousGesture 组合 LongPress 和 Tap，
                            // 但为了获取坐标，我们必须保留 DragGesture。
                            // 修正：在 .onEnded 中强制执行点击逻辑，不再依赖 TapGesture
                            // 另外，确保视图层级在最顶层，且 allowsHitTesting(true)
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .named("MenuOverlay"))
                                    .onChanged { value in
                                        if showMenu { return } // 菜单打开时忽略长按逻辑
                                        
                                        // 始终更新触摸位置，确保圆环跟随手指
                                        touchLocation = value.location
                                        
                                        if !isPressing {
                                            print("SmallWorldMenuOverlay: Drag started at \(value.location)")
                                            isPressing = true
                                            startLocation = value.location // 记录起始位置
                                            
                                            // 触发轻微震动反馈，提示用户已开始按压
                                            #if canImport(UIKit)
                                            let generator = UIImpactFeedbackGenerator(style: .light)
                                            generator.impactOccurred()
                                            #endif
                                            
                                            startLongPressTimer()
                                        } else {
                                            // 检测位移，如果移动距离过大，则取消长按（防止滑动误触）
                                            let distance = hypot(value.location.x - startLocation.x, value.location.y - startLocation.y)
                                            if distance > 20 { // 阈值设为 20
                                                print("SmallWorldMenuOverlay: Drag distance \(distance) > 20, cancelling long press")
                                                cancelLongPress()
                                            }
                                        }
                                    }
                                    .onEnded { value in
                                        print("SmallWorldMenuOverlay: Drag ended")
                                        handlePressEnded()
                                    }
                            )
                            // 尝试显式添加 TapGesture 以处理极短点击
                            // 某些情况下 DragGesture(minimumDistance: 0) 响应太快，而 Tap 可能在抬起时才确认
                            // 我们可以试试 simultaneousGesture(TapGesture().onEnded { ... }) 配合 Drag
                            // 但如果 highPriorityGesture(Drag) 生效，Tap 应该不会被触发。
                            // 这里的核心问题是 handlePressEnded 是否被调用了。
                            // 用户反馈说日志打印了 "Drag started" 和 "Drag ended"，但没生效。
                            // 这说明 handlePressEnded 确实被调用了。
                            // 问题可能出在逻辑内部判断或者 Binding 更新没反应。
                            
                            // 让我们再加一层保险：直接在视图上添加 TapGesture，不依赖 Drag 的 onEnded
                            // 但这会导致长按时也触发 Tap... 除非我们有状态判断
                            .simultaneousGesture(
                                TapGesture()
                                    .onEnded {
                                        print("SmallWorldMenuOverlay: Explicit TapGesture triggered")
                                        if showMenu {
                                            closeMenu()
                                        } else {
                                            handleTapAction()
                                        }
                                    }
                            )
                        Spacer()
                    }
                    
                    if isIPad {
                        Spacer()
                    }
                }
                .ignoresSafeArea(edges: isIPad ? .top : .bottom)
                // 确保遮罩层出现时，触发区不阻挡遮罩层的点击（虽然这里触发区在最上层，但它只覆盖底部）
                // 当菜单显示时，点击底部触发区也应该关闭菜单吗？
                // 通常长按呼出后，如果不选，松手不消失（微信是松手消失还是点击消失？）
                // 题目要求“长按...弹出”，通常意味着 Toggle 或者 Show。
                // 如果用户想取消，点击空白处（背景遮罩）即可。
                // 如果再次点击触发区，也应该是关闭或者无效。
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
        
        // 进度条动画
        withAnimation(.linear(duration: longPressDuration)) {
            pressProgress = 1.0
        }
        
        // 启动定时器检测长按完成
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { _ in
            // 长按完成，触发菜单
            triggerMenu()
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
        
        // 如果进度没满，视为点击
        if pressProgress < 1.0 {
            // 立即停止长按动画
            isPressing = false
            withAnimation(.easeOut(duration: 0.2)) {
                pressProgress = 0.0
            }
            
            // 执行单击逻辑
            print("SmallWorldMenuOverlay: Tap detected in handlePressEnded")
            if showMenu {
                closeMenu()
            } else {
                handleTapAction()
            }
        } else {
            // 已经触发了菜单（理论上会被 didLongPressTrigger 拦截，但以防万一）
            isPressing = false
            pressProgress = 0.0
        }
    }
    
    private func triggerMenu() {
        // 使用 HapticEngineManager 播放强震动 (模拟 Heavy Impact)
        // Intensity: 0.8 (强烈), Sharpness: 0.7 (较脆), Fallback: .heavy
        hapticManager.playUIFeedback(intensity: 0.8, sharpness: 0.7, fallbackStyle: .heavy)
        
        // 标记长按已触发
        didLongPressTrigger = true
        
        // 锁定当前触摸位置为菜单发射源点，并禁用动画防止位置跳变
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            menuOrigin = touchLocation
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
            // 使用 Transaction 禁用动画或加速过渡，提升“跟手”感
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
