import SwiftUI
import SwiftData

// MARK: - 公告管理视图 (管理员专用)
// 用于创建、编辑、删除公告

struct NoticeAdminView: View {
    @StateObject private var service = NoticeService.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // 表单状态
    @State private var title = ""
    @State private var summary = ""
    @State private var content = ""
    @State private var priority = 0
    @State private var status: Notice.Status = .draft
    @State private var channel: Notice.Channel = .inbox
    @State private var severity: Notice.Severity = .info
    @State private var isPinned = false
    @State private var requiresAck = false
    @State private var isSilent = false
    @State private var audience = "all"
    @State private var minAppVersion = ""
    @State private var maxAppVersion = ""
    @State private var actionType: Notice.ActionType = .none
    @State private var actionTarget = ""
    @State private var actionLabel = ""
    @State private var publishAt = Date()
    @State private var startAt = Date()
    @State private var endAt = Date()
    @State private var hasPublishAt = false
    @State private var hasStartAt = false
    @State private var hasEndAt = false
    @State private var mediaType: Notice.MediaType = .none
    @State private var selectedImageName: String?  // 内置图片名称
    @State private var selectedImageData: Data?

    // 编辑模式
    @State private var editingNotice: Notice?
    @State private var showAdvancedConfig = false

    // 提示
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var pendingDeleteNotice: Notice?

    // 预览
    @State private var showPreview = false
    @State private var previewNotice: Notice?

    // 内置图片选择器
    @State private var showBuiltinImagePicker = false

    // 管理员权限检查
    @State private var isAdmin = false
    @State private var isCheckingAdmin = true

