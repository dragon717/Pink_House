//
//  BookShelfToolbar.swift
//  ItemManager
//
//  书架工具栏组件
//

import SwiftUI

struct BookShelfToolbar: ToolbarContent {
    @ObservedObject private var guideManager = AppFirstLaunchGuideManager.shared
    @Binding var viewMode: BookShelfView.ViewMode
    @Binding var selectedBook: BookGroup?
    @Binding var isSpatialBookSelected: Bool
    @Binding var newBookName: String
    @Binding var showingNewBookAlert: Bool
    @Binding var showingTrash: Bool
    
    // Custom Sort Editing
    @Binding var isEditing: Bool
    
    var body: some ToolbarContent {
        // Show mode picker when no book is selected
        if selectedBook == nil && !isSpatialBookSelected {
            ToolbarItem(placement: .principal) {
                Picker("模式", selection: $viewMode) {
                    ForEach(BookShelfView.ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .captureGuideTarget(.spaceBookModeTabs)
            }
        }
        
        // Only show top-level menu in Grid Mode (Planar)
        if viewMode == .planar && selectedBook == nil {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    // Custom Sort Edit Button
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
                    
                    Group {
                        if guideManager.shouldUseCustomGuideMenu(for: .ootdShelfMore) {
                            Button {
                                presentGuideMenuForShelfMore()
                            } label: {
                                moreMenuIcon
                            }
                        } else {
                            Menu {
                                Button {
                                    createOotdBook()
                                } label: {
                                    Label("新建手帐", systemImage: "plus.rectangle.on.folder")
                                }

                                Button {
                                    showingTrash = true
                                } label: {
                                    Label("垃圾篓", systemImage: "trash")
                                }
                            } label: {
                                moreMenuIcon
                                    .onTapGesture {
                                        notifyShelfMoreMenuOpened()
                                    }
                            }
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    notifyShelfMoreMenuOpened()
                                }
                            )
                        }
                    }
                    .captureGuideTarget(.ootdShelfMoreMenuButton)
                }
            }
        }
    }

    private var moreMenuIcon: some View {
        Image(systemName: "ellipsis.circle")
            .font(.system(size: 22))
            .foregroundStyle(.primary)
    }

    private func notifyShelfMoreMenuOpened() {
        NotificationCenter.default.post(name: .ootdShelfMoreMenuOpened, object: nil)
    }

    private func createOotdBook() {
        newBookName = ""
        showingNewBookAlert = true
    }

    private func presentGuideMenuForShelfMore() {
        notifyShelfMoreMenuOpened()
        guideManager.presentGuideMenu(
            GuideMenuPresentationState(
                scenario: .ootdShelfMore,
                anchorKey: .ootdShelfMoreMenuButton,
                width: 220,
                submenuDepth: 0,
                items: [
                    .action(
                        title: "新建手帐",
                        systemImage: "plus.rectangle.on.folder",
                        isHighlighted: true,
                        action: createOotdBook
                    ),
                    .action(
                        title: "垃圾篓",
                        systemImage: "trash",
                        action: { showingTrash = true }
                    )
                ]
            )
        )
    }
}
