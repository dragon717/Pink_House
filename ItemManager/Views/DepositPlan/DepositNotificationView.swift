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
    @State private var isHistoryExpanded = false
    @State private var isPendingExpanded = false

    @Query(filter: #Predicate<Clothing> { $0.isDepositPlan == true && $0.deletedAt == nil }) private var depositPlans: [Clothing]
    @Query(filter: #Predicate<DepositNotificationRecord> { $0.isTriggered == false }, sort: \DepositNotificationRecord.scheduledDate, order: .forward) private var pendingRecords: [DepositNotificationRecord]
    @Query(filter: #Predicate<DepositNotificationRecord> { $0.isTriggered == true }, sort: \DepositNotificationRecord.actualDate, order: .reverse) private var triggeredRecords: [DepositNotificationRecord]

    private var palette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
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

    private var testTargetClothing: Clothing? {
        depositPlans
            .sorted { lhs, rhs in
                let lhsDate = lhs.finalPaymentDate ?? .distantFuture
                let rhsDate = rhs.finalPaymentDate ?? .distantFuture
                return lhsDate < rhsDate
            }
            .first
    }

    var body: some View {
        List {
            settingsSummarySection
                .depositReminderListRow(top: 16)

            historyHeaderRow
                .depositReminderListRow(top: 10, bottom: 2)

            if isHistoryExpanded {
                if triggeredRecords.isEmpty {
                    emptyStateView
                        .depositReminderListRow(top: 2)
                } else {
                    ForEach(triggeredRecords) { record in
                        NotificationRecordRow(record: record, clothing: clothing(for: record.clothingID)) {
                            openClothingDetail(record.clothingID)
                        }
                        .depositReminderListRow(top: 4, bottom: 4)
                    }
                }
            }

            pendingHeaderRow
                .depositReminderListRow(top: 10, bottom: 2)

            if isPendingExpanded {
                if pendingDisplayRecords.isEmpty {
                    pendingEmptyStateView
                        .depositReminderListRow(top: 2)
                } else {
                    ForEach(pendingDisplayRecords) { record in
                        PendingNotificationRecordRow(record: record, clothing: clothing(for: record.clothingID)) {
                            openClothingDetail(record.clothingID)
                        }
                        .depositReminderListRow(top: 4, bottom: 4)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(LiquidBackground(themeSkinWallpaperContext: .depositPlan))
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Toggle("开启尾款提醒", isOn: $isEnabled)
                        .font(.subheadline.weight(.semibold))
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
                            .frame(width: 34, height: 34)
                            .background(palette.secondaryText.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if isExpanded {
                    expandedSettingsPanel
                } else {
                    collapsedSettingsSummary
                }
            }
            .padding(12)
        }
    }

    private var reminderRuleSummary: String {
        guard isEnabled else {
            return "开启后按尾款日提醒".appLocalized
        }

        let daysText = selectedDays.sorted().map(dayText(for:)).joined(separator: "、")
        return "%@ · 每天 %@ 提醒".appLocalized(daysText, formatTime(notificationTime))
    }

    // MARK: - 折叠时显示的设置摘要

    private var collapsedSettingsSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: isEnabled ? "clock.badge.checkmark" : "bell.slash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isEnabled ? palette.accent : palette.secondaryText)

            Text(reminderRuleSummary)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
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
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)

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
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)

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
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)

                Button {
                    sendTestNotification()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                        Text("发送 5 秒测试通知")
                            .themeSkinLegibleText(level: .chip, slot: .primaryButton)
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

                Text(testTargetDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
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
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)

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
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            } else {
                Text("正在读取系统通知状态…")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
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
                .themeSkinLegibleText(level: .chip, slot: .filterChip)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? palette.accent : palette.accent.opacity(0.15))
                .foregroundStyle(isSelected ? .white : palette.accent)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 提醒记录区

    private var historyHeaderRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "已发送提醒",
                summary: historySummaryText,
                isExpanded: isHistoryExpanded
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isHistoryExpanded.toggle()
                }
            }

            if isHistoryExpanded && (unreadCount > 0 || readCount > 0) {
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
        }
    }

    private var pendingHeaderRow: some View {
        sectionHeader(
            title: "待提醒",
            summary: "%d 条".appLocalized(pendingRecords.count),
            isExpanded: isPendingExpanded
        ) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isPendingExpanded.toggle()
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
                .themeSkinLegibleText(level: .inline, slot: .emptyState)

            Text("当尾款提醒被系统送达或在站内记录后，将显示在这里")
                .font(.caption)
                .foregroundStyle(palette.secondaryText.opacity(0.7))
                .themeSkinLegibleText(level: .inline, slot: .emptyState)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var pendingEmptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 32))
                .foregroundStyle(palette.secondaryText.opacity(0.5))
            Text("暂无待提醒记录")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .themeSkinLegibleText(level: .inline, slot: .emptyState)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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
        case 0: return "当天".appLocalized
        case 1: return "提前1天".appLocalized
        case 3, 7, 15, 30: return "%d天".appLocalized(day)
        default: return "提前%d天".appLocalized(day)
        }
    }

    private var historySummaryText: String {
        if unreadCount > 0 {
            return "%d 未读 / %d 条".appLocalized(unreadCount, triggeredRecords.count)
        }
        return "%d 条".appLocalized(triggeredRecords.count)
    }

    private var testTargetDescription: String {
        if let clothing = testTargetClothing {
            return "将使用「%@」作为测试目标。正式通知发送时间可直接用上方时间选择器修改。".appLocalized(clothing.name)
        }
        return "请先创建至少一条心愿尾款记录，再发送测试通知。".appLocalized
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
                Text(title.appLocalized)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foreground)
            .themeSkinLegibleText(level: .chip, slot: .primaryButton)
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

                Text(title.appLocalized)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)

                Spacer()

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
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
            testAlertMessage = "请先创建一条用于测试的心愿尾款记录。建议新建一条“通知测试裙”，避免影响正式数据。".appLocalized
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
                    testAlertMessage = "已为「%@」安排 5 秒测试通知。请切到桌面或锁屏等待弹出，然后点击通知验证是否直达详情页。".appLocalized(clothing.name)
                }
            } catch {
                await MainActor.run {
                    testAlertMessage = "测试通知发送失败：%@".appLocalized(error.localizedDescription)
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
        case .notDetermined: return "未决定".appLocalized
        case .denied: return "已拒绝".appLocalized
        case .authorized: return "已允许".appLocalized
        case .provisional: return "临时允许".appLocalized
        case .ephemeral: return "临时会话".appLocalized
        @unknown default: return "未知".appLocalized
        }
    }
}

