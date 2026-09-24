
import SwiftUI
import SwiftData

protocol LabGridDisplayable: Identifiable {
    var title: String { get }
    var icon: String { get }
    var subtitle: String { get }
}

// MARK: - 实验室功能模块枚举
enum LabModule: String, CaseIterable, LabGridDisplayable {
    case effects = "特效测试"
    case petReference = "萌宠参考"
    case admin = "管理员"

    var id: String { rawValue }
    var title: String { rawValue }

    var icon: String {
        switch self {
        case .effects: return "sparkles"
        case .petReference: return "pawprint.fill"
        case .admin: return "person.crop.circle.badge.checkmark"
        }
    }

    var subtitle: String {
        switch self {
        case .effects: return "礼花 · 蝴蝶"
        case .petReference: return "萌宠 · 互动 · AI"
        case .admin: return "账号 · 公告 · 调试"
        }
    }
}

enum AdminLabModule: String, CaseIterable, LabGridDisplayable {
    case iap = "支付测试"
    case bottomDock = "底部导航"
    case noticeDiagnostics = "公告诊断"
    case featureUnlock = "功能解锁"
    case magicTasks = "魔法任务"
    case checkIn = "签到打卡"
    case clearPetChat = "清除对话"

    var id: String { rawValue }
    var title: String { rawValue }

    var icon: String {
        switch self {
        case .iap: return "cart.fill"
        case .bottomDock: return "star.fill"
        case .noticeDiagnostics: return "megaphone.fill"
        case .featureUnlock: return "lock.open.fill"
        case .magicTasks: return "wand.and.stars"
        case .checkIn: return "checkmark.seal.fill"
        case .clearPetChat: return "trash.circle.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .iap: return "喵币 · 首充 · VIP"
        case .bottomDock: return "布局 · 恢复"
        case .noticeDiagnostics: return "环境 · 同步 · 权限"
        case .featureUnlock: return "解锁 · 显示"
        case .magicTasks: return "状态 · 重置"
        case .checkIn: return "记录 · 重置"
        case .clearPetChat: return "萌宠 · 历史 · 清除"
        }
    }
}

// MARK: - 特效选项
enum EffectOption: String, CaseIterable, Identifiable {
    case random = "随机播放"
    case fireworks = "礼花 (Fireworks)"
    case butterflies = "蝴蝶 (Butterflies)"
    
    var id: String { rawValue }
    
    var effect: CelebrationEffect? {
        switch self {
        case .random: return nil
        case .fireworks: return .fireworks
        case .butterflies: return .butterflies
        }
    }
}

struct TestEffectsView: View {
    @State private var selectedModule: LabModule? = nil
    
    // 网格列配置
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground()
                
                ScrollView {
                    VStack(spacing: 20) {
                        Text("用于特效预览、调试验证和管理员工具")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.top, 20)
                        
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(LabModule.allCases) { module in
                                LabGridItem(module: module) {
                                    selectedModule = module
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 50)
                    }
                }
                // 底部悬浮 Dock 避让：实验室最后一块豆腐块会被 Dock 盖住。
                .avoidingBottomDock()
            }
            .navigationTitle("实验室")
            .sheet(item: $selectedModule) { module in
                Group {
                    if module == .petReference {
                        PetHomeViewWithCloseButton()
                    } else {
                        LabModuleDetailView(module: module)
                    }
                }
            }
        }
    }
}

// MARK: - 实验室豆腐块
struct LabGridItem<Module: LabGridDisplayable>: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    let module: Module
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: module.icon)
                        .font(.title2)
                        .foregroundStyle(themeManager.accentTextColor)
                        .frame(width: 40, height: 40)
                        .background(themeManager.accentTextColor.opacity(0.1))
                        .clipShape(Circle())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(module.title)
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryTextColor)
                        .lineLimit(1)

                    Text(module.subtitle)
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .lineLimit(1)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .aspectRatio(1.0, contentMode: .fill)
            .background(cardBackground)
            .overlay(cardOverlay)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - 卡片背景（适配主题色）
    private var cardBackground: some View {
        let isDark = colorScheme == .dark
        let cardColors = themeManager.themeColorConfig.currentTheme(forDarkMode: isDark).cardColors(forDarkMode: isDark)
        
        return Group {
            switch themeManager.cardStyle {
            case .solid:
                RoundedRectangle(cornerRadius: 20)
                    .fill(cardColors.backgroundRGBA.color)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            case .transparent:
                RoundedRectangle(cornerRadius: 20)
                    .fill(cardColors.backgroundRGBA.color.opacity(themeManager.transparentOpacity))
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            case .fullyTransparent:
                RoundedRectangle(cornerRadius: 20)
                    .fill(cardColors.backgroundRGBA.color.opacity(0.3))
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            case .tinted:
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(cardColors.backgroundRGBA.color.opacity(themeManager.tintOpacity))
                    )
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            }
        }
    }
    
    // MARK: - 卡片边框（适配主题色）
    private var cardOverlay: some View {
        let isDark = colorScheme == .dark
        let cardColors = themeManager.themeColorConfig.currentTheme(forDarkMode: isDark).cardColors(forDarkMode: isDark)
        
        return RoundedRectangle(cornerRadius: 20)
            .stroke(cardColors.accentRGBA.color.opacity(isDark ? 0.3 : 0.2), lineWidth: 1)
    }
}

// MARK: - 实验室模块详情视图
struct LabModuleDetailView: View {
    let module: LabModule
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground()
                
                Group {
                    switch module {
                    case .effects:
                        EffectsTestView()
                    case .petReference:
                        // 萌宠参考直接跳转到萌宠界面，不会走到这里
                        EmptyView()
                    case .admin:
                        AdminToolsView()
                    }
                }
            }
            .navigationTitle(module.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AdminToolsView: View {
    @State private var selectedModule: AdminLabModule? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("账号、公告、任务与调试工具")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top, 20)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(AdminLabModule.allCases) { module in
                        LabGridItem(module: module) {
                            selectedModule = module
                        }
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 50)
            }
        }
        .sheet(item: $selectedModule) { module in
            AdminLabModuleDetailView(module: module)
        }
    }
}

struct AdminLabModuleDetailView: View {
    let module: AdminLabModule
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground()

