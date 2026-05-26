//
//  SpaceBookToolbar.swift
//  ItemManager
//
//  空间书页工具栏
//

import SwiftUI

struct SpaceBookToolbar: ToolbarContent {
    @ObservedObject private var guideManager = AppFirstLaunchGuideManager.shared
    @Binding var isSidebarVisible: Bool
    @Binding var gridModeValue: Int
    @Binding var isEditing: Bool
    @Binding var isBatchEditing: Bool
    @Binding var selectedPages: Set<UUID>
    @Binding var showingNewPageAlert: Bool
    @Binding var showingCoverPicker: Bool
    @Binding var showingTrash: Bool
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
                    Picker("视图".appLocalized, selection: $gridModeValue) {
                        Label("单列".appLocalized, systemImage: "rectangle.grid.1x2")
                            .tag(1)
                        Label("双列".appLocalized, systemImage: "rectangle.grid.2x2")
                            .tag(2)
                        Label("三列".appLocalized, systemImage: "rectangle.grid.3x2")
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
                Group {
                    if guideManager.shouldUseCustomGuideMenu(for: .spaceBookDetailMore) {
                        Button {
                            presentGuideMenuForSpaceBookDetailMore()
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Menu {
                            Button {
                                showingNewPageAlert = true
                            } label: {
                                Label("新建空间搭配".appLocalized, systemImage: "plus")
                            }

                            Button {
                                showingCoverPicker = true
                            } label: {
                                Label("修改手帐封面".appLocalized, systemImage: "photo")
                            }

                            Button {
                                onRenameBook()
                            } label: {
                                Label("重命名手帐".appLocalized, systemImage: "pencil")
                            }

                            Divider()

                            // 批量编辑入口
                            Button {
                                isBatchEditing = true
                                selectedPages.removeAll()
                            } label: {
                                Label("批量编辑".appLocalized, systemImage: "checkmark.circle")
                            }

                            Divider()

                            Button {
                                showingTrash = true
                            } label: {
                                Label("垃圾篓".appLocalized, systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .captureGuideToolbarIconTarget(.spaceBookDetailMoreMenuButton)
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

    private func presentGuideMenuForSpaceBookDetailMore() {
        guideManager.presentGuideMenu(
            GuideMenuPresentationState(
                scenario: .spaceBookDetailMore,
                anchorKey: .spaceBookDetailMoreMenuButton,
                width: 240,
                submenuDepth: 0,
                items: [
                    .action(
                        title: "新建空间书页".appLocalized,
                        systemImage: "plus",
                        isHighlighted: true,
                        action: { showingNewPageAlert = true }
                    ),
                    .action(
                        title: "修改手帐封面".appLocalized,
                        systemImage: "photo",
                        action: { showingCoverPicker = true }
                    ),
                    .action(
                        title: "重命名手帐".appLocalized,
                        systemImage: "pencil",
                        action: onRenameBook
                    ),
                    .divider,
                    .action(
                        title: "批量编辑".appLocalized,
                        systemImage: "checkmark.circle",
                        action: {
                            isBatchEditing = true
                            selectedPages.removeAll()
                        }
                    ),
                    .divider,
                    .action(
                        title: "垃圾篓".appLocalized,
                        systemImage: "trash",
                        action: { showingTrash = true }
                    )
                ]
            )
        )
    }
}
