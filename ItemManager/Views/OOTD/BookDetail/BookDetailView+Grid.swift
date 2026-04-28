import SwiftUI
import SwiftData
import UniformTypeIdentifiers

extension BookDetailView {

    @ViewBuilder
    func pageCell(for page: Outfit) -> some View {
        if isBatchEditing {
            batchEditingPageCell(for: page)
        } else if isEditing {
            editingPageCell(for: page)
        } else {
            normalPageCell(for: page)
        }
    }

    @ViewBuilder
    private func batchEditingPageCell(for page: Outfit) -> some View {
        let isSelected = selectedPages.contains(page.id)
        PageThumbnailView(page: page, gridMode: gridMode)
            .overlay(alignment: .topLeading) {
                selectionIndicator(isSelected: isSelected)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.pink : Color.clear, lineWidth: 3)
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.2)) {
                    if isSelected {
                        selectedPages.remove(page.id)
                    } else {
                        selectedPages.insert(page.id)
                    }
                }
            }
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        ThemeSkinSelectionBadge(isSelected: isSelected)
    }

    @ViewBuilder
    private func editingPageCell(for page: Outfit) -> some View {
        PageThumbnailView(page: page, gridMode: gridMode)
            .overlay(alignment: .topTrailing) {
                dragHandle
            }
            .onDrag {
                return NSItemProvider(object: page.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: ReorderableDropDelegate(item: page, pages: sortedPages, onMove: movePage))
    }

    private var dragHandle: some View {
        ThemeSkinIconBadge(
            systemName: "line.3.horizontal",
            fallbackColor: .gray,
            size: 24,
            symbolSize: 10
        )
        .padding(4)
    }

    private func normalPageCell(for page: Outfit) -> some View {
        Group {
            if let onPageTap = onPageTap {
                // 使用自定义点击回调（从衣橱进入时使用）
                Button {
                    onPageTap(page)
                } label: {
                    PageThumbnailView(page: page, gridMode: gridMode)
                }
                .contextMenu {
                    pageContextMenu(for: page)
                }
            } else {
                // 使用 NavigationLink（正常导航时使用）
                NavigationLink(value: page) {
                    PageThumbnailView(page: page, gridMode: gridMode)
                }
                .contextMenu {
                    pageContextMenu(for: page)
                }
            }
        }
    }

    @ViewBuilder
    private func pageContextMenu(for page: Outfit) -> some View {
        Button {
            pageToRename = page
            newPageName = page.note
            showingRenameAlert = true
        } label: {
            Label("修改名称", systemImage: "pencil")
        }

        Button {
            duplicatePage(page)
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }

        Button {
            sharePage(page)
        } label: {
            Label("分享成图片", systemImage: "square.and.arrow.up")
        }

        Button {
            insertPage(after: page)
        } label: {
            Label("在后面新增", systemImage: "arrow.right.square")
        }

        Button {
            insertPage(before: page)
        } label: {
            Label("在前面新增", systemImage: "arrow.left.square")
        }

        Button {
            pageToMove = page
            showingMoveSheet = true
        } label: {
            Label("移动到...", systemImage: "folder")
        }

        Button(role: .destructive) {
            pageToDelete = page
            showingDeleteConfirmation = true
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    private func sharePage(_ page: Outfit) {
        // 打开分享卡片动画界面
        pageToShare = page
        showingShareCard = true
    }
}
