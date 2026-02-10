import SwiftUI
import UIKit

struct SmallWorldMenuOverlay: View {
    @Binding var selectedTab: Int
    @Binding var smallWorldDestination: SmallWorldDestination
    
    // 菜单状态
    @State private var showMenu = false
    
    // 长按动画状态
    @State private var pressProgress: CGFloat = 0.0
    @State private var isPressing: Bool = false
    @State private var touchLocation: CGPoint = .zero
    @State private var timer: Timer?
    private let longPressDuration: TimeInterval = 0.5
    
    // 震动管理器
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    
    // 菜单项数据
    struct MenuItem: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let destination: SmallWorldDestination
        let color: Color
    }
    
    private let menuItems: [MenuItem] = [
        // 萌宠: 莫妮卡珊瑚 (自定义暖色，对应萌宠活力)
        MenuItem(title: "萌宠", icon: "pawprint", destination: .pet, color: Color(red: 1.0, green: 0.65, blue: 0.55)),
        // 穿搭: 莫妮卡热粉 (对应 MonicaTheme FinalPayment)
        MenuItem(title: "穿搭", icon: "tshirt", destination: .ootd, color: Color(red: 1.0, green: 0.41, blue: 0.71)),
        // 来财: 莫妮卡金 (对应 MonicaTheme Deposit)
        MenuItem(title: "来财", icon: "yensign.circle", destination: .wealth, color: Color(red: 1.0, green: 0.84, blue: 0.0)),
        // 日历: 莫妮卡紫 (对应 MonicaTheme Accent，略加深以提升白色图标对比度)
        MenuItem(title: "梦裙日历", icon: "calendar", destination: .calendar, color: Color(red: 0.80, green: 0.65, blue: 0.80))
    ]
    
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
            // 动态计算 TabBar 交互区域高度 (标准高度 49 + 安全区域)
            let tabBarHeight = 49.0 + safeAreaBottom
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
                if showMenu {
                    ZStack {
                        ForEach(menuItems.indices, id: \.self) { index in
                            let item = menuItems[index]
                            
                            // 计算角度: 分布在 -160 (左下) 到 -20 (右下) 之间，上方是 -90
                            // 4个项目，区间跨度 140度
                            let totalAngle: Double = 140
                            let startAngle: Double = -160
                            let step = totalAngle / Double(menuItems.count - 1)
                            let degrees = startAngle + Double(index) * step
                            
                            // 转换为弧度
                            let radians = degrees * .pi / 180
                            
                            // 计算相对于中心的偏移
                            let currentRadius = getRadius(geometry: geometry)
                            let xOffset = currentRadius * cos(radians)
                            let yOffset = currentRadius * sin(radians)
                            
                            MenuBubbleView(item: item) {
                                selectItem(item.destination)
                            }
                            // 初始位置设为发射源点 (触摸位置或默认位置)
                            // 默认位置使用动态计算的 TabBar 中心
                            .position(
                                x: touchLocation == .zero ? geometry.size.width / 2 : touchLocation.x,
                                y: touchLocation == .zero ? geometry.size.height - (tabBarHeight / 2) : touchLocation.y
                            )
                            // 通过 offset 动画实现飞出效果
                            .offset(
                                x: showMenu ? xOffset : 0,
                                y: showMenu ? yOffset : 0
                            )
                            .scaleEffect(showMenu ? 1.0 : 0.1)
                            .opacity(showMenu ? 1.0 : 0.0)
                            // 使用插值弹簧动画实现灵动效果
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0.5)
                                .delay(Double(index) * 0.03),
                                value: showMenu
                            )
                        }
                    }
                }
                
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
                        y: touchLocation == .zero ? geometry.size.height - (tabBarHeight / 2) : touchLocation.y
                    )
                }
                
                // 4. 触发区域 (覆盖在 TabBar 中间按钮上)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        // 中间区域
                        // Color.white.opacity(0.01) // 确保有背景色以响应点击，clear 有时会穿透
                        // 使用 Color.black.opacity(0.001) 更稳妥
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .frame(width: triggerAreaWidth, height: tabBarHeight) // 动态高度和宽度
                            // 替换为同时支持点击和长按的组合手势
                            // DragGesture(minimumDistance: 0) 会独占事件，导致极短的点击可能被误判或不触发
                            // 更好的方式是使用 simultaneousGesture 组合 LongPress 和 Tap，
                            // 但为了获取坐标，我们必须保留 DragGesture。
                            // 修正：在 .onEnded 中强制执行点击逻辑，不再依赖 TapGesture
                            // 另外，确保视图层级在最顶层，且 allowsHitTesting(true)
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .named("MenuOverlay"))
                                    .onChanged { value in
                                        if !isPressing {
                                            print("SmallWorldMenuOverlay: Drag started at \(value.location)")
                                            isPressing = true
                                            touchLocation = value.location
                                            startLongPressTimer()
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
                                        if !showMenu { // 只有菜单没显示时才响应
                                            handleTapAction()
                                        }
                                    }
                            )
                        Spacer()
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                // 确保遮罩层出现时，触发区不阻挡遮罩层的点击（虽然这里触发区在最上层，但它只覆盖底部）
                // 当菜单显示时，点击底部触发区也应该关闭菜单吗？
                // 通常长按呼出后，如果不选，松手不消失（微信是松手消失还是点击消失？）
                // 题目要求“长按...弹出”，通常意味着 Toggle 或者 Show。
                // 如果用户想取消，点击空白处（背景遮罩）即可。
                // 如果再次点击触发区，也应该是关闭或者无效。
            }
            .coordinateSpace(name: "MenuOverlay")
        }
    }
    
    private func startLongPressTimer() {
        // 重置状态
        pressProgress = 0.0
        
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
        // 强制在主线程执行
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
    
    private func handlePressEnded() {
        timer?.invalidate()
        timer = nil
        
        // 如果进度没满，视为点击
        if pressProgress < 1.0 {
            // 立即停止长按动画
            isPressing = false
            withAnimation(.easeOut(duration: 0.2)) {
                pressProgress = 0.0
            }
            
            // 执行单击逻辑
            // 务必确保这里的逻辑是正确的，并且 selectedTab 和 smallWorldDestination 是有效的 Binding
            print("SmallWorldMenuOverlay: Tap detected in handlePressEnded")
            handleTapAction()
        } else {
            // 已经触发了菜单，这里只需要重置进度显示（如果菜单没出来的话）
            // 但通常 triggerMenu 已经处理了 UI
            // isPressing = false // 不要在这里设为 false，这会导致动画瞬间消失，应该在 triggerMenu 里处理
            // 但如果用户长按后移动手指导致 menu 没触发（比如取消），这里需要处理
            // 实际上我们的逻辑是只要时间到了就触发，不关心是否松手。
            // 松手后清理状态
            isPressing = false
            pressProgress = 0.0
        }
    }
    
    private func triggerMenu() {
        // 使用 HapticEngineManager 播放强震动 (模拟 Heavy Impact)
        // Intensity: 0.8 (强烈), Sharpness: 0.7 (较脆), Fallback: .heavy
        hapticManager.playUIFeedback(intensity: 0.8, sharpness: 0.7, fallbackStyle: .heavy)
        
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
        // 先关闭菜单
        closeMenu()
        
        // 延迟跳转，让动画先播放一点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            selectedTab = 1
            smallWorldDestination = dest
        }
    }
}

struct MenuBubbleView: View {
    let item: SmallWorldMenuOverlay.MenuItem
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(item.color)
                        .frame(width: 56, height: 56)
                        .shadow(color: item.color.opacity(0.4), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: item.icon)
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
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
