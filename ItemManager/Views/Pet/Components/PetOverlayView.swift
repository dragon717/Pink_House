import SwiftUI

struct PetOverlayView: View {
    // 点击动作
    var action: () -> Void
    
    // 位置状态
    @State private var positionX: CGFloat = 0
    @State private var positionY: CGFloat = 0
    @GestureState private var dragOffset: CGSize = .zero
    
    // 动画状态
    @State private var isBreathing: Bool = false
    
    // 交互状态
    @State private var isDragging: Bool = false
    
    // 触觉反馈管理器
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    
    // 配置参数
    // 假设 TabBar 高度约为 49pt (标准) + Safe Area
    // 我们希望宠物趴在 TabBar 上缘。
    // 可以通过 offset y 来微调垂直位置
    private let verticalOffset: CGFloat = -49 // 向上偏移，使其位于 TabBar 上方
    private let catWidth: CGFloat = 70 // 小猫图片宽度
    
    // 底部导航栏每个按钮的预估宽度 (假设3个Tab)
    // 系统 TabBar 默认是均匀分布，但在 iPad 或大屏上可能不同。
    // 这里我们假设 TabBar 的有效交互区域主要集中在中间或均匀分布。
    // 根据用户反馈 "底部导航栏宽度不是屏幕宽度，是根据底部导航栏的所有按钮实际占用宽度"
    // 我们需要估算一个合理的有效宽度。
    // 假设每个 TabItem 宽度约为 80-100pt，间距 20pt，3个 Tab 大约 300-360pt。
    // 或者更保守一点，只限制在左右两侧的一定范围内。
    // 这里我们定义一个可配置的 TabBar 有效宽度。
    private let tabBarEffectiveWidth: CGFloat = 320 // 3个Tab的大致宽度

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                
                HStack {
                    Spacer()
                    // 宠物图标
                    Image("PetPeekingIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: catWidth) // 根据实际图片比例调整大小
                        // 呼吸动画
                        .scaleEffect(isBreathing ? 1.05 : 1.0, anchor: .bottom)
                        .animation(
                            Animation.easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: true),
                            value: isBreathing
                        )
                        // 位置偏移 (拖动 + 固定偏移)
                        .offset(x: positionX + dragOffset.width, y: verticalOffset + positionY + dragOffset.height)
                        .gesture(
                            DragGesture(minimumDistance: 10) // 设置最小距离以区分点击
                                .updating($dragOffset) { value, state, _ in
                                    state = value.translation
                                }
                                .onChanged { _ in
                                    if !isDragging {
                                        isDragging = true
                                        // 拖动开始时的震动反馈：中等强度，稍硬
                                        hapticManager.playUIFeedback(intensity: 0.6, sharpness: 0.7, fallbackStyle: .medium)
                                    }
                                }
                                .onEnded { value in
                                    isDragging = false
                                    // 更新最终位置
                                    let newPositionX = positionX + value.translation.width
                                    let newPositionY = positionY + value.translation.height
                                    
                                    // 边界限制：不要拖出屏幕太远
                                    let screenWidth = geometry.size.width
                                    
                                    // 根据用户需求：吸附范围限制在 TabBar 的实际内容宽度内
                                    // 假设 TabBar 居中，那么最大偏移量应该是 (TabBar宽度 / 2) - (猫宽度 / 2)
                                    // 这样猫的中心点最远只能到达 TabBar 的边缘内侧
                                    let maxOffset = (min(screenWidth, tabBarEffectiveWidth) / 2) - (catWidth / 2)
                                    
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0)) {
                                        // X轴：限制在屏幕内
                                        if newPositionX > maxOffset {
                                            positionX = maxOffset
                                        } else if newPositionX < -maxOffset {
                                            positionX = -maxOffset
                                        } else {
                                            positionX = newPositionX
                                        }
                                        
                                        // Y轴：回弹到底部 (positionY 重置为 0)
                                        // 无论拖到哪里，松手都吸附回底部
                                        positionY = 0
                                    }
                                    
                                    // 结束时的轻微触觉反馈：轻微强度，柔和
                                    hapticManager.playUIFeedback(intensity: 0.3, sharpness: 0.3, fallbackStyle: .light)
                                }
                        )
                        // 点击交互：点击时进入萌宠 Tab
                        .onTapGesture {
                            // 只有在非拖动状态下才触发
                            if !isDragging {
                                // 点击反馈：中等强度
                                hapticManager.playUIFeedback(intensity: 0.5, sharpness: 0.5, fallbackStyle: .medium)
                                withAnimation {
                                    action()
                                }
                            }
                        }
                    
                    Spacer()
                }
                // 确保底部有一定的空间，不完全覆盖 TabBar 的操作区域（除非拖动过去）
                // 这里我们利用 offset(y: verticalOffset) 已经向上提了
            }
            // 确保不阻挡其他区域的点击
            .allowsHitTesting(true) 
        }
        // 整个 Overlay 容器不应该阻挡点击，只有图片部分阻挡
        // GeometryReader 默认会占满空间。
        // 我们需要设置 contentShape 或者只让 Image 响应
        // 但是 GeometryReader 本身是透明的，如果不设置 background，通常是透过的。
        // 不过为了保险，我们可以不用 GeometryReader 包裹整个屏幕，
        // 而是只在底部放一个 Overlay。
        .onAppear {
            isBreathing = true
        }
    }
}

#Preview {
    ZStack {
        Color.white
        VStack {
            Spacer()
            Color.gray.frame(height: 83) // 模拟 TabBar
        }
        PetOverlayView(action: {})
    }
}
