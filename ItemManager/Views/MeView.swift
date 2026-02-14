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
    @ObservedObject private var vipManager = VIPManager.shared
    
    @State private var isImporting = false
    @State private var showingImportAlert = false
    @State private var importMessage = ""
    @State private var showingCloudSyncSheet = false
    
    // Grid Layout
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // 1. VIP 卡片 (大卡片 1x2)
                    vipSection
                        .padding(.horizontal)
                    
                    // 2. 设置网格 (豆腐块)
                    LazyVGrid(columns: columns, spacing: 16) {
                        // 账户与云端 (1x1) - 聚合了登录和 iCloud
                        AccountCard(
                            authManager: authManager,
                            cloudManager: cloudManager
                        ) {
                            showingCloudSyncSheet = true
                        }
                        
                        // 梦幻衣橱
                        NavigationLink(destination: WardrobeSettingsView()) {
                            SettingsGridItem(
                                title: "梦幻衣橱",
                                subtitle: "外观 · 隐私 · 提醒",
                                icon: "tshirt",
                                iconColor: .pink
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 小世界
                        NavigationLink(destination: SmallWorldSettingsView()) {
                            SettingsGridItem(
                                title: "小世界",
                                subtitle: "风格 · 场景 · 3D",
                                icon: "globe.asia.australia.fill",
                                iconColor: .indigo
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 智能萌宠
                        NavigationLink(destination: PetAISettingsView()) {
                            SettingsGridItem(
                                title: "智能萌宠",
                                subtitle: "AI · 语音 · 形象",
                                icon: "pawprint.fill",
                                iconColor: .orange
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 彩蛋设置
                        EasterEggSettingsCard()
                        
                        // 马上来财设置
                        WealthHapticsSettingsCard()
                        
                        // 梦裙日历
                        CalendarSettingsCard()
                        
                        // 小组件
                        WidgetSettingsCard()
                        
                        // 回收站
                        NavigationLink(destination: RecycleBinView()) {
                            SettingsGridItem(
                                title: "回收站",
                                subtitle: "恢复 · 清空",
                                icon: "trash.fill",
                                iconColor: .red
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 系统与更多
                        NavigationLink(destination: SystemSettingsView()) {
                            SettingsGridItem(
                                title: "系统与更多",
                                subtitle: "组件 · 备份 · 通用",
                                icon: "gearshape.fill",
                                iconColor: .gray
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 开发测试 (仅 Debug)
                        #if DEBUG
                        NavigationLink(destination: TestEffectsView()) {
                            SettingsGridItem(
                                title: "实验室",
                                subtitle: "特效测试",
                                icon: "flask.fill",
                                iconColor: .green
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        #endif
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .padding(.top, 10)
            }
            .background {
                LiquidBackground()
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showingCloudSyncSheet) {
                CloudSyncSheetView(
                    authManager: authManager,
                    cloudManager: cloudManager,
                    modelContext: modelContext
                )
                .presentationDetents([.medium])
            }
            // 文件导入逻辑
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .alert("导入结果", isPresented: $showingImportAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(importMessage)
            }
            .onAppear {
                if authManager.isAuthenticated {
                    cloudManager.fetchLatestBackupMetadata()
                }
            }
        }
    }
    
    // MARK: - VIP Section
    @ViewBuilder
    private var vipSection: some View {
        if vipManager.isVIP {
            ZStack {
                VIPCardView(
                    vipNumber: vipManager.vipNumber ?? "88888888",
                    expireDate: vipManager.vipExpireDate,
                    isVIP: true,
                    cardStyle: vipManager.cardStyle
                )
                // 隐形链接
                NavigationLink(destination: VIPCenterView()) {
                    Color.clear
                }
            }
            .frame(height: 180) // 保持高度一致
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        } else {
            NavigationLink(destination: VIPCenterView()) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(Color(hex: "FFD700"))
                                .font(.title2)
                            Text("开通 VIP 会员")
                                .font(.title3)
                                .bold()
                                .foregroundStyle(.primary)
                        }
                        
                        Text("解锁尊享智能对话特权与专属卡片")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.gray)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 100) // 稍微矮一点
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color(hex: "FFD700").opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Import Logic
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            Task {
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
}

// MARK: - Cloud Sync Sheet
struct CloudSyncSheetView: View {
    @ObservedObject var authManager: AuthenticationManager
    @ObservedObject var cloudManager: CloudSyncManager
    let modelContext: ModelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showingLoginRequiredAlert = false
    @State private var showingSyncAlert = false
    @State private var showingRestoreSuccessAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                // 账户部分：在此处显示登录/用户信息
                Section {
                    UserInfoView(authManager: authManager, colorScheme: colorScheme)
                } header: {
                    Text("账户信息")
                }
                
                Section {
                    CloudSyncControlsView(
                        authManager: authManager,
                        cloudManager: cloudManager,
                        // 这里的 context 传递方式需要注意，CloudSyncControlsView 使用 Environment
                        // 我们在下面 .environment(\.modelContext, modelContext) 注入
                        showingLoginRequiredAlert: $showingLoginRequiredAlert,
                        showingSyncAlert: $showingSyncAlert
                    )
                } header: {
                    Text("iCloud 同步管理")
                } footer: {
                    Text("请确保您的 iCloud 空间充足。")
                }
            }
            .navigationTitle("账户与同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            // Alert logic copied from original MeView
            .alert("确认恢复", isPresented: $showingSyncAlert) {
                Button("取消", role: .cancel) { }
                Button("恢复", role: .destructive) {
                    Task {
                        let success = await cloudManager.restoreFromCloud(context: modelContext)
                        if success { showingRestoreSuccessAlert = true }
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
        }
        .environment(\.modelContext, modelContext) // Inject context
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