// MARK: - 单条已发送提醒行

private struct DepositReminderThumbnailView: View {
    let clothing: Clothing?
    @State private var thumbnailImage: UIImage?

    private let sideLength: CGFloat = 48
    private var imagePath: String? {
        clothing?.imagePaths.first
    }

    var body: some View {
        Group {
            if let thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                CutePlaceholderView(iconSize: 18)
            }
        }
        .frame(width: sideLength, height: sideLength)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: imagePath) {
            await loadThumbnail()
        }
    }

    @MainActor
    private func loadThumbnail() async {
        guard let imagePath else {
            thumbnailImage = nil
            return
        }

        let targetSize = CGSize(width: sideLength, height: sideLength)
        if let cached = ImageManager.shared.cachedImage(fileName: imagePath, targetSize: targetSize) {
            thumbnailImage = cached
            return
        }

        thumbnailImage = nil
        try? await Task.sleep(nanoseconds: 50_000_000)
        guard !Task.isCancelled else { return }
        thumbnailImage = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: targetSize)
    }
}

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

    private var displayName: String {
        DepositReminderDisplayFormatter.clothingName(for: record, clothing: clothing)
    }

    var body: some View {
        Button(action: openRecord) {
            ThemeSkinSectionCardContainer(cornerRadius: 12, showsDecoration: false) {
                HStack(alignment: .center, spacing: 10) {
                    DepositReminderThumbnailView(clothing: clothing)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(record.isRead ? palette.secondaryText.opacity(0.18) : palette.accent)
                                .frame(width: 7, height: 7)

                            Text(displayName)
                                .font(.subheadline.weight(record.isRead ? .regular : .semibold))
                                .foregroundStyle(palette.primaryText)
                                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                        }

                        Text(DepositReminderDisplayFormatter.triggeredTimeText(for: record))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text(DepositReminderDisplayFormatter.dayText(for: record.daysBefore))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background((record.isRead ? palette.secondaryText : palette.accent).opacity(0.12))
                        .foregroundStyle(record.isRead ? palette.secondaryText : palette.accent)
                        .themeSkinLegibleText(level: .chip, slot: .filterChip)
                        .clipShape(Capsule())
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                NotificationManager.shared.deleteRecord(record, modelContext: modelContext)
            } label: {
                Label("删除", systemImage: "trash")
            }

            if !record.isRead {
                Button {
                    markRecordAsRead()
                } label: {
                    Label("标为已读", systemImage: "checkmark.circle")
                }
                .tint(.blue)
            }
        }
    }

    private func openRecord() {
        if !record.isRead {
            markRecordAsRead()
        }
        onOpenDetail()
    }

    private func markRecordAsRead() {
        guard !record.isRead else { return }
        record.markAsRead()
        try? modelContext.save()
        NotificationManager.shared.updateApplicationBadge(modelContext: modelContext)
    }
}

