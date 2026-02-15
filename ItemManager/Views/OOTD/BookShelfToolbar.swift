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
    @Binding var showingBatchConfirmation: Bool
    @Binding var showingRepairConfirmation: Bool
    @Binding var showingBatchReplaceSheet: Bool
    
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
            }
        }
        
        // Only show top-level menu in Grid Mode (Planar)
        if viewMode == .planar && selectedBook == nil {
            ToolbarItem(placement: .topBarTrailing) {
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
                    
                    Divider()
                    
                    Button {
                        showingBatchConfirmation = true
                    } label: {
                        Label("批量处理小裙子", systemImage: "wand.and.stars")
                    }
                    
                    Button {
                        showingRepairConfirmation = true
                    } label: {
                        Label("修复数据", systemImage: "hammer")
                    }
                    
                    Button {
                        showingBatchReplaceSheet = true
                    } label: {
                        Label("一键替换主图", systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}
