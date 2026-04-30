//
//  DepositNotificationView.swift
//  ItemManager
//
//  补款提醒视图 - 全屏显示，默认折叠展开设置，点击小齿轮展开
//

import SwiftUI
import SwiftData
import UserNotifications
import os

struct DepositNotificationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    private let logger = AppLogger.category("DepositNotificationView")

    @AppStorage(NotificationManager.Keys.isDepositNotificationEnabled) private var isEnabled = false
    @State private var selectedDays: Set<Int> = []
    @State private var notificationTime: Date = Date()
    @State private var isExpanded = false
    @State private var showPermissionAlert = false
    @State private var showClearReadConfirmation = false
    @State private var testAlertMessage: String?
    @State private var debugSnapshot: NotificationDebugSnapshot?
    @State private var settingsSyncTask: Task<Void, Never>?
    @State private var isHistoryExpanded = true
    @State private var isPendingExpanded = false

    @Query(filter: #Predicate<Clothing> { $0.isDepositPlan == true && $0.deletedAt == nil }) private var depositPlans: [Clothing]
    @Query(filter: #Predicate<DepositNotificationRecord> { $0.isTriggered == false }, sort: \DepositNotificationRecord.scheduledDate, order: .forward) private var pendingRecords: [DepositNotificationRecord]
    @Query(filter: #Predicate<DepositNotificationRecord> { $0.isTriggered == true }, sort: \DepositNotificationRecord.actualDate, order: .reverse) private var triggeredRecords: [DepositNotificationRecord]

    private var palette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var totalPendingBalance: Decimal {
        depositPlans.reduce(Decimal(0)) { $0 + $1.totalBalance }
    }

    private var nextPendingRecord: DepositNotificationRecord? {
        pendingRecords.min { $0.scheduledDate < $1.scheduledDate }
    }

    private var nearestPaymentClothing: Clothing? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let datedPlans = depositPlans.filter { $0.finalPaymentDate != nil }
        let activeOrUpcoming = datedPlans
            .filter { clothing in
                guard let start = clothing.finalPaymentDate else { return false }
                let end = clothing.finalPaymentEndDate ?? start
                return calendar.startOfDay(for: end) >= today
            }
            .sorted { lhs, rhs in
                (lhs.finalPaymentDate ?? .distantFuture) < (rhs.finalPaymentDate ?? .distantFuture)
            }

        if let first = activeOrUpcoming.first {
            return first
        }

        return datedPlans.sorted { lhs, rhs in
            (lhs.finalPaymentDate ?? .distantPast) > (rhs.finalPaymentDate ?? .distantPast)
        }.first
    }

    private func clothing(for clothingID: UUID) -> Clothing? {
        depositPlans.first { $0.id == clothingID }
    }

    /// 未读记录数量
    private var unreadCount: Int {
        triggeredRecords.filter { !$0.isRead }.count
    }

    /// 已读记录数量
    private var readCount: Int {
        triggeredRecords.filter { $0.isRead }.count
    }

    private var pendingDisplayRecords: [DepositNotificationRecord] {
        Array(pendingRecords.prefix(NotificationManager.Config.pendingSectionLimit))
    }

    private var capturedPendingCount: Int {
        pendingRecords.filter { $0.source == "captured" || $0.source == "local" }.count
    }

    private var scheduledPendingCount: Int {
        pendingRecords.filter { $0.source == "scheduled" }.count
    }

    private var testTargetClothing: Clothing? {
        depositPlans
            .sorted { lhs, rhs in
                let lhsDate = lhs.finalPaymentDate ?? .distantFuture
                let rhsDate = rhs.finalPaymentDate ?? .distantFuture
                return lhsDate < rhsDate
            }
            .first
    }

    private var groupedTriggeredRecords: [(record: DepositNotificationRecord, records: [DepositNotificationRecord])] {
        let grouped = Dictionary(grouping: triggeredRecords) { $0.clothingID }
        return grouped.values
            .compactMap { records in
                guard let leadRecord = records.max(by: { ($0.actualDate ?? $0.scheduledDate) < ($1.actualDate ?? $1.scheduledDate) }) else {
                    return nil
                }
                let sortedRecords = records.sorted { ($0.actualDate ?? $0.scheduledDate) > ($1.actualDate ?? $1.scheduledDate) }
                return (leadRecord, sortedRecords)
            }
            .sorted { ($0.record.actualDate ?? $0.record.scheduledDate) > ($1.record.actualDate ?? $1.record.scheduledDate) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 第一排：设置情况概览（默认折叠时显示）
                settingsSummarySection
                    .padding(.horizontal, 16)

                timelineOverviewSection
                    .padding(.horizontal, 16)

                historySection
                    .padding(.horizontal, 16)

                pendingSection
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .background(LiquidBackground())
        .navigationTitle("尾款提醒")
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
            Task {
                logger.info("view_appear deposit_plan_count=\(depositPlans.count)")
                await NotificationManager.shared.reconcileDeliveredNotifications(modelContext: modelContext)
                await NotificationManager.shared.refreshDepositNotifications(
                    clothings: depositPlans,
                    modelContext: modelContext,
                    force: false,
                    reason: "notification-view-appear"
                )
                await refreshDebugSnapshot()
            }
            // 进入页面时限制历史记录数量
            NotificationManager.shared.enforceHistoryLimit(modelContext: modelContext)
            NotificationManager.shared.updateApplicationBadge(modelContext: modelContext)
        }
        .alert("需要通知权限", isPresented: $showPermissionAlert) {
            Button("去设置", role: .none) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("请在设置中允许 App 发送通知，以便接收尾款提醒。")
        }
        .alert("清除已读通知", isPresented: $showClearReadConfirmation) {
            Button("清除", role: .destructive) {
                NotificationManager.shared.clearAllReadNotifications(modelContext: modelContext)
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("确定要清除所有已读的通知记录吗？此操作不可撤销。")
        }
        .alert(
            "测试通知",
            isPresented: Binding(
                get: { testAlertMessage != nil },
                set: { newValue in
                    if !newValue {
                        testAlertMessage = nil
                    }
                }
            )
        ) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(testAlertMessage ?? "")
        }
    }

    // MARK: - 设置情况概览（默认折叠）

    private var settingsSummarySection: some View {
        ThemeSkinSectionCardContainer(cornerRadius: 12, showsDecoration: false) {
            VStack(spacing: 8) {
                // 标题栏：总开关 + 小齿轮
                HStack {
                    Toggle("开启尾款提醒", isOn: $isEnabled)
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
        }
    }

    // MARK: - 尾款时间线概览

    private var timelineOverviewSection: some View {
        ThemeSkinSectionCardContainer(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(palette.accent.opacity(0.14))
                            .frame(width: 36, height: 36)

                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("尾款时间线")
                            .font(.headline)
                            .foregroundStyle(palette.primaryText)

                        Text(reminderRuleSummary)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(2)
                    }

                    Spacer()

                    Text(isEnabled ? "提醒已开启" : "提醒未开启")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background((isEnabled ? palette.accent : palette.secondaryText).opacity(0.14))
                        .foregroundStyle(isEnabled ? palette.accent : palette.secondaryText)
                        .clipShape(Capsule())
                }

                Divider().opacity(0.45)

                if let record = nextPendingRecord {
                    overviewFocusRow(
                        icon: record.source == "scheduled" ? "bell.badge.fill" : "tray.full.fill",
                        title: "下次提醒",
                        primary: DepositReminderDisplayFormatter.clothingName(for: record, clothing: clothing(for: record.clothingID)),
                        secondary: DepositReminderDisplayFormatter.pendingReminderText(for: record),
                        footnote: DepositReminderDisplayFormatter.paymentWindowText(clothing: clothing(for: record.clothingID), fallbackDate: record.scheduledDate),
                        amount: DepositReminderDisplayFormatter.amountText(for: clothing(for: record.clothingID)),
                        badge: DepositReminderDisplayFormatter.sourceText(for: record)
                    )
                } else if let clothing = nearestPaymentClothing {
                    overviewFocusRow(
                        icon: "heart.text.square.fill",
                        title: "最近尾款",
                        primary: clothing.name,
                        secondary: DepositReminderDisplayFormatter.paymentStatusText(clothing: clothing, fallbackDate: clothing.finalPaymentDate),
                        footnote: DepositReminderDisplayFormatter.paymentWindowText(clothing: clothing, fallbackDate: clothing.finalPaymentDate),
                        amount: DepositReminderDisplayFormatter.amountText(for: clothing),
                        badge: isEnabled ? "暂无待提醒" : "未开启"
                    )
                } else {
                    overviewFocusRow(
                        icon: "sparkles",
                        title: "暂无尾款计划",
                        primary: "还没有需要提醒的心愿尾款",
                        secondary: "创建心愿尾款并填写尾款日后，这里会显示下一次提醒。",
                        footnote: nil,
                        amount: nil,
                        badge: nil
                    )
                }

                HStack(spacing: 8) {
                    overviewMetric(title: "待付总额", value: DepositReminderDisplayFormatter.amountText(totalPendingBalance), systemImage: "yensign.circle.fill")
                    overviewMetric(title: "待提醒", value: "\(pendingRecords.count) 条", systemImage: "bell.fill")
                    overviewMetric(title: "未读", value: "\(unreadCount) 条", systemImage: "envelope.badge.fill")
                }
            }
            .padding(16)
        }
    }

    private var reminderRuleSummary: String {
        guard isEnabled else {
            return "开启后会按尾款日自动排队提醒，站内也会保留待提醒记录。"
        }

        let daysText = selectedDays.sorted().map(dayText(for:)).joined(separator: "、")
        return "\(daysText) · 每天 \(formatTime(notificationTime)) 提醒"
    }

    @ViewBuilder
    private func overviewFocusRow(
        icon: String,
        title: String,
        primary: String,
        secondary: String,
        footnote: String?,
        amount: String?,
        badge: String?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 30, height: 30)
                .background(palette.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)

                Text(primary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(2)

                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(palette.primaryText.opacity(0.82))
                    .lineLimit(2)

                if let footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                if let amount {
                    Text(amount)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.accent)
                }

                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(palette.accent.opacity(0.12))
                        .foregroundStyle(palette.accent)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func overviewMetric(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accent)

            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardAccent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    ForEach(NotificationManager.Config.supportedReminderDays, id: \.self) { day in
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

            #if DEBUG
            VStack(alignment: .leading, spacing: 8) {
                Text("测试工具")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryText)

                Button {
                    sendTestNotification()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                        Text("发送 5 秒测试通知")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(testTargetClothing == nil ? palette.secondaryText.opacity(0.35) : palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(testTargetClothing == nil)

                Text(testTargetClothing.map { "将使用「\($0.name)」作为测试目标。正式通知发送时间可直接用上方时间选择器修改。" } ?? "请先创建至少一条心愿尾款记录，再发送测试通知。")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)
            }

            diagnosticsPanel
            #endif
        }
        .padding(.top, 6)
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("通知诊断")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryText)

                Spacer()

                Button("刷新") {
                    Task {
                        await refreshDebugSnapshot()
                    }
                }
                .font(.system(size: 11, weight: .semibold))

                Button("重新同步") {
                    Task {
                        await NotificationManager.shared.refreshDepositNotifications(
                            clothings: depositPlans,
                            modelContext: modelContext,
                            force: true,
                            reason: "manual"
                        )
                        await refreshDebugSnapshot()
                    }
                }
                .font(.system(size: 11, weight: .semibold))
            }

            if let snapshot = debugSnapshot {
                VStack(alignment: .leading, spacing: 4) {
                    Text("权限状态：\(authorizationText(snapshot.authorizationStatus))")
                    Text("系统待发送：总 \(snapshot.pendingCount) / 补款 \(snapshot.depositPendingCount)")
                    Text("系统已送达：总 \(snapshot.deliveredCount) / 补款 \(snapshot.depositDeliveredCount)")
                    Text("待提醒记录：\(snapshot.pendingRecordCount)（系统 \(snapshot.depositPendingCount) / 站内 \(snapshot.capturedRecordCount)，上限 \(snapshot.scheduledSystemLimit)）")
                    Text("App Icon 红点：\(snapshot.applicationBadgeCount)")
                    Text("App 内未读：\(unreadCount)")
                    Text("设备模式：\(snapshot.isMemoryConstrained ? "小内存保护" : "标准")")
                }
                .font(.system(size: 11))
                .foregroundStyle(palette.secondaryText)
            } else {
                Text("正在读取系统通知状态…")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)
            }
        }
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

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "待提醒",
                summary: "系统 \(scheduledPendingCount) / 站内 \(capturedPendingCount)",
                isExpanded: isPendingExpanded
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isPendingExpanded.toggle()
                }
            }

            if isPendingExpanded {
                if pendingDisplayRecords.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 32))
                            .foregroundStyle(palette.secondaryText.opacity(0.5))
                        Text("暂无待提醒记录")
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 8) {
                        ForEach(pendingDisplayRecords) { record in
                            PendingNotificationRecordRow(record: record, clothing: clothing(for: record.clothingID)) {
                                openClothingDetail(record.clothingID)
                            }
                        }
                    }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "已发送提醒",
                summary: unreadCount > 0 ? "\(unreadCount) 未读 / \(triggeredRecords.count) 条" : "\(triggeredRecords.count) 条",
                isExpanded: isHistoryExpanded
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isHistoryExpanded.toggle()
                }
            }

            if isHistoryExpanded {
                if unreadCount > 0 || readCount > 0 {
                    HStack(spacing: 12) {
                        if unreadCount > 0 {
                            largeActionButton(
                                title: "一键已读",
                                systemImage: "checkmark.circle.fill",
                                foreground: .white,
                                background: palette.accent
                            ) {
                                NotificationManager.shared.markAllTriggeredAsRead(modelContext: modelContext)
                            }
                        }

                        if readCount > 0 {
                            largeActionButton(
                                title: "一键清除",
                                systemImage: "trash.fill",
                                foreground: palette.secondaryText,
                                background: palette.secondaryText.opacity(0.16)
                            ) {
                                showClearReadConfirmation = true
                            }
                        }
                    }
                }

                if triggeredRecords.isEmpty {
                    emptyStateView
                } else {
                    ForEach(groupedTriggeredRecords, id: \.record.clothingID) { groupedRecord in
                        TriggeredNotificationCard(
                            clothingName: groupedRecord.record.clothingName,
                            clothingID: groupedRecord.record.clothingID,
                            clothing: clothing(for: groupedRecord.record.clothingID),
                            records: groupedRecord.records,
                            onOpenDetail: {
                                openClothingDetail(groupedRecord.record.clothingID)
                            }
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

            Text("当尾款提醒被系统送达或在站内记录后，将显示在这里")
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
            guard selectedDays.count > 1 else { return }
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
        NotificationManager.shared.daysBeforeList = Array(selectedDays)
        selectedDays = Set(NotificationManager.shared.daysBeforeList)
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

    private func openClothingDetail(_ clothingID: UUID) {
        TabNavigationManager.shared.navigateToDepositNotificationClothing(clothingID)
        dismiss()
    }

    @ViewBuilder
    private func largeActionButton(
        title: String,
        systemImage: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sectionHeader(
        title: String,
        summary: String,
        isExpanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.secondaryText)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleSettingsChange(enabled: Bool) {
        settingsSyncTask?.cancel()
        let selectedDaysText = selectedDays.sorted().map(String.init).joined(separator: ",")
        logger.info("settings_change_enqueued enabled=\(enabled) selected_days=\(selectedDaysText, privacy: .public)")
        settingsSyncTask = Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            logger.info("settings_change_apply enabled=\(enabled) deposit_plan_count=\(depositPlans.count)")

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

            await NotificationManager.shared.refreshDepositNotifications(
                clothings: depositPlans,
                modelContext: modelContext,
                force: false,
                reason: "settings-change"
            )
            await refreshDebugSnapshot()
        }
    }

    private func sendTestNotification() {
        guard let clothing = testTargetClothing else {
            testAlertMessage = "请先创建一条用于测试的心愿尾款记录。建议新建一条“通知测试裙”，避免影响正式数据。"
            return
        }

        Task {
            logger.info("send_test_notification target=\(clothing.name, privacy: .public)")
            let status = await NotificationManager.shared.checkAuthorizationStatus()
            if status == .notDetermined {
                let granted = try? await NotificationManager.shared.requestAuthorization()
                if granted != true {
                    await MainActor.run {
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

            do {
                try await NotificationManager.shared.scheduleTestNotification(for: clothing)
                await refreshDebugSnapshot()
                await MainActor.run {
                    testAlertMessage = "已为「\(clothing.name)」安排 5 秒测试通知。请切到桌面或锁屏等待弹出，然后点击通知验证是否直达详情页。"
                }
            } catch {
                await MainActor.run {
                    testAlertMessage = "测试通知发送失败：\(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func refreshDebugSnapshot() async {
        debugSnapshot = await NotificationManager.shared.debugSnapshot()
    }

    private func authorizationText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "未决定"
        case .denied: return "已拒绝"
        case .authorized: return "已允许"
        case .provisional: return "临时允许"
        case .ephemeral: return "临时会话"
        @unknown default: return "未知"
        }
    }
}

// MARK: - 已发送的提醒卡片

struct TriggeredNotificationCard: View {
    let clothingName: String
    let clothingID: UUID
    let clothing: Clothing?
    let records: [DepositNotificationRecord]
    let onOpenDetail: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var palette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var displayName: String {
        clothing?.name ?? clothingName
    }

    var body: some View {
        ThemeSkinSectionCardContainer(cornerRadius: 14, showsDecoration: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Button(action: onOpenDetail) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.primaryText)
                                .multilineTextAlignment(.leading)

                            Text(DepositReminderDisplayFormatter.paymentWindowText(clothing: clothing, fallbackDate: records.first?.scheduledDate))
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        if let amount = DepositReminderDisplayFormatter.amountText(for: clothing) {
                            Text(amount)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(palette.accent)
                        }

                        Text("\(records.count) 次提醒")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(palette.accent.opacity(0.12))
                            .foregroundStyle(palette.accent)
                            .clipShape(Capsule())
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(records) { record in
                        NotificationRecordRow(record: record, clothing: clothing, onOpenDetail: onOpenDetail)
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: - 单条通知记录行

struct NotificationRecordRow: View {
    let record: DepositNotificationRecord
    let clothing: Clothing?
    let onOpenDetail: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    private var palette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    var body: some View {
        ReminderSwipeRow(
            onOpen: {
                if !record.isRead {
                    record.markAsRead()
                    try? modelContext.save()
                    NotificationManager.shared.updateApplicationBadge(modelContext: modelContext)
                }
                onOpenDetail()
            },
            onDelete: {
                NotificationManager.shared.deleteRecord(record, modelContext: modelContext)
            }
        ) {
            ThemeSkinSectionCardContainer(cornerRadius: 10, showsDecoration: false) {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(record.isRead ? palette.secondaryText.opacity(0.16) : palette.cardAccent)
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(DepositReminderDisplayFormatter.triggeredReminderText(for: record))
                            .font(.subheadline.weight(record.isRead ? .regular : .semibold))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(2)

                        Text(DepositReminderDisplayFormatter.paymentStatusText(clothing: clothing, fallbackDate: record.scheduledDate))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(2)

                        HStack(spacing: 5) {
                            if record.source == "apple" {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 8))
                            }

                            Text(DepositReminderDisplayFormatter.originalPlanText(for: record))
                                .lineLimit(1)
                        }
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText.opacity(0.82))
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(DepositReminderDisplayFormatter.dayText(for: record.daysBefore))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background((record.isRead ? palette.secondaryText : palette.accent).opacity(0.12))
                            .foregroundStyle(record.isRead ? palette.secondaryText : palette.accent)
                            .clipShape(Capsule())

                        Text(record.isRead ? "已读" : "未读")
                            .font(.caption2)
                            .foregroundStyle(record.isRead ? palette.secondaryText : palette.accent)
                    }
                }
                .padding(10)
            }
        }
    }
}

struct PendingNotificationRecordRow: View {
    let record: DepositNotificationRecord
    let clothing: Clothing?
    let onOpenDetail: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var palette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var isCapturedOnly: Bool {
        record.source == "captured" || record.source == "local"
    }

    var body: some View {
        Button(action: onOpenDetail) {
            ThemeSkinSectionCardContainer(cornerRadius: 12, showsDecoration: false) {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(isCapturedOnly ? palette.secondaryText.opacity(0.45) : palette.cardAccent)
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(DepositReminderDisplayFormatter.clothingName(for: record, clothing: clothing))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.primaryText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        Text(DepositReminderDisplayFormatter.paymentWindowText(clothing: clothing, fallbackDate: record.scheduledDate))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(2)

                        Text(DepositReminderDisplayFormatter.pendingReminderText(for: record))
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText.opacity(0.86))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 6) {
                        if let amount = DepositReminderDisplayFormatter.amountText(for: clothing) {
                            Text(amount)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(palette.accent)
                                .lineLimit(1)
                        }

                        Text(DepositReminderDisplayFormatter.sourceText(for: record))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background((isCapturedOnly ? palette.secondaryText : palette.accent).opacity(0.14))
                            .foregroundStyle(isCapturedOnly ? palette.secondaryText : palette.accent)
                            .clipShape(Capsule())

                        Text(DepositReminderDisplayFormatter.paymentStatusText(clothing: clothing, fallbackDate: record.scheduledDate))
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .padding(10)
            }
        }
        .buttonStyle(.plain)
    }
}

private enum DepositReminderDisplayFormatter {
    static func clothingName(for record: DepositNotificationRecord, clothing: Clothing?) -> String {
        let name = clothing?.name ?? record.clothingName
        return name.isEmpty ? "这件心愿尾款" : name
    }

    static func amountText(for clothing: Clothing?) -> String? {
        guard let clothing, clothing.totalBalance > 0 else { return nil }
        return "待付 \(amountText(clothing.totalBalance))"
    }

    static func amountText(_ amount: Decimal) -> String {
        "¥\(NSDecimalNumber(decimal: amount).stringValue)"
    }

    static func paymentWindowText(clothing: Clothing?, fallbackDate: Date?) -> String {
        guard let start = clothing?.finalPaymentDate else {
            if let fallbackDate {
                return "提醒记录：\(dateText(fallbackDate))"
            }
            return "尾款时间待确认"
        }

        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let end = clothing?.finalPaymentEndDate ?? start
        let endDay = calendar.startOfDay(for: end)

        if endDay > startDay {
            return "支付期 \(dateText(start)) - \(dateText(end))"
        }

        return "\(dateText(start)) 开始付尾款"
    }

    static func paymentStatusText(clothing: Clothing?, fallbackDate: Date?) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let start = clothing?.finalPaymentDate else {
            if let fallbackDate {
                return "按 \(dateText(fallbackDate)) 的提醒记录显示"
            }
            return "尾款日待确认"
        }

        let startDay = calendar.startOfDay(for: start)
        let end = clothing?.finalPaymentEndDate ?? start
        let endDay = calendar.startOfDay(for: end)

        if today < startDay {
            let days = calendar.dateComponents([.day], from: today, to: startDay).day ?? 0
            return days == 0 ? "今天进入支付期" : "还有 \(days) 天进入支付期"
        }

        if today <= endDay {
            return "正在支付期内"
        }

        return "支付期已过，请确认处理"
    }

    static func pendingReminderText(for record: DepositNotificationRecord) -> String {
        "将于 \(dateTimeText(record.scheduledDate)) \(dayText(for: record.daysBefore))"
    }

    static func triggeredReminderText(for record: DepositNotificationRecord) -> String {
        guard let actualDate = record.actualDate else {
            return "已发送提醒"
        }
        return "已在 \(dateTimeText(actualDate)) 提醒"
    }

    static func originalPlanText(for record: DepositNotificationRecord) -> String {
        "原计划 \(dateTimeText(record.scheduledDate))"
    }

    static func sourceText(for record: DepositNotificationRecord) -> String {
        switch record.source {
        case "apple", "scheduled":
            return "系统通知"
        case "captured", "local":
            return "仅站内"
        default:
            return "站内记录"
        }
    }

    static func dayText(for day: Int) -> String {
        switch day {
        case 0: return "当天提醒"
        case 1: return "提前 1 天"
        case 3: return "提前 3 天"
        case 7: return "提前 7 天"
        case 15: return "提前 15 天"
        case 30: return "提前 30 天"
        default: return "提前 \(day) 天"
        }
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        if Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date()) {
            formatter.dateFormat = "M月d日"
        } else {
            formatter.dateFormat = "yyyy年M月d日"
        }
        return formatter.string(from: date)
    }

    private static func dateTimeText(_ date: Date) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_Hans_CN")
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: date)

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天 \(time)"
        }
        if calendar.isDateInTomorrow(date) {
            return "明天 \(time)"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 \(time)"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_Hans_CN")
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            dateFormatter.dateFormat = "M月d日 HH:mm"
        } else {
            dateFormatter.dateFormat = "yyyy年M月d日 HH:mm"
        }
        return dateFormatter.string(from: date)
    }
}

private struct ReminderSwipeRow<Content: View>: View {
    let onOpen: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var settledOffset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    private let deleteWidth: CGFloat = 92

    private var currentOffset: CGFloat {
        max(-deleteWidth, min(0, settledOffset + dragOffset))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    settledOffset = 0
                }
                onDelete()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("删除")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(width: deleteWidth)
                .frame(maxHeight: .infinity)
                .background(Color.red.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            content()
                .offset(x: currentOffset)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .updating($dragOffset) { value, state, _ in
                            let proposed = settledOffset + value.translation.width
                            state = max(-deleteWidth, min(0, proposed)) - settledOffset
                        }
                        .onEnded { value in
                            let proposed = settledOffset + value.translation.width
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                                settledOffset = proposed < (-deleteWidth * 0.45) ? -deleteWidth : 0
                            }
                        }
                )
                .onTapGesture {
                    if settledOffset != 0 {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                            settledOffset = 0
                        }
                    } else {
                        onOpen()
                    }
                }
        }
    }
}

// MARK: - GlobalSearchView 中的 FlowLayout 已实现
