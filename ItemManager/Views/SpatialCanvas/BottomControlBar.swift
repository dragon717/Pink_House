//
//  BottomControlBar.swift
//  ItemManager
//
//  底部操作栏 - 旋转/缩放/删除
//

import SwiftUI

// 注意：GSProcessingStage, GSProcessingOverlay, TransformMode 定义在 SpatialCanvasTypes.swift 中

struct BottomControlBar: View {
    @Binding var transformMode: TransformMode
    var onMove: () -> Void
    var onRotate: () -> Void
    var onScale: () -> Void
    var onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            // 移动按钮
            ControlButton(
                title: "移动",
                icon: "arrow.up.and.down.and.arrow.left.and.right",
                isActive: transformMode == .move,
                color: .purple
            ) {
                onMove()
            }
            
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color(uiColor: .systemGray5).opacity(0.9) : Color.white.opacity(0.8))
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.05), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 6, x: 0, y: 3)
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
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isActive ? color : .primary)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? color : .primary.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? color.opacity(0.15) : Color.gray.opacity(0.1))
                    .overlay(
                        Capsule()
                            .stroke(isActive ? color : Color.gray.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .pressEvents {
            isPressed = true
        } onRelease: {
            isPressed = false
        }
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
                onMove: {},
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