                Group {
                    switch module {
                    case .iap:
                        IAPTestView()
                    case .bottomDock:
                        BottomDockTestView()
                    case .noticeDiagnostics:
                        NoticeTestView()
                    case .featureUnlock:
                        FeatureUnlockSettingsView()
                    case .magicTasks:
                        MagicTasksTestView()
                    case .checkIn:
                        CheckInTestView()
                    case .clearPetChat:
                        ClearPetChatTestView()
                    }
                }
            }
            .navigationTitle(module.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 特效测试子视图
struct EffectsTestView: View {
    @State private var showCelebration = false
    @State private var selectedOption: EffectOption = .random
    @State private var currentEffectToPlay: CelebrationEffect?
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("选择特效类型并预览")
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .padding(.top, 20)

                // 特效选择器卡片
                VStack(alignment: .leading, spacing: 12) {
                    Text("特效类型")
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryTextColor)

                    Picker("特效类型", selection: $selectedOption) {
                        ForEach(EffectOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(themeManager.cardBackgroundColor.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(themeManager.accentTextColor.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)

                // 播放按钮
                Button {
                    if selectedOption == .random {
                        currentEffectToPlay = CelebrationEffect.allCases.randomElement()
                    } else {
                        currentEffectToPlay = selectedOption.effect
                    }
                    showCelebration = true
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("播放 \(selectedOption == .random ? "随机特效" : String(selectedOption.rawValue.split(separator: " ").first ?? ""))")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.accentTextColor)
                    .cornerRadius(16)
                }
                .padding(.horizontal)
                .shadow(color: themeManager.accentTextColor.opacity(0.3), radius: 8, x: 0, y: 4)

                Spacer(minLength: 100)
            }
        }
        .overlay {
            if showCelebration {
                CelebrationOverlay(isPresented: $showCelebration, forceEffect: currentEffectToPlay)
                    .ignoresSafeArea()
                    .zIndex(100)
            }
        }
    }
}

// MARK: - 底部导航测试子视图
struct BottomDockTestView: View {
    @ObservedObject private var bottomDockSettingsManager = BottomDockSettingsManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @State private var showAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("当前底部导航")
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryTextColor)

                    FlowLayout(spacing: 8) {
                        ForEach(bottomDockSettingsManager.slots, id: \.self) { slotIndex in
                            let feature = bottomDockSettingsManager.feature(at: slotIndex)
                            HStack(spacing: 4) {
                                Text("\(slotIndex + 1)")
                                    .fontWeight(.semibold)
                                Image(systemName: feature.systemImage)
                                Text(feature.title)
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(hex: feature.tintHex).opacity(0.12))
                            .foregroundStyle(Color(hex: feature.tintHex))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(themeManager.cardBackgroundColor.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(themeManager.accentTextColor.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
                .padding(.top, 20)

                // 操作按钮
                VStack(spacing: 12) {
                    Button {
                        showAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("恢复入口默认")
                        }
                        .font(.headline)
                        .foregroundStyle(themeManager.tertiaryTextColor)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(themeManager.tertiaryTextColor.opacity(0.1))
                        .cornerRadius(16)
                    }

                    Text("恢复底部导航默认设置")
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                Spacer(minLength: 100)
            }
        }
        .alert("确认清除", isPresented: $showAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                bottomDockSettingsManager.resetToDefault()
            }
        } message: {
            Text("这将清除底部导航设置，恢复为默认状态。确定要继续吗？")
        }
    }
}

// MARK: - 公告测试子视图
struct NoticeTestView: View {
    @State private var showNoticeAdmin = false
    @State private var showNoticePreview = false
    @State private var showResetAlert = false
    @StateObject private var service = NoticeService.shared
    @StateObject private var cloudKitService = NoticeCloudKitService.shared
    @StateObject private var readStatusService = NoticeReadStatusService.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @State private var showSyncAlert = false
    @State private var syncMessage = ""
    @State private var showReadStatusAlert = false
    @State private var currentUserID: String?
    @State private var isAdmin = false
    @State private var isCheckingAdmin = false
    @State private var lastOperationMessage = "准备就绪"
    @State private var hasInitializedNoticeService = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                noticeOverviewCard
                    .padding(.top, 20)

                latestNoticeCard

                actionSection