    var body: some View {
        NavigationStack {
            Group {
                if isCheckingAdmin {
                    checkingView
                } else if isAdmin {
                    adminForm
                } else {
                    noPermissionView
                }
            }
            .navigationTitle("公告管理".appLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成".appLocalized) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                service.setup(with: modelContext)
                checkAdminPermission()
            }
            .alert("提示".appLocalized, isPresented: $showAlert) {
                Button("确定".appLocalized, role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .alert(
                "确认删除公告".appLocalized,
                isPresented: pendingDeleteBinding,
                presenting: pendingDeleteNotice
            ) { notice in
                Button("取消".appLocalized, role: .cancel) {
                    pendingDeleteNotice = nil
                }
                Button("确认删除".appLocalized, role: .destructive) {
                    performDeleteNotice(notice)
                }
            } message: { notice in
                Text("“%@” 会被标记为删除并从“现有公告”列表中隐藏。".appLocalized(notice.title))
            }
            .overlay {
                if showPreview, let notice = previewNotice {
                    NoticePreviewOverlay(
                        isPresented: $showPreview,
                        notice: notice
                    )
                }
            }
            .sheet(isPresented: $showBuiltinImagePicker) {
                BuiltinImagePicker(
                    selectedImageName: $selectedImageName,
                    selectedImageData: $selectedImageData
                )
            }
        }
    }

    // MARK: - 检查权限中视图
    private var checkingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("检查管理员权限...".appLocalized)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 无权限视图
    private var noPermissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("需要管理员权限".appLocalized)
                .font(.title2)
                .fontWeight(.semibold)

            Text("只有管理员可以发布公告。\n如果您是管理员，请确保已登录 iCloud 账户。".appLocalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("重新检查".appLocalized) {
                checkAdminPermission()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding()
    }

    // MARK: - 检查管理员权限
    private func checkAdminPermission() {
        isCheckingAdmin = true
        Task {
            let hasPermission = await service.isAdmin()
            await MainActor.run {
                isAdmin = hasPermission
                isCheckingAdmin = false
            }
        }
    }

    // MARK: - 表单内容
    private var adminForm: some View {
        Form {
            quickModalSection
            advancedConfigToggleSection
            if showAdvancedConfig {
                advancedSummarySection
                deliverySection
                scheduleSection
                actionConfigSection
                prioritySection
                mediaSection
                actionSection
            }
            existingNoticesSection
        }
    }

    private var quickModalSection: some View {
        Section((showAdvancedConfig ? "基础内容" : "快捷发弹窗公告").appLocalized) {
            TextField("标题".appLocalized, text: $title)

            TextEditor(text: $content)
                .frame(minHeight: 100)
                .overlay(
                    placeholderOverlay,
                    alignment: .topLeading
                )

            quickImagePickerRow

            if hasSelectedImage {
                imagePreview
            }

            if !showAdvancedConfig {
                if editingNotice == nil {
                    Text("只填标题、正文、内置图片，系统会自动按“已发布 + 弹窗 + 关键”处理。".appLocalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    quickSubmitButton
                    quickPreviewButton
                } else {
                    Text("当前正在编辑已有公告，下面按钮会按当前配置更新，不会强制改成快捷弹窗。".appLocalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    submitButton
                    previewButton
                    cancelEditButton
                }
            }
        }
    }

    private var advancedConfigToggleSection: some View {
        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAdvancedConfig.toggle()
                }
            } label: {
                HStack {
                    Text((showAdvancedConfig ? "收起高级配置" : "切换到高级配置").appLocalized)
                    Spacer()
                    Image(systemName: showAdvancedConfig ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }

            if !showAdvancedConfig {
                Text("高级配置里可以补摘要、定时、动作、版本范围、优先级和媒体类型。".appLocalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedSummarySection: some View {
        Section("详细介绍".appLocalized) {
            TextField("摘要（列表可选）".appLocalized, text: $summary)
        }
    }

    private var deliverySection: some View {
        Section("投放规则".appLocalized) {
            Picker("状态".appLocalized, selection: $status) {
                ForEach(Notice.Status.allCases, id: \.self) { value in
                    Text(label(for: value)).tag(value)
                }
            }

            Picker("渠道".appLocalized, selection: $channel) {
                ForEach(Notice.Channel.allCases, id: \.self) { value in
                    Text(label(for: value)).tag(value)
                }
            }

            Picker("等级".appLocalized, selection: $severity) {
                ForEach(Notice.Severity.allCases, id: \.self) { value in
                    Text(label(for: value)).tag(value)
                }
            }

            Toggle("置顶".appLocalized, isOn: $isPinned)
            Toggle("需要确认".appLocalized, isOn: $requiresAck)
            Toggle("静默投放".appLocalized, isOn: $isSilent)
            TextField("受众".appLocalized, text: $audience)
            TextField("最低可见版本".appLocalized, text: $minAppVersion)
            TextField("最高可见版本".appLocalized, text: $maxAppVersion)
        }
    }

    private var scheduleSection: some View {
        Section("时间窗".appLocalized) {
            Toggle("设置发布时间".appLocalized, isOn: $hasPublishAt)
            if hasPublishAt {
                DatePicker("发布时间".appLocalized, selection: $publishAt)
            }

            Toggle("设置开始时间".appLocalized, isOn: $hasStartAt)
            if hasStartAt {
                DatePicker("开始时间".appLocalized, selection: $startAt)
            }

            Toggle("设置结束时间".appLocalized, isOn: $hasEndAt)
            if hasEndAt {
                DatePicker("结束时间".appLocalized, selection: $endAt)
            }
        }
    }

    private var actionConfigSection: some View {
        Section("动作".appLocalized) {
            Picker("动作类型".appLocalized, selection: $actionType) {
                ForEach(Notice.ActionType.allCases, id: \.self) { value in
                    Text(label(for: value)).tag(value)
                }
            }

            if actionType != .none {
                TextField("动作目标".appLocalized, text: $actionTarget)
                TextField("按钮文案".appLocalized, text: $actionLabel)
            }
        }
    }

    private var placeholderOverlay: some View {
        Group {
            if content.isEmpty {
                Text("输入公告内容...".appLocalized)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
            }
        }
    }

    // MARK: - 优先级区域
    private var prioritySection: some View {
        Section("优先级".appLocalized) {
            Stepper("优先级: %d".appLocalized(priority), value: $priority, in: 0...100)

            Text("数字越大，排序越靠前".appLocalized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 媒体区域
    private var mediaSection: some View {
        Section("媒体".appLocalized) {
            // 使用自定义按钮代替 Picker
            VStack(alignment: .leading, spacing: 12) {
                Text("类型".appLocalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    mediaTypeButton(type: .none, label: "无".appLocalized)
                    mediaTypeButton(type: .image, label: "图片".appLocalized)
                    mediaTypeButton(type: .video, label: "视频".appLocalized)
                }
            }

            if mediaType == .image {
                imagePickerRow
                imagePreview
            }
        }
    }

    private func mediaTypeButton(type: Notice.MediaType, label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                mediaType = type
                // 切换类型时清除图片选择
                if type != .image {
                    selectedImageName = nil
                    selectedImageData = nil
                }
            }
        } label: {
            Text(label)
                .font(.subheadline)
                .fontWeight(mediaType == type ? .semibold : .regular)
                .foregroundStyle(mediaType == type ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(mediaType == type ? Color.blue : Color.gray.opacity(0.2))
                )
        }
        .buttonStyle(.plain)
    }

    private var imagePickerRow: some View {
        Button {
            showBuiltinImagePicker = true
        } label: {
            HStack {
                Text("选择内置图片".appLocalized)
                Spacer()
                if selectedImageData != nil || selectedImageName != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var quickImagePickerRow: some View {
        Button {
            mediaType = .image
            showBuiltinImagePicker = true
        } label: {
            HStack {
                Text("选择内置图片".appLocalized)
                Spacer()
                if hasSelectedImage {
                    Text(selectedImageName ?? "已选择".appLocalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: hasSelectedImage ? "checkmark.circle.fill" : "photo.on.rectangle")
                    .foregroundStyle(hasSelectedImage ? .green : .secondary)
            }
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let imageName = selectedImageName {
            // 显示内置图片
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let imageData = selectedImageData,
                  let uiImage = UIImage(data: imageData) {
            // 显示从 Data 加载的图片
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 操作按钮区域
    private var actionSection: some View {
        Section {
            submitButton
            previewButton
            cancelEditButton
        }
    }

    private var submitButton: some View {
        Button {
            submitNotice(using: .standard)
        } label: {
            HStack {
                Spacer()
                if service.isSyncing {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 8)
                }
                Text(submitButtonTitle)
                    .fontWeight(.semibold)
                Spacer()
            }
        }
        .disabled(title.isEmpty || content.isEmpty || service.isSyncing)
    }

    private var quickSubmitButton: some View {
        Button {
            submitNotice(using: .quickModal)
        } label: {
            HStack {
                Spacer()
                if service.isSyncing {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 8)
                }
                Text("发布弹窗公告".appLocalized)
                    .fontWeight(.semibold)
                Spacer()
            }
        }
        .disabled(title.isEmpty || content.isEmpty || !hasSelectedBuiltinImage || service.isSyncing)
    }

    private var previewButton: some View {
        Button {
            previewCurrentNotice(using: .standard)
        } label: {
            HStack {
                Spacer()
                Text("预览效果".appLocalized)
                    .foregroundStyle(.blue)
                Spacer()
            }
        }
        .disabled(title.isEmpty || content.isEmpty)
    }

    private var quickPreviewButton: some View {
        Button {
            previewCurrentNotice(using: .quickModal)
        } label: {
            HStack {
                Spacer()
                Text("预览弹窗效果".appLocalized)
                    .foregroundStyle(.blue)
                Spacer()
            }
        }
        .disabled(title.isEmpty || content.isEmpty || !hasSelectedBuiltinImage)
    }

    @ViewBuilder
    private var cancelEditButton: some View {
        if editingNotice != nil {
            Button(action: cancelEdit) {
                HStack {
                    Spacer()
                    Text("取消编辑".appLocalized)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - 现有公告列表区域
    private var existingNoticesSection: some View {
        Section("现有公告".appLocalized) {
            if visibleManagedNotices.isEmpty {
                Text("暂无公告".appLocalized)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleManagedNotices, id: \.id) { notice in
                    NoticeAdminRow(
                        notice: notice,
                        sourceDisplay: sourceDisplay(for: notice),
                        onEdit: { startEdit(notice) },
                        onDelete: { deleteNotice(notice) }
                    )
                }
            }
        }
    }

    // MARK: - 预览当前公告
    private func previewCurrentNotice(using mode: NoticeSubmissionMode) {
        let builtinMediaName = selectedImageName
        let previewStatus: Notice.Status = mode == .quickModal ? .published : status
        let previewChannel: Notice.Channel = mode == .quickModal ? .modal : channel
        let previewSeverity: Notice.Severity = mode == .quickModal ? .critical : severity
        let previewPriority: Int = mode == .quickModal ? 0 : priority
        let previewPublishAt: Date? = mode == .quickModal ? nil : (hasPublishAt ? publishAt : nil)
        let previewStartAt: Date? = mode == .quickModal ? nil : (hasStartAt ? startAt : nil)
        let previewEndAt: Date? = mode == .quickModal ? nil : (hasEndAt ? endAt : nil)
        let previewActionType: Notice.ActionType = mode == .quickModal ? .none : actionType
        let previewActionTarget: String? = mode == .quickModal ? nil : normalizedOptional(actionTarget)
        let previewActionLabel: String? = mode == .quickModal ? nil : normalizedOptional(actionLabel)
        let previewMediaType: Notice.MediaType = builtinMediaName != nil ? .image : (mode == .quickModal ? .none : mediaType)
        let tempNotice = Notice(
            title: title,
            summary: mode == .quickModal ? nil : normalizedOptional(summary),
            content: content,
            mediaURL: builtinMediaName.map { Notice.builtinMediaURLString(for: $0) },
            builtinMediaName: builtinMediaName,
            mediaType: previewMediaType,
            priority: previewPriority,
            status: previewStatus,
            channel: previewChannel,
            severity: previewSeverity,
            isPinned: mode == .quickModal ? false : isPinned,
            requiresAck: mode == .quickModal ? false : requiresAck,
            isSilent: mode == .quickModal ? false : isSilent,
            publishAt: previewPublishAt,
            startAt: previewStartAt,
            endAt: previewEndAt,
            audience: mode == .quickModal ? "all" : audience,
            minAppVersion: mode == .quickModal ? nil : normalizedOptional(minAppVersion),
            maxAppVersion: mode == .quickModal ? nil : normalizedOptional(maxAppVersion),
            actionType: previewActionType,
            actionTarget: previewActionTarget,
            actionLabel: previewActionLabel
        )
        previewNotice = tempNotice
        showPreview = true
    }

    // MARK: - 提交公告
    private func submitNotice(using mode: NoticeSubmissionMode) {
        Task {
            print("🚀 提交公告...")
            print("   标题: \(title)")
            print("   内容: \(content)")
            print("   优先级: \(priority)")
            print("   媒体类型: \(mediaType)")

            guard service.checkRateLimit() else {
                alertMessage = "操作太频繁，请稍后再试".appLocalized
                showAlert = true
                return
            }

            if let editing = editingNotice {
                print("📝 更新现有公告...")
                editing.title = title
                editing.summary = normalizedOptional(summary)
                editing.content = content
                editing.displayPriority = priority
                editing.priority = priority
                editing.status = status
                editing.channel = channel
                editing.severity = severity
                editing.isPinned = isPinned
                editing.requiresAck = requiresAck
                editing.isSilent = isSilent
                editing.publishAt = hasPublishAt ? publishAt : nil
                editing.startAt = hasStartAt ? startAt : nil
                editing.endAt = hasEndAt ? endAt : nil
                editing.audience = audience
                editing.minAppVersion = normalizedOptional(minAppVersion)
                editing.maxAppVersion = normalizedOptional(maxAppVersion)
                editing.actionType = actionType
                editing.actionTarget = normalizedOptional(actionTarget)
                editing.actionLabel = normalizedOptional(actionLabel)

                // 如果有选择新的内置图片，更新 mediaURL
                if let imageName = selectedImageName {
                    editing.mediaURL = Notice.builtinMediaURLString(for: imageName)
                    editing.builtinMediaName = imageName
                    editing.mediaType = .image
                } else if selectedImageData == nil && mediaType == .none {
                    editing.mediaURL = nil
                    editing.cloudKitMediaURL = nil
                    editing.builtinMediaName = nil
                    editing.mediaType = .none
                }

                await service.updateNotice(editing)
                alertMessage = service.errorMessage ?? updateSuccessMessage
            } else {
                print("📝 创建新公告...")

                // 如果是内置图片，直接使用 builtin:// 前缀存储图片名称
                let builtinMediaName = selectedImageName
                let mediaURL: String?
                let actualMediaType: Notice.MediaType
                if let imageName = builtinMediaName {
                    mediaURL = Notice.builtinMediaURLString(for: imageName)
                    actualMediaType = .image
                } else {
                    mediaURL = nil
                    actualMediaType = mode == .quickModal ? .none : mediaType
                }

                let noticeStatus: Notice.Status = mode == .quickModal ? .published : status
                let noticeChannel: Notice.Channel = mode == .quickModal ? .modal : channel
                let noticeSeverity: Notice.Severity = mode == .quickModal ? .critical : severity
                let noticePriority: Int = mode == .quickModal ? 0 : priority
                let noticeSummary: String? = mode == .quickModal ? nil : normalizedOptional(summary)
                let noticePublishAt: Date? = mode == .quickModal ? nil : (hasPublishAt ? publishAt : nil)
                let noticeStartAt: Date? = mode == .quickModal ? nil : (hasStartAt ? startAt : nil)
                let noticeEndAt: Date? = mode == .quickModal ? nil : (hasEndAt ? endAt : nil)
                let noticeAudience: String = mode == .quickModal ? "all" : audience
                let noticeMinAppVersion: String? = mode == .quickModal ? nil : normalizedOptional(minAppVersion)
                let noticeMaxAppVersion: String? = mode == .quickModal ? nil : normalizedOptional(maxAppVersion)
                let noticeActionType: Notice.ActionType = mode == .quickModal ? .none : actionType
                let noticeActionTarget: String? = mode == .quickModal ? nil : normalizedOptional(actionTarget)
                let noticeActionLabel: String? = mode == .quickModal ? nil : normalizedOptional(actionLabel)
                let noticePinned = mode == .quickModal ? false : isPinned
                let noticeRequiresAck = mode == .quickModal ? false : requiresAck
                let noticeSilent = mode == .quickModal ? false : isSilent

                let notice = await service.createNotice(
                    title: title,
                    summary: noticeSummary,
                    content: content,
                    mediaURL: mediaURL,
                    builtinMediaName: builtinMediaName,
                    mediaType: actualMediaType,
                    priority: noticePriority,
                    status: noticeStatus,
                    channel: noticeChannel,
                    severity: noticeSeverity,
                    isPinned: noticePinned,
                    requiresAck: noticeRequiresAck,
                    isSilent: noticeSilent,
                    publishAt: noticePublishAt,
                    startAt: noticeStartAt,
                    endAt: noticeEndAt,
                    audience: noticeAudience,
                    minAppVersion: noticeMinAppVersion,
                    maxAppVersion: noticeMaxAppVersion,
                    actionType: noticeActionType,
                    actionTarget: noticeActionTarget,
                    actionLabel: noticeActionLabel
                )

                if notice != nil {
                    alertMessage = mode == .quickModal ? quickModalSuccessMessage : createSuccessMessage
                } else if let error = service.errorMessage {
                    alertMessage = error
                } else {
                    alertMessage = "保存公告失败".appLocalized
                }
            }

            showAlert = true
            if alertMessage == createSuccessMessage || alertMessage == updateSuccessMessage || alertMessage == quickModalSuccessMessage {
                resetForm()
            }
        }
    }

    // MARK: - 开始编辑
    private func startEdit(_ notice: Notice) {
        editingNotice = notice
        showAdvancedConfig = true
        title = notice.title
        summary = notice.summary ?? ""
        content = notice.content
        priority = notice.displayPriority
        status = notice.status
        channel = notice.channel
        severity = notice.severity
        isPinned = notice.isPinned
        requiresAck = notice.requiresAck
        isSilent = notice.isSilent
        audience = notice.audience
        minAppVersion = notice.minAppVersion ?? ""
        maxAppVersion = notice.maxAppVersion ?? ""
        actionType = notice.actionType
        actionTarget = notice.actionTarget ?? ""
        actionLabel = notice.actionLabel ?? ""
        hasPublishAt = notice.publishAt != nil
        publishAt = notice.publishAt ?? Date()
        hasStartAt = notice.startAt != nil
        startAt = notice.startAt ?? notice.publishAt ?? Date()
        hasEndAt = notice.endAt != nil
        endAt = notice.endAt ?? notice.startAt ?? Date()
        mediaType = notice.mediaType

        // 处理图片
        if notice.mediaType == .image {
            if let builtinMediaName = notice.builtinMediaName ?? notice.mediaURL.flatMap({ urlString in
                urlString.hasPrefix("builtin://") ? String(urlString.dropFirst("builtin://".count)) : nil
            }) {
                selectedImageName = builtinMediaName
                selectedImageData = nil
            } else if let urlString = notice.mediaURL,
                      let url = URL(string: urlString) {
                selectedImageName = nil
                selectedImageData = try? Data(contentsOf: url)
            } else {
                selectedImageName = nil
                selectedImageData = nil
            }
        } else {
            selectedImageName = nil
            selectedImageData = nil
        }
    }

    // MARK: - 取消编辑
    private func cancelEdit() {
        resetForm()
    }

    // MARK: - 删除公告
    private func deleteNotice(_ notice: Notice) {
        pendingDeleteNotice = notice
    }

    private func performDeleteNotice(_ notice: Notice) {
        pendingDeleteNotice = nil
        Task {
            await service.deleteNotice(notice)
            if let error = service.errorMessage {
                alertMessage = error
                showAlert = true
            }
        }
    }

    // MARK: - 重置表单
    private func resetForm() {
        editingNotice = nil
        showAdvancedConfig = false
        title = ""
        summary = ""
        content = ""
        priority = 0
        status = .draft
        channel = .inbox
        severity = .info
        isPinned = false
        requiresAck = false
        isSilent = false
        audience = "all"
        minAppVersion = ""
        maxAppVersion = ""
        actionType = .none
        actionTarget = ""
        actionLabel = ""
        publishAt = Date()
        startAt = Date()
        endAt = Date()
        hasPublishAt = false
        hasStartAt = false
        hasEndAt = false
        mediaType = .none
        selectedImageName = nil
        selectedImageData = nil
    }

    private var submitButtonTitle: String {
        if editingNotice != nil {
            return "更新公告".appLocalized
        }

        switch status {
        case .draft:
            return "保存草稿".appLocalized
        case .scheduled:
            return "创建定时公告".appLocalized
        case .published:
            return "发布公告".appLocalized
        case .archived:
            return "保存为归档".appLocalized
        }
    }

    private var createSuccessMessage: String {
        switch status {
        case .draft:
            return "草稿已保存".appLocalized
        case .scheduled:
            return "定时公告已创建".appLocalized
        case .published:
            return "公告已发布".appLocalized
        case .archived:
            return "归档公告已保存".appLocalized
        }
    }

    private var updateSuccessMessage: String {
        "公告已更新".appLocalized
    }

    private var quickModalSuccessMessage: String {
        "弹窗公告已发布".appLocalized
    }

    private func normalizedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var hasSelectedImage: Bool {
        selectedImageName != nil || selectedImageData != nil
    }

    private var hasSelectedBuiltinImage: Bool {
        selectedImageName != nil
    }

    private var visibleManagedNotices: [Notice] {
        service.managedNotices.filter { $0.status != .archived }
    }

    private var pendingDeleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteNotice != nil },
            set: { newValue in
                if !newValue {
                    pendingDeleteNotice = nil
                }
            }
        )
    }

    private func sourceDisplay(for notice: Notice) -> NoticeSourceDisplay {
        if service.wasFetchedFromCloudThisRun(notice) {
            return NoticeSourceDisplay(text: "本次已从云同步".appLocalized, tint: .green)
        }

        if notice.recordName != nil {
            return NoticeSourceDisplay(text: "本地缓存".appLocalized, tint: .orange)
        }

        return NoticeSourceDisplay(text: "仅本地未同步".appLocalized, tint: .red)
    }

    private func label(for status: Notice.Status) -> String {
        switch status {
        case .draft: return "草稿".appLocalized
        case .scheduled: return "定时".appLocalized
        case .published: return "已发布".appLocalized
        case .archived: return "已归档".appLocalized
        }
    }

    private func label(for channel: Notice.Channel) -> String {
        switch channel {
        case .inbox: return "公告中心".appLocalized
        case .banner: return "横幅".appLocalized
        case .modal: return "弹窗".appLocalized
        case .mixed: return "多渠道".appLocalized
        }
    }

    private func label(for severity: Notice.Severity) -> String {
        switch severity {
        case .info: return "普通".appLocalized
        case .important: return "重要".appLocalized
        case .critical: return "关键".appLocalized
        }
    }

    private func label(for actionType: Notice.ActionType) -> String {
        switch actionType {
        case .none: return "无动作".appLocalized
        case .deeplink: return "Deeplink"
        case .tab: return "Tab"
        case .page: return "页面".appLocalized
        case .externalURL: return "外链".appLocalized
        }
    }
}

private enum NoticeSubmissionMode {
    case quickModal
    case standard
}

struct NoticeSourceDisplay {
    let text: String
    let tint: Color
}

// MARK: - 公告管理行
struct NoticeAdminRow: View {
    let notice: Notice
    let sourceDisplay: NoticeSourceDisplay
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var statusLabel: String {
        switch notice.status {
        case .draft: return "草稿".appLocalized
        case .scheduled: return "定时".appLocalized
        case .published: return "已发布".appLocalized
        case .archived: return "已归档".appLocalized
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // 缩略图
            thumbnailView
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // 内容
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(notice.title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Text(statusLabel)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                }

                Text(sourceDisplay.text)
                    .font(.caption)
                    .foregroundStyle(sourceDisplay.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(sourceDisplay.tint.opacity(0.14))
                    .clipShape(Capsule())

                Text(notice.content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(notice.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("删除".appLocalized, systemImage: "trash")
            }

            Button(action: onEdit) {
                Label("编辑".appLocalized, systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if notice.mediaType == .image {
            NoticeAsyncImage(urlString: notice.mediaURL)
                .aspectRatio(contentMode: .fill)
        } else if notice.mediaType != .none {
            Image(systemName: notice.mediaType == .image ? "photo" : "video")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.2))
        } else {
            Image(systemName: "bell")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.2))
        }
    }
}

// MARK: - 公告预览遮罩
struct NoticePreviewOverlay: View {
    @Binding var isPresented: Bool
    let notice: Notice

    var body: some View {
        // 全局居中布局：公告内容在遮罩中水平和垂直双轴居中
        ZStack(alignment: .center) {
            Color.black
                .opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // 公告卡片 - 全局居中：水平和垂直双轴居中
            NoticeCardView(notice: notice)
                .frame(maxWidth: 340, maxHeight: 500)
                .padding(.horizontal, 32)
                .onTapGesture {
                    // 点击公告不关闭
                }
        }
        .zIndex(999)
    }
}

// MARK: - 预览
#Preview {
    NoticeAdminView()
}
