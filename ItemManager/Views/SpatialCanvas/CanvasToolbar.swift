//
//  CanvasToolbar.swift
//  ItemManager
//
//  空间画布左侧工具栏
//

import SwiftUI

struct CanvasToolbar: View {
    @Binding var selectedTool: CanvasTool?
    var onToolTap: (CanvasTool) -> Void
    var onResetCamera: () -> Void = {}
    var onOpenAssetPanel: (AssetCategory) -> Void = { _ in }
    @Environment(\.colorScheme) private var colorScheme
    
    // 工具分组
    private let toolGroups: [[CanvasTool]] = [
        [.record]
    ]
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 12) {
                // 重置视角按钮 - 放在最上面
                ToolButton(
                    tool: .resetCamera,
                    isSelected: false,
                    onTap: onResetCamera
                )
                
                Divider()
                    .background(Color.black.opacity(0.1))
                    .frame(width: 30)
                    .padding(.vertical, 4)
                
                // 选择按钮
                ToolButton(
                    tool: .select,
                    isSelected: selectedTool == .select,
                    onTap: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            print("[CanvasToolbar] 点击工具: select, 当前选中: \(selectedTool?.rawValue ?? "nil")")
                            onToolTap(.select)
                            print("[CanvasToolbar] 点击后选中: \(selectedTool?.rawValue ?? "nil")")
                        }
                    }
                )
                
                Divider()
                    .background(Color.black.opacity(0.1))
                    .frame(width: 30)
                    .padding(.vertical, 4)
                
                // 导入菜单按钮
                ImportMenuButton(onToolTap: onToolTap)
                
                Divider()
                    .background(Color.black.opacity(0.1))
                    .frame(width: 30)
                    .padding(.vertical, 4)
                
                // 素材库菜单按钮
                AssetMenuButton(onOpenAssetPanel: onOpenAssetPanel, onToolTap: onToolTap)
                
                Divider()
                    .background(Color.black.opacity(0.1))
                    .frame(width: 30)
                    .padding(.vertical, 4)
                
                ForEach(Array(toolGroups.enumerated()), id: \.offset) { groupIndex, tools in
                    VStack(spacing: 8) {
                        ForEach(tools, id: \.self) { tool in
                            ToolButton(
                                tool: tool,
                                isSelected: selectedTool == tool,
                                onTap: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        print("[CanvasToolbar] 点击工具: \(tool.rawValue), 当前选中: \(selectedTool?.rawValue ?? "nil")")
                                        // 不再在这里设置 selectedTool，让父视图决定
                                        onToolTap(tool)
                                        print("[CanvasToolbar] 点击后选中: \(selectedTool?.rawValue ?? "nil")")
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
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(uiColor: .systemGray5).opacity(0.9) : Color.white.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.05), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 10, x: 0, y: 5)
        .contentShape(Rectangle())
    }
}

// MARK: - 素材库菜单按钮

struct AssetMenuButton: View {
    var onOpenAssetPanel: (AssetCategory) -> Void
    var onToolTap: (CanvasTool) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    
    var body: some View {
        Menu {
            Button {
                onOpenAssetPanel(.models)
            } label: {
                Label("服装", systemImage: "tshirt")
            }
            
            Button {
                onOpenAssetPanel(.effect)
            } label: {
                Label("特效", systemImage: CanvasTool.effect.icon)
            }
            
            Button {
                onOpenAssetPanel(.light)
            } label: {
                Label("灯光", systemImage: CanvasTool.light.icon)
            }
            
            Divider()
            
            Button {
                onToolTap(.text)
            } label: {
                Label("文字", systemImage: CanvasTool.text.icon)
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    
                    Image(systemName: "folder")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .scaleEffect(isPressed ? 0.9 : 1.0)
                
                Text("素材")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
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

// MARK: - 导入菜单按钮

struct ImportMenuButton: View {
    var onToolTap: (CanvasTool) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    
    var body: some View {
        Menu {
            Button {
                onToolTap(.image)
            } label: {
                Label("图片", systemImage: CanvasTool.image.icon)
            }
            
            Button {
                onToolTap(.camera)
            } label: {
                Label("相机", systemImage: CanvasTool.camera.icon)
            }
            
            Button {
                onToolTap(.usdzModel)
            } label: {
                Label("3D模型", systemImage: CanvasTool.usdzModel.icon)
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .scaleEffect(isPressed ? 0.9 : 1.0)
                
                Text("导入")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
            }
        }
        .captureGuideTarget(.spatialCanvasImportMenu)
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
                },
            including: .all
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
