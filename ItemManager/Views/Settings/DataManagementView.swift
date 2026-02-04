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
                                Label(config.label, systemImage: config.systemImage)
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
                
                Section(header: Text("存储空间优化")) {
                    Button(action: performStorageCleanup) {
                        HStack {
                            Label("清理未使用的图片", systemImage: "trash")
                            Spacer()
                            Text("释放空间")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("数据管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
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
                    self.message = "生成备份失败: \(error.localizedDescription)"
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
            message = "无法访问文件 (Security Scoped Access Denied)"
            showingMessage = true
            return
        }
        
        isLoading = true
        loadingMessage = "正在准备恢复数据..."
        
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
                    message = "数据恢复失败: 备份文件无效或尚未从 iCloud 下载完成。请在 文件 App 中确保已下载该文件。"
                    showingMessage = true
                    try? FileManager.default.removeItem(at: tempURL)
                    return
                }
                
                // 在后台服务中进行解压和恢复
                loadingMessage = "正在恢复数据..."
                try await DataTransferService.shared.restoreBackup(from: tempURL, context: modelContext)
                
                // 清理临时文件
                try? FileManager.default.removeItem(at: tempURL)
                
                await MainActor.run {
                    message = "数据恢复成功"
                    showingMessage = true
                }
            } catch {
                print("Restore Error: \(error)")
                await MainActor.run {
                    // 如果是 BackupError，使用其详细描述，否则使用原生的
                    let errorDesc = (error as? BackupService.BackupError)?.errorDescription ?? error.localizedDescription
                    message = "数据恢复失败: \(errorDesc)"
                    showingMessage = true
                }
            }
        }
    }
    
    private func performStorageCleanup() {
        isLoading = true
        loadingMessage = "正在扫描并清理..."
        
        Task {
            // 注意：cleanOrphanedImages 需要在主线程访问 modelContext (因为它不是 Sendable)，
            // 但文件操作应该在后台？
            // ImageManager.cleanOrphanedImages 内部使用了 context.fetch，这必须在 context 所在的 actor 执行。
            // 我们的 modelContext 是 View 的 environment context，绑定在 MainActor。
            // ImageManager 也是 @MainActor。
            // 所以整个操作会在 MainActor 执行。
            // 对于大量文件遍历，可能会卡顿 UI。
            // 但考虑到是小内存设备优化，且文件操作 I/O 较慢，理想情况下应该 detach 到后台。
            // 但 context 传递比较麻烦。
            // 暂时在 MainActor 执行，因为 cleanOrphanedImages 已经是 MainActor 了。
            // 为了不阻塞 UI 渲染，可以 yield 一下？或者 ImageManager 内部优化。
            // 鉴于这是一个手动触发的维护操作，显示 Loading 遮罩是可以接受的。
            
            let count = ImageManager.shared.cleanOrphanedImages(context: modelContext)
            
            await MainActor.run {
                isLoading = false
                message = "清理完成，共删除了 \(count) 个未使用的图片文件。"
                showingMessage = true
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
