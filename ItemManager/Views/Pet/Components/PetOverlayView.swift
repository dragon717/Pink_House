import SwiftUI
import UIKit

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
    @State private var hasSetInitialPosition: Bool = false
    
    // 触觉反馈管理器
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    
    // 配置参数
    // 假设 TabBar 高度约为 49pt (标准) + Safe Area
    // 我们希望宠物趴在 TabBar 上缘。
    // 可以通过 offset y 来微调垂直位置
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
                    petView(geometry: geometry)
                    Spacer()
                }
            }
            .allowsHitTesting(true)
            .onAppear {
                isBreathing = true
            }
            .onChange(of: geometry.size) { newSize in
                if !hasSetInitialPosition && UIDevice.current.userInterfaceIdiom == .pad {
                    let rightOffset = (newSize.width / 2) - (catWidth / 2) - 40
                    positionX = rightOffset
                    hasSetInitialPosition = true
                }
            }
        }
    }
    
    private func petView(geometry: GeometryProxy) -> some View {
        let safeAreaBottom = geometry.safeAreaInsets.bottom
        
        return ZStack {
            // 1. 静止/呼吸状态的猫 (趴着)
            Image("PetPeekingIcon")
                .resizable()
                .scaledToFit()
                .frame(width: catWidth)
                .scaleEffect(isBreathing ? 1.05 : 1.0, anchor: .bottom)
                .opacity(isDragging ? 0 : 1)
                .animation(
                    isDragging ? .easeOut(duration: 0.15) : Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                    value: isBreathing
                )
            
            // 2. 拖拽状态的猫 (拎起)
            Image("PetDraggingIcon")
                .resizable()
                .scaledToFit()
                .frame(width: catWidth)
                .scaleEffect(2.5, anchor: .top)
                .offset(y: 30)
                .opacity(isDragging ? 1 : 0)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isDragging)
        .offset(x: positionX + dragOffset.width, y: getVerticalOffset(safeAreaBottom: safeAreaBottom) + positionY + dragOffset.height)
        .gesture(
            DragGesture(minimumDistance: 10)
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onChanged { _ in
                    if !isDragging {
                        isDragging = true
                        hapticManager.playUIFeedback(intensity: 0.6, sharpness: 0.7, fallbackStyle: .medium)
                    }
                }
                .onEnded { value in
                    isDragging = false
                    let newPositionX = positionX + value.translation.width
                    let newPositionY = positionY + value.translation.height
                    
                    let screenWidth = geometry.size.width
                    
                    let effectiveWidth: CGFloat
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        effectiveWidth = screenWidth - 40
                    } else {
                        effectiveWidth = min(screenWidth, tabBarEffectiveWidth)
                    }
                    
                    let maxOffset = (effectiveWidth / 2) - (catWidth / 2)
                    
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0)) {
                        if newPositionX > maxOffset {
                            positionX = maxOffset
                        } else if newPositionX < -maxOffset {
                            positionX = -maxOffset
                        } else {
                            positionX = newPositionX
                        }
                        positionY = 0
                    }
                    
                    hapticManager.playUIFeedback(intensity: 0.3, sharpness: 0.3, fallbackStyle: .light)
                }
        )
        .onTapGesture {
            if !isDragging {
                hapticManager.playUIFeedback(intensity: 0.5, sharpness: 0.5, fallbackStyle: .medium)
                withAnimation {
                    action()
                }
            }
        }
    }
    
    private func getVerticalOffset(safeAreaBottom: CGFloat) -> CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            // iPad: 趴在底部屏幕（稍微有点空隙）
            // 目标：距离屏幕底部约 15pt。
            // 当前基准线：屏幕底部 - safeAreaBottom
            // 如果 safeAreaBottom > 15，我们需要向下偏移 (正值)
            // 如果 safeAreaBottom < 15，我们需要向上偏移 (负值)
            // Offset = safeAreaBottom - 15
            // 例：Safe Area 20 -> Offset +5 -> 距离底部 15
            return safeAreaBottom - 15
        } else {
            // iPhone: 紧密贴在原生底部导航栏上
            // TabBar 高度 49。
            // 目标：位于 Safe Area 顶部上方 49pt 处
            return -35 // 49pt - 14pt padding
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