                Spacer(minLength: 100)
            }
        }
        .sheet(isPresented: $showNoticeAdmin, onDismiss: {
            Task {
                await refreshNoticeDiagnostics(forceSync: true)
            }
        }) {
            NoticeAdminView()
        }
        .overlay {
            if showNoticePreview, let notice = service.notices.first {
                NoticePreviewOverlay(isPresented: $showNoticePreview, notice: notice)
            }
        }
        .alert("同步结果", isPresented: $showSyncAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(syncMessage)
        }
        .alert("已读状态同步", isPresented: $showReadStatusAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("已读状态已从 iCloud 同步完成")
        }
        .alert("确认重置", isPresented: $showResetAlert) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                NoticePopupManager.shared.resetShownHistory()
                lastOperationMessage = "已重置公告展示记录"
            }
        } message: {
            Text("这将重置所有公告的展示记录，公告将可以再次展示。确定要继续吗？")
        }
        .onAppear {
            Task {
                await refreshNoticeDiagnostics(forceSync: false)
            }
        }
        .refreshable {
            await refreshNoticeDiagnostics(forceSync: true)
        }
    }

    private var noticeOverviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("公告诊断面板")
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryTextColor)

                    Text("复用原实验室页面，集中看环境、同步、权限和最新公告。")
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                }

                Spacer()

                if service.isSyncing || cloudKitService.isSyncing || readStatusService.isSyncing || isCheckingAdmin {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                debugBadge(title: "环境", value: environmentLabel, accent: themeManager.accentTextColor)
                debugBadge(title: "权限", value: isCheckingAdmin ? "检查中" : (isAdmin ? "管理员" : "普通用户"), accent: isAdmin ? .green : .orange)
                debugBadge(title: "公告", value: "\(service.notices.count) 条", accent: .blue)
            }

            VStack(spacing: 10) {
                debugInfoRow(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "当前 iCloud ID",
                    value: currentUserID ?? "未读取"
                )
                debugInfoRow(
                    icon: "arrow.clockwise.icloud",
                    title: "公告同步",
                    value: syncStatusText
                )
                debugInfoRow(
                    icon: "checkmark.circle",
                    title: "已读状态",
                    value: readStatusService.isSyncing ? "同步中" : "已同步"
                )
                debugInfoRow(
                    icon: "text.bubble",
                    title: "最近反馈",
                    value: latestStatusText
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(themeManager.cardBackgroundColor.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(themeManager.accentTextColor.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    @ViewBuilder
    private var latestNoticeCard: some View {
        if let latestNotice = service.notices.first {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最新公告")
                            .font(.headline)
                            .foregroundStyle(themeManager.primaryTextColor)

                        Text(latestNotice.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(themeManager.primaryTextColor)
                            .lineLimit(2)
                    }

                    Spacer()

                    Text(readStatusService.hasReadNotice(latestNotice) ? "已读" : "未读")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(readStatusService.hasReadNotice(latestNotice) ? .green : .orange))
                }

                VStack(spacing: 10) {
                    debugInfoRow(icon: "number", title: "优先级 / 版本", value: "P\(latestNotice.priority) / v\(latestNotice.version)")
                    debugInfoRow(icon: "clock", title: "更新时间", value: formattedDate(latestNotice.updatedAt))
                    debugInfoRow(icon: "photo", title: "媒体", value: latestNoticeMediaText(for: latestNotice))
                    debugInfoRow(icon: "key", title: "追踪键", value: latestNotice.readTrackingKey)
                }

                Text(latestNotice.content)
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .lineLimit(4)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeManager.cardBackgroundColor.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(themeManager.accentTextColor.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("最新公告")
                    .font(.headline)
                    .foregroundStyle(themeManager.primaryTextColor)

                Text("当前没有可用公告。你可以先用“管理公告”发布一条，再回到这里验证同步和弹窗。")
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeManager.cardBackgroundColor.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(themeManager.accentTextColor.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    currentUserID = await cloudKitService.getCurrentUserID()
                    lastOperationMessage = currentUserID == nil ? "读取 iCloud ID 失败" : "已读取当前 iCloud ID"
                    await refreshAdminStatus()
                }
            } label: {
                LabActionCard(
                    icon: "person.badge.key",
                    title: "获取我的 iCloud ID",
                    subtitle: "读取当前账号，并顺手检查管理员权限",
                    color: themeManager.accentTextColor,
                    tag: currentUserID == nil ? nil : "已读取",
                    tagColor: .green
                )
            }
            .padding(.horizontal)

            Button {
                showNoticeAdmin = true
            } label: {
                LabActionCard(
                    icon: "gear",
                    title: "管理公告",
                    subtitle: "继续复用原管理页，发布、编辑、删除都从这里进",
                    color: themeManager.accentTextColor,
                    tag: isAdmin ? "可发布" : "只读",
                    tagColor: isAdmin ? .green : .orange
                )
            }
            .padding(.horizontal)

            Button {
                Task {
                    await refreshNoticeDiagnostics(forceSync: true)
                    syncMessage = latestStatusText
                    showSyncAlert = true
                }
            } label: {
                LabActionCard(
                    icon: "arrow.clockwise.icloud",
                    title: "手动同步公告",
                    subtitle: "拉最新公告并刷新本地缓存",
                    color: themeManager.accentTextColor,
                    tag: service.isSyncing ? "同步中" : formattedDate(cloudKitService.lastSyncDate),
                    tagColor: .blue
                )
            }
            .disabled(service.isSyncing)
            .padding(.horizontal)

            Button {
                Task {
                    await readStatusService.syncFromCloud()
                    lastOperationMessage = "已读状态已从 iCloud 同步完成"
                    showReadStatusAlert = true
                }
            } label: {
                LabActionCard(
                    icon: "arrow.down.icloud",
                    title: "同步已读状态",
                    subtitle: "核对弹窗为什么出现/不出现",
                    color: themeManager.accentTextColor,
                    tag: readStatusService.isSyncing ? "同步中" : formattedDate(readStatusService.lastSyncDate),
                    tagColor: .purple
                )
            }
            .disabled(readStatusService.isSyncing)
            .padding(.horizontal)

            Button {
                showNoticePreview = true
            } label: {
                LabActionCard(
                    icon: "eye",
                    title: "预览公告弹窗",
                    subtitle: "直接预览当前排序第一条公告的展示效果",
                    color: themeManager.accentTextColor,
                    tag: service.notices.isEmpty ? "空" : "最新",
                    tagColor: service.notices.isEmpty ? .orange : .green
                )
            }
            .disabled(service.notices.isEmpty)
            .padding(.horizontal)

            Button {
                showResetAlert = true
            } label: {
                LabActionCard(
                    icon: "arrow.counterclockwise",
                    title: "重置公告展示记录",
                    subtitle: "清除已展示记录，验证修改后重新弹窗",
                    color: themeManager.tertiaryTextColor,
                    tag: "重置",
                    tagColor: .red
                )
            }
            .padding(.horizontal)
        }
    }

    private var environmentLabel: String {
        #if DEBUG
        return "Development"
        #else
        return "Production"
        #endif
    }

    private var syncStatusText: String {
        if service.isSyncing || cloudKitService.isSyncing {
            return "同步中"
        }

        if let error = service.errorMessage, !error.isEmpty {
            return error
        }

        if let error = cloudKitService.syncError, !error.isEmpty {
            return error
        }

        return cloudKitService.lastSyncDate.map(formattedDate) ?? "尚未同步"
    }

    private var latestStatusText: String {
        if let error = service.errorMessage, !error.isEmpty {
            return error
        }

        if let error = cloudKitService.syncError, !error.isEmpty {
            return error
        }

        return lastOperationMessage
    }

    private func latestNoticeMediaText(for notice: Notice) -> String {
        switch notice.mediaType {
        case .none:
            return "无媒体"
        case .image:
            return notice.builtinMediaName ?? notice.mediaURL ?? "图片"
        case .video:
            return notice.mediaURL ?? "视频"
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "未记录" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    @ViewBuilder
    private func debugBadge(title: String, value: String, accent: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(themeManager.secondaryTextColor)
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func debugInfoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(themeManager.accentTextColor)
                .frame(width: 14, height: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(themeManager.secondaryTextColor)

                Text(value)
                    .font(.caption)
                    .foregroundStyle(themeManager.primaryTextColor)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
    }

    private func refreshAdminStatus() async {
        isCheckingAdmin = true
        let hasPermission = await service.isAdmin()
        await MainActor.run {
            isAdmin = hasPermission
            isCheckingAdmin = false
        }
    }

    private func refreshNoticeDiagnostics(forceSync: Bool) async {
        if !hasInitializedNoticeService {
            service.setup(with: modelContext)
            hasInitializedNoticeService = true
        }
        await refreshAdminStatus()

        if forceSync {
            if currentUserID == nil {
                currentUserID = await cloudKitService.getCurrentUserID()
            }
            await service.manualSync()
        }

        await service.fetchNotices()
        lastOperationMessage = service.errorMessage ?? cloudKitService.syncError ?? (forceSync ? "公告同步完成" : "公告状态已刷新")
    }
}

// MARK: - 实验室操作卡片
struct LabActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    var tag: String? = nil
    var tagColor: Color = .red
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(themeManager.accentTextColor)
                .frame(width: 50, height: 50)
                .background(themeManager.accentTextColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(themeManager.primaryTextColor)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
            }

            Spacer()

            if let tag = tag {
                Text(tag)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tagColor))
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(themeManager.secondaryTextColor)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(themeManager.cardBackgroundColor.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(themeManager.accentTextColor.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - 魔法任务测试子视图
struct MagicTasksTestView: View {
    @ObservedObject private var manager = FeatureUnlockManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @State private var showResetAlert = false
    @State private var showResetAllAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 统计信息卡片
                VStack(spacing: 12) {
                    HStack {
                        VStack(spacing: 4) {
                            Text("\(manager.getUnlockedFeatures().count)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(themeManager.accentTextColor)
                            Text("已解锁")
                                .font(.caption)
                                .foregroundStyle(themeManager.secondaryTextColor)
                        }
                        .frame(maxWidth: .infinity)

                        Divider()

                        VStack(spacing: 4) {
                            Text("\(manager.getLockableFeatures().count)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(themeManager.tertiaryTextColor)
                            Text("待解锁")
                                .font(.caption)
                                .foregroundStyle(themeManager.secondaryTextColor)
                        }
                        .frame(maxWidth: .infinity)

                        Divider()

                        VStack(spacing: 4) {
                            Text("\(manager.getVisibleFeatures().count)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(themeManager.accentTextColor)
                            Text("可见")
                                .font(.caption)
                                .foregroundStyle(themeManager.secondaryTextColor)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(themeManager.cardBackgroundColor.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(themeManager.accentTextColor.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
                .padding(.top, 20)

                // 功能列表
                VStack(alignment: .leading, spacing: 12) {
                    Text("功能状态")
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryTextColor)
                        .padding(.horizontal)

                    LazyVStack(spacing: 8) {
                        ForEach(FeatureItem.allCases) { feature in
                            LabMagicTaskRow(feature: feature)
                        }
                    }
                    .padding(.horizontal)
                }

                // 操作按钮
                VStack(spacing: 12) {
                    Button {
                        showResetAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("重置所有魔法任务")
                        }
                        .font(.headline)
                        .foregroundStyle(themeManager.tertiaryTextColor)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(themeManager.tertiaryTextColor.opacity(0.1))
                        .cornerRadius(16)
                    }

                    Text("将所有功能重置为初始状态（仅免费功能保持解锁）")
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                .padding(.top, 20)

                Spacer(minLength: 100)
            }
        }
        .alert("确认重置", isPresented: $showResetAlert) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                resetAllMagicTasks()
            }
        } message: {
            Text("这将重置所有魔法任务状态，已解锁的功能将重新锁定（免费功能除外）。确定要继续吗？")
        }
    }
    
    private func resetAllMagicTasks() {
        // 重置所有功能状态
        for feature in FeatureItem.allCases {
            let condition = feature.defaultCondition
            // 免费功能保持解锁，其他重置
            if condition.type == UnlockConditionType.free.rawValue {
                manager.unlock(feature, force: true)
            } else {
                manager.lock(feature)
                // 重置显示状态
                manager.setVisible(feature, visible: !feature.isHiddenByDefault)
            }
        }
        // 重置衣物数量和登录天数缓存
        UserDefaults.standard.set(0, forKey: "clothingCount_cache")
        UserDefaults.standard.set(0, forKey: "loginDays")
    }
}

// MARK: - 实验室魔法任务行
struct LabMagicTaskRow: View {
    let feature: FeatureItem
    @ObservedObject private var manager = FeatureUnlockManager.shared
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack {
            Image(systemName: feature.icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(themeManager.primaryTextColor)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            // 状态指示器
            HStack(spacing: 8) {
                if manager.isUnlocked(feature) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(themeManager.accentTextColor)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(themeManager.tertiaryTextColor)
                }

                if !manager.isVisible(feature) {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.cardBackgroundColor.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeManager.accentTextColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var iconColor: Color {
        if manager.canAccess(feature) {
            return themeManager.accentTextColor
        } else if manager.isUnlocked(feature) {
            return themeManager.secondaryTextColor
        } else {
            return themeManager.tertiaryTextColor
        }
    }

    private var statusText: String {
        let condition = manager.getCondition(for: feature)
        if manager.isUnlocked(feature) {
            return manager.isVisible(feature) ? "已解锁" : "已解锁(隐藏)"
        } else {
            return condition.description
        }
    }

    private var statusColor: Color {
        if manager.isUnlocked(feature) {
            return manager.isVisible(feature) ? themeManager.accentTextColor : themeManager.secondaryTextColor
        } else {
            return themeManager.tertiaryTextColor
        }
    }
}

// MARK: - 签到打卡测试子视图
struct CheckInTestView: View {
    @ObservedObject private var manager = DailyCheckInManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @State private var showResetAlert = false
    @State private var showAddRecordAlert = false
    @State private var showClearAllAlert = false
    @State private var selectedMakeupDate = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 统计信息卡片
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(themeManager.accentTextColor)

                    HStack(spacing: 30) {
                        VStack(spacing: 4) {
                            Text("\(manager.totalDays)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(themeManager.primaryTextColor)
                            Text("累计打卡")
                                .font(.caption)
                                .foregroundStyle(themeManager.secondaryTextColor)
                        }

                        VStack(spacing: 4) {
                            Text("\(manager.consecutiveDays)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(themeManager.accentTextColor)
                            Text("连续打卡")
                                .font(.caption)
                                .foregroundStyle(themeManager.secondaryTextColor)
                        }
                    }

                    if manager.hasCheckedInToday {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(themeManager.accentTextColor)
                            Text("今日已打卡")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.accentTextColor)
                        }
                    } else {
                        HStack {
                            Image(systemName: "circle")
                                .foregroundStyle(themeManager.secondaryTextColor)
                            Text("今日未打卡")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.secondaryTextColor)
                        }
                    }
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(themeManager.cardBackgroundColor.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(themeManager.accentTextColor.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
                .padding(.top, 20)

                // 本周打卡状态
                VStack(alignment: .leading, spacing: 12) {
                    Text("本周打卡")
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryTextColor)
                        .padding(.horizontal)

                    HStack(spacing: 8) {
                        ForEach(0..<7) { index in
                            let dayNames = ["一", "二", "三", "四", "五", "六", "日"]
                            VStack(spacing: 6) {
                                Text(dayNames[index])
                                    .font(.caption)
                                    .foregroundStyle(themeManager.secondaryTextColor)

                                if index < manager.weekCheckIns.count {
                                    Image(systemName: manager.weekCheckIns[index] ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(manager.weekCheckIns[index] ? themeManager.accentTextColor : themeManager.secondaryTextColor.opacity(0.3))
                                        .font(.title3)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(themeManager.cardBackgroundColor.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(themeManager.accentTextColor.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal)
                }

                // 操作按钮
                VStack(spacing: 12) {
                    Button {
                        showResetAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("重置今日打卡")
                        }
                        .font(.headline)
                        .foregroundStyle(themeManager.tertiaryTextColor)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(themeManager.tertiaryTextColor.opacity(0.1))
                        .cornerRadius(16)
                    }

                    Button {
                        showAddRecordAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("补卡")
                        }
                        .font(.headline)
                        .foregroundStyle(themeManager.accentTextColor)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(themeManager.accentTextColor.opacity(0.1))
                        .cornerRadius(16)
                    }

                    Button {
                        fillThisWeekCheckIns()
                    } label: {
                        HStack {
                            Image(systemName: "calendar.badge.checkmark")
                            Text("补打本周未打卡")
                        }
                        .font(.headline)
                        .foregroundStyle(themeManager.accentTextColor)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(themeManager.accentTextColor.opacity(0.1))
                        .cornerRadius(16)
                    }

                    Button {
                        showClearAllAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("清空所有打卡记录")
                        }
                        .font(.headline)
                        .foregroundStyle(themeManager.tertiaryTextColor)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(themeManager.tertiaryTextColor.opacity(0.1))
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)

                Spacer(minLength: 100)
            }
        }
        .alert("确认重置", isPresented: $showResetAlert) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                resetTodayCheckIn()
            }
        } message: {
            Text("这将重置今日打卡状态，允许重新打卡。确定要继续吗？")
        }
        .sheet(isPresented: $showAddRecordAlert) {
            MakeupCheckInSheet(
                selectedDate: $selectedMakeupDate,
                checkedInDates: loadCheckedInDates(),
                onConfirm: { date in
                    addMakeupCheckInRecord(for: date)
                },
                onCancel: {
                    showAddRecordAlert = false
                }
            )
        }
        .alert("确认清空", isPresented: $showClearAllAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                clearAllCheckInRecords()
            }
        } message: {
            Text("这将清空所有打卡记录和统计数据，此操作不可恢复。确定要继续吗？")
        }
    }
    
    private func resetTodayCheckIn() {
        // 清除今日打卡状态
        let lastDate = UserDefaults.standard.object(forKey: "dailyCheckIn.lastDate") as? Date
        if let lastDate = lastDate, Calendar.current.isDateInToday(lastDate) {
            UserDefaults.standard.removeObject(forKey: "dailyCheckIn.lastDate")
            // 减少总天数
            let totalDays = UserDefaults.standard.integer(forKey: "dailyCheckIn.totalDays")
            if totalDays > 0 {
                UserDefaults.standard.set(totalDays - 1, forKey: "dailyCheckIn.totalDays")
            }
            // 重新计算连续天数
            let consecutiveDays = UserDefaults.standard.integer(forKey: "dailyCheckIn.consecutiveDays")
            if consecutiveDays > 0 {
                UserDefaults.standard.set(consecutiveDays - 1, forKey: "dailyCheckIn.consecutiveDays")
            }
            // 从记录中移除今日记录
            if let data = UserDefaults.standard.data(forKey: "dailyCheckIn.records"),
               var records = try? JSONDecoder().decode([CheckInRecord].self, from: data) {
                records.removeAll { Calendar.current.isDateInToday($0.date) }
                if let encoded = try? JSONEncoder().encode(records) {
                    UserDefaults.standard.set(encoded, forKey: "dailyCheckIn.records")
                }
            }
            // 刷新管理器
            manager.reloadFromDisk()
        }
    }
    
    private func addMakeupCheckInRecord(for date: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let makeupDate = calendar.startOfDay(for: date)

        // 只能补今天之前的日期
        guard makeupDate < today else {
            print("只能补今天之前的日期")
            return
        }

        // 添加单条记录
        addCheckInRecord(for: makeupDate)

        // 更新最后打卡日期为补卡日期（如果比当前记录的更晚）
        if let lastDate = UserDefaults.standard.object(forKey: "dailyCheckIn.lastDate") as? Date {
            let lastDay = calendar.startOfDay(for: lastDate)
            if makeupDate > lastDay {
                UserDefaults.standard.set(makeupDate, forKey: "dailyCheckIn.lastDate")
            }
        } else {
            UserDefaults.standard.set(makeupDate, forKey: "dailyCheckIn.lastDate")
        }

        // 重新计算累计天数和连续天数
        recalculateStats()

        // 刷新管理器
        manager.reloadFromDisk()
    }
    
    // 为指定日期添加打卡记录（从CloudKit获取或AI生成）
    private func addCheckInRecord(for date: Date) {
        let calendar = Calendar.current

        // 加载现有记录
        var records: [CheckInRecord] = []
        if let data = UserDefaults.standard.data(forKey: "dailyCheckIn.records"),
           let existingRecords = try? JSONDecoder().decode([CheckInRecord].self, from: data) {
            records = existingRecords
        }

        // 检查是否已有该日期的记录
        let hasRecord = records.contains { calendar.isDate($0.date, inSameDayAs: date) }
        guard !hasRecord else { return }

        // 从 CloudKit 获取或 AI 生成穿搭色
        Task {
            if let outfit = await manager.generateAndUploadOutfitForDate(date) {
                // 创建打卡记录
                let testRecord = CheckInRecord(
                    id: UUID().uuidString,
                    date: date,
                    colors: outfit.colorNames,
                    colorHexes: outfit.colors.map { $0.hex },
                    accessories: outfit.accessories,
                    weather: outfit.weather,
                    location: outfit.location,
                    temperature: outfit.temperature,
                    season: outfit.season,
                    isAIGenerated: outfit.source == "ai",
                    petName: outfit.petName
                )

                // 保存记录
                await MainActor.run {
                    records.append(testRecord)
                    if let encoded = try? JSONEncoder().encode(records) {
                        UserDefaults.standard.set(encoded, forKey: "dailyCheckIn.records")
                    }
                    // 更新统计
                    let totalDays = UserDefaults.standard.integer(forKey: "dailyCheckIn.totalDays")
                    UserDefaults.standard.set(totalDays + 1, forKey: "dailyCheckIn.totalDays")
                }
            } else {
                // AI 生成失败，使用默认数据
                await MainActor.run {
                    let defaultColors = ["樱花粉", "奶油白"]
                    let defaultRecord = CheckInRecord(
                        id: UUID().uuidString,
                        date: date,
                        colors: defaultColors,
                        colorHexes: Array(repeating: nil, count: defaultColors.count),
                        accessories: "搭配粉色蝴蝶结发饰",
                        weather: nil,
                        location: nil,
                        temperature: nil,
                        season: nil,
                        isAIGenerated: false,
                        petName: nil
                    )
                    records.append(defaultRecord)
                    if let encoded = try? JSONEncoder().encode(records) {
                        UserDefaults.standard.set(encoded, forKey: "dailyCheckIn.records")
                    }
                    let totalDays = UserDefaults.standard.integer(forKey: "dailyCheckIn.totalDays")
                    UserDefaults.standard.set(totalDays + 1, forKey: "dailyCheckIn.totalDays")
                }
            }
        }
    }
    
    // 补打本周未打卡的天数
    private func fillThisWeekCheckIns() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        // 调整为周一为第一天 (1=周日, 2=周一... 7=周六)
        let mondayOffset = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: today) else { return }

        // 从周一到今天，补打未打卡的天数
        var addedCount = 0
        for i in 0...mondayOffset {
            if let date = calendar.date(byAdding: .day, value: i, to: monday) {
                // 检查是否已有记录
                let hasRecord = hasCheckInRecord(for: date)
                if !hasRecord {
                    addCheckInRecord(for: date)
                    addedCount += 1
                }
            }
        }

        // 更新最后打卡日期为今天
        UserDefaults.standard.set(Date(), forKey: "dailyCheckIn.lastDate")

        // 重新计算累计天数和连续天数
        recalculateStats()

        // 刷新管理器
        manager.reloadFromDisk()

        print("补打本周打卡完成，新增 \(addedCount) 条记录")
    }
    

    // 检查某天是否已有打卡记录
    private func hasCheckInRecord(for date: Date) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: "dailyCheckIn.records"),
              let records = try? JSONDecoder().decode([CheckInRecord].self, from: data) else {
            return false
        }
        return records.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    // 加载所有已打卡的日期
    private func loadCheckedInDates() -> Set<Date> {
        let calendar = Calendar.current
        guard let data = UserDefaults.standard.data(forKey: "dailyCheckIn.records"),
              let records = try? JSONDecoder().decode([CheckInRecord].self, from: data) else {
            return []
        }
        return Set(records.map { calendar.startOfDay(for: $0.date) })
    }

    // MARK: - 重新计算统计信息
    private func recalculateStats() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 加载所有记录
        guard let data = UserDefaults.standard.data(forKey: "dailyCheckIn.records"),
              let records = try? JSONDecoder().decode([CheckInRecord].self, from: data) else {
            // 没有记录，重置统计
            UserDefaults.standard.set(0, forKey: "dailyCheckIn.totalDays")
            UserDefaults.standard.set(0, forKey: "dailyCheckIn.consecutiveDays")
            return
        }

        // 计算累计天数（去重日期）
        let uniqueDates = Set(records.map { calendar.startOfDay(for: $0.date) })
        let totalDays = uniqueDates.count
        UserDefaults.standard.set(totalDays, forKey: "dailyCheckIn.totalDays")

        // 计算连续天数（从今天往前数）
        var consecutiveDays = 0
        var checkDate = today

        // 如果今天没有打卡，从昨天开始算
        if !uniqueDates.contains(today) {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
                checkDate = yesterday
            }
        }

        // 往前数连续打卡天数
        while uniqueDates.contains(checkDate) {
            consecutiveDays += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                break
            }
            checkDate = previousDay
        }

        UserDefaults.standard.set(consecutiveDays, forKey: "dailyCheckIn.consecutiveDays")

        print("📊 重新计算统计：累计打卡 \(totalDays) 天，连续打卡 \(consecutiveDays) 天")
    }

    private func clearAllCheckInRecords() {
        // 清除所有打卡数据
        UserDefaults.standard.removeObject(forKey: "dailyCheckIn.records")
        UserDefaults.standard.removeObject(forKey: "dailyCheckIn.lastDate")
        UserDefaults.standard.removeObject(forKey: "dailyCheckIn.consecutiveDays")
        UserDefaults.standard.removeObject(forKey: "dailyCheckIn.totalDays")
        // 刷新管理器
        manager.reloadFromDisk()
    }
}

// MARK: - 补卡选择日期 Sheet
struct MakeupCheckInSheet: View {
    @Binding var selectedDate: Date
    let checkedInDates: Set<Date>
    let onConfirm: (Date) -> Void
    let onCancel: () -> Void
    @Environment(ThemeManager.self) private var themeManager

    @State private var currentMonth: Date = Date()

    private let calendar = Calendar.current
    private let weekDays = ["日", "一", "二", "三", "四", "五", "六"]

    // 限制日期范围
    private var minDate: Date {
        guard let date = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: Date())) else {
            return Date.distantPast
        }
        return date
    }

    private var maxDate: Date {
        // 今天之前的日期
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) else {
            return Date.distantPast
        }
        return yesterday
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("选择要补卡的日期")
                    .font(.headline)
                    .foregroundColor(themeManager.primaryTextColor)
                    .padding(.top, 20)

                // 月份导航
                HStack {
                    Button {
                        withAnimation {
                            currentMonth = previousMonth
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(themeManager.primaryTextColor)
                    }

                    Spacer()

                    Text(monthYearString)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.primaryTextColor)

                    Spacer()

                    Button {
                        withAnimation {
                            currentMonth = nextMonth
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(themeManager.primaryTextColor)
                    }
                    .disabled(isNextMonthDisabled)
                }
                .padding(.horizontal)

                // 星期标题
                HStack {
                    ForEach(weekDays, id: \.self) { day in
                        Text(day)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(themeManager.secondaryTextColor)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)

                // 日期网格
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                    ForEach(Array(daysInMonth.enumerated()), id: \.offset) { index, date in
                        if let date = date {
                            MakeupDayCell(
                                date: date,
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                isCheckedIn: isDateCheckedIn(date),
                                isEnabled: isDateEnabled(date)
                            )
                            .onTapGesture {
                                if isDateEnabled(date) {
                                    selectedDate = date
                                }
                            }
                        } else {
                            // 空占位
                            Color.clear
                                .frame(height: 40)
                        }
                    }
                }
                .padding(.horizontal)

                // 图例说明
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(themeManager.accentTextColor)
                            .frame(width: 8, height: 8)
                        Text("已打卡")
                            .font(.caption)
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(themeManager.accentTextColor)
                            .frame(width: 8, height: 8)
                        Text("选中")
                            .font(.caption)
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(themeManager.tertiaryTextColor.opacity(0.3))
                            .frame(width: 8, height: 8)
                        Text("不可选")
                            .font(.caption)
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }
                }
                .padding(.top, 8)

                // 检查选中的日期是否已打卡
                if isSelectedDateCheckedIn {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(themeManager.accentTextColor)
                        Text("该日期已打卡，无需补卡")
                            .font(.caption)
                            .foregroundStyle(themeManager.accentTextColor)
                    }
                    .padding(.top, 8)
                }

                Spacer()
            }
            .navigationTitle("补卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("确认") {
                        onConfirm(selectedDate)
                        onCancel()
                    }
                    .disabled(isSelectedDateCheckedIn)
                }
            }
        }
    }

    // MARK: - 辅助计算属性

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: currentMonth)
    }

    private var previousMonth: Date {
        guard let date = calendar.date(byAdding: .month, value: -1, to: currentMonth) else {
            return currentMonth
        }
        return date
    }

    private var nextMonth: Date {
        guard let date = calendar.date(byAdding: .month, value: 1, to: currentMonth) else {
            return currentMonth
        }
        return date
    }

    private var isNextMonthDisabled: Bool {
        let nextMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth))!
        return nextMonthStart > maxDate
    }

    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }

        var dates: [Date?] = []
        var current = firstWeek.start

        // 生成6周的日期（确保覆盖整个月）
        for _ in 0..<42 {
            if calendar.isDate(current, equalTo: monthInterval.start, toGranularity: .month) {
                dates.append(current)
            } else {
                dates.append(nil) // 非本月日期显示为空
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = nextDay
        }

        return dates
    }

    // MARK: - 辅助方法

    private func isDateCheckedIn(_ date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        return checkedInDates.contains(day)
    }

    private func isDateEnabled(_ date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= minDate && day <= maxDate
    }

    private var isSelectedDateCheckedIn: Bool {
        isDateCheckedIn(selectedDate)
    }
}

