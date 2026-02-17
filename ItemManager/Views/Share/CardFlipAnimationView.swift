//
//  CardFlipAnimationView.swift
//  ItemManager
//
//  卡牌翻转动画视图 - 裙子放入卡牌正面，沿Y轴旋转展示正反面
//

import SwiftUI

// MARK: - 卡牌翻转动画视图
struct CardFlipAnimationView<Front: View, Back: View>: View {
    let frontContent: Front
    let backContent: Back
    let cardFrontImage: UIImage? // 卡牌正面背景图
    let cardBackImage: UIImage?  // 卡牌背面背景图
    let onAnimationComplete: () -> Void
    
    @State private var rotationY: Double = 0
    @State private var frontOpacity: Double = 1
    @State private var backOpacity: Double = 0
    @State private var scale: CGFloat = 0.8
    
    var body: some View {
        ZStack {
            // 背景
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            // 卡牌容器
            ZStack {
                // 背面（初始隐藏，旋转180度后显示）
                CardFaceView(
                    backgroundImage: cardBackImage,
                    content: backContent,
                    isFront: false
                )
                .opacity(backOpacity)
                .rotation3DEffect(
                    .degrees(180),
                    axis: (x: 0, y: 1, z: 0)
                )
                
                // 正面（初始显示）
                CardFaceView(
                    backgroundImage: cardFrontImage,
                    content: frontContent,
                    isFront: true
                )
                .opacity(frontOpacity)
            }
            .frame(width: 320, height: 520)
            .scaleEffect(scale)
            .rotation3DEffect(
                .degrees(rotationY),
                axis: (x: 0, y: 1, z: 0)
            )
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // 第一阶段：放大进入
        withAnimation(.easeOut(duration: 0.3)) {
            scale = 1.0
        }
        
        // 第二阶段：开始旋转（延迟0.5秒后）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            // 旋转到90度时，正面渐隐，背面渐显
            withAnimation(.easeInOut(duration: 0.6)) {
                rotationY = 90
            }
            
            // 在90度时切换透明度
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.01)) {
                    frontOpacity = 0
                    backOpacity = 1
                }
            }
            
            // 继续旋转到180度（展示背面）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut(duration: 0.6)) {
                    rotationY = 180
                }
                
                // 暂停一下展示背面
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    // 旋转回0度（展示正面）
                    withAnimation(.easeInOut(duration: 0.6)) {
                        rotationY = 270
                    }
                    
                    // 在270度时切换透明度
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.01)) {
                            frontOpacity = 1
                            backOpacity = 0
                        }
                    }
                    
                    // 完成旋转
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            rotationY = 360
                        }
                        
                        // 动画完成回调
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            onAnimationComplete()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 卡牌面视图
struct CardFaceView<Content: View>: View {
    let backgroundImage: UIImage?
    let content: Content
    let isFront: Bool
    
    var body: some View {
        ZStack {
            // 背景图
            if let bgImage = backgroundImage {
                Image(uiImage: bgImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 320, height: 520)
                    .clipped()
            } else {
                // 默认背景
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: isFront 
                                ? [Color.purple.opacity(0.8), Color.pink.opacity(0.6)]
                                : [Color.blue.opacity(0.6), Color.purple.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 320, height: 520)
            }
            
            // 内容
            content
                .frame(width: 280, height: 480)
        }
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 10)
    }
}

// MARK: - 预览
#Preview {
    CardFlipAnimationView(
        frontContent: VStack {
            Text("正面内容")
                .font(.title)
                .foregroundColor(.white)
        },
        backContent: VStack {
            Text("背面内容")
                .font(.title)
                .foregroundColor(.white)
        },
        cardFrontImage: nil,
        cardBackImage: nil,
        onAnimationComplete: {
            print("动画完成")
        }
    )
}
