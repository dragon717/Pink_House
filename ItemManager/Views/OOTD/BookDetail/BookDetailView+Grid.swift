import SwiftUI
import SwiftData
import UniformTypeIdentifiers

extension BookDetailView {

    @ViewBuilder
    func pageCell(for page: Outfit) -> some View {
        if isEditing {
            editingPageCell(for: page)
        } else {
            normalPageCell(for: page)
        }
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
        Image(systemName: "line.3.horizontal")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(4)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .padding(4)
    }

    private func normalPageCell(for page: Outfit) -> some View {
        NavigationLink(value: page) {
            PageThumbnailView(page: page, gridMode: gridMode)
        }
        .contextMenu {
            pageContextMenu(for: page)
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
            deletePage(page)
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
