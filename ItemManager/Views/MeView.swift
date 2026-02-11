import SwiftUI
import UniformTypeIdentifiers
import AuthenticationServices
import SwiftData

struct MeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var cloudManager = CloudSyncManager.shared
    
    @State private var isImporting = false
    @State private var showingImportAlert = false
    @State private var importMessage = ""
    @State private var showingHapticTestAlert = false
    @State private var showingSyncAlert = false
    @State private var syncAlertMessage = ""
    @State private var showingLoginRequiredAlert = false
    @State private var showingRestoreSuccessAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                // Section: Account & iCloud Sync
                Section {
                    UserInfoView(authManager: authManager, colorScheme: colorScheme)
                    
                    CloudSyncControlsView(
                        authManager: authManager,
                        cloudManager: cloudManager,
                        showingLoginRequiredAlert: $showingLoginRequiredAlert,
                        showingSyncAlert: $showingSyncAlert
                    )
                } header: {
                    Text("账户与同步")
                }
                .onAppear {
                    // 视图显示时检查云端状态
                    if authManager.isAuthenticated {
                        cloudManager.fetchLatestBackupMetadata()
                    }
                }
                .alert("确认恢复", isPresented: $showingSyncAlert) {
                    Button("取消", role: .cancel) { }
                    Button("恢复", role: .destructive) {
                        Task {
                            let success = await cloudManager.restoreFromCloud(context: modelContext)
                            if success {
                                showingRestoreSuccessAlert = true
                            }
                        }
                    }
                } message: {
                    Text("从云端恢复将覆盖当前的本地数据（合并更新）。确定要继续吗？")
                }
                .alert("需要登录", isPresented: $showingLoginRequiredAlert) {
                    Button("确定", role: .cancel) { }
                } message: {
                    Text("请先登录 iCloud 账户以使用云同步功能。")
                }
                .alert("恢复成功", isPresented: $showingRestoreSuccessAlert) {
                    Button("确定", role: .cancel) { }
                } message: {
                    Text("云端数据已成功恢复到本地。")
                }

                // Section 3: Feature Settings
                Section {
                    NavigationLink(destination: GeneralSettingsView()) {
                        SettingsRow(icon: "slider.horizontal.3", title: "通用设置", subtitle: "语言、主题、个性化等")
                    }
                    NavigationLink(destination: NotificationSettingsView()) {
                        SettingsRow(icon: "bell", title: "通知设置", subtitle: "管理通知提醒")
                    }
                    
                    NavigationLink(destination: PrivacySettingsView()) {
                        SettingsRow(icon: "hand.raised", title: "隐私设置", subtitle: "管理价格显示与权限")
                    }
                    
                    NavigationLink(destination: WidgetSettingsView()) {
                        SettingsRow(icon: "rectangle.3.group", title: "小组件设置", subtitle: "自定义背景与添加教程")
                    }
                    NavigationLink(destination: DataManagementView()) {
                        SettingsRow(icon: "externaldrive", title: "数据管理", subtitle: "备份与导出及属性管理")
                    }
                    NavigationLink(destination: RecycleBinView()) {
                        SettingsRow(icon: "trash", title: "回收站", subtitle: "恢复已删除的裙子")
                    }
                    // 触感反馈设置 (跳转详情页)
                    NavigationLink(destination: HapticSettingsView()) {
                        SettingsRow(icon: "waveform.path.ecg", title: "音效和触感反馈", subtitle: "震动开关与系统设置引导")
                    }

                    // 应用系统设置
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "gear.circle")
                                .foregroundStyle(.brown)
                                .font(.body)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading) {
                                Text("应用系统设置")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text("管理通知、权限与隐私")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Label("功能设置", systemImage: "gearshape")
                        .outlined()
                }
                
                // Section: Test Project
                #if DEBUG
                Section {
                    NavigationLink(destination: TestEffectsView()) {
                        SettingsRow(icon: "flask", title: "特效测试实验室", subtitle: "预览特效与实验功能")
                    }
                } header: {
                    Label("开发测试", systemImage: "hammer")
                        .outlined()
                }
                #endif
            }
            .scrollContentBackground(.hidden)
            .background {
                LiquidBackground()
            }
            .navigationTitle("我的")
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.data], // 允许所有数据类型，或者自定义类型
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    
                    Task {
                        // 在 Task 内部获取权限，确保覆盖整个异步操作
                        guard url.startAccessingSecurityScopedResource() else {
                            importMessage = "无法访问文件，请检查权限"
                            showingImportAlert = true
                            return
                        }
                        
                        defer { url.stopAccessingSecurityScopedResource() }
                        
                        do {
                            let result = try await ImportManager.shared.importBackup(from: url, context: modelContext)
                            importMessage = "导入完成\n成功: \(result.successCount)\n失败: \(result.failCount)"
                            if !result.errors.isEmpty {
                                importMessage += "\n\n错误详情:\n" + result.errors.prefix(3).joined(separator: "\n")
                            }
                        } catch {
                            importMessage = "导入失败: \(error.localizedDescription)"
                        }
                        showingImportAlert = true
                    }
                    
                case .failure(let error):
                    importMessage = "选择文件失败: \(error.localizedDescription)"
                    showingImportAlert = true
                }
            }
            .alert("导入结果", isPresented: $showingImportAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(importMessage)
            }
        }
    }
}

// MARK: - Subviews

