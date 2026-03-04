
import SwiftUI

// MARK: - 实验室功能模块枚举
enum LabModule: String, CaseIterable, Identifiable {
    case effects = "特效测试"
    case vip = "VIP 测试"
    case favoriteMenu = "菜单设置"
    case notice = "公告管理"
    case featureUnlock = "功能解锁"
    case magicTasks = "魔法任务"
    case checkIn = "签到打卡"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .effects: return "sparkles"
        case .vip: return "crown.fill"
        case .favoriteMenu: return "star.fill"
        case .notice: return "megaphone.fill"
        case .featureUnlock: return "lock.open.fill"
        case .magicTasks: return "wand.and.stars"
        case .checkIn: return "checkmark.seal.fill"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .effects: return .pink
        case .vip: return .yellow
        case .favoriteMenu: return .orange
        case .notice: return .blue
        case .featureUnlock: return .green
        case .magicTasks: return .purple
        case .checkIn: return .red
        }
    }
    
    var subtitle: String {
        switch self {
        case .effects: return "礼花 · 蝴蝶"
        case .vip: return "状态 · 重置"
        case .favoriteMenu: return "常用 · 清除"
        case .notice: return "管理 · 预览"
        case .featureUnlock: return "解锁 · 显示"
        case .magicTasks: return "状态 · 重置"
        case .checkIn: return "记录 · 重置"
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
        ZStack {
            LiquidBackground()
            
            ScrollView {
                VStack(spacing: 20) {
                    Text("选择实验模块进入测试")
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
        }
        .navigationTitle("实验室")
        .sheet(item: $selectedModule) { module in
            LabModuleDetailView(module: module)
        }
    }
}

// MARK: - 实验室豆腐块
struct LabGridItem: View {
    let module: LabModule
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: module.icon)
                        .font(.title2)
                        .foregroundStyle(module.iconColor)
                        .frame(width: 40, height: 40)
                        .background(module.iconColor.opacity(0.1))
                        .clipShape(Circle())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(module.rawValue)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(module.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .aspectRatio(1.0, contentMode: .fill)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
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
                    case .vip:
                        VIPTestView()
                    case .favoriteMenu:
                        FavoriteMenuTestView()
                    case .notice:
                        NoticeTestView()
                    case .featureUnlock:
                        FeatureUnlockSettingsView()
                    case .magicTasks:
                        MagicTasksTestView()
                    case .checkIn:
                        CheckInTestView()
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

// MARK: - 特效测试子视图
struct EffectsTestView: View {
    @State private var showCelebration = false
    @State private var selectedOption: EffectOption = .random
    @State private var currentEffectToPlay: CelebrationEffect?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("选择特效类型并预览")
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
                
                // 特效选择器卡片
                VStack(alignment: .leading, spacing: 12) {
                    Text("特效类型")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
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
                        .fill(.ultraThinMaterial)
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
                    .background(Color.pink)
                    .cornerRadius(16)
                }
                .padding(.horizontal)
                .shadow(color: .pink.opacity(0.3), radius: 8, x: 0, y: 4)
                
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

// MARK: - VIP 测试子视图
struct VIPTestView: View {
    @ObservedObject private var vipManager = VIPManager.shared
    @State private var showAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // VIP 状态卡片
                VStack(spacing: 16) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.yellow)
                    
                    Text(vipManager.isVIP ? "VIP 会员" : "普通用户")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let expireDate = PetDataManager.shared.status.vipStatus.expireDate {
                        Text("到期时间: \(expireDate.formatted(date: .long, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(30)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                )
                .padding(.horizontal)
                .padding(.top, 20)
                
                // 操作按钮
                VStack(spacing: 12) {
                    Button {
                        showAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("清除 VIP 时间")
                        }
                        .font(.headline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(16)
                    }
                    
                    Text("重置为非会员状态，用于测试非 VIP 功能")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                
                Spacer(minLength: 100)
            }
        }
        .alert("确认清除", isPresented: $showAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                var status = PetDataManager.shared.status
                status.vipStatus.isActive = false
                status.vipStatus.expireDate = nil
                PetDataManager.shared.saveStatus(status)
                vipManager.reloadStatus()
            }
        } message: {
            Text("这将清除 VIP 状态，重置为非会员。确定要继续吗？")
        }
    }
}

// MARK: - 常用菜单测试子视图
struct FavoriteMenuTestView: View {
    @ObservedObject private var favoriteMenuManager = FavoriteMenuSettingsManager.shared
    @State private var showAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 当前设置预览
                VStack(alignment: .leading, spacing: 16) {
                    Text("当前常用菜单")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(Array(favoriteMenuManager.selectedItems.enumerated()), id: \.offset) { index, item in
                            HStack(spacing: 4) {
                                Image(systemName: item.icon)
                                Text(item.rawValue)
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.1))
                            .foregroundStyle(.orange)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
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
                            Text("清除常用菜单历史")
                        }
                        .font(.headline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(16)
                    }
                    
                    Text("恢复为默认的常用菜单设置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                
                Spacer(minLength: 100)
            }
        }
        .alert("确认清除", isPresented: $showAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                favoriteMenuManager.selectedItems = [.pet, .perler, .bigWorld, .smallWorld, .wealth]
                favoriteMenuManager.saveSettings()
            }
        } message: {
            Text("这将清除所有常用菜单设置，恢复为默认状态。确定要继续吗？")
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
    @State private var showSyncAlert = false
    @State private var syncMessage = ""
    @State private var showReadStatusAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 环境信息
                VStack(spacing: 8) {
                    Text("当前环境")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Image(systemName: "cloud.fill")
                            .foregroundStyle(.blue)
                        #if DEBUG
                        Text("Development (调试版)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        #else
                        Text("Production (发布版)")
                            .font(.caption)
                            .foregroundStyle(.green)
                        #endif
                    }
                    
                    Text("📢 已读状态: \(readStatusService.isSyncing ? "同步中..." : "已同步")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.top, 20)

                Text("公告管理功能测试")
                    .foregroundStyle(.secondary)

                // 同步状态
                if service.isSyncing || cloudKitService.isSyncing {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("同步中...")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                // 获取 iCloud ID（配置用）
                Button {
                    Task {
                        await cloudKitService.getCurrentUserID()
                    }
                } label: {
                    LabActionCard(
                        icon: "person.badge.key",
                        title: "获取我的 iCloud ID",
                        subtitle: "配置管理员权限时使用",
                        color: .orange
                    )
                }
                .padding(.horizontal)

                // 管理公告
                Button {
                    showNoticeAdmin = true
                } label: {
                    LabActionCard(
                        icon: "gear",
                        title: "管理公告",
                        subtitle: "添加、编辑、删除公告（需管理员权限）",
                        color: .blue
                    )
                }
                .padding(.horizontal)

                // 手动同步公告
                Button {
                    Task {
                        await service.manualSync()
                        syncMessage = service.errorMessage ?? "同步完成"
                        showSyncAlert = true
                    }
                } label: {
                    LabActionCard(
                        icon: "arrow.clockwise.icloud",
                        title: "手动同步公告",
                        subtitle: "从云端拉取最新公告",
                        color: .purple
                    )
                }
                .disabled(service.isSyncing)
                .padding(.horizontal)

                // 同步已读状态
                Button {
                    Task {
                        await readStatusService.syncFromCloud()
                        showReadStatusAlert = true
                    }
                } label: {
                    LabActionCard(
                        icon: "arrow.down.icloud",
                        title: "同步已读状态",
                        subtitle: "从 iCloud 同步已读状态",
                        color: .cyan
                    )
                }
                .disabled(readStatusService.isSyncing)
                .padding(.horizontal)

                // 预览公告
                Button {
                    showNoticePreview = true
                } label: {
                    LabActionCard(
                        icon: "eye",
                        title: "预览公告弹窗",
                        subtitle: "查看公告展示效果",
                        color: .green
                    )
                }
                .padding(.horizontal)

                // 重置记录
                Button {
                    showResetAlert = true
                } label: {
                    LabActionCard(
                        icon: "arrow.counterclockwise",
                        title: "重置公告展示记录",
                        subtitle: "清除已展示过的记录",
                        color: .red
                    )
                }
                .padding(.horizontal)

                // 显示当前公告数量
                if !service.notices.isEmpty {
                    Text("当前有 \(service.notices.count) 条公告")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }

                Spacer(minLength: 100)
            }
        }
        .sheet(isPresented: $showNoticeAdmin) {
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
            }
        } message: {
            Text("这将重置所有公告的展示记录，公告将可以再次展示。确定要继续吗？")
        }
        .onAppear {
            service.setup(with: modelContext)
        }
    }
}

