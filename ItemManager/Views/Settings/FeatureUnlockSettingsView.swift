import SwiftUI
import SwiftData

// MARK: - 功能解锁管理设置页面
struct FeatureUnlockSettingsView: View {
    @StateObject private var manager = FeatureUnlockManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    // 只获取通过魔法任务解锁的功能
    private var magicTaskFeatures: [FeatureItem] {
        manager.getLockableFeatures()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()

                // 内容
                featureToggleView
            }
            .navigationTitle("功能管理")
            .navigationBarTitleDisplayMode(.inline
            )
        }
    }

    // MARK: - 功能开关视图
    private var featureToggleView: some View {
        List {
            // 说明文字
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "switch.2")
                            .font(.system(size: 32))
                            .foregroundColor(themeManager.accentTextColor)

                        Text("功能开关")
                            .font(.headline)
                            .foregroundColor(themeManager.primaryTextColor)

                        Text("开启或关闭通过魔法任务解锁的功能\n关闭后功能将从菜单中隐藏")
                            .font(.caption)
                            .foregroundColor(themeManager.secondaryTextColor)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)

            // 功能开关列表
            Section {
                ForEach(magicTaskFeatures) { feature in
                    FeatureToggleRow(feature: feature)
                }
            } header: {
                Text("魔法任务功能")
                    .foregroundColor(themeManager.primaryTextColor)
            } footer: {
                Text("只有已解锁的功能才能开启，未解锁的功能需要先完成魔法任务")
                    .foregroundColor(themeManager.secondaryTextColor)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - 功能开关行
struct FeatureToggleRow: View {
    let feature: FeatureItem

    @StateObject private var manager = FeatureUnlockManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @State private var isEnabled: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // 图标
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 36, height: 36)

                Image(systemName: feature.icon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
            }

            // 内容
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(themeManager.primaryTextColor)

                Text(statusText)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }

            Spacer()

            // 开关
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .disabled(!manager.isUnlocked(feature))
                .onChange(of: isEnabled) { oldValue, newValue in
                    // 同步开关状态到功能显示状态
                    manager.setVisible(feature, visible: newValue)
                }
        }
        .padding(.vertical, 8)
        .onAppear {
            // 初始化开关状态
            isEnabled = manager.isVisible(feature) && manager.isUnlocked(feature)
        }
        .onReceive(NotificationCenter.default.publisher(for: FeatureUnlockManager.featureStatusChangedNotification)) { _ in
            // 当功能状态改变时更新开关
            isEnabled = manager.isVisible(feature) && manager.isUnlocked(feature)
        }
    }

    // MARK: - 样式计算

    private var backgroundColor: Color {
        if manager.isUnlocked(feature) {
            return themeManager.accentTextColor.opacity(0.1)
        } else {
            return themeManager.tertiaryTextColor.opacity(0.1)
        }
    }

    private var iconColor: Color {
        if manager.isUnlocked(feature) {
            return themeManager.accentTextColor
        } else {
            return themeManager.tertiaryTextColor
        }
    }

    private var statusText: String {
        if manager.isUnlocked(feature) {
            return manager.isVisible(feature) ? "已开启" : "已关闭"
        } else {
            let condition = manager.getCondition(for: feature)
            return "\("未解锁".appLocalized) · \(condition.localizedDescription)"
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

// MARK: - 预览
#Preview {
    FeatureUnlockSettingsView()
}
