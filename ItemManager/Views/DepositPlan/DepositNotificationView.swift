//
//  DepositNotificationView.swift
//  ItemManager
//
//  补款提醒视图 - 全屏显示，默认折叠展开设置，点击小齿轮展开
//

import SwiftUI
import SwiftData

struct DepositNotificationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(NotificationManager.Keys.isDepositNotificationEnabled) private var isEnabled = false
    @State private var selectedDays: Set<Int> = []
    @State private var notificationTime: Date = Date()
    @State private var isExpanded = false
    @State private var showPermissionAlert = false
    @State private var showClearReadConfirmation = false

    @Query(filter: #Predicate<Clothing> { $0.isDepositPlan == true && $0.deletedAt == nil }) private var depositPlans: [Clothing]
    @Query(filter: #Predicate<DepositNotificationRecord> { $0.isTriggered == true }, sort: \DepositNotificationRecord.actualDate, order: .reverse) private var triggeredRecords: [DepositNotificationRecord]

    private var palette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    /// 未读记录数量
    private var unreadCount: Int {
        triggeredRecords.filter { !$0.isRead }.count
    }

    /// 已读记录数量
    private var readCount: Int {
        triggeredRecords.filter { $0.isRead }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 第一排：设置情况概览（默认折叠时显示）
                settingsSummarySection
                    .padding(.horizontal, 16)

                // 历史补款记录
                historySection
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .background(LiquidBackground())
        .navigationTitle("补款提醒")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") {
                    dismiss()
                }
            }
        }
        .onAppear {
            loadSettings()
            // 进入页面时限制历史记录数量
            NotificationManager.shared.enforceHistoryLimit(modelContext: modelContext)
        }
        .alert("需要通知权限", isPresented: $showPermissionAlert) {
            Button("去设置", role: .none) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("请在设置中允许 App 发送通知，以便接收补款提醒。")
        }
        .alert("清除已读通知", isPresented: $showClearReadConfirmation) {
            Button("清除", role: .destructive) {
                NotificationManager.shared.clearAllReadNotifications(modelContext: modelContext)
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("确定要清除所有已读的通知记录吗？此操作不可撤销。")
        }
    }

    // MARK: - 设置情况概览（默认折叠）

    private var settingsSummarySection: some View {
        VStack(spacing: 8) {
            // 标题栏：总开关 + 小齿轮
            HStack {
                Toggle("开启补款提醒", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        handleSettingsChange(enabled: newValue)
                    }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(isExpanded ? palette.accent : palette.secondaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }

            // 展开的设置面板
            if isExpanded {
                expandedSettingsPanel
            } else {
                // 折叠时显示设置摘要
                collapsedSettingsSummary
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - 折叠时显示的设置摘要

    private var collapsedSettingsSummary: some View {
        HStack(spacing: 6) {
            if isEnabled && !selectedDays.isEmpty {
                ForEach(selectedDays.sorted(), id: \.self) { day in
                    Text(dayText(for: day))
                        .font(.system(size: 11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(palette.accent.opacity(0.15))
                        .foregroundStyle(palette.accent)
                        .clipShape(Capsule())
                }

                Spacer()

                Text(formatTime(notificationTime))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)
            } else {
                Text("未开启提醒")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    // MARK: - 展开的设置面板

    private var expandedSettingsPanel: some View {
        VStack(spacing: 12) {
            // 提醒天数选择
            VStack(alignment: .leading, spacing: 6) {
                Text("提醒天数")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryText)

                FlowLayout(spacing: 6) {
                    ForEach([0, 1, 3, 7, 15, 30], id: \.self) { day in
                        dayChip(day: day)
                    }
                }
            }

            // 提醒时间
            HStack {
                Text("提醒时间")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryText)

                Spacer()

                DatePicker("", selection: $notificationTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .onChange(of: notificationTime) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: NotificationManager.Keys.depositNotificationTime)
                        handleSettingsChange(enabled: isEnabled)
                    }
            }
        }
        .padding(.top, 6)
    }

    // MARK: - 提醒天数芯片

    private func dayChip(day: Int) -> some View {
        let isSelected = selectedDays.contains(day)

        return Button {
            toggleDay(day)
        } label: {
            Text(dayText(for: day))
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? palette.accent : palette.accent.opacity(0.15))
                .foregroundStyle(isSelected ? .white : palette.accent)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 历史补款记录（已发送的提醒）

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题栏：标题 + 数量 + 操作按钮
            HStack {
                Text("已发送提醒")
                    .font(.headline)

                Spacer()

                // 显示未读/总数
                HStack(spacing: 4) {
                    if unreadCount > 0 {
                        Text("\(unreadCount) 未读")
                            .font(.caption)
                            .foregroundStyle(palette.cardAccent)
                    }
                    Text("/ \(triggeredRecords.count) 条")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            }

            // 操作按钮栏
            if !triggeredRecords.isEmpty {
                HStack(spacing: 12) {
                    // 一键已读按钮
                    if unreadCount > 0 {
                        Button {
                            NotificationManager.shared.markAllTriggeredAsRead(modelContext: modelContext)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle")
                                Text("一键已读")
                            }
                            .font(.caption)
                            .foregroundStyle(palette.accent)
                        }
                    }

                    Spacer()

                    // 一键清除已读按钮
                    if readCount > 0 {
                        Button {
                            showClearReadConfirmation = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("清除已读")
                            }
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                        }
                    }
                }
            }

            if triggeredRecords.isEmpty {
                emptyStateView
            } else {
                // 按裙装分组显示
                let groupedRecords = Dictionary(grouping: triggeredRecords) { $0.clothingName }
                ForEach(Array(groupedRecords.keys.sorted()), id: \.self) { clothingName in
                    if let records = groupedRecords[clothingName] {
                        TriggeredNotificationCard(
                            clothingName: clothingName,
                            records: records.sorted { ($0.actualDate ?? Date()) > ($1.actualDate ?? Date()) }
                        )
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 40))
                .foregroundStyle(palette.secondaryText.opacity(0.5))

            Text("暂无已发送的提醒")
                .font(.headline)
                .foregroundStyle(palette.secondaryText)

            Text("当补款提醒通过 Apple 通知发送后，将显示在这里")
                .font(.caption)
                .foregroundStyle(palette.secondaryText.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helper Methods

    private func loadSettings() {
        selectedDays = Set(NotificationManager.shared.daysBeforeList)

        if let date = UserDefaults.standard.object(forKey: NotificationManager.Keys.depositNotificationTime) as? Date {
            notificationTime = date
        } else {
            notificationTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        }
    }

    private func toggleDay(_ day: Int) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
        NotificationManager.shared.daysBeforeList = Array(selectedDays)
        handleSettingsChange(enabled: isEnabled)
    }

    private func dayText(for day: Int) -> String {
        switch day {
        case 0: return "当天"
        case 1: return "提前1天"
        case 3: return "3天"
        case 7: return "7天"
        case 15: return "15天"
        case 30: return "30天"
        default: return "提前\(day)天"
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func handleSettingsChange(enabled: Bool) {
        Task {
            if enabled {
                let status = await NotificationManager.shared.checkAuthorizationStatus()
                if status == .notDetermined {
                    let granted = try? await NotificationManager.shared.requestAuthorization()
                    if granted == false {
                        await MainActor.run {
                            isEnabled = false
                            showPermissionAlert = true
                        }
                        return
                    }
                } else if status == .denied {
                    await MainActor.run {
                        showPermissionAlert = true
                    }
                    return
                }
            }

            await NotificationManager.shared.rescheduleAllNotifications(clothings: depositPlans, modelContext: modelContext)
        }
    }
}

// MARK: - 已发送的提醒卡片

struct TriggeredNotificationCard: View {
    let clothingName: String
    let records: [DepositNotificationRecord]

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    private var palette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 裙装名称
            HStack {
                Text(clothingName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(records.count) 次提醒")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            // 已发送的提醒列表
            VStack(alignment: .leading, spacing: 8) {
                ForEach(records) { record in
                    NotificationRecordRow(record: record)
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - 单条通知记录行

struct NotificationRecordRow: View {
    let record: DepositNotificationRecord

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    private var palette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 8) {
            // 未读指示器
            if !record.isRead {
                Circle()
                    .fill(palette.cardAccent)
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 6, height: 6)
            }

            // 提醒时间
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDate(record.scheduledDate))
                    .font(.subheadline)
                    .fontWeight(record.isRead ? .regular : .medium)

                HStack(spacing: 4) {
                    // 来源标记
                    if record.source == "apple" {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 8))
                    }
                    Text(formatActualTime(record.actualDate))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            }

            Spacer()

            // 提前天数标签
            Text(dayText(for: record.daysBefore))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(record.isRead ? palette.secondaryText.opacity(0.1) : palette.accent.opacity(0.15))
                .foregroundStyle(record.isRead ? palette.secondaryText : palette.accent)
                .clipShape(Capsule())
        }
        .padding(8)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击标记为已读
            if !record.isRead {
                record.markAsRead()
                try? modelContext.save()
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private func formatActualTime(_ date: Date?) -> String {
        guard let date = date else { return "未触发" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm 发送"
        return formatter.string(from: date)
    }

    private func dayText(for day: Int) -> String {
        switch day {
        case 0: return "当天"
        case 1: return "提前 1 天"
        case 3: return "3 天"
        case 7: return "7 天"
        case 15: return "15 天"
        case 30: return "30 天"
        default: return "提前\(day)天"
        }
    }
}

// MARK: - GlobalSearchView 中的 FlowLayout 已实现
