//
//  CanvasToolbarView.swift
//  ItemManager
//
//  画布左侧工具栏 - 提供图层管理和变换操作
//  特性：安全区域适配、自适应布局、可滑动
//

import SwiftUI
import SwiftData

/// 画布左侧工具栏
struct CanvasToolbarView: View {
    @Bindable var outfit: Outfit
    @Binding var selectedItemId: UUID?
    
    // 显示状态 - 由父视图控制
    @Binding var isVisible: Bool
    // 贴纸库显示状态
    @Binding var isStickerLibraryVisible: Bool
    // 横屏状态
    let isLandscape: Bool
    
    // 翻页相关
    let currentPageIndex: Int
    let totalPages: Int
    let hasPreviousPage: Bool
    let hasNextPage: Bool
    var onPreviousPage: () -> Void
    var onNextPage: () -> Void
    
    // 回调
    var onDelete: (OutfitItem) -> Void
    var onBringToFront: (OutfitItem) -> Void
    var onBringForward: (OutfitItem) -> Void
    var onSendBackward: (OutfitItem) -> Void
    var onSendToBack: (OutfitItem) -> Void
    var onResetTransform: (OutfitItem) -> Void
    
    // 显示状态
    @State private var showingDeleteConfirmation = false
    @State private var itemToDelete: OutfitItem?
    
    // 环境变量
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    
    var selectedItem: OutfitItem? {
        guard let id = selectedItemId else { return nil }
        return outfit.items?.first { $0.id == id }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            if isVisible {
                // 工具栏内容 - 使用 ScrollView 实现可滑动
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // 标题
                        Text("工具")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        
                        Divider()
                            .frame(width: 24)
                        
                        // 贴纸库按钮
                        ToolbarButton(
                            icon: isStickerLibraryVisible ? "rectangle.stack.fill" : "rectangle.stack",
                            label: "贴纸库",
                            tint: .pink,
                            isEnabled: true
                        ) {
                            print("[OOTD] 贴纸库按钮被点击，当前状态: \(isStickerLibraryVisible)")
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isStickerLibraryVisible.toggle()
                            }
                            print("[OOTD] 贴纸库按钮点击后状态: \(isStickerLibraryVisible)")
                        }
                        
                        Divider()
                            .frame(width: 24)
                        
                        // 翻页控制组
                        ToolbarButtonGroup(title: "翻页") {
                            // 上一页按钮
                            ToolbarButton(
                                icon: "chevron.left",
                                label: "上一张",
                                isEnabled: hasPreviousPage
                            ) {
                                onPreviousPage()
                            }

                            // 页码指示器
                            Text("\(currentPageIndex + 1)/\(totalPages)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 44)

                            // 下一页按钮
                            ToolbarButton(
                                icon: "chevron.right",
                                label: "下一张",
                                isEnabled: hasNextPage
                            ) {
                                onNextPage()
                            }
                        }
                        
                        Divider()
                            .frame(width: 24)
                        
                        // 图层控制组
                        ToolbarButtonGroup(title: "图层") {
                            ToolbarButton(
                                icon: "arrow.up.to.line",
                                label: "置顶",
                                isEnabled: selectedItem != nil
                            ) {
                                if let item = selectedItem {
                                    onBringToFront(item)
                                }
                            }
                            
                            ToolbarButton(
                                icon: "arrow.up",
                                label: "上一层",
                                isEnabled: selectedItem != nil
                            ) {
                                if let item = selectedItem {
                                    onBringForward(item)
                                }
                            }
                            
                            ToolbarButton(
                                icon: "arrow.down",
                                label: "下一层",
                                isEnabled: selectedItem != nil
                            ) {
                                if let item = selectedItem {
                                    onSendBackward(item)
                                }
                            }
                            
                            ToolbarButton(
                                icon: "arrow.down.to.line",
                                label: "置底",
                                isEnabled: selectedItem != nil
                            ) {
                                if let item = selectedItem {
                                    onSendToBack(item)
                                }
                            }
                        }
                        
                        Divider()
                            .frame(width: 24)
                        
                        // 变换控制组
                        ToolbarButtonGroup(title: "变换") {
                            ToolbarButton(
                                icon: "arrow.counterclockwise",
                                label: "重置",
                                isEnabled: selectedItem != nil
                            ) {
                                if let item = selectedItem {
                                    onResetTransform(item)
                                }
                            }
                        }
                        
                        Divider()
                            .frame(width: 24)
                        
                        // 删除按钮
                        ToolbarButton(
                            icon: "trash",
                            label: "删除",
                            tint: .red,
                            isEnabled: selectedItem != nil
                        ) {
                            if let item = selectedItem {
                                itemToDelete = item
                                showingDeleteConfirmation = true
                            }
                        }
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 8)
                    // 底部增加安全区域高度，确保内容不被遮挡
                    .padding(.bottom, max(safeAreaInsets.bottom, 16))
                }
                .frame(width: 64)
                .frame(maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .background(Color(UIColor.systemBackground).opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 2, y: 0)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        // 整体安全区域适配
        .padding(.top, 0)
        .padding(.bottom, 0)
        .padding(.leading, 0)
        .alert("确认删除", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) {
                itemToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let item = itemToDelete {
                    onDelete(item)
                }
                itemToDelete = nil
            }
        } message: {
            Text("确定要删除这个贴纸吗？此操作无法撤销。")
        }
    }
}

// MARK: - 工具栏按钮组
struct ToolbarButtonGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.7))
            
            VStack(spacing: 12) {
                content
            }
        }
    }
}

// MARK: - 工具栏按钮
struct ToolbarButton: View {
    let icon: String
    let label: String
    var tint: Color = .primary
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isEnabled ? tint.opacity(0.1) : Color.gray.opacity(0.05))
                    )
                    .foregroundStyle(isEnabled ? tint : Color.gray.opacity(0.5))
                
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(isEnabled ? .secondary : Color.gray.opacity(0.5))
            }
        }
        .disabled(!isEnabled)
        .buttonStyle(.plain)
    }
}

// MARK: - 安全区域扩展
/// 安全区域 Insets 环境变量
private struct SafeAreaInsetsKey: EnvironmentKey {
    static var defaultValue: EdgeInsets {
        EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
    }
}

extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        get { self[SafeAreaInsetsKey.self] }
        set { self[SafeAreaInsetsKey.self] = newValue }
    }
}

// MARK: - 预览
#Preview {
    CanvasToolbarView(
        outfit: Outfit(note: "测试"),
        selectedItemId: .constant(nil),
        isVisible: .constant(true),
        isStickerLibraryVisible: .constant(false),
        isLandscape: false,
        currentPageIndex: 2,
        totalPages: 10,
        hasPreviousPage: true,
        hasNextPage: true,
        onPreviousPage: {},
        onNextPage: {},
        onDelete: { _ in },
        onBringToFront: { _ in },
        onBringForward: { _ in },
        onSendBackward: { _ in },
        onSendToBack: { _ in },
        onResetTransform: { _ in }
    )
    .frame(height: 500)
    .background(Color.gray.opacity(0.1))
}
