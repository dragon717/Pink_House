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

    // Batch delete
    @Binding var isBatchEditingBooks: Bool
    @Binding var selectedBookIDs: Set<UUID>
    @Binding var showingBatchDeleteBooksAlert: Bool
    let books: [BookGroup]
    
    var body: some ToolbarContent {
        // Show mode picker when no book is selected
        if selectedBook == nil && !isSpatialBookSelected {
            ToolbarItem(placement: .principal) {
                if isBatchEditingBooks && viewMode == .planar {
                    Text("已选择 %d 项".appLocalized(selectedBookIDs.count))
                        .font(.headline)
                } else if FeatureUnlockManager.shared.isVisible(.spaceBook) {
                    Picker("模式".appLocalized, selection: $viewMode) {
                        ForEach(BookShelfView.ViewMode.allCases) { mode in
                            Text(mode.localizedTitle).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .captureGuideTarget(.spaceBookModeTabs)
                }
            }
        }
        
        // Only show top-level menu in Grid Mode (Planar)
        if viewMode == .planar && selectedBook == nil {
            ToolbarItem(placement: .topBarTrailing) {
                if isBatchEditingBooks {
                    batchEditingControls
                } else {
                    normalShelfControls
                }
            }
        }
    }

    private var normalShelfControls: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation {
                    isEditing.toggle()
                    if isEditing {
                        selectedBookIDs.removeAll()
                    }
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
                            Label("新建手帐".appLocalized, systemImage: "plus.rectangle.on.folder")
                        }

                        Divider()

                        Button {
                            beginBatchDelete()
                        } label: {
                            Label("批量删除".appLocalized, systemImage: "checkmark.circle")
                        }
                        .disabled(books.isEmpty)

                        Button {
                            showingTrash = true
                        } label: {
                            Label("垃圾篓".appLocalized, systemImage: "trash")
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

    private var batchEditingControls: some View {
        HStack(spacing: 16) {
            Button {
                toggleSelectAllBooks()
            } label: {
                Text((selectedBookIDs.count == books.count ? "取消全选" : "全选").appLocalized)
                    .font(.system(size: 16, weight: .medium))
            }
            .disabled(books.isEmpty)

            Button {
                if !selectedBookIDs.isEmpty {
                    showingBatchDeleteBooksAlert = true
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.red)
            }
            .disabled(selectedBookIDs.isEmpty)

            Button {
                withAnimation {
                    isBatchEditingBooks = false
                    selectedBookIDs.removeAll()
                }
            } label: {
                Text("完成".appLocalized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.pink)
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

    private func beginBatchDelete() {
        withAnimation {
            isEditing = false
            isBatchEditingBooks = true
            selectedBookIDs.removeAll()
        }
    }

    private func toggleSelectAllBooks() {
        if selectedBookIDs.count == books.count {
            selectedBookIDs.removeAll()
        } else {
            selectedBookIDs = Set(books.map(\.id))
        }
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
                        title: "新建手帐".appLocalized,
                        systemImage: "plus.rectangle.on.folder",
                        isHighlighted: true,
                        action: createOotdBook
                    ),
                    .divider,
                    .action(
                        title: "批量删除".appLocalized,
                        systemImage: "checkmark.circle",
                        action: beginBatchDelete
                    ),
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