// MARK: - 单条待提醒行

struct PendingNotificationRecordRow: View {
    let record: DepositNotificationRecord
    let clothing: Clothing?
    let onOpenDetail: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    private var palette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var displayName: String {
        DepositReminderDisplayFormatter.clothingName(for: record, clothing: clothing)
    }

    var body: some View {
        Button(action: onOpenDetail) {
            ThemeSkinSectionCardContainer(cornerRadius: 12, showsDecoration: false) {
                HStack(alignment: .center, spacing: 10) {
                    DepositReminderThumbnailView(clothing: clothing)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.primaryText)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        Text(DepositReminderDisplayFormatter.pendingTimeText(for: record))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text(DepositReminderDisplayFormatter.dayText(for: record.daysBefore))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(palette.accent.opacity(0.12))
                        .foregroundStyle(palette.accent)
                        .themeSkinLegibleText(level: .chip, slot: .filterChip)
                        .clipShape(Capsule())
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                NotificationManager.shared.deleteRecord(record, modelContext: modelContext)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

private enum DepositReminderDisplayFormatter {
    static func clothingName(for record: DepositNotificationRecord, clothing: Clothing?) -> String {
        let name = clothing?.name ?? record.clothingName
        return name.isEmpty ? "这件心愿尾款".appLocalized : name
    }

    static func pendingTimeText(for record: DepositNotificationRecord) -> String {
        "%@ · %@".appLocalized(dateTimeText(record.scheduledDate), dayText(for: record.daysBefore))
    }

    static func triggeredTimeText(for record: DepositNotificationRecord) -> String {
        "%@ · %@".appLocalized(dateTimeText(record.actualDate ?? record.scheduledDate), dayText(for: record.daysBefore))
    }

    static func dayText(for day: Int) -> String {
        switch day {
        case 0: return "当天提醒".appLocalized
        default: return "提前 %d 天".appLocalized(day)
        }
    }

    private static func dateTimeText(_ date: Date) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = LanguageManager.shared.locale
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: date)

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "\("今天".appLocalized) \(time)"
        }
        if calendar.isDateInTomorrow(date) {
            return "\("明天".appLocalized) \(time)"
        }
        if calendar.isDateInYesterday(date) {
            return "\("昨天".appLocalized) \(time)"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = LanguageManager.shared.locale
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            dateFormatter.setLocalizedDateFormatFromTemplate("MdHm")
        } else {
            dateFormatter.setLocalizedDateFormatFromTemplate("yMdHm")
        }
        return dateFormatter.string(from: date)
    }
}

private extension View {
    func depositReminderListRow(top: CGFloat = 6, bottom: CGFloat = 6) -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
    }
}

// MARK: - GlobalSearchView 中的 FlowLayout 已实现
