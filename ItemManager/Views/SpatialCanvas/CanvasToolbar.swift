//
//  CanvasToolbar.swift
//  ItemManager
//
//  空间画布左侧工具栏
//

import SwiftUI

struct CanvasToolbar: View {
    @Binding var selectedTool: CanvasTool
    var onToolTap: (CanvasTool) -> Void
    
    // 工具分组
    private let toolGroups: [[CanvasTool]] = [
        [.select],
        [.image, .camera, .gsModel],
        [.light, .text],
        [.material, .clothing, .effect, .template],
        [.record, .settings]
    ]
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(Array(toolGroups.enumerated()), id: \.offset) { groupIndex, tools in
                    VStack(spacing: 8) {
                        ForEach(tools, id: \.self) { tool in
                            ToolButton(
                                tool: tool,
                                isSelected: selectedTool == tool,
                                onTap: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedTool = tool
                                        onToolTap(tool)
                                    }
                                }
                            )
                        }
                    }

                    // 分组分隔线
                    if groupIndex < toolGroups.count - 1 {
                        Divider()
                            .background(Color.black.opacity(0.1))
                            .frame(width: 30)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .frame(maxHeight: 600)
    }
}

// MARK: - 工具按钮

struct ToolButton: View {
    let tool: CanvasTool
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    // 背景圆
                    Circle()
                        .fill(isSelected ? tool.color : Color.gray.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(
                                    isSelected ? tool.color.opacity(0.5) : Color.gray.opacity(0.2),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                        .shadow(
                            color: isSelected ? tool.color.opacity(0.4) : Color.clear,
                            radius: isSelected ? 8 : 0
                        )
                    
                    // 图标
                    Image(systemName: tool.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                .scaleEffect(isPressed ? 0.9 : 1.0)
                
                // 标签
                Text(tool.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? tool.color : .primary.opacity(0.7))
            }
        }
        .buttonStyle(PlainButtonStyle())
        .pressEvents {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
        } onRelease: {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = false
            }
        }
    }
}

// MARK: - 按压效果扩展

extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    onPress()
                }
                .onEnded { _ in
                    onRelease()
                }
        )
    }
}

// MARK: - 预览

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        CanvasToolbar(
            selectedTool: .constant(.select),
            onToolTap: { _ in }
        )
    }
}
