import SwiftUI
import PhotosUI

struct UserProfileEditView: View {
    @ObservedObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var nickname: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showActionSheet = false
    @State private var showClearAvatarConfirm = false
    
    // 账号删除相关状态
    @State private var showingDeleteAccountConfirm = false
    @State private var showingDeleteAccountFinalConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    
    // 裁剪相关状态
    @State private var cropRequest: CropRequest?
    @State private var pendingCameraImage: UIImage? // 临时存储相机图片
    
    private var canSave: Bool {
        nickname != authManager.customNickname || avatarImage != nil
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 40) {
                        // 头像区域
                        avatarSection
                            .padding(.top, 20)
                        
                        // 昵称输入区域
                        nicknameSection
                        
                        // 账号删除区域 (仅在已登录时显示)
                        if authManager.isAuthenticated {
                            deleteAccountSection
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("编辑资料".appLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消".appLocalized) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存".appLocalized) {
                        saveProfile()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .onAppear {
                nickname = authManager.customNickname
                loadCurrentAvatar()
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhoto,
                matching: .images
            )
            .onChange(of: selectedPhoto) { _, newItem in
                loadSelectedPhoto(newItem)
            }
            .confirmationDialog("选择头像".appLocalized, isPresented: $showActionSheet, titleVisibility: .visible) {
                Button("从相册选择".appLocalized) {
                    showPhotoPicker = true
                }
                
                Button("拍照".appLocalized) {
                    showCamera = true
                }
                
                if authManager.hasCustomAvatar || avatarImage != nil {
                    Button("删除当前头像".appLocalized, role: .destructive) {
                        showClearAvatarConfirm = true
                    }
                }
                
                Button("取消".appLocalized, role: .cancel) {}
            }
            .alert("确认删除".appLocalized, isPresented: $showClearAvatarConfirm) {
                Button("取消".appLocalized, role: .cancel) {}
                Button("删除".appLocalized, role: .destructive) {
                    clearAvatar()
                }
            } message: {
                Text("确定要删除当前头像吗？".appLocalized)
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker(image: $pendingCameraImage)
            }
            .onChange(of: pendingCameraImage) { _, newValue in
                // 相机拍照后，进入裁剪视图
                if let newImage = newValue {
                    // 延迟一点执行，确保sheet关闭后再打开裁剪视图
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        cropRequest = CropRequest(image: newImage, isNewSelection: true)
                        pendingCameraImage = nil // 清空临时变量
                    }
                }
            }
            // 头像裁剪视图
            .sheet(item: $cropRequest) { request in
                ImageCropView(
                    image: request.image,
                    aspectRatio: 1.0, // 1:1 正方形
                    targetWidth: 512, // 输出512x512
                    overlayType: .circle, // 圆形裁剪框
                    onCrop: { croppedImage in
                        avatarImage = croppedImage
                        cropRequest = nil
                    },
                    onCancel: {
                        cropRequest = nil
                    }
                )
            }
            // 账号删除确认弹窗 (第一步)
            .alert("删除账号".appLocalized, isPresented: $showingDeleteAccountConfirm) {
                Button("取消".appLocalized, role: .cancel) {}
                Button("继续".appLocalized, role: .destructive) {
                    showingDeleteAccountFinalConfirm = true
                }
            } message: {
                Text("删除账号将清除您的登录信息和个性化设置。\n\n您的衣橱数据将保留在设备本地，但 iCloud 同步功能将停止。\n\n此操作无法撤销。".appLocalized)
            }
            // 账号删除最终确认弹窗 (第二步)
            .alert("最终确认".appLocalized, isPresented: $showingDeleteAccountFinalConfirm) {
                Button("取消".appLocalized, role: .cancel) {}
                Button("确认删除".appLocalized, role: .destructive) {
                    performDeleteAccount()
                }
            } message: {
                Text("您确定要删除账号吗？此操作将立即生效且无法恢复。".appLocalized)
            }
            // 删除中状态
            .overlay {
                if isDeletingAccount {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("正在删除账号...".appLocalized)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 账号删除区域
    private var deleteAccountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("账号管理".appLocalized)
                .font(.headline)
                .foregroundStyle(.primary)
            
            Button(action: {
                showingDeleteAccountConfirm = true
            }) {
                HStack {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .foregroundStyle(.red)
                    
                    Text("删除账号".appLocalized)
                        .foregroundStyle(.red)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Text("删除账号将移除您的 Apple ID 关联信息，但保留本地数据。".appLocalized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
    
    // MARK: - 执行账号删除
    private func performDeleteAccount() {
        isDeletingAccount = true
        
        Task {
            do {
                try await authManager.deleteAccount()
                await MainActor.run {
                    isDeletingAccount = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    deleteError = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - 头像区域
    private var avatarSection: some View {
        VStack(spacing: 16) {
            Button {
                showActionSheet = true
            } label: {
                ZStack {
                    // 头像显示
                    if let avatarImage {
                        Image(uiImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                    } else if authManager.hasCustomAvatar {
                        let fileURL = authManager.avatarFileURL
                        if let image = UIImage(contentsOfFile: fileURL.path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                        } else {
                            DefaultAvatarView(
                                givenName: authManager.givenName,
                                familyName: authManager.familyName,
                                size: 120
                            )
                        }
                    } else {
                        // 使用默认头像
                        DefaultAvatarView(
                            givenName: authManager.givenName,
                            familyName: authManager.familyName,
                            size: 120
                        )
                    }
                    
                    // 编辑图标
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 36, height: 36)
                                
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                            }
                            .overlay(
                                Circle()
                                    .stroke(Color(.systemBackground), lineWidth: 3)
                            )
                        }
                    }
                    .frame(width: 120, height: 120)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Text("点击更换头像".appLocalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - 昵称区域
    private var nicknameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("昵称".appLocalized)
                .font(.headline)
                .foregroundStyle(.primary)
            
            TextField("输入昵称".appLocalized, text: $nickname)
                .font(.body)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
            
            if !authManager.givenName.isEmpty {
                Text("Apple ID 名称: %@".appLocalized(authManager.givenName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - 方法
    
    private func loadCurrentAvatar() {
        if authManager.hasCustomAvatar {
            let fileURL = authManager.avatarFileURL
            if let image = UIImage(contentsOfFile: fileURL.path) {
                avatarImage = image
            }
        }
    }
    
    private func loadSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    // 进入裁剪视图，而不是直接设置头像
                    self.cropRequest = CropRequest(image: image, isNewSelection: true)
                }
            }
        }
    }
    
    private func clearAvatar() {
        avatarImage = nil
        authManager.clearCustomAvatar()
    }
    
    private func saveProfile() {
        // 保存昵称
        if nickname != authManager.customNickname {
            authManager.updateCustomNickname(nickname)
        }
        
        // 保存头像
        if let avatarImage {
            authManager.updateCustomAvatar(image: avatarImage)
        }
        
        dismiss()
    }
}

// MARK: - 默认头像视图
struct DefaultAvatarView: View {
    let givenName: String
    let familyName: String
    let size: CGFloat
    
    var initials: String {
        var components = PersonNameComponents()
        components.givenName = givenName
        components.familyName = familyName
        
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .abbreviated
        return formatter.string(from: components)
    }
    
    var body: some View {
        if givenName.isEmpty && familyName.isEmpty {
            Image(systemName: "person.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(.gray)
        } else {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: size, height: size)
        }
    }
}

#Preview {
    UserProfileEditView(authManager: AuthenticationManager.shared)
}
