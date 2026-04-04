import SwiftUI

// MARK: - 魔法任务视图
struct MagicTasksView: View {
    @StateObject private var manager = FeatureUnlockManager.shared
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss
    @State private var guideDismissWasRequested = false

    // 按解锁条件类型分组
    private var groupedFeatures: [(type: UnlockConditionType, features: [FeatureItem])] {
        let lockableFeatures = manager.getLockableFeatures()
        let grouped = Dictionary(grouping: lockableFeatures) { feature in
            UnlockConditionType(rawValue: manager.getCondition(for: feature).type) ?? .manual
        }

        // 自定义排序：VIP专属 > 签到解锁 > 萌宠等级 > 收集解锁 > 喵币解锁 > 活动解锁
        let sortOrder: [UnlockConditionType] = [
            .vip,           // VIP专属
            .loginDays,     // 签到解锁
            .petLevel,      // 萌宠等级
            .clothingCount, // 收集解锁
            .meowCoin,      // 喵币解锁
            .manual          // 活动解锁
        ]

        return grouped.sorted {
            let index0 = sortOrder.firstIndex(of: $0.key) ?? Int.max
            let index1 = sortOrder.firstIndex(of: $1.key) ?? Int.max
            return index0 < index1
        }.map { (type: $0.key, features: $0.value) }
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
                                    .foregroundColor(themeManager.accentTextColor)

                                Text("完成魔法任务")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(themeManager.primaryTextColor)

                                Text("解锁更多神奇功能")
                                    .font(.caption)
                                    .foregroundColor(themeManager.secondaryTextColor)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    }
                    .listRowBackground(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.3 : 0.15))

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
                            .foregroundColor(themeManager.accentTextColor)
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
                                    .foregroundColor(themeManager.accentTextColor)

                                Text("有兑换码？")
                                    .font(.headline)
                                    .foregroundColor(themeManager.primaryTextColor)

                                Text("前往 VIP 中心输入兑换码\n直接解锁隐藏功能")
                                    .font(.caption)
                                    .foregroundColor(themeManager.secondaryTextColor)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 16)
                            Spacer()
                        }
                    }
                    .listRowBackground(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.3 : 0.15))
                }
                .scrollContentBackground(.hidden) // 隐藏List默认背景
            }
            .navigationTitle("魔法任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        markGuideDismissIfNeeded()
                        dismiss()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissMagicTasksView)) { _ in
                markGuideDismissIfNeeded()
                dismiss()
            }
            .onDisappear {
                NotificationCenter.default.post(
                    name: .magicTasksViewDismissed,
                    object: nil,
                    userInfo: ["guideDismissWasRequested": guideDismissWasRequested]
                )
                guideDismissWasRequested = false
            }
        }
    }

    private func markGuideDismissIfNeeded() {
        if guideManager.isShowingFeatureExperienceGuide {
            guideDismissWasRequested = true
        }
    }
}

// MARK: - 魔法任务行
struct MagicTaskRow: View {
    let feature: FeatureItem

    @StateObject private var manager = FeatureUnlockManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
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
                        .foregroundColor(themeManager.primaryTextColor)

                    Text(feature.defaultCondition.description)
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryTextColor)
                        .lineLimit(1)
                }

                Spacer()

                // 状态
                statusView
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.6 : 0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(themeManager.accentTextColor.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .captureGuideTarget(feature == .ootd ? .magicTasksOotdTaskRow : nil)
        .sheet(isPresented: $showDetail) {
            MagicTaskDetailView(feature: feature)
        }
    }

    private var backgroundColor: Color {
        if manager.isUnlocked(feature) {
            return themeManager.accentTextColor.opacity(0.1)
        } else {
            return themeManager.secondaryTextColor.opacity(0.1)
        }
    }

    private var iconColor: Color {
        if manager.isUnlocked(feature) {
            return themeManager.accentTextColor
        } else {
            return themeManager.secondaryTextColor
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if manager.isUnlocked(feature) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(themeManager.accentTextColor)
                .font(.title3)
        } else {
            let check = manager.checkUnlockCondition(feature)
            if check.met {
                // 条件满足但未解锁
                Text("可解锁")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(themeManager.accentTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(themeManager.accentTextColor.opacity(0.1))
                    .cornerRadius(8)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(themeManager.tertiaryTextColor)
                    .font(.caption)
            }
        }
    }
}

// MARK: - 魔法任务详情视图
struct MagicTaskDetailView: View {
    let feature: FeatureItem

    @StateObject private var manager = FeatureUnlockManager.shared
    @Environment(ThemeManager.self) private var themeManager
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
                                        .fill(manager.isUnlocked(feature) ? themeManager.accentTextColor.opacity(colorScheme == .dark ? 0.2 : 0.1) : themeManager.accentTextColor.opacity(colorScheme == .dark ? 0.2 : 0.1))
                                        .frame(width: 100, height: 100)

