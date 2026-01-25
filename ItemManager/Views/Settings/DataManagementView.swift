//
//  DataManagementView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

// ShareSheet 包装器，用于在 SwiftUI 中使用 UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("useCloudSync") private var useCloudSync = false
    
    @State private var showingRestoreImporter = false
    @State private var showingRestoreAlert = false
    @State private var showRestartAlert = false
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var restoreURL: URL?
    
    @State private var message: String?
    @State private var showingMessage = false
    @State private var isLoading = false
    @State private var loadingMessage = ""
    
    var body: some View {
        ZStack {
            List {
                Section(header: Text("基础数据管理")) {
                    NavigationLink(destination: TagModelManagementView()) {
                        Label("标签管理 (Tags)", systemImage: "tag")
                    }
                    NavigationLink(destination: BrandManagementView()) {
                        Label("品牌管理 (Brands)", systemImage: "crown")
                    }
                }
                
                Section(header: Text("属性数据管理")) {
                    NavigationLink(destination: FieldManagementView(title: "类型管理", keyPath: \.types, isCommaSeparated: true)) {
                        Label("类型 (Types)", systemImage: "tshirt")
                    }
                    
                    NavigationLink(destination: FieldManagementView(title: "颜色管理", keyPath: \.colors, isCommaSeparated: true)) {
                        Label("颜色 (Colors)", systemImage: "paintpalette")
                    }
                    
                    NavigationLink(destination: FieldManagementView(title: "尺码管理", keyPath: \.sizes, isCommaSeparated: true)) {
                        Label("尺码 (Sizes)", systemImage: "ruler")
                    }
                    
                    NavigationLink(destination: FieldManagementView(title: "衣长管理", keyPath: \.length, isCommaSeparated: false)) {
                        Label("衣长 (Length)", systemImage: "arrow.up.and.down")
                    }
                    
                    NavigationLink(destination: FieldManagementView(title: "状况管理", keyPath: \.condition, isCommaSeparated: false)) {
                        Label("状况 (Condition)", systemImage: "star")
                    }
                    
                    NavigationLink(destination: FieldManagementView(title: "小物管理", keyPath: \.accessories, isCommaSeparated: true)) {
                        Label("小物 (Accessories)", systemImage: "bag")
                    }
                }
                
                Section(header: Text("备份与导出")) {
                    Button(action: prepareCSVExport) {
                        Label("导出 CSV (Export CSV)", systemImage: "tablecells")
                    }
                    
                    Button(action: prepareBackup) {
                        Label("备份数据 (Backup Data)", systemImage: "externaldrive.badge.plus")
                    }
                    
                    Button(action: { showingRestoreImporter = true }) {
                        Label("恢复数据 (Restore Data)", systemImage: "arrow.clockwise.icloud")
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("数据管理")
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: shareItems)
            }
            .fileImporter(isPresented: $showingRestoreImporter, allowedContentTypes: [UTType(filenameExtension: "save") ?? .data, .json]) { result in
                switch result {
                case .success(let url):
                    self.restoreURL = url
                    self.showingRestoreAlert = true
                case .failure(let error):
                    self.message = "选择文件失败: \(error.localizedDescription)"
                    self.showingMessage = true
                }
            }
            .alert("确认恢复数据？", isPresented: $showingRestoreAlert) {
                Button("取消", role: .cancel) { }
                Button("确认恢复", role: .destructive) {
                    performRestore()
                }
            } message: {
                Text("恢复操作将合并或覆盖当前数据。建议先备份当前数据。")
            }
            .alert("提示", isPresented: $showingMessage) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(message ?? "")
            }
            .alert("需重启应用", isPresented: $showRestartAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text("更改同步设置需要重启应用才能生效。请手动关闭并重新打开应用。")
            }
            
            // Loading Indicator
            if isLoading {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text(loadingMessage)
                        .foregroundColor(.white)
                        .font(.headline)
                }
                .padding(30)
                .background(Color(.systemGray6).opacity(0.9))
                .cornerRadius(12)
            }
        }
    }
    
    private func prepareCSVExport() {
        print("DataManagementView: 准备导出 CSV...")
        isLoading = true
        loadingMessage = "正在生成 CSV..."
        
        Task {
            do {
                let url = try DataTransferService.shared.exportToCSV(context: modelContext)
                await MainActor.run {
                    self.shareItems = [url]
                    self.showingShareSheet = true
                    self.isLoading = false
                }
            } catch {
                print("DataManagementView: CSV 导出错误: \(error)")
                await MainActor.run {
                    self.message = "生成 CSV 失败: \(error.localizedDescription)"
                    self.showingMessage = true
                    self.isLoading = false
                }
            }
        }
    }
    
    private func prepareBackup() {
        print("DataManagementView: 准备备份数据...")
        isLoading = true
        loadingMessage = "正在打包数据..."
        
        Task {
            do {
                // 现在 createBackup 是异步的，内部会在后台线程执行压缩，不会阻塞 UI
                let url = try await DataTransferService.shared.createBackup(context: modelContext)
                
                await MainActor.run {
                    self.shareItems = [url]
                    self.showingShareSheet = true
                    self.isLoading = false
                }
            } catch {
                print("DataManagementView: 备份生成错误: \(error)")
                await MainActor.run {
                    self.message = "生成备份失败: \(error.localizedDescription)"
                    self.showingMessage = true
                    self.isLoading = false
                }
            }
        }
    }
    
    private func performRestore() {
        guard let url = restoreURL else { return }
        
        // Accessing security scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            message = "无法访问文件"
            showingMessage = true
            return
        }
        
        isLoading = true
        loadingMessage = "正在恢复数据..."
        
        Task {
            defer {
                url.stopAccessingSecurityScopedResource()
                Task { @MainActor in self.isLoading = false }
            }
            
            do {
                try await DataTransferService.shared.restoreBackup(from: url, context: modelContext)
                await MainActor.run {
                    message = "数据恢复成功"
                    showingMessage = true
                }
            } catch {
                await MainActor.run {
                    message = "数据恢复失败: \(error.localizedDescription)"
                    showingMessage = true
                }
            }
        }
    }
}
