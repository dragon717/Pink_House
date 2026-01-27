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
    
    var body: some View {
        NavigationStack {
            List {
                // Section: Account & iCloud Sync
                Section {
                    // 1. Sign In / Account Info
                    if authManager.isAuthenticated {
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .foregroundStyle(.gray)
                            
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
                        
                        if let errorMessage = authManager.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal)
                        }
                    }
                    
                    // 2. iCloud Sync Controls
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
                            Text("云端无备份")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let error = cloudManager.syncError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        
                        HStack(spacing: 16) {
                            Button {
                                Task {
                                    await cloudManager.uploadBackup(modelContainer: modelContext.container)
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
                                showingSyncAlert = true
                            } label: {
                                Label("从云端恢复", systemImage: "icloud.and.arrow.down")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                            .disabled(cloudManager.isSyncing)
                        }
                    }
                    .padding(.vertical, 8)
                    
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
                            await cloudManager.restoreFromCloud(context: modelContext)
                        }
                    }
                } message: {
                    Text("从云端恢复将覆盖当前的本地数据（合并更新）。确定要继续吗？")
                }

                // Section 3: Feature Settings
                Section {
                    

                    NavigationLink(destination: GeneralSettingsView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.brown)
                                .font(.body)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading) {
                                Text("通用设置")
                                    .font(.body)
                                Text("语言、主题等")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    NavigationLink(destination: NotificationSettingsView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "bell")
                                .foregroundStyle(.brown)
                                .font(.body)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading) {
                                Text("通知设置")
                                    .font(.body)
                                Text("管理通知提醒")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    // NavigationLink(destination: PrivacySettingsView()) {
                    //     HStack(spacing: 12) {
                    //         Image(systemName: "lock")
                    //             .foregroundStyle(.brown)
                    //             .font(.body)
                    //             .frame(width: 24)
                    //         VStack(alignment: .leading) {
                    //             Text("隐私设置")
                    //                 .font(.body)
                    //             Text("数据与隐私")
                    //                 .font(.caption)
                    //                 .foregroundStyle(.secondary)
                    //         }
                    //     }
                    //     .padding(.vertical, 2)
                    // }
                    NavigationLink(destination: WidgetSettingsView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.3.group")
                                .foregroundStyle(.brown)
                                .font(.body)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading) {
                                Text("小组件设置")
                                    .font(.body)
                                    .outlined()
                                Text("自定义背景与添加教程")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .outlined()
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    NavigationLink(destination: DataManagementView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "externaldrive")
                                .foregroundStyle(.brown)
                                .font(.body)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading) {
                                Text("数据管理")
                                    .font(.body)
                                Text("备份与导出及属性管理")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    // 触感反馈设置 (跳转详情页)
                    NavigationLink(destination: HapticSettingsView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundStyle(.brown)
                                .font(.body)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading) {
                                Text("触感反馈")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text("震动开关与系统设置引导")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
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
            
            // 2. 测试与系统引导
            Section {
                Button {
                    hapticManager.playTestHaptic()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text("播放测试震动")
                            .foregroundStyle(.primary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("如果您在点击测试按钮时感觉不到震动：")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    HStack(alignment: .top) {
                        Text("1.")
                        Text("请确保手机未处于静音模式，或在设置中开启了“静音模式下震动”。")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    HStack(alignment: .top) {
                        Text("2.")
                        Text("请检查 iOS 系统设置中是否开启了“系统触感反馈”。")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                
                Button {
                    // 尝试跳转到“声音与触感”设置页
                    let urlString = "App-Prefs:root=Sounds"
                    if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    } else if let appSettings = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(appSettings)
                    }
                } label: {
                    HStack {
                        Text("前往系统设置 > 声音与触感")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("故障排查")
            } footer: {
                Text("注意：如果 iOS 的“系统触感反馈”被关闭，App 将无法提供任何震动体验。")
            }
        }
        .navigationTitle("触感反馈")
        .background {
            LiquidBackground()
        }
        .scrollContentBackground(.hidden)
    }
}
