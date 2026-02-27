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
    @State private var content = ""
    @State private var priority = 0
    @State private var mediaType: Notice.MediaType = .none
    @State private var selectedImageName: String?  // 内置图片名称
    @State private var selectedImageData: Data?

    // 编辑模式
    @State private var editingNotice: Notice?

    // 提示
    @State private var showAlert = false
    @State private var alertMessage = ""

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
            .navigationTitle("公告管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                service.setup(with: modelContext)
                checkAdminPermission()
            }
            .alert("提示", isPresented: $showAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(alertMessage)
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
            Text("检查管理员权限...")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 无权限视图
    private var noPermissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("需要管理员权限")
                .font(.title2)
                .fontWeight(.semibold)

            Text("只有管理员可以发布公告。\n如果您是管理员，请确保已登录 iCloud 账户。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("重新检查") {
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
            contentSection
            prioritySection
            mediaSection
            actionSection
            existingNoticesSection
        }
    }

    // MARK: - 公告内容区域
    private var contentSection: some View {
        Section("公告内容") {
            TextField("标题", text: $title)

            TextEditor(text: $content)
                .frame(minHeight: 100)
                .overlay(
                    placeholderOverlay,
                    alignment: .topLeading
                )
        }
    }

    private var placeholderOverlay: some View {
        Group {
            if content.isEmpty {
                Text("输入公告内容...")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
            }
        }
    }

    // MARK: - 优先级区域
    private var prioritySection: some View {
        Section("优先级") {
            Stepper("优先级: \(priority)", value: $priority, in: 0...100)

            Text("数字越大，排序越靠前")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 媒体区域
    private var mediaSection: some View {
        Section("媒体") {
            // 使用自定义按钮代替 Picker
            VStack(alignment: .leading, spacing: 12) {
                Text("类型")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    mediaTypeButton(type: .none, label: "无")
                    mediaTypeButton(type: .image, label: "图片")
                    mediaTypeButton(type: .video, label: "视频")
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
                Text("选择内置图片")
                Spacer()
                if selectedImageData != nil || selectedImageName != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
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
        Button(action: submitNotice) {
            HStack {
                Spacer()
                if service.isSyncing {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 8)
                }
                Text(editingNotice == nil ? "发布公告" : "更新公告")
                    .fontWeight(.semibold)
                Spacer()
            }
        }
        .disabled(title.isEmpty || content.isEmpty || service.isSyncing)
    }

    private var previewButton: some View {
        Button(action: previewCurrentNotice) {
            HStack {
                Spacer()
                Text("预览效果")
                    .foregroundStyle(.blue)
                Spacer()
            }
        }
        .disabled(title.isEmpty || content.isEmpty)
    }

    @ViewBuilder
    private var cancelEditButton: some View {
        if editingNotice != nil {
            Button(action: cancelEdit) {
                HStack {
                    Spacer()
                    Text("取消编辑")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - 现有公告列表区域
    private var existingNoticesSection: some View {
        Section("现有公告") {
            if service.notices.isEmpty {
                Text("暂无公告")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.notices, id: \.id) { notice in
                    NoticeAdminRow(
                        notice: notice,
                        onEdit: { startEdit(notice) },
                        onDelete: { deleteNotice(notice) }
                    )
                }
            }
        }
    }

    // MARK: - 预览当前公告
    private func previewCurrentNotice() {
        let tempNotice = Notice(
            title: title,
            content: content,
            mediaURL: selectedImageName != nil ? "builtin://\(selectedImageName!)" : nil,
            mediaType: selectedImageName != nil ? .image : mediaType,
            priority: priority
        )
        previewNotice = tempNotice
        showPreview = true
    }

    // MARK: - 提交公告
    private func submitNotice() {
        Task {
            print("🚀 提交公告...")
            print("   标题: \(title)")
            print("   内容: \(content)")
            print("   优先级: \(priority)")
            print("   媒体类型: \(mediaType)")

            guard service.checkRateLimit() else {
                alertMessage = "操作太频繁，请稍后再试"
                showAlert = true
                return
            }

            if let editing = editingNotice {
                print("📝 更新现有公告...")
                editing.title = title
                editing.content = content
                editing.priority = priority

                // 如果有选择新的内置图片，更新 mediaURL
                if let imageName = selectedImageName {
                    editing.mediaURL = "builtin://\(imageName)"
                    editing.mediaType = .image
                } else if selectedImageData == nil && mediaType == .none {
                    editing.mediaURL = nil
                    editing.mediaType = .none
                }

                await service.updateNotice(editing)
                alertMessage = service.errorMessage ?? "公告已更新"
            } else {
                print("📝 创建新公告...")

                // 如果是内置图片，直接使用 builtin:// 前缀存储图片名称
                var mediaURL: String?
                let actualMediaType: Notice.MediaType
                if let imageName = selectedImageName {
                    mediaURL = "builtin://\(imageName)"
                    actualMediaType = .image
                } else {
                    actualMediaType = mediaType
                }

                let notice = await service.createNotice(
                    title: title,
                    content: content,
                    mediaType: actualMediaType,
                    priority: priority
                )

                if notice != nil {
                    // 更新 mediaURL（如果是内置图片）
                    if let mediaURL = mediaURL {
                        notice?.mediaURL = mediaURL
                        try? modelContext.save()
                    }
                    alertMessage = "公告已发布"
                } else if let error = service.errorMessage {
                    alertMessage = error
                } else {
                    alertMessage = "发布公告失败"
                }
            }

            showAlert = true
            if alertMessage == "公告已发布" || alertMessage == "公告已更新" {
                resetForm()
            }
        }
    }

    // MARK: - 开始编辑
    private func startEdit(_ notice: Notice) {
        editingNotice = notice
        title = notice.title
        content = notice.content
        priority = notice.priority
        mediaType = notice.mediaType

        // 处理图片
        if notice.mediaType == .image,
           let urlString = notice.mediaURL {
            if urlString.hasPrefix("builtin://") {
                // 内置图片
                let imageName = String(urlString.dropFirst("builtin://".count))
                selectedImageName = imageName
                selectedImageData = nil
            } else if let url = URL(string: urlString) {
                // 本地文件图片
                selectedImageName = nil
                selectedImageData = try? Data(contentsOf: url)
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
        Task {
            await service.deleteNotice(notice)
        }
    }

    // MARK: - 重置表单
    private func resetForm() {
        editingNotice = nil
        title = ""
        content = ""
        priority = 0
        mediaType = .none
        selectedImageName = nil
        selectedImageData = nil
    }
}

// MARK: - 公告管理行
struct NoticeAdminRow: View {
    let notice: Notice
    let onEdit: () -> Void
    let onDelete: () -> Void

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

                    Text("P\(notice.priority)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                }

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
                Label("删除", systemImage: "trash")
            }

            Button(action: onEdit) {
                Label("编辑", systemImage: "pencil")
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
