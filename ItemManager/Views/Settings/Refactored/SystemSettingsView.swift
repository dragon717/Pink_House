import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// 导入新手引导重置行组件
// 注意：NewbieGuideResetRow 定义在 GeneralSettingsView.swift 中

private enum LocalDataConfirmationAction: String, Identifiable {
    case exportCSV
    case backupData

    var id: String { rawValue }

    var confirmButtonTitle: String {
        switch self {
        case .exportCSV:
            return "确认导出"
        case .backupData:
            return "确认备份"
        }
    }

    var message: String {
        switch self {
        case .exportCSV:
            return "将生成当前数据的 CSV 文件，并打开系统分享面板。确定继续吗？"
        case .backupData:
            return "将把当前数据打包成本地备份文件，过程可能需要一点时间。确定继续吗？"
        }
    }
}

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
    @State private var pendingConfirmationAction: LocalDataConfirmationAction?
    
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

                NavigationLink(destination: LegalAndContactView()) {
                    Label("关于与协议", systemImage: "doc.text")
                }
                .adaptiveRow()
                
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("打开系统设置", systemImage: "gear")
                }
                .adaptiveRow()
                
                // 新手引导重置
                AppFirstLaunchGuideResetRow()
                    .adaptiveRow(showDivider: false)
            }
            
            // MARK: - 数据备份与恢复
            AdaptiveSection(header: "本地备份与恢复") {
                Button {
                    pendingConfirmationAction = .exportCSV
                } label: {
                    Label("导出 CSV (Export CSV)", systemImage: "tablecells")
                }
                .captureGuideTarget(.exportCSVEntry)
                .adaptiveRow()
                
                Button {
                    pendingConfirmationAction = .backupData
                } label: {
                    Label("备份数据 (Backup Data)", systemImage: "externaldrive.badge.plus")
                }
                .captureGuideTarget(.localBackupDataAction)
                .adaptiveRow()
                
                Button(action: {
                    NotificationCenter.default.post(name: .localRestoreTriggered, object: nil)
                    showingRestoreImporter = true
                }) {
                    Label("恢复数据 (Restore Data)", systemImage: "arrow.clockwise.icloud")
                }
                .foregroundColor(.red)
                .captureGuideTarget(.localRestoreDataAction)
                .adaptiveRow(showDivider: false)
            }
            
            // MARK: - 存储与性能
            AdaptiveSection(header: "存储与性能") {
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
        .alert("请再确认一次", isPresented: showingExportConfirmationAlert) {
            Button("取消", role: .cancel) { }
            Button(LocalDataConfirmationAction.exportCSV.confirmButtonTitle) {
                handleConfirmedAction(.exportCSV)
            }
        } message: {
            Text(LocalDataConfirmationAction.exportCSV.message)
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
        .overlay {
            if showingBackupConfirmationDialog {
                SystemSettingsBackupConfirmationDialog(
                    title: "请再确认一次",
                    message: LocalDataConfirmationAction.backupData.message,
                    confirmTitle: LocalDataConfirmationAction.backupData.confirmButtonTitle,
                    onCancel: { pendingConfirmationAction = nil },
                    onConfirm: { handleConfirmedAction(.backupData) }
                )
            }
        }
        .onAppear {
            NotificationCenter.default.post(name: .systemSettingsOpened, object: nil)
        }
        .onChange(of: pendingConfirmationAction) { _, newValue in
            if newValue != .backupData {
                clearLocalBackupConfirmationGuideTargets()
            }
        }
        .onDisappear {
            clearLocalBackupConfirmationGuideTargets()
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
        NotificationCenter.default.post(name: .exportCSVTriggered, object: nil)
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

    private var showingExportConfirmationAlert: Binding<Bool> {
        Binding(
            get: { pendingConfirmationAction == .exportCSV },
            set: { newValue in
                if !newValue {
                    pendingConfirmationAction = nil
                }
            }
        )
    }

    private var showingBackupConfirmationDialog: Bool {
        pendingConfirmationAction == .backupData
    }

    private func handleConfirmedAction(_ action: LocalDataConfirmationAction) {
        pendingConfirmationAction = nil
        switch action {
        case .exportCSV:
            prepareCSVExport()
        case .backupData:
            prepareBackup()
        }
    }
    
    private func prepareBackup() {
        NotificationCenter.default.post(name: .localBackupTriggered, object: nil)
        isLoading = true
        loadingMessage = "正在打包数据，备份需要时间，耐心等待，不要退出本界面..."
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

    private func clearLocalBackupConfirmationGuideTargets() {
        AppFirstLaunchGuideManager.shared.resetGuideTargetFrames([
            .localBackupConfirmationDialog,
            .localBackupConfirmButton
        ])
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
    
}

private struct SystemSettingsBackupConfirmationDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(spacing: 20) {
                VStack(spacing: 14) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.primary)

                    Text(message)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(5)
                }

                HStack(spacing: 16) {
                    Button(action: onCancel) {
                        Text("取消")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                    }

                    Button(action: onConfirm) {
                        Text(confirmTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(red: 0.72, green: 0.17, blue: 0.37))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(red: 0.97, green: 0.92, blue: 0.95))
                            .clipShape(Capsule())
                    }
                    .captureGuideTarget(.localBackupConfirmButton)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .captureGuideTarget(.localBackupConfirmationDialog)
        }
    }
}

struct LegalAndContactView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        AdaptiveSettingsView(title: "关于与协议") {
            AdaptiveSection(header: "协议中心") {
                Button {
                    openURL(LegalLinks.privacyURL)
                } label: {
                    Label("隐私政策", systemImage: "hand.raised")
                }
                .adaptiveRow()

                Button {
                    openURL(LegalLinks.userAgreementURL)
                } label: {
                    Label("用户协议", systemImage: "doc.text")
                }
                .adaptiveRow()

                Button {
                    openURL(LegalLinks.vipAgreementURL)
                } label: {
                    Label("会员协议", systemImage: "crown")
                }
                .adaptiveRow()

                Button {
                    openURL(LegalLinks.contactURL)
                } label: {
                    Label("联系我们（网页）", systemImage: "link")
                }
                .adaptiveRow(showDivider: false)
            }

            AdaptiveSection(header: "联系我们") {
                HStack {
                    Label("小红书", systemImage: "person.crop.circle")
                    Spacer()
                    Text(LegalLinks.xiaohongshuHandle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .adaptiveRow()

                HStack {
                    Label("小红书号", systemImage: "number")
                    Spacer()
                    Text(LegalLinks.xiaohongshuID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .adaptiveRow()

                Button {
                    openURL(LegalLinks.supportEmailURL)
                } label: {
                    Label("邮箱：huangsangmuniao@126.com", systemImage: "envelope")
                }
                .adaptiveRow(showDivider: false)
            }

            AdaptiveSection(header: "备案与版权") {
                HStack {
                    Label("备案号", systemImage: "doc.plaintext")
                    Spacer()
                    Text(LegalLinks.icpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .adaptiveRow()

                HStack {
                    Label("版权", systemImage: "c.circle")
                    Spacer()
                    Text(LegalLinks.copyrightText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .adaptiveRow(showDivider: false)
            }
        }
    }
}
