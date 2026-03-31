//
//  BookShelfToolbar.swift
//  ItemManager
//
//  书架工具栏组件
//

import SwiftUI

struct BookShelfToolbar: ToolbarContent {
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
                    
                    Menu {
                        Button {
                            newBookName = ""
                            showingNewBookAlert = true
                        } label: {
                            Label("新建手帐", systemImage: "plus.rectangle.on.folder")
                        }

                        Button {
                            showingTrash = true
                        } label: {
                            Label("垃圾篓", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(.primary)
                            .onTapGesture {
                                NotificationCenter.default.post(name: .ootdShelfMoreMenuOpened, object: nil)
                            }
                    }
                    .captureGuideTarget(.ootdShelfMoreMenuButton)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            NotificationCenter.default.post(name: .ootdShelfMoreMenuOpened, object: nil)
                        }
                    )
                }
            }
        }
    }
}