// MARK: - 补卡日期格子
private struct MakeupDayCell: View {
    let date: Date
    let isSelected: Bool
    let isCheckedIn: Bool
    let isEnabled: Bool
    @Environment(ThemeManager.self) private var themeManager

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            // 背景
            if isSelected {
                Circle()
                    .fill(themeManager.accentTextColor)
            } else if isCheckedIn {
                Circle()
                    .fill(themeManager.accentTextColor.opacity(0.2))
            }

            // 日期数字
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(textColor)

            // 已打卡标记
            if isCheckedIn && !isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(themeManager.accentTextColor)
                    .offset(x: 8, y: -8)
            }
        }
        .frame(height: 40)
        .opacity(isEnabled ? 1.0 : 0.3)
    }

    private var textColor: Color {
        if isSelected {
            return .white
        } else if isCheckedIn {
            return themeManager.accentTextColor
        } else {
            return themeManager.primaryTextColor
        }
    }
}

// MARK: - 支付测试子视图
struct IAPTestView: View {
    @ObservedObject private var testManager = IAPTestManager.shared
    @ObservedObject private var viewModel = IAPViewModel.shared
    @Environment(ThemeManager.self) private var themeManager
    @State private var customAmount: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 测试模式开关
                VStack(spacing: 12) {
                    HStack {
                        Text("测试模式")
                            .font(.headline)
                            .foregroundStyle(themeManager.primaryTextColor)
                        Spacer()
                        Toggle("", isOn: $testManager.isTestMode)
                            .labelsHidden()
                    }

                    if testManager.isTestMode {
                        Text("当前处于测试模式，支付将使用模拟数据")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(themeManager.cardBackgroundColor.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(themeManager.accentTextColor.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
                .padding(.top, 20)

                // 当前状态
                VStack(spacing: 12) {
                    Text("当前状态")
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryTextColor)

                    HStack {
                        Text("喵币余额")
                        Spacer()
                        Text("\(viewModel.currentBalance)")
                            .foregroundStyle(themeManager.accentTextColor)
                            .fontWeight(.bold)
                    }

                    HStack {
                        Text("VIP状态")
                        Spacer()
                        Text(viewModel.isVIP ? "已开通" : "未开通")
                            .foregroundStyle(viewModel.isVIP ? themeManager.accentTextColor : themeManager.secondaryTextColor)
                    }

                    HStack {
                        Text("首充状态")
                        Spacer()
                        Text(FirstDoubleBonusManager.shared.hasAnyFirstDoubleBonus() ? "✅ 有档位可享受双倍" : "所有档位已完成")
                            .foregroundStyle(FirstDoubleBonusManager.shared.hasAnyFirstDoubleBonus() ? .green : themeManager.secondaryTextColor)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(themeManager.cardBackgroundColor.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(themeManager.accentTextColor.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)

                // 快速添加喵币
                VStack(spacing: 12) {
                    Text("快速添加喵币")
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryTextColor)

                    // 60喵币档位
                    let hasFirstDouble60 = testManager.hasFirstDoubleBonus(for: "com.pinkhouse.app.meowcoin_60")
                    Button {
                        testManager.addMeowCoins(60, productID: "com.pinkhouse.app.meowcoin_60", isFirstDouble: true)
                        viewModel.loadUserData()
                    } label: {
                        LabActionCard(
                            icon: "pawprint.fill",
                            title: "首充档位 (60喵币)",
                            subtitle: hasFirstDouble60 ? "获得120喵币（首充双倍）" : "获得66喵币（+10%赠送）",
                            color: themeManager.accentTextColor,
                            tag: hasFirstDouble60 ? "首充双倍" : "+10%",
                            tagColor: hasFirstDouble60 ? .red : .orange
                        )
                    }

                    // 300喵币档位
                    let hasFirstDouble300 = testManager.hasFirstDoubleBonus(for: "com.pinkhouse.app.meowcoin_300")
                    Button {
                        testManager.addMeowCoins(300, productID: "com.pinkhouse.app.meowcoin_300", isFirstDouble: true)
                        viewModel.loadUserData()
                    } label: {
                        LabActionCard(
                            icon: "pawprint.fill",
                            title: "中充档位 (300喵币)",
                            subtitle: hasFirstDouble300 ? "获得600喵币（首充双倍）" : "获得330喵币（+10%赠送）",
                            color: themeManager.accentTextColor,
                            tag: hasFirstDouble300 ? "首充双倍" : "+10%",
                            tagColor: hasFirstDouble300 ? .red : .orange
                        )
                    }

                    // 500喵币档位
                    let hasFirstDouble500 = testManager.hasFirstDoubleBonus(for: "com.pinkhouse.app.meowcoin_500")
                    Button {
                        testManager.addMeowCoins(500, productID: "com.pinkhouse.app.meowcoin_500", isFirstDouble: true)
                        viewModel.loadUserData()
                    } label: {
                        LabActionCard(
                            icon: "pawprint",
                            title: "普通档位 (500喵币)",
                            subtitle: hasFirstDouble500 ? "获得1000喵币（首充双倍）" : "获得575喵币（+15%赠送）",
                            color: themeManager.secondaryTextColor,
                            tag: hasFirstDouble500 ? "首充双倍" : "+15%",
                            tagColor: hasFirstDouble500 ? .red : .green
                        )
                    }

                    // 3280喵币档位
                    let hasFirstDouble3280 = testManager.hasFirstDoubleBonus(for: "com.pinkhouse.app.mcoin_3280")
                    Button {
                        testManager.addMeowCoins(3280, productID: "com.pinkhouse.app.mcoin_3280", isFirstDouble: true)
                        viewModel.loadUserData()
                    } label: {
                        LabActionCard(
                            icon: "pawprint.fill",
                            title: "土豪档位 (3280喵币)",
                            subtitle: hasFirstDouble3280 ? "获得6560喵币（首充双倍）" : "获得4428喵币（+35%赠送）",
                            color: themeManager.accentTextColor,
                            tag: hasFirstDouble3280 ? "首充双倍" : "+35%",
                            tagColor: hasFirstDouble3280 ? .red : .purple
                        )
                    }
                }
                .padding(.horizontal)

                // VIP 测试
                VStack(spacing: 12) {
                    Text("VIP测试")
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryTextColor)

                    Button {
                        testManager.activateVIP(months: 1)
                        viewModel.loadUserData()
                    } label: {
                        LabActionCard(
                            icon: "crown.fill",
                            title: "开通月度VIP",
                            subtitle: "开通1个月VIP会员",
                            color: .orange
                        )
                    }

                    Button {
                        testManager.deactivateVIP()
                        viewModel.loadUserData()
                    } label: {
                        LabActionCard(
                            icon: "crown",
                            title: "取消VIP",
                            subtitle: "取消VIP会员状态",
                            color: themeManager.tertiaryTextColor
                        )
                    }
                }
                .padding(.horizontal)

                // 首次购买测试
                VStack(spacing: 12) {
                    Text("首次购买测试")
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryTextColor)

                    Toggle("启用首充双倍", isOn: $testManager.testConfig.enableFirstDouble)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(themeManager.cardBackgroundColor.opacity(0.3))
                        )

                    Button {
                        testManager.resetAllFirstPurchases()
                        viewModel.loadUserData()
                    } label: {
                        LabActionCard(
                            icon: "arrow.counterclockwise",
                            title: "重置所有首充状态",
                            subtitle: "清除后可重新测试各档位首充双倍",
                            color: .green
                        )
                    }
                }
                .padding(.horizontal)

                // 清除数据
                VStack(spacing: 12) {
                    Text("危险操作")
                        .font(.headline)
                        .foregroundStyle(themeManager.tertiaryTextColor)

                    Button {
                        testManager.clearAllPurchaseRecords()
                        viewModel.loadUserData()
                    } label: {
                        LabActionCard(
                            icon: "trash.fill",
                            title: "清除所有购买记录",
                            subtitle: "清除后可重新测试首次购买流程",
                            color: themeManager.tertiaryTextColor
                        )
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 100)
            }
        }
    }
}

