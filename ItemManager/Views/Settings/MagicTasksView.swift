import SwiftUI

// MARK: - 魔法任务视图
struct MagicTasksView: View {
    @StateObject private var manager = FeatureUnlockManager.shared
    @Environment(\.dismiss) private var dismiss
    
    // 按解锁条件类型分组
    private var groupedFeatures: [(type: UnlockConditionType, features: [FeatureItem])] {
        let lockableFeatures = manager.getLockableFeatures()
        let grouped = Dictionary(grouping: lockableFeatures) { feature in
            UnlockConditionType(rawValue: manager.getCondition(for: feature).type) ?? .manual
        }
        
        return grouped.sorted { $0.key.displayName < $1.key.displayName }
            .map { (type: $0.key, features: $0.value) }
    }
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景 - 适配暗黑模式
                LiquidBackground()
                    .ignoresSafeArea()
                
                // 内容
                List {
                    // 顶部说明
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 40))
                                    .foregroundColor(.pink)
                                
                                Text("完成魔法任务")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                                
                                Text("解锁更多神奇功能")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    }
                    .listRowBackground(Color.clear)
                    
                    // 按类型分组显示任务
                    ForEach(groupedFeatures, id: \.type) { group in
                        Section {
                            ForEach(group.features) { feature in
                                MagicTaskRow(feature: feature)
                            }
                        } header: {
                            HStack {
                                Image(systemName: group.type.icon)
                                Text(group.type.displayName)
                            }
                            .foregroundColor(.pink)
                            .font(.caption)
                            .fontWeight(.medium)
                        }
                    }
                    
                    // 兑换码提示
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "key.fill")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                                
                                Text("有兑换码？")
                                    .font(.headline)
                                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                                
                                Text("前往 VIP 中心输入兑换码\n直接解锁隐藏功能")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 16)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.orange.opacity(colorScheme == .dark ? 0.15 : 0.05))
                }
                .scrollContentBackground(.hidden) // 隐藏List默认背景
            }
            .navigationTitle("魔法任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 魔法任务行
struct MagicTaskRow: View {
    let feature: FeatureItem
    
    @StateObject private var manager = FeatureUnlockManager.shared
    @State private var showDetail = false
    
    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 12) {
                // 图标
                ZStack {
                    Circle()
                        .fill(backgroundColor)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: feature.icon)
                        .font(.system(size: 18))
                        .foregroundColor(iconColor)
                }
                
                // 内容
                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    let condition = manager.getCondition(for: feature)
                    Text(condition.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // 状态
                statusView
            }
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showDetail) {
            MagicTaskDetailView(feature: feature)
        }
    }
    
    private var backgroundColor: Color {
        if manager.isUnlocked(feature) {
            return .green.opacity(0.1)
        } else {
            return .gray.opacity(0.1)
        }
    }
    
    private var iconColor: Color {
        if manager.isUnlocked(feature) {
            return .green
        } else {
            return .gray
        }
    }
    
    @ViewBuilder
    private var statusView: some View {
        if manager.isUnlocked(feature) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)
        } else {
            let check = manager.checkUnlockCondition(feature)
            if check.met {
                // 条件满足但未解锁
                Text("可解锁")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.pink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.pink.opacity(0.1))
                    .cornerRadius(8)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
        }
    }
}

// MARK: - 魔法任务详情视图
struct MagicTaskDetailView: View {
    let feature: FeatureItem
    
    @StateObject private var manager = FeatureUnlockManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showUnlockAlert = false
    @State private var unlockMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景 - 适配暗黑模式
                LiquidBackground()
                    .ignoresSafeArea()
                
                // 内容
                List {
                    // 顶部图标和名称
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(manager.isUnlocked(feature) ? Color.green.opacity(colorScheme == .dark ? 0.2 : 0.1) : Color.pink.opacity(colorScheme == .dark ? 0.2 : 0.1))
                                        .frame(width: 100, height: 100)
                                    
                                    Image(systemName: feature.icon)
                                        .font(.system(size: 50))
                                        .foregroundColor(manager.isUnlocked(feature) ? .green : .pink)
                                }
                                
