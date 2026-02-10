import SwiftUI

struct PetOverlayView: View {
    // 点击动作
    var action: () -> Void
    
    // 位置状态
    @State private var positionX: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0
    
    // 动画状态
    @State private var isBreathing: Bool = false
    
    // 交互状态
    @State private var isDragging: Bool = false
    
    // 触觉反馈
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    
    // 配置参数
    // 假设 TabBar 高度约为 49pt (标准) + Safe Area
    // 我们希望宠物趴在 TabBar 上缘。
    // 可以通过 offset y 来微调垂直位置
    private let verticalOffset: CGFloat = -49 // 向上偏移，使其位于 TabBar 上方
    
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
                        .frame(width: 100) // 根据实际图片比例调整大小
                        // 呼吸动画
                        .scaleEffect(isBreathing ? 1.05 : 1.0, anchor: .bottom)
                        .animation(
                            Animation.easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: true),
                            value: isBreathing
                        )
                        // 水平位置偏移 (拖动)
                        .offset(x: positionX + dragOffset)
                        // 垂直位置偏移 (趴在导航栏上)
                        .offset(y: verticalOffset)
                        .gesture(
                            DragGesture(minimumDistance: 10) // 设置最小距离以区分点击
                                .updating($dragOffset) { value, state, _ in
                                    state = value.translation.width
                                }
                                .onChanged { _ in
                                    if !isDragging {
                                        isDragging = true
                                    }
                                }
                                .onEnded { value in
                                    isDragging = false
                                    // 更新最终位置
                                    let newPosition = positionX + value.translation.width
                                    
                                    // 边界限制：不要拖出屏幕太远
                                    let screenWidth = geometry.size.width
                                    let maxOffset = (screenWidth / 2) - 40
                                    
                                    withAnimation(.spring()) {
                                        if newPosition > maxOffset {
                                            positionX = maxOffset
                                        } else if newPosition < -maxOffset {
                                            positionX = -maxOffset
                                        } else {
                                            positionX = newPosition
                                        }
                                    }
                                    
                                    // 触觉反馈
                                    impactGenerator.impactOccurred()
                                }
                        )
                        // 点击交互：点击时进入萌宠 Tab
                        .onTapGesture {
                            // 只有在非拖动状态下才触发
                            if !isDragging {
                                impactGenerator.impactOccurred()
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
