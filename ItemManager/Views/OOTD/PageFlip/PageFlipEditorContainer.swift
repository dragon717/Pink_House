//
//  PageFlipEditorContainer.swift
//  ItemManager
//
//  带翻页动画的书页编辑器容器
//

import SwiftUI
import SwiftData

/// 带翻页动画的书页编辑器容器
struct PageFlipEditorContainer: View {
    @State var initialOutfit: Outfit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        OOTDEditorView(
            outfit: initialOutfit,
            onPageChange: { newOutfit in
                // 切换书页
                withAnimation(.easeInOut(duration: 0.2)) {
                    initialOutfit = newOutfit
                }
            }
        )
        .id(initialOutfit.id) // 关键：改变 id 强制重新创建视图
        .transition(.opacity)
    }
}

// MARK: - 预览
#Preview {
    // 预览需要模拟数据
    Text("PageFlipEditorContainer Preview")
}