                                Text(feature.displayName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                                
                                // 状态标签
                                statusBadge
                            }
                            Spacer()
                        }
                        .padding(.vertical, 30)
                    }
                    .listRowBackground(Color.clear)
                    
                    // 解锁条件
                    Section("解锁条件") {
                        let condition = manager.getCondition(for: feature)
                        
                        HStack {
                            Image(systemName: conditionIcon(for: condition))
                                .frame(width: 24)
                                .foregroundColor(.pink)
                            Text("解锁方式")
                            Spacer()
                            Text(UnlockConditionType(rawValue: condition.type)?.displayName ?? "未知")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Image(systemName: "text.bubble")
                                .frame(width: 24)
                                .foregroundColor(.pink)
                            Text("任务说明")
                            Spacer()
                            Text(condition.description)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        // 进度条
                        if let progress = calculateProgress(for: condition) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(progress.isCompleted ? "已完成" : "当前进度")
                                        .font(.subheadline)
                                        .foregroundColor(progress.isCompleted ? .green : .primary)
                                    Spacer()
                                    Text("\(Int(progress.current)) / \(Int(progress.total))")
                                        .font(.caption)
                                        .foregroundColor(progress.isCompleted ? .green : .secondary)
                                }
                                
                                ProgressView(value: min(progress.current, progress.total), total: progress.total)
                                    .progressViewStyle(.linear)
                                    .tint(progress.isCompleted ? .green : .pink)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    
                    // 解锁按钮
                    if !manager.isUnlocked(feature) {
                        Section {
                            let check = manager.checkUnlockCondition(feature)
                            
                            if check.met {
                                Button {
                                    unlockFeature()
                                } label: {
                                    HStack {
                                        Spacer()
                                        Image(systemName: "lock.open.fill")
                                        Text("立即解锁")
                                            .fontWeight(.medium)
                                        Spacer()
                                    }
                                }
                                .tint(.pink)
                            } else {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Image(systemName: "lock.fill")
                                            .font(.title2)
                                            .foregroundColor(.orange)
                                        
                                        Text(check.message ?? "尚未满足解锁条件")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 20)
                            }
                        }
                    }
                    
                    // 已解锁信息显示
                    if manager.isUnlocked(feature) {
                        Section("解锁信息") {
                            if let unlockedAt = manager.getStatus(for: feature).unlockedAt {
                                HStack {
                                    Text("解锁时间")
                                    Spacer()
                                    Text(unlockedAt, style: .date)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let unlockedBy = manager.getStatus(for: feature).unlockedBy {
                                HStack {
                                    Text("解锁方式")
                                    Spacer()
                                    Text(unlockedBy)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden) // 隐藏List默认背景
            }
            .navigationTitle("任务详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("解锁结果", isPresented: $showUnlockAlert) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(unlockMessage)
            }
        }
    }
    
    private var statusBadge: some View {
        let isUnlocked = manager.isUnlocked(feature)
        
        return HStack(spacing: 6) {
            Image(systemName: isUnlocked ? "checkmark.circle.fill" : "lock.fill")
            Text(isUnlocked ? "已解锁" : "未解锁")
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(isUnlocked ? .green : .orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            (isUnlocked ? Color.green : Color.orange)
                .opacity(0.15)
        )
        .cornerRadius(12)
    }
    
    private func unlockFeature() {
        let result = manager.unlock(feature)
        
        switch result {
        case .success:
            unlockMessage = "\(feature.displayName) 解锁成功！"
        case .alreadyUnlocked:
            unlockMessage = "\(feature.displayName) 已经解锁了"
        case .conditionNotMet(let message):
            unlockMessage = "解锁失败：\(message)"
        case .insufficientResource(let type, let required, let current):
            unlockMessage = "\(type)不足，需要 \(required)，当前只有 \(current)"
        }
        
        showUnlockAlert = true
    }
    
    private func conditionIcon(for condition: UnlockCondition) -> String {
        guard let type = UnlockConditionType(rawValue: condition.type) else {
            return "lock.fill"
        }
        return type.icon
    }
    
    private func calculateProgress(for condition: UnlockCondition) -> (current: Double, total: Double, isCompleted: Bool)? {
        // 如果已解锁，显示完整进度 1/1
        if manager.isUnlocked(feature) {
            return (1, 1, true)
        }
        
        guard let type = UnlockConditionType(rawValue: condition.type),
              type != .free,
              type != .manual,
              type != .redeemCode else {
            return nil
        }
        
        let current: Double
        let total = Double(condition.requiredValue)
        
        switch type {
        case .vip:
            current = VIPManager.shared.isVIP ? 1 : 0
        case .meowCoin:
            current = Double(PetDataManager.shared.status.meowCoin)
        case .clothingCount:
            current = Double(UserDefaults.standard.integer(forKey: "clothingCount_cache"))
        case .loginDays:
            current = Double(UserDefaults.standard.integer(forKey: "loginDays"))
        case .petLevel:
            current = 0
        default:
            return nil
        }
        
        let isCompleted = current >= total
        return (current, total, isCompleted)
    }
}

// MARK: - 预览
#Preview {
    MagicTasksView()
}