// 公告预览遮罩已移至 NoticeAdminView.swift

// MARK: - 带关闭按钮的萌宠界面
struct PetHomeViewWithCloseButton: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            PetHomeView()
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
                    .background(Circle().fill(.black.opacity(0.3)))
            }
            .padding(.trailing, 20)
            .padding(.top, 60)
        }
    }
}

// MARK: - 清除萌宠对话历史测试子视图
struct ClearPetChatTestView: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var showClearAlert = false
    @State private var showClearedSuccess = false
    @State private var messageCount: Int = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 统计信息卡片
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(themeManager.accentTextColor)

                    VStack(spacing: 4) {
                        Text("\(messageCount)")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(themeManager.primaryTextColor)
                        Text("当前对话记录数")
                            .font(.caption)
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(themeManager.cardBackgroundColor.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(themeManager.accentTextColor.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
                .padding(.top, 20)

                // 说明文字
                VStack(alignment: .leading, spacing: 12) {
                    Text("功能说明")
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryTextColor)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("清除萌宠对话的所有历史记录", systemImage: "checkmark.circle")
                        Label("包括用户消息和AI回复", systemImage: "checkmark.circle")
                        Label("操作后无法恢复", systemImage: "exclamationmark.triangle")
                    }
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(themeManager.cardBackgroundColor.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(themeManager.accentTextColor.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)

                // 清除按钮
                Button {
                    showClearAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("清除所有对话历史")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.tertiaryTextColor)
                    .cornerRadius(16)
                }
                .padding(.horizontal)
                .shadow(color: themeManager.tertiaryTextColor.opacity(0.3), radius: 8, x: 0, y: 4)

                Text("此操作将永久删除所有萌宠对话记录，请谨慎操作")
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer(minLength: 100)
            }
        }
        .alert("确认清除", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                clearPetChatHistory()
            }
        } message: {
            Text("这将清除所有萌宠对话历史记录，此操作不可恢复。确定要继续吗？")
        }
        .alert("清除成功", isPresented: $showClearedSuccess) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("萌宠对话历史记录已清除")
        }
        .onAppear {
            loadMessageCount()
        }
    }

    private func loadMessageCount() {
        messageCount = PetChatTranscriptStore.load().count
    }

    private func clearPetChatHistory() {
        PetHistoryResetManager.shared.clearAllPetHistory(reason: "lab_manual_clear")
        messageCount = 0
        showClearedSuccess = true
    }
}