struct UserInfoView: View {
    @ObservedObject var authManager: AuthenticationManager
    let colorScheme: ColorScheme
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                HStack(spacing: 12) {
                    UserAvatarView(
                        givenName: authManager.givenName,
                        familyName: authManager.familyName,
                        size: 40
                    )
                    
                    VStack(alignment: .leading) {
                        Text(authManager.givenName.isEmpty ? "已登录用户" : "\(authManager.familyName)\(authManager.givenName)")
                            .font(.headline)
                        if !authManager.email.isEmpty {
                            Text(authManager.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    
                    Button("退出") {
                        authManager.signOut()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            } else {
                if authManager.isLoggingIn {
                    HStack {
                        Spacer()
                        ProgressView("正在登录...")
                            .controlSize(.regular)
                        Spacer()
                    }
                    .frame(height: 44)
                    .padding(.vertical, 4)
                } else {
                    SignInWithAppleButton(
                        onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                        },
                        onCompletion: { result in
                            authManager.handleSignIn(result: result)
                        }
                    )
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 44)
                    .padding(.vertical, 4)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                }
                
                if let errorMessage = authManager.errorMessage {
                    Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct CloudSyncControlsView: View {
    @ObservedObject var authManager: AuthenticationManager
    @ObservedObject var cloudManager: CloudSyncManager
    @Environment(\.modelContext) private var modelContext // Use environment instead of passing
    @Binding var showingLoginRequiredAlert: Bool
    @Binding var showingSyncAlert: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "icloud")
                    .foregroundStyle(.blue)
                Text("iCloud 同步")
                    .font(.headline)
                Spacer()
                if cloudManager.isSyncing {
                    ProgressView()
                }
            }
            
            if let lastDate = cloudManager.lastCloudBackupDate {
                Text("云端备份: \(lastDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Text("云端无备份")
                //     .font(.caption)
                //     .foregroundStyle(.secondary)
            }
            
            if let error = cloudManager.syncError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            HStack(spacing: 16) {
                Button {
                    if !authManager.isAuthenticated {
                        showingLoginRequiredAlert = true
                    } else {
                        Task {
                            await cloudManager.uploadBackup(modelContainer: modelContext.container)
                        }
                    }
                } label: {
                    Label("备份到云端", systemImage: "icloud.and.arrow.up")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(cloudManager.isSyncing)
                
                Button {
                    if !authManager.isAuthenticated {
                        showingLoginRequiredAlert = true
                    } else {
                        showingSyncAlert = true
                    }
                } label: {
                    Label("从云端恢复", systemImage: "icloud.and.arrow.down")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(cloudManager.isSyncing)
            }
            
            
        }
        .padding(.vertical, 8)
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.brown)
                .font(.body)
                .frame(width: 24)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 独立的触感反馈设置页
struct HapticSettingsView: View {
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var audioManager = AudioManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    @AppStorage("isCelebrationHapticsEnabled") private var isCelebrationHapticsEnabled = true
    @AppStorage("isCelebrationSoundEnabled") private var isCelebrationSoundEnabled = true
    
    var body: some View {
        List {
            // 1. 应用内开关
            Section {
                Toggle(isOn: $hapticManager.isHapticsEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                            .foregroundStyle(.brown)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("应用内触感")
                                .foregroundStyle(.primary)
                            Text("控制金豆滚动、碰撞的震动反馈")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("功能开关")
            }
            
            // 2. 音量调节 (新增)
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    
                    
                    Toggle(isOn: $audioManager.useiPhoneMicWithHeadphones) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("耳机模式使用手机收音")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("佩戴耳机时，强制使用手机麦克风以获得更好音质")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundStyle(.pink)
                            .frame(width: 24)
                        Text("萌宠 BGM: \(Int(audioManager.bgmVolume * 100))%")
                    }
                    Slider(value: $audioManager.bgmVolume, in: 0...1) {
                        Text("BGM 音量")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill").font(.caption)
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill").font(.caption)
                    }
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.green)
                            .frame(width: 24)
                        Text("萌宠语音: \(Int(audioManager.petVoiceVolume * 100))%")
                    }
                    Slider(value: $audioManager.petVoiceVolume, in: 0...1.5) { // 允许稍微放大一点
                        Text("语音音量")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill").font(.caption)
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill").font(.caption)
                    }
                }
                .padding(.vertical, 4)
                
            } header: {
                Text("音量调节")
            }
            
            // 3. 彩蛋特效设置
            Section {
                Toggle(isOn: $isCelebrationHapticsEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("彩蛋震动")
                                .foregroundStyle(.primary)
                            Text("庆祝特效时的震动反馈")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Toggle(isOn: $isCelebrationSoundEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(.pink)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("彩蛋音效")
                                .foregroundStyle(.primary)
                            Text("庆祝特效时的爆炸与礼花声")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                VStack {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                            .frame(width: 24)
                        Text("彩蛋音量: \(Int(soundManager.celebrationVolume * 100))%")
                        Spacer()
                    }
                    Slider(value: $soundManager.celebrationVolume, in: 0...1) {
                        Text("彩蛋音量")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill").font(.caption)
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill").font(.caption)
                    }
                }
            } header: {
                Text("彩蛋特效")
            }
            
            // 3. 系统设置引导
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "gear")
                            .foregroundStyle(.blue)
                        Text("前往系统设置")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
                
                Text("如果应用内开启后仍无震动，请检查：\n1. 系统设置 > 声音与触感 > 系统触感反馈 是否开启\n2. 手机是否处于静音模式（部分震动在静音下可能不工作）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } header: {
                Text("系统设置")
            }
        }
        .scrollContentBackground(.hidden)
        .background {
            LiquidBackground()
        }
        .navigationTitle("音效和触感反馈设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
