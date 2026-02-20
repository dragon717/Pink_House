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
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
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
            .confirmationDialog("选择头像", isPresented: $showActionSheet, titleVisibility: .visible) {
                Button("从相册选择") {
                    showPhotoPicker = true
                }
                
                Button("拍照") {
                    showCamera = true
                }
                
                if authManager.hasCustomAvatar || avatarImage != nil {
                    Button("删除当前头像", role: .destructive) {
                        showClearAvatarConfirm = true
                    }
                }
                
                Button("取消", role: .cancel) {}
            }
            .alert("确认删除", isPresented: $showClearAvatarConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    clearAvatar()
                }
            } message: {
                Text("确定要删除当前头像吗？")
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
            
            Text("点击更换头像")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - 昵称区域
    private var nicknameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("昵称")
                .font(.headline)
                .foregroundStyle(.primary)
            
            TextField("输入昵称", text: $nickname)
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
                Text("Apple ID 名称: \(authManager.givenName)")
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
