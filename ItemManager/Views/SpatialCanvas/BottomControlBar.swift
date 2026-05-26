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
        HStack(spacing: 6) {
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
            
            Divider()
                .frame(height: 30)
            
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 12, x: 0, y: 4)
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.2 : 0.5), lineWidth: 1)
        )
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
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isActive ? color : .primary.opacity(0.7))
                    .symbolRenderingMode(isActive ? .hierarchical : .monochrome)
                
                Text(title.appLocalized)
                    .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? color : .primary.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(color.opacity(0.18))
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(color.opacity(0.6), lineWidth: 1.5)
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.clear)
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
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
                        Text("缩放".appLocalized)
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
                Text(title.appLocalized)
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