                                    Image(systemName: feature.icon)
                                        .font(.system(size: 50))
                                        .foregroundColor(manager.isUnlocked(feature) ? themeManager.accentTextColor : themeManager.accentTextColor)
                                }

                                Text(feature.displayName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(themeManager.primaryTextColor)

                                // 状态标签
                                statusBadge
                            }
                            Spacer()
                        }
                        .padding(.vertical, 30)
                    }
                    .listRowBackground(Color.clear)

                    let condition = manager.getCondition(for: feature)
                    let conditionType = UnlockConditionType(rawValue: condition.type)
                    let progress = calculateProgress(for: condition)
                    let isExperienceTask = condition.type == UnlockConditionType.manual.rawValue
                    let isUnlocked = manager.isUnlocked(feature)
                    let hasDestination = feature.destination != nil || feature.isSettingsFeature
                    let experienceGuideStepCount = feature.experienceGuideStepCount
                    let experienceFishCoinReward = feature.experienceFishCoinReward
                    let canShowGuide = FeatureUnlockManager.experienceGuidedFeatures.contains(feature) && (
                        isExperienceTask || isUnlocked || manager.canStartPreUnlockGuide(for: feature)
                    )
                    let unlockCheck = manager.checkUnlockCondition(feature)

                    // 核心信息（双列豆腐块）
                    Section("核心信息") {
                        VStack(spacing: 12) {
                            LazyVGrid(columns: infoColumns, spacing: 12) {
                                infoTofuBlock(
                                    title: "任务类型",
                                    value: conditionType?.displayName ?? "体验任务",
                                    icon: conditionType?.icon ?? "sparkles"
                                )

                                infoTofuBlock(
                                    title: "任务状态",
                                    value: isUnlocked ? "已完成" : "未完成",
                                    icon: isUnlocked ? "checkmark.circle.fill" : "clock",
                                    emphasized: isUnlocked
                                )

                                if isExperienceTask,
                                   let reward = experienceFishCoinReward {
                                    infoTofuBlock(
                                        title: "任务奖励",
                                        value: "鱼币 +\(reward)",
                                        icon: "sparkles.rectangle.stack.fill",
                                        emphasized: true
                                    )
                                }

                                if isExperienceTask,
                                   let stepCount = experienceGuideStepCount {
                                    infoTofuBlock(
                                        title: "引导步数",
                                        value: "\(stepCount) 步",
                                        icon: "figure.walk"
                                    )
                                }
                            }

                            if let progress {
                                progressTofuBlock(progress)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "text.alignleft")
                                        .font(.caption)
                                        .foregroundColor(themeManager.secondaryTextColor)
                                    Text("任务说明")
                                        .font(.caption)
                                        .foregroundColor(themeManager.secondaryTextColor)
                                }
                                Text(condition.description)
                                    .font(.subheadline)
                                    .foregroundColor(themeManager.primaryTextColor)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.65 : 0.9))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(themeManager.accentTextColor.opacity(0.12), lineWidth: 1)
                            )

                            if !isUnlocked {
                                progressSpaceBlock(
                                    progress: progress,
                                    conditionType: conditionType,
                                    fallbackMessage: unlockCheck.message
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // 解锁按钮
                    if !isUnlocked && !unlockCheck.met {
                        Section {
                            statusHintTofuBlock(
                                message: unlockCheck.message ?? "尚未满足解锁条件"
                            )
                        }
                    }

                    // 任务操作按钮
                    let shouldShowActionSection = (!isUnlocked && (unlockCheck.met || canShowGuide)) || (isUnlocked && (hasDestination || canShowGuide))
                    if shouldShowActionSection {
                        Section("推荐操作") {
                            VStack(spacing: 12) {
                                if !isUnlocked {
                                    if unlockCheck.met {
                                        taskActionTofuBlock(
                                            title: "立即解锁",
                                            icon: "lock.open.fill",
                                            style: .primary,
                                            actionGuideTarget: feature == .ootd ? .magicTasksOotdUnlockButton : nil
                                        ) {
                                            unlockFeature()
                                        }
                                    } else if canShowGuide {
                                        taskActionTofuBlock(
                                            title: "去完成任务",
                                            icon: "sparkles",
                                            style: .primary
                                        ) {
                                            dismissAndShowGuide()
                                        }
                                    }
                                } else {
                                    if hasDestination {
                                        taskActionTofuBlock(
                                            title: "进入功能",
                                            icon: "arrow.right.circle.fill",
                                            style: .primary
                                        ) {
                                            dismissAndNavigateToFeature()
                                        }
                                    }

                                    if canShowGuide {
                                        taskActionTofuBlock(
                                            title: "新手引导",
                                            icon: "sparkles",
                                            style: .secondary
                                        ) {
                                            dismissAndShowGuide()
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
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
        .foregroundColor(isUnlocked ? themeManager.accentTextColor : themeManager.tertiaryTextColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            (isUnlocked ? themeManager.accentTextColor : themeManager.tertiaryTextColor)
                .opacity(0.15)
        )
        .cornerRadius(12)
    }

    private var infoColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private func infoTofuBlock(
        title: String,
        value: String,
        icon: String,
        emphasized: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(themeManager.accentTextColor)
                Text(title)
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
            }

            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(emphasized ? themeManager.accentTextColor : themeManager.primaryTextColor)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.65 : 0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(themeManager.accentTextColor.opacity(0.12), lineWidth: 1)
        )
    }

    private func progressTofuBlock(_ progress: (current: Double, total: Double, isCompleted: Bool)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(progress.isCompleted ? "进度已达成" : "进度条")
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
                Spacer()
                Text("\(Int(progress.current)) / \(Int(progress.total))")
                    .font(.caption)
                    .foregroundColor(progress.isCompleted ? themeManager.accentTextColor : themeManager.secondaryTextColor)
            }

            ProgressView(value: min(progress.current, progress.total), total: progress.total)
                .progressViewStyle(.linear)
                .tint(themeManager.accentTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.65 : 0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(themeManager.accentTextColor.opacity(0.12), lineWidth: 1)
        )
    }

    private func progressSpaceBlock(
        progress: (current: Double, total: Double, isCompleted: Bool)?,
        conditionType: UnlockConditionType?,
        fallbackMessage: String?
    ) -> some View {
        let message = progressSpaceMessage(
            progress: progress,
            conditionType: conditionType,
            fallbackMessage: fallbackMessage
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.circle")
                    .font(.caption)
                    .foregroundColor(themeManager.accentTextColor)
                Text("进步空间")
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
            }

            Text(message)
                .font(.subheadline)
                .foregroundColor(themeManager.primaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.65 : 0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(themeManager.accentTextColor.opacity(0.12), lineWidth: 1)
        )
    }

    private func progressSpaceMessage(
        progress: (current: Double, total: Double, isCompleted: Bool)?,
        conditionType: UnlockConditionType?,
        fallbackMessage: String?
    ) -> String {
        guard let progress else {
            return fallbackMessage ?? "继续完成任务条件即可解锁。"
        }

        if progress.isCompleted {
            return "条件已达成，点击下方“立即解锁”即可完成任务。"
        }

        let remaining = max(0, Int(ceil(progress.total - progress.current)))
        switch conditionType {
        case .vip:
            return "开通 VIP 即可完成任务。"
        case .meowCoin:
            return "还差 \(remaining) 喵币的累计消费，去其他功能里使用喵币即可继续推进。"
        case .clothingCount:
            return "还差 \(remaining) 件衣物，继续录入衣橱即可推进。"
        case .loginDays:
            return "再签到 \(remaining) 天即可完成任务。"
        case .petLevel:
            return "萌宠等级还差 \(remaining) 级，继续陪伴互动可升级。"
        default:
            return fallbackMessage ?? "继续完成任务条件即可解锁。"
        }
    }

    private enum TaskActionStyle {
        case primary
        case secondary
    }

    private func statusHintTofuBlock(message: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title2)
                    .foregroundColor(themeManager.tertiaryTextColor)

                Text(message)
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.65 : 0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(themeManager.accentTextColor.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func taskActionTofuBlock(
        title: String,
        icon: String,
        style: TaskActionStyle,
        actionGuideTarget: GuideTargetKey? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .opacity(style == .primary ? 0.9 : 0.55)
            }
            .foregroundColor(style == .primary ? .white : themeManager.primaryTextColor)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        style == .primary
                        ? themeManager.accentTextColor
                        : themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.65 : 0.9)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        style == .primary
                        ? themeManager.accentTextColor.opacity(0.25)
                        : themeManager.accentTextColor.opacity(0.12),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .captureGuideTarget(actionGuideTarget)
    }

    private func dismissAndShowGuide() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
                name: .showFirstUseGuide,
                object: nil,
                userInfo: ["feature": feature.rawValue]
            )
        }
    }

    private func dismissAndNavigateToFeature() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            feature.postNavigationFromMagicTask()
        }
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
        let total = max(1.0, Double(condition.requiredValue))
        
        switch type {
        case .vip:
            current = VIPManager.shared.isVIP ? 1 : 0
        case .meowCoin:
            current = Double(StoreManager.synchronizedMeowCoinAccount().totalSpent)
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
