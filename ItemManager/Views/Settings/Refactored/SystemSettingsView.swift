import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SystemSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var languageManager = LanguageManager.shared
    @AppStorage("useAggressiveMemoryOptimization") private var useAggressiveMemoryOptimization = true
    
    // Backup & Restore State
    @State private var showingRestoreImporter = false
    @State private var showingRestoreAlert = false
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var restoreURL: URL?
    @State private var message: String?
    @State private var showingMessage = false
    @State private var isLoading = false
    @State private var loadingMessage = ""
    @State private var showingRestartAlert = false
    
    var body: some View {
        AdaptiveSettingsView(title: "系统与更多") {
            // MARK: - 桌面小组件 多余
            // AdaptiveSection(header: "桌面小组件") {
            //     NavigationLink(destination: WidgetSettingsView()) {
            //         Label("小组件背景与样式", systemImage: "rectangle.3.group")
            //     }
            //     .adaptiveRow(showDivider: false)
            // }
            
            // MARK: - 通用设置
            AdaptiveSection(header: "通用设置") {
                
                
                Picker("界面语言", selection: $languageManager.currentLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .onChange(of: languageManager.currentLanguage) { _, _ in
                    showingRestartAlert = true
                }
                .pickerStyle(.menu) // 明确指定 Menu 样式以适应非 List 环境
                .adaptiveRow()
                
                NavigationLink(destination: GeneralSoundHapticsSettingsView()) {
                    Label("音效与触感", systemImage: "speaker.wave.2.fill")
                }
                .adaptiveRow()
                
                NavigationLink(destination: PrivacySettingsView()) {
                    Label("隐私与系统权限", systemImage: "hand.raised")
                }
                .adaptiveRow()
                
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("打开系统设置", systemImage: "gear")
                }
                .adaptiveRow(showDivider: false)
            }
            
            // MARK: - 数据备份与恢复
            AdaptiveSection(header: "本地备份与恢复") {
                Button(action: prepareCSVExport) {
                    Label("导出 CSV (Export CSV)", systemImage: "tablecells")
                }
                .adaptiveRow()
                
                Button(action: prepareBackup) {
                    Label("备份数据 (Backup Data)", systemImage: "externaldrive.badge.plus")
                }
                .adaptiveRow()
                
                Button(action: { showingRestoreImporter = true }) {
                    Label("恢复数据 (Restore Data)", systemImage: "arrow.clockwise.icloud")
                }
                .foregroundColor(.red)
                .adaptiveRow(showDivider: false)
            }
            
            // MARK: - 存储与性能
            AdaptiveSection(header: "存储与性能") {
                Button(action: performStorageCleanup) {
                    HStack {
                        Label("清理未使用的图片", systemImage: "trash")
                        Spacer()
                        Text("释放空间")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .adaptiveRow()
                
                Toggle(isOn: $useAggressiveMemoryOptimization) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("积极内存优化")
                            .font(.body)
                        Text("开启后将更积极地清理内存缓存，防止闪退。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .adaptiveRow(showDivider: false)
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
        .alert("需要重启", isPresented: $showingRestartAlert) {
            Button("稍后") { }
        } message: {
            Text("语言更改将在下次启动应用时生效。")
        }
        // Loading Overlay
        .overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                    VStack(spacing: 20) {
                        ProgressView().scaleEffect(1.5).tint(.white)
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
    }
    
    // MARK: - Data Actions (Copied from DataManagementView)
    
    private func prepareCSVExport() {
        isLoading = true
        loadingMessage = "正在生成 CSV..."
        let container = modelContext.container
        Task {
            do {
                try? modelContext.save()
                let url = try await DataTransferService.shared.exportToCSV(container: container)
                await MainActor.run {
                    self.shareItems = [url]
                    self.showingShareSheet = true
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.message = "生成 CSV 失败: \(error.localizedDescription)"
                    self.showingMessage = true
                    self.isLoading = false
                }
            }
        }
    }
    
    private func prepareBackup() {
        isLoading = true
        loadingMessage = "正在打包数据..."
        let container = modelContext.container
        Task {
            do {
                try? modelContext.save()
                try await Task.sleep(nanoseconds: 200_000_000)
                let url = try await DataTransferService.shared.createBackup(container: container)
                await MainActor.run {
                    self.shareItems = [url]
                    self.showingShareSheet = true
                    self.isLoading = false
                }
            } catch {
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
        let canAccess = url.startAccessingSecurityScopedResource()
        guard canAccess else {
            message = "无法访问文件"
            showingMessage = true
            return
        }
        
        isLoading = true
        loadingMessage = "正在准备恢复数据..."
        
        Task {
            defer {
                url.stopAccessingSecurityScopedResource()
                Task { @MainActor in self.isLoading = false }
            }
            
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent("restore_backup_\(UUID().uuidString).save")
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                try FileManager.default.copyItem(at: url, to: tempURL)
                
                loadingMessage = "正在恢复数据..."
                try await DataTransferService.shared.restoreBackup(from: tempURL, context: modelContext)
                try? FileManager.default.removeItem(at: tempURL)
                
                await MainActor.run {
                    message = "数据恢复成功"
                    showingMessage = true
                }
            } catch {
                await MainActor.run {
                    // 处理不同类型的错误
                    let errorDesc: String
                    if let backupError = error as? BackupService.BackupError {
                        errorDesc = backupError.errorDescription ?? "未知错误"
                    } else if let partialError = error as? BackupService.RestorePartialFailureError {
                        // 部分恢复失败，显示详细报告
                        errorDesc = partialError.result.errorReport
                    } else {
                        errorDesc = error.localizedDescription
                    }
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
            let count = ImageManager.shared.cleanOrphanedImages(context: modelContext)
            await MainActor.run {
                isLoading = false
                message = "清理完成，共删除了 \(count) 个未使用的图片文件。"
                showingMessage = true
            }
        }
    }
}
