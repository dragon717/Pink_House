import SwiftUI
import SwiftData

// MARK: - 功能解锁管理设置页面
struct FeatureUnlockSettingsView: View {
    @StateObject private var manager = FeatureUnlockManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    @State private var showUnlockConfirmation = false
    @State private var showLockConfirmation = false
    @State private var selectedFeature: FeatureItem?
    @State private var showUnlockAlert = false
    @State private var unlockMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()

                // 内容
                featureManagementView
            }
            .navigationTitle("功能管理")
            .navigationBarTitleDisplayMode(.inline)
            .alert("解锁确认", isPresented: $showUnlockConfirmation) {
                Button("取消", role: .cancel) { }
                Button("解锁") {
                    if let feature = selectedFeature {
                        unlockFeature(feature)
                    }
                }
            } message: {
                if let feature = selectedFeature {
                    let condition = manager.getCondition(for: feature)
                    Text("确定要解锁 \(feature.displayName) 吗？\n\(condition.description)")
                }
            }
            .alert("锁定确认", isPresented: $showLockConfirmation) {
                Button("取消", role: .cancel) { }
                Button("锁定", role: .destructive) {
                    if let feature = selectedFeature {
                        manager.lock(feature)
                    }
                }
            } message: {
                if let feature = selectedFeature {
                    Text("确定要锁定 \(feature.displayName) 吗？锁定后需要重新满足条件才能使用。")
                }
            }
            .alert("解锁结果", isPresented: $showUnlockAlert) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(unlockMessage)
            }
        }
    }
    
    // MARK: - 功能管理视图
    private var featureManagementView: some View {
        List {
            // 已解锁且显示的功能
            Section {
                let accessibleFeatures = manager.getAccessibleFeatures()
                if accessibleFeatures.isEmpty {
                    Text("暂无已解锁的功能")
                        .foregroundColor(themeManager.secondaryTextColor)
                        .font(.caption)
                } else {
                    ForEach(accessibleFeatures) { feature in
                        AccessibleFeatureRow(
                            feature: feature,
                            onHide: { manager.setVisible(feature, visible: false) },
                            onLock: {
                                selectedFeature = feature
                                showLockConfirmation = true
                            }
                        )
                    }
                }
            } header: {
                HStack {
                    Text("已解锁且显示")
                        .foregroundColor(themeManager.primaryTextColor)
                    Spacer()
                    Text("\(manager.getAccessibleFeatures().count) 个")
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryTextColor)
                }
            }

            // 已解锁但不显示的功能
            Section {
                let unlockedHiddenFeatures = manager.getUnlockedFeatures().filter { !manager.isVisible($0) }
                if unlockedHiddenFeatures.isEmpty {
                    Text("暂无隐藏的功能")
                        .foregroundColor(themeManager.secondaryTextColor)
                        .font(.caption)
                } else {
                    ForEach(unlockedHiddenFeatures) { feature in
                        HiddenFeatureRow(
                            feature: feature,
                            onShow: { manager.setVisible(feature, visible: true) },
                            onLock: {
                                selectedFeature = feature
                                showLockConfirmation = true
                            }
                        )
                    }
                }
            } header: {
                HStack {
                    Text("已解锁但隐藏")
                        .foregroundColor(themeManager.primaryTextColor)
                    Spacer()
                    Text("\(manager.getUnlockedFeatures().filter { !manager.isVisible($0) }.count) 个")
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryTextColor)
                }
            }

            // 未解锁的功能
            Section {
                let lockedFeatures = FeatureItem.allCases.filter { !manager.isUnlocked($0) }
                if lockedFeatures.isEmpty {
                    Text("所有功能已解锁")
                        .foregroundColor(themeManager.secondaryTextColor)
                        .font(.caption)
                } else {
                    ForEach(lockedFeatures) { feature in
                        LockedFeatureRow(
                            feature: feature,
                            onUnlock: {
                                selectedFeature = feature
                                showUnlockConfirmation = true
                            }
                        )
                    }
                }
            } header: {
                HStack {
                    Text("未解锁")
                        .foregroundColor(themeManager.primaryTextColor)
                    Spacer()
                    Text("\(FeatureItem.allCases.filter { !manager.isUnlocked($0) }.count) 个")
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryTextColor)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
    
    private func unlockFeature(_ feature: FeatureItem) {
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
}

// MARK: - 可访问功能行（已解锁且显示）
struct AccessibleFeatureRow: View {
    let feature: FeatureItem
    let onHide: () -> Void
    let onLock: () -> Void
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack {
            Image(systemName: feature.icon)
                .frame(width: 24)
                .foregroundColor(themeManager.accentTextColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.displayName)
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.primaryTextColor)

                Text("已解锁 · 显示中")
                    .font(.caption)
                    .foregroundColor(themeManager.accentTextColor)
            }

            Spacer()

            Menu {
                Button {
                    onHide()
                } label: {
                    Label("隐藏", systemImage: "eye.slash")
                }

                Button(role: .destructive) {
                    onLock()
                } label: {
                    Label("重新锁定", systemImage: "lock.fill")
                }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(themeManager.accentTextColor)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 隐藏功能行（已解锁但不显示）
struct HiddenFeatureRow: View {
    let feature: FeatureItem
    let onShow: () -> Void
    let onLock: () -> Void
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack {
            Image(systemName: feature.icon)
                .frame(width: 24)
                .foregroundColor(themeManager.secondaryTextColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.displayName)
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.secondaryTextColor)

                Text("已解锁 · 已隐藏")
                    .font(.caption)
                    .foregroundColor(themeManager.tertiaryTextColor)
            }

            Spacer()

            Menu {
                Button {
                    onShow()
                } label: {
                    Label("显示", systemImage: "eye")
                }

                Button(role: .destructive) {
                    onLock()
                } label: {
                    Label("重新锁定", systemImage: "lock.fill")
                }
            } label: {
                Image(systemName: "eye.slash.fill")
                    .foregroundColor(themeManager.tertiaryTextColor)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 锁定功能行（未解锁）
struct LockedFeatureRow: View {
    let feature: FeatureItem
    let onUnlock: () -> Void

    @StateObject private var manager = FeatureUnlockManager.shared
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack {
            Image(systemName: feature.icon)
                .frame(width: 24)
                .foregroundColor(themeManager.secondaryTextColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.displayName)
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.secondaryTextColor)

                let condition = manager.getCondition(for: feature)
                Text(condition.description)
                    .font(.caption)
                    .foregroundColor(themeManager.tertiaryTextColor)
            }

            Spacer()

            let check = manager.checkUnlockCondition(feature)

            if check.met {
                Button {
                    onUnlock()
                } label: {
                    Text("解锁")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(themeManager.accentTextColor)
                        .cornerRadius(12)
                }
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(themeManager.tertiaryTextColor)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 状态徽章
struct StatusBadge: View {
    let feature: FeatureItem

    @StateObject private var manager = FeatureUnlockManager.shared
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let isUnlocked = manager.isUnlocked(feature)
        let isVisible = manager.isVisible(feature)

        HStack(spacing: 6) {
            if isUnlocked && isVisible {
                Image(systemName: "checkmark.circle.fill")
                Text("已解锁")
            } else if isUnlocked && !isVisible {
                Image(systemName: "eye.slash.fill")
                Text("已隐藏")
            } else {
                Image(systemName: "lock.fill")
                Text("未解锁")
            }
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(isUnlocked ? (isVisible ? themeManager.accentTextColor : themeManager.tertiaryTextColor) : themeManager.secondaryTextColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            (isUnlocked ? (isVisible ? themeManager.accentTextColor : themeManager.tertiaryTextColor) : themeManager.secondaryTextColor)
                .opacity(0.15)
        )
        .cornerRadius(12)
    }
}

// MARK: - 预览
#Preview {
    FeatureUnlockSettingsView()
}
