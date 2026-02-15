import SwiftUI
import SwiftData
import PhotosUI

extension BookDetailView {

    var leadingToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            sidebarToggleButton
        }
    }

    private var sidebarToggleButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isSidebarVisible.toggle()
            }
        } label: {
            Image(systemName: isSidebarVisible ? "sidebar.left" : "sidebar.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    var trailingToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 8) {
                gridModeMenu
                editToggleButton
                moreOptionsMenu
            }
        }
    }

    private var gridModeMenu: some View {
        Menu {
            Picker("视图布局", selection: $gridModeValue) {
                ForEach(GridMode.allCases, id: \.rawValue) { mode in
                    Label(mode.displayName, systemImage: mode.iconName)
                        .tag(mode.rawValue)
                }
            }
        } label: {
            Image(systemName: gridMode.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private var editToggleButton: some View {
        Button {
            withAnimation {
                isEditing.toggle()
            }
        } label: {
            if isEditing {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.pink)
            } else {
                Image(systemName: "list.number")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var moreOptionsMenu: some View {
        Menu {
            addPageMenu

            Button {
                showingCoverPicker = true
            } label: {
                Label("修改封面", systemImage: "photo")
            }

            Divider()

            Button {
                showingTrash = true
            } label: {
                Label("垃圾篓", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private var addPageMenu: some View {
        Menu {
            Button {
                addNewPage(canvasType: "mannequin")
            } label: {
                Label("人台画布", systemImage: "tshirt")
            }

            Button {
                addNewPage(canvasType: "blank")
            } label: {
                Label("空白画布", systemImage: "square.dashed")
            }

            Button {
                showingBackgroundPicker = true
            } label: {
                Label("自定义图片", systemImage: "photo")
            }
        } label: {
            Label("新增书页", systemImage: "doc.badge.plus")
        }
    }
}
