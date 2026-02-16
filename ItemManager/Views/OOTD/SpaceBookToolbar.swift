//
//  SpaceBookToolbar.swift
//  ItemManager
//
//  空间书页工具栏
//

import SwiftUI

struct SpaceBookToolbar: ToolbarContent {
    @Binding var isSidebarVisible: Bool
    @Binding var gridModeValue: Int
    @Binding var isEditing: Bool
    @Binding var showingNewPageAlert: Bool
    @Binding var showingCoverPicker: Bool
    var dismissAction: () -> Void
    var onRenameBook: () -> Void

    var body: some ToolbarContent {
        // Leading: Back button and Sidebar toggle
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 8) {
                

                // Toggle Sidebar Button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: isSidebarVisible ? "sidebar.left" : "sidebar.right")
                        .foregroundStyle(.primary)
                }
            }
        }

        // Trailing: View options, Edit, More
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                // View Options
                Menu {
                    Picker("视图", selection: $gridModeValue) {
                        Label("单列", systemImage: "rectangle.grid.1x2")
                            .tag(1)
                        Label("双列", systemImage: "rectangle.grid.2x2")
                            .tag(2)
                        Label("三列", systemImage: "rectangle.grid.3x2")
                            .tag(3)
                    }
                } label: {
                    Image(systemName: gridIconName)
                        .foregroundStyle(.primary)
                }

                // Custom Sort Edit Button
                Button {
                    withAnimation {
                        isEditing.toggle()
                    }
                } label: {
                    if isEditing {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.pink)
                    } else {
                        Image(systemName: "list.number")
                            .foregroundStyle(.primary)
                    }
                }

                // More Actions
                Menu {
                    Button {
                        showingNewPageAlert = true
                    } label: {
                        Label("新建空间搭配", systemImage: "plus")
                    }

                    Button {
                        showingCoverPicker = true
                    } label: {
                        Label("修改手帐封面", systemImage: "photo")
                    }
                    
                    Button {
                        onRenameBook()
                    } label: {
                        Label("重命名手帐", systemImage: "pencil")
                    }

                    Divider()

                    NavigationLink(destination: RecycleBinView(initialTab: 2)) {
                        Label("垃圾篓", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var gridIconName: String {
        switch gridModeValue {
        case 1: return "rectangle.grid.1x2"
        case 3: return "rectangle.grid.3x2"
        default: return "rectangle.grid.2x2"
        }
    }
}
