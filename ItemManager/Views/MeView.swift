import SwiftUI
import UniformTypeIdentifiers
import AuthenticationServices
import SwiftData
import CloudKit

// MARK: - 设置功能导航目的地
enum SettingsNavigationDestination: String, Identifiable {
    case themeCustomize = "themeCustomize"
    case themeSkinStore = "themeSkinStore"
    case widgetCustomize = "widgetCustomize"
    case batchImport = "batchImport"

    var id: String { rawValue }
}

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
    @State private var showMagicTasks = false
    @State private var navigationDestination: String? = nil
    @State private var isAdminUser = false
    @State private var isCheckingAdmin = true

    // Grid Layout
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    private var shouldShowAdminEntries: Bool {
        !isCheckingAdmin && isAdminUser
    }
    
    // MARK: - 魔法任务卡片背景（适配主题色）
    private var magicTaskCardBackground: some View {
        let isDark = colorScheme == .dark
        let cardColors = themeManager.themeColorConfig.currentTheme(forDarkMode: isDark).cardColors(forDarkMode: isDark)
        
        return Group {
            switch themeManager.cardStyle {
            case .solid:
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardColors.backgroundRGBA.color)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            case .transparent:
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardColors.backgroundRGBA.color.opacity(themeManager.transparentOpacity))
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            case .fullyTransparent:
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardColors.backgroundRGBA.color.opacity(0.3))
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            case .tinted:
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(cardColors.backgroundRGBA.color.opacity(themeManager.tintOpacity))
                    )
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            }
        }
    }
    
    // MARK: - 魔法任务卡片边框（适配主题色）
    private var magicTaskCardOverlay: some View {
        let isDark = colorScheme == .dark
        let cardColors = themeManager.themeColorConfig.currentTheme(forDarkMode: isDark).cardColors(forDarkMode: isDark)
        
        return RoundedRectangle(cornerRadius: 16)
            .stroke(cardColors.accentRGBA.color.opacity(isDark ? 0.3 : 0.2), lineWidth: 1)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                    // 1. VIP 卡片 (大卡片 1x2)
                    vipSection
                        .padding(.horizontal)

                    // 2. 魔法任务入口
                    NavigationLink(destination: MagicTasksView(), isActive: $showMagicTasks) {
                        HStack(spacing: 16) {
                            ThemeSkinIconBadge(
                                systemName: "sparkles",
                                fallbackColor: .pink,
                                size: 44,
                                symbolSize: 20
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("魔法任务")
                                    .font(.headline)
                                    .foregroundStyle(themeManager.primaryTextColor)
                                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                                Text("完成任务解锁更多功能")
                                    .font(.caption)
                                    .foregroundStyle(themeManager.secondaryTextColor)
                                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(themeManager.secondaryTextColor)
                        }
                        .padding()
                        .themeSkinSectionCard(cornerRadius: 16)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal)
                    
                    // 3. 设置网格 (豆腐块)
                    LazyVGrid(columns: columns, spacing: 16) {
                        // 账户与云端 (1x1) - 聚合了登录和 iCloud
                        AccountCard(
                            authManager: authManager,
                            cloudManager: cloudManager
                        ) {
                            showingCloudSyncSheet = true
                        }
                        .captureGuideTarget(.accountSyncEntry)
                        
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
                        .captureGuideTarget(.wardrobeSettingsEntry)
                        
                        // House
                        NavigationLink(destination: SmallWorldSettingsView()) {
                            SettingsGridItem(
                                title: "House",
                                subtitle: "风格 · 场景 · 3D",
                                icon: "house.fill",
                                iconColor: .indigo
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
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

                        // 主题
                        NavigationLink(destination: ThemeSkinStoreView()) {
                            SettingsGridItem(
                                title: "主题",
                                subtitle: "主题商店 · 已购主题",
                                icon: "sparkles.rectangle.stack.fill",
                                iconColor: .pink
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        NavigationLink(destination: MagicColorSettingsView()) {
                            SettingsGridItem(
                                title: "主题配色",
                                subtitle: "配色方案 · 魔法皮肤",
                                icon: "wand.and.stars",
                                iconColor: .purple
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .captureGuideTarget(.themeCustomizeEntry)
                        
                        // 底部导航设置
                        NavigationLink(destination: FavoriteMenuSettingsView()) {
                            SettingsGridItem(
                                title: "底部导航",
                                subtitle: "四个位置 · 快捷直达",
                                icon: "star.fill",
                                iconColor: .yellow
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 小组件
                        WidgetSettingsCard()
                            .captureGuideTarget(.widgetCustomizeEntry)
                        
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
                        .captureGuideTarget(.systemSettingsEntry)

                        NavigationLink(destination: LegalAndContactView()) {
                            SettingsGridItem(
                                title: "联系我们",
                                subtitle: "协议 · 备案 · 邮箱",
                                icon: "envelope.fill",
                                iconColor: .mint
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        if shouldShowAdminEntries {
                            NavigationLink(destination: NoticeAdminView()) {
                                SettingsGridItem(
                                    title: "公告管理",
                                    subtitle: "草稿 · 发布 · 云端同步",
                                    icon: "megaphone.fill",
                                    iconColor: .blue
                                )
                            }
                            .buttonStyle(PlainButtonStyle())

                            NavigationLink(destination: TestEffectsView()) {
                                SettingsGridItem(
                                    title: "实验室",
                                    subtitle: "特效 · 调试 · 管理员",
                                    icon: "flask.fill",
                                    iconColor: .green
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
            .padding(.top, 10)
        }
        .background {
            LiquidBackground(themeSkinWallpaperContext: .me)
        }
        .navigationTitle("我")
        .navigationDestination(for: String.self) { destination in
            switch destination {
            case "themeCustomize":
                MagicColorSettingsView()
            case "themeSkinStore":
                ThemeSkinStoreView()
            case "customColorPersonalization":
                MagicColorSettingsViewWithCustomTab()
            case "widgetCustomize":
                WidgetSettingsView()
            case "batchImport":
                WardrobeSettingsView()
            case "dataBackup", "localFileBackupRestore", "exportCSV":
                SystemSettingsView()
            case "cloudSync", "cloudFileBackupRestore":
                EmptyView()
            default:
                EmptyView()
            }
        }
        .sheet(isPresented: $showingCloudSyncSheet) {
            CloudSyncSheetView(
                authManager: authManager,
                cloudManager: cloudManager,
                modelContext: modelContext
            )
            .presentationDetents([.fraction(0.9)])
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
            refreshAdminAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMagicTasks)) { _ in
            showMagicTasks = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSettingsFeature)) { notification in
            if let feature = notification.userInfo?["feature"] as? String {
                if feature == "cloudSync" || feature == "cloudFileBackupRestore" {
                    showingCloudSyncSheet = true
                } else {
                    navigationDestination = feature
                }
            }
        }
        .overlay {
            hiddenNavigationLinks
        }
    }

    // MARK: - 隐藏的 NavigationLink 用于编程导航
    private var hiddenNavigationLinks: some View {
        Group {
            NavigationLink(destination: ThemeSkinStoreView(), tag: "themeSkinStore", selection: $navigationDestination) {
                EmptyView()
            }
            NavigationLink(destination: MagicColorSettingsViewWithMagicTab(), tag: "themeCustomize", selection: $navigationDestination) {
                EmptyView()
            }
            NavigationLink(destination: MagicColorSettingsViewWithCustomTab(), tag: "customColorPersonalization", selection: $navigationDestination) {
                EmptyView()
            }
            NavigationLink(destination: WidgetSettingsView(), tag: "widgetCustomize", selection: $navigationDestination) {
                EmptyView()
            }
            NavigationLink(destination: WardrobeSettingsView(), tag: "batchImport", selection: $navigationDestination) {
                EmptyView()
            }
            NavigationLink(destination: SystemSettingsView(), tag: "dataBackup", selection: $navigationDestination) {
                EmptyView()
            }
            NavigationLink(destination: SystemSettingsView(), tag: "localFileBackupRestore", selection: $navigationDestination) {
                EmptyView()
            }
            NavigationLink(destination: SystemSettingsView(), tag: "exportCSV", selection: $navigationDestination) {
                EmptyView()
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
                .captureGuideTarget(.aiAnalysisVIPCard)
                // 隐形链接
                NavigationLink(destination: VIPCenterView()) {
                    Color.clear
                }
            }
            .frame(height: 220) // 与 VIPCardView 真实容器高度保持一致，避免引导高亮取框偏小
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        } else {
            NavigationLink(destination: VIPCenterView()) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ThemeSkinIconBadge(
                                systemName: "crown.fill",
                                fallbackColor: Color(hex: "FFD700"),
                                size: 40,
                                symbolSize: 18
                            )
                            Text("开通 VIP 会员")
                                .font(.title3)
                                .bold()
                                .foregroundStyle(.primary)
                                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                        }
                        
                        Text("解锁尊享智能对话特权与专属卡片")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.gray)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 100) // 稍微矮一点
                .themeSkinSectionCard(cornerRadius: 20)
            }
            .buttonStyle(PlainButtonStyle())
            .captureGuideTarget(.aiAnalysisVIPCard)
        }
    }
    
    // MARK: - Import Logic
    private func refreshAdminAccess() {
        isCheckingAdmin = true

        Task {
            let hasAdminAccess = await NoticeCloudKitService.shared.isAdmin()
            await MainActor.run {
                isAdminUser = hasAdminAccess
                isCheckingAdmin = false
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            Task {
                guard url.startAccessingSecurityScopedResource() else {
                    importMessage = "无法访问文件，请检查权限".appLocalized
                    showingImportAlert = true
                    return
                }
                
                defer { url.stopAccessingSecurityScopedResource() }
                
                do {
                    let result = try await ImportManager.shared.importBackup(from: url, context: modelContext)
                    importMessage = "导入完成\n成功: %@\n失败: %@".appLocalized(
                        String(result.successCount),
                        String(result.failCount)
                    )
                    if !result.errors.isEmpty {
                        importMessage += "\n\n" + "错误详情:\n%@".appLocalized(result.errors.prefix(3).joined(separator: "\n"))
                    }
                } catch {
                    importMessage = "导入失败: %@".appLocalized(error.localizedDescription)
                }
                showingImportAlert = true
            }
            
        case .failure(let error):
            importMessage = "选择文件失败: %@".appLocalized(error.localizedDescription)
            showingImportAlert = true
        }
    }
}

// MARK: - Cloud Sync Sheet
enum CloudFileConfirmationAction: String, Identifiable {
    case uploadBackup

    var id: String { rawValue }

    var confirmButtonTitle: String {
        "确认备份".appLocalized
    }

    var message: String {
        "将把当前本地数据上传为一份云端备份。若云端已有旧备份，会以最新上传内容为准。确定继续吗？".appLocalized
    }
}

struct CloudSyncSheetView: View {
    @ObservedObject var authManager: AuthenticationManager
    @ObservedObject var cloudManager: CloudSyncManager
    let modelContext: ModelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showingLoginRequiredAlert = false
    @State private var showingSyncAlert = false
    @State private var showingRestoreSuccessAlert = false
    @State private var showingProfileEdit = false
    @State private var showingSignOutConfirm = false
    @State private var pendingConfirmationAction: CloudFileConfirmationAction?
    
    var body: some View {
        NavigationStack {
            List {
                // 账户部分：在此处显示登录/用户信息
                Section {
                    EnhancedUserInfoView(
                        authManager: authManager,
                        colorScheme: colorScheme,
                        onEditProfile: { showingProfileEdit = true },
                        onSignOut: { showingSignOutConfirm = true }
                    )
                } header: {
                    Text("账户信息")
                }
                
                Section {
                    CloudSyncControlsView(
                        authManager: authManager,
                        cloudManager: cloudManager,
                        showingLoginRequiredAlert: $showingLoginRequiredAlert,
                        showingSyncAlert: $showingSyncAlert,
                        pendingConfirmationAction: $pendingConfirmationAction
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
            .alert("请再确认一次", isPresented: showingConfirmationAlert, presenting: pendingConfirmationAction) { action in
                Button("取消", role: .cancel) { }
                Button(action.confirmButtonTitle) {
                    handleConfirmedAction(action)
                }
            } message: { action in
                Text(action.message)
            }
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
            .alert("确认退出", isPresented: $showingSignOutConfirm) {
                Button("取消", role: .cancel) { }
                Button("退出", role: .destructive) {
                    authManager.signOut()
                }
            } message: {
                Text("退出后将无法使用 iCloud 同步功能，确定要退出吗？")
            }
            .sheet(isPresented: $showingProfileEdit) {
                UserProfileEditView(authManager: authManager)
            }
        }
        .onAppear {
            NotificationCenter.default.post(name: .cloudSyncSheetOpened, object: nil)
        }
        .environment(\.modelContext, modelContext) // Inject context
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

    private func handleConfirmedAction(_ action: CloudFileConfirmationAction) {
        pendingConfirmationAction = nil
        switch action {
        case .uploadBackup:
            Task {
                await cloudManager.uploadBackup(modelContainer: modelContext.container)
            }
        }
    }
}

// MARK: - 增强版用户信息视图
struct EnhancedUserInfoView: View {
    @ObservedObject var authManager: AuthenticationManager
    let colorScheme: ColorScheme
    let onEditProfile: () -> Void
    let onSignOut: () -> Void
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                VStack(spacing: 20) {
                    // 头像和编辑按钮
                    Button(action: onEditProfile) {
                        ZStack {
                            UserAvatarView(
                                givenName: authManager.givenName,
                                familyName: authManager.familyName,
                                customAvatarPath: authManager.customAvatarPath,
                                size: 80
                            )
                            
                            // 编辑图标
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 28, height: 28)
                                        
                                        Image(systemName: "pencil")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white)
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(Color(.systemBackground), lineWidth: 2)
                                    )
                                }
                            }
                            .frame(width: 80, height: 80)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // 用户信息
                    VStack(spacing: 8) {
                        Text(authManager.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        if !authManager.email.isEmpty {
                            Text(authManager.email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        // 显示Apple ID名称（如果有自定义昵称）
                        if !authManager.customNickname.isEmpty && !authManager.givenName.isEmpty {
                            Text("Apple ID: \(authManager.givenName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    
                    // 操作按钮
                    HStack(spacing: 16) {
                        Button(action: onEditProfile) {
                            Label("编辑资料", systemImage: "pencil")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                        
                        Button(action: onSignOut) {
                            Label("退出", systemImage: "arrow.right.square")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(.top, 8)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
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
                    .environment(\.locale, LanguageManager.shared.locale)
                    .captureGuideTarget(.cloudAppleSignInButton)
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


// MARK: - Subviews

struct UserInfoView: View {
    @ObservedObject var authManager: AuthenticationManager
    let colorScheme: ColorScheme
    @State private var showingProfileEdit = false
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                HStack(spacing: 12) {
                    Button {
                        showingProfileEdit = true
                    } label: {
                        UserAvatarView(
                            givenName: authManager.givenName,
                            familyName: authManager.familyName,
                            customAvatarPath: authManager.customAvatarPath,
                            size: 50
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(authManager.displayName)
                            .font(.headline)
                        if !authManager.email.isEmpty {
                            Text(authManager.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    
                    Button {
                        showingProfileEdit = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.vertical, 8)
                .sheet(isPresented: $showingProfileEdit) {
                    UserProfileEditView(authManager: authManager)
                }
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
                    .environment(\.locale, LanguageManager.shared.locale)
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
    @StateObject private var migrationManager = SwiftDataMigrationManager.shared
    @Binding var showingLoginRequiredAlert: Bool
    @Binding var showingSyncAlert: Bool
    @Binding var pendingConfirmationAction: CloudFileConfirmationAction?
    
    @State private var showingRestartAlert = false
    @State private var pendingCloudSyncEnabled = false
    @State private var iCloudAccountStatus: CKAccountStatus = .couldNotDetermine
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: - SwiftData iCloud 同步开关
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath.icloud")
                        .foregroundStyle(.blue)
                        .font(.title3)
                    
                    VStack(alignment: .leading) {
                        Text("iCloud 及时同步")
                            .font(.headline)
                        Text("自动同步所有数据到 iCloud")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // 迁移中显示进度
                    if migrationManager.isMigrating {
                        ProgressView(value: migrationManager.migrationProgress)
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(width: 24, height: 24)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { migrationManager.isCloudSyncEnabled },
                            set: { newValue in
                                handleCloudSyncToggle(newValue)
                            }
                        ))
                        .labelsHidden()
                        .disabled(!authManager.isAuthenticated)
                    }
                }
                
                // iCloud 账户状态警告
                if iCloudAccountStatus != .available && migrationManager.isCloudSyncEnabled {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("iCloud 账户不可用，请检查设置")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                
                // 迁移进度条
                if migrationManager.isMigrating {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: migrationManager.migrationProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                        Text("正在迁移数据到 iCloud... \(Int(migrationManager.migrationProgress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 错误信息
                if let error = migrationManager.migrationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                
                // 上次迁移时间
                if let lastDate = migrationManager.lastMigrationDate {
                    Text("上次同步: \(lastDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .captureGuideTarget(.iCloudRealtimeSyncSection)
            .onAppear {
                checkiCloudAccountStatus()
            }
            
            Divider()
            
            // MARK: - 传统 CloudKit 备份（保留原有功能）
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "icloud")
                        .foregroundStyle(.indigo)
                    Text("云端文件备份管理")
                        .font(.headline)
                    Spacer()
                    if cloudManager.isSyncing {
                        ProgressView()
                    }
                }
                
                if let lastDate = cloudManager.lastCloudBackupDate {
                    Text("云端文件备份: \(lastDate.formatted(date: .abbreviated, time: .shortened))")
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
                        if !authManager.isAuthenticated {
                            showingLoginRequiredAlert = true
                        } else {
                            pendingConfirmationAction = .uploadBackup
                        }
                    } label: {
                        Label("备份到云端", systemImage: "icloud.and.arrow.up")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(cloudManager.isSyncing || migrationManager.isMigrating)
                    
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
                    .disabled(cloudManager.isSyncing || migrationManager.isMigrating)
                }
            }
            .captureGuideTarget(.cloudFileBackupSection)
        }
        .padding(.vertical, 8)
        .alert("需要重启应用", isPresented: $showingRestartAlert) {
            Button("稍后手动重启", role: .cancel) {
                // 用户选择稍后重启，设置已经保存
            }
        } message: {
            Text("iCloud 同步设置已更改。需要重启应用才能生效。请手动关闭并重新打开应用。")
        }
    }
    
    private func handleCloudSyncToggle(_ newValue: Bool) {
        // 如果尝试开启同步但未登录 Apple ID，强制关闭并提示
        if newValue && !authManager.isAuthenticated {
            showingLoginRequiredAlert = true
            return
        }
        
        pendingCloudSyncEnabled = newValue
        
        Task {
            let success = await migrationManager.toggleCloudSync(enabled: newValue)
            if success {
                // 设置已更改，需要重启
                await MainActor.run {
                    showingRestartAlert = true
                }
            }
        }
    }
    
    private func checkiCloudAccountStatus() {
        Task {
            let container = CKContainer(identifier: "iCloud.bugod2.ItemManager")
            do {
                let status = try await container.accountStatus()
                await MainActor.run {
                    iCloudAccountStatus = status
                }
            } catch {
                print("检查 iCloud 账户状态失败: \(error)")
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
                Text(title.appLocalized)
                    .font(.body)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                Text(subtitle.appLocalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            }
        }
        .padding(.vertical, 2)
    }
}
