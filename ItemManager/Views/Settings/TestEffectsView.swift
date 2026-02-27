
import SwiftUI

// MARK: - 实验室功能模块枚举
enum LabModule: String, CaseIterable, Identifiable {
    case effects = "特效测试"
    case vip = "VIP 测试"
    case favoriteMenu = "菜单设置"
    case notice = "公告管理"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .effects: return "sparkles"
        case .vip: return "crown.fill"
        case .favoriteMenu: return "star.fill"
        case .notice: return "megaphone.fill"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .effects: return .pink
        case .vip: return .yellow
        case .favoriteMenu: return .orange
        case .notice: return .blue
        }
    }
    
    var subtitle: String {
        switch self {
        case .effects: return "礼花 · 蝴蝶"
        case .vip: return "状态 · 重置"
        case .favoriteMenu: return "常用 · 清除"
        case .notice: return "管理 · 预览"
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
                        icon: "checkmark.circle.icloud",
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

// 公告预览遮罩已移至 NoticeAdminView.swift
