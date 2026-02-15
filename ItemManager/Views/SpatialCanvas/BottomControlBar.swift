//
//  BottomControlBar.swift
//  ItemManager
//
//  底部操作栏 - 旋转/缩放/删除
//

import SwiftUI

struct BottomControlBar: View {
    @Binding var transformMode: TransformMode
    var onRotate: () -> Void
    var onScale: () -> Void
    var onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 40) {
            // 旋转按钮
            ControlButton(
                title: "旋转",
                icon: "rotate.3d",
                isActive: transformMode == .rotate,
                color: .blue
            ) {
                onRotate()
            }
            
            // 缩放按钮
            ControlButton(
                title: "缩放",
                icon: "arrow.up.left.and.arrow.down.right",
                isActive: transformMode == .scale,
                color: .green
            ) {
                onScale()
            }
            
            // 删除按钮
            ControlButton(
                title: "删除",
                icon: "trash",
                isActive: false,
                color: .red
            ) {
                onDelete()
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 16)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color(uiColor: .systemGray5).opacity(0.9) : Color.white.opacity(0.8))
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.05), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 10, x: 0, y: 5)
    }
}

// MARK: - 控制按钮

struct ControlButton: View {
    let title: String
    let icon: String
    let isActive: Bool
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isActive ? color : .primary)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(isActive ? color.opacity(0.2) : Color.gray.opacity(0.15))
                            .overlay(
                                Circle()
                                    .stroke(isActive ? color : Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    )

                Text(title)
                    .font(.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? color : .primary.opacity(0.7))
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .pressEvents {
            isPressed = true
        } onRelease: {
            isPressed = false
        }
    }
}

// MARK: - 3DGS处理进度遮罩

struct GSProcessingOverlay: View {
    let stage: GSProcessingStage
    let progress: Double
    
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // 3D图标动画
                ZStack {
                    // 外圈脉冲
                    Circle()
                        .stroke(Color.purple.opacity(0.3), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .opacity(pulseAnimation ? 0 : 1)
                    
                    // 中圈
                    Circle()
                        .stroke(Color.purple.opacity(0.5), lineWidth: 2)
                        .frame(width: 100, height: 100)
                    
                    // 内圈
                    Circle()
                        .fill(Color.purple.opacity(0.2))
                        .frame(width: 80, height: 80)
                    
                    // 中心图标
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 40))
                        .foregroundStyle(.purple)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                        pulseAnimation.toggle()
                    }
                }
                
                // 标题
                VStack(spacing: 8) {
                    Text("3D高斯泼溅建模")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    
                    Text(stage.description)
                        .font(.subheadline)
                        .foregroundStyle(.purple)
                }
                
                // 进度条
                VStack(spacing: 8) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // 背景
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 8)
                            
                            // 进度
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .pink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progress, height: 8)
                                .animation(.easeInOut(duration: 0.3), value: progress)
                        }
                    }
                    .frame(width: 250, height: 8)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                
                // 阶段指示器
                HStack(spacing: 8) {
                    ForEach(GSProcessingStage.allCases, id: \.self) { s in
                        Circle()
                            .fill(stage == s ? Color.purple : Color.white.opacity(0.2))
                            .frame(width: 8, height: 8)
                            .scaleEffect(stage == s ? 1.5 : 1.0)
                    }
                }
                
                // 提示文字
                VStack(spacing: 4) {
                    Text("请勿关闭应用")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    
                    if stage == .training {
                        Text("这可能需要几分钟时间")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .padding(40)
        }
    }
}

// MARK: - GSProcessingStage 扩展

extension GSProcessingStage: CaseIterable {
    static var allCases: [GSProcessingStage] {
        [.uploading, .sfm, .training, .optimizing, .complete]
    }
}

// MARK: - 变换控制滑块

struct TransformControlSliders: View {
    let mode: TransformMode
    @Binding var rotationX: Double
    @Binding var rotationY: Double
    @Binding var rotationZ: Double
    @Binding var scale: Double
    var onChange: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            if mode == .rotate {
                // 旋转控制
                AxisSlider(title: "X轴", value: $rotationX, range: -180...180, color: .red) {
                    onChange()
                }
                
                AxisSlider(title: "Y轴", value: $rotationY, range: -180...180, color: .green) {
                    onChange()
                }
                
                AxisSlider(title: "Z轴", value: $rotationZ, range: -180...180, color: .blue) {
                    onChange()
                }
            } else {
                // 缩放控制
                VStack(spacing: 8) {
                    HStack {
                        Text("缩放")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        
                        Spacer()
                        
                        Text(String(format: "%.2fx", scale))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .monospacedDigit()
                    }
                    
                    Slider(value: $scale, in: 0.1...3.0, step: 0.1) { _ in
                        onChange()
                    }
                    .tint(.green)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 轴向滑块

struct AxisSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color
    let onChange: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(color)
                
                Spacer()
                
                Text("\(Int(value))°")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
            
            Slider(value: $value, in: range, step: 1) { _ in
                onChange()
            }
            .tint(color)
        }
    }
}

// MARK: - 预览

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            
            BottomControlBar(
                transformMode: .constant(.rotate),
                onRotate: {},
                onScale: {},
                onDelete: {}
            )
            .padding(.bottom, 40)
        }
    }
}

#Preview("Processing Overlay") {
    GSProcessingOverlay(stage: .training, progress: 0.65)
}