// MARK: - 实验室操作卡片
struct LabActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 50, height: 50)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - 魔法任务测试子视图
struct MagicTasksTestView: View {
    @ObservedObject private var manager = FeatureUnlockManager.shared
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
                                .foregroundStyle(.purple)
                            Text("已解锁")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Divider()
                        
                        VStack(spacing: 4) {
                            Text("\(manager.getLockableFeatures().count)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.orange)
                            Text("待解锁")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Divider()
                        
                        VStack(spacing: 4) {
                            Text("\(manager.getVisibleFeatures().count)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.green)
                            Text("可见")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
                .padding(.horizontal)
                .padding(.top, 20)
                
                // 功能列表
                VStack(alignment: .leading, spacing: 12) {
                    Text("功能状态")
                        .font(.headline)
                        .foregroundStyle(.primary)
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
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(16)
                    }
                    
                    Text("将所有功能重置为初始状态（仅免费功能保持解锁）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.primary)
                
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            
            Spacer()
            
            // 状态指示器
            HStack(spacing: 8) {
                if manager.isUnlocked(feature) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.orange)
                }
                
                if !manager.isVisible(feature) {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
    
    private var iconColor: Color {
        if manager.canAccess(feature) {
            return .purple
        } else if manager.isUnlocked(feature) {
            return .gray
        } else {
            return .orange
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
            return manager.isVisible(feature) ? .green : .secondary
        } else {
            return .orange
        }
    }
}

// MARK: - 签到打卡测试子视图
struct CheckInTestView: View {
    @ObservedObject private var manager = DailyCheckInManager.shared
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
                        .foregroundStyle(.red)
                    
                    HStack(spacing: 30) {
                        VStack(spacing: 4) {
                            Text("\(manager.totalDays)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.primary)
                            Text("累计打卡")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack(spacing: 4) {
                            Text("\(manager.consecutiveDays)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.red)
                            Text("连续打卡")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if manager.hasCheckedInToday {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("今日已打卡")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    } else {
                        HStack {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                            Text("今日未打卡")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                )
                .padding(.horizontal)
                .padding(.top, 20)
                
                // 本周打卡状态
                VStack(alignment: .leading, spacing: 12) {
                    Text("本周打卡")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .padding(.horizontal)
                    
                    HStack(spacing: 8) {
                        ForEach(0..<7) { index in
                            let dayNames = ["一", "二", "三", "四", "五", "六", "日"]
                            VStack(spacing: 6) {
                                Text(dayNames[index])
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                if index < manager.weekCheckIns.count {
                                    Image(systemName: manager.weekCheckIns[index] ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(manager.weekCheckIns[index] ? .green : .secondary.opacity(0.3))
                                        .font(.title3)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
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
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.1))
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
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
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
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.1))
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
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
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
    
    // 为指定日期添加打卡记录
    private func addCheckInRecord(for date: Date) {
        let calendar = Calendar.current
        let colors = [
            ["樱花粉", "奶油白"],
            ["薰衣草紫", "珍珠白"],
            ["薄荷绿", "浅灰蓝"],
            ["玫瑰红", "香槟金"]
        ]
        let accessories = [
            "搭配粉色蝴蝶结发饰",
            "搭配珍珠项链和蕾丝手套",
            "搭配同色系包包和鞋子",
            "搭配复古发带和耳环"
        ]
        
        let testRecord = CheckInRecord(
            id: UUID().uuidString,
            date: date,
            colors: colors.randomElement()!,
            accessories: accessories.randomElement()!,
            weather: nil,
            location: nil,
            isAIGenerated: true
        )
        
        // 加载现有记录
        var records: [CheckInRecord] = []
        if let data = UserDefaults.standard.data(forKey: "dailyCheckIn.records"),
           let existingRecords = try? JSONDecoder().decode([CheckInRecord].self, from: data) {
            records = existingRecords
        }
        
        // 检查是否已有该日期的记录
        let hasRecord = records.contains { calendar.isDate($0.date, inSameDayAs: date) }
        if !hasRecord {
            records.append(testRecord)
            if let encoded = try? JSONEncoder().encode(records) {
                UserDefaults.standard.set(encoded, forKey: "dailyCheckIn.records")
            }
            // 更新统计
            let totalDays = UserDefaults.standard.integer(forKey: "dailyCheckIn.totalDays")
            UserDefaults.standard.set(totalDays + 1, forKey: "dailyCheckIn.totalDays")
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
                    .padding(.top, 20)

                // 月份导航
                HStack {
                    Button {
                        withAnimation {
                            currentMonth = previousMonth
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Text(monthYearString)
                        .font(.system(size: 17, weight: .semibold))

                    Spacer()

                    Button {
                        withAnimation {
                            currentMonth = nextMonth
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.primary)
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
                            .foregroundStyle(.secondary)
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
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("已打卡")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text("选中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                        Text("不可选")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)

                // 检查选中的日期是否已打卡
                if isSelectedDateCheckedIn {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("该日期已打卡，无需补卡")
                            .font(.caption)
                            .foregroundStyle(.green)
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
        formatter.locale = Locale(identifier: "zh_CN")
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

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            // 背景
            if isSelected {
                Circle()
                    .fill(Color.blue)
            } else if isCheckedIn {
                Circle()
                    .fill(Color.green.opacity(0.2))
            }

            // 日期数字
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(textColor)

            // 已打卡标记
            if isCheckedIn && !isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
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
            return .green
        } else {
            return .primary
        }
    }
}

// 公告预览遮罩已移至 NoticeAdminView.swift
