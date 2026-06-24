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
    @StateObject private var pageFlipController = PageFlipController()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            OOTDEditorView(
                outfit: initialOutfit,
                onPageChange: { newOutfit in
                    let currentOutfit = initialOutfit
                    pageFlipController.startFlip(
                        from: currentOutfit,
                        to: newOutfit,
                        direction: pageFlipDirection(from: currentOutfit, to: newOutfit)
                    ) {
                        initialOutfit = newOutfit
                    }
                }
            )
            .id(initialOutfit.id) // 关键：改变 id 强制重新创建视图
            .transition(.opacity)

            if pageFlipController.isFlipping,
               let currentPageImage = pageFlipController.currentPageImage,
               let targetPageImage = pageFlipController.targetPageImage {
                PageFlipView(
                    currentPageImage: currentPageImage,
                    targetPageImage: targetPageImage,
                    direction: pageFlipController.flipDirection,
                    progress: $pageFlipController.flipProgress
                )
                .ignoresSafeArea()
                .background(Color.black.opacity(0.08))
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }

    private func pageFlipDirection(from current: Outfit, to target: Outfit) -> PageFlipDirection {
        if target.sortIndex != current.sortIndex {
            return target.sortIndex > current.sortIndex ? .next : .previous
        }
        return target.createdAt >= current.createdAt ? .next : .previous
    }
}

// MARK: - 预览
#Preview {
    // 预览需要模拟数据
    Text("PageFlipEditorContainer Preview")
}
