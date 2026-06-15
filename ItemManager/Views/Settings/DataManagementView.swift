//
//  DataManagementView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/20/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

private enum DataManagementConfirmationAction: String, Identifiable {
    case exportCSV
    case backupData

    var id: String { rawValue }

    var confirmButtonTitle: String {
        switch self {
        case .exportCSV:
            return "确认导出".appLocalized
        case .backupData:
            return "确认备份".appLocalized
        }
    }

    var message: String {
        switch self {
        case .exportCSV:
            return "将生成当前数据的 CSV 文件，并打开系统分享面板。确定继续吗？".appLocalized
        case .backupData:
            return "将把当前数据打包成本地备份文件，过程可能需要一点时间。确定继续吗？".appLocalized
        }
    }
}

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("useAggressiveMemoryOptimization") private var useAggressiveMemoryOptimization = true
    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared
    
    @State private var showingRestoreImporter = false
    @State private var showingRestoreAlert = false
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var restoreURL: URL?
    
    @State private var message: String?
    @State private var showingMessage = false
    @State private var isLoading = false
    @State private var loadingMessage = ""
    @State private var pendingConfirmationAction: DataManagementConfirmationAction?
    
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
                
                Section(header: Text("属性数据管理 (长按可排序)")) {
                    ForEach(visibilityManager.fieldOrder, id: \.self) { field in
                        let config = getFieldConfig(field)
                        HStack {
                            NavigationLink(destination: FieldManagementView(title: config.title, keyPath: config.keyPath, isCommaSeparated: config.isCommaSeparated)) {
                                Label(config.label.appLocalized, systemImage: config.systemImage)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                visibilityManager.toggleVisibility(field)
                            }) {
                                Image(systemName: visibilityManager.isVisible(field) ? "eye" : "eye.slash")
                                    .foregroundColor(visibilityManager.isVisible(field) ? .blue : .gray)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .onMove { indices, newOffset in
                        visibilityManager.moveField(from: indices, to: newOffset)
                    }
                }
                
                Section(header: Text("备份与导出")) {
                    Button {
                        pendingConfirmationAction = .exportCSV
                    } label: {
                        Label("导出 CSV (Export CSV)", systemImage: "tablecells")
                    }
                    
                    Button {
                        pendingConfirmationAction = .backupData
                    } label: {
                        Label("备份数据 (Backup Data)", systemImage: "externaldrive.badge.plus")
                    }
                    
                    Button(action: { showingRestoreImporter = true }) {
                        Label("恢复数据 (Restore Data)", systemImage: "arrow.clockwise.icloud")
                    }
                    .foregroundColor(.red)
                }
                
                Section(header: Text("高级设置")) {
                    Toggle(isOn: $useAggressiveMemoryOptimization) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("积极内存优化")
                                .font(.body)
                            Text("开启后将更积极地清理内存缓存，防止闪退，但可能导致图片需要重新加载。适合小内存设备或大量图片浏览场景。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.pink)
                }
                
                if #available(iOS 26.0, *) {
                    Section(header: Text("House（空间场景）")) {
                        Button(action: rebuildSpatialScene) {
                            HStack {
                                Label("重建空间场景", systemImage: "sparkles")
                                Spacer()
                                Text("iOS 26")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("数据管理".appLocalized)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .scrollContentBackground(.hidden)
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: shareItems)
            }
            .fileImporter(isPresented: $showingRestoreImporter, allowedContentTypes: [UTType(filenameExtension: "save") ?? .data, .json]) { result in
                switch result {
                case .success(let url):
                    self.restoreURL = url
                    self.showingRestoreAlert = true
                case .failure(let error):
                    self.message = "选择文件失败: %@".appLocalized(error.localizedDescription)
                    self.showingMessage = true
                }
            }
            .alert("请再确认一次".appLocalized, isPresented: showingConfirmationAlert, presenting: pendingConfirmationAction) { action in
                Button("取消".appLocalized, role: .cancel) { }
                Button(action.confirmButtonTitle) {
                    handleConfirmedAction(action)
                }
            } message: { action in
                Text(action.message)
            }
            .alert("确认恢复数据？".appLocalized, isPresented: $showingRestoreAlert) {
                Button("取消".appLocalized, role: .cancel) { }
                Button("确认恢复".appLocalized, role: .destructive) {
                    performRestore()
                }
            } message: {
                Text("恢复操作将合并或覆盖当前数据。建议先备份当前数据。".appLocalized)
            }
            .alert("提示".appLocalized, isPresented: $showingMessage) {
                Button("知道啦".appLocalized, role: .cancel) { }
            } message: {
                Text(message ?? "")
            }
            .onAppear {
                NotificationCenter.default.post(name: .dataBackupManagementOpened, object: nil)
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
        .background {
            LiquidBackground()
        }
    }

    private var showingConfirmationAlert: Binding<Bool> {
        Binding(
            get: { pendingConfirmationAction != nil },
            set: { newValue in
                if !newValue {
                    pendingConfirmationAction = nil
                }
            }
        )
    }

    private func handleConfirmedAction(_ action: DataManagementConfirmationAction) {
        pendingConfirmationAction = nil
        switch action {
        case .exportCSV:
            prepareCSVExport()
        case .backupData:
            prepareBackup()
        }
    }
    
    private func rebuildSpatialScene() {
        isLoading = true
        loadingMessage = "正在重建空间场景...".appLocalized
        Task {
            SpatialAssetManager.shared.clearAllCache()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                self.isLoading = false
                self.message = "已清理空间缓存，进入 House 时自动生效".appLocalized
                self.showingMessage = true
            }
        }
    }
    
    private func prepareCSVExport() {
        print("DataManagementView: 准备导出 CSV...")
        isLoading = true
        loadingMessage = "正在生成 CSV...".appLocalized
        
        // 获取 container 用于后台操作
        let container = modelContext.container
        
        Task {
            do {
                // 保存当前上下文以确保数据一致性（写入磁盘）
                try? modelContext.save()
                
                // 现在 exportToCSV 是异步的，内部使用背景上下文和 includePendingChanges = false
                let url = try await DataTransferService.shared.exportToCSV(container: container)
                await MainActor.run {
                    self.shareItems = [url]
                    self.showingShareSheet = true
                    self.isLoading = false
                }
            } catch {
                print("DataManagementView: CSV 导出错误: \(error)")
                await MainActor.run {
                    self.message = "生成 CSV 失败: %@".appLocalized(error.localizedDescription)
                    self.showingMessage = true
                    self.isLoading = false
                }
            }
        }
    }
    
    private func prepareBackup() {
        print("DataManagementView: 准备备份数据...")
        isLoading = true
        loadingMessage = "正在打包数据，备份需要时间，耐心等待，不要退出本界面...".appLocalized
        
        // Catch container on MainActor
        let container = modelContext.container
        
        Task {
            do {
                print("DataManagementView: 尝试保存当前上下文...")
                // 在启动后台导出前，必须确保主上下文的改动（尤其是删除）已持久化到磁盘，
                // 否则后台上下文可能会看到已在主线程逻辑上删除但尚未物理删除的对象，导致崩溃或数据状态不一致。
                try? modelContext.save()
                
                // 为了双重保险，稍微延迟一下，给 SwiftData/CoreData 的后台队列一点时间同步
                // 虽然理论上 try? save() 应该是同步阻塞直到写入，但在复杂并发下，给一点点 buffer 是安全的
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                
                print("DataManagementView: 上下文保存完毕")
                
                print("DataManagementView: 开始调用后台备份服务...")
                // 现在 createBackup 是异步的，内部会在后台线程执行压缩，不会阻塞 UI
                let url = try await DataTransferService.shared.createBackup(container: container)
                print("DataManagementView: 备份服务返回由: \(url)")
                
                await MainActor.run {
                    self.shareItems = [url]
                    self.showingShareSheet = true
                    self.isLoading = false
                }
            } catch {
                print("DataManagementView: 备份生成错误: \(error)")
                await MainActor.run {
                    self.message = "生成备份失败: %@".appLocalized(error.localizedDescription)
                    self.showingMessage = true
                    self.isLoading = false
                }
            }
        }
    }
    
    private func performRestore() {
        guard let url = restoreURL else { return }
        print("DataManagementView: Starting restore pre-check...")
        print("DataManagementView: Original URL: \(url)")
        
        // 访问安全通报资源（Security Scoped Resource）
        let canAccess = url.startAccessingSecurityScopedResource()
        print("DataManagementView: startAccessingSecurityScopedResource: \(canAccess)")
        
        guard canAccess else {
            message = "无法访问文件 (Security Scoped Access Denied)".appLocalized
            showingMessage = true
            return
        }
        
        isLoading = true
        loadingMessage = "正在准备恢复数据...".appLocalized
        
        Task {
            // 确保在任务结束时停止访问资源
            defer {
                url.stopAccessingSecurityScopedResource()
                Task { @MainActor in self.isLoading = false }
            }
            
            do {
                // 关键修复：将外部文件复制到本应用作用域内的临时目录
                // 这样可以规避 Sandbox 在跨进程或从 iCloud 读取时的 -54 (process may not map database) 错误
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent("restore_backup_\(UUID().uuidString).save")
                print("DataManagementView: Creating local copy at \(tempURL.path)")
                
                // 如果已存在则先删除（理论上 UUID 是唯一的）
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                
                // 执行复制
                try FileManager.default.copyItem(at: url, to: tempURL)
                
                // 验证复制后的文件权限和大小
                let isReadable = FileManager.default.isReadableFile(atPath: tempURL.path)
                let attr = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                let fileSize = attr[.size] as? Int64 ?? 0
                print("DataManagementView: Local copy pre-check - Readable: \(isReadable), Size: \(fileSize) bytes")
                
                if fileSize < 10 {
                    message = "数据恢复失败: 备份文件无效或尚未从 iCloud 下载完成。请在 文件 App 中确保已下载该文件。".appLocalized
                    showingMessage = true
                    try? FileManager.default.removeItem(at: tempURL)
                    return
                }
                
                // 在后台服务中进行解压和恢复
                loadingMessage = "正在恢复数据...".appLocalized
                try await DataTransferService.shared.restoreBackup(from: tempURL, context: modelContext)
                
                // 清理临时文件
                try? FileManager.default.removeItem(at: tempURL)
                
                await MainActor.run {
                    message = "数据恢复成功".appLocalized
                    showingMessage = true
                }
            } catch {
                print("Restore Error: \(error)")
                await MainActor.run {
                    // 处理不同类型的错误
                    let errorDesc: String
                    if let backupError = error as? BackupService.BackupError {
                        errorDesc = backupError.errorDescription ?? "未知错误".appLocalized
                    } else if let partialError = error as? BackupService.RestorePartialFailureError {
                        // 部分恢复失败，显示详细报告
                        errorDesc = partialError.result.errorReport
                    } else {
                        errorDesc = error.localizedDescription
                    }
                    message = "数据恢复失败: %@".appLocalized(errorDesc)
                    showingMessage = true
                }
            }
        }
    }
    
    private func getFieldConfig(_ field: ClothingField) -> (title: String, label: String, systemImage: String, keyPath: ReferenceWritableKeyPath<Clothing, String>, isCommaSeparated: Bool) {
        switch field {
        case .types:
            return ("类型管理", "类型 (Types)", "tshirt", \.types, true)
        case .colors:
            return ("颜色管理", "颜色 (Colors)", "paintpalette", \.colors, true)
        case .sizes:
            return ("尺码管理", "尺码 (Sizes)", "ruler", \.sizes, true)
        case .length:
            return ("衣长管理", "衣长 (Length)", "arrow.up.and.down", \.length, false)
        case .condition:
            return ("状况管理", "状况 (Condition)", "star", \.condition, false)
        case .accessories:
            return ("小物管理", "小物 (Accessories)", "bag", \.accessories, true)
        }
    }
}
